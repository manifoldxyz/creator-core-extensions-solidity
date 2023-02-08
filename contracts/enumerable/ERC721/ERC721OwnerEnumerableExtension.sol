// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ERC721/ERC721CreatorExtensionApproveTransfer.sol";

/**
 * Provide token enumeration functionality
 *
 * IMPORTANT: You must call _activate for each creator contract you want enumeration to work for
 */
abstract contract ERC721OwnerEnumerableExtension is ERC721CreatorExtensionApproveTransfer {

    mapping (address => mapping(address => uint256)) private _creatorOwnerBalance;
    mapping (address => mapping(address => mapping(uint256 => uint256))) private _creatorTokensByOwner;
    mapping (address => mapping(uint256 => uint256)) private _creatorTokensIndex;

    /**
     * @dev must call this to activate enumeration capability
     */
    function _activate(address creator) internal {
        IERC721CreatorCore(creator).setApproveTransferExtension(true);
    }

    /**
     * @dev Get the token for an owner by index (for a given creator contract this extension mints to)
     */
    function tokenOfOwnerByIndex(address creator, address owner, uint256 index) public view virtual returns (uint256) {
        require(index < _creatorOwnerBalance[creator][owner], "ERC721Enumerable: owner index out of bounds");
        return _creatorTokensByOwner[creator][owner][index];
    }

    /**
     * @dev Get the balance for the owner for this extension (for a given creator contract this extension mints to)
     */
    function balanceOf(address creator, address owner) public view virtual returns(uint256) {
        return _creatorOwnerBalance[creator][owner];
    }

    function approveTransfer(address, address from, address to, uint256 tokenId) external override returns (bool) {
        if (from != address(0) && from != to) {
            _removeTokenFromOwnerEnumeration(from, tokenId);
        }
        if (to != address(0) && to != from) {
            _addTokenToOwnerEnumeration(to, tokenId);
        }
        return true;
    }

    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = _creatorOwnerBalance[msg.sender][to];
        _creatorTokensByOwner[msg.sender][to][length] = tokenId;
        _creatorTokensIndex[msg.sender][tokenId] = length;
        _creatorOwnerBalance[msg.sender][to] += 1;
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _creatorOwnerBalance[msg.sender][from] - 1;
        uint256 tokenIndex = _creatorTokensIndex[msg.sender][tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _creatorTokensByOwner[msg.sender][from][lastTokenIndex];

            _creatorTokensByOwner[msg.sender][from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _creatorTokensIndex[msg.sender][lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _creatorTokensIndex[msg.sender][tokenId];
        delete _creatorTokensByOwner[msg.sender][from][lastTokenIndex];
        _creatorOwnerBalance[msg.sender][from] -= 1;        
    }

}