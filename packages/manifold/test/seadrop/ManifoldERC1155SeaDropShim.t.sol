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
    PublicDrop
} from "seadrop/src/lib/SeaDropStructs.sol";
import {
    ERC721SeaDropStructsErrorsAndEvents
} from "seadrop/src/lib/ERC721SeaDropStructsErrorsAndEvents.sol";

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
            INSTANCE_ID
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
            INSTANCE_ID + 1
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
    // Creator Core metadata passthroughs
    // -------------------------------------------------------------------

    function testSetBaseTokenURIExtensionWithSuffix() public {
        shim.initialize();
        uint256 tokenId = shim.tokenId();

        // 1-arg variant — Creator Core defaults identical=false, so the
        // returned URI is `<base><tokenId.toString()>`.
        shim.setBaseTokenURIExtension("ipfs://bafy/");

        assertEq(
            creator.uri(tokenId),
            string(abi.encodePacked("ipfs://bafy/", _toString(tokenId)))
        );
    }

    function testSetBaseTokenURIExtensionIdenticalReturnsRawUri() public {
        shim.initialize();
        uint256 tokenId = shim.tokenId();

        // identical=true — every tokenId resolves to the exact same URI,
        // which is what we want for an ERC1155 drop with a single bound
        // tokenId (no suffix appended).
        shim.setBaseTokenURIExtension(
            "ipfs://bafyidentical/metadata.json",
            true
        );

        assertEq(creator.uri(tokenId), "ipfs://bafyidentical/metadata.json");
    }

    function testSetBaseTokenURIExtensionRevertsForNonOwner() public {
        shim.initialize();
        vm.prank(alice);
        vm.expectRevert(); // TwoStepOwnable: OnlyOwner
        shim.setBaseTokenURIExtension("ipfs://nope/");

        vm.prank(alice);
        vm.expectRevert();
        shim.setBaseTokenURIExtension("ipfs://nope/", true);
    }

    function testSetBaseTokenURIExtensionPersistsAcrossMints() public {
        shim.initialize();
        shim.setMaxSupply(10);
        shim.setBaseTokenURIExtension("https://api.example/meta.json", true);

        uint256 tokenId = shim.tokenId();

        // Mint after setting base URI — uri must still resolve correctly.
        vm.prank(address(seadrop));
        shim.mintSeaDrop(alice, 3);

        assertEq(creator.uri(tokenId), "https://api.example/meta.json");
        assertEq(IERC1155(address(creator)).balanceOf(alice, tokenId), 3);
    }

    function testSetBaseTokenURIExtensionUpdatableAfterMint() public {
        shim.initialize();
        shim.setMaxSupply(10);
        shim.setBaseTokenURIExtension("ipfs://prereveal", true);

        uint256 tokenId = shim.tokenId();

        vm.prank(address(seadrop));
        shim.mintSeaDrop(alice, 1);
        assertEq(creator.uri(tokenId), "ipfs://prereveal");

        // Reveal: shim owner updates the base URI on the creator contract.
        shim.setBaseTokenURIExtension("ipfs://revealed/metadata.json", true);
        assertEq(creator.uri(tokenId), "ipfs://revealed/metadata.json");
    }

    function testSetTokenURIExtensionTakesPrecedenceOverBase() public {
        shim.initialize();
        uint256 tokenId = shim.tokenId();

        shim.setBaseTokenURIExtension("ipfs://base/", false);
        // Per-token override should win over the base URI.
        shim.setTokenURIExtension(tokenId, "ipfs://specific.json");

        assertEq(creator.uri(tokenId), "ipfs://specific.json");
    }

    function testSetTokenURIPrefixExtensionPrependsToPerTokenUri() public {
        shim.initialize();
        uint256 tokenId = shim.tokenId();

        // Creator Core only applies the prefix when there's a per-token
        // override stored — base URIs are unaffected.
        shim.setTokenURIPrefixExtension("ar://");
        shim.setTokenURIExtension(tokenId, "kRZf...cidonly");

        assertEq(creator.uri(tokenId), "ar://kRZf...cidonly");
    }

    function testSetTokenURIExtensionRevertsForNonOwner() public {
        shim.initialize();
        uint256 tokenId = shim.tokenId();

        vm.prank(alice);
        vm.expectRevert();
        shim.setTokenURIExtension(tokenId, "ipfs://hijack");

        vm.prank(alice);
        vm.expectRevert();
        shim.setTokenURIPrefixExtension("ar://");
    }

    /// @dev Minimal uint256 → decimal string for the suffix-mode assertion.
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
