// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ERC721/ERC721CreatorExtensionApproveTransfer.sol";

import "../../libraries/SingleCreatorExtension.sol";

/**
 * Provide token enumeration functionality (Base Class. Use if you are using multiple inheritance where other contracts
 * already derive from either ERC721SingleCreatorExtension or ERC1155SingleCreatorExtension).
 *
 * IMPORTANT: You must call _activate in order for enumeration to work
 */
abstract contract ERC721OwnerEnumerableSingleCreatorBase is SingleCreatorBase, ERC721CreatorExtensionApproveTransfer {

    mapping(address => uint256) private _ownerBalance;
    mapping(address => mapping(uint256 => uint256)) private _tokensByOwner;
    mapping(uint256 => uint256) private _tokensIndex;

    /**
     * @dev must call this to activate enumeration capability
     */
    function _activate() internal {
        IERC721CreatorCore(_creator).setApproveTransferExtension(true);
    }

    /**
     * @dev Get the token for an owner by index
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual returns (uint256) {
        require(index < _ownerBalance[owner], "ERC721Enumerable: owner index out of bounds");
        return _tokensByOwner[owner][index];
    }

    /**
     * @dev Get the balance for the owner for this extension
     */
    function balanceOf(address owner) public view virtual returns(uint256) {
        return _ownerBalance[owner];
    }

    function approveTransfer(address from, address to, uint256 tokenId) external override returns (bool) {
        require(msg.sender == _creator, "Invalid caller");
        if (from != address(0) && from != to) {
            _removeTokenFromOwnerEnumeration(from, tokenId);
        }
        if (to != address(0) && to != from) {
            _addTokenToOwnerEnumeration(to, tokenId);
        }
        return true;
    }

    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = _ownerBalance[to];
        _tokensByOwner[to][length] = tokenId;
        _tokensIndex[tokenId] = length;
        _ownerBalance[to] += 1;
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _ownerBalance[from] - 1;
        uint256 tokenIndex = _tokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _tokensByOwner[from][lastTokenIndex];

            _tokensByOwner[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _tokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _tokensIndex[tokenId];
        delete _tokensByOwner[from][lastTokenIndex];
        _ownerBalance[from] -= 1;        
    }

}

/**
 * Provide token enumeration functionality (Extension)
 *
 * IMPORTANT: You must call _activate in order for enumeration to work
 */
abstract contract ERC721OwnerEnumerableSingleCreatorExtension is ERC721OwnerEnumerableSingleCreatorBase, ERC721SingleCreatorExtension {
    constructor(address creator) ERC721SingleCreatorExtension(creator) {}
}

