// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @author: manifold.xyz

import "forge-std/Test.sol";

import {ERC1155Creator} from "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {ManifoldERC1155SeaDropShim} from "../../contracts/seadrop/ManifoldERC1155SeaDropShim.sol";
import {SeaDrop} from "seadrop/src/SeaDrop.sol";
import {INonFungibleSeaDropToken} from "seadrop/src/interfaces/INonFungibleSeaDropToken.sol";
import {ISeaDropTokenContractMetadata} from "seadrop/src/interfaces/ISeaDropTokenContractMetadata.sol";
import {
    AllowListData,
    PublicDrop,
    MintParams
} from "seadrop/src/lib/SeaDropStructs.sol";
import {
    ERC721SeaDropStructsErrorsAndEvents
} from "seadrop/src/lib/ERC721SeaDropStructsErrorsAndEvents.sol";

import {ReentrantMinter} from "./mocks/ReentrantMinter.sol";
import {RejectAllApprover} from "./mocks/RejectAllApprover.sol";
import {TwoStepOwnable} from "utility-contracts/TwoStepOwnable.sol";
import {IERC1155CreatorExtensionApproveTransfer} from "@manifoldxyz/creator-core-solidity/contracts/extensions/ERC1155/IERC1155CreatorExtensionApproveTransfer.sol";

/**
 * @notice Foundry harness for ManifoldERC1155SeaDropShim.
 *
 *         setUp deploys a real ERC1155Creator (Manifold Creator Core), the
 *         stock SeaDrop v1 implementation contract, and the shim — bound to
 *         both — then registers the shim as an extension on the creator
 *         contract. Tests then call `initialize(uri)` and friends as the shim
 *         owner (which is the deploy address, i.e. this test contract).
 *
 *         The shim's owner is the test contract itself by default — we deploy
 *         from `address(this)` and the new auth model (TwoStepOwnable from
 *         ERC721SeaDrop) gates config on the deployer.
 */
contract ManifoldERC1155SeaDropShimTest is
    Test,
    ERC1155Holder,
    ERC721SeaDropStructsErrorsAndEvents
{
    /// @dev Mirror of ManifoldERC1155SeaDropShim.TokenURIUpdated for vm.expectEmit.
    event TokenURIUpdated(uint256 indexed tokenId, string uri);
    /// @dev Mirror of ISeaDropTokenContractMetadata.MaxSupplyUpdated for vm.expectEmit.
    event MaxSupplyUpdated(uint256 newMaxSupply);
    /// @dev Mirror of ManifoldERC1155SeaDropShim.SeaDropShimDeployed for vm.expectEmit.
    event SeaDropShimDeployed(address indexed creatorContract);
    /// @dev Mirror of ManifoldERC1155SeaDropShim.TransferLockUpdated for vm.expectEmit.
    event TransferLockUpdated(uint256 unlockTime);
    /// @dev Mirror of ERC1155CreatorCore.ExtensionApproveTransferUpdated for vm.expectEmit.
    event ExtensionApproveTransferUpdated(address indexed extension, bool enabled);
    string internal constant NAME = "Manifold SeaDrop Shim";
    string internal constant SYMBOL = "MSS";

    address internal creatorAdmin;
    address internal alice = address(0x1111);
    address internal bob = address(0x2222);
    address internal feeRecipient = address(0xFEE);
    address internal payoutAddress = address(0xBEEF);

    ERC1155Creator internal creator;
    SeaDrop internal seadrop;
    ManifoldERC1155SeaDropShim internal shim;

    function setUp() public virtual {
        creatorAdmin = address(this);

        creator = new ERC1155Creator("TestCreator", "TEST");
        seadrop = new SeaDrop();

        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = address(seadrop);

        shim = new ManifoldERC1155SeaDropShim(
            NAME,
            SYMBOL,
            allowedSeaDrop,
            address(creator),
            address(this) // initialOwner — test contract is the drop admin
        );

        creator.registerExtension(address(shim), "");
    }

    // -------------------------------------------------------------------
    // Construction
    // -------------------------------------------------------------------

    function testConstructorSetsImmutablesAndOwner() public {
        assertEq(shim.creatorContractAddress(), address(creator));
        assertEq(shim.tokenId(), 0);
        assertEq(shim.owner(), address(this));
        assertEq(shim.name(), NAME);
        assertEq(shim.symbol(), SYMBOL);
    }

    function testConstructorTransfersOwnershipToInitialOwner() public {
        address newOwner = address(0xCAFE);
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = address(seadrop);

        ManifoldERC1155SeaDropShim s = new ManifoldERC1155SeaDropShim(
            NAME,
            SYMBOL,
            allowedSeaDrop,
            address(creator),
            newOwner
        );

        assertEq(s.owner(), newOwner, "owner must be initialOwner, not deployer");
    }

    function testConstructorRevertsForZeroInitialOwner() public {
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = address(seadrop);

        vm.expectRevert(
            ManifoldERC1155SeaDropShim.InitialOwnerIsZeroAddress.selector
        );
        new ManifoldERC1155SeaDropShim(
            NAME,
            SYMBOL,
            allowedSeaDrop,
            address(creator),
            address(0)
        );
    }

    function testConstructorEmitsCreatorContract() public {
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = address(seadrop);
        vm.expectEmit(true, false, false, true);
        emit SeaDropShimDeployed(address(creator));
        new ManifoldERC1155SeaDropShim(NAME, SYMBOL, allowedSeaDrop, address(creator), address(this));
    }

    function testConstructorPopulatesAllowedSeaDrop() public {
        // Calling `getMintStats` and then `mintSeaDrop` from the SeaDrop
        // contract is the public-surface proof; here we just verify
        // that an unallowed caller is rejected.
        shim.initialize("");
        vm.prank(address(0xDEAD));
        vm.expectRevert(); // OnlyAllowedSeaDrop
        shim.mintSeaDrop(alice, 1);
    }

    // -------------------------------------------------------------------
    // initialize()
    // -------------------------------------------------------------------

    function testInitializeSetsTokenId() public {
        assertEq(shim.tokenId(), 0);
        shim.initialize("");
        assertEq(shim.tokenId(), 1, "first mintExtensionNew should mint id 1");
    }

    function testInitializeRevertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(); // TwoStepOwnable: onlyOwner
        shim.initialize("");
    }

    function testInitializeRevertsWhenAlreadyInitialized() public {
        shim.initialize("");
        vm.expectRevert(ManifoldERC1155SeaDropShim.AlreadyInitializedShim.selector);
        shim.initialize("");
    }

    function testInitializeRevertsWhenShimNotRegisteredAsExtension() public {
        // Deploy a fresh shim that is *not* registered on the creator.
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = address(seadrop);
        ManifoldERC1155SeaDropShim unregistered = new ManifoldERC1155SeaDropShim(
            NAME,
            SYMBOL,
            allowedSeaDrop,
            address(creator),
            address(this)
        );

        vm.expectRevert(); // creator core "Must be registered extension"
        unregistered.initialize("");
    }

    function testInitializeSetsTokenURI() public {
        string memory uri = "ar://initial-metadata";
        vm.expectEmit(true, false, false, true, address(shim));
        emit TokenURIUpdated(1, uri);
        shim.initialize(uri);
        assertEq(creator.uri(shim.tokenId()), uri);
    }

    function testInitializeWithEmptyURILeavesURIUnsetAndUpdatable() public {
        shim.initialize("");
        shim.updateURI("ar://later");
        assertEq(creator.uri(shim.tokenId()), "ar://later");
    }

    // -------------------------------------------------------------------
    // airdrop()
    // -------------------------------------------------------------------

    function _recipients() internal view returns (address[] memory r, uint256[] memory a) {
        r = new address[](2);
        r[0] = alice;
        r[1] = bob;
        a = new uint256[](2);
        a[0] = 3;
        a[1] = 7;
    }

    function testAirdropMintsToRecipients() public {
        shim.initialize("");
        shim.setMaxSupply(100);
        (address[] memory r, uint256[] memory a) = _recipients();
        shim.airdrop(r, a);
        uint256 id = shim.tokenId();
        assertEq(IERC1155(address(creator)).balanceOf(alice, id), 3);
        assertEq(IERC1155(address(creator)).balanceOf(bob, id), 7);
        (uint256 aliceMinted, uint256 total, uint256 max) = shim.getMintStats(alice);
        assertEq(aliceMinted, 0, "airdrop must not count toward per-wallet mints");
        assertEq(total, 10, "airdrop counts toward total minted");
        assertEq(max, 100, "max supply unchanged when airdrop fits");
    }

    function testAirdropRaisesMaxSupplyWhenExceeded() public {
        shim.initialize("");
        shim.setMaxSupply(5);
        (address[] memory r, uint256[] memory a) = _recipients();
        vm.expectEmit(false, false, false, true, address(shim));
        emit MaxSupplyUpdated(10);
        shim.airdrop(r, a);
        assertEq(shim.maxSupply(), 10);
    }

    function testAirdropCountsTowardSeaDropCap() public {
        shim.initialize("");
        shim.setMaxSupply(12);
        (address[] memory r, uint256[] memory a) = _recipients();
        shim.airdrop(r, a);
        vm.prank(address(seadrop));
        shim.mintSeaDrop(alice, 2);
        vm.prank(address(seadrop));
        vm.expectRevert(abi.encodeWithSelector(MintQuantityExceedsMaxSupply.selector, 13, 12));
        shim.mintSeaDrop(alice, 1);
    }

    function testAirdropRevertsForNonOwner() public {
        shim.initialize("");
        (address[] memory r, uint256[] memory a) = _recipients();
        vm.prank(alice);
        vm.expectRevert(); // TwoStepOwnable: onlyOwner
        shim.airdrop(r, a);
    }

    function testAirdropRevertsBeforeInitialize() public {
        (address[] memory r, uint256[] memory a) = _recipients();
        vm.expectRevert(ManifoldERC1155SeaDropShim.NotInitialized.selector);
        shim.airdrop(r, a);
    }

    function testAirdropRevertsOnLengthMismatch() public {
        shim.initialize("");
        address[] memory r = new address[](2);
        r[0] = alice;
        r[1] = bob;
        uint256[] memory a = new uint256[](1);
        a[0] = 1;
        vm.expectRevert(ManifoldERC1155SeaDropShim.InvalidAirdrop.selector);
        shim.airdrop(r, a);
    }

    // -------------------------------------------------------------------
    // mintSeaDrop()
    // -------------------------------------------------------------------

    function testMintSeaDropRevertsForUnallowedCaller() public {
        shim.initialize("");
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        shim.mintSeaDrop(alice, 1);
    }

    function testMintSeaDropRevertsBeforeInitializeWhenMaxSupplyZero() public {
        // initialize() never called; maxSupply still 0. The shim-local
        // max-supply check trips first: newTotal (1) > cap (0).
        vm.prank(address(seadrop));
        vm.expectRevert(
            abi.encodeWithSelector(MintQuantityExceedsMaxSupply.selector, 1, 0)
        );
        shim.mintSeaDrop(alice, 1);
    }

    function testMintSeaDropRevertsBeforeInitializeWhenMaxSupplySet() public {
        // initialize() never called, but maxSupply *was* set. The local cap
        // check passes; the call then routes mintExtensionExisting on the
        // creator with tokenId=0, which Creator Core rejects (tokenId 0 has
        // no registered extension). The whole tx reverts, so the speculative
        // counter bumps in mintSeaDrop must not persist.
        shim.setMaxSupply(100);

        vm.prank(address(seadrop));
        vm.expectRevert();
        shim.mintSeaDrop(alice, 1);

        (uint256 minted, uint256 total, ) = shim.getMintStats(alice);
        assertEq(minted, 0, "no minter credit on revert");
        assertEq(total, 0, "no total-supply bump on revert");
        assertEq(
            IERC1155(address(creator)).balanceOf(alice, 0),
            0,
            "no ERC1155 balance must be transferred"
        );
    }

    function testMintSeaDropMintsERC1155BalanceToMinter() public {
        shim.initialize("");
        shim.setMaxSupply(100);
        uint256 tokenId = shim.tokenId();

        vm.prank(address(seadrop));
        shim.mintSeaDrop(alice, 5);

        assertEq(IERC1155(address(creator)).balanceOf(alice, tokenId), 5);
    }

    function testMintSeaDropIncrementsCounters() public {
        shim.initialize("");
        shim.setMaxSupply(100);

        vm.prank(address(seadrop));
        shim.mintSeaDrop(alice, 3);

        (
            uint256 minterNumMinted,
            uint256 currentTotalSupply,
            uint256 maxSupply
        ) = shim.getMintStats(alice);
        assertEq(minterNumMinted, 3);
        assertEq(currentTotalSupply, 3);
        assertEq(maxSupply, 100);
    }

    function testMintSeaDropAccumulatesAcrossCallsAndWallets() public {
        shim.initialize("");
        shim.setMaxSupply(100);

        vm.prank(address(seadrop));
        shim.mintSeaDrop(alice, 2);
        vm.prank(address(seadrop));
        shim.mintSeaDrop(alice, 3);
        vm.prank(address(seadrop));
        shim.mintSeaDrop(bob, 1);

        (uint256 aMinted, uint256 aTotal, ) = shim.getMintStats(alice);
        (uint256 bMinted, uint256 bTotal, ) = shim.getMintStats(bob);

        assertEq(aMinted, 5);
        assertEq(bMinted, 1);
        assertEq(aTotal, 6, "currentTotalSupply must be cumulative across wallets");
        assertEq(bTotal, 6);
    }

    function testMintSeaDropRevertsWhenQuantityExceedsMaxSupply() public {
        shim.initialize("");
        shim.setMaxSupply(10);

        vm.prank(address(seadrop));
        vm.expectRevert(
            abi.encodeWithSelector(
                MintQuantityExceedsMaxSupply.selector,
                11,
                10
            )
        );
        shim.mintSeaDrop(alice, 11);
    }

    function testMintSeaDropAllowsMaxSupplyThenRevertsNextMint() public {
        shim.initialize("");
        shim.setMaxSupply(5);

        vm.prank(address(seadrop));
        shim.mintSeaDrop(alice, 5);

        vm.prank(address(seadrop));
        vm.expectRevert(
            abi.encodeWithSelector(MintQuantityExceedsMaxSupply.selector, 6, 5)
        );
        shim.mintSeaDrop(bob, 1);
    }

    function testMintSeaDropAllowsLargeSupply() public {
        // Confirm there is no uint24 ceiling — shim accounting uses uint256.
        shim.initialize("");
        uint256 large = 100_000;
        shim.setMaxSupply(large);

        vm.prank(address(seadrop));
        shim.mintSeaDrop(alice, large);

        (, uint256 currentTotalSupply, uint256 maxSupply) = shim.getMintStats(
            alice
        );
        assertEq(currentTotalSupply, large);
        assertEq(maxSupply, large);
    }

    // -------------------------------------------------------------------
    // getMintStats()
    // -------------------------------------------------------------------

    function testGetMintStatsPreInitialize() public {
        (
            uint256 minterNumMinted,
            uint256 currentTotalSupply,
            uint256 maxSupply
        ) = shim.getMintStats(alice);
        assertEq(minterNumMinted, 0);
        assertEq(currentTotalSupply, 0);
        assertEq(maxSupply, 0);
    }

    function testGetMintStatsReflectsMaxSupplyChange() public {
        shim.initialize("");
        shim.setMaxSupply(42);
        (, , uint256 maxSupply) = shim.getMintStats(alice);
        assertEq(maxSupply, 42);
    }

    // -------------------------------------------------------------------
    // SeaDrop integration end-to-end (config + mint via real SeaDrop)
    // -------------------------------------------------------------------

    function testEndToEndPublicDropMintViaSeaDrop() public {
        shim.initialize("");
        shim.setMaxSupply(100);

        // Configure public drop on real SeaDrop via the inherited owner-gated
        // setter — this is the key ergonomic win of the new architecture.
        PublicDrop memory pd = PublicDrop({
            mintPrice: 0.01 ether,
            startTime: uint48(block.timestamp),
            endTime: uint48(block.timestamp + 1 days),
            maxTotalMintableByWallet: 5,
            feeBps: 1000, // 10%
            restrictFeeRecipients: true
        });
        shim.updatePublicDrop(address(seadrop), pd);
        shim.updateCreatorPayoutAddress(address(seadrop), payoutAddress);
        shim.updateAllowedFeeRecipient(address(seadrop), feeRecipient, true);

        uint256 quantity = 3;
        uint256 totalCost = pd.mintPrice * quantity;

        vm.deal(alice, totalCost);
        vm.prank(alice);
        seadrop.mintPublic{value: totalCost}(
            address(shim),
            feeRecipient,
            address(0), // minterIfNotPayer — zero means msg.sender
            quantity
        );

        // Mint landed on the creator contract for the bound tokenId.
        uint256 tokenId = shim.tokenId();
        assertEq(IERC1155(address(creator)).balanceOf(alice, tokenId), quantity);

        (uint256 aMinted, uint256 total, ) = shim.getMintStats(alice);
        assertEq(aMinted, quantity);
        assertEq(total, quantity);
    }

    function testSeaDropEnforcesPerWalletCapAcrossPublicMints() public {
        shim.initialize("");
        shim.setMaxSupply(100);

        PublicDrop memory pd = PublicDrop({
            mintPrice: 0,
            startTime: uint48(block.timestamp),
            endTime: uint48(block.timestamp + 1 days),
            maxTotalMintableByWallet: 2,
            feeBps: 0,
            restrictFeeRecipients: true
        });
        shim.updatePublicDrop(address(seadrop), pd);
        shim.updateCreatorPayoutAddress(address(seadrop), payoutAddress);
        shim.updateAllowedFeeRecipient(address(seadrop), feeRecipient, true);

        vm.prank(alice);
        seadrop.mintPublic(address(shim), feeRecipient, address(0), 2);

        vm.prank(alice);
        vm.expectRevert(); // MintQuantityExceedsMaxMintedPerWallet on SeaDrop
        seadrop.mintPublic(address(shim), feeRecipient, address(0), 1);
    }

    // -------------------------------------------------------------------
    // supportsInterface (inherited)
    // -------------------------------------------------------------------

    // -------------------------------------------------------------------
    // supportsInterface (inherited)
    // -------------------------------------------------------------------

    function testSupportsInterfaceCovers165AndSeaDrop() public {
        assertTrue(shim.supportsInterface(type(INonFungibleSeaDropToken).interfaceId));
        assertTrue(
            shim.supportsInterface(
                type(ISeaDropTokenContractMetadata).interfaceId
            )
        );
        assertTrue(shim.supportsInterface(0x01ffc9a7)); // ERC165
    }

    // -------------------------------------------------------------------
    // updateURI — Creator Core token metadata passthrough
    // -------------------------------------------------------------------

    function testUpdateURISetsCreatorTokenURI() public {
        shim.initialize("");
        uint256 tokenId = shim.tokenId();

        vm.expectEmit(true, false, false, true, address(shim));
        emit TokenURIUpdated(tokenId, "ipfs://bafyidentical/metadata.json");
        shim.updateURI("ipfs://bafyidentical/metadata.json");

        assertEq(creator.uri(tokenId), "ipfs://bafyidentical/metadata.json");
    }

    function testUpdateURIRevertsBeforeInitialize() public {
        vm.expectRevert(ManifoldERC1155SeaDropShim.NotInitialized.selector);
        shim.updateURI("ipfs://nope");
    }

    function testUpdateURIRevertsForNonOwner() public {
        shim.initialize("");
        vm.prank(alice);
        vm.expectRevert(); // TwoStepOwnable: OnlyOwner
        shim.updateURI("ipfs://hijack");
    }

    function testUpdateURIIsRewriteableForReveal() public {
        shim.initialize("");
        shim.setMaxSupply(10);
        uint256 tokenId = shim.tokenId();

        // Pre-reveal URI.
        shim.updateURI("ipfs://prereveal");
        vm.prank(address(seadrop));
        shim.mintSeaDrop(alice, 1);
        assertEq(creator.uri(tokenId), "ipfs://prereveal");
        assertEq(IERC1155(address(creator)).balanceOf(alice, tokenId), 1);

        // Reveal: shim owner rewrites the URI on the creator contract.
        shim.updateURI("ipfs://revealed/metadata.json");
        assertEq(creator.uri(tokenId), "ipfs://revealed/metadata.json");
    }

    // -------------------------------------------------------------------
    // Reentrancy — proves nonReentrant on mintSeaDrop blocks the attack
    // -------------------------------------------------------------------

    function testMintSeaDropBlocksReentrancyViaERC1155Receiver() public {
        shim.initialize("");
        shim.setMaxSupply(100);

        ReentrantMinter attacker = new ReentrantMinter(address(shim));

        // First call enters mintSeaDrop, which calls Creator Core's
        // mintExtensionExisting, which calls _mint -> ERC1155 safe-transfer
        // hook on the attacker, which re-enters mintSeaDrop. The shim's
        // `nonReentrant` modifier reverts the inner call. Because the
        // attacker swallows nothing and Creator Core surfaces the failure,
        // the outer mint reverts too — counters remain unchanged.
        vm.prank(address(seadrop));
        vm.expectRevert(); // solmate ReentrancyGuard "REENTRANCY"
        shim.mintSeaDrop(address(attacker), 1);

        // Confirm no state mutation occurred.
        (uint256 minted, uint256 total, ) = shim.getMintStats(address(attacker));
        assertEq(minted, 0, "reentrancy attempt must not credit minter");
        assertEq(total, 0, "reentrancy attempt must not bump total supply");
        assertEq(
            IERC1155(address(creator)).balanceOf(address(attacker), shim.tokenId()),
            0,
            "no ERC1155 balance must be transferred"
        );
    }

    // -------------------------------------------------------------------
    // mintAllowList end-to-end — covers the allowlist phase path
    // -------------------------------------------------------------------

    function testEndToEndAllowListMintViaSeaDrop() public {
        shim.initialize("");
        shim.setMaxSupply(100);

        // Allowlist params for `alice`. Single-leaf merkle tree means
        // root == leaf and the proof is empty.
        MintParams memory params = MintParams({
            mintPrice: 0, // free allowlist phase per the CON-2955 spec
            maxTotalMintableByWallet: 5,
            startTime: block.timestamp,
            endTime: block.timestamp + 1 days,
            dropStageIndex: 1,
            maxTokenSupplyForStage: 100,
            feeBps: 0,
            restrictFeeRecipients: true
        });
        bytes32 leaf = keccak256(abi.encode(alice, params));

        AllowListData memory ald = AllowListData({
            merkleRoot: leaf,
            publicKeyURIs: new string[](0),
            allowListURI: ""
        });
        shim.updateAllowList(address(seadrop), ald);
        shim.updateCreatorPayoutAddress(address(seadrop), payoutAddress);
        shim.updateAllowedFeeRecipient(address(seadrop), feeRecipient, true);

        bytes32[] memory proof = new bytes32[](0);

        vm.prank(alice);
        seadrop.mintAllowList(
            address(shim),
            feeRecipient,
            address(0),
            3,
            params,
            proof
        );

        uint256 tokenId = shim.tokenId();
        assertEq(IERC1155(address(creator)).balanceOf(alice, tokenId), 3);

        (uint256 aMinted, uint256 total, ) = shim.getMintStats(alice);
        assertEq(aMinted, 3);
        assertEq(total, 3);
    }

    function testWalletCapIsCumulativeAcrossAllowListAndPublic() public {
        // CON-2955 spec: per-wallet cap is cumulative across phases.
        // SeaDrop reads `getMintStats(minter).minterNumMinted` which is our
        // shim-local counter — this test proves an allowlist mint counts
        // toward the public-phase per-wallet cap, and vice-versa.
        shim.initialize("");
        shim.setMaxSupply(100);

        // Allowlist phase: free, cap 2.
        MintParams memory params = MintParams({
            mintPrice: 0,
            maxTotalMintableByWallet: 2,
            startTime: block.timestamp,
            endTime: block.timestamp + 1 days,
            dropStageIndex: 1,
            maxTokenSupplyForStage: 100,
            feeBps: 0,
            restrictFeeRecipients: true
        });
        bytes32 leaf = keccak256(abi.encode(alice, params));
        AllowListData memory ald = AllowListData({
            merkleRoot: leaf,
            publicKeyURIs: new string[](0),
            allowListURI: ""
        });
        shim.updateAllowList(address(seadrop), ald);

        // Public phase: paid, cap 3 total per wallet (= allowlist + 1 more).
        PublicDrop memory pd = PublicDrop({
            mintPrice: 0,
            startTime: uint48(block.timestamp),
            endTime: uint48(block.timestamp + 1 days),
            maxTotalMintableByWallet: 3,
            feeBps: 0,
            restrictFeeRecipients: true
        });
        shim.updatePublicDrop(address(seadrop), pd);
        shim.updateCreatorPayoutAddress(address(seadrop), payoutAddress);
        shim.updateAllowedFeeRecipient(address(seadrop), feeRecipient, true);

        // Step 1: alice mints 2 from allowlist (hits allowlist cap).
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(alice);
        seadrop.mintAllowList(
            address(shim),
            feeRecipient,
            address(0),
            2,
            params,
            proof
        );

        // Step 2: alice mints 1 from public — succeeds (2 + 1 = 3 = cap).
        vm.prank(alice);
        seadrop.mintPublic(address(shim), feeRecipient, address(0), 1);

        // Step 3: alice tries to mint 1 more from public — exceeds cumulative cap.
        vm.prank(alice);
        vm.expectRevert(); // MintQuantityExceedsMaxMintedPerWallet
        seadrop.mintPublic(address(shim), feeRecipient, address(0), 1);

        (uint256 minted, , ) = shim.getMintStats(alice);
        assertEq(minted, 3, "cumulative across allowlist + public must equal 3");
    }

    // -------------------------------------------------------------------
    // Fee split — proves SeaDrop actually pays out
    // -------------------------------------------------------------------

    function testPublicMintSplitsPaymentBetweenCreatorAndFeeRecipient() public {
        shim.initialize("");
        shim.setMaxSupply(100);

        PublicDrop memory pd = PublicDrop({
            mintPrice: 1 ether,
            startTime: uint48(block.timestamp),
            endTime: uint48(block.timestamp + 1 days),
            maxTotalMintableByWallet: 5,
            feeBps: 1000, // 10% to feeRecipient, 90% to creator
            restrictFeeRecipients: true
        });
        shim.updatePublicDrop(address(seadrop), pd);
        shim.updateCreatorPayoutAddress(address(seadrop), payoutAddress);
        shim.updateAllowedFeeRecipient(address(seadrop), feeRecipient, true);

        uint256 quantity = 2;
        uint256 totalCost = pd.mintPrice * quantity;
        uint256 expectedFee = (totalCost * pd.feeBps) / 10_000;
        uint256 expectedPayout = totalCost - expectedFee;

        vm.deal(alice, totalCost);
        uint256 creatorBalanceBefore = payoutAddress.balance;
        uint256 feeBalanceBefore = feeRecipient.balance;

        vm.prank(alice);
        seadrop.mintPublic{value: totalCost}(
            address(shim),
            feeRecipient,
            address(0),
            quantity
        );

        assertEq(
            payoutAddress.balance - creatorBalanceBefore,
            expectedPayout,
            "creator payout address must receive 90% of mint revenue"
        );
        assertEq(
            feeRecipient.balance - feeBalanceBefore,
            expectedFee,
            "fee recipient must receive 10% of mint revenue"
        );
    }

    function testPublicMintRevertsForUnallowedFeeRecipient() public {
        shim.initialize("");
        shim.setMaxSupply(100);

        PublicDrop memory pd = PublicDrop({
            mintPrice: 0,
            startTime: uint48(block.timestamp),
            endTime: uint48(block.timestamp + 1 days),
            maxTotalMintableByWallet: 5,
            feeBps: 1000,
            restrictFeeRecipients: true // <- gate is on
        });
        shim.updatePublicDrop(address(seadrop), pd);
        shim.updateCreatorPayoutAddress(address(seadrop), payoutAddress);
        // Note: feeRecipient is NOT added to allowedFeeRecipients.

        vm.prank(alice);
        vm.expectRevert(); // FeeRecipientNotAllowed
        seadrop.mintPublic(address(shim), feeRecipient, address(0), 1);
    }

    // -------------------------------------------------------------------
    // updateAllowedSeaDrop — emergency stop / SeaDrop rotation
    // -------------------------------------------------------------------

    function testUpdateAllowedSeaDropRevokesAccess() public {
        shim.initialize("");
        shim.setMaxSupply(100);

        // Verify the original SeaDrop can mint.
        vm.prank(address(seadrop));
        shim.mintSeaDrop(alice, 1);

        // Owner revokes all SeaDrop deployments via empty array.
        address[] memory empty = new address[](0);
        shim.updateAllowedSeaDrop(empty);

        // Original SeaDrop now rejected.
        vm.prank(address(seadrop));
        vm.expectRevert(); // OnlyAllowedSeaDrop
        shim.mintSeaDrop(alice, 1);
    }

    function testUpdateAllowedSeaDropRevertsForNonOwner() public {
        address[] memory empty = new address[](0);
        vm.prank(alice);
        vm.expectRevert();
        shim.updateAllowedSeaDrop(empty);
    }

    // -------------------------------------------------------------------
    // Transfer lock
    // -------------------------------------------------------------------

    bytes internal constant APPROVAL_FAILURE = "Extension approval failure";

    function _lockedDrop() internal returns (uint256 id) {
        shim.initialize("");
        shim.setMaxSupply(100);
        (address[] memory r, uint256[] memory a) = _recipients();
        shim.airdrop(r, a); // alice 3, bob 7
        id = shim.tokenId();
        shim.setTransferLock(block.timestamp + 1 days);
    }

    function _transfer(address from, address to, uint256 id, uint256 amount) internal {
        vm.prank(from);
        IERC1155(address(creator)).safeTransferFrom(from, to, id, amount, "");
    }

    function testSupportsApproveTransferInterfaces() public {
        assertTrue(shim.supportsInterface(type(IERC1155CreatorExtensionApproveTransfer).interfaceId));
        assertTrue(shim.supportsInterface(0x93a80b14), "v1 approve-transfer id");
        // Existing surface unchanged.
        assertTrue(shim.supportsInterface(type(INonFungibleSeaDropToken).interfaceId));
        assertTrue(shim.supportsInterface(type(ISeaDropTokenContractMetadata).interfaceId));
        assertTrue(shim.supportsInterface(0x01ffc9a7), "ERC165");
        assertTrue(shim.supportsInterface(0x2a55205a), "ERC2981");
        assertFalse(shim.supportsInterface(0xffffffff));
    }

    function testRegisterOptsInAndInitializeOptsOut() public {
        // setUp's registerExtension opted the shim in (it advertises the
        // interface). initialize() must opt it back out.
        vm.expectEmit(true, false, false, true, address(creator));
        emit ExtensionApproveTransferUpdated(address(shim), false);
        shim.initialize("");
    }

    function testUnlockedDropDoesNotConsultShim() public {
        shim.initialize("");
        shim.setMaxSupply(100);
        (address[] memory r, uint256[] memory a) = _recipients();
        shim.airdrop(r, a);
        uint256 id = shim.tokenId();

        // Prove the shim is opted out: a contract-wide approver that rejects
        // everything is what the creator consults for this token.
        RejectAllApprover reject = new RejectAllApprover();
        creator.setApproveTransfer(address(reject));
        vm.prank(alice);
        vm.expectRevert(APPROVAL_FAILURE);
        IERC1155(address(creator)).safeTransferFrom(alice, bob, id, 1, "");

        // Without a base approver, transfers go through untouched.
        creator.setApproveTransfer(address(0));
        _transfer(alice, bob, id, 1);
        assertEq(IERC1155(address(creator)).balanceOf(bob, id), 8);
    }

    function testLockBlocksTransfers() public {
        uint256 id = _lockedDrop();

        vm.prank(alice);
        vm.expectRevert(APPROVAL_FAILURE);
        IERC1155(address(creator)).safeTransferFrom(alice, bob, id, 1, "");

        // Batch transfers too.
        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;
        vm.prank(alice);
        vm.expectRevert(APPROVAL_FAILURE);
        IERC1155(address(creator)).safeBatchTransferFrom(alice, bob, ids, amounts, "");

        // Approved operators (marketplaces) too.
        vm.prank(alice);
        IERC1155(address(creator)).setApprovalForAll(feeRecipient, true);
        vm.prank(feeRecipient);
        vm.expectRevert(APPROVAL_FAILURE);
        IERC1155(address(creator)).safeTransferFrom(alice, bob, id, 1, "");

        // Sending to a dead address is a transfer, not a burn.
        vm.prank(alice);
        vm.expectRevert(APPROVAL_FAILURE);
        IERC1155(address(creator)).safeTransferFrom(alice, address(0xdEaD), id, 1, "");
    }

    function testLockAllowsMintsAirdropsAndBurns() public {
        uint256 id = _lockedDrop();

        // SeaDrop mint.
        vm.prank(address(seadrop));
        shim.mintSeaDrop(alice, 2);
        assertEq(IERC1155(address(creator)).balanceOf(alice, id), 5);

        // Owner airdrop.
        address[] memory r = new address[](1);
        r[0] = bob;
        uint256[] memory a = new uint256[](1);
        a[0] = 1;
        shim.airdrop(r, a);
        assertEq(IERC1155(address(creator)).balanceOf(bob, id), 8);

        // Holder burn through the creator contract.
        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2;
        vm.prank(alice);
        creator.burn(alice, ids, amounts);
        assertEq(IERC1155(address(creator)).balanceOf(alice, id), 3);
    }

    function testLockAllowsPublicMintThroughSeaDrop() public {
        uint256 id = _lockedDrop();
        PublicDrop memory pd = PublicDrop({
            mintPrice: 0.01 ether,
            startTime: uint48(block.timestamp),
            endTime: uint48(block.timestamp + 1 days),
            maxTotalMintableByWallet: 5,
            feeBps: 0,
            restrictFeeRecipients: true
        });
        shim.updatePublicDrop(address(seadrop), pd);
        shim.updateCreatorPayoutAddress(address(seadrop), payoutAddress);
        shim.updateAllowedFeeRecipient(address(seadrop), feeRecipient, true);

        // A collector with no prior balance mints through SeaDrop mid-lock.
        address carol = address(0xCA201);
        vm.deal(carol, 0.02 ether);
        vm.prank(carol);
        seadrop.mintPublic{value: 0.02 ether}(address(shim), feeRecipient, address(0), 2);
        assertEq(IERC1155(address(creator)).balanceOf(carol, id), 2);

        // ...and still can't pass them on until the lock ends.
        vm.prank(carol);
        vm.expectRevert(APPROVAL_FAILURE);
        IERC1155(address(creator)).safeTransferFrom(carol, alice, id, 1, "");
    }

    function testLockOnlyAffectsShimToken() public {
        uint256 id = _lockedDrop();

        // A base token on the same creator contract stays transferable.
        address[] memory to = new address[](1);
        to[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5;
        string[] memory uris = new string[](1);
        uint256 baseId = creator.mintBaseNew(to, amounts, uris)[0];
        _transfer(alice, bob, baseId, 1);
        assertEq(IERC1155(address(creator)).balanceOf(bob, baseId), 1);

        // So does a token from a second, unlocked shim.
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = address(seadrop);
        ManifoldERC1155SeaDropShim other = new ManifoldERC1155SeaDropShim(
            NAME, SYMBOL, allowedSeaDrop, address(creator), address(this)
        );
        creator.registerExtension(address(other), "");
        other.initialize("");
        other.setMaxSupply(10);
        address[] memory r = new address[](1);
        r[0] = alice;
        uint256[] memory a = new uint256[](1);
        a[0] = 1;
        other.airdrop(r, a);
        _transfer(alice, bob, other.tokenId(), 1);

        // The locked token is still locked.
        vm.prank(alice);
        vm.expectRevert(APPROVAL_FAILURE);
        IERC1155(address(creator)).safeTransferFrom(alice, bob, id, 1, "");
    }

    function testLockExpiresOnItsOwn() public {
        uint256 id = _lockedDrop();
        uint256 until = shim.transferLockUntil();

        vm.warp(until - 1);
        vm.prank(alice);
        vm.expectRevert(APPROVAL_FAILURE);
        IERC1155(address(creator)).safeTransferFrom(alice, bob, id, 1, "");

        vm.warp(until);
        _transfer(alice, bob, id, 1);
        assertEq(IERC1155(address(creator)).balanceOf(bob, id), 8);
    }

    function testUnlockNowOptsOut() public {
        uint256 id = _lockedDrop();

        vm.expectEmit(true, false, false, true, address(creator));
        emit ExtensionApproveTransferUpdated(address(shim), false);
        vm.expectEmit(false, false, false, true, address(shim));
        emit TransferLockUpdated(0);
        shim.setTransferLock(0);

        assertEq(shim.transferLockUntil(), 0);
        _transfer(alice, bob, id, 1);
    }

    function testSetTransferLockInPastOptsOut() public {
        shim.initialize("");
        vm.warp(1000);
        vm.expectEmit(true, false, false, true, address(creator));
        emit ExtensionApproveTransferUpdated(address(shim), false);
        shim.setTransferLock(999);
    }

    function testSetTransferLockOptsInAndEmits() public {
        shim.initialize("");
        uint256 until = block.timestamp + 1 days;
        vm.expectEmit(true, false, false, true, address(creator));
        emit ExtensionApproveTransferUpdated(address(shim), true);
        vm.expectEmit(false, false, false, true, address(shim));
        emit TransferLockUpdated(until);
        shim.setTransferLock(until);
        assertEq(shim.transferLockUntil(), until);
    }

    function testLockHasNoUpperBound() public {
        uint256 id = _lockedDrop();
        shim.setTransferLock(type(uint256).max);
        vm.warp(block.timestamp + 365 days * 100);
        vm.prank(alice);
        vm.expectRevert(APPROVAL_FAILURE);
        IERC1155(address(creator)).safeTransferFrom(alice, bob, id, 1, "");
        shim.setTransferLock(0);
        _transfer(alice, bob, id, 1);
    }

    function testLockOverridesContractWideApprover() public {
        uint256 id = _lockedDrop();
        RejectAllApprover reject = new RejectAllApprover();
        creator.setApproveTransfer(address(reject));

        // Once the lock time passes the shim (still opted in) approves, and
        // the contract-wide approver is not consulted for this token.
        vm.warp(shim.transferLockUntil());
        _transfer(alice, bob, id, 1);

        // After an explicit unlock the shim opts out and the contract-wide
        // approver applies again.
        shim.setTransferLock(0);
        vm.prank(alice);
        vm.expectRevert(APPROVAL_FAILURE);
        IERC1155(address(creator)).safeTransferFrom(alice, bob, id, 1, "");
    }

    function testCreatorAdminCannotSetTransferLock() public {
        _lockedDrop();
        address carol = address(0xCA201);
        creator.approveAdmin(carol);

        vm.prank(carol);
        vm.expectRevert(TwoStepOwnable.OnlyOwner.selector);
        shim.setTransferLock(0);

        vm.prank(carol);
        vm.expectRevert(TwoStepOwnable.OnlyOwner.selector);
        shim.setApproveTransfer(address(creator), false);
    }

    function testSetTransferLockRevertsForStranger() public {
        shim.initialize("");
        vm.prank(alice);
        vm.expectRevert(TwoStepOwnable.OnlyOwner.selector);
        shim.setTransferLock(block.timestamp + 1 days);
    }

    function testSetTransferLockRevertsBeforeInitialize() public {
        vm.expectRevert(ManifoldERC1155SeaDropShim.NotInitialized.selector);
        shim.setTransferLock(block.timestamp + 1 days);
    }

    function testSetApproveTransferAuthAndCreatorCheck() public {
        shim.initialize("");

        vm.prank(alice);
        vm.expectRevert(TwoStepOwnable.OnlyOwner.selector);
        shim.setApproveTransfer(address(creator), true);

        vm.expectRevert(ManifoldERC1155SeaDropShim.InvalidCreator.selector);
        shim.setApproveTransfer(address(0xBAD), true);

        vm.expectEmit(true, false, false, true, address(creator));
        emit ExtensionApproveTransferUpdated(address(shim), true);
        shim.setApproveTransfer(address(creator), true);
    }

    function testApproveTransferViews() public {
        shim.initialize("");
        uint256[] memory none = new uint256[](0);
        assertTrue(shim.approveTransfer(address(0), alice, bob, none, none));
        shim.setTransferLock(block.timestamp + 1 days);
        assertFalse(shim.approveTransfer(address(0), alice, bob, none, none));
        assertTrue(shim.approveTransfer(address(0), alice, address(0), none, none), "burn");
        assertFalse(shim.approveTransfer(alice, bob, none, none), "v1 variant");
        assertTrue(shim.approveTransfer(alice, address(0), none, none), "v1 burn");
    }
}
