---
title: Editions and Singles
created: 2026-07-15
updated: 2026-07-15
type: concept
package: manifold
tags: [contract, interface, edition, single, erc721, erc1155, struct, pitfall]
sources: [manifold/contracts/edition/ManifoldERC721Edition.sol, manifold/contracts/edition/IManifoldERC721Edition.sol, manifold/contracts/single/ManifoldERC721Single.sol, manifold/contracts/single/ManifoldERC1155Single.sol, manifold/contracts/single/IManifoldERC721Single.sol, manifold/contracts/single/IManifoldERC1155Single.sol]
confidence: high
---

# Editions and Singles

## What it is

Two admin-only minting extensions for Manifold Creator Core contracts. **Edition** batch-mints a numbered series (`1..maxSupply`) of ERC721 tokens sharing one metadata prefix. **Single** performs a one-off 1/1 mint (ERC721 `mintBase` or ERC1155 `mintBaseNew`). Both are shared singletons — every function is keyed by `creatorCore` and gated by `creatorAdminRequired`. Neither takes payment: these are pure creator distribution tools, not paid claim pages. Compare with the older, separate `[[edition-package]]`.

## Contract map

| File (relative to `packages/`) | Role |
|---|---|
| `manifold/contracts/edition/ManifoldERC721Edition.sol` | Edition controller; `CreatorExtension` + `ICreatorExtensionTokenURI` + `ReentrancyGuard`. Batch mint, tokenURI resolution. |
| `manifold/contracts/edition/IManifoldERC721Edition.sol` | Edition interface: `EditionInfo`/`Recipient`/`IndexRange` structs, errors, `SeriesCreated` event. |
| `manifold/contracts/single/ManifoldERC721Single.sol` | ERC721 1/1 mint via `mintBase`. |
| `manifold/contracts/single/ManifoldERC1155Single.sol` | ERC1155 mint via `mintBaseNew` (multi-recipient/amount). |
| `manifold/contracts/single/IManifoldERC721Single.sol` | ERC721 single interface. |
| `manifold/contracts/single/IManifoldERC1155Single.sol` | ERC1155 single interface. |

## Key structs (edition)

`edition/IManifoldERC721Edition.sol`:
- `EditionInfo { uint192 firstTokenId; uint8 contractVersion; uint24 totalSupply; uint24 maxSupply; StorageProtocol storageProtocol; string location; }`
- `Recipient { address recipient; uint16 count; }`
- `enum StorageProtocol { INVALID, NONE, ARWEAVE, IPFS }`
- `IndexRange { uint256 startIndex; uint256 count; }` (defined in the impl, `ManifoldERC721Edition.sol`)

## External surface

Edition — `edition/ManifoldERC721Edition.sol`:
- `createSeries(address creatorCore, uint256 instanceId, uint24 maxSupply_, StorageProtocol storageProtocol, string location, Recipient[] recipients)`
- `setTokenURI(address creatorCore, uint256 instanceId, StorageProtocol storageProtocol, string location)`
- `mint(address creatorCore, uint256 instanceId, uint24 currentSupply, Recipient[] recipients)` — `nonReentrant`
- `getEditionInfo(address creatorCore, uint256 instanceId) → EditionInfo`
- `getInstanceIdsForTokens(address creatorCore, uint256[] tokenIds) → uint256[]`
- `getInstanceTokenIds(address creatorCore, uint256 instanceId) → uint256[]`
- `tokenURI(address creatorCore, uint256 tokenId) → string`

Single — `single/ManifoldERC721Single.sol`:
- `mint(address creatorCore, uint256 expectedTokenId, string uri, address recipient)`

Single — `single/ManifoldERC1155Single.sol`:
- `mint(address creatorCore, uint256 expectedTokenId, string uri, address[] recipients, uint256[] amounts)`

## Distinctive mechanic

**Version-dependent token indexing (edition).** Two storage strategies switch on the creator contract's `VERSION()`:
- **v3+**: the per-token index is packed into `tokenData` as `uint56(instanceId) << 24 | uint24(mintIndex)` and written at mint via `mintExtensionBatch`. No auxiliary storage. See `_mintTokens` in `edition/ManifoldERC721Edition.sol`.
- **< v3**: no per-token data slot, so the extension records `IndexRange[]` per instance and reverse-derives `(instanceId, index)` by scanning `_creatorInstanceIds` in `_tokenInstanceAndIndex`.

`tokenURI` returns `prefix + location + "/" + (index+1)`, prefix chosen from `StorageProtocol` (Arweave/IPFS/none). Editions are 1-indexed in the URI.

**Expected-id assertion (single & edition mint).** Single's `mint` reverts with `InvalidInput()` if the freshly minted id ≠ `expectedTokenId`; edition's `mint` reverts if `currentSupply != info.totalSupply`. Both are optimistic-concurrency guards so a caller's off-chain assumption can't silently drift.

## Fee / membership handling

None. Neither extension is payable, references `MINT_FEE`, nor touches Manifold Membership. Access control is the only gate. Contrast with `[[collectible]]`.

## Pitfalls

- `createSeries` requires `instanceId` in `(0, MAX_UINT_56]` and rejects a re-used instanceId (existing `storageProtocol != INVALID`) — one series per id.
- Edition `mint`'s `currentSupply` argument must exactly equal the on-chain `totalSupply` or it reverts; callers must read current supply first.
- For creator versions **< 3**, instanceIds are pushed to `_creatorInstanceIds` and token→instance lookups are an O(series × ranges) scan — gas grows with history.
- Single mint's `expectedTokenId` must be predicted correctly by the caller; a concurrent mint on the creator contract shifts the id and reverts the tx.
- `getInstanceTokenIds` for v3+ linearly walks token ids from `firstTokenId` until `totalSupply` matches — unbounded scan for sparse mints.

## Open questions

- No burn or supply-reduction path — is a series immutable in size once `maxSupply` is set? (Appears yes.)
- `StorageProtocol.NONE` yields an empty prefix; is a fully-qualified `location` expected in that mode?

## See also

- `[[repo-overview]]` — where these sit among the extension families.
- `[[edition-package]]` — the older, separate edition implementation for comparison.
- `[[collectible]]` — the payable claim/purchase cousin.
