---
title: LazyWhitelist & Fonts Packages
created: 2026-07-15
updated: 2026-07-15
type: concept
package: lazywhitelist
tags: [contract, abstract, interface, whitelist, merkle, erc721, pitfall]
sources: [lazywhitelist/contracts/ERC721LazyMintWhitelistBase.sol, lazywhitelist/contracts/ERC721LazyMintWhitelistImplementation.sol, lazywhitelist/contracts/ERC721LazyMintWhitelistTemplate.sol, lazywhitelist/contracts/IERC721LazyMintWhitelist.sol, fonts/contracts/IFontWOFF.sol]
confidence: high
---

# LazyWhitelist & Fonts Packages

Two small, unrelated packages. **LazyWhitelist** is a merkle-gated paid lazy-mint extension (clone pattern). **Fonts** is a single interface for on-chain WOFF font storage. See [[repo-overview]], [[shared-libraries]].

---

## Section 1 — LazyWhitelist (merkle-gated lazy mint)

### What it is
An ERC721 extension letting whitelisted addresses pay a fixed price to lazy-mint a token from a Manifold creator contract, with admin "premint" (gifting) and a sequential edition-numbered `tokenURI`. Allowlist membership is proven with a merkle proof. Ships as `Base` (abstract) + `Implementation` (clone target) + `Template` (EIP-1967 minimal proxy) — the same clone shape as [[lazy-payable-claim]] and the edition package.

### Contract map
- `lazywhitelist/contracts/ERC721LazyMintWhitelistBase.sol` — abstract core. Holds `merkleRoot`, `MINT_PRICE = 0.1 ether`, `MAX_MINTS = 50`, `_tokensMinted`, per-token `_tokenEdition`. Implements `ICreatorExtensionTokenURI` and the merkle check.
- `lazywhitelist/contracts/ERC721LazyMintWhitelistImplementation.sol` — concrete clone target: `AdminControlUpgradeable` + `initializer`, exposes the public admin/mint surface.
- `lazywhitelist/contracts/ERC721LazyMintWhitelistTemplate.sol` — `Proxy` writing implementation into `_IMPLEMENTATION_SLOT` and delegatecalling `initialize(address,string)` in its constructor.
- `lazywhitelist/contracts/IERC721LazyMintWhitelist.sol` — interface.

### Key state / interface
- `bytes32 merkleRoot`, `uint MINT_PRICE`, `uint MAX_MINTS`, `uint256 public _tokensMinted`, `mapping(uint256 => uint256) _tokenEdition`, `string _tokenPrefix`.
- `onAllowList(address claimer, bytes32[] proof)` — `MerkleProof.verify(proof, merkleRoot, keccak256(abi.encodePacked(claimer)))`.

### External surface (traced)
`IERC721LazyMintWhitelist`: `premint(address[] to)`, `mint(bytes32[] merkleProof) payable`, `setAllowList(bytes32 _merkleRoot)`, `setTokenURIPrefix(string prefix)`, `withdraw(address _to, uint amount)`.
`Base` public: `onAllowList(address,bytes32[])`, `tokenURI(address,uint256)`, `_tokensMinted`.
`Implementation`: `initialize(address creator, string prefix)` (initializer); `premint`/`setAllowList`/`setTokenURIPrefix`/`withdraw` are `adminRequired`; `mint` is public `payable`.

### Distinctive mechanic — clone/template pattern
`ERC721LazyMintWhitelistTemplate` (an OZ `Proxy`) stores the implementation in the EIP-1967 slot `0x360894...382bbc` and `Address.functionDelegateCall`s `initialize(address,string)` at construction, producing a cheap per-creator clone. `mint` checks, in order: `_tokensMinted < MAX_MINTS`, `MINT_PRICE == msg.value`, and `onAllowList(msg.sender, proof)`, then mints via `IERC721CreatorCore.mintExtension` and records a 1-based `_tokenEdition`. `tokenURI = prefix + edition`.

### Pitfalls
- **`MINT_PRICE` and `MAX_MINTS` are hard-coded** (`0.1 ether` / `50`) with `// to be changed` comments and **no setter** — there is no way to change price/cap after deploy; treat this package as example/starter code, not production-hardened.
- `_premint` both mints gifts *and* bumps `MAX_MINTS += to.length`, so gifting quietly raises the public cap.
- `mint` requires exact `msg.value == MINT_PRICE` (no over/under-pay).
- Merkle leaf is `keccak256(abi.encodePacked(claimer))` (address only) — the allowlist tree must be built the same way, and it does not bind quantity.
- `Base.supportsInterface` only reports `ICreatorExtensionTokenURI` (the `Implementation` OR-combines admin + its own interface).

---

## Section 2 — Fonts (on-chain WOFF interface)

### What it is
A single interface, `IFontWOFF`, describing a contract that returns a WOFF font as a string — intended so fully on-chain art (e.g. SVG generators) can pull font data from a dedicated storage contract. This package is **interface-only**; no implementation ships here.

### Contract map
- `fonts/contracts/IFontWOFF.sol` — `interface IFontWOFF { function woff() external view returns(string memory); }`.

### External surface (traced)
- `woff() external view returns(string memory)` — the entire surface.

### Pitfalls / notes
- No concrete contract in this package — consumers must supply their own storage implementation returning `woff()`.
- Returning a full WOFF as a `string` implies large calldata/return payloads; only practical for on-chain rendering read paths (view calls), not on-chain writes per render.

## Open questions
- Is there a deployed `IFontWOFF` implementation elsewhere in the monorepo or an external repo that on-chain SVG extensions consume?
- Was LazyWhitelist ever deployed in production given the hard-coded, unchangeable price/cap, or is it purely a reference implementation?

See also: [[repo-overview]], [[lazy-payable-claim]], [[shared-libraries]].
