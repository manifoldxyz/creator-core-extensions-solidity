// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./ISerendipity.sol";

/**
 * @title Serendipity Allowlist Lazy Claim Interface
 * @notice Unified interface combining Serendipity gacha mechanics with allowlist functionality
 */
interface ISerendipityAllowlist is ISerendipity {
    
    // ========== CUSTOM ERRORS ==========
    
    error InvalidMerkleProof();
    error MintIndexAlreadyUsed();
    error NotAllowlisted();
    error InvalidAllowlistParameters();
    error AllowlistNotActive();
    error ExceedsAllowlistLimit();
    
    // ========== EVENTS ==========
    
    event AllowlistClaimInitialized(
        address indexed creatorContract,
        uint256 indexed instanceId,
        address initializer
    );
    
    event AllowlistClaimUpdated(
        address indexed creatorContract,
        uint256 indexed instanceId
    );
    
    event AllowlistMintReserved(
        address indexed creatorContract,
        uint256 indexed instanceId,
        address indexed collector,
        uint32 mintCount,
        uint32[] mintIndices
    );
    
    event AllowlistTokensDelivered(
        address indexed creatorContract,
        uint256 indexed instanceId,
        address indexed collector,
        uint32 deliveredCount
    );
    
    // ========== STRUCTS ==========
    
    /**
     * @notice Combined claim structure for gacha + allowlist functionality
     * @dev Combines fields from both Serendipity.Claim and LazyPayableClaim.Claim
     * @dev NOTE: Global _signer is used at contract level, not per-claim
     */
    struct AllowlistClaim {
        // Core Serendipity fields
        StorageProtocol storageProtocol;
        uint32 total;
        uint32 totalMax;
        uint48 startDate;
        uint48 endDate;
        uint80 startingTokenId;
        uint8 tokenVariations;
        string location;
        address payable paymentReceiver;
        uint96 cost;
        address erc20;
        
        // Allowlist-specific fields
        bytes32 merkleRoot;         // Merkle root for allowlist validation
        uint32 walletMax;           // Max mints per wallet (for non-merkle claims)
        uint32 allowlistMax;        // Max total allowlist mints
        uint32 allowlistMinted;     // Current allowlist mints count
        bool allowlistActive;       // Whether allowlist is currently active
    }
    
    /**
     * @notice Parameters for initializing an allowlist claim
     */
    struct AllowlistClaimParameters {
        StorageProtocol storageProtocol;
        uint32 totalMax;
        uint48 startDate;
        uint48 endDate;
        uint8 tokenVariations;
        string location;
        address payable paymentReceiver;
        uint96 cost;
        address erc20;
        bytes32 merkleRoot;
        uint32 walletMax;
        uint32 allowlistMax;
        bool allowlistActive;
    }
    
    /**
     * @notice Parameters for updating an allowlist claim
     */
    struct UpdateAllowlistClaimParameters {
        StorageProtocol storageProtocol;
        address payable paymentReceiver;
        uint32 totalMax;
        uint48 startDate;
        uint48 endDate;
        uint96 cost;
        string location;
        bytes32 merkleRoot;
        uint32 walletMax;
        uint32 allowlistMax;
        bool allowlistActive;
    }
    
    /**
     * @notice Reservation details for allowlist mints
     */
    struct AllowlistReservation {
        uint32 reservedCount;
        uint32 deliveredCount;
        uint256[] mintIndices;      // Used for merkle-based allowlists
    }
    
    // ========== ALLOWLIST FUNCTIONS ==========
    
    /**
     * @notice Initialize a new allowlist claim
     * @param creatorContractAddress    the creator contract the claim will mint tokens for
     * @param instanceId                the claim instanceId for the creator contract
     * @param claimParameters           the parameters which will affect the minting behavior of the claim
     */
    function initializeAllowlistClaim(
        address creatorContractAddress,
        uint256 instanceId,
        AllowlistClaimParameters calldata claimParameters
    ) external payable;
    
    /**
     * @notice Update an existing allowlist claim
     * @param creatorContractAddress    the creator contract corresponding to the claim
     * @param instanceId                the claim instanceId for the creator contract
     * @param updateClaimParameters     the updateable parameters that affect the minting behavior of the claim
     */
    function updateAllowlistClaim(
        address creatorContractAddress,
        uint256 instanceId,
        UpdateAllowlistClaimParameters calldata updateClaimParameters
    ) external;
    
    /**
     * @notice Allowlist minting request with merkle proof validation
     * @param creatorContractAddress    the creator contract address
     * @param instanceId                the claim instanceId for the creator contract
     * @param mintCount                 the number of claims to mint
     * @param mintIndices               array of mint indices for merkle validation
     * @param merkleProofs              array of merkle proofs for validation
     */
    function mintAllowlistReserve(
        address creatorContractAddress,
        uint256 instanceId,
        uint32 mintCount,
        uint32[] calldata mintIndices,
        bytes32[][] calldata merkleProofs
    ) external payable;
    
    /**
     * @notice Batch allowlist minting for multiple addresses (admin only)
     * @param creatorContractAddress    the creator contract address
     * @param instanceId                the claim instanceId for the creator contract
     * @param recipients                addresses to mint for
     * @param mintCounts               number of mints for each recipient
     */
    function mintAllowlistBatch(
        address creatorContractAddress,
        uint256 instanceId,
        address[] calldata recipients,
        uint32[] calldata mintCounts
    ) external;
    
    /**
     * @notice Deliver NFTs for allowlist reservations
     * @param mints                     the mints to deliver with creatorContractAddress, instanceId and variationMints
     */
    function deliverAllowlistMints(ClaimMint[] calldata mints) external;
    
    // ========== VIEW FUNCTIONS ==========
    
    /**
     * @notice Get an allowlist claim
     * @param creatorContractAddress    the address of the creator contract
     * @param instanceId                the claim instanceId for the creator contract
     * @return                          the allowlist claim object
     */
    function getAllowlistClaim(
        address creatorContractAddress,
        uint256 instanceId
    ) external view returns (AllowlistClaim memory);
    
    /**
     * @notice Get allowlist reservation details for a specific wallet
     * @param minter                    the address of the minting address
     * @param creatorContractAddress    the address of the creator contract for the claim
     * @param instanceId                the claim instance for the creator contract
     * @return                          the wallet's allowlist reservation details
     */
    function getAllowlistReservation(
        address minter,
        address creatorContractAddress,
        uint256 instanceId
    ) external view returns (AllowlistReservation memory);
    
    /**
     * @notice Check if multiple mint indices have been used
     * @param creatorContractAddress    the address of the creator contract
     * @param instanceId                the claim instanceId for the creator contract
     * @param mintIndices              array of mint indices to check
     * @return                          array of boolean values indicating usage status
     */
    function checkMintIndices(
        address creatorContractAddress,
        uint256 instanceId,
        uint32[] calldata mintIndices
    ) external view returns (bool[] memory);
    
    /**
     * @notice Verify merkle proof for allowlist
     * @param merkleRoot               the merkle root to verify against
     * @param account                  the account to verify
     * @param mintIndex               the mint index to verify
     * @param merkleProof             the merkle proof
     * @return                         whether the proof is valid
     */
    function verifyAllowlistProof(
        bytes32 merkleRoot,
        address account,
        uint32 mintIndex,
        bytes32[] calldata merkleProof
    ) external pure returns (bool);
}