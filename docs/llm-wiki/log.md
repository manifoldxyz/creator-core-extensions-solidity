# Wiki Log

> Chronological record of all wiki actions. Append-only.
> Format: `## [YYYY-MM-DD] action | subject`
> Actions: ingest, update, query, lint, create, archive

## [2026-07-15] create | Wiki initialized
- Domain: manifoldxyz/creator-core-extensions-solidity (Solidity NFT extension apps)
- Repo pinned to commit 5bc29bd (2026-03-20)
- Structure created: SCHEMA.md, index.md, log.md, concepts/, reference/, comparisons/, queries/
- Source survey: 7 packages, ~90 non-lib .sol files (manifold=92 incl. libs, the dominant package)

## [2026-07-15] ingest | Full repo seeded — 19 concept pages
- Read ~90 non-lib .sol across 7 packages at commit 5bc29bd
- Parent-written: repo-overview.md, shared-libraries.md
- Subagent-seeded (6 parallel leaf agents, all traced to source):
  - lazy-payable-claim, lazy-payable-claim-v2, burn-redeem, cross-chain-burn,
    deck-claims, gacha-serendipity, frame-claims, editions-and-singles,
    collectible, physical-claim, metadata-frozen, soulbound, operator-filterer,
    redeem-package, edition-package, dynamic-and-enumerable, lazywhitelist-and-fonts
- index.md written from per-page gotcha one-liners
- Lint: 19 pages, 0 broken wikilinks, 0 orphans, 0 missing frontmatter, all <200 lines

## [2026-07-15] lint | 0 issues
- broken links: 0 | orphans: 0 | missing frontmatter: 0 | oversized pages: 0

## [2026-07-16] create | concepts/manifold-packs.md (US-016)
- New concept page for the ManifoldPacksSeaDropShim pack contract family (branch `manifoldpacks-pack-contract`)
- Read & cited: manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol + IManifoldPacksSeaDropShim.sol (confidence: high)
- Documents: dual-role ERC721SeaDrop pack + ERC1155 cards-core extension; RipOrder struct; deliverBatch/initializeCards/both tokenURI surfaces; EIP-712 RipPermit consent model (no nonces — burn is the replay lock); verbatim error taxonomy
- Pitfalls captured: CardsAlreadyInitialized naming (avoids inherited ConstructorInitializable.AlreadyInitialized collision); OZ EIP712 from node_modules not lib/openzeppelin-contracts; EIP-1271/Safe holders cannot rip in v1 (ecrecover-only, accepted non-goal); registerExtension is a cards-core admin action
- index.md: added catalog line under Burn/Redeem Families with the no-nonces / burn-is-the-lock gotcha
- Wikilinks: [[repo-overview]], [[burn-redeem]], [[collectible]], [[shared-libraries]]

- 2026-07-16 — manifold-packs: reworked per PR #119 review — PackConfig (owner-updatable card params, Serendipity-style init/update guards), SignatureChecker+EIP-1271 (Safe holders can rip), break-glass ripSignatureRequired switch + signatureVerified event flag, dynamic RipOrder cardIds/amounts (duplicate variations, sum==cardsPerPack), removed pack tokenURI override.

- 2026-07-16 — manifold-packs: 2nd review pass (PR #119) — removed MAX_PACKS constant (SeaDrop maxSupply is the cap); ripSignatureRequired now internal (per-rip signatureVerified flag suffices); creatorContractAddress moved from constructor immutable to a set-once param of initializeCards(cardsCreator, config); dropped SignerUpdated event; numberOfVariations now FIXED at init (CannotChangeVariations replaces raise-path CannotLowerVariations/NonContiguousVariations).

- 2026-07-17 — manifold-packs: **L1 Merkle contents-commitment (F1 fix, PR #119, branch cxrds-pack-contract).** Added `contentsRoot` + one-shot-per-seed `seedContents(bytes32) onlyOwner` (emits `ContentsSeeded`); `RipOrder` gains `bytes32 salt` + `bytes32[] proof`; `deliverBatch` now computes leaf `keccak256(abi.encode(packId, cardIds, amounts, salt))` and gates on `MerkleProof.verify` (else `ContentsMismatch`), plus up-front `ContentsNotSeeded` when the root is zero. **Additive** — the collector EIP-712 permit check is unchanged and still enforced independently. **Deliberate trust choice (Don):** NO `_totalMinted()==0` lock — the root is owner-mutable at any time; it binds the *signer* (can't substitute/over-mint/misdeliver contents), not the *owner* (already trusted for airdrop/break-glass/metadata). Leaf uses `abi.encode` (NOT encodePacked — array-boundary collision), single-hashed, OZ sorted-pair convention (matches murky in tests). New pitfalls: hash-convention-mismatch bricks every rip; changing cardsPerPack without re-seeding bricks rips. 100/100 manifoldpacks tests green (87 baseline + 13 new merkle); runtime size 22,288 B (< 24,576).

- 2026-07-18 — manifold-packs: **owner-controlled secondary-transfer pause (PR #119, branch cxrds-pack-contract).** Added `transfersPaused` (public bool) + `updateTransfersPaused(bool) onlyOwner` (emits `TransfersPausedChanged`) + `TransfersPaused` error, plus `approve`/`setApprovalForAll`/`_beforeTokenTransfers` overrides. Adapts OpenSea `ERC721SeaDropPausable` (which is NOT vendored in the pinned seadrop submodule, so the mechanic is inlined) with TWO deliberate divergences: **defaults `false`/unpaused** (upstream defaults paused → would brick sealed-pack secondary market on deploy) and the pause is **secondary-only** via `from != 0 && to != 0` (upstream reverts on any `from != 0`, which would revert the rip `_burn` and brick every rip). Mint + rip always flow; only wallet-to-wallet / marketplace moves + their approvals are pausable. 111/111 manifoldpacks tests green (+11 pausable, incl. paused-does-not-block-mint/rip); runtime size 22,591 B (< 24,576).

- 2026-07-18 — manifold-packs: **optional external tokenURI resolver (PR #119, branch cxrds-pack-contract).** `PackConfig` gains `address tokenURIExtension` (freely updatable). When non-zero, card `tokenURI(creator, tokenId)` delegates verbatim to `ICreatorExtensionTokenURI(tokenURIExtension).tokenURI(creator, tokenId)`, bypassing the built-in `cardsLocation` folder pattern; `address(0)` (default) keeps folder-pattern resolution. Mirrors lazy-claim's `StorageProtocol.ADDRESS` delegation (`ERC1155LazyPayableClaimCore.tokenURI`) — lets the owner point card metadata at an on-chain renderer / future resolver without redeploying. Both `tokenURI` args are forwarded (a shared resolver can key on `creator`). 117/117 manifoldpacks tests green (+6 tokenURI-extension: default folder, verbatim delegation, actually-called via reverting mock, clear-back-to-folder, config persistence); runtime size 23,085 B (< 24,576).
