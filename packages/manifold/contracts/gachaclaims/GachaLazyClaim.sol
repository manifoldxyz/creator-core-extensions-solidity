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
  uint256 internal constant MAX_UINT_80 = 0xffffffffffffffffff;
  uint256 internal constant MAX_UINT_256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
  address internal constant ADDRESS_ZERO = 0x0000000000000000000000000000000000000000;

  uint256 public constant MINT_FEE = 500000000000000;

  // { contractAddress => { instanceId => { walletAddress => UserMint } } }
  mapping(address => mapping(uint256 => mapping(address => UserMint))) internal _mintDetailsPerWallet;

  constructor(address initialOwner) {
    _transferOwnership(initialOwner);
  }

  /**
   * See {IGachaLazyClaim-withdraw}.
   */
  function withdraw(address payable receiver, uint256 amount) external override adminRequired {
    (bool sent, ) = receiver.call{ value: amount }("");
    if (!sent) revert IGachaLazyClaim.FailedToTransfer();
  }

  /**
   * See {IGachaLazyClaim-setSigner}.
   */
  function setSigner(address signer) external override adminRequired {
    _signer = signer;
  }

  function _validateSigner() internal view {
    if (msg.sender != _signer) revert IGachaLazyClaim.InvalidSignature();
  }

  function _getUserMints(
    address minter,
    address creatorContractAddress,
    uint256 instanceId
  ) internal view returns (UserMint memory) {
    return (_mintDetailsPerWallet[creatorContractAddress][instanceId][minter]);
  }

  function _sendFunds(address payable recipient, uint256 amount) internal {
    if (recipient == ADDRESS_ZERO) revert FailedToTransfer();
    (bool sent, ) = recipient.call{ value: amount }("");
    if (!sent) revert FailedToTransfer();
  }
}
