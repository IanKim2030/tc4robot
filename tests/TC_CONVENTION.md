# TC_CONVENTION — Test Case Authoring Rules

## Naming

```text
TC-<IFACE>-NNN <Korean description>
```

- `<IFACE>` is `NAG`, `PCF`, `LRS`, `UPM`, `CDS`, `NWDAF`, or `RTS`.
- `NNN` is a three-digit, zero-padded number.
- Preserve Korean test names, Robot `Documentation`, and log messages.

**File order follows number order.** Use a continuous sequence beginning at 001,
without missing or duplicate numbers. When inserting a test, shift later numbers
and update the test numbering block at the top of the suite.
The unified NAG group owns TC-NAG-001–017: the PCF section uses 008–017 in the same file. Preserve those IDs when changing the group.

Overlapping ranges make sequential replacement unsafe: `005→007` collides with an
existing `007`. Renumber in one pass in file order, or replace in descending order.
Do not introduce hundreds-based feature ranges such as `1NN` or `9NN`.
Use section separators (`# ═══`) and the suite's numbering summary to group features.

## Suite File Structure

```robot
*** Settings ***
Documentation
...    <One-line summary; preserve Korean in actual suites>
...    <Target / suite policy / message flow / test numbering summary>

Resource    ../../resources/variables.robot
Resource    ../../resources/<iface>_variables.robot
Resource    ../../resources/common_keywords.robot
Resource    ../../resources/<iface>_keywords.robot

Suite Setup      Suite <IFACE> Connect
Suite Teardown   Suite <IFACE> Disconnect
Test Setup       Check <IFACE> Socket

*** Test Cases ***
```

The numbering block summarizes the test groups. Update it whenever numbers change;
stale numbering summaries are a frequent source of documentation drift.

## Test Case Template

```robot
# ════════════════════════════════════════════════════════════════
# <Group title> (Specification X.Y)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-006 PGW STATUS Normal (0)
    [Documentation]    STATUS='0' (Normal)
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_status
    Send Subscriber QoS Notification PGW    status=${NWDAF_STATUS_NORMAL}
```

- Use `<iface>_variables.robot` constants instead of literal values in TC bodies.
- Group related cases with section separators (`# ═══`).
- Extract repeated send/receive sequences into `<iface>_keywords.robot`.

## Tags

Select tests using `--include`. The following tags reflect existing suite usage.

Common tags: `smoke`, `negative`, `validation`, `lte`, `5g`.

`slow` identifies tests that wait for PG polling rather than immediate message
application. `TC-CDS-020` waits for coupon expiration processing by PG.RDS, which
can take several minutes. Use `--exclude slow` for faster runs.

Node tags: `nag`, `pcf`, `lrs`, `upm`, `cds`, `nwdaf`, `rts`.

| Node | Feature tags |
|---|---|
| NAG | `hello`, `ping`, `zion`, `subs-zone`, `subs-cellid`, `adot` |
| PCF | `hello`, `ping`, `zion`, `zone-inout` (also `nag`) |
| LRS | `health-check`, `session-info` |
| UPM | `hello`, `ping`, `cellinfo-noti`, `subs-sync`, `subs-info`*, `subs-change`*, `info-change`* |
| CDS | `connect`, `process-state`, `command`, `db`, `subs-data`*, `upload`*, `release` |
| NWDAF | `nwdaf_smoke`, `nwdaf_pgw`, `nwdaf_enb`, `nwdaf_dpi`, `nwdaf_5g`, `nwdaf_status`, `nwdaf_quick`, `nwdaf_qos_policy`, `nwdaf_support`, `nwdaf_arpqci`, `nwdaf_band`, `nwdaf_cu`, `nwdaf_network`, `nwdaf_ratio`, `nwdaf_usage`, `nwdaf_common1`, `nwdaf_common2`, `nwdaf_msgid_wrap`, `nwdaf_healthcheck` |
| RTS | `order`, `roaming`, `db`, `noti` |

`*` marks tags on commented-out TCs; they become active when those tests are enabled.
Some historical tags may no longer be used; check the current suite before selecting tests.

Only NWDAF uses the `nwdaf_` prefix for feature tags. Follow each suite's existing
convention rather than normalizing all suites.

## Disabling Tests

Comment out tests with `#` rather than deleting them, and always state the reason.

```robot
#TC-NWDAF-042 COMMON2 NETWORK 2G (0)
#    [Documentation]    NETWORK=0 (2G).
#    ...    Do not enable: the PG receiver accepts only 0x01/0x02/0x03.
#    ...    Other values produce "Unknown NetType" and return nfwError.
```

Typical reasons:

- A real PG event is required, such as subscription, cancellation, or number change.
- PG rejects a value listed in the specification.
- Required environment data is unavailable.

Mark disabled ranges in section headings, for example `TC-042 ~ 051 (currently disabled)`.
Keep the numbers reserved so uncommenting restores the sequence.

## Waiting, Independence, and Legacy Gaps

Follow the root spacing and variable-naming rules. Do not add fixed `Sleep`
calls; poll an observable state with a bounded `Wait Until Keyword Succeeds`.
Avoid retrying non-idempotent operations as part of a readiness check.

Tests must have self-contained prerequisites and teardown. Existing PCF event
pairs, CDS chains, and startup waits are legacy gaps described in node documents,
not templates for new dependent tests or waits. Converting those scenarios requires
an explicit behavior change and individual plus suite-level runtime validation;
a documentation change alone does not authorize that redesign.

## Socket Lifecycle

Open sockets once per suite and share them through Suite Variables.
Do not add per-test connect/disconnect logic. A closed socket detected in `Test Setup`
triggers `Fatal Error` and aborts the suite.
NWDAF's explicitly isolated malformed-packet tests are a documented exception; preserve
that isolation rather than applying it to ordinary tests.

## Assertion Limits

Before writing a TC, ask whether it can fail for the behavior being tested.

| Flow | What can be asserted automatically |
|---|---|
| Request/response (NAG/PCF/UPM/CDS/LRS) | Response codes, headers, and body fields |
| One-way NWDAF notification | Packet construction, successful sending, and socket state; not PG interpretation |
| Response with insufficient business meaning (CDS `CommandResult`) | Supplement with PDB queries |

CDS `CommandResult` (0017) returns `SC` regardless of body content. Verify actual
application through PDB: inserted rows (A1/1X/I2), deleted rows (1Y/I3/Z1), or
before/after aggregates (C1/G1/D3). Code-specific SQL and remaining gaps are
in the [CDS specification](cds/SPEC.md).

NWDAF notifications have no PG response. Incorrect encoding can therefore pass every
send-only TC. Seven of eight eNB fields were previously wrong while all tests passed.
Use two complementary checks:

1. **Build-only byte assertions**, without sending, to detect encoding regressions.
2. **PG log comparison**, matching the transmitted hexdump in `log.html` byte for byte.
   See the wire encoding skill for the procedure.

## Validation Procedure

```bash
python -m robot -V config/env/dev.py --dryrun tests/<iface>/
python -m robot -V config/env/dev.py --dryrun --include <tag> tests/
bash run_tests.sh <iface>                        # Live PG integration
```

Dry runs resolve Robot keywords but do not execute Python keyword bodies. They miss
runtime helper bugs and argument conversion failures, including the previous failure
when `${NONE}` was passed to a `bytes`-annotated parameter. Exercise transport changes
against a local fake PG and add byte-level assertions as appropriate.

## Steps for Adding a Test Case

1. Read the target node's message types and wire encoding in `tests/<iface>/AGENTS.md`.
2. Check or add constants in `<iface>_variables.robot`.
3. Assign the number, shift later numbers where applicable, and update the suite summary.
4. Run a direct Robot dry run with the environment file.
5. Add a build-only assertion when introducing or changing encoding.

`docs/callflow/` is developer reference material for understanding internal flows;
it is not a prerequisite for TC authoring.
