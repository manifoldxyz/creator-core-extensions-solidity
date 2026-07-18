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
 *         owner, burns the pack, and mints the pack's
 *         cards to the owner on the cards core via
 *         `mintExtensionExisting`.
 *
 *         Card-side parameters live in an owner-configurable `PackConfig`
 *         (variation count, cards-per-pack, rip window, optional supply cap,
 *         metadata location), set once at `initializeCards` and updatable via
 *         `updateConfig`.
 */
contract ManifoldPacksSeaDropShim is ERC721SeaDrop, EIP712, ICreatorExtensionTokenURI, IManifoldPacksSeaDropShim {
    /// @notice EIP-712 typehash of the collector-signed rip authorization.
    ///         Only `packId` and `deadline` are covered by the signature.
    bytes32 public constant RIP_TYPEHASH = keccak256("RipPermit(uint256 packId,uint256 deadline)");

    // -------------------------------------------------------------------------
    // Storage — width-sized and ordered so related fields share slots.
    //
    //   Slot A: signer + mintedCards + ripSignatureRequired + transfersPaused
    //   Slot B: creatorContractAddress + startingCardTokenId
    //   Slot C: contentsRoot
    //   Slot D+: _config (its five numeric fields share one slot; see PackConfig)
    //
    // The `deliverBatch` hot path reads signer/ripSignatureRequired (slot A),
    // startingCardTokenId (slot B), contentsRoot (slot C) and all five config
    // numerics (slot D) in four SLOADs total, and writes mintedCards back into
    // the already-warm slot A.
    // -------------------------------------------------------------------------

    /// @notice The address authorized to submit rip batches via `deliverBatch`.
    address public signer;

    /// @notice Running total of card units minted across all rips. Enforced
    ///         against `config.maxCardsSupply` when that cap is non-zero.
    ///         `uint32` to share the `maxCardsSupply` domain and pack with
    ///         `signer`.
    uint32 public mintedCards;

    /// @notice Whether every rip requires a valid owner permit. Defaults to
    ///         `true`.
    bool internal ripSignatureRequired;

    /// @notice Whether secondary transfers/approvals are paused. Defaults to
    ///         `true`.
    bool public transfersPaused;

    /// @notice The ERC1155 creator-core "cards" contract this pack collection
    ///         is registered on and mints cards from. Set once at
    ///         `initializeCards` (zero until then).
    address public creatorContractAddress;

    /// @notice The first of the contiguous card variation tokenIds reserved on
    ///         the cards core by `initializeCards`. Zero until initialized —
    ///         the uninitialized sentinel (creator-core token ids start at 1).
    ///         `uint80` (packs with `creatorContractAddress`).
    uint80 public startingCardTokenId;

    /// @notice Merkle root committing each pack's cards. `bytes32(0)` == unseeded.
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
        ripSignatureRequired = true;
        transfersPaused = true;
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
     *         extension on the creator core via `registerExtension` (an admin
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

        startingCardTokenId = uint80(ids[0]);
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
     *         count > 0 (the `<= 255` upper bound is enforced by the uint8
     *         type), cards-per-pack > 0, and a coherent rip window.
     */
    function _validateConfig(PackConfig calldata config_) internal pure {
        if (config_.numberOfVariations == 0) revert InvalidConfig();
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
     * @param required The new requirement value.
     */
    function setRipSignatureRequired(bool required) external onlyOwner {
        ripSignatureRequired = required;
        emit RipSignatureRequirementUpdated(required);
    }

    function updateTransfersPaused(bool paused) external onlyOwner {
        transfersPaused = paused;
        emit TransfersPausedChanged(paused);
    }

    function seedContents(bytes32 root_) external onlyOwner {
        if (startingCardTokenId == 0) revert CardsNotInitialized();
        contentsRoot = root_;
    }

    /**
     * @notice Deliver a batch of collector-authorized rip permits. For each
     *         order: verify the permit, burn the
     *         pack, and mint its cards to the owner.
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

        // Accumulate minted cards in a local, write back to storage once after
        // the batch (mintedCards shares a warm slot with `signer`).
        uint256 mintedCardsLocal = mintedCards;

        for (uint256 i = 0; i < len;) {
            RipOrder calldata order = orders[i];

            if (block.timestamp > order.deadline) revert PermitExpired();

            address packOwner = ownerOf(order.packId);

            // Verify the collector's permit against the current owner (EOA ECDSA
            // OR EIP-1271 contract wallet)
            if (sigRequired) {
                bytes32 digest = _hashTypedDataV4(
                    keccak256(abi.encode(RIP_TYPEHASH, order.packId, order.deadline))
                );
                if (!SignatureChecker.isValidSignatureNow(packOwner, digest, order.signature)) {
                    revert InvalidPermit();
                }
            }

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

            if (
                !MerkleProof.verify(
                    order.proof,
                    contentsRoot,
                    keccak256(abi.encode(order.packId, order.cardIds, order.amounts, order.salt))
                )
            ) revert ContentsMismatch();

            if (maxCardsSupply != 0 && mintedCardsLocal + sum > maxCardsSupply) {
                revert MaxCardsSupplyExceeded();
            }
            mintedCardsLocal += sum;

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

        mintedCards = uint32(mintedCardsLocal);
    }

    /**
     * @notice Owner airdrop: mint reserved card variations directly to
     *         recipients.
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
        uint256 totalAmount;
        for (uint256 i = 0; i < len;) {
            uint256 cardId = cardIds[i];
            if (cardId < start || cardId >= rangeEnd) revert InvalidCardIds();
            totalAmount += amounts[i];
            unchecked {
                ++i;
            }
        }

        uint256 newMinted = uint256(mintedCards) + totalAmount;
        mintedCards = uint32(newMinted);
        if (_config.maxCardsSupply != 0 && newMinted > _config.maxCardsSupply) {
            _config.maxCardsSupply = uint32(newMinted);
        }

        IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(recipients, cardIds, amounts);

        emit Airdropped(recipients, cardIds, amounts);
    }

    /**
     *
     * @param creator The cards-core contract querying the URI (passed through
     *                to an external resolver so a shared resolver can key on it).
     * @param tokenId The ERC1155 card variation tokenId on the cards core.
     * @return The metadata URI for the card.
     */
    function tokenURI(address creator, uint256 tokenId)
        external
        view
        override
        returns (string memory)
    {
        address ext = _config.tokenURIExtension;
        if (ext != address(0)) {
            return ICreatorExtensionTokenURI(ext).tokenURI(creator, tokenId);
        }
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

    function setApprovalForAll(address operator, bool approved) public virtual override {
        if (transfersPaused) revert TransfersPaused();
        super.setApprovalForAll(operator, approved);
    }

    function approve(address to, uint256 tokenId) public virtual override {
        if (transfersPaused) revert TransfersPaused();
        super.approve(to, tokenId);
    }

    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        if (from != address(0) && to != address(0) && transfersPaused) {
            revert TransfersPaused();
        }
        super._beforeTokenTransfers(from, to, startTokenId, quantity);
    }
}
