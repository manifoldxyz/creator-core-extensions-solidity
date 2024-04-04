// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Manifold ERC721 Single Mint interface
 */
interface IManifoldERC721Single {

    error InvalidInput();

    /**
     * @dev Mint a token
     */
    function mint(address creatorCore, uint256 expectedTokenId, string calldata uri, address recipient) external;
}
