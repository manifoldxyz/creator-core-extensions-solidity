// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "./IGachaLazyClaim.sol";

/**
 * @title Gacha Lazy Claim
 * @author manifold.xyz
 */
abstract contract GachaLazyClaim is IGachaLazyClaim, AdminControl {
  using EnumerableSet for EnumerableSet.AddressSet;

  string internal constant ARWEAVE_PREFIX = "https://arweave.net/";
  string internal constant IPFS_PREFIX = "ipfs://";
  address internal _signer;

  uint256 internal constant MAX_UINT_24 = 0xffffff;
  uint256 internal constant MAX_UINT_32 = 0xffffffff;
  uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;
  uint256 internal constant MAX_UINT_256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
  address internal constant ADDRESS_ZERO = 0x0000000000000000000000000000000000000000;

  // { contractAddress => { instanceId => { walletAddress => reservedMints } } }
  mapping(address => mapping(uint256 => mapping(address => uint64))) internal _reservedMintsPerWallet;
  // { contractAddress => { instanceId => { walletAddress => deliveredMints } } }
  mapping(address => mapping(uint256 => mapping(address => uint64))) internal _deliveredMintsPerWallet;

  //   // { creatorContractAddress => { instanceId => nonce => t/f  } }
  //   mapping(address => mapping(uint256 => mapping(bytes32 => bool))) internal _usedMessages;

  constructor(address initialOwner) {
    _transferOwnership(initialOwner);
  }

  function _validateMintReserve(
    address creatorContractAddress,
    uint256 instanceId,
    uint48 startDate,
    uint48 endDate,
    uint32 walletMax,
    uint16 mintCount,
    address mintFor
  ) internal {
    if ((startDate > block.timestamp) || (endDate > 0 && endDate < block.timestamp)) revert IGachaLazyClaim.ClaimInactive();
    if (mintFor != msg.sender) revert IGachaLazyClaim.InvalidInput();
    if (walletMax != 0) {
      _reservedMintsPerWallet[creatorContractAddress][instanceId][mintFor] += mintCount;
      if (_reservedMintsPerWallet[creatorContractAddress][instanceId][mintFor] > walletMax)
        revert IGachaLazyClaim.TooManyRequested();
    }
  }

  /**
   * See {IGachaLazyClaim-withdraw}.
   */
  function withdraw(address payable receiver, uint256 amount) external override adminRequired {
    (bool sent, ) = receiver.call{ value: amount }("");
    if (!sent) revert FailedToTransfer();
  }

  /**
   * See {IGachaLazyClaim-setSigner}.
   */
  function setSigner(address signer) external override adminRequired {
    _signer = signer;
  }

  function _validateSigner() internal view {
    if (msg.sender != _signer) revert InvalidSignature();
  }

  function _getUserMints(
    address minter,
    address creatorContractAddress,
    uint256 instanceId
  ) internal view returns (UserMint memory) {
    UserMint memory userMint = UserMint({
      receiver: minter,
      reservedCount: _reservedMintsPerWallet[creatorContractAddress][instanceId][minter],
      deliveredCount: _deliveredMintsPerWallet[creatorContractAddress][instanceId][minter]
    });
    return (userMint);
  }
}
