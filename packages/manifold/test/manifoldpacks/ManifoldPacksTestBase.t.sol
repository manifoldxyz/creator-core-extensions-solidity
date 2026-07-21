// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {ERC1155Creator} from "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";

import {ManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol";
import {IManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol";

import {MockSeaDropCaller} from "./mocks/MockSeaDropCaller.sol";

import {Merkle} from "../../lib/murky/src/Merkle.sol";

/**
 * @title  ManifoldPacksTestBase
 * @notice Shared Foundry harness for the ManifoldPacksSeaDropShim pack contract test suite.
 *         Deploys a stock ERC1155Creator as the "cards" core, deploys
 *         ManifoldPacksSeaDropShim wired to it, registers the extension (a cards-core admin
 *         action) BEFORE initializeCards, initializes the card `PackConfig`
 *         (251 variations, 4 cards/pack, rip open now, no end, no cap), sets the
 *         backend signer, and exposes: three test wallets, a mock allowed-
 *         SeaDrop caller, a frozen-sheet fixture of 10 packs -> uint256[4] card
 *         ids, and EIP-712 RipPermit signing helpers that reproduce the exact
 *         digest ManifoldPacksSeaDropShim verifies via `_hashTypedDataV4` and pack the
 *         signature as `bytes` (abi.encodePacked(r, s, v)) for
 *         `SignatureChecker`.
 *
 * @dev    Error taxonomy children exercise (pinned by the contract):
 *           - InvalidPermit: SignatureChecker rejects the permit against the
 *             current owner (malformed, forged, non-owner, or stale-after-
 *             transfer — all collapse to one error now).
 *           - InvalidCardAmounts: mismatched/empty cardIds+amounts or
 *             sum(amounts) != cardsPerPack.
 *           - InvalidCardIds: a card id outside the reserved variation range.
 *           - OwnerQueryForNonexistentToken (ERC721A): burned/nonexistent pack
 *             (the replay lock — no nonces).
 *           - CardsAlreadyInitialized: double initializeCards().
 */
contract ManifoldPacksTestBase is Test {
    // ---------------------------------------------------------------------
    // Wallets. All three carry known private keys (via vm.addr) so children
    // can sign RipPermits as the pack owner — the rip mechanic verifies the
    // permit against ownerOf(packId), so the pack HOLDER must be able to sign.
    // ---------------------------------------------------------------------

    /// @notice Owner / partner-stand-in: cards-core admin AND the ManifoldPacksSeaDropShim
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
    // Card config constants (mirror the production defaults).
    // ---------------------------------------------------------------------

    /// @notice Number of contiguous card variation ids reserved on init.
    uint256 internal constant NUM_CARD_DESIGNS = 251;

    /// @notice Number of card units a single pack yields when ripped.
    uint256 internal constant CARDS_PER_PACK = 4;

    // ---------------------------------------------------------------------
    // Deployed system under test.
    // ---------------------------------------------------------------------

    /// @notice Stock ERC1155 creator-core "cards" contract.
    ERC1155Creator internal creator;

    /// @notice The pack collection under test.
    ManifoldPacksSeaDropShim internal packs;

    /// @notice Mock allowed-SeaDrop caller wired into `allowedSeaDrop_`.
    MockSeaDropCaller internal seaDropCaller;

    // ---------------------------------------------------------------------
    // Fixture.
    // ---------------------------------------------------------------------

    /// @notice Number of packs pre-minted to `owner` in the frozen fixture.
    uint256 internal constant FIXTURE_PACK_COUNT = 10;

    /// @notice Pack collection size for the drop (SeaDrop max supply). The
    ///         contract no longer exposes this as a constant — it lives in the
    ///         SeaDrop `maxSupply` config — so the harness keeps its own copy.
    uint256 internal constant MAX_PACKS = 3943;

    /// @notice The first reserved card variation id on the cards core
    ///         (== packs.startingCardTokenId() after initializeCards).
    uint256 internal startingCardTokenId;

    /// @notice packId => the four valid card ids to mint when that pack is
    ///         ripped. All ids are inside [startingCardTokenId,
    ///         startingCardTokenId + NUM_CARD_DESIGNS).
    mapping(uint256 => uint256[4]) internal fixtureCards;

    // ---------------------------------------------------------------------
    // Merkle contents-commitment fixture. Each committed pack contributes a
    // leaf keccak256(abi.encode(packId, cardIds, amounts, salt)); the root is
    // seeded on-chain via seedContents. murky's Merkle (ascending-sorted pair
    // hashing) matches OZ MerkleProof.verify's commutative _hashPair exactly, so
    // proofs generated here verify against the contract. Root is owner-mutable
    // any time (deliberate trust choice), so the harness can re-commit custom
    // pack contents mid-test via _commitAndSeed.
    // ---------------------------------------------------------------------

    /// @notice murky tree generator/prover used to build real roots + proofs.
    Merkle internal merkle;

    /// @notice packIds committed into the tree, in insertion order (== leaf order).
    uint256[] internal committedPackIds;

    /// @notice packId => its 1-based index in `committedPackIds` (0 == absent).
    mapping(uint256 => uint256) internal committedIndex;

    /// @notice packId => committed card ids.
    mapping(uint256 => uint256[]) internal committedCardIds;

    /// @notice packId => committed amounts (parallel to committedCardIds).
    mapping(uint256 => uint256[]) internal committedAmounts;

    /// @notice packId => committed per-pack salt.
    mapping(uint256 => bytes32) internal committedSalt;

    function setUp() public virtual {
        owner = vm.addr(OWNER_PK);
        collector = vm.addr(COLLECTOR_PK);
        signerAddr = vm.addr(SIGNER_PK);

        vm.warp(1_000_000);

        vm.startPrank(owner);

        // Deploy the cards core (owner becomes its admin).
        creator = new ERC1155Creator("ManifoldPacksSeaDropShim Cards", "ManifoldPacksSeaDropShim");

        // Deploy the mock SeaDrop caller and wire it as an allowed SeaDrop.
        seaDropCaller = new MockSeaDropCaller();
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = address(seaDropCaller);

        // Deploy the pack collection. Constructor sets owner to msg.sender then
        // transfers to initialOwner (owner here).
        packs = new ManifoldPacksSeaDropShim(
            "ManifoldPacksSeaDropShim Packs",
            "PACK",
            allowedSeaDrop,
            owner
        );

        // Order matters: registerExtension (a cards-core ADMIN action) THEN
        // initializeCards on the pack contract with the cards-core address and
        // the card config.
        creator.registerExtension(address(packs), "");
        packs.initializeCards(address(creator), defaultConfig());

        // Configure the backend signer.
        packs.setSigner(signerAddr);

        // Allow SeaDrop minting: cap supply (mint happens after the root is seeded).
        packs.setMaxSupply(MAX_PACKS);

        vm.stopPrank();

        // Deploy the murky tree generator/prover.
        merkle = new Merkle();

        // Record the reserved card range (available immediately after init) and
        // build + commit the frozen sheet fixture BEFORE minting: each fixture
        // pack commits to its four default cards. The root must exist before any
        // deliverBatch, and the sheet must use the REAL post-init card ids.
        startingCardTokenId = packs.startingCardTokenId();
        for (uint256 packId = 1; packId <= FIXTURE_PACK_COUNT; packId++) {
            fixtureCards[packId] = [
                startingCardTokenId,
                startingCardTokenId + 1,
                startingCardTokenId + 2,
                startingCardTokenId + 3
            ];
            (uint256[] memory ids, uint256[] memory amounts) = _fixtureArrays(fixtureCards[packId]);
            _commit(packId, ids, amounts, _defaultSalt(packId));
        }
        _seed();

        // Mint FIXTURE_PACK_COUNT packs to owner via the allowed SeaDrop caller.
        // ERC721A starts token ids at 1, so packs are ids 1..FIXTURE_PACK_COUNT.
        seaDropCaller.mint(address(packs), owner, FIXTURE_PACK_COUNT);
    }

    // ---------------------------------------------------------------------
    // Merkle commitment helpers.
    // ---------------------------------------------------------------------

    /// @notice Deterministic per-pack salt for the default fixture commitment.
    function _defaultSalt(uint256 packId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("cxrds-salt", packId));
    }

    /// @notice The committed leaf for a pack: keccak256(abi.encode(packId,
    ///         cardIds, amounts, salt)). Single-hashed, matching the contract.
    function _leaf(
        uint256 packId,
        uint256[] memory cardIds,
        uint256[] memory amounts,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(packId, cardIds, amounts, salt));
    }

    /// @notice Record (or overwrite) a pack's committed contents in the harness
    ///         tree bookkeeping. Does NOT touch the chain — call `_seed` after.
    function _commit(
        uint256 packId,
        uint256[] memory cardIds,
        uint256[] memory amounts,
        bytes32 salt
    ) internal {
        if (committedIndex[packId] == 0) {
            committedPackIds.push(packId);
            committedIndex[packId] = committedPackIds.length; // 1-based
        }
        committedCardIds[packId] = cardIds;
        committedAmounts[packId] = amounts;
        committedSalt[packId] = salt;
    }

    /// @notice Build the current leaf set from all committed packs. Pads to a
    ///         minimum of two leaves (murky refuses a single-leaf tree) with a
    ///         sentinel leaf that maps to no real pack.
    function _leaves() internal view returns (bytes32[] memory data) {
        uint256 n = committedPackIds.length;
        uint256 size = n < 2 ? 2 : n;
        data = new bytes32[](size);
        for (uint256 i = 0; i < n; i++) {
            uint256 packId = committedPackIds[i];
            data[i] = _leaf(packId, committedCardIds[packId], committedAmounts[packId], committedSalt[packId]);
        }
        // Pad with distinct sentinel leaves (never proven for a real order).
        for (uint256 i = n; i < size; i++) {
            data[i] = keccak256(abi.encodePacked("cxrds-pad", i));
        }
    }

    /// @notice Recompute the root over all committed packs and seed it on-chain
    ///         (owner-pranked). Safe to call repeatedly — the root is
    ///         owner-mutable at any time.
    function _seed() internal {
        bytes32 root = merkle.getRoot(_leaves());
        vm.prank(owner);
        packs.seedContents(root);
    }

    /// @notice Commit a pack's custom contents AND re-seed in one step.
    function _commitAndSeed(
        uint256 packId,
        uint256[] memory cardIds,
        uint256[] memory amounts,
        bytes32 salt
    ) internal {
        _commit(packId, cardIds, amounts, salt);
        _seed();
    }

    /// @notice The Merkle proof for a committed pack against the current tree.
    function _proofFor(uint256 packId) internal view returns (bytes32[] memory) {
        uint256 idx1 = committedIndex[packId];
        require(idx1 != 0, "pack not committed");
        return merkle.getProof(_leaves(), idx1 - 1);
    }

    // ---------------------------------------------------------------------
    // Config helpers.
    // ---------------------------------------------------------------------

    /// @notice The default card config used at setUp: rip open at the current
    ///         timestamp, no end, no supply cap, empty location.
    function defaultConfig() internal view returns (IManifoldPacksSeaDropShim.PackConfig memory) {
        return IManifoldPacksSeaDropShim.PackConfig({
            maxCardsSupply: 0,
            cardsPerPack: uint16(CARDS_PER_PACK),
            numberOfVariations: uint8(NUM_CARD_DESIGNS),
            ripStartDate: uint48(block.timestamp),
            ripEndDate: 0,
            cardsLocation: "",
            tokenURIExtension: address(0)
        });
    }

    /// @notice Set only the rip start date via updateConfig (owner-pranked).
    function _setRipStart(uint256 ripStartDate) internal {
        IManifoldPacksSeaDropShim.PackConfig memory cfg = packs.getConfig();
        cfg.ripStartDate = uint48(ripStartDate);
        vm.prank(owner);
        packs.updateConfig(cfg);
    }

    /// @notice Set the rip window via updateConfig (owner-pranked).
    function _setRipWindow(uint256 ripStartDate, uint256 ripEndDate) internal {
        IManifoldPacksSeaDropShim.PackConfig memory cfg = packs.getConfig();
        cfg.ripStartDate = uint48(ripStartDate);
        cfg.ripEndDate = uint48(ripEndDate);
        vm.prank(owner);
        packs.updateConfig(cfg);
    }

    /// @notice Set the cards metadata location via updateConfig (owner-pranked).
    function _setCardsLocation(string memory location) internal {
        IManifoldPacksSeaDropShim.PackConfig memory cfg = packs.getConfig();
        cfg.cardsLocation = location;
        vm.prank(owner);
        packs.updateConfig(cfg);
    }

    /// @notice Set the max card supply cap via updateConfig (owner-pranked).
    function _setMaxCardsSupply(uint256 maxCardsSupply) internal {
        IManifoldPacksSeaDropShim.PackConfig memory cfg = packs.getConfig();
        cfg.maxCardsSupply = uint32(maxCardsSupply);
        vm.prank(owner);
        packs.updateConfig(cfg);
    }

    // ---------------------------------------------------------------------
    // EIP-712 RipPermit signing helpers.
    // ---------------------------------------------------------------------

    /**
     * @notice The EIP-712 domain separator for the deployed ManifoldPacksSeaDropShim, matching
     *         OZ EIP712("ManifoldPacksSeaDropShim", "1") exactly.
     */
    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("ManifoldPacksSeaDropShim")),
                keccak256(bytes("1")),
                block.chainid,
                address(packs)
            )
        );
    }

    /**
     * @notice Reproduce the EXACT digest ManifoldPacksSeaDropShim verifies via
     *         `_hashTypedDataV4(keccak256(abi.encode(RIP_TYPEHASH, packId,
     *         deadline)))`. Uses the contract's own RIP_TYPEHASH constant so the
     *         struct hash is byte-for-byte identical.
     */
    function _ripDigest(uint256 packId, uint256 deadline) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(packs.RIP_TYPEHASH(), packId, deadline));
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
    }

    /**
     * @notice Sign a RipPermit over (packId, deadline) with an arbitrary private
     *         key, returning the raw (v, r, s) components.
     */
    function signRipPermit(uint256 privateKey, uint256 packId, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        (v, r, s) = vm.sign(privateKey, _ripDigest(packId, deadline));
    }

    /**
     * @notice Sign a RipPermit and pack it as the 65-byte `bytes` signature
     *         SignatureChecker/ECDSA expects: `abi.encodePacked(r, s, v)`.
     */
    function signRipPermitBytes(uint256 privateKey, uint256 packId, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = signRipPermit(privateKey, packId, deadline);
        return abi.encodePacked(r, s, v);
    }

    /**
     * @notice Build a fully-populated RipOrder signed by `privateKey`, using a
     *         fixed 4-card sheet (each card amount 1, so sum == CARDS_PER_PACK).
     *
     * @param privateKey The key to sign the permit with.
     * @param packId     The pack tokenId to rip.
     * @param cardIds    The four card ids to mint (amount 1 each).
     * @param deadline   The permit deadline.
     */
    function buildRipOrder(
        uint256 privateKey,
        uint256 packId,
        uint256[4] memory cardIds,
        uint256 deadline
    ) internal view returns (IManifoldPacksSeaDropShim.RipOrder memory order) {
        uint256[] memory ids = new uint256[](4);
        uint256[] memory amounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            ids[i] = cardIds[i];
            amounts[i] = 1;
        }
        order = IManifoldPacksSeaDropShim.RipOrder({
            packId: packId,
            cardIds: ids,
            amounts: amounts,
            deadline: deadline,
            signature: signRipPermitBytes(privateKey, packId, deadline),
            salt: committedSalt[packId],
            proof: _proofOrEmpty(packId)
        });
    }

    /**
     * @notice Build a RipOrder with arbitrary dynamic cardIds + amounts (for
     *         duplicate-variation and count-validation tests).
     */
    function buildRipOrderDyn(
        uint256 privateKey,
        uint256 packId,
        uint256[] memory cardIds,
        uint256[] memory amounts,
        uint256 deadline
    ) internal view returns (IManifoldPacksSeaDropShim.RipOrder memory order) {
        order = IManifoldPacksSeaDropShim.RipOrder({
            packId: packId,
            cardIds: cardIds,
            amounts: amounts,
            deadline: deadline,
            signature: signRipPermitBytes(privateKey, packId, deadline),
            salt: committedSalt[packId],
            proof: _proofOrEmpty(packId)
        });
    }

    /// @notice The proof for `packId` if it is committed, else an empty proof
    ///         (used by failure-axis tests that revert on signature / range /
    ///         sum BEFORE the Merkle gate, so the proof is never reached).
    function _proofOrEmpty(uint256 packId) internal view returns (bytes32[] memory) {
        if (committedIndex[packId] == 0) return new bytes32[](0);
        return _proofFor(packId);
    }

    /**
     * @notice Convenience: build a valid RipOrder for a fixture pack owned by
     *         `owner`, signed by `owner`, with a far-future deadline. The pack's
     *         default four cards are pre-committed in setUp, so the attached
     *         proof verifies against the seeded root.
     */
    function buildFixtureRipOrder(uint256 packId)
        internal
        view
        returns (IManifoldPacksSeaDropShim.RipOrder memory)
    {
        return buildRipOrder(OWNER_PK, packId, fixtureCards[packId], block.timestamp + 1 days);
    }

    /// @notice Expose a fixture pack's four card ids to child contracts.
    function cardsForPack(uint256 packId) internal view returns (uint256[4] memory) {
        return fixtureCards[packId];
    }

    /**
     * @notice Convert a fixed 4-card fixture sheet into the dynamic
     *         `cardIds` / `amounts` arrays the new `RipOrder` / `Ripped` event
     *         carry (each card amount 1, so sum == CARDS_PER_PACK). Handy for
     *         reconstructing the exact `Ripped` event payload in vm.expectEmit.
     */
    function _fixtureArrays(uint256[4] memory cardIds)
        internal
        pure
        returns (uint256[] memory ids, uint256[] memory amounts)
    {
        ids = new uint256[](4);
        amounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            ids[i] = cardIds[i];
            amounts[i] = 1;
        }
    }

    // ---------------------------------------------------------------------
    // Sanity test — verifies the harness wiring compiles and initializes.
    // ---------------------------------------------------------------------

    function testHarnessSetup() public virtual {
        assertEq(packs.owner(), owner, "packs owner");
        assertEq(packs.signer(), signerAddr, "backend signer");
        assertEq(packs.getConfig().ripStartDate, block.timestamp, "ripStart open");
        assertGt(startingCardTokenId, 0, "cards initialized");
        assertEq(packs.ownerOf(1), owner, "fixture pack 1 owned by owner");
        assertEq(packs.ownerOf(FIXTURE_PACK_COUNT), owner, "fixture pack N owned by owner");

        // Signing helper recovers to the signing key's address.
        (uint8 v, bytes32 r, bytes32 s) = signRipPermit(OWNER_PK, 1, block.timestamp + 1 days);
        address recovered = ecrecover(_ripDigest(1, block.timestamp + 1 days), v, r, s);
        assertEq(recovered, owner, "permit recovers to signer");
    }
}
