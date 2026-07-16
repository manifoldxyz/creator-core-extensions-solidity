// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title  ICXRDSPacks
 * @author manifold.xyz
 * @notice Interface for the CXRDS pack collection — the config/order structs,
 *         events, and custom-error taxonomy of the gasless "rip" mechanic.
 *
 *         CXRDSPacks is a dual-role contract: an ERC721SeaDrop "pack"
 *         collection that is ALSO a registered extension on a separate stock
 *         ERC1155 creator-core "cards" contract. The core mechanic — "rip" —
 *         lets a trusted signer submit collector-authorized EIP-712
 *         `RipPermit`s: the contract verifies the permit against the current
 *         owner of the pack (EOA via ECDSA or smart-contract wallet via
 *         EIP-1271, through OpenZeppelin `SignatureChecker`), burns the pack,
 *         and mints that pack's cards to the owner. The whole flow is atomic
 *         and gasless for the collector.
 *
 *         Card-side parameters (variation count, cards-per-pack, rip window,
 *         supply cap, metadata location) are NOT constants — they are captured
 *         in a `PackConfig` set at `initializeCards` and owner-updatable via
 *         `updateConfig`, mirroring the Serendipity claim
 *         initialize/update ideology (`gachaclaims/ERC1155Serendipity.sol`).
 */
interface ICXRDSPacks {
    /**
     * @notice Card-side configuration for the pack collection. Set once at
     *         `initializeCards` and owner-updatable via `updateConfig`.
     *
     * @param maxCardsSupply    Optional hard cap on total card units minted
     *                          across all rips. `0` == unlimited. Cannot be set
     *                          below the already-minted count (`mintedCards`).
     * @param cardsPerPack      Exact number of card units a single pack yields
     *                          when ripped. Every `RipOrder`'s `amounts` MUST
     *                          sum to this value. Must be > 0. Freely updatable.
     * @param numberOfVariations Number of contiguous card variation tokenIds
     *                          reserved on the cards core (`> 0`, `<= 255` —
     *                          the uint8 variation cap). May be RAISED via
     *                          `updateConfig` (reserving additional contiguous
     *                          ids) but never lowered.
     * @param ripStartDate      Earliest timestamp at which `deliverBatch` may
     *                          rip (inclusive lower gate).
     * @param ripEndDate        Latest timestamp at which `deliverBatch` may rip.
     *                          `0` == no end. When non-zero must be strictly
     *                          greater than `ripStartDate`.
     * @param cardsLocation     Folder-pattern base URI for card metadata. Card
     *                          `tokenURI` is `cardsLocation + (tokenId -
     *                          startingCardTokenId + 1)`. Freely updatable.
     */
    struct PackConfig {
        uint256 maxCardsSupply;
        uint256 cardsPerPack;
        uint256 numberOfVariations;
        uint256 ripStartDate;
        uint256 ripEndDate;
        string cardsLocation;
    }

    /**
     * @notice A single collector-authorized instruction to rip one pack.
     *
     * @dev    The signed EIP-712 payload is the `RipPermit(uint256 packId,
     *         uint256 deadline)` typed struct — ONLY `packId` and `deadline`
     *         are covered by the signature. `cardIds` and `amounts` are chosen
     *         by the signer/backend and validated on-chain (range check + sum
     *         == `cardsPerPack`), not signed; they are relay data, not part of
     *         the collector's authorization. `signature` is the collector's
     *         signature over that typed payload — an ECDSA signature packed as
     *         `abi.encodePacked(r, s, v)` for an EOA owner, or any EIP-1271
     *         `bytes` blob the owning contract wallet recognizes.
     *
     * @param packId    The ERC721 pack tokenId to rip (burn). Also the replay
     *                  lock: once burned, `ownerOf(packId)` reverts ERC721A's
     *                  `OwnerQueryForNonexistentToken`, so the same permit
     *                  cannot be redeemed twice (no nonces are used).
     * @param cardIds   The ERC1155 card variation tokenIds to mint to the pack
     *                  owner. Length must equal `amounts.length` and be > 0.
     *                  Each id must fall in the reserved variation range. A
     *                  pack may contain duplicate variations (the same id may
     *                  appear more than once / carry amount > 1).
     * @param amounts   Per-`cardIds` unit counts. `sum(amounts)` MUST equal
     *                  `config.cardsPerPack` — the real runtime "wrong count"
     *                  guard the old fixed-length array made impossible.
     * @param deadline  Unix timestamp after which the permit is expired and the
     *                  order reverts `PermitExpired`.
     * @param signature The collector's signature over the typed
     *                  `RipPermit(packId, deadline)` payload. Verified against
     *                  `ownerOf(packId)` via `SignatureChecker.isValidSignatureNow`
     *                  (EOA ECDSA OR EIP-1271 contract wallet) when
     *                  `ripSignatureRequired` is true; ignored when false.
     */
    struct RipOrder {
        uint256 packId;
        uint256[] cardIds;
        uint256[] amounts;
        uint256 deadline;
        bytes signature;
    }

    /**
     * @notice Emitted once per pack successfully ripped in a batch: the pack
     *         has been burned and its cards minted to `owner`.
     *
     * @param packId            The pack tokenId that was ripped (now burned).
     * @param owner             The pack owner who received the cards (the
     *                          current `ownerOf(packId)`).
     * @param cardIds           The card variation tokenIds minted to `owner`.
     * @param amounts           The per-`cardIds` unit counts minted.
     * @param signatureVerified Whether an owner permit was actually verified
     *                          for THIS rip (the value of `ripSignatureRequired`
     *                          at rip time). `false` means the trusted signer
     *                          alone authorized the burn (break-glass mode).
     */
    event Ripped(
        uint256 indexed packId,
        address indexed owner,
        uint256[] cardIds,
        uint256[] amounts,
        bool signatureVerified
    );

    /**
     * @notice Emitted when the card-side `PackConfig` is set at
     *         `initializeCards`.
     *
     * @param startingCardTokenId The first reserved card variation tokenId.
     * @param config              The initial card configuration.
     */
    event CardsInitialized(uint256 startingCardTokenId, PackConfig config);

    /**
     * @notice Emitted when the card-side `PackConfig` is updated by the owner.
     *
     * @param config The new card configuration.
     */
    event ConfigUpdated(PackConfig config);

    /**
     * @notice Emitted when the owner toggles the per-rip signature requirement.
     *
     * @param required The new value of `ripSignatureRequired`. `false` is the
     *                 break-glass mode where the trusted signer alone authorizes
     *                 burns.
     */
    event RipSignatureRequirementUpdated(bool required);

    /**
     * @notice Reverts when `deliverBatch` is called by any address other than
     *         the configured `signer`.
     */
    error OnlySigner();

    /**
     * @notice Reverts when `deliverBatch` is called before `config.ripStartDate`.
     */
    error RipNotStarted();

    /**
     * @notice Reverts when `deliverBatch` is called after `config.ripEndDate`
     *         (only when `ripEndDate != 0`).
     */
    error RipEnded();

    /**
     * @notice Reverts when an order's `deadline` has already passed
     *         (`block.timestamp > deadline`).
     */
    error PermitExpired();

    /**
     * @notice Reverts when `ripSignatureRequired` is true and the order's
     *         `signature` does not validate against `ownerOf(packId)` via
     *         `SignatureChecker.isValidSignatureNow` (neither a valid EOA ECDSA
     *         signature from the owner NOR a valid EIP-1271 signature from an
     *         owning contract wallet). This single error replaces the old
     *         `InvalidSignature` / `PermitSignerNotOwner` split: SignatureChecker
     *         returns one bool, so malformed, forged, non-owner, and
     *         stale-after-transfer permits all collapse to this one error.
     */
    error InvalidPermit();

    /**
     * @notice Reverts when an order's `cardIds` / `amounts` are structurally
     *         invalid: lengths differ, are zero, or `sum(amounts)` does not
     *         equal `config.cardsPerPack`.
     */
    error InvalidCardAmounts();

    /**
     * @notice Reverts when any of an order's `cardIds` falls outside the valid
     *         card variation range
     *         `[startingCardTokenId, startingCardTokenId + numberOfVariations)`.
     */
    error InvalidCardIds();

    /**
     * @notice Reverts when a rip would push `mintedCards` above a non-zero
     *         `config.maxCardsSupply`.
     */
    error MaxCardsSupplyExceeded();

    /**
     * @notice Reverts when a `PackConfig` fails validation at init/update:
     *         `numberOfVariations == 0` or `> 255`, or `cardsPerPack == 0`.
     */
    error InvalidConfig();

    /**
     * @notice Reverts when `config.ripEndDate != 0` and
     *         `config.ripStartDate >= config.ripEndDate` (mirrors Serendipity's
     *         `InvalidDate`).
     */
    error InvalidDate();

    /**
     * @notice Reverts when `updateConfig` attempts to change `numberOfVariations`
     *         (it is fixed at `initializeCards`; mirrors Serendipity's
     *         `CannotChangeTokenVariations`).
     */
    error CannotChangeVariations();

    /**
     * @notice Reverts when `initializeCards` is given a zero cards-core address.
     */
    error InvalidCardsCreator();

    /**
     * @notice Reverts when `updateConfig` sets a non-zero `maxCardsSupply`
     *         below the already-minted card count (`mintedCards`).
     */
    error CannotLowerMaxBeyondMinted();

    /**
     * @notice Reverts when `initializeCards` is called more than once (the
     *         `startingCardTokenId` sentinel is already set).
     *
     * @dev    Named `CardsAlreadyInitialized` — NOT `AlreadyInitialized` —
     *         to avoid colliding with `ConstructorInitializable.AlreadyInitialized()`
     *         inherited up the ERC721SeaDrop chain.
     */
    error CardsAlreadyInitialized();

    /**
     * @notice Reverts when `updateConfig` is called before `initializeCards`
     *         (mirrors Serendipity's `ClaimNotInitialized`).
     */
    error CardsNotInitialized();
}
