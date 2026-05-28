*** Settings ***
Documentation
...    PCF ↔ PG 연동 키워드 (PG-SC Message Format / JSON Body)
...
...    [인터페이스]
...      방향   : 테스트 도구(PCF 역할 / Client) → PG (Server, Port ${PCF_PG_PORT})
...      Body   : JSON
...
...    [Suite 정책 — Dual Socket]
...      Suite Setup    : Suite Connect With NAG
...        1) NAG → PG(${NAG_PG_PORT}) Hello → NAG 세션 등록
...        2) PCF → PG(${PCF_PG_PORT}) 연결 + Hello
...      Test Setup     : Check PCF And NAG Socket (둘 중 하나라도 닫히면 Fatal Error)
...      Suite Teardown : Suite Disconnect With NAG
...
...    [메시지 흐름]
...      0x01 Hello / 0x03 Ping  (PCF → PG)
...      0x05 Zone-InOut-Request / 0x06 Zone-InOut-Response (PCF → PG)

Library    Collections
Library    String
Library    DateTime
Library    BuiltIn
Library    ${CURDIR}/TcpHelper.py    WITH NAME    Tcp
Resource   ${CURDIR}/common_keywords.robot
Resource   ${CURDIR}/nag_keywords.robot

*** Variables ***
${PCF_SOCK}      ${NONE}


*** Keywords ***

# ══════════════════════════════════════════════════════════════════
# PCF Suite 연결 관리 (NAG 세션 선등록 포함)
# ══════════════════════════════════════════════════════════════════

Suite Connect With NAG
    [Documentation]
    ...    PCF Suite Setup 전용
    ...    1) NAG → PG(8012) Hello → NAG 세션 등록
    ...    2) PCF → PG(8011) 연결 + Hello
    [Arguments]    ${pcf_host}    ${pcf_port}    ${timeout}=10
    Log    [Suite] NAG 세션 선등록 → ${NAG_PG_HOST}:${NAG_PG_PORT}    console=True
    ${nag_sock}=    Tcp.Tcp Connect    ${NAG_PG_HOST}    ${NAG_PG_PORT}    ${timeout}
    Set Suite Variable    ${NAG_SOCK}    ${nag_sock}
    ${txn}=    Next TXN ID
    ${nag_payload}=    Create Dictionary
    ...    sys-id=${NAG_SYS_ID}    branch-name=${NAG_BRANCH_NAME}
    Tcp.Send Message    ${NAG_SOCK}    ${1}    ${txn}    ${nag_payload}
    ${hdr}    ${body}=    Tcp.Receive Message    ${NAG_SOCK}
    ${code}=    Get From Dictionary    ${body}    code
    Should Be Equal As Numbers    ${code}    200
    ...    msg=NAG Hello 실패 (code=${code}). PCF 테스트 시작 불가.
    Log    [Suite] NAG Hello 성공 code=${code}    console=True
    Log    [Suite] PCF 연결 시작 → ${pcf_host}:${pcf_port}    console=True
    ${pcf_sock}=    Tcp.Tcp Connect    ${pcf_host}    ${pcf_port}    ${timeout}
    Set Suite Variable    ${PCF_SOCK}    ${pcf_sock}
    ${txn2}=    Next TXN ID
    ${pcf_payload}=    Create Dictionary
    ...    sys-id=${PCF_SYS_ID}    branch-name=${PCF_BRANCH_NAME}
    Tcp.Send Message    ${PCF_SOCK}    ${1}    ${txn2}    ${pcf_payload}
    ${hdr2}    ${body2}=    Tcp.Receive Message    ${PCF_SOCK}
    ${code2}=    Get From Dictionary    ${body2}    code
    Should Be Equal As Numbers    ${code2}    200
    ...    msg=PCF Hello 실패 (code=${code2}). 테스트 시작 불가.
    Log    [Suite] PCF Hello 성공 code=${code2}    console=True

Suite Disconnect With NAG
    [Documentation]    PCF Suite Teardown 전용. PCF + NAG 소켓 종료.
    Run Keyword If    $PCF_SOCK is not None    Tcp.Tcp Close    ${PCF_SOCK}
    Run Keyword If    $NAG_SOCK is not None    Tcp.Tcp Close    ${NAG_SOCK}
    Log    [Suite] PCF + NAG 연결 종료    console=True

Check PCF And NAG Socket
    [Documentation]    PCF Test Setup 전용. 닫히면 Fatal Error.
    ${ok_pcf}=    Tcp.Is Connected    ${PCF_SOCK}
    ${ok_nag}=    Tcp.Is Connected    ${NAG_SOCK}
    Run Keyword If    not ${ok_pcf}
    ...    Fatal Error    PCF 소켓이 닫혀 있습니다. 이후 TC를 실행할 수 없습니다.
    Run Keyword If    not ${ok_nag}
    ...    Fatal Error    NAG 소켓이 닫혀 있습니다. 이후 TC를 실행할 수 없습니다.


# ══════════════════════════════════════════════════════════════════
# PCF 메시지 송수신 (JSON)
# ══════════════════════════════════════════════════════════════════

Send PCF Message
    [Arguments]    ${msg_type}    ${txn_id}    ${payload}=${NONE}
    Tcp.Send Message    ${PCF_SOCK}    ${msg_type}    ${txn_id}    ${payload}

Receive PCF Message
    ${hdr}    ${body}=    Tcp.Receive Message    ${PCF_SOCK}
    Log    [RX-PCF] type=0x${hdr}[msg_type] txn=${hdr}[txn_id]
    RETURN    ${hdr}    ${body}

Send And Receive PCF
    [Arguments]    ${msg_type}    ${txn_id}    ${payload}=${NONE}
    Send PCF Message    ${msg_type}    ${txn_id}    ${payload}
    ${hdr}    ${body}=    Receive PCF Message
    RETURN    ${hdr}    ${body}


# ══════════════════════════════════════════════════════════════════
# PCF Hello (0x01/0x02) / Ping (0x03/0x04)
# ══════════════════════════════════════════════════════════════════

Send PCF Hello
    [Arguments]    ${sys_id}    ${branch_name}    ${txn_id}=${NONE}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${payload}=    Create Dictionary    sys-id=${sys_id}    branch-name=${branch_name}
    ${hdr}    ${body}=    Send And Receive PCF    ${1}    ${txn_id}    ${payload}
    RETURN    ${hdr}    ${body}

Send PCF Ping
    [Arguments]    ${txn_id}=${NONE}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${hdr}    ${body}=    Send And Receive PCF    ${3}    ${txn_id}    ${NONE}
    RETURN    ${hdr}    ${body}


# ══════════════════════════════════════════════════════════════════
# PCF Zone-InOut (0x05/0x06)
# ══════════════════════════════════════════════════════════════════

Send PCF Zone InOut
    [Arguments]
    ...    ${sys_id}       ${branch_name}
    ...    ${mdn}          ${client_host}  ${mobile_ip}
    ...    ${cell_info}    ${ta_code}      ${rat_type}
    ...    ${zone_info}    ${apn}          ${service_id}
    ...    ${event_timestamp}=${NONE}      ${txn_id}=${NONE}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${event_timestamp}=    Run Keyword If    $event_timestamp is None
    ...    Get KST Timestamp    ELSE    Set Variable    ${event_timestamp}
    ${payload}=    Create Dictionary
    ...    sys-id=${sys_id}              branch-name=${branch_name}
    ...    event-timestamp=${event_timestamp}
    ...    mdn=${mdn}                    client-host=${client_host}
    ...    mobile-ip=${mobile_ip}        cell-info=${cell_info}
    ...    ta-code=${ta_code}            rat-type=${rat_type}
    ...    zone-info=${zone_info}        apn=${apn}
    ...    service-id=${service_id}
    ${hdr}    ${body}=    Send And Receive PCF    ${5}    ${txn_id}    ${payload}
    RETURN    ${hdr}    ${body}

PCF Zone InOut Should Succeed
    [Arguments]    ${resp_body}
    ${code}=    Get From Dictionary    ${resp_body}    code
    Should Be Equal As Numbers    ${code}    200    msg=ZoneInOut 실패: code=${code}
