// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "./IDeck.sol";

/**
 * @title Deck Lazy Claim
 * @author manifold.xyz
 */
abstract contract Deck is IDeck, AdminControl {
  using EnumerableSet for EnumerableSet.AddressSet;

  string internal constant ARWEAVE_PREFIX = "https://arweave.net/";
  string internal constant IPFS_PREFIX = "ipfs://";
  address internal _signer;

  uint256 internal constant MAX_UINT_8 = 0xff;
  uint256 internal constant MAX_UINT_32 = 0xffffffff;
  uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;
  uint256 internal constant MAX_UINT_80 = 0xffffffffffffffffffff;
  address internal constant ADDRESS_ZERO = 0x0000000000000000000000000000000000000000;

  bool public deprecated;

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

  function _validateSigner() internal view {
    if (msg.sender != _signer) revert IDeck.InvalidSignature();
  }
}
