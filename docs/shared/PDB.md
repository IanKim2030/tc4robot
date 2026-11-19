# PDB — DB access and inquiry common (CDS, RTS, seed)

PDB is a DB where PG stores subscribers, sessions, and settings. Depending on the environment, it is Goldilocks or Altibase,
In a redundant environment, both are possible. In this repo, there are three places attached to PDB and one  helper is  —
[libraries/PdbHelper.py](../../libraries/PdbHelper.py) (ODBC / `pyodbc`, `DatabaseLibrary` are not used).

| Where to use | alias | What you do | Details |
|---|---|---|---|
| CDS suite | `CdsDb` | Application assertions (SELECT), session preload (INSERT), cleanup at end (DELETE) | [../../tests/cds/AGENTS.md](../../tests/cds/AGENTS.md#pdb-judgment-criteria-by-business-code) |
| RTS suite | `RtsDb` | Judgment to reflect blocking, cleanup upon completion | [../../tests/rts/AGENTS.md](../../tests/rts/AGENTS.md) |
| Seed before run | `SeedDb` | Check the settings row → INSERT/UPDATE | Below [DB setting seed before execution](#db-setup-seed-before-execution-configdb_seedsql) |

## variable

| variable | default | Description |
|---|---|---|
| `${PDB_CONNSTR}` | None (environment file required) | ODBC string — Leave out PWD and write . If there is an environment variable `PG_PDB_CONNSTR` (formerly `PG_CDS_DB_CONNSTR`), that takes precedence. |
| `${PDB_CONNSTR_2}` | empty value | Second DB. Environment variable `PG_PDB_CONNSTR_2` (no legacy fallback) |
| Environment variable `PG_PWD_PDB_1` | — | First DB password. Insert `PWD=` in the connection string (replace if present, append if not). If there is `;{}`, wrap it with `{...}` |
| Environment variable `PG_PWD_PDB_2` | — | Second DB password — same method as above |

If there is no password environment variable and no PWD in the connection string, there is no PDB password before connecting to  —
It fails with ‘Please set the environment variable PG_PWD_PDB_1’ (configuration with a password in odbc.ini of DSN is not supported).
| `${PDB_TIMEOUT}` | `5` | Connection/query timeout (seconds). Even if it is covered with the old name `${CDS_DB_TIMEOUT}`, it is eaten. |
| `${PDB_AUTOCOMMIT}` | `${FALSE}` | Old name `${CDS_DB_AUTOCOMMIT}`. The reason for turning it off is below [autocommit trap](#trap--autocommitfalse-can-neutralize-rechecks) |

The definition is [resources/variables.robot](../../resources/variables.robot), the value is `config/env/<env>.py`.
In either case, the connection string is Python reads it directly (it is not passed as a Robot keyword argument) — so
Only the masked string (`PWD=`) remains in `log.html`.

★ CDS suite is attached to PDB in Suite Setup. If  connection string is incorrect, only `db` tag TC is used.
In addition, the entire CDS suite, including the message transmission and reception TC, does not stop.(`--exclude db`
It cannot be avoided either — Suite Setup runs regardless of the tag).

## Connection string — do not assemble

If you enter the completed ODBC string in `${PDB_CONNSTR}`, it goes as  as  `pyodbc`.
Register the DSN in `odbc.ini` (Linux) / ODBC Data Source Manager (Windows) and enter only the name.
Referring to it is a Goldilocks rule.

```python
PDB_CONNSTR = 'DSN=GOLD_GLOBAL;UID=pdb;'     # PWD is the environment variable PG_PWD_PDB_1
```

`${CDS_DB_KIND}` `${CDS_DB_DSN}` `${CDS_DB_DRIVER}` `HOST`/`PORT`/`NAME`/`USER`/
The path of  assembly with `PASSWORD`/`EXTRA` has been removed.  assembly logic (`_KIND_SPEC`,
`build_conn_str`, `_fmt_driver`) were also eliminated. DSN-less assembly rejected at Goldilocks
(Section below), there are items in the actual environment `odbc.ini` that are difficult to translate into strings, so all of them are DSN.
This is because it converged to the registration + completion string.

The fact that the keyword notation is different for each DB is still valid.  — Now you can directly enter the string
The writer must know.

| item | Goldilocks | Altibase |
|---|---|---|
| host | `HOST` | `Server` |
| port | `PORT` | `PORT` |
| DB name | `DATABASE` | `DBName` |
| Account/Password | `UID` / `PWD` | `UID` / `PWD` |

The Goldilocks value is actual environment `odbc.ini` actual measurement (2026-08-06), and the Altibase value is still unverified .

You can also use it directly without a DSN. However, curly braces should not be added to the `.so`  path, and the  host key
Not `SERVER`, but `HOST` — both are Goldilocks measurements (IM012 trap below).

```python
PDB_CONNSTR = ('DRIVER=/PG/goldilocks_home/lib/libgoldilockscs-ul64.so;'
               'HOST=10.20.30.40;PORT=22581;UID=pgtest;CHARSET=UHC;')   # PWD is PG_PWD_PDB_1
```

Password is not written in this string. — Given as environment variable `PG_PWD_PDB_1` (variable table above). connection string
There is also a way to give the entire thing as an environment variable (priority to Robot variables).

```bash
export PG_PWD_PDB_1='...'                          # Password only (recommended)
export PG_PDB_CONNSTR='DSN=PDB;UID=pgtest;'        # Only when changing the entire connection string
# PowerShell: $env:PG_PWD_PDB_1='...'
# The legacy name PG_CDS_DB_CONNSTR is also continued to be read as a fallback.
```

## Second DB — `${PDB_CONNSTR_2}`

Depending on the environment, set Goldilocks and Altibase to  and both  and session information (`T_SMF_SESSION_INFO`).
There is a mix of cases where it must be placed in both places and cases where there is only one DB. `${PDB_CONNSTR_2}`
If you fill in (environment variable `PG_PDB_CONNSTR_2`, no legacy fallback), you will get `Ensure CDS Session In PDB`
(session preload) and `Cleanup CDS Subscriber Rows` (section below, cleanup on exit)
Enter the same SQL on both `${CDS_DB_CONN}` (first) and `${CDS_DB_CONN_2}` (second) .
Run. If empty (default), only applies to the first DB — the same behavior as before.

```python
# config/env/<env>.py
PDB_CONNSTR   = 'DSN=GOLD_GLOBAL;UID=pdb;'                   # Goldilocks — PWD is PG_PWD_PDB_1
PDB_CONNSTR_2 = 'Server=...;PORT=...;DBName=...;UID=...;'    # Altibase — PWD is PG_PWD_PDB_2
```

★ The only target of application is writing (INSERT/DELETE). Decision to reflect subscriber profile/service
(`SELECT` series such as `Verify Subscriber Provisioned In PDB`) still sees only the first DB of
— The premise is that which DB PG.SDM considers to be reflected is fixed to one.

★ Seed is different — `${PDB_CONNSTR_2}` If present, all blocks in the seed file are also stored in DB2.
Apply. If DB2 does not have a seed target table (for example, `T_SESSION_INFO`), the seed is `42S02 Table not found`
It fails with The toggle to turn off only the session table of CDS by DB is [../../tests/cds/AGENTS.md](../../tests/cds/AGENTS.md)]
The section is “Turn off session tables separately for each DB.”

## DB setup seed before execution (`config/db_seed/<env>.sql`)

`run_tests.sh` is , regardless of the target (nag/…/all/smoke).  `setup/db_seed.robot`
Turn once separately. If there is no configuration line that PG reads, this is the step to insert it and start. With node
It is unrelated. There is a separate file for each environment.

| run | seed file |
|---|---|
| `bash run_tests.sh nag` / `nag dev` / `nag 192.168.1.1` | `config/db_seed/dev.sql` |
| `bash run_tests.sh nag stg` | `config/db_seed/stg.sql` |
| `prd` / `local` | `config/db_seed/<env>.sql` — If there is no DB connection, it is skipped. |

```sql
-- @name: Block name (optional)
SELECT COUNT(*) FROM T_XXX_CFG WHERE KEY_COL = 'A';     -- Open block (1 row 1 column integer)
INSERT INTO T_XXX_CFG (KEY_COL, VAL) VALUES ('A', '1'); -- Execute only when the above result is 0
UPDATE T_XXX_CFG SET VAL = '1' WHERE KEY_COL = 'A';     -- Execute only when the above result is 1 or more
```

- The statement that starts with SELECT opens the block, and INSERT / UPDATE before the next SELECT does it.
  Belongs to a block. It can be written over multiple lines (sentences are separated only by `;`). Any other sentences are rejected.

  | OK SELECT | run | After running |
  |---|---|---|
  | 0 cases | INSERT only | Count again with the same SELECT to see if there are more than 1 (or FAIL) |
  | 1 or more | UPDATE only (if not present, skip to "present") | WARN if impact row is 0 |

  If there is only INSERT, it is “insert it if it does not exist,” if there is only UPDATE, it is “fix it if it exists,” and if there are both, it is upsert.
  UPDATE overwrites the value on each execution — any value changed by TC is also returned before starting.
- For each executed INSERT/UPDATE statement, the number of target tables and affected rows is displayed in the console, and the total SQL is displayed in `log.html`.
  It remains. At the end, write a summary for each DB (number of existence/INSERT/UPDATE blocks).
- There is no bind parameter (`?`). The value is written as a literal or `${VARIABLE}` — as an environment file value at run time.
  changes (`'${CDS_MDN}'`, `'82${CDS_MIN}'`, `'http://${TOOL_HOST}:${SBI_NOTI_PORT}/...'`).
  So, when changing the number or address, you only need to change `config/env/<env>.py`. Because it is literally inserted into
  If you write the quotation marks directly and include `'` in the value, the SQL will be broken. The name only accepts `${ASCII_LETTERS_DIGITS_OR_UNDERSCORES}`.
  Variables without  will fail with line number  (do not leave them empty). `${...}` in the comment remains the same.
- Do not add the `PDB.` prefix to the table name.
- If there are no blocks, there is no connection to the DB — an environment that does not use the DB operates as is.
- The connection is `${PDB_CONNSTR}`, the same as this run (passing the same `--variablefile`/`--variable`).
  If `${PDB_CONNSTR_2}` exists, perform the same confirmation/INSERT/UPDATE on the second DB.
- If the seed fails, the main execution is not performed. The log is `results/<TS>/db_seed/log.html`.

```bash
bash run_tests.sh nag --no-db-seed      # Skip the seed step
bash run_tests.sh nag --db-seed-check   # OK only — WARN if not present, no INSERT/UPDATE
bash run_tests.sh nag --no-db-seed-ssh  # Omitting remote commands after INSERT
python -m robot -V config/env/dev.py setup/db_seed.robot   # When running directly, first manually (default dev.sql)
python -m robot --variablefile config/env/stg.py \
    --variable DB_SEED_FILE:config/db_seed/stg.sql setup/db_seed.robot   # stg
```

If there was even one INSERT block, send a follow-up command (`stopMP app` → `startMP app`) to the PG server via SSH.
Send — [SSH.md](SSH.md#remote-command-after-seed-insert).

## trap

### Pitfall — Goldilocks DSN-less rejected with `IM012`

```
DRIVER={/PG/goldilocks_home/lib/libgoldilockscs-ul64.so};SERVER=...;PORT=22581;...
→ IM012 [SUNJESOFT][ODBC][GOLDILOCKS]DRIVER keyword syntax error (19043)
```

The two things overlapped. Applied when writing a string directly without DSN.

1. `.so` You should not put curly braces in the path. The ODBC standard is `DRIVER={name}` But GOLDILOCKS
   The driver manager rejects this. The path is written bare, and only wrapped in the driver 'name'.
   (Spaces are common in names, so braces are needed).
2. The  host keyword is not `SERVER` but `HOST` (actual `odbc.ini`).

Even knowing the two, DSN registration is the rule for Goldilocks. real environment `odbc.ini` to
`ALTERNATE_SERVERS`(186~188 fallback) · `LOCALITY_AWARE_TRANSACTION` · `LOCATOR_DSN`
This is because it is inconvenient to transfer it as is into the connection string. The stanza message is
I left it in the comment of the PDB section of `cds_variables.robot`. Clear assembly path and complete string
The fact that only one is left is an extension of this conclusion.

### Pitfall — `?` binding dies without diagnosis

After connecting, the following was found in the inquiry (Goldilocks, 2026-08-06).

```
('HY000', 'The driver did not supply an error!')
sql=SELECT COUNT(*) FROM T_5G_SUBS_PROFILE WHERE MDN = ?  params=('01090010001',)
```

The main cause is character encoding. Goldilocks·Altibase ODBC driver uses Unicode
(`SQL_WVARCHAR`) There are cases where binding is not supported, but pyodbc basically uses strings.
Send wide. The second factor is the binding itself — when pyodbc binds `?`
The parameter type is asked as `SQLDescribeParam`, but in drivers that do not implement this,
As expected, only SQL_ERROR is returned without diagnosis.

The current correspondence is fixed binding of `CHARSET=` + `?` in the connection string.

| factor | In the past | now |
|---|---|---|
| character encoding | `${CDS_DB_ENCODING}` (default `utf-8`) → `conn.setencoding` / `setdecoding` | `${PDB_CONNSTR}` to `CHARSET=` (Goldilocks is `UHC`). Remove all variables and code |
| Parameter binding | `${CDS_DB_BIND}` selects `auto`/`param`/`literal`, with literal fallback | `?` fixed (equivalent to `param`). Avoid `SQLDescribeParam` with `setinputsizes`. Select mode/Remove literal path |

★ The two are not the same. `CHARSET=` is the character set that driver exchanges with the server,
`setencoding` is the SQL type to which pyodbc binds Python `str`.
You must check in the real environment  whether this HY000 does not appear with only `CHARSET=`.  — Literal fallback
Therefore, if it recurs, the query will simply fail. At that time, to revive the pyodbc side, use `db_connect`
Just put three lines right after `pyodbc.connect(...)`.

```python
conn.setencoding(encoding='utf-8')
conn.setdecoding(pyodbc.SQL_CHAR,  encoding='utf-8')
conn.setdecoding(pyodbc.SQL_WCHAR, encoding='utf-8')
```

(PG reference sample unconditionally applies this setting to both DBs.)

### Trap — Altibase rejects host variable if placed in `SELECT` list (2026-09-30)

When executing session preload (`Ensure CDS Session In PDB`) in Altibase (DB2), the following occurred.

```
('HY000', "[HY000] Invalid use of host variables \n0001 : INSERT INTO T_SMF_SESSION_INFO (...)
SELECT ?, ?, 2, ?, ?, ?, '5g.sktelecom.com', ... FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM T_SMF_SESSION_INFO WHERE SM_POLICY_ID = ?)")
```

Cause: `session_insert_sql()` previously guaranteed idempotency in a single
`INSERT INTO ... SELECT ?, ?, ... FROM DUAL WHERE NOT EXISTS (...)` statement,
so the same `SM_POLICY_ID` would not be inserted twice. A bind parameter is valid
when compared with a real column, such as `WHERE SM_POLICY_ID = ?`, as in the
other bindings in this repository. In a columnless `SELECT ?, ?, ... FROM DUAL`,
however, the compiler cannot infer parameter types. Goldilocks accepts this form;
Altibase rejects it during compilation.

`_try_setinputsizes` (the client informs the driver of the type in advance and calls `SQLDescribeParam`)
This cannot be fixed using an avoidance device (see the section above) — this is because the server (Altibase) refuses to compile SQL.
Client hint does not reach.

 response: Idempotent judgment was moved outside of SQL (Robot keyword). `session_insert_sql()` is now
Create only plain `INSERT INTO ... VALUES (...)` without `WHERE NOT EXISTS` (all `?`
Type inference is clear as it is paired with the INSERT target column by position), `cds_keywords.robot`
Before `Insert CDS Session Row` is executed, `SELECT COUNT(*) ... WHERE SM_POLICY_ID = ?`
First, check its existence and INSERT only when it is not present.

### Trap — Same HY000, but different cause (2026-08-18)

The above symptoms recurred without any difference. However, the cause was neither binding nor encoding.
Even `SELECT 1`, which does not use `?`, dies with the same error as  — that is, not a single statement is executed.
It was in bad condition, and no matter how much I tried to fix the binding, it wouldn't have been fixed.

The real message came out as  when we removed `CHARSET=` from the connection string.

```
('HY000', '[SUNJESOFT][ODBC][GOLDILOCKS]failed to open library
          (libgoldilockscvtUHC_64.so)\n (11087) (SQLExecDirectW)')
```

★ If you have `CHARSET=`, Goldilocks swallows the diagnostic records. This is the crux of this trap —
If you encounter "HY000 without diagnosis",  first remove `CHARSET=` and turn once. then
The driver will tell you the real cause. For the 2026-08-06 case, the cause may not have been found for the same reason.

The cause was the environment. The driver body is loaded with the absolute path of `DRIVER=`,
The  character set conversion library must be on the search path because it becomes `dlopen` by name alone at runtime.

```
LD_LIBRARY_PATH = /opt/gcc-8.3.0/lib64:/lib: ← $GOLDILOCKS_HOME/lib does not exist
GOLDILOCKS_HOME = (not set)
```

So,  connections (`pyodbc.connect`) and `getinfo` succeed, but only the SELECT fails.
Just because it's connected doesn't mean it can be viewed — separate the two when diagnosing.

Action:

```bash
export GOLDILOCKS_HOME=/PG/goldilocks_home
export LD_LIBRARY_PATH=$GOLDILOCKS_HOME/lib:$LD_LIBRARY_PATH
```

`run_tests.sh` has already been set (if it is already set, it is not touched).
If you call `robot` directly, you must first export it from the shell.
Entering `os.environ` in Python is useless — glibc is
Since `LD_LIBRARY_PATH` is read, it must be  before launching robot.

#### Order of determining cause

| inspection | If you fail |
|---|---|
| `pyodbc.connect` | Host·Port·Account·Driver File Path |
| `getinfo(SQL_DBMS_NAME)` | Same as above (connection is normal up to this point) |
| `SELECT 1 FROM DUAL` | Environment — Transformation library, `LD_LIBRARY_PATH` |
| `SELECT COUNT(*) FROM <table>` (without parameters) | Table·Permission·Schema |
| `... WHERE MDN = ?` | Finally, binding (`SQLDescribeParam`) |

If we narrow it down one by one from the top, it turns out that the last place to question the binding is.
Don't forget to compare one more connection minus `CHARSET=`.

### Trap — `autocommit=False` can neutralize rechecks

`autocommit` has  off (`${PDB_AUTOCOMMIT}` — old `${CDS_DB_AUTOCOMMIT}` — default `${FALSE}`, same as PG reference sample).
This helper only queries, so there is nothing to commit, but when  is turned off, `SELECT` also opens a transaction.
`Verify Subscriber Provisioned In PDB` rechecks for 30 seconds, and if you leave the transaction as is,
Re-query  is stuck in a snapshot of the first query and SDM never sees the rows reflected later — re-try is
completely neutralized.

So, `db_count` ends the transaction with `db_end_transaction(conn)` just before the inquiry.

```python
def db_end_transaction(conn):
    if conn is None or getattr(conn, 'autocommit', True):
        return            # If autocommit, there are no open transactions.
    conn.rollback()       # There are no changes to revert — the purpose is to open a new snapshot.
```

If you remove this rollback with autocommit turned off, the symptom is immediately reproduced.  Conversely, with `${TRUE}`
When turned on, rollback becomes a no-op and the result should be the same.
