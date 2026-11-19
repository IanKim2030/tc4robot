# Test Suite Instructions

Read [TC conventions](TC_CONVENTION.md) and the target suite's `AGENTS.md`.
Use [the TC authoring skill](../.claude/skills/pg-tc-authoring/SKILL.md) for authoring or renumbering.

- Define the observable failure condition before adding a test: packet bytes, response fields, DB application, or notification arrival.
- Reuse Robot resources and variable constants; do not embed transport implementations in scenarios.
- Preserve test IDs, tags, ordering, suite setup/teardown, and disabled cases unless the task requires changing them.
- Read the node's prerequisites and dependencies before selecting individual tests.
- Validate through a direct Robot command with an explicit environment file. The runner can seed DBs before running tests; it is not a shortcut for offline dry runs.
- Call-flow documents are optional developer reference, not TC requirements.

## Independence and Existing Stateful Suites

The root policy requires independent tests with cleanup. Current PCF sender/receiver
pairs and CDS subscriber chains are known legacy gaps, not exceptions allowing new
order-dependent tests. Folder and node documents describe how the existing suites
currently work so they can be executed correctly until redesigned.

Do not add new dependencies or change existing chain order as incidental cleanup.
When a task explicitly changes those scenarios, make their prerequisites and
cleanup self-contained and validate both individual and suite execution.

Preserve Korean Robot test names, `Documentation`, logs, and failure messages unless explicitly asked to translate them. Project documentation remains English.

## Maintaining Node Specifications

Each `tests/<node>/AGENTS.md` owns both local instructions and the full node specification for TC authoring.
Read [TC conventions](TC_CONVENTION.md) for shared rules.

For each node, keep a concise TC authoring section with:

1. Test suite, keyword, variable, and Python library links.
2. Required connections, environment data, and external services.
3. Inputs, expected results, observable assertions, and verification limits.
4. Ordering dependencies and restrictions on selecting individual tests.
5. Relevant shared references and applicable validation commands.

Keep protocol details and node-specific pitfalls here. Link shared DB/SSH/SBI
procedures rather than copying them. Call flows are optional developer reference;
do not place TC-only requirements exclusively there. Verify counts and defaults
against current code when editing them, and distinguish confirmed behavior from assumptions.

## Node Specifications

- [NAG](nag/AGENTS.md)
- [PCF](pcf/AGENTS.md)
- [LRS](lrs/AGENTS.md)
- [UPM](upm/AGENTS.md)
- [CDS](cds/AGENTS.md)
- [NWDAF](nwdaf/AGENTS.md)
- [RTS](rts/AGENTS.md)
