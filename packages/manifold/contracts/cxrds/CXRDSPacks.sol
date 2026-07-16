// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC721SeaDrop} from "seadrop/src/ERC721SeaDrop.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC1155CreatorCore} from "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import {ICreatorExtensionTokenURI} from "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {ICXRDSPacks} from "./ICXRDSPacks.sol";

/**
 * @title  CXRDSPacks
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
 *         `updateConfig`, mirroring the Serendipity claim initialize/update
 *         ideology (`gachaclaims/ERC1155Serendipity.sol`).
 *
 *         As a card-metadata extension, this contract also implements
 *         `ICreatorExtensionTokenURI` — the cards core delegates
 *         `tokenURI(creator, tokenId)` resolution back here, and we serve a
 *         folder-pattern URI derived from `config.cardsLocation`. Pack metadata
 *         is left to the inherited `ERC721ContractMetadata`/`ERC721SeaDrop`
 *         behavior (no bespoke pack `tokenURI` override).
 *
 *         SIGNATURE OFF-SWITCH (break-glass): `ripSignatureRequired` defaults
 *         to `true` — every rip requires a valid owner permit. The owner MAY
 *         flip it to `false` via `setRipSignatureRequired`, in which case
 *         signature verification is SKIPPED ENTIRELY and the trusted `signer`
 *         ALONE authorizes burns. A compromised signer could then rip ANY pack.
 *         This is a deliberate break-glass control, not the normal mode — the
 *         per-rip `signatureVerified` flag on the `Ripped` event records which
 *         rips were unverified.
 *
 *         Deployment order:
 *           1. Deploy this contract (constructor stores the immutable cards
 *              creator and transfers ownership to `initialOwner`).
 *           2. Cards-core admin calls `registerExtension(thisContract, "")` on
 *              the cards core (an ADMIN action — NOT performed by this contract).
 *           3. Call `initializeCards(config)` to reserve the contiguous card
 *              variation ids on the cards core (amount 0 / blank URI) and store
 *              the card configuration.
 *           4. Configure `signer` and the SeaDrop drop parameters.
 */
contract CXRDSPacks is ERC721SeaDrop, EIP712, ICreatorExtensionTokenURI, ICXRDSPacks {
    /// @notice Total number of packs in the collection (informational; the
    ///         authoritative pack max-supply cap is SeaDrop's own `maxSupply`).
    uint256 public constant MAX_PACKS = 3943;

    /// @notice Upper bound on `numberOfVariations` — the uint8 variation cap
    ///         (mirrors Serendipity `MAX_UINT_8`).
    uint256 internal constant MAX_UINT_8 = 0xff;

    /// @notice EIP-712 typehash of the collector-signed rip authorization.
    ///         Only `packId` and `deadline` are covered by the signature.
    bytes32 public constant RIP_TYPEHASH = keccak256("RipPermit(uint256 packId,uint256 deadline)");

    /// @notice The ERC1155 creator-core "cards" contract this pack collection
    ///         is registered on and mints cards from. Immutable, set at deploy.
    address public immutable creatorContractAddress;

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
    ///         trusted `signer` alone authorizes burns (break-glass).
    bool public ripSignatureRequired;

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
     * @param cardsCreator_     The ERC1155 creator-core "cards" contract.
     * @param initialOwner_     Wallet to transfer ownership to immediately
     *                          after deploy. Required when deploying through a
     *                          CREATE2 factory (where the broadcaster is the
     *                          factory address, not the intended drop admin).
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address[] memory allowedSeaDrop_,
        address cardsCreator_,
        address initialOwner_
    ) ERC721SeaDrop(name_, symbol_, allowedSeaDrop_) EIP712("CXRDSPacks", "1") {
        creatorContractAddress = cardsCreator_;
        // Default ON: every rip requires a valid owner permit unless the owner
        // explicitly flips the break-glass off-switch.
        ripSignatureRequired = true;
        // ERC721SeaDrop's TwoStepOwnable constructor already set the owner to
        // msg.sender; transfer to the explicit initialOwner (CREATE2-safe).
        _transferOwnership(initialOwner_);
    }

    /**
     * @notice Reserve `config_.numberOfVariations` contiguous card variation
     *         tokenIds on the cards core and store the card configuration. Calls
     *         `mintExtensionNew` with a zeros amounts array (register-without-
     *         minting) and an empty uris array (all cards use the extension/
     *         default uri). Records the first reserved id as `startingCardTokenId`.
     *
     * @dev    Must be called after this contract has been registered as an
     *         extension on the cards core via `registerExtension` (an admin
     *         action on the cards core). Reverts `CardsAlreadyInitialized` if
     *         already initialized.
     *
     * @param config_ The initial card configuration.
     */
    function initializeCards(PackConfig calldata config_) external onlyOwner {
        if (startingCardTokenId != 0) revert CardsAlreadyInitialized();
        _validateConfig(config_);

        address[] memory to = new address[](1);
        to[0] = msg.sender;
        // Zero amounts -> reserve N new tokenIds, none actually minted.
        uint256[] memory amounts = new uint256[](config_.numberOfVariations);
        // Empty uris -> all reserved cards use the default/extension uri.
        string[] memory uris = new string[](0);

        uint256[] memory ids = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(to, amounts, uris);

        startingCardTokenId = ids[0];
        _config = config_;

        emit CardsInitialized(ids[0], config_);
    }

    /**
     * @notice Update the card configuration. Mirrors Serendipity's `updateClaim`
     *         guard semantics:
     *           - `numberOfVariations` may be RAISED (reserving the additional
     *             contiguous ids on the cards core and asserting contiguity) but
     *             never lowered.
     *           - `maxCardsSupply` cannot be set below already-minted cards.
     *           - `cardsPerPack`, the rip window, and `cardsLocation` are freely
     *             updatable (subject to the shared `PackConfig` validation).
     *
     * @param config_ The new card configuration.
     */
    function updateConfig(PackConfig calldata config_) external onlyOwner {
        if (startingCardTokenId == 0) revert CardsNotInitialized();
        _validateConfig(config_);

        uint256 oldVariations = _config.numberOfVariations;
        if (config_.numberOfVariations < oldVariations) revert CannotLowerVariations();
        if (config_.numberOfVariations > oldVariations) {
            // Reserve the additional contiguous ids and assert they continue the
            // existing block (no other extension slipped ids in between).
            uint256 additional = config_.numberOfVariations - oldVariations;
            address[] memory to = new address[](1);
            to[0] = msg.sender;
            uint256[] memory amounts = new uint256[](additional);
            string[] memory uris = new string[](0);
            uint256[] memory ids = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(to, amounts, uris);
            if (ids[0] != startingCardTokenId + oldVariations) revert NonContiguousVariations();
        }

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
        emit SignerUpdated(signer_);
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
     * @notice Deliver a batch of collector-authorized rip permits. For each
     *         order: verify the permit (unless the off-switch is set), burn the
     *         pack, and mint its cards to the owner. Atomic — any single failure
     *         reverts the entire batch.
     *
     * @dev    Callable only by `signer`, only within the configured rip window.
     *         No nonces and no burn-credit ledger: replay is prevented
     *         structurally because a burned pack makes `ownerOf(packId)` revert
     *         ERC721A's `OwnerQueryForNonexistentToken`.
     *
     *         Error order (pinned; matters for tests):
     *           OnlySigner -> RipNotStarted -> RipEnded ->
     *           (per order) PermitExpired ->
     *           [ownerOf revert for burned/nonexistent pack] ->
     *           InvalidPermit (only when ripSignatureRequired) ->
     *           InvalidCardAmounts -> InvalidCardIds -> MaxCardsSupplyExceeded.
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
