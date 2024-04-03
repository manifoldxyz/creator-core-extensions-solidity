// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";

import "../libraries/IERC721CreatorCoreVersion.sol";
import "./IManifoldSingleCore.sol";

/**
 * Manifold Single Mint Implementation
 */
abstract contract ManifoldSingleCore is IManifoldSingleCore {

    string internal constant ARWEAVE_PREFIX = "https://arweave.net/";
    string internal constant IPFS_PREFIX = "ipfs://";

    uint256 internal constant MAX_UINT_24 = 0xffffff;
    uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;

    mapping(address => mapping(uint256 => bytes)) internal _tokenData;
    mapping(address => mapping(uint256 => uint256)) internal _creatorInstanceIds;

    /**
     * @dev Only allows approved admins to call the specified function
     */
    modifier creatorAdminRequired(address creator) {
        if (!IAdminControl(creator).isAdmin(msg.sender)) revert("Must be owner or admin of creator contract");
        _;
    }

    /**
     * @dev See {IManifoldERC721Single-exists}.
     */
    function exists(address creatorCore, uint256 instanceId) external view override returns (bool) {
        return _tokenData[creatorCore][instanceId].length != 0;
    }

    /**
     * See {IManifoldERC721Single-setTokenURI}.
     */
    function setTokenURI(address creatorCore, uint256 instanceId, StorageProtocol storageProtocol, bytes calldata storageData) external override creatorAdminRequired(creatorCore) {
        if (_tokenData[creatorCore][instanceId].length == 0) revert InvalidToken();
        if (storageProtocol == StorageProtocol.INVALID) revert InvalidInput();
        _tokenData[creatorCore][instanceId] = abi.encodePacked(uint8(storageProtocol), storageData);
    }

    function _getTokenInfo(address creatorCore, uint256 instanceId) internal view returns (StorageProtocol storageProtocol, bytes memory storageData) {
        bytes memory tokenData = _tokenData[creatorCore][instanceId];
        if (tokenData.length == 0) revert InvalidToken();
        storageProtocol = StorageProtocol(uint8(tokenData[0]));
        storageData = new bytes(tokenData.length - 1);
        for (uint256 i = 1; i < _tokenData[creatorCore][instanceId].length; i++) {
            storageData[i - 1] = _tokenData[creatorCore][instanceId][i];
        }
    }

}
