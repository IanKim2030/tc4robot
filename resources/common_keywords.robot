*** Settings ***
Documentation
...    PG 연동 통합 공통 키워드 (NAG / PCF / LRS / UPM / NWDAF 가 모두 공유)
...
...    인터페이스별 키워드는 각각의 *_keywords.robot 으로 분리되어 있음:
...      resources/nag_keywords.robot    ← NAG (LRS-PCF dual-socket 포함)
...      resources/pcf_keywords.robot    ← PCF (NAG 세션 선등록 포함)
...      resources/lrs_keywords.robot    ← LRS (서버 모드, Hello/Ping/Location-Info)
...      resources/upm_keywords.robot    ← UPM (Hello/Ping/CellInfo-Noti/Subs-Sync 등)
...      resources/nwdaf_keywords.robot  ← NWDAF (TLV Notification)
...
...    여기에는 다음 두 종류만 둔다:
...      1) 모든 인터페이스가 공유하는 유틸 (Next TXN ID / KST timestamp / 17자리 timestamp)
...      2) JSON 응답에 대한 generic 검증 (NAG/PCF/UPM 공통)

Library    Collections
Library    String
Library    DateTime
Library    BuiltIn
Library    ${CURDIR}/TcpHelper.py    WITH NAME    Tcp


*** Keywords ***

# ══════════════════════════════════════════════════════════════════
# 공통 유틸 — 시간 / TXN ID
# ══════════════════════════════════════════════════════════════════

Get KST Timestamp
    [Documentation]    ISO 8601 + KST 오프셋 (NAG/PCF event-timestamp 용)
    ${ts}=    Get Current Date    result_format=%Y-%m-%dT%H:%M:%S+09:00
    RETURN    ${ts}

Get Timestamp17
    [Documentation]    yyyyMMddHHmmssSSS 17자리 (LRS EVENT_TIMESTAMP, UPM event-timestamp 등)
    ${ts}=    Get Current Date    result_format=%Y%m%d%H%M%S%f
    ${ts17}=    Get Substring    ${ts}    0    17
    RETURN    ${ts17}

Next TXN ID
    [Documentation]    트랜잭션 ID 생성 (0 금지 — 규격 명시)
    ${ts}=    Get Current Date    result_format=%f
    ${txn}=    Evaluate    max(1, int('${ts}') % 2147483647)
    RETURN    ${txn}


# ══════════════════════════════════════════════════════════════════
# Hello / Ping 응답 공통 (NAG/PCF/UPM JSON 응답)
# ══════════════════════════════════════════════════════════════════

Hello Should Succeed
    [Arguments]    ${resp_body}
    ${code}=    Get From Dictionary    ${resp_body}    code
    Should Be Equal As Numbers    ${code}    200    msg=Hello 실패: code=${code}

Get Ping Interval
    [Documentation]    Hello-Response 의 ping-interval 추출. 없으면 기본 30.
    [Arguments]    ${resp_body}
    ${ok}=    Run Keyword And Return Status
    ...    Dictionary Should Contain Key    ${resp_body}    ping-interval
    ${interval}=    Run Keyword If    ${ok}
    ...    Get From Dictionary    ${resp_body}    ping-interval
    ...    ELSE    Set Variable    ${30}
    RETURN    ${interval}

Ping Should Succeed
    [Arguments]    ${resp_body}
    ${code}=    Get From Dictionary    ${resp_body}    code
    Should Be Equal As Numbers    ${code}    200    msg=Ping 실패: code=${code}


# ══════════════════════════════════════════════════════════════════
# 공통 검증 (NAG/PCF/UPM JSON 응답)
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


# ══════════════════════════════════════════════════════════════════
# 공통 포맷 검증 (NAG/PCF/UPM cell-info, ta-code 등)
# ══════════════════════════════════════════════════════════════════

Cell Info Should Be Valid
    [Documentation]    cell-info: NodeB:Cell 또는 plmn-NodeB:Cell
    [Arguments]    ${cell_info}
    Should Match Regexp    ${cell_info}    ^(\\d+-)?\\d+:\\d+$

TA Code Should Be Valid
    [Documentation]    ta-code: Hexa 4/6자리 또는 0
    [Arguments]    ${ta_code}
    Should Match Regexp    ${ta_code}    ^([0-9a-fA-F]{4}|[0-9a-fA-F]{6}|0)$
