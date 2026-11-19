# NWDAF Test Instructions

Read the [shared test guide](../AGENTS.md), [TC conventions](../TC_CONVENTION.md)
before editing. The node specification is included below.

Use byte-level build assertions for encoding; successful sending does not prove PG interpretation. Preserve the isolated malformed-packet cases 034–037. Update Python and Robot tag catalogs together.

- Suite: `nwdaf_tests.robot`; keywords and variables are under `resources/`.
- Use the specification's implementation links and shared references for the affected behavior.
- Structural check from the repository root: `python -m robot -V config/env/dev.py --dryrun --outputdir /tmp/tc4robot-nwdaf-dryrun tests/nwdaf/`.
- Runtime or live integration checks are additional evidence; do not treat a dry run as proof of business correctness.

---

## Node Specification

### TC Authoring Entry Point

- [TC conventions](../TC_CONVENTION.md) · [Validation workflow](../../docs/agent/workflow.md)
- Test suite: [`nwdaf_tests.robot`](nwdaf_tests.robot)
- Keywords: [`nwdaf_keywords.robot`](../../resources/nwdaf_keywords.robot)
- Variables: [`nwdaf_variables.robot`](../../resources/nwdaf_variables.robot)
- Python libraries: [`TlvHelper.py`](../../libraries/TlvHelper.py)
- Shared references: No mandatory node-specific PDB/SBI/SSH reference; consult the workflow before using runner-level seeding.

Use build-only byte assertions for encoding. Send success and a live socket do not prove correct PG interpretation. Preserve the isolated malformed-packet tests.

Use the sections below for message inputs, assertions, dependencies, and known limits.
Developer call-flow documents are optional background and are not prerequisites for TC authoring.

Specification: `PG Interface Specification V1.2 (2024-09-20)` (PG.NWMQOS — Base Station Congestion Control)
File: [`nwdaf_tests.robot`](nwdaf_tests.robot) · [`nwdaf_keywords.robot`](../../resources/nwdaf_keywords.robot) · [`nwdaf_variables.robot`](../../resources/nwdaf_variables.robot) · [`TlvHelper.py`](../../libraries/TlvHelper.py)

### connection

| item | value |
|---|---|
| tool role | NWDAF (Client) |
| direction | Tools → PG |
| port | `${NWDAF_PORT}` = 10305 |
| Body | TLV binary |
| time out | `${NWDAF_TIMEOUT}` = 10 seconds |
| socket | Single — datalength negative TC (034~037) does not open two sockets at the same time, but closes the existing socket and connects only one by one (`Send NWDAF Notification On New Connection`) |

### Message type

3 types of Message Types — `0b001` Request / `0b100` Response / `0b010` Notification (main).

According to the standard, there is only one Service Id, `0x0305` — QoS control per subscriber. `txn_id` has no concept
Message Id plays that role (`Next NWDAF Msg Id` wraps 0xFFF→0x000).

For header bit placement, see [wire encoding](#header--8-octets-but-not-a-common-header) below.

#### Health Check

The tool sends a request to PG. Timeout 30 seconds.

```
NWDAF → PG: Message Type 0x01, no body (length 0)
PG → NWDAF: Message Type 0x04, Service Id / Message Id echo, no body
```

Since the socket timeout is set only once when connecting, only that section is set to `Tlv.Nwdaf Set Timeout`.
Raise to `${NWDAF_HEALTHCHECK_TIMEOUT}` (35 seconds) and return to `TRY/FINALLY`.

In the reverse direction (when PG sends first), `Handle NWDAF Health Check` / `Drain NWDAF Pending Messages` is
Handle it defensively. The latter returns to non-blocking in `Check NWDAF Socket` (Test Setup).
Clears accumulated requests.

### ★ wire encoding

Don't trust the specifications table. "numeric" in the table doesn't tell you the wire format — the actual format is
Confirmed only with PG sources. The section-by-section field table below is for PG Transmission Simulator +
This is the result of verification with the receiving unit (`CNWQosGateway.cpp`).

#### Header — 8 octets, but not a common header

```
Byte 0 bitfield: Extension(1) | ProtoVer(2) | HeaderType(2) | MessageType(3)
Byte 1-2  Service Id   (BE)
Byte 3-5 Message Id (BE, 0x000~0xFFF cycle)
Byte 6-7  Body Length  (BE)
```

#### Body structure

```
Body = MULTI_MESSAGE(0xFF) { COMMON1 + QoSCtrl sections + COMMON2 }
```

TLV encoding is divided into Tag MSB:
- Tag `0x00~0x7F` : `[Tag(1B)][Length(1B)][Value]`
- Tag `0x80~0xFF` : `[Tag(1B)][Length(2B BE)][Value]` — 0xFF MULTI_MESSAGE is this

Service ID 0x0305 is “Multi Message Processing Capable”, so multiple subscribers  can be registered within 0xFF of .
It can contain (`build_multi_subscriber_body`).

#### PCEF_TYPE is a bitmask

`PCEF_TYPE` (0x0D) is not an exclusive enum . PG checks the bit with `if (pcef_type & 0x02)`.

| bit | value | QoSCtrl section |
|---|---|---|
| `0x01` | P-GW / SMF | pcefQoSCtrl |
| `0x02` | DPI | dpiQoSCtrl |
| `0x04` | DPI (2nd) | — |
| `0x08` | APRS | — |
| `0x10` | eNB | enodebQoSCtl |

 combination value is valid. LTE DPI case is `0x01|0x02 = 0x03`, in this case pcefQoSCtrl and
dpiQoSCtrl is included in  message along with  → `build_notification_body(..., dpi_qos_ctrl=)`.

#### TAG 0x0C is ambiguous

| section | 0x0C Meaning | count |
|---|---|---|
| pcefQoSCtrl | STATUS | 1 |
| dpiQoSCtrl | CATEGORY 6 times + STATUS 1 time | 7 |

DPI cannot be verified with `tlv_find`, which only gives the first match — use `tlv_find_all`.

#### COMMON1 (required)

| TAG | field | wire |
|---|---|---|
| 0x0D | PCEF_TYPE | 1B binary |
| 0x0E | QOS_CONTROL_TYPE | 1B binary |
| 0x08 | CREATE_DATE | String `YYYYMMDD` |
| 0x09 | CREATE_TIME | String `HHmmss` |
| 0x0F | PGW_IP_ADDRESS | string |
| 0x01 / 0x02 | MIN / MDN | string |
| 0x38 / 0x39 | RCT_3M / 1M_USAGE | 4B BE int |

*Confirm normal output of all fields in PG log `BodyInfo`. Transmitter source is unconfirmed.*

#### pcefQoSCtrl (bit 0x01)

| TAG | field | wire |
|---|---|---|
| 0x3A | QOS_HDR = `0x01` | 1B binary |
| 0x10 | QOS_POLICY | Fixed length NUL padding |
| 0x0C | STATUS | 1B ASCII `'0'`~`'3'` |
| 0x20 | TIMER | 4B BE int |
| 0x3B | QUICK_SUPPORT | 1B ASCII `'0'`/`'1'` |

*Receiver source unconfirmed — See items requiring confirmation.*

#### dpiQoSCtrl (bit 0x02)

```
QOS_HDR(0x3A)=0x02 1B binary
(CATEGORY + QOS_POLICY) × 6 CATEGORY is 1B ASCII ‘A’~’F’
STATUS(0x0C)                1B ASCII (0x30)
TIMER(0x20)                 4B BE int (htonl)
QUICK_SUPPORT(0x3B)         1B ASCII "1"
```

The number of pairs is fixed. The receiver is hardcoded as `for (i = 0; i < 6; i++)`.
If 5 pairs are sent, the 6th iteration uses STATUS·TIMER as a pair, and all subsequent iterations are pushed back.

#### enodebQoSCtl (bit 0x10)

The receiver does not check TAG and reads it in fixed order . Even if just one order or width is wrong, everything that follows is pushed back.

| TAG | field | transmitter | receiver | wire |
|---|---|---|---|---|
| 0x3A | QOS_HDR | `temp=0x10, &temp` | `cQosHdr = *p` | 1B binary |
| 0x41 | SUPPORT_TYPE | `"1"`/`"2"` | `cSupportType = *p` | 1B ASCII |
| 0x3F | ARP_QCI_FLAG | `htonl(v)` len 4 | `ntohl(...)` | 4B BE int |
| 0x3C | ENB_ARP | `htonl(v)` len 4 | `ntohl(...)` | 4B BE int |
| 0x42 | ARP_CAPABILITY | `"1"`/`"2"` | `cCapability = *p` | 1B ASCII |
| 0x43 | ARP_VULNERABILITY | `"1"`/`"2"` | `cVnlnerability = *p` | 1B ASCII |
| 0x11 | QCI | len 2, `"9"` | `memcpy(cQCI,p,len)` | 2B ASCII + NUL |
| 0x20 | TIMER | `htonl(300)` len 4 | `ntohl(...)` | 4B BE int |

The specifications table lists the eNB TIMER as `string`, but both implementations of  are `htonl`/`ntohl`.

#### COMMON2 (required)

The receiving unit is tag-based `switch` and  is free in the order  (different from eNB).

| TAG | field | wire |
|---|---|---|
| 0x1F | NETWORK | 4B BE int |
| 0x40 | CONTROL_UNIT | 1B ASCII (output `cControlUnit` as `%c`) |
| 0x0B | CELL_ID | String (receiver is `RTrim`) |
| 0x31 / 0x1A / 0x35 / 0x32 / 0x36 / 0x37 | DN_USAGE / USING_USER / CELL_AVG_USAGE / HEAVY_USER / USER_USAGE / USER_RATIO | 4B BE int |

`NETWORK = 0x00`(2G) is rejected by PG. receiver only accepts `0x01`/`0x02`/`0x03` and others
After logging `"Unknown NetType"`, discard the message as `return nfwError`. There is 2G in the standard table, but  should not be used.

### TC

Currently 37 cases (001~037 consecutive). Only NWDAF uses the `nwdaf_` prefix tag system.

| band | content |
|---|---|
| 001 | Health Check |
| 002~005 | Smoke (PGW/eNB), 5G subscribers |
| 006~013 | pcefQoSCtrl (STATUS / QUICK_SUPPORT / QOS_POLICY) |
| 014~020 | enodebQoSCtl |
| 021~030 | COMMON1 / COMMON2 |
| 031 | Message Id wrap |
| 032~033 | dpiQoSCtrl (LTE DPI QoS added / DPI only) |
| 034~037 | datalength (excessive length) negative — QOS_POLICY (PGW/DPI) / CATEGORY (DPI) / QCI (ENB), all kept below 0x80 (anything beyond that would hit a separate sign extension bug). To avoid polluting the shared socket, send it to `Send NWDAF Notification On New Connection` (close the existing socket and connect only one by one). accept/reject is not decisive and only observes and logs whether the connection is maintained (refer to the judgment gap). |

### trap

#### Decision gap — the core constraint of this node

Notification does not receive a response from PG. Therefore, what the robot can automatically determine is
The only results are message assembly result (TC in build unit), TCP transmission success, and FIN/RST detection of `Check NWDAF Socket`.

In fact, there is a precedent where all TCs passed  with 7 out of 8 fields in the eNB section incorrect.
So:
- Maintain a high proportion of build unit TC
- For each transmission `Send NWDAF Notification` leaves a full packet hexdump in `log.html` —
  Compare byte by byte with PG's `Header Info`/`BodyInfo` dump.

PG's `BodyInfo` printf only outputs COMMON1 + COMMON2. pcefQoSCtrl/eNB/DPI fields are
What is not visible in the log is not a parsing failure, but missing logging .

#### dual management

TLV tag catalogs are `TlvHelper.py` (`TAG_*`) and `nwdaf_variables.robot` (`${NWDAF_TAG_*}`)
 is on both sides. If you add the tag , you should fix both.

#### PG Source Location (Checked 2026-07-31)

```
G:\My Drive\21_Work\001_Ntels\03_PG\repo\SRC-remote-r133-ads-vertica\SRC-remote-r133-ads-vertica\
```

NWDAF receiver is `DEV/Online/SC_Package/SCMQos/`

| file | content |
|---|---|
| `SCMQos/CSCMQosGateway.cpp` | receiver main body |
| `SCMQos/SCMQosDefine.hpp` | Length macro, structure, TAG definition |

The file name `CNWQosGateway.cpp` that this document has written so far is not , but  — `CNWQosGateway` is
The class name  defined in `CSCMQosGateway.cpp` is  (`CNWQosGateway::ParsingPacket`). `SCMQos.vGL/`
There is another version of the same file, so check which one it is when comparing. `ParsingPacket()` The whole
Confirmed by user - see "Code and source mismatch" section below.

Macros with names like  have different values for each node. `SC/CommonDef.hpp` and
There are also `LEN_QOS_POLICY` and `LEN_QCI` in `LRS/LRS_SIM/CommonDef.hpp`, but the values of  are different.
NWDAF must see `SCMQosDefine.hpp`.

#### ★ Code and source are misaligned (not reflected)

The source code below has been confirmed, but it has not yet been reflected in the  code. Delete this section when fixing.

| constant | PG Source (`SCMQosDefine.hpp`) | Currently `TlvHelper.py` |
|---|---|---|
| `LEN_QOS_POLICY` | 50 (`:22`, `TAG_LEN_QOS_POLICY = 0x32`) | `16` |
| `LEN_QCI` | 3 (`:23`, `cQCI[LEN_QCI+1]`) | `2` |
| `LEN_CELL_ID` | 14 (`:15`) | `LEN_LOCATION_ID = None` (variable) |
| `LEN_CATEGORY` | 29 (confirmed by user) | No constants — only variable length supported as `pack_string` |

The `category_len`(`build_dpi_qos_ctrl`)/`qci_len`(`build_enb_qos_ctrl`) override parameters are
This is only for TC-NWDAF-034~037 (datalength overload and negative length) using the above drift — default operation
(Variable length / `LEN_QCI`) remains the same.

`16`/`2` is the value  of another node header  (`SC/CommonDef.hpp:41-42`,
`LRS/LRS_SIM/CommonDef.hpp:41-42` is exactly 16/2). It seems to have come from there.

Receiver has length upper bound checking on all three fields (QOS_POLICY/CATEGORY/QCI) —
The entire `CNWQosGateway::ParsingPacket` of `CSCMQosGateway.cpp` is provided and confirmed by the user (see below)
(see section "Length field sign extension bug"). `if (length > LEN_XXX) { memcpy(dst, p, LEN_XXX); WARNING log } else if
(length > 0) { memcpy(dst, p, length); }` With the pattern , you can safely truncate — I previously did this
The code in question and the comment `TlvHelper.py` say, "There is no defense, so a buffer overflow occurs."
It was an incorrect assumption without seeing the block. TC-NWDAF-034/035 truncate+WARNING path
It is designed to be observed accurately (keep the oversize value below 0x80 — see section below).

Source confirmed:

- DPI 6 pairs confirmed — `ST_DPI_QOS_INFO` becomes `cCategory[6][30]` · `cQosPolicy[6][51]`
  (`SCMQosDefine.hpp:67-75`). There is a separate 5-pair `ST_DPI_QOS_INFO_OLD`.
- eNB Field width confirmed — `ST_ENB_QOS_INFO`(`:97-107`)
  `cSupportType`/`cCapability`/`cVnlnerability` is `char`(1B),
  `nArpQCIFlag`/`nEnbArp`/`nValidTimer` is `int`(4B). It matches the encoding table above.
- `ParsingPacket()` Full confirmation (user-provided source) — `CSCMQosGateway.cpp` of
  Checked all `CNWQosGateway::ParsingPacket`: pcefQoSCtrl/dpiQoSCtrl/enodebQoSCtl all
  Inside `case TAG_QOS_HDR:`
  TAG Reads subfields by repeating  `p++; length=*p; p++;` in fixed order without checking (document
  The “TAG non-inspection fixed order” previously claimed was correct). DPI is `for (i=0;i<6;i++)`, 6 pairs
  It's hardcoded (correctly). QOS_POLICY/CATEGORY/QCI is `if (length > LEN_XXX)` upper limit respectively
  There is a check, so it is safely processed as a truncate+WARNING log (the claim of "no upper bound check" is wrong —
  (see section below). `ntohl` is a COMMON field, and the QOS_HDR subTIMER is also `memcpy(&tmp,p,sizeof(int))`
  With , 4 bytes  are always read (no length branching — different from RCT_3M/1M_USAGE of COMMON switch).

#### Length field sign extension bug (over 0x80) — TC-NWDAF-034 confirmed by actual measurement

`ParsingPacket()` reads the entire 1-byte length field as `short length; ... length = *p;`.
`p` is `char*` and in this build `char` is signed — that is, if `*p` is greater than or equal to 0x80(128)
After being sign extended to a negative number, it enters `length`.

Real-world example of sending QOS_POLICY length 200 (0xC8) to TC-NWDAF-034:
```
0xC8(200) → signed char → 200 - 256 = -56
if (length > LEN_QOS_POLICY) // -56 > 50 → false, WARNING log not recorded
else if (length > 0) // -56 > 0 → false, memcpy does not work either
p = p + length;                 // p is rewound 56 bytes back
multiMessageLength -= length + 2;  // Subtract the negative number and increase it by 54
```
Afterwards, the parsing was completely different and the entire message ended up being `default: Unknown TAG(00) Packet ignore!`.
It is discarded. PG does not disconnect in this case either, but quietly ignores it as `return nfwOk` (“judgment gap” is
(Applies to this case as well).

QOS_POLICY as well as all 1-byte length fields of this function have in common the defect  — which
If you declare a tag length greater than 128, the entire parser will be broken. So the datalength negative TC of
Oversize constants (`NWDAF_LEN_QOS_POLICY_OVERSIZED`/`_CATEGORY_OVERSIZED`/`_QCI_OVERSIZED`,
`resources/nwdaf_variables.robot`) all remain below 0x80 — what we want to see is
It's "is it safely truncated when the buffer is overflowed", not this sign extension bug (fixing this bug itself
There is no dedicated TC yet).

### ⚠ Confirmation required

1. Transmission simulator unconfirmed — The wire length is determined by the transmitter. QCI·QOS_POLICY
   You must check how many bytes are actually exported before you can decide whether to use 50/3 in the table above.
2. Health Check only Service ID unknown — Currently `0x0305` is used as is.
3. CATEGORY value system — The simulator uses `'A'`~`'F'`, but the meaning definition is not confirmed.
