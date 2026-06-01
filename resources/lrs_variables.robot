*** Settings ***
Documentation
...    LRS 인터페이스 변수 (서버 정보 / 메시지 타입 / RESULT_CODE / 테스트 데이터)
...
...    테스트 도구가 PCRF/PCF 역할로 Listen 하고 LRS(PG)가 접속한다.
...    ${LRS_*} 변수 다수는 운영 PG 대상 슈트가 통과하려면 실환경값으로 교체해야 한다.

*** Variables ***

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
${LRS_EXPECTED_SYS_ID}      PG11
# TODO: 실환경 LRS(PG)의 BRANCH_NAME (2자리: SS=성수, DS=둔산)
${LRS_EXPECTED_BRANCH_NAME}    SS

# Hello-Response에 내려줄 Ping 주기(초)
${LRS_RESP_INTERVAL}        30

# ════════════════════════════════════════════
# LRS 전용 메시지 타입 (Location-Info, 헤더 Byte1)
# ════════════════════════════════════════════
${MSG_LOC_INFO_REQ}           ${5}     # 0x05  LRS(PG) → PCRF/PCF (수신)
${MSG_LOC_INFO_RESP}          ${6}     # 0x06  PCRF/PCF → LRS(PG) (송신)

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
# LRS Location-Info-Request 테스트 데이터
# 도구 → LRS(PG) 방향
# TODO: 실환경 LRS(PG)가 처리 가능한 값으로 교체
# ════════════════════════════════════════════
${LRS_SYS_ID}              PG01            # TODO: 실환경 SYS_ID
${LRS_BRANCH_NAME}         SS              # TODO: 실환경 BRANCH_NAME

# LTE 정상 세션 (PDB T_SESSION_INFO_XX 에 존재하는 MDN)
${LRS_MDN_LTE}             01012345678     # TODO: 실환경 LTE 정상 MDN
${LRS_DST_HOST_LTE}        ltepcrf01       # TODO: T_SESSION_INFO_XX.DESTINATION_HOST
${LRS_APN_LTE}             lte.sktelecom.com
${LRS_SVC_ID_LTE}          000001

# 5G 정상 세션 (PDB T_PCF_BINDNG_INFO 에 존재하는 MDN, SBI → SERVICE_ID 미전송)
${LRS_MDN_5G}              01012345678     # TODO: 실환경 5G 정상 MDN
${LRS_DST_HOST_5G}         pcrf01-mp01-app06  # TODO: T_SMF_SESSION_INFO.NODE_ID
${LRS_APN_5G}              5g.sktelecom.com

# 세션 없는 MDN → RESULT_CODE=200 기대
${LRS_MDN_NO_SESSION}      00000000000     # TODO: PDB에 세션이 없는 MDN

# ════════════════════════════════════════════
# LRS Location-Info-Response 기대 필드값 검증용
# TODO: 실환경 응답값으로 교체
# ════════════════════════════════════════════
${LRS_MOCK_CELL_INFO_LTE}      1048575:63
${LRS_MOCK_CELL_INFO_5G}       4194303:16383
${LRS_MOCK_CELL_INFO_ROAMING}  45008-1048575:255

${LRS_MOCK_TA_CODE_LTE}        3113
${LRS_MOCK_TA_CODE_5G}         6000F0

${LRS_MOCK_NET_TP_LTE}         L
${LRS_MOCK_NET_TP_5G}          S
${LRS_MOCK_NET_TP_3G}          W
