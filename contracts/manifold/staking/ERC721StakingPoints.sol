// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "../../libraries/IERC721CreatorCoreVersion.sol";
import "./IERC721StakingPoints.sol";
import "./StakingPointsCore.sol";
import "./IStakingPointsCore.sol";

/**
 * @title ERC721 Staking Points
 * @author manifold.xyz
 * @notice logic for Staking Points for ERC721 extension.
 */
contract ERC721StakingPoints is StakingPointsCore, IERC721StakingPoints {

  uint256 public totalPointsCirculation;

  // { instanceId => { walletAddress => points } }
  mapping(uint256 => mapping(address => uint256)) public stakerPoints;

  function supportsInterface(bytes4 interfaceId) public view virtual override(StakingPointsCore, IERC165) returns (bool) {
    return interfaceId == type(IERC721StakingPoints).interfaceId || super.supportsInterface(interfaceId);
  }

  function initializeStakingPoints(
    address creatorContractAddress,
    uint256 instanceId,
    StakingPointsParams calldata stakingPointsParams
  ) external creatorAdminRequired(creatorContractAddress) nonReentrant {
    // Max uint56 for instanceId
    require(instanceId > 0 && instanceId <= MAX_UINT_56, "Invalid instanceId");
    require(stakingPointsParams.paymentReceiver != address(0), "Cannot initialize without payment receiver");

    uint8 creatorContractVersion;
    try IERC721CreatorCoreVersion(creatorContractAddress).VERSION() returns (uint256 version) {
      require(version <= 255, "Unsupported contract version");
      creatorContractVersion = uint8(version);
    } catch {}

    _initialize(creatorContractAddress, creatorContractVersion, instanceId, stakingPointsParams);

    emit StakingPointsInitialized(creatorContractAddress, instanceId, msg.sender);
  }

  /**
   * @dev was originally using safeTransferFrom but was getting a reentrancy error
   */
  function _transfer(address contractAddress, uint256 tokenId, address from, address to) internal override {
    require(
      IERC721(contractAddress).ownerOf(tokenId) == from &&
        (IERC721(contractAddress).getApproved(tokenId) == address(this) ||
          IERC721(contractAddress).isApprovedForAll(from, address(this))),
      "Token not owned or not approved"
    );
    require(IERC721(contractAddress).ownerOf(tokenId) == from, "Token not in sender possesion");
    IERC721(contractAddress).transferFrom(from, to, tokenId);
  }

  /**
   * @dev was originally using safeTransferFrom but was getting a reentrancy error
   */
  function _transferBack(address contractAddress, uint256 tokenId, address from, address to) internal override {
    require(IERC721(contractAddress).ownerOf(tokenId) == from, "Token not in sender possesion");
    IERC721(contractAddress).transferFrom(from, to, tokenId);
  }

  /**
   * @dev
   */
  function _redeem(uint256 instanceId, uint256 pointsAmount, address redeemer) internal override {
    totalPointsCirculation = SafeMath.add(totalPointsCirculation, pointsAmount);
    stakerPoints[instanceId][redeemer];
  }
}
