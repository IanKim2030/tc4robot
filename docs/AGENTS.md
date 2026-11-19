# Documentation Instructions

Use [the documentation index](README.md) to find the owning document.

- Write documentation in English; preserve literal API names, byte values, and existing code identifiers.
- Put common TC policy in `tests/TC_CONVENTION.md`, the resource catalog in `resources/AGENTS.md`, node requirements in `tests/<node>/AGENTS.md`, and shared infrastructure details in `shared/`.
- `callflow/` is developer-only background. TC prerequisites, ordering, assertions, and known limits must be understandable without reading it.
- Link to the owning source instead of copying mutable ports, defaults, counts, or procedure lists into several documents.
- Keep code paths current: Python helpers are in `libraries/`; Robot resources remain in `resources/`.
- When changing headings, update incoming section links. Check link targets, Markdown structure, and `git diff --check`.
- The generated CDS call-flow document must be changed through its generator.

## Documentation Entry Points

Maintain the [documentation index](README.md), [architecture](ARCHITECTURE.md),
and [applied changes](agent/current-state.md) here rather than expanding the root
instructions into a documentation catalog. Write new documentation in English.
`CLAUDE.md` and `CLAUDE.md.english` remain pointers to the root `AGENTS.md`.
