# Applied Structure and Validation

This document records the current local work on branch `dev-many-variable`.
It describes implemented changes, not deployed or merged changes.

## Documentation and Instruction Structure

- Root `AGENTS.md` contains shared policy, a compact layout, and task reading paths.
- Scoped `AGENTS.md` files cover the project folders, all six test-group folders,
  configuration subfolders, documentation subfolders, repository skills, and editor settings.
  Generated cache directories are excluded.
- `CLAUDE.md` and `CLAUDE.md.english` point to the root instructions.
- Project documentation and repository skills are in English. Actual Robot test names,
  documentation fields, logs, and failure messages retain the existing Korean convention.
- `tests/TC_CONVENTION.md` owns shared TC policy. The TC authoring skill describes
  the working sequence and links to that policy rather than duplicating it.
- Each node specification has a TC authoring entry point linking its suite, keywords,
  variables, Python libraries, shared references, and validation guidance.
- `docs/callflow/` remains developer-only reference. PCF TC ordering and known assertion
  gaps are documented in its node specification independently of the call-flow document.

## Python Library Migration

Eleven modules moved from `resources/` to `libraries/`:

| Group | Modules |
|---|---|
| Protocol and data | `TcpHelper.py`, `CdsHelper.py`, `TlvHelper.py`, `HttpHelper.py`, `RtsHelper.py`, `PdbHelper.py` |
| Receivers | `HttpNotiServer.py`, `FtpServerHelper.py`, `SftpServerHelper.py` |
| Infrastructure | `DbSeedHelper.py`, `SshHelper.py` |

Robot keywords and variables remain in `resources/`. Resource files import Python
libraries with `${CURDIR}/../libraries/<Module>.py`; setup uses `../libraries/`.
Existing Robot aliases and Python function signatures are preserved. The standalone
module style is retained; this migration does not introduce a new package API.

Documentation links, Python examples, requirement comments, and the CDS call-flow
generator use the new paths. FTP still loads the sibling SFTP module relative to
`__file__`. Optional service dependencies retain their lazy imports.

## Documentation Corrections

- The interface matrix now reflects environment-file ownership of `PG_HOST`, without a shared dev fallback.
- NAG setup is documented as LRS accept/Hello first, NAG connection last, matching the current suite.
- Shared lifecycle policy preserves the documented isolated-connection NWDAF negative tests.
- PCF's node specification records ordered Zone-InOut/ZION pairing and the current MDN/TA-code assertion limits.
- The CDS call-flow generator produces English output and imports `libraries/CdsHelper.py`.

## Verification Evidence — Library Migration

| Check | Result and scope |
|---|---|
| Baseline dev dry run before moving libraries | 94 TCs passed |
| Dev dry run after moving libraries | The same 94 TCs passed |
| Stg dry run after moving libraries | 94 TCs passed |
| Setup dry run | `setup/db_seed.robot`: 1 TC passed |
| Python imports | All 11 relocated modules imported; sibling SFTP module loading succeeded |
| Local behavior comparison | Before/after digests matched for representative TCP, CDS, RTS, and NWDAF packet construction, a local socket-pair JSON exchange, and seed parsing |
| Seed parser fixtures | dev SQL: 18 blocks; stg SQL: 0 active blocks; no SQL executed |
| Documentation | 55 English Markdown documents; 376 local links and their section targets checked; fenced code blocks balanced |
| Python migration integrity | All 11 modules pass syntax checks; implementation ASTs match the pre-move snapshot after excluding docstrings |
| Generated documentation | English CDS output is reproducible for all 11 business codes |
| Diff hygiene | `git diff --check` passed; no stale `resources/<PythonModule>.py` paths remain |

The structural checks above use direct Robot commands, so the runner's live DB
seed phase is not invoked. Example reproducible checks from the repository root:

```bash
python -m robot -V config/env/dev.py --dryrun --outputdir /tmp/tc4robot-dev-check tests/
python -m robot -V config/env/stg.py --dryrun --outputdir /tmp/tc4robot-stg-check tests/
python -m robot -V config/env/dev.py --dryrun --outputdir /tmp/tc4robot-seed-check setup/db_seed.robot
python docs/callflow/gen_callflow.py
```

## Root Policy Reorganization

The root `AGENTS.md` now follows Project Overview, Commands, Architecture & Coding
Rules, Boundaries, and Task Completion Checklist. Task reading paths and folder
implementation details live in the workflow and scoped guides.

The requested lowercase library examples are adapted to the existing `libraries/`
layout, and direct Robot commands include the required environment file. Missing
lint/format tooling, library tests, and regression tags are stated explicitly.
Fixed waits and order-dependent legacy suites are recorded as gaps against the new
policy; this documentation update does not change their runtime behavior.

`results/` is explicitly Git-ignored. `config/env/AGENTS.md` is explicitly allowed
through the environment-directory ignore rules so its local instructions can be tracked.

### Files Changed in the Root Policy Update

- `AGENTS.md`: requested overview, commands, coding rules, boundaries, and completion checklist.
- `.gitignore`: ignore `results/` and allow `config/env/AGENTS.md` to be tracked.
- `resources/AGENTS.md`: variable impact analysis and bounded polling guidance.
- `libraries/AGENTS.md`: keyword contracts, compatible annotations, errors, and test-tool availability.
- `tests/AGENTS.md`: independence policy, legacy gaps, and existing Korean test language.
- `tests/nag/AGENTS.md` and `tests/cds/AGENTS.md`: classify existing order dependencies as legacy gaps.
- `docs/AGENTS.md` and `docs/agent/AGENTS.md`: documentation ownership and policy/reporting responsibilities.
- `docs/agent/workflow.md`: task reading paths and current command/tool limitations.
- `tests/TC_CONVENTION.md`: waiting and independence guidance aligned with the root.
- `docs/agent/current-state.md`: this change record and verification evidence.

### Verification of the Root Policy Update

- Mandatory command: `robot --dryrun -V config/env/dev.py -d results tests/`; 94 TCs passed.
- 375 local documentation links and section targets validated; `git diff --check` passed.
- Confirmed that `results/output.xml` is ignored, no result artifacts are tracked, and the environment guide is trackable.
- Robocop, Robotidy, pytest, and Ruff are unavailable in the current execution environment; their checks were not run and no dependencies were installed.
- No shared keyword or variable implementation changed in this policy update; the mandatory structural check covered all seven suites.

## Lowercase Library Directory

The Python library directory is now consistently named `libraries/`. Robot imports,
setup imports, generator imports, examples, node implementation links, and folder
instructions use the lowercase path. Public APIs and protocol behavior are unchanged.

Validation for this rename: all seven suites passed the mandatory dry run (94 TCs),
the setup dry run passed (1 TC), and the local library behavior probe matched the
pre-migration baseline. All 11 Python modules imported, sibling SFTP loading worked,
375 local Markdown links resolved, no uppercase library path references remained,
and `git diff --check` passed.

## Node Specifications Consolidated into Suite Guides

Each of the seven `tests/<node>/AGENTS.md` files now includes the complete node
specification alongside its existing scoped instructions. The previous separate
node-document directory has been removed to avoid maintaining duplicate copies.
The node documentation maintenance rules now live in `tests/AGENTS.md`.

Relative links inside the moved specifications, incoming file and section links,
Python/Robot comment references, skill reading paths, and the CDS generator's
references point to the suite guides. Existing protocol tables, TC dependencies,
assertion limits, and examples are retained. Validation confirmed preservation of all original fenced code examples, protocol table rows, and section titles. The mandatory dry run passed all 94 TCs, 368 local links and section targets resolved, the CDS generator remained reproducible, and `git diff --check` passed. No suite keyword or variable behavior changed. Call-flow documents remain developer-only
reference material and now link to these guides for node requirements.

## Common Documentation Consolidation

Shared TC conventions now live in `tests/TC_CONVENTION.md`. The resource catalog
is included directly in `resources/AGENTS.md` alongside its scoped instructions;
there is no separate catalog copy under the documentation directory. Incoming file
and section links, local relative links, skill references, and documentation indexes
point to these owning files. Protocol and helper tables and examples are retained.

The catalog also explicitly preserves the documented NWDAF isolated-test exception
and correctly states that a CDS PDB setup failure prevents the suite from starting.
No Robot keyword, variable, or Python runtime implementation changed in this step. The mandatory dry run passed all 94 TCs, 366 local links and section targets resolved, original code examples and non-link table rows were preserved, and `git diff --check` passed.

## CDS Guide and Reference Split

CDS now separates always-applicable working instructions (`tests/cds/AGENTS.md`)
from the detailed technical reference (`tests/cds/SPEC.md`). The guide links to
specific sections by task; the reference retains the previous protocol tables,
DB schemas, acceptance criteria, dependency descriptions, samples, and history.
This was initially applied to CDS; the same split is now applied to all seven nodes.

The CDS guide was reduced from 1,132 to 54 lines. The detailed reference was
preserved verbatim. Validation: all 94 TCs passed the mandatory dry run, 385
local file/section links resolved, generated CDS documentation was reproducible,
and `git diff --check` passed.

Specification references and the CDS generator point to `SPEC.md`; suite and
documentation index navigation still starts at the CDS guide. No executable
keyword, variable, or protocol behavior is changed by this documentation split.

## Guide and Reference Split for All Nodes

LRS, NAG, NWDAF, PCF, RTS, and UPM now follow the CDS structure: compact
`AGENTS.md` working instructions and task-specific links, with the complete
technical reference in a sibling `SPEC.md`. Existing protocol tables, examples,
acceptance criteria, dependencies, limitations, and historical evidence are retained.
Incoming detail links and implementation comment references point to the specifications;
documentation and suite indexes continue to start at the agent guides.
No executable keyword, variable, or protocol behavior changed in this step. The six guides are now 44–46 lines each. Validation confirmed that all detailed reference text was preserved apart from updated link destinations, all 94 TCs passed the mandatory dry run, 456 local links and section targets resolved, and `git diff --check` passed.

## NAG and PCF Test-Group Consolidation

PCF-role tests now live in `tests/nag/nag_tests.robot`, alongside the seven NAG-role
cases. The NAG group owns 17 cases and one guide/specification pair. PCF reference
material and its NAG registration, environment, socket, and ordered ZION prerequisites
are included in the NAG specification. There is no separate PCF test directory.

The two child suites retain separate setup/teardown because their required channels
differ. `nag` runs both, `pcf` remains a compatibility selector for the PCF-role file,
and PCF-role cases retain `pcf` tags while also inheriting `nag`. Existing 17 test
IDs, assertions, and lifecycle keyword bodies are preserved.

Validation: all 94 TCs passed the full dry run, with 17 cases under the NAG group
and `nag` tag. Local fake-PG execution passed all 10 PCF-role cases (four Zone-InOut
requests and four ZION acknowledgments). A rejected NAG Hello prevented any PCF
connection. Runner routing was checked with a local command spy, shell syntax
passed, 448 local file/section links resolved, and `git diff --check` passed.
No live PG, DB, or SSH service was contacted for these checks.

## Single-File NAG Suite

`tests/nag/nag_tests.robot` now contains all 17 NAG and PCF integration cases.
The separate PCF-role file has been removed. `resources/nag_suite_keywords.robot`
initializes the selected path lazily, checks shared sockets, closes the NAG/LRS
connections on the one-way transition, and registers NAG again before PCF Hello.
PCF-only selection does not start the LRS listener. Suite teardown closes all handles
and initialization failures abort the remaining suite.

The `pcf` runner alias uses `--exclude NOTpcf` against the unified file, so user
include/test filters still restrict the PCF subset rather than expanding it.
Validation of the single-file implementation: all 94 TCs passed the full dry run; all 17 NAG cases passed against local fake PG/LRS peers, including connection teardown and re-registration on transition. PCF-only execution passed 10 runtime cases without an LRS listener, and rejected NAG Hello prevented PCF connection. Runner selectors produced 17 NAG cases, 10 PCF cases, and 2 PCF cases when combined with the validation tag. All 448 local file/section links resolved and `git diff --check` passed. No live PG/DB/SSH integration was executed.

Original TC bodies and assertions are retained. Existing settle waits are relocated
from the two previous setups, not added to ordinary cases. Cross-path randomization
and standalone ZION receivers remain unsupported due to documented ordering constraints.

## Dev LRS-to-PCF Prerequisite Endpoint

Dev now sets `LRS_SERVER_HOST = TOOL_HOST` (`192.168.15.142`) and
`LRS_SERVER_PORT = 8890`. PG LRS connects inbound to that tool-side PCF listener.
The NAG request path waits for accept and a valid Hello before opening NAG,
and checks both NAG and LRS handles before each request TC. A prerequisite failure
aborts the path rather than sending NAG requests. PCF-only selection retains its
separate initialization path. The shared default remains 8890 for environments
without an override; the LRS dev suite shares the configured 8890 endpoint.

Historical validation before the port correction: the dev whole-suite dry run passed 94 cases. Local fake PG/LRS peers
passed all 17 NAG cases using loopback port 8889. An invalid LRS Hello caused
prerequisite failure without attempting a NAG connection. These are local checks,
not confirmation that the private host 142 is reachable from this environment.

Port correction validation: after correcting the dev endpoint to port 8890, the
mandatory dev whole-suite dry run passed all 94 cases. This affects the NAG
request path and LRS side channel. No live PG connectivity was verified.

## Remaining Limits

Dry runs do not execute Python keyword bodies. Local migration checks establish
representative behavior preservation, not complete protocol coverage. No live PG,
ODBC/DB mutation, remote SSH command, or real FTP/SFTP/SBI service integration was
performed for this migration. The generated call-flow documents remain developer
references and can contain historical observations; TC requirements belong in node specifications.

Existing uncommitted work was preserved. No commit, push, merge, or deployment is
implied by this summary.

## Shared Pre-seed Configuration Resolution

The runner now resolves CLI > explicit environment > supported remote settings >
node defaults before DB seed. Seed and regression consume the same private
snapshot. Remote mapping currently covers NAG/PCF destination ports only. Direct
Robot CLI runs use the same port priority without automatically executing seed.
Offline checks cover precedence, disabled lookup, invalid ports, remote failures,
and snapshot permissions. No live PG SSH or DB mutation was performed.

Validation for this change: 9 offline configuration tests passed, including shared
seed/test snapshot and explicit CLI override checks. The direct Robot CLI port
check passed; the runner dry run passed 1 seed case and 17 NAG cases. The required
whole-suite dev dry run passed all 94 cases. Bash syntax and diff checks passed.

## Remote Configuration Catalog at Startup

All runner targets now read enabled mappings from `config/remote_settings.json`
before DB seed. Confirmed mappings cover NAG/PCF and CDS O/R ports. The catalog
supports additional verified variables, paths, sections, keys, hosts, and types;
unknown UPM/NWDAF/RTS/LRS/DB mappings are pending server configuration evidence.
`--no-remote-config` disables all reads, and dry runs remain offline. A direct SSH
attempt to the configured PG host failed with connection refused; no live server
configuration was obtained or applied during this development check.

Catalog extension validation: 12 offline configuration checks passed, including
all runner targets and custom typed mappings. Whole-suite direct and runner dry
runs each passed 94 cases; the runner also dry-ran its seed case successfully.
