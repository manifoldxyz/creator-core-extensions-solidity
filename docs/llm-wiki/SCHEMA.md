# Wiki Schema — creator-core-extensions-solidity Knowledge Base

## Domain

A code-oriented knowledge base for **[manifoldxyz/creator-core-extensions-solidity](https://github.com/manifoldxyz/creator-core-extensions-solidity)** — a monorepo of Solidity *extension applications ("Apps")* that install onto any [Manifold Creator Core](https://github.com/manifoldxyz/creator-core-solidity) ERC-721/ERC-1155 contract to add claims, burn-redeems, editions, metadata, and more.

Purpose: let an agent (or engineer) understand what each contract family does, its exact on-chain surface (functions/structs/events/errors traced to source), how the families relate, and the traps — without re-reading 90 `.sol` files each time.

Pinned to commit `5bc29bd` (2026-03-20). Solidity `^0.8.17`, Foundry-primary (Truffle legacy tests).

### The mental model (the #1 thing to get right)

These are **shared, singleton extensions**: ONE instance of e.g. `ERC721LazyPayableClaim` is deployed per chain, and *every* creator contract installs that same instance and registers its own **instance** (a claim/burnRedeem/etc. keyed by `(creatorContractAddress, instanceId)`). The extension holds the logic + funds flow; the creator contract holds the tokens and delegates mint/burn to the registered extension. Contrast with a per-creator deployed contract — that is NOT how this repo works.

Core inherited plumbing (from `@manifoldxyz/creator-core-solidity` + `libraries-solidity`):
- `AdminControl` — owner/admin gating; `creatorAdminRequired(creator)` modifier restricts config to the creator's admins.
- `IERC165` / `ICreatorExtensionTokenURI` — extensions advertise interfaces; creator core routes `tokenURI` to the extension.
- Delegation Registry (v1 `IDelegationRegistry`, v2 `IDelegationRegistryV2`) — lets a delegate wallet mint/act on behalf of a vault.
- `IManifoldMembership` — membership holders skip/discount the Manifold mint fee.

## Conventions

- File names: lowercase, hyphens, no spaces (e.g. `lazy-payable-claim.md`).
- Every page has YAML frontmatter (see below).
- Use `[[wikilinks]]` between pages (min 2 outbound per page).
- Cross-reference source with inline code paths RELATIVE to `packages/`, e.g. `manifold/contracts/lazyclaim/LazyPayableClaim.sol` — NOT wikilinks. Line-anchor when useful: `...LazyPayableClaim.sol:L120`.
- Every function signature / struct / error / event stated MUST trace to a real source file. Cite the path or omit it. NEVER invent a signature.
- `updated` bumps on every edit. New pages get added to `index.md`. Every action appends to `log.md`.

## Frontmatter

```yaml
---
title: Page Title
created: YYYY-MM-DD
updated: YYYY-MM-DD
type: concept | reference | comparison | query | overview
package: manifold | dynamic | edition | enumerable | lazywhitelist | redeem | fonts | repo
tags: [from taxonomy below]
sources: [manifold/contracts/lazyclaim/LazyPayableClaim.sol]
confidence: high | medium | low   # high ONLY when verified against source this run
contested: true                    # unresolved contradiction; never silently overwrite
---
```

`confidence: high` is reserved for claims read off the actual `.sol` during the run that set them.

## Tag Taxonomy (add here BEFORE using)

- Packages: `manifold`, `dynamic`, `edition`, `enumerable`, `lazywhitelist`, `redeem`, `fonts`
- Surface: `contract`, `abstract`, `interface`, `library`, `struct`, `event`, `error`, `modifier`
- Token standard: `erc721`, `erc1155`, `erc20`, `usdc`
- Mechanic: `claim`, `burn-redeem`, `edition`, `single`, `metadata`, `soulbound`, `gacha`, `deck`, `frame`, `physical`, `cross-chain`, `collectible`, `operator-filter`, `whitelist`, `dynamic-token`, `enumerable`
- Cross-cutting: `merkle`, `signature`, `delegation`, `membership`, `fee`, `admin`, `version-v2`
- Meta: `overview`, `pitfall`, `comparison`, `gap`, `unknown`

Every tag on a page must appear here. New tag → add here first.

## Page types

- `overview` (repo root) — architecture, package map, the shared extension model, install lifecycle. Start here.
- `concept/` — one page per contract FAMILY (lazy-payable-claim, burn-redeem, deck-claims, ...). Each: what it is → contract map (files + roles) → key structs/params → external surface (the functions a caller uses, signatures traced) → fees/membership handling → pitfalls → open questions. Split at ~200 lines.
- `reference/` — pure 1:1 surface dumps when a concept page would blow past 200 lines.
- `comparisons/` — v1-vs-v2, ERC721-vs-ERC1155, redeem-package-vs-burnredeem, etc.
- `queries/` — filed answers to "how do I X" worth keeping.

## Page Thresholds

- **Create a concept page** per contract family (a coherent directory under a package's `contracts/`), or per shared library group.
- **Add to existing** when a source belongs to a family already covered.
- **DON'T** create a page per interface `.sol` — fold interfaces into their family page.
- **Split** when a page exceeds ~200 lines → dedicated `reference/` dump.

## Confidence + contradiction policy

1. Newer source (higher V-suffix, later commit) supersedes older; note both.
2. Genuine contradiction → keep both, set `contested: true`, surface in run summary. NEVER silently overwrite.
3. A vague claim you couldn't trace to source → flag as `unknown` in that page's open questions.

## Honesty rule

Every "this contract does X" claim traces to a source path, or it is marked `(inference)` and gets `confidence: low`. The wiki documents the code as written, not as assumed. Match-existing-behavior: describe what the contract does, don't editorialize about bugs unless the code proves one.
