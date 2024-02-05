// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Frame Lazy Claim interface
 */
interface IFrameLazyClaim {
    enum StorageProtocol { INVALID, NONE, ARWEAVE, IPFS }

    error InvalidSignature();
    error FailedToTransfer();
    error InsufficientPayment();

    event FrameClaimInitialized(address indexed creatorContract, uint256 indexed instanceId, address initializer);
    event FrameClaimUpdated(address indexed creatorContract, uint256 indexed instanceId);
    event FrameClaimMint(address indexed creatorContract, uint256 indexed instanceId);

    struct Recipient {
        address receiver;
        uint256 amount;
        uint256 payment;
    }

    struct Mint {
        address creatorContractAddress;
        uint256 instanceId;
        Recipient[] recipients;
    }

    /**
     * @notice Set the signing address
     * @param signer    the signer address
     */
    function setSigner(address signer) external;

    /**
     * @notice allowlist minting based on signatures
     * @param mints    the mint instructions
     */
    function mint(Mint[] calldata mints) external payable;

}