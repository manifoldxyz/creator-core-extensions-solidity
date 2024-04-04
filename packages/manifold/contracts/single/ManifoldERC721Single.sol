// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "./IManifoldERC721Single.sol";

/**
 * Manifold ERC721 Single Mint Implementation
 */
contract ManifoldERC721Single is IManifoldERC721Single {

    /**
     * @dev Only allows approved admins to call the specified function
     */
    modifier creatorAdminRequired(address creator) {
        if (!IAdminControl(creator).isAdmin(msg.sender)) revert("Must be owner or admin of creator contract");
        _;
    }

    /**
     * @dev See {IManifoldERC721Single-mint}.
     */
    function mint(address creatorCore, uint256 expectedTokenId, string calldata uri, address recipient) external override creatorAdminRequired(creatorCore) {
        uint256 tokenId = IERC721CreatorCore(creatorCore).mintBase(recipient, uri);
        if (tokenId != expectedTokenId) {
            revert InvalidInput();
        }
    }
}
