# Development and Validation Workflow

## Before Editing

1. Read [AGENTS.md](../../AGENTS.md), then follow its task-specific reading table.
2. Run `git status --short` and inspect the target files and their imports.
3. Follow the existing four-layer structure. Reuse keywords and constants rather than adding protocol details to test cases.

## Task Reading Paths

| Task | Read next |
|---|---|
| Node TC authoring | `tests/<node>/AGENTS.md` (including its node specification) and [TC conventions](../../tests/TC_CONVENTION.md) |
| Robot keywords and constants | [Resource instructions and catalog](../../resources/AGENTS.md) |
| Python implementation or encoding | [Library guide](../../libraries/AGENTS.md), affected node specification, and the wire encoding skill when applicable |
| Environment values or seed configuration | [Configuration guide](../../config/AGENTS.md) and [environment rules](../ENVIRONMENTS.md) |
| Shared DB, SBI, or SSH changes | The relevant [shared guide](../shared/AGENTS.md) and topic document |
| Documentation | [Documentation guide](../AGENTS.md); keep call flows developer-only |

The root requires a Robot dry run before completion. Its command includes
`-V config/env/dev.py` because this repository has no shared environment fallback.
Use the actual case-sensitive `libraries/` path in commands and links.

### Current Validation Toolchain Limits

Robot Framework is declared in `requirements.txt`. Robocop, Robotidy, pytest,
and Ruff are not declared as a development toolchain, `libraries/tests/` does
not exist, and current suites have no `regression` tag. Do not treat a missing
target or an empty tag selection as a successful check. Report missing checks
and obtain prior confirmation before adding dependencies. The formatter command
can modify many files; keep formatting within the authorized scope.

Single-test and tag-based runs execute real setup/teardown and are not mandatory
for documentation-only changes. Do not replace the offline dry run with an
unrequested live integration run.

## Environment Setup

From the repository root:

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

PDB access also requires the appropriate system ODBC driver. Optional services depend
on the enabled features; consult `requirements.txt` and the relevant shared documentation.
Only `dev.py` and `stg.py` are tracked under `config/env/`; production and local files
must be supplied separately as described in [environment guidance](../ENVIRONMENTS.md).

## Choose Validation by Change

| Change | Validation |
|---|---|
| Documentation only | Check relative links, descriptions, and `git diff --check`; inspect untracked files separately |
| Robot scenarios, keywords, or variables | Run a direct Robot dry run for the affected suite with an explicit environment file |
| Python protocol or transport helpers | Check syntax, then exercise changed behavior with local fake peers or byte-level assertions; a dry run alone is insufficient |
| Runner | Run `bash -n run_tests.sh` and inspect argument/environment handling before any integration execution |
| DB, SSH, or notification behavior | Use the relevant shared guide and report which external checks were actually run |

Example direct dry run (replace `nag` with the affected interface):

```bash
python -m robot -V config/env/dev.py --dryrun --outputdir /tmp/tc4robot-dryrun tests/nag/
```

This checks Robot keyword resolution, not Python keyword execution or PG behavior.
Library imports and variable-file loading still occur.

## Live Integration Execution

```bash
bash run_tests.sh nag stg
bash run_tests.sh nag stg --no-db-seed
```

These commands use real configured services. The runner seeds the DB by default and
may issue SSH follow-up commands; suite setup and teardown can also change remote
state. `--no-db-seed` skips only the seed phase, not all DB or SSH activity.
Do not use the runner merely to perform a dry run: its seed phase runs first.
Read the target node and shared guides before executing the applicable integration checks.

The runner supports six test groups, `all`, `smoke`, and tag selections. The `nag` group includes PCF-role checks; `pcf` remains a compatibility selector for the PCF-tagged section of the single NAG suite.
See `run_tests.sh` for the current flags rather than maintaining another full flag list.
Reports are written to `results/<YYYYMMDD_HHMMSS>/`.

## Finish

Review the diff and new files, run `git diff --check`, and update the affected node
specification or test numbering block when applicable. Report what changed, which
checks passed, and any checks that were skipped or blocked by unavailable services.
A successful send or socket check does not prove that PG interpreted a notification correctly.
