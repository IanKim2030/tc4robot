*** Settings ***
Documentation
...    PG 연동 통합 테스트 공통 변수 (NAG / PCF / LRS / UPM / NWDAF 가 모두 공유)
...
...    인터페이스별 변수는 각각의 *_variables.robot 으로 분리되어 있음:
...      resources/nag_variables.robot    ← NAG 접속/메시지/응답코드 + NAG·PCF 공용 테스트 데이터
...      resources/pcf_variables.robot    ← PCF 접속/메시지 (NAG 변수 의존)
...      resources/lrs_variables.robot    ← LRS 서버 정보/메시지/RESULT_CODE/테스트 데이터
...      resources/upm_variables.robot    ← UPM 접속/메시지/code-type/테스트 데이터
...      resources/nwdaf_variables.robot  ← NWDAF 접속/TLV TAG/테스트 데이터
...
...    여기에는 모든 인터페이스가 공유하는 메시지 타입 상수만 둔다.

*** Variables ***

# ════════════════════════════════════════════
# 메시지 타입 상수 (헤더 Byte1) — NAG / PCF / LRS / UPM 공통
# ════════════════════════════════════════════
${MSG_HELLO_REQ}              ${1}     # 0x01
${MSG_HELLO_RESP}             ${2}     # 0x02
${MSG_PING_REQ}               ${3}     # 0x03
${MSG_PING_RESP}              ${4}     # 0x04

# ════════════════════════════════════════════
# 환경 축 — **환경값은 여기 두지 않는다. config/env/<env>.py 에만 있다.**
#
# 환경마다 달라지는 값(호스트/IP, DB 접속, 가입자 번호)은 환경 파일이 단일 출처다.
#   PG_HOST · TOOL_HOST · PDB_CONNSTR · SUBS_MDN_LTE/SUBS_MIN_LTE/SUBS_MDN_5G/SUBS_MIN_5G
# 여기에 기본값을 두면 그 값이 stg/prd 에도 조용히 흘러 들어간다 — 그래서 뺐다.
# 환경 파일에 없으면 그 변수를 쓰는 곳에서 "Variable not found" 로 바로 실패한다.
#
# run_tests.sh 는 항상 환경 파일을 넘긴다(인자 없으면 dev). robot 을 직접 돌릴 때는
#   python -m robot --variablefile config/env/dev.py tests/nag/
# 우선순위: --variable > --variablefile > 슈트 *** Variables *** > 임포트 Resource
#
# 노드별 변수(*_variables.robot)는 위 값을 **참조만** 한다 — 값을 중복 정의하지 말 것.
# ════════════════════════════════════════════

# ── 가입자 데이터 (환경 무관 — 존재하지 않는 번호) ──
${SUBS_MDN_NO_HFC}           00000000000       # HFC 미가입 → code 402
${SUBS_MDN_NO_SESSION}       99999999999       # 세션 없음 → code 403
# CDS 가입자는 CDS 슈트만 쓰므로 cds_variables.robot 의 ${CDS_MDN} 계열에 직접 있다.

# ── PDB 접속 (CDS · RTS · 시드 공용) ─────────
# ${PDB_CONNSTR} 은 환경값이라 여기 없다 — config/env/<env>.py 또는 환경변수
# PG_PDB_CONNSTR(구 이름 PG_CDS_DB_CONNSTR 폴백)로 준다. 둘 다 없으면 PdbHelper 가
# 어디에 채워야 하는지까지 담아 실패한다. 형식은 config/env/dev.py 참조.

# 두 번째 DB (선택, CDS 세션 사전 적재 전용) — 환경에 따라 골디락스+알티베이스
# 이중화라 세션 정보를 **두 DB 모두에** 넣어야 하는 경우가 있다. 비워 두면(기본)
# 기존과 같이 DB 한 곳에만 넣는다 — PdbHelper.has_second_db() 가 이 값으로 판정한다.
# 조회(SELECT, 반영 판정)는 항상 ${PDB_CONNSTR}(첫 번째 DB) 기준이다.
# 비밀번호를 파일에 남기지 않으려면 환경변수 PG_PDB_CONNSTR_2 를 쓴다(레거시 폴백 없음).
${PDB_CONNSTR_2}             ${EMPTY}

# 접속 공통 설정 — CDS · RTS 가 같이 쓴다. 구 이름 ${CDS_DB_TIMEOUT} / ${CDS_DB_AUTOCOMMIT}
# 으로 덮어도 계속 먹는다(Suite CDS Connect 가 구 이름을 먼저 보고 WARN 을 남긴다).
# autocommit 을 끄는 이유는 docs/shared/PDB.md "autocommit=False 는 재조회를 무력화할 수 있다".
${PDB_TIMEOUT}               5               # 접속·쿼리 타임아웃(초)
${PDB_AUTOCOMMIT}            ${FALSE}

# ── 실행 전 DB 설정 시드 (setup/db_seed.robot) ─
# run_tests.sh 가 본 실행 전에 한 번 돌린다 — 표·값은 config/db_seed/<env>.sql 에 쓴다.
# run_tests.sh 는 환경 인자로 파일을 골라 --variable 로 덮는다(IP 지정은 dev).
# 아래 기본값(dev)은 robot 을 직접 돌릴 때만 쓰인다.
#   bash run_tests.sh nag --no-db-seed      # 생략 (run_tests.sh 가 아예 안 부른다)
#   bash run_tests.sh nag --db-seed-check   # 확인만 — 없으면 WARN, INSERT/UPDATE 안 함
# ${PDB_CONNSTR_2} 가 있으면 두 번째 DB 에도 같은 확인·INSERT 를 한다.
${DB_SEED_FILE}              ${CURDIR}/../config/db_seed/dev.sql
${DB_SEED_CHECK_ONLY}        ${FALSE}
${DB_SEED_TIMEOUT}           5               # 접속·쿼리 타임아웃(초)

# 시드가 INSERT 를 한 건이라도 했으면(DB1+DB2 합산, 블록 기준) PG 서버(${PG_HOST})에
# SSH 로 접속해 아래 명령을 차례로 실행한다. 명령 사이에는 ${DB_SEED_SSH_GAP} 만큼
# 쉰다. 접속 계정·인증은 아래 "PG 프로세스 기동 보장" 과 같다(${PG_SSH_USER},
# ${PG_SSH_KEY_FILE} 또는 환경변수 PG_PWD_SSH).
# 명령은 config/env/<env>.py 에 리스트로 넣는다 — 비어 있으면(기본) 건너뛴다.
#   DB_SEED_SSH_CMDS = ['<명령1>', '<명령2>']
# 명령이 실패(종료코드≠0)하면 시드가 실패하고 본 실행을 하지 않는다.
# 끄려면: bash run_tests.sh <대상> --no-db-seed-ssh
@{DB_SEED_SSH_CMDS}
${DB_SEED_SSH_ENABLE}        ${TRUE}
${DB_SEED_SSH_GAP}           5s              # 명령 사이 대기
${DB_SEED_SSH_TIMEOUT}       60              # 명령 하나의 ssh 타임아웃(초)

# ── PG 프로세스 기동 보장 (SSH, 선택) ────────
# Suite Setup 이 슈트가 의존하는 PG 프로세스의 .RUN 파일을 touch 해 죽어 있으면
# 다시 띄운다(resources/ssh_keywords.robot 의 `Ensure PG Process Running`).
#
# 계정 정보는 여기 넣지 않는다 — 예전에 SSH 비밀번호가 평문 커밋된 사고
# 전례가 있다(docs/ENVIRONMENTS.md "자격증명" 절). ${PG_SSH_USER} 만 두고,
# 비밀번호는 환경변수 PG_PWD_SSH 로만 준다. 키 인증을 쓰려면
# config/env/<env>.py 에서 ${PG_SSH_KEY_FILE} 을 채운다(있으면 키 우선).
#
# ${PG_SSH_USER} 가 비어 있으면(기본) 통째로 건너뛴다 — SSH 없이도 슈트는
# 정상 동작한다. 끄려면: --variable PG_SSH_ENSURE:False (--no-ssh-ensure)
${PG_SSH_ENSURE}             ${TRUE}
${PG_SSH_USER}               ${EMPTY}
${PG_SSH_KEY_FILE}           ${EMPTY}
${PG_SSH_RUN_DIR}            /PG/BIN/PDB_RUN

# .RUN touch 는 "띄워 달라"는 신호일 뿐, PG 가 그 프로세스를 실제로 인식해
# 기동을 끝내기까지는 시간이 더 걸린다 — touch 직후 곧바로 접속하면 아직
# 안 올라온 상태라 9999/Connection reset 으로 헤맬 수 있다(2026-10-20).
# NAG/PCF/LRS 는 Ensure PG Process Running 뒤에 곧바로 소켓을 여는 구조라
# 이 여유가 없다 — 그래서 그 셋의 Suite Setup 에서만 이 시간만큼 쉰다.
# CDS/RTS 는 PDB 접속·세션 적재 등 다른 단계가 먼저 끼어들어 자연히 그만큼
# 지연되므로 별도로 넣지 않았다.
${PG_SSH_SETTLE}             3s

# ── PCF SBI Noti 수신 검증 (CDS · RTS 공용) ──
# 도구가 PCF 역할로 h2c 를 Listen 해 PG.SNOTI 가 보내는 SBI Noti 를 받는 판정.
# **CDS 와 RTS 가 같은 포트(16101)·같은 HttpNotiServer 를 쓴다** — 손잡이도 하나다.
# 끄면 Listen 자체를 안 한다(h2 패키지 없이도 슈트가 돈다).
#   bash run_tests.sh cds --no-sbi   /   bash run_tests.sh rts --no-sbi
${SNOTI_PCF_NOTI}            ${TRUE}
# Listen 주소 — 노드 변수 ${CDS_NOTI_PORT}/${RTS_NOTI_PORT} 의 기본값이다(구 이름으로 덮어도 된다).
${SBI_NOTI_PORT}             16101           # PG 설정과 일치해야 함
${SBI_NOTI_HOST}             0.0.0.0         # bind 주소 — PG 에서 닿는 주소는 ${TOOL_HOST}

# ── 망 데이터 ────────────────────────────────
${SUBS_APN_LTE}              lte.sktelecom.com
${SUBS_APN_5G}               5g.sktelecom.com
${SUBS_MOBILE_IP}            2001:0d88:131f:0000::/64
${NET_CELL_ID}               123456:0
${NET_PGW_IP}                60.50.10.2
${NET_SI_FROM_IP}            112.172.129.68    # PG 에 등록된 IP 여야 함 (아니면 403)
