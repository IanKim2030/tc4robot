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
# 도구가 PCF 역할로 SBI Noti(HTTP/2 h2c)를 받는다 → 의존성: pip install h2
Library    ${CURDIR}/HttpNotiServer.py    WITH NAME    Noti
Resource   ${CURDIR}/common_keywords.robot
# 1X(HFC 가입)가 PG.BSUBS→UPM Subs-Info(0x07)를 유발한다 → TC-CDS-003 이 UPM
# 키워드를 쓴다. PCF 슈트가 nag_keywords 를 들여오는 것과 같은 구조.
Resource   ${CURDIR}/upm_keywords.robot

*** Variables ***
${CDS_SCH_SOCK}        ${NONE}
${CDS_RCH_SOCK}        ${NONE}
${CDS_DB_CONN}         ${NONE}     # PDB connection (Suite Setup 에서 접속)
${CDS_SYSTEM_ID}       ${NONE}
${CDS_NOTI_SRV}        ${NONE}     # PCF Noti 수신 서버 핸들 (Suite Setup 에서 기동)
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
    # 5) UPM 접속 — TC-CDS-003(1X)이 PG.BSUBS→UPM Subs-Info(0x07)를 받아야 한다.
    #    ${CDS_UPM_VERIFY}=${FALSE} 면 통째로 건너뛴다(그러면 UPM 의존이 사라진다).
    IF    ${CDS_UPM_VERIFY}
        Suite UPM Connect
    ELSE
        Log    [Suite] UPM 연동 검증 꺼짐 (CDS_UPM_VERIFY=${CDS_UPM_VERIFY})    console=True
    END
    # 6) PCF Noti 수신 서버 — 도구가 PCF 역할로 h2c Listen.
    #    소켓·DB 와 달리 **PG 가 붙어 오는 쪽**이라 여기서는 Listen 만 열어 둔다.
    IF    ${CDS_NOTI_VERIFY}
        Log    [Suite] PCF Noti 수신 서버 시작 → ${CDS_NOTI_HOST}:${CDS_NOTI_PORT} (h2c)    console=True
        ${srv}=    Noti.Noti Server Start    ${CDS_NOTI_PORT}    ${CDS_NOTI_HOST}
        Set Suite Variable    ${CDS_NOTI_SRV}    ${srv}
        Wait For PCF Noti Connection
    ELSE
        Log    [Suite] PCF Noti 검증 꺼짐 (CDS_NOTI_VERIFY=${CDS_NOTI_VERIFY})    console=True
    END
    Log    [Suite] CDS 접속 완료 (Rchannel→Schannel + PDB, UPM=${CDS_UPM_VERIFY}, Noti=${CDS_NOTI_VERIFY})    console=True

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
    # UPM 은 붙었을 때만 닫는다. Suite Setup 이 CDS 소켓 단계에서 실패했으면
    # ${UPM_SOCK} 이 ${NONE} 이라 Suite UPM Disconnect 가 그냥 지나간다.
    Run Keyword If    ${CDS_UPM_VERIFY}    Suite UPM Disconnect
    # Noti 서버는 데몬 스레드라 안 닫아도 프로세스와 함께 죽지만, 포트를 붙들고 있으면
    # 바로 이어 도는 다음 실행이 bind 에서 실패한다 → 반드시 닫는다.
    Run Keyword If    $CDS_NOTI_SRV is not None    Noti.Noti Server Stop    ${CDS_NOTI_SRV}
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

CDS DB Count Should Be At Least
    [Documentation]
    ...    COUNT 조회 결과가 ${minimum} 이상인지 검증. ${label} 은 실패 메시지에만 쓴다.
    ...    "있으면 성공" 판정용이다 — 몇 건인지는 업무·환경에 따라 달라 못 박지 않는다.
    [Arguments]    ${label}    ${minimum}    ${sql}    @{params}
    ${count}=    CDS DB Count    ${sql}    @{params}
    Should Be True    ${count} >= ${minimum}
    ...    msg=${label} 행 수 기대=${minimum}건 이상, 실제=${count}

Settle Before PDB Query
    [Documentation]
    ...    ResultAck(0018) 를 보낸 뒤 **첫 PDB 조회까지 쉬는 시간**.
    ...    모든 `Verify ... In PDB` 키워드가 재조회 루프에 들어가기 전에 한 번 부른다.
    ...
    ...    PG.SDM 이 T_CDS_ORDER_HIST 를 폴링해 반영하므로 ResultAck 직후에는 아직
    ...    아무것도 안 들어와 있다. 그 상태로 조회하면 "없음"을 보고 재시도 루프만 돌게
    ...    되는데, 실패한 조회도 로그를 남기고 트랜잭션을 여닫아 진단이 지저분해진다.
    ...
    ...    ${CDS_DB_WAIT} 와 **별개로 센다** — 최대 대기는 settle + ${CDS_DB_WAIT} 다.
    ...    0 이나 0s 를 주면 쉬지 않고 바로 조회한다.
    [Arguments]    ${settle}=${CDS_DB_SETTLE}
    IF    not ${{ str($settle).strip() in ('', '0', '0s', 'None') }}
        Log    [PDB] ResultAck 수신 → ${settle} 대기 후 조회    console=True
        Sleep    ${settle}
    END

CDS DB Group Counts
    [Documentation]
    ...    `SELECT <키>, COUNT(*) ... GROUP BY <키>` → `{키: 개수}` 딕셔너리 반환.
    ...    행이 없으면 빈 딕셔너리다(실패가 아니다).
    [Arguments]    ${sql}    @{params}
    Ensure CDS DB Connection
    ${counts}=    CdsDb.Db Group Counts    ${CDS_DB_CONN}    ${sql}    @{params}
    Log    [PDB] ${sql} / params=@{params} → ${counts}
    RETURN    ${counts}

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
    ...            ${settle}=${CDS_DB_SETTLE}
    Ensure CDS DB Connection
    Settle Before PDB Query    ${settle}
    Wait Until Keyword Succeeds    ${CDS_DB_WAIT}    ${CDS_DB_WAIT_INTERVAL}
    ...    Subscriber Rows Should Be Provisioned    ${mdn}    ${svc_1}    ${svc_2}

Subscriber Rows Should Be Absent
    [Documentation]
    ...    가입자 프로파일·서비스 행이 **하나도 없는지** 한 번 조회한다.
    ...    재시도는 `Verify Subscriber Removed From PDB` 가 한다.
    ...
    ...    서비스는 SVC_ID 를 가리지 않고 본다(${CDS_DB_SQL_SERVICE_ANY}) — 해지라면
    ...    DATA_USAGE_LEVEL 두 건뿐 아니라 **어떤 서비스도 남아 있으면 안 되기** 때문이다.
    [Arguments]    ${mdn}
    CDS DB Count Should Be    ${CDS_DB_TBL_PROFILE} (MDN=${mdn}, 해지 후 잔존)
    ...    ${0}    ${CDS_DB_SQL_PROFILE}    ${mdn}
    CDS DB Count Should Be    ${CDS_DB_TBL_SERVICE} (MDN=${mdn}, 해지 후 잔존)
    ...    ${0}    ${CDS_DB_SQL_SERVICE_ANY}    ${mdn}

Verify Subscriber Removed From PDB
    [Documentation]
    ...    해지 전문이 PDB 에 반영됐는지 판정한다. **두 조회가 모두 0이어야 성공**이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_PROFILE WHERE MDN=?
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE WHERE MDN=?
    ...    행이 남아 있으면 실패다 — `Verify Subscriber Provisioned In PDB` 의 반대다.
    ...
    ...    반영이 비동기인 것도 같다 → ${CDS_DB_WAIT} 동안 ${CDS_DB_WAIT_INTERVAL} 간격으로
    ...    재조회한다. 그 시간 안에 행이 다 사라지지 않으면 실패한다.
    ...
    ...    ※ **가입한 적이 없어도 통과한다** — 0건은 "지워졌다"와 "원래 없었다"를
    ...      구분하지 못한다. 해지 TC 는 앞선 가입 TC 가 실제로 넣은 뒤에 도는 것을
    ...      전제로 한다(슈트 순서상 TC-CDS-002 가 넣는다).
    [Arguments]    ${mdn}=${CDS_MDN}    ${settle}=${CDS_DB_SETTLE}
    Ensure CDS DB Connection
    Settle Before PDB Query    ${settle}
    Wait Until Keyword Succeeds    ${CDS_DB_WAIT}    ${CDS_DB_WAIT_INTERVAL}
    ...    Subscriber Rows Should Be Absent    ${mdn}


# ── 업무 코드별 PDB 판정 (1X / 1Y / I2 / I3 / C1 / G1 / D3) ────────
#
# 위 A1/Z1 과 같은 이유로 CommandResult(SC)만으로는 판정할 수 없다.
# 판정 기준은 2026-08-07 에 지정된 것이며 두 갈래다.
#
#   [있다/없다]  1X·I2 는 조건을 만족하는 행이 **1건 이상**이면 성공,
#                쌍이 되는 1Y·I3 는 해당 SVC_ID 행이 **0건**이면 성공.
#   [전후 동일]  C1·G1·D3 는 업무 수행 **전** SVC_ID 별 행 수와, 수행 **후**
#                그 업무 코드로 적재된 행의 SVC_ID 별 행 수가 같으면 성공.
#
# 전후 비교형은 TC 가 `Command Download Flow` **앞에서** Capture 키워드를 먼저
# 불러야 한다 — 순서가 바뀌면 이미 바뀐 상태를 기준으로 삼게 된다.
#
# 모든 `Verify ... In PDB` 는 재조회 루프에 들어가기 전에 `Settle Before PDB Query`
# 로 ${CDS_DB_SETTLE} 만큼 쉰다(ResultAck 직후에는 아직 반영 전이다).
# 특정 코드만 더 기다려야 하면 TC 에서 `settle=10s` 처럼 덮어쓴다.

# ── 1X → UPM Subs-Info (0x07/0x08) ──────────────────────────────
#
# 1X(HFC 가입)는 CDS 쪽에서 끝나지 않는다. PG.BSUBS 가 이어서 **UPM 으로
# Subs-Info-Request(0x07)** 를 밀고, UPM 이 Cell 정보를 담아 0x08 로 답해야
# 흐름이 완결된다. UPM 슈트의 TC-UPM-301 이 바로 이 구간인데, 거기서는 트리거할
# 방법이 없어(1X 를 보내는 쪽이 CDS 다) 주석 처리돼 있다.
# → 그래서 이 검증은 **1X 를 보내는 TC-CDS-003 에 붙는 것이 맞다.**
#
# ★ 순서: PG 는 CDS CommandResult(0017)와 UPM 0x07 을 각각 다른 소켓으로 보낸다.
#   둘의 도착 순서는 보장되지 않지만, 먼저 온 0x07 은 소켓 버퍼에 남아 있으므로
#   `Command Download Flow` 를 끝낸 뒤 읽어도 문제없다.

Verify UPM Subs Info Notified
    [Documentation]
    ...    1X 송신 뒤 PG.BSUBS → UPM Subs-Info-Request(0x07) 를 받아 검증하고
    ...    Subs-Info-Response(0x08, result-code=${UPM_RC_SUCCESS}) 로 답한다.
    ...    (UPM 슈트 TC-UPM-301 과 같은 내용 — 트리거가 있는 이쪽으로 옮겨 온 것이다)
    ...
    ...    검증 항목: mdn / branch-name / event-timestamp 형식 + tid·service-id 존재.
    ...    ${mdn} 을 주면 요청의 mdn 이 그 번호인지까지 본다(1X 를 보낸 가입자와 일치).
    ...
    ...    ${CDS_UPM_VERIFY}=${FALSE} 면 아무것도 하지 않고 넘어간다 — 그때는 UPM 에
    ...    접속조차 하지 않았으므로 읽을 소켓이 없다.
    ...
    ...    ★ 응답까지 보내는 것이 중요하다. 0x08 을 돌려주지 않으면 PG 가 UPM 응답을
    ...      기다리다 타임아웃/재시도로 넘어가 **뒤따르는 TC 의 PDB 판정이 흔들린다.**
    [Arguments]    ${mdn}=${NONE}
    IF    not ${CDS_UPM_VERIFY}
        Log    [UPM] 연동 검증 꺼짐 — 0x07 수신을 건너뜁니다    console=True
        RETURN
    END
    ${ok}=    Tcp.Is Connected    ${UPM_SOCK}
    Should Be True    ${ok}
    ...    msg=UPM 소켓이 닫혀 있습니다 — 1X 의 Subs-Info(0x07)를 받을 수 없습니다
    ${hdr}    ${body}=    Receive Subs Info Request
    UPM MDN Should Be Valid              ${body}
    UPM Branch Name Should Be Valid      ${body}
    UPM Event Timestamp Should Be Valid  ${body}
    Dictionary Should Contain Key    ${body}    tid
    Dictionary Should Contain Key    ${body}    service-id
    IF    $mdn is not None
        Should Be Equal As Strings    ${body}[mdn]    ${mdn}
        ...    msg=Subs-Info(0x07)의 mdn 이 1X 를 보낸 가입자와 다릅니다 (기대=${mdn}, 실제=${body}[mdn])
    END
    ${cell}=     Build Cell Item    ${UPM_TEST_CELL_INFO}    ${UPM_TEST_TA_CODE}
    ${cells}=    Create List    ${cell}
    Send Subs Info Response    ${hdr}[txn_id]    ${body}
    ...    cell_list=${cells}    result_code=${UPM_RC_SUCCESS}
    Log    [UPM] Subs-Info 0x07 수신 → 0x08 응답 완료 (mdn=${body}[mdn])    console=True


# ── PCF Noti 수신 (도구가 PCF 역할, HTTP/2 h2c) ──────────────────
#
# SA(5G) 가입자는 PG 가 PCF 로 SBI Noti 를 보낸다. 도구가 그 포트를 Listen 해
# **알림이 실제로 나갔는지**를 본다 — 전문(SC)·PDB 로는 안 보이는 구간이다.
#
# 1X 흐름의 PCF 방향 화살표는 규격상 둘인데 **실제로 나가는 건 하나뿐이다.**
#   SNOTI → PCF : 가입자 정보 변경 통보 → 1X/1Y 는 나가지 않는다
#   BSUBS → PCF : Cell List 전송      (UPM 0x08 응답을 받은 뒤)
#
# ★ PG.SDM 은 1X/1Y 에 대해 SNOTI 로 RBUS NOTI 를 보내지 않는다. SNOTI 가 깨지 않으니
#   가입자 Noti 도 없다(docs/callflow/CDS_X1.md). 그 알림을 기다리게 만들면 전문이
#   멀쩡해도 TC 가 실패한다 — TC-CDS-003 이 Cell List 한 건만 보는 이유다.
#
# Cell List 는 CommandResult(0017) 보다 **늦게** 오므로 대기가 필요하다(${CDS_NOTI_WAIT}).
#
# ★ 경로(:path)로 종류를 가르는데 ${CDS_NOTI_PATH_*} 기본값이 비어 있다 — 실 PG 의
#   경로가 확인되지 않아서다. 비어 있으면 **경로를 가리지 않고** "무엇이든 왔는가"만
#   본다. 경로가 확인되면 변수만 채우면 그때부터 종류별로 구분된다.
#
# ★ LTE 가입자는 SBI 가 아니라 RBUS 라 아무것도 안 들어온다 — 이 판정은 SA 전제다.

Wait For PCF Noti Connection
    [Documentation]
    ...    PG 가 h2c 로 **붙을 때까지** 기다린다. Suite Setup 이 부르며,
    ...    이게 성립해야 TC 를 시작한다.
    ...
    ...    왜 기다리는가 — 접속 전에 CDS 전문을 보내면 PG 는 알림을 보낼 상대가
    ...    없어 그냥 흘려보낸다. 그러면 TC-CDS-003 이 "Noti 안 옴"으로 실패하는데,
    ...    원인은 전문이 아니라 **시작 타이밍**이다. 로그만으로는 구분이 안 되므로
    ...    아예 시작 조건으로 못 박는다.
    ...
    ...    ${CDS_NOTI_ACCEPT_TIMEOUT} 안에 안 붙으면 실패한다 — 그때는 PG 가 이
    ...    주소로 보내도록 설정됐는지, 포트(${CDS_NOTI_PORT})가 맞는지부터 볼 것.
    ...    HTTP/1.1 로 붙어 온 경우도 접속으로 치지 않으므로 오류 목록에 남는다.
    ...
    ...    끄는 손잡이가 둘이고 층이 다르다.
    ...      ${CDS_NOTI_VERIFY}=${FALSE}       Listen 자체를 안 한다 → 여기도 무의미
    ...      ${CDS_NOTI_WAIT_CONNECT}=${FALSE} Listen 은 하되 **기다리지 않는다**
    ...    후자는 PG 가 이미 상시 접속돼 있거나 접속 시점을 못 맞추는 환경용이다.
    ...    끄면 PG 가 늦게 붙었을 때 TC-CDS-003 의 Noti 판정이 샌다.
    [Arguments]    ${timeout}=${CDS_NOTI_ACCEPT_TIMEOUT}
    IF    not ${CDS_NOTI_VERIFY}
        RETURN
    END
    IF    not ${CDS_NOTI_WAIT_CONNECT}
        Log    [Suite] h2c 접속 대기 꺼짐 (CDS_NOTI_WAIT_CONNECT=${CDS_NOTI_WAIT_CONNECT}) — Listen 만 하고 시작합니다    console=True
        RETURN
    END
    Log    [Suite] PG 의 h2c 접속 대기 (최대 ${timeout}) — 포트 ${CDS_NOTI_PORT}    console=True
    ${conns}=    Noti.Noti Wait Connection    ${CDS_NOTI_SRV}    timeout=${timeout}
    ${n}=        Get Length    ${conns}
    ${errs}=     Noti.Noti Errors    ${CDS_NOTI_SRV}
    Should Be True    ${n} > 0
    ...    msg=PG 가 ${timeout} 안에 h2c 로 접속하지 않았습니다 (포트 ${CDS_NOTI_PORT}). PG 가 이 주소로 보내도록 설정됐는지, 포트가 맞는지 확인하세요. 서버 오류=${errs}
    Log    [Suite] h2c 접속 확인 ${n}건 — ${conns}[0][peer]    console=True

Clear PCF Noti
    [Documentation]
    ...    쌓인 수신 알림을 비운다. **전문을 보내기 직전에** 부를 것 —
    ...    안 비우면 앞 TC 가 유발한 알림을 자기 결과로 착각한다.
    IF    not ${CDS_NOTI_VERIFY}
        RETURN
    END
    Noti.Noti Clear    ${CDS_NOTI_SRV}

Verify PCF Noti Received
    [Documentation]
    ...    PCF Noti 가 ${CDS_NOTI_WAIT} 안에 **1건 이상** 도착했는지 본다.
    ...
    ...    ${path}      : :path 에 포함돼야 할 문자열. 비면 경로를 가리지 않는다.
    ...    ${body}      : 본문에 포함돼야 할 문자열(예: MDN). 비면 내용을 가리지 않는다.
    ...    ${label}     : 실패 메시지에 쓸 이름 (예: "Cell List").
    ...    반환: 조건에 맞는 요청 목록(dict) — ${req}[json] / [path] / [headers] 로 꺼낸다.
    ...
    ...    ${CDS_NOTI_VERIFY}=${FALSE} 면 아무것도 하지 않고 빈 목록을 준다.
    ...
    ...    ★ 못 받으면 서버가 남긴 오류도 함께 띄운다. 가장 흔한 원인은 PG 가
    ...      HTTP/1.1 로 붙는 경우인데(h2c prior-knowledge 만 지원), 그러면
    ...      "h2c prior-knowledge 가 아닌 접속" 이 오류 목록에 찍힌다.
    ...    ★ ${since} 를 주면 **그 시각 이후 도착분만** 본다. 경로 필터가 비어 있을 때
    ...      앞서 온 다른 알림을 다시 집어 "통과"해 버리는 것을 막는 유일한 수단이다
    ...      (`Noti Timestamp` 로 기준 시각을 뜬다).
    [Arguments]    ${label}=PCF Noti    ${path}=${EMPTY}    ${body}=${EMPTY}
    ...            ${since}=${NONE}    ${wait}=${CDS_NOTI_WAIT}
    IF    not ${CDS_NOTI_VERIFY}
        Log    [Noti] 수신 검증 꺼짐 — ${label} 확인을 건너뜁니다    console=True
        ${empty}=    Create List
        RETURN    ${empty}
    END
    ${alive}=    Noti.Noti Server Is Running    ${CDS_NOTI_SRV}
    Should Be True    ${alive}
    ...    msg=PCF Noti 수신 서버가 떠 있지 않습니다 (포트 ${CDS_NOTI_PORT})
    ${found}=    Noti.Noti Wait    ${CDS_NOTI_SRV}    timeout=${wait}
    ...          path_contains=${path}    body_contains=${body}    since=${since}
    ${n}=      Get Length    ${found}
    ${errs}=   Noti.Noti Errors    ${CDS_NOTI_SRV}
    ${all}=    Noti.Noti Count    ${CDS_NOTI_SRV}
    Should Be True    ${n} > 0
    ...    msg=${label} 알림이 ${wait} 안에 오지 않았습니다 (조건: path~'${path}', body~'${body}', since=${since} / 전체 수신 ${all}건 / 서버 오류 ${errs})
    Log    [Noti] ${label} ${n}건 수신 — ${found}[0][method] ${found}[0][path]    console=True
    RETURN    ${found}

Noti Timestamp
    [Documentation]
    ...    현재 시각(epoch)을 뜬다. `Verify PCF Noti Received` 의 since= 기준점이다.
    ...    "이 동작 **뒤에** 온 알림"만 보고 싶을 때 그 동작 앞에서 부른다.
    ${ts}=    Noti.Noti Now
    RETURN    ${ts}


Zone Service Should Be Subscribed
    [Documentation]    1X 판정 1회 조회. 재시도는 Verify ... 키워드가 한다.
    [Arguments]    ${mdn}
    CDS DB Count Should Be At Least
    ...    ${CDS_DB_TBL_SERVICE} (MDN=${mdn}, SVC_ID=${CDS_DB_SVC_ZONE_D}, SVC_TYPE=${CDS_DB_SVC_TYPE_D}, JOB_CODE=${CDS_CODE_1X})
    ...    ${1}    ${CDS_DB_SQL_SERVICE_1X}
    ...    ${mdn}    ${CDS_DB_SVC_ZONE_D}    ${CDS_DB_SVC_TYPE_D}    ${CDS_CODE_1X}

Verify Zone Service Subscribed In PDB
    [Documentation]
    ...    1X(HFC 서비스 가입) 판정. **1건 이상이면 성공**이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...       WHERE MDN=? AND SVC_ID='ZONE_SVC_D' AND SVC_TYPE='D' AND JOB_CODE='1X'
    ...    건수를 못 박지 않는 것은 의도다 — 존 서비스가 여러 건일 수 있다.
    [Arguments]    ${mdn}=${CDS_MDN}    ${settle}=${CDS_DB_SETTLE}
    Ensure CDS DB Connection
    Settle Before PDB Query    ${settle}
    Wait Until Keyword Succeeds    ${CDS_DB_WAIT}    ${CDS_DB_WAIT_INTERVAL}
    ...    Zone Service Should Be Subscribed    ${mdn}

Zone Service Should Be Released
    [Documentation]    1Y 판정 1회 조회. 재시도는 Verify ... 키워드가 한다.
    [Arguments]    ${mdn}
    CDS DB Count Should Be
    ...    ${CDS_DB_TBL_SERVICE} (MDN=${mdn}, SVC_ID=${CDS_DB_SVC_ZONE_D}, 해지 후 잔존)
    ...    ${0}    ${CDS_DB_SQL_SERVICE}    ${mdn}    ${CDS_DB_SVC_ZONE_D}

Verify Zone Service Released In PDB
    [Documentation]
    ...    1Y(HFC 서비스 해지) 판정. **0건이어야 성공**이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE WHERE MDN=? AND SVC_ID='ZONE_SVC_D'
    ...    SVC_TYPE·JOB_CODE 를 걸지 않는다 — 어떤 형태로든 남아 있으면 해지가 덜 된 것이다.
    [Arguments]    ${mdn}=${CDS_MDN}    ${settle}=${CDS_DB_SETTLE}
    Ensure CDS DB Connection
    Settle Before PDB Query    ${settle}
    Wait Until Keyword Succeeds    ${CDS_DB_WAIT}    ${CDS_DB_WAIT_INTERVAL}
    ...    Zone Service Should Be Released    ${mdn}

Addon Service Should Be Subscribed
    [Documentation]    I2 판정 1회 조회. 재시도는 Verify ... 키워드가 한다.
    [Arguments]    ${mdn}
    CDS DB Count Should Be At Least
    ...    ${CDS_DB_TBL_SERVICE} (MDN=${mdn}, SVC_ID=${CDS_DB_SVC_YOUNG_HARM}, SVC_TYPE=${CDS_DB_SVC_TYPE_N}, JOB_CODE=${CDS_CODE_I2}, TIME_PERIOD_ID=${CDS_DB_TIME_PERIOD_ID}, LIMIT=${CDS_DB_LIMIT_FLAG})
    ...    ${1}    ${CDS_DB_SQL_SERVICE_I2}
    ...    ${mdn}    ${CDS_DB_SVC_YOUNG_HARM}    ${CDS_DB_SVC_TYPE_N}    ${CDS_CODE_I2}
    ...    ${CDS_DB_TIME_PERIOD_ID}    ${CDS_DB_LIMIT_FLAG}

Verify Addon Service Subscribed In PDB
    [Documentation]
    ...    I2(부가서비스신청) 판정. **1건 이상이면 성공**이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...       WHERE MDN=? AND SVC_TYPE='N' AND JOB_CODE='I2' AND TIME_PERIOD_ID='56'
    ...             AND "LIMIT"='Y' AND SVC_ID='YOUNG_HARM_INFO_BLOCK'
    ...    ※ LIMIT 은 예약어라 큰따옴표로 감쌌다 — cds_variables.robot 의 해당 SQL 주석 참조.
    [Arguments]    ${mdn}=${CDS_MDN}    ${settle}=${CDS_DB_SETTLE}
    Ensure CDS DB Connection
    Settle Before PDB Query    ${settle}
    Wait Until Keyword Succeeds    ${CDS_DB_WAIT}    ${CDS_DB_WAIT_INTERVAL}
    ...    Addon Service Should Be Subscribed    ${mdn}

Addon Service Should Be Released
    [Documentation]    I3 판정 1회 조회. 재시도는 Verify ... 키워드가 한다.
    [Arguments]    ${mdn}
    CDS DB Count Should Be
    ...    ${CDS_DB_TBL_SERVICE} (MDN=${mdn}, SVC_ID=${CDS_DB_SVC_YOUNG_HARM}, 해지 후 잔존)
    ...    ${0}    ${CDS_DB_SQL_SERVICE}    ${mdn}    ${CDS_DB_SVC_YOUNG_HARM}

Verify Addon Service Released In PDB
    [Documentation]
    ...    I3(부가서비스해지) 판정. **0건이어야 성공**이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE WHERE MDN=? AND SVC_ID='YOUNG_HARM_INFO_BLOCK'
    [Arguments]    ${mdn}=${CDS_MDN}    ${settle}=${CDS_DB_SETTLE}
    Ensure CDS DB Connection
    Settle Before PDB Query    ${settle}
    Wait Until Keyword Succeeds    ${CDS_DB_WAIT}    ${CDS_DB_WAIT_INTERVAL}
    ...    Addon Service Should Be Released    ${mdn}

Capture Service Counts Per SVC_ID
    [Documentation]
    ...    현재 MDN 의 SVC_ID 별 서비스 행 수를 딕셔너리로 떠 둔다.
    ...    C1/G1/D3 판정의 **기준선**이며 `Command Download Flow` **앞에서** 불러야 한다.
    ...      SELECT SVC_ID, COUNT(*) FROM T_5G_SUBS_SERVICE WHERE MDN=? GROUP BY SVC_ID
    [Arguments]    ${mdn}=${CDS_MDN}
    ${counts}=    CDS DB Group Counts    ${CDS_DB_SQL_SERVICE_GROUP}    ${mdn}
    Log    [PDB] 수행 전 SVC_ID 별 행 수 (MDN=${mdn}): ${counts}    console=True
    RETURN    ${counts}

Service Counts Should Match Baseline
    [Documentation]    전후 비교 1회 조회. 재시도는 Verify ... 키워드가 한다.
    [Arguments]    ${mdn}    ${job_code}    ${before}
    ${after}=    CDS DB Group Counts    ${CDS_DB_SQL_SERVICE_GROUP_JOB}    ${mdn}    ${job_code}
    Dictionaries Should Be Equal    ${after}    ${before}
    ...    msg=${job_code} 수행 후 SVC_ID 별 행 수가 수행 전과 다릅니다 (MDN=${mdn}) — 수행전=${before}, 수행후(JOB_CODE=${job_code})=${after}

Verify Service Counts Preserved In PDB
    [Documentation]
    ...    C1/G1/D3 판정. **수행 전 SVC_ID 별 행 수 == 수행 후 같은 집계**면 성공이다.
    ...      수행 전: SELECT SVC_ID, COUNT(*) ... WHERE MDN=?                GROUP BY SVC_ID
    ...      수행 후: SELECT SVC_ID, COUNT(*) ... WHERE MDN=? AND JOB_CODE=? GROUP BY SVC_ID
    ...    "기존 서비스가 하나도 빠짐없이 이번 업무 코드로 다시 쓰였는가" 를 본다.
    ...
    ...    ${before} 는 `Capture Service Counts Per SVC_ID` 가 미리 떠 둔 값이다.
    ...    ${mdn} 은 **수행 후** 가입자 번호다 — D3(번호변경)는 수행 전후가 다르므로
    ...    Capture 에는 옛 번호를, 여기에는 새 번호를 넘겨야 한다.
    ...
    ...    ※ 수행 전이 0건이면(서비스가 원래 없으면) 수행 후도 0건이라 그냥 통과한다 —
    ...      이 판정은 "지켜졌는가"만 보고 "있었는가"는 보지 않는다.
    [Arguments]    ${mdn}    ${job_code}    ${before}    ${settle}=${CDS_DB_SETTLE}
    Ensure CDS DB Connection
    Settle Before PDB Query    ${settle}
    Wait Until Keyword Succeeds    ${CDS_DB_WAIT}    ${CDS_DB_WAIT_INTERVAL}
    ...    Service Counts Should Match Baseline    ${mdn}    ${job_code}    ${before}




# ── 쿠폰/옵션 계열 PDB 판정 (Y9 / K1~K6 / SS / ST) ────────────────
#
# 판정 기준은 2026-08-10 지정표를 그대로 옮긴 것이다. 앞의 코드들과 마찬가지로
# **주 판정 대상은 가입자 서비스 테이블**(${CDS_DB_TBL_SERVICE})이고, 가입 계열
# 3개(K1/K5/Y9)만 예약 큐 적재를 **추가로** 본다 — 가입과 동시에 만료·사용시점
# 예약이 걸리기 때문이다.
#
#   [저장]  K1·K5·Y9·SS 는 지정된 컬럼 조합을 만족하는 행이 **1건 이상**이면 성공.
#   [삭제]  K2·K3·K4·K6 은 `MDN + R17 + CNUM(핀)` 행이 **0건**,
#           ST 는 `MDN + TIME_SVC_I` 행이 **0건**이면 성공.
#
# ★ K2/K3/K4/K6 은 판정 기준이 **글자 그대로 같다**(해지·만료·취소가 구분되지 않는다).
#   그래서 각 TC 는 자기 전용 핀으로 가입을 먼저 만든 뒤 그게 지워지는 것을 봐야 한다 —
#   0건은 "지워졌다"와 "원래 없었다"를 구분하지 못하기 때문이다.
#
# ★ 시간 컬럼은 전부 전문의 START_TIME 에서 나오는데 **폭이 다르다** — 전문은 12자리
#   (YYYYMMDDHH24MI)인데 **컬럼마다 폭이 다르다.**
#     K1/K5/Y9 : LIMIT_VALID_TIME = START_TIME+'00'   14자리  (${CDS_LIMIT_VALID_TIME})
#     SS       : TIME_PERIOD_ID   = 'SS_' + START_TIME 접두+12 (${CDS_DB_TPID_SS})
#   ★ 기준표가 둘 다 $LIMIT_VALID_TIME 으로 적어 놔서 같은 값으로 읽기 쉬운데 아니다.
#     SS 만 초 '00' 이 붙지 않는다. 형식이 또 어긋나면 저 두 변수만 고치면 된다.

Current CDS Start Time
    [Documentation]
    ...    현재 시각(±${offset_min}분)을 전문 START_TIME 형식으로 만든다.
    ...    ${CDS_START_TIME}(먼 미래 고정값) 대신 **지금 근처**를 보내야 하는 TC 가 쓴다.
    ...
    ...    ${offset_min} : 현재 시각에 더할 **분**. 음수면 과거다. 기본 0 = 지금.
    ...
    ...    반환 2개 — 폭이 다르니 섞어 쓰지 말 것.
    ...      1) start_time       12자리 YYYYMMDDHH24MI    → **전문 필드에 넣는 값**
    ...      2) limit_valid_time 14자리 (+ 초 '00')       → **PDB 판정에 쓰는 값**
    ...                                                     (LIMIT_VALID_TIME 은 CHAR(14))
    ...
    ...    예)
    ...    | ${st}    ${lvt}=    Current CDS Start Time              | # 지금
    ...    | ${st}    ${lvt}=    Current CDS Start Time    ${5}      | # 5분 뒤
    ...    | ${st}    ${lvt}=    Current CDS Start Time    ${-10}    | # 10분 전
    ...
    ...    분 단위인 것은 전문 형식이 분까지만 담기 때문이다(초 자리가 없다).
    ...    그래서 **0 과 1 사이에도 실질 차이가 있다** — 0 이면 이번 분이 이미
    ...    시작돼 있어 PG.RDS 가 곧 집어가고, 양수면 그만큼 여유가 생긴다.
    ...    만료(K3)처럼 "때가 된 예약"을 다루는 TC 는 0 이나 음수를, 예약이 아직
    ...    실행되면 안 되는 TC 는 양수를 준다.
    ...
    ...    ★ 초를 버리므로 같은 분 안에서는 같은 값이 나온다. 판정에 쓸 값은 전문을
    ...      보내기 **전에 한 번 받아 두고 그것을 계속 써야 한다** — 조회 시점에 다시
    ...      부르면 분이 넘어가는 순간 값이 어긋난다.
    [Arguments]    ${offset_min}=${0}
    ${start}=    Get Current Date
    ...    increment=${offset_min} minutes    result_format=%Y%m%d%H%M
    RETURN    ${start}    ${start}00

Coupon Service Should Be Subscribed
    [Documentation]    K1/K5 판정 1회 조회. 재시도는 Verify ... 키워드가 한다.
    [Arguments]    ${mdn}    ${job_code}    ${time_period_id}    ${limit}    ${coupon_pin}
    ...            ${limit_valid_time}=${CDS_LIMIT_VALID_TIME}
    CDS DB Count Should Be At Least
    ...    ${CDS_DB_TBL_SERVICE} (MDN=${mdn}, SVC_ID=${CDS_DB_SVC_COUPON}, SVC_TYPE=${CDS_DB_SVC_TYPE_N}, JOB_CODE=${job_code}, TIME_PERIOD_ID=${time_period_id}, LIMIT=${limit}, LIMIT_VALID_TIME=${limit_valid_time}, CNUM=${coupon_pin})
    ...    ${1}    ${CDS_DB_SQL_SERVICE_COUPON}
    ...    ${mdn}    ${CDS_DB_SVC_COUPON}    ${CDS_DB_SVC_TYPE_N}    ${job_code}
    ...    ${time_period_id}    ${limit}    ${limit_valid_time}    ${coupon_pin}

Verify Coupon Service Subscribed In PDB
    [Documentation]
    ...    쿠폰 가입(K1/K5) 판정. **1건 이상이면 성공**이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...       WHERE MDN=? AND SVC_ID='R17' AND SVC_TYPE='N' AND JOB_CODE=?
    ...             AND TIME_PERIOD_ID=? AND "LIMIT"=? AND LIMIT_VALID_TIME=? AND CNUM=?
    ...    CNUM 이 쿠폰 핀(COUPON_PIN)이 들어가는 컬럼이다.
    ...    K1 은 (113, 1), K5 는 (0, 2) 로 TIME_PERIOD_ID·LIMIT 이 다르다.
    ...
    ...    LIMIT_VALID_TIME 기대값은 전문 start_time 에 초 '00' 을 붙인 **14자리**다
    ...    (${CDS_LIMIT_VALID_TIME}). 전문은 12자리라 그대로 비교하면 안 맞는다.
    ...    형식이 또 어긋나면 이 판정만 실패하므로 그 변수부터 확인할 것.
    [Arguments]    ${mdn}    ${job_code}    ${time_period_id}    ${limit}    ${coupon_pin}
    ...            ${limit_valid_time}=${CDS_LIMIT_VALID_TIME}    ${settle}=${CDS_DB_SETTLE}
    Ensure CDS DB Connection
    Settle Before PDB Query    ${settle}
    Wait Until Keyword Succeeds    ${CDS_DB_WAIT}    ${CDS_DB_WAIT_INTERVAL}
    ...    Coupon Service Should Be Subscribed
    ...    ${mdn}    ${job_code}    ${time_period_id}    ${limit}    ${coupon_pin}
    ...    ${limit_valid_time}

Coupon Service Should Be Released
    [Documentation]    K2/K3/K4/K6 판정 1회 조회. 재시도는 Verify ... 키워드가 한다.
    [Arguments]    ${mdn}    ${coupon_pin}
    CDS DB Count Should Be
    ...    ${CDS_DB_TBL_SERVICE} (MDN=${mdn}, SVC_ID=${CDS_DB_SVC_COUPON}, CNUM=${coupon_pin}, 해지 후 잔존)
    ...    ${0}    ${CDS_DB_SQL_SERVICE_CNUM}
    ...    ${mdn}    ${CDS_DB_SVC_COUPON}    ${coupon_pin}

Verify Coupon Service Released In PDB
    [Documentation]
    ...    쿠폰 해지(K2/K6) · 만료(K3) · 취소(K4) 판정. **0건이어야 성공**이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE WHERE MDN=? AND SVC_ID='R17' AND CNUM=?
    ...
    ...    네 코드의 판정 기준이 **완전히 같다** — 해지·만료·취소를 서로 구분하지 못한다.
    ...    그래서 각 TC 는 자기 전용 핀으로 가입을 먼저 만들어야 판정이 의미를 갖는다.
    [Arguments]    ${mdn}    ${coupon_pin}    ${settle}=${CDS_DB_SETTLE}
    Ensure CDS DB Connection
    Settle Before PDB Query    ${settle}
    Wait Until Keyword Succeeds    ${CDS_DB_WAIT}    ${CDS_DB_WAIT_INTERVAL}
    ...    Coupon Service Should Be Released    ${mdn}    ${coupon_pin}

Zone Coupon Service Should Be Subscribed
    [Documentation]    Y9 판정 1회 조회. 재시도는 Verify ... 키워드가 한다.
    [Arguments]    ${mdn}    ${limit_valid_time}=${CDS_LIMIT_VALID_TIME}
    CDS DB Count Should Be At Least
    ...    ${CDS_DB_TBL_SERVICE} (MDN=${mdn}, SVC_ID=${CDS_DB_SVC_ZONE_B}, SVC_TYPE=${CDS_DB_SVC_TYPE_Z}, JOB_CODE=${CDS_CODE_Y9}, TIME_PERIOD_ID=${CDS_DB_TPID_Y9}, LIMIT=${CDS_DB_LIMIT_Y9}, LIMIT_VALID_TIME=${limit_valid_time})
    ...    ${1}    ${CDS_DB_SQL_SERVICE_ZONE_B}
    ...    ${mdn}    ${CDS_DB_SVC_ZONE_B}    ${CDS_DB_SVC_TYPE_Z}    ${CDS_CODE_Y9}
    ...    ${CDS_DB_TPID_Y9}    ${CDS_DB_LIMIT_Y9}    ${limit_valid_time}

Verify Zone Coupon Service Subscribed In PDB
    [Documentation]
    ...    Y9(Zone 부가서비스 쿠폰 사용시점 알림) 판정. **1건 이상이면 성공**이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...       WHERE MDN=? AND SVC_ID='ZONE_SVC_B' AND SVC_TYPE='Z' AND JOB_CODE='Y9'
    ...             AND TIME_PERIOD_ID='25' AND "LIMIT"='0' AND LIMIT_VALID_TIME=?
    ...    SVC_ID 가 1X 의 ZONE_SVC_D 가 아니라 **ZONE_SVC_B** 인 것에 주의.
    ...    JOB_CODE 는 인입 코드 그대로 Y9 다 — 예약 큐 쪽만 Y6 으로 바뀐다.
    ...    LIMIT_VALID_TIME 기대값은 K1/K5 와 같은 14자리 ${CDS_LIMIT_VALID_TIME} 이다.
    [Arguments]    ${mdn}=${CDS_MDN}    ${limit_valid_time}=${CDS_LIMIT_VALID_TIME}
    ...            ${settle}=${CDS_DB_SETTLE}
    Ensure CDS DB Connection
    Settle Before PDB Query    ${settle}
    Wait Until Keyword Succeeds    ${CDS_DB_WAIT}    ${CDS_DB_WAIT_INTERVAL}
    ...    Zone Coupon Service Should Be Subscribed    ${mdn}    ${limit_valid_time}

Option Service Should Be Subscribed
    [Documentation]    SS 판정 1회 조회. 재시도는 Verify ... 키워드가 한다.
    [Arguments]    ${mdn}    ${time_period_id}=${CDS_DB_TPID_SS}
    CDS DB Count Should Be At Least
    ...    ${CDS_DB_TBL_SERVICE} (MDN=${mdn}, SVC_ID=${CDS_DB_SVC_TIME_I}, SVC_TYPE=${CDS_DB_SVC_TYPE_T}, JOB_CODE=${CDS_CODE_SS}, TIME_PERIOD_ID=${time_period_id}, LIMIT=${CDS_DB_LIMIT_SS}, CNUM=${CDS_DB_CNUM_SS})
    ...    ${1}    ${CDS_DB_SQL_SERVICE_OPTION}
    ...    ${mdn}    ${CDS_DB_SVC_TIME_I}    ${CDS_DB_SVC_TYPE_T}    ${CDS_CODE_SS}
    ...    ${time_period_id}    ${CDS_DB_LIMIT_SS}    ${CDS_DB_CNUM_SS}

Verify Option Service Subscribed In PDB
    [Documentation]
    ...    SS(0플랜 옵션 3시간프리 가입) 판정. **1건 이상이면 성공**이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...       WHERE MDN=? AND SVC_ID='TIME_SVC_I' AND SVC_TYPE='T' AND JOB_CODE='SS'
    ...             AND TIME_PERIOD_ID=? AND "LIMIT"='0' AND CNUM='0'
    ...    CNUM 이 쿠폰 핀이 아니라 **0 고정**이다 — 쿠폰이 아니라 옵션이기 때문이다.
    ...
    ...    SS 는 시간을 **TIME_PERIOD_ID 로 본다** — 'SS_' 접두 + 전문 START_TIME(12자리)
    ...    이다. 예) SS_203712312359 (${CDS_DB_TPID_SS})
    ...
    ...    ★ K1/K5/Y9 의 LIMIT_VALID_TIME(14자리, 초 '00' 부가)과 **값이 다르다.**
    ...      기준표가 둘 다 $LIMIT_VALID_TIME 으로 적어 놔 같은 값으로 읽기 쉬운 자리다.
    ...      LIMIT_VALID_TIME 컬럼 자체는 이 테이블에 있지만 SS 판정 기준에는 없다.
    [Arguments]    ${mdn}=${CDS_MDN}    ${time_period_id}=${CDS_DB_TPID_SS}
    ...            ${settle}=${CDS_DB_SETTLE}
    Ensure CDS DB Connection
    Settle Before PDB Query    ${settle}
    Wait Until Keyword Succeeds    ${CDS_DB_WAIT}    ${CDS_DB_WAIT_INTERVAL}
    ...    Option Service Should Be Subscribed    ${mdn}    ${time_period_id}

Option Service Should Be Released
    [Documentation]    ST 판정 1회 조회. 재시도는 Verify ... 키워드가 한다.
    [Arguments]    ${mdn}
    CDS DB Count Should Be
    ...    ${CDS_DB_TBL_SERVICE} (MDN=${mdn}, SVC_ID=${CDS_DB_SVC_TIME_I}, 해지 후 잔존)
    ...    ${0}    ${CDS_DB_SQL_SERVICE}    ${mdn}    ${CDS_DB_SVC_TIME_I}

Verify Option Service Released In PDB
    [Documentation]
    ...    ST(0플랜 옵션 3시간프리 해지) 판정. **0건이어야 성공**이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE WHERE MDN=? AND SVC_ID='TIME_SVC_I'
    ...    CNUM 을 걸지 않는다 — 판정 기준이 MDN + SVC_ID 뿐이다.
    [Arguments]    ${mdn}=${CDS_MDN}    ${settle}=${CDS_DB_SETTLE}
    Ensure CDS DB Connection
    Settle Before PDB Query    ${settle}
    Wait Until Keyword Succeeds    ${CDS_DB_WAIT}    ${CDS_DB_WAIT_INTERVAL}
    ...    Option Service Should Be Released    ${mdn}

Reserved Job Should Be Created
    [Documentation]    K1/K5/Y9 의 예약 큐 적재 1회 조회. 재시도는 Verify ... 가 한다.
    [Arguments]    ${mdn}    ${rsv_job_code}    ${coupon_pin}
    CDS DB Count Should Be At Least
    ...    ${CDS_DB_TBL_RESERVED} (MDN=${mdn}, JOB_CODE=${rsv_job_code}, COUPON_PIN=${coupon_pin})
    ...    ${1}    ${CDS_DB_SQL_RESERVED_JOB}
    ...    ${mdn}    ${rsv_job_code}    ${coupon_pin}

Verify Reserved Job Created In PDB
    [Documentation]
    ...    가입(K1/K5/Y9)이 예약 큐에 만료·사용시점 예약을 걸었는지 판정한다.
    ...    **1건 이상이면 성공**이다.
    ...      SELECT COUNT(*) FROM T_5G_RESERVED_JOB WHERE MDN=? AND JOB_CODE=? AND COUPON_PIN=?
    ...
    ...    ${rsv_job_code} 는 **인입 업무 코드가 아니라 예약 큐에 적재되는 코드**다.
    ...    K1→${CDS_DB_RSV_JOB_K1} / K5→${CDS_DB_RSV_JOB_K5} / Y9→${CDS_DB_RSV_JOB_Y9}.
    ...    인입 코드로 조회하면 한 건도 나오지 않는다.
    ...
    ...    STATUS 를 걸지 않는 것은 의도다 — 판정 기준표가 예약 건을 "시간 확인 필요"로
    ...    남겨 둬 대기(N)/실행(R) 중 무엇을 기대할지 못 박을 근거가 없다.
    [Arguments]    ${mdn}    ${rsv_job_code}    ${coupon_pin}    ${settle}=${CDS_DB_SETTLE}
    Ensure CDS DB Connection
    Settle Before PDB Query    ${settle}
    Wait Until Keyword Succeeds    ${CDS_DB_WAIT}    ${CDS_DB_WAIT_INTERVAL}
    ...    Reserved Job Should Be Created    ${mdn}    ${rsv_job_code}    ${coupon_pin}
