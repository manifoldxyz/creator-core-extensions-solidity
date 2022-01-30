// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/CreatorExtension.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "../libraries/single-creator/ERC721/ERC721SingleCreatorExtensionBase.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./IERC721Edition.sol";

/**
 * ERC721 Edition Base Implementation
 */
abstract contract ERC721EditionBase is ERC721SingleCreatorExtensionBase, CreatorExtension, ICreatorExtensionTokenURI, IERC721Edition, ReentrancyGuard {
    using Strings for uint256;

    struct IndexRange {
        uint256 startIndex;
        uint256 count;
    }

    uint256 internal _maxSupply;
    uint256 internal _totalSupply;
    IndexRange[] private _indexRanges;
    
    function supportsInterface(bytes4 interfaceId) public view virtual override(CreatorExtension, IERC165) returns (bool) {
        return interfaceId == type(ICreatorExtensionTokenURI).interfaceId || interfaceId == type(IERC721Edition).interfaceId || CreatorExtension.supportsInterface(interfaceId);
    }

    /**
     * @dev Initialize the edition contract
     */
    function _initialize(address creator, uint256 maxSupply_) internal {
        require(_creator == address(0), "Already initialized");
        super._setCreator(creator);
        _maxSupply = maxSupply_;
    }

    /**
     * @dev Mint tokens to a single recipient
     */
    function _mint(address recipient, uint16 count) internal nonReentrant {
        require(count > 0, "Invalid amount requested");
        require(_totalSupply+count <= _maxSupply, "Too many requested");
        
        uint256[] memory tokenIds = IERC721CreatorCore(_creator).mintExtensionBatch(recipient, count);
        _updateIndexRanges(tokenIds[0], count);
    }

    /**
     * @dev Mint tokens to a set of recipients
     */
    function _mint(address[] calldata recipients) internal nonReentrant {
        require(recipients.length > 0, "Invalid amount requested");
        require(_totalSupply+recipients.length <= _maxSupply, "Too many requested");
        
        uint256 startIndex = IERC721CreatorCore(_creator).mintExtension(recipients[0]);
        for (uint256 i = 1; i < recipients.length; i++) {
            IERC721CreatorCore(_creator).mintExtension(recipients[i]);
        }
        _updateIndexRanges(startIndex, recipients.length);
    }

    /**
     * @dev Update the index ranges, which is used to figure out the index from a tokenId
     */
    function _updateIndexRanges(uint256 startIndex, uint256 count) internal {
        if (_indexRanges.length == 0) {
           _indexRanges.push(IndexRange(startIndex, count));
        } else {
          IndexRange storage lastIndexRange = _indexRanges[_indexRanges.length-1];
          if ((lastIndexRange.startIndex + lastIndexRange.count) == startIndex) {
             lastIndexRange.count += count;
          } else {
            _indexRanges.push(IndexRange(startIndex, count));
          }
        }
        _totalSupply += count;
    }

    /**
     * @dev Index from tokenId
     */
    function _tokenIndex(address creator, uint256 tokenId) internal view returns(uint256) {
        require(creator == _creator, "Invalid token");
        
        uint256 offset;
        for (uint i = 0; i < _indexRanges.length; i++) {
            IndexRange memory currentIndex = _indexRanges[i];
            if (tokenId < currentIndex.startIndex) break;
            if (tokenId >= currentIndex.startIndex && tokenId < currentIndex.startIndex + currentIndex.count) {
               return tokenId - currentIndex.startIndex + offset;
            }
            offset += currentIndex.count;
        }
        revert("Invalid token");
    }

    /**
     * @dev See {IERC721Edition-totalSupply}.
     */
    function totalSupply() external view override returns(uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC721Edition-maxSupply}.
     */
    function maxSupply() external view override returns(uint256) {
        return _maxSupply;
    }

}
