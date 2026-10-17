// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC721SeaDrop} from "seadrop/src/ERC721SeaDrop.sol";
import {IERC1155CreatorCore} from "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import {IERC1155CreatorExtensionApproveTransfer} from "@manifoldxyz/creator-core-solidity/contracts/extensions/ERC1155/IERC1155CreatorExtensionApproveTransfer.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAdminControl} from "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";

/**
 * @title  ManifoldERC1155SeaDropShim
 * @notice Sells one ERC1155 token on a Manifold creator contract through
 *         OpenSea SeaDrop.
 */
contract ManifoldERC1155SeaDropShim is
    ERC721SeaDrop,
    IERC1155CreatorExtensionApproveTransfer
{
    /// @notice Reverts if `initialize()` is called more than once.
    error AlreadyInitializedShim();

    /// @notice Reverts if the constructor is given a zero `initialOwner_`.
    error InitialOwnerIsZeroAddress();

    /// @notice Reverts if called before `initialize()`.
    error NotInitialized();

    /// @notice Reverts if `airdrop` recipients and amounts lengths differ.
    error InvalidAirdrop();

    /// @notice Reverts if `setApproveTransfer` names another creator contract.
    error InvalidCreator();

    /// @notice Reverts if the caller is not an admin of the creator contract.
    error CreatorAdminRequired();

    /// @notice Emitted when the token's metadata URI is set.
    event TokenURIUpdated(uint256 indexed tokenId, string uri);

    /// @notice Emitted at deployment with the creator contract this shim
    ///         mints on.
    event SeaDropShimDeployed(address indexed creatorContract);

    /// @notice Emitted when the transfer lock changes. 0 means unlocked.
    event TransferLockUpdated(uint256 unlockTime);

    /// @dev ERC-165 id of the legacy approve-transfer interface, checked by
    ///      older creator contracts.
    bytes4 private constant IERC1155CreatorExtensionApproveTransfer_v1 = 0x93a80b14;

    /// @notice The creator contract this shim mints on.
    address public immutable creatorContractAddress;

    /// @notice The token this shim mints. Zero until `initialize()`.
    uint256 public tokenId;

    /// @notice Total minted through this shim, for the max-supply cap.
    uint256 internal _shimTotalMinted;

    /// @notice Minted per wallet through this shim, for the per-wallet cap.
    mapping(address => uint256) internal _shimMinterNumMinted;

    /// @notice Unix time (seconds) until which transfers of `tokenId` are
    ///         blocked. 0 or a past time means unlocked.
    uint256 public transferLockUntil;

    /// @notice Restricts a call to admins of the creator contract.
    modifier creatorAdminRequired() {
        _creatorAdminRequired();
        _;
    }

    /**
     * @param name_                   Collection name.
     * @param symbol_                 Collection symbol.
     * @param allowedSeaDrop_         SeaDrop contracts allowed to mint.
     * @param creatorContractAddress_ Creator contract to mint on.
     * @param initialOwner_           Drop owner. Set explicitly because a
     *                                CREATE2 factory is the deployer.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address[] memory allowedSeaDrop_,
        address creatorContractAddress_,
        address initialOwner_
    ) ERC721SeaDrop(name_, symbol_, allowedSeaDrop_) {
        if (initialOwner_ == address(0)) revert InitialOwnerIsZeroAddress();
        creatorContractAddress = creatorContractAddress_;
        emit SeaDropShimDeployed(creatorContractAddress_);
        _transferOwnership(initialOwner_);
    }

    /**
     * @notice Create the token on the creator contract, with no supply.
     *         Call once, after this shim is registered as an extension.
     *
     * @param uri_ Token metadata URI. Empty leaves it unset.
     */
    function initialize(string calldata uri_) external creatorAdminRequired {
        if (tokenId != 0) revert AlreadyInitializedShim();

        address[] memory to = new address[](1);
        to[0] = msg.sender;
        uint256[] memory amounts = new uint256[](1);
        string[] memory uris = new string[](1);
        uris[0] = uri_;

        uint256[] memory mintedTokenIds = IERC1155CreatorCore(
            creatorContractAddress
        ).mintExtensionNew(to, amounts, uris);

        tokenId = mintedTokenIds[0];

        // Registration turns transfer checks on. Turn them off so unlocked
        // drops pay no extra gas per transfer.
        IERC1155CreatorCore(creatorContractAddress).setApproveTransferExtension(false);

        if (bytes(uri_).length > 0) {
            emit TokenURIUpdated(tokenId, uri_);
        }
    }

    /**
     * @notice Block transfers of `tokenId` until `until`. Mints and burns
     *         still work. Pass 0 to unlock now.
     *
     * @param until Unix time (seconds) when transfers open.
     */
    function setTransferLock(uint256 until) external creatorAdminRequired {
        if (tokenId == 0) revert NotInitialized();
        transferLockUntil = until;
        IERC1155CreatorCore(creatorContractAddress).setApproveTransferExtension(
            until > block.timestamp
        );
        emit TransferLockUpdated(until);
    }

    /**
     * @notice Turn the creator's transfer checks for `tokenId` on or off.
     *         Prefer `setTransferLock`, which keeps this in sync.
     */
    function setApproveTransfer(address creator, bool enabled)
        external
        override
        creatorAdminRequired
    {
        if (creator != creatorContractAddress) revert InvalidCreator();
        IERC1155CreatorCore(creatorContractAddress).setApproveTransferExtension(enabled);
    }

    /**
     * @notice Called by the creator contract on transfers of `tokenId`.
     *         Allows burns, and other transfers once the lock has passed.
     */
    function approveTransfer(address, address, address to, uint256[] calldata, uint256[] calldata)
        external
        view
        override
        returns (bool)
    {
        return _transferAllowed(to);
    }

    /// @notice Legacy variant of `approveTransfer`.
    function approveTransfer(address, address to, uint256[] calldata, uint256[] calldata)
        external
        view
        returns (bool)
    {
        return _transferAllowed(to);
    }

    function _transferAllowed(address to) internal view returns (bool) {
        return to == address(0) || block.timestamp >= transferLockUntil;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721SeaDrop, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IERC1155CreatorExtensionApproveTransfer).interfaceId ||
            interfaceId == IERC1155CreatorExtensionApproveTransfer_v1 ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @notice Mint `tokenId` to recipients. Counts toward total minted and
     *         raises max supply if exceeded. Per-wallet counts unchanged.
     */
    function airdrop(address[] calldata recipients, uint256[] calldata amounts)
        external
        creatorAdminRequired
        nonReentrant
    {
        if (tokenId == 0) revert NotInitialized();
        if (recipients.length != amounts.length) revert InvalidAirdrop();

        uint256 totalAmount;
        for (uint256 i; i < amounts.length; ) {
            totalAmount += amounts[i];
            unchecked {
                ++i;
            }
        }

        uint256 newTotal = _shimTotalMinted + totalAmount;
        if (newTotal > 2**64 - 1) {
            revert CannotExceedMaxSupplyOfUint64(newTotal);
        }
        _shimTotalMinted = newTotal;
        if (newTotal > _maxSupply) {
            _maxSupply = newTotal;
            emit MaxSupplyUpdated(newTotal);
        }

        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(
            recipients,
            ids,
            amounts
        );
    }

    /// @notice Called by SeaDrop to mint `quantity` of `tokenId` to `minter`.
    function mintSeaDrop(address minter, uint256 quantity)
        external
        override
        nonReentrant
    {
        _onlyAllowedSeaDrop(msg.sender);

        // SeaDrop checks this too; re-check here.
        uint256 newTotal = _shimTotalMinted + quantity;
        uint256 cap = maxSupply();
        if (newTotal > cap) {
            revert MintQuantityExceedsMaxSupply(newTotal, cap);
        }

        // Update counts before the external call.
        _shimMinterNumMinted[minter] += quantity;
        _shimTotalMinted = newTotal;

        address[] memory to = new address[](1);
        to[0] = minter;
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = quantity;

        IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(
            to,
            ids,
            amounts
        );
    }

    /// @notice Mint counts SeaDrop uses for its caps. Counts only mints
    ///         made through this shim.
    function getMintStats(address minter)
        external
        view
        override
        returns (
            uint256 minterNumMinted,
            uint256 currentTotalSupply,
            uint256 maxSupply_
        )
    {
        minterNumMinted = _shimMinterNumMinted[minter];
        currentTotalSupply = _shimTotalMinted;
        maxSupply_ = maxSupply();
    }

    /// @notice Set the metadata URI of `tokenId`.
    function updateURI(string calldata uri_) external creatorAdminRequired {
        if (tokenId == 0) revert NotInitialized();
        IERC1155CreatorCore(creatorContractAddress).setTokenURIExtension(
            tokenId,
            uri_
        );
        emit TokenURIUpdated(tokenId, uri_);
    }

    function _creatorAdminRequired() internal view {
        if (!IAdminControl(creatorContractAddress).isAdmin(msg.sender)) {
            revert CreatorAdminRequired();
        }
    }
}
