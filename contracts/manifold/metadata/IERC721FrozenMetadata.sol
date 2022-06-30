// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Manifold ERC721 Frozen Metadata interface
 */
interface IERC721FrozenMetadata {

    /**
     * @dev Mints a new token. Returns the tokenId
     */
    function mintToken(address creator, address recipient, string calldata tokenURI) external returns(uint256);
}
