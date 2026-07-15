---
title: Soulbound Token Extensions
created: 2026-07-15
updated: 2026-07-15
type: concept
package: manifold
tags: [contract, abstract, soulbound, erc721, erc1155, admin, pitfall]
sources: [manifold/contracts/soulbound/Soulbound.sol, manifold/contracts/soulbound/ERC721Soulbound.sol, manifold/contracts/soulbound/ERC1155Soulbound.sol]
confidence: high
---

# Soulbound Token Extensions

## What it is

Shared extensions that make Manifold-creator tokens **non-transferable
(soulbound) by default, while remaining burnable by default**. Enforcement is a
per-transfer approval hook: the creator core calls the extension's
`approveTransfer` on every transfer, and the extension returns `false` to veto a
disallowed move. Soulbound/burnable state is configurable per-contract and
per-token; the token-level flag OR the contract-level flag can lift a
restriction. See [[repo-overview]].

## Contract map

| File | Role |
|------|------|
| `soulbound/Soulbound.sol` | `abstract` base — storage maps + configuration logic |
| `soulbound/ERC721Soulbound.sol` | ERC721 impl of `IERC721CreatorExtensionApproveTransfer` |
| `soulbound/ERC1155Soulbound.sol` | ERC1155 impl of `IERC1155CreatorExtensionApproveTransfer` |

## Base storage & config (`soulbound/Soulbound.sol`)

Four mappings track state (all default `false`, i.e. soulbound + burnable):
`_tokenNonSoulbound`, `_tokenNonBurnable` (both `address→uint256→bool`),
`_contractNonSoulbound`, `_contractNonBurnable` (both `address→bool`).

- `_configureContract(address, bool soulbound, bool burnable) internal` — stores the **negation** of each flag.
- `configureToken(address creator, uint256 tokenId, bool soulbound, bool burnable) external` and its `uint256[] tokenIds` overload — admin-gated per-token config.

All external config is behind
`creatorAdminRequired`: `require(IAdminControl(creatorContractAddress).isAdmin(msg.sender), "Must be owner or admin")`.

## External surface (traced)

**ERC721** (`soulbound/ERC721Soulbound.sol`):
- `setApproveTransfer(address creator, bool enabled)` — verifies the creator supports `IERC721CreatorCore` via `ERC165Checker`, then `setApproveTransferExtension(enabled)`.
- `approveTransfer(address, address from, address to, uint256 tokenId) → bool` (v2) and `approveTransfer(address from, address to, uint256 tokenId) → bool` (v1, iface `0x99cdaa22`) — both delegate to private `_approveTransfer`.
- `configureContract(address, bool soulbound, bool burnable, string tokenURIPrefix)` — sets URI prefix + calls `_configureContract`.
- `mintToken(address, address recipient, string tokenURI)`, `setTokenURI(...)` (single + array overloads).

**ERC1155** (`soulbound/ERC1155Soulbound.sol`): mirror surface with array-based
`approveTransfer(... uint256[] tokenIds, uint256[])` (v1 iface `0x93a80b14`),
`mintNewToken`, `mintExistingToken`, and `setTokenURI` overloads.

## Enforcement mechanism

The veto lives in `_approveTransfer` (ERC721, `soulbound/ERC721Soulbound.sol`
lines 57–61):

```
if (from == address(0)) return true;               // mint always allowed
if (to == address(0))   return !(_tokenNonBurnable[msg.sender][tokenId]
                                 || _contractNonBurnable[msg.sender]); // burn
return _tokenNonSoulbound[msg.sender][tokenId]
       || _contractNonSoulbound[msg.sender];        // ordinary transfer
```

`msg.sender` here is the **creator contract** calling back into the extension.
Mints (`from == 0`) always pass. Burns (`to == 0`) pass unless marked
non-burnable. Ordinary transfers pass **only** if the token or its contract has
been flipped non-soulbound — otherwise the extension returns `false` and the
creator core reverts the transfer. The ERC1155 variant applies the same logic
in a loop over `tokenIds` (`soulbound/ERC1155Soulbound.sol` lines 54–66), and
its transfer branch uses AND-of-negations, so a mixed batch fails if **any**
token is still soulbound.

Enforcement is only active once an admin calls `setApproveTransfer(creator,
true)` — this flips the creator core's per-extension approve-transfer check on.

## Relationship to operator filtering

Both soulbound contracts implement the same
`IERC*CreatorExtensionApproveTransfer` hook that the operator-filter extensions
use — they are alternative consumers of the creator's single approve-transfer
slot. A creator can install soulbound **or** an operator filterer on that hook,
not trivially both. See [[operator-filterer]] and [[shared-libraries]].

## Pitfalls

- **Double negatives.** Storage records `Non*` flags; a stored `true` means the
  restriction is lifted. Reading the maps directly inverts intuition.
- **OR semantics.** A token is transferable if the token-level OR contract-level
  non-soulbound flag is set; you cannot re-soulbind a single token once the whole
  contract is marked non-soulbound.
- Enforcement is inert until `setApproveTransfer(creator, true)` is called — a
  creator that merely deploys/registers the extension without enabling the check
  gets freely transferable tokens.
- ERC1155 batch transfers are all-or-nothing: one still-soulbound token in the
  batch vetoes the entire transfer.

## Open questions

- Behavior if a creator has approve-transfer disabled at the core level while
  soulbound state is configured — presumably no enforcement (needs
  `creator-core-solidity` confirmation).
