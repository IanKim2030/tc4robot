# CMS (CMSWEB) — Specification

The tool plays **CMSWEB**, SKT's integrated configuration management system (CMS).
PG's CMS process (`CmsMain`, process name `CMS201`) is the client: it connects to
`PG_V2.cfg [CMS] CMSWEB_ADDR:CMSWEB_PORT`, receives file notifications (NTI),
fetches the files from the tool's SFTP simulator, uploads a `.FIN` marker to the
tool host's **real sshd** and records the result in `T_CMSWEB_ZONE`. For a service code with `SC_FTP_YN=Y` it then forwards the file
and a `.FIN` to the SC (NWDAF) server, which the tool also plays.

Sources: CMS interface specification v1.9 and the PG source
`Online/CMS.vGL.SFTP/CCMSWeb.cpp`, `CParseJson.cpp`, `CCMSEnv.cpp`,
`CommonOdbcDefine.hpp` (reference tree on 172.22.40.2, read 2026-11-23).

## Channels

| Channel | Direction | Port (dev, from `PG_V2.cfg [CMS]`) | Notes |
|---|---|---|---|
| Control | PG.CMS → tool (tool listens) | `CMSWEB_PORT` 9980 → `${CMS_LISTEN_PORT}` | 13B header + EUC-KR JSON |
| Files (SFTP) | PG.CMS → tool SFTP simulator | `CMS_SFTP_PORT` (absent → 22) → `${CMS_SFTP_PORT}` | `CMSWEB_SFTP` not `N`. GET data file only |
| Files (FTP) | PG.CMS → tool FTP simulator | 21, fixed in PG source (`FTP_PORT`, no cfg key) → `${CMS_FTP_PORT}` | `CMSWEB_SFTP=N`. GET + `.FIN` PUT in the same session |
| FIN (SFTP) | PG.CMS → tool host real sshd | 22 (no `.port()` in PG) → `${CMS_FIN_SSH_PORT}` | PUT empty `.FIN` as real OS user `pg` |
| SC forward | PG.CMS → tool SC receiver | SFTP: `[CMS] NWDAF_SFTP_PORT` 32001 (absent → 22) → `${CMS_SC_SFTP_PORT}`; FTP: `[CMS] NWDAF_FTP_PORT` (absent → 21) → `${CMS_SC_FTP_PORT}` | PUT data file + `.FIN` (only `SC_FTP_YN=Y`). `NWDAF_SFTP=N` selects FTP |
| Result | PG.CMS → PDB | — | `T_ZONE_LIST` lookup, `T_CMSWEB_ZONE` insert |

### Prerequisites (PG configuration — the suite never edits it)

`Check CMS Prerequisites` collects every mismatch and fails Suite Setup once:

- `CMSWEB_ADDR` must equal `${TOOL_HOST}` (dev since 2026-11-24: `192.168.15.142`).
- In SFTP mode `CMS_SFTP_PORT` must be ≥ 1024. On the tool host 22 is the real sshd. dev uses `2322`, separate from the UPM SFTP receiver on 2222.
- A key repeated in `[CMS]` uses its **last** value, as PG does. The CmsMain startup log on 2026-11-24 printed the later `CMSWEB_ADDR` and `CMS_SFTP_PORT`. The cfg reader logs a warning for each repeated key.

### FTP or SFTP — chosen from the PG cfg at startup

`Resolve CMS Settings` reads `[CMS] CMSWEB_SFTP` and `[CMS] NWDAF_SFTP` and applies PG's
rule from `CCMSEnv::ReadConfig`: a value whose first character is `N` selects FTP;
anything else, including a missing key, selects SFTP. The check is case-sensitive, so
`n` means SFTP, as in PG. The startup log prints the chosen protocol and port for both
channels.

| Setting | SFTP | FTP |
|---|---|---|
| CMSWEB download | `Cms Sftp Start` on `${CMS_SFTP_PORT}` | `Cms Ftp Start` on `${CMS_FTP_PORT}` (21) |
| FIN | Real sshd (`CMS_FIN_MODE=sshd`) | Same FTP session; `CMS_FIN_MODE` is switched to `simulator` |
| SC forward | `Cms Sc Sftp Start` on `${CMS_SC_SFTP_PORT}` | `Cms Sc Ftp Start` on `${CMS_SC_FTP_PORT}` |

Ports come from the cfg. `CMS_SFTP_PORT`, `NWDAF_SFTP_PORT`, `NWDAF_FTP_PORT`,
`CMSWEB_SFTP` and `NWDAF_SFTP` are catalog entries with `"pg_default"`. When the key is
missing, the suite uses PG's own default (22, 22, 21, `Y`, `Y`). The report marks that as
`없음 → PG 기본값`. The CMS FTP port has no cfg key: PG always uses 21.

The FTP simulator is `FtpServerHelper.FtpServer` (pyftpdlib). It runs on its own IOLoop
so the download and SC servers can run together. Accounts and password environment
variables are the same as for SFTP.

- **Port 21 needs privilege.** On 142, `kky` cannot bind below 1024
  (`ip_unprivileged_port_start=1024`, no sudo), and nothing listens on 21. If binding
  fails, Suite Setup says why. To run FTP mode, either run as root or redirect 21 to an
  unprivileged port (`iptables -t nat -A PREROUTING -p tcp --dport 21 -j REDIRECT
  --to-port 2121`) and pass `--variable CMS_FTP_PORT:2121`. With a redirect, also fix
  the passive range with `CMS_FTP_PASSIVE_PORTS` and open it.
- **ASCII mode.** PG calls `SetAscii` (TYPE A). Test files contain no line breaks, so
  ASCII conversion cannot change their size.
- **Unconfirmed:** how `NLCFTP::GetDir` lists files. Its source is not in the reference
  tree; pyftpdlib supports `NLST`, `LIST` and `MLSD` with a file argument.
- **Unconfirmed — FIN in FTP mode may never arrive.** `RunFtpCMS` only builds the FIN
  name (`makeFinFile`) and calls `FtpWork.Put(cFinFile, …)` without creating a local file;
  `RunFtpSC` creates one first (`makeCheckFile`). If `NLCFTP::Put` fails on a missing local
  file, PG logs `Put Fin File error` and carries on, and TC-004 then fails on the FIN
  wait. The fake PG always uploads an empty FIN, so it cannot show this. Check the PG log
  on the first real FTP run.
- A cfg port that is present but not a valid number (`0`, `22abc`) stops the suite,
  while PG falls back to its default (`strtol` ≤ 0). Fix the cfg value instead.
- In FTP mode `[CMS] NWDAF_FTP_PORT` must not be 21 when the CMSWEB FTP server is moved
  off 21 by a redirect. Both PG uploads would then reach the CMSWEB server. The SC test
  fails with that message.

After changing them, restart `CMS201`. The SFTP accounts must match the ones PG.CMS
uses for its `SYSTEM_TYPE` (compiled into PG, dev `SYSTEM_TYPE=IN`). dev (user-confirmed
2026-11-24): download account `pg` (CMSWEB `userId_`/`passWd_`), upload account `pg`
(SC `scUserId_`/`scPassWd_`), each with its own password.
Give user names in the environment file (`CMS_SFTP_USER`, `CMS_SC_SFTP_USER`) and the
passwords only through environment variables:

| Variable | Use |
|---|---|
| `PG_PWD_CMS_SFTP` | CMSWEB download simulator (GET, SFTP `${CMS_SFTP_PORT}` or FTP `${CMS_FTP_PORT}`). Required. |
| `PG_PWD_CMS_SFTP_UPLOAD` | SC receive server (SFTP `${CMS_SC_SFTP_PORT}` or FTP `${CMS_SC_FTP_PORT}`), started in Suite Setup. Required. |
| `PG_PWD_CMS_FIN_SSH` | Real `pg` OS account on the tool host. The suite logs in to `${CMS_FIN_SSH_HOST}:${CMS_FIN_SSH_PORT}` with it to check, wait for and delete the CMSWEB FIN. Optional: when unset, `PG_PWD_CMS_SFTP` is used, because PG PUTs the FIN with the CMSWEB download account (dev 142: the same password, checked 2026-11-24). |

Each simulator accepts only its own password.

**Unconfirmed — FIN credentials:** in `CCMSWeb.cpp`, `RunSFtpCMS` logs in with the
CMSWEB *download* credentials (`userId_`/`passWd_`) for both the GET and the FIN PUT.
The FIN PUT goes to port 22, so it succeeds only if 142's real `pg` password equals
the download password. If the two differ, every FIN PUT fails and CmsMain exits.

FIN target (`sshd` mode, Suite Setup `Check CMS FIN Target`): the suite logs in as
`${CMS_FIN_SSH_USER}` (default `${CMS_SFTP_USER}`) and checks that `${CMS_REMOTE_DIR}`
exists and is writable. It writes and deletes an empty probe file. Any failure stops
Suite Setup **before** an NTI is sent, because a failed FIN PUT makes CmsMain exit.

dev on 142 (read 2026-11-24 as `kky`): `pg:x:500:500::/PG:/bin/ksh`.
`/PG/FTP/CMS` exists as `pg:pg drwxr-xr-x` and is empty, so `pg` can write there and
`kky` can only read. `/CMS/ROBOT` (the earlier default) does not exist. The default
`${CMS_REMOTE_DIR}` is therefore `/PG/FTP/CMS`. The simulator creates the same
relative path under its virtual root.

Port, session key, timeout, address and FTP/SFTP mode are read at startup from
`PG_V2.cfg [CMS]` through [config/remote_settings.json](../../config/remote_settings.json).
Those entries carry `"targets": ["cms"]`, so other single-node runs do not read them.
The startup configuration report shows the source of each value.

## Wire format

```
Cmd(3) REG|DRG|HBC|NTI|ANS + Length(10, ASCII %010d) + Body(EUC-KR JSON, PG prefixes "\n")
```

**Send compact JSON.** `CParseJson::GetValue` is not a JSON parser. It finds the
key with `strstr` and requires `"` (string) or `["` (array) **immediately after
the colon**. `COLUMN_DATA` must additionally start with `["/`. `"key": "v"` is read
as empty and PG raises `PG_ALARM_CMSWEB_NTI_MSG_ERROR`. `CmsHelper.cms_pack` always
uses `separators=(',', ':')`.

## Message flow (CCMSWeb::Run)

| Step | Sender | Message | PG behavior |
|---|---|---|---|
| Connect | PG | `REG {"sourceSessionKey":[GROUP,KEY]}` | Sent right after connect |
| Register | tool | `REG {"result":"REG_OK"}` | If `result` exists and is not `REG_OK`, PG closes and reconnects (1 s × 10 cycle) |
| Heartbeat | tool | `HBC {"result":"HBC_OK","dateTime":…}` | PG replies `HBC {sourceSessionKey,dateTime,result:"HBC_OK"}` |
| Idle | — | — | No message for `CMSWEB_TIMEOUT` (dev 900 s) → PG closes |
| Notify | tool | `NTI` (Report, `data.COLUMN_DATA:["/dir/file.dat"]`) | PG sends `ANS` **before** validating fields |
| Ack | PG | `ANS {sourceSessionKey,messageId(echo),dateTime,data:"NTI_OK"}` | — |
| Close | PG | `DRG` | Tool answers `DRG {"result":"DRG_OK"}` |

NTI is rejected after ANS (no SFTP) when any of these are empty: `messageType`, `dateTime`, `serviceCode`,
`messageId`, `sourceSessionKey`, `COLUMN_HEAD`. It is also rejected when `COLUMN_DATA` lacks `dat`.
`messageId` is 18 chars: group(3) + `YYMMDDHHMISS` + sequence(3) (dev rows: `CMS261013131458003`).

## File handling

1. PG downloads `sftp://CMSWEB_ADDR:CMS_SFTP_PORT/<dir>/<file>` into `LOCAL_PATH/YYYYMMDD`.
   `<dir>` is the absolute directory from `COLUMN_DATA` (`${CMS_REMOTE_DIR}`).
2. If the name is `<name>_<YYYYMMDDHHMISS>_<size>.dat`, PG renames it to `<name>_<datetime>.dat` and compares sizes.
   On mismatch it retries up to 3 times (`ERR_GET_FILE`). The retries look for the renamed name, so only the first GET hits the tool.
3. On success PG PUTs an empty file to `sftp://CMSWEB_ADDR/<dir>/<fin>`: `<serviceCode>_<NTI dateTime digits>_<GROUP><KEY>_<YYYYMMDDhhmmss>.FIN`.
   The uploader sets no `.port()` (`RunSFtpCMS`, `SFTPUploader`), so libcurl uses SFTP port 22.
   That is the tool host's real sshd, and the file lands in the real `<dir>` as the real `pg` user.
   If the PUT fails, `RunSFtpCMS` returns false. `Run()` then returns false and CmsMain exits
   (`gDoErrExit`) without a `T_CMSWEB_ZONE` row. **This stops the shared PG's CMS process.**
4. `_V..` version suffixes are stripped from `serviceCode` before the zone lookup. The FIN name keeps the original code.

`${CMS_FIN_MODE}` selects where the suite observes the FIN:

| Mode | Use | Check | Cleanup |
|---|---|---|---|
| `sshd` (default) | Real PG | SFTP client to `${CMS_FIN_SSH_HOST}:${CMS_FIN_SSH_PORT}` (127.0.0.1:22) as `${CMS_FIN_SSH_USER}`, listing `${CMS_REMOTE_DIR}` | Kept by default. With `${CMS_FIN_CLEANUP}=True`, Suite Teardown deletes only `.FIN` files that match this run's prefixes; a failure is logged as WARN |
| `simulator` | PG built with the FIN port, a fake PG, or FTP mode (set automatically) | Simulator upload history | Not needed (temp dir, removed when the server stops) |

## PDB result (`setData` / `setFileStatus`)

`T_ZONE_LIST` is looked up by `SERVICE_CODE`: Goldilocks unless `PCRF_SUPPORT=Y`.
`T_CMSWEB_ZONE` always gets a row in Goldilocks, and in Altibase as well when `ALTIBASE_USE=Y`.

| Case | STATUS | REASON | FILESIZE | ZONE_CODE |
|---|---|---|---|---|
| Fetched, zone registered (`NOTI_YN=Y`) | `C` (ZONE may later set `E`) | `OK` | actual size | from `T_ZONE_LIST` |
| Size mismatch / not fetched | `W` | `Waiting State` | 0 | from `T_ZONE_LIST` |
| Not registered or `NOTI_YN=N` | `F` | `Err ZoneCode` | 0 | `NO` |
| FIN upload failed | no row, CmsMain exits | — | — | — |

`SC_FTP_YN=Y` forwards the file to the SC server and writes **no** row. See [SC forwarding](#sc-nwdaf-forwarding-runsftpsc).

The suite and the DB seed never INSERT or UPDATE `T_ZONE_LIST`; they use the rows that already exist.

Before any TC runs, Suite Setup (`Show CMS Zone List`) reads `SC_FTP_YN`, `NOTI_YN` and `ZONE_CODE` and prints them.
It reads the four SC service codes (`CMS_SERVICE_CODES_SC`: `TRAP_5G_EQP_INFO`, `TRAP_5G_EQP_INFO_V1`,
`TRAP_LTE_EQP_INFO`, `TRAP_LTE_EQP_INFO_CO`) and `CMS_SERVICE_CODE`, from DB1 and, if configured, DB2.

- The values never stop the suite. If PDB is unreachable, Suite Setup logs a warning and starts anyway.
- `CMS_ZONE_SHOW=False` skips the lookup (fake-PG runs without PDB).
- PG strips a trailing `_V...` before the lookup (`deleteVersion`), so `TRAP_5G_EQP_INFO_V1` reads the `TRAP_5G_EQP_INFO` row.
  The lookup uses the same key.
- PG reads `T_ZONE_LIST` from Altibase when `Pcrf_Support=Y`, otherwise from Goldilocks. TCs judge by the DB1 values.

The TCs use those values as follows:

- **TC-006:** a code whose `SC_FTP_YN` is not `Y` fails for that code without an NTI. The other codes still run.
- **TC-005:** needs `CMS_SERVICE_CODE` registered with `SC_FTP_YN='N'`. The expected `ZONE_CODE` is the value read at
  startup, unless `CMS_ZONE_CODE` is set. A missing row fails with a message to set `CMS_SERVICE_CODE`.
  The default `TRAP_ROBOT_ZONE_TEST` is no longer seeded.

Suite Teardown deletes `T_CMSWEB_ZONE` rows only for `CMS_SERVICE_CODE` and `TRAP_ROBOT_ZONE_UNREG`.
It never deletes rows for the four SC codes.

## SC (NWDAF) forwarding (RunSFtpSC)

Source (2026-11-24): `CCMSWeb::Run` (zone lookup → `RunSFtpSC` → `return true`), `RunSFtpSC`, `makeCheckFile`, `CCMSEnv.cpp`.

1. The forward runs only after `RunSFtpCMS` succeeds, so the CMSWEB GET and FIN PUT must work first.
   PG then looks up `T_ZONE_LIST`. If `SC_FTP_YN='Y'`, it calls `RunSFtpSC` when `[CMS] NWDAF_SFTP=Y`, and plain-FTP `RunFtpSC` (`NWDAF_FTP_PORT`) otherwise.
   It then returns **without `setData`**, so no `T_CMSWEB_ZONE` row is written. The return value of `RunSFtpSC` is ignored: an SC failure only raises `PG_ALARM_FILE_PUT_ERROR` and does not stop CmsMain.
2. PG creates an empty local `<file without the last 3 chars>FIN`. The file is the renamed `<name>_<datetime>.dat`, so the FIN is `<name>_<datetime>.FIN`.
3. PG uploads `sftp://<[SC] SC_PRIIP>:<[CMS] NWDAF_SFTP_PORT><[CMS] SC_PATH>/<file>`, then the `.FIN`, as `scUserId_`/`scPassWd_` (default port 22 if unset).

dev `PG_V2.cfg` on 141 (read 2026-11-24, last value wins):

| Key | Value |
|---|---|
| `[SC] SC_PRIIP` | `192.168.15.142` |
| `[CMS] NWDAF_SFTP` | `Y` (an earlier line has `N`) |
| `[CMS] NWDAF_SFTP_PORT` | `32001` |
| `[CMS] NWDAF_FTP_PORT` | `32001` |
| `[CMS] SC_PATH` | `/PG/FTP/CMS` |

The tool's SC receiver (`Cms Sc Sftp Start`) listens on `${CMS_SC_SFTP_PORT}`. It mounts the
virtual prefix `${CMS_SC_PATH}` onto the real directory `${CMS_SC_UPLOAD_DIR}` (dev
`/home/kky/ROBOT/cmsweb/upload`, created if missing). Uploads outside the prefix land in a temp root.
Suite Setup prepares the SC side (`Start CMS Upload Server`) together with the download server.
`[SC] SC_PRIIP` decides how:

| `[SC] SC_PRIIP` | Mode | Suite Setup | TC-006 check |
|---|---|---|---|
| Empty or `${TOOL_HOST}` | `local` | Starts the tool's SC receiver. Port checks: SFTP port ≥ 1024, and different from the download server's port | Receiver history and `${CMS_SC_UPLOAD_DIR}` |
| Any other IP | `remote` | Starts nothing. Logs in to `SC_PRIIP:<NWDAF_SFTP_PORT or NWDAF_FTP_PORT>` with PG's SC account (`CMS_SC_SFTP_USER` + `PG_PWD_CMS_SFTP_UPLOAD`) and checks that `SC_PATH` is readable. Writes nothing | Polls `SC_PATH` on that server for the data file and `.FIN` (same size checks) |

A failed check stops Suite Setup with every problem listed.

The NTI TCs are split by side:

- TC-004 checks the CMSWEB side: PG downloaded the file, and the `.FIN` exists in the CMSWEB directory.
- TC-006 checks the SC side: PG uploaded the data file and its `.FIN` to the SC.

Files are kept by default. With `${CMS_SC_CLEANUP}=True`, Suite Teardown deletes only the names this
run expected (`${CMS_SC_FILES}`), locally or on the remote SC.

## When the environment is not ready, no TC runs (FAIL)

`Prepare CMSWEB` runs every setup step inside `Start CMSWEB Session`. If any step fails, it logs
`[Suite] CMS TC 미수행 — <reason>` at ERROR level and fails Suite Setup with `CMS TC 미수행 — <reason>`.
No TC body runs; every TC is FAIL with `Parent suite setup failed: CMS TC 미수행 — <reason>`, and the
exit code is non-zero. Typical reasons:

- A setting the TCs need is empty (`Check CMS Settings Present` lists them all).
- A password is missing, or the download/upload server cannot start (port in use, no permission).
- PG.CMS does not connect to `${CMS_LISTEN_PORT}` within `${CMS_ACCEPT_TIMEOUT}` s, or sends no REG.
- A PG cfg prerequisite is wrong (`CMSWEB_ADDR`, SC server unreachable).


## Test cases

| TC | Check | Tags |
|---|---|---|
| 001 | REG `sourceSessionKey` = cfg GROUP/KEY (received in Suite Setup) | reg |
| 002 | HBC reply fields | hbc |
| 003 | NTI → ANS echoes `messageId`, `NTI_OK` | nti |
| 004 | SFTP GET + FIN name rule | sftp |
| 005 | `T_CMSWEB_ZONE` row: C/E, OK, size, renamed file, zone code | db |
| 006 | `SC_FTP_YN=Y` → data file (same size) + `.FIN` arrive in `${CMS_SC_UPLOAD_DIR}` via SC SFTP | sftp sc |
| 007 | Declared size ≠ actual → no FIN, `W`/`Waiting State` | sftp db negative |
| 008 | `serviceCode` missing → ANS only, no GET | nti negative |
| 009 | Unregistered service code → FIN, `F`/`Err ZoneCode`/`NO` | db negative |
| 010 | `REG_NOK` → PG closes and re-registers | reg negative |
| 011 | Idle `CMSWEB_TIMEOUT` → PG closes and re-registers | reg slow |

TC-006 sends one NTI for each of the four SC service codes and checks each upload; one failure does not stop the rest.
It uses the `SC_FTP_YN` values read in Suite Setup and does not query the DB itself, so it is not tagged `db`.

010 and 011 first check that the control socket is still open (`Cms Should Be Connected`,
non-blocking `MSG_PEEK`). If PG already closed it, for example because `CMSWEB_TIMEOUT`
is shorter than an earlier quiet window, the test fails instead of passing on the
already closed socket.

Every NTI case uses a unique file name and `dateTime`. Late side effects of an
earlier case therefore cannot satisfy or break a later one.

## Validation status (2026-11-24)

- `libraries/tests/test_cms_helper.py`: wire format, PG parser compatibility (ported `GetValue`), naming, socket receive, `cms_should_be_connected` (socketpair), FIN SFTP client against a local paramiko stand-in for sshd, SC receiver (`SC_PATH` mount, wait for both files, size check, name-only cleanup).
- Fake PG client that follows `CCMSWeb.cpp`, including a `RunSFtpSC` port, on 142 (Py 3.6.8, `~/venv`): `--exclude db`, `CMS_PG_TIMEOUT` 20 s. 8/8 pass in both modes:
  - `simulator`: the FIN goes to the simulator.
  - `sshd`: the FIN goes to a local stand-in sshd.
  - TC-006: the SC upload landed in `/home/kky/ROBOT/cmsweb/upload` (sshd run) or a temp dir (simulator run), and Teardown removed exactly those two files.
  - TC-006 fails alone when `CMS_SC_PG_ADDR` ≠ `TOOL_HOST`.
  - TC-010 (REG_NOK) fails as intended when the fake closes the connection before it.
- **Not tested:** the real sshd path (127.0.0.1:22 as `pg`), because the `pg` password was not available.
  Before the first real run, an operator with `PG_PWD_CMS_FIN_SSH` should run Suite Setup.
  `Check CMS FIN Target` verifies login and write access to `/PG/FTP/CMS`.
- Real PG 141: not run. Its cfg (read 2026-11-24) already points at 142: `CMSWEB_ADDR`, `CMS_SFTP_PORT=2322`, `[SC] SC_PRIIP`, `NWDAF_SFTP=Y/32001`.
  A real run waits for the passwords and an operator check of the FIN credentials (see above).
