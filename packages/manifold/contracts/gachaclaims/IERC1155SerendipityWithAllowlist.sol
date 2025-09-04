// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./ISerendipityAllowlist.sol";

/**
 * @title ERC1155 Serendipity With Allowlist Interface
 * @notice Interface for ERC1155 Serendipity contract with allowlist functionality
 */
interface IERC1155SerendipityWithAllowlist is ISerendipityAllowlist {
    // ========== EVENTS ==========
    
    event SerendipityAllowlistClaimInitialized(
        address indexed creatorContract,
        uint256 indexed instanceId,
        address initializer
    );
    
    event SerendipityAllowlistClaimUpdated(
        address indexed creatorContract,
        uint256 indexed instanceId
    );
    
    event SerendipityAllowlistMintReserved(
        address indexed creatorContract,
        uint256 indexed instanceId,
        address indexed collector,
        uint32 mintCount,
        uint32[] mintIndices
    );
    
    // ========== FUNCTIONS ==========
    
    /**
     * @notice Get claim for a specific token
     * @param creatorContractAddress    the address of the creator contract
     * @param tokenId                   the token ID
     * @return instanceId               the claim instanceId for the token
     * @return claim                    the allowlist claim object for the token
     */
    function getAllowlistClaimForToken(
        address creatorContractAddress,
        uint256 tokenId
    ) external view returns (uint256 instanceId, AllowlistClaim memory claim);
    
    /**
     * @notice Update token URI parameters for an allowlist claim
     * @param creatorContractAddress    the creator contract address
     * @param instanceId                the claim instanceId for the creator contract
     * @param storageProtocol           the new storage protocol
     * @param location                  the new location
     */
    function updateAllowlistTokenURIParams(
        address creatorContractAddress,
        uint256 instanceId,
        StorageProtocol storageProtocol,
        string calldata location
    ) external;
}