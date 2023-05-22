// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/CreatorExtension.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
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
    mapping(address => uint256) _currentSeries;
    
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
    function totalSupply(address creator, uint256 series) external view override returns(uint256) {
        return _totalSupply[creator][series];
    }

    /**
     * @dev See {IManifoldERC721Edition-maxSupply}.
     */
    function maxSupply(address creator, uint256 series) external view override returns(uint256) {
        return _maxSupply[creator][series];
    }

    /**
     * @dev See {IManifoldERC721Edition-createSeries}.
     */
    function createSeries(address creator, uint256 maxSupply_, string calldata prefix) external override creatorAdminRequired(creator) returns(uint256) {
        _currentSeries[creator] += 1;
        uint256 series = _currentSeries[creator];
        _maxSupply[creator][series] = maxSupply_;
        _tokenPrefix[creator][series] = prefix;
        emit SeriesCreated(msg.sender, creator, series, maxSupply_);
        return series;
    }

    /**
     * @dev See {IManifoldERC721Edition-latestSeries}.
     */
    function latestSeries(address creator) external view override returns(uint256) {
        return _currentSeries[creator];
    }

    /**
     * See {IManifoldERC721Edition-setTokenURIPrefix}.
     */
    function setTokenURIPrefix(address creator, uint256 series, string calldata prefix) external override creatorAdminRequired(creator) {
        require(series > 0 && series <= _currentSeries[creator], "Invalid series");
        _tokenPrefix[creator][series] = prefix;
    }
    
    /**
     * @dev See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creator, uint256 tokenId) external view override returns (string memory) {
        (uint256 series, uint256 index) = _tokenSeriesAndIndex(creator, tokenId);
        return string(abi.encodePacked(_tokenPrefix[creator][series], (index+1).toString()));
    }
    
    /**
     * @dev See {IManifoldERC721Edition-mint}.
     */
    function mint(address creator, uint256 series, address recipient, uint16 count) external override nonReentrant creatorAdminRequired(creator) {
        require(count > 0, "Invalid amount requested");
        require(_totalSupply[creator][series]+count <= _maxSupply[creator][series], "Too many requested");
        
        uint256[] memory tokenIds = IERC721CreatorCore(creator).mintExtensionBatch(recipient, count);
        _updateIndexRanges(creator, series, tokenIds[0], count);
    }

    /**
     * @dev See {IManifoldERC721Edition-mint}.
     */
    function mint(address creator, uint256 series, address[] calldata recipients) external override nonReentrant creatorAdminRequired(creator) {
        require(recipients.length > 0, "Invalid amount requested");
        require(_totalSupply[creator][series]+recipients.length <= _maxSupply[creator][series], "Too many requested");
        
        uint256 startIndex = IERC721CreatorCore(creator).mintExtension(recipients[0]);
        for (uint256 i = 1; i < recipients.length;) {
            IERC721CreatorCore(creator).mintExtension(recipients[i]);
            unchecked{i++;}
        }
        _updateIndexRanges(creator, series, startIndex, recipients.length);
    }

    /**
     * @dev Update the index ranges, which is used to figure out the index from a tokenId
     */
    function _updateIndexRanges(address creator, uint256 series, uint256 startIndex, uint256 count) internal {
        IndexRange[] storage indexRanges = _indexRanges[creator][series];
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
        _totalSupply[creator][series] += count;
    }

    /**
     * @dev Index from tokenId
     */
    function _tokenSeriesAndIndex(address creator, uint256 tokenId) internal view returns(uint256, uint256) {
        require(_currentSeries[creator] > 0, "Invalid token");
        for (uint series=1; series <= _currentSeries[creator]; series++) {
            IndexRange[] memory indexRanges = _indexRanges[creator][series];
            uint256 offset;
            for (uint i = 0; i < indexRanges.length; i++) {
                IndexRange memory currentIndex = indexRanges[i];
                if (tokenId < currentIndex.startIndex) break;
                if (tokenId >= currentIndex.startIndex && tokenId < currentIndex.startIndex + currentIndex.count) {
                   return (series, tokenId - currentIndex.startIndex + offset);
                }
                offset += currentIndex.count;
            }
        }
        revert("Invalid token");
    }

}
