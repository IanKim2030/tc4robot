*** Settings ***
Documentation
...    RTS ↔ PG.RTS 로밍 데이터 차단 연동 기능 검증 (SVC_CODE=L1/L2)
...
...    [테스트 대상]
...    테스트 도구(RTS 역할 / Client) → PG (Server, Port ${RTS_PG_PORT})
...
...    RTS 는 PG 내부 공식 명칭이다(디렉토리 `RTS/`, 클래스 `CRts`) — CDS 문서의
...    "PG.RDS"(쿠폰 예약작업 폴러)와는 별개 인터페이스이므로 혼동하지 말 것.
...
...    [Suite 소켓 정책]
...    Suite Setup    : RTS → PG 연결 + Connect Req(1)/Ack(2) 처리
...                     → ${RTS_SOCK} 공유, PG 가 준 TID(date/seq) 로 채번 기준 저장
...    Test Setup     : Check RTS Socket (소켓 닫히면 Suite 즉시 중단)
...    Suite Teardown : RTS 연결 종료 (Release 송신) + PDB 종료 시 정리 (아래 참조)
...    각 TC          : ${RTS_SOCK} 공유 사용 (TC별 연결/해제 없음)
...
...    [TC 번호 체계]
...    001      Order(11/12) WCDMA 차단 — L1 + 플래그 'Y' (SVC_ID=W_DATA_ROAMING_BLOCK)
...    002      Order(11/12) WCDMA 해제 — L1 + 플래그 'N'
...    003      Order(11/12) LTE   차단 — L2 + 플래그 'Y' (SVC_ID=L_DATA_ROAMING_BLOCK)
...    004      Order(11/12) LTE   해제 — L2 + 플래그 'N'
...    005      Order(11/12) 패킷 크기 검증 negative — Data Size 과대 신고 시 E_WRONG_SIZE(12)
...
...    L1/L2 는 ON/OFF 쌍이 아니라 망 종류다(사용자 확인, 2026-10-27) — L1=WCDMA(W_),
...    L2=LTE(L_). 차단/해제는 코드가 아니라 로밍 플래그(Y/N)로 가른다.
...    **해제 TC(002/004)는 T_5G_SUBS_SERVICE 행의 존재/부재를 단정하지 않는다** — 해제
...    시 행이 지워지는지 남는지가 PG 동작으로 확인되지 않았다. 확인되면 TC 에
...    svc_id 를 넘기거나 부재 판정을 추가할 것. L3/L4(mVoIP 차단)·L5~LE(QoS Param)는
...    PG 소스(RTS/CDownMessage.cpp)에 처리 분기가 살아있으나 실제 운영에서 미사용
...    확인됨 — 이 슈트에서 TC 로 다루지 않는다.
...
...    [PDB 조회]
...    `db` 태그 TC 는 두 계층을 확인한다.
...      프로토콜 계층 — T_RTS_ORDER_HIST.ORDER_DATA (TC-RTS-001~004 공통, 와이어 왕복 확인용)
...      업무 계층    — T_5G_SUBS_SERVICE.SVC_ID (TC-RTS-001/003 차단만, 사용자 확인, 비동기라 재시도)
...    PDB 접속은 CDS 와 같은 DB 다(사용자 확인) — 접속 문자열은 공용
...    ${PDB_CONNSTR}(variables.robot) 하나뿐이다. 그래도 환경 오버라이드로
...    접속 문자열이 비게 되는 경우를 대비해, 없으면 실패 대신 Skip 한다 — CDS 처럼
...    Suite 전체를 막지 않는다.
...
...    [잔존 데이터 사전 확인 / 종료 시 정리] (2026-10-19 추가, PROFILE 포함으로 정정)
...    CDS 와 같은 목적 — RTS 도 PROFILE 을 건드린다는 게 실측으로 확인돼("가입자를
...    안 만든다"던 처음 추정은 틀렸다) T_5G_SUBS_SERVICE(W_DATA_ROAMING_BLOCK/
...    L_DATA_ROAMING_BLOCK) 와 T_5G_SUBS_PROFILE 을 ${RTS_TEST_MDN} 기준으로 둘 다
...    본다. Suite Setup 이 리포트만 하고(RTS Precheck Existing Subscriber Rows),
...    Suite Teardown 이 지운다(Cleanup RTS Subscriber Rows, SERVICE 먼저/PROFILE
...    나중, ${RTS_CLEANUP_ON_TEARDOWN}=${TRUE} 기본).
...    `run_tests.sh rts --no-cleanup`(CDS 와 공용 플래그)로 끌 수 있다.
...
...    [PCF SBI Noti]
...    `noti` 태그 TC 는 L1/L2 전문이 PCF SBI Noti 도 유발하는지 확인한다(사용자 확인 —
...    RTS 소스만으로는 notify 호출이 안 보여 미확인이었던 부분). CDS 와 같은 메커니즘
...    (HttpNotiServer, 도구가 PCF 역할로 Listen)을 그대로 쓴다. ${SNOTI_PCF_NOTI}=${FALSE}
...    (--no-sbi) 면 Listen 자체를 안 하고 통째로 건너뛴다.

Resource    ../../resources/variables.robot
Resource    ../../resources/rts_variables.robot
Resource    ../../resources/common_keywords.robot
Resource    ../../resources/rts_keywords.robot

Suite Setup      Suite RTS Connect
Suite Teardown   Suite RTS Disconnect
Test Setup       Check RTS Socket

*** Test Cases ***

# ════════════════════════════════════════════════════════════════
# 11/12  Order — 로밍 데이터 차단/해제 (L1=WCDMA, L2=LTE)
# ════════════════════════════════════════════════════════════════

TC-RTS-001 WCDMA 로밍 데이터 차단 (L1, 플래그 Y, SVC_ID=W_DATA_ROAMING_BLOCK) - PDB/Noti 반영 확인
    [Documentation]
    ...    SVC_CODE=L1(WCDMA), MDN 12B, 로밍 차단 플래그='Y'.
    ...    와이어 오프셋(수신 파싱) 14 / DB 저장 오프셋 85 — 서로 다르다
    ...    (RtsHelper.py 모듈 docstring 참조).
    ...    1) ACK(RESULT=SC) 확인
    ...    2) PCF SBI Noti 도착 확인(사용자 확인)
    ...    3) T_RTS_ORDER_HIST.ORDER_DATA[85]='Y' 로 프로토콜 계층 반영 확인
    ...    4) T_5G_SUBS_SERVICE(SVC_ID=W_DATA_ROAMING_BLOCK) 로 업무 계층 반영 확인(사용자 확인)
    ...    PDB/Noti 접속 정보가 없으면 해당 부분만 Skip — Noti 를 PDB 보다 먼저 확인해
    ...    PDB 접속 문제로 Skip 되더라도(Skip 은 TC 를 즉시 끝낸다) Noti 확인은 남게 한다.
    ...
    ...    ★ 비동기 반영(Noti/PDB) 타이밍이 빠듯해 실패하면 **한 번 더 전체를 재시도**한다
    ...      (최대 ${RTS_TC001_RETRY_COUNT}, 2026-10-01). 소켓은 재사용하고 TID만 새로
    ...      받으므로 "소켓은 슈트당 1회" 규칙과는 무관하다 — rts_keywords.robot 의
    ...      `Send RTS Order And Verify Reflection` 참조.
    [Tags]    rts    order    roaming    wcdma    block    db    noti
    Wait Until Keyword Succeeds    ${RTS_TC001_RETRY_COUNT}    ${RTS_TC001_RETRY_INTERVAL}
    ...    Send RTS Order And Verify Reflection
    ...    ${RTS_SVC_L1}    ${RTS_ROAMING_BLOCK_ON}    ${RTS_SVC_ID_W_DATA_ROAMING_BLOCK}

TC-RTS-002 WCDMA 로밍 데이터 차단 해제 (L1, 플래그 N) - PDB/Noti 반영 확인
    [Documentation]
    ...    SVC_CODE=L1(WCDMA), 로밍 차단 플래그='N'(해제).
    ...    1) ACK(RESULT=SC) 확인
    ...    2) PCF SBI Noti 도착 확인
    ...    3) T_RTS_ORDER_HIST.ORDER_DATA[85]='N' 로 프로토콜 계층 반영 확인
    ...    T_5G_SUBS_SERVICE 는 확인하지 않는다 — 해제 시 W_DATA_ROAMING_BLOCK 행이
    ...    지워지는지/남는지가 확인되지 않았다(슈트 상단 참조).
    ...    재시도 정책은 TC-RTS-001 과 같다.
    [Tags]    rts    order    roaming    wcdma    release    db    noti
    Wait Until Keyword Succeeds    ${RTS_TC001_RETRY_COUNT}    ${RTS_TC001_RETRY_INTERVAL}
    ...    Send RTS Order And Verify Reflection
    ...    ${RTS_SVC_L1}    ${RTS_ROAMING_BLOCK_OFF}

TC-RTS-003 LTE 로밍 데이터 차단 (L2, 플래그 Y, SVC_ID=L_DATA_ROAMING_BLOCK) - PDB/Noti 반영 확인
    [Documentation]
    ...    SVC_CODE=L2(LTE), 로밍 차단 플래그='Y'.
    ...    1) ACK(RESULT=SC) 확인
    ...    2) PCF SBI Noti 도착 확인
    ...    3) T_RTS_ORDER_HIST.ORDER_DATA[85]='Y' 로 프로토콜 계층 반영 확인
    ...    4) T_5G_SUBS_SERVICE(SVC_ID=L_DATA_ROAMING_BLOCK) 로 업무 계층 반영 확인
    ...    재시도 정책은 TC-RTS-001 과 같다.
    [Tags]    rts    order    roaming    lte    block    db    noti
    Wait Until Keyword Succeeds    ${RTS_TC001_RETRY_COUNT}    ${RTS_TC001_RETRY_INTERVAL}
    ...    Send RTS Order And Verify Reflection
    ...    ${RTS_SVC_L2}    ${RTS_ROAMING_BLOCK_ON}    ${RTS_SVC_ID_L_DATA_ROAMING_BLOCK}

TC-RTS-004 LTE 로밍 데이터 차단 해제 (L2, 플래그 N) - PDB/Noti 반영 확인
    [Documentation]
    ...    SVC_CODE=L2(LTE), 로밍 차단 플래그='N'(해제).
    ...    1) ACK(RESULT=SC) 확인
    ...    2) PCF SBI Noti 도착 확인
    ...    3) T_RTS_ORDER_HIST.ORDER_DATA[85]='N' 로 프로토콜 계층 반영 확인
    ...    T_5G_SUBS_SERVICE 는 확인하지 않는다 — 해제 시 L_DATA_ROAMING_BLOCK 행이
    ...    지워지는지/남는지가 확인되지 않았다(슈트 상단 참조).
    ...    재시도 정책은 TC-RTS-001 과 같다.
    [Tags]    rts    order    roaming    lte    release    db    noti
    Wait Until Keyword Succeeds    ${RTS_TC001_RETRY_COUNT}    ${RTS_TC001_RETRY_INTERVAL}
    ...    Send RTS Order And Verify Reflection
    ...    ${RTS_SVC_L2}    ${RTS_ROAMING_BLOCK_OFF}


# ════════════════════════════════════════════════════════════════
# 11/12  Order — negative (패킷 크기 검증)
# ════════════════════════════════════════════════════════════════

TC-RTS-005 Order - Data Size 필드 과대 신고 시 패킷 크기 검증 (E_WRONG_SIZE)
    [Documentation]
    ...    Data Size 헤더 필드를 실제 Body(17B, RTS_WIRE_BODY_SIZE)보다 훨씬 큰
    ...    ${RTS_DATA_SIZE_OVERSIZED}B 로 거짓 신고하고, 실제로는 정상 17B Body 만
    ...    보낸다. PG 가 선언된 크기 불일치를 감지해 Order Ack 에 RESULT=FA,
    ...    REASON=${RTS_REASON_WRONG_SIZE}(E_WRONG_SIZE)를 돌려주는지 검증한다.
    ...    (이 REASON 코드는 rts_variables.robot 에 이미 정의는 돼 있었으나 실제로
    ...    유발하는 TC 는 이번이 처음 — 기대와 다르면 이 TC 를 근거로 재조정한다.)
    [Tags]    rts    order    negative
    ${hdr}    ${ack}=    Send RTS Order With Wrong Data Size
    ...    ${RTS_SVC_L1}    ${RTS_TEST_MDN}    ${RTS_ROAMING_BLOCK_ON}
    ...    ${RTS_DATA_SIZE_OVERSIZED}
    RTS Order Should Fail    ${ack}    ${RTS_REASON_WRONG_SIZE}
