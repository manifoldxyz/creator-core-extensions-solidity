// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./ISerendipity.sol";

/**
 * Serendipity Lazy Claim interface for ERC-1155 with allowlist support
 */
interface IERC1155SerendipityWithAllowlist is ISerendipity {
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
    bytes32 merkleRoot;
    uint32 walletMax;
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
    bytes32 merkleRoot;
    uint32 walletMax;
  }

  struct UpdateClaimParameters {
    StorageProtocol storageProtocol;
    address payable paymentReceiver;
    uint32 totalMax;
    uint48 startDate;
    uint48 endDate;
    uint96 cost;
    string location;
    bytes32 merkleRoot;
    uint32 walletMax;
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

  /**
   * @notice mint tokens - handles both merkle/allowlist and non-merkle cases
   * @param creatorContractAddress    the creator contract to mint tokens for
   * @param instanceId                the claim instanceId for the creator contract
   * @param mintIndex                 the index for the merkle proof (0 for non-merkle)
   * @param merkleProof               the merkle proof (empty array for non-merkle)
   * @param mintCount                 the number of tokens to mint
   */
  function mintReserve(
    address creatorContractAddress,
    uint256 instanceId,
    uint32 mintIndex,
    bytes32[] calldata merkleProof,
    uint32 mintCount
  ) external payable;

  /**
   * @notice check if a mint index has been used
   * @param creatorContractAddress    the creator contract address
   * @param instanceId                the claim instanceId
   * @param mintIndex                 the index to check
   * @return                          true if the index has been used
   */
  function checkMintIndex(address creatorContractAddress, uint256 instanceId, uint32 mintIndex) external view returns (bool);

  /**
   * @notice check multiple mint indices
   * @param creatorContractAddress    the creator contract address
   * @param instanceId                the claim instanceId
   * @param mintIndices               the indices to check
   * @return                          array of booleans indicating which indices have been used
   */
  function checkMintIndices(address creatorContractAddress, uint256 instanceId, uint32[] calldata mintIndices) external view returns (bool[] memory);

  /**
   * @notice get total mints for a wallet (non-merkle claims only)
   * @param creatorContractAddress    the creator contract address
   * @param instanceId                the claim instanceId
   * @param minter                    the minter address
   * @return                          the total number of mints
   */
  function getTotalMints(address creatorContractAddress, uint256 instanceId, address minter) external view returns (uint32);
}