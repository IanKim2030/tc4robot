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
Resource    ../../resources/lrs_keywords.robot


Variables    ../resources/DynamicVars.py    /PG/CFG/PG.CFG COMMON
Variables    ../resources/DynamicVars.py    /PG/CFG/PG.CFG COMMON



Suite Setup      Suite LRS Accept
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
# LRS(PG) → 도구               : Request 수신
# 도구(PCRF/PCF 역할) → LRS(PG) : Response 송신
# ════════════════════════════════════════════════════════════════

# TC-LRS-003 Location-Info - LTE Request 수신 → Response 송신
#     [Documentation]
#     ...    규격서 3.2.6 / 3.2.7 / 4.2
#     ...    LRS(PG) → 도구: Location-Info-Request(0x05) 수신
#     ...    도구 → LRS(PG): Location-Info-Response(0x06, NET_TP=L) 송신
#     [Tags]    lrs    location    lte    smoke
#     ${hdr}    ${req}=    Receive And Validate LRS Location Info
#     LRS TXN ID Should Not Be Zero    ${hdr}
#     LRS MDN Should Be Valid       ${req}
#     LRS TID Should Be Valid       ${req}
#     Send LRS Location Info Response    ${hdr}[txn_id]    ${req}
#     ...    cell_info=${LRS_MOCK_CELL_INFO_LTE}
#     ...    ta_code=${LRS_MOCK_TA_CODE_LTE}
#     ...    net_tp=${LRS_MOCK_NET_TP_LTE}
#     ...    result_code=${LRS_CODE_SUCCESS}

# TC-LRS-004 Location-Info - 5G Request 수신 → Response 송신 (SBI)
#     [Documentation]
#     ...    규격서 3.2.6 주석: SBI 처리 시 SERVICE_ID 미전송 (Body=169B)
#     ...    LRS(PG) → 도구: Location-Info-Request(0x05) 수신 (SERVICE_ID 없음)
#     ...    도구 → LRS(PG): Location-Info-Response(0x06, NET_TP=S) 송신
#     [Tags]    lrs    location    5g    smoke
#     ${hdr}    ${req}=    Receive And Validate LRS Location Info
#     LRS TXN ID Should Not Be Zero    ${hdr}
#     LRS MDN Should Be Valid       ${req}
#     LRS TID Should Be Valid       ${req}
#     Send LRS Location Info Response    ${hdr}[txn_id]    ${req}
#     ...    cell_info=${LRS_MOCK_CELL_INFO_5G}
#     ...    ta_code=${LRS_MOCK_TA_CODE_5G}
#     ...    net_tp=${LRS_MOCK_NET_TP_5G}
#     ...    result_code=${LRS_CODE_SUCCESS}
