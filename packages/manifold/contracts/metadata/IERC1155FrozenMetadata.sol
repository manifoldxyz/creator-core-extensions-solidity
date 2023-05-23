// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Manifold ERC1155 Frozen Metadata interface
 */
interface IERC1155FrozenMetadata {

    /**
     * @dev Mints a new token. Returns the tokenId
     */
    function mintTokenNew(address creator, address[] calldata to, uint256[] calldata amounts, string[] calldata uris) external returns(uint256[] memory);

    /**
     * @dev Mints more of an existing token. Returns the tokenId
     */
    function mintTokenExisting(address creator, address[] calldata to, uint256[] calldata tokenIds, uint256[] calldata amounts) external;
}
