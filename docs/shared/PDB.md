# PDB — DB 접속·조회 공통 (CDS · RTS · 시드)

PDB 는 PG 가 가입자·세션·설정을 두는 DB 다. 환경에 따라 **골디락스** 또는 **알티베이스**이고,
이중화 환경이면 둘 다다. 이 리포에서 PDB 에 붙는 곳은 셋이고 **헬퍼는 하나**다 —
[resources/PdbHelper.py](../../resources/PdbHelper.py) (ODBC / `pyodbc`, `DatabaseLibrary` 는 쓰지 않는다).

| 사용처 | 별칭 | 하는 일 | 상세 |
|---|---|---|---|
| CDS 슈트 | `CdsDb` | 반영 판정(SELECT), 세션 사전 적재(INSERT), 종료 시 정리(DELETE) | [nodes/CDS.md](../nodes/CDS.md#pdb-판정-기준-업무-코드별) |
| RTS 슈트 | `RtsDb` | 차단 반영 판정, 종료 시 정리 | [nodes/RTS.md](../nodes/RTS.md) |
| 실행 전 시드 | `SeedDb` | 설정 행 확인 → INSERT/UPDATE | 아래 [실행 전 DB 설정 시드](#실행-전-db-설정-시드-configdb_seedenvsql) |

## 변수

| 변수 | 기본값 | 설명 |
|---|---|---|
| `${PDB_CONNSTR}` | **없음 (환경 파일 필수)** | 완성된 ODBC 문자열. 환경변수 `PG_PDB_CONNSTR`(구 `PG_CDS_DB_CONNSTR`) 가 우선 |
| `${PDB_CONNSTR_2}` | 빈 값 | 두 번째 DB. 환경변수 `PG_PDB_CONNSTR_2`(레거시 폴백 없음) |
| `${PDB_TIMEOUT}` | `5` | 접속·쿼리 타임아웃(초). 구 이름 `${CDS_DB_TIMEOUT}` 으로 덮어도 먹는다 |
| `${PDB_AUTOCOMMIT}` | `${FALSE}` | 구 이름 `${CDS_DB_AUTOCOMMIT}`. 끄는 이유는 아래 [autocommit 함정](#함정--autocommitfalse-는-재조회를-무력화할-수-있다) |

정의는 [resources/variables.robot](../../resources/variables.robot), 값은 `config/env/<env>.py` 다.
어느 쪽이든 접속 문자열은 **Python 이 직접 읽는다**(Robot 키워드 인자로 넘기지 않는다) — 그래서
`log.html` 에는 마스킹된 문자열(`PWD=****`)만 남는다.

★ **CDS 슈트는 Suite Setup 에서 PDB 에 붙는다.** 접속 문자열이 틀리면 `db` 태그 TC 뿐
아니라 **전문 송수신 TC 까지 포함해 CDS 슈트 전체가 서지 않는다**(`--exclude db`
로도 피할 수 없다 — Suite Setup 은 태그와 무관하게 실행된다).

## 접속 문자열 — 조립하지 않는다

`${PDB_CONNSTR}` 에 완성된 ODBC 문자열을 넣으면 **그대로** `pyodbc` 로 간다.
DSN 을 `odbc.ini`(Linux) / ODBC 데이터 원본 관리자(Windows)에 등록해 두고 이름만
참조하는 것이 골디락스 정석이다.

```python
PDB_CONNSTR = 'DSN=GOLD_GLOBAL;UID=pdb;PWD=...'
```

`${CDS_DB_KIND}` `${CDS_DB_DSN}` `${CDS_DB_DRIVER}` `HOST`/`PORT`/`NAME`/`USER`/
`PASSWORD`/`EXTRA` 로 **조립하던 경로는 제거했다.** 조립 로직(`_KIND_SPEC`,
`build_conn_str`, `_fmt_driver`)도 함께 없앴다. 골디락스에서 DSN-less 조립이 거부됐고
(아래 절), 실환경 `odbc.ini` 에 문자열로 옮기기 번거로운 항목이 있어 결국 전부 DSN
등록 + 완성 문자열로 수렴했기 때문이다.

DB 마다 키워드 표기가 다르다는 사실 자체는 **여전히 유효하다** — 이제 문자열을 직접
쓰는 사람이 알아야 한다.

| 항목 | 골디락스 | 알티베이스 |
|---|---|---|
| 호스트 | `HOST` | `Server` |
| 포트 | `PORT` | `PORT` |
| DB 이름 | `DATABASE` | `DBName` |
| 계정 / 비밀번호 | `UID` / `PWD` | `UID` / `PWD` |

골디락스 값은 실환경 `odbc.ini` 실측(2026-08-06)이고 **알티베이스 값은 아직 미검증**이다.

DSN 없이 직접 쓸 수도 있다. 다만 `.so` **경로에 중괄호를 붙이면 안 되고** 호스트 키는
`SERVER` 가 아니라 `HOST` 다 — 둘 다 골디락스 실측이다(아래 IM012 함정).

```python
PDB_CONNSTR = ('DRIVER=/PG/goldilocks_home/lib/libgoldilockscs-ul64.so;'
               'HOST=10.20.30.40;PORT=22581;UID=pgtest;PWD=...;CHARSET=UHC;')
```

**비밀번호가 이 문자열 안에 들어가므로 파일에 적지 않는 쪽이 낫다.** 환경변수가
Robot 변수보다 우선한다.

```bash
export PG_PDB_CONNSTR='DSN=PDB;UID=pgtest;PWD=...'
# PowerShell: $env:PG_PDB_CONNSTR='DSN=PDB;UID=pgtest;PWD=...'
# 구 이름 PG_CDS_DB_CONNSTR 도 폴백으로 계속 읽는다.
```

## 두 번째 DB — `${PDB_CONNSTR_2}`

환경에 따라 골디락스·알티베이스를 **둘 다** 두고 세션 정보(`T_SMF_SESSION_INFO`)를
양쪽에 넣어야 하는 경우와, DB 한 곳만 있는 경우가 섞여 있다. `${PDB_CONNSTR_2}`
(환경변수 `PG_PDB_CONNSTR_2`, 레거시 폴백 없음)를 채우면 `Ensure CDS Session In PDB`
(세션 사전 적재)와 `Cleanup CDS Subscriber Rows`(아래 절, 종료 시 정리)가
`${CDS_DB_CONN}`(첫 번째)과 `${CDS_DB_CONN_2}`(두 번째) **양쪽에 같은 SQL** 을
실행한다. 비어 있으면(기본) 첫 번째 DB에만 적용한다 — 기존 동작 그대로다.

```python
# config/env/<env>.py
PDB_CONNSTR   = 'DSN=GOLD_GLOBAL;UID=pdb;PWD=...'        # 골디락스
PDB_CONNSTR_2 = 'Server=...;PORT=...;DBName=...;UID=...;PWD=...'  # 알티베이스
```

★ **이중 적용 대상은 쓰기(INSERT/DELETE) 뿐이다.** 가입자 프로파일/서비스 반영 판정
(`Verify Subscriber Provisioned In PDB` 등 `SELECT` 계열)은 여전히 **첫 번째 DB만** 본다
— PG.SDM 이 어느 DB를 반영 대상으로 보는지는 하나로 고정돼 있다는 전제다.

★ **시드는 다르다** — `${PDB_CONNSTR_2}` 가 있으면 시드 파일의 **모든 블록**을 DB2 에도
적용한다. DB2 에 시드 대상 표가 없으면(예: `T_SESSION_INFO`) 시드가 `42S02 Table not found`
로 실패한다. CDS 의 세션 테이블만 DB 별로 끄는 토글은 [nodes/CDS.md](../nodes/CDS.md)
"세션 테이블만 DB 별로 따로 끄기" 절이다.

## 실행 전 DB 설정 시드 (`config/db_seed/<env>.sql`)

`run_tests.sh` 는 대상(nag/…/all/smoke)과 무관하게 **본 실행 전에** `setup/db_seed.robot`
을 따로 한 번 돌린다. PG 가 읽는 설정 행이 없으면 넣고 시작하기 위한 단계다. 노드와는
무관하고 **환경별로 파일이 따로 있다.**

| 실행 | 시드 파일 |
|---|---|
| `bash run_tests.sh nag` / `nag dev` / `nag 192.168.1.1` | `config/db_seed/dev.sql` |
| `bash run_tests.sh nag stg` | `config/db_seed/stg.sql` |
| `prd` / `local` | `config/db_seed/<env>.sql` — 없으면 DB 접속 없이 건너뜀 |

```sql
-- @name: 블록 이름 (선택)
SELECT COUNT(*) FROM T_XXX_CFG WHERE KEY_COL = 'A';     -- 블록을 연다 (1행 1열 정수)
INSERT INTO T_XXX_CFG (KEY_COL, VAL) VALUES ('A', '1'); -- 위 결과가 0건일 때만 실행
UPDATE T_XXX_CFG SET VAL = '1' WHERE KEY_COL = 'A';     -- 위 결과가 1건 이상일 때만 실행
```

- SELECT 로 시작하는 문장이 블록을 열고, 다음 SELECT 전까지의 INSERT / UPDATE 가 그
  블록에 속한다. 여러 줄에 걸쳐 써도 된다(문장은 `;` 로만 나뉜다). 그 밖의 문장은 거부한다.

  | 확인 SELECT | 실행 | 실행 후 |
  |---|---|---|
  | 0건 | INSERT 만 | 같은 SELECT 로 다시 세어 1건 이상인지 (아니면 FAIL) |
  | 1건 이상 | UPDATE 만 (없으면 "있음" 으로 건너뜀) | 영향 행 0 이면 WARN |

  INSERT 만 있으면 "없으면 넣기", UPDATE 만 있으면 "있으면 고치기", 둘 다 있으면 upsert 다.
  UPDATE 는 매 실행마다 값을 덮어쓴다 — TC 가 바꿔 둔 값도 시작 전에 되돌린다.
- 실행한 INSERT/UPDATE 는 문장마다 콘솔에 대상 표·영향 행 수가, `log.html` 에 전체 SQL 이
  남는다. 끝에 DB 별 요약(있음/INSERT/UPDATE 블록 수)을 찍는다.
- 바인드 파라미터(`?`)는 없다. 값은 리터럴 또는 **`${변수}`** 로 쓴다 — 실행 시 환경 파일 값으로
  바뀐다(`'${CDS_MDN}'`, `'82${CDS_MIN}'`, `'http://${TOOL_HOST}:${SBI_NOTI_PORT}/...'`).
  그래서 번호·주소를 바꿀 때 `config/env/<env>.py` 만 고치면 된다. 글자 그대로 끼워 넣으므로
  따옴표는 직접 쓰고, 값에 `'` 가 들어가면 SQL 이 깨진다. 이름은 `${영문·숫자·_}` 만 받는다.
  **없는 변수는 줄 번호와 함께 실패한다**(빈 값으로 넣지 않는다). 주석 안의 `${...}` 는 그대로다.
- 표 이름에 `PDB.` 접두사를 붙이지 않는다.
- 블록이 하나도 없으면 DB 에 접속하지 않는다 — DB 를 안 쓰는 환경도 그대로 돈다.
- 접속은 본 실행과 같은 `${PDB_CONNSTR}` 이다(같은 `--variablefile`/`--variable` 을 넘긴다).
  `${PDB_CONNSTR_2}` 가 있으면 두 번째 DB 에도 같은 확인·INSERT·UPDATE 를 한다.
- **시드가 실패하면 본 실행을 하지 않는다.** 로그는 `results/<TS>/db_seed/log.html`.

```bash
bash run_tests.sh nag --no-db-seed      # 시드 단계 생략
bash run_tests.sh nag --db-seed-check   # 확인만 — 없으면 WARN, INSERT/UPDATE 안 함
bash run_tests.sh nag --no-db-seed-ssh  # INSERT 후 원격 명령 생략
python -m robot -V config/env/dev.py setup/db_seed.robot   # 직접 돌릴 때는 먼저 수동으로 (기본 dev.sql)
python -m robot --variablefile config/env/stg.py \
    --variable DB_SEED_FILE:config/db_seed/stg.sql setup/db_seed.robot   # stg
```

INSERT 가 한 블록이라도 있었으면 PG 서버에 SSH 로 후속 명령(`stopMP app` → `startMP app`)을
보낸다 — [SSH.md](SSH.md#시드-insert-후-원격-명령).

## 함정

### 함정 — 골디락스 DSN-less 는 `IM012` 로 거부됐다

```
DRIVER={/PG/goldilocks_home/lib/libgoldilockscs-ul64.so};SERVER=...;PORT=22581;...
→ IM012 [SUNJESOFT][ODBC][GOLDILOCKS]DRIVER keyword syntax error (19043)
```

두 가지가 겹쳐 있었다. **DSN 없이 문자열을 직접 쓸 때 그대로 적용된다.**

1. **`.so` 경로에 중괄호를 붙이면 안 된다.** ODBC 표준은 `DRIVER={이름}` 이지만 GOLDILOCKS
   드라이버 매니저가 이를 거부한다. 경로는 맨몸으로 쓰고, 드라이버 '이름'일 때만 감싼다
   (이름에는 공백이 흔해 중괄호가 필요하다).
2. **호스트 키워드가 `SERVER` 가 아니라 `HOST`** 다 (`odbc.ini` 실측).

둘을 알고도 **골디락스는 DSN 등록이 정석**이다. 실환경 `odbc.ini` 에
`ALTERNATE_SERVERS`(186~188 폴백) · `LOCALITY_AWARE_TRANSACTION` · `LOCATOR_DSN` 이
들어 있어 접속 문자열로 그대로 옮기기 번거롭기 때문이다. 스탠자 전문은
`cds_variables.robot` 의 PDB 절 주석에 남겨 뒀다. 조립 경로를 지우고 완성 문자열
하나만 남긴 것도 이 결론의 연장이다.

### 함정 — `?` 바인딩이 진단 없이 죽는다

접속이 붙은 뒤 조회에서 다음이 나왔다(골디락스, 2026-08-06).

```
('HY000', 'The driver did not supply an error!')
sql=SELECT COUNT(*) FROM T_5G_SUBS_PROFILE WHERE MDN = ?  params=('01090010001',)
```

**주 원인은 문자 인코딩이다.** 골디락스·알티베이스 ODBC 드라이버는 유니코드
(`SQL_WVARCHAR`) 바인딩을 지원하지 않는 경우가 있는데, pyodbc 는 기본적으로 문자열을
와이드로 보낸다. 두 번째 요인은 바인딩 자체다 — pyodbc 는 `?` 를 바인딩할 때
`SQLDescribeParam` 으로 파라미터 타입을 묻는데, 이를 구현하지 않은 드라이버에서는
역시 진단 없이 SQL_ERROR 만 돌아온다.

**현재 대응은 접속 문자열의 `CHARSET=` + `?` 바인딩 고정이다.**

| 요인 | 예전 | 지금 |
|---|---|---|
| 문자 인코딩 | `${CDS_DB_ENCODING}`(기본 `utf-8`) → `conn.setencoding` / `setdecoding` | **`${PDB_CONNSTR}` 의 `CHARSET=`** (골디락스는 `UHC`). 변수·코드 모두 제거 |
| 파라미터 바인딩 | `${CDS_DB_BIND}` 로 `auto`/`param`/`literal` 선택, 리터럴 폴백 있음 | **`?` 고정**(`param` 상당). `setinputsizes` 로 `SQLDescribeParam` 회피. 모드 선택·리터럴 경로 제거 |

★ **둘은 같은 것이 아니다.** `CHARSET=` 은 **드라이버**가 서버와 주고받는 문자셋이고,
`setencoding` 은 **pyodbc** 가 Python `str` 을 어느 SQL 타입으로 바인딩하는지다.
`CHARSET=` 만으로 이 HY000 이 안 나는지는 **실환경에서 확인해야 한다** — 리터럴 폴백이
없으므로 재발하면 조회가 그대로 실패한다. 그때 pyodbc 쪽을 되살리려면 `db_connect` 의
`pyodbc.connect(...)` 직후에 세 줄을 넣으면 된다.

```python
conn.setencoding(encoding='utf-8')
conn.setdecoding(pyodbc.SQL_CHAR,  encoding='utf-8')
conn.setdecoding(pyodbc.SQL_WCHAR, encoding='utf-8')
```

(PG 참조 샘플은 두 DB 모두에 이 설정을 무조건 적용한다.)

### 함정 — 알티베이스는 host variable 을 `SELECT` 목록에 놓으면 거부한다 (2026-09-30)

세션 사전 적재(`Ensure CDS Session In PDB`)를 알티베이스(DB2)에 실행하면 다음이 났다.

```
('HY000', "[HY000] Invalid use of host variables \n0001 : INSERT INTO T_SMF_SESSION_INFO (...)
SELECT ?, ?, 2, ?, ?, ?, '5g.sktelecom.com', ... FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM T_SMF_SESSION_INFO WHERE SM_POLICY_ID = ?)")
```

**원인**: 예전 `session_insert_sql()`은 `INSERT INTO ... SELECT ?, ?, ... FROM DUAL
WHERE NOT EXISTS (...)` 한 문장으로 멱등(같은 `SM_POLICY_ID`면 0행)을 DB 안에서
보장했다. 바인드 파라미터(`?`, 알티베이스 용어로 host variable)가 `WHERE SM_POLICY_ID
= ?` 처럼 **실제 컬럼과 비교되는 자리**면 문제없지만(이 리포의 다른 모든 `?` 바인딩이
이 형태다), `SELECT ?, ?, ... FROM DUAL` 처럼 **컬럼 없는 `DUAL` 의 SELECT 목록에
바로 놓인 `?`**는 컴파일러가 타입을 정할 근거가 없다. 골디락스는 관대하게 받아주지만
알티베이스는 컴파일 단계에서 거부한다.

`_try_setinputsizes`(클라이언트가 드라이버에 타입을 미리 알려 `SQLDescribeParam` 호출을
피하는 장치, 위 절 참조)로는 못 고친다 — 이건 **서버(알티베이스)의 SQL 컴파일 거부**라
클라이언트 힌트가 닿지 않는다.

**대응**: 멱등 판단을 SQL 밖(Robot 키워드)으로 옮겼다. `session_insert_sql()`은 이제
`WHERE NOT EXISTS` 없는 평범한 `INSERT INTO ... VALUES (...)` 만 만들고(모든 `?` 가
INSERT 대상 컬럼과 위치대로 짝지어져 타입 추론이 명확하다), `cds_keywords.robot` 의
`Insert CDS Session Row` 가 실행 전에 `SELECT COUNT(*) ... WHERE SM_POLICY_ID = ?`
로 먼저 존재를 확인하고 없을 때만 INSERT 한다.

### 함정 — 같은 HY000 인데 원인이 다르다 (2026-08-18)

위 증상이 **글자 하나 다르지 않게** 재발했다. 그런데 원인은 바인딩도 인코딩도 아니었다.
**`?` 를 쓰지 않는 `SELECT 1` 조차 같은 에러로 죽었다** — 즉 문장이 하나도 실행되지 않는
상태였고, 바인딩을 아무리 손봐도 고쳐지지 않았을 것이다.

진짜 메시지는 접속 문자열에서 **`CHARSET=` 을 빼자** 나왔다.

```
('HY000', '[SUNJESOFT][ODBC][GOLDILOCKS]failed to open library
          (libgoldilockscvtUHC_64.so)\n (11087) (SQLExecDirectW)')
```

★ **`CHARSET=` 이 있으면 골디락스가 진단 레코드를 삼킨다.** 이게 이 함정의 핵심이다 —
"진단 없는 HY000" 을 만나면 **가장 먼저 `CHARSET=` 을 빼고 한 번 돌려 볼 것.** 그러면
드라이버가 진짜 원인을 말해 준다. 2026-08-06 건도 같은 이유로 원인이 안 보였을 수 있다.

원인은 환경이었다. 드라이버 본체는 `DRIVER=` 의 절대경로로 로드되지만,
**문자셋 변환 라이브러리는 런타임에 이름만으로 `dlopen`** 되므로 탐색 경로에 있어야 한다.

```
LD_LIBRARY_PATH = /opt/gcc-8.3.0/lib64:/lib:      ← $GOLDILOCKS_HOME/lib 이 없다
GOLDILOCKS_HOME = (설정 안 됨)
```

그래서 **접속(`pyodbc.connect`)과 `getinfo` 는 성공하는데 SELECT 만 전부 실패한다.**
접속이 됐다고 조회가 되는 것이 아니다 — 진단할 때 이 둘을 나눠 볼 것.

조치:

```bash
export GOLDILOCKS_HOME=/PG/goldilocks_home
export LD_LIBRARY_PATH=$GOLDILOCKS_HOME/lib:$LD_LIBRARY_PATH
```

`run_tests.sh` 가 이미 넣어 준다(이미 설정돼 있으면 건드리지 않는다).
**`robot` 을 직접 부르면 셸에서 먼저 export 해야 한다.**
Python 안에서 `os.environ` 으로 넣는 것은 소용없다 — glibc 가 프로세스 시작 시점에
`LD_LIBRARY_PATH` 를 읽어 두기 때문에 **robot 을 띄우기 전**이어야 한다.

#### 원인을 가르는 순서

| 검사 | 실패하면 |
|---|---|
| `pyodbc.connect` | 호스트·포트·계정·드라이버 파일 경로 |
| `getinfo(SQL_DBMS_NAME)` | 위와 같음 (여기까지 되면 접속은 정상이다) |
| `SELECT 1 FROM DUAL` | **환경** — 변환 라이브러리, `LD_LIBRARY_PATH` |
| `SELECT COUNT(*) FROM <표>` (파라미터 없이) | 테이블·권한·스키마 |
| `... WHERE MDN = ?` | 비로소 **바인딩** (`SQLDescribeParam`) |

위에서부터 하나씩 좁히면 바인딩을 의심할 자리가 마지막이라는 것이 드러난다.
`CHARSET=` 을 뺀 접속을 한 벌 더 두고 비교하는 것도 잊지 말 것.

### 함정 — `autocommit=False` 는 재조회를 무력화할 수 있다

`autocommit` 은 **꺼져 있다**(`${PDB_AUTOCOMMIT}` — 구 `${CDS_DB_AUTOCOMMIT}` — 기본 `${FALSE}`, PG 참조 샘플과 동일).
이 헬퍼는 조회만 하므로 커밋할 것이 없지만, **끈 상태에서는 `SELECT` 도 트랜잭션을 연다.**
`Verify Subscriber Provisioned In PDB` 는 30초간 재조회하는데, 그 트랜잭션을 그대로 두면
재조회가 **첫 조회의 스냅샷에 갇혀 SDM 이 나중에 반영한 행을 영영 못 본다** — 재시도가
통째로 무력화된다.

그래서 `db_count` 는 조회 직전마다 `db_end_transaction(conn)` 으로 트랜잭션을 끊는다.

```python
def db_end_transaction(conn):
    if conn is None or getattr(conn, 'autocommit', True):
        return            # autocommit 이면 열린 트랜잭션이 없다
    conn.rollback()       # 되돌릴 변경이 없다 — 새 스냅샷을 뜨는 것이 목적
```

**autocommit 을 끈 채 이 rollback 을 빼면 증상이 바로 재현된다.** 반대로 `${TRUE}` 로
켜면 rollback 은 no-op 이 되고 결과는 같아야 한다.
