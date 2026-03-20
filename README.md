# Creator Core Extension Applications (Apps) — Solidity Contracts

A library of extension applications (Apps) for use with [Manifold Creator Core](https://github.com/manifoldxyz/creator-core-solidity) contracts. These extensions add functionality — claims, burn-redeems, editions, metadata, and more — to any Manifold Creator Core ERC-721 or ERC-1155 contract deployed via [Manifold Studio](https://studio.manifold.xyz).

## Prerequisites

- [Node.js](https://nodejs.org/) v20+
- [Yarn](https://yarnpkg.com/)
- [Truffle](https://trufflesuite.com/) (`yarn global add truffle`)
- [Ganache CLI](https://github.com/trufflesuite/ganache) (`yarn global add ganache-cli`)
- [Foundry](https://book.getfoundry.sh/getting-started/installation) (for `dynamic`, `enumerable`, and `manifold` packages)
- NPM registry access token (`NPM_TOKEN`) for `@manifoldxyz` scoped packages

## Setup

```bash
# Clone with submodules
git clone --recurse-submodules git@github.com:manifoldxyz/creator-core-extensions-solidity.git
cd creator-core-extensions-solidity

# Install dependencies for a specific package
cd packages/<package-name>
echo "//registry.npmjs.org/:_authToken=$NPM_TOKEN" > .npmrc
yarn install
```

Each package is independent — install and build within the specific package directory you're working on.

## Architecture

This is a monorepo organized into independent Solidity extension packages:

```
creator-core-extensions-solidity/
├── packages/
│   ├── manifold/          # Core Manifold extensions (claims, burn-redeem, metadata, etc.)
│   ├── dynamic/           # Dynamic token extensions (SVG, Arweave hash, time-based)
│   ├── edition/           # ERC-721 edition contracts (numbered, prefix)
│   ├── enumerable/        # Owner-enumerable extensions for ERC-721
│   ├── lazywhitelist/     # Lazy mint with whitelist support
│   ├── redeem/            # Token redeem/burn mechanics (ERC-721/ERC-1155)
│   └── fonts/             # On-chain font storage (WOFF)
├── .github/workflows/     # CI — Truffle + Forge test matrix
└── .gitmodules            # forge-std, operator-filter-registry, murky
```

### Package Details

| Package | Description | Test Framework |
|---------|-------------|----------------|
| **manifold** | Production claim apps: lazy payable claims, burn-redeem (v1 & v2), cross-chain burn, deck claims, gacha/serendipity, frame claims, physical claims, editions, singles, soulbound, frozen metadata, operator filterer | Truffle + Forge |
| **dynamic** | Dynamic NFT extensions — SVG rendering, Arweave hash updates, time-based tokens | Truffle + Forge |
| **edition** | ERC-721 edition contracts — numbered editions, prefix editions with template/implementation pattern | Truffle |
| **enumerable** | Owner-enumerable extensions for tracking token ownership on ERC-721 Creator Core | Forge |
| **lazywhitelist** | Lazy minting with Merkle-tree whitelist verification | Truffle |
| **redeem** | Token burn-and-redeem mechanics for ERC-721 and ERC-1155 | Truffle |
| **fonts** | On-chain WOFF font storage interface | — |

### Key Contract Families (manifold package)

- **Lazy Claims** — `LazyPayableClaim`, `ERC721LazyPayableClaim`, `ERC1155LazyPayableClaim` + USDC variants + V2 (updatable fee)
- **Burn Redeem** — `BurnRedeemCore`, `ERC721BurnRedeem`, `ERC1155BurnRedeem` + V2
- **Cross-Chain Burn** — `CrossChainBurn` for multi-chain token burning
- **Deck Claims** — `Deck`, `ERC1155Deck` for card-deck style reveals
- **Gacha/Serendipity** — `Serendipity`, `ERC1155Serendipity` for randomized claims
- **Frame Claims** — `FrameLazyClaim`, `FramePaymaster` for Farcaster Frame minting
- **Physical Claims** — `PhysicalClaim` for physical item redemption
- **Editions** — `ManifoldERC721Edition` for managed editions
- **Singles** — `ManifoldERC721Single`, `ManifoldERC1155Single` for 1/1 minting
- **Metadata** — `ERC721FrozenMetadata`, `ERC1155FrozenMetadata` for immutable metadata
- **Soulbound** — `Soulbound`, `ERC721Soulbound`, `ERC1155Soulbound` for non-transferable tokens
- **Operator Filterer** — `CreatorOperatorFilterer`, `OperatorFilterer` for marketplace filtering

## Available Scripts

Each package has the same set of npm scripts:

| Command | Description |
|---------|-------------|
| `yarn test` | Run Truffle tests (starts ganache internally) |
| `yarn compile` | Compile contracts via Truffle |
| `yarn develop` | Start Truffle develop console |
| `yarn test-server` | Start Ganache CLI (quiet mode, 50 accounts) |
| `yarn debug-server` | Start Ganache CLI (verbose mode, 50 accounts) |
| `yarn startLocal` | Start deterministic Ganache with high gas limit |
| `yarn deployLocal` | Deploy to local development network |
| `yarn lint` | Run Solhint linter |

For Forge-enabled packages (`dynamic`, `enumerable`, `manifold`):

```bash
forge build     # Compile with Foundry
forge test      # Run Forge tests
forge coverage  # Generate coverage report
```

### Deployment Scripts (manifold package)

The `packages/manifold/script/` directory contains Forge deployment scripts for each contract:

```bash
forge script script/ERC721LazyPayableClaim.s.sol --rpc-url <RPC_URL> --broadcast
```

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `NPM_TOKEN` | NPM registry auth token for `@manifoldxyz` scoped packages | Yes |
| `RPC_URL` | Ethereum RPC endpoint (for deployment scripts) | For deployment |
| `PRIVATE_KEY` | Deployer wallet private key | For deployment |
| `ETHERSCAN_API_KEY` | Etherscan API key for contract verification | For verification |

## External Dependencies

### Internal Packages

| Package | Version | Purpose |
|---------|---------|---------|
| `@manifoldxyz/creator-core-solidity` | `^3.0.0` | Core Creator contract interfaces and base implementations |

### Git Submodules

| Submodule | Source | Purpose |
|-----------|--------|---------|
| `forge-std` | [foundry-rs/forge-std](https://github.com/foundry-rs/forge-std) v1.5.6 | Foundry test utilities and cheatcodes |
| `operator-filter-registry` | [ProjectOpenSea/operator-filter-registry](https://github.com/ProjectOpenSea/operator-filter-registry) v1.4.1 | OpenSea operator filtering for marketplace compliance |
| `murky` | [dmfxyz/murky](https://github.com/dmfxyz/murky) | Merkle tree implementation for whitelist verification |

### Third-Party Services

| Service | Purpose | Config |
|---------|---------|--------|
| Ethereum RPC (Infura/Alchemy) | Mainnet/testnet deployment | `RPC_URL` env var |
| Etherscan | Contract source verification | `ETHERSCAN_API_KEY` env var |
| OpenSea | Operator filter registry integration | On-chain submodule |

## CI/CD

GitHub Actions runs on PRs and pushes to `main`:

- **Truffle tests**: `edition`, `lazywhitelist`, `redeem`, `manifold` — compiles and runs full test suite with ganache
- **Forge tests**: `dynamic`, `enumerable`, `manifold` — builds, tests, and generates coverage reports

## Related Repositories

- [creator-core-solidity](https://github.com/manifoldxyz/creator-core-solidity) — Core ERC-721/ERC-1155 Creator contracts
- [studio-client-v3](https://github.com/manifoldxyz/studio-client-v3) — Manifold Studio frontend
- [contract-deployer-server](https://github.com/manifoldxyz/contract-deployer-server) — Contract deployment service

## License

See individual package directories for license information.
