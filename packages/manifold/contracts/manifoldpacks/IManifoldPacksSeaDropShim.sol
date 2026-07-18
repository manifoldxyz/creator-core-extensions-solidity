// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title  IManifoldPacksSeaDropShim
 * @author manifold.xyz
 */
interface IManifoldPacksSeaDropShim {
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
     *                          IGNORED when `tokenURIExtension` is set.
     * @param tokenURIExtension Optional external metadata resolver. When set to
     *                          a non-zero address, card `tokenURI` is delegated
     *                          verbatim to
     *                          `ICreatorExtensionTokenURI(tokenURIExtension).tokenURI(creator, tokenId)`
     *                          and the built-in `cardsLocation` folder pattern
     *                          is bypassed. `address(0)` (the default) keeps the
     *                          built-in folder-pattern resolution.
     */
    struct PackConfig {
        uint256 maxCardsSupply;
        uint256 cardsPerPack;
        uint256 numberOfVariations;
        uint256 ripStartDate;
        uint256 ripEndDate;
        string cardsLocation;
        address tokenURIExtension;
    }

    /**
     * @notice A single collector-authorized instruction to rip one pack.
     *
     * @param packId    The ERC721 pack tokenId to rip (burn). Also the replay
     *                  lock: once burned, `ownerOf(packId)` reverts ERC721A's
     *                  `OwnerQueryForNonexistentToken`, so the same permit
     *                  cannot be redeemed twice (no nonces are used).
     * @param cardIds   The ERC1155 card variation tokenIds to mint to the pack
     *                  owner.
     * @param amounts   Per-`cardIds` unit counts. `sum(amounts)` MUST equal
     *                  `config.cardsPerPack` — the real runtime "wrong count"
     *                  guard the old fixed-length array made impossible.
     * @param deadline  Unix timestamp after which the permit is expired and the
     *                  order reverts `PermitExpired`.
     * @param signature The collector's signature over the typed
     *                  `RipPermit(packId, deadline)` payload. Verified against
     *                  `ownerOf(packId)` via `SignatureChecker.isValidSignatureNow`
     *                  (EOA ECDSA OR EIP-1271 contract wallet).
     * @param salt      Per-pack CSPRNG salt included in the committed leaf
     *                  preimage. It never appears in the collector's signature —
     *                  it is contents-commitment data, supplied by the signer at
     *                  rip time.
     * @param proof     Merkle proof that this pack's leaf.
     */
    struct RipOrder {
        uint256 packId;
        uint256[] cardIds;
        uint256[] amounts;
        uint256 deadline;
        bytes signature;
        bytes32 salt;
        bytes32[] proof;
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
     *                          for THIS rip.
     */
    event Ripped(
        uint256 indexed packId,
        address indexed owner,
        uint256[] cardIds,
        uint256[] amounts,
        bool signatureVerified
    );

    /**
     * @notice Emitted when the owner airdrops card variations directly to
     *         recipients.
     *
     * @param recipients The addresses that received cards.
     * @param cardIds    The card variation tokenIds minted (parallel to amounts).
     * @param amounts    The per-entry unit counts minted.
     */
    event Airdropped(address[] recipients, uint256[] cardIds, uint256[] amounts);

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
     */
    event RipSignatureRequirementUpdated(bool required);

    /**
     * @notice Emitted when the owner pauses or unpauses secondary transfers via
     *         `updateTransfersPaused`.
     * @param paused The new value of `transfersPaused`.
     */
    event TransfersPausedChanged(bool paused);

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
     *         `SignatureChecker.isValidSignatureNow`.
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
     *         `numberOfVariations == 0`, or `cardsPerPack == 0`.
     */
    error InvalidConfig();

    /**
     * @notice Reverts when `config.ripEndDate != 0` and
     *         `config.ripStartDate >= config.ripEndDate`.
     */
    error InvalidDate();

    /**
     * @notice Reverts when `updateConfig` attempts to change `numberOfVariations`
     *         (it is fixed at `initializeCards`.
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
     */
    error CardsAlreadyInitialized();

    /**
     * @notice Reverts when `updateConfig` is called before `initializeCards`
     * 
     */
    error CardsNotInitialized();

    /**
     * @notice Reverts when `airdrop` is given empty or mismatched-length
     *         `recipients` / `cardIds` / `amounts` arrays.
     */
    error InvalidAirdrop();

    /**
     * @notice Reverts when a SECONDARY transfer (or a new approval) is attempted
     *         while `transfersPaused` is true.
     */
    error TransfersPaused();

    /**
     * @notice Reverts when `deliverBatch` is called while `contentsRoot` is
     *         unseeded (`bytes32(0)`) — the contract refuses to rip any pack
     *         until a contents commitment exists.
     */
    error ContentsNotSeeded();

    /**
     * @notice Reverts when an order's `(cardIds, amounts, salt)` do not hash to
     *         a leaf committed under `contentsRoot` for `packId` (the Merkle
     *         proof fails).
     */
    error ContentsMismatch();
}
