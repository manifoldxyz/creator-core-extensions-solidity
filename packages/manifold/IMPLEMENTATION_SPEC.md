# Implementation Specification: ERC1155 Serendipity with Allowlist Support

## Executive Summary

We are enhancing the existing ERC1155Serendipity contract to support merkle tree-based allowlists, enabling controlled access to blind mint (gacha) claims. This implementation will mirror the approach used in the ERC1155LazyPayableClaim contract, maintaining consistency across the codebase while adding allowlist functionality to the Serendipity two-phase minting system.

## Requirements

### Functional Requirements

1. **Merkle Tree Allowlist Support**
   - Add optional merkle root to claim parameters
   - Support merkle proof validation during mintReserve
   - Track used merkle indices to prevent double-minting
   - Allow both allowlisted and public minting (when merkle root is empty)

2. **Per-Wallet Limits**
   - Support walletMax parameter for non-merkle claims
   - Track mints per wallet for limit enforcement
   - Provide getter function for checking wallet mint counts

3. **Mint Index Tracking**
   - Implement bitmap-based tracking for merkle claim indices
   - Support checking if specific indices have been used
   - Batch check functionality for multiple indices

4. **Backward Compatibility**
   - Existing claims without merkle roots continue to work
   - No breaking changes to current API
   - Preserve all existing functionality

### Non-Functional Requirements

1. **Gas Efficiency**
   - Use bitmap storage for mint index tracking (256 indices per storage slot)
   - Minimize storage operations
   - Efficient merkle proof validation

2. **Security**
   - Prevent replay attacks on merkle proofs
   - Maintain existing security checks (no contract minting, etc.)
   - Proper validation of all inputs

3. **Consistency**
   - Follow patterns from LazyPayableClaim implementation
   - Maintain code style and conventions
   - Use existing error definitions where applicable

## Technical Architecture

### System Overview

The enhanced ERC1155SerendipityWithAllowlist contract extends the base Serendipity functionality with merkle tree allowlist support, following the two-phase minting pattern:
1. **Reserve Phase**: Users mint reservations (with optional allowlist validation)
2. **Delivery Phase**: Admin delivers actual NFT variations to reserved users

### Components

#### 1. Updated Claim Structure
```solidity
struct Claim {
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
    bytes32 merkleRoot;    // NEW: Optional merkle root for allowlist
    uint32 walletMax;      // NEW: Per-wallet limit for non-merkle claims
}
```

#### 2. Storage Mappings
```solidity
// Existing mappings
mapping(address => mapping(uint256 => Claim)) private _claims;
mapping(address => mapping(uint256 => uint256)) private _tokenInstances;

// New mappings for allowlist support
// For merkle claims: track used indices via bitmap
mapping(address => mapping(uint256 => mapping(uint256 => uint256))) private _claimMintIndices;

// For non-merkle claims: track mints per wallet
mapping(address => mapping(uint256 => mapping(address => uint256))) private _mintsPerWallet;
```

#### 3. Key Functions

##### Initialize Claim (Updated)
```solidity
function initializeClaim(
    address creatorContractAddress,
    uint256 instanceId,
    ClaimParameters calldata claimParameters
) external payable
```
- Adds merkleRoot and walletMax to ClaimParameters
- Stores these values in the Claim struct

##### Mint Reserve with Merkle (New Overload)
```solidity
function mintReserve(
    address creatorContractAddress,
    uint256 instanceId,
    uint32 mintCount,
    uint32[] calldata mintIndices,
    bytes32[][] calldata merkleProofs,
    address mintFor
) external payable
```
- Validates merkle proofs for each mint
- Updates bitmap to track used indices
- Supports delegation through mintFor parameter

##### Check Functions (New)
```solidity
function checkMintIndex(address creatorContractAddress, uint256 instanceId, uint32 mintIndex) external view returns (bool)
function checkMintIndices(address creatorContractAddress, uint256 instanceId, uint32[] calldata mintIndices) external view returns (bool[] memory)
function getTotalMints(address minter, address creatorContractAddress, uint256 instanceId) external view returns (uint32)
```

### Data Models

#### ClaimParameters (Updated)
```solidity
struct ClaimParameters {
    StorageProtocol storageProtocol;
    uint32 totalMax;
    uint48 startDate;
    uint48 endDate;
    uint8 tokenVariations;
    string location;
    address payable paymentReceiver;
    uint96 cost;
    address erc20;
    bytes32 merkleRoot;  // NEW
    uint32 walletMax;    // NEW
}
```

#### UpdateClaimParameters (Updated)
```solidity
struct UpdateClaimParameters {
    StorageProtocol storageProtocol;
    address payable paymentReceiver;
    uint32 totalMax;
    uint48 startDate;
    uint48 endDate;
    uint96 cost;
    string location;
    bytes32 merkleRoot;  // NEW
    uint32 walletMax;    // NEW
}
```

### API Specifications

#### mintReserve Variations
1. **Original (backward compatible)**
   - `mintReserve(address, uint256, uint32)` - For non-merkle claims

2. **Single Merkle Mint**
   - `mintReserve(address, uint256, uint32, bytes32[], address)` - Single merkle proof

3. **Batch Merkle Mint**
   - `mintReserve(address, uint256, uint32, uint32[], bytes32[][], address)` - Multiple merkle proofs

## User Flows

### Admin Flow - Creating Allowlisted Claim
1. Admin prepares merkle tree of allowed addresses with indices
2. Calls `initializeClaim` with merkle root in parameters
3. Sets other parameters (cost, dates, variations, etc.)
4. Claim is ready for allowlisted minting

### User Flow - Allowlisted Minting
1. User obtains merkle proof from frontend/API
2. Calls `mintReserve` with proof and mint index
3. Contract validates proof and checks index not used
4. Reservation is recorded, payment processed
5. Later, admin delivers variations via `deliverMints`

### User Flow - Public Minting (No Allowlist)
1. User calls standard `mintReserve` (no merkle proof)
2. Contract checks walletMax if configured
3. Standard reservation and delivery flow continues

## Integration Points

### External Dependencies
- OpenZeppelin MerkleProof library for validation
- OpenZeppelin ECDSA for signature validation (if needed)
- Manifold Creator Core contracts for minting

### Frontend Requirements
- Merkle tree generation for allowlists
- Proof generation for users
- Index tracking to prevent duplicate attempts

## Security Considerations

### Merkle Proof Validation
- Leaf format: `keccak256(abi.encodePacked(address, mintIndex))`
- Prevents proof reuse across different addresses
- Index ensures each proof used only once

### Access Control
- Maintain existing admin requirements
- Preserve contract minting prevention
- Validate all input parameters

### Fund Management
- No changes to payment flow
- Maintain existing refund logic
- Preserve payment receiver configuration

## Testing Strategy

### Unit Tests
- Merkle proof validation (valid/invalid proofs)
- Index tracking and bitmap operations
- Per-wallet limits for non-merkle claims
- Backward compatibility with existing claims

### Integration Tests
- Full flow: initialize → reserve → deliver
- Mixed merkle and non-merkle claims
- Edge cases (sold out, expired, etc.)
- Gas consumption benchmarks

### Security Tests
- Attempt double-minting with same proof
- Invalid merkle proofs
- Overflow/underflow scenarios
- Access control violations

## Deployment Plan

1. Deploy new ERC1155SerendipityWithAllowlist contract
2. Transfer ownership to appropriate admin
3. Register with creator contracts as needed
4. Migrate existing claims if necessary
5. Update frontend to support merkle proofs

## Success Metrics

- Successful merkle-based allowlist minting
- No breaking changes to existing functionality
- Gas costs comparable to LazyPayableClaim
- All tests passing with >95% coverage
- Successful audit with no critical findings

## Validated Assumptions

Based on LazyPayableClaim implementation:
- Merkle tree approach for allowlists (gas efficient)
- Bitmap storage for index tracking (256 per slot)
- Per-wallet tracking for non-merkle claims
- Support for both merkle and non-merkle in same contract
- Merkle root stored in claim struct
- Index format: upper 24 bits for slot, lower 8 for position
- Leaf format includes address and index
- No updateability of merkle root after initialization