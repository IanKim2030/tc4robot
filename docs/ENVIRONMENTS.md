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
resources/variables.robot        ← 공용 변수(상수·토글·공용 기본값). **환경값은 없다**
resources/<iface>_variables.robot ← 노드 변수. 공용 값은 참조만 한다
config/env/dev.py                ← dev 환경값(필수) + 덮을 수 있는 값의 카탈로그. git 에 있다
config/env/stg.py                ← (gitignore) stg 환경값(필수) + 기본값과 다른 값
config/env/prd.py                ← (gitignore) prd 환경값(필수) + 실행 가드
config/env/local.py              ← (gitignore) 개인 오버라이드, 선택
```

### 환경값은 환경 파일에만 둔다 (2026-11-03)

환경마다 달라지는 값 — **`PG_HOST` · `TOOL_HOST` · `PDB_CONNSTR` · `SUBS_MDN_LTE` /
`SUBS_MIN_LTE` / `SUBS_MDN_5G` / `SUBS_MIN_5G`** — 은 `resources/variables.robot` 에 기본값이 없다.
예전에는 dev 값이 기본값으로 있어서, stg/prd 환경 파일이 빠뜨린 키가 **dev 값으로 조용히
채워졌다**(prd 에서 dev DB·dev 번호로 도는 사고 자리). 지금은 빠뜨리면 그 변수를 쓰는 곳에서
`Variable '${...}' not found` 로 바로 실패한다. `PDB_CONNSTR` 만은 환경변수 `PG_PDB_CONNSTR`
로도 줄 수 있다.

`run_tests.sh` 는 **환경 인자가 없거나 IP 만 줘도 `config/env/dev.py` 를 읽는다**(2026-10-29).
`python -m robot tests/nag/` 처럼 직접 돌리면 환경 파일을 읽지 않으므로 **반드시**
`-V config/env/dev.py`(`--variablefile`) 를 붙인다 — 안 붙이면 위 변수가 없어 실패한다.

### 이름이 바뀐 변수 — 구 이름도 계속 먹는다

| 새 이름 (variables.robot) | 구 이름 (노드 변수) | 동작 |
|---|---|---|
| `${SBI_NOTI_PORT}` / `${SBI_NOTI_HOST}` | `${CDS_NOTI_PORT}` `${RTS_NOTI_PORT}` / `${CDS_NOTI_HOST}` `${RTS_NOTI_HOST}` | 노드 변수의 기본값이 새 이름이다. 구 이름으로 덮으면 그 노드만 바뀐다 |
| `${PDB_TIMEOUT}` / `${PDB_AUTOCOMMIT}` | `${CDS_DB_TIMEOUT}` / `${CDS_DB_AUTOCOMMIT}` | 위와 같다 |
| `${TOOL_HOST}` | (`cds_variables.robot` 의 `192.168.15.142` 리터럴) | `${CDS_SESSION_PCF_ADDR}`/`SMF_ADDR` 가 이 값으로 만들어진다 |
| `resources/PdbHelper.py` · `PdbError` | `CdsDbHelper.py` · `CdsDbError` | 예외는 별칭으로 남겼다. 파일 이름은 리포 안 import 를 전부 고쳤다 |
| 환경변수 `PG_PDB_CONNSTR` | `PG_CDS_DB_CONNSTR` | 폴백으로 계속 읽는다 |

## 변수 우선순위

```
--variable  >  --variablefile  >  슈트 *** Variables ***  >  임포트된 Resource
```

Robot 소스(`GlobalVariables._set_cli_variables`)가 variable file 을 먼저, `--variable` 을
나중에 적용한다. `*** Variables ***` 는 `overwrite=False` 로 처리돼 **이미 있는 이름을 덮지 않는다.**

→ 환경 파일(`--variablefile`)이 노드별 변수 파일과 슈트 내부 변수를 **모두 이긴다.**

## 환경 축 변수

이름은 `resources/variables.robot` 에 모여 있다(환경값은 위 규칙대로 값 없이 이름만 —
값은 환경 파일). 노드별 변수는 이를 참조만 하므로 **환경 파일에서 아래 하나만 바꾸면
관련 노드 전부에 전파된다.**

**여기 두는 기준은 "두 노드 이상이 공유하는 값"이다.** 한 노드만 쓰는 환경 값은
해당 `<iface>_variables.robot` 에 **값을 직접** 둔다 — 예로 CDS 가입자는
`${CDS_MDN}` / `${CDS_MIN}`(`cds_variables.robot`) 에 있다.
공유되지 않는 값을 축에 두면 이득 없는 간접 계층만 생긴다.
(환경 파일 오버라이드는 우선순위상 어느 파일에 있든 이기므로, 배치가 좌우하는 것은
**중복 위험뿐**이다.)

| 변수 | 전파 대상 |
|---|---|
| `${PG_HOST}` | `${NAG_PG_HOST}` `${PCF_PG_HOST}` `${UPM_PG_HOST}` `${NWDAF_HOST}` `${CDS_PG_HOST}` `${LRS_CLIENT_HOST}` |
| `${TOOL_HOST}` | `${CDS_SESSION_PCF_ADDR}` `${CDS_SESSION_SMF_ADDR}` ([shared/SBI_NOTI.md](shared/SBI_NOTI.md)) |
| `${SBI_NOTI_PORT}` / `${SBI_NOTI_HOST}` | `${CDS_NOTI_PORT}` `${RTS_NOTI_PORT}` / `${CDS_NOTI_HOST}` `${RTS_NOTI_HOST}` |
| `${PDB_TIMEOUT}` / `${PDB_AUTOCOMMIT}` | `${CDS_DB_TIMEOUT}` / `${CDS_DB_AUTOCOMMIT}` ([shared/PDB.md](shared/PDB.md)) |
| `${SUBS_MDN_LTE}` | `${NAG_MDN}` `${PCF_MDN}` `${LRS_MDN}`(아래 노드별 대상 번호의 기본값) `${NWDAF_MDN}` |
| `${SUBS_MIN_LTE}` | `${NWDAF_MIN}` |
| `${SUBS_MDN_5G}` / `${SUBS_MIN_5G}` | `${LRS_MDN_5G}` `${NWDAF_MDN_5G}` `${NWDAF_MIN_5G}` |
| `${SUBS_MDN_NO_HFC}` | `${NAG_MDN_NO_HFC}` `${LRS_MDN_NO_SESSION}` |
| `${SUBS_MDN_NO_SESSION}` | `${NAG_MDN_NO_SESSION}` |
| `${SUBS_APN_LTE}` / `${SUBS_APN_5G}` | `${NAG_APN}` `${LRS_APN_LTE}` `${LRS_APN_5G}` |
| `${SUBS_MOBILE_IP}` | `${NAG_MOBILE_IP}` `${LRS_SI_CLIENT_IP}` |
| `${NET_CELL_ID}` / `${NET_PGW_IP}` | `${NWDAF_CELL_ID}` `${NWDAF_PGW_IP}` |
| `${NET_SI_FROM_IP}` | `${LRS_SI_FROM_IP}` — **PG 에 등록된 IP 여야 함** (아니면 403) |

### 노드별 대상 번호 (MDN)

노드마다 시험 가입자를 따로 쓸 수 있게 **노드별 MDN 변수**가 있다. 환경 파일에서 이 이름으로
덮는다 — dev 는 `config/env/dev.py` 의 "노드별 대상 번호" 절에 모여 있다.

| 노드 | 환경 파일 이름 | 기본값 | 실제로 쓰는 변수 |
|---|---|---|---|
| NAG | `NAG_MDN` | `${SUBS_MDN_LTE}` | `${NAG_MDN_NORMAL}` |
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
# ── 필수 (variables.robot 에 기본값 없음) ──
PG_HOST      = '10.20.30.40'
TOOL_HOST    = '10.20.30.50'    # 도구 호스트 — PG 가 되돌아 접속하는 주소
PDB_CONNSTR  = 'DSN=PDB;UID=pgtest;PWD=...'   # 또는 환경변수 PG_PDB_CONNSTR
SUBS_MDN_LTE = '01011112222'    # NAG/PCF/LRS/NWDAF 에 자동 전파
SUBS_MIN_LTE = '1011112222'
SUBS_MDN_5G  = '01011113333'
SUBS_MIN_5G  = '1011113333'

# ── 선택 ──
CDS_MDN      = '01090020001'    # 노드별 대상 번호는 개별 지정

CDS_DST_SYS_ID = 'PG02'         # 노드별 개별 지정
NAG_PG_PORT    = 8012
```

Robot 은 변수 파일의 **모듈 전역 이름을 그대로 변수로 읽는다.** `PG_HOST = ...` 가
`${PG_HOST}` 가 된다. 언더스코어로 시작하는 이름은 무시된다.

## PDB 접속 · 실행 전 DB 설정 시드

[shared/PDB.md](shared/PDB.md) 로 옮겼다 — 접속 문자열(`PDB_CONNSTR`, 환경변수 `PG_PDB_CONNSTR`),
두 번째 DB, 골디락스/알티베이스 함정, `config/db_seed/<env>.sql` 형식과 시드 옵션이 거기 있다.
시드 INSERT 뒤 PG 원격 명령(`stopMP app` → `startMP app`)은 [shared/SSH.md](shared/SSH.md).

## prd 가드

`config/env/prd.py` 는 환경변수 없이는 실행을 거부한다.

```bash
export PG_ALLOW_PRD=1              # PowerShell: $env:PG_ALLOW_PRD='1'
bash run_tests.sh smoke prd
```

특히 **NWDAF Notification 은 PG 가 응답을 주지 않아 실수를 되돌릴 수 없다.**
prd 실행 전에 대상 가입자와 `--include` 태그를 반드시 확인할 것.

## 새 환경 추가

1. `config/env/<name>.py` 생성 — 필수 환경값(위 "환경값은 환경 파일에만 둔다") + 기본값과 다른 값
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
