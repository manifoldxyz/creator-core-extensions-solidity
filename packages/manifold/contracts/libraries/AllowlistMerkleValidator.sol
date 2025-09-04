// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title AllowlistMerkleValidator
 * @author manifold.xyz
 * @notice Library for validating merkle proofs and tracking used mint indices for allowlist claims
 * @dev Optimized for gas efficiency with bitmap tracking to prevent replay attacks
 */
library AllowlistMerkleValidator {
    
    // ========== CONSTANTS ==========
    
    /// @notice Bitmask for extracting the lower 8 bits of mint index
    uint256 internal constant MINT_INDEX_BITMASK = 0xFF;
    
    /// @notice Maximum value for uint32
    uint256 internal constant MAX_UINT_32 = 0xffffffff;
    
    // ========== CUSTOM ERRORS ==========
    
    error InvalidMerkleProof();
    error MintIndexAlreadyUsed();
    error InvalidMintIndex();
    error ArrayLengthMismatch();
    
    // ========== STRUCTS ==========
    
    /**
     * @notice Storage structure for tracking consumed mint indices
     * @dev Uses bitmap approach for gas-efficient storage
     */
    struct MintIndexTracker {
        // Maps claimMintIndex => bitmap of used indices
        // claimMintIndex = mintIndex >> 8
        // bitmap position = mintIndex & MINT_INDEX_BITMASK
        mapping(uint256 => uint256) consumedIndices;
    }
    
    /**
     * @notice Validation parameters for single mint
     */
    struct SingleValidationParams {
        bytes32 merkleRoot;
        address account;
        uint32 mintIndex;
        bytes32[] merkleProof;
    }
    
    /**
     * @notice Validation parameters for batch mint
     */
    struct BatchValidationParams {
        bytes32 merkleRoot;
        address account;
        uint32[] mintIndices;
        bytes32[][] merkleProofs;
    }
    
    // ========== VALIDATION FUNCTIONS ==========
    
    /**
     * @notice Validate merkle proof for a single mint and mark index as used
     * @param tracker               storage reference to the mint index tracker
     * @param params               validation parameters
     * @dev Reverts if proof is invalid or index already used
     */
    function validateAndReserve(
        MintIndexTracker storage tracker,
        SingleValidationParams calldata params
    ) external {
        // Validate mint index bounds
        if (params.mintIndex > MAX_UINT_32) revert InvalidMintIndex();
        
        // Check if mint index already used
        if (_isMintIndexUsed(tracker, params.mintIndex)) {
            revert MintIndexAlreadyUsed();
        }
        
        // Validate merkle proof
        if (!_verifyMerkleProof(params.merkleRoot, params.account, params.mintIndex, params.merkleProof)) {
            revert InvalidMerkleProof();
        }
        
        // Mark mint index as used
        _markMintIndexUsed(tracker, params.mintIndex);
    }
    
    /**
     * @notice Validate merkle proofs for batch mints and mark indices as used
     * @param tracker               storage reference to the mint index tracker
     * @param params               batch validation parameters
     * @dev Reverts if any proof is invalid or any index already used
     */
    function batchValidateAndReserve(
        MintIndexTracker storage tracker,
        BatchValidationParams calldata params
    ) external {
        uint256 mintCount = params.mintIndices.length;
        
        // Validate array lengths match
        if (mintCount != params.merkleProofs.length) {
            revert ArrayLengthMismatch();
        }
        
        // Validate each mint index and proof
        for (uint256 i; i < mintCount;) {
            uint32 mintIndex = params.mintIndices[i];
            
            // Validate mint index bounds
            if (mintIndex > MAX_UINT_32) revert InvalidMintIndex();
            
            // Check if mint index already used
            if (_isMintIndexUsed(tracker, mintIndex)) {
                revert MintIndexAlreadyUsed();
            }
            
            // Validate merkle proof
            if (!_verifyMerkleProof(params.merkleRoot, params.account, mintIndex, params.merkleProofs[i])) {
                revert InvalidMerkleProof();
            }
            
            // Mark mint index as used
            _markMintIndexUsed(tracker, mintIndex);
            
            unchecked {
                ++i;
            }
        }
    }
    
    /**
     * @notice Validate merkle proof without reserving (read-only verification)
     * @param merkleRoot           the merkle root to verify against
     * @param account             the account address
     * @param mintIndex           the mint index
     * @param merkleProof         the merkle proof
     * @return                     whether the proof is valid
     */
    function verifyProof(
        bytes32 merkleRoot,
        address account,
        uint32 mintIndex,
        bytes32[] calldata merkleProof
    ) external pure returns (bool) {
        return _verifyMerkleProof(merkleRoot, account, mintIndex, merkleProof);
    }
    
    // ========== VIEW FUNCTIONS ==========
    
    /**
     * @notice Check if a mint index has been used
     * @param tracker               storage reference to the mint index tracker
     * @param mintIndex            the mint index to check
     * @return                      whether the mint index has been used
     */
    function isMintIndexUsed(
        MintIndexTracker storage tracker,
        uint32 mintIndex
    ) external view returns (bool) {
        return _isMintIndexUsed(tracker, mintIndex);
    }
    
    /**
     * @notice Check if multiple mint indices have been used
     * @param tracker               storage reference to the mint index tracker
     * @param mintIndices          array of mint indices to check
     * @return usedStatus           array of boolean values indicating usage status
     */
    function checkMintIndices(
        MintIndexTracker storage tracker,
        uint32[] calldata mintIndices
    ) external view returns (bool[] memory usedStatus) {
        uint256 length = mintIndices.length;
        usedStatus = new bool[](length);
        
        for (uint256 i; i < length;) {
            usedStatus[i] = _isMintIndexUsed(tracker, mintIndices[i]);
            unchecked {
                ++i;
            }
        }
    }
    
    // ========== INTERNAL FUNCTIONS ==========
    
    /**
     * @notice Internal function to verify merkle proof
     * @param merkleRoot           the merkle root to verify against
     * @param account             the account address
     * @param mintIndex           the mint index
     * @param merkleProof         the merkle proof
     * @return                     whether the proof is valid
     * @dev Merkle leaf = keccak256(abi.encodePacked(account, mintIndex))
     */
    function _verifyMerkleProof(
        bytes32 merkleRoot,
        address account,
        uint32 mintIndex,
        bytes32[] memory merkleProof
    ) internal pure returns (bool) {
        // Empty merkle root means no allowlist validation required
        if (merkleRoot == bytes32(0)) {
            return true;
        }
        
        // Construct leaf node from account and mint index
        bytes32 leaf = keccak256(abi.encodePacked(account, mintIndex));
        
        // Verify proof against merkle root
        return MerkleProof.verify(merkleProof, merkleRoot, leaf);
    }
    
    /**
     * @notice Internal function to check if mint index is used
     * @param tracker               storage reference to the mint index tracker
     * @param mintIndex            the mint index to check
     * @return                      whether the mint index has been used
     * @dev Uses bitmap storage for gas efficiency
     */
    function _isMintIndexUsed(
        MintIndexTracker storage tracker,
        uint32 mintIndex
    ) internal view returns (bool) {
        uint256 claimMintIndex = mintIndex >> 8;  // Upper 24 bits
        uint256 bitmask = 1 << (mintIndex & MINT_INDEX_BITMASK);  // Lower 8 bits
        return tracker.consumedIndices[claimMintIndex] & bitmask != 0;
    }
    
    /**
     * @notice Internal function to mark mint index as used
     * @param tracker               storage reference to the mint index tracker
     * @param mintIndex            the mint index to mark as used
     * @dev Uses bitmap storage for gas efficiency
     */
    function _markMintIndexUsed(
        MintIndexTracker storage tracker,
        uint32 mintIndex
    ) internal {
        uint256 claimMintIndex = mintIndex >> 8;  // Upper 24 bits
        uint256 bitmask = 1 << (mintIndex & MINT_INDEX_BITMASK);  // Lower 8 bits
        
        // Set the bit to mark as used
        tracker.consumedIndices[claimMintIndex] |= bitmask;
    }
    
    // ========== UTILITY FUNCTIONS ==========
    
    /**
     * @notice Generate merkle leaf for given account and mint index
     * @param account             the account address
     * @param mintIndex           the mint index
     * @return                     the merkle leaf hash
     */
    function generateMerkleLeaf(address account, uint32 mintIndex) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, mintIndex));
    }
    
    /**
     * @notice Batch generate merkle leaves for given accounts and indices
     * @param accounts            array of account addresses
     * @param mintIndices         array of mint indices
     * @return leaves            array of merkle leaf hashes
     */
    function batchGenerateMerkleLeaves(
        address[] calldata accounts,
        uint32[] calldata mintIndices
    ) external pure returns (bytes32[] memory leaves) {
        if (accounts.length != mintIndices.length) revert ArrayLengthMismatch();
        
        uint256 length = accounts.length;
        leaves = new bytes32[](length);
        
        for (uint256 i; i < length;) {
            leaves[i] = keccak256(abi.encodePacked(accounts[i], mintIndices[i]));
            unchecked {
                ++i;
            }
        }
    }
}