# PCF Test Instructions

Read the [shared test guide](../AGENTS.md), [TC conventions](../TC_CONVENTION.md)
before editing. The node specification is included below.

Preserve NAG session registration before PCF. Existing TC IDs are TC-NAG-008 through TC-NAG-017. Existing ZION reception depends on the preceding Zone-InOut case. This is a legacy independence gap; do not copy that dependency into new cases.

- Suite: `pcf_tests.robot`; keywords and variables are under `resources/`.
- Use the specification's implementation links and shared references for the affected behavior.
- Structural check from the repository root: `python -m robot -V config/env/dev.py --dryrun --outputdir /tmp/tc4robot-pcf-dryrun tests/pcf/`.
- Runtime or live integration checks are additional evidence; do not treat a dry run as proof of business correctness.

---

## Node Specification

### TC Authoring Entry Point

- [TC conventions](../TC_CONVENTION.md) · [Validation workflow](../../docs/agent/workflow.md)
- Test suite: [`pcf_tests.robot`](pcf_tests.robot)
- Keywords: [`pcf_keywords.robot`](../../resources/pcf_keywords.robot)
- Variables: [`pcf_variables.robot`](../../resources/pcf_variables.robot)
- Python libraries: [`TcpHelper.py`](../../libraries/TcpHelper.py)
- Shared references: [SSH](../../docs/shared/SSH.md)

The NAG session must be registered before PCF connects. Run each ZION receiver together with the preceding Zone-InOut sender; existing IDs are NAG-prefixed.

Use the sections below for message inputs, assertions, dependencies, and known limits.
Developer call-flow documents are optional background and are not prerequisites for TC authoring.

Specification: PCRF–PG ZONE Notification Processing Interface, 2021-03-29.
Files: [`pcf_tests.robot`](pcf_tests.robot) · [`pcf_keywords.robot`](../../resources/pcf_keywords.robot) · [`pcf_variables.robot`](../../resources/pcf_variables.robot)

### Connection

| Item | Value |
|---|---|
| Tool role | PCF client |
| Direction | Tool → PG |
| Port | `${PCF_PG_PORT}` = 8011 |
| Header | Shared 8-octet header, Byte0 `0x00` |
| Body | JSON |
| Timeout | `${PCF_TIMEOUT}` = 10 seconds |

#### Dual Sockets: Register the NAG Session First

`Suite Connect With NAG` opens two sockets before the tests:

```text
1. Connect NAG (8012) and perform Hello to register the subscriber session.
2. Connect PCF (8011) and perform Hello → ${PCF_SOCK}.
```

PG needs the registered subscriber session before sending a ZONE notification.
Both sockets must remain open for the entire suite. `Check PCF And NAG Socket`
raises `Fatal Error` if either socket closes.

### Message Types

| Opcode | Constant | Request direction |
|---|---|---|
| `0x01` / `0x02` | `${MSG_HELLO_REQ}` / `${MSG_HELLO_RESP}` | PCF → PG |
| `0x03` / `0x04` | `${MSG_PING_REQ}` / `${MSG_PING_RESP}` | PCF → PG |
| `0x05` / `0x06` | `${MSG_PCF_ZONE_REQ}` / `${MSG_PCF_ZONE_RESP}` | PCF → PG |

`0x05/0x06` mean different things on LRS and UPM. Always use `${MSG_PCF_ZONE_*}` constants.
This suite also passively receives `0x07` ZION on the NAG channel, for example
`TC-NAG-011`. NAG-prefixed IDs intentionally appear in the PCF suite.

### Test Cases

Ten tests. Tags: `pcf`, `nag`, `hello`, `ping`, `zion`, `zone-inout`, `smoke`, `validation`.
The existing specification lists `${PCF_TEST_MDN}` = `01020300553` and
`${PCF_SERVICE_ID}` = `ZN100001`; check current variable definitions and environment overrides.

### Pitfalls

- Test IDs do not match the suite name: PCF includes IDs such as `TC-NAG-008`
  because it also validates the NAG channel. Find the owning file before changing IDs.
- PG initiates ZION (`0x07`). Process `Receive ZION Request` followed by
  `Send ZION Response`, echoing the request transaction ID with `code=200`.

### Execution Dependencies and Assertion Limits

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
