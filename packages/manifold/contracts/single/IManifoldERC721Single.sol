// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Manifold ERC721 Single Mint interface
 */
interface IManifoldERC721Single {

    error InvalidInput();
    error InvalidToken();

    enum StorageProtocol { INVALID, NONE, ARWEAVE, IPFS }

    /**
     * @dev Mint a token
     */
    function mint(address creatorCore, uint256 instanceId, StorageProtocol storageProtocol, bytes calldata storageData, address recipient) external;

    /**
     * @dev Check if token exists
     */
    function exists(address creatorCore, uint256 instanceId) external view returns (bool);

    /**
     * @dev Set the token uri prefix
     */
    function setTokenURI(address creatorCore, uint256 instanceId, StorageProtocol storageProtocol, bytes calldata storageData) external;
}
