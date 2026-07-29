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
...    포트/SYSTEM_ID 는 cds_variables.robot 기본값(9200/9201, PG01).
...    환경별로 다르면 config/env/<env>.py 에서 오버라이드한다.
...
...    [TC 번호 체계]
...      TC-CDS-001       : 접속 (Schannel/Rchannel 세션 생존)
...      TC-CDS-002       : ProcessState 상태확인 (0013/0014)
...      TC-CDS-003 ~ 011 : Download Command (0015~0018) — 업무 코드별
...      TC-CDS-012       : Command Body 인코딩 검증 (A1 골든 샘플 327B, 송신 없음)
...      TC-CDS-013       : SubsData (0029~0032) ※ 현재 주석 처리 (PG 조회 필요)
...      TC-CDS-014       : UpLoad (0025~0028) ※ 현재 주석 처리 (PG 가 먼저 송신)
...      TC-CDS-015       : 접속 해제 (0005~0008)

Resource    ../../resources/variables.robot
Resource    ../../resources/cds_variables.robot
Resource    ../../resources/common_keywords.robot
Resource    ../../resources/cds_keywords.robot


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

TC-CDS-002 상태확인 - ProcessStateReuqest(0013) S/R채널 각각 → ACK(0014)
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

TC-CDS-003 Download(A1 신규) - Request → ACK → Result → ACK
    [Documentation]
    ...    0015(A1 신규) 송신 → 0016 ACK(SC) → 0017 Result 수신 → 0018 ResultACK 송신
    ...    Body 는 실 A1 전문 샘플(327B, 5G SA 가입자)과 동일한 13개 필드를 채운다.
    ...    ca / imsi 는 규격 A1 필드 목록에 없으나 실 전문이 채워 보내므로 함께 보낸다.
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_A1}
    ...    min=${CDS_TEST_MIN}
    ...    network=${CDS_A1_NETWORK}            tablet_yn=${CDS_A1_TABLET_YN}
    ...    os_ver=${CDS_A1_OS_VER}              device_model=${CDS_A1_DEVICE_MODEL}
    ...    ca=${CDS_A1_CA}                      aprf=${CDS_A1_APRF}
    ...    imsi=${CDS_A1_IMSI}
    ...    device_type=${CDS_A1_DEVICE_TYPE}    product_type=${CDS_A1_PROD_TYPE}

TC-CDS-004 Download(1X HFC가입) - Request → ACK → Result → ACK
    [Documentation]    0015(1X HFC 서비스 가입) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_1X}    addr=${CDS_TEST_ADDR}

TC-CDS-005 Download(1Y HFC해지) - Request → ACK → Result → ACK
    [Documentation]    0015(1Y HFC 서비스 해지) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_1Y}

TC-CDS-006 Download(I2 부가서비스신청) - Request → ACK → Result → ACK
    [Documentation]    0015(I2 부가서비스신청) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_I2}

TC-CDS-007 Download(I3 부가서비스해지) - Request → ACK → Result → ACK
    [Documentation]    0015(I3 부가서비스해지) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_I3}

TC-CDS-008 Download(C1 기기변경) - Request → ACK → Result → ACK
    [Documentation]    0015(C1 기기변경) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_C1}    new_mdn=${CDS_TEST_NEW_MDN}    new_min=${CDS_TEST_NEW_MIN}

TC-CDS-009 Download(G1 정보변경) - Request → ACK → Result → ACK
    [Documentation]    0015(G1 정보변경) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_G1}

TC-CDS-010 Download(D3 번호변경) - Request → ACK → Result → ACK
    [Documentation]    0015(D3 번호변경) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_D3}    new_mdn=${CDS_TEST_NEW_MDN}    min=${CDS_TEST_MIN}    new_min=${CDS_TEST_NEW_MIN}

TC-CDS-011 Download(Z1 해지) - Request → ACK → Result → ACK
    [Documentation]    0015(Z1 해지) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    [Tags]    cds    command    validation
    Command Download Flow    ${CDS_CODE_Z1}

TC-CDS-012 CommandRequest Body 인코딩 - A1 골든 샘플 327B 대조
    [Documentation]
    ...    조립한 A1 Body 를 실 전문 골든 샘플(327B)과 바이트 단위로 대조한다. 송신하지 않는다.
    ...    CdsHelper._CMD_LAYOUT 의 필드 순서·길이가 바뀌면 여기서 걸린다.
    ...    ※ CDS 는 PG 가 Body 내용과 무관하게 SC 를 돌려주므로, 인코딩 회귀를 잡는
    ...       자동 판정 수단은 이 TC 가 유일하다.
    [Tags]    cds    command    validation
    Verify A1 Golden Body


# ════════════════════════════════════════════════════════════════
# 가입자 데이터 SubsData (0029~0032)
# ════════════════════════════════════════════════════════════════

#TC-CDS-013 SubsData - SubsDataRequest → ACK → SubsDataResult → ACK
#    [Documentation]
#    ...    0029 송신(MIN) → 0030 ACK(SC) → 0031 Result 수신 → 0032 ResultACK 송신
#    ...    ※ 실 PG.CDS 가 가입자 데이터를 조회·보고해야 동작 (MIN 은 TODO)
#    [Tags]    cds    subs-data    validation
#    ${date}    ${seq}=    Send Subs Data Request
#    Receive And Validate Subs Data Ack
#    ${hdr}    ${data}=    Receive Subs Data Result
#    Send Subs Data Result Ack    ${hdr}[tid_date]    ${hdr}[tid_seq]


# ════════════════════════════════════════════════════════════════
# UpLoad (0025~0028) — PG(Server)가 먼저 송신해야 동작 → 주석 처리
# ════════════════════════════════════════════════════════════════

# TC-CDS-014 UpLoad - 요구 수신 → ACK → 결과 보고 → 결과 응답
#     [Documentation]
#     ...    PG 발신 UploadRequest(0025) 수신 → 0026 ACK 송신 →
#     ...    0027 UploadResult 송신 → 0028 ResultACK 수신
#     ...    ※ PG.CDS 가 실제 UpLoad 이벤트를 발생시켜야 동작
#     [Tags]    cds    upload
#     ${hdr}    ${data}=    Receive Upload Request
#     Send Upload Request Ack    ${hdr}[tid_date]    ${hdr}[tid_seq]
#     Send Upload Result    ${hdr}[tid_date]    ${hdr}[tid_seq]    payload=0
#     Receive And Validate Upload Result Ack

TC-CDS-015 접속 해제 - Schannel 해제 후 Rchannel 해제
    [Documentation]
    ...    Schannel 접속 해제 요구(0005) → 응답(0006, SC) 처리 후,
    ...    Rchannel 접속 해제 요구(0007) → 응답(0008, SC) 처리
    [Tags]    cds    release
    # 1) Schannel 접속 해제 요구/응답 (ACK 없이 종료 시에도 정상 해제로 간주)
    Send Release And Validate    ${CDS_SCH_SOCK}    ${CDS_MSG_SCH_REL_REQ}    ${CDS_MSG_SCH_REL_ACK}
    # 2) Rchannel 접속 해제 요구/응답
    Send Release And Validate    ${CDS_RCH_SOCK}    ${CDS_MSG_RCH_REL_REQ}    ${CDS_MSG_RCH_REL_ACK}
