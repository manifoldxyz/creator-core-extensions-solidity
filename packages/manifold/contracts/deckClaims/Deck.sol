// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./IDeck.sol";

/**
 * @title Deck Lazy Claim
 * @author manifold.xyz
 */
abstract contract Deck is IDeck, AdminControl {
  using EnumerableSet for EnumerableSet.AddressSet;
  using ECDSA for bytes32;

  string internal constant ARWEAVE_PREFIX = "https://arweave.net/";
  string internal constant IPFS_PREFIX = "ipfs://";
  address internal _signer;

  uint256 internal constant MAX_UINT_8 = 0xff;
  uint256 internal constant MAX_UINT_32 = 0xffffffff;
  uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;
  uint256 internal constant MAX_UINT_80 = 0xffffffffffffffffffff;
  address internal constant ADDRESS_ZERO = 0x0000000000000000000000000000000000000000;

  bool public deprecated;

  // Mapping to track used nonces to prevent replay attacks
  mapping(bytes32 => bool) internal _usedNonces;

  /**
   * @notice This extension is shared, not single-creator. So we must ensure
   * that a claim's initializer is an admin on the creator contract
   * @param creatorContractAddress    the address of the creator contract to check the admin against
   */
  modifier creatorAdminRequired(address creatorContractAddress) {
    AdminControl creatorCoreContract = AdminControl(creatorContractAddress);
    require(creatorCoreContract.isAdmin(msg.sender), "Wallet is not an administrator for contract");
    _;
  }

  constructor(address initialOwner) {
    _transferOwnership(initialOwner);
  }

  /**
   * Admin function to deprecate the contract
   */
  function deprecate(bool _deprecated) external adminRequired {
    deprecated = _deprecated;
  }

  /**
   * See {IDeck-withdraw}.
   */
  function withdraw(address payable receiver, uint256 amount) external override adminRequired {
    (bool sent, ) = receiver.call{ value: amount }("");
    if (!sent) revert IDeck.FailedToTransfer();
  }

  /**
   * See {IDeck-setSigner}.
   */
  function setSigner(address signer) external override adminRequired {
    _signer = signer;
  }

  /**
   * See {IDeck-isNonceUsed}.
   */
  function isNonceUsed(bytes32 nonce) external view override returns (bool) {
    return _usedNonces[nonce];
  }

  /**
   * @notice Validates signature and marks nonce as used
   * @param mints The mint data that was signed
   * @param signedParams The signature parameters
   */
  function _validateSignature(
    IDeck.ClaimMint[] calldata mints,
    IDeck.SignedDeliveryParams calldata signedParams
  ) internal {
    // Check expiration
    if (block.timestamp > signedParams.expiration) {
      revert IDeck.ExpiredSignature();
    }

    // Check nonce hasn't been used
    if (_usedNonces[signedParams.nonce]) {
      revert IDeck.NonceAlreadyUsed();
    }

    // Compute expected message from mints data
    bytes32 expectedMessage = _computeMintsHash(mints, signedParams.nonce, signedParams.expiration);

    // Recover signer from signature
    address recoveredSigner = signedParams.message.recover(signedParams.signature);

    // Verify message matches and signer is correct
    if (signedParams.message != expectedMessage || recoveredSigner != _signer) {
      revert IDeck.InvalidSignature();
    }

    // Mark nonce as used
    _usedNonces[signedParams.nonce] = true;
  }

  /**
   * @notice Computes the hash of mints data for signature verification
   * @param mints The mint data to hash
   * @param nonce The nonce for replay protection
   * @param expiration The expiration timestamp
   * @return The keccak256 hash of the encoded data
   */
  function _computeMintsHash(
    IDeck.ClaimMint[] calldata mints,
    bytes32 nonce,
    uint256 expiration
  ) internal pure returns (bytes32) {
    bytes memory encodedMints;
    for (uint256 i; i < mints.length; ) {
      IDeck.ClaimMint calldata mintData = mints[i];
      bytes memory encodedVariations;
      for (uint256 j; j < mintData.variationMints.length; ) {
        IDeck.VariationMint calldata vm = mintData.variationMints[j];
        encodedVariations = abi.encodePacked(encodedVariations, vm.variationIndex, vm.amount, vm.recipient);
        unchecked {
          ++j;
        }
      }
      encodedMints = abi.encodePacked(
        encodedMints,
        mintData.creatorContractAddress,
        mintData.instanceId,
        keccak256(encodedVariations)
      );
      unchecked {
        ++i;
      }
    }

    return keccak256(abi.encodePacked(encodedMints, nonce, expiration));
  }
}
