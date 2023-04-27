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
   */
  function initializeStakingPoints(
    address creatorContractAddress,
    uint256 instanceId,
    StakingPointsParams calldata stakingPointsParams
  ) external;

}
