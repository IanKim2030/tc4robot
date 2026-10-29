# ENVIRONMENTS — 환경 설정 (dev / stg / prd)

## 실행

```bash
bash run_tests.sh nag              # dev (기본) — config/env/dev.py 를 읽는다
bash run_tests.sh nag stg          # stg
bash run_tests.sh all prd          # prd — PG_ALLOW_PRD=1 필요
bash run_tests.sh all 192.168.1.1  # IP 만 바꾸기 (dev.py + PG_HOST 오버라이드)

# run_tests.sh 우회
python -m robot --variablefile config/env/stg.py tests/nag/
```

배너의 `ENV:` 줄로 어느 환경이 적용됐는지 확인한다.

## 구조

```
resources/variables.robot        ← dev 기준 기본값의 단일 출처
resources/<iface>_variables.robot ← 위 값을 참조만 한다
config/env/dev.py                ← dev 실제 값(노드별 MDN·PDB·UPM FTP 등) + 덮을 수 있는 값의 카탈로그. git 에 있다
config/env/stg.py                ← (gitignore) dev 와 다른 값만
config/env/prd.py                ← (gitignore) dev 와 다른 값만 + 실행 가드
config/env/local.py              ← (gitignore) 개인 오버라이드, 선택
```

`run_tests.sh` 는 **환경 인자가 없거나 IP 만 줘도 `config/env/dev.py` 를 읽는다**(2026-10-29 —
예전에는 인자 없이 돌리면 dev.py 를 건너뛰어 dev.py 의 값이 무시됐다).
`python -m robot tests/nag/` 처럼 직접 돌리면 dev.py 를 읽지 않으므로
`--variablefile config/env/dev.py` 를 붙인다.

## 변수 우선순위

```
--variable  >  --variablefile  >  슈트 *** Variables ***  >  임포트된 Resource
```

Robot 소스(`GlobalVariables._set_cli_variables`)가 variable file 을 먼저, `--variable` 을
나중에 적용한다. `*** Variables ***` 는 `overwrite=False` 로 처리돼 **이미 있는 이름을 덮지 않는다.**

→ 환경 파일(`--variablefile`)이 노드별 변수 파일과 슈트 내부 변수를 **모두 이긴다.**

## 환경 축 변수

`resources/variables.robot` 에 모여 있다. 노드별 변수는 이를 참조만 하므로
**환경 파일에서 아래 하나만 바꾸면 관련 노드 전부에 전파된다.**

**여기 두는 기준은 "두 노드 이상이 공유하는 값"이다.** 한 노드만 쓰는 환경 값은
해당 `<iface>_variables.robot` 에 **값을 직접** 둔다 — 예로 CDS 가입자는
`${CDS_MDN}` / `${CDS_MIN}`(`cds_variables.robot`) 에 있다.
공유되지 않는 값을 축에 두면 이득 없는 간접 계층만 생긴다.
(환경 파일 오버라이드는 우선순위상 어느 파일에 있든 이기므로, 배치가 좌우하는 것은
**중복 위험뿐**이다.)

| 변수 | 전파 대상 |
|---|---|
| `${PG_HOST}` | `${NAG_PG_HOST}` `${PCF_PG_HOST}` `${UPM_PG_HOST}` `${NWDAF_HOST}` `${CDS_PG_HOST}` `${LRS_CLIENT_HOST}` |
| `${SUBS_MDN_LTE}` | `${NAG_MDN}` `${PCF_MDN}` `${LRS_MDN}`(아래 노드별 대상 번호의 기본값) `${NWDAF_TEST_MDN}` |
| `${SUBS_MIN_LTE}` | `${NWDAF_TEST_MIN}` |
| `${SUBS_MDN_5G}` / `${SUBS_MIN_5G}` | `${LRS_MDN_5G}` `${NWDAF_TEST_MDN_5G}` `${NWDAF_TEST_MIN_5G}` |
| `${SUBS_MDN_NO_HFC}` | `${TEST_MDN_NO_SS}` `${LRS_MDN_NO_SESSION}` |
| `${SUBS_MDN_NO_SESSION}` | `${TEST_MDN_NO_SESSION}` |
| `${SUBS_APN_LTE}` / `${SUBS_APN_5G}` | `${TEST_APN}` `${LRS_APN_LTE}` `${LRS_APN_5G}` |
| `${SUBS_MOBILE_IP}` | `${TEST_MOBILE_IP}` `${LRS_SI_CLIENT_IP}` |
| `${NET_CELL_ID}` / `${NET_PGW_IP}` | `${NWDAF_TEST_CELL_ID}` `${NWDAF_TEST_PGW_IP}` |
| `${NET_SI_FROM_IP}` | `${LRS_SI_FROM_IP}` — **PG 에 등록된 IP 여야 함** (아니면 403) |

### 노드별 대상 번호 (MDN)

노드마다 시험 가입자를 따로 쓸 수 있게 **노드별 MDN 변수**가 있다. 환경 파일에서 이 이름으로
덮는다 — dev 는 `config/env/dev.py` 의 "노드별 대상 번호" 절에 모여 있다.

| 노드 | 환경 파일 이름 | 기본값 | 실제로 쓰는 변수 |
|---|---|---|---|
| NAG | `NAG_MDN` | `${SUBS_MDN_LTE}` | `${TEST_MDN_NORMAL}` |
| PCF | `PCF_MDN` | `${SUBS_MDN_LTE}` | `${PCF_TEST_MDN}` |
| LRS | `LRS_MDN` | `${SUBS_MDN_LTE}` | `${LRS_SI_MDN}` `${LRS_MDN_LTE}` |
| CDS | `CDS_MDN` / `CDS_NEW_MDN` | `01090010001` / `01090010002` | 그대로 |
| RTS | `RTS_MDN` | `01090010001` | `${RTS_TEST_MDN}` |

dev.py 는 CDS 의 `CDS_MIN` / `CDS_NEW_MIN`(MDN 앞 0 제거)과 세션 IMSI(`45005` + MIN)를
MDN 에서 계산한다 — MDN 만 바꾸면 따라온다. 다른 환경 파일도 같은 식으로 쓰면 된다.

노드 식별자(`*_SYS_ID` / `*_BRANCH_NAME`)와 포트는 노드마다 값이 달라 통합하지 않았다.
필요하면 환경 파일에서 **노드별로 직접 지정**한다.

## 환경 파일 작성

`config/env/dev.py` 가 덮을 수 있는 값의 전체 카탈로그다. 주석을 풀고 값만 넣으면 된다.

```python
# config/env/stg.py
PG_HOST = '10.20.30.40'

SUBS_MDN_LTE = '01011112222'    # NAG/PCF/LRS/NWDAF 에 자동 전파
SUBS_MIN_LTE = '1011112222'
CDS_MDN      = '01090020001'    # 노드별 대상 번호는 개별 지정

CDS_DST_SYS_ID = 'PG02'         # 노드별 개별 지정
NAG_PG_PORT    = 8012
```

Robot 은 변수 파일의 **모듈 전역 이름을 그대로 변수로 읽는다.** `PG_HOST = ...` 가
`${PG_HOST}` 가 된다. 언더스코어로 시작하는 이름은 무시된다.

## CDS PDB 접속 (TC-CDS-002 / TC-CDS-013)

`db` 태그가 붙은 두 TC 는 전문 흐름에 더해 **PDB 반영까지** 판정한다 —
`TC-CDS-002`(A1 신규가입)는 행이 생겼는지, `TC-CDS-013`(Z1 가입해지)는 행이
사라졌는지를 본다. 접속 문자열은 `variables.robot` 의 `${PDB_CONNSTR}` 하나뿐이다 — CDS·RTS 공용이다.

★ **CDS 슈트는 Suite Setup 에서 PDB 에 붙는다.** 그래서 이 값이 틀리면 이 두 TC 뿐
아니라 **전문 송수신 TC 까지 포함해 CDS 슈트 전체가 서지 않는다**(`--exclude db`
로도 피할 수 없다 — Suite Setup 은 태그와 무관하게 실행된다).

**완성된 ODBC 접속 문자열을 통째로 준다.** 도구는 조립하지 않는다 — 받은 값을 그대로
`pyodbc` 에 넘긴다. 골디락스는 `odbc.ini`(Linux) / ODBC 데이터 원본 관리자(Windows)에
DSN 을 등록해 두고 이름만 참조하는 것이 정석이다(드라이버 경로·호스트·포트·
`ALTERNATE_SERVERS` 를 DSN 이 갖는다).

```python
# config/env/stg.py
PDB_CONNSTR = 'DSN=PDB;UID=pgtest;PWD=...'
```

**세션 사전 적재를 두 DB 모두에 넣어야 하면 `PDB_CONNSTR_2` 도 채운다** — 환경에 따라
골디락스+알티베이스 이중화가 있는 경우와 DB 한 곳뿐인 경우가 섞여 있어서다. 비워
두면(기본) 기존처럼 DB 한 곳에만 넣는다. 반영 판정(SELECT)은 항상 `PDB_CONNSTR`
(첫 번째 DB) 기준이다. 레거시 환경변수 폴백은 없다 — 새로 쓸 때는 `PG_PDB_CONNSTR_2`.
상세는 `docs/nodes/CDS.md` "두 번째 DB" 절.

```python
# config/env/stg.py — stg 가 골디락스+알티베이스 이중화라면
PDB_CONNSTR   = 'DSN=GOLD_PDB;UID=pgtest;PWD=...'
PDB_CONNSTR_2 = 'Server=...;PORT=...;DBName=...;UID=pgtest;PWD=...'
```

DSN 없이 직접 쓸 수도 있다. 다만 `.so` **경로에 중괄호를 붙이면 안 되고** 호스트 키는
`SERVER` 가 아니라 `HOST` 다 — 둘 다 골디락스 실측이다.

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

어느 쪽이든 **Python 이 직접 읽는다**(Robot 키워드 인자로 넘기지 않는다) — 그래서
`log.html` 에는 마스킹된 문자열(`PWD=****`)만 남는다.

골디락스 DSN-less 가 `IM012 DRIVER keyword syntax error` 로 거부된 이력은
[nodes/CDS.md](nodes/CDS.md) 의 PDB 조회 절에 있다.

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
- 값은 리터럴로 쓴다(바인드 파라미터 없음). 표 이름에 `PDB.` 접두사를 붙이지 않는다.
- 블록이 하나도 없으면 DB 에 접속하지 않는다 — DB 를 안 쓰는 환경도 그대로 돈다.
- 접속은 본 실행과 같은 `${PDB_CONNSTR}` 이다(같은 `--variablefile`/`--variable` 을 넘긴다).
  `${PDB_CONNSTR_2}` 가 있으면 두 번째 DB 에도 같은 확인·INSERT·UPDATE 를 한다.
- **시드가 실패하면 본 실행을 하지 않는다.** 로그는 `results/<TS>/db_seed/log.html`.

```bash
bash run_tests.sh nag --no-db-seed      # 시드 단계 생략
bash run_tests.sh nag --db-seed-check   # 확인만 — 없으면 WARN, INSERT/UPDATE 안 함
python -m robot setup/db_seed.robot     # robot 을 직접 돌릴 때는 먼저 수동으로 (기본 dev.sql)
python -m robot --variablefile config/env/stg.py \
    --variable DB_SEED_FILE:config/db_seed/stg.sql setup/db_seed.robot   # stg
```

## prd 가드

`config/env/prd.py` 는 환경변수 없이는 실행을 거부한다.

```bash
export PG_ALLOW_PRD=1              # PowerShell: $env:PG_ALLOW_PRD='1'
bash run_tests.sh smoke prd
```

특히 **NWDAF Notification 은 PG 가 응답을 주지 않아 실수를 되돌릴 수 없다.**
prd 실행 전에 대상 가입자와 `--include` 태그를 반드시 확인할 것.

## 새 환경 추가

1. `config/env/<name>.py` 생성 — dev 와 다른 값만
2. `run_tests.sh` 의 `case` 에 `<name>` 추가
3. 이 문서에 한 줄 추가

## 개인 오버라이드

`config/env/local.py` 는 `.gitignore` 되어 있다. 각자 다른 IP 로 돌릴 때 쓴다.

```bash
bash run_tests.sh nag local
```

## 자격증명

**SSH 로 PG 설정을 읽던 `DynamicVars` 는 제거됐다.** 따라서 SSH 계정·비밀번호가 필요 없다.

제거 근거 — 실측 cfg 값이 하드코딩 기본값과 전부 같아 **동작 차이가 없었다**:

| cfg | 키 | 실측 | 기본값 |
|---|---|---|---|
| `PG_V2.cfg [CDS]` | `O_PORT` | 9200 | 9200 |
| `PG_V2.cfg [CDS]` | `R_PORT` | 9201 | 9201 |
| `BarodNoti.cfg [Barod.IF]` | `Barod.IF.Port.NAG` | 8012 | 8012 |

게다가 코드는 `S_PORT` 를 조회했는데 실제 키는 `O_PORT` 라, Schannel 은 **애초에 조회에
실패해 폴백만 타고 있었다.** 폴백 값이 실제 값과 같아 아무도 눈치채지 못한 상태였다.

> ⚠ 이전에 `resources/variables.robot` 에 SSH 비밀번호가 평문으로 커밋돼 있었다.
> 파일에서는 제거했지만 **git 히스토리에는 남아 있다.** 실제로 쓰이는 계정이면
> **비밀번호 자체를 교체**해야 한다.
