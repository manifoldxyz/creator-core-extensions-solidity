# AGENTS.md — creator-core-extensions-solidity

## Gather context from the LLM wiki FIRST

This repo has a source-grounded knowledge base at **`docs/llm-wiki/`**. Before exploring `packages/**/*.sol` by hand, use the wiki — it answers most "what does X do / how do the families relate" questions in one or two file reads instead of dozens.

### How to use it

1. **Start at `docs/llm-wiki/index.md`** — a sectioned catalog of all 19 concept pages, each with a one-line "the thing to know" (including the sharpest gotchas, e.g. V2 fees default to 0).
2. **Read `docs/llm-wiki/concepts/repo-overview.md`** for the architecture: the **shared singleton extension model** (one instance per chain, every creator installs it, instances keyed by `(creatorContractAddress, instanceId)`), the package map, and version lineage traps (redeem → burnredeem → burnredeemUpdatableFee; lazyclaim → lazyUpdatableFeeClaim).
3. **Jump to the family page** for whatever you're touching (e.g. `concepts/lazy-payable-claim.md`, `concepts/burn-redeem.md`). Each page has: contract map, real struct fields, external function signatures, fee/membership handling, and pitfalls — every claim cited to a `.sol` path relative to `packages/`.
4. **Cross-cutting plumbing** (membership fee gate, delegation registry v1/v2, standard `Instance*Mint` events, single-creator base) lives in `concepts/shared-libraries.md`.
5. **Verify against source before writing code.** The wiki is pinned to the commit noted in its `index.md` header. If the contract has changed since, the source wins — then update the wiki page.

### Keep the wiki current

If your change alters a documented behavior (signatures, structs, fees, mechanics):
- Update the relevant `docs/llm-wiki/concepts/*.md` page and bump its `updated` frontmatter date.
- Adjust its one-liner in `docs/llm-wiki/index.md` if the "thing to know" changed.
- Append an entry to `docs/llm-wiki/log.md`.
- Rules and tag taxonomy: `docs/llm-wiki/SCHEMA.md`. Never invent a signature — cite the `.sol` path or leave it out.

## Repo basics

- Monorepo of independent packages under `packages/` (`manifold` is the production suite). Build/test per package: `cd packages/<pkg>` then `forge build` / `forge test` (Foundry-primary; Truffle legacy for `edition`, `lazywhitelist`, `redeem`, `manifold`).
- `yarn install` per package requires `NPM_TOKEN` for `@manifoldxyz` scoped deps. Clone with `--recurse-submodules` (forge-std, operator-filter-registry, murky).
- Per-package agent guidance: `packages/manifold/CLAUDE.md` (conventions, gas patterns, custom errors).
