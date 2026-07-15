---
title: Gacha / Serendipity Claims
created: 2026-07-15
updated: 2026-07-15
type: concept
package: manifold
tags: [contract, abstract, interface, claim, gacha, erc1155, signature, fee, struct, pitfall]
sources: [manifold/contracts/gachaclaims/Serendipity.sol, manifold/contracts/gachaclaims/ERC1155Serendipity.sol, manifold/contracts/gachaclaims/ISerendipity.sol, manifold/contracts/gachaclaims/IERC1155Serendipity.sol]
confidence: high
---

# Gacha / Serendipity Claims

## What it is

A **shared singleton** gacha ("lucky draw") extension for ERC-1155. A collector pays to **reserve** a number of mints; a trusted backend **signer** later randomizes which variation each reservation resolves to and **delivers** the tokens. The randomization itself is **off-chain** — the contract only enforces payment, supply caps, and a reserve/deliver accounting invariant. Instances keyed by `(creatorContractAddress, instanceId)`. It is a payment-bearing sibling of [[deck-claims]] and a variant of the [[lazy-payable-claim]] family. See [[repo-overview]].

## Contract map

| File | Role |
|------|------|
| `gachaclaims/ISerendipity.sol` | Base interface: errors, events, `VariationMint`/`ClaimMint`/`UserMintDetails`, `mintReserve`/`deliverMints` surface |
| `gachaclaims/IERC1155Serendipity.sol` | ERC-1155 `Claim`, `ClaimParameters`, `UpdateClaimParameters`, init/update/getters |
| `gachaclaims/Serendipity.sol` | `abstract Serendipity is ISerendipity, AdminControl` — `MINT_FEE`, per-wallet mint accounting, signer, `_sendFunds` |
| `gachaclaims/ERC1155Serendipity.sol` | Concrete `ERC1155Serendipity` — claim storage, `mintReserve`, `deliverMints`, `tokenURI` |

## Key structs (from source)

`Claim` (`IERC1155Serendipity.sol:13`): `StorageProtocol storageProtocol; uint32 total; uint32 totalMax; uint48 startDate; uint48 endDate; uint80 startingTokenId; uint8 tokenVariations; string location; address payable paymentReceiver; uint96 cost; address erc20;`

`ClaimParameters` (`:27`) mirrors `Claim` minus `total`/`startingTokenId`.

`UserMintDetails` (`ISerendipity.sol:63`): `uint32 reservedCount; uint32 deliveredCount;`

`VariationMint` (`ISerendipity.sol:51`): `uint8 variationIndex; uint32 amount; address recipient;`

`ClaimMint` (`ISerendipity.sol:57`): `address creatorContractAddress; uint256 instanceId; VariationMint[] variationMints;`

## External surface (traced)

- `initializeClaim(address, uint256, ClaimParameters) external payable creatorAdminRequired` — `ERC1155Serendipity.sol:45`
- `updateClaim(address, uint256, UpdateClaimParameters) external creatorAdminRequired` — `:99`
- `mintReserve(address, uint256, uint32 mintCount) external payable` — `:159` (user entrypoint)
- `deliverMints(ClaimMint[] calldata) external` — `:190` (signer-only)
- `getUserMints(address, address, uint256)` — `:233`
- `getClaim` / `getClaimForToken` / `tokenURI` / `updateTokenURIParams`
- From `Serendipity.sol`: `setSigner adminRequired` (`:68`), `withdraw adminRequired` (`:60`), `deprecate adminRequired` (`:53`); constant `MINT_FEE = 500000000000000` (0.0005 ETH, `:28`).

## The distinctive mechanic: randomness + supply

**Reserve (on-chain), then deliver (off-chain-randomized):**

1. `mintReserve` (`ERC1155Serendipity.sol:159`) requires `!Address.isContract(msg.sender)` (`:160`, blocks contract callers so tx-hash entropy can't be gamed by a contract), checks the claim window (`startDate`/`endDate`, `:164`), sold-out (`:166`), and requires exact payment `msg.value == (cost + MINT_FEE) * mintCount` (`:168`).
2. **Supply model:** `totalMax == 0` ⇒ **unlimited**; otherwise **limited**. When limited, the reserve is clamped: `amountToReserve = min(mintCount, totalMax - total)` (`:172`), `claim.total` bumps, and any overpayment for un-fulfillable mints is **refunded** (`:180-183`).
3. Reserved count is banked per wallet in `_mintDetailsPerWallet[...][msg.sender].reservedCount` (`:175`) and `SerendipityMintReserved` is emitted.
4. **Randomization is entirely off-chain.** The signer computes which variation each reservation wins, then calls `deliverMints`, which for each `VariationMint` mints `startingTokenId + variationIndex - 1` and enforces the invariant `deliveredCount + amount <= reservedCount` (`:211`) before bumping `deliveredCount`.

So the contract guarantees *conservation* (no wallet is delivered more than it reserved) but the *fairness of the draw* is a backend trust assumption.

## Fee & membership handling

- **`MINT_FEE` = 0.0005 ETH** is charged per mint on top of `cost` and retained by the contract (`:168`); `cost * amountToReserve` is forwarded to `claim.paymentReceiver` immediately (`:176-178`).
- `cost` is `uint96`; an `erc20` field exists in `Claim` but `mintReserve` only handles **native ETH** payment — ERC-20 pricing is stored but not exercised in the reserve path here.
- No merkle allowlist, delegation, or membership fee-waiver logic (contrast [[lazy-payable-claim]]).

## Pitfalls

- **Off-chain RNG.** No on-chain randomness source (no VRF, no blockhash). Trust the signer for fair draws.
- The `erc20` claim field is set at init and **immutable** (`CannotChangePaymentToken` error exists) but `mintReserve` ignores it — do not assume ERC-20 gacha works via this path without a separate flow.
- `updateClaim` cannot lower `totalMax` below `total` (`CannotLowerTotalMaxBeyondTotal`, `:111`) and cannot change `tokenVariations`.
- Overpayment refund only triggers on the clamped-supply branch; exact-payment is otherwise required.

## Open questions

- Is ERC-20 payment handled by a different/newer variant, or dead config?
- Delivery ordering/timeliness after reserve is a backend SLA, not enforced on-chain.

See also: [[deck-claims]], [[frame-claims]], [[shared-libraries]].
