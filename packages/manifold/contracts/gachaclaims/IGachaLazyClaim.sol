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
  error InvalidStartDate();
  error InvalidAirdrop();
  error InvalidInstance();
  error InvalidInput();
  error ClaimAlreadyInitialized();
  error ClaimNotInitialized();
  error ClaimInactive();
  error TokenDNE();
  error TooManyRequested();
  error CannotChangeTotalMax();
  error CannotChangeStartingTokenId();
  error CannotChangeItemVariations();
  error CannotChangeStorageProtocol();
  error CannotChangeLocation();
  error CannotChangePaymentReceiver();
  error CannotChangePaymentToken();

  error InvalidSignature();
  error ExpiredSignature();
  error InvalidNonce();
  error FailedToTransfer();
  error InsufficientPayment();

  event GachaClaimInitialized(address indexed creatorContract, uint256 indexed instanceId, address initializer);
  event GachaClaimUpdated(address indexed creatorContract, uint256 indexed instanceId);
  event GachaClaimMintReserved(address indexed creatorContract, uint256 indexed instanceId, address indexed collector);
  event GachaClaimMintReservedBatch(
    address indexed creatorContract,
    uint256 indexed instanceId,
    address indexed collector,
    uint256 mintCount
  );
  event GachaClaimMintDelivered(address indexed creatorContract, uint256 indexed instanceId, address indexed collector);
  event GachaClaimMintDeliveredBatch(
    address indexed creatorContract,
    uint256 indexed instanceId,
    address indexed collector,
    uint256 mintCount
  );

  struct MintReservation {
    Mint[] mints;
    uint256 fid;
    uint256 nonce;
    uint256 expiration;
    bytes32 message;
    bytes signature;
  }

  struct Recipient {
    uint256 mintCount;
    address receiver;
  }

  struct Mint {
    address creatorContractAddress;
    uint256 instanceId;
    uint256 tokenId;
    Recipient[] recipients;
  }

  struct UserMint {
    address receiver;
    uint64 reservedCount;
    uint64 deliveredCount;
  }

  /**
   * @notice Set the signing address
   * @param signer    the signer address
   */
  function setSigner(address signer) external;

  /**
   * @notice Withdraw funds
   */
  function withdraw(address payable receiver, uint256 amount) external;

  /**
   * @notice                          minting request
   * @param mintReservation           mint reservation details
   */
  function mintReserve(MintReservation calldata mintReservation) external payable;

  // /**
  //  * @notice minting request
  //  * @param creatorContractAddress    the creator contract address
  //  * @param instanceId                the claim instanceId for the creator contract
  //  * @param mintCount                 the number of claims to mint
  //  */
  // function mintReserveBatch(address creatorContractAddress, uint256 instanceId, uint16 mintCount) external payable;

  /**
   * @notice Deliver NFTs
   */
  function deliverMints(Mint[] calldata mints) external;

  // add airdrop?
  //   /**
  //  * @notice allow admin to airdrop arbitrary tokens
  //  * @param creatorContractAddress    the creator contract the claim will mint tokens for
  //  * @param instanceId                the claim instanceId for the creator contract
  //  * @param recipients                addresses to airdrop to
  //  * @param amounts                   number of tokens to airdrop to each address in addresses
  //  */
  // function airdrop(
  //   address creatorContractAddress,
  //   uint256 instanceId,
  //   address[] calldata recipients,
  //   uint256[] calldata amounts
  // ) external;

  /**
   * @notice get mints made for a wallet
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
