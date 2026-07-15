# LLM Wiki — creator-core-extensions-solidity

An interlinked, source-grounded knowledge base for this repo, built for both humans and AI agents to quickly understand the contract families without re-reading ~90 `.sol` files.

Every claim (function signatures, struct fields, events, errors) is traced to a real source file at the commit this wiki was generated against. Pages cross-reference source with inline paths relative to `packages/` (e.g. `manifold/contracts/lazyclaim/LazyPayableClaim.sol`) and link each other with `[[wikilinks]]` — open the directory in Obsidian or VS Code for clickable navigation.

## Where to start

- **[index.md](./index.md)** — the catalog. Every page with a one-line "the thing to know."
- **[concepts/repo-overview.md](./concepts/repo-overview.md)** — architecture, package map, and the shared singleton extension model. Read this first.
- **[concepts/shared-libraries.md](./concepts/shared-libraries.md)** — the cross-cutting plumbing (membership fee gate, delegation registry, standard mint events).
- **[SCHEMA.md](./SCHEMA.md)** — conventions, tag taxonomy, and the rules the wiki follows.

## Structure

```
docs/llm-wiki/
├── SCHEMA.md        # conventions + domain config
├── index.md         # sectioned catalog with one-line summaries
├── log.md           # chronological build/maintenance log
└── concepts/        # one page per contract family (19 pages)
```

## Maintaining it

When contracts change, update the relevant `concepts/*.md` page, bump its `updated` frontmatter date, adjust its `index.md` entry, and append to `log.md`. Keep every claim traced to source — cite the file or leave it out. See `SCHEMA.md` for the full contribution rules.
