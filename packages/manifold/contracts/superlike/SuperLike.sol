// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ERC1155/IERC1155CreatorExtensionApproveTransfer.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import ".././libraries/manifold-membership/IManifoldMembership.sol";

import "./ISuperLike.sol";

error InvalidStorageProtocol();
error SuperLikeNotInitialized();
error FailedToTransfer();
error InvalidInstance();

/**
 * @title SuperLike
 * @author manifold.xyz
 * @notice SuperLike extension
 */
contract SuperLikeExtension is ISuperLikeExtension, ICreatorExtensionTokenURI, AdminControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct TokenSuperLike {
        address creatorContractAddress;
        uint56 instanceId;
    }

    string internal constant ARWEAVE_PREFIX = "https://arweave.net/";
    string internal constant IPFS_PREFIX = "ipfs://";

    uint256 public constant MINT_FEE = 100000000000000;
    uint256 public constant SUPERLIKE_FEE = 500000000000000;
    // solhint-disable-next-line
    address public MEMBERSHIP_ADDRESS;

    uint256 internal constant MAX_UINT_24 = 0xffffff;
    uint256 internal constant MAX_UINT_32 = 0xffffffff;
    uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;
    uint256 internal constant MAX_UINT_200 = 0xffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 internal constant MAX_UINT_256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    address private constant ADDRESS_ZERO = 0x0000000000000000000000000000000000000000;

    // stores mapping from contractAddress/instanceId to the claim it represents
    // { contractAddress => { instanceId => Claim } }
    mapping(address => mapping(uint256 => SuperLikeInstance)) private _superLikes;


    // { contractAddress => { tokenId => { TokenSuperLike } }
    mapping(address => mapping(uint256 => TokenSuperLike)) private _tokenSuperLike;


    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override (AdminControl, IERC165) returns (bool) {
        return interfaceId == type(ISuperLikeExtension).interfaceId
            || interfaceId == type(ICreatorExtensionTokenURI).interfaceId
            || interfaceId == type(IERC1155CreatorExtensionApproveTransfer).interfaceId
            || interfaceId == type(IAdminControl).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @notice This extension is shared, not single-creator. So we must ensure
     * that a claim's initializer is an admin on the creator contract
     * @param creatorContractAddress    the address of the creator contract to check the admin against
     */
    modifier creatorAdminRequired(address creatorContractAddress) {
        AdminControl creatorCoreContract = AdminControl(creatorContractAddress);
        require(creatorCoreContract.isAdmin(msg.sender), "Wallet is not an administrator for contract");
        _;
    }

    constructor(address initialOwner) {
        _transferOwnership(initialOwner);
    }

    /**
     * See {ISuperLikeExtension-initializeSuperLike}.
     */
    function initializeSuperLike(
        address creatorContractAddress,
        address editionAddress,
        uint256 instanceId,
        SuperLikeParameters calldata parameters
    ) external override creatorAdminRequired(creatorContractAddress) creatorAdminRequired(editionAddress) {
        // Revert if claim at instanceId already exists
        require(_superLikes[creatorContractAddress][instanceId].storageProtocol == StorageProtocol.INVALID, "Claim already initialized");

        // Max uint56 for instanceId
        if (instanceId == 0 || instanceId > MAX_UINT_56) revert InvalidInstance();
        // Sanity checks
        if (parameters.storageProtocol == StorageProtocol.INVALID) revert InvalidStorageProtocol();

        uint256 erc721TokenId = IERC721CreatorCore(creatorContractAddress).mintExtension(msg.sender);
        address[] memory receivers = new address[](1);
        receivers[0] = msg.sender;
        string[] memory uris = new string[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory erc1155TokenIds = IERC1155CreatorCore(editionAddress).mintExtensionNew(receivers, amounts, uris);

         // Create the claim
        _superLikes[creatorContractAddress][instanceId] = SuperLikeInstance({
            proofTokenId: erc721TokenId,
            editionTokenId: erc1155TokenIds[0],
            editionAddress: editionAddress,
            storageProtocol: parameters.storageProtocol,
            location: parameters.location,
            paymentReceiver: parameters.paymentReceiver,
            editionCount: 0
        });
        _tokenSuperLike[creatorContractAddress][erc721TokenId] = TokenSuperLike(creatorContractAddress, uint56(instanceId));
        _tokenSuperLike[editionAddress][erc1155TokenIds[0]] = TokenSuperLike(creatorContractAddress, uint56(instanceId));
        
        emit SuperLikeInitialized(creatorContractAddress, instanceId, editionAddress, msg.sender);
    }

    /**
     * See {ISuperLikeExtension-updateSuperLike}.
     */
    function updateSuperLike(
        address creatorContractAddress,
        uint256 instanceId,
        SuperLikeParameters calldata parameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        // Sanity checks
        SuperLikeInstance storage superLikeInstance = _superLikes[creatorContractAddress][instanceId];
        if (superLikeInstance.storageProtocol == StorageProtocol.INVALID) revert SuperLikeNotInitialized();
        if (parameters.storageProtocol == StorageProtocol.INVALID) revert InvalidStorageProtocol();

        superLikeInstance.location = parameters.location;
        superLikeInstance.storageProtocol = parameters.storageProtocol;
        superLikeInstance.paymentReceiver = parameters.paymentReceiver;

        emit SuperLikeUpdated(creatorContractAddress, instanceId);
    }

    /**
     * See {ILazyPayableClaim-withdraw}.
     */
    function withdraw(address payable receiver, uint256 amount) external override adminRequired {
        (bool sent, ) = receiver.call{value: amount}("");
        if (!sent) revert FailedToTransfer();
    }

    /**
     * See {ILazyPayableClaim-setMembershipAddress}.
     */
    function setMembershipAddress(address membershipAddress) external override adminRequired {
        MEMBERSHIP_ADDRESS = membershipAddress;
    }

    /**
     * See {ISuperLike-mint}.
     */
    function mint(address creatorContractAddress, uint256 instanceId, uint96 count) external payable override {
        SuperLikeInstance storage superLikeInstance = _getSuperLike(creatorContractAddress, instanceId);

        // Transfer funds
        _transferFunds(SUPERLIKE_FEE, superLikeInstance.paymentReceiver, count, true);

        // Do mint
        address[] memory recipients = new address[](1);
        recipients[0] = msg.sender;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = count;
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = superLikeInstance.editionTokenId;
        IERC1155CreatorCore(superLikeInstance.editionAddress).mintExtensionExisting(recipients, tokenIds, amounts);
        superLikeInstance.editionCount += count;

        emit SuperLike(creatorContractAddress, instanceId, msg.sender, count);
    }

    /**
     * See {ISuperLike-mintProxy}.
     */
    function mintProxy(address creatorContractAddress, uint256 instanceId, uint96 count, address mintFor) external payable override {
        SuperLikeInstance storage superLikeInstance = _getSuperLike(creatorContractAddress, instanceId);

        // Transfer funds
        _transferFunds(SUPERLIKE_FEE, superLikeInstance.paymentReceiver, count, false);

        // Do mint
        address[] memory recipients = new address[](1);
        recipients[0] = mintFor;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = count;
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = superLikeInstance.editionTokenId;
        IERC1155CreatorCore(superLikeInstance.editionAddress).mintExtensionExisting(recipients, tokenIds, amounts);
        superLikeInstance.editionCount += count;

        emit SuperLikeProxy(creatorContractAddress, instanceId, mintFor, count, msg.sender);
    }

    function _transferFunds(uint256 cost, address payable recipient, uint96 mintCount, bool allowMembership) internal {
        uint256 payableCost = cost;

        /**
         * Add mint fee if:
         * 1. Not allowing memberships OR
         * 2. No membership address set OR
         * 3. Not an active member
        */
        if (MEMBERSHIP_ADDRESS == ADDRESS_ZERO || !allowMembership || !IManifoldMembership(MEMBERSHIP_ADDRESS).isActiveMember(msg.sender)) {
            payableCost += MINT_FEE; 
        }
        if (mintCount > 1) {
            payableCost *= mintCount;
            cost *= mintCount;
        }

        // Check price
        require(msg.value >= payableCost, "Invalid amount");
        // solhint-disable-next-line
        (bool sent, ) = recipient.call{value: cost}("");
        if (!sent) revert FailedToTransfer();
    }

    function _getSuperLike(address creatorContractAddress, uint256 instanceId) private view returns(SuperLikeInstance storage superLikeInstance) {
        superLikeInstance = _superLikes[creatorContractAddress][instanceId];
        if (superLikeInstance.storageProtocol == StorageProtocol.INVALID) revert SuperLikeNotInitialized();
    }

    /**
     * See {ISuperLike-getSuperLike}.
     */
    function getSuperLike(address creatorContractAddress, uint256 instanceId) external view returns(SuperLikeInstance memory) {
        return _getSuperLike(creatorContractAddress, instanceId);
    }

    /**
     * See {ISuperLike-extendTokenURI}.
     */
    function extendTokenURI(
        address creatorContractAddress, uint256 instanceId,
        string calldata locationChunk
    ) external override creatorAdminRequired(creatorContractAddress) {
        SuperLikeInstance storage superLikeInstance = _superLikes[creatorContractAddress][instanceId];
        require(superLikeInstance.storageProtocol == StorageProtocol.NONE, "Invalid storage protocol");
        superLikeInstance.location = string(abi.encodePacked(superLikeInstance.location, locationChunk));
    }
    /**
     * See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creatorContractAddress, uint256 tokenId) external override view returns(string memory uri) {
        TokenSuperLike memory tokenSuperLike = _tokenSuperLike[creatorContractAddress][tokenId];
        require(tokenSuperLike.instanceId > 0, "Token does not exist");
        SuperLikeInstance memory superLikeInstance = _superLikes[tokenSuperLike.creatorContractAddress][tokenSuperLike.instanceId];

        string memory prefix = "";
        if (superLikeInstance.storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (superLikeInstance.storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        uri = string(abi.encodePacked(prefix, superLikeInstance.location));
    }

    /**
     * @dev ERC1155: Called by creator contract to approve a transfer. ERC1155 tokens are soulbound.
     */
    function approveTransfer(address, address from, address, uint256[] calldata, uint256[] calldata)
        external
        pure
        returns (bool)
    {
        return from == ADDRESS_ZERO;
    }

}