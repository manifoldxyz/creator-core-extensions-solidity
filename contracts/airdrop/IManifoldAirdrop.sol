// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Manifold airdrop extension interface
 */
interface IManifoldAirdrop {
    /**
     * @dev Enable/Disable this airdrop function
     */
    function setEnabled(bool enabled_) external;

    /**
     * @dev Check whether or not the creator contract has registered this extension
     */
    function isRegistered(address tokenAddress) external view returns(bool);

    /**
     * @dev Airdrop nfts to recipients (same asset)
     */
    function airdrop(address tokenAddress, address[] calldata recipients, string memory tokenURI) external;

    /**
     * @dev Airdrop nfts to recipients
     */
    function airdrop(address tokenAddress, address[] calldata recipients, string[] memory tokenURIs) external;
}