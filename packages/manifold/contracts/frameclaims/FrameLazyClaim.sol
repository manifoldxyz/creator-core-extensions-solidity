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
    address payable internal _fundsReceiver;

    uint256 internal constant MAX_UINT_24 = 0xffffff;
    uint256 internal constant MAX_UINT_32 = 0xffffffff;
    uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;
    uint256 internal constant MAX_UINT_256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    address internal constant ADDRESS_ZERO = 0x0000000000000000000000000000000000000000;

    uint256 public SPONSORED_MINT_FEE = 0.0001 ether;
    uint56 public MANIFOLD_FREE_MINTS = 5;

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
     * See {IFrameLazyClaim-updateSponsoredMintFee}.
     */
    function updateSponsoredMintFee(uint256 fee) external override adminRequired {
        SPONSORED_MINT_FEE = fee;
    }

    /**
     * See {IFrameLazyClaim-updateManifoldFreeMints}.
     */
    function updateManifoldFreeMints(uint56 amount) external override adminRequired {
        MANIFOLD_FREE_MINTS = amount;
    }

    /**
     * See {IFrameLazyClaim-setSigner}.
     */
    function setSigner(address signer) external override adminRequired {
        _signer = signer;
    }

    /**
     * See {IFrameLazyClaim-setFundsReceiver}.
     */
    function setFundsReceiver(address payable fundsReceiver) external override adminRequired {
        _fundsReceiver = fundsReceiver;
    }

    function _validateSigner() internal view {
        if (msg.sender != _signer) revert InvalidSignature();
    }

    function _sendFunds(address payable recipient, uint256 amount) internal {
        if (recipient == ADDRESS_ZERO) revert FailedToTransfer();
        (bool sent, ) = recipient.call{value: amount}("");
        if (!sent) revert FailedToTransfer();
    }
}