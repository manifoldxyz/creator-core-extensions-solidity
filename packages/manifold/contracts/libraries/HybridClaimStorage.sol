// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./AllowlistMerkleValidator.sol";
import "../gachaclaims/ISerendipityAllowlist.sol";
import "../gachaclaims/ISerendipity.sol";

/**
 * @title HybridClaimStorage
 * @author manifold.xyz
 * @notice Optimized storage library for ERC1155SerendipityWithAllowlist
 * @dev Provides gas-efficient storage layout and access patterns for hybrid gacha+allowlist claims
 */
library HybridClaimStorage {
    
    // ========== CUSTOM ERRORS ==========
    
    error ClaimNotFound();
    error ClaimAlreadyExists();
    error InvalidInstanceId();
    error StorageAccessError();
    
    // ========== STRUCTS ==========
    
    /**
     * @notice Optimized storage for hybrid claims
     * @dev Uses nested mapping structure for efficient access patterns
     */
    struct Storage {
        // Primary claim storage: contractAddress => instanceId => AllowlistClaim
        mapping(address => mapping(uint256 => ISerendipityAllowlist.AllowlistClaim)) claims;
        
        // Allowlist reservation tracking: contractAddress => instanceId => wallet => AllowlistReservation
        mapping(address => mapping(uint256 => mapping(address => ISerendipityAllowlist.AllowlistReservation))) reservations;
        
        // Mint index tracking for merkle proofs: contractAddress => instanceId => MintIndexTracker
        mapping(address => mapping(uint256 => AllowlistMerkleValidator.MintIndexTracker)) mintTrackers;
        
        // Token instance mapping: contractAddress => tokenId => instanceId
        mapping(address => mapping(uint256 => uint256)) tokenInstances;
        
        // Wallet mint counts (for non-merkle claims): contractAddress => instanceId => wallet => count
        mapping(address => mapping(uint256 => mapping(address => uint32))) walletMintCounts;
    }
    
    /**
     * @notice Parameters for claim initialization
     */
    struct InitClaimParams {
        address creatorContractAddress;
        uint256 instanceId;
        ISerendipityAllowlist.AllowlistClaimParameters claimParams;
        uint256[] newTokenIds;
    }
    
    /**
     * @notice Parameters for claim updates
     */
    struct UpdateClaimParams {
        address creatorContractAddress;
        uint256 instanceId;
        ISerendipityAllowlist.UpdateAllowlistClaimParameters updateParams;
    }
    
    // ========== CLAIM MANAGEMENT ==========
    
    /**
     * @notice Initialize a new hybrid claim
     * @param storage_               storage reference
     * @param params                initialization parameters
     * @dev Creates new claim and sets up associated mappings
     */
    function initializeClaim(
        Storage storage storage_,
        InitClaimParams calldata params
    ) external {
        // Validate instance ID
        if (params.instanceId == 0) revert InvalidInstanceId();
        
        // Check if claim already exists
        if (_claimExists(storage_, params.creatorContractAddress, params.instanceId)) {
            revert ClaimAlreadyExists();
        }
        
        // Create the claim
        ISerendipityAllowlist.AllowlistClaim storage claim = 
            storage_.claims[params.creatorContractAddress][params.instanceId];
            
        // Set core Serendipity fields
        claim.storageProtocol = params.claimParams.storageProtocol;
        claim.total = 0;
        claim.totalMax = params.claimParams.totalMax;
        claim.startDate = params.claimParams.startDate;
        claim.endDate = params.claimParams.endDate;
        claim.startingTokenId = uint80(params.newTokenIds[0]);
        claim.tokenVariations = params.claimParams.tokenVariations;
        claim.location = params.claimParams.location;
        claim.paymentReceiver = params.claimParams.paymentReceiver;
        claim.cost = params.claimParams.cost;
        claim.erc20 = params.claimParams.erc20;
        
        // Set allowlist-specific fields
        claim.merkleRoot = params.claimParams.merkleRoot;
        claim.walletMax = params.claimParams.walletMax;
        claim.allowlistMax = params.claimParams.allowlistMax;
        claim.allowlistMinted = 0;
        claim.allowlistActive = params.claimParams.allowlistActive;
        
        // Map token IDs to instance ID
        for (uint256 i; i < params.newTokenIds.length;) {
            storage_.tokenInstances[params.creatorContractAddress][params.newTokenIds[i]] = params.instanceId;
            unchecked {
                ++i;
            }
        }
    }
    
    /**
     * @notice Update an existing hybrid claim
     * @param storage_               storage reference
     * @param params                update parameters
     * @dev Updates claim parameters while preserving state data
     */
    function updateClaim(
        Storage storage storage_,
        UpdateClaimParams calldata params
    ) external {
        // Get existing claim
        ISerendipityAllowlist.AllowlistClaim storage claim = 
            storage_.claims[params.creatorContractAddress][params.instanceId];
            
        // Verify claim exists
        if (!_claimExists(storage_, params.creatorContractAddress, params.instanceId)) {
            revert ClaimNotFound();
        }
        
        // Update fields (preserving state data like total, allowlistMinted)
        claim.storageProtocol = params.updateParams.storageProtocol;
        claim.totalMax = params.updateParams.totalMax;
        claim.startDate = params.updateParams.startDate;
        claim.endDate = params.updateParams.endDate;
        claim.location = params.updateParams.location;
        claim.paymentReceiver = params.updateParams.paymentReceiver;
        claim.cost = params.updateParams.cost;
        claim.merkleRoot = params.updateParams.merkleRoot;
        claim.walletMax = params.updateParams.walletMax;
        claim.allowlistMax = params.updateParams.allowlistMax;
        claim.allowlistActive = params.updateParams.allowlistActive;
    }
    
    // ========== CLAIM ACCESS ==========
    
    /**
     * @notice Get a hybrid claim
     * @param storage_               storage reference
     * @param creatorContractAddress contract address
     * @param instanceId            claim instance ID
     * @return                       the hybrid claim
     */
    function getClaim(
        Storage storage storage_,
        address creatorContractAddress,
        uint256 instanceId
    ) external view returns (ISerendipityAllowlist.AllowlistClaim memory) {
        if (!_claimExists(storage_, creatorContractAddress, instanceId)) {
            revert ClaimNotFound();
        }
        return storage_.claims[creatorContractAddress][instanceId];
    }
    
    /**
     * @notice Get claim by token ID
     * @param storage_               storage reference  
     * @param creatorContractAddress contract address
     * @param tokenId               token ID
     * @return instanceId            claim instance ID
     * @return claim                 the hybrid claim
     */
    function getClaimForToken(
        Storage storage storage_,
        address creatorContractAddress,
        uint256 tokenId
    ) external view returns (uint256 instanceId, ISerendipityAllowlist.AllowlistClaim memory claim) {
        instanceId = storage_.tokenInstances[creatorContractAddress][tokenId];
        if (instanceId == 0) revert ClaimNotFound();
        claim = storage_.claims[creatorContractAddress][instanceId];
    }
    
    // ========== RESERVATION MANAGEMENT ==========
    
    /**
     * @notice Add reservation for a wallet
     * @param storage_               storage reference
     * @param creatorContractAddress contract address
     * @param instanceId            claim instance ID
     * @param wallet                wallet address
     * @param mintCount             number of mints to reserve
     * @param mintIndices           mint indices (for merkle claims)
     */
    function addReservation(
        Storage storage storage_,
        address creatorContractAddress,
        uint256 instanceId,
        address wallet,
        uint32 mintCount,
        uint32[] memory mintIndices
    ) external {
        ISerendipityAllowlist.AllowlistReservation storage reservation = 
            storage_.reservations[creatorContractAddress][instanceId][wallet];
            
        reservation.reservedCount += mintCount;
        
        // Store mint indices if provided (merkle claims)
        if (mintIndices.length > 0) {
            for (uint256 i; i < mintIndices.length;) {
                reservation.mintIndices.push(mintIndices[i]);
                unchecked {
                    ++i;
                }
            }
        }
    }
    
    /**
     * @notice Update delivered count for a reservation
     * @param storage_               storage reference
     * @param creatorContractAddress contract address
     * @param instanceId            claim instance ID
     * @param wallet                wallet address
     * @param deliveredCount        number of tokens delivered
     */
    function updateDeliveredCount(
        Storage storage storage_,
        address creatorContractAddress,
        uint256 instanceId,
        address wallet,
        uint32 deliveredCount
    ) external {
        ISerendipityAllowlist.AllowlistReservation storage reservation = 
            storage_.reservations[creatorContractAddress][instanceId][wallet];
            
        reservation.deliveredCount += deliveredCount;
    }
    
    /**
     * @notice Get reservation for a wallet
     * @param storage_               storage reference
     * @param creatorContractAddress contract address
     * @param instanceId            claim instance ID
     * @param wallet                wallet address
     * @return                       the allowlist reservation
     */
    function getReservation(
        Storage storage storage_,
        address creatorContractAddress,
        uint256 instanceId,
        address wallet
    ) external view returns (ISerendipityAllowlist.AllowlistReservation memory) {
        return storage_.reservations[creatorContractAddress][instanceId][wallet];
    }
    
    // ========== MINT INDEX TRACKING ==========
    
    /**
     * @notice Get mint index tracker reference
     * @param storage_               storage reference
     * @param creatorContractAddress contract address
     * @param instanceId            claim instance ID
     * @return                       reference to mint index tracker
     */
    function getMintTracker(
        Storage storage storage_,
        address creatorContractAddress,
        uint256 instanceId
    ) external view returns (AllowlistMerkleValidator.MintIndexTracker storage) {
        return storage_.mintTrackers[creatorContractAddress][instanceId];
    }
    
    // ========== WALLET MINT COUNTS ==========
    
    /**
     * @notice Increment wallet mint count
     * @param storage_               storage reference
     * @param creatorContractAddress contract address
     * @param instanceId            claim instance ID
     * @param wallet                wallet address
     * @param mintCount             number of mints to add
     */
    function incrementWalletMintCount(
        Storage storage storage_,
        address creatorContractAddress,
        uint256 instanceId,
        address wallet,
        uint32 mintCount
    ) external {
        storage_.walletMintCounts[creatorContractAddress][instanceId][wallet] += mintCount;
    }
    
    /**
     * @notice Get wallet mint count
     * @param storage_               storage reference
     * @param creatorContractAddress contract address
     * @param instanceId            claim instance ID
     * @param wallet                wallet address
     * @return                       wallet mint count
     */
    function getWalletMintCount(
        Storage storage storage_,
        address creatorContractAddress,
        uint256 instanceId,
        address wallet
    ) external view returns (uint32) {
        return storage_.walletMintCounts[creatorContractAddress][instanceId][wallet];
    }
    
    // ========== CLAIM STATE UPDATES ==========
    
    /**
     * @notice Increment total minted count
     * @param storage_               storage reference
     * @param creatorContractAddress contract address
     * @param instanceId            claim instance ID
     * @param mintCount             number of mints to add
     */
    function incrementTotalMinted(
        Storage storage storage_,
        address creatorContractAddress,
        uint256 instanceId,
        uint32 mintCount
    ) external {
        storage_.claims[creatorContractAddress][instanceId].total += mintCount;
    }
    
    /**
     * @notice Increment allowlist minted count
     * @param storage_               storage reference
     * @param creatorContractAddress contract address
     * @param instanceId            claim instance ID
     * @param mintCount             number of allowlist mints to add
     */
    function incrementAllowlistMinted(
        Storage storage storage_,
        address creatorContractAddress,
        uint256 instanceId,
        uint32 mintCount
    ) external {
        storage_.claims[creatorContractAddress][instanceId].allowlistMinted += mintCount;
    }
    
    // ========== INTERNAL HELPERS ==========
    
    /**
     * @notice Check if a claim exists
     * @param storage_               storage reference
     * @param creatorContractAddress contract address
     * @param instanceId            claim instance ID
     * @return                       whether claim exists
     */
    function _claimExists(
        Storage storage storage_,
        address creatorContractAddress,
        uint256 instanceId
    ) internal view returns (bool) {
        return storage_.claims[creatorContractAddress][instanceId].storageProtocol != 
               ISerendipity.StorageProtocol.INVALID;
    }
    
    // ========== BATCH OPERATIONS ==========
    
    /**
     * @notice Batch check mint indices usage
     * @param storage_               storage reference
     * @param creatorContractAddress contract address
     * @param instanceId            claim instance ID
     * @param mintIndices           array of mint indices to check
     * @return usedStatus           array of usage status
     */
    function batchCheckMintIndices(
        Storage storage storage_,
        address creatorContractAddress,
        uint256 instanceId,
        uint32[] calldata mintIndices
    ) external view returns (bool[] memory usedStatus) {
        AllowlistMerkleValidator.MintIndexTracker storage tracker = 
            storage_.mintTrackers[creatorContractAddress][instanceId];
            
        return AllowlistMerkleValidator.checkMintIndices(tracker, mintIndices);
    }
    
    // ========== GAS OPTIMIZATION UTILITIES ==========
    
    /**
     * @notice Check multiple conditions in a single call for gas optimization
     * @param storage_               storage reference
     * @param creatorContractAddress contract address
     * @param instanceId            claim instance ID
     * @param wallet                wallet address
     * @return exists                whether claim exists
     * @return isActive              whether claim is active (within date range)
     * @return allowlistActive       whether allowlist is active
     * @return walletMintCount       current wallet mint count
     */
    function getClaimStatus(
        Storage storage storage_,
        address creatorContractAddress,
        uint256 instanceId,
        address wallet
    ) external view returns (
        bool exists,
        bool isActive,
        bool allowlistActive,
        uint32 walletMintCount
    ) {
        ISerendipityAllowlist.AllowlistClaim storage claim = 
            storage_.claims[creatorContractAddress][instanceId];
            
        exists = claim.storageProtocol != ISerendipity.StorageProtocol.INVALID;
        
        if (exists) {
            uint48 currentTime = uint48(block.timestamp);
            isActive = (claim.startDate == 0 || currentTime >= claim.startDate) &&
                      (claim.endDate == 0 || currentTime <= claim.endDate);
            allowlistActive = claim.allowlistActive;
            walletMintCount = storage_.walletMintCounts[creatorContractAddress][instanceId][wallet];
        }
    }
}