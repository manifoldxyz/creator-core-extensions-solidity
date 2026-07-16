// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title  ICXRDSPacks
 * @author manifold.xyz
 * @notice Interface for the CXRDS pack collection — the struct, events, and
 *         custom-error taxonomy of the gasless "rip" mechanic.
 *
 *         CXRDSPacks is a dual-role contract: an ERC721SeaDrop "pack"
 *         collection that is ALSO a registered extension on a separate stock
 *         ERC1155 creator-core "cards" contract. The core mechanic — "rip" —
 *         lets a signer submit collector-signed EIP-712 `RipPermit`s: the
 *         contract verifies the permit signer is the current owner of the
 *         pack, burns the pack, and mints exactly four cards to that owner.
 *         The whole flow is atomic and gasless for the collector.
 */
interface ICXRDSPacks {
    /**
     * @notice A single collector-signed instruction to rip one pack.
     *
     * @dev    The signed EIP-712 payload is the `RipPermit(uint256 packId,
     *         uint256 deadline)` typed struct — ONLY `packId` and `deadline`
     *         are covered by the signature. `cardIds` are chosen by the
     *         signer/backend and are validated on-chain (range check), not
     *         signed; they are relay data, not part of the collector's
     *         authorization. `(v, r, s)` is the collector's signature over
     *         that typed payload.
     *
     * @param packId   The ERC721 pack tokenId to rip (burn). Also the replay
     *                 lock: once burned, `ownerOf(packId)` reverts ERC721A's
     *                 `OwnerQueryForNonexistentToken`, so the same permit
     *                 cannot be redeemed twice (no nonces are used).
     * @param cardIds  The four ERC1155 card variation tokenIds to mint to the
     *                 pack owner. Fixed-length exactly four — the count is a
     *                 compile-time guarantee, so no runtime "wrong count" case
     *                 exists. Each id must fall in the valid card range.
     * @param deadline Unix timestamp after which the permit is expired and
     *                 the order reverts `PermitExpired`.
     * @param v        `ecrecover` recovery id of the collector's signature.
     * @param r        `ecrecover` r component of the collector's signature.
     * @param s        `ecrecover` s component of the collector's signature.
     */
    struct RipOrder {
        uint256 packId;
        uint256[4] cardIds;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /**
     * @notice Emitted once per pack successfully ripped in a batch: the pack
     *         has been burned and the four cards minted to `owner`.
     *
     * @param packId  The pack tokenId that was ripped (now burned).
     * @param owner   The pack owner who received the four cards (the recovered
     *                permit signer, asserted equal to `ownerOf(packId)`).
     * @param cardIds The four card variation tokenIds minted to `owner`.
     */
    event Ripped(uint256 indexed packId, address indexed owner, uint256[4] cardIds);

    /**
     * @notice Emitted when the authorized rip `signer` is updated by the owner.
     *
     * @param signer The new signer address permitted to call `deliverBatch`.
     */
    event SignerUpdated(address signer);

    /**
     * @notice Emitted when the `ripStart` timestamp gate is updated by the owner.
     *
     * @param ripStart The new earliest timestamp at which ripping is allowed.
     */
    event RipStartUpdated(uint256 ripStart);

    /**
     * @notice Emitted when the `cardsLocation` metadata folder base is updated.
     *
     * @param location The new folder-pattern base URI for card metadata.
     */
    event CardsLocationUpdated(string location);

    /**
     * @notice Reverts when `deliverBatch` is called by any address other than
     *         the configured `signer`.
     */
    error OnlySigner();

    /**
     * @notice Reverts when `deliverBatch` is called before `ripStart`.
     */
    error RipNotStarted();

    /**
     * @notice Reverts when an order's `deadline` has already passed
     *         (`block.timestamp > deadline`).
     */
    error PermitExpired();

    /**
     * @notice Reverts ONLY when `ecrecover` returns `address(0)` for a
     *         malformed / structurally-invalid signature (bad `v`, or an
     *         out-of-range `s`). This error is reserved for the
     *         `ecrecover -> address(0)` case exclusively — a well-formed
     *         signature that simply recovers to the wrong (non-owner) address
     *         does NOT hit this path; it reverts `PermitSignerNotOwner`.
     */
    error InvalidSignature();

    /**
     * @notice Reverts when the recovered permit signer is not the current
     *         owner of the pack. This single error covers every "well-formed
     *         signature, wrong signer" case: a forged-but-well-formed
     *         signature that recovers to some arbitrary address, a signature
     *         from a non-owner, and a stale signature whose signer transferred
     *         the pack away after signing. (Malformed `ecrecover -> address(0)`
     *         signatures are handled earlier by `InvalidSignature`.)
     */
    error PermitSignerNotOwner();

    /**
     * @notice Reverts when any of an order's four `cardIds` falls outside the
     *         valid card variation range
     *         `[startingCardTokenId, startingCardTokenId + NUM_CARD_DESIGNS)`.
     */
    error InvalidCardIds();

    /**
     * @notice Reverts when `initializeCards()` is called more than once (the
     *         `startingCardTokenId` sentinel is already set).
     *
     * @dev    Named `CardsAlreadyInitialized` — NOT `AlreadyInitialized` —
     *         to avoid colliding with `ConstructorInitializable.AlreadyInitialized()`
     *         inherited up the ERC721SeaDrop chain.
     */
    error CardsAlreadyInitialized();
}
