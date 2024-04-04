// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Manifold Single Mint interface
 */
interface IManifoldSingleCore {

    error InvalidInput();
    error InvalidToken();

    enum StorageProtocol { INVALID, NONE, ARWEAVE, IPFS }

    /**
     * @dev Check if token exists
     */
    function exists(address creatorCore, uint256 instanceId) external view returns (bool);

    /**
     * @dev Set the token uri prefix
     */
    function setTokenURI(address creatorCore, uint256 instanceId, StorageProtocol storageProtocol, bytes calldata storageData) external;

    /**
     * @dev Get the instance id for a given token
     */
    function getInstanceId(address creatorCore, uint256 tokenId) external view returns (uint256);

}
