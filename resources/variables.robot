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
# 환경 축 — 여기 있는 값이 dev 기준 기본값의 단일 출처다.
#
# stg / prd 는 config/env/<env>.py 가 --variablefile 로 덮어쓴다.
#   bash run_tests.sh nag stg
# 우선순위: --variable > --variablefile > 슈트 *** Variables *** > 임포트 Resource
# 따라서 환경 파일이 여기 값과 노드별 변수 파일을 모두 이긴다.
#
# 노드별 변수(*_variables.robot)는 아래 값을 **참조만** 한다 — 값을 중복 정의하지 말 것.
# ════════════════════════════════════════════

# ── 접속 ─────────────────────────────────────
${PG_HOST}                   192.168.15.141

# ── 가입자 데이터 ────────────────────────────
${SUBS_MDN_LTE}              01020300553
${SUBS_MIN_LTE}              1020300553
${SUBS_MDN_5G}               01093742433
${SUBS_MIN_5G}               1093742433
${SUBS_MDN_NO_HFC}           00000000000       # HFC 미가입 → code 402
${SUBS_MDN_NO_SESSION}       99999999999       # 세션 없음 → code 403
# CDS 가입자는 CDS 슈트만 쓰므로 cds_variables.robot 의 ${CDS_MDN} 계열에 직접 있다.

# ── PDB 접속 (CDS · RTS 공용) ────────────────
# 두 슈트가 **같은 DB** 를 본다(사용자 확인). 예전에는 ${CDS_DB_CONNSTR} /
# ${RTS_DB_CONNSTR} 로 같은 값이 두 벌 있었는데, 한쪽만 고쳐 어긋나는 자리였다.
#
# 완성된 ODBC 문자열을 통째로 준다 — 도구가 조립하지 않는다.
# 비밀번호를 파일에 남기지 않으려면 환경변수 PG_PDB_CONNSTR 을 쓴다
# (구 이름 PG_CDS_DB_CONNSTR 도 폴백으로 계속 읽는다 — CdsDbHelper.py).
#   DSN 방식      : DSN=GOLD_GLOBAL;UID=pdb;PWD=...
#   DSN-less 방식 : DRIVER=<.so 절대경로>;HOST=...;PORT=...;UID=...;PWD=...;CHARSET=UHC;
${PDB_CONNSTR}               DRIVER=/PG/goldilocks_home/lib/libgoldilockscs-ul64.so;HOST=192.168.15.185;PORT=22581;UID=pdb;PWD=pdb1234;CHARSET=UHC;

# 두 번째 DB (선택, CDS 세션 사전 적재 전용) — 환경에 따라 골디락스+알티베이스
# 이중화라 세션 정보를 **두 DB 모두에** 넣어야 하는 경우가 있다. 비워 두면(기본)
# 기존과 같이 DB 한 곳에만 넣는다 — CdsDbHelper.has_second_db() 가 이 값으로 판정한다.
# 조회(SELECT, 반영 판정)는 항상 ${PDB_CONNSTR}(첫 번째 DB) 기준이다.
# 비밀번호를 파일에 남기지 않으려면 환경변수 PG_PDB_CONNSTR_2 를 쓴다(레거시 폴백 없음).
${PDB_CONNSTR_2}             ${EMPTY}

# ── 실행 전 DB 설정 시드 (setup/db_seed.robot) ─
# run_tests.sh 가 본 실행 전에 한 번 돌린다 — 표·값은 config/db_seed/<env>.sql 에 쓴다.
# run_tests.sh 는 환경 인자로 파일을 골라 --variable 로 덮는다(IP 지정은 dev).
# 아래 기본값(dev)은 robot 을 직접 돌릴 때만 쓰인다.
#   bash run_tests.sh nag --no-db-seed      # 생략 (run_tests.sh 가 아예 안 부른다)
#   bash run_tests.sh nag --db-seed-check   # 확인만 — 없으면 WARN, INSERT 안 함
# ${PDB_CONNSTR_2} 가 있으면 두 번째 DB 에도 같은 확인·INSERT 를 한다.
${DB_SEED_FILE}              ${CURDIR}/../config/db_seed/dev.sql
${DB_SEED_CHECK_ONLY}        ${FALSE}
${DB_SEED_TIMEOUT}           5               # 접속·쿼리 타임아웃(초)

# ── PG 프로세스 기동 보장 (SSH, 선택) ────────
# Suite Setup 이 슈트가 의존하는 PG 프로세스의 .RUN 파일을 touch 해 죽어 있으면
# 다시 띄운다(resources/ssh_keywords.robot 의 `Ensure PG Process Running`).
#
# 계정 정보는 여기 넣지 않는다 — 예전에 SSH 비밀번호가 평문 커밋된 사고
# 전례가 있다(docs/ENVIRONMENTS.md "자격증명" 절). ${PG_SSH_USER} 만 두고,
# 비밀번호는 환경변수 PG_SSH_PASSWORD 로만 준다. 키 인증을 쓰려면
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

# ── 망 데이터 ────────────────────────────────
${SUBS_APN_LTE}              lte.sktelecom.com
${SUBS_APN_5G}               5g.sktelecom.com
${SUBS_MOBILE_IP}            2001:0d88:131f:0000::/64
${NET_CELL_ID}               123456:0
${NET_PGW_IP}                60.50.10.2
${NET_SI_FROM_IP}            112.172.129.68    # PG 에 등록된 IP 여야 함 (아니면 403)
