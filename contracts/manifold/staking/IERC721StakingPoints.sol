// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./IStakingPointsCore.sol";
import "./StakingPointsCore.sol";

interface IERC721StakingPoints is IStakingPointsCore {

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
   * @notice update tokenURI parameters for an existing stakingPoints at instanceId
   * @param creatorContractAddress    the creator contract corresponding to the stakingPoints
   * @param instanceId                the stakingPoints instanceId for the creator contract
   * @param storageProtocol           the new storage protocol
   * @param location                  the new location
   */
  function updateTokenURIParams(
    address creatorContractAddress,
    uint256 instanceId,
    StorageProtocol storageProtocol,
    string calldata location
  ) external;
}
