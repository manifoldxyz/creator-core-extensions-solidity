// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./IBurnRedeemCore.sol";

interface IERC1155BurnRedeem is IBurnRedeemCore {
    struct ExtendedConfig {
        uint256 redeemTokenId;
    }

    /**
     * @notice initialize a new burn redeem, emit initialize event, and return the newly created index
     * @param creatorContractAddress    the creator contract the burn will mint redeem tokens for
     * @param index                     the index of the burnRedeem in the mapping of creatorContractAddress' _burnRedeems
     * @param burnRedeemParameters      the parameters which will affect the minting behavior of the burn redeem
     */
    function initializeBurnRedeem(address creatorContractAddress, uint256 index, BurnRedeemParameters calldata burnRedeemParameters) external;

    /**
     * @notice update an existing burn redeem at index
     * @param creatorContractAddress    the creator contract corresponding to the burn redeem
     * @param index                     the index of the burn redeem in the list of creatorContractAddress' _burnRedeems
     * @param burnRedeemParameters      the parameters which will affect the minting behavior of the burn redeem
     */
    function updateBurnRedeem(address creatorContractAddress, uint256 index, BurnRedeemParameters calldata burnRedeemParameters) external;

    /**
     * @notice update an existing burn redeem at index
     * @param creatorContractAddress    the creator contract corresponding to the burn redeem
     * @param index                     the index of the burn redeem in the list of creatorContractAddress' _burnRedeems
     * @param storageProtocol           the storage protocol for the metadata
     * @param location                  the location of the metadata
     */
    function updateURI(address creatorContractAddress, uint256 index, StorageProtocol storageProtocol, string calldata location) external;
}
