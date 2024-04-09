// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "./IManifoldERC1155Single.sol";

/**
 * Manifold ERC1155 Single Mint Implementation
 */
contract ManifoldERC1155Single is IManifoldERC1155Single {

    /**
     * @dev Only allows approved admins to call the specified function
     */
    modifier creatorAdminRequired(address creator) {
        if (!IAdminControl(creator).isAdmin(msg.sender)) revert("Must be owner or admin of creator contract");
        _;
    }

    /**
     * @dev See {IManifoldERC1155Single-mintNew}.
     */
    function mint(address creatorCore, uint256 expectedTokenId, string calldata uri, address[] calldata recipients, uint256[] calldata amounts) external override creatorAdminRequired(creatorCore) {
        string[] memory uris = new string[](1);
        uris[0] = uri;
        uint256[] memory tokenIds = IERC1155CreatorCore(creatorCore).mintBaseNew(recipients, amounts, uris);
        if (tokenIds.length != 1 || tokenIds[0] != expectedTokenId) {
            revert InvalidInput();
        }
    }
}
