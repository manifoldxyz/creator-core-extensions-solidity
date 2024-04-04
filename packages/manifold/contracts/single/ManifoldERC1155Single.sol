// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/CreatorExtension.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "./ManifoldSingleCore.sol";
import "./IManifoldERC1155Single.sol";

/**
 * Manifold ERC1155 Single Mint Implementation
 */
contract ManifoldERC1155Single is CreatorExtension, ManifoldSingleCore, ICreatorExtensionTokenURI, IManifoldERC1155Single {

    function supportsInterface(bytes4 interfaceId) public view virtual override(CreatorExtension, IERC165) returns (bool) {
        return
            interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
            interfaceId == type(IManifoldERC1155Single).interfaceId ||
            CreatorExtension.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IManifoldERC1155Single-mintNew}.
     */
    function mintNew(address creatorCore, uint256 instanceId, StorageProtocol storageProtocol, bytes calldata storageData, address[] calldata recipients, uint256[] calldata amounts) external override creatorAdminRequired(creatorCore) {
        if (instanceId == 0 ||
            instanceId > MAX_UINT_56 ||
            storageProtocol == StorageProtocol.INVALID ||
            _tokenData[creatorCore][instanceId].length != 0
        ) revert InvalidInput();
        _tokenData[creatorCore][instanceId] = abi.encodePacked(uint8(storageProtocol), storageData);
        string[] memory uris;
        uint256[] memory tokenIds = IERC1155CreatorCore(creatorCore).mintExtensionNew(recipients, amounts, uris);
        _creatorInstanceIds[creatorCore][tokenIds[0]] = instanceId;
    }

    /**
     * @dev See {IManifoldERC1155Single-mintExisting}.
     */
    function mintExisting(address creatorCore, uint256 tokenId, address[] calldata recipients, uint256[] calldata amounts) external override creatorAdminRequired(creatorCore) {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        IERC1155CreatorCore(creatorCore).mintExtensionExisting(recipients, tokenIds, amounts);
    }
    
    /**
     * @dev See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creatorCore, uint256 tokenId) external view override returns (string memory) {
        uint256 instanceId = _creatorInstanceIds[creatorCore][tokenId];
        (StorageProtocol storageProtocol, bytes memory data) = _getTokenInfo(creatorCore, instanceId);
        string memory prefix = "";
        if (storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        return string(abi.encodePacked(prefix, data));
    }

    /**
     * @dev See {IManifoldSingleCore-getInstanceId}.
     */
    function getInstanceId(address creatorCore, uint256 tokenId) external view override returns (uint256 instanceId) {
        instanceId = _creatorInstanceIds[creatorCore][tokenId];
        if (instanceId == 0) revert InvalidToken();
    }
    

}
