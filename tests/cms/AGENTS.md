# CMS Agent Instructions

## Required Reading

Read the [shared test guide](../AGENTS.md) and [TC conventions](../TC_CONVENTION.md).
The tool is the **server** here (CMSWEB); PG.CMS (`CMS201`) connects to it.

## Implementation Files

- Suite: [cms_tests.robot](cms_tests.robot)
- Keywords: [cms_keywords.robot](../../resources/cms_keywords.robot)
- Variables: [cms_variables.robot](../../resources/cms_variables.robot)
- Python: [CmsHelper.py](../../libraries/CmsHelper.py) · [SftpServerHelper.py](../../libraries/SftpServerHelper.py) · [TcpHelper.py](../../libraries/TcpHelper.py) · [PdbHelper.py](../../libraries/PdbHelper.py)

## Essential Rules

- Send compact JSON only; PG's parser needs `"`/`["` right after each colon ([Wire format](SPEC.md#wire-format)).
- Never edit PG configuration from the suite. Report mismatches in `Check CMS Prerequisites`.
- File-server protocol follows the PG cfg (`[CMS] CMSWEB_SFTP` / `NWDAF_SFTP`; first character `N` → FTP). Never hard-code SFTP-only behaviour in a TC ([FTP or SFTP](SPEC.md#ftp-or-sftp--chosen-from-the-pg-cfg-at-startup)).
- SFTP/FTP passwords only from environment variables, never a Robot argument or a committed value:
  - `PG_PWD_CMS_SFTP`: simulator download.
  - `PG_PWD_CMS_SFTP_UPLOAD`: SC receive server.
  - `PG_PWD_CMS_FIN_SSH`: real `pg` account on the tool host, for the FIN check. Optional; defaults to `PG_PWD_CMS_SFTP`.
- The SC receive server (`${CMS_SC_SFTP_PORT}`) starts only in the SC test (`Ensure CMS SC Server`). Its prerequisites fail that test alone. Received files are kept by default; with `${CMS_SC_CLEANUP}=True`, delete only the files named by `${CMS_SC_FILES}` from `${CMS_SC_UPLOAD_DIR}`.
- The simulator serves GET only. Real PG PUTs the `.FIN` to the tool host's real sshd (port 22), so `${CMS_REMOTE_DIR}` must exist there and be writable by `pg` ([File handling](SPEC.md#file-handling)). Keep `${CMS_FIN_MODE}=sshd` for real PG; `simulator` is for a patched or fake PG.
- FIN files are kept by default (`${CMS_FIN_CLEANUP}=False`). When cleanup is on, delete only FIN files matching this run's prefixes (`${CMS_FIN_PREFIXES}`). Never remove other files in the real directory.
- Tests that wait for PG to close the control channel must first call `Cms Should Be Connected`, so an already closed socket fails instead of passing.
- Give every NTI case a unique file name and `dateTime` (`cms_new_case` does this).
- Negative "must not happen" checks observe a bounded window (`${CMS_QUIET_WINDOW}`) by file name, not by count.

## Task-Specific References

| Change | Read first |
|---|---|
| Connection, prerequisites, settings | [Channels](SPEC.md#channels) |
| Message fields and order | [Message flow](SPEC.md#message-flow-ccmswebrun) |
| File names, FIN, retries | [File handling](SPEC.md#file-handling) |
| SC (NWDAF) forwarding | [SC forwarding](SPEC.md#sc-nwdaf-forwarding-runsftpsc) |
| DB assertions | [PDB result](SPEC.md#pdb-result-setdata--setfilestatus) |

## Validation

```bash
robot --dryrun -V config/env/dev.py -d results tests/cms/
python -m unittest libraries.tests.test_cms_helper
```

A local peer run needs `paramiko` (present on the 142 test host). Run the suite
against a fake PG client with `--variable REMOTE_CONFIG_ENABLED:False --variable PG_SSH_ENSURE:False --variable PG_HOST:127.0.0.1 --exclude db`.
On 142 use `~/venv/bin/python` (system `python3` has no `paramiko`). For `sshd` mode without the real
`pg` password, start a second local `SftpServer` as the stand-in sshd and point `CMS_FIN_SSH_PORT` at it.
A dry run does not execute Python keyword bodies.
