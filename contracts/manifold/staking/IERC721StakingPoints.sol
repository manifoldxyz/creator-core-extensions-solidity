// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./IStakingPoints.sol";
import "./StakingPoints.sol";

interface IERC721StakingPoints is IStakingPoints, StakingPoints {
  /**
   * @notice initialize a new staking points, emit initialize event
   * @param creatorContractAddress    t
   * @param instanceId                t
   * @param stakingPointsParams       t
   * @param identicalTokenURI         t
   */
  function initializeStakingPoints(
    address creatorContractAddress,
    uint256 instanceId,
    bool identicalTokenURI,
    StakingPointsParams calldata stakingPointsParams
  ) external;

  //   function updateStakingPoints(address creatorContractAddress, uint256 instanceId, Staking);

  /**
   * @notice update tokenURI parameters for an existing claim at instanceId
   * @param creatorContractAddress    the creator contract corresponding to the claim
   * @param instanceId                the claim instanceId for the creator contract
   * @param storageProtocol           the new storage protocol
   * @param identical                 the new value of identical
   * @param location                  the new location
   */
  function updateTokenURIParams(
    address creatorContractAddress,
    uint256 instanceId,
    StorageProtocol storageProtocol,
    bool identical,
    string calldata location
  ) external;
}
