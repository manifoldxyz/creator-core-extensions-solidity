// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @author: manifold.xyz

/**
 * @dev CollectibleBase Interface
 */
interface ICollectibleCore is IERC165 {
  struct ActivationParameters {
    uint48 startTime;
    uint48 duration;
    uint48 presaleInterval;
    uint48 claimStartTime;
    uint48 claimEndTime;
  }

  struct InitializationParameters {
    bool useDynamicPresalePurchaseLimit;
    uint16 transactionLimit;
    uint16 purchaseMax;
    uint16 purchaseRemaining;
    uint16 purchaseLimit;
    uint16 presalePurchaseLimit;
    uint256 purchasePrice;
    uint256 presalePurchasePrice;
    address signingAddress;
    address payable paymentReceiver;
  }


  struct ModifyInitializationParameters {
    bool useDynamicPresalePurchaseLimit;
    uint16 transactionLimit;
    uint16 purchaseMax;
    uint16 purchaseRemaining;
    uint16 purchaseLimit;
    uint16 presalePurchaseLimit;
    uint256 purchasePrice;
    uint256 presalePurchasePrice;
  }

  struct CollectibleInstance {
    bool isActive;
    bool useDynamicPresalePurchaseLimit;
    bool isTransferLocked;
    uint16 transactionLimit;
    uint16 purchaseMax;
    uint16 purchaseRemaining;
    uint16 purchaseLimit;
    uint16 presalePurchaseLimit;
    uint16 purchaseCount;
    uint48 startTime;
    uint48 endTime;
    uint48 presaleInterval;
    uint48 claimStartTime;
    uint48 claimEndTime;
    uint256 purchasePrice;
    uint256 presalePurchasePrice;
    string baseURI;
    address payable paymentReceiver;
  }

  event CollectibleInitialized(address creatorContractAddress, uint256 instanceId, address initializer);

  event CollectibleActivated(
    address creatorContractAddress,
    uint256 instanceId,
    uint48 startTime,
    uint48 endTime,
    uint48 presaleInterval,
    uint48 claimStartTime,
    uint48 claimEndTime
  );

  event CollectibleDeactivated(address creatorContractAddress, uint256 instanceId);

  /**
   * @notice get a burn redeem corresponding to a creator contract and index
   * @param creatorContractAddress    the address of the creator contract
   * @param index                     the index of the burn redeem
   * @return CollectibleInstsance               the burn redeem object
   */
  function getCollectible(
    address creatorContractAddress,
    uint256 index
  ) external view returns (CollectibleInstance memory);

  /**
   * @dev Check if nonce has been used
   * @param creatorContractAddress    the creator contract address
   * @param instanceId                the index of the claim for which we will mint
   */
  function nonceUsed(address creatorContractAddress, uint256 instanceId, bytes32 nonce) external view returns (bool);

  /**
   * @dev Activate the contract
   * @param creatorContractAddress    the creator contract the claim will mint tokens for
   * @param instanceId                the index of the claim in the list of creatorContractAddress' _claims
   * @param activationParameters      the sale start time
   */
  function activate(
    address creatorContractAddress,
    uint256 instanceId,
    ActivationParameters calldata activationParameters
  ) external;

  /**
   * @dev Deactivate the contract
   * @param creatorContractAddress    the creator contract the claim will mint tokens for
   * @param instanceId                the index of the claim in the list of creatorContractAddress' _claims
   */
  function deactivate(address creatorContractAddress, uint256 instanceId) external;

  /**
   * @notice Set the Manifold Membership address
   */
  function setMembershipAddress(address membershipAddress) external;

  /**
   * @notice withdraw Manifold fee proceeds from the contract
   * @param recipient                 recepient of the funds
   * @param amount                    amount to withdraw in Wei
   */
  function withdraw(address payable recipient, uint256 amount) external;

  /**
   * @notice initialize a new burn redeem, emit initialize event, and return the newly created index
   * @param creatorContractAddress    the creator contract the burn will mint redeem tokens for
   * @param instanceId                the id of the multi-asssetclaim in the mapping of creatorContractAddress <-> instance id
   * @param initializationParameters  initial claim parameters
   */
  function initializeCollectible(
    address creatorContractAddress,
    uint256 instanceId,
    InitializationParameters calldata initializationParameters
  ) external;

  /**
   * Allows a handful of initial variables to be modified
   * @param creatorContractAddress    the creator contract the burn will mint redeem tokens for
   * @param instanceId                the id of the multi-asssetclaim in the mapping of creatorContractAddress <-> instance id
   * @param initializationParameters  initial claim parameters
   */
  function modifyInitializationParameters(
    address creatorContractAddress,
    uint256 instanceId,
    ModifyInitializationParameters calldata initializationParameters
  ) external;
}
