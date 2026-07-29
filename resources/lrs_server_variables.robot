*** Settings ***
Documentation
...    LRS 서버 모드 변수 (도구가 PCRF/PCF 역할로 Listen, LRS(PG)가 접속)
...
...    ※ 이 서버 모드(Port 8890)는 현재 NAG 슈트의 LRS-PCF 채널에서만 사용한다.
...      (lrs_keywords.robot 와 한 세트 — NAG 가 lrs_keywords.robot 를 임포트하면 함께 로드됨)
...    LRS 슈트 자체는 클라이언트 모드(→ PG.LRS:10204)이며 resources/lrs_variables.robot 를 쓴다.
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
# 수락 허용 출발지 IP (콤마/공백 구분, 여러 개 가능). 그 외 IP 접속은 거부하고 계속 대기.
# 빈 값(${EMPTY})이면 모든 IP 허용(기존 동작).
# TODO: 실환경 LRS(PG)의 LRS-PCF 채널 실제 출발지 IP 로 교체
${LRS_ALLOWED_PEER_IPS}   ${PG_HOST}
# 도구가 LRS 채널로 보낼 응답 헤더 Byte0(ProtoVer). 표준 LRS 서버모드=0x20(${32}).
# NAG-Barod LRS-PCF 채널은 0x00(${0}) — 그 슈트에서 오버라이드한다.
${LRS_TX_BYTE0}           ${32}

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
${LRS_MDN_LTE}             ${SUBS_MDN_LTE}
${LRS_DST_HOST_LTE}        ltepcrf01       # TODO: T_SESSION_INFO_XX.DESTINATION_HOST
${LRS_APN_LTE}             ${SUBS_APN_LTE}
${LRS_SVC_ID_LTE}          000001

# 5G 정상 세션 (PDB T_PCF_BINDNG_INFO 에 존재하는 MDN, SBI → SERVICE_ID 미전송)
${LRS_MDN_5G}              ${SUBS_MDN_5G}
${LRS_DST_HOST_5G}         pcrf01-mp01-app06  # TODO: T_SMF_SESSION_INFO.NODE_ID
${LRS_APN_5G}              ${SUBS_APN_5G}

# 세션 없는 MDN → RESULT_CODE=200 기대
${LRS_MDN_NO_SESSION}      ${SUBS_MDN_NO_HFC}   # PDB 에 세션이 없는 MDN

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
