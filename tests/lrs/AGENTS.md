# LRS Test Instructions

Read the [shared test guide](../AGENTS.md), [TC conventions](../TC_CONVENTION.md)
before editing. The node specification is included below.

Distinguish the 10204 client channel (raw REQ/ANS and HTTP) from the 8890 server channel. Session-Info needs the side-channel Location-Info response.

- Suite: `lrs_tests.robot`; keywords and variables are under `resources/`.
- Use the specification's implementation links and shared references for the affected behavior.
- Structural check from the repository root: `python -m robot -V config/env/dev.py --dryrun --outputdir /tmp/tc4robot-lrs-dryrun tests/lrs/`.
- Runtime or live integration checks are additional evidence; do not treat a dry run as proof of business correctness.

---

## Node Specification

### TC Authoring Entry Point

- [TC conventions](../TC_CONVENTION.md) · [Validation workflow](../../docs/agent/workflow.md)
- Test suite: [`lrs_tests.robot`](lrs_tests.robot)
- Keywords: [`lrs_client_keywords.robot`](../../resources/lrs_client_keywords.robot) · [`lrs_keywords.robot`](../../resources/lrs_keywords.robot)
- Variables: [`lrs_variables.robot`](../../resources/lrs_variables.robot) · [`lrs_server_variables.robot`](../../resources/lrs_server_variables.robot)
- Python libraries: [`TcpHelper.py`](../../libraries/TcpHelper.py) · [`HttpHelper.py`](../../libraries/HttpHelper.py)
- Shared references: [SSH](../../docs/shared/SSH.md)

Prepare the PG-initiated 8890 connection within the accept timeout. The 10204 Session-Info request needs a 8890 Location-Info response before its HTTP response can complete.

Use the sections below for message inputs, assertions, dependencies, and known limits.
Developer call-flow documents are optional background and are not prerequisites for TC authoring.

Specifications: PG–LRS Information Query Interface, 2021021, V1.7;
PCRF/PCF–PG RAR Optimization Interface, v0.8, 2023-11-15.
Files: [`lrs_tests.robot`](lrs_tests.robot) · [`lrs_client_keywords.robot`](../../resources/lrs_client_keywords.robot) · [`lrs_keywords.robot`](../../resources/lrs_keywords.robot)

### Connection: Two Distinct Channels

The primary LRS interface operates in client mode.

| Channel | Tool role | Direction | Port | Protocol |
|---|---|---|---|---|
| Primary LRS client | Client | Tool → PG.LRS | `${LRS_CLIENT_DEFAULT_PORT}` = 10204 | Raw TCP and HTTP |
| Auxiliary LRS-PCF | Server | PG → tool | `${LRS_SERVER_PORT}` = 8890 | 8-octet header |

Port discovery from `PG_V2.cfg` `[LRS] LISTEN_PORT` is currently commented out
in the `Variables` declaration, so the default 10204 is used.

#### Port 10204: Two Protocols

1. **Health Check:** raw TCP without a header. The tool sends three bytes,
   `"REQ"`, and PG replies `"ANS"`. The default interval is 30 seconds
   (`${LRS_HC_DEFAULT_INTERVAL}`).
2. **SESSION-INFO-RETRIEVAL:** HTTP/1.1 `POST /SESSION-INFO-RETRIEVAL`, with XML
   `AIMS_REQ` and `AIMS_RES`, implemented by `HttpHelper.py`.

#### Port 8890: Required for Session-Info

While processing HTTP Session-Info, PG sends `0x05` Location-Info-Request on
8890. The tool must reply with `0x06` before PG fills LOCATION/TAC and returns
HTTP 200. Split sending and receiving to service the other socket synchronously:

```robot
${sock}=    Send Session Info Request        # Nonblocking POST
Handle LRS Location Info                     # 0x05 → 0x06 on 8890
${res}=     Receive Session Info Response    ${sock}
```

This is the same 8890 side channel used by the NAG suite.

#### Suite Flow

```text
Suite Connect LRS Client → ${LRS_CLIENT_SOCK} (10204)
Suite LRS Accept         → ${LRS_CONN} (8890, blocking accept)
Handle LRS Hello         → receive 0x01, reply with 0x02
```

`Server Accept` blocks for `${LRS_ACCEPT_TIMEOUT}` = 30 seconds.
Prepare PG to connect within that window. `${LRS_ALLOWED_PEER_IPS}` restricts accepted peers.

### Message Types on Port 8890

| Opcode | Constant | Direction |
|---|---|---|
| `0x01` / `0x02` | Hello-Request / Response | PG → tool / tool → PG |
| `0x03` / `0x04` | Ping-Request / Response | PG → tool / tool → PG |
| `0x05` / `0x06` | `${MSG_LOC_INFO_REQ}` / `${MSG_LOC_INFO_RESP}` | PG → tool / tool → PG |

PG initiates every request. Bodies are fixed-width ASCII, handled through
`pack_fields`/`unpack_fields`, rather than JSON. The standard header Byte0 is
`0x20` (ProtoVer 01'B); the NAG suite overrides it with `0x00`.

Handle intervening Pings while waiting for the expected message:

```robot
WHILE    True    limit=10
    ${hdr}    ${raw}=    Receive From LRS PG
    IF    ${hdr}[msg_type] == ${5}    BREAK
    END
    IF    ${hdr}[msg_type] == ${3}
        Send LRS Ping Response    ${hdr}[txn_id]
        CONTINUE
    END
    Fail    Expected Location-Info-Request(0x05), actual msg_type=${hdr}[msg_type]
END
```

#### HTTP Response Codes

`${LRS_SI_CODE_*}`: 404 NOT_FOUND, 403 FORBIDDEN (unregistered source IP),
500 INTERNAL, 601 RAA_ERROR, and 602 RAA_TIMEOUT.
`${LRS_SI_FROM_IP}` must be registered in PG; otherwise PG returns 403.

When Content-Length exceeds the actual body size, PG closes the connection
instead of returning 400, as verified by TC-LRS-003. The specification defines
400 (`${LRS_SI_CODE_BAD_REQ}`), but it was not observed for this case.

### Test Cases

Three active tests. Tags: `lrs`, `health-check`, `session-info`, `smoke`, `negative`, `validation`.
`TC-LRS-003` manipulates Content-Length and asserts connection closure without
requiring a separate PG state trigger. Most other negative cases
(`TC-LRS-SI-00x`) are commented out.

### Open Questions

- Several `lrs_variables.robot` values have environment-related TODO comments.
  Replace them with real environment data before expecting live integration success.
- `${LRS_MSG_TIMEOUT}` (10 seconds) is declared but not referenced.
