---
title: Edition Package (Numbered & Prefix Editions)
created: 2026-07-15
updated: 2026-07-15
type: concept
package: edition
tags: [contract, abstract, interface, edition, erc721, struct, pitfall]
sources: [edition/contracts/ERC721EditionBase.sol, edition/contracts/IERC721Edition.sol, edition/contracts/ERC721NumberedEditionBase.sol, edition/contracts/IERC721NumberedEdition.sol, edition/contracts/ERC721NumberedEdition.sol, edition/contracts/ERC721NumberedEditionImplementation.sol, edition/contracts/ERC721NumberedEditionTemplate.sol, edition/contracts/ERC721PrefixEditionBase.sol, edition/contracts/IERC721PrefixEdition.sol, edition/contracts/nifty/NiftyGatewayERC721NumberedEditionImplementation.sol, edition/contracts/nifty/INiftyGatewayERC721NumberedEdition.sol]
confidence: high
---

# Edition Package (Numbered & Prefix Editions)

## What it is
Extensions for minting fixed-supply **editions** on a Manifold ERC721 creator contract. An edition has a `maxSupply`, tracks `totalSupply`, and computes each token's *edition index* from its tokenId. Two URI styles: **numbered** (a templated JSON `data:` URI with `<EDITION>/<TOTAL>/<MAX>` tag substitution) and **prefix** (a base string + edition number appended). Ships in three deployment shapes — direct contract, minimal-proxy Implementation, and Template — plus a Nifty Gateway variant. Related: [[editions-and-singles]], [[repo-overview]].

## Contract map
- `edition/contracts/ERC721EditionBase.sol` — abstract core. Supply accounting + `IndexRange[]` bookkeeping to map tokenId → sequential edition index. Implements `ICreatorExtensionTokenURI`.
- `edition/contracts/IERC721Edition.sol` — `mint` (single + multi-recipient), `totalSupply`, `maxSupply`.
- `edition/contracts/ERC721NumberedEditionBase.sol` — abstract; tag-substitution URI builder over `string[] _uriParts`.
- `edition/contracts/ERC721NumberedEdition.sol` — concrete, constructor-initialized, `AdminControl`.
- `edition/contracts/ERC721NumberedEditionImplementation.sol` — concrete clone target, `AdminControlUpgradeable`, `initializer`.
- `edition/contracts/ERC721NumberedEditionTemplate.sol` — EIP-1967 minimal proxy that hard-codes `uriParts` and delegatecalls `initialize`.
- `edition/contracts/ERC721PrefixEditionBase.sol` — abstract; `tokenURI = prefix + (index+1)`. (`Base/Implementation/Template` mirror the numbered trio.)
- `edition/contracts/IERC721PrefixEdition.sol` — adds `setTokenURIPrefix(string)`.
- `edition/contracts/nifty/NiftyGatewayERC721NumberedEditionImplementation.sol` — Nifty Gateway minter-gated variant.

## Key structs / interfaces
- `ERC721EditionBase.IndexRange { uint256 startIndex; uint256 count; }` — coalesced runs of minted tokenIds; used by `_tokenIndex` to derive the 0-based edition index (URI adds `+1`).
- Numbered tags: `_EDITION_TAG='<EDITION>'`, `_TOTAL_TAG='<TOTAL>'`, `_MAX_TAG='<MAX>'`.
- `INiftyGatewayERC721NumberedEdition`: `activate(address[],address)`, `mintNifty(uint256,uint16)`, `_mintCount(uint256)`.

## External surface (traced)
Common (`IERC721Edition`): `mint(address recipient, uint16 count)`, `mint(address[] recipients)`, `totalSupply()`, `maxSupply()`.
Numbered concrete/impl: `updateURIParts(string[])` + the two `mint` overloads, all `adminRequired`; `Implementation.initialize(address creator, uint256 maxSupply_, string[] uriParts)` is `initializer`.
Prefix: adds `setTokenURIPrefix(string)`.
Nifty impl: `activate(address[] minters, address niftyOmnibusWallet)`, `mintNifty(uint256 niftyType, uint16 count)` (requires `niftyType == 1` and caller in `_minters`), `_mintCount(uint256)`, plus `updateURIParts`/`mint`.
All: `tokenURI(address creator, uint256 tokenId)` via `ICreatorExtensionTokenURI`.

## Distinctive mechanic — clone/template pattern
`ERC721NumberedEditionTemplate` is an OpenZeppelin `Proxy` writing `editionImplementation` into the EIP-1967 `_IMPLEMENTATION_SLOT` (`0x360894...382bbc`), then `Address.functionDelegateCall`-ing `initialize(address,uint256,string[])` in its constructor — the `uriParts` are baked into the template's bytecode. `Implementation` uses `AdminControlUpgradeable` + `initializer` (no constructor state) so it is safe to clone. The plain `ERC721NumberedEdition` skips proxying and initializes in its constructor. Numbered vs prefix differ only in the `tokenURI` builder: numbered walks `_uriParts` doing `keccak256` tag comparison and substituting `(tokenIndex+1)`, `_totalSupply`, `_maxSupply`; prefix just concatenates.

## Pitfalls
- `_tokenIndex` reverts "Invalid token" for any tokenId not in a recorded `IndexRange`; ranges only coalesce when mints are contiguous (`ERC721EditionBase.sol` lines 78–83) — interleaved mints from other extensions create multiple ranges.
- Template bakes `uriParts` at deploy — changing metadata later still requires `updateURIParts` (admin) on the proxy.
- `_mint(address[])` mints one-by-one via `mintExtension` (no batch), so gas scales with recipient count; `_mint(recipient,count)` uses `mintExtensionBatch`.
- Nifty variant: `mintNifty` only supports `niftyType == 1` and mints to the fixed `_niftyOmnibusWallet` set at `activate`.
- `initialize`/`_initialize` guard on `_creator == address(0)` — cannot re-initialize a clone.

## Open questions
- Numbered `<EDITION>` is `index+1` while `<MAX>` is `_maxSupply`; confirm intended display when supply < max (open editions).
- Nifty `_mintCount` returns `_totalSupply` regardless of type — is per-type accounting ever needed?

See also: [[repo-overview]], [[editions-and-singles]], [[shared-libraries]].
