*** Settings ***
Documentation
...    PCF 기능 검증 - msg_type 기준 (공유 소켓)
...
...    Suite Setup  : NAG 세션 선등록 후 PCF TCP 연결 1회 + Hello 완료
...    Test Setup   : PCF + NAG 소켓 상태 확인 (닫히면 Suite 중단)
...    각 TC        : ${PCF_SOCK} 공유 사용, TC별 연결/해제 없음

Resource    ../../resources/variables.robot
Resource    ../../resources/pcf_variables.robot
Resource    ../../resources/common_keywords.robot
Resource    ../../resources/pcf_keywords.robot

Suite Setup      Suite Connect With NAG
...              ${PCF_PG_HOST}    ${PCF_PG_PORT}    ${PCF_TIMEOUT}
Suite Teardown   Suite Disconnect With NAG
Test Setup       Check PCF And NAG Socket

*** Variables ***
${PCF_TEST_MDN}       01020300553
${PCF_SERVICE_ID}     ZN100001

*** Test Cases ***

# ── 0x01/0x02 Hello ──────────────────────────────────────────────

TC-PCF-001 Hello - ping-interval 확인
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

TC-PCF-002 Ping - 정상 응답
    [Documentation]    0x03 전송(Body 없음) → 0x04 수신, code=200, TXN ID 에코
    [Tags]    pcf    ping    smoke
    ${txn}=    Next TXN ID
    ${hdr}    ${body}=    Send PCF Ping    ${txn}
    Response Msg Type Should Be    ${hdr}    ${4}
    TXN ID Should Match    ${txn}    ${hdr}
    Ping Should Succeed    ${body}

TC-PCF-003 Ping - Body 없음 검증
    [Documentation]    body_length=0 헤더만 전송 (규격 4.2.2)
    [Tags]    pcf    ping
    ${txn}=    Next TXN ID
    Send PCF Message    ${3}    ${txn}    ${NONE}
    ${hdr}    ${body}=    Receive PCF Message
    Response Msg Type Should Be    ${hdr}    ${4}
    Ping Should Succeed    ${body}

TC-PCF-004 Ping - TXN ID 순차 에코
    [Documentation]    Ping 연속 2회 TXN ID 에코
    [Tags]    pcf    ping
    FOR    ${i}    IN RANGE    2
        ${txn}=    Next TXN ID
        ${hdr}    ${body}=    Send PCF Ping    ${txn}
        TXN ID Should Match    ${txn}    ${hdr}
        Ping Should Succeed    ${body}
    END


# ── 0x05/0x06 Zone-InOut ─────────────────────────────────────────

TC-PCF-005 Zone-InOut - Zone IN (LTE)
    [Documentation]
    ...    0x05 전송 → 0x06 수신 (code=200)
    ...    zone-info=I, rat-type=L, ta-code=Hexa 4자리
    ...    ※ PG는 Zone IN 수신 후 NAG로 ZION-Request(0x07)를 발송함
    ...      → TC-NAG-014 에서 ZION 수신/응답 처리
    [Tags]    pcf    zone-inout    smoke
    ${txn}=    Next TXN ID
    ${hdr}    ${body}=    Send PCF Zone InOut
    ...    sys_id=${PCF_SYS_ID}         branch_name=${PCF_BRANCH_NAME}
    ...    mdn=${PCF_TEST_MDN}          client_host=${TEST_CLIENT_HOST}
    ...    mobile_ip=10.10.10.10        cell_info=${TEST_CELL_INFO}
    ...    ta_code=3113                 rat_type=L
    ...    zone_info=I                  apn=${TEST_APN}
    ...    service_id=${PCF_SERVICE_ID}
    ...    txn_id=${txn}
    Response Msg Type Should Be    ${hdr}    ${6}
    TXN ID Should Match    ${txn}    ${hdr}
    PCF Zone InOut Should Succeed    ${body}
    Log    [TC-PCF-005] Zone IN 200 수신 완료. PG → NAG ZION 발송 예상 → TC-NAG-014 에서 처리

TC-NAG-014 ZION 수신 및 0x08 정상 응답 (code=200)
    [Documentation]
    ...    TC-PCF-005 Zone IN 후 PG가 NAG로 발송하는 ZION-Request(0x07) 수신
    ...    → 필드 검증 → ZION-Response(0x08) code=200 전송
    ...    ※ NAG 소켓(${NAG_SOCK})을 공유하여 처리 (PCF Suite 내 실행)
    [Tags]    pcf    nag    zion    smoke
    ${hdr}    ${body}=    Receive ZION Request
    Log    [TC-NAG-014] ZION 수신: mdn=${body}[mdn]
    Dictionary Should Contain Key    ${body}    mdn
    Dictionary Should Contain Key    ${body}    zone-info
    Dictionary Should Contain Key    ${body}    cell-info
    Dictionary Should Contain Key    ${body}    rat-type
    ${zone}=    Get From Dictionary    ${body}    zone-info
    Should Be True    '${zone}' in ['I', 'O']    msg=zone-info 기대 I/O, 실제=${zone}
    Cell Info Should Be Valid    ${body}[cell-info]
    ${req_txn}=    Get From Dictionary    ${hdr}    txn_id
    Send ZION Response    ${req_txn}    200
    Log    [TC-NAG-014] ZION-Response(0x08) code=200 전송 완료

TC-PCF-006 Zone-InOut - Zone OUT (5G)
    [Documentation]
    ...    zone-info=O, rat-type=S, ta-code=0 (ZONE OUT 시 0)
    ...    PCF 200 수신 후 → TC-NAG-015 에서 ZION 수신/응답 처리
    [Tags]    pcf    zone-inout
    ${hdr}    ${body}=    Send PCF Zone InOut
    ...    sys_id=SPCF0001              branch_name=${PCF_BRANCH_NAME}
    ...    mdn=${PCF_TEST_MDN}          client_host=smf01.5gsktelecom.net
    ...    mobile_ip=${TEST_MOBILE_IP}  cell_info=${TEST_CELL_INFO}
    ...    ta_code=0                    rat_type=S
    ...    zone_info=O                  apn=5g.sktelecom.com
    ...    service_id=${PCF_SERVICE_ID}
    PCF Zone InOut Should Succeed    ${body}
    Log    [TC-PCF-006] Zone OUT 200 수신 완료. PG → NAG ZION 발송 예상 → TC-NAG-015 에서 처리

TC-NAG-015 ZION 수신 및 0x08 정상 응답 - Zone OUT (5G)
    [Documentation]
    ...    TC-PCF-006 Zone OUT 후 PG가 NAG로 발송하는 ZION-Request(0x07) 수신
    ...    → zone-info=O 검증 → ZION-Response(0x08) code=200 전송
    [Tags]    pcf    nag    zion
    ${zion_hdr}    ${zion_body}=    Receive ZION Request
    Log    [TC-NAG-015] ZION 수신: mdn=${zion_body}[mdn]
    Dictionary Should Contain Key    ${zion_body}    mdn
    Dictionary Should Contain Key    ${zion_body}    zone-info
    ${zone}=    Get From Dictionary    ${zion_body}    zone-info
    Should Be Equal As Strings    ${zone}    O    msg=ZION zone-info 기대 O, 실제=${zone}
    ${zion_txn}=    Get From Dictionary    ${zion_hdr}    txn_id
    Send ZION Response    ${zion_txn}    200
    Log    [TC-NAG-015] ZION-Response(0x08) code=200 전송 완료

TC-PCF-007 Zone-InOut - Zone IN (3G, 타사망)
    [Documentation]
    ...    rat-type=W, 타사망 cell-info(plmn-NodeB:Cell), ta-code=Hexa 6자리
    ...    PCF 200 수신 후 → TC-NAG-016 에서 ZION 수신/응답 처리
    [Tags]    pcf    zone-inout
    ${hdr}    ${body}=    Send PCF Zone InOut
    ...    sys_id=${PCF_SYS_ID}         branch_name=${PCF_BRANCH_NAME}
    ...    mdn=${PCF_TEST_MDN}          client_host=${TEST_CLIENT_HOST}
    ...    mobile_ip=10.10.10.10        cell_info=45006-9999:99
    ...    ta_code=008461               rat_type=W
    ...    zone_info=I                  apn=shi.sktelecom.com
    ...    service_id=${PCF_SERVICE_ID}
    PCF Zone InOut Should Succeed    ${body}
    Log    [TC-PCF-007] Zone IN 200 수신 완료. PG → NAG ZION 발송 예상 → TC-NAG-016 에서 처리

TC-NAG-016 ZION 수신 및 0x08 정상 응답 - Zone IN (3G, 타사망)
    [Documentation]
    ...    TC-PCF-007 Zone IN 후 PG가 NAG로 발송하는 ZION-Request(0x07) 수신
    ...    → zone-info=I, cell-info 포맷(plmn-NodeB:Cell) 검증 → ZION-Response(0x08) code=200 전송
    [Tags]    pcf    nag    zion
    ${zion_hdr}    ${zion_body}=    Receive ZION Request
    Log    [TC-NAG-016] ZION 수신: mdn=${zion_body}[mdn]
    Dictionary Should Contain Key    ${zion_body}    mdn
    Dictionary Should Contain Key    ${zion_body}    zone-info
    Dictionary Should Contain Key    ${zion_body}    cell-info
    ${zone}=    Get From Dictionary    ${zion_body}    zone-info
    Should Be Equal As Strings    ${zone}    I    msg=ZION zone-info 기대 I, 실제=${zone}
    Cell Info Should Be Valid    ${zion_body}[cell-info]
    ${zion_txn}=    Get From Dictionary    ${zion_hdr}    txn_id
    Send ZION Response    ${zion_txn}    200
    Log    [TC-NAG-016] ZION-Response(0x08) code=200 전송 완료

TC-PCF-008 Zone-InOut - TXN ID 에코
    [Documentation]
    ...    Zone-InOut Response TXN ID 에코 검증
    ...    PCF 200 수신 후 → TC-NAG-017 에서 ZION 수신/응답 처리
    [Tags]    pcf    zone-inout    validation
    ${txn}=    Next TXN ID
    ${hdr}    ${body}=    Send PCF Zone InOut
    ...    sys_id=${PCF_SYS_ID}         branch_name=${PCF_BRANCH_NAME}
    ...    mdn=${PCF_TEST_MDN}          client_host=${TEST_CLIENT_HOST}
    ...    mobile_ip=10.10.10.10        cell_info=${TEST_CELL_INFO}
    ...    ta_code=3113                 rat_type=L
    ...    zone_info=I                  apn=${TEST_APN}
    ...    service_id=${PCF_SERVICE_ID}
    ...    txn_id=${txn}
    TXN ID Should Match    ${txn}    ${hdr}
    Log    [TC-PCF-008] Zone IN 200 수신 완료. PG → NAG ZION 발송 예상 → TC-NAG-017 에서 처리

TC-NAG-017 ZION 수신 및 0x08 정상 응답 - TXN ID 에코 확인
    [Documentation]
    ...    TC-PCF-008 Zone IN 후 PG가 NAG로 발송하는 ZION-Request(0x07) 수신
    ...    → ZION txn_id 에코 검증 → ZION-Response(0x08) code=200 전송
    [Tags]    pcf    nag    zion    validation
    ${zion_hdr}    ${zion_body}=    Receive ZION Request
    Log    [TC-NAG-017] ZION 수신: mdn=${zion_body}[mdn]
    Dictionary Should Contain Key    ${zion_body}    mdn
    ${zion_txn}=    Get From Dictionary    ${zion_hdr}    txn_id
    Send ZION Response    ${zion_txn}    200
    Log    [TC-NAG-017] ZION-Response(0x08) code=200 전송 완료 (txn=${zion_txn})
