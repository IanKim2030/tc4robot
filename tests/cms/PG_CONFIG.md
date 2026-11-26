# PG configuration for the CMS suite

The suite never edits the PG configuration. When Suite Setup stops on a PG setting, change
`PG_V2.cfg` (`${PG_CFG_PATH}`, dev `/PG/CFG/PG_V2.cfg` on `${PG_HOST}`) as listed here, restart
`CMS201`, and run the suite again. Record every change in the [change log](#change-log).

Keep all PG cfg changes the CMS suite needs in this file. [SPEC.md](SPEC.md) links here
instead of repeating them.

## How to change

1. Edit the key in `PG_V2.cfg`. A key repeated in a section uses its **last** value, as PG does,
   so change the last occurrence (or remove the earlier ones). The suite's cfg reader logs a
   warning for each repeated key.
2. Restart `CMS201`. PG reads the cfg only at startup.
3. Run the suite. Suite Setup reads the keys over SSH through
   [config/remote_settings.json](../../config/remote_settings.json) (entries with `"targets": ["cms"]`)
   and prints each value with its source. A missing key with a `"pg_default"` is shown as
   `없음 → PG 기본값`.
4. Add a row to the [change log](#change-log).

## Keys that must match the tool

Suite Setup collects every mismatch and fails once, before any NTI is sent.

| Key | Required value | Checked by | Suite Setup message starts with |
|---|---|---|---|
| `[CMS] CMSWEB_ADDR` | `${TOOL_HOST}` (dev `192.168.15.142`) | `Check CMS Prerequisites` | `PG_V2.cfg [CMS] 설정이 CMSWEB 시뮬레이터와 맞지 않습니다 — CMSWEB_ADDR=…` |
| `[CMS] CMS_SFTP_PORT` | ≥ 1024 in SFTP mode; 22 is the tool host's real sshd. dev `2322` (not `2222`, the UPM receiver) | `Check CMS Prerequisites` | same, `CMS_SFTP_PORT=…` |
| `[CMS] NWDAF_SFTP_PORT` | ≥ 1024 when the SC receiver is local and SFTP | `Start CMS Upload Server` | `업로드(SC 수신) 서버 전제가 맞지 않습니다 — …` |
| `[CMS] NWDAF_SFTP_PORT` / `NWDAF_FTP_PORT` | Different from the CMSWEB download port | `Start CMS Upload Server` | same |
| `[CMS] NWDAF_FTP_PORT` | Not 21 in FTP mode when the CMSWEB FTP server is moved off 21 by a redirect | `Start CMS Upload Server` | same |
| Any port key | A valid number. PG falls back to its default for `0` or `22abc`; the suite stops instead | Settings report | — |

## Keys that choose a mode

Change these only to test another mode. The suite follows whatever the cfg says.

| Key | Effect | Notes |
|---|---|---|
| `[CMS] CMSWEB_SFTP` | First character `N` → FTP download on 21, `.FIN` in the same FTP session. Anything else (or missing) → SFTP | FTP needs port 21 on the tool host — see [FTP or SFTP](SPEC.md#ftp-or-sftp--chosen-from-the-pg-cfg-at-startup) |
| `[CMS] NWDAF_SFTP` | First character `N` → SC upload by FTP (`NWDAF_FTP_PORT`). Anything else → SFTP (`NWDAF_SFTP_PORT`) | Used only for `SC_FTP_YN=Y` codes (TC-005/009) |
| `[SC] SC_PRIIP` | Empty or `${TOOL_HOST}` → the tool runs the SC receiver. Other IP → the suite logs in to that server read-only (`PG_PWD_CMS_SFTP_UPLOAD`) | [SC forwarding](SPEC.md#sc-nwdaf-forwarding-runsftpsc) |
| `[CMS] SC_PATH` | Directory PG uploads to on the SC | Local mode mounts it onto `${CMS_SC_UPLOAD_DIR}` |
| `[CMS] CMSWEB_PORT` | Port the tool listens on (`${CMS_LISTEN_PORT}`) | — |
| `[CMS] GROUP` / `KEY` | Expected REG `sourceSessionKey` (TC-001) | — |
| `[CMS] CMSWEB_TIMEOUT` | PG closes after this many seconds without a message | Keep it longer than `${CMS_QUIET_WINDOW}` waits, or TC-015 fails |

## Current dev values

PG 141, read 2026-11-24 (last value wins). Re-read before relying on them; the settings report
of a run shows the live values.

| Key | Value |
|---|---|
| `[CMS] CMSWEB_ADDR` | `192.168.15.142` |
| `[CMS] CMSWEB_PORT` | `9980` |
| `[CMS] CMS_SFTP_PORT` | `2322` |
| `[CMS] CMSWEB_TIMEOUT` | `900` |
| `[SC] SC_PRIIP` | `192.168.15.142` |
| `[CMS] NWDAF_SFTP` | `Y` (an earlier line has `N`) |
| `[CMS] NWDAF_SFTP_PORT` | `32001` |
| `[CMS] NWDAF_FTP_PORT` | `32001` |
| `[CMS] SC_PATH` | `/PG/FTP/CMS` |

## Change log

Add a row for every change made to the PG cfg for this suite.

| Date | Host | Key | Old → new | Reason |
|---|---|---|---|---|
| 2026-11-24 | 141 | `[CMS]` / `[SC]` keys above | — → baseline as read | First read when the suite was set up; already pointing at 142. Earlier values not recorded |
