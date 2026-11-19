# UPM Specification

Read [AGENTS.md](AGENTS.md) for working rules. Read only the sections relevant to the task.

### TC Authoring Entry Point

- [TC conventions](../TC_CONVENTION.md) · [Validation workflow](../../docs/agent/workflow.md)
- Test suite: [`upm_tests.robot`](upm_tests.robot)
- Keywords: [`upm_keywords.robot`](../../resources/upm_keywords.robot)
- Variables: [`upm_variables.robot`](../../resources/upm_variables.robot)
- Python libraries: [`TcpHelper.py`](../../libraries/TcpHelper.py) · [`FtpServerHelper.py`](../../libraries/FtpServerHelper.py) · [`SftpServerHelper.py`](../../libraries/SftpServerHelper.py)
- Shared references: No mandatory node-specific PDB/SBI/SSH reference; consult the workflow before using runner-level seeding.

Hello is handled in suite setup. Active requests differ from passive PG-triggered requests; enable FTP/SFTP checks only with the matching environment configuration.

Use the sections below for message inputs, assertions, dependencies, and known limits.
Developer call-flow documents are optional background and are not prerequisites for TC authoring.

Specification: `UPM ↔ PG.BSUBS HFC Service Interface v1.1 (2025-12-02)`
File: [`upm_tests.robot`](upm_tests.robot) · [`upm_keywords.robot`](../../resources/upm_keywords.robot) · [`upm_variables.robot`](../../resources/upm_variables.robot)

### connection

| item | value |
|---|---|
| tool role | UPM (Client) |
| direction | Tools → PG |
| port | `${UPM_PG_PORT}` = 10506 |
| header | 8-octet common, Byte0 `0x00` |
| Body | JSON |
| time out | `${UPM_TIMEOUT}` = 10 seconds |
| socket | Single |

#### Suite Setup even says hello

Specification 3.1: If Hello is not sent within 5 seconds after connection, PG disconnects.
So `Suite UPM Connect` processes Hello immediately after connection.

```
Connection → Hello-Request (0x01) transmission → Response (0x02) verification (code=200)
     → Save ping-interval in ${UPM_PING_INTERVAL}
     → Save the key list to ${UPM_KEY_LIST}
```

If Hello fails, the suite does not even start with `Fatal Error`.

### Message type — two-way

| direction | opcode | constant | meaning |
|---|---|---|---|
| UPM → PG | `0x01` / `0x02` | `${MSG_HELLO_REQ}` / `_RESP` | Hello |
| | `0x03` / `0x04` | `${MSG_PING_REQ}` / `_RESP` | Ping |
| | `0x09` / `0x0a` | `${MSG_UPM_CELLINFO_NOTI_REQ}` / `_RESP` | Change Cell Info Notification |
| | `0x0b` / `0x0c` | `${MSG_UPM_SUBS_SYNC_REQ}` / `_RESP` | Full sync request |
| PG → UPM | `0x05` / `0x06` | `${MSG_UPM_SUBS_CHANGE_REQ}` / `_RESP` | change number |
| | `0x07` / `0x08` | `${MSG_UPM_SUBS_INFO_REQ}` / `_RESP` | Subscriber Cell Info Request |
| | `0x0d` / `0x0e` | `${MSG_UPM_INFO_CHANGE_REQ}` / `_RESP` | Product/Device Change |

`0x05`·`0x07`·`0x09`·`0x0b` have completely different meanings in different nodes —
[opcode conflict table](../../docs/INTERFACES.md#opcode-conflict--use-the-constant-name-for-each-node-as-is).

All three types of passive reception look the same: echo `code-type`/`branch-name`/`tid`/`mdn` of the request body
Add `result-code=${UPM_RC_SUCCESS}` and reply as `${hdr}[txn_id]`.

#### tid — separate from txn_id

Inside the JSON Body `tid`(24 digits) in the header `txn_id`It is completely separate from (4-byte binary).
The `Next UPM TID` keyword produces:

```
EquipmentNo(5) + "-" + yyyyMMdd(8) + seq(10)
```

#### code-type

`${UPM_CT_*}` — Join `01` / … / `06` Product/Device change. It is a string.
Verify with `UPM Code Type Should Be`.

#### fileinfo (0x0c) — FTP receiving server (connection information confirmed, fileinfo schema ⚠ unconfirmed)

Specification 6.6.1/6.6.2 only says “fileinfo can be included” in the 0x0c (Subs-Sync-Response) response.
It is written. The schema of the fileinfo field itself (file name/size, etc.) is still not confirmed.
Did — The original text of the specification is not in this repo, and the overall grep results show no other mention.

> The current dev is `UPM-R2`(SFTP) (transitioned 2026-10-29). `${UPM_SYS_ID}` Default and
> `config/env/dev.py` is `UPM-R2`, and dev.py holds the SFTP connection —
> `UPM_FTP_USE_SFTP=True` · `UPM_FTP_PORT=2222` · `UPM_FTP_REMOTE_PATH=/UPM-R2`
> (The `UPM-R1` configuration for plain text FTP is left commented out in dev.py). seed's
> Enter `T_BAROD_PEER_TABLE` as `SYSTEM_ID='UPM-R2'`.
> ★ Password is not committed. — Given as environment variable `PG_PWD_UPM_FTP` (2026-11-04).
> Since `FtpServerHelper.py` is read directly, the Robot variable (`${UPM_FTP_PASSWORD}`) has been removed.
> The table below is the record  of `UPM-R0` (plain text FTP) items before .

However, FTP connection information was confirmed to be the FTP target setting on the PG side. (2026-10-22) — PG settings
`SYSTEM_ID_04=UPM-R0` item (confirmed to be our item as it matches `${UPM_SYS_ID}` at the time. 2026-10-28 UPMROB → UPM-R0,
PASSWORD_04 upm1234 → changed to upm, 2026-10-29 dev changed to UPM-R2)
It contained:

| key | value | meaning |
|---|---|---|
| `IP_04` | `192.168.15.142` | Address to which PG will connect (host where the tool runs) |
| `PORT_04` | `2121` | `${UPM_FTP_PORT}` |
| `USER_ID_04` / `PASSWORD_04` | `upm` / `upm` | `${UPM_FTP_USER}` / Environment variable `PG_PWD_UPM_FTP` |
| `REMOTE_PATH_04` | `/PG/FTP/UPM-ROBOT` | Path to CWD after logging in — `${UPM_FTP_REMOTE_PATH}` |
| `LOCAL_PATH_04` | `/PG/FTP/UPM` | Local path on PG side (original file location, for reference only) |
| `USE_SFTP_04` | `N` | Plaintext FTP (not SFTP) — matches pyftpdlib selection |

In other words, “PG sends a file to UPM” means that PG attaches to the FTP Client and pushes it.
It was correct (user confirmed), and this setting also confirmed that the tool would act as FTP server  —
`libraries/FtpServerHelper.py`(same structure as `HttpNotiServer.py`: delayed import +
daemon thread + receive queue, wrapping pyftpdlib). `REMOTE_PATH_04` is pyftpdlib
FTP is interpreted as a relative path  based on the virtual root (upload directory), so when starting the server,
Create that subdirectory in advance (if it does not exist, CWD will be rejected with 550 after logging in).

There are 2 files being transmitted (confirmed by user, 2026-10-22) — data file + "FIN" file
(Trigger file to signal completion of transfer, common practice in legacy batch transfers). Which one
FIN is identified by `${UPM_FTP_FIN_PATTERN}` (default `FIN`, case irrelevant) in the file name.
Assume that it is included — once the actual naming convention is confirmed, you only need to change that variable.

After `TC-UPM-004` receives 0x0c, it goes to `Verify Subs Sync Fileinfo`(`upm_keywords.robot`)
Let the following be best-effort:

1. If fileinfo is not present, it is skipped (it is only “included” in the specification and is not present in every response).
2. If fileinfo exists, 2 files  (data+FIN) for `${UPM_FTP_WAIT}` (default 30s)
   Wait to see if all come in — if you can't fill both, Fail (this is strict). failure
   Leave the number of messages (0/1 only) and FTP connection history .
   Distinguishes between “PG does not connect” and “Connected but does not send files”
   (2026-10-22 — In fact, a situation where connection, reception, and errors were all 0 was reproduced, and the two
   (I fixed what I couldn't tell).
3. If neither of the two received files matches the FIN pattern, only a ⚠ WARN log is left (whichever one is
   Failure to distinguish FIN recognition—pattern may differ from assumption).
4. The key assumed to be the file name in fileinfo (`filename`/`fileName`/`file_name`/
   (see `file-name`/`name`, `Guess Fileinfo Filename`), the received file name and
   However, even if  is not correct, it leaves only a WARN log and does not fail.  — fileinfo
   This is because the actual key name may differ from the estimate.

> ⚠ Once you have the actual fileinfo sample and FIN file naming convention, `Guess Fileinfo
> Filename`/`${UPM_FTP_FIN_PATTERN}`(upm_keywords.robot / upm_variables.robot)
> Update this section together — it's all speculation for now.

To turn it off: `bash run_tests.sh upm --no-ftp` (the suite runs without pyftpdlib).

SFTP alternative (added 2026-10-22) — `USE_SFTP_04` in PG settings is checked, the value is `N`
(plaintext FTP), but `${UPM_FTP_USE_SFTP}` in case it changes to `Y` in other environments.
If you set (default `${FALSE}`) to True, the same receiving server will be launched through SFTP instead of FTP —
`libraries/SftpServerHelper.py`(paramiko, delayed import). host/port/account/
The remote_path variable reuses the exact same one as FTP, and the returned server handle is also
Methods like FtpServer (files/errors/connections/clear/stop/is_running)
Implement `upm_keywords.robot`/`Verify Subs Sync Fileinfo` no matter which side is floating
Write it as is. Toggle: `bash run_tests.sh upm --sftp` / `--no-sftp`.

> ⚠ Could not actually run and verify — Unlike pyftpdlib (FTP), it is a mature SFTP
> Since there is no server-specific library, I directly implemented it with the paramiko low-level API, and this
> I don't even have to run `import paramiko` since I don't have local Python in my work environment.
> I couldn't do it. Before testing an environment where USE_SFTP_04 is actually `Y`, you must
> First check the upload round trip with a standard `sftp` client, etc.

### TC

Currently 4 active / 1 comment. Tags: `upm` `hello` `ping` `cellinfo-noti` `subs-sync` `smoke` `validation`
(+ comment TC to `subs-info` `subs-change` `info-change`). `TC-UPM-004` is fileinfo
When receiving, confirm that the FTP file is received (refer to the “fileinfo (0x0c)” section above).

### trap

Most of the passive reception TCs are commented out. Actual events (subscription, cancellation, number change) on the PG side
This is because it needs to happen for it to work. Since all keywords (`Receive Subs Info Request`, etc.) are implemented,
Once PG event triggering is enabled, all you have to do is uncomment it.
