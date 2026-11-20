# Python Library Instructions

This directory owns Python protocol, infrastructure, and configuration helpers.
Read the [resource catalog](../resources/AGENTS.md) and the affected [node specification](../tests/AGENTS.md).

- Preserve public Robot keyword names, function signatures, aliases, and wire layouts during structural refactors.
- Robot resources import libraries by file path: `${CURDIR}/../libraries/<Module>.py`. Setup suites use `../libraries/<Module>.py`.
- For standalone Python tools, add this directory to the import path before importing the existing top-level modules. This is not a new Python package API.
- Keep sibling dependencies together. CDS and RTS import `TcpHelper`; FTP loads `SftpServerHelper.py` relative to `__file__`.
- Preserve lazy imports for optional `pyodbc`, `h2`, `pyftpdlib`, and `paramiko` dependencies.
- Encoding changes require the [wire encoding skill](../.claude/skills/pg-wire-encoding/SKILL.md), byte-level assertions, and node encoding-table updates.
- NWDAF tag changes must update both `TlvHelper.py` and `resources/nwdaf_variables.robot`.
- Validate imports through Robot as well as Python. Use local peers for transport checks; dry runs alone do not execute library behavior.

## Public Keyword Contracts

Follow the root type-hint, docstring, and assertion-message rules when adding or
changing public keywords. An annotation must accept the values Robot actually
passes, including `None` where supported. Do not mechanically annotate legacy
functions without checking Robot conversion and runtime compatibility.

Use `AssertionError` for keyword assertion failures. Existing transport/DB exception
classes are part of the library contract; do not replace them as an unrelated
cleanup. Internal helpers must use underscore-prefixed names.

## Test and Lint Availability

The requested commands are `pytest libraries/tests/` and `ruff check libraries/`.
Configuration precedence tests live in `libraries/tests/` and run without additional
packages: `python -m unittest discover -s libraries/tests -v`. pytest/ruff are not
declared development dependencies; report unavailable tools rather than installing
them. Import, byte-level, and local-peer checks complement the mandatory dry run.
