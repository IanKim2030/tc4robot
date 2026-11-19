# Environment File Instructions

Follow [environment configuration and precedence](../../docs/ENVIRONMENTS.md).

- `dev.py` and `stg.py` are tracked; production and personal files are supplied separately.
- Preserve required variable names and the production execution guard.
- Receive passwords from environment variables; never add plaintext passwords to Python files or Robot command-line variables.
- Prefer one shared environment axis for values used by multiple nodes and explicit node overrides where necessary.
- Check syntax and run direct Robot dry runs with the changed variable file. Do not contact configured services just to validate paths.
