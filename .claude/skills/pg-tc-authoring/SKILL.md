---
name: pg-tc-authoring
description: Use when adding, editing, disabling, or renumbering test cases in the PG integration Robot Framework suites (NAG/PCF/LRS/UPM/CDS/NWDAF/RTS).
---

# Authoring PG Test Cases

## Read Before Editing

1. [TC conventions](../../../tests/TC_CONVENTION.md) own naming, numbering, tags, lifecycle rules, and exceptions.
2. Read the target suite's `tests/<iface>/AGENTS.md`, which links to the relevant sections of its sibling `SPEC.md`.
3. Use the [interface matrix](../../../docs/INTERFACES.md) when changing message types or cross-channel behavior.

## Procedure

1. **State the assertion.** Identify the input, expected observable result, and the failure the TC must detect. Distinguish byte construction, response receipt, DB application, and notification arrival.
2. **Find an existing example.** Reuse the target suite's keywords and constants. Add missing values in `resources/<iface>_variables.robot`, not as literals in the TC.
3. **Check prerequisites.** Read node ordering and state dependencies before inserting or selecting cases. PCF-role cases belong to the NAG group (TC-NAG-008–017); NWDAF isolated malformed-packet connections have a documented lifecycle exception.
4. **Implement the smallest coherent scenario.** Preserve the suite's established Korean test language. Apply the numbering and disabled-test rules from TC conventions and update the suite summary where necessary.
5. **Validate.** Run a direct Robot dry run with the explicit environment file, then check changed runtime behavior with local peers or byte assertions. Use live PG only for integration evidence.
6. **Update the owning specification.** Record changed inputs, assertions, dependencies, and remaining limits in the node document. Call flows are developer-only reference.

Example structural checks from the repository root:

```bash
python -m robot -V config/env/dev.py --dryrun tests/<iface>/
python -m robot -V config/env/dev.py --dryrun --include <tag> tests/
```

Replace `<iface>` and `<tag>` with actual values. Do not run the seeding wrapper merely
to obtain a dry run. Consult the [workflow](../../../docs/agent/workflow.md) for execution details.

## Runtime Evidence

A dry run resolves Robot keywords but does not execute Python keyword bodies or
exercise argument conversion and network behavior. For send/receive changes,
provide a local fake peer for the relevant protocol and all required auxiliary channels.
No generic `fake_pg.py` is bundled. Use byte-level assertions for new encoding and
follow the [wire encoding skill](../pg-wire-encoding/SKILL.md) when applicable.

Report completed checks and unverified live behavior separately. A successful send,
ACK, or dry run must not be described as proof of business application.
