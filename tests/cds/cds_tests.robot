*** Settings ***
Documentation
...    CDS 인터페이스 기능 검증 (TCP 고정길이 48B, 클라이언트 듀얼 소켓)
...
...    [테스트 대상]
...    테스트 도구(CDS / 능동 Connector) → PG.CDS 접속
...    Schannel(${CDS_SCH_PORT}) / Rchannel(${CDS_RCH_PORT}) 2개 outbound 소켓
...
...    [Suite 소켓 정책]
...    Suite Setup  : Schannel/Rchannel 연결 → ConnectionRequest 송신 + ACK 검증
...    Test Setup   : Check CDS Sockets (하나라도 닫히면 Suite 중단)
...    Suite Teardown : Release 후 소켓 종료
...    각 TC        : ${CDS_SCH_SOCK}/${CDS_RCH_SOCK} 공유 사용 (TC별 연결/해제 없음)
...
...    포트/SYSTEM_ID 는 PG_V2.cfg [CDS] 에서 읽되, 미수신 시 기본값(9200/9201, PG01).

Resource    ../../resources/variables.robot
Resource    ../../resources/cds_variables.robot
Resource    ../../resources/common_keywords.robot
Resource    ../../resources/cds_keywords.robot

Variables    ../../resources/DynamicVars.py    pg@192.168.15.141:/PG/CFG/PG_V2.cfg    section=CDS:SYSTEM_ID=PG_CDS_PG_V2_SYSTEM_ID    pass=${PG_ROBOT_SSH_PASS}
Variables    ../../resources/DynamicVars.py    pg@192.168.15.141:/PG/CFG/PG_V2.cfg    section=CDS:R_PORT=CDS_RCH_PORT    pass=${PG_ROBOT_SSH_PASS}
Variables    ../../resources/DynamicVars.py    pg@192.168.15.141:/PG/CFG/PG_V2.cfg    section=CDS:S_PORT=CDS_SCH_PORT    pass=${PG_ROBOT_SSH_PASS}


Suite Setup      Suite CDS Connect
Suite Teardown   Suite CDS Disconnect
Test Setup       Check CDS Sockets

*** Test Cases ***

# ════════════════════════════════════════════════════════════════
# 접속 (0001~0004) — Suite Setup 에서 수행, 여기서 세션 생존 재확인
# ════════════════════════════════════════════════════════════════

TC-CDS-001 접속 - Schannel/Rchannel 연결 및 세션 유지
    [Documentation]    Suite Setup 의 ConnectionRequest/ACK(SC) 성공 후 두 소켓 생존 확인
    [Tags]    cds    connect    smoke
    Should Not Be Equal    ${CDS_SCH_SOCK}    ${NONE}
    Should Not Be Equal    ${CDS_RCH_SOCK}    ${NONE}
    ${ok_s}=    Cds.Is Connected    ${CDS_SCH_SOCK}
    ${ok_r}=    Cds.Is Connected    ${CDS_RCH_SOCK}
    Should Be True    ${ok_s}    msg=Schannel 소켓이 닫혀 있음
    Should Be True    ${ok_r}    msg=Rchannel 소켓이 닫혀 있음


# ════════════════════════════════════════════════════════════════
# 프로세스 상태 확인 (0013/0014)
# ════════════════════════════════════════════════════════════════

TC-CDS-002 ProcessState - 요구 → ACK(Normal)
    [Documentation]    0013 송신 → 0014 수신, Process State=Normal(1) 확인
    [Tags]    cds    process-state    smoke
    Send Process State Request
    ${state}=    Receive And Validate Process State Ack
    Process State Should Be Normal    ${state}


# ════════════════════════════════════════════════════════════════
# DownLoad Command (0015~0018)
# ════════════════════════════════════════════════════════════════

TC-CDS-003 Command - 처리 요구 → ACK → 결과 보고 → 결과 응답
    [Documentation]
    ...    0015 송신 → 0016 ACK(SC) → 0017 Result 수신 → 0018 ResultACK 송신
    ...    ※ 실 PG.CDS 가 명령어를 처리·결과 보고해야 동작 (CDS_TEST_COMMAND_DATA 는 TODO)
    [Tags]    cds    command    validation
    ${date}    ${seq}=    Send Command Request
    Receive And Validate Command Ack
    ${hdr}    ${res}=    Receive Command Result
    CDS Result Should Be SC    ${res}
    Send Command Result Ack    ${hdr}[tid_date]    ${hdr}[tid_seq]


# ════════════════════════════════════════════════════════════════
# 가입자 데이터 SubsData (0029~0032)
# ════════════════════════════════════════════════════════════════

TC-CDS-004 SubsData - 데이터 요구 → ACK → 결과 보고 → 결과 응답
    [Documentation]
    ...    0029 송신(MIN) → 0030 ACK(SC) → 0031 Result 수신 → 0032 ResultACK 송신
    ...    ※ 실 PG.CDS 가 가입자 데이터를 조회·보고해야 동작 (MIN 은 TODO)
    [Tags]    cds    subs-data    validation
    ${date}    ${seq}=    Send Subs Data Request
    Receive And Validate Subs Data Ack
    ${hdr}    ${data}=    Receive Subs Data Result
    Send Subs Data Result Ack    ${hdr}[tid_date]    ${hdr}[tid_seq]


# ════════════════════════════════════════════════════════════════
# UpLoad (0025~0028) — PG(Server)가 먼저 송신해야 동작 → 주석 처리
# ════════════════════════════════════════════════════════════════

# TC-CDS-005 UpLoad - 요구 수신 → ACK → 결과 보고 → 결과 응답
#     [Documentation]
#     ...    PG 발신 UploadRequest(0025) 수신 → 0026 ACK 송신 →
#     ...    0027 UploadResult 송신 → 0028 ResultACK 수신
#     ...    ※ PG.CDS 가 실제 UpLoad 이벤트를 발생시켜야 동작
#     [Tags]    cds    upload
#     ${hdr}    ${data}=    Receive Upload Request
#     Send Upload Request Ack    ${hdr}[tid_date]    ${hdr}[tid_seq]
#     Send Upload Result    ${hdr}[tid_date]    ${hdr}[tid_seq]    payload=0
#     Receive And Validate Upload Result Ack

# TC-CDS-006 접속 해제 - Schannel/Rchannel Release (0005~0008)
#     [Documentation]    0005/0007 송신 → 0006/0008 ACK(SC) 수신
#     [Tags]    cds    release
#     Send CDS Message    ${CDS_SCH_SOCK}    ${CDS_MSG_SCH_REL_REQ}
#     ${hdr}    ${data}=    Receive CDS Message    ${CDS_SCH_SOCK}
#     CDS Msg Id Should Be    ${hdr}    ${CDS_MSG_SCH_REL_ACK}
#     ${ack}=    Cds.Unpack Ack    ${data}
#     CDS Result Should Be SC    ${ack}
