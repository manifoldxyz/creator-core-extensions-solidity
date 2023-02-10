// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "./IERC1155FrozenMetadata.sol";

/**
 * Manifold ERC1155 Frozen Metadata Implementation
 */
contract ERC1155FrozenMetadata is IERC165, IERC1155FrozenMetadata {
    /**
     * @dev Only allows approved admins to call the specified function
     */
    modifier creatorAdminRequired(address creator) {
        require(IAdminControl(creator).isAdmin(msg.sender), "Must be owner or admin of creator contract");
        _;
    }
    
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
        return interfaceId == type(IERC1155FrozenMetadata).interfaceId;
    }
    
    /**
     * @dev See {IManifoldERC1155FrozenMetadata-mintTokenNew}.
     */
    function mintTokenNew(address creator, address[] calldata to, uint256[] calldata amounts, string[] calldata uris) external override creatorAdminRequired(creator) returns(uint256[] memory) {
        for (uint i; i < uris.length;) {
            require(bytes(uris[i]).length > 0, "Cannot mint blank string");
            unchecked { ++i; }
        }
        return IERC1155CreatorCore(creator).mintExtensionNew(to, amounts, uris);
    }

    /**
     * @dev See {IManifoldERC1155FrozenMetadata-mintTokenExisting}.
     */
    function mintTokenExisting(address creator, address[] calldata to, uint256[] calldata tokenIds, uint256[] calldata amounts) external override creatorAdminRequired(creator) {
        IERC1155CreatorCore(creator).mintExtensionExisting(to, tokenIds, amounts);
    }
}
