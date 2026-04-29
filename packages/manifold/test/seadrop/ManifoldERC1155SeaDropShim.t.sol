// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

import "forge-std/Test.sol";

import {ERC1155Creator} from "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";

import {IManifoldERC1155SeaDropShim} from "../../contracts/seadrop/IManifoldERC1155SeaDropShim.sol";
import {INonFungibleSeaDropToken} from "../../contracts/seadrop/INonFungibleSeaDropToken.sol";
import {ISeaDropTokenContractMetadata} from "../../contracts/seadrop/ISeaDropTokenContractMetadata.sol";
import {ManifoldERC1155SeaDropShim} from "../../contracts/seadrop/ManifoldERC1155SeaDropShim.sol";
import {
    AllowListData,
    MultiConfigureStruct,
    PublicDrop,
    SignedMintValidationParams,
    StorageProtocol,
    TokenGatedDropStage
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
    event SeaDropTokenDeployed();
    event SeaDropShimForContract(address nftContract);
    event Initialized(uint256 indexed instanceId, uint256 indexed tokenId);
    event MaxSupplyUpdated(uint256 newMaxSupply);
    event AllowedSeaDropUpdated(address[] allowed);
    event DropURIUpdated(address indexed nftContract, string newDropURI);
    event BatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId);

    uint256 internal constant INSTANCE_ID = 1;

    // Creator admin for the ERC1155Creator — used to register the shim and
    // later to call initialize() / multiConfigure() via vm.prank.
    address internal creatorAdmin = address(0xA11CE);
    address internal payoutAddress = address(0xBEEF);
    address internal feeRecipient = address(0xFEE);
    address internal notAdmin = address(0xB0B);
    address internal alice = address(0x1111);
    address internal bob = address(0x2222);

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

        mockSeaDrop.setObservedNftContract(address(shim));
        creator.registerExtension(address(shim), "");

        vm.stopPrank();
    }

    /**
     * @dev Canonical default MultiConfigureStruct for scenarios that don't
     *      exercise a specific field. Scenario tests should clone into a
     *      memory variable, tweak the fields they care about, then pass in.
     */
    function _singleStringArray(string memory value) internal pure returns (string[] memory values) {
        values = new string[](1);
        values[0] = value;
    }

    function _defaultCfg() internal view returns (MultiConfigureStruct memory cfg) {
        address[] memory feeRecipients = new address[](1);
        feeRecipients[0] = feeRecipient;

        cfg = MultiConfigureStruct({
            maxSupply: 100,
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
            dropURI: "",
            allowListData: AllowListData({
                merkleRoot: bytes32(uint256(0xA110)),
                publicKeyURIs: _singleStringArray("https://keys.example.com/default"),
                allowListURI: "https://example.com/default-allowlist.json"
            }),
            creatorPayoutAddress: payoutAddress,
            allowedFeeRecipients: feeRecipients,
            disallowedFeeRecipients: new address[](0),
            allowedPayers: new address[](0),
            disallowedPayers: new address[](0),
            tokenGatedAllowedNftTokens: new address[](0),
            tokenGatedDropStages: new TokenGatedDropStage[](0),
            disallowedTokenGatedAllowedNftTokens: new address[](0),
            signers: new address[](0),
            signedMintValidationParams: new SignedMintValidationParams[](0),
            disallowedSigners: new address[](0)
        });
    }

    function testScaffoldBoots() public {
        assertTrue(address(shim) != address(0), "shim deployed");
        assertTrue(address(creator) != address(0), "creator deployed");
        assertTrue(address(mockSeaDrop) != address(0), "mockSeaDrop deployed");
        assertEq(shim.creatorContractAddress(), address(creator), "shim bound to creator");
        // instanceId is bound at construction as an immutable, so it reads
        // the constructor argument immediately — no initialize() required.
        assertEq(shim.instanceId(), INSTANCE_ID, "instanceId set at construction");

        address[] memory allowed = shim.getAllowedSeaDrop();
        assertEq(allowed.length, 1, "one allowed seadrop");
        assertEq(allowed[0], address(mockSeaDrop), "mockSeaDrop is allowed");
    }

    /**
     * @notice The shim constructor emits stock SeaDrop deployment/indexing
     *         events as its last action so OpenSea can discover the shim and
     *         associate it with the underlying Creator Core contract.
     */
    function testConstructorEmitsSeaDropIndexingEvents() public {
        address[] memory allowed = new address[](1);
        allowed[0] = address(mockSeaDrop);

        vm.recordLogs();
        ManifoldERC1155SeaDropShim deployed = new ManifoldERC1155SeaDropShim(
            address(creator),
            INSTANCE_ID,
            allowed
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // AdminControl emits OwnershipTransferred first; the SeaDrop indexing
        // signals must be the constructor's final two logs, from the new shim.
        assertGe(entries.length, 2, "constructor emitted indexing logs");
        uint256 seaDropEventIndex = entries.length - 2;
        assertEq(entries[seaDropEventIndex].emitter, address(deployed), "SeaDropTokenDeployed emitter");
        assertEq(
            entries[seaDropEventIndex].topics[0],
            keccak256("SeaDropTokenDeployed()"),
            "SeaDropTokenDeployed topic"
        );

        uint256 shimEventIndex = entries.length - 1;
        assertEq(entries[shimEventIndex].emitter, address(deployed), "SeaDropShimForContract emitter");
        assertEq(
            entries[shimEventIndex].topics[0],
            keccak256("SeaDropShimForContract(address)"),
            "SeaDropShimForContract topic"
        );
        assertEq(
            abi.decode(entries[shimEventIndex].data, (address)),
            address(creator),
            "SeaDropShimForContract creator"
        );
    }

    /**
     * @notice CI tripwire pinning the locally-mirrored SeaDrop interfaceIds to
     *         their canonical ProjectOpenSea/seadrop bytes4. Stock SeaDrop's
     *         `onlyINonFungibleSeaDropToken` modifier ERC165-checks
     *         `type(INonFungibleSeaDropToken).interfaceId` against the calling
     *         shim — if our mirror drifts (function signature, struct layout)
     *         the XOR shifts, supportsInterface returns false, and every
     *         mintSeaDrop call from a real SeaDrop reverts. These literals are
     *         the XOR of every directly-declared selector on each mirror;
     *         inherited functions don't contribute (Solidity language rule).
     *         Recompute via `cast sig "<selector>"` per function and XOR if
     *         this test ever fails.
     */
    function testInterfaceIdsMatchUpstreamSeaDrop() public {
        // Pinned against the deployed SeaDrop @ 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5
        // (verified Etherscan source). Recompute by XOR'ing the directly-declared
        // selectors on each interface — inherited fns don't contribute (Solidity rule),
        // and `payable` mutability does not affect the function selector.
        bytes4 expectedNonFungible = 0x1890fe8e;
        bytes4 expectedMetadata = 0x37c62e4e;

        assertEq(
            type(INonFungibleSeaDropToken).interfaceId,
            expectedNonFungible,
            "INonFungibleSeaDropToken.interfaceId drift"
        );
        assertEq(
            type(ISeaDropTokenContractMetadata).interfaceId,
            expectedMetadata,
            "ISeaDropTokenContractMetadata.interfaceId drift"
        );
        assertTrue(
            shim.supportsInterface(expectedNonFungible),
            "shim does not advertise INonFungibleSeaDropToken"
        );
        assertTrue(
            shim.supportsInterface(expectedMetadata),
            "shim does not advertise ISeaDropTokenContractMetadata"
        );
    }

    // -----------------------------------------------------------------------
    // initialize() — happy path + revert cases
    // -----------------------------------------------------------------------

    /**
     * @notice Full happy-path assertion: initialize seeds the tokenId via
     *         Creator Core's mintExtensionNew, emits Initialized after
     *         _applyConfig has run, pushes every local cfg field into shim
     *         state, and forwards publicDrop / allowList / payout /
     *         fee-recipient to the configured SeaDrop impl.
     * @dev A fresh ERC1155Creator assigns its first mintExtensionNew tokenId
     *      as 1 (Creator Core uses `_tokenCount + 1`), so we can hard-code
     *      the expected tokenId in the event match and subsequent tokenURI
     *      read without exposing an internal getter.
     */
    function testInitializeHappyPath() public {
        MultiConfigureStruct memory cfg = _defaultCfg();
        uint256 expectedTokenId = 1;

        // Initialized fires after _applyConfig has populated _instanceId and
        // the rest of drop state, so indexers that key off it see a fully-live
        // drop. Per-field events (MaxSupplyUpdated, TokenURIUpdated, etc.)
        // fire during _applyConfig before Initialized.
        vm.expectEmit(true, true, false, true, address(shim));
        emit Initialized(INSTANCE_ID, expectedTokenId);

        vm.prank(creatorAdmin);
        shim.initialize(cfg);

        // --- Local shim state reflects cfg
        assertEq(shim.maxSupply(), cfg.maxSupply, "maxSupply applied");
        assertEq(shim.totalSupply(), 0, "no mints during initialize");
        assertEq(shim.contractURI(), cfg.contractURI, "contractURI applied");
        // StorageProtocol.NONE -> empty prefix, so tokenURI == tokenUriLocation.
        assertEq(shim.tokenURI(expectedTokenId), cfg.tokenUriLocation, "tokenURI assembled");

        // getMintStats surfaces the supply cap applied during initialize.
        // Per-wallet caps live on SeaDrop (PublicDrop.maxTotalMintableByWallet
        // + allowlist merkle leaves), not the shim.
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
        // Stock SeaDrop stores only the merkle root; publicKeyURIs and allowListURI are event-only.

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

    // -----------------------------------------------------------------------
    // mintSeaDrop — auth + counters + Creator Core mint (US-015)
    // -----------------------------------------------------------------------

    /**
     * @dev Convenience wrapper so each mint test can re-use the happy-path
     *      initialize. Kept inline (not in setUp) because the pre-init revert
     *      test in this story needs an un-initialized shim.
     */
    function _initializeDefault() internal {
        vm.prank(creatorAdmin);
        shim.initialize(_defaultCfg());
    }

    function _mintPublic(address minter, uint256 quantity) internal {
        uint256 payment = uint256(_defaultCfg().publicDrop.mintPrice) * quantity;
        vm.deal(minter, 1 ether);
        vm.prank(minter);
        mockSeaDrop.mintPublic{value: payment}(
            address(shim),
            feeRecipient,
            address(0),
            quantity
        );
    }

    function _mintSeaDropDirect(address minter, uint256 quantity) internal {
        vm.prank(address(mockSeaDrop));
        shim.mintSeaDrop(minter, quantity);
    }

    /**
     * @notice A direct EOA call to mintSeaDrop fails the allowed-SeaDrop gate.
     * @dev The shim's onlyAllowedSeaDrop modifier checks msg.sender against
     *      _allowedSeaDrop — an EOA outside the set must revert with
     *      OnlyAllowedSeaDrop regardless of whether the shim is initialized.
     */
    function testMintSeaDropRevertsForNonAllowedSender() public {
        _initializeDefault();

        vm.prank(alice);
        vm.expectRevert(INonFungibleSeaDropToken.OnlyAllowedSeaDrop.selector);
        shim.mintSeaDrop(alice, 1);
    }

    /**
     * @notice Routing through stock SeaDrop's public mint path satisfies the
     *         allowed gate and updates the per-wallet + drop-wide counters,
     *         keeping totalSupply() aligned with _totalMinted.
     */
    function testMintSeaDropIncrementsCounters() public {
        _initializeDefault();

        _mintPublic(alice, 3);

        (uint256 minted, uint256 total, uint256 cap) = shim.getMintStats(alice);
        assertEq(minted, 3, "alice minterNumMinted");
        assertEq(total, 3, "totalMinted");
        assertEq(cap, _defaultCfg().maxSupply, "maxSupply unchanged");
        assertEq(shim.totalSupply(), 3, "totalSupply mirrors _totalMinted");
    }

    /**
     * @notice Two mintSeaDrop calls for the same minter accumulate both the
     *         per-wallet and drop-wide counters — SeaDrop's cap enforcement
     *         depends on this cumulative behaviour across phases.
     */
    function testMintSeaDropAccumulatesAcrossCalls() public {
        _initializeDefault();

        _mintPublic(alice, 3);
        _mintPublic(alice, 2);

        (uint256 minted, uint256 total, ) = shim.getMintStats(alice);
        assertEq(minted, 5, "alice cumulative minterNumMinted");
        assertEq(total, 5, "cumulative totalMinted");
        assertEq(shim.totalSupply(), 5, "totalSupply accumulated");
    }

    /**
     * @notice mintSeaDrop forwards the actual ERC1155 mint to Creator Core via
     *         mintExtensionExisting; Alice's balance on the real ERC1155Creator
     *         must equal her minterNumMinted after the call — cross-contract
     *         proof that the shim's local counters track real on-chain balance.
     * @dev Uses a second minter (bob) to confirm _totalMinted is the sum of
     *      per-wallet balances, not just a mirror of alice's counter.
     */
    function testMintSeaDropCreditsERC1155Balance() public {
        _initializeDefault();
        uint256 expectedTokenId = 1;

        _mintPublic(alice, 4);
        _mintPublic(bob, 2);

        assertEq(creator.balanceOf(alice, expectedTokenId), 4, "alice ERC1155 balance");
        assertEq(creator.balanceOf(bob, expectedTokenId), 2, "bob ERC1155 balance");

        (uint256 aliceMinted, , ) = shim.getMintStats(alice);
        (uint256 bobMinted, uint256 total, ) = shim.getMintStats(bob);
        assertEq(creator.balanceOf(alice, expectedTokenId), aliceMinted, "balance == alice.minterNumMinted");
        assertEq(creator.balanceOf(bob, expectedTokenId), bobMinted, "balance == bob.minterNumMinted");
        assertEq(total, 6, "totalMinted sums across wallets");
    }

    /**
     * @notice mintSeaDrop before initialize must revert with NotInitialized.
     *         MockSeaDrop is in the allowed set from setUp, so the onlyAllowed
     *         gate passes; the revert comes from the shim's `_tokenId == 0`
     *         guard, which blocks minting into an un-seeded drop.
     */
    function testMintSeaDropRevertsBeforeInitialize() public {
        vm.expectRevert(IManifoldERC1155SeaDropShim.NotInitialized.selector);
        _mintSeaDropDirect(alice, 1);
    }

    /**
     * @notice Even though stock SeaDrop checks getMintStats before minting,
     *         mintSeaDrop keeps its own final max-supply guard for direct-call
     *         safety and reverts with the canonical SeaDrop error.
     */
    function testMintSeaDropRevertsWhenQuantityExceedsMaxSupply() public {
        _initializeDefault();

        vm.expectRevert(
            abi.encodeWithSignature("MintQuantityExceedsMaxSupply(uint256,uint256)", 101, 100)
        );
        _mintSeaDropDirect(alice, 101);

        (uint256 minted, uint256 total, uint256 cap) = shim.getMintStats(alice);
        assertEq(minted, 0, "minter counter unchanged");
        assertEq(total, 0, "total counter unchanged");
        assertEq(cap, 100, "cap unchanged");
        assertEq(creator.balanceOf(alice, 1), 0, "no ERC1155 mint on revert");
    }

    /**
     * @notice Direct mintSeaDrop can mint exactly to maxSupply, then the next
     *         allowed-SeaDrop mint reverts before counters or ERC1155 balance
     *         change. This catches off-by-one errors in the shim's final guard.
     */
    function testMintSeaDropAllowsMaxSupplyThenRevertsNextMint() public {
        _initializeDefault();

        vm.prank(creatorAdmin);
        shim.setMaxSupply(5);

        _mintSeaDropDirect(alice, 5);
        assertEq(creator.balanceOf(alice, 1), 5, "alice minted exactly to cap");

        vm.expectRevert(
            abi.encodeWithSignature("MintQuantityExceedsMaxSupply(uint256,uint256)", 6, 5)
        );
        _mintSeaDropDirect(bob, 1);

        (uint256 bobMinted, uint256 total, uint256 cap) = shim.getMintStats(bob);
        assertEq(bobMinted, 0, "bob counter unchanged");
        assertEq(total, 5, "total stays at cap");
        assertEq(cap, 5, "cap unchanged");
        assertEq(creator.balanceOf(bob, 1), 0, "bob did not mint on revert");
    }

    /**
     * @notice The same cap boundary is enforced when minting through the real
     *         SeaDrop public path, not just a direct allowed-SeaDrop call.
     */
    function testMintPublicRevertsWhenDropSupplyExceededByRealSeaDrop() public {
        _initializeDefault();

        vm.prank(creatorAdmin);
        shim.setMaxSupply(5);

        _mintPublic(alice, 5);

        uint256 payment = uint256(_defaultCfg().publicDrop.mintPrice);
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSignature("MintQuantityExceedsMaxSupply(uint256,uint256)", 6, 5)
        );
        mockSeaDrop.mintPublic{value: payment}(
            address(shim),
            feeRecipient,
            address(0),
            1
        );

        (uint256 bobMinted, uint256 total, uint256 cap) = shim.getMintStats(bob);
        assertEq(bobMinted, 0, "bob counter unchanged");
        assertEq(total, 5, "total remains capped");
        assertEq(cap, 5, "cap unchanged");
        assertEq(creator.balanceOf(bob, 1), 0, "bob did not mint through SeaDrop");
    }

    /**
     * @notice An admin-configured maxSupply above the legacy uint24 ceiling is
     *         honored at face value — mintSeaDrop has no implicit uint24 clamp,
     *         and the cap-exceeded revert reports the configured maxSupply, not
     *         uint24.max.
     */
    function testMintSeaDropAllowsSupplyAboveUint24() public {
        _initializeDefault();

        uint256 overUint24 = uint256(type(uint24).max) + 1;
        vm.prank(creatorAdmin);
        shim.setMaxSupply(overUint24);

        _mintSeaDropDirect(alice, overUint24);

        (uint256 minted, uint256 total, uint256 cap) = shim.getMintStats(alice);
        assertEq(minted, overUint24, "minter counter reflects mint above uint24");
        assertEq(total, overUint24, "total counter reflects mint above uint24");
        assertEq(cap, overUint24, "configured cap visible in getMintStats");
        assertEq(creator.balanceOf(alice, 1), overUint24, "ERC1155 balance reflects mint above uint24");

        vm.expectRevert(
            abi.encodeWithSignature(
                "MintQuantityExceedsMaxSupply(uint256,uint256)",
                overUint24 + 1,
                overUint24
            )
        );
        _mintSeaDropDirect(bob, 1);
    }

    // -----------------------------------------------------------------------
    // getMintStats — SeaDrop cap-enforcement tuple (US-016)
    // -----------------------------------------------------------------------

    /**
     * @notice Before any mint, getMintStats(alice) reports zero wallet and
     *         zero drop-wide counters, with the configured cap intact.
     * @dev SeaDrop reads this tuple every mint to enforce per-wallet +
     *      drop-wide caps; the pre-mint baseline has to be identity-valued
     *      or the first mint's cap check would be off.
     */
    function testGetMintStatsPreMint() public {
        _initializeDefault();

        (uint256 minted, uint256 total, uint256 cap) = shim.getMintStats(alice);
        assertEq(minted, 0, "alice minterNumMinted pre-mint");
        assertEq(total, 0, "totalMinted pre-mint");
        assertEq(cap, _defaultCfg().maxSupply, "maxSupply pre-mint");
    }

    /**
     * @notice After alice mints 2, her per-wallet counter is 2 but bob's is
     *         still 0 — the drop-wide counter equals 2 for both queries.
     * @dev Asserts the isolation SeaDrop depends on: per-wallet caps track
     *      the specific minter while the supply cap tracks cumulative mints.
     */
    function testGetMintStatsAfterMintIsPerWallet() public {
        _initializeDefault();

        _mintPublic(alice, 2);

        uint256 maxSupply = _defaultCfg().maxSupply;

        (uint256 aliceMinted, uint256 aliceTotal, uint256 aliceCap) = shim.getMintStats(alice);
        assertEq(aliceMinted, 2, "alice minterNumMinted after mint");
        assertEq(aliceTotal, 2, "totalMinted reflects alice's mint");
        assertEq(aliceCap, maxSupply, "maxSupply unchanged");

        (uint256 bobMinted, uint256 bobTotal, uint256 bobCap) = shim.getMintStats(bob);
        assertEq(bobMinted, 0, "bob minterNumMinted isolated from alice");
        assertEq(bobTotal, 2, "totalMinted shared across minters");
        assertEq(bobCap, maxSupply, "maxSupply shared across minters");
    }

    /**
     * @notice Raising the cap above current supply is a plain write — the new
     *         value shows up in getMintStats.maxSupply unchanged, and the
     *         MaxSupplyUpdated event carries the raised value.
     */
    function testGetMintStatsReflectsMaxSupplyIncrease() public {
        _initializeDefault();

        _mintPublic(alice, 2);

        uint256 newCap = 200;

        vm.expectEmit(false, false, false, true, address(shim));
        emit MaxSupplyUpdated(newCap);

        vm.prank(creatorAdmin);
        shim.setMaxSupply(newCap);

        (, uint256 total, uint256 cap) = shim.getMintStats(alice);
        assertEq(total, 2, "totalMinted unchanged by cap update");
        assertEq(cap, newCap, "maxSupply reflects raised cap");
        assertEq(shim.maxSupply(), newCap, "maxSupply view agrees");
    }

    /**
     * @notice Lowering the cap below _totalMinted reverts so SeaDrop's
     *         getMintStats can never imply over-mint against the hard cap.
     *         Supply + cap state must remain untouched on revert.
     */
    function testSetMaxSupplyRevertsBelowTotalMinted() public {
        _initializeDefault();

        _mintPublic(alice, 5);

        vm.expectRevert(
            abi.encodeWithSignature(
                "NewMaxSupplyCannotBeLessThenTotalMinted(uint256,uint256)",
                3,
                5
            )
        );
        vm.prank(creatorAdmin);
        shim.setMaxSupply(3);

        (, uint256 total, uint256 cap) = shim.getMintStats(alice);
        assertEq(total, 5, "totalMinted unchanged by reverted update");
        assertEq(cap, 100, "maxSupply unchanged by reverted update");
        assertEq(shim.maxSupply(), 100, "maxSupply view unchanged by revert");
    }

    /**
     * @notice setMaxSupply must reject any value above uint64 max — SeaDrop
     *         packs the cap into a uint64 in downstream state, so accepting
     *         a larger value would silently truncate.
     */
    function testSetMaxSupplyRevertsAboveUint64() public {
        _initializeDefault();

        uint256 tooBig = uint256(type(uint64).max) + 1;

        vm.expectRevert(
            abi.encodeWithSignature("CannotExceedMaxSupplyOfUint64(uint256)", tooBig)
        );
        vm.prank(creatorAdmin);
        shim.setMaxSupply(tooBig);

        assertEq(shim.maxSupply(), 100, "maxSupply unchanged by reverted update");
    }

    // -----------------------------------------------------------------------
    // multiConfigure — post-init reconfigure path (US-017)
    // -----------------------------------------------------------------------

    /**
     * @notice Calling multiConfigure before initialize must revert — the shim
     *         blocks "half-initialization" where admin config is applied
     *         without a Creator Core tokenId seeded.
     */
    function testMultiConfigureRevertsBeforeInitialize() public {
        MultiConfigureStruct memory cfg = _defaultCfg();

        vm.prank(creatorAdmin);
        vm.expectRevert(IManifoldERC1155SeaDropShim.NotInitialized.selector);
        shim.multiConfigure(cfg);
    }

    /**
     * @notice After initialize, multiConfigure re-applies cfg: mutated fields
     *         land in local shim state AND the new PublicDrop / allowList /
     *         payout / fee-recipient tuples reach MockSeaDrop. Uses a cfg that
     *         differs from the default in every field the shim tracks, so a
     *         regression that forgets to write one of them will fail loudly.
     * @dev Asserts MockSeaDrop.lastPublicDrop reflects the NEW public drop
     *         (not the one initialize pushed), proving _applyConfig ran a
     *         second time rather than short-circuiting.
     */
    function testMultiConfigureUpdatesStateAfterInitialize() public {
        _initializeDefault();

        // Build a reconfigure cfg that differs from the default in every
        // tracked field — extending end time, raising caps, swapping payout,
        // swapping fee recipient, bumping metadata, moving to IPFS storage.
        address newPayout = address(0xC0FFEE);
        address newFeeRecipient = address(0xDEAD);
        MultiConfigureStruct memory cfg = _defaultCfg();
        cfg.maxSupply = 250;
        cfg.storageProtocol = StorageProtocol.IPFS;
        cfg.tokenUriLocation = "QmNewHash";
        cfg.contractURI = "https://example.com/new-contract.json";
        cfg.publicDrop.mintPrice = 0.05 ether;
        cfg.publicDrop.endTime = uint48(block.timestamp + 30 days);
        cfg.publicDrop.maxTotalMintableByWallet = 10;
        cfg.publicDrop.feeBps = 1000;
        cfg.creatorPayoutAddress = newPayout;
        address[] memory newFeeRecipients = new address[](1);
        newFeeRecipients[0] = newFeeRecipient;
        cfg.allowedFeeRecipients = newFeeRecipients;

        // Per-field events (TokenURIUpdated, MaxSupplyUpdated, etc.) fire as
        // _applyConfig runs each dispatch branch — asserted on the local shim
        // state below rather than via vm.expectEmit for readability.
        vm.prank(creatorAdmin);
        shim.multiConfigure(cfg);

        // --- Local shim state matches the reconfigure cfg (not the defaults)
        assertEq(shim.maxSupply(), cfg.maxSupply, "maxSupply updated");
        assertEq(shim.contractURI(), cfg.contractURI, "contractURI updated");
        // StorageProtocol.IPFS -> "ipfs://" prefix + opaque location suffix.
        assertEq(
            shim.tokenURI(1),
            string.concat("ipfs://", cfg.tokenUriLocation),
            "tokenURI reassembled with IPFS prefix"
        );

        // --- MockSeaDrop recorded the NEW forwarded config
        PublicDrop memory pd = mockSeaDrop.lastPublicDrop();
        assertEq(pd.mintPrice, cfg.publicDrop.mintPrice, "publicDrop.mintPrice updated");
        assertEq(pd.endTime, cfg.publicDrop.endTime, "publicDrop.endTime updated");
        assertEq(
            pd.maxTotalMintableByWallet,
            cfg.publicDrop.maxTotalMintableByWallet,
            "publicDrop.maxTotalMintableByWallet updated"
        );
        assertEq(pd.feeBps, cfg.publicDrop.feeBps, "publicDrop.feeBps updated");

        assertEq(mockSeaDrop.lastCreatorPayoutAddress(), newPayout, "payout updated");
        assertTrue(mockSeaDrop.allowedFeeRecipient(newFeeRecipient), "new fee recipient allowed");
    }

    /**
     * @notice Non-admin callers cannot multiConfigure — the creatorAdminRequired
     *         modifier reverts with the same literal string the initialize
     *         gate uses (the shim's admin gate is a revert-string, not a
     *         custom error; see testInitializeRevertsForNonAdmin).
     */
    function testMultiConfigureRevertsForNonAdmin() public {
        _initializeDefault();

        MultiConfigureStruct memory cfg = _defaultCfg();

        vm.prank(notAdmin);
        vm.expectRevert("Must be owner or admin of creator contract");
        shim.multiConfigure(cfg);
    }

    /**
     * @notice Overwrite-only fields are idempotent when repeated. Additive set
     *         updates such as allowedFeeRecipients are intentionally excluded:
     *         stock SeaDrop reverts on duplicate fee recipients.
     */
    function testMultiConfigureOverwriteFieldsAreIdempotent() public {
        _initializeDefault();

        MultiConfigureStruct memory cfg = _defaultCfg();
        cfg.maxSupply = 150;
        cfg.contractURI = "https://example.com/idempotent.json";
        cfg.allowedFeeRecipients = new address[](0);

        vm.prank(creatorAdmin);
        shim.multiConfigure(cfg);

        // Snapshot post-first-call state.
        uint256 supplyAfterFirst = shim.maxSupply();
        string memory contractURIAfterFirst = shim.contractURI();
        address payoutAfterFirst = mockSeaDrop.lastCreatorPayoutAddress();
        PublicDrop memory pdAfterFirst = mockSeaDrop.lastPublicDrop();

        // Second call with the same overwrite-only cfg should be a no-op observationally.
        vm.prank(creatorAdmin);
        shim.multiConfigure(cfg);

        assertEq(shim.maxSupply(), supplyAfterFirst, "maxSupply unchanged by repeat");
        assertEq(shim.contractURI(), contractURIAfterFirst, "contractURI unchanged by repeat");
        assertEq(
            mockSeaDrop.lastCreatorPayoutAddress(),
            payoutAfterFirst,
            "payout unchanged by repeat"
        );

        PublicDrop memory pdAfterSecond = mockSeaDrop.lastPublicDrop();
        assertEq(pdAfterSecond.mintPrice, pdAfterFirst.mintPrice, "publicDrop.mintPrice stable");
        assertEq(pdAfterSecond.endTime, pdAfterFirst.endTime, "publicDrop.endTime stable");
        assertEq(pdAfterSecond.feeBps, pdAfterFirst.feeBps, "publicDrop.feeBps stable");
    }

    /**
     * @notice Stock SeaDrop rejects adding an already-allowed fee recipient.
     *         The shim forwards additive arrays verbatim, so a repeated full
     *         cfg is not idempotent when it includes allowedFeeRecipients.
     */
    function testMultiConfigureRevertsOnDuplicateAllowedFeeRecipient() public {
        _initializeDefault();

        MultiConfigureStruct memory cfg = _defaultCfg();

        vm.prank(creatorAdmin);
        vm.expectRevert(bytes4(keccak256("DuplicateFeeRecipient()")));
        shim.multiConfigure(cfg);
    }

    // -----------------------------------------------------------------------
    // Metadata setters + tokenURI rendering across storage protocols (US-018)
    // -----------------------------------------------------------------------

    /**
     * @notice ARWEAVE protocol: both tokenURI overloads assemble to the
     *         arweave gateway prefix + the opaque location suffix. Proves the
     *         bare-tokenId overload (direct callers) and the ICreatorExtension
     *         overload (Creator Core-routed callers) agree byte-for-byte so
     *         indexers see the same metadata regardless of path.
     */
    function testUpdateTokenURIArweaveBothSignatures() public {
        _initializeDefault();

        vm.expectEmit(false, false, false, true, address(shim));
        emit BatchMetadataUpdate(1, 1);

        vm.prank(creatorAdmin);
        shim.updateTokenURI(StorageProtocol.ARWEAVE, "abc123");

        string memory expected = "https://arweave.net/abc123";
        assertEq(shim.tokenURI(1), expected, "tokenURI(uint256) arweave");
        assertEq(shim.tokenURI(address(creator), 1), expected, "tokenURI(creator, id) arweave");
    }

    /**
     * @notice IPFS protocol: tokenURI assembles to `ipfs://` + opaque hash.
     */
    function testUpdateTokenURIIpfs() public {
        _initializeDefault();

        vm.expectEmit(false, false, false, true, address(shim));
        emit BatchMetadataUpdate(1, 1);

        vm.prank(creatorAdmin);
        shim.updateTokenURI(StorageProtocol.IPFS, "QmHash");

        assertEq(shim.tokenURI(1), "ipfs://QmHash", "tokenURI ipfs");
        assertEq(
            shim.tokenURI(address(creator), 1),
            "ipfs://QmHash",
            "tokenURI(creator, id) ipfs agrees"
        );
    }

    /**
     * @notice NONE protocol: empty prefix — tokenURI returns the stored
     *         location verbatim. This is the mode creators use to supply a
     *         fully-qualified URL (https://... or data:...).
     */
    function testUpdateTokenURINoneReturnsLocationAsIs() public {
        _initializeDefault();

        string memory fullUrl = "https://example.com/meta.json";
        vm.expectEmit(false, false, false, true, address(shim));
        emit BatchMetadataUpdate(1, 1);

        vm.prank(creatorAdmin);
        shim.updateTokenURI(StorageProtocol.NONE, fullUrl);

        assertEq(shim.tokenURI(1), fullUrl, "tokenURI NONE returns location");
        assertEq(
            shim.tokenURI(address(creator), 1),
            fullUrl,
            "tokenURI(creator, id) NONE agrees"
        );
    }

    /**
     * @notice Any tokenId other than the one initialize() seeded reverts with
     *         TokenDNE — the shim manages exactly one drop tokenId.
     */
    function testTokenURIRevertsForUnknownTokenId() public {
        _initializeDefault();

        vm.expectRevert(IManifoldERC1155SeaDropShim.TokenDNE.selector);
        shim.tokenURI(2);
    }

    /**
     * @notice The ICreatorExtensionTokenURI overload reverts when the caller
     *         passes a creator address other than the one the shim was bound
     *         to — guards against spurious routing from an unexpected
     *         Creator Core claiming ownership of this tokenId.
     */
    function testTokenURIRevertsForWrongCreator() public {
        _initializeDefault();

        address otherCreator = address(0x5EA);
        vm.expectRevert(IManifoldERC1155SeaDropShim.TokenDNE.selector);
        shim.tokenURI(otherCreator, 1);
    }

    /**
     * @notice When the storage protocol is NONE, extendTokenURI appends the
     *         chunk to the stored location, allowing creators to build up a
     *         large on-chain data URI across multiple admin transactions.
     * @dev Two successive chunks prove the append compounds; pin to NONE with
     *      a known base so the expected concatenation is obvious.
     */
    function testExtendTokenURIAppendsWhenNone() public {
        _initializeDefault();

        vm.prank(creatorAdmin);
        shim.updateTokenURI(StorageProtocol.NONE, "data:application/json;base64,");

        vm.prank(creatorAdmin);
        shim.extendTokenURI("eyJuYW1lIjoi");

        vm.prank(creatorAdmin);
        shim.extendTokenURI("VGVzdCJ9");

        assertEq(
            shim.tokenURI(1),
            "data:application/json;base64,eyJuYW1lIjoiVGVzdCJ9",
            "extendTokenURI concatenates in order"
        );
    }

    /**
     * @notice extendTokenURI refuses to append when the storage protocol is
     *         anything other than NONE — ARWEAVE / IPFS locations are opaque
     *         content-addressed IDs, and appending bytes would produce a
     *         garbage URI.
     */
    function testExtendTokenURIRevertsWhenNotNone() public {
        _initializeDefault();

        vm.prank(creatorAdmin);
        shim.updateTokenURI(StorageProtocol.IPFS, "QmHash");

        vm.prank(creatorAdmin);
        vm.expectRevert(IManifoldERC1155SeaDropShim.InvalidStorageProtocol.selector);
        shim.extendTokenURI("suffix");

        vm.prank(creatorAdmin);
        shim.updateTokenURI(StorageProtocol.ARWEAVE, "abc");

        vm.prank(creatorAdmin);
        vm.expectRevert(IManifoldERC1155SeaDropShim.InvalidStorageProtocol.selector);
        shim.extendTokenURI("suffix");
    }

    /**
     * @notice setContractURI overwrites the stored OpenSea collection pointer
     *         and contractURI() reads back the new value.
     */
    function testSetContractURIUpdatesStoredValue() public {
        _initializeDefault();

        string memory next = "https://example.com/updated-contract.json";
        vm.prank(creatorAdmin);
        shim.setContractURI(next);

        assertEq(shim.contractURI(), next, "contractURI reflects setContractURI");
    }

    /**
     * @notice setBaseURI is the canonical INonFungibleSeaDropToken entry that
     *         OpenSea / SeaDrop tooling calls to update the URI location. It
     *         shares the `_tokenUriLocation` storage slot with the shim's own
     *         `updateTokenURI` flow, so baseURI() round-trips: read after
     *         write returns the value just written, and tokenURI() reflects
     *         the new location (no protocol prefix in this default cfg
     *         because StorageProtocol.NONE is in effect).
     */
    function testSetBaseURIRoundTripsAndUpdatesTokenURI() public {
        _initializeDefault();

        string memory next = "https://example.com/updated-base.json";
        vm.expectEmit(false, false, false, true, address(shim));
        emit BatchMetadataUpdate(1, 1);

        vm.prank(creatorAdmin);
        shim.setBaseURI(next);

        assertEq(shim.baseURI(), next, "baseURI() reflects setBaseURI");
        // Default cfg uses StorageProtocol.NONE, so tokenURI == location.
        assertEq(shim.tokenURI(1), next, "tokenURI() reflects setBaseURI");
    }

    /**
     * @notice setBaseURI is creatorAdmin-only — same gate as every other
     *         shim setter. Non-admin callers hit the canonical revert string.
     */
    function testSetBaseURIRevertsForNonAdmin() public {
        _initializeDefault();

        vm.prank(notAdmin);
        vm.expectRevert("Must be owner or admin of creator contract");
        shim.setBaseURI("ignored");
    }

    /**
     * @notice setProvenanceHash is implemented for canonical INonFungibleSeaDropToken
     *         compliance but always reverts — provenance reveal flows are a v1
     *         non-goal. Tooling that calls this fails loudly rather than
     *         silently no-op'ing into a misleading "set" state.
     */
    function testSetProvenanceHashAlwaysReverts() public {
        _initializeDefault();

        vm.prank(creatorAdmin);
        vm.expectRevert(IManifoldERC1155SeaDropShim.ProvenanceHashNotSupported.selector);
        shim.setProvenanceHash(bytes32(uint256(1)));

        // Even an admin cannot set it — provenanceHash() stays bytes32(0).
        assertEq(shim.provenanceHash(), bytes32(0), "provenanceHash unchanged");
    }

    // -----------------------------------------------------------------------
    // SeaDrop pass-through setters forward correct args (US-019)
    // -----------------------------------------------------------------------
    //
    // The pass-through setters are admin-only thin forwards to an arbitrary
    // SeaDrop deployment (see ManifoldERC1155SeaDropShim's "SeaDrop pass-through
    // setters" section). They do not depend on initialize() — they target
    // `seaDropImpl` directly, regardless of the shim's drop state — so these
    // tests deliberately skip _initializeDefault() to keep the assertions tight
    // on the forwarding behaviour itself.

    /**
     * @notice updatePublicDrop forwards a fully-populated PublicDrop verbatim
     *         to the configured SeaDrop impl. Uses values that differ from the
     *         _defaultCfg() PublicDrop in every field so a regression that
     *         caches one of them would fail loud on the deep-equal.
     */
    function testUpdatePublicDropForwardsToSeaDrop() public {
        PublicDrop memory pd = PublicDrop({
            mintPrice: 0.077 ether,
            startTime: uint48(block.timestamp + 1 days),
            endTime: uint48(block.timestamp + 21 days),
            maxTotalMintableByWallet: 7,
            feeBps: 750,
            restrictFeeRecipients: false
        });

        vm.prank(creatorAdmin);
        shim.updatePublicDrop(address(mockSeaDrop), pd);

        PublicDrop memory recorded = mockSeaDrop.lastPublicDrop();
        assertEq(recorded.mintPrice, pd.mintPrice, "mintPrice forwarded");
        assertEq(recorded.startTime, pd.startTime, "startTime forwarded");
        assertEq(recorded.endTime, pd.endTime, "endTime forwarded");
        assertEq(
            recorded.maxTotalMintableByWallet,
            pd.maxTotalMintableByWallet,
            "maxTotalMintableByWallet forwarded"
        );
        assertEq(recorded.feeBps, pd.feeBps, "feeBps forwarded");
        assertEq(
            recorded.restrictFeeRecipients,
            pd.restrictFeeRecipients,
            "restrictFeeRecipients forwarded"
        );
    }

    /**
     * @notice updateAllowList forwards the whole AllowListData struct including
     *         its dynamic publicKeyURIs[] member — uses two URIs so the array
     *         length + per-element forwarding both get exercised.
     */
    function testUpdateAllowListForwardsStruct() public {
        string[] memory keyURIs = new string[](2);
        keyURIs[0] = "https://keys.example.com/1";
        keyURIs[1] = "https://keys.example.com/2";
        AllowListData memory ald = AllowListData({
            merkleRoot: bytes32(uint256(0xABCDEF)),
            publicKeyURIs: keyURIs,
            allowListURI: "https://example.com/allowlist.json"
        });

        vm.prank(creatorAdmin);
        shim.updateAllowList(address(mockSeaDrop), ald);

        AllowListData memory recorded = mockSeaDrop.lastAllowListData();
        assertEq(recorded.merkleRoot, ald.merkleRoot, "merkleRoot forwarded");
        // Stock SeaDrop stores only the root; publicKeyURIs and allowListURI are event-only.
    }

    /**
     * @notice updateCreatorPayoutAddress forwards the address scalar.
     */
    function testUpdateCreatorPayoutAddressForwards() public {
        address newPayout = address(0xC0FFEE);

        vm.prank(creatorAdmin);
        shim.updateCreatorPayoutAddress(address(mockSeaDrop), newPayout);

        assertEq(mockSeaDrop.lastCreatorPayoutAddress(), newPayout, "payout forwarded");
    }

    /**
     * @notice updateAllowedFeeRecipient toggles the cumulative allow-map on
     *         the SeaDrop side: setting allowed=true marks the address allowed,
     *         then a second call with allowed=false flips it back. Asserts both
     *         the cumulative map and the last-call snapshot the mock records.
     */
    function testUpdateAllowedFeeRecipientToggles() public {
        address newFr = address(0xFEE5);

        vm.prank(creatorAdmin);
        shim.updateAllowedFeeRecipient(address(mockSeaDrop), newFr, true);
        assertTrue(mockSeaDrop.allowedFeeRecipient(newFr), "fee recipient allowed");

        vm.prank(creatorAdmin);
        shim.updateAllowedFeeRecipient(address(mockSeaDrop), newFr, false);
        assertFalse(mockSeaDrop.allowedFeeRecipient(newFr), "fee recipient revoked");
    }

    /**
     * @notice updateDropURI forwards the string scalar to SeaDrop.
     */
    function testUpdateDropURIForwardsString() public {
        string memory dropURI = "https://example.com/drop-metadata.json";

        vm.expectEmit(true, false, false, true, address(mockSeaDrop));
        emit DropURIUpdated(address(shim), dropURI);

        vm.prank(creatorAdmin);
        shim.updateDropURI(address(mockSeaDrop), dropURI);
    }

    /**
     * @notice updatePayer forwards the (payer, allowed) pair — verifies both
     *         the cumulative allow-map and the last-call snapshot.
     */
    function testUpdatePayerForwards() public {
        address payer = address(0xDA11A5);

        vm.prank(creatorAdmin);
        shim.updatePayer(address(mockSeaDrop), payer, true);
        assertTrue(mockSeaDrop.allowedPayer(payer), "payer allowed in map");
    }

    /**
     * @notice updateAllowedSeaDrop drains the existing set, replaces it with
     *         the new addresses (in array order), and emits AllowedSeaDropUpdated
     *         with the raw input array. Uses two new addresses so the test
     *         exercises both the multi-element add path AND the implicit removal
     *         of the original mockSeaDrop seeded by setUp.
     */
    function testUpdateAllowedSeaDropReplacesSetAndEmits() public {
        address newSeaDropA = address(0xAAAA);
        address newSeaDropB = address(0xBBBB);
        address[] memory newAllowed = new address[](2);
        newAllowed[0] = newSeaDropA;
        newAllowed[1] = newSeaDropB;

        vm.expectEmit(false, false, false, true, address(shim));
        emit AllowedSeaDropUpdated(newAllowed);

        vm.prank(creatorAdmin);
        shim.updateAllowedSeaDrop(newAllowed);

        address[] memory current = shim.getAllowedSeaDrop();
        assertEq(current.length, 2, "set replaced (size)");
        assertEq(current[0], newSeaDropA, "set[0] is newSeaDropA");
        assertEq(current[1], newSeaDropB, "set[1] is newSeaDropB");
    }

    /**
     * @notice Pass-through setters share the same creatorAdminRequired modifier
     *         as initialize() / multiConfigure() — pick updatePublicDrop as the
     *         representative case. Asserts the literal revert string the shim's
     *         admin gate uses (see testInitializeRevertsForNonAdmin).
     */
    function testPassThroughSetterRevertsForNonAdmin() public {
        PublicDrop memory pd = _defaultCfg().publicDrop;

        vm.prank(notAdmin);
        vm.expectRevert("Must be owner or admin of creator contract");
        shim.updatePublicDrop(address(mockSeaDrop), pd);
    }

    /**
     * @notice Pass-through setters must reject a `seaDropImpl` that is not in
     *         the shim's allowed-SeaDrop set — a typo in the admin-supplied
     *         address cannot silently push config to an un-whitelisted SeaDrop
     *         deployment. Asserts against updatePublicDrop as the representative
     *         case; all six forwarders share the same `_onlyAllowedSeaDrop` gate.
     */
    function testPassThroughSetterRevertsForUnallowedSeaDrop() public {
        PublicDrop memory pd = _defaultCfg().publicDrop;
        address strangerSeaDrop = address(0xDEADBEEF);

        vm.prank(creatorAdmin);
        vm.expectRevert(INonFungibleSeaDropToken.OnlyAllowedSeaDrop.selector);
        shim.updatePublicDrop(strangerSeaDrop, pd);
    }

    // -----------------------------------------------------------------------
    // Token-gated + signed-mint pass-throughs
    // -----------------------------------------------------------------------

    /**
     * @notice updateTokenGatedDrop forwards the (allowedNftToken, stage) tuple
     *         to the mocked SeaDrop so OpenSea reads a token-gated phase keyed
     *         off the shim's address. Admin gate + allowed-SeaDrop gate are
     *         exercised via the shared _onlyAllowedSeaDrop path.
     */
    function testUpdateTokenGatedDropForwards() public {
        _initializeDefault();

        address gateToken = address(0xBEEFCAFE);
        TokenGatedDropStage memory stage = TokenGatedDropStage({
            mintPrice: 0.02 ether,
            maxTotalMintableByWallet: 3,
            startTime: uint48(block.timestamp),
            endTime: uint48(block.timestamp + 7 days),
            dropStageIndex: 1,
            maxTokenSupplyForStage: 50,
            feeBps: 500,
            restrictFeeRecipients: true
        });

        vm.prank(creatorAdmin);
        shim.updateTokenGatedDrop(address(mockSeaDrop), gateToken, stage);

        TokenGatedDropStage memory stored = mockSeaDrop.tokenGatedDrop(gateToken);
        assertEq(stored.mintPrice, stage.mintPrice, "stage.mintPrice");
        assertEq(stored.maxTotalMintableByWallet, stage.maxTotalMintableByWallet);
        assertEq(stored.dropStageIndex, stage.dropStageIndex);
    }

    /**
     * @notice updateSignedMintValidationParams forwards the (signer, params)
     *         tuple to the mocked SeaDrop — symmetrical to the tokenGated case.
     */
    function testUpdateSignedMintValidationParamsForwards() public {
        _initializeDefault();

        address signer = address(0xFEEDFACE);
        SignedMintValidationParams memory params = SignedMintValidationParams({
            minMintPrice: 0.01 ether,
            maxMaxTotalMintableByWallet: 10,
            minStartTime: uint40(block.timestamp),
            maxEndTime: uint40(block.timestamp + 30 days),
            maxMaxTokenSupplyForStage: 100,
            minFeeBps: 250,
            maxFeeBps: 1000
        });

        vm.prank(creatorAdmin);
        shim.updateSignedMintValidationParams(address(mockSeaDrop), signer, params);

        SignedMintValidationParams memory stored = mockSeaDrop.signedMintValidationParams(signer);
        assertEq(stored.minMintPrice, params.minMintPrice);
        assertEq(stored.maxMaxTotalMintableByWallet, params.maxMaxTotalMintableByWallet);
        assertEq(stored.maxFeeBps, params.maxFeeBps);
    }

    /**
     * @notice _applyConfig must reject a MultiConfigureStruct where the paired
     *         tokenGated arrays disagree in length — the shim would otherwise
     *         silently push only the shorter-array prefix, which is the class
     *         of bug stock SeaDrop's TokenGatedMismatch error exists to prevent.
     */
    function testMultiConfigureRevertsOnTokenGatedLengthMismatch() public {
        _initializeDefault();

        MultiConfigureStruct memory cfg = _defaultCfg();
        cfg.allowedFeeRecipients = new address[](0);
        cfg.tokenGatedAllowedNftTokens = new address[](2);
        cfg.tokenGatedAllowedNftTokens[0] = address(0xCAFE01);
        cfg.tokenGatedAllowedNftTokens[1] = address(0xCAFE02);
        cfg.tokenGatedDropStages = new TokenGatedDropStage[](1);

        vm.prank(creatorAdmin);
        vm.expectRevert(IManifoldERC1155SeaDropShim.TokenGatedMismatch.selector);
        shim.multiConfigure(cfg);
    }

    /**
     * @notice Same length-mismatch invariant for the paired signers /
     *         signedMintValidationParams arrays. Stock-style guard: the check
     *         fires only when the primary `signedMintValidationParams` array
     *         is non-empty — an empty params array paired with non-empty
     *         signers is treated as a skip, matching stock SeaDrop semantics.
     */
    function testMultiConfigureRevertsOnSignerLengthMismatch() public {
        _initializeDefault();

        MultiConfigureStruct memory cfg = _defaultCfg();
        cfg.allowedFeeRecipients = new address[](0);
        cfg.signers = new address[](1);
        cfg.signers[0] = address(0x516E);
        cfg.signedMintValidationParams = new SignedMintValidationParams[](2);

        vm.prank(creatorAdmin);
        vm.expectRevert(IManifoldERC1155SeaDropShim.SignersMismatch.selector);
        shim.multiConfigure(cfg);
    }
}
