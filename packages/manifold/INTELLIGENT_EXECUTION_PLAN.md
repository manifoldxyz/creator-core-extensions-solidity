# Intelligent Execution Plan - ERC1155 Serendipity with Allowlist

## 🎯 Project Overview

Enhance the ERC1155Serendipity contract with merkle tree-based allowlist functionality, following the proven patterns from ERC1155LazyPayableClaim while maintaining the unique two-phase (reserve → deliver) minting mechanism.

## 🔍 Discovery-Driven Foundation

### Critical Shared Interfaces
Based on codebase analysis, these interfaces and patterns must be implemented:

```solidity
// From LazyPayableClaim pattern:
- Merkle proof validation using OpenZeppelin
- Bitmap-based index tracking (256 indices per slot)
- Per-wallet mint tracking for non-merkle claims
- Delegation support for merkle mints
```

### Dependency Analysis
- **Base Contract**: Serendipity.sol (shared functionality)
- **Interface**: IERC1155Serendipity.sol (must extend)
- **Libraries**: OpenZeppelin (MerkleProof, Math, Strings)
- **Creator Core**: IERC1155CreatorCore (for minting)

## 📋 Stage-Based Execution Plan

### Stage 1: Interface & Type Contracts (20-30 minutes)
```yaml
interface_update:
  agent: "backend-engineer"
  duration: "20-30m"
  tasks:
    - Update IERC1155SerendipityWithAllowlist interface
    - Add merkleRoot and walletMax to Claim struct
    - Add new ClaimParameters fields
    - Define new function signatures for merkle minting
  input:
    - Existing IERC1155Serendipity.sol interface
    - LazyPayableClaim patterns for reference
  output:
    - Updated interface with allowlist support
    - Type definitions matching LazyPayableClaim pattern
  validation:
    - Interface compiles without errors
    - All types properly defined
```

### Stage 2: Core Contract Implementation (45-60 minutes)
```yaml
contract_implementation:
  agent: "backend-engineer"
  duration: "45-60m"
  tasks:
    - Implement ERC1155SerendipityWithAllowlist contract
    - Add storage mappings for merkle indices and wallet mints
    - Implement merkle validation in mintReserve
    - Add index tracking with bitmap storage
    - Implement check functions for mint status
  input:
    - Updated interface from Stage 1
    - LazyPayableClaimCore.sol as reference
    - Existing ERC1155Serendipity.sol to extend
  output:
    - Complete contract implementation
    - All merkle validation logic
    - Backward compatible with non-merkle claims
  validation:
    - Contract compiles successfully
    - All functions implemented
    - Storage patterns match LazyPayableClaim
```

### Stage 3: Validation & Helper Functions (30-40 minutes)
```yaml
validation_helpers:
  agent: "backend-engineer"
  duration: "30-40m"
  tasks:
    - Implement _validateMerkle internal function
    - Add _checkMerkleAndUpdate logic
    - Implement getTotalMints for wallet tracking
    - Add checkMintIndex/checkMintIndices functions
    - Ensure proper error handling
  input:
    - Core contract from Stage 2
    - LazyPayableClaimCore validation patterns
  output:
    - Complete validation logic
    - Helper functions for merkle checks
    - Proper error messages
  validation:
    - All validation paths covered
    - Error messages match interface
```

### Stage 4: Testing Implementation (60-75 minutes)
```yaml
comprehensive_testing:
  agent: "qa-engineer"
  duration: "60-75m"
  tasks:
    - Write unit tests for merkle validation
    - Test bitmap index tracking
    - Test per-wallet limits
    - Test backward compatibility
    - Edge case testing (double mint, invalid proofs)
    - Gas optimization tests
  input:
    - Completed contract from Stages 2-3
    - Existing ERC1155Serendipity.t.sol tests
    - LazyPayableClaim test patterns
  output:
    - Comprehensive test suite
    - >95% code coverage
    - Gas benchmarks
  validation:
    - All tests passing
    - No security vulnerabilities
    - Gas costs acceptable
```

### Stage 5: Integration Testing (30-45 minutes)
```yaml
integration_tests:
  agent: "qa-engineer"
  duration: "30-45m"
  tasks:
    - Test with Creator Core contracts
    - Full flow testing (initialize → reserve → deliver)
    - Test mixed merkle/non-merkle claims
    - Frontend integration scenarios
    - Multi-user concurrent minting
  input:
    - Completed contract and unit tests
    - Creator Core test contracts
  output:
    - Integration test suite
    - End-to-end flow validation
  validation:
    - Full flows work correctly
    - No integration issues
```

### Stage 6: Security Audit (30-40 minutes)
```yaml
security_review:
  agent: "security-auditor"
  duration: "30-40m"
  tasks:
    - Review merkle proof validation
    - Check for reentrancy vulnerabilities
    - Validate access control
    - Review fund management
    - Check for overflow/underflow
    - Verify no double-spending possible
  input:
    - Complete implementation
    - Test results
  output:
    - Security audit report
    - Vulnerability fixes if needed
  validation:
    - No critical vulnerabilities
    - All security best practices followed
```

### Stage 7: Documentation & Deployment Prep (20-30 minutes)
```yaml
documentation:
  agent: "backend-engineer"
  duration: "20-30m"
  tasks:
    - Write deployment script
    - Create integration guide
    - Document merkle tree generation
    - API documentation for frontend
    - Migration guide from existing claims
  input:
    - Final contract implementation
    - Test results
  output:
    - Deployment scripts
    - Complete documentation
    - Frontend integration guide
  validation:
    - Documentation complete
    - Scripts tested
```

## 🚦 Quality Checkpoints

### Checkpoint 1: After Interface Update
```yaml
tests:
  - Interface compiles successfully
  - All new types defined
  - Backward compatibility maintained
```

### Checkpoint 2: After Core Implementation
```yaml
tests:
  - Contract compiles without warnings
  - All functions implemented
  - Storage layout optimized
  - Gas estimates acceptable
```

### Checkpoint 3: After Testing
```yaml
tests:
  - Unit tests: 100% pass rate
  - Integration tests: Full flow works
  - Security: No vulnerabilities found
  - Gas: Within acceptable limits
```

## 🔗 Implementation Guidelines

### Critical Implementation Details

1. **Merkle Leaf Format**
```solidity
bytes32 leaf = keccak256(abi.encodePacked(address, mintIndex));
```

2. **Bitmap Storage Pattern**
```solidity
uint256 claimMintIndex = mintIndex >> 8;  // Upper 24 bits
uint256 mintBitmask = 1 << (mintIndex & 0xFF);  // Lower 8 bits
```

3. **Validation Flow**
- Check dates and active status
- Validate merkle proof if merkleRoot exists
- Check and update bitmap for used indices
- Track per-wallet mints for non-merkle

4. **Backward Compatibility**
- Empty merkleRoot = public minting
- Original mintReserve function still works
- No changes to delivery phase

## 📊 Success Criteria

- ✅ All existing functionality preserved
- ✅ Merkle allowlist fully functional
- ✅ Gas costs <10% higher than original
- ✅ 100% test coverage on new code
- ✅ Security audit passed
- ✅ Frontend can integrate seamlessly

## 🎬 Execution Sequence

```bash
# Recommended command sequence:
1. Stage 1: Interface Update (backend-engineer)
2. Stage 2: Core Implementation (backend-engineer) 
3. Stage 3: Validation Helpers (backend-engineer)
4. Stage 4: Unit Testing (qa-engineer)
5. Stage 5: Integration Testing (qa-engineer)
6. Stage 6: Security Audit (security-auditor)
7. Stage 7: Documentation (backend-engineer)

# Total estimated time: 4-5 hours
```

## 🔒 Risk Mitigation

- **Risk**: Breaking existing claims
  - **Mitigation**: Extensive backward compatibility testing
  
- **Risk**: Gas costs too high
  - **Mitigation**: Bitmap storage optimization, gas benchmarking
  
- **Risk**: Security vulnerabilities
  - **Mitigation**: Follow LazyPayableClaim patterns, security audit

- **Risk**: Frontend integration issues
  - **Mitigation**: Clear documentation, example implementations