---
title: Frozen Metadata Extensions
created: 2026-07-15
updated: 2026-07-15
type: concept
package: manifold
tags: [contract, interface, metadata, erc721, erc1155, admin, operator-filter, pitfall]
sources: [manifold/contracts/metadata/ERC721FrozenMetadata.sol, manifold/contracts/metadata/ERC1155FrozenMetadata.sol, manifold/contracts/metadata/ERC721FrozenMetadataNoFilterer.sol, manifold/contracts/metadata/ERC1155FrozenMetadataNoFilterer.sol, manifold/contracts/metadata/IERC721FrozenMetadata.sol, manifold/contracts/metadata/IERC1155FrozenMetadata.sol]
confidence: high
---

# Frozen Metadata Extensions

## What it is

A pair of shared extensions (ERC721 + ERC1155) that mint tokens whose `tokenURI`
is a **fully-qualified, immutable URI supplied at mint time**. The extension
exposes only mint functions — there is no `setTokenURI` on the contract — so once
a token is minted through it, that extension can never rewrite the URI. This is
the "frozen metadata" guarantee. See [[repo-overview]] for where this sits among
the shared extensions.

## Contract map

| File | Role |
|------|------|
| `metadata/IERC721FrozenMetadata.sol` | Interface — declares `mintToken` |
| `metadata/IERC1155FrozenMetadata.sol` | Interface — declares `mintTokenNew`, `mintTokenExisting` |
| `metadata/ERC721FrozenMetadata.sol` | ERC721 implementation |
| `metadata/ERC1155FrozenMetadata.sol` | ERC1155 implementation |
| `metadata/ERC721FrozenMetadataNoFilterer.sol` | ERC721 impl + `ERC721NoFilterer` mix-in |
| `metadata/ERC1155FrozenMetadataNoFilterer.sol` | ERC1155 impl + `ERC1155NoFilterer` mix-in |

## External surface (traced)

**ERC721** (`metadata/ERC721FrozenMetadata.sol`):
- `mintToken(address creator, address recipient, string calldata tokenURI) external returns(uint256)` — reverts `"Cannot mint blank string"` if `tokenURI` is empty, then calls `IERC721CreatorCore(creator).mintExtension(recipient, tokenURI)`.
- `supportsInterface(bytes4) → bool` — true only for `type(IERC721FrozenMetadata).interfaceId`.

**ERC1155** (`metadata/ERC1155FrozenMetadata.sol`):
- `mintTokenNew(address creator, address[] to, uint256[] amounts, string[] uris) external returns(uint256[])` — loops all `uris`, reverts `"Cannot mint blank string"` on any empty entry, then `mintExtensionNew(to, amounts, uris)`.
- `mintTokenExisting(address creator, address[] to, uint256[] tokenIds, uint256[] amounts) external` — `mintExtensionExisting(...)`; adds supply to already-minted tokens (no new URI).
- `supportsInterface(bytes4) → bool` — true only for `type(IERC1155FrozenMetadata).interfaceId`.

All mint functions are gated by the `creatorAdminRequired(creator)` modifier:
`require(IAdminControl(creator).isAdmin(msg.sender), "Must be owner or admin of creator contract")`.

## Enforcement mechanism

Immutability is **structural, not a runtime hook**. The extension delegates
minting to the creator core's `mintExtension*` functions, which permanently
associate the passed URI with the token. Because the extension exposes no
URI-mutation entrypoint, no admin path exists to change it later *through this
extension*. Contrast with [[soulbound]], which keeps `setTokenURI*` methods.

## Filterer vs no-filterer distinction

The base contracts do **not** implement `IERC*CreatorExtensionApproveTransfer`,
so a creator using them applies no operator gating from this extension. The
`*NoFilterer` variants additionally inherit
`operatorfilterer/nofilterer/ERC721NoFilterer.sol` /
`ERC1155NoFilterer.sol`, which implement `approveTransfer(...) → true` (always
allow) and advertise the ApproveTransfer interface. This lets a creator that has
approve-transfer checking enabled install a frozen-metadata extension that
**explicitly opts out** of any marketplace filtering. See [[operator-filterer]].

The only override in the `*NoFilterer` contracts is `supportsInterface`, which
ORs both parents so both the frozen-metadata and the no-filterer interfaces are
advertised.

## Pitfalls

- `mintTokenExisting` (ERC1155) does **not** validate any URI — it only adds
  supply to existing tokens. The "no blank string" guard is on `mintTokenNew`
  only.
- The ERC721 `supportsInterface` in the base contract advertises *only* the
  frozen-metadata interface (not `IERC165` itself) — a strict `IERC165`
  probe returns false. The `*NoFilterer` variant fixes this by ORing in the
  no-filterer interface set.
- "Frozen" is a property of *this extension's* surface. It does not stop a
  different admin extension on the same creator from rewriting the URI.

## Open questions

- Does `IERC721CreatorCore.mintExtension` itself reject later URI edits, or is
  immutability purely a function of no extension exposing an editor? (Requires
  reading `creator-core-solidity`; see [[shared-libraries]].)
