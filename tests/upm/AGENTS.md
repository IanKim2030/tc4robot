# UPM Agent Instructions

## Required Reading

Read the [shared test guide](../AGENTS.md) and [TC conventions](../TC_CONVENTION.md).
Use the task-specific references below instead of loading the full specification for every change.

## Implementation Files

- Suite: [upm_tests.robot](upm_tests.robot)
- Keywords: [upm_keywords.robot](../../resources/upm_keywords.robot)
- Variables: [upm_variables.robot](../../resources/upm_variables.robot)
- Python: [TcpHelper.py](../../libraries/TcpHelper.py) · [FtpServerHelper.py](../../libraries/FtpServerHelper.py) · [SftpServerHelper.py](../../libraries/SftpServerHelper.py)

## Essential Rules

- Preserve suite-level Hello within the protocol deadline; a successful connection alone is insufficient.
- Distinguish active requests from PG-triggered passive requests. Do not enable passive cases without their event prerequisites.
- Keep the body `tid` distinct from the header `txn_id`.
- Use the matching FTP/SFTP environment configuration and preserve optional dependencies.
- Do not turn unconfirmed fileinfo fields or guessed FIN names into strict assertions without evidence.

## Task-Specific References

| Change | Read first |
|---|---|
| Connection setup and lifecycle | [connection](SPEC.md#connection) |
| Message direction, constants, and response formats | [Message type — two-way](SPEC.md#message-type--two-way) |
| Current TC coverage | [TC](SPEC.md#tc) |
| FTP/SFTP and fileinfo reception | [fileinfo (0x0c) — FTP receiving server (connection information confirmed, fileinfo schema ⚠ unconfirmed)](SPEC.md#fileinfo-0x0c--ftp-receiving-server-connection-information-confirmed-fileinfo-schema--unconfirmed) |
| Known limitations and unresolved behavior | [trap](SPEC.md#trap) |

[Full specification](SPEC.md). Use its shared-document links for DB, SBI, or SSH details when applicable.
Call-flow documents remain optional developer reference, not prerequisites for TC authoring.

## Validation

From the repository root:

```bash
robot --dryrun -V config/env/dev.py -d results tests/upm/
```

Follow the root instructions for the mandatory final whole-suite dry run.
Byte-level and local-peer checks are additional evidence for encoding or transport changes.
A dry run does not execute Python keyword bodies or prove runtime or PG behavior.
