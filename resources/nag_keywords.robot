*** Settings ***
Documentation
...    NAG ↔ PG 연동 키워드 (PG-SC Message Format / JSON Body)
...
...    [인터페이스]
...      방향   : 테스트 도구(NAG 역할 / Client) → PG (Server, Port ${NAG_PG_PORT})
...      Body   : JSON (Tcp.Send Message / Receive Message)
...
...    [Suite 정책 — Single Socket]
...      Suite Setup    : Suite Connect NAG (NAG → PG(${NAG_PG_PORT}) 소켓 연결)
...      Test Setup     : Check NAG Socket (닫히면 Fatal Error)
...      Suite Teardown : Suite Disconnect NAG
...
...      Subs-Cellid(0x0b) 송신 시 PG 가 LRS-PCF 와 연동해 위치 정보를 조회하지만,
...      그 처리는 PG 내부에서 이뤄지므로 도구는 0x0c Response 만 수신/검증한다.
...
...    [메시지 흐름]
...      0x01 Hello / 0x03 Ping  (NAG → PG)
...      0x07 ZION-Request (PG → NAG) / 0x08 ZION-Response
...      0x09 Subs-Zone-Status (NAG → PG)
...      0x0b Subs-Cellid (NAG → PG, ADOT)

Library    Collections
Library    String
Library    DateTime
Library    BuiltIn
Library    ${CURDIR}/TcpHelper.py    WITH NAME    Tcp
Resource   ${CURDIR}/common_keywords.robot

*** Variables ***
${NAG_SOCK}      ${NONE}


*** Keywords ***

# ══════════════════════════════════════════════════════════════════
# NAG Suite 연결 관리 (단일 소켓)
# ══════════════════════════════════════════════════════════════════

Suite Connect NAG
    [Documentation]
    ...    NAG Suite Setup 전용. NAG → PG(${NAG_PG_PORT}) 소켓 1회 연결.
    ...    (NAG Hello 는 TC-NAG-001 에서 수행)
    [Arguments]    ${nag_host}=${NAG_PG_HOST}    ${nag_port}=${NAG_PG_PORT}
    ...            ${timeout}=${NAG_TIMEOUT}
    Log    [Suite] NAG 연결 시작 → ${nag_host}:${nag_port}    console=True
    ${nag_sock}=    Tcp.Tcp Connect    ${nag_host}    ${nag_port}    ${timeout}
    Set Suite Variable    ${NAG_SOCK}    ${nag_sock}

Suite Disconnect NAG
    [Documentation]    NAG Suite Teardown 전용. NAG 소켓 종료.
    Run Keyword If    $NAG_SOCK is not None    Tcp.Tcp Close    ${NAG_SOCK}
    Log    [Suite] NAG 연결 종료    console=True

Check NAG Socket
    [Documentation]    NAG Test Setup 전용. NAG 소켓이 닫히면 Fatal Error.
    ${ok_nag}=    Tcp.Is Connected    ${NAG_SOCK}
    Run Keyword If    not ${ok_nag}
    ...    Fatal Error    NAG 소켓이 닫혀 있습니다. 이후 TC를 실행할 수 없습니다.


# ══════════════════════════════════════════════════════════════════
# NAG 메시지 송수신 (JSON)
# ══════════════════════════════════════════════════════════════════

Send NAG Message
    [Arguments]    ${msg_type}    ${txn_id}    ${payload}=${NONE}
    Tcp.Send Message    ${NAG_SOCK}    ${msg_type}    ${txn_id}    ${payload}

Receive NAG Message
    ${hdr}    ${body}=    Tcp.Receive Message    ${NAG_SOCK}
    Log    [RX-NAG] type=0x${hdr}[msg_type] txn=${hdr}[txn_id]
    RETURN    ${hdr}    ${body}

Send And Receive NAG
    [Arguments]    ${msg_type}    ${txn_id}    ${payload}=${NONE}
    Send NAG Message    ${msg_type}    ${txn_id}    ${payload}
    ${hdr}    ${body}=    Receive NAG Message
    RETURN    ${hdr}    ${body}


# ══════════════════════════════════════════════════════════════════
# NAG Hello (0x01/0x02) / Ping (0x03/0x04)
# ══════════════════════════════════════════════════════════════════

Send NAG Hello
    [Arguments]    ${sys_id}    ${branch_name}    ${txn_id}=${NONE}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${payload}=    Create Dictionary    sys-id=${sys_id}    branch-name=${branch_name}
    ${hdr}    ${body}=    Send And Receive NAG    ${1}    ${txn_id}    ${payload}
    RETURN    ${hdr}    ${body}

Send NAG Ping
    [Arguments]    ${txn_id}=${NONE}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${hdr}    ${body}=    Send And Receive NAG    ${3}    ${txn_id}    ${NONE}
    RETURN    ${hdr}    ${body}


# ══════════════════════════════════════════════════════════════════
# NAG ZION (0x07/0x08) PG → NAG
# ══════════════════════════════════════════════════════════════════

Receive ZION Request
    [Documentation]    PG 발송 ZION-Request(0x07) NAG 소켓에서 수신 대기
    ${hdr}    ${body}=    Receive NAG Message
    Should Be Equal As Numbers    ${hdr}[msg_type]    ${7}
    ...    msg=ZION-Request(0x07) 기대, 실제=${hdr}[msg_type]
    RETURN    ${hdr}    ${body}

Send ZION Response
    [Arguments]    ${txn_id}    ${code}=200    ${cause}=${NONE}
    ${payload}=    Create Dictionary    code=${code}
    IF    $cause is not None
        Set To Dictionary    ${payload}    cause=${cause}
    END
    Send NAG Message    ${8}    ${txn_id}    ${payload}


# ══════════════════════════════════════════════════════════════════
# NAG Subs-Zone-Status (0x09/0x0a)
# ══════════════════════════════════════════════════════════════════

Send Subs Zone Status
    [Arguments]
    ...    ${sys_id}    ${branch_name}    ${mdn}
    ...    ${mobile_ip}=${NONE}
    ...    ${event_timestamp}=${NONE}     ${txn_id}=${NONE}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${event_timestamp}=    Run Keyword If    $event_timestamp is None
    ...    Get KST Timestamp    ELSE    Set Variable    ${event_timestamp}
    ${payload}=    Create Dictionary
    ...    sys-id=${sys_id}    branch-name=${branch_name}
    ...    event-timestamp=${event_timestamp}    mdn=${mdn}
    IF    $mobile_ip is not None
        Set To Dictionary    ${payload}    mobile-ip=${mobile_ip}
    END
    ${hdr}    ${body}=    Send And Receive NAG    ${9}    ${txn_id}    ${payload}
    RETURN    ${hdr}    ${body}

Subs Zone Status Should Succeed
    [Arguments]    ${resp_body}
    ${code}=    Get From Dictionary    ${resp_body}    code
    Should Be Equal As Strings    ${code}    200
    ${zone}=    Get From Dictionary    ${resp_body}    zone-info
    Should Not Be Empty    ${zone}


# ══════════════════════════════════════════════════════════════════
# NAG Subs-Cellid (0x0b/0x0c) ADOT
# ══════════════════════════════════════════════════════════════════

Send Subs Cellid
    [Arguments]
    ...    ${sys_id}    ${branch_name}    ${mdn}    ${mobile_ip}
    ...    ${event_timestamp}=${NONE}     ${txn_id}=${NONE}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${event_timestamp}=    Run Keyword If    $event_timestamp is None
    ...    Get KST Timestamp    ELSE    Set Variable    ${event_timestamp}
    ${payload}=    Create Dictionary
    ...    sys-id=${sys_id}    branch-name=${branch_name}
    ...    event-timestamp=${event_timestamp}
    ...    mdn=${mdn}          mobile-ip=${mobile_ip}
    ${hdr}    ${body}=    Send And Receive NAG    ${11}    ${txn_id}    ${payload}
    RETURN    ${hdr}    ${body}

Send Subs Cellid Request
    [Documentation]    Subs-Cellid Request(0x0b) 송신만. 응답 수신은 별도.
    [Arguments]
    ...    ${sys_id}    ${branch_name}    ${mdn}    ${mobile_ip}
    ...    ${event_timestamp}=${NONE}     ${txn_id}=${NONE}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${event_timestamp}=    Run Keyword If    $event_timestamp is None
    ...    Get KST Timestamp    ELSE    Set Variable    ${event_timestamp}
    ${payload}=    Create Dictionary
    ...    sys-id=${sys_id}    branch-name=${branch_name}
    ...    event-timestamp=${event_timestamp}
    ...    mdn=${mdn}          mobile-ip=${mobile_ip}
    Send NAG Message    ${11}    ${txn_id}    ${payload}
    RETURN    ${txn_id}

Receive Subs Cellid Response
    [Documentation]    Subs-Cellid Response(0x0c) 수신 + msg_type 검증
    ${hdr}    ${body}=    Receive NAG Message
    Should Be Equal As Numbers    ${hdr}[msg_type]    ${12}
    ...    msg=Subs-Cellid-Response(0x0c) 기대, 실제=${hdr}[msg_type]
    RETURN    ${hdr}    ${body}

Subs Cellid Should Succeed
    [Arguments]    ${resp_body}
    ${code}=    Get From Dictionary    ${resp_body}    code
    Should Be Equal As Strings    ${code}    200
    ${cell}=    Get From Dictionary    ${resp_body}    cell-info
    Should Not Be Empty    ${cell}
