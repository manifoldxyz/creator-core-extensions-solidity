// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {ERC1155Creator} from "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";

import {CXRDSPacks} from "../../contracts/cxrds/CXRDSPacks.sol";
import {ICXRDSPacks} from "../../contracts/cxrds/ICXRDSPacks.sol";

import {MockSeaDropCaller} from "./mocks/MockSeaDropCaller.sol";

/**
 * @title  CXRDSTestBase
 * @notice Shared Foundry harness for the CXRDS pack contract test suite
 *         (US-005..US-012 / US-014 inherit this). Deploys a stock ERC1155Creator
 *         as the "cards" core, deploys CXRDSPacks wired to it, registers the
 *         extension (a cards-core admin action) BEFORE initializeCards, sets the
 *         backend signer and ripStart, and exposes: three test wallets, a mock
 *         allowed-SeaDrop caller, a frozen-sheet fixture of 10 packs -> uint256[4]
 *         card ids, and an EIP-712 RipPermit signing helper that reproduces the
 *         exact digest CXRDSPacks verifies via `_hashTypedDataV4`.
 *
 * @dev    Error taxonomy children exercise (pinned by the contract):
 *           - InvalidSignature: ONLY ecrecover -> address(0) (malformed v/r/s).
 *           - PermitSignerNotOwner: well-formed sig recovering to a non-owner,
 *             a forged sig, or a stale sig after transfer.
 *           - OwnerQueryForNonexistentToken (ERC721A): burned/nonexistent pack
 *             (the replay lock — no nonces).
 *           - CardsAlreadyInitialized: double initializeCards().
 */
contract CXRDSTestBase is Test {
    // ---------------------------------------------------------------------
    // Wallets. All three carry known private keys (via vm.addr) so children
    // can sign RipPermits as the pack owner — the rip mechanic requires the
    // recovered permit signer to equal ownerOf(packId), so the pack HOLDER
    // must be able to sign. See ASSUMPTIONS.md entry for why all three are keyed.
    // ---------------------------------------------------------------------

    /// @notice Owner / partner-stand-in: cards-core admin AND the CXRDSPacks
    ///         owner. Holds the frozen-sheet fixture packs.
    uint256 internal constant OWNER_PK = 0xA11CE;
    address internal owner;

    /// @notice Zero-balance collector: holds no packs at setUp; used for
    ///         negative-path and card-receipt assertions.
    uint256 internal constant COLLECTOR_PK = 0xC0FFEE;
    address internal collector;

    /// @notice Backend signer authorized to call `deliverBatch`.
    uint256 internal constant SIGNER_PK = 0xBEEF;
    address internal signerAddr;

    // ---------------------------------------------------------------------
    // Deployed system under test.
    // ---------------------------------------------------------------------

    /// @notice Stock ERC1155 creator-core "cards" contract.
    ERC1155Creator internal creator;

    /// @notice The pack collection under test.
    CXRDSPacks internal cxrds;

    /// @notice Mock allowed-SeaDrop caller wired into `allowedSeaDrop_`.
    MockSeaDropCaller internal seaDropCaller;

    // ---------------------------------------------------------------------
    // Fixture.
    // ---------------------------------------------------------------------

    /// @notice Number of packs pre-minted to `owner` in the frozen fixture.
    uint256 internal constant FIXTURE_PACK_COUNT = 10;

    /// @notice The first reserved card variation id on the cards core
    ///         (== cxrds.startingCardTokenId() after initializeCards).
    uint256 internal startingCardTokenId;

    /// @notice packId => the four valid card ids to mint when that pack is
    ///         ripped. All ids are inside [startingCardTokenId,
    ///         startingCardTokenId + NUM_CARD_DESIGNS).
    mapping(uint256 => uint256[4]) internal fixtureCards;

    function setUp() public virtual {
        owner = vm.addr(OWNER_PK);
        collector = vm.addr(COLLECTOR_PK);
        signerAddr = vm.addr(SIGNER_PK);

        vm.warp(1_000_000);

        vm.startPrank(owner);

        // Deploy the cards core (owner becomes its admin).
        creator = new ERC1155Creator("CXRDS Cards", "CXRDS");

        // Deploy the mock SeaDrop caller and wire it as an allowed SeaDrop.
        seaDropCaller = new MockSeaDropCaller();
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = address(seaDropCaller);

        // Deploy the pack collection. Constructor sets owner to msg.sender then
        // transfers to initialOwner (owner here).
        cxrds = new CXRDSPacks(
            "CXRDS Packs",
            "PACK",
            allowedSeaDrop,
            address(creator),
            owner
        );

        // Order matters: registerExtension (a cards-core ADMIN action) THEN
        // initializeCards on the pack contract.
        creator.registerExtension(address(cxrds), "");
        cxrds.initializeCards();

        // Configure the backend signer and open the rip phase now.
        cxrds.setSigner(signerAddr);
        cxrds.setRipStart(block.timestamp);

        // Allow SeaDrop minting: cap supply and mint the fixture packs to owner.
        cxrds.setMaxSupply(cxrds.MAX_PACKS());

        vm.stopPrank();

        // Mint FIXTURE_PACK_COUNT packs to owner via the allowed SeaDrop caller.
        // ERC721A starts token ids at 1, so packs are ids 1..FIXTURE_PACK_COUNT.
        seaDropCaller.mint(address(cxrds), owner, FIXTURE_PACK_COUNT);

        // Record the reserved card range and build the frozen sheet fixture.
        startingCardTokenId = cxrds.startingCardTokenId();
        for (uint256 packId = 1; packId <= FIXTURE_PACK_COUNT; packId++) {
            fixtureCards[packId] = [
                startingCardTokenId,
                startingCardTokenId + 1,
                startingCardTokenId + 2,
                startingCardTokenId + 3
            ];
        }
    }

    // ---------------------------------------------------------------------
    // EIP-712 RipPermit signing helpers.
    // ---------------------------------------------------------------------

    /**
     * @notice The EIP-712 domain separator for the deployed CXRDSPacks, matching
     *         OZ EIP712("CXRDSPacks", "1") exactly.
     */
    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("CXRDSPacks")),
                keccak256(bytes("1")),
                block.chainid,
                address(cxrds)
            )
        );
    }

    /**
     * @notice Reproduce the EXACT digest CXRDSPacks verifies via
     *         `_hashTypedDataV4(keccak256(abi.encode(RIP_TYPEHASH, packId,
     *         deadline)))`. Uses the contract's own RIP_TYPEHASH constant so the
     *         struct hash is byte-for-byte identical.
     */
    function _ripDigest(uint256 packId, uint256 deadline) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(cxrds.RIP_TYPEHASH(), packId, deadline));
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
    }

    /**
     * @notice Sign a RipPermit over (packId, deadline) with an arbitrary private
     *         key. Pass the pack owner's key for a valid permit, another key to
     *         exercise PermitSignerNotOwner.
     */
    function signRipPermit(uint256 privateKey, uint256 packId, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        (v, r, s) = vm.sign(privateKey, _ripDigest(packId, deadline));
    }

    /**
     * @notice Build a fully-populated RipOrder signed by `privateKey`.
     *
     * @param privateKey The key to sign the permit with.
     * @param packId     The pack tokenId to rip.
     * @param cardIds    The four card ids to mint.
     * @param deadline   The permit deadline.
     */
    function buildRipOrder(
        uint256 privateKey,
        uint256 packId,
        uint256[4] memory cardIds,
        uint256 deadline
    ) internal view returns (ICXRDSPacks.RipOrder memory order) {
        (uint8 v, bytes32 r, bytes32 s) = signRipPermit(privateKey, packId, deadline);
        order = ICXRDSPacks.RipOrder({
            packId: packId,
            cardIds: cardIds,
            deadline: deadline,
            v: v,
            r: r,
            s: s
        });
    }

    /**
     * @notice Convenience: build a valid RipOrder for a fixture pack owned by
     *         `owner`, signed by `owner`, with a far-future deadline.
     */
    function buildFixtureRipOrder(uint256 packId)
        internal
        view
        returns (ICXRDSPacks.RipOrder memory)
    {
        return buildRipOrder(OWNER_PK, packId, fixtureCards[packId], block.timestamp + 1 days);
    }

    /// @notice Expose a fixture pack's four card ids to child contracts.
    function cardsForPack(uint256 packId) internal view returns (uint256[4] memory) {
        return fixtureCards[packId];
    }

    // ---------------------------------------------------------------------
    // Sanity test — verifies the harness wiring compiles and initializes.
    // ---------------------------------------------------------------------

    function testHarnessSetup() public {
        assertEq(cxrds.owner(), owner, "cxrds owner");
        assertEq(cxrds.signer(), signerAddr, "backend signer");
        assertEq(cxrds.ripStart(), block.timestamp, "ripStart open");
        assertGt(startingCardTokenId, 0, "cards initialized");
        assertEq(cxrds.ownerOf(1), owner, "fixture pack 1 owned by owner");
        assertEq(cxrds.ownerOf(FIXTURE_PACK_COUNT), owner, "fixture pack N owned by owner");

        // Signing helper recovers to the signing key's address.
        (uint8 v, bytes32 r, bytes32 s) = signRipPermit(OWNER_PK, 1, block.timestamp + 1 days);
        address recovered = ecrecover(_ripDigest(1, block.timestamp + 1 days), v, r, s);
        assertEq(recovered, owner, "permit recovers to signer");
    }
}
