# CDS Agent Instructions

## Required Reading

Read the [shared test guide](../AGENTS.md) and [TC conventions](../TC_CONVENTION.md).
Use the task-specific references below; do not load the entire specification for every change.

## Implementation Files

- Suite: [cds_tests.robot](cds_tests.robot)
- Keywords: [cds_keywords.robot](../../resources/cds_keywords.robot)
- Variables: [cds_variables.robot](../../resources/cds_variables.robot)
- Protocol: [CdsHelper.py](../../libraries/CdsHelper.py)
- Database: [PdbHelper.py](../../libraries/PdbHelper.py)
- Notifications: [HttpNotiServer.py](../../libraries/HttpNotiServer.py)

## Essential Rules

- Connect Rchannel before Schannel; manage connections in Suite Setup/Teardown.
- PDB access is required during suite setup. Excluding DB-tagged tests does not remove that prerequisite.
- `CommandResult=SC` alone does not prove business application. Assert the expected DB change and applicable notifications.
- Preserve existing assertions and cleanup. Do not suppress release-ACK validation failures; teardown must still close sockets.
- Existing cases 021–028 have subscriber-number and HFC state dependencies. Review them before selecting or modifying individual cases; do not introduce new order-dependent tests.
- Keep test values in the variable files and environment-only values in `config/env/<env>.py`.
- Do not infer byte widths or business success from field names or successful message exchange. Keep unconfirmed behavior explicit.

## Task-Specific References

| Change | Read first |
|---|---|
| Connection setup, handshake, or release | [Connections and lifecycle](SPEC.md#connection--dual-socket-rchannel-first) |
| Header, transaction ID, or body encoding | [Wire encoding](SPEC.md#wire-encoding) |
| Business-code fields | [Field sets](SPEC.md#set-of-fields-by-business-code) and [known gaps](SPEC.md#business-code) |
| Business application assertions | [PDB criteria](SPEC.md#pdb-judgment-criteria-by-business-code) and [coupon/option criteria](SPEC.md#couponoption-series-judgment-criteria-designated-on-2026-08-10) |
| Test selection or execution order | [TC dependencies](SPEC.md#dependency-between-tcs--tc-cds-021--028-is-one-chain) |
| Notification assertions | [Expected SBI notifications](SPEC.md#pcf-sbi-noti-received--what-are-you-waiting-for) |
| PDB configuration or queries | [Shared PDB guide](../../docs/shared/PDB.md) |
| HTTP/2 receiver behavior | [Shared SBI guide](../../docs/shared/SBI_NOTI.md) |
| Remote process startup | [Shared SSH guide](../../docs/shared/SSH.md) |

[The full specification](SPEC.md) contains protocol tables, schemas, samples, and historical evidence.
Call-flow documents remain optional developer reference, not prerequisites for TC authoring.

## Validation

From the repository root:

```bash
robot --dryrun -V config/env/dev.py -d results tests/cds/
```

Follow the root instructions for the mandatory final whole-suite dry run.
For encoding changes, also verify constructed bytes; for transport changes, use a local peer.
A dry run does not execute Python keyword bodies or prove runtime or PG behavior.
