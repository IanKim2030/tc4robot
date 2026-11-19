# NWDAF Agent Instructions

## Required Reading

Read the [shared test guide](../AGENTS.md) and [TC conventions](../TC_CONVENTION.md).
Use the task-specific references below instead of loading the full specification for every change.

## Implementation Files

- Suite: [nwdaf_tests.robot](nwdaf_tests.robot)
- Keywords: [nwdaf_keywords.robot](../../resources/nwdaf_keywords.robot)
- Variables: [nwdaf_variables.robot](../../resources/nwdaf_variables.robot)
- Python: [TlvHelper.py](../../libraries/TlvHelper.py)

## Essential Rules

- Verify encoding with build-only byte assertions; successful sending does not prove PG interpretation.
- Preserve the isolated malformed-packet cases 034–037; do not generalize reconnection to ordinary TCs.
- Update TLV tags in both `libraries/TlvHelper.py` and `resources/nwdaf_variables.robot`.
- Confirm field widths, byte representations, and supported ranges from the relevant source evidence; do not guess.

## Task-Specific References

| Change | Read first |
|---|---|
| Connection setup and lifecycle | [connection](SPEC.md#connection) |
| Message direction, constants, and response formats | [Message type](SPEC.md#message-type) |
| Wire layout or byte-level changes | [★ wire encoding](SPEC.md#-wire-encoding) |
| Current TC coverage | [TC](SPEC.md#tc) |
| Known limitations and unresolved behavior | [⚠ Confirmation required](SPEC.md#-confirmation-required) |

[Full specification](SPEC.md). Use its shared-document links for DB, SBI, or SSH details when applicable.
Call-flow documents remain optional developer reference, not prerequisites for TC authoring.

## Validation

From the repository root:

```bash
robot --dryrun -V config/env/dev.py -d results tests/nwdaf/
```

Follow the root instructions for the mandatory final whole-suite dry run.
Byte-level and local-peer checks are additional evidence for encoding or transport changes.
A dry run does not execute Python keyword bodies or prove runtime or PG behavior.
