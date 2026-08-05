*** Settings ***
Documentation
...    CDS 인터페이스 기능 검증 (TCP 고정길이 48B, 클라이언트 듀얼 소켓)
...
...    [테스트 대상]
...    테스트 도구(CDS / 능동 Connector) → PG.CDS 접속
...    Schannel(${CDS_SCH_PORT}) / Rchannel(${CDS_RCH_PORT}) 2개 outbound 소켓
...
...    [Suite 소켓 정책]
...    Suite Setup    : Suite CDS Connect — 연결 → ConnectionRequest(0001/0003) + ACK 검증
...                     → 두 소켓 생존 확인까지 (접속은 TC 가 아니다)
...    Test Setup     : Check CDS Sockets (하나라도 닫히면 Suite 중단)
...    Suite Teardown : Suite CDS Disconnect — Release(0005/0007) + ACK(0006/0008) 검증 후 종료
...                     (해제도 TC 가 아니다. 슈트가 끝나면 반드시 수행돼야 한다)
...    각 TC          : ${CDS_SCH_SOCK}/${CDS_RCH_SOCK} 공유 사용 (TC별 연결/해제 없음)
...
...    포트/SYSTEM_ID 는 cds_variables.robot 기본값(9200/9201, PG01).
...    환경별로 다르면 config/env/<env>.py 에서 오버라이드한다.
...
...    [TC 번호 체계]
...      TC-CDS-001       : ProcessState 상태확인 (0013/0014)
...      TC-CDS-002 ~ 008 : Download Command (0015~0018) — 업무 코드별 (원래 번호)
...      TC-CDS-009 ~ 012 : Download Command — 번호변경(D3) 후 체인
...      TC-CDS-013       : SubsData (0029~0032) ※ 현재 주석 처리 (PG 조회 필요)
...      TC-CDS-014       : UpLoad (0025~0028) ※ 현재 주석 처리 (PG 가 먼저 송신)
...
...    [TC 간 의존성] TC-CDS-009 ~ 012 는 하나의 체인이다
...      009 D3 번호변경  : 성공하면 ${CDS_ACTIVE_MDN} 을 ${CDS_NEW_MDN} 으로 갱신
...      010 1X HFC가입   : 바뀐 번호로 가입
...      011 1Y HFC해제   : 010 이 가입한 번호를 해제
...      012 Z1 해지      : 가입자 자체를 해지 (체인의 끝)
...    D3 를 건너뛰거나 실패하면 ${CDS_ACTIVE_MDN} 이 기본값(${CDS_MDN})으로 남아
...    010~012 가 원래 번호를 대상으로 동작한다 — 단독 실행도 그대로 된다.
...    특정 번호를 지정하려면: --variable CDS_ACTIVE_MDN:01090010002

Resource    ../../resources/variables.robot
Resource    ../../resources/cds_variables.robot
Resource    ../../resources/common_keywords.robot
Resource    ../../resources/cds_keywords.robot


Suite Setup      Suite CDS Connect
Suite Teardown   Suite CDS Disconnect
Test Setup       Check CDS Sockets

*** Test Cases ***

# 접속(0001~0004)과 소켓 생존 확인은 Suite Setup(`Suite CDS Connect`)에서 수행한다.
# Setup 이 실패하면 슈트가 서지 않으므로 별도 TC 로 재확인할 필요가 없다.

# ════════════════════════════════════════════════════════════════
# 프로세스 상태 확인 (0013/0014)
# ════════════════════════════════════════════════════════════════

TC-CDS-001 상태확인 - ProcessStateReuqest(0013) S/R채널 각각 → ACK(0014)
    [Documentation]
    ...    요구/ACK 는 각 채널 내에서 완결 (규격 2.4)
    ...    Schannel: 요구(0013) → ACK(0014) / Rchannel: 요구(0013) → ACK(0014)
    ...    각 ACK 의 Process State=Normal(1) 확인
    [Tags]    cds    process-state    smoke
    # Schannel 내 요구 → ACK
    Send Process State Request    ${CDS_SCH_SOCK}
    ${state_s}=    Receive And Validate Process State Ack    ${CDS_SCH_SOCK}
    Process State Should Be Normal    ${state_s}
    # Rchannel 내 요구 → ACK
    Send Process State Request    ${CDS_RCH_SOCK}
    ${state_r}=    Receive And Validate Process State Ack    ${CDS_RCH_SOCK}
    Process State Should Be Normal    ${state_r}


# ════════════════════════════════════════════════════════════════
# DownLoad Command (0015~0018)
# ════════════════════════════════════════════════════════════════

TC-CDS-002 A1 (신규가입) 
    [Documentation]
    ...    0015(A1 신규) 송신 → 0016 ACK(SC) → 0017 Result 수신 → 0018 ResultACK 송신
    ...    규격 A1 이 요구하는 17개 필드는 cds_variables.robot 기본값으로 전달된다
    ...    (Body 는 코드와 무관하게 항상 327B).
    ...    ※ 단말·망 필드(${CDS_NETWORK} 등)가 비어 있으면 공백으로 나가고 PG 는 그래도
    ...       SC 를 준다. 실환경 값을 채워야 실제 검증이 된다.
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_A1}

TC-CDS-003 1X (HFC가입) 
    [Documentation]    0015(1X HFC 서비스 가입) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_1X}    addr=${CDS_ADDR}

TC-CDS-004 1Y (HFC해지) 
    [Documentation]    0015(1Y HFC 서비스 해지) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_1Y}

TC-CDS-005 I2 (부가서비스신청) 
    [Documentation]    0015(I2 부가서비스신청) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_I2}

TC-CDS-006 I3 (부가서비스해지) 
    [Documentation]    0015(I3 부가서비스해지) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_I3}

TC-CDS-007 C1 (기기변경) 
    [Documentation]
    ...    0015(C1 기기변경) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    C1 은 MDN 이 바뀌지 않고 단말(MIN)만 바뀌므로 new_min 만 넘긴다.
    ...    C1 분기는 min ← mdn 을 강제하고 new_mdn 을 선언하지 않는다(CdsHelper).
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_C1}    new_min=${CDS_NEW_MIN}

TC-CDS-008 G1 (정보변경) 
    [Documentation]    0015(G1 정보변경) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_G1}

TC-CDS-009 D3 (번호변경) 
    [Documentation]
    ...    0015(D3 번호변경) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    성공하면 가입자의 현재 번호가 new_mdn 으로 바뀌므로 ${CDS_ACTIVE_MDN} 을 갱신한다.
    ...    이후 TC-CDS-010 ~ 012 가 전부 이 값을 대상으로 동작한다.
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_D3}    new_mdn=${CDS_NEW_MDN}    new_min=${CDS_NEW_MIN}
    Set Suite Variable    ${CDS_ACTIVE_MDN}    ${CDS_NEW_MDN}

TC-CDS-010 1X (HFC가입 - 번호변경 후)
    [Documentation]
    ...    0015(1X HFC 서비스 가입) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    TC-CDS-009(D3)이 바꾼 번호(${CDS_ACTIVE_MDN})로 HFC 가입한다.
    ...    번호가 바뀐 가입자에게 HFC 를 붙이는 경로를 검증한다 — TC-CDS-003 는 원래 번호다.
    ...    D3 를 건너뛰었거나 실패하면 ${CDS_MDN} 이 되어 TC-CDS-003 와 같은 전문이 된다.
    ...    1X 는 addr 를 쓰는 유일한 코드다(170B, cp949).
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_1X}    mdn=${CDS_ACTIVE_MDN}    addr=${CDS_ADDR}

TC-CDS-011 1Y (HFC해제 - 번호변경 후)
    [Documentation]
    ...    0015(1Y HFC 서비스 해지) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    바로 앞 TC-CDS-010 이 가입한 번호(${CDS_ACTIVE_MDN})를 그대로 해제한다.
    ...    ※ 1Y 규격 필드 집합은 아직 미확인이다 — 쌍이 되는 1X 에 있는 limitSubsFlag 가
    ...       현재 분기에 빠져 있어 누락이 의심된다(docs/nodes/CDS.md 의 업무 코드 절).
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_1Y}    mdn=${CDS_ACTIVE_MDN}

TC-CDS-012 Z1 (가입해지) 
    [Documentation]
    ...    0015(Z1 해지) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    규격 Z1 필드 15개(A1 에서 min·addSvc 를 뺀 집합)를 기본값으로 전달한다.
    ...    ※ 해지 대상은 ${CDS_ACTIVE_MDN} — TC-CDS-009(D3)이 번호를 바꿨으면 바뀐 번호,
    ...       D3 를 건너뛰었거나 실패했으면 원래 번호(${CDS_MDN})다.
    ...    가입자 자체를 없애므로 이 체인의 마지막에 둔다.
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_Z1}    mdn=${CDS_ACTIVE_MDN}

# 접속 해제(0005~0008)는 Suite Teardown(`Suite CDS Disconnect`)에서 수행한다.
# 슈트가 끝나면 반드시 해야 하는 일이라 TC 로 두면 실패·필터 시 건너뛰게 된다.
