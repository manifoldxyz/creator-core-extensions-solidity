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
    error PaymentNotAllowed();

    event FrameClaimInitialized(address indexed creatorContract, uint256 indexed instanceId, address initializer);
    event FrameClaimUpdated(address indexed creatorContract, uint256 indexed instanceId);
    event FrameClaimMint(address indexed creatorContract, uint256 indexed instanceId);
    event FrameClaimSponsored(address indexed sponsor, address indexed creatorContract, uint256 indexed instanceId, uint256 amount);

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
     * @notice Update the sponsored mint fee
     * @param fee    the new fee
     */
    function updateSponsoredMintFee(uint256 fee) external;

    /**
     * @notice Update the number of free mints sponsored by manifold
     * @param amount    the new amount
     */
    function updateManifoldFreeMints(uint56 amount) external;


    /**
     * @notice Increase the number of sponsored mints for a claim
     * @param creatorContractAddress    the address of the creator contract
     * @param instanceId                the instance id of the claim
     * @param amount                    the amount to increase by
     */
    function sponsorMints(address creatorContractAddress, uint256 instanceId, uint56 amount) external payable;

    /**
     * @notice Set the signing address
     * @param signer    the signer address
     */
    function setSigner(address signer) external;

    /**
     * @notice Set the funds receiver
     * @param fundsReceiver    the funds receiver address
     */
    function setFundsReceiver(address payable fundsReceiver) external;

    /**
     * @notice allowlist minting based on signatures
     * @param mints    the mint instructions
     */
    function mint(Mint[] calldata mints) external payable;

}