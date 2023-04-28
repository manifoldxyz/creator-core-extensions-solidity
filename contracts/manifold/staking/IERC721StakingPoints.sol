// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./IStakingPointsCore.sol";
import "./StakingPointsCore.sol";

interface IERC721StakingPoints is IStakingPointsCore {

  /**
   * @notice initialize a new staking points, emit initialize event
   * @param creatorContractAddress    the address of the creator contract
   * @param instanceId                the instanceId of the staking points for the creator contract
   * @param stakingPointsParams       the stakingPointsParams object
   */
  function initializeStakingPoints(
    address creatorContractAddress,
    uint256 instanceId,
    StakingPointsParams calldata stakingPointsParams
  ) external;

}
