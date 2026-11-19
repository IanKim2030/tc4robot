# NAG Test Instructions

Read the [shared test guide](../AGENTS.md), [TC conventions](../TC_CONVENTION.md)
before editing. The node specification is included below.

Complete the LRS-PCF listener and Hello before opening NAG. TC-NAG-001 performs the NAG Hello. Subs-Cellid requires servicing the auxiliary channel.

- Suite: `nag_tests.robot`; keywords and variables are under `resources/`.
- Use the specification's implementation links and shared references for the affected behavior.
- Structural check from the repository root: `python -m robot -V config/env/dev.py --dryrun --outputdir /tmp/tc4robot-nag-dryrun tests/nag/`.
- Runtime or live integration checks are additional evidence; do not treat a dry run as proof of business correctness.

---

## Node Specification

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

Seven tests. Tags: `nag`, `hello`, `ping`, `zion`, `subs-zone`, `subs-cellid`,
`adot`, `smoke`, `negative`, `validation`.
Use `${NAG_MDN_NO_HFC}` and `${NAG_MDN_NO_SESSION}` for their corresponding negative inputs.

### Pitfalls

- The suite should stop if either socket closes. Currently `Check NAG Socket`
  checks only `${NAG_SOCK}` and does not detect LRS-PCF channel closure.
- `Tcp.Is Connected` checks only the local file descriptor and can pass after PG disconnects.
