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
Library    ${CURDIR}/CdsDbHelper.py    WITH NAME    CdsDb
Resource   ${CURDIR}/common_keywords.robot

*** Variables ***
${CDS_SCH_SOCK}        ${NONE}
${CDS_RCH_SOCK}        ${NONE}
${CDS_DB_CONN}         ${NONE}     # PDB connection (Suite Setup 에서 접속)
${CDS_SYSTEM_ID}       ${NONE}
${CDS_TID_SEQ}         ${0}        # 같은 초 안의 일련번호 (Next CDS TID 가 관리)
${CDS_TID_LAST_HMS}    ${EMPTY}    # 직전 TID 의 HHMMSS. 초가 바뀌면 위 일련번호를 리셋


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
    ...    3) 두 소켓 생존 확인 — 실패 시 Suite Setup 이 실패해 전 TC 가 실행되지 않는다
    ...    4) PDB 접속 → ${CDS_DB_CONN} (소켓과 같이 슈트당 1회)
    ...
    ...    ※ 접속 자체가 TC 가 아니다. Setup 이 실패하면 슈트가 서지 않으므로
    ...       별도 TC 로 재확인할 필요가 없다(구 TC-CDS-001 을 여기로 흡수).
    ...
    ...    ★ PDB 접속도 여기서 한다(소켓과 동일 정책) — 그래서 접속 정보가 없거나
    ...       DB 가 안 붙으면 **DB 를 안 쓰는 전문 TC 까지 포함해 슈트 전체가 서지 않는다.**
    ...       `--exclude db` 로도 피할 수 없다(Setup 은 태그와 무관하게 돈다).
    ...       cds_variables.robot 의 ${CDS_DB_*} 를 반드시 채울 것.
    [Arguments]    ${host}=${CDS_PG_HOST}
    ...            ${sch_port}=${CDS_SCH_PORT}    ${rch_port}=${CDS_RCH_PORT}
    ...            ${timeout}=${CDS_TIMEOUT}
    ${sid}=    Resolve CDS System Id
    Set Suite Variable    ${CDS_SYSTEM_ID}    ${sid}
    Set Suite Variable    ${CDS_TID_SEQ}    ${0}
    Set Suite Variable    ${CDS_TID_LAST_HMS}    ${EMPTY}
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
    # 3) 두 소켓 생존 확인 (구 TC-CDS-001)
    Should Not Be Equal    ${CDS_SCH_SOCK}    ${NONE}    msg=Schannel 소켓이 생성되지 않았습니다
    Should Not Be Equal    ${CDS_RCH_SOCK}    ${NONE}    msg=Rchannel 소켓이 생성되지 않았습니다
    ${ok_s}=    Cds.Is Connected    ${CDS_SCH_SOCK}
    ${ok_r}=    Cds.Is Connected    ${CDS_RCH_SOCK}
    Should Be True    ${ok_s}    msg=Schannel 소켓이 닫혀 있음
    Should Be True    ${ok_r}    msg=Rchannel 소켓이 닫혀 있음
    # 4) PDB 접속 — 소켓과 같이 슈트당 1회. Suite CDS Disconnect 가 닫는다.
    Ensure CDS DB Connection
    Log    [Suite] CDS 접속 완료 (Rchannel→Schannel + PDB)    console=True

Suite CDS Disconnect
    [Documentation]
    ...    CDS Suite Teardown 전용.
    ...    Schannel 해제 요구(0005) → ACK(0006, SC) 검증, 이어서 Rchannel(0007→0008),
    ...    그 뒤 소켓 종료.
    ...
    ...    `Send Release And Validate` 가 ACK 를 검증하되 **PG 가 ACK 없이 끊는 것도
    ...    정상 해제로 간주**한다(규격상 허용되는 동작). 따라서 Teardown 이 그 이유로
    ...    실패하지 않는다.
    ...
    ...    ※ 해제 자체가 TC 가 아니다 — 슈트가 끝나면 반드시 수행돼야 하므로
    ...       Teardown 이 맞다(구 TC-CDS-016 을 여기로 흡수).
    ...       Teardown 은 TC 실패 여부와 무관하게 항상 실행된다.
    ...
    ...    ACK 검증을 Run Keyword And Ignore Error 로 감싸지 않는다 — 감싸면 구 TC-CDS-016
    ...    의 검증이 무력화된다. Robot 은 teardown 안의 키워드가 실패해도 **나머지를 계속
    ...    실행**하므로, 아래 Tcp Close 는 어차피 수행된다.
    Send Release And Validate    ${CDS_SCH_SOCK}    ${CDS_MSG_SCH_REL_REQ}    ${CDS_MSG_SCH_REL_ACK}
    Send Release And Validate    ${CDS_RCH_SOCK}    ${CDS_MSG_RCH_REL_REQ}    ${CDS_MSG_RCH_REL_ACK}
    Run Keyword If    $CDS_SCH_SOCK is not None    Cds.Tcp Close    ${CDS_SCH_SOCK}
    Run Keyword If    $CDS_RCH_SOCK is not None    Cds.Tcp Close    ${CDS_RCH_SOCK}
    Close CDS DB Connection
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
    [Documentation]
    ...    Transaction ID 생성. (반환: date, seq)
    ...
    ...    와이어 형식은 규격 그대로 date char(8) + seq uint32 BE 다 — 바꾸지 않았다.
    ...    다만 seq 를 `HHMMSS * ${CDS_TID_SEQ_MOD} + 일련번호` 로 채워서,
    ...    PG 가 `sprintf("%8.8s%08d")` 로 만드는 16자 TRANSACTION_ID 가
    ...    **YYYYMMDDHHMMSS + 2자리 일련번호** 가 되게 한다.
    ...    (근거: CDS/CDownMessage.cpp:70, CDS/sql.txt:6 — cds_variables.robot 주석 참조)
    ...
    ...    일련번호는 **초가 바뀌면 0 으로 리셋**된다. 같은 초 안에서만 증가하므로
    ...    PG DB 의 PRIMARY KEY(TRANSACTION_ID) 와 충돌하지 않는다.
    ${now}=    Get Current Date    result_format=%Y%m%d%H%M%S
    ${date}=    Get Substring    ${now}    0    8
    ${hms}=     Get Substring    ${now}    8    14
    IF    '${hms}' != '${CDS_TID_LAST_HMS}'
        Set Suite Variable    ${CDS_TID_LAST_HMS}    ${hms}
        Set Suite Variable    ${CDS_TID_SEQ}    ${0}
    END
    ${no}=    Evaluate    ${CDS_TID_SEQ} + 1
    IF    ${no} >= ${CDS_TID_SEQ_MOD}
        Log    같은 초(HHMMSS=${hms})에 TID 를 ${CDS_TID_SEQ_MOD} 개 넘게 만들었습니다. 일련번호가 순환하므로 TID 가 중복될 수 있습니다.    level=WARN
        ${no}=    Evaluate    ${no} % ${CDS_TID_SEQ_MOD}
    END
    Set Suite Variable    ${CDS_TID_SEQ}    ${no}
    ${seq}=    Evaluate    int('${hms}') * ${CDS_TID_SEQ_MOD} + ${no}
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
    # PG 로그·DB 와 대조하기 쉽도록 PG 가 만드는 16자 형태(%8.8s%08d)를 같이 남긴다
    ${tid16}=    Evaluate    '${tid_date}'[:8] + '%08d' % ${tid_seq}
    Log    [TX→PG.CDS] msg_id=${msg_id} tid=${tid16} (${tid_date}/${tid_seq}) cont=${cont_flag} ser=${serial_no}

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
        # 실 PG.CDS 는 Release 후 ACK 없이 끊는 것이 통상 동작이라 매 실행마다 WARN 2건
        # (Release 5 / Release 7)이 리포트 상단에 떴다. 코드 스스로 "정상 해제로 간주"
        # 한다고 선언한 경로를 WARN 으로 올리는 것이 어긋나므로 INFO 로 내렸다.
        # 추적은 유지된다 — log.html 에서 이 줄로 ACK 수신 여부를 구분할 수 있다.
        #Log    Release(${req_msg_id}) 후 PG 가 ACK 없이 연결 종료 → 정상 해제로 간주    level=WARN
        Log    Release(${req_msg_id}) 후 PG 가 ACK 없이 연결 종료 → 정상 해제로 간주
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
    ...    가입자·단말·망 공용 필드를 cds_variables.robot 기본값으로 전달한다
    ...    (A1/Z1/C1/G1/D3 이 거의 같은 집합을 쓴다).
    ...    코드 전용 필드는 &{extra} 로: 예) new_mdn=... new_min=... addr=... data_prod_id=...
    ...    ※ code 의 분기가 선언하지 않은 필드는 값을 넘겨도 버려진다(CdsHelper 참조).
    ...    반환: tid_date, tid_seq.
    [Arguments]    ${code}=${CDS_CMD_CODE}
    ...            ${mdn}=${CDS_MDN}                      ${min}=${CDS_MIN}
    ...            ${prod_id}=${CDS_PROD_ID}              ${limit}=${CDS_LIMIT}
    ...            ${network}=${CDS_NETWORK}              ${tablet_yn}=${CDS_TABLET_YN}
    ...            ${os_ver}=${CDS_OS_VER}                ${device_model}=${CDS_DEVICE_MODEL}
    ...            ${ca}=${CDS_CA}                        ${aprf}=${CDS_APRF}
    ...            ${imsi}=${CDS_IMSI}                    ${mvno}=${CDS_MVNO}
    ...            ${ms_type}=${CDS_MS_TYPE}
    ...            ${category_lte}=${CDS_CATEGORY_LTE}    ${category_5g}=${CDS_CATEGORY_5G}
    ...            ${device_type}=${CDS_DEVICE_TYPE}      ${product_type}=${CDS_PROD_TYPE}
    ...            &{extra}
    ${body}=    Cds.Pack Command Body    ${code}
    ...    mdn=${mdn}                      min=${min}
    ...    prod_id=${prod_id}              limit=${limit}
    ...    network=${network}              tablet_yn=${tablet_yn}
    ...    os_ver=${os_ver}                device_model=${device_model}
    ...    ca=${ca}                        aprf=${aprf}
    ...    imsi=${imsi}                    mvno=${mvno}
    ...    ms_type=${ms_type}
    ...    category_lte=${category_lte}    category_5g=${category_5g}
    ...    device_type=${device_type}      product_type=${product_type}
    ...    &{extra}
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
    [Arguments]    ${min}=${CDS_SUBS_MIN}
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
    ...    Body 필드 기본값은 `Send Command Request` 가 cds_variables.robot 에서 채운다
    ...    (가입자·단말·망 공용 필드). 여기서 재선언하지 않는다 — 기본값이 두 곳에 생기면 어긋난다.
    ...    필드를 덮거나 코드 전용 필드를 줄 때만 &{extra} 로 전달한다:
    ...      Command Download Flow    ${CDS_CODE_D3}    new_mdn=...    new_min=...
    [Arguments]    ${code}    &{extra}
    Send Command Request    code=${code}    &{extra}
    Receive And Validate Command Ack
    ${hdr}    ${res}=    Receive Command Result
    CDS Result Should Be SC    ${res}
    Send Command Result Ack    ${hdr}[tid_date]    ${hdr}[tid_seq]


# ══════════════════════════════════════════════════════════════════
# PDB 조회 — 전문 반영 판정 (ODBC / pyodbc)
#
# CommandResult(0017)는 Body 내용과 무관하게 SC 를 준다. 전문이 실제로 가입자
# 테이블에 반영됐는지는 PDB 를 직접 봐야 알 수 있다.
#
# 접속은 **소켓과 같은 정책**이다 — Suite Setup(`Suite CDS Connect`)에서 슈트당 1회
# 붙고 connection 을 Suite Variable 로 공유한다(TC 별 접속/해제 없음).
# 종료는 Suite CDS Disconnect 가 한다.
# → 그 대가로 DB 접속 정보가 없으면 전문 송수신 TC 까지 포함해 슈트가 서지 않는다.
#
# 트랜잭션은 **autocommit 을 끈 상태**로 연다(CdsDbHelper.db_connect). 조회 직전마다
# rollback 으로 트랜잭션을 끊어야 재조회가 새 스냅샷을 본다 — 그건 Db Count 가 한다.
# ══════════════════════════════════════════════════════════════════

Ensure CDS DB Connection
    [Documentation]
    ...    PDB 에 접속돼 있지 않으면 접속한다(슈트당 1회). 이미 있으면 그대로 쓴다.
    ...    정상 경로에서는 `Suite CDS Connect` 가 한 번 부르고 끝이다 — 조회 키워드에도
    ...    남겨 둔 것은 슈트 밖에서 키워드만 따로 부를 때의 안전장치다.
    ...
    ...    ★ 접속 문자열(${CDS_DB_CONNSTR})은 **인자로 넘기지 않는다** — 비밀번호가
    ...      들어 있어 log.html 의 Arguments 에 평문으로 남기 때문이다. Python 이
    ...      환경변수 PG_CDS_DB_CONNSTR → ${CDS_DB_CONNSTR} 순으로 직접 읽고,
    ...      비어 있으면 어디에 채워야 하는지까지 담아 실패한다.
    ...      로그에는 마스킹된 문자열(PWD=****)만 남는다.
    ...
    ...    autocommit 은 ${CDS_DB_AUTOCOMMIT}(기본 ${FALSE}) 로 전달한다.
    IF    $CDS_DB_CONN is not None
        RETURN
    END
    ${shown}=    CdsDb.Masked Conn Str
    Log    [Suite] PDB 접속 시도 — ${shown}    console=True
    ${conn}=    CdsDb.Db Connect
    ...    timeout=${CDS_DB_TIMEOUT}    autocommit=${CDS_DB_AUTOCOMMIT}
    Set Suite Variable    ${CDS_DB_CONN}    ${conn}
    Log    [Suite] PDB 접속 완료 (autocommit=${CDS_DB_AUTOCOMMIT})    console=True

Close CDS DB Connection
    [Documentation]    PDB connection 종료. 접속한 적이 없으면 아무것도 하지 않는다.
    IF    $CDS_DB_CONN is None
        RETURN
    END
    CdsDb.Db Close    ${CDS_DB_CONN}
    Set Suite Variable    ${CDS_DB_CONN}    ${NONE}
    Log    [Suite] PDB 연결 종료    console=True

CDS DB Count
    [Documentation]
    ...    COUNT(*) 조회 → 정수 반환. `?` 자리표시자에 @{params} 가 순서대로
    ...    **파라미터 바인딩**된다 — 방식 선택은 없다(리터럴 모드는 제거됐다).
    [Arguments]    ${sql}    @{params}
    Ensure CDS DB Connection
    ${count}=    CdsDb.Db Count    ${CDS_DB_CONN}    ${sql}    @{params}
    Log    [PDB] ${sql} / params=@{params} → ${count}
    RETURN    ${count}

CDS DB Count Should Be
    [Documentation]    COUNT 조회 결과 검증. ${label} 은 실패 메시지에만 쓴다.
    [Arguments]    ${label}    ${expected}    ${sql}    @{params}
    ${count}=    CDS DB Count    ${sql}    @{params}
    Should Be Equal As Integers    ${count}    ${expected}
    ...    msg=${label} 행 수 기대=${expected}, 실제=${count}

Subscriber Rows Should Be Provisioned
    [Documentation]
    ...    가입자 프로파일 1건 + 서비스 2건(DATA_USAGE_LEVEL / DATA_USAGE_LEVEL_2)이
    ...    모두 있는지 한 번 조회한다. 재시도는 `Verify Subscriber Provisioned In PDB` 가 한다.
    [Arguments]    ${mdn}    ${svc_1}    ${svc_2}
    CDS DB Count Should Be    ${CDS_DB_TBL_PROFILE} (MDN=${mdn})
    ...    ${1}    ${CDS_DB_SQL_PROFILE}    ${mdn}
    CDS DB Count Should Be    ${CDS_DB_TBL_SERVICE} (MDN=${mdn}, SVC_ID=${svc_1})
    ...    ${1}    ${CDS_DB_SQL_SERVICE}    ${mdn}    ${svc_1}
    CDS DB Count Should Be    ${CDS_DB_TBL_SERVICE} (MDN=${mdn}, SVC_ID=${svc_2})
    ...    ${1}    ${CDS_DB_SQL_SERVICE}    ${mdn}    ${svc_2}

Verify Subscriber Provisioned In PDB
    [Documentation]
    ...    전문이 PDB 에 반영됐는지 판정한다. **세 조회가 모두 1이어야 성공**이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_PROFILE WHERE MDN=?
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE WHERE MDN=? AND SVC_ID='DATA_USAGE_LEVEL'
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE WHERE MDN=? AND SVC_ID='DATA_USAGE_LEVEL_2'
    ...
    ...    PG.SDM 이 T_CDS_ORDER_HIST 를 주기적으로 폴링해 반영하므로 CommandResult(0017)
    ...    직후에는 아직 안 들어와 있을 수 있다 → ${CDS_DB_WAIT} 동안 ${CDS_DB_WAIT_INTERVAL}
    ...    간격으로 재조회한다. 그 시간 안에 세 건이 다 차지 않으면 실패한다.
    [Arguments]    ${mdn}=${CDS_MDN}
    ...            ${svc_1}=${CDS_DB_SVC_DATA_USAGE}    ${svc_2}=${CDS_DB_SVC_DATA_USAGE_2}
    Ensure CDS DB Connection
    Wait Until Keyword Succeeds    ${CDS_DB_WAIT}    ${CDS_DB_WAIT_INTERVAL}
    ...    Subscriber Rows Should Be Provisioned    ${mdn}    ${svc_1}    ${svc_2}
