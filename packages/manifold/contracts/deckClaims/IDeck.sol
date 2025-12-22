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
   * @notice                          Deliver NFTs
   * @param mints                     the mints to deliver with creatorcontractaddress, instanceId and variationMints
   */
  function deliverMints(ClaimMint[] calldata mints) external;
}
