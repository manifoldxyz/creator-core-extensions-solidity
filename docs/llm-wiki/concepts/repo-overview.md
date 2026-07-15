---
title: Repo Overview — creator-core-extensions-solidity
created: 2026-07-15
updated: 2026-07-15
type: overview
package: repo
tags: [overview, contract, erc721, erc1155]
sources: [README.md, manifold/CLAUDE.md, .gitmodules]
confidence: high
---

# Repo Overview — creator-core-extensions-solidity

A monorepo of Solidity **extension applications ("Apps")** that install onto any [Manifold Creator Core](https://github.com/manifoldxyz/creator-core-solidity) ERC-721/ERC-1155 contract (deployed via [Manifold Studio](https://studio.manifold.xyz)) to add mint, burn-redeem, edition, metadata, and other mechanics. Pinned to commit `5bc29bd` (2026-03-20). Solidity `^0.8.17`.

## The shared singleton extension model (read this first)

The single most important concept: these are **shared, singleton extensions**, not per-creator deployments.

- ONE instance of e.g. `ERC721LazyPayableClaim` is deployed **per chain**.
- **Every** creator contract installs that same shared instance as an extension.
- Each creator registers its own **instance** — a claim / burnRedeem / etc. — keyed by `(creatorContractAddress, instanceId)`.
- The extension holds the *logic* and the *funds/fee flow*; the creator contract holds the *tokens* and delegates mint/burn to the registered extension via the Creator Core extension interface.

Config for an instance is gated by `AdminControl.creatorAdminRequired(creator)` — only the creator's admins can create/update their instance. Mints emit standard `Instance*Mint` events (see [[shared-libraries]]).

Exceptions: the `edition` and `lazywhitelist` packages use a **Template/Implementation minimal-proxy clone** pattern (one deployed impl, cloned per creator) rather than the multi-creator singleton keyed by instanceId. See [[edition-package]] and [[lazywhitelist-and-fonts]].

## Package map

| Package | What it is | Wiki page |
|---|---|---|
| **manifold** | The production extension suite — 13+ families (claims, burn-redeem, editions, singles, metadata, soulbound, gacha, deck, frames, physical, operator-filter) | many (below) |
| **dynamic** | On-chain dynamic tokenURI — Arweave hash swap, on-chain SVG, time-based | [[dynamic-and-enumerable]] |
| **edition** | ERC721 numbered & prefix editions via Template/Implementation clones (+ Nifty Gateway variant) | [[edition-package]] |
| **enumerable** | Owner-enumeration extension for creator ERC721 | [[dynamic-and-enumerable]] |
| **lazywhitelist** | Lazy mint gated by a Merkle whitelist, clone pattern | [[lazywhitelist-and-fonts]] |
| **redeem** | The **original/older** burn-redeem implementation (superseded by manifold/burnredeem) | [[redeem-package]] |
| **fonts** | On-chain WOFF font storage interface (interface only) | [[lazywhitelist-and-fonts]] |

## manifold package — the family map

| Family | Pages |
|---|---|
| Lazy Payable Claim (v1 + USDC) | [[lazy-payable-claim]] |
| Lazy Payable Claim V2 (updatable fee) | [[lazy-payable-claim-v2]] |
| Burn Redeem (v1 + V2 updatable fee) | [[burn-redeem]] |
| Cross-Chain Burn | [[cross-chain-burn]] |
| Deck Claims | [[deck-claims]] |
| Gacha / Serendipity | [[gacha-serendipity]] |
| Frame Claims (+ Paymaster) | [[frame-claims]] |
| Editions & Singles | [[editions-and-singles]] |
| Collectible | [[collectible]] |
| Physical Claim | [[physical-claim]] |
| Frozen Metadata | [[metadata-frozen]] |
| Soulbound | [[soulbound]] |
| Operator Filterer | [[operator-filterer]] |
| Shared libraries / plumbing | [[shared-libraries]] |

## Naming conventions (repo-wide)

- Core/base logic: `*Core.sol` (abstract) — e.g. `LazyPayableClaimCore.sol`, `BurnRedeemCore.sol`.
- Token-standard concretes: `ERC721*.sol` / `ERC1155*.sol`.
- Interfaces: `I*.sol`.
- V2 lives in a **separate directory** with a `V2` suffix (`lazyUpdatableFeeClaim/`, `burnredeemUpdatableFee/`) — the defining V2 change across families is an **updatable Manifold mint fee**.
- Custom errors over `require` strings; `unchecked { ++i; }` loops; bitmask/packed-struct gas patterns.

## Tooling

- **Foundry primary** (`forge build` / `forge test`), Truffle for legacy tests. Test matrix: Truffle on `edition`/`lazywhitelist`/`redeem`/`manifold`; Forge on `dynamic`/`enumerable`/`manifold`.
- Each package is independent — `cd packages/<pkg>` then `yarn install` (needs `NPM_TOKEN` for `@manifoldxyz` scoped deps).
- Submodules: `forge-std` (v1.5.6), `operator-filter-registry` (v1.4.1), `murky` (Merkle trees).
- Deploy scripts: `packages/manifold/script/*.s.sol`.

## Version lineage (the traps)

- **redeem package** is the ancestor of burn-redeem; **manifold/burnredeem** superseded it, then **burnredeemUpdatableFee** (V2) superseded that. Same for lazyclaim → lazyUpdatableFeeClaim. Always confirm which version a deployed instance is.
- `edition` package (clone pattern) vs `manifold/edition` (`ManifoldERC721Edition`, singleton) are **different implementations of "editions"** — don't conflate. See [[editions-and-singles]] vs [[edition-package]].

## Open questions

- Per-chain deployed addresses of each shared singleton (live in README/deploy scripts).

Related: [[shared-libraries]], [[lazy-payable-claim]], [[burn-redeem]]
