// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "./IFrameLazyClaim.sol";

/**
 * @title Frame Lazy Claim
 * @author manifold.xyz
 */
abstract contract FrameLazyClaim is IFrameLazyClaim, AdminControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    string internal constant ARWEAVE_PREFIX = "https://arweave.net/";
    string internal constant IPFS_PREFIX = "ipfs://";
    address internal _signer;

    uint256 internal constant MAX_UINT_24 = 0xffffff;
    uint256 internal constant MAX_UINT_32 = 0xffffffff;
    uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;
    uint256 internal constant MAX_UINT_256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    address private constant ADDRESS_ZERO = 0x0000000000000000000000000000000000000000;

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
     * See {IFrameLazyClaim-setSigner}.
     */
    function setSigner(address signer) external override adminRequired {
        _signer = signer;
    }

    function _validateMint() internal view {
        if (msg.sender != _signer) revert InvalidSignature();
    }
}