# SSH — PG Process Startup and Post-Seed Commands

Two operations execute commands on `${PG_HOST}` through
[libraries/SshHelper.py](../../libraries/SshHelper.py), using different SSH clients.

| Operation | When | Keyword or function | Connection |
|---|---|---|---|
| Ensure PG processes are running | Suite Setup | `Ensure PG Process Running` in [ssh_keywords.robot](../../resources/ssh_keywords.robot) → `ensure_pg_process_running` | System `ssh` through subprocess; no Python package |
| Commands after seed INSERT | End of `setup/db_seed.robot` | `Run Seed SSH Commands` → `run_remote_command` | `paramiko`; install with `pip install paramiko` |
| Read NAG/PCF ports from PG cfg | NAG Suite Setup | `Load NAG Ports From BNOTI Cfg` → `read_remote_cfg` | System `ssh` (`cat`); no Python package |

Paramiko is imported lazily. It is unnecessary when no rows were inserted, the
command list is empty, or `--no-db-seed-ssh` is set. If an enabled command needs
Paramiko and it is missing, seeding fails with an installation hint.
On Python 3.6, upgrade pip to at least 21.3.1 before installing binary dependencies
(`cryptography`, `bcrypt`, and `pynacl`). Older pip 9 attempted a failing pynacl
source build on Rocky8, as observed on 2026-11-04.

## Account · Authentication

| Variable | Default | Meaning |
|---|---|---|
| `${PG_SSH_USER}` | Empty | Empty skips process startup; dev/stg use `pg` |
| `${PG_SSH_KEY_FILE}` | Empty | Key authentication takes precedence: system `-i`/`BatchMode=yes`, or Paramiko `key_filename` |
| Environment variable `PG_PWD_SSH` | Not set | Password authentication; never pass it as a Robot variable because that exposes it in `log.html` |

Both paths use the same account rules and bypass host-key confirmation through
`StrictHostKeyChecking=no` or Paramiko `AutoAddPolicy`. Password authentication
does not first attempt an SSH key agent.

- System SSH injects the password through OpenSSH's `SSH_ASKPASS`, without
  `sshpass`. The temporary askpass script contains no password literal and is
  deleted immediately after execution.
- Paramiko receives the password directly from `PG_PWD_SSH`, and returns exit
  status, stdout, and stderr through its channel. Connection, banner, and
  authentication timeouts are 10 seconds. The command timeout is
  `${DB_SEED_SSH_TIMEOUT}` (60 seconds).

A previous plaintext password commit is documented under
[environment credentials](../ENVIRONMENTS.md#credentials).

## Ensure PG process startup — `.RUN` touch

Touch `${PG_SSH_RUN_DIR}/<name>.RUN` for each required PG process; the default
directory is `/PG/BIN/PDB_RUN`. Message responses can still return `SC` while a
downstream process is stopped, leaving only DB or notification checks to fail.

| Suite | Required processes | Developer reference |
|---|---|---|
| NAG | `G_BNOTI201`, `G_LRS201`, `CDS201` | [NAG flow](../callflow/nag_callflow.md) |
| PCF | `CDS201` | [PCF flow](../callflow/pcf_callflow.md) |
| LRS | `G_LRS201`, `CDS201` | [LRS flow](../callflow/lrs_callflow.md) |
| CDS | `CDS201`, `P_SDM601`, `R_SDM601`, `SNOTI501`, `BSUBS201`, `RDS601` | [CDS flow](../callflow/cds_callflow.md) |
| RTS | `RTS201`, `P_SDM601`, `SNOTI501` | [RTS flow](../callflow/rts_callflow.md) |

UPM/NWDAF do not call this mechanism because their `.RUN` paths are unconfirmed.
Do not invent paths. NAG/PCF/LRS wait `${PG_SSH_SETTLE}` (default 3 seconds)
after touching the flag before opening sockets: the flag is only a signal, and
PG needs time to start. CDS/RTS perform other setup, including DB access, during that interval.

An empty `${PG_SSH_USER}` or disabled `${PG_SSH_ENSURE}` (`--no-ssh-ensure`)
skips startup. Once configured, a missing `ssh` executable or failed connection
or command raises `SshEnsureError`, failing Suite Setup and preventing TCs from
running against stopped processes.

## Remote command after seed INSERT

If [configuration seeding](PDB.md#db-setup-seed-before-execution-configdb_seedsql)
inserts at least one row across DB1 and DB2, run `${DB_SEED_SSH_CMDS}` in order
to make PG reload its configuration. Each command opens a separate SSH session;
wait `${DB_SEED_SSH_GAP}` between commands.

```python
# config/env/stg.py: enabled
DB_SEED_SSH_ENABLE = True
DB_SEED_SSH_CMDS   = ['stopMP app', 'startMP app']
DB_SEED_SSH_GAP    = '5s'

# config/env/dev.py: disabled; enable for one run with --db-seed-ssh
DB_SEED_SSH_ENABLE = False
```

| Variable | Default | Meaning |
|---|---|---|
| `@{DB_SEED_SSH_CMDS}` | Empty | Empty skips commands |
| `${DB_SEED_SSH_GAP}` | `5s` | Pause between commands, not after the final command |
| `${DB_SEED_SSH_TIMEOUT}` | `60` | Timeout in seconds per command |
| `${DB_SEED_SSH_ENABLE}` | `${TRUE}` | dev overrides to False; stg to True. CLI flags `--db-seed-ssh`/`--no-db-seed-ssh` override the environment file. |

No commands run when zero rows were inserted or `--db-seed-check` is enabled.
For enabled commands, an empty `${PG_SSH_USER}` is a failure rather than a skip.
A nonzero remote exit status fails seeding and prevents the main suite execution.

## Read NAG/PCF ports from `BarodNoti.cfg`

The NAG suite's Suite Setup (`Initialize NAG Regression`) runs `cat ${BNOTI_CFG_PATH}`
on `${PG_HOST}` before any socket is opened and overrides the destination ports:

```ini
[Barod.IF]
Barod.IF.Port.PCF=8011 # → ${PCF_PG_PORT}
Barod.IF.Port.NAG=8012 # → ${NAG_PG_PORT}
```

| Variable | Default | Meaning |
|---|---|---|
| `${BNOTI_CFG_PATH}` | `/PG/CFG/BarodNoti.cfg` | Empty skips (`bash run_tests.sh nag --no-bnoti-cfg`) |
| `${BNOTI_CFG_SECTION}` | `Barod.IF` | Section to read |
| `${BNOTI_CFG_KEY_PCF}` / `${BNOTI_CFG_KEY_NAG}` | `Barod.IF.Port.PCF` / `Barod.IF.Port.NAG` | Keys |

An empty `${PG_SSH_USER}` also skips it and keeps the defaults from
`nag_variables.robot` / `pcf_variables.robot`. Once enabled, an SSH failure, a
missing section or key, an empty value, or a non-integer value fails Suite Setup.
It never silently falls back: the removed `DynamicVars` looked up a wrong key for
a long time without anyone noticing, because the fallback matched the real value
([ENVIRONMENTS](../ENVIRONMENTS.md)). `#` starts an inline comment.
