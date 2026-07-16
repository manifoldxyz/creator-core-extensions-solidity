# CLAUDE.md — creator-core-extensions-solidity

See **[AGENTS.md](./AGENTS.md)** for full agent guidance. The short version:

## Gather context from the LLM wiki FIRST

Before exploring `packages/**/*.sol` by hand, read the knowledge base at **`docs/llm-wiki/`**:

1. **`docs/llm-wiki/index.md`** — catalog of all concept pages, each with a one-line "the thing to know."
2. **`docs/llm-wiki/concepts/repo-overview.md`** — the shared singleton extension model (one instance per chain, instances keyed by `(creatorContractAddress, instanceId)`), package map, version lineage traps.
3. **`docs/llm-wiki/concepts/<family>.md`** — per-family contract maps, real signatures/structs, fee handling, pitfalls; every claim cited to a `.sol` path.
4. Wiki is pinned to the commit in its `index.md` header — **source wins on conflict**; update the wiki page when you change documented behavior (see `docs/llm-wiki/SCHEMA.md`).

Package-level conventions (gas patterns, custom errors, naming): `packages/manifold/CLAUDE.md`.
