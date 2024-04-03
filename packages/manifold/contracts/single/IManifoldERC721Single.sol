// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./IManifoldSingleCore.sol";

/**
 * Manifold ERC721 Single Mint interface
 */
interface IManifoldERC721Single is IManifoldSingleCore {

    /**
     * @dev Mint a token
     */
    function mint(address creatorCore, uint256 instanceId, StorageProtocol storageProtocol, bytes calldata storageData, address recipient) external;

}
