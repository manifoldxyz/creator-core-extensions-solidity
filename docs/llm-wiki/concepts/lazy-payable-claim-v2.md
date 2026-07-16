---
title: Lazy Payable Claim V2 (Updatable Fee)
created: 2026-07-15
updated: 2026-07-15
type: concept
package: manifold
tags: [contract, abstract, interface, claim, erc721, erc1155, merkle, signature, delegation, membership, fee, version-v2, pitfall]
sources: [manifold/contracts/lazyUpdatableFeeClaim/LazyPayableClaimV2.sol, manifold/contracts/lazyUpdatableFeeClaim/ERC721LazyPayableClaimV2.sol, manifold/contracts/lazyUpdatableFeeClaim/ERC1155LazyPayableClaimV2.sol, manifold/contracts/lazyUpdatableFeeClaim/ILazyPayableClaimV2.sol, manifold/contracts/lazyclaim/LazyPayableClaimCore.sol, manifold/contracts/lazyclaim/LazyPayableClaim.sol]
confidence: high
---

# Lazy Payable Claim V2 (Updatable Fee)

## What it is

V2 of the [[lazy-payable-claim]] family. Same **shared singleton** model (one instance per chain, claims keyed by `(creatorContractAddress, instanceId)`), same `Claim` struct, same merkle/signature/delegation/membership mechanics — the **only** functional change is that the Manifold platform mint fee is now **mutable state** (settable by the extension owner) instead of a hardcoded `constant`, plus a global `active` kill-switch on new claim creation. See [[repo-overview]] and [[shared-libraries]].

## Contract map

- `manifold/contracts/lazyUpdatableFeeClaim/LazyPayableClaimV2.sol` — abstract: replaces `LazyPayableClaim.sol` from v1. Reuses the v1 `manifold/contracts/lazyclaim/LazyPayableClaimCore.sol` base directly (imported across directories) but redefines the fee layer.
- `manifold/contracts/lazyUpdatableFeeClaim/ERC721LazyPayableClaimV2.sol` — concrete ERC721; inherits v1 `ERC721LazyPayableClaimCore` + `LazyPayableClaimV2`.
- `manifold/contracts/lazyUpdatableFeeClaim/ERC1155LazyPayableClaimV2.sol` — concrete ERC1155 counterpart.
- `manifold/contracts/lazyUpdatableFeeClaim/ILazyPayableClaimV2.sol` — extends `ILazyPayableClaim`, adds `Inactive` error + `setMintFees`/`setActive`.

## The Claim struct

**Unchanged from v1.** V2 imports the v1 interfaces and cores wholesale, so the ERC721 `Claim`/`ClaimParameters` (with `total`, `totalMax`, `walletMax`, `startDate`, `endDate`, `storageProtocol`, `contractVersion`, `identical`, `merkleRoot`, `location`, `cost`, `paymentReceiver`, `erc20`, `signingAddress`) and the ERC1155 `Claim` (with `tokenId`, no `contractVersion`/`identical`) are exactly as documented on [[lazy-payable-claim]]. No new claim fields were added.

## External surface

Identical `mint`/`mintBatch`/`mintProxy`/`mintSignature` signatures to v1 (declared via `ILazyPayableClaim` through `ILazyPayableClaimV2`), implemented in `ERC721LazyPayableClaimV2.sol` / `ERC1155LazyPayableClaimV2.sol`. Same admin surface (`initializeClaim`, `updateClaim`, `updateTokenURIParams`, `extendTokenURI`, `airdrop`) inherited from the v1 cores.

**New owner-only functions** (`manifold/contracts/lazyUpdatableFeeClaim/ILazyPayableClaimV2.sol`, implemented in `LazyPayableClaimV2.sol`):

```solidity
function setMintFees(uint256 mintFee, uint256 mintFeeMerkle) external; // adminRequired
function setActive(bool active) external;                              // adminRequired
```

## What changed vs v1

| Aspect | v1 (`LazyPayableClaim.sol`) | V2 (`LazyPayableClaimV2.sol`) |
| --- | --- | --- |
| `MINT_FEE` / `MINT_FEE_MERKLE` | `public constant` (0.0005 / 0.00069 ETH) | mutable `public` storage `uint256`, initially `0` |
| Fee setter | none | `setMintFees(uint256, uint256)` (`adminRequired`) |
| New-claim gating | none | `bool public active = true` + `setActive`; `initializeClaim` reverts `Inactive()` when `active == false` (`ERC721LazyPayableClaimV2.sol:38`) |
| Core / Claim struct / merkle / sig / delegation | — | reused unchanged from `manifold/contracts/lazyclaim/` |

## Fee & membership handling

`LazyPayableClaimV2._transferFunds` is byte-for-byte the same logic as v1's, except it reads the **mutable** `MINT_FEE` / `MINT_FEE_MERKLE` storage variables. Membership waiver is identical: fee skipped only when `MEMBERSHIP_ADDRESS` set, `allowMembership` true, and `IManifoldMembership.isActiveMember(msg.sender)` true (so `mintProxy`/`mintSignature` still never waive). Creator `cost` still forwards to `paymentReceiver`; platform fee accrues to the contract and is pulled with `withdraw`.

## Merkle / signature / delegation mechanics

Unchanged — all validation still runs through the shared v1 `manifold/contracts/lazyclaim/LazyPayableClaimCore.sol` (`_checkMerkleAndUpdate`, `_checkSignatureAndUpdate`, delegation-registry v1/v2 delegate checks). See [[lazy-payable-claim]] for details.

## Pitfalls

- **Fees default to ZERO on deployment.** `MINT_FEE` and `MINT_FEE_MERKLE` are uninitialized storage (`0`), not the v1 constants. The owner **must** call `setMintFees` after deploying or platform fees are silently uncollected.
- **`setActive(false)` only blocks new `initializeClaim` calls** — it does NOT pause minting on already-initialized claims (`active` is only checked in `initializeClaim`).
- Both new setters are `adminRequired` (extension owner), not `creatorAdminRequired` — they are global platform controls, not per-creator.
- All v1 pitfalls still apply: signature claims require `mintSignature`; `walletMax`/`merkleRoot` mutually exclusive; `updateClaim` cannot change `erc20`.

## Open questions

- No USDC variant exists under `lazyUpdatableFeeClaim/` — USDC claims remain on the v1 fixed-fee `manifold/contracts/lazyclaim/*USDC.sol` contracts.
- Whether existing v1 deployments were migrated to V2 or run in parallel is a deployment/ops question, not answerable from source.
