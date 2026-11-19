# AGENTS.md

## Project Overview

A Robot Framework-based regression automation testing tool for PG (PCRF Gateway).

- `tests/`: executable `.robot` suites expressing business scenario flow.
- `resources/`: reusable Robot keywords and shared variables (`.resource`, `*_keywords.robot`, and `*_variables.robot`).
- `libraries/`: Python custom libraries for complex logic, protocols, networking, and database integration. Use this lowercase directory name consistently in imports and documentation.
- `results/`: generated `output.xml`, `log.html`, and `report.html`; excluded from Git.

Read the target folder's `AGENTS.md` before editing. Folder guides contain local
implementation details; the rules below apply across the repository.

## Commands (Always run before finishing)

Run the mandatory syntax/keyword check after changes. Run the other checks when
applicable to the task, and report unavailable tools or test targets rather than
claiming success. Commands below run from the repository root.

- **Syntax & Keyword Check (required):** `robot --dryrun -V config/env/dev.py -d results tests/`
- **Single Test Run:** `robot -V config/env/dev.py -d results -t "Test Case Name" tests/path/to_suite.robot`
- **Tag-based Regression Run:** `robot -V config/env/dev.py -d results -i regression tests/`
- **Robot Lint & Format:** `robocop check .` / `robotidy .`
- **Python Library Test & Lint:** `pytest libraries/tests/` and `ruff check libraries/`

The explicit variable file is required here. Single-test and tag runs execute real
suite setup/teardown and can access PG, DB, and SSH services; use the selected
environment and the folder's execution guidance. A dry run does not execute Python
keyword bodies or prove runtime correctness.

`regression` tags, `libraries/tests/`, and the lint/format tools are not currently
configured as a complete validation toolchain. Until configured, use existing test
tags and report the missing checks. Do not install packages or add dependencies
without prior confirmation. Detailed validation belongs in the folder guides and
[development workflow](docs/agent/workflow.md).

## Architecture & Coding Rules

### 1. Robot Framework (`.robot`, `.resource`)

- **Spacing:** separate keywords and arguments with exactly four spaces. Do not use tabs or two-space separators.
- **Separation of responsibilities:** keep business scenario flow in suites. Move nested `IF`/`FOR`, parsing, and repeated or complex logic into resource keywords or Python libraries.
- **Variable naming:** use `${UPPER_SNAKE_CASE}` for global, suite, and shared variables; use `${lower_snake_case}` for local variables.
- **Waiting:** do not introduce fixed `Sleep` calls. Use `Wait Until Keyword Succeeds` to poll an observable state with a bounded timeout.
- **Test independence:** test cases must pass independently of execution order. Clean up created data and sessions in `[Teardown]` or `Suite Teardown`.

### 2. Python Custom Libraries (`libraries/*.py`)

- Add type hints and docstrings to every public keyword function. Type hints must be compatible with Robot argument conversion and the supported Python runtime.
- Prefix internal functions that must not be exposed as Robot keywords with an underscore, such as `_helper`.
- Raise `AssertionError` with a clear failure reason for keyword assertion failures so the cause is visible in `log.html`.

## Boundaries (Do NOT do)

- **Do not change shared variables without impact analysis:** search all references across the repository and identify every affected suite before editing shared variables in `resources/`.
- **Do not bypass failing tests:** never remove or weaken assertions, or add skip tags, merely to make regression tests pass.
- **Do not commit secrets or generated output:** use environment variables or environment configuration for IPs, accounts, and tokens; do not hardcode them in test or library logic. Never commit `results/` contents or tracked plaintext credentials.
- **Do not add dependencies without prior confirmation:** this includes additions to `requirements.txt` or `pyproject.toml`.
- Preserve existing user changes and keep edits within the requested scope. Documentation edits do not authorize an unrelated suite or protocol redesign.

## Task Completion Checklist

Include the following in the completion report:

1. Changed files and the reason for each main change.
2. A summary of `robot --dryrun` or targeted test results, including checks that could not run.
3. The affected test suites when shared keywords or variables change.
