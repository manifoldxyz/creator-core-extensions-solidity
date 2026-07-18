// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC721SeaDrop} from "seadrop/src/ERC721SeaDrop.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC1155CreatorCore} from "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import {ICreatorExtensionTokenURI} from "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IManifoldPacksSeaDropShim} from "./IManifoldPacksSeaDropShim.sol";

/**
 * @title  ManifoldPacksSeaDropShim
 * @author manifold.xyz
 * @notice A dual-role NFT contract: an ERC721SeaDrop "pack" collection that is
 *         ALSO a registered extension on a separate stock ERC1155 creator-core
 *         "cards" contract.
 *
 *         Packs are sold as a normal SeaDrop drop (ERC721A supply, per-wallet
 *         and max-supply caps enforced by SeaDrop through the inherited
 *         `getMintStats`, which reads the real ERC721A counters). Once the rip
 *         phase opens, the authorized `signer` submits batches of
 *         collector-authorized EIP-712 `RipPermit`s via `deliverBatch`: for each
 *         permit the contract validates the permit against the current pack
 *         owner (EOA ECDSA OR EIP-1271 contract wallet via OpenZeppelin
 *         `SignatureChecker`), burns the pack, and mints the pack's
 *         predetermined cards to the owner on the cards core via
 *         `mintExtensionExisting`. The flow is atomic (any single failure
 *         reverts the whole batch) and gasless for the collector.
 *
 *         Card-side parameters live in an owner-configurable `PackConfig`
 *         (variation count, cards-per-pack, rip window, optional supply cap,
 *         metadata location), set once at `initializeCards` and updatable via
 *         `updateConfig`.
 *
 *         As a card-metadata extension, this contract also implements
 *         `ICreatorExtensionTokenURI` — the cards core delegates
 *         `tokenURI(creator, tokenId)` resolution back here, and we serve a
 *         folder-pattern URI derived from `config.cardsLocation`. Pack metadata
 *         is left to the inherited `ERC721ContractMetadata`/`ERC721SeaDrop`
 *         behavior (no bespoke pack `tokenURI` override).
 */
contract ManifoldPacksSeaDropShim is ERC721SeaDrop, EIP712, ICreatorExtensionTokenURI, IManifoldPacksSeaDropShim {
    /// @notice Upper bound on `numberOfVariations` — the uint8 variation cap
    ///         (mirrors Serendipity `MAX_UINT_8`).
    uint256 internal constant MAX_UINT_8 = 0xff;

    /// @notice EIP-712 typehash of the collector-signed rip authorization.
    ///         Only `packId` and `deadline` are covered by the signature.
    bytes32 public constant RIP_TYPEHASH = keccak256("RipPermit(uint256 packId,uint256 deadline)");

    /// @notice The ERC1155 creator-core "cards" contract this pack collection
    ///         is registered on and mints cards from. Set once at
    ///         `initializeCards` (zero until then).
    address public creatorContractAddress;

    /// @notice The first of the contiguous card variation tokenIds reserved on
    ///         the cards core by `initializeCards`. Zero until initialized —
    ///         the uninitialized sentinel (creator-core token ids start at 1).
    uint256 public startingCardTokenId;

    /// @notice The address authorized to submit rip batches via `deliverBatch`.
    address public signer;

    /// @notice Running total of card units minted across all rips. Enforced
    ///         against `config.maxCardsSupply` when that cap is non-zero.
    uint256 public mintedCards;

    /// @notice Whether every rip requires a valid owner permit. Defaults to
    ///         `true`. When `false`, signature verification is skipped and the
    ///         trusted `signer` alone authorizes burns (break-glass). Internal:
    ///         the per-rip `signatureVerified` flag on `Ripped` records state
    ///         off-chain, so no external getter is exposed.
    bool internal ripSignatureRequired;

    /// @notice Merkle root committing each `packId` to its predetermined cards.
    ///         The leaf for a pack is
    ///         `keccak256(abi.encode(packId, cardIds, amounts, salt))`. Set/updated
    ///         via `seedContents` — OWNER-MUTABLE at any time by design (no
    ///         pre-mint lock): the root binds the `signer`, not the `owner`.
    ///         `bytes32(0)` == unseeded (a state in which `deliverBatch` refuses
    ///         to rip). This is the contents-integrity commitment: with a root in
    ///         place a compromised `signer` can only deliver each pack's committed
    ///         cards or revert — it cannot substitute, over-mint, or misdeliver.
    bytes32 public contentsRoot;

    /// @notice Card-side configuration. Set at `initializeCards`, owner-updatable
    ///         via `updateConfig`. Read externally via `getConfig()`.
    PackConfig internal _config;

    /**
     * @notice Deploy the pack collection.
     *
     * @param name_             ERC721 name (used by ERC721A).
     * @param symbol_           ERC721 symbol (used by ERC721A).
     * @param allowedSeaDrop_   SeaDrop contract addresses allowed to call
     *                          `mintSeaDrop` on this collection.
     * @param initialOwner_     Wallet to transfer ownership to immediately
     *                          after deploy. Required when deploying through a
     *                          CREATE2 factory (where the broadcaster is the
     *                          factory address, not the intended drop admin).
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address[] memory allowedSeaDrop_,
        address initialOwner_
    ) ERC721SeaDrop(name_, symbol_, allowedSeaDrop_) EIP712("ManifoldPacksSeaDropShim", "1") {
        // Default ON: every rip requires a valid owner permit unless the owner
        // explicitly flips the break-glass off-switch.
        ripSignatureRequired = true;
        // ERC721SeaDrop's TwoStepOwnable constructor already set the owner to
        // msg.sender; transfer to the explicit initialOwner (CREATE2-safe).
        _transferOwnership(initialOwner_);
    }

    /**
     * @notice Reserve `config_.numberOfVariations` contiguous card variation
     *         tokenIds on the cards core and store the cards-core address plus
     *         the card configuration. Calls `mintExtensionNew` with a zeros
     *         amounts array (register-without-minting) and an empty uris array
     *         (all cards use the extension/default uri). Records the first
     *         reserved id as `startingCardTokenId`.
     *
     * @dev    Must be called after this contract has been registered as an
     *         extension on the cards core via `registerExtension` (an admin
     *         action on the cards core). Reverts `CardsAlreadyInitialized` if
     *         already initialized.
     *
     * @param cardsCreator_ The ERC1155 creator-core "cards" contract to reserve
     *                      variations on and mint cards from. Set once here.
     * @param config_       The initial card configuration.
     */
    function initializeCards(address cardsCreator_, PackConfig calldata config_) external onlyOwner {
        if (startingCardTokenId != 0) revert CardsAlreadyInitialized();
        if (cardsCreator_ == address(0)) revert InvalidCardsCreator();
        _validateConfig(config_);

        creatorContractAddress = cardsCreator_;

        address[] memory to = new address[](1);
        to[0] = msg.sender;
        // Zero amounts -> reserve N new tokenIds, none actually minted.
        uint256[] memory amounts = new uint256[](config_.numberOfVariations);
        // Empty uris -> all reserved cards use the default/extension uri.
        string[] memory uris = new string[](0);

        uint256[] memory ids = IERC1155CreatorCore(cardsCreator_).mintExtensionNew(to, amounts, uris);

        startingCardTokenId = ids[0];
        _config = config_;

        emit CardsInitialized(ids[0], config_);
    }

    /**
     * @notice Update the card configuration. Mirrors Serendipity's `updateClaim`
     *         guard semantics:
     *           - `numberOfVariations` is FIXED at init and may not change.
     *           - `maxCardsSupply` cannot be set below already-minted cards.
     *           - `cardsPerPack`, the rip window, and `cardsLocation` are freely
     *             updatable (subject to the shared `PackConfig` validation).
     *
     * @param config_ The new card configuration.
     */
    function updateConfig(PackConfig calldata config_) external onlyOwner {
        if (startingCardTokenId == 0) revert CardsNotInitialized();
        _validateConfig(config_);

        if (config_.numberOfVariations != _config.numberOfVariations) revert CannotChangeVariations();

        if (config_.maxCardsSupply != 0 && config_.maxCardsSupply < mintedCards) {
            revert CannotLowerMaxBeyondMinted();
        }

        _config = config_;
        emit ConfigUpdated(config_);
    }

    /**
     * @notice Shared `PackConfig` validation used by init and update: variation
     *         count in `(0, 255]`, cards-per-pack > 0, and a coherent rip window.
     */
    function _validateConfig(PackConfig calldata config_) internal pure {
        if (config_.numberOfVariations == 0 || config_.numberOfVariations > MAX_UINT_8) revert InvalidConfig();
        if (config_.cardsPerPack == 0) revert InvalidConfig();
        if (config_.ripEndDate != 0 && config_.ripStartDate >= config_.ripEndDate) revert InvalidDate();
    }

    /**
     * @notice The current card configuration.
     */
    function getConfig() external view returns (PackConfig memory) {
        return _config;
    }

    /**
     * @notice Set the address authorized to submit rip batches.
     *
     * @param signer_ The new signer address.
     */
    function setSigner(address signer_) external onlyOwner {
        signer = signer_;
    }

    /**
     * @notice Toggle whether every rip requires a valid owner permit.
     *
     * @dev    BREAK-GLASS: setting this to `false` SKIPS signature verification
     *         entirely — the trusted `signer` alone authorizes burns, so a
     *         compromised signer could rip ANY pack. Use only as an emergency
     *         control. The `Ripped` event's `signatureVerified` flag records
     *         which rips ran unverified.
     *
     * @param required The new requirement value.
     */
    function setRipSignatureRequired(bool required) external onlyOwner {
        ripSignatureRequired = required;
        emit RipSignatureRequirementUpdated(required);
    }

    /**
     * @notice Seed or update the Merkle root committing each pack's
     *         predetermined cards. Owner-updatable at any time.
     *
     * @dev    TRUST MODEL: this root binds the `signer` — a compromised signer
     *         can only ever deliver each pack's committed cards or revert, never
     *         substitute/over-mint/misdeliver. It does NOT bind the `owner`: the
     *         owner may re-seed a new root at any time (this is a deliberate
     *         operational choice — a live drop needs to correct a bad sheet or a
     *         late card swap). A re-seed is a trusted-owner power, in the same
     *         class as `airdrop`, break-glass, and metadata updates. Every
     *         (re-)seed emits `ContentsSeeded` so the change is publicly
     *         monitorable.
     *
     *         Must be called after `initializeCards` so the sheet is built from
     *         the REAL post-init contiguous card ids (`startingCardTokenId`) —
     *         a correctness guard, not a trust guard.
     *
     * @param root_ The Merkle root over the pack->cards sheet. Each leaf is
     *              `keccak256(abi.encode(packId, cardIds, amounts, salt))`.
     */
    function seedContents(bytes32 root_) external onlyOwner {
        if (startingCardTokenId == 0) revert CardsNotInitialized();
        contentsRoot = root_;
        emit ContentsSeeded(root_);
    }

    /**
     * @notice Deliver a batch of collector-authorized rip permits. For each
     *         order: verify the permit (unless the off-switch is set), burn the
     *         pack, and mint its cards to the owner.
     *
     * @dev    Callable only by `signer`, only within the configured rip window.
     *         No nonces and no burn-credit ledger: replay is prevented
     *         structurally because a burned pack makes `ownerOf(packId)` revert
     *         ERC721A's `OwnerQueryForNonexistentToken`.
     *
     * @param orders The rip orders to process.
     */
    function deliverBatch(RipOrder[] calldata orders) external nonReentrant {
        if (msg.sender != signer) revert OnlySigner();

        uint256 ripStartDate = _config.ripStartDate;
        uint256 ripEndDate = _config.ripEndDate;
        if (block.timestamp < ripStartDate) revert RipNotStarted();
        if (ripEndDate != 0 && block.timestamp > ripEndDate) revert RipEnded();

        uint256 start = startingCardTokenId;
        uint256 numberOfVariations = _config.numberOfVariations;
        uint256 cardsPerPack = _config.cardsPerPack;
        uint256 maxCardsSupply = _config.maxCardsSupply;
        bool sigRequired = ripSignatureRequired;
        if (contentsRoot == bytes32(0)) revert ContentsNotSeeded();
        uint256 len = orders.length;

        for (uint256 i = 0; i < len;) {
            RipOrder calldata order = orders[i];

            if (block.timestamp > order.deadline) revert PermitExpired();

            // Reverts ERC721A's OwnerQueryForNonexistentToken for a burned or
            // nonexistent pack — the replay/duplicate lock.
            address packOwner = ownerOf(order.packId);

            // Verify the collector's permit against the current owner (EOA ECDSA
            // OR EIP-1271 contract wallet). Skipped in break-glass mode.
            if (sigRequired) {
                bytes32 digest = _hashTypedDataV4(
                    keccak256(abi.encode(RIP_TYPEHASH, order.packId, order.deadline))
                );
                if (!SignatureChecker.isValidSignatureNow(packOwner, digest, order.signature)) {
                    revert InvalidPermit();
                }
            }

            // Validate the card ids/amounts: matched non-empty lengths, every id
            // in the reserved variation range, and sum(amounts) == cardsPerPack.
            uint256 n = order.cardIds.length;
            if (n == 0 || n != order.amounts.length) revert InvalidCardAmounts();

            uint256 sum;
            for (uint256 j = 0; j < n;) {
                uint256 cardId = order.cardIds[j];
                if (cardId < start || cardId >= start + numberOfVariations) {
                    revert InvalidCardIds();
                }
                sum += order.amounts[j];
                unchecked {
                    ++j;
                }
            }
            if (sum != cardsPerPack) revert InvalidCardAmounts();

            // Verify the pack's contents against the committed root. The leaf
            // binds packId -> (cardIds, amounts, salt), so a compromised signer
            // cannot substitute contents, swap another pack's cards onto this
            // packId, or over-mint — it can only deliver the committed multiset
            // or revert. abi.encode (NOT encodePacked) is load-bearing: it is
            // canonical/injective over the typed tuple, so no two distinct
            // orders share a leaf. Read `contentsRoot` from storage inline
            // (rather than hoisting a local) to keep the loop off the
            // stack-too-deep cliff without viaIR.
            if (
                !MerkleProof.verify(
                    order.proof,
                    contentsRoot,
                    keccak256(abi.encode(order.packId, order.cardIds, order.amounts, order.salt))
                )
            ) revert ContentsMismatch();

            if (maxCardsSupply != 0 && mintedCards + sum > maxCardsSupply) {
                revert MaxCardsSupplyExceeded();
            }
            mintedCards += sum;

            // Burn the pack, then mint the pack's cards to the owner.
            _burn(order.packId);

            address[] memory to = new address[](1);
            to[0] = packOwner;
            IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(to, order.cardIds, order.amounts);

            emit Ripped(order.packId, packOwner, order.cardIds, order.amounts, sigRequired);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Owner airdrop: mint reserved card variations directly to
     *         recipients, bypassing the pack-burn rip flow. An admin escape
     *         hatch for corrections, giveaways, or partner allocations.
     *
     * @dev    Parallel arrays: recipient `recipients[i]` receives `amounts[i]`
     *         units of card variation `cardIds[i]`. All three lengths must be
     *         equal and non-zero (to give one recipient several cards, repeat
     *         the address across entries). Every `cardIds[i]` must fall in the
     *         reserved variation range. `onlyOwner`.
     *
     *         DELIBERATELY independent of the rip budget: unlike the reference
     *         lazy-claim airdrop (which counts toward the claim total and
     *         auto-raises the max), this does NOT touch `mintedCards` or
     *         `config.maxCardsSupply`. Those govern RIP output (pack economics:
     *         packs * cardsPerPack) and coupling an airdrop into them could
     *         starve unripped packs of their cap headroom and make them
     *         permanently un-rippable. Airdropped card supply is still fully
     *         accounted on the cards core via `totalSupply(cardId)`.
     *
     *         No rip-window gate (`ripStartDate`/`ripEndDate` are not checked)
     *         — the owner may airdrop any time after `initializeCards`.
     *
     * @param recipients The addresses to receive cards (parallel to cardIds/amounts).
     * @param cardIds    The card variation tokenIds to mint (each in range).
     * @param amounts    The per-entry unit counts to mint.
     */
    function airdrop(
        address[] calldata recipients,
        uint256[] calldata cardIds,
        uint256[] calldata amounts
    ) external onlyOwner nonReentrant {
        if (startingCardTokenId == 0) revert CardsNotInitialized();

        uint256 len = recipients.length;
        if (len == 0 || len != cardIds.length || len != amounts.length) revert InvalidAirdrop();

        uint256 start = startingCardTokenId;
        uint256 rangeEnd = start + _config.numberOfVariations;
        for (uint256 i = 0; i < len;) {
            uint256 cardId = cardIds[i];
            if (cardId < start || cardId >= rangeEnd) revert InvalidCardIds();
            unchecked {
                ++i;
            }
        }

        // Parallel-array mint: for len == 1 the cards core does a single mint;
        // for len > 1 it mints cardIds[i] (amounts[i]) to recipients[i].
        IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(recipients, cardIds, amounts);

        emit Airdropped(recipients, cardIds, amounts);
    }

    /**
     * @notice Card metadata resolution delegated by the cards core
     *         (`ICreatorExtensionTokenURI`). Serves a folder-pattern URI:
     *         `cardsLocation + (tokenId - startingCardTokenId + 1)`, so the
     *         first reserved card variation maps to `.../1`.
     *
     * @param tokenId The ERC1155 card variation tokenId on the cards core.
     * @return The folder-pattern metadata URI for the card.
     */
    function tokenURI(address, uint256 tokenId)
        external
        view
        override
        returns (string memory)
    {
        uint256 index = tokenId - startingCardTokenId + 1;
        return string(abi.encodePacked(_config.cardsLocation, _toString(index)));
    }

    /**
     * @notice ERC-165 interface support. Adds `ICreatorExtensionTokenURI` on
     *         top of the ERC721SeaDrop / ERC721A / EIP-2981 surface.
     *
     * @param interfaceId The interface id to check against.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721SeaDrop, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
