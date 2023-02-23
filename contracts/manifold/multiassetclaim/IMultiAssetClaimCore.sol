// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @author: manifold.xyz

/**
 * @dev MultiAssetClaimBase Interface
 */
interface IMultiAssetClaimCore is IERC165 {
  struct ActivationParameters {
    uint256 startTime;
    uint256 duration;
    uint256 presaleInterval;
    uint256 claimStartTime;
    uint256 claimEndTime;
  }

  struct InitializationParameters {
    address signingAddress;
    address payable paymentReceiver;
    uint16 transactionLimit;
    uint16 purchaseMax;
    uint16 purchaseRemaining;
    uint256 purchasePrice;
    uint16 purchaseLimit;
    uint256 presalePurchasePrice;
    uint16 presalePurchaseLimit;
    bool useDynamicPresalePurchaseLimit;
  }

  struct MultiAssetClaimInstance {
    string baseURI;
    address payable paymentReceiver;
    bool isTransferLocked;
    uint16 transactionLimit;
    uint16 purchaseMax;
    uint16 purchaseRemaining;
    uint256 purchasePrice;
    uint16 purchaseLimit;
    uint256 presalePurchasePrice;
    uint16 presalePurchaseLimit;
    uint16 purchaseCount;
    bool isActive;
    uint256 startTime;
    uint256 endTime;
    uint256 presaleInterval;
    uint256 claimStartTime;
    uint256 claimEndTime;
    bool useDynamicPresalePurchaseLimit;
  }

  event MultiAssetClaimInitialized(address creatorContractAddress, uint256 instanceId, address initializer);

  event MultiAssetClaimActivated(
    address creatorContractAddress,
    uint256 instanceId,
    uint256 startTime,
    uint256 endTime,
    uint256 presaleInterval,
    uint256 claimStartTime,
    uint256 claimEndTime
  );

  event MultiAssetClaimDeactivated(address creatorContractAddress, uint256 instanceId);

  /**
   * @notice get a burn redeem corresponding to a creator contract and index
   * @param creatorContractAddress    the address of the creator contract
   * @param index                     the index of the burn redeem
   * @return MultiAssetClaimInstsance               the burn redeem object
   */
  function getMultiAssetClaim(
    address creatorContractAddress,
    uint256 index
  ) external view returns (MultiAssetClaimInstance memory);

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
  function initializeMultiAssetClaim(
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
    InitializationParameters calldata initializationParameters
  ) external;
}
