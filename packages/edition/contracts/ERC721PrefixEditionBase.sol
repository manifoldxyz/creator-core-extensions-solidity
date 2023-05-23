// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/CreatorExtension.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "../libraries/single-creator/ERC721/ERC721SingleCreatorExtensionBase.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./IERC721PrefixEdition.sol";
import "./ERC721EditionBase.sol";

/**
 * ERC721 Prefix Edition Base Implementation
 */
abstract contract ERC721PrefixEditionBase is ERC721EditionBase, IERC721PrefixEdition {
    using Strings for uint256;

    string private _tokenPrefix;
    
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721EditionBase) returns (bool) {
        return interfaceId == type(IERC721PrefixEdition).interfaceId || ERC721EditionBase.supportsInterface(interfaceId);
    }

    /**
     * @dev Initialize the Open Edition contract
     */
    function _initialize(address creator, uint256 maxSupply_, string memory prefix) internal {
        require(_creator == address(0), "Already initialized");
        super._initialize(creator, maxSupply_);
        _tokenPrefix = prefix;
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
        return string(abi.encodePacked(_tokenPrefix, (_tokenIndex(creator, tokenId)+1).toString()));
    }
}
