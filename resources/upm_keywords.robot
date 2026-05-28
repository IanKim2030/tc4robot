*** Settings ***
Documentation
...    UPM ↔ PG 연동 키워드 (PG-SC Message Format / JSON Body)
...
...    [인터페이스]
...      방향   : UPM(테스트 도구 / Client) → PG (Server, Port ${UPM_PG_PORT})
...      Body   : JSON
...
...    [Suite 정책 — Single Socket]
...      Suite Setup    : Suite UPM Connect → ${UPM_SOCK}
...                       규격 3.1 의 "5초 이내 Hello-Request" 를 Suite Setup 에서 처리.
...                       ping-interval 을 ${UPM_PING_INTERVAL} 에 저장.
...      Test Setup     : Check UPM Socket (닫히면 Fatal Error)
...      Suite Teardown : Suite UPM Disconnect
...
...    [메시지 흐름]
...      능동 송신 (UPM → PG): 0x01 Hello / 0x03 Ping / 0x09 CellInfo-Noti / 0x0b Subs-Sync
...      수동 수신 (PG → UPM): 0x05 Subs-Change / 0x07 Subs-Info / 0x0d Info-Change
...
...    [TID]
...      24자리 = 장비No(5) + "-" + yyyyMMdd(8) + seq(10). Next UPM TID 키워드 사용.
...      Header 의 txn_id(4B 바이너리) 와는 별개.

Library    Collections
Library    String
Library    DateTime
Library    BuiltIn
Library    ${CURDIR}/TcpHelper.py    WITH NAME    Tcp
Resource   ${CURDIR}/common_keywords.robot

*** Variables ***
${UPM_SOCK}      ${NONE}
${UPM_TID_SEQ}   ${0}


*** Keywords ***

# ══════════════════════════════════════════════════════════════════
# UPM Suite 연결 관리 (Client 모드, PG=Server)
# ══════════════════════════════════════════════════════════════════

Suite UPM Connect
    [Documentation]
    ...    UPM Suite Setup 전용
    ...    1) UPM → PG(${UPM_PG_PORT}) 소켓 연결
    ...    2) 5초 이내 Hello-Request 전송 + Hello-Response 검증 → ping-interval 저장
    ...    Hello 미수신 시 PG가 연결 종료하므로 Suite Setup 에서 즉시 처리
    [Arguments]    ${host}=${UPM_PG_HOST}    ${port}=${UPM_PG_PORT}    ${timeout}=${UPM_TIMEOUT}
    Log    [Suite] UPM 연결 시작 → ${host}:${port}    console=True
    ${sock}=    Tcp.Tcp Connect    ${host}    ${port}    ${timeout}
    Set Suite Variable    ${UPM_SOCK}    ${sock}
    ${txn}=    Next TXN ID
    ${hdr}    ${body}=    Send UPM Hello    ${UPM_SYS_ID}    ${UPM_BRANCH_NAME}    ${txn}
    ${code}=    Get From Dictionary    ${body}    code
    Should Be Equal As Numbers    ${code}    200
    ...    msg=UPM Hello 실패 (code=${code}). UPM 테스트 시작 불가.
    ${pi}=    Get Ping Interval    ${body}
    Set Suite Variable    ${UPM_PING_INTERVAL}    ${pi}
    Log    [Suite] UPM Hello 성공 code=${code} ping-interval=${pi}    console=True

Suite UPM Disconnect
    [Documentation]    UPM Suite Teardown 전용. UPM 소켓 종료.
    Run Keyword If    $UPM_SOCK is not None    Tcp.Tcp Close    ${UPM_SOCK}
    Log    [Suite] UPM 연결 종료    console=True

Check UPM Socket
    [Documentation]    UPM Test Setup 전용. 소켓이 닫히면 Fatal Error.
    ${ok}=    Tcp.Is Connected    ${UPM_SOCK}
    Run Keyword If    not ${ok}
    ...    Fatal Error    UPM 소켓이 닫혀 있습니다. 이후 TC를 실행할 수 없습니다.


# ══════════════════════════════════════════════════════════════════
# UPM 메시지 송수신 (JSON, Client 모드)
# ══════════════════════════════════════════════════════════════════

Send UPM Message
    [Arguments]    ${msg_type}    ${txn_id}    ${payload}=${NONE}
    Tcp.Send Message    ${UPM_SOCK}    ${msg_type}    ${txn_id}    ${payload}

Receive UPM Message
    ${hdr}    ${body}=    Tcp.Receive Message    ${UPM_SOCK}
    Log    [RX-UPM] type=0x${hdr}[msg_type] txn=${hdr}[txn_id]
    RETURN    ${hdr}    ${body}

Send And Receive UPM
    [Arguments]    ${msg_type}    ${txn_id}    ${payload}=${NONE}
    Send UPM Message    ${msg_type}    ${txn_id}    ${payload}
    ${hdr}    ${body}=    Receive UPM Message
    RETURN    ${hdr}    ${body}


# ══════════════════════════════════════════════════════════════════
# UPM 공통 헬퍼: TID(24자리) / event-timestamp(17자리) 생성
# ══════════════════════════════════════════════════════════════════

Next UPM TID
    [Documentation]
    ...    UPM TID 24자리 생성: 장비No(5) + "-" + yyyyMMdd(8) + seq(10)
    ...    예: UPM01-2026043000000001
    [Arguments]    ${sys_id}=${UPM_SYS_ID}
    ${UPM_TID_SEQ}=    Evaluate    ${UPM_TID_SEQ} + 1
    Set Suite Variable    ${UPM_TID_SEQ}
    ${date}=    Get Current Date    result_format=%Y%m%d
    ${seq10}=    Evaluate    f"{${UPM_TID_SEQ}:010d}"
    ${prefix5}=    Evaluate    "${sys_id}"[:5].ljust(5, "0")
    ${tid}=    Set Variable    ${prefix5}-${date}${seq10}
    RETURN    ${tid}

Get Event Timestamp
    [Documentation]    yyyyMMddHHmmssSSS 17자리 (UPM event-timestamp)
    ${ts}=    Get Current Date    result_format=%Y%m%d%H%M%S%f
    ${ts17}=    Get Substring    ${ts}    0    17
    RETURN    ${ts17}


# ══════════════════════════════════════════════════════════════════
# UPM Hello (0x01/0x02)  UPM → PG
# ══════════════════════════════════════════════════════════════════

Send UPM Hello
    [Arguments]    ${sys_id}    ${branch_name}    ${txn_id}=${NONE}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${payload}=    Create Dictionary    sys-id=${sys_id}    branch-name=${branch_name}
    ${hdr}    ${body}=    Send And Receive UPM    ${1}    ${txn_id}    ${payload}
    RETURN    ${hdr}    ${body}


# ══════════════════════════════════════════════════════════════════
# UPM Ping (0x03/0x04)  UPM → PG, Body 없음
# ══════════════════════════════════════════════════════════════════

Send UPM Ping
    [Arguments]    ${txn_id}=${NONE}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${hdr}    ${body}=    Send And Receive UPM    ${3}    ${txn_id}    ${NONE}
    RETURN    ${hdr}    ${body}


# ══════════════════════════════════════════════════════════════════
# UPM Subs-Info (0x07/0x08)  PG → UPM 요청 → UPM → PG 응답
# ══════════════════════════════════════════════════════════════════

Receive Subs Info Request
    [Documentation]    PG → UPM Subs-Info-Request(0x07) 수신 (msg_type 검증)
    ${hdr}    ${body}=    Receive UPM Message
    Should Be Equal As Numbers    ${hdr}[msg_type]    ${7}
    ...    msg=Subs-Info-Request(0x07) 기대, 실제=${hdr}[msg_type]
    RETURN    ${hdr}    ${body}

Send Subs Info Response
    [Documentation]
    ...    UPM → PG Subs-Info-Response(0x08)
    ...    code-type=03(해지) 인 경우 subsList 미포함
    [Arguments]
    ...    ${txn_id}    ${req_body}
    ...    ${cell_list}=${NONE}
    ...    ${result_code}=${UPM_RC_SUCCESS}
    ...    ${sys_id}=${UPM_SYS_ID}
    ${msg_type_v}=    Get From Dictionary    ${req_body}    msg-type
    ${code_type}=     Get From Dictionary    ${req_body}    code-type
    ${branch}=        Get From Dictionary    ${req_body}    branch-name
    ${tid}=           Get From Dictionary    ${req_body}    tid
    ${mdn}=           Get From Dictionary    ${req_body}    mdn
    ${payload}=    Create Dictionary
    ...    msg-type=${msg_type_v}        code-type=${code_type}
    ...    sys-id=${sys_id}              branch-name=${branch}
    ...    tid=${tid}                    result-code=${result_code}
    IF    '${code_type}' != '03'
        ${cl}=    Run Keyword If    $cell_list is None    Create List
        ...       ELSE    Set Variable    ${cell_list}
        ${subs}=    Create Dictionary    mdn=${mdn}    cell-list=${cl}
        ${arr}=     Create List    ${subs}
        Set To Dictionary    ${payload}    subsList=${arr}
    END
    Send UPM Message    ${8}    ${txn_id}    ${payload}


# ══════════════════════════════════════════════════════════════════
# UPM CellInfo-Noti (0x09/0x0a)  UPM → PG NOTI → PG → UPM 응답
# ══════════════════════════════════════════════════════════════════

Send CellInfo Noti
    [Documentation]
    ...    UPM → PG CellInfo-Noti-Request(0x09) 송신 + 응답(0x0a) 수신
    ...    subs_list 예: [{mdn, cell-list:[{cell-info, ta-code}]}]
    ...    제약: subs_list 최대 100 개 (규격서 6.4.1)
    [Arguments]    ${subs_list}    ${txn_id}=${NONE}    ${sys_id}=${UPM_SYS_ID}    ${branch}=${UPM_BRANCH_NAME}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${tid}=    Next UPM TID    ${sys_id}
    ${ts17}=   Get Event Timestamp
    ${payload}=    Create Dictionary
    ...    msg-type=${UPM_MT_NOTI}
    ...    sys-id=${sys_id}                branch-name=${branch}
    ...    tid=${tid}                      event-timestamp=${ts17}
    ...    subsList=${subs_list}
    ${hdr}    ${body}=    Send And Receive UPM    ${9}    ${txn_id}    ${payload}
    RETURN    ${hdr}    ${body}

Build Cell Item
    [Documentation]    cell-list 항목 한 건 생성
    [Arguments]    ${cell_info}    ${ta_code}=${NONE}
    ${item}=    Create Dictionary    cell-info=${cell_info}
    IF    $ta_code is not None
        Set To Dictionary    ${item}    ta-code=${ta_code}
    END
    RETURN    ${item}

Build Subs Item
    [Documentation]    subsList 항목 한 건 생성
    [Arguments]    ${mdn}    @{cells}
    ${cell_list}=    Create List    @{cells}
    ${item}=    Create Dictionary    mdn=${mdn}    cell-list=${cell_list}
    RETURN    ${item}

CellInfo Noti Should Succeed
    [Arguments]    ${resp_body}
    ${rc}=    Get From Dictionary    ${resp_body}    result-code
    Should Be Equal As Strings    ${rc}    ${UPM_RC_SUCCESS}
    ...    msg=CellInfo-Noti 실패: result-code=${rc}


# ══════════════════════════════════════════════════════════════════
# UPM Subs-Change (0x05/0x06) PG→UPM 번호변경 NOTI / UPM→PG 응답
# ══════════════════════════════════════════════════════════════════

Receive Subs Change Request
    [Documentation]    PG → UPM Subs-Change-Request(0x05) 수신 (code-type=04)
    ${hdr}    ${body}=    Receive UPM Message
    Should Be Equal As Numbers    ${hdr}[msg_type]    ${5}
    ...    msg=Subs-Change-Request(0x05) 기대, 실제=${hdr}[msg_type]
    RETURN    ${hdr}    ${body}

Send Subs Change Response
    [Documentation]    UPM → PG Subs-Change-Response(0x06): mdn/new-mdn 에코
    [Arguments]    ${txn_id}    ${req_body}
    ...            ${result_code}=${UPM_RC_SUCCESS}    ${sys_id}=${UPM_SYS_ID}
    ${branch}=    Get From Dictionary    ${req_body}    branch-name
    ${tid}=       Get From Dictionary    ${req_body}    tid
    ${mdn}=       Get From Dictionary    ${req_body}    mdn
    ${new_mdn}=   Get From Dictionary    ${req_body}    new-mdn
    ${payload}=    Create Dictionary
    ...    code-type=${UPM_CT_MDN_CHANGE}
    ...    sys-id=${sys_id}        branch-name=${branch}
    ...    tid=${tid}              mdn=${mdn}
    ...    new-mdn=${new_mdn}      result-code=${result_code}
    Send UPM Message    ${6}    ${txn_id}    ${payload}


# ══════════════════════════════════════════════════════════════════
# UPM Subs-Sync (0x0b/0x0c)  UPM → PG 전체 동기화 요청
# ══════════════════════════════════════════════════════════════════

Send Subs Sync Request
    [Documentation]    UPM → PG Subs-Sync-Request(0x0b): code-type=05 (전체 요청)
    [Arguments]    ${txn_id}=${NONE}    ${sys_id}=${UPM_SYS_ID}    ${branch}=${UPM_BRANCH_NAME}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${tid}=    Next UPM TID    ${sys_id}
    ${ts17}=   Get Event Timestamp
    ${payload}=    Create Dictionary
    ...    code-type=${UPM_CT_SYNC_ALL}
    ...    sys-id=${sys_id}      branch-name=${branch}
    ...    tid=${tid}            event-timestamp=${ts17}
    ${hdr}    ${body}=    Send And Receive UPM    ${11}    ${txn_id}    ${payload}
    RETURN    ${hdr}    ${body}

Subs Sync Should Succeed
    [Arguments]    ${resp_body}
    ${rc}=    Get From Dictionary    ${resp_body}    result-code
    Should Be Equal As Strings    ${rc}    ${UPM_RC_SUCCESS}
    ...    msg=Subs-Sync 실패: result-code=${rc}


# ══════════════════════════════════════════════════════════════════
# UPM Info-Change (0x0d/0x0e) PG→UPM 상품/Device 변경 / UPM→PG 응답
# ══════════════════════════════════════════════════════════════════

Receive Info Change Request
    [Documentation]    PG → UPM Info-Change-Request(0x0d) 수신 (code-type=06)
    ${hdr}    ${body}=    Receive UPM Message
    Should Be Equal As Numbers    ${hdr}[msg_type]    ${13}
    ...    msg=Info-Change-Request(0x0d) 기대, 실제=${hdr}[msg_type]
    RETURN    ${hdr}    ${body}

Send Info Change Response
    [Documentation]    UPM → PG Info-Change-Response(0x0e): mdn 에코
    [Arguments]    ${txn_id}    ${req_body}
    ...            ${result_code}=${UPM_RC_SUCCESS}    ${sys_id}=${UPM_SYS_ID}
    ${branch}=    Get From Dictionary    ${req_body}    branch-name
    ${tid}=       Get From Dictionary    ${req_body}    tid
    ${mdn}=       Get From Dictionary    ${req_body}    mdn
    ${payload}=    Create Dictionary
    ...    code-type=${UPM_CT_INFO_CHANGE}
    ...    sys-id=${sys_id}        branch-name=${branch}
    ...    tid=${tid}              mdn=${mdn}
    ...    result-code=${result_code}
    Send UPM Message    ${14}    ${txn_id}    ${payload}


# ══════════════════════════════════════════════════════════════════
# UPM 공통 검증
# ══════════════════════════════════════════════════════════════════

UPM Result Code Should Be Success
    [Arguments]    ${resp_body}
    ${rc}=    Get From Dictionary    ${resp_body}    result-code
    Should Match Regexp    ${rc}    ^SC\\d{4}$
    ...    msg=result-code 성공 패턴 아님: ${rc}

UPM TID Should Match
    [Arguments]    ${req_body}    ${resp_body}
    ${req_tid}=    Get From Dictionary    ${req_body}    tid
    ${rsp_tid}=    Get From Dictionary    ${resp_body}    tid
    Should Be Equal As Strings    ${req_tid}    ${rsp_tid}
    ...    msg=TID 에코 불일치: req=${req_tid} resp=${rsp_tid}

UPM Code Type Should Be
    [Arguments]    ${req_body}    ${expected}
    ${actual}=    Get From Dictionary    ${req_body}    code-type
    Should Be Equal As Strings    ${actual}    ${expected}
    ...    msg=code-type: expected=${expected}, actual=${actual}

UPM Branch Name Should Be Valid
    [Arguments]    ${req_body}
    ${br}=    Get From Dictionary    ${req_body}    branch-name
    Should Be True    '${br}' in ['SS', 'DS', 'BR']
    ...    msg=branch-name 기대 SS/DS/BR, 실제=${br}

UPM MDN Should Be Valid
    [Arguments]    ${req_body}
    ${mdn}=    Get From Dictionary    ${req_body}    mdn
    Should Match Regexp    ${mdn}    ^\\d{10,11}$    msg=MDN 포맷 오류: ${mdn}

UPM Event Timestamp Should Be Valid
    [Arguments]    ${req_body}
    ${ts}=    Get From Dictionary    ${req_body}    event-timestamp
    Should Match Regexp    ${ts}    ^\\d{17}$    msg=event-timestamp 17자리 아님: ${ts}
