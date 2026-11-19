# NAG Specification

Read [AGENTS.md](AGENTS.md) for working rules. Read only the sections relevant to the task.

### TC Authoring Entry Point

- [TC conventions](../TC_CONVENTION.md) · [Validation workflow](../../docs/agent/workflow.md)
- Test suite: [`nag_tests.robot`](nag_tests.robot)
- Keywords: [`nag_keywords.robot`](../../resources/nag_keywords.robot)
- Variables: [`nag_variables.robot`](../../resources/nag_variables.robot)
- Python libraries: [`TcpHelper.py`](../../libraries/TcpHelper.py)
- Shared references: [SSH](../../docs/shared/SSH.md)

The LRS-PCF channel must complete accept/Hello before the NAG socket is opened. The suite owns both channels; TC-NAG-001 performs NAG Hello.

Use the sections below for message inputs, assertions, dependencies, and known limits.
Developer call-flow documents are optional background and are not prerequisites for TC authoring.

Specification: PG–NAG HFC/ADOT Service Interface, 2023-07-18.
Files: [`nag_tests.robot`](nag_tests.robot) · [`nag_keywords.robot`](../../resources/nag_keywords.robot) · [`nag_variables.robot`](../../resources/nag_variables.robot)

### Connection

| Item | Value |
|---|---|
| Tool role | NAG client |
| Direction | Tool → PG |
| Port | `${NAG_PG_PORT}` = 8012 |
| Header | Shared 8-octet header, Byte0 `0x00` |
| Body | JSON |
| Timeout | `${NAG_TIMEOUT}` = 10 seconds |

The default port is 8012 in `nag_variables.robot`; override it in `config/env/<env>.py` when required.

#### Dual Sockets: The LRS-PCF Channel Is Required

The suite uses two sockets:

```text
1. Suite LRS Accept  : listen/accept on the LRS-PCF server socket (8890) → ${LRS_CONN}
2. Handle LRS Hello  : receive Hello-Request (0x01), reply with Hello-Response (0x02)
3. Suite Connect NAG : connect the NAG client socket (8012) → ${NAG_SOCK}
```

When a Subs-Cellid TC sends `0x0b`, PG first sends `0x05` Location-Info-Request
on the LRS-PCF channel. The tool must reply with `0x06` before PG can complete
its `0x0c` response. Steps 1 and 2 must finish before the TC runs.

**Why the order is 1, 2, then 3 (2026-10-07):** opening NAG first left its socket
idle during slow PG.LRS reconnection, especially immediately after the LRS suite
in `run_tests.sh all`. PG.BNOTI then reset the connection. This did not reproduce
in standalone NAG runs. Finish the slower LRS-dependent setup first, then open
the NAG socket just before use. The developer call-flow reference describes this history in more detail.

The exchange is handled synchronously by separating send and receive:

```robot
${txn}=    Send Subs Cellid Request    ...     # Send only
Handle LRS Location Info                       # Reply to 0x05 on the other socket
${hdr}    ${body}=    Receive Subs Cellid Response
```

The NAG-Barod LRS-PCF channel uses header Byte0 `0x00`, not the standard LRS
`0x20`. The suite overrides `${LRS_TX_BYTE0}` with `${0}`.
NAG Hello runs in **TC-NAG-001**, not in Suite Setup.

### Message Types

| Opcode | Constant | Request direction |
|---|---|---|
| `0x01` / `0x02` | `${MSG_HELLO_REQ}` / `${MSG_HELLO_RESP}` | NAG → PG |
| `0x03` / `0x04` | `${MSG_PING_REQ}` / `${MSG_PING_RESP}` | NAG → PG |
| `0x07` / `0x08` | `${MSG_ZION_REQ}` / `${MSG_ZION_RESP}` | **PG → NAG**, passive reception |
| `0x09` / `0x0a` | `${MSG_SUBS_ZONE_STATUS_REQ}` / `_RESP` | NAG → PG |
| `0x0b` / `0x0c` | `${MSG_SUBS_CELLID_REQ}` / `_RESP` | NAG → PG, ADOT |

The LRS-PCF channel uses `0x01/0x02` for Hello and `0x05/0x06` for Location-Info.
Other nodes assign different meanings to `0x07`, `0x09`, and `0x0b`;
see the [interface matrix](../../docs/INTERFACES.md).

#### Response Codes

`${CODE_*}` in `nag_variables.robot`: 400 UNSUPPORT_MSG, 401 UNEXPECTED_DATA,
402 no HFC subscription or no session, 429 RETRY_AFTER, 502 PEER_NODE_DOWN,
504 GATEWAY_TIMEOUT, and 9999 HAVE_TO_FAILOVER.

Negative tests check the error code and the presence of `cause`:

```robot
Response Code Should Be    ${body}    402
Dictionary Should Contain Key    ${body}    cause
```

### Test Cases

The NAG section has seven tests; the unified single-file suite has 17 tests. Tags: `nag`, `hello`, `ping`, `zion`, `subs-zone`, `subs-cellid`,
`adot`, `smoke`, `negative`, `validation`.
Use `${NAG_MDN_NO_HFC}` and `${NAG_MDN_NO_SESSION}` for their corresponding negative inputs.

### Pitfalls

- The suite should stop if either socket closes. Currently `Check NAG Socket`
  checks only `${NAG_SOCK}` and does not detect LRS-PCF channel closure.
- `Tcp.Is Connected` checks only the local file descriptor and can pass after PG disconnects.

## Unified NAG Test Group

A single `nag_tests.robot` suite owns TC-NAG-001–017. NAG requests occupy 001–007;
PCF integration occupies 008–017. Protocol-specific resource and variable names
remain distinct because ports and opcode meanings differ.

Suite Setup initializes route state without opening connections. Test Setup starts
the first selected path once, then checks shared sockets for subsequent cases.
When the file advances from NAG to PCF, it closes the NAG/LRS sockets before
initializing the NAG/PCF path. There is one forward transition, not per-case reconnects.
PCF-only selection bypasses the LRS listener. Suite Teardown closes all handles,
including those left by partial initialization failures. Cross-path randomization
is unsupported; the existing event-pair dependencies also require file order.

`resources/nag_suite_keywords.robot` owns this orchestration. The connection
keywords described below retain their original protocol behavior but now run
on path entry from Test Setup. The existing startup-settle waits were relocated,
not expanded. Replacing that legacy timing behavior is a separate validated change.

## PCF Integration Prerequisites

1. Load the selected environment file and shared variables before NAG/PCF variables.
2. Prepare the configured PG services. The existing PCF suite ensures `CDS201` through
   the shared SSH startup keyword when SSH configuration enables that mechanism.
3. `Suite Connect With NAG` opens NAG on `${NAG_PG_HOST}:${NAG_PG_PORT}` and
   completes NAG Hello with code 200 before opening the PCF connection.
4. It then opens `${PCF_PG_HOST}:${PCF_PG_PORT}` and completes PCF Hello with code 200.
   Both handles remain suite-owned until `Close NAG Regression Connections` invokes the existing close keywords.
5. For Zone-InOut/ZION checks, PG must have the relevant subscriber session and
   matching environment/test data. Hello registers the NAG peer connection; it is
   not a substitute for provisioning subscriber/session data in the environment.
6. Existing ZION receivers consume events generated by their preceding Zone-InOut
   senders. Include those pairs when selecting tests; this is a legacy independence
   gap, not a pattern for new cases. `Check PCF And NAG Socket` aborts on closed handles.

The PCF-role path does not require the 8890 LRS-PCF listener used by the NAG-role
Subs-Cellid path. Running PCF-only must not wait for that unrelated connection.

## PCF Interface Reference

Read [NAG instructions](AGENTS.md) for working rules. Read only the sections relevant to the task.

### PCF TC Authoring Entry Point

- [TC conventions](../TC_CONVENTION.md) · [Validation workflow](../../docs/agent/workflow.md)
- Test suite: [`nag_tests.robot`](nag_tests.robot)
- Keywords: [`pcf_keywords.robot`](../../resources/pcf_keywords.robot)
- Variables: [`pcf_variables.robot`](../../resources/pcf_variables.robot)
- Python libraries: [`TcpHelper.py`](../../libraries/TcpHelper.py)
- Shared references: [SSH](../../docs/shared/SSH.md)

The NAG session must be registered before PCF connects. Run each ZION receiver together with the preceding Zone-InOut sender; existing IDs are NAG-prefixed.

Use the sections below for message inputs, assertions, dependencies, and known limits.
Developer call-flow documents are optional background and are not prerequisites for TC authoring.

Specification: PCRF–PG ZONE Notification Processing Interface, 2021-03-29.
Files: [`nag_tests.robot`](nag_tests.robot) · [`pcf_keywords.robot`](../../resources/pcf_keywords.robot) · [`pcf_variables.robot`](../../resources/pcf_variables.robot)

### PCF Connection

| Item | Value |
|---|---|
| Tool role | PCF client |
| Direction | Tool → PG |
| Port | `${PCF_PG_PORT}` = 8011 |
| Header | Shared 8-octet header, Byte0 `0x00` |
| Body | JSON |
| Timeout | `${PCF_TIMEOUT}` = 10 seconds |

#### PCF Dual Sockets: Register the NAG Session First

`Suite Connect With NAG` opens two sockets before the tests:

```text
1. Connect NAG (8012) and perform Hello to register the subscriber session.
2. Connect PCF (8011) and perform Hello → ${PCF_SOCK}.
```

PG needs the registered subscriber session before sending a ZONE notification.
Both sockets must remain open for the entire suite. `Check PCF And NAG Socket`
raises `Fatal Error` if either socket closes.

### PCF Message Types

| Opcode | Constant | Request direction |
|---|---|---|
| `0x01` / `0x02` | `${MSG_HELLO_REQ}` / `${MSG_HELLO_RESP}` | PCF → PG |
| `0x03` / `0x04` | `${MSG_PING_REQ}` / `${MSG_PING_RESP}` | PCF → PG |
| `0x05` / `0x06` | `${MSG_PCF_ZONE_REQ}` / `${MSG_PCF_ZONE_RESP}` | PCF → PG |

`0x05/0x06` mean different things on LRS and UPM. Always use `${MSG_PCF_ZONE_*}` constants.
This suite also passively receives `0x07` ZION on the NAG channel, for example
`TC-NAG-011`. NAG-prefixed IDs intentionally appear in the PCF suite.

### PCF Test Cases

Ten tests. Tags: `pcf`, `nag`, `hello`, `ping`, `zion`, `zone-inout`, `smoke`, `validation`.
The existing specification lists `${PCF_TEST_MDN}` = `01020300553` and
`${PCF_SERVICE_ID}` = `ZN100001`; check current variable definitions and environment overrides.

### PCF Pitfalls

- Test IDs do not match the suite name: PCF includes IDs such as `TC-NAG-008`
  because it also validates the NAG channel. Find the owning file before changing IDs.
- PG initiates ZION (`0x07`). Process `Receive ZION Request` followed by
  `Send ZION Response`, echoing the request transaction ID with `code=200`.

### PCF Execution Dependencies and Assertion Limits

- Zone-InOut cases generate ZION messages consumed by the next receiver case.
  For example, selecting only `TC-NAG-011` does not generate its required event;
  include its preceding `TC-NAG-010` sender or provide the corresponding external trigger.
- Unread ZION messages can remain queued and shift subsequent request/response pairing.
  The current PCF Test Setup does not implement NWDAF-style message draining.
- Existing ZION checks verify that `mdn` exists, but do not compare it with
  `${PCF_TEST_MDN}`. An unrelated subscriber's notification can therefore pass.
- The existing ZION cases do not call `TA Code Should Be Valid`. Do not describe
  their PASS result as proof of TA-code validity.
- Define and assert the expected subscriber, fields, and transaction pairing when
  adding coverage; preserve documented ordering unless explicitly redesigning it.
