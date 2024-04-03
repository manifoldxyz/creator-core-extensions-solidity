// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/CreatorExtension.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../libraries/IERC721CreatorCoreVersion.sol";
import "./IManifoldERC721Single.sol";

/**
 * Manifold ERC721 Single Mint Implementation
 */
contract ManifoldERC721Single is CreatorExtension, ICreatorExtensionTokenURI, IManifoldERC721Single, ReentrancyGuard {

    string private constant ARWEAVE_PREFIX = "https://arweave.net/";
    string private constant IPFS_PREFIX = "ipfs://";

    uint256 private constant MAX_UINT_24 = 0xffffff;
    uint256 private constant MAX_UINT_56 = 0xffffffffffffff;

    mapping(address => mapping(uint256 => bytes)) _tokenData;
    mapping(address => mapping(uint256 => uint256)) _creatorInstanceIds;

    /**
     * @dev Only allows approved admins to call the specified function
     */
    modifier creatorAdminRequired(address creator) {
        if (!IAdminControl(creator).isAdmin(msg.sender)) revert("Must be owner or admin of creator contract");
        _;
    }
    
    function supportsInterface(bytes4 interfaceId) public view virtual override(CreatorExtension, IERC165) returns (bool) {
        return
            interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
            interfaceId == type(IManifoldERC721Single).interfaceId ||
            CreatorExtension.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IManifoldERC721Single-mint}.
     */
    function mint(address creatorCore, uint256 instanceId, StorageProtocol storageProtocol, bytes calldata storageData, address recipient) external override creatorAdminRequired(creatorCore) {
        if (instanceId == 0 ||
            instanceId > MAX_UINT_56 ||
            storageProtocol == StorageProtocol.INVALID ||
            _tokenData[creatorCore][instanceId].length != 0
        ) revert InvalidInput();

        uint8 contractVersion;
        try IERC721CreatorCoreVersion(creatorCore).VERSION() returns(uint256 version) {
            require(version <= 255, "Unsupported contract version");
            contractVersion = uint8(version);
        } catch {}

        _tokenData[creatorCore][instanceId] = abi.encodePacked(uint8(storageProtocol), storageData);
        _mintToken(creatorCore, instanceId, contractVersion, recipient);
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

    function _getTokenInfo(address creatorCore, uint256 instanceId) private view returns (StorageProtocol storageProtocol, bytes memory storageData) {
        bytes memory tokenData = _tokenData[creatorCore][instanceId];
        if (tokenData.length == 0) revert InvalidToken();
        storageProtocol = StorageProtocol(uint8(tokenData[0]));
        storageData = new bytes(tokenData.length - 1);
        for (uint256 i = 1; i < _tokenData[creatorCore][instanceId].length; i++) {
            storageData[i - 1] = _tokenData[creatorCore][instanceId][i];
        }
    }
    
    /**
     * @dev See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creatorCore, uint256 tokenId) external view override returns (string memory) {
        uint8 contractVersion;
        try IERC721CreatorCoreVersion(creatorCore).VERSION() returns(uint256 version) {
            require(version <= 255, "Unsupported contract version");
            contractVersion = uint8(version);
        } catch {}

        uint256 instanceId;
        if (contractVersion >= 3) {
            // Contract versions 3+ support storage of data with the token mint, so use that
            instanceId = IERC721CreatorCore(creatorCore).tokenData(tokenId);
        } else {
            instanceId = _creatorInstanceIds[creatorCore][tokenId];
        }
        
        if (instanceId == 0) revert InvalidToken();
        (StorageProtocol storageProtocol, bytes memory data) = _getTokenInfo(creatorCore, instanceId);
        string memory prefix = "";
        if (storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        return string(abi.encodePacked(prefix, data));
    }
    
    function _mintToken(address creatorCore, uint256 instanceId, uint8 contractVersion, address recipient) private {
        if (contractVersion >= 3) {
            IERC721CreatorCore(creatorCore).mintExtension(recipient, uint80(instanceId));
        } else {
            uint256 tokenId = IERC721CreatorCore(creatorCore).mintExtension(recipient);
            _creatorInstanceIds[creatorCore][tokenId] = instanceId;
        }
    }

}
