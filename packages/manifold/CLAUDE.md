# CLAUDE.md - AI Assistant Guidelines

> **Gather context first:** this repo has a source-grounded LLM wiki at the repo root — `docs/llm-wiki/`. Start at `docs/llm-wiki/index.md` (catalog + per-family gotchas), then the family page for whatever you're touching (e.g. `concepts/lazy-payable-claim.md`, `concepts/burn-redeem.md`). It documents contract maps, real signatures/structs, fee handling, and pitfalls for every family in this package, each claim cited to source. On conflict, source wins — then update the wiki page.

## Project Overview
**Manifold Creator Core Extensions** - Solidity smart contracts providing extension functionality for [Manifold Creator Core](https://github.com/manifoldxyz/creator-core-solidity) NFT contracts deployed via [Manifold Studio](https://studio.manifold.xyz).

These are **shared extensions** - single deployed instances that any Manifold Creator contract can install for enhanced functionality.

## Tech Stack
- **Language**: Solidity ^0.8.17
- **Framework**: Foundry (primary), Truffle (legacy tests)
- **Dependencies**:
  - `@manifoldxyz/creator-core-solidity` ^3.0.0
  - OpenZeppelin contracts
- **Test Framework**: Foundry (`forge test`)
- **Build**: `forge build`

## Project Structure
```
contracts/
├── burnredeem/          # Burn-to-redeem NFT mechanics
├── burnredeemUpdatableFee/  # V2 with updatable fees
├── collectible/         # Collectible extensions (ERC721)
├── crossChainBurn/      # Cross-chain burn functionality
├── edition/             # ERC721 batch minting editions
├── frameclaims/         # Farcaster Frame claim extensions
├── gachaclaims/         # Serendipity/gacha mechanics
├── lazyclaim/           # Lazy payable claim pages (ETH)
├── lazyUpdatableFeeClaim/  # V2 lazy claims with updatable fees
├── libraries/           # Shared libraries & interfaces
├── metadata/            # Frozen metadata extensions
├── operatorfilterer/    # OpenSea operator filter support
├── physicalclaim/       # Physical item redemption
├── single/              # Single-creator extensions
└── soulbound/           # Soulbound token extensions
test/                    # Foundry tests (.t.sol) & Truffle tests (.js)
script/                  # Foundry deployment scripts (.s.sol)
```

## Key Extension Types

### Lazy Claim (Claim Pages)
- `LazyPayableClaimCore.sol` - Base logic for payable claims
- Supports merkle tree allowlists
- Delegation registry integration (v1 & v2)
- Signature-based minting
- ERC721 and ERC1155 variants

### Burn Redeem
- Burn existing NFTs to mint new ones
- Supports multiple burn token types
- ERC721 and ERC1155 output variants

### Serendipity (Gacha)
- Randomized NFT minting mechanics
- Supply management with limited/unlimited modes

## Development Commands
```bash
# Install dependencies
npm install

# Build contracts
forge build

# Run all tests
forge test

# Run specific test file
forge test --match-path test/lazyclaim/ERC721LazyPayableClaim.t.sol

# Run with verbosity
forge test -vvv

# Lint
npm run lint
```

## Code Patterns & Conventions

### Contract Architecture
- Extensions inherit from `AdminControl` for access control
- Use `creatorAdminRequired` modifier for creator-specific operations
- Abstract base contracts with ERC721/ERC1155 concrete implementations
- Interface contracts prefixed with `I` (e.g., `ILazyPayableClaimCore`)

### Naming Conventions
- Core/base contracts: `*Core.sol`
- ERC721 implementations: `ERC721*.sol`
- ERC1155 implementations: `ERC1155*.sol`
- Interfaces: `I*.sol`
- V2 contracts in separate directories with `V2` suffix

### Gas Optimization Patterns
```solidity
// Unchecked increments in loops
unchecked { ++i; }

// Bitmask tracking for merkle mints
uint256 internal constant MINT_INDEX_BITMASK = 0xFF;

// Max value constants
uint256 internal constant MAX_UINT_24 = 0xffffff;
```

### Common Imports
```solidity
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
```

### Custom Errors
Use custom errors instead of require strings:
```solidity
revert ILazyPayableClaimCore.ClaimInactive();
revert ILazyPayableClaimCore.InvalidInput();
```

## Testing Patterns
- Foundry tests in `test/**/*.t.sol`
- Mock contracts in `test/mocks/`
- Delegation registry mocks available
- Legacy Truffle tests in `.js` files

## Deployment
- Scripts in `script/*.s.sol`
- Multi-network support (Mainnet, Goerli, Sepolia, Base)
- Addresses documented in README.md

## Solhint Rules
- Compiler version: ^0.8.0
- `not-rely-on-time`: off (timestamps used for claim windows)
- `no-empty-blocks`: off

## Context Summary
This is a mature Solidity codebase for NFT creator extensions. When making changes:
1. Follow existing patterns for new extensions
2. Create both interface and implementation contracts
3. Support both ERC721 and ERC1155 where applicable
4. Include Foundry tests
5. Use custom errors over require strings
6. Apply gas optimizations (unchecked loops, bitmasks)
