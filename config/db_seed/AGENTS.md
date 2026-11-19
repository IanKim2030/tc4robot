# Seed SQL Instructions

Read [shared PDB guidance](../../docs/shared/PDB.md) for seed block syntax,
variable substitution, DB selection, and idempotency.

- Keep SQL in the appropriate environment file and preserve check/insert/update block boundaries.
- Use supported Robot variable substitutions rather than duplicating environment values or credentials.
- Preserve DB-specific syntax and the intended target tables.
- Validate parsing offline using `libraries/DbSeedHelper.py`. Execution and even check-only seeding can access real DBs; distinguish parsing from integration verification.
