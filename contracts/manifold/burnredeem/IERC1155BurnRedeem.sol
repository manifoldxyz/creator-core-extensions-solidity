// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./IBurnRedeemCore.sol";

interface IERC1155BurnRedeem is IBurnRedeemCore {
    struct ExtendedConfig {
        uint256 redeemTokenId;
    }

    /**
     * @notice initialize a new burn redeem, emit initialize event
     * @param creatorContractAddress    the creator contract the burn will mint redeem tokens for
     * @param instanceId                the instanceId of the burnRedeem for the creator contract
     * @param burnRedeemParameters      the parameters which will affect the minting behavior of the burn redeem
     */
    function initializeBurnRedeem(address creatorContractAddress, uint256 instanceId, BurnRedeemParameters calldata burnRedeemParameters) external;

    /**
     * @notice update an existing burn redeem
     * @param creatorContractAddress    the creator contract corresponding to the burn redeem
     * @param instanceId                the instanceId of the burnRedeem for the creator contract
     * @param burnRedeemParameters      the parameters which will affect the minting behavior of the burn redeem
     */
    function updateBurnRedeem(address creatorContractAddress, uint256 instanceId, BurnRedeemParameters calldata burnRedeemParameters) external;

    /**
     * @notice update an existing burn redeem
     * @param creatorContractAddress    the creator contract corresponding to the burn redeem
     * @param instanceId                the instanceId of the burnRedeem for the creator contract
     * @param storageProtocol           the storage protocol for the metadata
     * @param location                  the location of the metadata
     */
    function updateURI(address creatorContractAddress, uint256 instanceId, StorageProtocol storageProtocol, string calldata location) external;

    /**
     * @notice get the redeem token ID for a burn redeem
     */
    function getBurnRedeemToken(address creatorContractAddress, uint256 instanceId) external view returns (uint256);
}
