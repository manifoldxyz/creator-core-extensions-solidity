# CLAUDE.md - AI Assistant Guide for Manifold Creator Core Extensions

## Project Overview

This is **Manifold's Creator Core Extensions** - a Solidity smart contract package containing shared extensions for [Manifold Creator Core](https://github.com/manifoldxyz/creator-core-solidity) contracts. These extensions provide enhanced functionality for NFT creators using the Manifold ecosystem.

**Key Principle**: Single deployed instances of each extension serve all creator contracts. Creators install the same extension instance and access functionality through it.

## Technology Stack

- **Language**: Solidity 0.8.17
- **Build System**: Foundry (primary), Truffle (legacy support)
- **Testing**: Foundry tests (`forge test`)
- **Dependencies**:
  - `@manifoldxyz/creator-core-solidity` ^3.0.0
  - OpenZeppelin contracts (via creator-core)
  - forge-std (testing)
  - operator-filter-registry

## Project Structure

```
contracts/
├── burnredeem/           # Burn-to-redeem NFT functionality
├── burnredeemUpdatableFee/  # V2 with updatable fees
├── collectible/          # ERC721 collectibles
├── crossChainBurn/       # Cross-chain burn functionality
├── edition/              # Batch minting (ERC721 editions)
├── frameclaims/          # Farcaster Frame claims
├── gachaclaims/          # Serendipity (gacha/random) claims
├── lazyclaim/            # Lazy claim pages (primary claim system)
├── lazyUpdatableFeeClaim/   # V2 lazy claims with updatable fees
├── libraries/            # Shared utilities & interfaces
├── metadata/             # Frozen metadata extensions
├── operatorfilterer/     # OpenSea operator filter support
├── physicalclaim/        # Physical item claims
├── single/               # Single token minting
└── soulbound/            # Non-transferable tokens
script/                   # Foundry deployment scripts
test/                     # Foundry tests (.t.sol) + Truffle tests (.js)
```

## Core Extension Types

### Lazy Claims (`lazyclaim/`, `lazyUpdatableFeeClaim/`)
- Claim page functionality for airdrops and mints
- Supports ERC721 and ERC1155
- Variants: Standard, USDC payment, Signature minting, Updatable fees

### Burn Redeem (`burnredeem/`, `burnredeemUpdatableFee/`)
- Burn tokens to receive new tokens
- Supports complex burn requirements (AND/OR rules)
- ERC721 and ERC1155 output support

### Serendipity/Gacha (`gachaclaims/`)
- Random distribution minting system
- ERC1155 output with weighted randomness
- Current development focus (gacha-v2 branch)

### Edition (`edition/`)
- Efficient batch minting for ERC721
- Single and multi-recipient support

## Development Commands

```bash
# Install dependencies
npm install

# Compile contracts
forge build

# Run all tests
forge test

# Run specific test file
forge test --match-path test/gacha/ERC1155Serendipity.t.sol

# Run with verbosity
forge test -vvv

# Gas report
forge test --gas-report
```

## Coding Conventions

### Contract Naming
- Interface: `I{ContractName}.sol` (e.g., `ISerendipity.sol`)
- Implementation: `{ContractName}.sol` (e.g., `Serendipity.sol`)
- Token-specific: `{TokenStandard}{Feature}.sol` (e.g., `ERC1155Serendipity.sol`)
- Versioned: `{ContractName}V2.sol` for updatable fee versions

### Architecture Pattern
- **Core contract**: Base logic (e.g., `Serendipity.sol`, `LazyPayableClaimCore.sol`)
- **Token implementation**: Token-specific wrapper (e.g., `ERC1155Serendipity.sol`)
- **Interface**: Public API definition (e.g., `ISerendipity.sol`)

### Common Patterns
- Admin functions use `adminRequired` modifier
- Creator functions check `creatorAdminRequired(creatorContractAddress)`
- Extensions inherit from `AdminControl` for permission management
- Uses delegation registry for wallet delegation support
- Manifold membership integration for fee discounts

### Test File Naming
- Foundry tests: `{ContractName}.t.sol`
- Located in `test/{feature}/` directories

## Key Interfaces & Libraries

### From creator-core-solidity
- `IERC721CreatorCore`, `IERC1155CreatorCore` - Creator contract interfaces
- `AdminControl` - Admin permission management
- `ERC721SingleCreatorExtension`, `ERC1155SingleCreatorExtension` - Base extension classes

### Internal Libraries
- `contracts/libraries/delegation-registry/` - Wallet delegation
- `contracts/libraries/manifold-membership/` - Membership verification
- `ABDKMath64x64.sol` - Fixed-point math

## Deployment

Scripts are in `script/` directory, one per contract:
```bash
forge script script/{ContractName}.s.sol --rpc-url <RPC_URL> --broadcast
```

## Testing Tips

1. Mock contracts are in `test/mocks/`
2. Delegation registry mocks available for testing delegation features
3. Use `vm.prank()` for caller impersonation in Foundry tests
4. Test both happy path and revert conditions

## Security Considerations

- All state-changing functions should have proper access control
- Reentrancy guards on external calls
- Check for zero addresses in initializations
- Validate merkle proofs for allowlist claims
- Signature verification for authorized mints
