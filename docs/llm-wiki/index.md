# Wiki Index — creator-core-extensions-solidity

> Content catalog for the [manifoldxyz/creator-core-extensions-solidity](https://github.com/manifoldxyz/creator-core-extensions-solidity) knowledge base.
> Every page listed under its section with a one-line "the thing to know."
> Read [[repo-overview]] first, then jump to the family you need.
> Last updated: 2026-07-15 | Total pages: 19 | Repo pinned: commit 5bc29bd (2026-03-20)

## Start Here

- [[repo-overview]] — Architecture, package map, and the **shared singleton extension model**: one instance per chain, every creator installs it, instances keyed by `(creatorContractAddress, instanceId)`.
- [[shared-libraries]] — The copy-pasted-per-package plumbing: `IManifoldMembership` (waives platform fee), delegation registry v1/v2 (`mintFor` a vault), standard `Instance*Mint` events, single-creator base.

## Claim Families (manifold)

- [[lazy-payable-claim]] — ETH/USDC lazy claims. **Gotcha:** a claim with a non-zero `signingAddress` can ONLY be minted via `mintSignature`; `mint`/`mintBatch`/`mintProxy` hard-revert `MustUseSignatureMinting`, and proxy/signature paths never waive the platform fee.
- [[lazy-payable-claim-v2]] — Updatable-fee variant. **Gotcha:** the ONLY real change is `MINT_FEE`/`MINT_FEE_MERKLE` became mutable and **default to 0** — a fresh V2 deploy collects no platform fee until the owner calls `setMintFees`.
- [[deck-claims]] — Card-deck reveals. **Gotcha:** no user mint/payment path at all — `initializeClaim` mints zero-supply variation token IDs and a trusted signer deals them via `deliverMints`; fairness is 100% off-chain signer trust.
- [[gacha-serendipity]] — Randomized gacha. **Gotcha:** randomness is entirely off-chain — collectors `mintReserve` (paying `cost + 0.0005 ETH`, contract callers blocked), backend signer picks winners and calls `deliverMints`; on-chain only guarantees `delivered ≤ reserved`.
- [[frame-claims]] — Farcaster Frame mints + Paymaster. **Gotcha:** paymaster signature is recovered from a raw `bytes32` with NO EIP-191 prefix, with per-`(fid, nonce)` replay protection; 5 free sponsored mints then 0.0001 ETH each, paid XOR sponsored.
- [[collectible]] — Signature-gated purchase/premint. **Gotcha:** not merkle — every claim/purchase is an ECDSA sig over `(msg.sender, nonce)` so payloads are sender-bound and non-relayable; `purchaseMax != 0` doubles as the init sentinel.

## Burn / Redeem Families (manifold)

- [[burn-redeem]] — v1 + V2 burn-to-redeem (`BurnItem`/`BurnGroup`/`BurnRedeem`). **Gotcha:** in V2 the burn fees are mutable and **default to 0** (constructor never sets them) — nothing collected until an admin calls `setBurnFees`; v1 hardcodes 0.00069/0.00099 ETH.
- [[cross-chain-burn]] — Burn here, fulfill elsewhere. **Gotcha:** this contract NEVER mints — it only burns, bumps a counter, and emits `CrossChainBurn` for an off-chain fulfiller; all trust rests on one `_signingAddress` ECDSA sig, no on-chain cross-chain proof.
- [[physical-claim]] — Burn/mark a token to redeem a physical item. **Gotcha:** no on-chain instance config and no `initialize` — ALL economic terms live inside the server-signed `BurnSubmission`; `ERC721_NO_BURN` marks a token used without burning it.
- [[redeem-package]] — The **legacy** burn-redeem (package `redeem`), superseded by [[burn-redeem]]. **Gotcha:** "burns" are actually `transferFrom(..., 0xdEaD, ...)` pseudo-burns, so source-contract supply/enumeration never reflects them.
- [[manifold-packs]] — Gasless "rip": a dual-role `ERC721SeaDrop` pack collection that is ALSO an extension on a stock ERC1155 cards core; a signer submits collector-signed EIP-712 `RipPermit`s, each burning one pack to mint exactly 4 cards. **Gotcha:** **no nonces** — the pack burn IS the replay lock (a used permit's `ownerOf` reverts `OwnerQueryForNonexistentToken`); and the init error is `CardsAlreadyInitialized`, deliberately named to dodge the inherited `ConstructorInitializable.AlreadyInitialized()` collision.

## Edition / Single Families

- [[editions-and-singles]] — `ManifoldERC721Edition` + 1/1 singles (manifold pkg). **Gotcha:** token→instance indexing forks on creator `VERSION()` — v3+ packs `instanceId<<24|index`; pre-v3 reverse-scans `IndexRange[]` (gas grows with mint history). Not payable, no fee logic.
- [[edition-package]] — Numbered/prefix editions via minimal-proxy clones (package `edition`, incl. Nifty Gateway variant). **Gotcha:** EIP-1967 clone `initialize` pattern; `IndexRange`s only coalesce for contiguous mints — interleaved extension mints fragment them.

## Utility Extensions (manifold)

- [[metadata-frozen]] — Immutable-tokenURI mints. **Gotcha:** "frozen" is structural, not a runtime lock — the extension just exposes no URI-mutation entrypoint, but a *different* admin extension on the same creator still could rewrite the URI.
- [[soulbound]] — Non-transferable tokens. **Gotcha:** completely inert until an admin calls `setApproveTransfer(creator, true)`; enforcement is the `approveTransfer` veto where `msg.sender` is the creator contract; soulbound+burnable by default (inverted `Non*` flags).
- [[operator-filterer]] — OpenSea operator filtering. **Gotcha:** blocked operators cause a **revert with a custom error** (not a `false` return); `from == operator` always bypasses; `CreatorOperatorFilterer` keys blocklists per-creator by `msg.sender` despite being one shared deploy.

## Other Packages

- [[dynamic-and-enumerable]] — On-chain dynamic tokenURI (Arweave hash / SVG / time-based) + owner-enumeration extension. Two packages, two sections.
- [[lazywhitelist-and-fonts]] — Merkle-gated lazy mint (clone pattern) + on-chain WOFF fonts. **Gotcha:** `ERC721LazyMintWhitelistBase` hardcodes `MINT_PRICE = 0.1 ether` / `MAX_MINTS = 50` with no setter (reference code, not production); Fonts ships interface-only.
