# Robot Resource Instructions

This directory owns reusable Robot keywords and constants. Python implementations
live in [libraries](../libraries/AGENTS.md); do not add Python helpers here.

- Read [TC conventions](../tests/TC_CONVENTION.md), the affected [node specification](../tests/AGENTS.md), and the resource catalog below.
- Keep scenarios in `tests/`, reusable operations in `*_keywords.robot`, and test values in `*_variables.robot`.
- Import shared `variables.robot` before node variables that reference it. Load environment-only values through the selected variable file.
- Use `Library    ${CURDIR}/../libraries/<Module>.py` and retain existing `WITH NAME` aliases.
- Use interface-specific message constants; equal numeric opcodes can have different meanings on different channels.
- Follow the socket lifecycle and documented isolated-test exceptions in TC conventions. Do not alter lifecycle policy as part of a path-only refactor.
- Run a direct Robot dry run for each affected suite; add local runtime checks for changed behavior.

## Shared Variable Impact Analysis

Before changing a shared variable, use `rg` to find its definitions, aliases,
and references in resources, suites, environment files, setup, and documentation.
Trace resource imports to identify affected suites, validate them, and report the scope.
Keep environment-only values in `config/env/<env>.py`; do not add dev fallbacks.

## Polling and Existing Timing Behavior

Apply the root four-space and naming rules to edited Robot statements without
reformatting unrelated files. Poll observable state with bounded retries; do not
blindly retry non-idempotent send/insert operations. Existing fixed startup waits
are legacy behavior to migrate through a separately validated timing change,
not a precedent for adding new `Sleep` calls.

## Resource Catalog

Robot resources live under `resources/`; Python implementations live under `libraries/`. For keywords and variables for each node, refer to each node specification (`tests/<iface>/AGENTS.md`).

### layer structure

```
tests/<iface>/<iface>_tests.robot ← Test case
        │ Use
        ▼
resources/<iface>_keywords.robot ← Keywords for each node (transmission/reception scenario, verification)
resources/<iface>_variables.robot ← Node-specific constants / test data
        │ Use
        ▼
resources/common_keywords.robot ← Common keywords (TXN ID, response verification)
resources/ssh_keywords.robot ← Guaranteed PG process startup (.RUN touch)
resources/variables.robot ← Shared variables (Hello/Ping opcode, PDB·SBI·SSH settings). There is no environmental value
        │ USE (WITH NAME …)
        ▼
libraries/*.py ← Python helpers (table below)
```

Import order is important. Node-specific variable files include common variables of `variables.robot` (`${SBI_NOTI_PORT}`, etc.)
Environment values in the environment file (`${PG_HOST}` etc.), so`variables.robot` Always import first.
All suites follow this order.

### Python helpers

There are three personalities — 6 types of message helper  (creates and sends messages with PG),  receiving server  (sends messages with PG attached)
(received) 3 types,  infrastructure (DB seed, SSH) 2 types.

#### message helper

| module | Robot alias | in charge | main function |
|---|---|---|---|
| `TcpHelper.py` | `Tcp` | Socket + 8 octet header. Server mode is also here | `tcp_connect` `server_start` `server_accept` `build_header` `parse_header` `send_message` `receive_message` `pack_fields` `unpack_fields` `send_lrs_message` `receive_lrs_message` `send_text` `recv_text` `recv_http_response` |
| `CdsHelper.py` | `Cds` | 48 octet CDS fixed message. Socket reuses `TcpHelper` | `pack_cds_header` `parse_cds_header` `send_cds` `receive_cds` `pack_ack` `unpack_ack` `pack_command_body` `unpack_command_body` |
| `TlvHelper.py` | `Tlv` | NWDAF TLV. Self-implementation of even sockets | `build_nwdaf_header` `parse_nwdaf_header` `pack_tlv` `unpack_tlv_stream` `tlv_find` `tlv_find_all` `build_common1` `build_pcef_qos_ctrl` `build_dpi_qos_ctrl` `build_enb_qos_ctrl` `build_common2` `send_nwdaf_notification` `send_nwdaf_raw` `receive_nwdaf_message` `hex_dump` |
| `HttpHelper.py` | — | LRS Session-Info only | `build_aims_req` `parse_xml_fields` `post_session_info` |
| `PdbHelper.py` | `CdsDb` · `RtsDb` · `SeedDb` | PDB (Goldilocks/Altibase) lookup + write (session preload INSERT, cleanup DELETE on exit). ODBC. Modules with the same CDS, RTS, and seed are used under different aliases. A second DB is also supported with `${PDB_CONNSTR_2}`. Exception `PdbError` (formerly `CdsDbError` alias) | `masked_conn_str` `db_connect` `db_end_transaction` `db_close` `db_count` `db_group_counts` `db_rows` `db_execute` `session_insert_sql` `has_second_db` (also `CmsDb` for CMS) |
| `RtsHelper.py` | `Rts` | 32 octet RTS fixed message (roaming data blocking L1/L2). Socket reuses `TcpHelper` | `pack_rts_header` `parse_rts_header` `send_rts` `receive_rts` `pack_rts_order_body` `unpack_rts_order_body` `unpack_connect_ack` `unpack_order_ack` `unpack_keepalive_ack` |
| `CmsHelper.py` | `Cms` | CMSWEB simulator: 13 octet CMS header + compact EUC-KR JSON (PG parser needs no space after `:`), NTI case/file/FIN naming, CMSWEB SFTP download server via `SftpServerHelper` (password env `PG_PWD_CMS_SFTP`), SC (NWDAF) receive SFTP server with an `SC_PATH` → real directory mount (password env `PG_PWD_CMS_SFTP_UPLOAD`), FIN check on the tool host's real sshd via an SFTP client (password env `PG_PWD_CMS_FIN_SSH`) | `cms_pack` `cms_unpack` `cms_send` `cms_recv` `cms_expect` `cms_should_be_connected` `cms_wait_closed` `cms_nti` `cms_new_case` `cms_ans_should_match` `cms_zone_row_should_match` `cms_sftp_start` `cms_sftp_wait_download` `cms_sftp_wait_upload` `cms_sftp_should_stay_quiet` `cms_fin_ssh_check` `cms_fin_ssh_wait` `cms_fin_ssh_should_stay_quiet` `cms_fin_ssh_cleanup` `cms_sc_sftp_start` `cms_sc_wait_uploads` `cms_sc_cleanup` |

Only `PdbHelper` has a different character — it does not create a message, but checks whether PG is reflected in the DB. .
Connection string (not assembled, does not receive password as argument, masking) · Trap is [shared/PDB.md](../docs/shared/PDB.md).
`pyodbc` lazy imports  (if placed at the top of the module, the entire suite will not be loaded in an environment without pyodbc).

#### Receiving Server — PG comes with a tool

| module | Robot alias | in charge | main function |
|---|---|---|---|
| `HttpNotiServer.py` | `Noti` | PCF SBI Noti(h2c) Listen — CDS·RTS common. `h2` delayed import | `noti_server_start` `noti_server_stop` `noti_wait` `noti_count` `noti_list` `noti_errors` `noti_clear` `noti_wait_connection` `noti_link_report` |
| `FtpServerHelper.py` | `Ftp` | FTP receiving server (`pyftpdlib`) corresponding to UPM `0x0c` fileinfo. If `use_sftp=True`, launch the SFTP server below instead. | `ftp_server_start` `ftp_server_stop` `ftp_wait` `ftp_count` `ftp_list` `ftp_errors` `ftp_clear` |
| `SftpServerHelper.py` | (Do not import directly) | SFTP server (`paramiko`). `FtpServerHelper` (UPM upload) and `CmsHelper` (CMSWEB, PG downloads + FIN upload) load it by file path — name import was `ModuleNotFoundError` in real world | `SftpServer.start` `stop` `files` `downloads` `errors` |

LRS 8890 side channel Listen is not a separate module, but a server mode (`server_start`/`server_accept`) of `TcpHelper`.
SBI Noti details are [shared/SBI_NOTI.md](../docs/shared/SBI_NOTI.md).

#### infrastructure

| module | Robot alias | in charge | main function |
|---|---|---|---|
| `DbSeedHelper.py` | `Seed` | Seed DB settings before execution — Divide `config/db_seed/<env>.sql` into “Confirm SELECT + INSERT/UPDATE” blocks and replace `${VARIABLE}` with the Robot variable value. Connect and run `PdbHelper` | `load_seed_blocks` `describe_statement` `describe_check` |
| `SshHelper.py` | `Ssh` | `.RUN` touch is system `ssh` (password is `SSH_ASKPASS` injection), seed follow-up commands (stopMP/startMP) are `paramiko` (lazy import) | `ensure_pg_process_running` `run_remote_command` |

The seed format is [shared/PDB.md](../docs/shared/PDB.md#db-setup-seed-before-execution-configdb_seedsql), SSH is [shared/SSH.md](../docs/shared/SSH.md).

Body The core complexity of this repo is that the encoding is divided into three classes. JSON (NAG/PCF/UPM) /
Fixed length ASCII (LRS 8890 channel) / TLV binary (NWDAF) / 48B fixed message (CDS).
For detailed comparison, see [INTERFACES.md](../docs/INTERFACES.md).

### `common_keywords.robot`

| keyword | Use |
|---|---|
| `Next TXN ID` | txn_id number. Never returns 0 (specification constraint) |
| `Get KST Timestamp` / `Get Timestamp17` | Visual string for message |
| `Hello Should Succeed` | Hello response verification |
| `Get Ping Interval` | Extract ping-interval from Hello response |
| `Ping Should Succeed` | Ping response verification |
| `Response Code Should Be` | JSON Body `code` Verification |
| `Response Msg Type Should Be` | Header msg_type validation |
| `TXN ID Should Match` | Request/response txn_id matching |
| `Response Should Be Success` | code 200~299 |
| `Cell Info Should Be Valid` / `TA Code Should Be Valid` | Cell/TA field format |

### `variables.robot`

A common, single source of truth. Change the value in this file (or environment file), not in TC.

- Environment axis variables — `${PG_HOST}`, `${TOOL_HOST}`, `${PDB_CONNSTR}`, subscribers (`${SUBS_MDN_LTE}`, etc.)
  Only the name  is public and the value is only found in `config/env/<env>.py` (there is no default value in this file).
  Network data (`${NET_CELL_ID}`, etc.) has default values here. Node-specific variable files refer to this only as
  Therefore, if one change is made, it is propagated to all related nodes. The  standard is "a value shared by two or more nodes" .
  Values exclusive to one node are placed directly in the corresponding `<iface>_variables.robot` (e.g., CDS subscriber `${CDS_MDN}`).
  The rule and phrase name correspondence table is [ENVIRONMENTS.md](../docs/ENVIRONMENTS.md)
- Common Settings — PDB(`${PDB_TIMEOUT}` `${PDB_AUTOCOMMIT}` `${PDB_CONNSTR_2}`),
  SBI Noti(`${SNOTI_PCF_NOTI}` `${SBI_NOTI_PORT}` `${SBI_NOTI_HOST}`), SSH(`${PG_SSH_*}`),
  Seed(`${DB_SEED_*}`)
- `${MSG_HELLO_REQ}`(0x01) / `${MSG_HELLO_RESP}`(0x02) / `${MSG_PING_REQ}`(0x03) /
  `${MSG_PING_RESP}`(0x04) — Only the 4 here are common to the nodes

`0x05` and above have different meanings for each node and are located separately in each `<iface>_variables.robot`.
The conflict table is [INTERFACES.md](../docs/INTERFACES.md#opcode-conflict--use-the-constant-name-for-each-node-as-is).

### Socket sharing rules (absolute)

A socket is opened only once per suite and is shared by all TCs as a Suite Variable:
`${NAG_SOCK}` `${PCF_SOCK}` `${LRS_CONN}` `${LRS_SRV_SOCK}` `${UPM_SOCK}`
`${CDS_SCH_SOCK}` `${CDS_RCH_SOCK}` `${NWDAF_SOCK}` `${RTS_SOCK}`

each `Test Setup` of `Check ... Socket` When it detects this closure`Fatal Error` Stop the entire suite with .
This is because if there is no connection, subsequent TC is meaningless.

Do not add per-test connect/disconnect logic. Preserve the documented NWDAF isolated malformed-packet cases; they are not a pattern for ordinary TCs.

PDB connection (`${CDS_DB_CONN}`) of CDS is also , once per  suite — `Suite CDS Connect`
connects to the socket and `Suite CDS Disconnect` closes it. So, if the DB connection information is incorrect,
The entire suite, including message exchange TCs, cannot start if PDB setup fails (even with `--exclude db` —
Suite Setup is executed regardless of tags).

Note: `Tcp.Is Connected` only sees `fileno() != -1` — It does not detect that the other party hung up.
Only NWDAF catches FIN/RST with `Tlv.Nwdaf Peer Closed` (non-blocking `MSG_PEEK`).

### Dual managed catalog

There are intentionally the same values in both places. If you change only one side, it will be out of alignment.

| target | Location 1 (Python) | Position 2 (Robot) |
|---|---|---|
| NWDAF TLV tag | `TlvHelper.py` `TAG_*` | `nwdaf_variables.robot` `${NWDAF_TAG_*}` |

### time out

Socket timeout is set only once when connecting and is set for all subsequent times. `recv` inherits it.
Legacy receive paths use the connection timeout rather than a per-receive override. For new readiness checks, follow the root bounded-polling policy; do not introduce fixed sleeps.

`${NAG_TIMEOUT}` `${PCF_TIMEOUT}` `${UPM_TIMEOUT}` `${CDS_TIMEOUT}` `${NWDAF_TIMEOUT}`
`${RTS_TIMEOUT}` `${LRS_CLIENT_TIMEOUT}` All default 10 seconds. `${LRS_ACCEPT_TIMEOUT}` Only 30 seconds.

If you have to wait longer, upload and revert only in that section —
NWDAF Health Check (30 second standard) uses this pattern as `Tlv.Nwdaf Set Timeout` + `TRY/FINALLY`.

`libraries/RuntimeConfig.py` resolves configuration priority and loads the shared
pre-seed snapshot; see [environment priority](../docs/ENVIRONMENTS.md#variable-priority).
