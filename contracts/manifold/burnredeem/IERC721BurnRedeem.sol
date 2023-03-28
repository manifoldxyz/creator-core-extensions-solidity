// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./IBurnRedeemCore.sol";

interface IERC721BurnRedeem is IBurnRedeemCore {
    struct RedeemToken {
        uint224 instanceId;
        uint32 mintNumber;
    }

    /**
     * @notice initialize a new burn redeem, emit initialize event
     * @param creatorContractAddress    the creator contract the burn will mint redeem tokens for
     * @param instanceId                the instanceId of the burnRedeem for the creator contract
     * @param burnRedeemParameters      the parameters which will affect the minting behavior of the burn redeem
     * @param identicalTokenURI         whether or not the tokenURI is identical
     */
    function initializeBurnRedeem(address creatorContractAddress, uint256 instanceId, BurnRedeemParameters calldata burnRedeemParameters, bool identicalTokenURI) external;

    /**
     * @notice update an existing burn redeem
     * @param creatorContractAddress    the creator contract corresponding to the burn redeem
     * @param instanceId                the instanceId of the burnRedeem for the creator contract
     * @param burnRedeemParameters      the parameters which will affect the minting behavior of the burn redeem
     * @param identicalTokenURI         whether or not the tokenURI is identical
     */
    function updateBurnRedeem(address creatorContractAddress, uint256 instanceId, BurnRedeemParameters calldata burnRedeemParameters, bool identicalTokenURI) external;

    /**
     * @notice update an existing burn redeem
     * @param creatorContractAddress    the creator contract corresponding to the burn redeem
     * @param instanceId                the instanceId of the burnRedeem for the creator contract
     * @param storageProtocol           the storage protocol for the metadata
     * @param location                  the location of the metadata
     * @param identicalTokenURI         whether or not the URI's are supposed to be identical
     */
    function updateTokenURI(address creatorContractAddress, uint256 instanceId, StorageProtocol storageProtocol, string calldata location, bool identicalTokenURI) external;
}
