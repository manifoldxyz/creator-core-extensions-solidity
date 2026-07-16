// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC721SeaDrop} from "seadrop/src/ERC721SeaDrop.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
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
 *         collector-signed EIP-712 `RipPermit`s via `deliverBatch`: for each
 *         permit the contract verifies the recovered signer is the current
 *         pack owner, burns the pack, and mints exactly four cards to the owner
 *         on the cards core via `mintExtensionExisting`. The flow is atomic
 *         (any single failure reverts the whole batch) and gasless for the
 *         collector.
 *
 *         As a card-metadata extension, this contract also implements
 *         `ICreatorExtensionTokenURI` — the cards core delegates
 *         `tokenURI(creator, tokenId)` resolution back here, and we serve a
 *         folder-pattern URI derived from `cardsLocation`.
 *
 *         Deployment order:
 *           1. Deploy this contract (constructor stores the immutable cards
 *              creator and transfers ownership to `initialOwner`).
 *           2. Cards-core admin calls `registerExtension(thisContract, "")` on
 *              the cards core (an ADMIN action — NOT performed by this contract).
 *           3. Call `initializeCards()` to reserve the 251 contiguous card
 *              variation ids on the cards core (amount 0 / blank URI).
 *           4. Configure `signer`, `ripStart`, `cardsLocation`, and the SeaDrop
 *              drop parameters.
 */
contract CXRDSPacks is ERC721SeaDrop, EIP712, ICreatorExtensionTokenURI, ICXRDSPacks {
    /// @notice Total number of packs in the collection (SeaDrop max supply).
    uint256 public constant MAX_PACKS = 3943;

    /// @notice Number of cards minted per pack when ripped.
    uint256 public constant CARDS_PER_PACK = 4;

    /// @notice Number of distinct card variation designs (contiguous ids
    ///         reserved on the cards core by `initializeCards`).
    uint256 public constant NUM_CARD_DESIGNS = 251;

    /// @notice EIP-712 typehash of the collector-signed rip authorization.
    ///         Only `packId` and `deadline` are covered by the signature.
    bytes32 public constant RIP_TYPEHASH = keccak256("RipPermit(uint256 packId,uint256 deadline)");

    /// @notice The ERC1155 creator-core "cards" contract this pack collection
    ///         is registered on and mints cards from. Immutable, set at deploy.
    address public immutable creatorContractAddress;

    /// @notice The first of the 251 contiguous card variation tokenIds reserved
    ///         on the cards core by `initializeCards`. Zero until initialized —
    ///         the uninitialized sentinel (creator-core token ids start at 1).
    uint256 public startingCardTokenId;

    /// @notice The address authorized to submit rip batches via `deliverBatch`.
    address public signer;

    /// @notice Earliest timestamp at which `deliverBatch` may be called.
    uint256 public ripStart;

    /// @notice Folder-pattern base URI for card metadata. Card `tokenURI` is
    ///         `cardsLocation + (tokenId - startingCardTokenId + 1)`.
    string public cardsLocation;

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
        // ERC721SeaDrop's TwoStepOwnable constructor already set the owner to
        // msg.sender; transfer to the explicit initialOwner (CREATE2-safe).
        _transferOwnership(initialOwner_);
    }

    /**
     * @notice Reserve the 251 contiguous card variation tokenIds on the cards
     *         core. Calls `mintExtensionNew` with a 251-length amounts array of
     *         zeros (register-without-minting) and an empty uris array (all
     *         cards use the extension/default uri). Records the first reserved
     *         id as `startingCardTokenId`.
     *
     * @dev    Must be called after this contract has been registered as an
     *         extension on the cards core via `registerExtension` (an admin
     *         action on the cards core). Reverts `CardsAlreadyInitialized` if
     *         already initialized.
     */
    function initializeCards() external onlyOwner {
        if (startingCardTokenId != 0) revert CardsAlreadyInitialized();

        address[] memory to = new address[](1);
        to[0] = msg.sender;
        // 251 zero amounts -> mint 251 new tokenIds, none actually minted.
        uint256[] memory amounts = new uint256[](NUM_CARD_DESIGNS);
        // Empty uris -> all reserved cards use the default/extension uri.
        string[] memory uris = new string[](0);

        uint256[] memory ids = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(to, amounts, uris);

        startingCardTokenId = ids[0];
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
     * @notice Set the earliest timestamp at which ripping is allowed.
     *
     * @param ripStart_ The new rip-start timestamp.
     */
    function setRipStart(uint256 ripStart_) external onlyOwner {
        ripStart = ripStart_;
        emit RipStartUpdated(ripStart_);
    }

    /**
     * @notice Set the folder-pattern base URI for card metadata.
     *
     * @param location_ The new card metadata folder base URI.
     */
    function setCardsLocation(string calldata location_) external onlyOwner {
        cardsLocation = location_;
        emit CardsLocationUpdated(location_);
    }

    /**
     * @notice Deliver a batch of collector-signed rip permits. For each order:
     *         verify the permit, burn the pack, and mint four cards to the
     *         owner. Atomic — any single failure reverts the entire batch.
     *
     * @dev    Callable only by `signer`, only after `ripStart`. No nonces and
     *         no burn-credit ledger: replay is prevented structurally because a
     *         burned pack makes `ownerOf(packId)` revert ERC721A's
     *         `OwnerQueryForNonexistentToken`.
     *
     *         Error order (pinned; matters for tests):
     *           OnlySigner -> RipNotStarted -> (per order) PermitExpired ->
     *           InvalidSignature (ecrecover == address(0)) ->
     *           [ownerOf revert for burned/nonexistent pack] ->
     *           PermitSignerNotOwner -> InvalidCardIds.
     *
     * @param orders The rip orders to process.
     */
    function deliverBatch(RipOrder[] calldata orders) external nonReentrant {
        if (msg.sender != signer) revert OnlySigner();
        if (block.timestamp < ripStart) revert RipNotStarted();

        uint256 start = startingCardTokenId;
        uint256 len = orders.length;

        for (uint256 i = 0; i < len;) {
            RipOrder calldata order = orders[i];

            if (block.timestamp > order.deadline) revert PermitExpired();

            // EIP-712 digest over (RIP_TYPEHASH, packId, deadline).
            bytes32 digest = _hashTypedDataV4(
                keccak256(abi.encode(RIP_TYPEHASH, order.packId, order.deadline))
            );
            address recovered = ecrecover(digest, order.v, order.r, order.s);
            // Malformed signature only — a well-formed sig recovering to the
            // wrong address is caught below by PermitSignerNotOwner.
            if (recovered == address(0)) revert InvalidSignature();

            // Reverts ERC721A's OwnerQueryForNonexistentToken for a burned or
            // nonexistent pack — the replay/duplicate lock.
            address owner = ownerOf(order.packId);
            if (recovered != owner) revert PermitSignerNotOwner();

            // Validate all four card ids fall in the reserved variation range.
            for (uint256 j = 0; j < CARDS_PER_PACK;) {
                uint256 cardId = order.cardIds[j];
                if (cardId < start || cardId >= start + NUM_CARD_DESIGNS) {
                    revert InvalidCardIds();
                }
                unchecked {
                    ++j;
                }
            }

            // Burn the pack, then mint one of each of the four cards to owner.
            _burn(order.packId);

            address[] memory to = new address[](1);
            to[0] = owner;
            uint256[] memory tokenIds = new uint256[](CARDS_PER_PACK);
            uint256[] memory mintAmounts = new uint256[](CARDS_PER_PACK);
            for (uint256 j = 0; j < CARDS_PER_PACK;) {
                tokenIds[j] = order.cardIds[j];
                mintAmounts[j] = 1;
                unchecked {
                    ++j;
                }
            }
            IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(to, tokenIds, mintAmounts);

            emit Ripped(order.packId, owner, order.cardIds);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Metadata for a sealed pack tokenId. All packs share a single
     *         base-URI image (the sealed-pack artwork) until ripped.
     *
     * @dev    Overrides ERC721A/ERC721SeaDrop `tokenURI`. Returns the base URI
     *         verbatim for every existing pack.
     *
     * @param tokenId The pack tokenId.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();
        return _baseURI();
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
        return string(abi.encodePacked(cardsLocation, _toString(index)));
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
