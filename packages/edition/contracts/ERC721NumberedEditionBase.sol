// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/CreatorExtension.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "../libraries/single-creator/ERC721/ERC721SingleCreatorExtensionBase.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./IERC721NumberedEdition.sol";
import "./ERC721EditionBase.sol";

/**
 * ERC721 Numbered Edition Base Implementation
 */
abstract contract ERC721NumberedEditionBase is ERC721EditionBase, IERC721NumberedEdition {
    using Strings for uint256;

    string constant internal _EDITION_TAG = '<EDITION>';
    string constant internal _TOTAL_TAG = '<TOTAL>';    
    string constant internal _MAX_TAG = '<MAX>'; 
    string[] private _uriParts;

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721EditionBase) returns (bool) {
        return interfaceId == type(IERC721NumberedEdition).interfaceId || ERC721EditionBase.supportsInterface(interfaceId);
    }

    /**
     * @dev Initialize the Open Edition contract
     */
    function _initialize(address creator, uint256 maxSupply_, string[] memory uriParts) internal {
        require(_creator == address(0), "Already initialized");
        super._initialize(creator, maxSupply_);
        _uriParts = uriParts;
    }

    /**
     * @dev Update the URI data
     */
    function _updateURIParts(string[] memory uriParts) internal {
        _uriParts = uriParts;
    }

    /**
     * @dev See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creator, uint256 tokenId) external view override returns (string memory) {
        return _generateURI(_tokenIndex(creator, tokenId));
    }

    function _generateURI(uint256 tokenIndex) private view returns(string memory) {
        bytes memory byteString;
        for (uint i = 0; i < _uriParts.length; i++) {
            if (_checkTag(_uriParts[i], _EDITION_TAG)) {
                byteString = abi.encodePacked(byteString, (tokenIndex+1).toString());
            } else if (_checkTag(_uriParts[i], _TOTAL_TAG)) {
                byteString = abi.encodePacked(byteString, _totalSupply.toString());
            } else if (_checkTag(_uriParts[i], _MAX_TAG)) {
                byteString = abi.encodePacked(byteString, _maxSupply.toString());
            } else {
                byteString = abi.encodePacked(byteString, _uriParts[i]);
            }
        }
        return string(byteString);
    }

    function _checkTag(string storage a, string memory b) private pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
    
}
