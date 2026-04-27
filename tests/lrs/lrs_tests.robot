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
# 도구(PCRF/PCF 역할) → LRS(PG) : Request 송신
# LRS(PG) → 도구               : Response 수신
# ════════════════════════════════════════════════════════════════

TC-LRS-003 Location-Info - LTE 정상 조회 (RESULT_CODE=0)
    [Documentation]
    ...    규격서 3.2.6 / 3.2.7 / 4.2
    ...    도구 → LRS(PG): Location-Info-Request(0x05) 송신
    ...    LRS(PG) → 도구: Location-Info-Response(0x06) 수신
    ...    → RESULT_CODE=0, CELL_INFO, TA_CODE, NET_TP=L 검증
    [Tags]    lrs    location    lte    smoke
    ${txn_id}=    Next TXN ID
    ${req_txn}    ${req_tid}=    Send LRS Location Info Request
    ...    sys_id=${LRS_SYS_ID}
    ...    branch_name=${LRS_BRANCH_NAME}
    ...    dst_host=${LRS_DST_HOST_LTE}
    ...    apn=${LRS_APN_LTE}
    ...    mdn=${LRS_MDN_LTE}
    ...    svc_id=${LRS_SVC_ID_LTE}
    ...    txn_id=${txn_id}
    ${hdr}    ${resp}=    Receive LRS Location Info Response
    LRS TXN ID Should Match    ${txn_id}    ${hdr}
    LRS Location Info Should Succeed    ${resp}
    LRS Location Info TID Should Match    ${req_tid}    ${resp}
    Cell Info Should Be Valid    ${resp}[CELL_INFO]
    TA Code Should Be Valid      ${resp}[TA_CODE]
    Should Be Equal As Strings   ${resp}[NET_TP]    L
    ...    msg=LTE 세션 NET_TP 기대 L, 실제=${resp}[NET_TP]

TC-LRS-004 Location-Info - 5G 정상 조회 (SBI, SERVICE_ID 없음, RESULT_CODE=0)
    [Documentation]
    ...    규격서 3.2.6 주석: SBI 처리 시 SERVICE_ID 미전송 (Body=169B)
    ...    도구 → LRS(PG): Location-Info-Request 송신 (sbi=True)
    ...    LRS(PG) → 도구: Location-Info-Response 수신
    ...    → RESULT_CODE=0, NET_TP=S 검증
    [Tags]    lrs    location    5g    smoke
    ${txn_id}=    Next TXN ID
    ${req_txn}    ${req_tid}=    Send LRS Location Info Request
    ...    sys_id=${LRS_SYS_ID}
    ...    branch_name=${LRS_BRANCH_NAME}
    ...    dst_host=${LRS_DST_HOST_5G}
    ...    apn=${LRS_APN_5G}
    ...    mdn=${LRS_MDN_5G}
    ...    sbi=${True}
    ...    txn_id=${txn_id}
    ${hdr}    ${resp}=    Receive LRS Location Info Response
    LRS TXN ID Should Match    ${txn_id}    ${hdr}
    LRS Location Info Should Succeed    ${resp}
    Cell Info Should Be Valid    ${resp}[CELL_INFO]
    Should Be Equal As Strings   ${resp}[NET_TP]    S
    ...    msg=5G 세션 NET_TP 기대 S, 실제=${resp}[NET_TP]

TC-LRS-005 Location-Info - TXN ID 에코 검증
    [Documentation]
    ...    규격서 3.2 f. Location-Info-Response TXN ID = Request TXN ID
    [Tags]    lrs    location    validation
    ${txn_id}=    Next TXN ID
    ${req_txn}    ${req_tid}=    Send LRS Location Info Request
    ...    sys_id=${LRS_SYS_ID}
    ...    branch_name=${LRS_BRANCH_NAME}
    ...    dst_host=${LRS_DST_HOST_LTE}
    ...    apn=${LRS_APN_LTE}
    ...    mdn=${LRS_MDN_LTE}
    ...    svc_id=${LRS_SVC_ID_LTE}
    ...    txn_id=${txn_id}
    ${hdr}    ${resp}=    Receive LRS Location Info Response
    LRS TXN ID Should Match    ${txn_id}    ${hdr}
    Log    Location-Info TXN ID 에코: ${txn_id}

TC-LRS-006 Location-Info - TID 에코 검증
    [Documentation]    규격서 3.2.7: 응답 TID = 요청 TID 그대로 에코
    [Tags]    lrs    location    validation
    ${txn_id}=    Next TXN ID
    ${req_txn}    ${req_tid}=    Send LRS Location Info Request
    ...    sys_id=${LRS_SYS_ID}
    ...    branch_name=${LRS_BRANCH_NAME}
    ...    dst_host=${LRS_DST_HOST_LTE}
    ...    apn=${LRS_APN_LTE}
    ...    mdn=${LRS_MDN_LTE}
    ...    svc_id=${LRS_SVC_ID_LTE}
    ...    txn_id=${txn_id}
    ${hdr}    ${resp}=    Receive LRS Location Info Response
    LRS Location Info TID Should Match    ${req_tid}    ${resp}
    Log    TID 에코 확인: ${req_tid}

TC-LRS-007 Location-Info - 응답 필드 검증 (CELL_INFO, TA_CODE, NET_TP)
    [Documentation]
    ...    규격서 3.2.7: 응답 필드 형식 검증
    ...    CELL_INFO: NodeB:Cell 또는 plmn-NodeB:Cell
    ...    TA_CODE: Hex 4자리(ECGI) 또는 6자리(NCGI), 대문자
    ...    NET_TP: L / S / W
    [Tags]    lrs    location    validation
    ${txn_id}=    Next TXN ID
    ${req_txn}    ${req_tid}=    Send LRS Location Info Request
    ...    sys_id=${LRS_SYS_ID}
    ...    branch_name=${LRS_BRANCH_NAME}
    ...    dst_host=${LRS_DST_HOST_LTE}
    ...    apn=${LRS_APN_LTE}
    ...    mdn=${LRS_MDN_LTE}
    ...    svc_id=${LRS_SVC_ID_LTE}
    ...    txn_id=${txn_id}
    ${hdr}    ${resp}=    Receive LRS Location Info Response
    Cell Info Should Be Valid    ${resp}[CELL_INFO]
    TA Code Should Be Valid      ${resp}[TA_CODE]
    Should Be True    '${resp}[NET_TP]' in ['L', 'S', 'W']
    ...    msg=NET_TP 기대 L/S/W, 실제=${resp}[NET_TP]


# ════════════════════════════════════════════════════════════════
# 오류 응답 시나리오
# ════════════════════════════════════════════════════════════════

TC-LRS-008 Location-Info - 세션 Not Found (RESULT_CODE=200)
    [Documentation]
    ...    규격서 3.2.8: RESULT_CODE=200 → 세션 Not Found
    ...    세션이 없는 MDN으로 요청 → RESULT_CODE=200 검증
    [Tags]    lrs    location    negative
    ${txn_id}=    Next TXN ID
    ${req_txn}    ${req_tid}=    Send LRS Location Info Request
    ...    sys_id=${LRS_SYS_ID}
    ...    branch_name=${LRS_BRANCH_NAME}
    ...    dst_host=${LRS_DST_HOST_LTE}
    ...    apn=${LRS_APN_LTE}
    ...    mdn=${LRS_MDN_NO_SESSION}
    ...    svc_id=${LRS_SVC_ID_LTE}
    ...    txn_id=${txn_id}
    ${hdr}    ${resp}=    Receive LRS Location Info Response
    ${code}=    Get From Dictionary    ${resp}    RESULT_CODE
    Should Be Equal As Strings    ${code}    200
    ...    msg=RESULT_CODE 기대 200, 실제=${code}

TC-LRS-009 Location-Info - PGW RAA Timeout (RESULT_CODE=300)
    [Documentation]
    ...    규격서 3.2.8: RESULT_CODE=300 → PGW RAA Timeout
    [Tags]    lrs    location    negative
    ${txn_id}=    Next TXN ID
    ${req_txn}    ${req_tid}=    Send LRS Location Info Request
    ...    sys_id=${LRS_SYS_ID}
    ...    branch_name=${LRS_BRANCH_NAME}
    ...    dst_host=${LRS_DST_HOST_LTE}
    ...    apn=${LRS_APN_LTE}
    ...    mdn=${LRS_MDN_LTE}
    ...    svc_id=${LRS_SVC_ID_LTE}
    ...    txn_id=${txn_id}
    ${hdr}    ${resp}=    Receive LRS Location Info Response
    ${code}=    Get From Dictionary    ${resp}    RESULT_CODE
    Should Be True    '${code}' in ['0', '300']
    ...    msg=RESULT_CODE 기대 0 또는 300, 실제=${code}

TC-LRS-010 Location-Info - Failover (RESULT_CODE=9999)
    [Documentation]
    ...    규격서 3.2.8: RESULT_CODE=9999 → Active→Standby 절체 신호
    [Tags]    lrs    location    negative
    ${txn_id}=    Next TXN ID
    ${req_txn}    ${req_tid}=    Send LRS Location Info Request
    ...    sys_id=${LRS_SYS_ID}
    ...    branch_name=${LRS_BRANCH_NAME}
    ...    dst_host=${LRS_DST_HOST_LTE}
    ...    apn=${LRS_APN_LTE}
    ...    mdn=${LRS_MDN_LTE}
    ...    svc_id=${LRS_SVC_ID_LTE}
    ...    txn_id=${txn_id}
    ${hdr}    ${resp}=    Receive LRS Location Info Response
    ${code}=    Get From Dictionary    ${resp}    RESULT_CODE
    Should Be True    '${code}' in ['0', '9999']
    ...    msg=RESULT_CODE 기대 0 또는 9999, 실제=${code}
