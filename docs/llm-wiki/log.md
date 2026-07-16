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

## [2026-07-16] create | concepts/cxrds-packs.md (US-016)
- New concept page for the CXRDS pack contract family (branch `cxrds-pack-contract`)
- Read & cited: manifold/contracts/cxrds/CXRDSPacks.sol + ICXRDSPacks.sol (confidence: high)
- Documents: dual-role ERC721SeaDrop pack + ERC1155 cards-core extension; RipOrder struct; deliverBatch/initializeCards/both tokenURI surfaces; EIP-712 RipPermit consent model (no nonces — burn is the replay lock); verbatim error taxonomy
- Pitfalls captured: CardsAlreadyInitialized naming (avoids inherited ConstructorInitializable.AlreadyInitialized collision); OZ EIP712 from node_modules not lib/openzeppelin-contracts; EIP-1271/Safe holders cannot rip in v1 (ecrecover-only, accepted non-goal); registerExtension is a cards-core admin action
- index.md: added catalog line under Burn/Redeem Families with the no-nonces / burn-is-the-lock gotcha
- Wikilinks: [[repo-overview]], [[burn-redeem]], [[collectible]], [[shared-libraries]]
