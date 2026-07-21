*** Settings ***
Documentation
...    LRS ↔ PG 연동 키워드 (PG-SC Message Format / 고정길이 ASCII Body)
...
...    [인터페이스]
...      방향   : LRS(PG) → 테스트 도구 (도구가 PCRF/PCF 역할 / 서버)
...      포트   : ${LRS_SERVER_PORT} (도구가 Listen, LRS(PG) 가 접속)
...      Body   : 고정길이 ASCII 필드 (Tcp.Pack Fields / Unpack Fields)
...
...    [Suite 정책]
...      Suite Setup    : Suite LRS Accept → Listen + accept → ${LRS_CONN}
...      Test Setup     : Check LRS Socket (닫히면 Fatal Error)
...      Suite Teardown : Suite LRS Disconnect
...
...    [메시지 흐름 — 모두 LRS(PG) 가 Request 발신]
...      0x01 Hello-Request          / 0x02 Hello-Response
...      0x03 Ping-Request           / 0x04 Ping-Response
...      0x05 Location-Info-Request  / 0x06 Location-Info-Response

Library    Collections
Library    String
Library    DateTime
Library    BuiltIn
Library    ${CURDIR}/TcpHelper.py    WITH NAME    Tcp
Resource   ${CURDIR}/common_keywords.robot

*** Variables ***
# LRS 서버 소켓 / 클라이언트 연결 소켓
${LRS_SRV_SOCK}  ${NONE}
${LRS_CONN}      ${NONE}


*** Keywords ***

# ══════════════════════════════════════════════════════════════════
# LRS Suite 소켓 관리 (서버 모드)
# ══════════════════════════════════════════════════════════════════

Suite LRS Accept
    [Documentation]
    ...    LRS Suite Setup 전용
    ...    1) Port ${LRS_SERVER_PORT} Listen 시작
    ...    2) 허용 IP(${allowed_ips}) 에서 온 접속만 수락 → ${LRS_CONN} 저장
    ...       (그 외 IP 는 거부하고 남은 시간 동안 계속 대기)
    ...    Hello 처리는 TC-LRS-001 에서 수행 (최초 TC)
    [Arguments]    ${host}=${LRS_SERVER_HOST}    ${port}=${LRS_SERVER_PORT}
    ...            ${allowed_ips}=${LRS_ALLOWED_PEER_IPS}
    Log    [Suite] LRS 서버 시작 → ${host}:${port} Listen (허용 IP: ${allowed_ips})    console=True
    ${srv}=    Tcp.Server Start    ${port}    ${host}
    Set Suite Variable    ${LRS_SRV_SOCK}    ${srv}
    Log    [Suite] LRS(PG) 접속 대기 중...    console=True
    ${conn}    ${addr}=    Tcp.Server Accept    ${LRS_SRV_SOCK}    ${LRS_ACCEPT_TIMEOUT}    ${allowed_ips}
    Set Suite Variable    ${LRS_CONN}    ${conn}
    Log    [Suite] LRS(PG) 접속 수락: ${addr}    console=True

Suite LRS Disconnect
    [Documentation]    LRS Suite Teardown 전용. 클라이언트 연결 + 서버 소켓 모두 종료.
    Run Keyword If    $LRS_CONN is not None        Tcp.Client Close    ${LRS_CONN}
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
# LRS 메시지 송수신 (고정길이 ASCII)
# ══════════════════════════════════════════════════════════════════

Receive From LRS PG
    [Documentation]    LRS(PG)가 보낸 메시지 수신 → (header_dict, raw_body_bytes) 반환
    ${hdr}    ${raw}=    Tcp.Receive Lrs Message    ${LRS_CONN}
    Log    [RX←LRS] type=${hdr}[msg_type] txn=${hdr}[txn_id] len=${hdr}[body_length]
    RETURN    ${hdr}    ${raw}

Send To LRS PG
    [Documentation]    LRS(PG)에게 메시지 송신 (헤더 Byte0 = ${LRS_TX_BYTE0})
    [Arguments]    ${msg_type}    ${txn_id}    ${body_bytes}
    Tcp.Send Lrs Message    ${LRS_CONN}    ${msg_type}    ${txn_id}    ${body_bytes}    ${LRS_TX_BYTE0}
    Log    [TX→LRS] type=${msg_type} txn=${txn_id} byte0=${LRS_TX_BYTE0}


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

Handle LRS Hello
    [Documentation]
    ...    LRS-PCF 채널 Hello 핸드셰이크 (NAG Suite Setup 등에서 사용)
    ...    Hello-Request(0x01) 수신·검증 → 같은 TXN ID 로 Hello-Response(0x02) 송신.
    ...    반환: (header_dict, request_dict[SYS_ID/BRANCH_NAME])
    ${hdr}    ${req}=    Receive And Validate LRS Hello
    Send LRS Hello Response    ${hdr}[txn_id]
    Log    [Suite] LRS Hello 처리 완료: SYS_ID=${req}[SYS_ID] BRANCH=${req}[BRANCH_NAME] txn=${hdr}[txn_id]    console=True
    RETURN    ${hdr}    ${req}


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
    [Documentation]
    ...    LRS(PG)로부터 Location-Info-Request(0x05) 수신 및 msg_type 검증
    ...    중간에 Ping-Request(0x03)가 오면 Ping-Response(0x04)로 응답하고 계속 대기
    WHILE    True    limit=10
        ${hdr}    ${raw}=    Receive From LRS PG
        IF    ${hdr}[msg_type] == ${5}
            BREAK
        END
        IF    ${hdr}[msg_type] == ${3}
            Send LRS Ping Response    ${hdr}[txn_id]
            CONTINUE
        END
        Fail    Location-Info-Request(0x05) 기대, 실제 msg_type=${hdr}[msg_type]
    END
    ${total}=    Get Length    ${raw}
    ${fs}=    Run Keyword If    ${total} == 175
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

Handle LRS Location Info
    [Documentation]
    ...    LRS-PCF 채널 Location-Info 처리 (NAG Subs-Cellid 흐름 중 사용)
    ...    Location-Info-Request(0x05) 수신 → 같은 TXN ID 로 Location-Info-Response(0x06) 송신.
    ...    cell/ta_code/net_tp 미지정 시 LTE 목값 사용. 반환: (header_dict, request_dict)
    [Arguments]    ${cell_info}=${LRS_MOCK_CELL_INFO_LTE}    ${ta_code}=${LRS_MOCK_TA_CODE_LTE}
    ...            ${net_tp}=${LRS_MOCK_NET_TP_LTE}          ${result_code}=0
    ${hdr}    ${req}=    Receive And Validate LRS Location Info
    Send LRS Location Info Response    ${hdr}[txn_id]    ${req}
    ...    ${cell_info}    ${ta_code}    ${net_tp}    ${result_code}
    Log    [LRS-PCF] Location-Info 응답 완료: MDN=${req}[MDN] CELL=${cell_info} NET=${net_tp}    console=True
    RETURN    ${hdr}    ${req}


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
