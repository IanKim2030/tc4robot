# RTS Test Instructions

Read the [shared test guide](../AGENTS.md), [TC conventions](../TC_CONVENTION.md)
before editing. The node specification is included below.

Keep RTS separate from the CDS PG.RDS poller. Distinguish wire offset 14 from DB offset 85. L1 means WCDMA and L2 means LTE; Y/N selects block/unblock.

- Suite: `rts_tests.robot`; keywords and variables are under `resources/`.
- Use the specification's implementation links and shared references for the affected behavior.
- Structural check from the repository root: `python -m robot -V config/env/dev.py --dryrun --outputdir /tmp/tc4robot-rts-dryrun tests/rts/`.
- Runtime or live integration checks are additional evidence; do not treat a dry run as proof of business correctness.

---

## Node Specification

### TC Authoring Entry Point

- [TC conventions](../TC_CONVENTION.md) · [Validation workflow](../../docs/agent/workflow.md)
- Test suite: [`rts_tests.robot`](rts_tests.robot)
- Keywords: [`rts_keywords.robot`](../../resources/rts_keywords.robot)
- Variables: [`rts_variables.robot`](../../resources/rts_variables.robot)
- Python libraries: [`RtsHelper.py`](../../libraries/RtsHelper.py) · [`PdbHelper.py`](../../libraries/PdbHelper.py) · [`HttpNotiServer.py`](../../libraries/HttpNotiServer.py)
- Shared references: [PDB](../../docs/shared/PDB.md) · [SBI_NOTI](../../docs/shared/SBI_NOTI.md) · [SSH](../../docs/shared/SSH.md)

Separate receipt ACK, history bytes, subscriber service application, and SBI arrival. Unblock cases do not assert unconfirmed SERVICE-row deletion behavior.

Use the sections below for message inputs, assertions, dependencies, and known limits.
Developer call-flow documents are optional background and are not prerequisites for TC authoring.

Files: [`rts_tests.robot`](rts_tests.robot) · [`rts_keywords.robot`](../../resources/rts_keywords.robot) · [`rts_variables.robot`](../../resources/rts_variables.robot) · [`RtsHelper.py`](../../libraries/RtsHelper.py)

### Do Not Confuse RTS with RDS

The official PG name is **RTS**, confirmed by the `RTS/` source directory,
`CRts`/`CRtsDB`/`CRtsPacket`/`CRtsSocket` classes, and RTS log tags.
The **PG.RDS** described in [CDS](../cds/AGENTS.md) is a separate coupon reservation poller:
`RDS/` and `RDS_5G/`, K1 subscription followed by K3 expiration processing,
no socket interface, and polling of `T_5G_RESERVED_JOB`. Do not treat them as the same component.

### Connection

| Item | Value |
|---|---|
| Tool role | RTS client |
| Direction | Tool → PG server; PG accepts and waits for Connect Req |
| Port | `${RTS_PG_PORT}` = 6003, currently intentionally hardcoded from legacy `rts_sim.py`. PG itself reads `PG_V2.cfg [RTS]` through `RTS/CEnv.cpp GetRTSPort()`. Tool-side configuration-file discovery remains TODO. |
| Header | Fixed 32B, `RTS/RtsDefine.hpp` `stNePacket` |
| Body | Fixed-width fields; size depends on the message |
| Timeout | `${RTS_TIMEOUT}` = 10 seconds |
| Sockets | One |
| System IDs | `${RTS_SRC_SYS_ID}` = `SCSL00`, `${RTS_DST_SYS_ID}` = `PCRF`, confirmed in legacy `rts_sim.py`. Source ID matches `${CDS_SRC_SYS_ID}`. |

#### 32B Header Layout

```text
Message ID             (4, uint32 big-endian)
Transaction ID Date    (8, char, YYYYMMDD; no byte swap)
Transaction ID Seq     (4, uint32 big-endian)
Source System ID       (6, char, space-padded)
Destination System ID  (6, char, space-padded)
Data Size              (4, uint32 big-endian)
```

#### Suite Setup Performs the Connect Handshake

```text
Connect → send Connect Req (1) → validate Connect Ack (2), RESULT=SC
        → save PG's maximum TID (SelectMaxTid) as the sequence baseline
```

Subsequent Order TIDs increase from that baseline. A lower TID produces `E_REVERSE_TID_ERROR(3)`.

### Message Types

| msg_id | Constant | Meaning | Body size |
|---|---|---|---|
| `1` | `${MSG_RTS_CONNECT_REQ}` | Connect Req, tool → PG | 0 |
| `2` | `${MSG_RTS_CONNECT_ACK}` | Connect Ack, PG → tool | 16B: RESULT(2)+REASON(2)+tid_date(8)+tid_seq(4) |
| `5` | `${MSG_RTS_KEEPALIVE_REQ}` | Keepalive Req | 0; not sent by the tool in the current scope |
| `6` | `${MSG_RTS_KEEPALIVE_ACK}` | Keepalive Ack | 2B: REASON only, no RESULT string |
| `9` | `${MSG_RTS_RELEASE_REQ}` | Release, tool → PG | 0; PG sends no response (`RecvReleaseRequest` returns `false`) |
| `11` | `${MSG_RTS_ORDER_REQ}` | Order Req, L1/L2 | Variable; 17B in the current scope |
| `12` | `${MSG_RTS_ORDER_ACK}` | Order Ack, PG → tool | 4B: RESULT(2)+REASON(2) |

RTS IDs are independent of other nodes' opcodes. Its 32B header is separate from
the 8B/48B families and is not part of the shared opcode collision table.

### Wire Encoding: Two Offset Systems

`RTS/CDownMessage.cpp` `RecvCommandRequest` uses two different buffers.
The legacy GenRts.py wire layout and the reported DB offset 85 are both valid:
they describe different layers.

#### 1. Wire Offsets: Order Body Sent by the Tool

| Offset | Field | Size | Notes |
|---|---|---|---|
| 0 | SVC_CODE | 2B ASCII | `L1` = WCDMA; `L2` = LTE, confirmed 2026-10-27. These select networks, not enable/disable operations. |
| 2 | MDN | 12B | Right-pad with spaces; use an 11-digit MDN |
| 14 | Roaming block flag | 1B | L1/L2: `Y` or `N` |
| 15 | mVoIP block flag | 1B | L3/L4; out of scope |
| 16 | QoS Param | 1B | L5/L7/L9/LD/LJ/LL; out of scope |

#### 2. Database Offsets: The 265B ORDER_DATA Buffer

| Offset in `T_RTS_ORDER_HIST.ORDER_DATA` | Field |
|---|---|
| 85 | Roaming block flag |
| 86 | mVoIP block flag |
| 110 | QoS Param |

Only SVC_CODE(0) and MDN(2) happen to share offsets between layers.
`RtsHelper.py` separates them as `RTS_WIRE_LOC_*` and `RTS_DB_OFS_*`; never mix them.
`Verify RTS Order In PDB` uses DB offset 85.

#### RESULT and REASON

`RESULT` is `SC` only when `InsertOrder` succeeds, or `FA` on failure.

| REASON | Constant | Meaning |
|---|---|---|
| 0 | `${RTS_REASON_NO_ERROR}` | Success |
| 1 | `${RTS_REASON_NOT_EXIST}` | Not established here |
| 2 | `${RTS_REASON_INTERNAL_ERROR}` | Database insert failed |
| 3 | `${RTS_REASON_REVERSE_TID}` | TID lower than the previous value |
| 4 | `${RTS_REASON_DUP_TID}` | Duplicate TID |
| 12 | `${RTS_REASON_WRONG_SIZE}` | Suspected Data Size mismatch; first exercised by TC-RTS-005, pending live confirmation |
| 54 | `${RTS_REASON_NOT_DEFINE}` | Not established here |
| 99 | `${RTS_REASON_NO_COUNT}` | Not established here |

#### MDN Pitfall

`RTS/CDownMessage.cpp` `attachMDN` rearranges a 10-digit MDN when its eleventh
character (index 10) is a space. Use 11-digit test MDNs to avoid this branch.
`${RTS_TEST_MDN}` already has 11 digits.

### Database

| Table | Purpose |
|---|---|
| `T_RTS_ORDER_HIST` | Protocol layer: `TRANSACTION_ID` (16-character PK, `%8.8s%08d`), `MDN`, `MIN`, `ORDER_DATA` (265B), `UPDATE_TIME`, `STATUS` (always inserted as `1`) |
| `T_RTS_ORDER_TID` | Auxiliary check: `NAME` is the PG process instance name, not an MDN, so it cannot distinguish individual TCs; also stores `TID` |
| `T_5G_SUBS_SERVICE` | Business layer: MDN and SVC_ID. L1 inserts `W_DATA_ROAMING_BLOCK`; L2 inserts `L_DATA_ROAMING_BLOCK`. Poll using `${RTS_DB_WAIT}` and `${RTS_DB_WAIT_INTERVAL}` for apparently asynchronous application. |

PDB is the same database used by CDS, as confirmed by the user. Both use the shared
`${PDB_CONNSTR}` and `PdbHelper.py`, with alias `RtsDb` for RTS.
See [shared PDB guidance](../../docs/shared/PDB.md). Former duplicate RTS/CDS connection
strings and their fallback chain were removed to prevent divergent values.
If the environment connection string is empty, DB-tagged RTS tests **skip**;
unlike CDS, this does not block the entire suite.

Prechecks and cleanup were added on 2026-10-19. Initially cleanup covered only
the two SERVICE IDs, based on the assumption that RTS did not create subscribers.
Actual observations showed that L1/L2 also affect `T_5G_SUBS_PROFILE`, apparently
through an upsert. Cleanup therefore deletes SERVICE first, then PROFILE, matching
the suspected foreign-key dependency.

CDS and RTS can share subscriber `01090010001`. CDS cleanup removes all PROFILE/SERVICE
rows for its MDN, including RTS-created data; an RTS run without cleanup can also
leave data detected by the next CDS precheck.

- `RTS Precheck Existing Subscriber Rows` reports existing rows in Suite Setup; there is no mode selector.
- `Cleanup RTS Subscriber Rows` deletes the two SERVICE IDs and PROFILE in Suite Teardown when `${RTS_CLEANUP_ON_TEARDOWN}` is `${TRUE}` (default).
- `bash run_tests.sh rts --no-cleanup` disables cleanup using the flag shared with CDS.

### PCF SBI Notifications

L1/L2 trigger PCF SBI notifications, as confirmed by the user, although the RTS
receiver alone does not show the notification call. The suite reuses the CDS
mechanism described in [shared SBI guidance](../../docs/shared/SBI_NOTI.md):
`HttpNotiServer.py` listens over h2c on `${RTS_NOTI_PORT}`, inherited from
`${SBI_NOTI_PORT}` (16101). Suite connect/disconnect starts and stops the server;
`h2` is required. `Verify RTS SBI Noti Sent` checks arrival.
Unlike CDS, RTS has no business-code exception list or BSUBS/SDM routing-label layer.

`${SNOTI_PCF_NOTI}=${FALSE}`, or `bash run_tests.sh rts --no-sbi`, disables both
listening and notification assertions, allowing execution without `h2`.

### Test Cases

There are **five active cases**: WCDMA block/unblock (001/002), LTE block/unblock
(003/004), and malformed packet-size validation (005).
Tags: `rts`, `order`, `roaming`, `db`, `noti`, `negative`.

Acceptance evidence has four levels:

1. **ACK RESULT=SC and REASON=0:** proves `InsertOrder` succeeded, but not that body values are correct.
2. **Order history (001–004):** `SUBSTR(ORDER_DATA, 86, 1)` checks the requested flag at DB offset 85 and detects wire-encoding regressions.
3. **Subscriber service:** for blocking cases 001/003, at least one row for the MDN/SVC_ID proves business application. Do not require an exact total. Unblocking behavior is still unconfirmed.
4. **SBI arrival:** `Verify RTS SBI Noti Sent` checks notification delivery.

**TC-RTS-005** declares Data Size 600 (`${RTS_DATA_SIZE_OVERSIZED}`, above 512)
while sending the actual 17B body through `Send RTS Order With Wrong Data Size`
and `RtsHelper.send_rts_wrong_size`. It expects RESULT=FA and
`${RTS_REASON_WRONG_SIZE}` (12, `E_WRONG_SIZE`). This reason had previously only
been defined, not triggered. Live PG confirmation remains pending; reconcile the
expectation with observed behavior if PG closes the connection or sends no response.

### Call Flow

The [RTS call-flow document](../../docs/callflow/rts_callflow.md) is developer-only reference
for Order reception, SDM polling, database application, and SBI notification delivery.
It is not required reading for TC authoring.

### Pitfalls

- Keep wire and DB offsets separate.
- Avoid the 10-digit MDN rearrangement branch by using 11 digits.
- Keepalive Ack is 2B (REASON only), while Order Ack is 4B (RESULT and REASON); select parsers by msg_id.
- Release(9) has no PG response. Suite disconnect closes immediately without waiting for ACK.
- Cases 001–004 retry the full flow once by default because notification and DB propagation waits remain estimates. `${RTS_TC001_RETRY_COUNT}` defaults to `2x`; see `Send RTS Order And Verify Reflection`.

### Open Questions

- User confirmation establishes L1 → `W_DATA_ROAMING_BLOCK` and L2 → `L_DATA_ROAMING_BLOCK`. The codes denote networks, not ON/OFF. Whether flag `N` removes or retains SERVICE rows, and whether both N combinations actually unblock, still require live confirmation. Cases 002/004 therefore do not assert SERVICE rows.
- The polling interval and propagation delay remain unknown. `${RTS_DB_WAIT}` = 10 seconds is an estimate borrowed from CDS.
- L3–LE mVoIP/QoS branches exist but are not used. Extend `pack_rts_order_body` at offsets 15/16 if required later.
- SBI arrival is established, but MDN presence in the payload remains unconfirmed. Once verified, narrow the assertion with a body filter such as `body=${RTS_TEST_MDN}`.
