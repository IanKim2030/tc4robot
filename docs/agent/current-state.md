# Applied Structure and Validation

This document records the current local work on branch `dev-many-variable`.
It describes implemented changes, not deployed or merged changes.

## Documentation and Instruction Structure

- Root `AGENTS.md` contains shared policy, a compact layout, and task reading paths.
- Twenty-three scoped `AGENTS.md` files cover the project folders, all seven test-node folders,
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
- `tests/pcf/AGENTS.md` and `tests/cds/AGENTS.md`: classify existing order dependencies as legacy gaps.
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

## Remaining Limits

Dry runs do not execute Python keyword bodies. Local migration checks establish
representative behavior preservation, not complete protocol coverage. No live PG,
ODBC/DB mutation, remote SSH command, or real FTP/SFTP/SBI service integration was
performed for this migration. The generated call-flow documents remain developer
references and can contain historical observations; TC requirements belong in node specifications.

Existing uncommitted work was preserved. No commit, push, merge, or deployment is
implied by this summary.
