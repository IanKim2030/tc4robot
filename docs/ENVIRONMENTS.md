# ENVIRONMENTS — Environment settings (dev/stg/prd)

## run

```bash
bash run_tests.sh nag              # dev (default) — read config/env/dev.py
bash run_tests.sh nag stg          # stg
bash run_tests.sh all prd          # prd — Requires PG_ALLOW_PRD=1
bash run_tests.sh all 192.168.1.1  # Just change the IP (dev.py + override PG_HOST)

# Bypass run_tests.sh
python -m robot --variablefile config/env/stg.py tests/nag/
```

Check which environment is applied using the `ENV:` line in the banner.

## structure

```
resources/variables.robot ← Shared variables (constants, toggles, shared defaults). **There is no environment value**
resources/<iface>_variables.robot ← Node variable. Shared values are for reference only
config/env/dev.py ← dev environment values (required) + catalog of overridable values. It's in git
config/env/stg.py ← stg environment value (required) + value different from default. It's in git
config/env/prd.py ← (gitignore) prd environment value (required) + execution guard
config/env/local.py ← (gitignore) private override, optional
```

### Environment values are placed only in the environment file (2026-11-03)

Environment-specific values (`PG_HOST`, `TOOL_HOST`, `PDB_CONNSTR`, and the shared
`SUBS_MDN_*`/`SUBS_MIN_*` identities) have no defaults in `resources/variables.robot`.
Previously, missing stg/prd values silently fell back to dev, potentially targeting
the wrong DB or subscribers. Missing values now fail where referenced with
`Variable '${...}' not found`. `PDB_CONNSTR` can also come from `PG_PDB_CONNSTR`.

`run_tests.sh` loads `config/env/dev.py` even when no environment argument is given
or only a host IP is supplied. Direct Robot commands must explicitly include
`-V config/env/dev.py` or the corresponding environment file; otherwise required
variables are unavailable.

### Renamed variables — old names are still used

| New name (variables.robot) | Legacy name (node variable) | action |
|---|---|---|
| `${SBI_NOTI_PORT}` / `${SBI_NOTI_HOST}` | `${CDS_NOTI_PORT}` `${RTS_NOTI_PORT}` / `${CDS_NOTI_HOST}` `${RTS_NOTI_HOST}` | The default value of the node variable is the new name. If you cover it with a legacy name, only that node will change. |
| `${PDB_TIMEOUT}` / `${PDB_AUTOCOMMIT}` | `${CDS_DB_TIMEOUT}` / `${CDS_DB_AUTOCOMMIT}` | Same as above |
| `${TOOL_HOST}` | (`cds_variables.robot` to `192.168.15.142` literals) | `${CDS_SESSION_PCF_ADDR}`/`SMF_ADDR` is created with this value |
| `libraries/PdbHelper.py` · `PdbError` | `CdsDbHelper.py` · `CdsDbError` | Exceptions are left as aliases. The file name has changed all imports in the repo. |
| Environment variable `PG_PDB_CONNSTR` | `PG_CDS_DB_CONNSTR` | Continue reading with fallback |

## Variable Priority

From highest to lowest:

1. Explicit CLI `--variable` values.
2. Explicit values in `config/env/<env>.py` or other CLI variable files.
3. Supported values read from the target server configuration.
4. Defaults in `resources/*_variables.robot` and shared `variables.robot`.

An explicit environment value wins even when it equals the node default. Multiple
variable files and CLI variables follow Robot's ordering rules. The remote mapping catalog is
[`config/remote_settings.json`](../config/remote_settings.json). All runner targets
read its enabled mappings at startup: currently NAG/PCF destination ports from
`BarodNoti.cfg` and CDS O/R ports from `PG_V2.cfg [CDS]`. Unmapped settings retain
their environment overrides and defaults; unverified server keys are not guessed.
See [SSH configuration](shared/SSH.md#read-nagpcf-ports-from-barodnoticfg).

`run_tests.sh` resolves configuration **before DB seeding**, writes a private JSON
snapshot under the ignored results directory, and passes it to both the seed and
main Robot processes through `libraries/RuntimeConfig.py`. Explicit CLI variables,
including DB connection and subscriber overrides, therefore reach both phases.
The seed imports node defaults for SQL variable substitution. Suite-local protocol
state and overrides remain local; the snapshot does not promote every resource
default above suite variables. DB credentials retain the existing environment
variable handling in `PdbHelper`.

Configuration resolution failure prevents DB seed and tests. Dry runs skip remote
reads and make the seed phase a dry run too. Snapshot files may contain private
configuration; keep their owner-only permissions and never commit or share them.
Post-seed SSH commands do not trigger a second configuration read: a run uses one
snapshot. Start a new run to pick up later server configuration changes.

Direct `robot -V config/env/dev.py ...` NAG CLI execution applies the same port
priority in Suite Setup, but does not execute DB seed. Use the runner for one
shared configuration snapshot across both phases.

## environment axis variables

Shared configuration names live in `resources/variables.robot`, while environment-only
values are supplied by the environment file. Node variables reference these shared
values, so one environment override reaches all relevant nodes.

Use a shared configuration axis only for values used by at least two nodes.
Node-only defaults belong directly in `<iface>_variables.robot`, for example
`${CDS_MDN}` and `${CDS_MIN}`. Environment overrides work regardless of the default's
location; unnecessary indirection only increases duplication risk.

| variable | Spread to |
|---|---|
| `${PG_HOST}` | `${NAG_PG_HOST}` `${PCF_PG_HOST}` `${UPM_PG_HOST}` `${NWDAF_HOST}` `${CDS_PG_HOST}` `${LRS_CLIENT_HOST}` |
| `${TOOL_HOST}` | `${CDS_SESSION_PCF_ADDR}` `${CDS_SESSION_SMF_ADDR}` ([shared/SBI_NOTI.md](shared/SBI_NOTI.md)) |
| `${SBI_NOTI_PORT}` / `${SBI_NOTI_HOST}` | `${CDS_NOTI_PORT}` `${RTS_NOTI_PORT}` / `${CDS_NOTI_HOST}` `${RTS_NOTI_HOST}` |
| `${PDB_TIMEOUT}` / `${PDB_AUTOCOMMIT}` | `${CDS_DB_TIMEOUT}` / `${CDS_DB_AUTOCOMMIT}` ([shared/PDB.md](shared/PDB.md)) |
| `${SUBS_MDN_LTE}` | `${NAG_MDN}` `${PCF_MDN}` `${LRS_MDN}` (default for node-specific destination numbers below) `${NWDAF_MDN}` |
| `${SUBS_MIN_LTE}` | `${NWDAF_MIN}` |
| `${SUBS_MDN_5G}` / `${SUBS_MIN_5G}` | `${LRS_MDN_5G}` `${NWDAF_MDN_5G}` `${NWDAF_MIN_5G}` |
| `${SUBS_MDN_NO_HFC}` | `${NAG_MDN_NO_HFC}` `${LRS_MDN_NO_SESSION}` |
| `${SUBS_MDN_NO_SESSION}` | `${NAG_MDN_NO_SESSION}` |
| `${SUBS_APN_LTE}` / `${SUBS_APN_5G}` | `${NAG_APN}` `${LRS_APN_LTE}` `${LRS_APN_5G}` |
| `${SUBS_MOBILE_IP}` | `${NAG_MOBILE_IP}` `${LRS_SI_CLIENT_IP}` |
| `${NET_CELL_ID}` / `${NET_PGW_IP}` | `${NWDAF_CELL_ID}` `${NWDAF_PGW_IP}` |
| `${NET_SI_FROM_IP}` | `${LRS_SI_FROM_IP}` — Must be an IP registered in PG (otherwise 403) |

### Target number per node (MDN)

There is an MDN variable  for each node, , so that test subscribers can be used separately for each node. with this name in the environment file
Covers — dev is gathered in the "Node Target Number" section of `config/env/dev.py`.

| node | environment file name | default | Variables actually used |
|---|---|---|---|
| NAG | `NAG_MDN` | `${SUBS_MDN_LTE}` | `${NAG_MDN_NORMAL}` |
| PCF | `PCF_MDN` | `${SUBS_MDN_LTE}` | `${PCF_TEST_MDN}` |
| LRS | `LRS_MDN` | `${SUBS_MDN_LTE}` | `${LRS_SI_MDN}` `${LRS_MDN_LTE}` |
| CDS | `CDS_MDN` / `CDS_NEW_MDN` | `01090010001` / `01090010002` | As it is |
| RTS | `RTS_MDN` | `01090010001` | `${RTS_TEST_MDN}` |

dev.py contains CDS `CDS_MIN` / `CDS_NEW_MIN` (MDN leading 0 removed) and session IMSI (`45005` + MIN)
Calculate from MDN — just change MDN and it will follow. Other environment files can be used in the same way.

Node identifiers (`*_SYS_ID` / `*_BRANCH_NAME`) and ports have different values for each node and were not integrated.
If necessary, specify  directly for each  node in the environment file.

## Create environment file

This is the entire catalog of values that `config/env/dev.py` can cover. Just uncomment it and enter the value.

```python
# config/env/stg.py
# ── Required (no default value in variables.robot ) ──
PG_HOST      = '10.20.30.40'
TOOL_HOST    = '10.20.30.50'    # Tool Host — The address to which the PG connects back.
PDB_CONNSTR  = 'DSN=PDB;UID=pgtest;'          # Except PWD — environment variable PG_PWD_PDB_1
SUBS_MDN_LTE = '01011112222'    # Automatic propagation to NAG/PCF/LRS/NWDAF
SUBS_MIN_LTE = '1011112222'
SUBS_MDN_5G  = '01011113333'
SUBS_MIN_5G  = '1011113333'

# ── Selection ──
CDS_MDN      = '01090020001'    # Target number for each node is individually specified

CDS_DST_SYS_ID = 'PG02'         # Individual designation for each node
NAG_PG_PORT    = 8012
```

Robot reads the  module global name in the variable file as a variable. `PG_HOST = ...`
It becomes `${PG_HOST}`. Names starting with an underscore are ignored.

## DB setting seed before PDB connection/execution

Moved to [shared/PDB.md](shared/PDB.md) — connection string (`PDB_CONNSTR`, environment variable `PG_PDB_CONNSTR`),
The second DB, Goldilocks/Altibase trap, `config/db_seed/<env>.sql` format and seed options are there.
After the seed INSERT, the PG remote command (`stopMP app` → `startMP app`) is [shared/SSH.md](shared/SSH.md).

## prd guard

`config/env/prd.py` refuses to run without environment variables.

```bash
export PG_ALLOW_PRD=1              # PowerShell: $env:PG_ALLOW_PRD='1'
bash run_tests.sh smoke prd
```

In particular, the NWDAF Notification cannot be reversed because the PG does not respond.
Before executing prd, be sure to check the target subscriber and `--include` tag.

## Add new environment

1. Create `config/env/<name>.py` — Required environment values (“Environment values are only placed in the environment file” above) + values different from the default
2. Add `<name>` to `case` of `run_tests.sh`
3. Add a line to this document

## private override

`config/env/local.py` becomes `.gitignore`. Used when redirecting to different IPs.

```bash
bash run_tests.sh nag local
```

## Credentials

### Password is only an environment variable (2026-11-04)

The password is also included in the environment file (entered in git) and in the Robot variable/keyword argument (remained in log.html).
Do not leave it. If  is given as an environment variable in the execution shell, the Python helper reads it directly.

| environment variables | Use | Where to read | If there is no |
|---|---|---|---|
| `PG_PWD_SSH` | PG server SSH (`.RUN` touch, seed follow-up `stopMP`/`startMP`) | `SshHelper.py` (old name `PG_SSH_PASSWORD` fallback) | Connection fails without key authentication (`PG_SSH_KEY_FILE`) |
| `PG_PWD_PDB_1` | First PDB — Insert `PWD=` in `PDB_CONNSTR` | `PdbHelper.py` | If there is no PWD in the connection string, the connection fails. |
| `PG_PWD_PDB_2` | Second PDB — `PWD=` of `PDB_CONNSTR_2` | `PdbHelper.py` | Same as above only when using DB2 |
| `PG_PWD_UPM_FTP` | UPM FTP/SFTP listening server — same value as PG setting `PASSWORD_04` | `FtpServerHelper.py` | If you turn on FTP reception (`UPM_FTP_ENABLE`), Suite Setup will fail (avoid with `--no-ftp`) |

```bash
export PG_PWD_SSH='...'
export PG_PWD_PDB_1='...'
export PG_PWD_UPM_FTP='...'
bash run_tests.sh all stg
# PowerShell: $env:PG_PWD_SSH='...'
```

In `config/env/<env>.py`, write `PDB_CONNSTR` without PWD (`'DSN=PDB;UID=pdb;CHARSET=UHC;'`).
The environment variable value does not depend on the  environment. — If you run dev and stg alternately on one host, the password will be
You have to change export every time it is different. The values when these three were in plain text in dev.py are in the git history.
Remains — If the account is actually used, the password itself must be changed.

### Remove DynamicVars

> Since 2026-11-20 the NAG suite reads `BarodNoti.cfg [Barod.IF]` ports again, but through
> `Load NAG Ports From BNOTI Cfg` with no silent fallback — see [shared/SSH.md](shared/SSH.md).

`DynamicVars`, which read PG settings with SSH, has been removed. (Current SSH is `.RUN` touch and seed successor
This is the command — [shared/SSH.md](shared/SSH.md).)

Reasons for removal — The actual cfg values were all the same as the hard-coded default values, so there was no difference in operation :

| cfg | key | actual measurement | default |
|---|---|---|---|
| `PG_V2.cfg [CDS]` | `O_PORT` | 9200 | 9200 |
| `PG_V2.cfg [CDS]` | `R_PORT` | 9201 | 9201 |
| `BarodNoti.cfg [Barod.IF]` | `Barod.IF.Port.NAG` | 8012 | 8012 |

Moreover, the code looked up `S_PORT`, but the actual key was `O_PORT`, and Schannel was  in the search in the first place.
It failed and was only riding a fallback. The fallback value was the same as the actual value, so no one noticed.

> ⚠ Previously, the SSH password was committed in plain text to `resources/variables.robot`.
> Although it was removed from the file, it remains in the git history. If the account is actually used,
> The password itself must be replaced.

## Startup Remote Configuration Catalog

Every runner target resolves the same catalog before DB seed. Configure
`REMOTE_CONFIG_MAP_PATH` in the environment file to use an extended JSON catalog.
Each entry supplies `variable`, `path`, `section`, `key`, and optional `type`
(`string`, `integer`, `port`, or `boolean`) and `host` (default `${PG_HOST}`).
Path, section, key, and host fields can reference existing Robot variables.
Entries with an empty path are explicitly disabled; explicit CLI/environment
values override the matching remote entries. Reads are grouped by host, path,
and section. Missing keys, invalid values, SSH failures, or a missing SSH account
abort startup before DB access. Use `--no-remote-config` for an explicitly offline
run. `--no-bnoti-cfg` disables only the BarodNoti mappings; CDS still resolves.
Dry runs perform no remote reads.

Only add mappings with confirmed server configuration keys and direction. A
server listen address is not necessarily a valid tool bind address. Passwords
remain environment variables, outside the remote catalog. UPM, NWDAF, RTS,
LRS side-channel, DB, and notification mappings require verified server files
and keys before automatic discovery can cover them. Existing environment values,
including the LRS listener endpoint, remain effective meanwhile.
