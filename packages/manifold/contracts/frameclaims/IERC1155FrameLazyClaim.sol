// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./IFrameLazyClaim.sol";

/**
 * Lazy Claim interface
 */
interface IERC1155FrameLazyClaim is IFrameLazyClaim {

    struct ClaimParameters {
        StorageProtocol storageProtocol;
        string location;
        address payable paymentReceiver;
    }

    struct Claim {
        StorageProtocol storageProtocol;
        string location;
        uint256 tokenId;
        address payable paymentReceiver;
    }

    /**
     * @notice initialize a new claim, emit initialize event
     * @param creatorContractAddress    the creator contract the claim will mint tokens for
     * @param instanceId                the claim instanceId for the creator contract
     * @param claimParameters           the parameters which will affect the minting behavior of the claim
     */
    function initializeClaim(address creatorContractAddress, uint256 instanceId, ClaimParameters calldata claimParameters) external;

    /**
     * @notice update tokenURI parameters for an existing claim at instanceId
     * @param creatorContractAddress    the creator contract corresponding to the claim
     * @param instanceId                the claim instanceId for the creator contract
     * @param storageProtocol           the new storage protocol
     * @param location                  the new location
     */
    function updateTokenURIParams(address creatorContractAddress, uint256 instanceId, StorageProtocol storageProtocol, string calldata location) external;

    /**
     * @notice extend tokenURI parameters for an existing claim at instanceId.  Must have NONE StorageProtocol
     * @param creatorContractAddress    the creator contract corresponding to the claim
     * @param instanceId                the claim instanceId for the creator contract
     * @param locationChunk             the additional location chunk
     */
    function extendTokenURI(address creatorContractAddress, uint256 instanceId, string calldata locationChunk) external;

    /**
     * @notice get a claim corresponding to a creator contract and instanceId
     * @param creatorContractAddress    the address of the creator contract
     * @param instanceId                the claim instanceId for the creator contract
     * @return                          the claim object
     */
    function getClaim(address creatorContractAddress, uint256 instanceId) external view returns(Claim memory);

    /**
     * @notice get a claim corresponding to a token
     * @param creatorContractAddress    the address of the creator contract
     * @param tokenId                   the tokenId of the claim
     * @return                          the claim instanceId and claim object
     */
    function getClaimForToken(address creatorContractAddress, uint256 tokenId) external view returns(uint256, Claim memory);

}
