*** Settings ***
Documentation
...    NAG 통합 Regression 검증 — 단일 슈트, TC-NAG-001~017.
...    [TC 번호 체계] 001~007: NAG 요청 / 008~017: PCF 연동.
...    Suite Setup: 경로 상태 초기화. Test Setup에서 선택된 첫 경로를 준비한다.
...    NAG 경로: LRS-PCF accept + Hello 후 NAG 연결. TC-001에서 NAG Hello 검증.
...    PCF 경로: 앞 경로 연결 정리 후 NAG Hello 선등록 → PCF 연결 + Hello.
...    PCF만 선택하면 LRS-PCF 접속을 기다리지 않는다.
...    일반 TC 간 소켓은 공유하며 경로는 NAG→PCF 순서로 한 번만 전환한다.
...    Suite Teardown은 부분 초기화 실패에도 LRS/PCF/NAG 연결을 모두 정리한다.
...    기존 기동 대기 PG_SSH_SETTLE은 경로 초기화로 옮겨 보존한다.

Resource    ../../resources/variables.robot
Resource    ../../resources/nag_variables.robot
Resource    ../../resources/pcf_variables.robot
Resource    ../../resources/common_keywords.robot
Resource    ../../resources/ssh_keywords.robot
Resource    ../../resources/nag_keywords.robot
Resource    ../../resources/lrs_keywords.robot
Resource    ../../resources/nag_suite_keywords.robot


Suite Setup    Initialize NAG Regression
Suite Teardown    Close NAG Regression Connections
Test Setup    Prepare NAG Regression Test
Force Tags    nag

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
    ...    ${NAG_MDN_NORMAL}    ${NAG_MOBILE_IP}    txn_id=${txn}
    Response Msg Type Should Be    ${hdr}    ${10}
    TXN ID Should Match    ${txn}    ${hdr}
    Subs Zone Status Should Succeed    ${body}
    ${zone}=    Get From Dictionary    ${body}    zone-info
    Should Be True    '${zone}' in ['I', 'O']

TC-NAG-004 Subs-Zone-Status - mobile-ip 미포함 (Optional)
    [Documentation]    mobile-ip 없이 mdn만 요청 (Optional 필드)
    [Tags]    nag    subs-zone
    ${hdr}    ${body}=    Send Subs Zone Status
    ...    ${NAG_SYS_ID}    ${NAG_BRANCH_NAME}    ${NAG_MDN_NORMAL}
    Response Should Be Success    ${body}

TC-NAG-005 Subs-Zone-Status - HFC 미가입 (402)
    [Documentation]    미가입 MDN → code=402, cause 포함
    [Tags]    nag    subs-zone    negative
    ${hdr}    ${body}=    Send Subs Zone Status
    ...    ${NAG_SYS_ID}    ${NAG_BRANCH_NAME}    ${NAG_MDN_NO_HFC}
    Response Code Should Be    ${body}    402
    Dictionary Should Contain Key    ${body}    cause

TC-NAG-006 Subs-Zone-Status - 세션 없음 (402)
    [Documentation]    세션 없는 MDN → code=402 또는 403, cause 포함
    [Tags]    nag    subs-zone    negative
    ${hdr}    ${body}=    Send Subs Zone Status
    ...    ${NAG_SYS_ID}    ${NAG_BRANCH_NAME}    ${NAG_MDN_NO_SESSION}
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
    ...    ${NAG_MDN_NORMAL}    ${NAG_MOBILE_IP}
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



# ════════════════════════════════════════════════════════════════
# PCF 연동 경로 — TC-NAG-008 ~ 017 (NAG 등록 선행)
# ════════════════════════════════════════════════════════════════


# ── 0x01/0x02 Hello ──────────────────────────────────────────────

TC-NAG-008 Hello - ping-interval 확인
    [Documentation]    Hello-Response(0x02) ping-interval 포함 및 TXN ID 에코
    [Tags]    pcf    hello    smoke
    ${txn}=    Next TXN ID
    ${hdr}    ${body}=    Send PCF Hello    ${PCF_SYS_ID}    ${PCF_BRANCH_NAME}    ${txn}
    Response Msg Type Should Be    ${hdr}    ${2}
    TXN ID Should Match    ${txn}    ${hdr}
    Hello Should Succeed    ${body}
    ${pi}=    Get Ping Interval    ${body}
    Should Be True    ${pi} > 0    msg=ping-interval 누락 또는 0


# ── 0x03/0x04 Ping ───────────────────────────────────────────────

TC-NAG-009 Ping - 정상 응답
    [Documentation]    0x03 전송(Body 없음) → 0x04 수신, code=200, TXN ID 에코
    [Tags]    pcf    ping    smoke
    ${txn}=    Next TXN ID
    ${hdr}    ${body}=    Send PCF Ping    ${txn}
    Response Msg Type Should Be    ${hdr}    ${4}
    TXN ID Should Match    ${txn}    ${hdr}
    Ping Should Succeed    ${body}

# ── 0x05/0x06 Zone-InOut ─────────────────────────────────────────

TC-NAG-010 Zone-InOut - Zone IN (LTE)
    [Documentation]
    ...    0x05 전송 → 0x06 수신 (code=200)
    ...    zone-info=I, rat-type=L, ta-code=Hexa 4자리
    ...    ※ PG는 Zone IN 수신 후 NAG로 ZION-Request(0x07)를 발송함
    ...      → TC-NAG-010 에서 ZION 수신/응답 처리
    [Tags]    pcf    zone-inout    smoke
    ${txn}=    Next TXN ID
    ${hdr}    ${body}=    Send PCF Zone InOut
    ...    sys_id=${PCF_SYS_ID}         branch_name=${PCF_BRANCH_NAME}
    ...    mdn=${PCF_TEST_MDN}          client_host=${NAG_CLIENT_HOST}
    ...    mobile_ip=10.10.10.10        cell_info=${NAG_CELL_INFO}
    ...    ta_code=3113                 rat_type=L
    ...    zone_info=I                  apn=${NAG_APN}
    ...    service_id=${PCF_SERVICE_ID}
    ...    txn_id=${txn}
    Response Msg Type Should Be    ${hdr}    ${6}
    TXN ID Should Match    ${txn}    ${hdr}
    PCF Zone InOut Should Succeed    ${body}
    Log    [TC-NAG-010] Zone IN 200 수신 완료. PG → NAG ZION 발송 예상 → TC-NAG-011 에서 처리

TC-NAG-011 ZION 수신 및 0x08 정상 응답 (code=200)
    [Documentation]
    ...    TC-NAG-010 Zone IN 후 PG가 NAG로 발송하는 ZION-Request(0x07) 수신
    ...    → 필드 검증 → ZION-Response(0x08) code=200 전송
    ...    ※ NAG 소켓(${NAG_SOCK})을 공유하여 처리 (PCF Suite 내 실행)
    [Tags]    pcf    nag    zion    smoke
    ${hdr}    ${body}=    Receive ZION Request
    Log    [TC-NAG-011] ZION 수신: mdn=${body}[mdn]
    Dictionary Should Contain Key    ${body}    mdn
    Dictionary Should Contain Key    ${body}    zone-info
    Dictionary Should Contain Key    ${body}    cell-info
    Dictionary Should Contain Key    ${body}    rat-type
    ${zone}=    Get From Dictionary    ${body}    zone-info
    Should Be True    '${zone}' in ['I', 'O']    msg=zone-info 기대 I/O, 실제=${zone}
    Cell Info Should Be Valid    ${body}[cell-info]
    ${req_txn}=    Get From Dictionary    ${hdr}    txn_id
    Send ZION Response    ${req_txn}    200
    Log    [TC-NAG-011] ZION-Response(0x08) code=200 전송 완료

TC-NAG-012 Zone-InOut - Zone OUT (5G)
    [Documentation]
    ...    zone-info=O, rat-type=S, ta-code=0 (ZONE OUT 시 0)
    ...    PCF 200 수신 후 → TC-NAG-013 에서 ZION 수신/응답 처리
    [Tags]    pcf    zone-inout
    ${hdr}    ${body}=    Send PCF Zone InOut
    ...    sys_id=SPCF0001              branch_name=${PCF_BRANCH_NAME}
    ...    mdn=${PCF_TEST_MDN}          client_host=smf01.5gsktelecom.net
    ...    mobile_ip=${NAG_MOBILE_IP}   cell_info=${NAG_CELL_INFO}
    ...    ta_code=0                    rat_type=S
    ...    zone_info=O                  apn=5g.sktelecom.com
    ...    service_id=${PCF_SERVICE_ID}
    PCF Zone InOut Should Succeed    ${body}
    Log    [TC-NAG-012] Zone OUT 200 수신 완료. PG → NAG ZION 발송 예상 → TC-NAG-013 에서 처리

TC-NAG-013 ZION 수신 및 0x08 정상 응답 - Zone OUT (5G)
    [Documentation]
    ...    TC-NAG-012 Zone OUT 후 PG가 NAG로 발송하는 ZION-Request(0x07) 수신
    ...    → zone-info=O 검증 → ZION-Response(0x08) code=200 전송
    [Tags]    pcf    nag    zion
    ${zion_hdr}    ${zion_body}=    Receive ZION Request
    Log    [TC-NAG-013] ZION 수신: mdn=${zion_body}[mdn]
    Dictionary Should Contain Key    ${zion_body}    mdn
    Dictionary Should Contain Key    ${zion_body}    zone-info
    ${zone}=    Get From Dictionary    ${zion_body}    zone-info
    Should Be Equal As Strings    ${zone}    O    msg=ZION zone-info 기대 O, 실제=${zone}
    ${zion_txn}=    Get From Dictionary    ${zion_hdr}    txn_id
    Send ZION Response    ${zion_txn}    200
    Log    [TC-NAG-013] ZION-Response(0x08) code=200 전송 완료

TC-NAG-014 Zone-InOut - Zone IN (3G, 타사망)
    [Documentation]
    ...    rat-type=W, 타사망 cell-info(plmn-NodeB:Cell), ta-code=Hexa 6자리
    ...    PCF 200 수신 후 → TC-NAG-015 에서 ZION 수신/응답 처리
    [Tags]    pcf    zone-inout
    ${hdr}    ${body}=    Send PCF Zone InOut
    ...    sys_id=${PCF_SYS_ID}         branch_name=${PCF_BRANCH_NAME}
    ...    mdn=${PCF_TEST_MDN}          client_host=${NAG_CLIENT_HOST}
    ...    mobile_ip=10.10.10.10        cell_info=45006-9999:99
    ...    ta_code=008461               rat_type=W
    ...    zone_info=I                  apn=shi.sktelecom.com
    ...    service_id=${PCF_SERVICE_ID}
    PCF Zone InOut Should Succeed    ${body}
    Log    [TC-NAG-014] Zone IN 200 수신 완료. PG → NAG ZION 발송 예상 → TC-NAG-015 에서 처리

TC-NAG-015 ZION 수신 및 0x08 정상 응답 - Zone IN (3G, 타사망)
    [Documentation]
    ...    TC-NAG-014 Zone IN 후 PG가 NAG로 발송하는 ZION-Request(0x07) 수신
    ...    → zone-info=I, cell-info 포맷(plmn-NodeB:Cell) 검증 → ZION-Response(0x08) code=200 전송
    [Tags]    pcf    nag    zion
    ${zion_hdr}    ${zion_body}=    Receive ZION Request
    Log    [TC-NAG-015] ZION 수신: mdn=${zion_body}[mdn]
    Dictionary Should Contain Key    ${zion_body}    mdn
    Dictionary Should Contain Key    ${zion_body}    zone-info
    Dictionary Should Contain Key    ${zion_body}    cell-info
    ${zone}=    Get From Dictionary    ${zion_body}    zone-info
    Should Be Equal As Strings    ${zone}    I    msg=ZION zone-info 기대 I, 실제=${zone}
    Cell Info Should Be Valid    ${zion_body}[cell-info]
    ${zion_txn}=    Get From Dictionary    ${zion_hdr}    txn_id
    Send ZION Response    ${zion_txn}    200
    Log    [TC-NAG-015] ZION-Response(0x08) code=200 전송 완료

TC-NAG-016 Zone-InOut - TXN ID 에코
    [Documentation]
    ...    Zone-InOut Response TXN ID 에코 검증
    ...    PCF 200 수신 후 → TC-NAG-017 에서 ZION 수신/응답 처리
    [Tags]    pcf    zone-inout    validation
    ${txn}=    Next TXN ID
    ${hdr}    ${body}=    Send PCF Zone InOut
    ...    sys_id=${PCF_SYS_ID}         branch_name=${PCF_BRANCH_NAME}
    ...    mdn=${PCF_TEST_MDN}          client_host=${NAG_CLIENT_HOST}
    ...    mobile_ip=10.10.10.10        cell_info=${NAG_CELL_INFO}
    ...    ta_code=3113                 rat_type=L
    ...    zone_info=I                  apn=${NAG_APN}
    ...    service_id=${PCF_SERVICE_ID}
    ...    txn_id=${txn}
    TXN ID Should Match    ${txn}    ${hdr}
    Log    [TC-NAG-016] Zone IN 200 수신 완료. PG → NAG ZION 발송 예상 → TC-NAG-0176 에서 처리

TC-NAG-017 ZION 수신 및 0x08 정상 응답 - TXN ID 에코 확인
    [Documentation]
    ...    TC-NAG-016 Zone IN 후 PG가 NAG로 발송하는 ZION-Request(0x07) 수신
    ...    → ZION txn_id 에코 검증 → ZION-Response(0x08) code=200 전송
    [Tags]    pcf    nag    zion    validation
    ${zion_hdr}    ${zion_body}=    Receive ZION Request
    Log    [TC-NAG-017] ZION 수신: mdn=${zion_body}[mdn]
    Dictionary Should Contain Key    ${zion_body}    mdn
    ${zion_txn}=    Get From Dictionary    ${zion_hdr}    txn_id
    Send ZION Response    ${zion_txn}    200
    Log    [TC-NAG-017] ZION-Response(0x08) code=200 전송 완료 (txn=${zion_txn})
