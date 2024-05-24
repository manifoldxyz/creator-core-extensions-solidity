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
    address payable internal _fundsReceiver;

    uint256 internal constant MAX_UINT_24 = 0xffffff;
    uint256 internal constant MAX_UINT_32 = 0xffffffff;
    uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;
    uint256 internal constant MAX_UINT_256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    address internal constant ADDRESS_ZERO = 0x0000000000000000000000000000000000000000;

    constructor(address initialOwner) {
        _transferOwnership(initialOwner);
    }
}
