---
title: Deck Claims
created: 2026-07-15
updated: 2026-07-15
type: concept
package: manifold
tags: [contract, abstract, interface, claim, deck, erc1155, signature, struct, pitfall]
sources: [manifold/contracts/deckClaims/Deck.sol, manifold/contracts/deckClaims/ERC1155Deck.sol, manifold/contracts/deckClaims/IDeck.sol, manifold/contracts/deckClaims/IERC1155Deck.sol]
confidence: high
---

# Deck Claims

## What it is

A **shared singleton** extension for "card-deck" style ERC-1155 claims. A creator initializes a claim that mints a fixed set of *variation* tokens (the "deck" — e.g. distinct cards). A trusted backend **signer** then deals those cards out to recipients via `deliverMints`. Unlike [[lazy-payable-claim]], **there is no user-facing on-chain mint or payment path** — all delivery is signer-driven and free at the contract level. Instances are keyed by `(creatorContractAddress, instanceId)`. See [[repo-overview]].

## Contract map

| File | Role |
|------|------|
| `deckClaims/IDeck.sol` | Base interface: errors, events, `VariationMint`/`ClaimMint` structs, signer/withdraw/deliver surface |
| `deckClaims/IERC1155Deck.sol` | ERC-1155 interface: `Claim`, `ClaimParameters`, `UpdateClaimParameters`, init/update/getters |
| `deckClaims/Deck.sol` | `abstract contract Deck is IDeck, AdminControl` — signer storage, `deprecate`, `withdraw`, `_validateSigner` |
| `deckClaims/ERC1155Deck.sol` | Concrete `ERC1155Deck` — claim storage, init/update, `deliverMints`, `tokenURI` |

## Key structs (from source)

`Claim` (`IERC1155Deck.sol:13`): `StorageProtocol storageProtocol; uint32 total; uint80 startingTokenId; uint8 tokenVariations; string location;`

`ClaimParameters` (`IERC1155Deck.sol:21`): `StorageProtocol storageProtocol; uint8 tokenVariations; string location;`

`VariationMint` (`IDeck.sol:34`): `uint8 variationIndex; uint32 amount; address recipient;`

`ClaimMint` (`IDeck.sol:40`): `address creatorContractAddress; uint256 instanceId; VariationMint[] variationMints;`

Note: no `cost`, `paymentReceiver`, `startDate`/`endDate`, or `totalMax` — Deck has **no pricing or supply-cap fields at all**.

## External surface (traced)

- `initializeClaim(address, uint256, ClaimParameters) external payable creatorAdminRequired` — `ERC1155Deck.sol:43`
- `updateClaim(address, uint256, UpdateClaimParameters) external creatorAdminRequired` — `ERC1155Deck.sol:86`
- `deliverMints(ClaimMint[] calldata) external` — `ERC1155Deck.sol:135` (signer-only)
- `getClaim` / `getClaimForToken` — `ERC1155Deck.sol:112` / `:119`
- `updateTokenURIParams(...) creatorAdminRequired` — `ERC1155Deck.sol:192`
- `tokenURI(address, uint256)` — `ERC1155Deck.sol:175`
- From `Deck.sol`: `setSigner(address) adminRequired` (`:61`), `withdraw(address payable, uint256) adminRequired` (`:53`), `deprecate(bool) adminRequired` (`:46`)

## The distinctive mechanic: dealing a deck

1. `initializeClaim` mints `tokenVariations` **new** token IDs on the creator contract via `mintExtensionNew(receivers, amounts, uris)` with **all-zero amounts and empty URIs** (`ERC1155Deck.sol:59-61`). These are the deck's card slots. Only `newTokenIds[0]` is stored as `startingTokenId`; each of the `tokenVariations` token IDs is mapped back to the instance in `_tokenInstances` (`:73-78`).
2. Card token for a variation is computed as `startingTokenId + variationIndex - 1` (`ERC1155Deck.sol:155`) — so `variationIndex` is **1-based** and validated `>= 1 && <= tokenVariations` (`:149`).
3. The backend decides *who gets which card* off-chain, then the **signer** calls `deliverMints`, which loops variations and calls `mintExtensionExisting` to mint the dealt cards to recipients (`:165`). `claim.total` accumulates delivered supply.

`tokenURI` returns `prefix + location + "/" + (tokenId - startingTokenId + 1)` (`ERC1155Deck.sol:186`), i.e. metadata index is the 1-based variation number.

## Fee & membership handling

None on-chain. There is **no mint fee, no cost, no membership/fee-waiver logic** — contrast with [[gacha-serendipity]] (`MINT_FEE`) and [[lazy-payable-claim]]. `withdraw` exists only to sweep any stray ETH sent to the contract.

## Pitfalls

- **No user mint entrypoint.** Collectors cannot mint directly; everything flows through the off-chain backend + `deliverMints`. A compromised or offline signer fully controls distribution.
- `deliverMints` performs **no per-recipient reservation or cap check** (unlike Serendipity's `reservedCount`). The signer is fully trusted to mint the right amounts.
- `variationIndex` bound check is `variationIndex > MAX_UINT_8` then `> claim.tokenVariations` — the first is redundant since the field is `uint8`.
- `initializeClaim` is `payable` but consumes no value.

## Open questions

- Where does the randomness/fairness of "which card" live? Entirely off-chain in the signer service; not verifiable on-chain.
- `updateClaim` cannot change `tokenVariations` or `startingTokenId` — how are new cards added to an existing deck? Apparently not supported.

See also: [[gacha-serendipity]], [[frame-claims]], [[shared-libraries]].
