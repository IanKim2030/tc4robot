*** Settings ***
Documentation    PG 연동 통합 테스트 공통 변수 (NAG / PCF / LRS)

*** Variables ***

# ════════════════════════════════════════════
# NAG PG 접속 정보 (클라이언트 모드, Port 8012)
# ════════════════════════════════════════════
${NAG_PG_HOST}         192.168.15.141
${NAG_PG_PORT}         8012
${NAG_TIMEOUT}         10
${NAG_SYS_ID}          NAG01
${NAG_BRANCH_NAME}     BR

# ════════════════════════════════════════════
# PCF PG 접속 정보 (클라이언트 모드, Port 8011)
# ════════════════════════════════════════════
${PCF_PG_HOST}         192.168.15.141
${PCF_PG_PORT}         8011
${PCF_TIMEOUT}         10
${PCF_SYS_ID}          LTE-PCRF01
${PCF_BRANCH_NAME}     SS

# ════════════════════════════════════════════
# LRS 서버 정보 (서버 모드, Port 8890)
# 테스트 도구가 PCRF/PCF 역할로 Listen
# LRS(PG)가 접속하면 TC 진행
# ════════════════════════════════════════════
${LRS_SERVER_HOST}        0.0.0.0    # 모든 인터페이스 Listen
${LRS_SERVER_PORT}        8890       # 규격서 고정값
${LRS_ACCEPT_TIMEOUT}     30         # LRS(PG) 접속 대기 최대 시간(초)
${LRS_MSG_TIMEOUT}        10         # 메시지 수신 최대 대기 시간(초)

# LRS(PG)가 Hello에 실어 보내는 식별값 (검증용)
${LRS_EXPECTED_SYS_ID}      PG01
# TODO: 실환경 LRS(PG)의 BRANCH_NAME (2자리: SS=성수, DS=둔산)
${LRS_EXPECTED_BRANCH_NAME}    SS

# Hello-Response에 내려줄 Ping 주기(초)
${LRS_RESP_INTERVAL}        30

# ════════════════════════════════════════════
# 메시지 타입 상수 (헤더 Byte1)
# ════════════════════════════════════════════
# NAG / PCF / LRS 공통
${MSG_HELLO_REQ}              ${1}     # 0x01
${MSG_HELLO_RESP}             ${2}     # 0x02
${MSG_PING_REQ}               ${3}     # 0x03
${MSG_PING_RESP}              ${4}     # 0x04

# PCF 전용 (Zone-InOut)
${MSG_PCF_ZONE_REQ}           ${5}     # 0x05  PCF → PG
${MSG_PCF_ZONE_RESP}          ${6}     # 0x06  PG → PCF

# NAG 전용
${MSG_ZION_REQ}               ${7}     # 0x07  PG → NAG (수신)
${MSG_ZION_RESP}              ${8}     # 0x08  NAG → PG
${MSG_SUBS_ZONE_STATUS_REQ}   ${9}     # 0x09  NAG → PG
${MSG_SUBS_ZONE_STATUS_RESP}  ${10}    # 0x0a  PG → NAG
${MSG_SUBS_CELLID_REQ}        ${11}    # 0x0b  NAG → PG (ADOT)
${MSG_SUBS_CELLID_RESP}       ${12}    # 0x0c  PG → NAG (ADOT)

# LRS 전용 (Location-Info)
${MSG_LOC_INFO_REQ}           ${5}     # 0x05  LRS(PG) → PCRF/PCF (수신)
${MSG_LOC_INFO_RESP}          ${6}     # 0x06  PCRF/PCF → LRS(PG) (송신)

# ════════════════════════════════════════════
# NAG/PCF 응답 코드
# ════════════════════════════════════════════
${CODE_SUCCESS}               ${200}
${CODE_SUCCESS_WITH_INFO}     ${201}
${CODE_UNSUPPORT_MSG}         ${400}
${CODE_UNEXPECTED_DATA}       ${401}
${CODE_NOT_FOUND_SS}          ${402}    # HFC 미가입 (NAG)
${CODE_NOT_FOUND_SESSION}     ${403}    # 세션 없음 (NAG)
${CODE_RETRY_AFTER}           ${429}    # 과부하 (NAG)
${CODE_INTERNAL_ERROR}        ${500}
${CODE_PEER_NODE_DOWN}        ${502}    # Peer 연결 없음 (NAG)
${CODE_SERVICE_UNAVAILABLE}   ${503}
${CODE_GATEWAY_TIMEOUT}       ${504}    # T-Server Timeout (NAG)
${CODE_HAVE_TO_FAILOVER}      ${9999}

# ════════════════════════════════════════════
# LRS RESULT_CODE (규격서 3.2.8)
# ════════════════════════════════════════════
${LRS_CODE_SUCCESS}            0       # 성공
${LRS_CODE_INTERNAL_ERROR}     100     # 내부 처리 Error
${LRS_CODE_SESSION_NOT_FOUND}  200     # 세션 Not Found
${LRS_CODE_PGW_RAA_TIMEOUT}    300     # PGW RAA Timeout
${LRS_CODE_PGW_RAA_ERROR}      400     # PGW RAA Error Code
${LRS_CODE_RAR_DUPLICATE}      500     # RAR 중복 전송 한도 초과
${LRS_CODE_FAILOVER}           9999    # 내부 RM 단절 / Active→Standby 절체

# ════════════════════════════════════════════
# NAG/PCF 테스트 데이터
# ════════════════════════════════════════════
${TEST_MDN_NORMAL}        01020300553
${TEST_MDN_NO_SS}         00000000000    # HFC 미가입 → code=402
${TEST_MDN_NO_SESSION}    99999999999    # 세션 없음 → code=403
${TEST_MOBILE_IP}         2001:0d88:131f:0000::/64
${TEST_CELL_INFO}         9999:99
${TEST_APN}               lte.sktelecom.com
${TEST_CLIENT_HOST}       ltepgw01.sktelecom.com

# ════════════════════════════════════════════
# LRS Mock 응답 데이터 (Location-Info-Response)
# TODO: 실환경 시나리오에 맞게 조정
# ════════════════════════════════════════════
${LRS_MOCK_CELL_INFO_LTE}      1048575:63
${LRS_MOCK_CELL_INFO_5G}       4194303:16383
${LRS_MOCK_CELL_INFO_ROAMING}  45008-1048575:255

${LRS_MOCK_TA_CODE_LTE}        3113
${LRS_MOCK_TA_CODE_5G}         6000F0

${LRS_MOCK_NET_TP_LTE}         L
${LRS_MOCK_NET_TP_5G}          S
${LRS_MOCK_NET_TP_3G}          W
