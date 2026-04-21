// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

import "forge-std/Test.sol";

import {ERC1155Creator} from "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";

import {IManifoldERC1155SeaDropShim} from "../../contracts/seadrop/IManifoldERC1155SeaDropShim.sol";
import {ManifoldERC1155SeaDropShim} from "../../contracts/seadrop/ManifoldERC1155SeaDropShim.sol";
import {
    AllowListData,
    MultiConfigureStruct,
    PublicDrop,
    StorageProtocol
} from "../../contracts/seadrop/SeaDropStructs.sol";

import {MockSeaDrop} from "./mocks/MockSeaDrop.sol";

/**
 * @notice Shared Foundry harness for every ManifoldERC1155SeaDropShim test.
 * @dev setUp deploys a real ERC1155Creator (not a mock — we want the full
 *      Creator Core mintExtensionNew / mintExtensionExisting paths exercised),
 *      a MockSeaDrop trace mock, and the shim bound to both. The shim is
 *      registered as a Creator Core extension inside the same admin prank so
 *      subsequent tests can call initialize() without repeating the wiring.
 *
 *      _defaultCfg() returns a sane MultiConfigureStruct that every
 *      scenario-specific test can mutate; centralising the defaults keeps
 *      later test stories focused on the field(s) under test.
 */
contract ManifoldERC1155SeaDropShimTest is Test {
    // Shim events re-declared locally so tests can use `emit` + `vm.expectEmit`.
    // Solidity only allows `emit` of events declared in the current contract
    // or a base contract, so mirroring the IManifoldERC1155SeaDropShim
    // signatures here is the cleanest way to assert on them.
    event Initialized(uint256 indexed instanceId, uint256 indexed tokenId);
    event Configured(uint256 indexed instanceId, uint256 indexed tokenId);

    uint256 internal constant INSTANCE_ID = 1;

    // Creator admin for the ERC1155Creator — used to register the shim and
    // later to call initialize() / multiConfigure() via vm.prank.
    address internal creatorAdmin = address(0xA11CE);
    address internal payoutAddress = address(0xBEEF);
    address internal feeRecipient = address(0xFEE);
    address internal notAdmin = address(0xB0B);

    ERC1155Creator internal creator;
    MockSeaDrop internal mockSeaDrop;
    ManifoldERC1155SeaDropShim internal shim;

    function setUp() public virtual {
        vm.startPrank(creatorAdmin);

        creator = new ERC1155Creator("TestCreator", "TEST");
        mockSeaDrop = new MockSeaDrop();

        address[] memory allowed = new address[](1);
        allowed[0] = address(mockSeaDrop);
        shim = new ManifoldERC1155SeaDropShim(address(creator), INSTANCE_ID, allowed);

        creator.registerExtension(address(shim), "");

        vm.stopPrank();
    }

    /**
     * @dev Canonical default MultiConfigureStruct for scenarios that don't
     *      exercise a specific field. Scenario tests should clone into a
     *      memory variable, tweak the fields they care about, then pass in.
     */
    function _defaultCfg() internal view returns (MultiConfigureStruct memory cfg) {
        address[] memory feeRecipients = new address[](1);
        feeRecipients[0] = feeRecipient;

        cfg = MultiConfigureStruct({
            maxSupply: 100,
            maxMintsPerWallet: 5,
            tokenUriLocation: "https://example.com/meta.json",
            storageProtocol: StorageProtocol.NONE,
            contractURI: "https://example.com/contract.json",
            seaDropImpl: address(mockSeaDrop),
            publicDrop: PublicDrop({
                mintPrice: 0.01 ether,
                startTime: uint48(block.timestamp),
                endTime: uint48(block.timestamp + 7 days),
                maxTotalMintableByWallet: 5,
                feeBps: 500,
                restrictFeeRecipients: true
            }),
            allowListData: AllowListData({
                merkleRoot: bytes32(0),
                publicKeyURIs: new string[](0),
                allowListURI: ""
            }),
            creatorPayoutAddress: payoutAddress,
            allowedFeeRecipients: feeRecipients
        });
    }

    function testScaffoldBoots() public {
        assertTrue(address(shim) != address(0), "shim deployed");
        assertTrue(address(creator) != address(0), "creator deployed");
        assertTrue(address(mockSeaDrop) != address(0), "mockSeaDrop deployed");
        assertEq(shim.creatorContractAddress(), address(creator), "shim bound to creator");
        assertEq(shim.instanceId(), INSTANCE_ID, "instanceId stored");

        address[] memory allowed = shim.getAllowedSeaDrop();
        assertEq(allowed.length, 1, "one allowed seadrop");
        assertEq(allowed[0], address(mockSeaDrop), "mockSeaDrop is allowed");
    }

    // -----------------------------------------------------------------------
    // initialize() — happy path + revert cases (US-014)
    // -----------------------------------------------------------------------

    /**
     * @notice Full happy-path assertion: initialize seeds the tokenId via
     *         Creator Core's mintExtensionNew, emits Initialized then
     *         Configured, pushes every local cfg field into shim state, and
     *         forwards publicDrop / allowList / payout / fee-recipient to the
     *         configured SeaDrop impl.
     * @dev A fresh ERC1155Creator assigns its first mintExtensionNew tokenId
     *      as 1 (Creator Core uses `_tokenCount + 1`), so we can hard-code
     *      the expected tokenId in the event match and subsequent tokenURI
     *      read without exposing an internal getter.
     */
    function testInitializeHappyPath() public {
        MultiConfigureStruct memory cfg = _defaultCfg();
        uint256 expectedTokenId = 1;

        // Initialized is emitted BEFORE _applyConfig; Configured at the very
        // end. Ordering matters to indexers that key off Configured to know
        // the drop is fully live, so assert both events in sequence.
        vm.expectEmit(true, true, false, true, address(shim));
        emit Initialized(INSTANCE_ID, expectedTokenId);
        vm.expectEmit(true, true, false, true, address(shim));
        emit Configured(INSTANCE_ID, expectedTokenId);

        vm.prank(creatorAdmin);
        shim.initialize(cfg);

        // --- Local shim state reflects cfg
        assertEq(shim.maxSupply(), cfg.maxSupply, "maxSupply applied");
        assertEq(shim.totalSupply(), 0, "no mints during initialize");
        assertEq(shim.contractURI(), cfg.contractURI, "contractURI applied");
        // StorageProtocol.NONE -> empty prefix, so tokenURI == tokenUriLocation.
        assertEq(shim.tokenURI(expectedTokenId), cfg.tokenUriLocation, "tokenURI assembled");

        // getMintStats exposes _maxMintsPerWallet indirectly via maxSupply;
        // use the maxMintsPerWallet getter-equivalent by checking getMintStats
        // also reflects the cap update path. Here we just assert supply cap
        // propagated; US-016 covers the full getMintStats surface.
        (uint256 minted, uint256 total, uint256 cap) = shim.getMintStats(creatorAdmin);
        assertEq(minted, 0);
        assertEq(total, 0);
        assertEq(cap, cfg.maxSupply);

        // --- MockSeaDrop recorded the forwarded config
        PublicDrop memory pd = mockSeaDrop.lastPublicDrop();
        assertEq(pd.mintPrice, cfg.publicDrop.mintPrice, "publicDrop.mintPrice");
        assertEq(pd.startTime, cfg.publicDrop.startTime, "publicDrop.startTime");
        assertEq(pd.endTime, cfg.publicDrop.endTime, "publicDrop.endTime");
        assertEq(
            pd.maxTotalMintableByWallet,
            cfg.publicDrop.maxTotalMintableByWallet,
            "publicDrop.maxTotalMintableByWallet"
        );
        assertEq(pd.feeBps, cfg.publicDrop.feeBps, "publicDrop.feeBps");
        assertEq(
            pd.restrictFeeRecipients,
            cfg.publicDrop.restrictFeeRecipients,
            "publicDrop.restrictFeeRecipients"
        );

        AllowListData memory ald = mockSeaDrop.lastAllowListData();
        assertEq(ald.merkleRoot, cfg.allowListData.merkleRoot, "allowList.merkleRoot");
        assertEq(ald.allowListURI, cfg.allowListData.allowListURI, "allowList.allowListURI");
        assertEq(
            ald.publicKeyURIs.length,
            cfg.allowListData.publicKeyURIs.length,
            "allowList.publicKeyURIs.length"
        );

        assertEq(mockSeaDrop.lastCreatorPayoutAddress(), payoutAddress, "payout forwarded");
        assertTrue(
            mockSeaDrop.allowedFeeRecipient(feeRecipient),
            "fee recipient allowed on MockSeaDrop"
        );
    }

    /**
     * @notice A non-admin caller cannot initialize; the shim's
     *         creatorAdminRequired modifier reverts with the literal string
     *         "Must be owner or admin of creator contract" (the shim does not
     *         use a custom error here — matches the revert string verbatim).
     */
    function testInitializeRevertsForNonAdmin() public {
        MultiConfigureStruct memory cfg = _defaultCfg();

        vm.prank(notAdmin);
        vm.expectRevert("Must be owner or admin of creator contract");
        shim.initialize(cfg);
    }

    /**
     * @notice Second initialize() on the same shim reverts with
     *         AlreadyInitialized — _tokenId is non-zero after the first call.
     */
    function testInitializeRevertsWhenAlreadyInitialized() public {
        MultiConfigureStruct memory cfg = _defaultCfg();

        vm.prank(creatorAdmin);
        shim.initialize(cfg);

        vm.prank(creatorAdmin);
        vm.expectRevert(IManifoldERC1155SeaDropShim.AlreadyInitialized.selector);
        shim.initialize(cfg);
    }

    /**
     * @notice A shim that was never registered as a Creator Core extension
     *         cannot initialize — Creator Core's requireExtension reverts
     *         during mintExtensionNew with "Must be registered extension".
     * @dev Uses a freshly-constructed shim that skips setUp's registerExtension
     *      step. The freshly-deployed shim passes its own creatorAdminRequired
     *      check (creatorAdmin is the owner of the bound creator), so the
     *      revert can only come from Creator Core's extension gate.
     */
    function testInitializeRevertsWhenShimNotRegistered() public {
        vm.startPrank(creatorAdmin);

        address[] memory allowed = new address[](1);
        allowed[0] = address(mockSeaDrop);
        ManifoldERC1155SeaDropShim unregisteredShim =
            new ManifoldERC1155SeaDropShim(address(creator), INSTANCE_ID, allowed);

        MultiConfigureStruct memory cfg = _defaultCfg();

        vm.expectRevert("Must be registered extension");
        unregisteredShim.initialize(cfg);

        vm.stopPrank();
    }
}
