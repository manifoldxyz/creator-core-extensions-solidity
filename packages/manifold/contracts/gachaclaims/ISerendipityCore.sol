// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Serendipity Core interface - shared definitions for ETH and USDC variants
 */
interface ISerendipityCore {
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
  error ExpiredSignature();
  error CannotReplayTransaction();
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
  event SerendipityMintReserved(
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
   * @notice                          Deliver NFTs
   *                                  initiated after backend has handled randomization
   * @param mints                     the mints to deliver with creatorcontractaddress, instanceId and variationMints
   * @param signature                 the signature from the signing address
   * @param message                   the signed message hash
   * @param nonce                     unique nonce to prevent replay attacks
   * @param expiration                timestamp when the signature expires
   */
  function deliverMints(
    ClaimMint[] calldata mints,
    bytes calldata signature,
    bytes32 message,
    bytes32 nonce,
    uint256 expiration
  ) external;

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
