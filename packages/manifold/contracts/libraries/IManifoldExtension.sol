// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IManifoldExtension
 * @notice Interface for Manifold extensions. It defines all the events that an extension will emit whenever a token is minted.
 */
interface IManifoldExtension {
    event InstanceMint(
        address creatorContractAddress,
        uint256 indexed instanceId,
        address minter,
        address indexed tokenAddress,
        uint256 indexed tokenId,
        uint256 quantity
    );
    event InstanceBatchMint(
        address creatorContractAddress,
        uint256 indexed instanceId,
        address minter,
        address indexed tokenAddress,
        uint256[] indexed tokenIds,
        uint256[] quantity
    );
    event InstanceRangeMint(
        address creatorContractAddress,
        uint256 indexed instanceId,
        address minter,
        address indexed tokenAddress,
        uint256 fromTokenId,
        uint256 toTokenId,
        uint256 quantity
    );
}
