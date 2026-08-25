*** Settings ***
Documentation
...    RTS ↔ PG.RTS 연동 키워드 (로밍 데이터 차단 L1/L2, 32B 고정헤더 + 고정폭 Body)
...
...    [인터페이스]
...      방향   : RTS(테스트 도구 / Client) → PG (Server, Port ${RTS_PG_PORT})
...      Body   : 고정폭 (와이어 오프셋은 RtsHelper.py 모듈 docstring 참조)
...
...    [Suite 정책 — Single Socket]
...      Suite Setup    : Suite RTS Connect → ${RTS_SOCK}
...                       Connect Req(1)/Ack(2) 핸드셰이크, PG 가 준 최대 TID 를
...                       ${RTS_TID_DATE}/${RTS_TID_SEQ} 에 저장(TID 역전 방지).
...      Test Setup     : Check RTS Socket (닫히면 Fatal Error)
...      Suite Teardown : Suite RTS Disconnect (Release 송신 후 소켓 종료)
...
...    [범위]
...      SVC_CODE=L1(로밍 데이터 차단 ON)/L2(차단 해제)만 다룬다.
...      L3~LE 는 PG 소스에 분기가 있으나 미사용 확인됨 — 이 슈트에서 다루지 않는다.

Library    Collections
Library    String
Library    DateTime
Library    BuiltIn
Library    ${CURDIR}/RtsHelper.py     WITH NAME    Rts
Library    ${CURDIR}/CdsDbHelper.py   WITH NAME    RtsDb
Resource   ${CURDIR}/common_keywords.robot

*** Variables ***
${RTS_SOCK}       ${NONE}
${RTS_TID_DATE}    ${EMPTY}
${RTS_TID_SEQ}     ${0}


*** Keywords ***

# ══════════════════════════════════════════════════════════════════
# RTS Suite 연결 관리 (Client 모드, PG=Server)
# ══════════════════════════════════════════════════════════════════

Suite RTS Connect
    [Documentation]
    ...    RTS Suite Setup 전용
    ...    1) RTS → PG(${RTS_PG_PORT}) 소켓 연결
    ...    2) Connect Req(1) 송신 → Connect Ack(2) 검증(RESULT=SC)
    ...       Ack 에 담긴 tid_date/tid_seq(PG 의 SelectMaxTid 결과)를 그대로
    ...       Suite Variable 로 저장해 이후 Order 의 TID 채번 기준으로 쓴다 —
    ...       PG 가 준 값보다 낮은 TID 를 보내면 E_REVERSE_TID_ERROR(3) 다.
    [Arguments]    ${host}=${RTS_PG_HOST}    ${port}=${RTS_PG_PORT}    ${timeout}=${RTS_TIMEOUT}
    Log    [Suite] RTS 연결 시작 → ${host}:${port}    console=True
    ${sock}=    Rts.Tcp Connect    ${host}    ${port}    ${timeout}
    Set Suite Variable    ${RTS_SOCK}    ${sock}
    ${today}=    Get Current Date    result_format=%Y%m%d
    Rts.Send Rts    ${sock}    ${MSG_RTS_CONNECT_REQ}    ${today}    ${0}
    ...    ${RTS_SRC_SYS_ID}    ${RTS_DST_SYS_ID}
    ${hdr}    ${data}=    Rts.Receive Rts    ${sock}
    Should Be Equal As Numbers    ${hdr}[msg_id]    ${MSG_RTS_CONNECT_ACK}
    ...    msg=Connect Ack(2) 기대, 실제=${hdr}[msg_id]
    ${ack}=    Rts.Unpack Connect Ack    ${data}
    Should Be Equal As Strings    ${ack}[result]    ${RTS_RESULT_SUCCESS}
    ...    msg=RTS Connect 실패 (result=${ack}[result] reason=${ack}[reason]). RTS 테스트 시작 불가.
    Set Suite Variable    ${RTS_TID_DATE}    ${ack}[tid_date]
    Set Suite Variable    ${RTS_TID_SEQ}     ${ack}[tid_seq]
    Log    [Suite] RTS Connect 성공 tid=${RTS_TID_DATE}/${RTS_TID_SEQ}    console=True

Suite RTS Disconnect
    [Documentation]
    ...    RTS Suite Teardown 전용. Release(9) 송신 후 소켓 종료.
    ...    RTS/CDownMessage.cpp 의 RecvReleaseRequest 는 응답을 주지 않고 연결
    ...    종료를 유도할 뿐이므로, ACK 를 기다리지 않고 바로 소켓을 닫는다.
    IF    $RTS_SOCK is not None
        Run Keyword And Ignore Error
        ...    Rts.Send Rts    ${RTS_SOCK}    ${MSG_RTS_RELEASE_REQ}
        ...    ${RTS_TID_DATE}    ${RTS_TID_SEQ}    ${RTS_SRC_SYS_ID}    ${RTS_DST_SYS_ID}
        Rts.Tcp Close    ${RTS_SOCK}
    END
    Log    [Suite] RTS 연결 종료    console=True

Check RTS Socket
    [Documentation]    RTS Test Setup 전용. 소켓이 닫히면 Fatal Error.
    ${ok}=    Rts.Is Connected    ${RTS_SOCK}
    Run Keyword If    not ${ok}
    ...    Fatal Error    RTS 소켓이 닫혀 있습니다. 이후 TC를 실행할 수 없습니다.


# ══════════════════════════════════════════════════════════════════
# RTS 공통 헬퍼: TID(date+seq) 채번
# ══════════════════════════════════════════════════════════════════

Next RTS TID
    [Documentation]
    ...    Transaction ID 생성 → (tid_date, tid_seq).
    ...    Suite RTS Connect 가 저장한 값에서 seq 를 1씩 증가시킨다 — 절대
    ...    역전시키지 말 것(E_REVERSE_TID_ERROR).  date 는 오늘 날짜로 갱신한다.
    ${date}=    Get Current Date    result_format=%Y%m%d
    ${seq}=    Evaluate    ${RTS_TID_SEQ} + 1
    Set Suite Variable    ${RTS_TID_SEQ}     ${seq}
    Set Suite Variable    ${RTS_TID_DATE}    ${date}
    RETURN    ${date}    ${seq}


# ══════════════════════════════════════════════════════════════════
# RTS Order (11/12) — 로밍 데이터 차단 L1/L2
# ══════════════════════════════════════════════════════════════════

Send RTS Order
    [Documentation]
    ...    Order(11) 송신 + Ack(12) 수신. TID 미지정 시 Next RTS TID 로 자동 채번.
    ...    반환: (header_dict, ack_dict) — ack_dict 는 Rts.Unpack Order Ack 결과.
    [Arguments]    ${svc_code}    ${mdn}    ${roaming_block}
    ...            ${tid_date}=${NONE}    ${tid_seq}=${NONE}
    IF    $tid_date is None or $tid_seq is None
        ${tid_date}    ${tid_seq}=    Next RTS TID
    END
    ${body}=    Rts.Pack Rts Order Body    ${svc_code}    ${mdn}    ${roaming_block}
    Log    [TX-RTS] Order svc=${svc_code} mdn=${mdn} roaming=${roaming_block} tid=${tid_date}/${tid_seq}
    Rts.Send Rts    ${RTS_SOCK}    ${MSG_RTS_ORDER_REQ}    ${tid_date}    ${tid_seq}
    ...    ${RTS_SRC_SYS_ID}    ${RTS_DST_SYS_ID}    ${body}
    ${hdr}    ${data}=    Rts.Receive Rts    ${RTS_SOCK}
    Should Be Equal As Numbers    ${hdr}[msg_id]    ${MSG_RTS_ORDER_ACK}
    ...    msg=Order Ack(12) 기대, 실제=${hdr}[msg_id]
    ${ack}=    Rts.Unpack Order Ack    ${data}
    Log    [RX-RTS] Order Ack result=${ack}[result] reason=${ack}[reason]
    RETURN    ${hdr}    ${ack}

RTS Order Should Succeed
    [Documentation]    result=SC, reason=0 확인.
    [Arguments]    ${ack}
    Should Be Equal As Strings    ${ack}[result]    ${RTS_RESULT_SUCCESS}
    ...    msg=RTS Order 실패 (reason=${ack}[reason])
    Should Be Equal As Numbers    ${ack}[reason]    ${RTS_REASON_NO_ERROR}
    ...    msg=RTS Order reason 이 0 이 아님: ${ack}[reason]

RTS Order Should Fail
    [Documentation]    result=FA + 기대 reason 확인.
    [Arguments]    ${ack}    ${expected_reason}
    Should Be Equal As Strings    ${ack}[result]    ${RTS_RESULT_FAIL}
    ...    msg=RTS Order 성공했음(FA 기대): ${ack}
    Should Be Equal As Numbers    ${ack}[reason]    ${expected_reason}
    ...    msg=reason 불일치: expected=${expected_reason}, actual=${ack}[reason]


# ══════════════════════════════════════════════════════════════════
# PDB 검증 — CDS 와 DSN 동일함(사용자 확인, rts_variables.robot 참조)
# ══════════════════════════════════════════════════════════════════

Resolve RTS DB Connstr
    [Documentation]
    ...    ${RTS_DB_CONNSTR} → (비었으면) ${CDS_DB_CONNSTR} 순으로 접속 문자열을 찾는다.
    ...    둘 다 없으면 빈 문자열을 반환한다(호출부가 Skip 여부를 결정).
    ${conn_str}=    Set Variable    ${RTS_DB_CONNSTR}
    IF    not $conn_str
        ${conn_str}=    Get Variable Value    \${CDS_DB_CONNSTR}    ${EMPTY}
    END
    RETURN    ${conn_str}

Verify RTS Order In PDB
    [Documentation]
    ...    T_RTS_ORDER_HIST 에서 방금 보낸 Order 의 ORDER_DATA 를 조회해
    ...    로밍 차단 플래그가 실제로 반영됐는지 확인한다(프로토콜 계층 확인).
    ...    ORDER_DATA 는 265B 고정폭이며, 로밍 플래그는 **DB 저장 오프셋(85)**에
    ...    있다 — 와이어 오프셋(14)과 다르다(RtsHelper.py 모듈 docstring 참조).
    ...
    ...    ${RTS_DB_CONNSTR} 기본값이 CDS 와 동일하게 채워져 있지만, 환경 오버라이드로
    ...    비어 있는 경우까지 대비해 접속 문자열이 없으면 실패 대신 Skip 한다 —
    ...    CDS 처럼 Suite 전체를 막지 않는다.
    [Arguments]    ${tid_date}    ${tid_seq}    ${expected_roaming_block}
    ${conn_str}=    Resolve RTS DB Connstr
    IF    not $conn_str
        Skip    RTS PDB 접속 문자열이 없습니다. rts_variables.robot 의 RTS_DB_CONNSTR(기본값은 CDS 와 동일 DSN) 이 환경 오버라이드로 비워진 것으로 보입니다 — 채우면 이 TC 가 동작합니다.
    END
    ${transaction_id}=    Evaluate    "%8.8s%08d" % ("${tid_date}", ${tid_seq})
    ${status}    ${conn}=    Run Keyword And Ignore Error
    ...    RtsDb.Db Connect    ${conn_str}
    IF    '${status}' != 'PASS'
        Skip    RTS PDB 접속 실패 — ${conn}
    END
    # ORDER_DATA(265B) 는 문자열 컬럼이라 db_count 로 통째로 못 꺼낸다(COUNT 전용).
    # 대신 SUBSTR 로 DB 저장 오프셋(85, 0-index → SQL 1-index=86)의 1바이트를 걸어
    # COUNT 로 판정한다 — db_count 의 기존 계약(SELECT COUNT(*) 1행1열)을 그대로 쓴다.
    TRY
        ${count}=    RtsDb.Db Count    ${conn}
        ...    SELECT COUNT(*) FROM T_RTS_ORDER_HIST WHERE TRANSACTION_ID = ? AND SUBSTR(ORDER_DATA, 86, 1) = ?
        ...    ${transaction_id}    ${expected_roaming_block}
    EXCEPT    AS    ${err}
        RtsDb.Db Close    ${conn}
        Skip    RTS PDB 조회 실패 — ${err}
    END
    RtsDb.Db Close    ${conn}
    Should Be Equal As Numbers    ${count}    ${1}
    ...    msg=T_RTS_ORDER_HIST 에 반영된 로밍 차단 값을 못 찾음 (tid=${transaction_id}, expected=${expected_roaming_block})

RTS Service Should Be Applied
    [Documentation]    T_5G_SUBS_SERVICE 단발 조회(재시도는 호출부가 한다).
    [Arguments]    ${conn}    ${mdn}    ${svc_id}
    ${count}=    RtsDb.Db Count    ${conn}
    ...    SELECT COUNT(*) FROM T_5G_SUBS_SERVICE WHERE MDN = ? AND SVC_ID = ?
    ...    ${mdn}    ${svc_id}
    Should Be True    ${count} >= 1
    ...    msg=T_5G_SUBS_SERVICE 에 SVC_ID=${svc_id} 반영이 없습니다 (mdn=${mdn})

Verify RTS Service Applied In PDB
    [Documentation]
    ...    L1/L2 Order 가 가입자 서비스 테이블(T_5G_SUBS_SERVICE)까지 실제로
    ...    반영됐는지 확인한다(업무 계층 확인 — CDS 의 CommandResult 함정과 같은
    ...    이유로 ACK 만으로는 부족하다).
    ...      L1 → SVC_ID=${RTS_SVC_ID_W_DATA_ROAMING_BLOCK} INSERT
    ...      L2 → SVC_ID=${RTS_SVC_ID_L_DATA_ROAMING_BLOCK} INSERT
    ...    (사용자 확인 — 정확한 W_/L_ 의미는 별도 확인 필요, rts_variables.robot 참조)
    ...    비동기 반영으로 추정되어 ${RTS_DB_WAIT}/${RTS_DB_WAIT_INTERVAL} 로 재시도한다.
    ...    접속 문자열이 없으면 Skip.
    [Arguments]    ${mdn}    ${svc_id}    ${wait}=${RTS_DB_WAIT}    ${interval}=${RTS_DB_WAIT_INTERVAL}
    ${conn_str}=    Resolve RTS DB Connstr
    IF    not $conn_str
        Skip    RTS PDB 접속 문자열이 없습니다. rts_variables.robot 의 RTS_DB_CONNSTR(기본값은 CDS 와 동일 DSN) 이 환경 오버라이드로 비워진 것으로 보입니다 — 채우면 이 TC 가 동작합니다.
    END
    ${status}    ${conn}=    Run Keyword And Ignore Error
    ...    RtsDb.Db Connect    ${conn_str}
    IF    '${status}' != 'PASS'
        Skip    RTS PDB 접속 실패 — ${conn}
    END
    TRY
        Wait Until Keyword Succeeds    ${wait}    ${interval}
        ...    RTS Service Should Be Applied    ${conn}    ${mdn}    ${svc_id}
    FINALLY
        RtsDb.Db Close    ${conn}
    END
