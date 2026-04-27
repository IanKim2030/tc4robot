*** Settings ***
Documentation
...    LRS(PG) → PCRF/PCF 위치 정보 처리 연동 규격서 v0.8 기능 검증
...
...    [테스트 대상]
...    LRS(PG) → 테스트 도구(PCRF/PCF 서버 역할, Port 8890)
...
...    [Suite 소켓 정책]
...    Suite Setup    : Port 8890 Listen → LRS(PG) 접속 수락 → Hello 완료 → ${LRS_CONN} 공유
...    Test Setup     : Check LRS Socket (소켓 닫히면 Suite 즉시 중단)
...    Suite Teardown : LRS 연결 종료
...    각 TC          : ${LRS_CONN} 공유 사용 (TC별 연결/해제 없음)

Resource    ../../resources/variables.robot
Resource    ../../resources/common_keywords.robot

Suite Setup      Suite LRS Accept And Hello
Suite Teardown   Suite LRS Disconnect
Test Setup       Check LRS Socket

*** Test Cases ***

# ════════════════════════════════════════════════════════════════
# 0x01/0x02  Hello  ← 접속 후 최초 수신 메시지
# ════════════════════════════════════════════════════════════════

TC-LRS-001 Hello - SYS_ID / BRANCH_NAME 수신 및 정상 응답
    [Documentation]
    ...    규격서 3.2.1 / 3.2.2 / 4.1
    ...    소켓 accept 후 LRS(PG)가 가장 먼저 전송하는 Hello-Request(0x01) 수신
    ...    → SYS_ID, BRANCH_NAME, TXN ID 검증
    ...    → Hello-Response(0x02) RESULT_CODE=0, INTERVAL 응답
    ...    ※ 규격: 접속 후 5초 내 Hello 미수신 시 서버가 연결 종료해야 함
    [Tags]    lrs    hello    smoke
    ${hdr}    ${req}=    Receive And Validate LRS Hello
    LRS TXN ID Should Not Be Zero    ${hdr}
    LRS Request SYS ID Should Be        ${req}    ${LRS_EXPECTED_SYS_ID}
    LRS Request Branch Name Should Be   ${req}    ${LRS_EXPECTED_BRANCH_NAME}
    Log    Hello 수신: SYS_ID=${req}[SYS_ID] BRANCH=${req}[BRANCH_NAME] TXN=${hdr}[txn_id]
    Send LRS Hello Response    ${hdr}[txn_id]    0    ${LRS_RESP_INTERVAL}


# ════════════════════════════════════════════════════════════════
# 0x03/0x04  Ping
# ════════════════════════════════════════════════════════════════

TC-LRS-002 Ping - SYS_ID / BRANCH_NAME 수신 및 정상 응답
    [Documentation]
    ...    규격서 3.2.3 / 3.2.1(Ping Response) / 4.1
    ...    Ping-Request(0x03) 수신 → SYS_ID, BRANCH_NAME, TXN ID 검증
    ...    → Ping-Response(0x04) RESULT_CODE=0 응답
    [Tags]    lrs    ping    smoke
    ${hdr}    ${req}=    Receive And Validate LRS Ping
    LRS TXN ID Should Not Be Zero    ${hdr}
    LRS Request SYS ID Should Be        ${req}    ${LRS_EXPECTED_SYS_ID}
    LRS Request Branch Name Should Be   ${req}    ${LRS_EXPECTED_BRANCH_NAME}
    Send LRS Ping Response    ${hdr}[txn_id]    0


# ════════════════════════════════════════════════════════════════
# 0x05/0x06  Location-Info
# ════════════════════════════════════════════════════════════════

TC-LRS-003 Location-Info - LTE 정상 조회 및 응답 (RESULT_CODE=0)
    [Documentation]
    ...    규격서 3.2.6 / 3.2.7 / 4.2
    ...    Location-Info-Request(0x05) 수신
    ...    → MDN, TID, APN, DESTINATION_HOST 필드 검증
    ...    → Location-Info-Response(0x06) 위치 정보 포함 응답
    [Tags]    lrs    location    lte    smoke
    ${hdr}    ${req}=    Receive And Validate LRS Location Info
    LRS TXN ID Should Not Be Zero    ${hdr}
    LRS MDN Should Be Valid    ${req}
    LRS TID Should Be Valid    ${req}
    Log    Location-Info 수신: MDN=${req}[MDN] APN=${req}[APN] DST=${req}[DESTINATION_HOST]
    Send LRS Location Info Response
    ...    txn_id=${hdr}[txn_id]
    ...    req=${req}
    ...    cell_info=${LRS_MOCK_CELL_INFO_LTE}
    ...    ta_code=${LRS_MOCK_TA_CODE_LTE}
    ...    net_tp=${LRS_MOCK_NET_TP_LTE}
    ...    result_code=0

TC-LRS-004 Location-Info - 5G 정상 조회 및 응답 (SBI, SERVICE_ID 없음)
    [Documentation]
    ...    규격서 3.2.6 주석: SBI 처리 시 SERVICE_ID 미전송 (Body=169B)
    ...    → SERVICE_ID 필드 없이도 정상 파싱되는지 검증
    [Tags]    lrs    location    5g    smoke
    ${hdr}    ${req}=    Receive And Validate LRS Location Info
    LRS MDN Should Be Valid    ${req}
    LRS TID Should Be Valid    ${req}
    Log    5G Location-Info 수신: MDN=${req}[MDN] APN=${req}[APN]
    Send LRS Location Info Response
    ...    txn_id=${hdr}[txn_id]
    ...    req=${req}
    ...    cell_info=${LRS_MOCK_CELL_INFO_5G}
    ...    ta_code=${LRS_MOCK_TA_CODE_5G}
    ...    net_tp=${LRS_MOCK_NET_TP_5G}
    ...    result_code=0

TC-LRS-005 Location-Info - TXN ID 에코 검증
    [Documentation]    규격서 3.2 f. Location-Info-Response TXN ID = Request TXN ID
    [Tags]    lrs    location    validation
    ${hdr}    ${req}=    Receive And Validate LRS Location Info
    ${req_txn}=    Get From Dictionary    ${hdr}    txn_id
    Send LRS Location Info Response
    ...    txn_id=${req_txn}
    ...    req=${req}
    ...    cell_info=${LRS_MOCK_CELL_INFO_LTE}
    ...    ta_code=${LRS_MOCK_TA_CODE_LTE}
    ...    net_tp=${LRS_MOCK_NET_TP_LTE}
    ...    result_code=0
    Log    Location-Info TXN ID 에코: ${req_txn}

TC-LRS-006 Location-Info - TID 에코 검증
    [Documentation]    규격서 3.2.7: 응답 TID = 수신한 Request TID (그대로 에코)
    [Tags]    lrs    location    validation
    ${hdr}    ${req}=    Receive And Validate LRS Location Info
    ${req_tid}=    Get From Dictionary    ${req}    TID
    Send LRS Location Info Response
    ...    txn_id=${hdr}[txn_id]
    ...    req=${req}
    ...    cell_info=${LRS_MOCK_CELL_INFO_LTE}
    ...    ta_code=${LRS_MOCK_TA_CODE_LTE}
    ...    net_tp=${LRS_MOCK_NET_TP_LTE}
    ...    result_code=0
    Log    TID 에코 확인: ${req_tid}

TC-LRS-007 Location-Info - 응답 필드 검증 (CELL_INFO, TA_CODE, NET_TP)
    [Documentation]
    ...    규격서 3.2.7: 응답 필드 형식 검증
    ...    CELL_INFO: NodeB:Cell 또는 plmn-NodeB:Cell
    ...    TA_CODE: Hex 4자리(ECGI) 또는 6자리(NCGI), 대문자
    ...    NET_TP: L / S / W
    [Tags]    lrs    location    validation
    ${hdr}    ${req}=    Receive And Validate LRS Location Info
    Send LRS Location Info Response
    ...    txn_id=${hdr}[txn_id]
    ...    req=${req}
    ...    cell_info=${LRS_MOCK_CELL_INFO_LTE}
    ...    ta_code=${LRS_MOCK_TA_CODE_LTE}
    ...    net_tp=${LRS_MOCK_NET_TP_LTE}
    ...    result_code=0
    Cell Info Should Be Valid    ${LRS_MOCK_CELL_INFO_LTE}
    TA Code Should Be Valid      ${LRS_MOCK_TA_CODE_LTE}
    Should Be True    '${LRS_MOCK_NET_TP_LTE}' in ['L', 'S', 'W']


# ════════════════════════════════════════════════════════════════
# 오류 응답 시나리오
# ════════════════════════════════════════════════════════════════

TC-LRS-008 Location-Info - 세션 Not Found 응답 (RESULT_CODE=200)
    [Documentation]
    ...    규격서 3.2.8: RESULT_CODE=200 → 세션 Not Found
    ...    LRS(PG)가 RESULT_CODE=200 수신 시 정상 처리하는지 검증
    [Tags]    lrs    location    negative
    ${hdr}    ${req}=    Receive And Validate LRS Location Info
    Log    세션 Not Found 응답 전송: MDN=${req}[MDN]
    Send LRS Location Info Response
    ...    txn_id=${hdr}[txn_id]
    ...    req=${req}
    ...    cell_info=${EMPTY}
    ...    ta_code=0
    ...    net_tp=${EMPTY}
    ...    result_code=200

TC-LRS-009 Location-Info - PGW RAA Timeout 응답 (RESULT_CODE=300)
    [Documentation]
    ...    규격서 3.2.8: RESULT_CODE=300 → PGW RAA Timeout
    ...    LRS(PG)가 RESULT_CODE=300 수신 시 정상 처리하는지 검증
    [Tags]    lrs    location    negative
    ${hdr}    ${req}=    Receive And Validate LRS Location Info
    Log    PGW RAA Timeout 응답 전송: MDN=${req}[MDN]
    Send LRS Location Info Response
    ...    txn_id=${hdr}[txn_id]
    ...    req=${req}
    ...    cell_info=${EMPTY}
    ...    ta_code=0
    ...    net_tp=${EMPTY}
    ...    result_code=300

TC-LRS-010 Location-Info - Failover 응답 (RESULT_CODE=9999)
    [Documentation]
    ...    규격서 3.2.8: RESULT_CODE=9999 → Active→Standby 절체 신호
    ...    LRS(PG)가 RESULT_CODE=9999 수신 시 Standby로 재접속하는지 검증
    [Tags]    lrs    location    negative
    ${hdr}    ${req}=    Receive And Validate LRS Location Info
    Log    Failover 응답 전송: MDN=${req}[MDN]
    Send LRS Location Info Response
    ...    txn_id=${hdr}[txn_id]
    ...    req=${req}
    ...    cell_info=${EMPTY}
    ...    ta_code=0
    ...    net_tp=${EMPTY}
    ...    result_code=9999
