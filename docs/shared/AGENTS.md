# Shared Reference Instructions

This directory owns infrastructure behavior used by multiple nodes: PDB, SBI
notifications, and SSH. Keep node-specific acceptance criteria in `tests/<node>/AGENTS.md`.

- Link to the current Python implementation under `libraries/` and its Robot resource callers.
- Document configuration precedence, lifecycle, optional dependencies, and observable failure modes.
- Keep connection credentials out of examples and generated logs.
- Clearly distinguish offline parsing/import checks from DB writes, remote commands, and live listeners.
- Update affected node references when changing shared behavior.
