*** Settings ***
Documentation
...    LRS 클라이언트 모드 변수 (도구 → PG.LRS 접속, Port 10204)
...
...    1) Health Check / Ping (raw TCP "REQ"/"ANS")
...    2) SESSION-INFO-RETRIEVAL (HTTP/1.1)
...    ${LRS_*} 변수 다수는 운영 PG 대상 슈트가 통과하려면 실환경값으로 교체해야 한다.
...
...    ※ LRS 서버 모드(Port 8890, LRS-PCF 채널) 변수는 resources/lrs_server_variables.robot 로
...      분리했다. 현재 그 서버 모드는 NAG 슈트에서만 쓰이며 lrs_keywords.robot 와 한 세트다.

*** Variables ***

# ════════════════════════════════════════════
# LRS 클라이언트 모드 (도구 → PG.LRS 접속, Port 10204)
#   1) Health Check (raw TCP "REQ"/"ANS")
#   2) SESSION-INFO-RETRIEVAL (HTTP/1.1)
# 포트/주기는 PG_V2.cfg 에서 DynamicVars 로 읽되, 미수신 시 아래 기본값 사용:
#   ${PG_LRS_PG_V2_LISTEN_PORT} → 없으면 ${LRS_CLIENT_DEFAULT_PORT}
#   ${PG_LRS_PG_V2_TIMEOUT}     → 없으면 ${LRS_HC_DEFAULT_INTERVAL}
# ════════════════════════════════════════════
${LRS_CLIENT_HOST}          192.168.15.141   # TODO: 실환경 PG.LRS 서비스 IP
${LRS_CLIENT_DEFAULT_PORT}  10204            # 규격 디폴트 (config 미수신 시)
${LRS_HC_DEFAULT_INTERVAL}  30               # Health Check 주기(초) 디폴트
${LRS_CLIENT_TIMEOUT}       10               # 송수신 타임아웃(초)

# Health Check 메시지 (헤더 없는 순수 ASCII)
${LRS_HC_REQ}               REQ
${LRS_HC_ANS}               ANS

# Ping(keepalive) — 지속 소켓에서 REQ/ANS 를 반복 송수신하며 연결 유지 검증
${LRS_PING_COUNT}           ${3}    # 연속 Ping 횟수
${LRS_PING_GAP}             1       # Ping 간 간격(초). 실주기 검증 시 ${LRS_HC_INTERVAL} 로 오버라이드

# ── SESSION-INFO-RETRIEVAL 요청 데이터 (규격 예시값) ──
# TODO: 실환경 PG 에 등록된 From IP / PGW Group / 조회 대상으로 교체
${LRS_SI_PATH}              /SESSION-INFO-RETRIEVAL
${LRS_SI_FROM_IP}          112.172.129.68   # From 필드: PG 에 등록된 IP 여야 함(아니면 403)
${LRS_SI_REQ_ID}           wapgw03-01-6-00039
${LRS_SI_PGW_GROUP_ID}     ${EMPTY}
${LRS_SI_CLIENT_IP}        2001:0d88:131f:0000::/64    # 조회 대상 단말 IP
${LRS_SI_MIN}              ${EMPTY}
${LRS_SI_MDN}              01020300553
${LRS_SI_IMSI}             ${EMPTY}

# SESSION-INFO 응답 상태코드 (규격)
${LRS_SI_CODE_OK}          ${200}    # 세션 정보 존재
${LRS_SI_CODE_BAD_REQ}     ${400}    # Header/Body Syntax 오류
${LRS_SI_CODE_FORBIDDEN}   ${403}    # From IP 미등록 / 허용되지 않은 PGW 그룹
${LRS_SI_CODE_NOT_FOUND}   ${404}    # 세션 정보 없음
${LRS_SI_CODE_INTERNAL}    ${500}    # 내부 에러 (DB / PCRF·PCF 연동 실패 / Failover)
${LRS_SI_CODE_RAA_ERROR}   ${601}    # PCRF/PCF RAA 에러 리턴
${LRS_SI_CODE_RAA_TIMEOUT}  ${602}   # PCRF/PCF RAA Timeout
