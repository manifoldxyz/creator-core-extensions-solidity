// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/**
 * StakingPoints interface
 */
interface IStakingPoints is IERC165, IERC721Receiver, IERC1155Receiver {
  enum StorageProtocol {
    INVALID,
    NONE,
    ARWEAVE,
    IPFS
  }

  enum TokenSpec {
    INVALID,
    ERC721,
    ERC1155
  }

  /** TODO: CONFIRM STRUCTS */
  struct StakedToken {
    uint256 id;
    uint256 tokenId;
    address tokenAddress;
    uint256 timeStamp;
  }

  struct StakingRule {
    address tokenAddress;
    TokenSpec tokenSpec;
    uint256 pointsRate;
    uint256 timeUnit;
    uint256 startTime;
    uint256 endTime;
  }

  struct StakingPoints {
    address payable paymentReceiver;
    StorageProtocol storageProtocol;
    uint8 contractVersion;
    string location;
    StakingRule[] stakingRules;
  }

  struct StakingPointsParams {
    address payable paymentReceiver;
    StorageProtocol storageProtocol;
    string location;
    StakingRule[] stakingRules;
  }

  struct StakingTokenParam {
    address tokenAddress;
    uint256 tokenId;
  }

  //** TODO: EVENTS */

  event StakingPointsInitialized(address indexed creatorContract, uint256 indexed instanceId, address initializer);
  event StakingPointsUpdated(address indexed creatorContract, uint256 indexed instanceId);
  event TokensStaked();
  event TokensUnstaked();
  event PointsDistributed();

  /**
   * @notice stake tokens
   * @param owner                     the address of the token owner
   * @param stakingTokens             a list of tokenIds with token contract addresses
   */
  function stakeTokens(address owner, StakingTokenParam[] calldata stakingTokens) external payable;

  /**
   * @notice unstake tokens
   * @param owner                     the address of the token owner
   * @param unstakingTokens           a list of tokenIds with token contract addresses
   */
  function unstakeTokens(address owner, StakingTokenParam[] calldata unstakingTokens) external payable;

  /**
   * @notice get a staking points instance corresponding to a creator contract and instanceId
   * @param creatorContractAddress    the address of the creator contract
   * @param instanceId                the instanceId of the staking points for the creator contract
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
}
