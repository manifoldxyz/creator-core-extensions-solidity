// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "./IERC721FrozenMetadata.sol";

/**
 * Manifold ERC721 Frozen Metadata Implementation
 */
contract ERC721FrozenMetadata is IERC165, IERC721FrozenMetadata {
    /**
     * @dev Only allows approved admins to call the specified function
     */
    modifier creatorAdminRequired(address creator) {
        require(IAdminControl(creator).isAdmin(msg.sender), "Must be owner or admin of creator contract");
        _;
    }
    
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
        return interfaceId == type(IERC721FrozenMetadata).interfaceId;
    }
    
    /**
     * @dev See {IManifoldERC721FrozenMetadata-mintToken}.
     */
    function mintToken(address creator, address recipient, string calldata tokenURI) external override creatorAdminRequired(creator) returns(uint256) {
        require(bytes(tokenURI).length > 0, "Cannot mint blank string");
        
        return IERC721CreatorCore(creator).mintExtension(recipient, tokenURI);
    }
}
