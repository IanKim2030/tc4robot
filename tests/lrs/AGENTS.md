# LRS Agent Instructions

## Required Reading

Read the [shared test guide](../AGENTS.md) and [TC conventions](../TC_CONVENTION.md).
Use the task-specific references below instead of loading the full specification for every change.

## Implementation Files

- Suite: [lrs_tests.robot](lrs_tests.robot)
- Keywords: [lrs_client_keywords.robot](../../resources/lrs_client_keywords.robot) · [lrs_keywords.robot](../../resources/lrs_keywords.robot)
- Variables: [lrs_variables.robot](../../resources/lrs_variables.robot) · [lrs_server_variables.robot](../../resources/lrs_server_variables.robot)
- Python: [TcpHelper.py](../../libraries/TcpHelper.py) · [HttpHelper.py](../../libraries/HttpHelper.py)

## Essential Rules

- Distinguish the 10204 client channel (raw REQ/ANS and HTTP) from the environment-configured LRS-PCF server channel (dev `192.168.15.142:8890`).
- Session-Info requires a side-channel Location-Info response before the HTTP response can complete.
- Prepare the PG-initiated connection within the accept timeout; preserve peer restrictions.
- Use real environment values where the specification records unresolved fixture data.

## Task-Specific References

| Change | Read first |
|---|---|
| Connection setup and lifecycle | [Connection: Two Distinct Channels](SPEC.md#connection-two-distinct-channels) |
| Message direction, constants, and response formats | [Message Types on Port 8890](SPEC.md#message-types-on-port-8890) |
| Current TC coverage | [Test Cases](SPEC.md#test-cases) |
| Known limitations and unresolved behavior | [Open Questions](SPEC.md#open-questions) |

[Full specification](SPEC.md). Use its shared-document links for DB, SBI, or SSH details when applicable.
Call-flow documents remain optional developer reference, not prerequisites for TC authoring.

## Validation

From the repository root:

```bash
robot --dryrun -V config/env/dev.py -d results tests/lrs/
```

Follow the root instructions for the mandatory final whole-suite dry run.
Byte-level and local-peer checks are additional evidence for encoding or transport changes.
A dry run does not execute Python keyword bodies or prove runtime or PG behavior.
