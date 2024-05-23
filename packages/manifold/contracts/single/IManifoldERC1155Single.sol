// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Manifold ERC1155 Single Mint interface
 */
interface IManifoldERC1155Single {

    error InvalidInput();

    /**
     * @dev Mint a new token
     */
    function mint(address creatorCore, uint256 expectedTokenId, string calldata uri, address[] calldata recipients, uint256[] calldata amounts) external;
}
