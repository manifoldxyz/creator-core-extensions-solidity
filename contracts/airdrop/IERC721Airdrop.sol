// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * ERC721 Airdrop interface
 */
interface IERC721Airdrop {
    /**
     * @dev Airdrop nfts to recipients
     */
    function airdrop(address[] calldata recipients) external;

    /**
     * @dev Set the token uri prefix
     */
    function setTokenURIPrefix(string calldata prefix) external;
}
