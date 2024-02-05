// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Frame Paymaster interface
 */
interface IFramePaymaster {

    error InvalidSignature();
    error ExpiredSignature();
    error InsufficientPayment();
    error InvalidNonce();
    error FailedToTransfer();

    event CheckoutComplete(address indexed sender, uint256 indexed fid, uint256 nonce);

    struct MintSubmission {
        ExtensionMint[] extensionMints;
        uint256 fid;
        uint256 nonce;
        uint256 expiration;
        bytes32 message;
        bytes signature;
    }

    struct ExtensionMint {
        address extensionAddress;
        Mint[] mints;
    }

    struct Mint {
        address creatorContractAddress;
        uint256 instanceId;
        uint256 amount;
        uint256 payment;
    }

    /**
     * @notice Withdraw funds
     */
    function withdraw(address payable receiver, uint256 amount) external;


    /**
     * @notice Checkout and mint NFTs
     */
    function checkout(MintSubmission calldata submission) external payable;

    /**
     * @notice Set the signing address
     * @param signer    the signer address
     */
    function setSigner(address signer) external;

}