// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "./ISerendipity.sol";

/**
 * @title Serendipity Lazy Claim
 * @author manifold.xyz
 */
abstract contract Serendipity is ISerendipity, AdminControl {
  using EnumerableSet for EnumerableSet.AddressSet;

  string internal constant ARWEAVE_PREFIX = "https://arweave.net/";
  string internal constant IPFS_PREFIX = "ipfs://";
  address internal _signer;

  uint256 internal constant MAX_UINT_8 = 0xff;
  uint256 internal constant MAX_UINT_32 = 0xffffffff;
  uint256 internal constant MAX_UINT_48 = 0xffffffffffff;
  uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;
  uint256 internal constant MAX_UINT_80 = 0xffffffffffffffffffff;
  uint256 internal constant MAX_UINT_96 = 0xffffffffffffffffffffffff;
  address internal constant ADDRESS_ZERO = 0x0000000000000000000000000000000000000000;

  uint256 public constant MINT_FEE = 500000000000000;

  bool public deprecated;

  // { contractAddress => { instanceId => { walletAddress => UserMintDetails } } }
  mapping(address => mapping(uint256 => mapping(address => UserMintDetails))) internal _mintDetailsPerWallet;

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
   * See {ISerendipity-withdraw}.
   */
  function withdraw(address payable receiver, uint256 amount) external override adminRequired {
    (bool sent, ) = receiver.call{ value: amount }("");
    if (!sent) revert ISerendipity.FailedToTransfer();
  }

  /**
   * See {ISerendipity-setSigner}.
   */
  function setSigner(address signer) external override adminRequired {
    _signer = signer;
  }

  function _validateSigner() internal view {
    if (msg.sender != _signer) revert ISerendipity.InvalidSignature();
  }

  function _getUserMints(
    address minter,
    address creatorContractAddress,
    uint256 instanceId
  ) internal view returns (UserMintDetails memory) {
    return (_mintDetailsPerWallet[creatorContractAddress][instanceId][minter]);
  }

  function _sendFunds(address payable recipient, uint256 amount) internal {
    if (recipient == ADDRESS_ZERO) revert FailedToTransfer();
    (bool sent, ) = recipient.call{ value: amount }("");
    if (!sent) revert FailedToTransfer();
  }
}
