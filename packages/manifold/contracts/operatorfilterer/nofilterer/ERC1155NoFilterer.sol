// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@manifoldxyz/creator-core-solidity/contracts/extensions/ERC1155/IERC1155CreatorExtensionApproveTransfer.sol";

/// @author: manifold.xyz

/**
 * Extension which prevents any filtering for ERC1155
 */
abstract contract ERC1155NoFilterer is IERC165 {

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override (IERC165) returns (bool) {
        return interfaceId == type(IERC1155CreatorExtensionApproveTransfer).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @dev ERC1155: Called by creator contract to approve a transfer
     */
    function approveTransfer(address, address, address, uint256[] calldata, uint256[] calldata) external pure returns (bool) {
        return true;
    }
}
