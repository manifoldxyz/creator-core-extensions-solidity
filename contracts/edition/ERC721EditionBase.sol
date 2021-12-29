// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/CreatorExtension.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "../libraries/single-creator/ERC721/ERC721SingleCreatorExtensionBase.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * ERC721 Edition Base Implementation
 */
abstract contract ERC721EditionBase is ERC721SingleCreatorExtensionBase, CreatorExtension, ICreatorExtensionTokenURI, ReentrancyGuard {
    using Strings for uint256;

    string constant internal _EDITION_TAG = '<EDITION>';
    string constant internal _TOTAL_TAG = '<TOTAL>';
    
    bool private _active;
    uint256 private _total;
    uint256 private _totalMinted;
    string[] private _uriParts;

    mapping(uint256 => uint256) private _tokenEdition;

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, CreatorExtension) returns (bool) {
        return interfaceId == type(ICreatorExtensionTokenURI).interfaceId || CreatorExtension.supportsInterface(interfaceId);
    }

    /**
     * @dev Initialize the Open Edition contract
     */
    function _initialize(address creator, string[] memory uriParts) internal {
        require(_creator == address(0), "Already initialized");
        super._setCreator(creator);
        _uriParts = uriParts;
    }

    /**
     * @dev Activate the edition with a maximum number of mints
     */
    function _activate(uint256 total) internal {
        require(!_active, "Already activated");
        _active = true;
        _total = total;
    }

    /**
     * @dev Mint tokens to a single recipient
     */
    function _mint(address recipient, uint256 count) internal nonReentrant {
        require(_active, "Not activated");
        require(_totalMinted+count <= _total, "Too many requested");
        for (uint256 i = 0; i < count; i++) {
            _tokenEdition[IERC721CreatorCore(_creator).mintExtension(recipient)] = _totalMinted + i + 1;
        }
        _totalMinted += count;
    }

    /**
     * @dev Mint tokens to a set of recipients
     */
    function _mint(address[] calldata recipients) internal nonReentrant {
        require(_active, "Not activated");
        require(_totalMinted+recipients.length <= _total, "Too many requested");
        for (uint256 i = 0; i < recipients.length; i++) {
            _tokenEdition[IERC721CreatorCore(_creator).mintExtension(recipients[i])] = _totalMinted + i + 1;
        }
        _totalMinted += recipients.length;
    }

    /**
     * @dev Update the URI data
     */
    function _updateURIParts(string[] memory uriParts) internal {
        _uriParts = uriParts;
    }

    /**
     * @dev Total tokens minted
     */
    function _mintCount() internal view returns(uint256) {
        return _totalMinted;
    }

    /**
     * @dev See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creator, uint256 tokenId) external view override returns (string memory) {
        require(creator == _creator && _tokenEdition[tokenId] != 0, "Invalid token");
        return _generateURI(tokenId);
    }

    function _generateURI(uint256 tokenId) private view returns(string memory) {
        bytes memory byteString;
        for (uint i = 0; i < _uriParts.length; i++) {
        if (_checkTag(_uriParts[i], _EDITION_TAG)) {
            byteString = abi.encodePacked(byteString, _tokenEdition[tokenId].toString());
        } else if (_checkTag(_uriParts[i], _TOTAL_TAG)) {
            byteString = abi.encodePacked(byteString, _total.toString());
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
