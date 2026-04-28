*** Settings ***
Documentation
...    PG 연동 통합 공통 키워드 (NAG / PCF / LRS)
...
...    ┌─────────────────────────────────────────────────────┐
...    │ 인터페이스   역할          방향              포트   │
...    │ NAG         클라이언트    도구 → PG 서버     8012   │
...    │ PCF         클라이언트    도구 → PG 서버     8011   │
...    │ LRS         서버         LRS(PG) → 도구     8890   │
...    └─────────────────────────────────────────────────────┘
...
...    [NAG/PCF 소켓 정책]
...    Suite Setup   : Suite Connect / Suite Connect With NAG 1회 실행
...    Test Setup    : Check NAG Socket / Check PCF And NAG Socket
...    소켓 닫히면  : Fatal Error → Suite 즉시 중단
...
...    [LRS 소켓 정책]
...    Suite Setup   : Suite LRS Server Start → Port 8890 Listen
...    Test Setup    : Accept PG Connection → ${LRS_CONN} 저장
...    Test Teardown : Close PG Connection → 다음 TC에서 새 접속 수락
...    Suite Teardown: Suite LRS Server Stop

Library    Collections
Library    String
Library    DateTime
Library    BuiltIn
Library    ${CURDIR}/TcpHelper.py    WITH NAME    Tcp

*** Variables ***
# NAG/PCF 공유 소켓
${NAG_SOCK}      ${NONE}
${PCF_SOCK}      ${NONE}

# LRS 서버 소켓 / 클라이언트 연결 소켓
${LRS_SRV_SOCK}  ${NONE}
${LRS_CONN}      ${NONE}


# ══════════════════════════════════════════════════════════════════
# 공통 유틸리티
# ══════════════════════════════════════════════════════════════════

*** Keywords ***

Get KST Timestamp
    ${ts}=    Get Current Date    result_format=%Y-%m-%dT%H:%M:%S+09:00
    RETURN    ${ts}

Get Timestamp17
    [Documentation]    yyyyMMddHHmmssSSS 17자리 (LRS EVENT_TIMESTAMP 용)
    ${ts}=    Get Current Date    result_format=%Y%m%d%H%M%S%f
    ${ts17}=    Get Substring    ${ts}    0    17
    RETURN    ${ts17}

Next TXN ID
    [Documentation]    트랜잭션 ID 생성 (0 금지)
    ${ts}=    Get Current Date    result_format=%f
    ${txn}=    Evaluate    max(1, int('${ts}') % 2147483647)
    RETURN    ${txn}


# ══════════════════════════════════════════════════════════════════
# NAG Suite 연결 관리
# ══════════════════════════════════════════════════════════════════

Suite Connect
    [Documentation]    NAG Suite Setup 전용: TCP 연결 + Hello
    [Arguments]    ${host}    ${port}    ${sock_var}    ${timeout}=10
    Log    [Suite] NAG 연결 시작 → ${host}:${port}    console=True
    ${sock}=    Tcp.Tcp Connect    ${host}    ${port}    ${timeout}
    Set Suite Variable    ${NAG_SOCK}    ${sock}
    ${txn}=    Next TXN ID
    ${payload}=    Create Dictionary    sys-id=${NAG_SYS_ID}    branch-name=${NAG_BRANCH_NAME}
    Tcp.Send Message    ${NAG_SOCK}    ${1}    ${txn}    ${payload}
    ${hdr}    ${body}=    Tcp.Receive Message    ${NAG_SOCK}
    ${code}=    Get From Dictionary    ${body}    code
    Should Be Equal As Numbers    ${code}    200
    ...    msg=NAG Hello 실패 (code=${code}). 테스트 시작 불가.
    Log    [Suite] NAG Hello 성공 code=${code}    console=True

Suite Disconnect
    [Documentation]    NAG Suite Teardown 전용
    Run Keyword If    $NAG_SOCK is not None    Tcp.Tcp Close    ${NAG_SOCK}
    Log    [Suite] NAG 연결 종료    console=True

Check NAG Socket
    [Documentation]    NAG Test Setup 전용. 닫히면 Fatal Error.
    ${ok}=    Tcp.Is Connected    ${NAG_SOCK}
    Run Keyword If    not ${ok}
    ...    Fatal Error    NAG 소켓이 닫혀 있습니다. 이후 TC를 실행할 수 없습니다.


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
# LRS Suite 소켓 관리 (서버 모드, NAG/PCF와 동일한 Suite 단위 연결 유지)
# ══════════════════════════════════════════════════════════════════

Suite LRS Accept And Hello
    [Documentation]
    ...    LRS Suite Setup 전용
    ...    1) Port 8890 Listen 시작
    ...    2) LRS(PG) 접속 수락 → ${LRS_CONN} 저장
    ...    Hello 처리는 TC-LRS-001 에서 수행 (최초 TC)
    [Arguments]    ${host}=${LRS_SERVER_HOST}    ${port}=${LRS_SERVER_PORT}
    Log    [Suite] LRS 서버 시작 → ${host}:${port} Listen    console=True
    ${srv}=    Tcp.Server Start    ${port}    ${host}
    Set Suite Variable    ${LRS_SRV_SOCK}    ${srv}
    Log    [Suite] LRS(PG) 접속 대기 중...    console=True
    ${conn}    ${addr}=    Tcp.Server Accept    ${LRS_SRV_SOCK}    ${LRS_ACCEPT_TIMEOUT}
    Set Suite Variable    ${LRS_CONN}    ${conn}
    Log    [Suite] LRS(PG) 접속 수락: ${addr}    console=True

Suite LRS Disconnect
    [Documentation]    LRS Suite Teardown 전용. 클라이언트 연결 + 서버 소켓 모두 종료.
    Run Keyword If    $LRS_CONN is not None     Tcp.Client Close    ${LRS_CONN}
    Run Keyword If    $LRS_SRV_SOCK is not None    Tcp.Server Stop    ${LRS_SRV_SOCK}
    Log    [Suite] LRS 연결 종료    console=True

Check LRS Socket
    [Documentation]
    ...    LRS Test Setup 전용.
    ...    소켓이 닫혀 있으면 Fatal Error → Suite 즉시 중단
    ${ok}=    Tcp.Is Connected    ${LRS_CONN}
    Run Keyword If    not ${ok}
    ...    Fatal Error    LRS 소켓이 닫혀 있습니다. 이후 TC를 실행할 수 없습니다.


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
# LRS 메시지 송수신 (고정길이 ASCII, 서버 모드)
# ══════════════════════════════════════════════════════════════════

Receive From LRS PG
    [Documentation]    LRS(PG)가 보낸 메시지 수신 → (header_dict, raw_body_bytes) 반환
    ${hdr}    ${raw}=    Tcp.Receive Lrs Message    ${LRS_CONN}
    Log    [RX←LRS] type=${hdr}[msg_type] txn=${hdr}[txn_id] len=${hdr}[body_length]
    RETURN    ${hdr}    ${raw}

Send To LRS PG
    [Documentation]    LRS(PG)에게 메시지 송신
    [Arguments]    ${msg_type}    ${txn_id}    ${body_bytes}
    Tcp.Send Lrs Message    ${LRS_CONN}    ${msg_type}    ${txn_id}    ${body_bytes}
    Log    [TX→LRS] type=${msg_type} txn=${txn_id}


# ══════════════════════════════════════════════════════════════════
# NAG/PCF Hello (0x01/0x02)
# ══════════════════════════════════════════════════════════════════

Send NAG Hello
    [Arguments]    ${sys_id}    ${branch_name}    ${txn_id}=${NONE}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${payload}=    Create Dictionary    sys-id=${sys_id}    branch-name=${branch_name}
    ${hdr}    ${body}=    Send And Receive NAG    ${1}    ${txn_id}    ${payload}
    RETURN    ${hdr}    ${body}

Send PCF Hello
    [Arguments]    ${sys_id}    ${branch_name}    ${txn_id}=${NONE}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${payload}=    Create Dictionary    sys-id=${sys_id}    branch-name=${branch_name}
    ${hdr}    ${body}=    Send And Receive PCF    ${1}    ${txn_id}    ${payload}
    RETURN    ${hdr}    ${body}

Hello Should Succeed
    [Arguments]    ${resp_body}
    ${code}=    Get From Dictionary    ${resp_body}    code
    Should Be Equal As Numbers    ${code}    200    msg=Hello 실패: code=${code}

Get Ping Interval
    [Arguments]    ${resp_body}
    ${ok}=    Run Keyword And Return Status
    ...    Dictionary Should Contain Key    ${resp_body}    ping-interval
    ${interval}=    Run Keyword If    ${ok}
    ...    Get From Dictionary    ${resp_body}    ping-interval
    ...    ELSE    Set Variable    ${30}
    RETURN    ${interval}


# ══════════════════════════════════════════════════════════════════
# NAG/PCF Ping (0x03/0x04)
# ══════════════════════════════════════════════════════════════════

Send NAG Ping
    [Arguments]    ${txn_id}=${NONE}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${hdr}    ${body}=    Send And Receive NAG    ${3}    ${txn_id}    ${NONE}
    RETURN    ${hdr}    ${body}

Send PCF Ping
    [Arguments]    ${txn_id}=${NONE}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${hdr}    ${body}=    Send And Receive PCF    ${3}    ${txn_id}    ${NONE}
    RETURN    ${hdr}    ${body}

Ping Should Succeed
    [Arguments]    ${resp_body}
    ${code}=    Get From Dictionary    ${resp_body}    code
    Should Be Equal As Numbers    ${code}    200    msg=Ping 실패: code=${code}


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


# ══════════════════════════════════════════════════════════════════
# NAG ZION (0x07/0x08) PG→NAG
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

Subs Cellid Should Succeed
    [Arguments]    ${resp_body}
    ${code}=    Get From Dictionary    ${resp_body}    code
    Should Be Equal As Strings    ${code}    200
    ${cell}=    Get From Dictionary    ${resp_body}    cell-info
    Should Not Be Empty    ${cell}


# ══════════════════════════════════════════════════════════════════
# LRS Hello 처리 (0x01 수신 → 0x02 송신)
# ══════════════════════════════════════════════════════════════════

Receive And Validate LRS Hello
    [Documentation]    LRS(PG)로부터 Hello-Request(0x01) 수신 및 msg_type 검증
    ${hdr}    ${raw}=    Receive From LRS PG
    Should Be Equal As Numbers    ${hdr}[msg_type]    ${1}
    ...    msg=Hello-Request(0x01) 기대, 실제 msg_type=${hdr}[msg_type]
    ${fs}=    Evaluate    [('SYS_ID', 4), ('BRANCH_NAME', 2)]
    ${req}=    Tcp.Unpack Fields    ${raw}    ${fs}
    RETURN    ${hdr}    ${req}

Send LRS Hello Response
    [Documentation]    Hello-Response(0x02): RESULT_CODE(4) + INTERVAL(4) 송신
    [Arguments]    ${txn_id}    ${result_code}=0    ${interval}=${LRS_RESP_INTERVAL}
    ${fs}=    Evaluate    [('${result_code}', 4), ('${interval}', 4)]
    ${body}=    Tcp.Pack Fields    ${fs}
    Send To LRS PG    ${2}    ${txn_id}    ${body}


# ══════════════════════════════════════════════════════════════════
# LRS Ping 처리 (0x03 수신 → 0x04 송신)
# ══════════════════════════════════════════════════════════════════

Receive And Validate LRS Ping
    [Documentation]    LRS(PG)로부터 Ping-Request(0x03) 수신 및 msg_type 검증
    ${hdr}    ${raw}=    Receive From LRS PG
    Should Be Equal As Numbers    ${hdr}[msg_type]    ${3}
    ...    msg=Ping-Request(0x03) 기대, 실제 msg_type=${hdr}[msg_type]
    ${fs}=    Evaluate    [('SYS_ID', 4), ('BRANCH_NAME', 2)]
    ${req}=    Tcp.Unpack Fields    ${raw}    ${fs}
    RETURN    ${hdr}    ${req}

Send LRS Ping Response
    [Documentation]    Ping-Response(0x04): RESULT_CODE(4) 송신
    [Arguments]    ${txn_id}    ${result_code}=0
    ${fs}=    Evaluate    [('${result_code}', 4)]
    ${body}=    Tcp.Pack Fields    ${fs}
    Send To LRS PG    ${4}    ${txn_id}    ${body}


# ══════════════════════════════════════════════════════════════════
# LRS Location-Info 처리 (0x05 수신 → 0x06 송신)
# LRS(PG) → 도구              : Request
# 도구(PCRF/PCF 역할) → LRS(PG): Response
# ══════════════════════════════════════════════════════════════════

Receive And Validate LRS Location Info
    [Documentation]    LRS(PG)로부터 Location-Info-Request(0x05) 수신 및 msg_type 검증
    ${hdr}    ${raw}=    Receive From LRS PG
    Should Be Equal As Numbers    ${hdr}[msg_type]    ${5}
    ...    msg=Location-Info-Request(0x05) 기대, 실제 msg_type=${hdr}[msg_type]
    ${total}=    Evaluate    len(${raw})
    ${fs}=    Run Keyword If    ${total} >= 175
    ...    Evaluate    [('SYS_ID',4),('BRANCH_NAME',2),('TID',23),('EVENT_TIMESTAMP',17),('DESTINATION_HOST',62),('APN',40),('MIN',10),('MDN',11),('SERVICE_ID',6)]
    ...    ELSE
    ...    Evaluate    [('SYS_ID',4),('BRANCH_NAME',2),('TID',23),('EVENT_TIMESTAMP',17),('DESTINATION_HOST',62),('APN',40),('MIN',10),('MDN',11)]
    ${req}=    Tcp.Unpack Fields    ${raw}    ${fs}
    RETURN    ${hdr}    ${req}

Send LRS Location Info Response
    [Documentation]
    ...    Location-Info-Response(0x06) 송신
    ...    TID는 Request에서 받은 값 그대로 에코 (규격서 3.2.7)
    [Arguments]
    ...    ${txn_id}       ${req}
    ...    ${cell_info}    ${ta_code}    ${net_tp}
    ...    ${result_code}=0
    ${event_ts}=    Get Timestamp17
    ${sys_id}=      Get From Dictionary    ${req}    SYS_ID
    ${br}=          Get From Dictionary    ${req}    BRANCH_NAME
    ${tid}=         Get From Dictionary    ${req}    TID
    ${apn}=         Get From Dictionary    ${req}    APN
    ${min}=         Get From Dictionary    ${req}    MIN
    ${mdn}=         Get From Dictionary    ${req}    MDN
    ${fs}=    Evaluate
    ...    [('${sys_id}',4),('${br}',2),('${tid}',23),('${event_ts}',17),('${apn}',40),('${min}',10),('${mdn}',11),('${cell_info}',20),('${ta_code}',6),('${net_tp}',6),('${result_code}',4)]
    ${body}=    Tcp.Pack Fields    ${fs}
    Send To LRS PG    ${6}    ${txn_id}    ${body}
    Log    [TX→LRS] Location-Info-Response: MDN=${mdn} CELL=${cell_info} NET_TP=${net_tp} CODE=${result_code}


# ══════════════════════════════════════════════════════════════════
# 공통 검증 (NAG/PCF JSON 기반)
# ══════════════════════════════════════════════════════════════════

Response Code Should Be
    [Arguments]    ${resp_body}    ${expected}
    ${code}=    Get From Dictionary    ${resp_body}    code
    Should Be Equal As Strings    ${code}    ${expected}
    ...    msg=code: expected=${expected}, actual=${code}

Response Msg Type Should Be
    [Arguments]    ${resp_hdr}    ${expected}
    ${actual}=    Get From Dictionary    ${resp_hdr}    msg_type
    Should Be Equal As Numbers    ${actual}    ${expected}
    ...    msg=msg_type: expected=${expected}, actual=${actual}

TXN ID Should Match
    [Arguments]    ${req_txn_id}    ${resp_hdr}
    ${resp_txn}=    Get From Dictionary    ${resp_hdr}    txn_id
    Should Be Equal As Numbers    ${resp_txn}    ${req_txn_id}
    ...    msg=TXN ID 불일치: req=${req_txn_id} resp=${resp_txn}

Response Should Be Success
    [Arguments]    ${resp_body}
    ${code}=    Get From Dictionary    ${resp_body}    code
    ${n}=    Evaluate    int(str(${code}))
    Should Be True    200 <= ${n} <= 299

Cell Info Should Be Valid
    [Documentation]    cell-info: NodeB:Cell 또는 plmn-NodeB:Cell
    [Arguments]    ${cell_info}
    Should Match Regexp    ${cell_info}    ^(\\d+-)?\\d+:\\d+$

TA Code Should Be Valid
    [Documentation]    ta-code: Hexa 4/6자리 또는 0
    [Arguments]    ${ta_code}
    Should Match Regexp    ${ta_code}    ^([0-9a-fA-F]{4}|[0-9a-fA-F]{6}|0)$


# ══════════════════════════════════════════════════════════════════
# LRS 전용 검증
# ══════════════════════════════════════════════════════════════════

LRS Request SYS ID Should Be
    [Arguments]    ${req}    ${expected}
    ${actual}=    Get From Dictionary    ${req}    SYS_ID
    Should Be Equal As Strings    ${actual}    ${expected}
    ...    msg=SYS_ID: expected=${expected}, actual=${actual}

LRS Request Branch Name Should Be
    [Arguments]    ${req}    ${expected}
    ${actual}=    Get From Dictionary    ${req}    BRANCH_NAME
    Should Be Equal As Strings    ${actual}    ${expected}
    ...    msg=BRANCH_NAME: expected=${expected}, actual=${actual}

LRS TXN ID Should Not Be Zero
    [Arguments]    ${hdr}
    ${txn}=    Get From Dictionary    ${hdr}    txn_id
    Should Be True    ${txn} != 0    msg=TXN ID=0 금지 (규격서 명시)

LRS MDN Should Be Valid
    [Arguments]    ${req}
    ${mdn}=    Get From Dictionary    ${req}    MDN
    Should Match Regexp    ${mdn}    ^\\d{10,11}$    msg=MDN 포맷 오류: ${mdn}

LRS TID Should Be Valid
    [Documentation]    TID 23자리: prefix(4)_yyyyMMdd(8)+seq(10)
    [Arguments]    ${req}
    ${tid}=    Get From Dictionary    ${req}    TID
    Should Match Regexp    ${tid}    ^.{4}_.{18}$    msg=TID 포맷 오류 (23자리): ${tid}
