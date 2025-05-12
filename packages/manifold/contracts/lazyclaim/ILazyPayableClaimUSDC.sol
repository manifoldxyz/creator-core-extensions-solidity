// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./ILazyPayableClaimCore.sol";

/**
 * Lazy Payable Claim interface
 */
interface ILazyPayableClaimUSDC is ILazyPayableClaimCore {
    error InvalidUSDCAddress();

    /**
     * @notice allow a wallet to lazily claim a token according to parameters
     * @param creatorContractAddress    the creator contract address
     * @param instanceId                the claim instanceId for the creator contract
     * @param mintIndex                 the mint index (only needed for merkle claims)
     * @param merkleProof               if the claim has a merkleRoot, verifying merkleProof ensures that address + minterValue was used to construct it  (only needed for merkle claims)
     * @param mintFor                   mintFor must be the msg.sender or a delegate wallet address (in the case of merkle based mints)
     */
    function mint(
        address creatorContractAddress,
        uint256 instanceId,
        uint32 mintIndex,
        bytes32[] calldata merkleProof,
        address mintFor
    ) external;

    /**
     * @notice allow a wallet to lazily claim a token according to parameters
     * @param creatorContractAddress    the creator contract address
     * @param instanceId                the claim instanceId for the creator contract
     * @param mintCount                 the number of claims to mint
     * @param mintIndices               the mint index (only needed for merkle claims)
     * @param merkleProofs              if the claim has a merkleRoot, verifying merkleProof ensures that address + minterValue was used to construct it  (only needed for merkle claims)
     * @param mintFor                   mintFor must be the msg.sender or a delegate wallet address (in the case of merkle based mints)
     */
    function mintBatch(
        address creatorContractAddress,
        uint256 instanceId,
        uint16 mintCount,
        uint32[] calldata mintIndices,
        bytes32[][] calldata merkleProofs,
        address mintFor
    ) external;

    /**
     * @notice allow a proxy to mint a token for another address
     * @param creatorContractAddress    the creator contract address
     * @param instanceId                the claim instanceId for the creator contract
     * @param mintCount                 the number of claims to mint
     * @param mintIndices               the mint index (only needed for merkle claims)
     * @param merkleProofs              if the claim has a merkleRoot, verifying merkleProof ensures that address + minterValue was used to construct it  (only needed for merkle claims)
     * @param mintFor                   the address to mint for
     */
    function mintProxy(
        address creatorContractAddress,
        uint256 instanceId,
        uint16 mintCount,
        uint32[] calldata mintIndices,
        bytes32[][] calldata merkleProofs,
        address mintFor
    ) external;

    /**
     * @notice allowlist minting based on signatures
     * @param creatorContractAddress    the creator contract address
     * @param instanceId                the claim instanceId for the creator contract
     * @param mintCount                 the number of claims to mint
     * @param signature                 if the claim has a signerAddress, verifying signatures were signed by it
     * @param message                   the message that was signed
     * @param nonce                     the nonce that was signed
     * @param mintFor                   the address to mint for
     */
    function mintSignature(
        address creatorContractAddress,
        uint256 instanceId,
        uint16 mintCount,
        bytes calldata signature,
        bytes32 message,
        bytes32 nonce,
        address mintFor,
        uint256 expiration
    ) external;
}
