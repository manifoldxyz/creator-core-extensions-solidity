// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./ISerendipityLazyClaim.sol";

/**
 * Serendipity Lazy Claim interface for ERC-1155
 */
interface IERC1155SerendipityLazyClaim is ISerendipityLazyClaim {
  struct Claim {
    StorageProtocol storageProtocol;
    uint32 total;
    uint32 totalMax;
    uint48 startDate;
    uint48 endDate;
    uint80 startingTokenId;
    uint8 tokenVariations;
    string location;
    address payable paymentReceiver;
    uint96 cost;
    address erc20;
  }

  struct ClaimParameters {
    StorageProtocol storageProtocol;
    uint32 totalMax;
    uint48 startDate;
    uint48 endDate;
    uint8 tokenVariations;
    string location;
    address payable paymentReceiver;
    uint96 cost;
    address erc20;
  }

  struct UpdateClaimParameters {
    StorageProtocol storageProtocol;
    address payable paymentReceiver;
    uint32 totalMax;
    uint48 startDate;
    uint48 endDate;
    uint96 cost;
    string location;
  }

  /**
   * @notice initialize a new claim, emit initialize event
   * @param creatorContractAddress    the creator contract the claim will mint tokens for
   * @param instanceId                the claim instanceId for the creator contract
   * @param claimParameters           the parameters which will affect the minting behavior of the claim
   */
  function initializeClaim(
    address creatorContractAddress,
    uint256 instanceId,
    ClaimParameters calldata claimParameters
  ) external payable;

  /**
   * @notice update an existing claim at instanceId
   * @param creatorContractAddress    the creator contract corresponding to the claim
   * @param instanceId                the claim instanceId for the creator contract
   * @param updateClaimParameters     the updateable parameters that affect the minting behavior of the claim
   */
  function updateClaim(
    address creatorContractAddress,
    uint256 instanceId,
    UpdateClaimParameters calldata updateClaimParameters
  ) external;

  /**
   * @notice get a claim corresponding to a creator contract and instanceId
   * @param creatorContractAddress    the address of the creator contract
   * @param instanceId                the claim instanceId for the creator contract
   * @return                          the claim object
   */
  function getClaim(address creatorContractAddress, uint256 instanceId) external view returns (Claim memory);

  /**
   * @notice get a claim corresponding to a token
   * @param creatorContractAddress    the address of the creator contract
   * @param tokenId                   the tokenId of the claim
   * @return                          the claim instanceId and claim object
   */
  function getClaimForToken(address creatorContractAddress, uint256 tokenId) external view returns (uint256, Claim memory);

  /**
   * @notice update tokenURI for an existing token
   * @param creatorContractAddress    the creator contract corresponding to the burn redeem
   * @param instanceId                the instanceId of the burnRedeem for the creator contract
   * @param storageProtocol           the storage protocol for the metadata
   * @param location                  the location of the metadata
   */
  function updateTokenURIParams(
    address creatorContractAddress,
    uint256 instanceId,
    StorageProtocol storageProtocol,
    string calldata location
  ) external;
}
