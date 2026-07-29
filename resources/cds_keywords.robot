*** Settings ***
Documentation
...    CDS 인터페이스 키워드 (TCP 고정길이 48B 헤더, 클라이언트 듀얼 소켓)
...
...    [인터페이스]
...      방향   : 테스트 도구(CDS / 능동 Connector) → PG.CDS 접속
...      채널   : Schannel(${CDS_SCH_PORT}) / Rchannel(${CDS_RCH_PORT})
...      Body   : 48B 헤더 + Data (CdsHelper, big-endian)
...
...    [Suite 정책 — Dual Socket, Rchannel 우선]
...      Suite Setup    : Suite CDS Connect
...        1) Rchannel 연결 → RchannelConnectionRequest(0003) + ACK(0004) (세션 등록)
...        2) 성공 후 Schannel 연결 → SchannelConnectionRequest(0001) + ACK(0002)
...      Test Setup     : Check CDS Sockets (둘 중 하나라도 닫히면 Fatal Error)
...      Suite Teardown : Suite CDS Disconnect
...
...    [메시지 흐름 — 로봇 능동 송신 기준]
...      접속   0001/0002(S), 0003/0004(R)
...      해제   0005/0006(S), 0007/0008(R)
...      상태   0013 ProcessStateRequest / 0014 ACK
...      Cmd    0015 → 0016 ACK → 0017 Result → 0018 ResultACK
...      UpLoad 0025 → 0026 → 0027 → 0028 (PG 발신 가능, Send/Receive 대칭)
...      Subs   0029 → 0030 → 0031 → 0032

Library    Collections
Library    String
Library    DateTime
Library    BuiltIn
Library    ${CURDIR}/CdsHelper.py    WITH NAME    Cds
Resource   ${CURDIR}/common_keywords.robot

*** Variables ***
${CDS_SCH_SOCK}        ${NONE}
${CDS_RCH_SOCK}        ${NONE}
${CDS_SYSTEM_ID}       ${NONE}
${CDS_TID_SEQ}         ${0}


*** Keywords ***

# ══════════════════════════════════════════════════════════════════
# CDS Suite 연결 관리 (클라이언트 듀얼 소켓)
# ══════════════════════════════════════════════════════════════════

Resolve CDS System Id
    [Documentation]
    ...    PG.CDS SYSTEM_ID 반환. 헤더 Destination System ID 로 사용한다.
    ...    값은 ${CDS_DST_SYS_ID}(cds_variables.robot 기본 PG01)이며
    ...    환경별로 다르면 config/env/<env>.py 에서 오버라이드한다.
    RETURN    ${CDS_DST_SYS_ID}

Suite CDS Connect
    [Documentation]
    ...    CDS Suite Setup 전용.
    ...    1) Schannel/Rchannel 2개 소켓 연결 → ${CDS_SCH_SOCK}/${CDS_RCH_SOCK}
    ...    2) Schannel/Rchannel ConnectionRequest(0001/0003) 송신 + ACK(0002/0004) 검증
    [Arguments]    ${host}=${CDS_PG_HOST}
    ...            ${sch_port}=${CDS_SCH_PORT}    ${rch_port}=${CDS_RCH_PORT}
    ...            ${timeout}=${CDS_TIMEOUT}
    ${sid}=    Resolve CDS System Id
    Set Suite Variable    ${CDS_SYSTEM_ID}    ${sid}
    Set Suite Variable    ${CDS_TID_SEQ}    ${0}
    # 1) Rchannel 먼저: TCP 연결 → RchannelConnectionRequest(0003) → ACK(0004)
    Log    [Suite] CDS Rchannel 연결 → ${host}:${rch_port} (DST_SYS=${sid})    console=True
    ${rch}=    Cds.Tcp Connect    ${host}    ${rch_port}    ${timeout}
    Set Suite Variable    ${CDS_RCH_SOCK}    ${rch}
    Send Connection Request    ${CDS_RCH_SOCK}    ${CDS_MSG_RCH_CONN_REQ}
    ${hdr}    ${data}=    Receive CDS Message    ${CDS_RCH_SOCK}
    Validate Connection Ack    ${hdr}    ${data}    ${CDS_MSG_RCH_CONN_ACK}
    # 2) Rchannel 등록 성공 후 Schannel: TCP 연결 → SchannelConnectionRequest(0001) → ACK(0002)
    Log    [Suite] CDS Schannel 연결 → ${host}:${sch_port}    console=True
    ${sch}=    Cds.Tcp Connect    ${host}    ${sch_port}    ${timeout}
    Set Suite Variable    ${CDS_SCH_SOCK}    ${sch}
    Send Connection Request    ${CDS_SCH_SOCK}    ${CDS_MSG_SCH_CONN_REQ}
    ${hdr2}    ${data2}=    Receive CDS Message    ${CDS_SCH_SOCK}
    Validate Connection Ack    ${hdr2}    ${data2}    ${CDS_MSG_SCH_CONN_ACK}
    Log    [Suite] CDS 접속 완료 (Rchannel→Schannel)    console=True

Suite CDS Disconnect
    [Documentation]    CDS Suite Teardown 전용. Release 요구(best-effort) 후 소켓 종료.
    Run Keyword And Ignore Error    Send CDS Message    ${CDS_SCH_SOCK}    ${CDS_MSG_SCH_REL_REQ}
    Run Keyword And Ignore Error    Send CDS Message    ${CDS_RCH_SOCK}    ${CDS_MSG_RCH_REL_REQ}
    Run Keyword If    $CDS_SCH_SOCK is not None    Cds.Tcp Close    ${CDS_SCH_SOCK}
    Run Keyword If    $CDS_RCH_SOCK is not None    Cds.Tcp Close    ${CDS_RCH_SOCK}
    Log    [Suite] CDS 연결 종료    console=True

Check CDS Sockets
    [Documentation]    CDS Test Setup 전용. Schannel/Rchannel 중 하나라도 닫히면 Fatal Error.
    ${ok_s}=    Cds.Is Connected    ${CDS_SCH_SOCK}
    ${ok_r}=    Cds.Is Connected    ${CDS_RCH_SOCK}
    Run Keyword If    not ${ok_s}
    ...    Fatal Error    CDS Schannel 소켓이 닫혀 있습니다. 이후 TC를 실행할 수 없습니다.
    Run Keyword If    not ${ok_r}
    ...    Fatal Error    CDS Rchannel 소켓이 닫혀 있습니다. 이후 TC를 실행할 수 없습니다.


# ══════════════════════════════════════════════════════════════════
# TID / 송수신 공통
# ══════════════════════════════════════════════════════════════════

Next CDS TID
    [Documentation]    Transaction ID 생성: date(YYYYMMDD) + 증가 seq. (반환: date, seq)
    ${date}=    Get Current Date    result_format=%Y%m%d
    ${seq}=    Evaluate    ${CDS_TID_SEQ} + 1
    Set Suite Variable    ${CDS_TID_SEQ}    ${seq}
    RETURN    ${date}    ${seq}

Send CDS Message
    [Documentation]
    ...    CDS 메시지 송신(헤더 필드는 변수/기본값에서 채움).
    ...    tid_date/tid_seq 미지정 시 오늘 날짜 + 증가 seq 자동 생성(Next CDS TID).
    ...    Continue Flag 기본 1(비연속), Serial No 기본 3.
    [Arguments]    ${sock}    ${msg_id}
    ...            ${tid_date}=${NONE}    ${tid_seq}=${NONE}
    ...            ${data}=${EMPTY}    ${cont_flag}=${1}    ${serial_no}=${3}
    IF    $tid_date is None or $tid_seq is None
        ${tid_date}    ${tid_seq}=    Next CDS TID
    END
    Cds.Send Cds    ${sock}    ${msg_id}    ${tid_date}    ${tid_seq}
    ...    ${CDS_SRC_SYS_ID}    ${CDS_SYSTEM_ID}
    ...    src_app=${CDS_SRC_APP_ID}    dst_app=${CDS_DST_APP_ID}
    ...    data=${data}    cont_flag=${cont_flag}    serial_no=${serial_no}
    Log    [TX→PG.CDS] msg_id=${msg_id} tid=${tid_date}/${tid_seq} cont=${cont_flag} ser=${serial_no}

Receive CDS Message
    [Documentation]    CDS 메시지 수신 → (header_dict, data_bytes)
    [Arguments]    ${sock}
    ${hdr}    ${data}=    Cds.Receive Cds    ${sock}
    Log    [RX←PG.CDS] msg_id=${hdr}[msg_id] tid=${hdr}[tid_date]/${hdr}[tid_seq] len=${hdr}[data_size]
    RETURN    ${hdr}    ${data}


# ══════════════════════════════════════════════════════════════════
# 접속 요구/응답 (0001~0004)
# ══════════════════════════════════════════════════════════════════

Send Connection Request
    [Documentation]    ConnectionRequest(0001/0003) 송신. TID=오늘+증가seq, Data 없음.
    [Arguments]    ${sock}    ${msg_id}
    Send CDS Message    ${sock}    ${msg_id}

Validate Connection Ack
    [Documentation]    ConnectionRequestACK(0002/0004) 검증: msg_id + Result=SC.
    [Arguments]    ${hdr}    ${data}    ${expected_msg_id}
    CDS Msg Id Should Be    ${hdr}    ${expected_msg_id}
    ${ack}=    Cds.Unpack Ack    ${data}
    CDS Result Should Be SC    ${ack}


# ══════════════════════════════════════════════════════════════════
# 접속 해제 요구/응답 (0005~0008)
# ══════════════════════════════════════════════════════════════════

Send Release Request
    [Documentation]    ReleaseRequest(0005/0007) 송신. Data 없음.
    [Arguments]    ${sock}    ${msg_id}
    Send CDS Message    ${sock}    ${msg_id}

Receive And Validate Release Ack
    [Documentation]    ReleaseRequestACK(0006/0008) 수신 → msg_id + Result=SC.
    [Arguments]    ${sock}    ${expected_msg_id}
    ${hdr}    ${data}=    Receive CDS Message    ${sock}
    CDS Msg Id Should Be    ${hdr}    ${expected_msg_id}
    ${ack}=    Cds.Unpack Ack    ${data}
    CDS Result Should Be SC    ${ack}

Send Release And Validate
    [Documentation]
    ...    ReleaseRequest(0005/0007) 송신 → ReleaseRequestACK(0006/0008, SC) 수신·검증.
    ...    단, PG 가 해제 후 ACK 없이 연결을 종료하는 동작도 정상 해제로 간주한다
    ...    (송신 전 이미 닫힘 → 건너뜀, 송신 후 ACK 없이 닫힘 → 정상 해제).
    ...    ACK 를 수신하면 msg_id + Result=SC 를 검증한다.
    [Arguments]    ${sock}    ${req_msg_id}    ${ack_msg_id}
    ${sent}=    Run Keyword And Return Status    Send Release Request    ${sock}    ${req_msg_id}
    IF    not ${sent}
        Log    Release(${req_msg_id}) 송신 전 이미 연결 종료됨 → 건너뜀    level=WARN
        RETURN
    END
    ${status}    ${ret}=    Run Keyword And Ignore Error    Receive CDS Message    ${sock}
    IF    '${status}' == 'FAIL'
        Log    Release(${req_msg_id}) 후 PG 가 ACK 없이 연결 종료 → 정상 해제로 간주    level=WARN
        RETURN
    END
    ${hdr}=    Set Variable    ${ret}[0]
    ${data}=    Set Variable    ${ret}[1]
    CDS Msg Id Should Be    ${hdr}    ${ack_msg_id}
    ${ack}=    Cds.Unpack Ack    ${data}
    CDS Result Should Be SC    ${ack}


# ══════════════════════════════════════════════════════════════════
# 프로세스 상태 확인 (0013/0014)
# ══════════════════════════════════════════════════════════════════

Send Process State Request
    [Documentation]
    ...    ProcessStateRequest(0013) 송신: CDS → PG.CDS. T-ID 는 의미 없음(자동 생성).
    ...    요구/ACK 는 동일 채널 내에서 완결(Schannel·Rchannel 각각). 기본 Schannel.
    [Arguments]    ${sock}=${CDS_SCH_SOCK}
    Send CDS Message    ${sock}    ${CDS_MSG_PROC_STATE_REQ}

Receive And Validate Process State Ack
    [Documentation]
    ...    ProcessStateRequestACK(0014) 수신: 요구를 보낸 동일 채널에서 수신(PG.CDS → CDS).
    ...    → ProcessState 반환(1=Normal). 기본 Schannel.
    [Arguments]    ${sock}=${CDS_SCH_SOCK}
    ${hdr}    ${data}=    Receive CDS Message    ${sock}
    CDS Msg Id Should Be    ${hdr}    ${CDS_MSG_PROC_STATE_ACK}
    ${state}=    Cds.Unpack Process State    ${data}
    RETURN    ${state}

Process State Should Be Normal
    [Documentation]    ProcessState 정상 검증. 0 과 ${CDS_PS_NORMAL}(1) 둘 다 정상으로 간주(2=Abnormal).
    [Arguments]    ${state}
    Should Be True    ${state} == 0 or ${state} == ${CDS_PS_NORMAL}
    ...    msg=ProcessState 기대=Normal(0 또는 ${CDS_PS_NORMAL}), 실제=${state}


# ══════════════════════════════════════════════════════════════════
# DownLoad Command (0015~0018)  — 하나의 Transaction = 동일 TID
# ══════════════════════════════════════════════════════════════════

Send Command Request
    [Documentation]
    ...    CommandRequest(0015) 송신(Schannel).
    ...    공통 5개 필드(스펙): mdn(mdn) / prod_id(product_id) / limit(limitSubsFlag) / product_type(produGenType) / device_type
    ...    코드별 추가 필드는 &{extra} 로 전달: 예) min=... new_mdn=... imsi=... addr=...
    ...    code 에 무관한 필드는 무시되고, 누락 필드는 공백으로 채워진다.
    ...    반환: tid_date, tid_seq.
    [Arguments]    ${code}=${CDS_TEST_CMD_CODE}
    ...            ${mdn}=${CDS_TEST_MDN}
    ...            ${prod_id}=${CDS_TEST_PROD_ID}
    ...            ${limit}=${CDS_TEST_LIMIT}
    ...            ${product_type}=${CDS_TEST_PROD_TYPE}
    ...            ${device_type}=${CDS_TEST_DEVICE_TYPE}
    ...            &{extra}
    ${body}=    Cds.Pack Command Body    ${code}
    ...    mdn=${mdn}    prod_id=${prod_id}    limit=${limit}    product_type=${product_type}
    ...    device_type=${device_type}    &{extra}
    ${date}    ${seq}=    Next CDS TID
    Send CDS Message    ${CDS_SCH_SOCK}    ${CDS_MSG_CMD_REQ}
    ...    tid_date=${date}    tid_seq=${seq}    data=${body}
    RETURN    ${date}    ${seq}

Receive And Validate Command Ack
    [Documentation]    CommandRequestACK(0016) 수신(Schannel) → Result=SC.
    ${hdr}    ${data}=    Receive CDS Message    ${CDS_SCH_SOCK}
    CDS Msg Id Should Be    ${hdr}    ${CDS_MSG_CMD_REQ_ACK}
    ${ack}=    Cds.Unpack Ack    ${data}
    CDS Result Should Be SC    ${ack}

Receive Command Result
    [Documentation]
    ...    CommandResult(0017) 수신 → (header, result dict). 기본 Rchannel 수신.
    ...    (Server 비동기 송신 채널 가정 — 실 PG 동작에 따라 sock 인자로 조정)
    [Arguments]    ${sock}=${CDS_RCH_SOCK}
    ${hdr}    ${data}=    Receive CDS Message    ${sock}
    CDS Msg Id Should Be    ${hdr}    ${CDS_MSG_CMD_RESULT}
    ${res}=    Cds.Unpack Result Data    ${data}
    RETURN    ${hdr}    ${res}

Send Command Result Ack
    [Documentation]    CommandResultACK(0018) 송신. 수신한 TID 를 에코.
    [Arguments]    ${tid_date}    ${tid_seq}    ${sock}=${CDS_RCH_SOCK}    ${result}=${CDS_RESULT_SC}
    ${data}=    Cds.Pack Ack    ${result}    ${0}
    Send CDS Message    ${sock}    ${CDS_MSG_CMD_RESULT_ACK}
    ...    tid_date=${tid_date}    tid_seq=${tid_seq}    data=${data}


# ══════════════════════════════════════════════════════════════════
# 가입자 데이터 SubsData (0029~0032)  — DownLoad 채널
# ══════════════════════════════════════════════════════════════════

Send Subs Data Request
    [Documentation]    SubsDataRequest(0029) 송신(Schannel, Data=MIN). 반환: tid_date, tid_seq.
    [Arguments]    ${min}=${CDS_TEST_SUBS_MIN}
    ${date}    ${seq}=    Next CDS TID
    Send CDS Message    ${CDS_SCH_SOCK}    ${CDS_MSG_SUBS_DATA_REQ}
    ...    tid_date=${date}    tid_seq=${seq}    data=${min}
    RETURN    ${date}    ${seq}

Receive And Validate Subs Data Ack
    [Documentation]    SubsDataRequestACK(0030) 수신(Schannel) → Result=SC.
    ${hdr}    ${data}=    Receive CDS Message    ${CDS_SCH_SOCK}
    CDS Msg Id Should Be    ${hdr}    ${CDS_MSG_SUBS_DATA_REQ_ACK}
    ${ack}=    Cds.Unpack Ack    ${data}
    CDS Result Should Be SC    ${ack}

Receive Subs Data Result
    [Documentation]    SubsDataResult(0031) 수신 → (header, data_bytes). 기본 Rchannel.
    [Arguments]    ${sock}=${CDS_RCH_SOCK}
    ${hdr}    ${data}=    Receive CDS Message    ${sock}
    CDS Msg Id Should Be    ${hdr}    ${CDS_MSG_SUBS_DATA_RESULT}
    RETURN    ${hdr}    ${data}

Send Subs Data Result Ack
    [Documentation]    SubsDataResultACK(0032) 송신. 수신 TID 에코.
    [Arguments]    ${tid_date}    ${tid_seq}    ${sock}=${CDS_RCH_SOCK}    ${result}=${CDS_RESULT_SC}
    ${data}=    Cds.Pack Ack    ${result}    ${0}
    Send CDS Message    ${sock}    ${CDS_MSG_SUBS_DATA_RESULT_ACK}
    ...    tid_date=${tid_date}    tid_seq=${tid_seq}    data=${data}


# ══════════════════════════════════════════════════════════════════
# UpLoad (0025~0028)  — PG(Server) 발신 가능, Send/Receive 대칭
# ══════════════════════════════════════════════════════════════════

Receive Upload Request
    [Documentation]    UploadRequest(0025) 수신 → (header, data_bytes). 기본 Rchannel.
    [Arguments]    ${sock}=${CDS_RCH_SOCK}
    ${hdr}    ${data}=    Receive CDS Message    ${sock}
    CDS Msg Id Should Be    ${hdr}    ${CDS_MSG_UPLOAD_REQ}
    RETURN    ${hdr}    ${data}

Send Upload Request Ack
    [Documentation]    UploadRequestACK(0026) 송신. 수신 TID 에코.
    [Arguments]    ${tid_date}    ${tid_seq}    ${sock}=${CDS_RCH_SOCK}    ${result}=${CDS_RESULT_SC}
    ${data}=    Cds.Pack Ack    ${result}    ${0}
    Send CDS Message    ${sock}    ${CDS_MSG_UPLOAD_REQ_ACK}
    ...    tid_date=${tid_date}    tid_seq=${tid_seq}    data=${data}

Send Upload Result
    [Documentation]    UploadResult(0027) 송신(Result char2 + payload).
    [Arguments]    ${tid_date}    ${tid_seq}    ${payload}=${EMPTY}
    ...            ${sock}=${CDS_SCH_SOCK}    ${result}=${CDS_RESULT_SC}
    ${data}=    Cds.Pack Result Data    ${result}    ${payload}
    Send CDS Message    ${sock}    ${CDS_MSG_UPLOAD_RESULT}
    ...    tid_date=${tid_date}    tid_seq=${tid_seq}    data=${data}

Receive And Validate Upload Result Ack
    [Documentation]    UploadResultACK(0028) 수신 → Result=SC.
    [Arguments]    ${sock}=${CDS_SCH_SOCK}
    ${hdr}    ${data}=    Receive CDS Message    ${sock}
    CDS Msg Id Should Be    ${hdr}    ${CDS_MSG_UPLOAD_RESULT_ACK}
    ${ack}=    Cds.Unpack Ack    ${data}
    CDS Result Should Be SC    ${ack}


# ══════════════════════════════════════════════════════════════════
# 공통 검증
# ══════════════════════════════════════════════════════════════════

CDS Msg Id Should Be
    [Arguments]    ${hdr}    ${expected}
    Should Be Equal As Integers    ${hdr}[msg_id]    ${expected}
    ...    msg=Message ID 기대=${expected}, 실제=${hdr}[msg_id]

CDS Result Should Be SC
    [Arguments]    ${ack}
    Should Be Equal As Strings    ${ack}[result]    ${CDS_RESULT_SC}
    ...    msg=Result 기대=SC, 실제=${ack}[result]

Command Download Flow
    [Documentation]
    ...    CommandRequest(0015) → ACK(0016, SC) → Result(0017, SC) → ResultACK(0018) 전체 흐름.
    ...    공통 5개 필드(mdn/prod_id/limit/product_type/device_type)를 명시하고, 코드별 추가 필드는 &{extra} 로 전달한다.
    [Arguments]    ${code}
    ...            ${mdn}=${CDS_TEST_MDN}
    ...            ${prod_id}=${CDS_TEST_PROD_ID}
    ...            ${limit}=${CDS_TEST_LIMIT}
    ...            ${product_type}=${CDS_TEST_PROD_TYPE}
    ...            ${device_type}=${CDS_TEST_DEVICE_TYPE}
    ...            &{extra}
    Send Command Request    code=${code}
    ...    mdn=${mdn}    prod_id=${prod_id}    limit=${limit}    product_type=${product_type}
    ...    device_type=${device_type}    &{extra}
    Receive And Validate Command Ack
    ${hdr}    ${res}=    Receive Command Result
    CDS Result Should Be SC    ${res}
    Send Command Result Ack    ${hdr}[tid_date]    ${hdr}[tid_seq]
