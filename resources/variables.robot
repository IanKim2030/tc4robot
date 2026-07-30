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

# ── 망 데이터 ────────────────────────────────
${SUBS_APN_LTE}              lte.sktelecom.com
${SUBS_APN_5G}               5g.sktelecom.com
${SUBS_MOBILE_IP}            2001:0d88:131f:0000::/64
${NET_CELL_ID}               123456:0
${NET_PGW_IP}                60.50.10.2
${NET_SI_FROM_IP}            112.172.129.68    # PG 에 등록된 IP 여야 함 (아니면 403)
