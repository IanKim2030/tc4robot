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
...    Suite Teardown : RTS 연결 종료 (Release 송신)
...    각 TC          : ${RTS_SOCK} 공유 사용 (TC별 연결/해제 없음)
...
...    [TC 번호 체계]
...    001      Order(11/12) L1 — SVC_ID=W_DATA_ROAMING_BLOCK
...    002      Order(11/12) L2 — SVC_ID=L_DATA_ROAMING_BLOCK
...
...    이번 범위는 SVC_CODE=L1/L2 뿐이다. L1/L2 를 단순 ON/OFF 토글 쌍으로 단정하지
...    않는다 — 반영 SVC_ID 가 서로 다른 걸 보면 코드마다 별개 차단 유형일 수 있다
...    (정확한 의미는 확인 필요, rts_variables.robot 참조). L3/L4(mVoIP 차단)·
...    L5~LE(QoS Param)는 PG 소스(RTS/CDownMessage.cpp)에 처리 분기가 살아있으나
...    실제 운영에서 미사용 확인됨 — 이 슈트에서 TC 로 다루지 않는다.
...
...    [PDB 조회]
...    `db` 태그 TC 는 두 계층을 확인한다.
...      프로토콜 계층 — T_RTS_ORDER_HIST.ORDER_DATA (TC-RTS-001 만, 와이어 왕복 확인용)
...      업무 계층    — T_5G_SUBS_SERVICE.SVC_ID (TC-RTS-001/002 공통, 사용자 확인, 비동기라 재시도)
...    PDB 접속은 CDS 와 DSN 이 동일함(사용자 확인) — ${RTS_DB_CONNSTR} 기본값이 이미
...    ${CDS_DB_CONNSTR} 과 같은 문자열로 채워져 있다. 그래도 환경 오버라이드로
...    접속 문자열이 비게 되는 경우를 대비해, 없으면 실패 대신 Skip 한다 — CDS 처럼
...    Suite 전체를 막지 않는다.
...
...    [PCF SBI Noti]
...    `noti` 태그 TC 는 L1/L2 전문이 PCF SBI Noti 도 유발하는지 확인한다(사용자 확인 —
...    RTS 소스만으로는 notify 호출이 안 보여 미확인이었던 부분). CDS 와 같은 메커니즘
...    (HttpNotiServer, 도구가 PCF 역할로 Listen)을 그대로 쓴다. ${RTS_NOTI_VERIFY}=${FALSE}
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
# 11/12  Order — 로밍 데이터 차단 (SVC_CODE=L1/L2)
# ════════════════════════════════════════════════════════════════

TC-RTS-001 로밍 데이터 차단 L1 (SVC_ID=W_DATA_ROAMING_BLOCK) - PDB/Noti 반영 확인
    [Documentation]
    ...    SVC_CODE=L1, MDN 12B, 로밍 차단 플래그='Y'.
    ...    와이어 오프셋(수신 파싱) 14 / DB 저장 오프셋 85 — 서로 다르다
    ...    (RtsHelper.py 모듈 docstring 참조).
    ...    1) ACK(RESULT=SC) 확인
    ...    2) PCF SBI Noti 도착 확인(사용자 확인)
    ...    3) T_RTS_ORDER_HIST.ORDER_DATA[85] 로 프로토콜 계층 반영 확인
    ...    4) T_5G_SUBS_SERVICE(SVC_ID=W_DATA_ROAMING_BLOCK) 로 업무 계층 반영 확인(사용자 확인)
    ...    PDB/Noti 접속 정보가 없으면 해당 부분만 Skip — Noti 를 PDB 보다 먼저 확인해
    ...    PDB 접속 문제로 Skip 되더라도(Skip 은 TC 를 즉시 끝낸다) Noti 확인은 남게 한다.
    ...    Noti 확인은 실패하면 **한 번 더 재시도**한다(각 시도가 ${RTS_NOTI_WAIT} 만큼
    ...    이미 기다리므로, 지연 도착까지 감안해 최대 2회).
    [Tags]    rts    order    roaming    db    noti
    ${since}=    RTS Noti Timestamp
    ${tid_date}    ${tid_seq}=    Next RTS TID
    ${hdr}    ${ack}=    Send RTS Order
    ...    ${RTS_SVC_L1}    ${RTS_TEST_MDN}    ${RTS_ROAMING_BLOCK_ON}
    ...    ${tid_date}    ${tid_seq}
    RTS Order Should Succeed    ${ack}
    Wait Until Keyword Succeeds    2x    0s
    ...    Verify RTS SBI Noti Sent    ${RTS_SVC_L1}    since=${since}
    Verify RTS Order In PDB    ${tid_date}    ${tid_seq}    ${RTS_ROAMING_BLOCK_ON}
    Verify RTS Service Applied In PDB    ${RTS_TEST_MDN}    ${RTS_SVC_ID_W_DATA_ROAMING_BLOCK}

TC-RTS-002 로밍 데이터 차단 L2 (SVC_ID=L_DATA_ROAMING_BLOCK) - PDB/Noti 반영 확인
    [Documentation]
    ...    SVC_CODE=L2, 로밍 차단 플래그='N'.
    ...    1) ACK(RESULT=SC) 확인
    ...    2) PCF SBI Noti 도착 확인(사용자 확인)
    ...    3) T_5G_SUBS_SERVICE(SVC_ID=L_DATA_ROAMING_BLOCK) 로 업무 계층 반영 확인(사용자 확인)
    ...    PDB/Noti 접속 정보가 없으면 해당 부분만 Skip — Noti 를 PDB 보다 먼저 확인해
    ...    PDB 접속 문제로 Skip 되더라도(Skip 은 TC 를 즉시 끝낸다) Noti 확인은 남게 한다.
    [Tags]    rts    order    roaming    db    noti
    ${since}=    RTS Noti Timestamp
    ${hdr}    ${ack}=    Send RTS Order
    ...    ${RTS_SVC_L2}    ${RTS_TEST_MDN}    ${RTS_ROAMING_BLOCK_OFF}
    RTS Order Should Succeed    ${ack}
    Verify RTS SBI Noti Sent    ${RTS_SVC_L2}    since=${since}
    Verify RTS Service Applied In PDB    ${RTS_TEST_MDN}    ${RTS_SVC_ID_L_DATA_ROAMING_BLOCK}
