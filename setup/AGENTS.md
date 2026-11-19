# Setup Suite Instructions

This directory orchestrates pre-run DB seeding. Read [PDB](../docs/shared/PDB.md)
and [SSH](../docs/shared/SSH.md) before changing setup behavior.

- Import Python helpers from `../libraries/` and preserve Robot aliases.
- Keep SQL in `config/db_seed/` and parsing/DB/SSH implementations in `libraries/`.
- Preserve failure propagation: failed seed preparation must prevent the main suite execution.
- Keep check-only mode separate from INSERT/UPDATE and post-insert SSH commands.
- Use a direct Robot dry run for structural checks. Do not execute live seeding as part of an import-path check.
