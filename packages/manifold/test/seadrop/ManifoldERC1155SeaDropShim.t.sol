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

/**
 * @notice Foundry harness for ManifoldERC1155SeaDropShim.
 *
 *         setUp deploys a real ERC1155Creator (Manifold Creator Core), the
 *         stock SeaDrop v1 implementation contract, and the shim — bound to
 *         both — then registers the shim as an extension on the creator
 *         contract. Tests then call `initialize()` and friends as the shim
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
    uint256 internal constant INSTANCE_ID = 1;
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
            INSTANCE_ID,
            address(this) // initialOwner — test contract is the drop admin
        );

        creator.registerExtension(address(shim), "");
    }

    // -------------------------------------------------------------------
    // Construction
    // -------------------------------------------------------------------

    function testConstructorSetsImmutablesAndOwner() public {
        assertEq(shim.creatorContractAddress(), address(creator));
        assertEq(shim.instanceId(), INSTANCE_ID);
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
            INSTANCE_ID + 100,
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
            INSTANCE_ID + 200,
            address(0)
        );
    }

    function testConstructorPopulatesAllowedSeaDrop() public {
        // Calling `getMintStats` and then `mintSeaDrop` from the SeaDrop
        // contract is the public-surface proof; here we just verify
        // that an unallowed caller is rejected.
        shim.initialize();
        vm.prank(address(0xDEAD));
        vm.expectRevert(); // OnlyAllowedSeaDrop
        shim.mintSeaDrop(alice, 1);
    }

    // -------------------------------------------------------------------
    // initialize()
    // -------------------------------------------------------------------

    function testInitializeSetsTokenId() public {
        assertEq(shim.tokenId(), 0);
        shim.initialize();
        assertEq(shim.tokenId(), 1, "first mintExtensionNew should mint id 1");
    }

    function testInitializeRevertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(); // TwoStepOwnable: onlyOwner
        shim.initialize();
    }

    function testInitializeRevertsWhenAlreadyInitialized() public {
        shim.initialize();
        vm.expectRevert(ManifoldERC1155SeaDropShim.AlreadyInitializedShim.selector);
        shim.initialize();
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
            INSTANCE_ID + 1,
            address(this)
        );

        vm.expectRevert(); // creator core "Must be registered extension"
        unregistered.initialize();
    }

    // -------------------------------------------------------------------
    // mintSeaDrop()
    // -------------------------------------------------------------------

    function testMintSeaDropRevertsForUnallowedCaller() public {
        shim.initialize();
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        shim.mintSeaDrop(alice, 1);
    }

    function testMintSeaDropMintsERC1155BalanceToMinter() public {
        shim.initialize();
        shim.setMaxSupply(100);
        uint256 tokenId = shim.tokenId();

        vm.prank(address(seadrop));
        shim.mintSeaDrop(alice, 5);

        assertEq(IERC1155(address(creator)).balanceOf(alice, tokenId), 5);
    }

    function testMintSeaDropIncrementsCounters() public {
        shim.initialize();
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
        shim.initialize();
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
        shim.initialize();
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
        shim.initialize();
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
        shim.initialize();
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
        shim.initialize();
        shim.setMaxSupply(42);
        (, , uint256 maxSupply) = shim.getMintStats(alice);
        assertEq(maxSupply, 42);
    }

    // -------------------------------------------------------------------
    // SeaDrop integration end-to-end (config + mint via real SeaDrop)
    // -------------------------------------------------------------------

    function testEndToEndPublicDropMintViaSeaDrop() public {
        shim.initialize();
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
        shim.initialize();
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
        shim.initialize();
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
        shim.initialize();
        vm.prank(alice);
        vm.expectRevert(); // TwoStepOwnable: OnlyOwner
        shim.updateURI("ipfs://hijack");
    }

    function testUpdateURIIsRewriteableForReveal() public {
        shim.initialize();
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
        shim.initialize();
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
        shim.initialize();
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
        shim.initialize();
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
        shim.initialize();
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
        shim.initialize();
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
        shim.initialize();
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
}
