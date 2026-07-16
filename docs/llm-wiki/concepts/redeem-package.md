---
title: Redeem Package (Legacy Burn-Redeem)
created: 2026-07-15
updated: 2026-07-15
type: concept
package: redeem
tags: [contract, abstract, interface, burn-redeem, erc721, erc1155, struct, pitfall]
sources: [redeem/contracts/RedeemBase.sol, redeem/contracts/IRedeemBase.sol, redeem/contracts/RedeemSetBase.sol, redeem/contracts/ERC721/ERC721RedeemBase.sol, redeem/contracts/ERC721/ERC721BurnRedeem.sol, redeem/contracts/ERC721/IERC721BurnRedeem.sol, redeem/contracts/ERC721/ERC721BurnRedeemSet.sol, redeem/contracts/ERC1155/ERC1155RedeemBase.sol, redeem/contracts/ERC1155/ERC1155ClaimRedeem.sol]
confidence: high
---

# Redeem Package (Legacy Burn-Redeem)

## What it is
The **original** burn-redeem system: users burn one or more approved NFTs and receive a freshly lazy-minted reward NFT from a Manifold creator contract. This package **predates and is superseded by** [[burn-redeem]] (manifold/burnredeem). Contracts here send burned tokens to `address(0xdEaD)` (a pseudo-burn) rather than calling a native burn, and configuration is stored per-extension rather than in a shared shared-storage manager. Prefer the newer implementation for anything current; this page documents the legacy model. See [[repo-overview]].

## Contract map
- `redeem/contracts/RedeemBase.sol` — abstract base (`AdminControl`). Manages the *approved redeemables* registry: whole contracts, specific tokens, and token ranges.
- `redeem/contracts/IRedeemBase.sol` — interface; defines `TokenRange{min,max}` struct + admin/getter surface.
- `redeem/contracts/RedeemSetBase.sol` — abstract base for **set** redemptions (must supply a full set of tokens to redeem one reward). Holds `RedemptionItem[]`.
- `redeem/contracts/ERC721/ERC721RedeemBase.sol` — abstract; adds redemption accounting (rate/max/count, mint numbering) and mints via `IERC721CreatorCore.mintExtension`.
- `redeem/contracts/ERC721/ERC721BurnRedeem.sol` — concrete burn-redeem (contract named `ERC721Burn`). Accepts NFTs via explicit call or `onERC721Received`/`onERC1155Received`.
- `redeem/contracts/ERC721/ERC721BurnRedeemSet.sol` — concrete set variant; requires a complete set before minting.
- `redeem/contracts/ERC1155/ERC1155RedeemBase.sol` — abstract ERC1155 redeem base.
- `redeem/contracts/ERC1155/ERC1155ClaimRedeem.sol` — abstract; claim (not burn) an ERC1155 reward, tracking `_claimedERC721` to prevent double-claims.

## Key structs / interfaces
- `IRedeemBase.TokenRange { uint256 min; uint256 max; }` — inclusive redeemable range.
- `RedeemBase` storage: `_approvedContracts`, `_approvedTokens` (per-contract `UintSet`), `_approvedTokenRange` (per-contract `TokenRange[]`).
- `ERC721RedeemBase`: `_redemptionRate` (immutable, NFTs burned per reward), `_redemptionMax`, `_redemptionCount`, `_mintNumbers`, `_mintedTokens`.
- `RedemptionItem` (from `IRedeemSetBase`) — used by set variants; carries `tokenAddress`, `minTokenId`, `maxTokenId`.

## External surface (traced)
`RedeemBase`: `updateApprovedContracts(address[],bool[])`, `getApprovedContracts()`, `updateApprovedTokens(address,uint256[],bool[])`, `getApprovedTokens()`, `updateApprovedTokenRanges(address,uint256[],uint256[])`, `getApprovedTokenRanges()`, `redeemable(address,uint256)` — all admin-gated writes via `adminRequired`.
`ERC721RedeemBase`: `redemptionMax()`, `redemptionRate()`, `redemptionRemaining()`, `mintNumber(uint256)`, `mintedTokens()`.
`ERC721Burn` (BurnRedeem): `setERC721Recoverable(address,uint256,address)`, `recoverERC721(address,uint256)`, `redeemERC721(address[],uint256[])`, plus `onERC721Received`/`onERC1155Received`/`onERC1155BatchReceived`.
`ERC1155ClaimRedeem`: `initialize(string uri)`, `updateURI(string)`, `redeemable(...)` override.

## Distinctive mechanic
Burns are performed by `transferFrom(..., address(0xdEaD), tokenId)` inside a `try/catch` — the extension needs prior approval (`getApproved` or `isApprovedForAll`). When `_redemptionRate == 1`, tokens can be redeemed simply by `safeTransferFrom`-ing them to the extension (the `onERC*Received` hook burns then mints). `redeemERC721` requires `contracts.length == _redemptionRate` exactly. Set variants call `_validateCompleteSet` — every `RedemptionItem` slot must be matched or the whole redemption reverts.

## Pitfalls
- **`0xdEaD` is not a true burn** — the token still exists on-chain, just unspendable; supply/enumeration on the source contract won't reflect a real burn.
- Recovery (`setERC721Recoverable`/`recoverERC721`) exists because tokens sent directly with rate != 1 can get stuck; `ERC721BurnRedeemSet.onERC1155Received` (single) always reverts "Incomplete set".
- `redeemable` returns false once max range fields are zero; ranges with `max == 0` are ignored (`RedeemBase.sol` line 144).
- `ERC1155ClaimRedeem` guards double-claims via `_claimedERC721`; the reward tokenId must be `initialize`d before `updateURI`.
- No native membership/fee logic — this is pre-[[burn-redeem]] and lacks the newer merkle/fee/manifold-membership features.

## Open questions
- Exact deployment status vs the newer [[burn-redeem]] — is this package still deployed anywhere, or purely historical?
- `ERC1155ClaimRedeem` is abstract; which concrete contract wires the actual claim entrypoint (not present in the files read)?

See also: [[repo-overview]], [[burn-redeem]], [[shared-libraries]].
