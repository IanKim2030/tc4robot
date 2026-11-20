# Configuration Instructions

Read [environment rules](../docs/ENVIRONMENTS.md) before editing values or precedence.

- Keep environment-only endpoints, connection strings, and shared subscriber identities in `env/`.
- Keep environment-specific seed SQL in `db_seed/`; keep execution logic in `setup/` and Python implementations in `libraries/`.
- Do not add credentials or silently substitute dev values for missing stg/prd keys.
- Preserve the distinction between shared defaults, node defaults, and explicit environment overrides.
- Configuration changes can affect multiple nodes; validate all affected suite imports with the chosen variable file.

`remote_settings.json` owns verified server-file-to-Robot-variable mappings.
Keep precedence and startup behavior in [environment rules](../docs/ENVIRONMENTS.md).
Do not infer keys or copy server listener addresses into tool bind variables.
