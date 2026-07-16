---
title: Dynamic & Enumerable Packages
created: 2026-07-15
updated: 2026-07-15
type: concept
package: dynamic
tags: [contract, abstract, dynamic-token, enumerable, erc721, library, pitfall]
sources: [dynamic/contracts/DynamicArweaveHash.sol, dynamic/contracts/DynamicSVGExample.sol, dynamic/contracts/TimeToken.sol, enumerable/contracts/ERC721/ERC721OwnerEnumerableExtension.sol, enumerable/contracts/ERC721/ERC721OwnerEnumerableSingleCreatorExtension.sol]
confidence: high
---

# Dynamic & Enumerable Packages

Two independent extension families for Manifold ERC721 creator contracts. **Dynamic** computes `tokenURI` on-chain so metadata can change over time or by owner. **Enumerable** adds per-owner token enumeration the base creator contract does not natively provide. See [[repo-overview]], [[shared-libraries]].

---

## Section 1 — Dynamic (on-chain / mutable tokenURI)

### What it is
Extensions implementing `ICreatorExtensionTokenURI.tokenURI` to return metadata built at read time rather than a static stored URI. Three examples, from simplest to most elaborate.

### Contract map
- `dynamic/contracts/DynamicArweaveHash.sol` — abstract base. Stores `string[] imageArweaveHashes` / `animationArweaveHashes` and builds a `data:application/json` URI pointing at `https://arweave.net/<hash>`. Owner can swap the hash arrays. Abstract hooks: `_getName`, `_getDescription`, `_getImageHash`, `_getAnimationHash`.
- `dynamic/contracts/TimeToken.sol` — concrete `DynamicArweaveHash`. Selects which Arweave hash to serve by elapsed time: `(block.timestamp - _creationTimestamp)/_cadence % hashes.length`. Single-token (`mint` guards `_tokenId == 0`).
- `dynamic/contracts/DynamicSVGExample.sol` — fully **on-chain SVG**. Assembles an animated `<svg>` from `_imageParts` with tag substitution (`<RADIUS>`, `<HUE1>`…`<LIGHTNESS2>`), coloring derived from the owner's address bytes and a time-based `completion` curve using `ABDKMath64x64` fixed-point math. Also implements `IERC721CreatorExtensionApproveTransfer` to capture creation/completion timestamps on first transfer.

### External surface (traced)
- `DynamicArweaveHash`: `tokenURI(address,uint256)`, `setImageArweaveHashes(string[])` (onlyOwner), `setAnimationAreaveHashes(string[])` (onlyOwner) — note the misspelled setter name.
- `TimeToken`: `constructor(address creator, string name, string description, uint256 cadence)`, `mint(address) returns(uint256)`.
- `DynamicSVGExample`: `mint(address)` (onlyOwner), `tokenURI(address,uint256)`, `updateImageParts(string[])`, `setApproveTransfer(address,bool)`, `approveTransfer(address,address,address,uint256)`.

### Distinctive mechanic
`DynamicSVGExample` reads `IERC721(creator).ownerOf(tokenId)` inside `tokenURI` and folds the low bytes of the owner address into hue/offset — so the image visibly changes when the token changes hands. The `completion` factor decays over ~1 year (`31536000` seconds); `approveTransfer` sets `_completionTimestamp = block.timestamp + 31536000` on the first tracked transfer.

### Pitfalls
- Owner-dependent rendering means `tokenURI` output is **not stable** — marketplaces caching metadata will show stale art after transfers.
- On-chain SVG is gas-heavy to read and depends on `ABDKMath64x64`; the file has a real-looking constant `315...6000` for one year — verify no precision surprises.
- `TimeToken` will revert on `_getImageHash`/`_getAnimationHash` if the corresponding hash array is empty (modulo by zero / index).

---

## Section 2 — Enumerable (per-owner enumeration)

### What it is
Adds `tokenOfOwnerByIndex` / `balanceOf(owner)` for tokens an extension mints, by hooking `approveTransfer` on the creator contract. The base ERC721 creator core does not track per-owner token lists for extension-minted tokens; this fills the gap via swap-and-pop arrays.

### Contract map
- `enumerable/contracts/ERC721/ERC721OwnerEnumerableExtension.sol` — abstract, **multi-creator** keyed by creator address: `balanceOf(creator,owner)`, `tokenOfOwnerByIndex(creator,owner,index)`. Call `_activate(creator)` per creator.
- `enumerable/contracts/ERC721/ERC721OwnerEnumerableSingleCreatorExtension.sol` — two contracts in one file: `ERC721OwnerEnumerableSingleCreatorBase` (single-creator, `balanceOf(owner)` / `tokenOfOwnerByIndex(owner,index)`, and `approveTransfer` requires `msg.sender == _creator`) and `ERC721OwnerEnumerableSingleCreatorExtension` wiring in `ERC721SingleCreatorExtension`.

### External surface (traced)
- Multi: `tokenOfOwnerByIndex(address creator,address owner,uint256 index)`, `balanceOf(address creator,address owner)`, `approveTransfer(address,address from,address to,uint256 tokenId)`.
- Single: `tokenOfOwnerByIndex(address owner,uint256 index)`, `balanceOf(address owner)`, `approveTransfer(...)`.
- Internal mint helpers `_mintExtension(...)` / `_mintExtensionBatch(...)` add tokens to enumeration as they mint.

### Distinctive mechanic
`approveTransfer` is the enumeration engine: on mint (`from == address(0)`) it returns early (mint helpers already indexed the token); on transfer it removes from `from` and adds to `to` using swap-and-pop (`_removeTokenFromOwnerEnumeration`). Enumeration only works after `_activate` calls `setApproveTransferExtension(true)` on the creator.

### Pitfalls
- **Must call `_activate`** (per creator for the multi-creator variant) or `approveTransfer` is never invoked and counts stay zero — flagged IMPORTANT in-source.
- The multi-creator `approveTransfer` does **not** check `msg.sender == creator` (uses `msg.sender` as creator key), unlike the single-creator base which requires it — mixing them or trusting the multi variant's caller is a footgun.
- Only tokens minted through this extension's `_mintExtension*` helpers are enumerated; externally-minted tokens on the same creator are invisible here.

## Open questions
- Does any shipped concrete contract combine Enumerable + Dynamic, or are they always used separately?
- `DynamicSVGExample` completion math relies on ABDK `log_2` of `completion` which can be ≤0 near completion — confirm domain safety.

See also: [[repo-overview]], [[shared-libraries]], [[editions-and-singles]].
