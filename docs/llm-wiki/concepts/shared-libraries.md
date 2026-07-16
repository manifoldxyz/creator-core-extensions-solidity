---
title: Shared Libraries & Cross-Cutting Plumbing
created: 2026-07-15
updated: 2026-07-15
type: concept
package: manifold
tags: [library, interface, delegation, membership, admin, event, single, erc721, erc1155]
sources: [manifold/contracts/libraries/IManifoldExtension.sol, manifold/contracts/libraries/manifold-membership/IManifoldMembership.sol, manifold/contracts/libraries/delegation-registry/IDelegationRegistryV2.sol, manifold/contracts/libraries/delegation-registry/IDelegationRegistry.sol, manifold/contracts/libraries/single-creator/SingleCreatorExtensionBase.sol]
confidence: high
---

# Shared Libraries & Cross-Cutting Plumbing

The `contracts/libraries/` directory is **duplicated verbatim in every package** (`manifold`, `dynamic`, `edition`, `enumerable`, `lazywhitelist`, `redeem` each carry their own copy) so each package builds independently. These are the primitives that nearly every extension family in this repo inherits or calls. Understand these once; they recur everywhere.

## The library set (per package `contracts/libraries/`)

| File | Role |
|---|---|
| `manifold-membership/IManifoldMembership.sol` | Manifold Membership check — one method, gates the mint fee |
| `delegation-registry/IDelegationRegistry.sol` | Delegate.xyz **v1** registry interface (delegate-wallet minting) |
| `delegation-registry/IDelegationRegistryV2.sol` | Delegate.xyz **v2** registry interface (typed delegations) |
| `single-creator/SingleCreatorExtensionBase.sol` | Base for extensions bound to ONE creator contract |
| `single-creator/ERC721/…` `ERC1155/…` | ERC721/ERC1155 flavors of the single-creator base |
| `IManifoldExtension.sol` | Standard mint **events** every extension emits (manifold pkg only) |
| `IERC721CreatorCoreVersion.sol` | Version-probe interface for the target creator core |
| `LegacyInterfaces.sol` | Old interface IDs kept for backward-compat ERC165 checks |
| `ABDKMath64x64.sol` | Fixed-point math lib (vendored; used by dynamic/time extensions) |

## Manifold Membership — the fee gate

`IManifoldMembership.isActiveMember(address) → bool`. Extensions that charge a Manifold platform mint fee (all the claim/burn families) check this: an **active member mints without the platform fee**, a non-member pays it. The fee is separate from the creator's own `cost`/price. This single boolean is why "why was I charged extra" answers always route through membership status. ^[manifold/contracts/libraries/manifold-membership/IManifoldMembership.sol]

## Delegation Registry — mint-for-a-vault

Two versions coexist. `mintFor` / delegate parameters in the claim families let a **delegate (hot) wallet** mint on behalf of a **vault (cold) wallet** that actually holds the allowlist/membership entitlement. v1 (`IDelegationRegistry`) is boolean-per-scope; **v2 (`IDelegationRegistryV2`)** adds a typed `DelegationType {NONE, ALL, CONTRACT, ERC721, ERC20, ERC1155}` model with a `Delegation` struct and a `multicall`. Contracts that support v2 check the registry to confirm `delegate → vault` before crediting the vault's allowlist slot. ^[manifold/contracts/libraries/delegation-registry/IDelegationRegistryV2.sol]

## Standard mint events — `IManifoldExtension`

Every manifold extension emits one of three events on mint, so indexers get a uniform signal keyed by `instanceId`:
- `InstanceMint(creator, instanceId, minter, tokenAddress, tokenId, quantity)`
- `InstanceBatchMint(…, tokenIds[], quantity[])`
- `InstanceRangeMint(…, fromTokenId, toTokenId, quantity)`

`instanceId`, `tokenAddress`, `tokenId` are indexed. This is the canonical way to watch mints across all families. ^[manifold/contracts/libraries/IManifoldExtension.sol]

## Single-creator base

`SingleCreatorExtensionBase` stores one `_creator` address and exposes `creatorContract()`. Extensions that serve a single creator (rather than the shared multi-creator singletons keyed by `(creator, instanceId)`) inherit this to hard-bind their creator at deploy. The ERC721/ERC1155 subclasses add the standard-specific interface checks in `_setCreator`. ^[manifold/contracts/libraries/single-creator/SingleCreatorExtensionBase.sol]

## Inherited-but-external plumbing (from `@manifoldxyz/creator-core-solidity` + `libraries-solidity`)

Not in this repo but every extension leans on it:
- **`AdminControl`** — owner + admins; the `creatorAdminRequired(creator)` modifier restricts instance config to the creator's admins.
- **`ICreatorExtensionTokenURI`** — extensions that own metadata implement this; creator core routes `tokenURI` back to the extension.
- **ERC165** — extensions advertise supported interfaces so creator core can discover their capabilities.

## Pitfalls

- **The libraries dir is copy-pasted per package.** A fix in `manifold/contracts/libraries/` does NOT propagate to `redeem/contracts/libraries/`. Check the package you're actually building.
- **v1 vs v2 delegation are not interchangeable** — a contract wired for v1 won't read v2 typed delegations and vice versa. Confirm which registry a given family calls.
- **Membership ≠ allowlist.** Membership waives the *platform* fee; the *creator* cost and any merkle/signature allowlist are independent gates.

## Open questions

- Exact deployed registry addresses per chain (v1 vs v2) live in deploy scripts / README, not here.

Related: [[repo-overview]], [[lazy-payable-claim]], [[burn-redeem]]
