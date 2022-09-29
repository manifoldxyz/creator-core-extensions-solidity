// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/**
 * Burn Redeem interface
 */
interface IERC1155BurnRedeem is IERC1155Receiver {
    struct BurnRedeemParameters {
        address burnTokenAddress;
        uint256 burnTokenId;
        uint32 burnAmount;
        uint32 redeemAmount;
        uint32 totalSupply;
        uint48 startDate;
        uint48 endDate;
        string uri;
    }

    struct BurnRedeem {
        address burnTokenAddress;
        uint256 burnTokenId;
        uint32 burnAmount;
        uint256 redeemTokenId;
        uint32 redeemAmount;
        uint32 redeemedCount;
        uint32 totalSupply;
        uint48 startDate;
        uint48 endDate;
        string uri;
    }

    struct BurnRedeemCallData {
        address creatorContractAddress;
        uint256 index;
        uint256 amount;
    }

    event BurnRedeemInitialized(address indexed creatorContract, uint224 indexed burnRedeemIndex, address initializer);
    event BurnRedeemMint(address indexed creatorContract, uint256 indexed burnRedeemIndex, uint256 amountMinted);

    /**
     * @notice initialize a new burn redeem, emit initialize event, and return the newly created index
     * @param creatorContractAddress    the creator contract the burn will mint redeem tokens for
     * @param burnRedeemParameters      the parameters which will affect the minting behavior of the burn redeem
     * @return                          the index of the newly created burn redeem
     */
    function initializeBurnRedeem(address creatorContractAddress, BurnRedeemParameters calldata burnRedeemParameters) external returns(uint256);

    /**
     * @notice update an existing burn redeem at index
     * @param creatorContractAddress    the creator contract corresponding to the burn redeem
     * @param index                     the index of the burn redeem in the list of creatorContractAddress' _burnRedeems
     * @param burnRedeemParameters      the parameters which will affect the minting behavior of the burn redeem
     */
    function updateBurnRedeem(address creatorContractAddress, uint256 index, BurnRedeemParameters calldata burnRedeemParameters) external;

    /**
     * @notice get the number of _burnRedeems initialized for a given creator contract
     * @param creatorContractAddress    the address of the creator contract
     * @return                          the number of _burnReedems initialized for this creator contract
     */
    function getBurnRedeemCount(address creatorContractAddress) external view returns(uint256);

    /**
     * @notice get a burn redeem corresponding to a creator contract and index
     * @param creatorContractAddress    the address of the creator contract
     * @param index                     the index of the burn redeem
     * @return                          the burn redeem object
     */
    function getBurnRedeem(address creatorContractAddress, uint256 index) external view returns(BurnRedeem memory);

    /**
     * @notice check if an wallet can participate in the provided burn redeem
     * @param wallet                    the wallet to check ownership against
     * @param creatorContractAddress    the creator contract address
     * @param index                     the index of the burn redeem for which we will mint
     * @return                          the max number of tokens the wallet can mint (0 if ineligible)
     */
    function isEligible(address wallet, address creatorContractAddress, uint256 index) external view returns(uint256);
}
