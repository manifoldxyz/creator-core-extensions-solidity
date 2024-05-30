// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Gacha Lazy Claim interface
 */
interface IGachaLazyClaim {
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
  error InvalidVariationIndex();
  error ClaimAlreadyInitialized();
  error ClaimNotInitialized();
  error ClaimInactive();
  error ClaimSoldOut();
  error TokenDNE();
  error FailedToTransfer();
  error TooManyRequested();
  error CannotChangeTotalMax();
  error CannotChangeStartingTokenId();
  error CannotChangeItemVariations();
  error CannotChangeStorageProtocol();
  error CannotChangeLocation();
  error CannotChangePaymentReceiver();
  error CannotChangePaymentToken();
  error CannotMintMoreThanReserved();

  event GachaClaimInitialized(address indexed creatorContract, uint256 indexed instanceId, address initializer);
  event GachaClaimUpdated(address indexed creatorContract, uint256 indexed instanceId);
  event GachaClaimMintReserved(
    address indexed creatorContract,
    uint256 indexed instanceId,
    address indexed collector,
    uint32 mintCount
  );

  struct Recipient {
    uint256 mintCount;
    address receiver;
  }

  struct Mint {
    address creatorContractAddress;
    uint256 instanceId;
    uint8 variationIndex;
    Recipient[] recipients;
  }

  struct UserMint {
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
   * @param mints                     the mints to deliver including variation, receiver, and count
   */
  function deliverMints(Mint[] calldata mints) external;

  /**
   * @notice                          get mints made for a wallet
   *
   * @param minter                    the address of the minting address
   * @param creatorContractAddress    the address of the creator contract for the claim
   * @param instanceId                the claim instance for the creator contract
   * @return                          the user mint details (receiver, reservedCount, deliveredCount)
   */
  function getUserMints(
    address minter,
    address creatorContractAddress,
    uint256 instanceId
  ) external view returns (UserMint memory);
}
