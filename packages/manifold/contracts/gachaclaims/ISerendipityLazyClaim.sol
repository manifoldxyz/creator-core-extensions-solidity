// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Serendipity Lazy Claim interface
 */
interface ISerendipityLazyClaim {
  enum StorageProtocol {
    INVALID,
    NONE,
    ARWEAVE,
    IPFS
  }

  error InvalidStorageProtocol();
  error InvalidDate();
  error InvalidInstance();
  error InvalidInput();
  error InvalidPayment();
  error InvalidSignature();
  error InvalidMintCount();
  error InvalidVariationIndex();
  error InvalidStartingTokenId();
  error ClaimAlreadyInitialized();
  error ClaimNotInitialized();
  error ClaimInactive();
  error ClaimSoldOut();
  error ContractDeprecated();
  error TokenDNE();
  error FailedToTransfer();
  error TooManyRequested();
  error CannotLowerTotalMaxBeyondTotal();
  error CannotChangeTokenVariations();
  error CannotChangePaymentToken();
  error CannotLowertokenVariationsBeyondVariations();
  error CannotMintMoreThanReserved();
  error CannotMintFromContract();

  event SerendipityClaimInitialized(address indexed creatorContract, uint256 indexed instanceId, address initializer);
  event SerendipityClaimUpdated(address indexed creatorContract, uint256 indexed instanceId);
  event SerendipityClaimMintReserved(
    address indexed creatorContract,
    uint256 indexed instanceId,
    address indexed collector,
    uint32 mintCount
  );

  struct VariationMint {
    uint8 variationIndex;
    uint32 amount;
    address recipient;
  }

  struct ClaimMint {
    address creatorContractAddress;
    uint256 instanceId;
    VariationMint[] variationMints;
  }

  struct UserMintDetails {
    uint32 reservedCount;
    uint32 deliveredCount;
  }

  /**
   * @notice                          Set the signing address
   * @param signer                    the signer address
   */
  function setSigner(address signer) external;

  /**
   * @notice                          Withdraw funds
   */
  function withdraw(address payable receiver, uint256 amount) external;

  /**
   * @notice                          minting request
   * @param creatorContractAddress    the creator contract address
   * @param instanceId                the claim instanceId for the creator contract
   * @param mintCount                 the number of claims to mint
   */
  function mintReserve(address creatorContractAddress, uint256 instanceId, uint32 mintCount) external payable;

  /**
   * @notice                          Deliver NFTs 
   *                                  initiated after be has handled randomization
   * @param mints                     the mints to deliver with creatorcontractaddress, instanceId and variationMints
   */
  function deliverMints(ClaimMint[] calldata mints) external;

  /**
   * @notice                          get mints made for a wallet
   *
   * @param minter                    the address of the minting address
   * @param creatorContractAddress    the address of the creator contract for the claim
   * @param instanceId                the claim instance for the creator contract
   * @return userMintdetails          the wallet's reservedCount and deliveredCount
   */
  function getUserMints(
    address minter,
    address creatorContractAddress,
    uint256 instanceId
  ) external view returns (UserMintDetails memory);
}
