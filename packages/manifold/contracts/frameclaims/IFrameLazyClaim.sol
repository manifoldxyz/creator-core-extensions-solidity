// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Frame Lazy Claim interface
 */
interface IFrameLazyClaim {
    enum StorageProtocol { INVALID, NONE, ARWEAVE, IPFS }

    error InvalidSignature();

    event FrameClaimInitialized(address indexed creatorContract, uint256 indexed instanceId, address initializer);
    event FrameClaimUpdated(address indexed creatorContract, uint256 indexed instanceId);
    event FrameClaimMint(address indexed creatorContract, uint256 indexed instanceId);

    struct Recipient {
        address receiver;
        uint256 amount;
    }

    /**
     * @notice Set the signing address
     * @param signer    the signer address
     */
    function setSigner(address signer) external;

    /**
     * @notice allowlist minting based on signatures
     * @param creatorContractAddress    the creator contract address
     * @param instanceId                the claim instanceId for the creator contract
     * @param recipients                the recipients to mint to
     */
    function mint(address creatorContractAddress, uint256 instanceId, Recipient[] calldata recipients) external;

}