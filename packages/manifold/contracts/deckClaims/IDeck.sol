// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Deck Lazy Claim interface
 */
interface IDeck {
  enum StorageProtocol {
    INVALID,
    NONE,
    ARWEAVE,
    IPFS
  }

  error InvalidStorageProtocol();
  error InvalidInstance();
  error InvalidInput();
  error InvalidSignature();
  error ExpiredSignature();
  error NonceAlreadyUsed();
  error InvalidVariationIndex();
  error InvalidStartingTokenId();
  error ClaimAlreadyInitialized();
  error ClaimNotInitialized();
  error ContractDeprecated();
  error TokenDNE();
  error FailedToTransfer();
  error TooManyRequested();

  event DeckClaimInitialized(address indexed creatorContract, uint256 indexed instanceId, address initializer);
  event DeckClaimUpdated(address indexed creatorContract, uint256 indexed instanceId);
  event DeckMintDelivered(address indexed creatorContract, uint256 indexed instanceId, uint32 totalMinted, bytes32 nonce);

  struct SignedDeliveryParams {
    bytes signature;
    bytes32 message;
    bytes32 nonce;
    uint256 expiration;
  }

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
   * @notice                          Deliver NFTs with signature verification
   * @param mints                     the mints to deliver with creatorcontractaddress, instanceId and variationMints
   * @param signedParams              signature parameters for validation
   */
  function deliverMints(ClaimMint[] calldata mints, SignedDeliveryParams calldata signedParams) external;

  /**
   * @notice                          Check if a nonce has been used
   * @param nonce                     the nonce to check
   * @return                          true if the nonce has been used
   */
  function isNonceUsed(bytes32 nonce) external view returns (bool);
}
