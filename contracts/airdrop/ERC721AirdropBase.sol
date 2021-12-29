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
 * Airdrop ERC721 tokens to a set of addresses
 */
abstract contract ERC721AirdropBase is ERC721SingleCreatorExtensionBase, CreatorExtension, ICreatorExtensionTokenURI, ReentrancyGuard {
    using Strings for uint256;

    string private _tokenPrefix;
    uint256 private _tokensMinted;
    mapping(uint256 => uint256) private _tokenEdition;

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, CreatorExtension) returns (bool) {
        return interfaceId == type(ICreatorExtensionTokenURI).interfaceId || CreatorExtension.supportsInterface(interfaceId);
    }

    function _initialize(address creator, string memory prefix) internal {
      require(_creator == address(0), "Already initialized");
      _setCreator(creator);
      _tokenPrefix = prefix;
    }

    /**
     * @dev Airdrop tokens to recipients
     */
    function _airdrop(address[] calldata recipients) internal nonReentrant {
        for (uint i = 0; i < recipients.length; i++) {
            _tokenEdition[IERC721CreatorCore(_creator).mintExtension(recipients[i])] = _tokensMinted + i + 1;
        }
        _tokensMinted += recipients.length;
    }

    /**
     * Set the token URI prefix
     */
    function _setTokenURIPrefix(string calldata prefix) internal {
        _tokenPrefix = prefix;
    }

    /**
     * @dev See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creator, uint256 tokenId) external view override returns (string memory) {
        require(creator == _creator && _tokenEdition[tokenId] != 0, "Invalid token");
        return  string(abi.encodePacked(_tokenPrefix, _tokenEdition[tokenId].toString()));
    }
    
}
