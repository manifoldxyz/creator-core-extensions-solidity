// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

import "forge-std/Test.sol";

import {ERC1155Creator} from "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";

import {ManifoldERC1155SeaDropShim} from "../../contracts/seadrop/ManifoldERC1155SeaDropShim.sol";
import {
    AllowListData,
    MultiConfigureStruct,
    PublicDrop,
    StorageProtocol
} from "../../contracts/seadrop/SeaDropStructs.sol";

/**
 * @notice Canonical SeaDrop v1 MintParams — kept local to this test file
 *         because the shim's public surface never forwards MintParams
 *         (allowlist data forwards only the merkle root via AllowListData).
 *         Field order + types mirror ProjectOpenSea/seadrop verbatim so the
 *         leaf hash `keccak256(abi.encode(minter, mintParams))` matches what
 *         the deployed SeaDrop bytecode reconstructs for proof verification.
 */
struct MintParams {
    uint256 mintPrice;
    uint256 maxTotalMintableByWallet;
    uint256 startTime;
    uint256 endTime;
    uint256 dropStageIndex; // non-zero; 0 is reserved for public mints
    uint256 maxTokenSupplyForStage;
    uint256 feeBps;
    bool restrictFeeRecipients;
}

/**
 * @notice Minimal slice of the stock SeaDrop v1 external ABI the fork test
 *         invokes. Only the two mint entry points + the two views used for
 *         post-initialize config assertions are declared here — the shim's
 *         own ISeaDrop.sol is admin-side only and does not expose mint fns.
 */
interface ISeaDropFullSlice {
    function mintPublic(
        address nftContract,
        address feeRecipient,
        address minterIfNotPayer,
        uint256 quantity
    ) external payable;

    function mintAllowList(
        address nftContract,
        address feeRecipient,
        address minterIfNotPayer,
        uint256 quantity,
        MintParams calldata mintParams,
        bytes32[] calldata proof
    ) external payable;

    function getPublicDrop(address nftContract) external view returns (PublicDrop memory);

    function getAllowListMerkleRoot(address nftContract) external view returns (bytes32);
}

/**
 * @notice Sepolia fork integration test for the full 3-tx deploy runbook.
 * @dev Deploys a fresh ERC1155Creator + the shim against the real stock
 *      SeaDrop at 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5, registers the
 *      shim as a Creator Core extension, runs `initialize(cfg)`, then
 *      exercises both the allowlist phase (single-leaf merkle proof = empty
 *      array) and the public phase through SeaDrop's real mint dispatchers.
 *      Asserts the ERC1155 lands on Creator Core, counters bump on the shim,
 *      and ETH splits into the configured creator payout + fee recipient.
 *
 *      Skips gracefully when SEPOLIA_RPC_URL is not set AND the runner
 *      hasn't been invoked with `--fork-url` already on Sepolia — so the
 *      fork test stays a no-op in CI by default (no RPC credentials leaked
 *      into the repo) but runs end-to-end locally or in a CI environment
 *      that provides SEPOLIA_RPC_URL. Invocation (either pattern works):
 *          SEPOLIA_RPC_URL=<url> forge test --match-contract \
 *              ManifoldERC1155SeaDropShimFork
 *          forge test --fork-url <sepolia-rpc> --match-contract \
 *              ManifoldERC1155SeaDropShimFork
 *
 *      Pinning the MintParams leaf format + INonFungibleSeaDropToken
 *      interfaceId against the deployed bytecode is tracked under US-022.
 *      If that pin reveals a drift, update MintParams here in lockstep.
 */
contract ManifoldERC1155SeaDropShimForkTest is Test {
    address internal constant SEADROP = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5;
    uint256 internal constant SEPOLIA_CHAIN_ID = 11_155_111;

    uint256 internal constant INSTANCE_ID = 1;
    uint256 internal constant MAX_SUPPLY = 1000;
    uint256 internal constant MAX_MINTS_PER_WALLET = 10;
    uint256 internal constant PUBLIC_MINT_PRICE = 0.01 ether;
    uint256 internal constant ALLOWLIST_MINT_PRICE = 0;
    uint256 internal constant FEE_BPS = 500; // 5%

    address internal creatorAdmin = address(0xA11CE);
    address internal payoutAddress = address(0xCAFE);
    address internal feeRecipient = address(0xFEE);
    address internal alice = address(0x1111);
    address internal bob = address(0x2222);

    ERC1155Creator internal creator;
    ManifoldERC1155SeaDropShim internal shim;

    // Single-leaf allowlist with alice as the sole eligible wallet. Populated
    // by _setupFork once the fork's block.timestamp is known so startTime /
    // endTime align with `_checkActive` on the live SeaDrop deployment.
    MintParams internal allowlistMintParams;

    /**
     * @dev Sets up the fork + deploys the full 3-tx runbook state in one
     *      shot: fork, ERC1155Creator, shim, registerExtension, initialize.
     *      Returns false (and tests early-return) if neither SEPOLIA_RPC_URL
     *      is set nor the runner is already on a Sepolia fork via --fork-url.
     */
    function _setupFork() internal returns (bool) {
        // Already on a Sepolia fork? (`forge test --fork-url <sepolia>` path)
        // Otherwise, try to create one from SEPOLIA_RPC_URL.
        if (block.chainid != SEPOLIA_CHAIN_ID) {
            string memory rpcUrl = vm.envOr("SEPOLIA_RPC_URL", string(""));
            if (bytes(rpcUrl).length == 0) {
                emit log_string(
                    "[SKIP] SEPOLIA_RPC_URL not set and not already on Sepolia fork; skipping fork test."
                );
                return false;
            }
            vm.createSelectFork(rpcUrl);
        }

        require(
            SEADROP.code.length > 0,
            "SeaDrop bytecode not present at 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5 on fork"
        );

        vm.startPrank(creatorAdmin);

        creator = new ERC1155Creator("TestCreator", "TEST");

        address[] memory allowed = new address[](1);
        allowed[0] = SEADROP;
        shim = new ManifoldERC1155SeaDropShim(address(creator), INSTANCE_ID, allowed);

        creator.registerExtension(address(shim), "");

        // Build the allowlist MintParams AFTER the fork is selected so
        // startTime binds to the fork's block.timestamp (the same timestamp
        // the test-exec-time `_checkActive` reads against).
        allowlistMintParams = MintParams({
            mintPrice: ALLOWLIST_MINT_PRICE,
            maxTotalMintableByWallet: MAX_MINTS_PER_WALLET,
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            dropStageIndex: 1,
            maxTokenSupplyForStage: MAX_SUPPLY,
            feeBps: FEE_BPS,
            restrictFeeRecipients: true
        });

        // Single-leaf tree: root == leaf, proof = []. SeaDrop's MerkleProof.verify
        // with an empty proof returns `leaf == root`, so no siblings are needed.
        bytes32 leaf = keccak256(abi.encode(alice, allowlistMintParams));

        shim.initialize(_forkCfg(leaf));

        vm.stopPrank();
        return true;
    }

    function _forkCfg(bytes32 merkleRoot) internal view returns (MultiConfigureStruct memory cfg) {
        address[] memory feeRecipients = new address[](1);
        feeRecipients[0] = feeRecipient;

        cfg = MultiConfigureStruct({
            maxSupply: MAX_SUPPLY,
            maxMintsPerWallet: MAX_MINTS_PER_WALLET,
            tokenUriLocation: "https://example.com/meta.json",
            storageProtocol: StorageProtocol.NONE,
            contractURI: "https://example.com/contract.json",
            seaDropImpl: SEADROP,
            publicDrop: PublicDrop({
                mintPrice: uint80(PUBLIC_MINT_PRICE),
                startTime: uint48(block.timestamp),
                endTime: uint48(block.timestamp + 7 days),
                maxTotalMintableByWallet: uint16(MAX_MINTS_PER_WALLET),
                feeBps: uint16(FEE_BPS),
                restrictFeeRecipients: true
            }),
            allowListData: AllowListData({
                merkleRoot: merkleRoot,
                publicKeyURIs: new string[](0),
                allowListURI: ""
            }),
            creatorPayoutAddress: payoutAddress,
            allowedFeeRecipients: feeRecipients,
            disallowedFeeRecipients: new address[](0),
            allowedPayers: new address[](0),
            disallowedPayers: new address[](0)
        });
    }

    // -----------------------------------------------------------------------
    // Sanity: config forwarded to real SeaDrop is readable via its getters.
    // -----------------------------------------------------------------------

    function testForkInitializePushedConfigToRealSeaDrop() public {
        if (!_setupFork()) return;

        PublicDrop memory pd = ISeaDropFullSlice(SEADROP).getPublicDrop(address(shim));
        assertEq(pd.mintPrice, uint80(PUBLIC_MINT_PRICE), "publicDrop.mintPrice on SeaDrop");
        assertEq(
            pd.maxTotalMintableByWallet,
            uint16(MAX_MINTS_PER_WALLET),
            "publicDrop.maxTotalMintableByWallet on SeaDrop"
        );
        assertEq(pd.feeBps, uint16(FEE_BPS), "publicDrop.feeBps on SeaDrop");
        assertTrue(pd.restrictFeeRecipients, "publicDrop.restrictFeeRecipients on SeaDrop");

        bytes32 root = ISeaDropFullSlice(SEADROP).getAllowListMerkleRoot(address(shim));
        bytes32 expected = keccak256(abi.encode(alice, allowlistMintParams));
        assertEq(root, expected, "allowList merkleRoot on SeaDrop matches single-leaf root");
    }

    // -----------------------------------------------------------------------
    // Allowlist phase: alice mints 1 with a proof=[] single-leaf tree.
    // -----------------------------------------------------------------------

    function testForkAllowlistMintLandsOnCreatorCore() public {
        if (!_setupFork()) return;

        uint256 tokenId = 1; // first mintExtensionNew on a fresh ERC1155Creator
        bytes32[] memory proof = new bytes32[](0);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        ISeaDropFullSlice(SEADROP).mintAllowList(
            address(shim),
            feeRecipient,
            address(0), // minter == msg.sender
            1,
            allowlistMintParams,
            proof
        );

        assertEq(creator.balanceOf(alice, tokenId), 1, "alice received ERC1155 from allowlist phase");

        (uint256 minted, uint256 total, uint256 cap) = shim.getMintStats(alice);
        assertEq(minted, 1, "alice minterNumMinted bumped");
        assertEq(total, 1, "_totalMinted bumped");
        assertEq(cap, MAX_SUPPLY, "maxSupply unchanged");
    }

    // -----------------------------------------------------------------------
    // Public phase: bob mints 2 with msg.value; ETH splits across payout + fee.
    // -----------------------------------------------------------------------

    function testForkPublicMintSplitsEthToCreatorAndFee() public {
        if (!_setupFork()) return;

        uint256 tokenId = 1;
        uint256 quantity = 2;
        uint256 payment = PUBLIC_MINT_PRICE * quantity;
        uint256 expectedFee = (payment * FEE_BPS) / 10_000;
        uint256 expectedPayout = payment - expectedFee;

        uint256 payoutBefore = payoutAddress.balance;
        uint256 feeBefore = feeRecipient.balance;

        vm.deal(bob, 1 ether);
        vm.prank(bob);
        ISeaDropFullSlice(SEADROP).mintPublic{value: payment}(
            address(shim),
            feeRecipient,
            address(0),
            quantity
        );

        assertEq(creator.balanceOf(bob, tokenId), quantity, "bob received ERC1155 from public phase");
        assertEq(
            payoutAddress.balance - payoutBefore,
            expectedPayout,
            "creator payout credited with msg.value minus fee"
        );
        assertEq(
            feeRecipient.balance - feeBefore,
            expectedFee,
            "fee recipient credited with feeBps share"
        );

        (uint256 minted, uint256 total, ) = shim.getMintStats(bob);
        assertEq(minted, quantity, "bob minterNumMinted bumped");
        assertEq(total, quantity, "_totalMinted bumped");
    }
}
