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

    mapping(uint256 => string) _tokenPrefix;
    mapping(uint256 => uint256) _maxSupply;
    mapping(uint256 => uint256) _totalSupply;
    mapping(uint256 => IndexRange[]) _indexRanges;

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
    function totalSupply(uint256 instanceId) external view override returns(uint256) {
        return _totalSupply[instanceId];
    }

    /**
     * @dev See {IManifoldERC721Edition-maxSupply}.
     */
    function maxSupply(uint256 instanceId) external view override returns(uint256) {
        return _maxSupply[instanceId];
    }

    /**
     * @dev See {IManifoldERC721Edition-createSeries}.
     */
    function createSeries(address creator, uint256 maxSupply_, string calldata prefix, uint256 instanceId) external override creatorAdminRequired(creator) returns(uint256) {
        require(instanceId > 0 && _maxSupply[instanceId] == 0, "Invalid instanceId");
        _maxSupply[instanceId] = maxSupply_;
        _tokenPrefix[instanceId] = prefix;
        _creatorInstanceIds[creator].push(instanceId);
        emit SeriesCreated(msg.sender, creator, instanceId, maxSupply_);
        return instanceId;
    }

    /**
     * See {IManifoldERC721Edition-setTokenURIPrefix}.
     */
    function setTokenURIPrefix(address creator, uint256 instanceId, string calldata prefix) external override creatorAdminRequired(creator) {
        require(instanceId > 0, "Invalid instanceId");
        _tokenPrefix[instanceId] = prefix;
    }
    
    /**
     * @dev See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creator, uint256 tokenId) external view override returns (string memory) {
        (uint256 instanceId, uint256 index) = _tokenInstanceAndIndex(creator, tokenId);
        return string(abi.encodePacked(_tokenPrefix[instanceId], (index+1).toString()));
    }
    
    /**
     * @dev See {IManifoldERC721Edition-mint}.
     */
    function mint(address creator, uint256 instanceId, address recipient, uint16 count) external override nonReentrant creatorAdminRequired(creator) {
        require(count > 0, "Invalid amount requested");
        require(_totalSupply[instanceId]+count <= _maxSupply[instanceId], "Too many requested");
        
        uint256[] memory tokenIds = IERC721CreatorCore(creator).mintExtensionBatch(recipient, count);
        _updateIndexRanges(instanceId, tokenIds[0], count);
    }

    /**
     * @dev See {IManifoldERC721Edition-mint}.
     */
    function mint(address creator, uint256 instanceId, address[] calldata recipients) external override nonReentrant creatorAdminRequired(creator) {
        require(recipients.length > 0, "Invalid amount requested");
        require(_totalSupply[instanceId]+recipients.length <= _maxSupply[instanceId], "Too many requested");
        
        uint256 startIndex = IERC721CreatorCore(creator).mintExtension(recipients[0]);
        for (uint256 i = 1; i < recipients.length;) {
            IERC721CreatorCore(creator).mintExtension(recipients[i]);
            unchecked{i++;}
        }
        _updateIndexRanges(instanceId, startIndex, recipients.length);
    }

    /**
     * @dev Update the index ranges, which is used to figure out the index from a tokenId
     */
    function _updateIndexRanges(uint256 instanceId, uint256 startIndex, uint256 count) internal {
        IndexRange[] storage indexRanges = _indexRanges[instanceId];
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
        _totalSupply[instanceId] += count;
    }

    /**
     * @dev Index from tokenId
     */
    function _tokenInstanceAndIndex(address creator, uint256 tokenId) internal view returns(uint256, uint256) {
        // Go through all their series until we find the tokenId
        for (uint i = 0; i < _creatorInstanceIds[creator].length; i++) {
            uint256 instanceId = _creatorInstanceIds[creator][i];
            IndexRange[] memory indexRanges = _indexRanges[instanceId];
            uint256 offset;
            for (uint j = 0; j < indexRanges.length; j++) {
                IndexRange memory currentIndex = indexRanges[j];
                if (tokenId < currentIndex.startIndex) break;
                if (tokenId >= currentIndex.startIndex && tokenId < currentIndex.startIndex + currentIndex.count) {
                   return (instanceId, tokenId - currentIndex.startIndex + offset);
                }
                offset += currentIndex.count;
            }
        }
        revert("Invalid token");
    }

}
