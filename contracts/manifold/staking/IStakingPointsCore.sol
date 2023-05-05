// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

// import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/**
 * StakingPointsCore interface
 */
interface IStakingPointsCore is IERC165, IERC721Receiver {
  /** TODO: CONFIRM STRUCTS */

  struct StakedToken {
    uint256 tokenId;
    address contractAddress;
    address stakerAddress;
    uint256 timeStaked;
    uint256 timeUnstaked;
    uint256 tokenIdx;
  }

  struct StakedTokenIdx {
    uint256 tokenIdx;
    address stakerAddress;
  }

  struct StakedTokenParams {
    address tokenAddress;
    uint256 tokenId;
  }

  struct Staker {
    uint256 pointsRedeemed;
    uint256 stakerIdx;
    StakedToken[] stakersTokens;
    address stakerAddress;
  }

  struct StakingRule {
    address tokenAddress;
    uint256 pointsRatePerDay;
    uint256 startTime;
    uint256 endTime;
  }

  struct StakingPoints {
    address payable paymentReceiver;
    uint8 contractVersion;
    StakingRule[] stakingRules;
    Staker[] stakers;
  }

  struct StakingPointsParams {
    address payable paymentReceiver;
    StakingRule[] stakingRules;
  }

  event StakingPointsInitialized(address indexed creatorContract, uint256 indexed instanceId, address initializer);
  event StakingPointsUpdated(address indexed creatorContract, uint256 indexed instanceId, address updater);
  event TokensStaked(address indexed creatorContract, uint256 indexed instanceId, StakedToken[] stakedTokens, address owner);
  event TokensUnstaked(address indexed creatorContract, uint256 indexed instanceId, StakedToken[] stakedTokens, address owner);
  event PointsDistributed(address indexed creatorContract, uint256 indexed instanceId, address user, uint256 amount);

  /**
   * @notice stake tokens
   * @param creatorContractAddress    the address of the creator contract
   * @param instanceId                the staking points instanceId for the creator contract
   * @param stakingTokens             a list of tokenIds with token contract addresses
   */
  function stakeTokens(
    address creatorContractAddress,
    uint256 instanceId,
    StakedTokenParams[] calldata stakingTokens
  ) external;

  /**
   * @notice unstake tokens
   * @param creatorContractAddress    the address of the creator contract
   * @param instanceId                the staking points instanceId for the creator contract
   * @param unstakingTokens           a list of tokenIds with token contract addresses
   */
  function unstakeTokens(
    address creatorContractAddress,
    uint256 instanceId,
    StakedTokenParams[] calldata unstakingTokens
  ) external;

  /**
   * @notice get a staking points instance corresponding to a creator contract and instanceId
   * @param creatorContractAddress    the address of the creator contract
   * @param instanceId                the staking points instanceId for the creator contract
   * @return StakingPoints            the staking points object
   */
  function getStakingPointsInstance(
    address creatorContractAddress,
    uint256 instanceId
  ) external view returns (StakingPoints memory);

  /**
   * @notice recover a token that was sent to the contract without safeTransferFrom
   * @param tokenAddress              the address of the token contract
   * @param tokenId                   the id of the token
   * @param destination               the address to send the token to
   */
  function recoverERC721(address tokenAddress, uint256 tokenId, address destination) external;

  /**
   * @notice set the Manifold Membership contract address
   * @param addr                      the address of the Manifold Membership contract
   */
  function setMembershipAddress(address addr) external;
}
