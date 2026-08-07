# ENVIRONMENTS — 환경 설정 (dev / stg / prd)

## 실행

```bash
bash run_tests.sh nag              # dev (기본)
bash run_tests.sh nag stg          # stg
bash run_tests.sh all prd          # prd — PG_ALLOW_PRD=1 필요
bash run_tests.sh all 192.168.1.1  # IP 만 바꾸기 (PG_HOST 오버라이드)

# run_tests.sh 우회
python -m robot --variablefile config/env/stg.py tests/nag/
```

배너의 `ENV:` 줄로 어느 환경이 적용됐는지 확인한다.

## 구조

```
resources/variables.robot        ← dev 기준 기본값의 단일 출처
resources/<iface>_variables.robot ← 위 값을 참조만 한다
config/env/dev.py                ← 비어 있음. 덮을 수 있는 값의 카탈로그
config/env/stg.py                ← dev 와 다른 값만
config/env/prd.py                ← dev 와 다른 값만 + 실행 가드
config/env/local.py              ← (gitignore) 개인 오버라이드, 선택
```

`resources/variables.robot` 이 dev 값을 갖고 있으므로 **인자 없이 실행하면 dev 로 동작한다.**
`python -m robot tests/nag/` 같은 기존 사용법이 그대로 유효하다.

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
| `${SUBS_MDN_LTE}` | `${TEST_MDN_NORMAL}`(NAG) `${PCF_TEST_MDN}` `${LRS_SI_MDN}` `${LRS_MDN_LTE}` `${NWDAF_TEST_MDN}` |
| `${SUBS_MIN_LTE}` | `${NWDAF_TEST_MIN}` |
| `${SUBS_MDN_5G}` / `${SUBS_MIN_5G}` | `${LRS_MDN_5G}` `${NWDAF_TEST_MDN_5G}` `${NWDAF_TEST_MIN_5G}` |
| `${SUBS_MDN_NO_HFC}` | `${TEST_MDN_NO_SS}` `${LRS_MDN_NO_SESSION}` |
| `${SUBS_MDN_NO_SESSION}` | `${TEST_MDN_NO_SESSION}` |
| `${SUBS_APN_LTE}` / `${SUBS_APN_5G}` | `${TEST_APN}` `${LRS_APN_LTE}` `${LRS_APN_5G}` |
| `${SUBS_MOBILE_IP}` | `${TEST_MOBILE_IP}` `${LRS_SI_CLIENT_IP}` |
| `${NET_CELL_ID}` / `${NET_PGW_IP}` | `${NWDAF_TEST_CELL_ID}` `${NWDAF_TEST_PGW_IP}` |
| `${NET_SI_FROM_IP}` | `${LRS_SI_FROM_IP}` — **PG 에 등록된 IP 여야 함** (아니면 403) |

노드 식별자(`*_SYS_ID` / `*_BRANCH_NAME`)와 포트는 노드마다 값이 달라 통합하지 않았다.
필요하면 환경 파일에서 **노드별로 직접 지정**한다.

## 환경 파일 작성

`config/env/dev.py` 가 덮을 수 있는 값의 전체 카탈로그다. 주석을 풀고 값만 넣으면 된다.

```python
# config/env/stg.py
PG_HOST = '10.20.30.40'

SUBS_MDN_LTE = '01011112222'    # 노드 5곳에 자동 전파
SUBS_MIN_LTE = '1011112222'

CDS_DST_SYS_ID = 'PG02'         # 노드별 개별 지정
NAG_PG_PORT    = 8012
```

Robot 은 변수 파일의 **모듈 전역 이름을 그대로 변수로 읽는다.** `PG_HOST = ...` 가
`${PG_HOST}` 가 된다. 언더스코어로 시작하는 이름은 무시된다.

## CDS PDB 접속 (TC-CDS-002 / TC-CDS-012)

`db` 태그가 붙은 두 TC 는 전문 흐름에 더해 **PDB 반영까지** 판정한다 —
`TC-CDS-002`(A1 신규가입)는 행이 생겼는지, `TC-CDS-012`(Z1 가입해지)는 행이
사라졌는지를 본다. 접속 문자열은 `cds_variables.robot` 의 `${CDS_DB_CONNSTR}` 하나뿐이다.

★ **CDS 슈트는 Suite Setup 에서 PDB 에 붙는다.** 그래서 이 값이 틀리면 이 두 TC 뿐
아니라 **전문 송수신 TC 까지 포함해 CDS 슈트 전체가 서지 않는다**(`--exclude db`
로도 피할 수 없다 — Suite Setup 은 태그와 무관하게 실행된다).

**완성된 ODBC 접속 문자열을 통째로 준다.** 도구는 조립하지 않는다 — 받은 값을 그대로
`pyodbc` 에 넘긴다. 골디락스는 `odbc.ini`(Linux) / ODBC 데이터 원본 관리자(Windows)에
DSN 을 등록해 두고 이름만 참조하는 것이 정석이다(드라이버 경로·호스트·포트·
`ALTERNATE_SERVERS` 를 DSN 이 갖는다).

```python
# config/env/stg.py
CDS_DB_CONNSTR = 'DSN=PDB;UID=pgtest;PWD=...'
```

DSN 없이 직접 쓸 수도 있다. 다만 `.so` **경로에 중괄호를 붙이면 안 되고** 호스트 키는
`SERVER` 가 아니라 `HOST` 다 — 둘 다 골디락스 실측이다.

```python
CDS_DB_CONNSTR = ('DRIVER=/PG/goldilocks_home/lib/libgoldilockscs-ul64.so;'
                  'HOST=10.20.30.40;PORT=22581;UID=pgtest;PWD=...;CHARSET=UHC;')
```

**비밀번호가 이 문자열 안에 들어가므로 파일에 적지 않는 쪽이 낫다.** 환경변수가
Robot 변수보다 우선한다.

```bash
export PG_CDS_DB_CONNSTR='DSN=PDB;UID=pgtest;PWD=...'
# PowerShell: $env:PG_CDS_DB_CONNSTR='DSN=PDB;UID=pgtest;PWD=...'
```

어느 쪽이든 **Python 이 직접 읽는다**(Robot 키워드 인자로 넘기지 않는다) — 그래서
`log.html` 에는 마스킹된 문자열(`PWD=****`)만 남는다.

골디락스 DSN-less 가 `IM012 DRIVER keyword syntax error` 로 거부된 이력은
[nodes/CDS.md](nodes/CDS.md) 의 PDB 조회 절에 있다.

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
