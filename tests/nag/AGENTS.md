# NAG Agent Instructions

## Required Reading

Read the [shared test guide](../AGENTS.md) and [TC conventions](../TC_CONVENTION.md).
Use the task-specific references below instead of loading the full specification for every change.

## Implementation Files

- Suite: [nag_tests.robot](nag_tests.robot), TC-NAG-001–017 (NAG 001–007; PCF 008–017)
- Lifecycle: [nag_suite_keywords.robot](../../resources/nag_suite_keywords.robot)
- Keywords: [nag_keywords.robot](../../resources/nag_keywords.robot) and [pcf_keywords.robot](../../resources/pcf_keywords.robot)
- Variables: [nag_variables.robot](../../resources/nag_variables.robot) and [pcf_variables.robot](../../resources/pcf_variables.robot)
- Python: [TcpHelper.py](../../libraries/TcpHelper.py)

## Essential Rules

- Before NAG request TCs start, PG LRS must connect to the tool-side PCF listener and complete Hello. In dev this is `192.168.15.142:8889`, configured by `LRS_SERVER_HOST`/`LRS_SERVER_PORT`. Only then open NAG; TC-NAG-001 performs NAG Hello.
- Check both NAG and LRS handles before each NAG request TC. A failed prerequisite must abort execution rather than run requests without the side channel.
- Subs-Cellid requires servicing the auxiliary Location-Info channel between sending and receiving.
- Preserve the NAG-Barod Byte0 override; do not substitute the standard LRS header blindly.
- Keep the documented socket-check limits explicit; a local file descriptor alone does not prove peer liveness.

- PCF is an integration role within NAG, not a separate test group. Read [PCF prerequisites](SPEC.md#pcf-integration-prerequisites) before changing or running that path.
- PCF initialization must establish NAG Hello/session registration before PCF Hello; it cannot rely on previous NAG tests.
- Keep both socket checks, ZION sender/receiver pairing, existing IDs, and protocol-specific variable names.
- Old commented ZION placeholders in `nag_tests.robot` reuse IDs now active in the PCF section. Do not enable them unchanged or create duplicate active IDs.

## Task-Specific References

| Change | Read first |
|---|---|
| Connection setup and lifecycle | [Connection](SPEC.md#connection) |
| Message direction, constants, and response formats | [Message Types](SPEC.md#message-types) |
| PCF setup and environment prerequisites | [PCF integration prerequisites](SPEC.md#pcf-integration-prerequisites) |
| PCF ordering and assertion limits | [PCF constraints](SPEC.md#pcf-execution-dependencies-and-assertion-limits) |
| Current NAG-role TC coverage | [Test Cases](SPEC.md#test-cases) |
| Known limitations and unresolved behavior | [Pitfalls](SPEC.md#pitfalls) |

[Full specification](SPEC.md). Use its shared-document links for DB, SBI, or SSH details when applicable.
Call-flow documents remain optional developer reference, not prerequisites for TC authoring.

## Validation

From the repository root:

```bash
robot --dryrun -V config/env/dev.py -d results tests/nag/
```

Follow the root instructions for the mandatory final whole-suite dry run.
Byte-level and local-peer checks are additional evidence for encoding or transport changes.
A dry run does not execute Python keyword bodies or prove runtime or PG behavior.

`bash run_tests.sh nag` runs the single 17-case suite. `bash run_tests.sh pcf`
selects its 10 `pcf`-tagged cases. All cases also carry `nag`. Neither command is offline.

Connections are initialized lazily for the first selected path. On the single
NAG→PCF transition, close the NAG/LRS path and initialize NAG/PCF afresh. PCF-only
selection must not open the LRS listener. Keep file order; randomizing cases across
paths is unsupported. Do not add per-case reconnections. Existing Zone-InOut/ZION
pairs remain order-dependent legacy cases.
