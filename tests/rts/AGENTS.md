# RTS Agent Instructions

## Required Reading

Read the [shared test guide](../AGENTS.md) and [TC conventions](../TC_CONVENTION.md).
Use the task-specific references below instead of loading the full specification for every change.

## Implementation Files

- Suite: [rts_tests.robot](rts_tests.robot)
- Keywords: [rts_keywords.robot](../../resources/rts_keywords.robot)
- Variables: [rts_variables.robot](../../resources/rts_variables.robot)
- Python: [RtsHelper.py](../../libraries/RtsHelper.py) · [PdbHelper.py](../../libraries/PdbHelper.py) · [HttpNotiServer.py](../../libraries/HttpNotiServer.py)

## Essential Rules

- Keep RTS separate from the CDS PG.RDS coupon reservation poller.
- L1 denotes WCDMA and L2 denotes LTE; Y/N selects block/unblock.
- Distinguish wire offset 14 from DB offset 85; never mix the two constant sets.
- Separate ACK receipt, order-history bytes, subscriber service application, and SBI arrival in assertions.
- Do not assert unconfirmed SERVICE-row deletion for unblock cases; preserve documented cleanup and retry behavior.

## Task-Specific References

| Change | Read first |
|---|---|
| Connection setup and lifecycle | [Connection](SPEC.md#connection) |
| Message direction, constants, and response formats | [Message Types](SPEC.md#message-types) |
| Wire layout or byte-level changes | [Wire Encoding: Two Offset Systems](SPEC.md#wire-encoding-two-offset-systems) |
| Current TC coverage | [Test Cases](SPEC.md#test-cases) |
| Known limitations and unresolved behavior | [Open Questions](SPEC.md#open-questions) |

[Full specification](SPEC.md). Use its shared-document links for DB, SBI, or SSH details when applicable.
Call-flow documents remain optional developer reference, not prerequisites for TC authoring.

## Validation

From the repository root:

```bash
robot --dryrun -V config/env/dev.py -d results tests/rts/
```

Follow the root instructions for the mandatory final whole-suite dry run.
Byte-level and local-peer checks are additional evidence for encoding or transport changes.
A dry run does not execute Python keyword bodies or prove runtime or PG behavior.
