// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@manifoldxyz/creator-core-solidity/contracts/extensions/ERC721/IERC721CreatorExtensionApproveTransfer.sol";

/// @author: manifold.xyz

/**
 * Extension which prevents any filtering for ERC721
 */
abstract contract ERC721NoFilterer is IERC165 {

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override (IERC165) returns (bool) {
        return interfaceId == type(IERC721CreatorExtensionApproveTransfer).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @dev ERC721: Called by creator contract to approve a transfer
     */
    function approveTransfer(address, address, address, uint256) external pure returns (bool) {
        return true;
    }
}
