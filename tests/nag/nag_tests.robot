*** Settings ***
Documentation
...    NAG 기능 검증 - msg_type 기준 (공유 소켓)
...
...    Suite Setup  : NAG → PG.BNOTI(${NAG_PG_PORT}) 소켓 연결 → ${NAG_SOCK} 공유
...                   + PCF 서버 소켓(${LRS_SERVER_PORT}) Listen → PG.LRS 접속 수락 (${LRS_CONN})
...                   → PCF Hello-Request(0x01) 수신 → Hello-Response(0x02) 처리
...                   (NAG Hello 는 TC-NAG-001 에서 직접 수행)
...    Test Setup   : NAG 소켓 상태 확인 (닫히면 Suite 중단)
...    각 TC        : ${NAG_SOCK} 공유 사용, TC별 연결/해제 없음

Resource    ../../resources/variables.robot
Resource    ../../resources/nag_variables.robot
Resource    ../../resources/common_keywords.robot
Resource    ../../resources/nag_keywords.robot
Resource    ../../resources/lrs_keywords.robot


Suite Setup      Run Keywords
...              Suite Connect NAG    AND
...              Suite LRS Accept    AND
...              Handle LRS Hello
Suite Teardown   Run Keywords
...              Suite LRS Disconnect    AND
...              Suite Disconnect NAG
Test Setup       Check NAG Socket

*** Variables ***
# NAG-Barod LRS-PCF 채널은 응답 헤더 Byte0=0x00 (표준 LRS 0x20 아님)
${LRS_TX_BYTE0}    ${0}

*** Test Cases ***

# ── 0x01/0x02 Hello ──────────────────────────────────────────────

TC-NAG-001 Hello - ping-interval 확인
    [Documentation]    Hello-Response(0x02) ping-interval 포함 및 TXN ID 에코
    [Tags]    nag    hello    smoke
    ${txn}=    Next TXN ID
    ${hdr}    ${body}=    Send NAG Hello    ${NAG_SYS_ID}    ${NAG_BRANCH_NAME}    ${txn}
    Response Msg Type Should Be    ${hdr}    ${2}
    TXN ID Should Match    ${txn}    ${hdr}
    Hello Should Succeed    ${body}
    ${pi}=    Get Ping Interval    ${body}
    Should Be True    ${pi} > 0    msg=ping-interval 누락 또는 0


# ── 0x03/0x04 Ping ───────────────────────────────────────────────

TC-NAG-002 Ping - 정상 응답
    [Documentation]    0x03 전송(Body 없음) → 0x04 수신, code=200, TXN ID 에코
    [Tags]    nag    ping    smoke
    ${txn}=    Next TXN ID
    ${hdr}    ${body}=    Send NAG Ping    ${txn}
    Response Msg Type Should Be    ${hdr}    ${4}
    TXN ID Should Match    ${txn}    ${hdr}
    Ping Should Succeed    ${body}


# ── 0x09/0x0a Subs-Zone-Status ───────────────────────────────────

TC-NAG-003 Subs-Zone-Status - 정상 (mobile-ip 포함)
    [Documentation]    0x09 전송 → 0x0a 수신, code=200, zone-info, TXN ID 에코
    [Tags]    nag    subs-zone    smoke
    ${txn}=    Next TXN ID
    ${hdr}    ${body}=    Send Subs Zone Status
    ...    ${NAG_SYS_ID}    ${NAG_BRANCH_NAME}
    ...    ${TEST_MDN_NORMAL}    ${TEST_MOBILE_IP}    txn_id=${txn}
    Response Msg Type Should Be    ${hdr}    ${10}
    TXN ID Should Match    ${txn}    ${hdr}
    Subs Zone Status Should Succeed    ${body}
    ${zone}=    Get From Dictionary    ${body}    zone-info
    Should Be True    '${zone}' in ['I', 'O']

TC-NAG-004 Subs-Zone-Status - mobile-ip 미포함 (Optional)
    [Documentation]    mobile-ip 없이 mdn만 요청 (Optional 필드)
    [Tags]    nag    subs-zone
    ${hdr}    ${body}=    Send Subs Zone Status
    ...    ${NAG_SYS_ID}    ${NAG_BRANCH_NAME}    ${TEST_MDN_NORMAL}
    Response Should Be Success    ${body}

TC-NAG-005 Subs-Zone-Status - HFC 미가입 (402)
    [Documentation]    미가입 MDN → code=402, cause 포함
    [Tags]    nag    subs-zone    negative
    ${hdr}    ${body}=    Send Subs Zone Status
    ...    ${NAG_SYS_ID}    ${NAG_BRANCH_NAME}    ${TEST_MDN_NO_SS}
    Response Code Should Be    ${body}    402
    Dictionary Should Contain Key    ${body}    cause

TC-NAG-006 Subs-Zone-Status - 세션 없음 (402)
    [Documentation]    세션 없는 MDN → code=402 또는 403, cause 포함
    [Tags]    nag    subs-zone    negative
    ${hdr}    ${body}=    Send Subs Zone Status
    ...    ${NAG_SYS_ID}    ${NAG_BRANCH_NAME}    ${TEST_MDN_NO_SESSION}
    ${code}=    Get From Dictionary    ${body}    code
    Should Be True    '${code}' in ['402', '403']    msg=code 기대 402/403, 실제=${code}
    Dictionary Should Contain Key    ${body}    cause


# ── 0x0b/0x0c Subs-Cellid ADOT ───────────────────────────────────
# 흐름: 0x0b Request 송신 → 0x0c Response 수신
#       (PG 가 LRS-PCF 와 연동해 위치 정보를 조회하는 처리는 PG 내부에서 수행)

TC-NAG-007 Subs-Cellid - 정상 및 응답 필드 검증
    [Documentation]    0x0b 송신 → (LRS-PCF 0x05 조회 → 0x06 응답) → 0x0c 수신,
    ...                code=200, TXN ID 에코, cell-info / ta-code / rat-type 검증
    [Tags]    nag    subs-cellid    adot    smoke    validation
    ${txn}=    Send Subs Cellid Request
    ...    ${NAG_SYS_ID}    ${NAG_BRANCH_NAME}
    ...    ${TEST_MDN_NORMAL}    ${TEST_MOBILE_IP}
    # PG 가 LRS-PCF 채널로 Location-Info-Request(0x05) 를 보내오면 0x06 으로 응답해야
    # PG 가 0x0c Subs-Cellid-Response 를 반환한다.
    Handle LRS Location Info
    ${hdr}    ${body}=    Receive Subs Cellid Response
    TXN ID Should Match    ${txn}    ${hdr}
    Subs Cellid Should Succeed    ${body}
    Cell Info Should Be Valid    ${body}[cell-info]
    TA Code Should Be Valid      ${body}[ta-code]
    ${rat}=    Get From Dictionary    ${body}    rat-type
    Should Be True    '${rat}' in ['W', 'L', 'S']


# ── 0x07/0x08 ZION (PG→NAG 방향) ────────────────────────────────
# 아래 TC는 PG에서 실제 ZION 이벤트가 발생해야 동작하므로 주석 처리

# TC-NAG-014 ZION 수신 및 0x08 정상 응답 (code=200)
#     [Documentation]
#     ...    PG 발송 ZION-Request(0x07) 수신 → 필드 검증 → 0x08 code=200
#     ...    ※ PG에서 실제 ZION 이벤트가 발생해야 동작
#     [Tags]    nag    zion    smoke
#     ${hdr}    ${body}=    Receive ZION Request
#     Dictionary Should Contain Key    ${body}    mdn
#     Dictionary Should Contain Key    ${body}    zone-info
#     Dictionary Should Contain Key    ${body}    cell-info
#     Dictionary Should Contain Key    ${body}    rat-type
#     ${zone}=    Get From Dictionary    ${body}    zone-info
#     Should Be True    '${zone}' in ['I', 'O']
#     Cell Info Should Be Valid    ${body}[cell-info]
#     ${txn}=    Get From Dictionary    ${hdr}    txn_id
#     Send ZION Response    ${txn}    200

# TC-NAG-015 ZION Response - T전화 서버 불가 (code=503)
#     [Documentation]    T전화 서버 불가 → code=503 응답
#     [Tags]    nag    zion    negative
#     ${hdr}    ${body}=    Receive ZION Request
#     ${txn}=    Get From Dictionary    ${hdr}    txn_id
#     Send ZION Response    ${txn}    503    T-Telephone Server Service Unavailable

# TC-NAG-016 ZION Response - TXN ID 에코 확인
#     [Tags]    nag    zion    validation
#     ${hdr}    ${body}=    Receive ZION Request
#     ${req_txn}=    Get From Dictionary    ${hdr}    txn_id
#     Send ZION Response    ${req_txn}    200


