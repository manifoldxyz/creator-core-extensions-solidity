// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./IManifoldSingleCore.sol";

/**
 * Manifold ERC1155 Single Mint interface
 */
interface IManifoldERC1155Single is IManifoldSingleCore {

    struct Recipient {
        address recipient;
        uint256 amount;
    }

    /**
     * @dev Mint a new token
     */
    function mintNew(address creatorCore, uint256 instanceId, StorageProtocol storageProtocol, bytes calldata storageData, address[] calldata recipients, uint256[] calldata amounts) external;

    /**
     * @dev Mint an existing token
     */
    function mintExisting(address creatorCore, uint256 tokenId, address[] calldata recipients, uint256[] calldata amounts) external;

}
