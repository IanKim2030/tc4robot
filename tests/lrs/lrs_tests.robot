*** Settings ***
Documentation
...    LRS 클라이언트 모드 기능 검증 (도구 → PG.LRS 접속)
...
...    [테스트 대상]
...    테스트 도구(LRS 역할 / Client) → PG.LRS (Server, Port 기본 10204)
...    같은 포트에서 두 프로토콜 검증:
...      1) Health Check (raw TCP "REQ"/"ANS", 주기 기본 30초)
...      2) SESSION-INFO-RETRIEVAL (HTTP/1.1, AIMS_REQ → AIMS_RES)
...
...    [LRS-PCF 채널 — Session-Info 처리용 (TC-NAG-007 과 동일)]
...    Session-Info(HTTP) 처리 중 PG 가 LRS-PCF 채널(도구 Listen, Port 8890)로
...    Location-Info-Request(0x05)를 보내 위치를 조회하고, 도구가 0x06 으로 응답해야
...    PG 가 LOCATION/TAC 를 채워 HTTP 200 을 준다.
...    → Suite Setup 에서 8890 accept + Hello 를 미리 마치고(lrs_keywords.robot),
...      TC-LRS-002 는 HTTP 송신/수신을 분리해 그 사이 Handle LRS Location Info 로 0x06 응답(단일 스레드).
...
...    [Suite 소켓 정책]
...    Suite Setup    : Suite Connect LRS Client(→PG.LRS 10204) + Suite LRS Accept(8890) + Handle LRS Hello
...    Test Setup     : Check LRS Client Socket (닫히면 Suite 즉시 중단)
...    Suite Teardown : Suite LRS Disconnect + Suite Disconnect LRS Client
...    각 TC          : ${LRS_CLIENT_SOCK} 공유 (TC-LRS-002 는 ${LRS_CONN} 도 사용)
...
...    포트/주기는 PG_V2.cfg 에서 읽되, 미수신 시 기본값(10204 / 30초) 사용.

Resource    ../../resources/variables.robot
Resource    ../../resources/lrs_variables.robot
Resource    ../../resources/common_keywords.robot
Resource    ../../resources/lrs_client_keywords.robot
Resource    ../../resources/lrs_keywords.robot

#Variables    ../../resources/DynamicVars.py    pg@192.168.15.141:/PG/CFG/PG_V2.cfg    section=LRS:LISTEN_PORT=PG_LRS_PG_V2_LISTEN_PORT    pass=${PG_ROBOT_SSH_PASS}
#Variables    ../../resources/DynamicVars.py    pg@192.168.15.141:/PG/CFG/PG_V2.cfg    section=LRS:TIMEOUT=PG_LRS_PG_V2_TIMEOUT    pass=${PG_ROBOT_SSH_PASS}

Suite Setup      Run Keywords
...              Suite Connect LRS Client    AND
...              Suite LRS Accept    AND
...              Handle LRS Hello
Suite Teardown   Run Keywords
...              Suite LRS Disconnect    AND
...              Suite Disconnect LRS Client
Test Setup       Check LRS Client Socket

*** Test Cases ***

# ════════════════════════════════════════════════════════════════
# Health Check (raw TCP "REQ" → "ANS")
# ════════════════════════════════════════════════════════════════

TC-LRS-001 Health Check - REQ 송신 → ANS 수신
    [Documentation]    PG.LRS 로 "REQ" 송신 → "ANS" 수신 확인 (주기 ${LRS_HC_INTERVAL}s)
    [Tags]    lrs    health-check    smoke
    ${ans}=    Send LRS Health Check
    Health Check Should Succeed    ${ans}

# ════════════════════════════════════════════════════════════════
# SESSION-INFO-RETRIEVAL (HTTP/1.1)
# ════════════════════════════════════════════════════════════════

TC-LRS-002 Session-Info - 200 성공 및 응답 필드 검증 (LRS-PCF 연동)
    [Documentation]
    ...    POST /SESSION-INFO-RETRIEVAL (AIMS_REQ) → 200 OK (AIMS_RES)
    ...    REQ_ID 에코 일치 + CLIENT_ID-MDN / NETWORK_TOPOLOGY / LOCATION / TAC 존재 검증
    ...
    ...    TC-NAG-007 과 동일한 3단계(단일 스레드): 요청 송신 → LRS-PCF 응답 처리 → 응답 수신.
    ...    PG 가 HTTP 처리 중 보내는 Location-Info-Request(0x05)에 0x06 으로 응답해야 200 이 온다.
    [Tags]    lrs    session-info    smoke    validation
    ${sock}=    Send Session Info Request
    # PG 가 LRS-PCF 채널로 보내는 0x05 를 받아 0x06(LTE 목값)으로 응답
    Handle LRS Location Info
    ${res}=    Receive Session Info Response    ${sock}
    Session Info Should Succeed    ${res}


# ── 아래 TC 는 실 PG 가 해당 상태코드를 유발해야 동작하므로 주석 처리 ──

# TC-LRS-SI-002 Session-Info - 404 세션 없음
#     [Documentation]    조회 대상 세션이 PG 에 없을 때 404 Not Found
#     [Tags]    lrs    session-info    negative
#     ${res}=    Send Session Info Retrieval    client_ip=10.0.0.0
#     Session Info Status Should Be    ${res}    ${LRS_SI_CODE_NOT_FOUND}

# TC-LRS-SI-003 Session-Info - 403 From IP 미등록 / 허용 안 된 PGW 그룹
#     [Documentation]    From 필드 IP 가 PG 에 미등록이거나 허용되지 않은 PGW 그룹
#     [Tags]    lrs    session-info    negative
#     ${res}=    Send Session Info Retrieval    from_ip=1.1.1.1
#     Session Info Status Should Be    ${res}    ${LRS_SI_CODE_FORBIDDEN}

# TC-LRS-SI-004 Session-Info - 400 Bad Request (Syntax 오류)
#     [Tags]    lrs    session-info    negative
#     # Header/Body Syntax 오류를 의도적으로 만들어야 함 (별도 raw 송신 필요)
#     No Operation

# TC-LRS-SI-005 Session-Info - 500 내부 에러 (DB / PCRF·PCF 연동 실패 / Failover)
#     [Tags]    lrs    session-info    negative
#     ${res}=    Send Session Info Retrieval
#     Session Info Status Should Be    ${res}    ${LRS_SI_CODE_INTERNAL}

# TC-LRS-SI-006 Session-Info - 601 PCRF/PCF RAA 에러
#     [Tags]    lrs    session-info    negative
#     ${res}=    Send Session Info Retrieval
#     Session Info Status Should Be    ${res}    ${LRS_SI_CODE_RAA_ERROR}

# TC-LRS-SI-007 Session-Info - 602 PCRF/PCF RAA Timeout
#     [Tags]    lrs    session-info    negative
#     ${res}=    Send Session Info Retrieval
#     Session Info Status Should Be    ${res}    ${LRS_SI_CODE_RAA_TIMEOUT}
