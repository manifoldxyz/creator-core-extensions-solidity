// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/CreatorExtension.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./IManifoldERC721Edition.sol";

/**
 * Manifold ERC721 Edition Controller Implementation
 */
contract ManifoldERC721Edition is CreatorExtension, ICreatorExtensionTokenURI, IManifoldERC721Edition, ReentrancyGuard {
    using Strings for uint256;

    struct IndexRange {
        uint256 startIndex;
        uint256 count;
    }

    mapping(address => mapping(uint256 => string)) _tokenPrefix;
    mapping(address => mapping(uint256 => uint256)) _maxSupply;
    mapping(address => mapping(uint256 => uint256)) _totalSupply;
    mapping(address => mapping(uint256 => IndexRange[])) _indexRanges;

    mapping(address => uint256[]) _creatorInstanceIds;
    
    /**
     * @dev Only allows approved admins to call the specified function
     */
    modifier creatorAdminRequired(address creator) {
        require(IAdminControl(creator).isAdmin(msg.sender), "Must be owner or admin of creator contract");
        _;
    }
    
    function supportsInterface(bytes4 interfaceId) public view virtual override(CreatorExtension, IERC165) returns (bool) {
        return interfaceId == type(ICreatorExtensionTokenURI).interfaceId || interfaceId == type(IManifoldERC721Edition).interfaceId ||
               CreatorExtension.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IManifoldERC721Edition-totalSupply}.
     */
    function totalSupply(address creatorCore, uint256 instanceId) external view override returns(uint256) {
        return _totalSupply[creatorCore][instanceId];
    }


    /**
     * @dev See {IManifoldERC721Edition-instanceExists}.
     */
    function instanceExists(address creatorCore, uint256 instanceId) external view override returns(bool) {
        return _maxSupply[creatorCore][instanceId] > 0;
    }

    /**
     * @dev See {IManifoldERC721Edition-maxSupply}.
     */
    function maxSupply(address creatorCore, uint256 instanceId) external view override returns(uint256) {
        return _maxSupply[creatorCore][instanceId];
    }

    /**
     * See {IManifoldERC721Edition-setTokenURIPrefix}.
     */
    function setTokenURIPrefix(address creatorCore, uint256 instanceId, string calldata prefix) external override creatorAdminRequired(creatorCore) {
        require(_maxSupply[creatorCore][instanceId] != 0, "Invalid instanceId");
        _tokenPrefix[creatorCore][instanceId] = prefix;
    }
    
    /**
     * @dev See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creatorCore, uint256 tokenId) external view override returns (string memory) {
        (uint256 instanceId, uint256 index) = _tokenInstanceAndIndex(creatorCore, tokenId);
        return string(abi.encodePacked(_tokenPrefix[creatorCore][instanceId], (index+1).toString()));
    }
    
    /**
     * @dev See {IManifoldERC721Edition-mint}.
     */
    function mint(address creatorCore, uint256 instanceId, address recipient, uint16 count) external override nonReentrant creatorAdminRequired(creatorCore) {
        require(count > 0, "Invalid amount requested");
        require(_totalSupply[creatorCore][instanceId]+count <= _maxSupply[creatorCore][instanceId], "Too many requested");
        
        uint256[] memory tokenIds = IERC721CreatorCore(creatorCore).mintExtensionBatch(recipient, count);
        _updateIndexRanges(creatorCore, instanceId, tokenIds[0], count);
    }

    /**
     * @dev See {IManifoldERC721Edition-mint}.
     */
    function mint(address creatorCore, uint256 instanceId, address[] calldata recipients) external override nonReentrant creatorAdminRequired(creatorCore) {
        require(recipients.length > 0, "Invalid amount requested");
        require(_totalSupply[creatorCore][instanceId]+recipients.length <= _maxSupply[creatorCore][instanceId], "Too many requested");
        
        mintTokens(creatorCore, recipients, instanceId);
    }

    function mintTokens(address creatorCore, address[] memory recipients, uint256 instanceId) internal {
        uint256 startIndex = IERC721CreatorCore(creatorCore).mintExtension(recipients[0]);
        for (uint256 i = 1; i < recipients.length;) {
            IERC721CreatorCore(creatorCore).mintExtension(recipients[i]);
            unchecked{++i;}
        }
        _updateIndexRanges(creatorCore, instanceId, startIndex, recipients.length);
    }


    /**
     * @dev See {IManifoldERC721Edition-createSeries}.
     */
    function createSeries(address creatorCore, uint256 maxSupply_, string calldata prefix, uint256 instanceId, address[] memory recipients) external override creatorAdminRequired(creatorCore) returns(uint256) {
        require(instanceId > 0 && maxSupply_ > 0 && _maxSupply[creatorCore][instanceId] == 0, "Invalid instance");
        _maxSupply[creatorCore][instanceId] = maxSupply_;
        _tokenPrefix[creatorCore][instanceId] = prefix;
        _creatorInstanceIds[creatorCore].push(instanceId);
        emit SeriesCreated(msg.sender, creatorCore, instanceId, maxSupply_);

        // Mint to recipients
        if (recipients.length > 0) {
            mintTokens(creatorCore, recipients, instanceId);
        }

        return instanceId;
    }

    /**
     * @dev Update the index ranges, which is used to figure out the index from a tokenId
     */
    function _updateIndexRanges(address creatorCore, uint256 instanceId, uint256 startIndex, uint256 count) internal {
        IndexRange[] storage indexRanges = _indexRanges[creatorCore][instanceId];
        if (indexRanges.length == 0) {
           indexRanges.push(IndexRange(startIndex, count));
        } else {
          IndexRange storage lastIndexRange = indexRanges[indexRanges.length-1];
          if ((lastIndexRange.startIndex + lastIndexRange.count) == startIndex) {
             lastIndexRange.count += count;
          } else {
            indexRanges.push(IndexRange(startIndex, count));
          }
        }
        _totalSupply[creatorCore][instanceId] += count;
    }

    /**
     * @dev Index from tokenId
     */
    function _tokenInstanceAndIndex(address creatorCore, uint256 tokenId) internal view returns(uint256, uint256) {
        // Go through all their series until we find the tokenId
        for (uint256 i; i < _creatorInstanceIds[creatorCore].length;) {
            uint256 instanceId = _creatorInstanceIds[creatorCore][i];
            IndexRange[] memory indexRanges = _indexRanges[creatorCore][instanceId];
            uint256 offset;
            for (uint j; j < indexRanges.length;) {
                IndexRange memory currentIndex = indexRanges[j];
                if (tokenId < currentIndex.startIndex) break;
                if (tokenId >= currentIndex.startIndex && tokenId < currentIndex.startIndex + currentIndex.count) {
                   return (instanceId, tokenId - currentIndex.startIndex + offset);
                }
                offset += currentIndex.count;
                unchecked{++j;}
            }
            unchecked{++i;}
        }
        revert("Invalid token");
    }

}
