*** Settings ***
Documentation
...    CMSWEB 시뮬레이터 키워드 — 도구가 CMSWEB(SKT 통합 구성관리 시스템) 서버 역할
...
...    [인터페이스]
...      제어 채널 : PG.CMS → 도구 ${CMS_LISTEN_PORT} (도구 Listen, 13B 헤더 + EUC-KR JSON)
...      파일 채널 : [CMS] CMSWEB_SFTP 로 고른다(PG 와 같이 'N' 이면 FTP, 그 밖은 SFTP)
...                  SFTP → 도구 SFTP ${CMS_SFTP_PORT}([CMS] CMS_SFTP_PORT) / FTP → 도구 FTP ${CMS_FTP_PORT}(PG 고정 21)
...      FIN       : SFTP → 도구 호스트 실제 sshd ${CMS_FIN_SSH_PORT} (PUT .FIN, ${CMS_FIN_MODE}=sshd)
...                  FTP  → GET 과 같은 FTP 세션으로 도구 FTP 에 PUT (기동 시 simulator 로 바뀐다)
...      SC 전달   : [CMS] NWDAF_SFTP 로 고른다 — SFTP ${CMS_SC_SFTP_PORT}(NWDAF_SFTP_PORT) /
...                  FTP ${CMS_SC_FTP_PORT}(NWDAF_FTP_PORT). SC_FTP_YN=Y — 받은 파일 + .FIN PUT,
...                  가상 경로 ${CMS_SC_PATH} → 실제 ${CMS_SC_UPLOAD_DIR}. SC 시험에서만 띄운다.
...      PDB       : PG 가 처리 결과를 T_CMSWEB_ZONE 에 넣는다
...
...    [Suite 정책]
...      Suite Setup    : Prepare CMSWEB — 설정 확정(PG_V2.cfg) → 전제 확인 → FIN 디렉터리 확인
...                       → 다운로드 서버·업로드(SC 수신) 서버 기동 → CMS201 .RUN touch → Listen
...                       → PG 접속·REG 수신 → REG_OK
...      TC 판정        : NTI → ANS 수신 뒤 다운로드 서버에서 가져갔는지, 업로드 서버로 올라왔는지 본다
...                       (PDB 는 첫 DB 판정 때 접속한다 — db 태그를 빼면 PDB 없이 돈다)
...      Test Setup     : Check CMS Session (닫혀 있으면 슈트 중단)
...      Suite Teardown : Close CMSWEB — 시험 행 정리(FIN·SC 파일은 기본으로 남김) → 연결·서버 종료
...
...    상세: tests/cms/SPEC.md
Library    Collections
Library    ${CURDIR}/../libraries/TcpHelper.py    WITH NAME    Tcp
Library    ${CURDIR}/../libraries/CmsHelper.py    WITH NAME    Cms
Library    ${CURDIR}/../libraries/PdbHelper.py    WITH NAME    CmsDb
Library    ${CURDIR}/../libraries/RuntimeConfig.py    WITH NAME    Runtime
Resource   ${CURDIR}/ssh_keywords.robot
Resource   ${CURDIR}/cms_variables.robot


*** Variables ***
${CMS_SRV_SOCK}       ${NONE}
${CMS_CONN}           ${NONE}
${CMS_REG_MSG}        ${NONE}
${CMS_SFTP_SERVER}    ${NONE}    # 파일 서버 핸들 — SFTP 든 FTP 든 같은 인터페이스(files/downloads/clear)
${CMS_FILE_PROTO}     SFTP       # Resolve CMS Settings 가 [CMS] CMSWEB_SFTP 로 정한다
${CMS_SC_FILE_PROTO}  SFTP       # Resolve CMS Settings 가 [CMS] NWDAF_SFTP 로 정한다
${CMS_DB_CONN}        ${NONE}
${CMS_DB_CONN_2}      ${NONE}
&{CMS_ZONES}         # 시작 전 T_ZONE_LIST 조회 결과(DB1) — 서비스코드 → Cms Zone Summary
@{CMS_FIN_PREFIXES}    # 이번 실행에서 보낸 NTI 의 FIN 접두사 — Suite Teardown 이 이것과 맞는 FIN 만 지운다
${CMS_SC_SERVER}      ${NONE}
${CMS_SC_REAL_DIR}    ${EMPTY}
${CMS_SC_MODE}        local      # local: 도구가 SC 수신 서버를 띄운다 / remote: [SC] SC_PRIIP 서버에 접속해 확인한다
${CMS_SC_PORT}        ${EMPTY}   # PG 가 SC 로 올리는 포트 (NWDAF_SFTP_PORT 또는 NWDAF_FTP_PORT)
@{CMS_SC_FILES}       # 이번 실행의 SC 시험이 기대한 파일 이름 — Suite Teardown 이 이것만 지운다


*** Keywords ***

# ══════════════════════════════════════════════════════════════════
# Suite 수명주기
# ══════════════════════════════════════════════════════════════════

Prepare CMSWEB
    [Documentation]
    ...    CMS 슈트 Suite Setup. 시험 환경이 준비되지 않으면 TC 를 **수행하지 않고 실패**로 끝낸다:
    ...    TC 에 필요한 설정값이 없음 / 파일 서버(SFTP·FTP)·업로드 서버 기동 실패 / PG.CMS 미접속 등.
    ...    이유는 콘솔에 ERROR 한 줄로 남기고, 각 TC 는 "Parent suite setup failed: CMS TC 미수행 — <이유>"
    ...    로 FAIL 된다(본문은 한 줄도 돌지 않는다). 종료 코드도 실패다.
    ${status}    ${error}=    Run Keyword And Ignore Error    Start CMSWEB Session
    IF    $status == 'FAIL'
        Log    [Suite] CMS TC 미수행 — ${error}    level=ERROR
        Fail    CMS TC 미수행 — ${error}
    END

Start CMSWEB Session
    [Documentation]    시험 환경 준비 — 설정 확정 → 전제 확인 → 서버 기동 → Listen → PG.CMS 접속·REG. 어느 단계든 실패하면 실패.
    Resolve CMS Settings
    Check CMS Settings Present
    Show CMS Zone List
    Check CMS Prerequisites
    Check CMS FIN Target
    Start CMS File Server
    Start CMS Upload Server
    Ensure PG Process Running    ${CMS_PROCESS}
    Log    [Suite] CMSWEB 제어 채널 Listen → ${CMS_LISTEN_HOST}:${CMS_LISTEN_PORT} (허용 IP: ${CMS_ALLOWED_PEER_IPS})    console=True
    ${srv}=    Tcp.Server Start    ${CMS_LISTEN_PORT}    ${CMS_LISTEN_HOST}
    Set Suite Variable    ${CMS_SRV_SOCK}    ${srv}
    Accept CMS Session

Resolve CMS Settings
    [Documentation]
    ...    CLI > 환경 파일 > PG_V2.cfg [CMS] > 기본값 순으로 확정한 값을 슈트 변수로 둔다.
    ...    그 값으로 파일 채널(CMSWEB_SFTP)과 SC 전달(NWDAF_SFTP)의 FTP/SFTP 를 PG 와 같은 규칙으로 정한다.
    ${values}=    Runtime.Resolve Settings    cms
    ...    CMS_LISTEN_PORT    CMS_SFTP_PORT    CMS_PG_TARGET_ADDR    CMS_PG_GROUP
    ...    CMS_PG_KEY    CMS_PG_TIMEOUT    CMS_PG_USE_SFTP
    ...    CMS_SC_SFTP_PORT    CMS_SC_FTP_PORT    CMS_SC_USE_SFTP    CMS_SC_PATH    CMS_SC_PG_ADDR
    FOR    ${name}    ${value}    IN    &{values}
        Set Suite Variable    \${${name}}    ${value}
    END
    ${proto}=    Cms.Cms File Protocol    ${CMS_PG_USE_SFTP}
    ${sc_proto}=    Cms.Cms File Protocol    ${CMS_SC_USE_SFTP}
    Set Suite Variable    ${CMS_FILE_PROTO}    ${proto}
    Set Suite Variable    ${CMS_SC_FILE_PROTO}    ${sc_proto}
    IF    $proto == 'FTP' and $CMS_FIN_MODE == 'sshd'
        Log    [Suite] CMSWEB_SFTP=${CMS_PG_USE_SFTP} → FTP 모드 — FIN 은 같은 FTP 세션으로 오므로 FIN 확인을 simulator 로 바꾼다    console=True
        Set Suite Variable    ${CMS_FIN_MODE}    simulator
    END
    ${file_port}=    Set Variable If    $proto == 'SFTP'    ${CMS_SFTP_PORT}    ${CMS_FTP_PORT}
    ${sc_port}=    Set Variable If    $sc_proto == 'SFTP'    ${CMS_SC_SFTP_PORT}    ${CMS_SC_FTP_PORT}
    Log    [Suite] 파일 채널 ${proto} (CMSWEB_SFTP=${CMS_PG_USE_SFTP}) 포트 ${file_port} / SC 전달 ${sc_proto} (NWDAF_SFTP=${CMS_SC_USE_SFTP}) 포트 ${sc_port}    console=True

Check CMS Settings Present
    [Documentation]    TC 수행에 필요한 설정값이 모두 있는지 본다 — 비어 있으면 그 이름을 모두 모아 실패한다.
    ${missing}=    Create List
    FOR    ${name}    IN    CMS_LISTEN_PORT    CMS_PG_GROUP    CMS_PG_KEY    CMS_PG_USE_SFTP    CMS_SC_USE_SFTP
    ...    CMS_SFTP_PORT    CMS_SC_SFTP_PORT    CMS_SC_FTP_PORT    CMS_SC_PATH    CMS_SFTP_USER    CMS_SC_SFTP_USER
    ...    CMS_REMOTE_DIR    CMS_PROCESS
        ${value}=    Get Variable Value    \${${name}}    ${EMPTY}
        IF    $value is None or str($value).strip() == ''
            Append To List    ${missing}    ${name}
        END
    END
    IF    $missing
        ${names}=    Evaluate    ', '.join($missing)
        Fail    TC 에 필요한 설정값이 없습니다 — ${names} (PG_V2.cfg [CMS]/[SC] 또는 환경 파일 config/env/<env>.py 확인)
    END

Check CMS Prerequisites
    [Documentation]
    ...    PG 설정이 이 도구를 가리키는지 확인한다. PG cfg 는 고치지 않는다 — 틀린 항목을 모두 모아
    ...    무엇을 바꿔야 하는지 알려 주고 슈트를 세운다.
    ${problems}=    Create List
    IF    $CMS_PG_TARGET_ADDR and $CMS_PG_TARGET_ADDR != $TOOL_HOST
        Append To List    ${problems}    CMSWEB_ADDR=${CMS_PG_TARGET_ADDR} → ${TOOL_HOST} 로 바꿔야 PG.CMS 가 이 도구에 붙습니다
    END
    IF    $CMS_FILE_PROTO == 'SFTP' and int($CMS_SFTP_PORT) < 1024
        Append To List    ${problems}    CMS_SFTP_PORT=${CMS_SFTP_PORT} → 도구 호스트의 실제 sshd/특권 포트입니다. 1024 이상(예: 2322)으로 바꾸십시오
    END
    IF    $CMS_FIN_MODE not in ('sshd', 'simulator')
        Fail    CMS_FIN_MODE=${CMS_FIN_MODE} → sshd(실제 PG, 기본) 또는 simulator 여야 합니다.
    END
    IF    $problems
        ${detail}=    Evaluate    ' / '.join($problems)
        Fail    PG_V2.cfg [CMS] 설정이 CMSWEB 시뮬레이터와 맞지 않습니다 — ${detail}. 바꾼 뒤 CMS201 을 재기동하십시오.
    END

Check CMS FIN Target
    [Documentation]
    ...    sshd 모드: PG 의 FIN 이 떨어질 도구 호스트 실제 디렉터리(${CMS_REMOTE_DIR})를 FIN 계정으로
    ...    미리 확인한다(로그인·존재·쓰기). FIN PUT 이 실패하면 CmsMain 이 종료되므로 시험 전에 막는다.
    ...    비밀번호는 환경변수 PG_PWD_CMS_FIN_SSH(도구 호스트 실제 pg 계정), 없으면 PG_PWD_CMS_SFTP.
    IF    $CMS_FIN_MODE != 'sshd'
        Log    [Suite] FIN 확인 모드 ${CMS_FIN_MODE} — FIN 을 시뮬레이터 파일 서버(${CMS_FILE_PROTO}) 업로드 이력에서 본다    console=True
        RETURN
    END
    ${target}=    Cms.Cms Fin Ssh Check    ${CMS_FIN_SSH_HOST}    ${CMS_FIN_SSH_PORT}    ${CMS_FIN_SSH_USER}    ${CMS_REMOTE_DIR}
    Log    [Suite] FIN 확인 모드 sshd — ${target}    console=True

Start CMS File Server
    [Documentation]
    ...    CMSWEB 다운로드 서버를 ${CMS_FILE_PROTO} 로 띄운다(SFTP: CMS_SFTP_PORT, FTP: CMS_FTP_PORT).
    ...    계정은 ${CMS_SFTP_USER}, 비밀번호는 환경변수 PG_PWD_CMS_SFTP(둘 다 같은 CMSWEB 계정).
    IF    $CMS_FILE_PROTO == 'SFTP'
        ${srv}=    Cms.Cms Sftp Start    ${CMS_SFTP_PORT}    ${CMS_SFTP_HOST}    ${CMS_SFTP_USER}    ${CMS_REMOTE_DIR}
        ${where}=    Set Variable    ${CMS_SFTP_HOST}:${CMS_SFTP_PORT}
    ELSE
        ${srv}=    Cms.Cms Ftp Start    ${CMS_FTP_PORT}    ${CMS_FTP_HOST}    ${CMS_SFTP_USER}    ${CMS_REMOTE_DIR}
        ...    ${CMS_FTP_PASSIVE_PORTS}
        ${where}=    Set Variable    ${CMS_FTP_HOST}:${CMS_FTP_PORT}
    END
    Set Suite Variable    ${CMS_SFTP_SERVER}    ${srv}
    Log    [Suite] CMSWEB ${CMS_FILE_PROTO} 기동 → ${where} (계정 ${CMS_SFTP_USER}, 디렉터리 ${CMS_REMOTE_DIR})    console=True

Start CMS Upload Server
    [Documentation]
    ...    PG 가 SC_FTP_YN=Y 서비스코드의 파일·FIN 을 올리는 SC 쪽을 Suite Setup 에서 준비한다.
    ...    - [SC] SC_PRIIP 가 비었거나 도구(${TOOL_HOST})면 local: 도구가 SC 수신 서버를 띄운다.
    ...    - 다른 IP 면 remote: 서버를 띄우지 않고 그 SC 서버에 PG 의 SC 계정으로 접속해 SC_PATH 를
    ...      읽을 수 있는지 확인한다. 판정 때도 그 서버의 SC_PATH 를 본다.
    ...    전제가 틀리면 틀린 항목을 모두 모아 슈트를 세운다.
    IF    $CMS_SC_SERVER is not None or $CMS_SC_MODE == 'remote'
        RETURN
    END
    IF    $CMS_SC_FILE_PROTO == 'SFTP'
        ${sc_port}=    Set Variable    ${CMS_SC_SFTP_PORT}
        ${sc_key}=    Set Variable    NWDAF_SFTP_PORT
    ELSE
        ${sc_port}=    Set Variable    ${CMS_SC_FTP_PORT}
        ${sc_key}=    Set Variable    NWDAF_FTP_PORT
    END
    Set Suite Variable    ${CMS_SC_PORT}    ${sc_port}
    IF    $CMS_SC_PG_ADDR and $CMS_SC_PG_ADDR != $TOOL_HOST
        Set Suite Variable    ${CMS_SC_MODE}    remote
        Set Suite Variable    ${CMS_SC_REAL_DIR}    ${CMS_SC_PG_ADDR}:${CMS_SC_PATH}
        Log    [Suite] [SC] SC_PRIIP=${CMS_SC_PG_ADDR} 는 도구가 아님 → SC 서버에 접속해 확인한다 (${CMS_SC_FILE_PROTO} ${sc_port}, ${CMS_SC_PATH})    console=True
        ${checked}=    Cms.Cms Sc Remote Check    ${CMS_SC_FILE_PROTO}    ${CMS_SC_PG_ADDR}    ${sc_port}
        ...    ${CMS_SC_SFTP_USER}    ${CMS_SC_PATH}
        Log    [Suite] SC 서버 확인 — ${checked}    console=True
        RETURN
    END
    ${problems}=    Create List
    ${file_port}=    Set Variable If    $CMS_FILE_PROTO == 'SFTP'    ${CMS_SFTP_PORT}    ${CMS_FTP_PORT}
    IF    $CMS_SC_FILE_PROTO == 'SFTP' and int($sc_port) < 1024
        Append To List    ${problems}    [CMS] ${sc_key}=${sc_port} → 도구 호스트의 실제 sshd/특권 포트입니다. 1024 이상으로 두십시오
    END
    IF    int($sc_port) == int($file_port)
        Append To List    ${problems}    [CMS] ${sc_key}=${sc_port} → CMSWEB 파일 서버(${CMS_FILE_PROTO} ${file_port})와 달라야 합니다
    END
    # FTP 모드의 PG 는 CMSWEB 다운로드를 항상 21 로 붙는다 — 도구가 21 을 리다이렉트해 다른 포트로
    # 받더라도, SC 가 21 이면 PG 의 SC 업로드가 같은 리다이렉트를 타고 CMSWEB 서버로 들어간다.
    IF    $CMS_FILE_PROTO == 'FTP' and int($sc_port) == 21 and int($file_port) != 21
        Append To List    ${problems}    [CMS] ${sc_key}=21 → PG 의 CMSWEB FTP 포트(21 고정)와 같아 SC 업로드가 CMSWEB FTP 서버(${file_port})로 갑니다. 다른 포트로 두십시오
    END
    IF    $problems
        ${detail}=    Evaluate    ' / '.join($problems)
        Fail    업로드(SC 수신) 서버 전제가 맞지 않습니다 — ${detail}. 바꾼 뒤 CMS201 을 재기동하십시오.
    END
    IF    $CMS_SC_FILE_PROTO == 'SFTP'
        ${srv}=    Cms.Cms Sc Sftp Start    ${sc_port}    ${CMS_SC_SFTP_HOST}    ${CMS_SC_SFTP_USER}
        ...    ${CMS_SC_PATH}    ${CMS_SC_UPLOAD_DIR}
    ELSE
        ${srv}=    Cms.Cms Sc Ftp Start    ${sc_port}    ${CMS_SC_SFTP_HOST}    ${CMS_SC_SFTP_USER}
        ...    ${CMS_SC_PATH}    ${CMS_SC_UPLOAD_DIR}    ${CMS_SC_FTP_PASSIVE_PORTS}
    END
    ${real_dir}=    Evaluate    $srv.mounts[0][1]
    Set Suite Variable    ${CMS_SC_SERVER}    ${srv}
    Set Suite Variable    ${CMS_SC_REAL_DIR}    ${real_dir}
    Set Suite Variable    ${CMS_SC_MODE}    local
    Log    [Suite] SC 수신 ${CMS_SC_FILE_PROTO} 기동 → ${CMS_SC_SFTP_HOST}:${sc_port} (계정 ${CMS_SC_SFTP_USER}, ${CMS_SC_PATH} → ${real_dir})    console=True

Accept CMS Session
    [Documentation]    PG.CMS 접속을 받아 첫 REG 를 확인하고 REG_OK 로 답한다. 받은 REG 는 ${CMS_REG_MSG} 에 둔다.
    Log    [Suite] PG.CMS → CMSWEB 접속 대기 중 (최대 ${CMS_ACCEPT_TIMEOUT}초)...    console=True
    ${conn}    ${addr}=    Tcp.Server Accept    ${CMS_SRV_SOCK}    ${CMS_ACCEPT_TIMEOUT}    ${CMS_ALLOWED_PEER_IPS}
    ...    label=PG.CMS → CMSWEB(${CMS_LISTEN_PORT})
    Set Suite Variable    ${CMS_CONN}    ${conn}
    ${reg}=    Cms.Cms Expect    ${CMS_CONN}    REG    ${CMS_RECV_TIMEOUT}
    Log    [Suite] PG.CMS 접속 수락: ${addr} — REG ${reg}[body]    console=True
    ${ok}=    Cms.Cms Reg Result    ${TRUE}
    Cms.Cms Send    ${CMS_CONN}    REG    ${ok}
    Set Suite Variable    ${CMS_REG_MSG}    ${reg}

Show CMS Zone List
    [Documentation]
    ...    시작 전 — SC 전달 서비스코드(${CMS_SERVICE_CODES_SC})와 정상 수집 코드(${CMS_SERVICE_CODE})의
    ...    T_ZONE_LIST 값(SC_FTP_YN·NOTI_YN·ZONE_CODE)을 조회해 보여 준다. 조회만 하고 INSERT/UPDATE 하지 않는다.
    ...    PG 와 같이 '_V..' 를 뗀 코드로 조회한다. 값이 어떻든 시작을 막지 않는다 — 판정은 TC 가 한다.
    ...    PDB 에 붙지 못하면 경고만 남기고 시작한다(값을 모르는 코드는 TC 가 그대로 시험한다).
    IF    not ${CMS_ZONE_SHOW}
        Log    [Suite] T_ZONE_LIST 조회 생략 (CMS_ZONE_SHOW=False)    console=True
        RETURN
    END
    ${status}    ${error}=    Run Keyword And Ignore Error    Ensure CMS DB Connection
    IF    $status == 'FAIL'
        Log    [Suite] T_ZONE_LIST 조회 불가 — PDB 접속 실패: ${error}    level=WARN    console=True
        RETURN
    END
    ${codes}=    Create List    @{CMS_SERVICE_CODES_SC}    ${CMS_SERVICE_CODE}
    ${dbs}=    Create List    DB1
    IF    $CMS_DB_CONN_2 is not None
        Append To List    ${dbs}    DB2
    END
    ${zones}=    Create Dictionary
    Log    [Suite] T_ZONE_LIST 조회 (시작 전, 변경 없음)    console=True
    FOR    ${db}    IN    @{dbs}
        ${conn}=    Set Variable If    $db == 'DB1'    ${CMS_DB_CONN}    ${CMS_DB_CONN_2}
        FOR    ${code}    IN    @{codes}
            ${key}=    Cms.Cms Zone Lookup Code    ${code}
            ${rows}=    CmsDb.Db Rows    ${conn}    ${CMS_DB_SQL_ZONE_LIST}    ${key}
            ${info}=    Cms.Cms Zone Summary    ${code}    ${rows}
            # 메시지 안에 공백 2칸 이상을 두지 말 것 — Robot 이 인자 구분으로 읽어 로그 레벨로 해석한다
            Log    [Suite] T_ZONE_LIST(${db}) ${info}[text]    console=True
            IF    $code in $CMS_SERVICE_CODES_SC and $info['sc_ftp_yn'] != 'Y'
                Log    [Suite] T_ZONE_LIST(${db}) ${code} 는 SC_FTP_YN 이 'Y' 가 아님 → TC-006 에서 이 코드는 실패로 남는다    level=WARN
            END
            # TC 판정은 DB1(PG 가 조회하는 쪽과 같다고 본다) 값으로 한다
            IF    $db == 'DB1'    Set To Dictionary    ${zones}    ${code}=${info}
        END
    END
    Set Suite Variable    ${CMS_ZONES}    ${zones}

CMS Zone Should Allow SC Forward
    [Documentation]    TC-006 — 시작 전 조회한 이 코드의 SC_FTP_YN 이 'Y' 가 아니면 실패(조회하지 못했으면 통과시켜 그대로 시험).
    [Arguments]    ${code}
    IF    $code not in $CMS_ZONES
        RETURN
    END
    ${info}=    Set Variable    ${CMS_ZONES}[${code}]
    IF    $info['sc_ftp_yn'] != 'Y'
        Fail    ${info}[text] — SC_FTP_YN 이 'Y' 가 아니라 PG 가 SC 로 올리지 않습니다(T_ZONE_LIST 는 슈트가 바꾸지 않음)
    END

CMS Zone Code For Normal Case
    [Documentation]    TC-005 의 기대 ZONE_CODE — ${CMS_ZONE_CODE} 가 있으면 그 값, 없으면 시작 전 조회값. 등록이 없거나 SC 전달 코드면 실패.
    IF    $CMS_ZONE_CODE
        RETURN    ${CMS_ZONE_CODE}
    END
    IF    $CMS_SERVICE_CODE not in $CMS_ZONES
        Fail    ${CMS_SERVICE_CODE} 의 T_ZONE_LIST 값을 시작 전에 조회하지 못했습니다 — CMS_ZONE_CODE 를 주거나 PDB 접속을 확인하십시오
    END
    ${info}=    Set Variable    ${CMS_ZONES}[${CMS_SERVICE_CODE}]
    IF    not $info['found']
        Fail    ${info}[text] — TC-005 는 T_ZONE_LIST 에 등록된(SC_FTP_YN='N') 서비스코드가 필요합니다. CMS_SERVICE_CODE 를 바꾸십시오(슈트는 행을 만들지 않음)
    END
    IF    $info['sc_ftp_yn'] == 'Y'
        Fail    ${info}[text] — SC_FTP_YN='Y' 면 PG 가 T_CMSWEB_ZONE 에 기록하지 않습니다. SC_FTP_YN='N' 인 코드를 CMS_SERVICE_CODE 로 주십시오
    END
    RETURN    ${info}[zone_code]

Ensure CMS DB Connection
    [Documentation]    T_CMSWEB_ZONE 판정용 PDB 접속(한 번만). ${PDB_CONNSTR_2} 가 있으면 두 번째 DB 도 붙는다.
    IF    $CMS_DB_CONN is not None
        RETURN
    END
    ${conn}=    CmsDb.Db Connect    timeout=${PDB_TIMEOUT}    autocommit=${FALSE}
    Set Suite Variable    ${CMS_DB_CONN}    ${conn}
    ${has_2nd}=    CmsDb.Has Second Db
    IF    ${has_2nd}
        ${conn_2}=    CmsDb.Db Connect    timeout=${PDB_TIMEOUT}    autocommit=${FALSE}    which=${2}
        Set Suite Variable    ${CMS_DB_CONN_2}    ${conn_2}
    END

Check CMS Session
    [Documentation]    Test Setup — 제어 채널이 살아 있어야 한다.
    IF    $CMS_CONN is None
        Fail    PG.CMS 제어 채널이 없습니다 — Suite Setup 이 실패했거나 앞 TC 가 복구하지 못했습니다.
    END
    Cms.Cms Sftp Clear    ${CMS_SFTP_SERVER}
    Cms.Cms Sftp Clear    ${CMS_SC_SERVER}

Restore CMS Session
    [Documentation]    TC 가 연결을 끊었다면(REG_NOK·타임아웃 시험) PG 재접속을 받아 원상태로 돌린다.
    Run Keyword If    $CMS_CONN is not None    Tcp.Client Close    ${CMS_CONN}
    Set Suite Variable    ${CMS_CONN}    ${NONE}
    Accept CMS Session

Close CMSWEB
    [Documentation]    Suite Teardown — 시험 행 정리 → PDB·제어 채널·SFTP 종료. 앞 단계가 실패해도 뒤 단계는 한다.
    Run Keyword And Ignore Error    Cleanup CMS Zone Rows
    Run Keyword And Ignore Error    Cleanup CMS FIN Files
    Run Keyword And Ignore Error    Cleanup CMS SC Files
    Run Keyword If    $CMS_DB_CONN is not None      CmsDb.Db Close    ${CMS_DB_CONN}
    Run Keyword If    $CMS_DB_CONN_2 is not None    CmsDb.Db Close    ${CMS_DB_CONN_2}
    Run Keyword If    $CMS_CONN is not None         Tcp.Client Close    ${CMS_CONN}
    Run Keyword If    $CMS_SRV_SOCK is not None     Tcp.Server Stop    ${CMS_SRV_SOCK}
    Cms.Cms Sftp Stop    ${CMS_SFTP_SERVER}
    Cms.Cms Sftp Stop    ${CMS_SC_SERVER}

Cleanup CMS Zone Rows
    [Documentation]    이번 슈트의 서비스코드로 생긴 T_CMSWEB_ZONE 행을 지운다(${CMS_CLEANUP_ON_TEARDOWN}).
    IF    not ${CMS_CLEANUP_ON_TEARDOWN} or $CMS_DB_CONN is None
        RETURN
    END
    ${n}=    CmsDb.Db Execute    ${CMS_DB_CONN}    ${CMS_DB_SQL_CLEANUP}    ${CMS_SERVICE_CODE}    ${CMS_SERVICE_CODE_UNREG}
    Log    [Suite] 종료 시 정리 — ${CMS_DB_TBL_ZONE} ${n}건 삭제 (DB1)    console=True
    IF    $CMS_DB_CONN_2 is not None
        ${n2}=    CmsDb.Db Execute    ${CMS_DB_CONN_2}    ${CMS_DB_SQL_CLEANUP}    ${CMS_SERVICE_CODE}    ${CMS_SERVICE_CODE_UNREG}
        Log    [Suite] 종료 시 정리 — ${CMS_DB_TBL_ZONE} ${n2}건 삭제 (DB2)    console=True
    END

Cleanup CMS FIN Files
    [Documentation]
    ...    sshd 모드: 이번 실행에서 보낸 NTI 의 FIN 접두사와 맞는 .FIN 만 실제 디렉터리에서 지운다
    ...    (${CMS_FIN_CLEANUP}). 못 지운 것은 로그만 남긴다. simulator 모드는 임시 디렉터리라 할 일이 없다.
    IF    not ${CMS_FIN_CLEANUP} or $CMS_FIN_MODE != 'sshd' or not $CMS_FIN_PREFIXES
        IF    not ${CMS_FIN_CLEANUP} and $CMS_FIN_MODE == 'sshd' and $CMS_FIN_PREFIXES    Log    [Suite] CMSWEB FIN 을 남깁니다 — ${CMS_REMOTE_DIR}    console=True
        RETURN
    END
    ${result}=    Cms.Cms Fin Ssh Cleanup    ${CMS_FIN_SSH_HOST}    ${CMS_FIN_SSH_PORT}    ${CMS_FIN_SSH_USER}
    ...    ${CMS_REMOTE_DIR}    ${CMS_FIN_PREFIXES}
    ${removed}=    Get Length    ${result}[removed]
    Log    [Suite] 종료 시 정리 — ${CMS_REMOTE_DIR} FIN ${removed}건 삭제 ${result}[removed]    console=True
    IF    $result['failed']
        Log    [Suite] FIN 정리 실패(수동 정리 필요) — ${result}[failed]    level=WARN
    END

Cleanup CMS SC Files
    [Documentation]
    ...    ${CMS_SC_CLEANUP} 일 때만 이번 실행의 SC 시험이 기대한 이름의 파일만 지운다(기본은 남긴다).
    ...    local 은 도구의 수신 디렉터리, remote 는 SC 서버의 SC_PATH 에서 지운다.
    IF    not ${CMS_SC_CLEANUP} or not $CMS_SC_FILES or ($CMS_SC_MODE == 'local' and $CMS_SC_SERVER is None)
        IF    $CMS_SC_FILES    Log    [Suite] SC 파일을 남깁니다 — ${CMS_SC_REAL_DIR} ${CMS_SC_FILES}    console=True
        RETURN
    END
    IF    $CMS_SC_MODE == 'remote'
        ${result}=    Cms.Cms Sc Remote Cleanup    ${CMS_SC_FILE_PROTO}    ${CMS_SC_PG_ADDR}    ${CMS_SC_PORT}
        ...    ${CMS_SC_SFTP_USER}    ${CMS_SC_PATH}    ${CMS_SC_FILES}
    ELSE
        ${result}=    Cms.Cms Sc Cleanup    ${CMS_SC_REAL_DIR}    ${CMS_SC_FILES}
    END
    ${removed}=    Get Length    ${result}[removed]
    Log    [Suite] 종료 시 정리 — ${CMS_SC_REAL_DIR} SC 파일 ${removed}건 삭제 ${result}[removed]    console=True
    IF    $result['failed']
        Log    [Suite] SC 파일 정리 실패(수동 정리 필요) — ${result}[failed]    level=WARN
    END

# ══════════════════════════════════════════════════════════════════
# 제어 채널 — REG / HBC / NTI / ANS
# ══════════════════════════════════════════════════════════════════

REG Should Carry PG Session Key
    [Documentation]    REG 의 sourceSessionKey 가 PG_V2.cfg [CMS] GROUP/KEY 와 같은지 본다.
    [Arguments]    ${reg}=${CMS_REG_MSG}
    Cms.Cms Session Key Should Be    ${reg}    ${CMS_PG_GROUP}    ${CMS_PG_KEY}

Reject PG Registration
    [Documentation]
    ...    REG_NOK 를 보내고 PG 가 연결을 닫는지 본다(CCMSWeb::Run — REG result 가 REG_OK 가 아니면 ClearSocket).
    ...    시작 전에 연결이 살아 있어야 한다 — 이미 닫혀 있으면 REG_NOK 를 시험하지 못한 것이므로 실패한다.
    Cms.Cms Should Be Connected    ${CMS_CONN}
    ${nok}=    Cms.Cms Reg Result    ${FALSE}
    ${sent}=    Cms.Cms Send    ${CMS_CONN}    REG    ${nok}
    Log    [CMS] → REG ${sent}
    ${elapsed}=    Cms.Cms Wait Closed    ${CMS_CONN}    ${CMS_RECV_TIMEOUT}
    Log    [CMS] PG.CMS 가 REG_NOK 후 ${elapsed}초 만에 연결을 닫았습니다    console=True

Wait PG Idle Disconnect
    [Documentation]
    ...    아무것도 보내지 않고 CMSWEB_TIMEOUT(${CMS_PG_TIMEOUT}초) 뒤 PG 가 끊는지 본다 → 걸린 초.
    ...    시작 전에 연결이 살아 있어야 한다 — 이미 닫혀 있으면 타임아웃을 시험하지 못한 것이므로 실패한다.
    Cms.Cms Should Be Connected    ${CMS_CONN}
    ${limit}=    Evaluate    int(${CMS_PG_TIMEOUT}) + 60
    Log    [CMS] 무수신 타임아웃 대기 — 최대 ${limit}초    console=True
    ${elapsed}=    Cms.Cms Wait Closed    ${CMS_CONN}    ${limit}
    Log    [CMS] PG.CMS 가 ${elapsed}초 만에 연결을 닫았습니다    console=True
    RETURN    ${elapsed}

Send CMS HBC And Expect Reply
    [Documentation]    도구 → PG HBC, PG → 도구 HBC 응답을 받아 돌려준다.
    ${hbc}=    Cms.Cms Hbc
    ${sent}=    Cms.Cms Send    ${CMS_CONN}    HBC    ${hbc}
    Log    [CMS] → HBC ${sent}
    ${reply}=    Cms.Cms Expect    ${CMS_CONN}    HBC    ${CMS_RECV_TIMEOUT}
    Log    [CMS] ← HBC ${reply}[text]
    RETURN    ${reply}

HBC Reply Should Be Valid
    [Documentation]    HBC 응답 — sourceSessionKey=[GROUP,KEY], result=HBC_OK, dateTime 형식(규격 4.5.2).
    [Arguments]    ${reply}
    Cms.Cms Session Key Should Be    ${reply}    ${CMS_PG_GROUP}    ${CMS_PG_KEY}
    ${result}=    Cms.Cms Field    ${reply}    result
    Should Be Equal    ${result}    HBC_OK    msg=HBC result 기대=HBC_OK, 실제=${result}
    ${dt}=    Cms.Cms Field    ${reply}    dateTime
    Cms.Cms Date Time Should Be Valid    ${dt}

Send CMS NTI
    [Documentation]
    ...    시험 파일을 SFTP 서버에 만들고 NTI 를 보낸 뒤, PG 의 ANS 를 받아 검증한다 → 시험 정보(dict).
    ...    omit 에 필드 이름을 주면 그 필드를 뺀 NTI 를 보낸다(음성 시험). ANS 는 그래도 와야 한다
    ...    — PG 는 필드 검증 전에 ANS 를 보낸다.
    [Arguments]    ${service_code}=${CMS_SERVICE_CODE}    ${size}=${CMS_FILE_BYTES}
    ...            ${declared_size}=${EMPTY}    ${omit}=${EMPTY}
    ${case}=    Cms.Cms New Case    ${CMS_SFTP_SERVER}    ${CMS_REMOTE_DIR}    ${service_code}
    ...    ${CMS_PG_GROUP}    ${CMS_PG_KEY}    size=${size}    declared_size=${declared_size}
    ...    omit=${omit}    source_group=${CMS_SRC_GROUP}    source_key=${CMS_SRC_KEY}
    ...    id_group=${CMS_MSG_ID_GROUP}
    Append To List    ${CMS_FIN_PREFIXES}    ${case}[fin_prefix]
    IF    $service_code in $CMS_SERVICE_CODES_SC
        Append To List    ${CMS_SC_FILES}    ${case}[sc_data]    ${case}[sc_fin]
    END
    ${sent}=    Cms.Cms Send    ${CMS_CONN}    NTI    ${case}[body]
    Log    [CMS] → NTI ${sent}
    ${ans}=    Cms.Cms Expect    ${CMS_CONN}    ANS    ${CMS_RECV_TIMEOUT}
    Log    [CMS] ← ANS ${ans}[text]
    Cms.Cms Ans Should Match    ${ans}    ${case}    ${CMS_PG_GROUP}    ${CMS_PG_KEY}
    RETURN    ${case}

# ══════════════════════════════════════════════════════════════════
# 파일 채널 — SFTP GET(시뮬레이터) / FIN PUT(실제 sshd 또는 시뮬레이터)
# ══════════════════════════════════════════════════════════════════

PG Should Download File From CMSWEB
    [Documentation]    PG 가 NTI 의 파일을 파일 서버(${CMS_FILE_PROTO})에서 가져갔는지 본다.
    [Arguments]    ${case}
    Cms.Cms Sftp Wait Download    ${CMS_SFTP_SERVER}    ${case}[file_name]    ${CMS_FIN_TIMEOUT}

PG Should Upload FIN To CMSWEB
    [Documentation]
    ...    PG 가 `<serviceCode>_<dateTime>_<GROUP><KEY>_<시각>.FIN` 을 올렸는지 본다 → 파일명.
    ...    sshd 모드는 도구 호스트 실제 sshd 의 ${CMS_REMOTE_DIR} 를, simulator 모드는 시뮬레이터 업로드 이력을 본다.
    [Arguments]    ${case}
    IF    $CMS_FIN_MODE == 'sshd'
        ${fin}=    Cms.Cms Fin Ssh Wait    ${CMS_FIN_SSH_HOST}    ${CMS_FIN_SSH_PORT}    ${CMS_FIN_SSH_USER}
        ...    ${CMS_REMOTE_DIR}    ${case}[fin_prefix]    ${CMS_FIN_TIMEOUT}
    ELSE
        ${fin}=    Cms.Cms Sftp Wait Upload    ${CMS_SFTP_SERVER}    ${case}[fin_prefix]    ${CMS_FIN_TIMEOUT}
    END
    Log    [CMS] FIN 확인(${CMS_FIN_MODE}) — ${fin}[filename]
    Should Match Regexp    ${fin}[filename]    ^${case}[fin_prefix]\\d{14}\\.FIN$
    ...    msg=FIN 파일명 형식이 다릅니다: ${fin}[filename]
    Should Be Equal As Integers    ${fin}[size]    0    msg=FIN 파일은 빈 파일이어야 합니다: ${fin}[size]바이트
    RETURN    ${fin}[filename]

PG Should Upload File And FIN To SC
    [Documentation]
    ...    SC_FTP_YN=Y — PG 가 받은 파일(이름 바뀐 .dat, 크기 그대로)과 빈 .FIN 을 SC 로(${CMS_SC_FILE_PROTO}) 올려
    ...    두 파일이 생겼는지 본다(CCMSWeb::RunSFtpSC / RunFtpSC). local 은 도구의 수신 디렉터리
    ...    (${CMS_SC_UPLOAD_DIR}), remote 는 [SC] SC_PRIIP 서버의 SC_PATH 에 접속해 본다.
    [Arguments]    ${case}
    IF    $CMS_SC_MODE == 'remote'
        ${got}=    Cms.Cms Sc Remote Wait Uploads    ${CMS_SC_FILE_PROTO}    ${CMS_SC_PG_ADDR}    ${CMS_SC_PORT}
        ...    ${CMS_SC_SFTP_USER}    ${CMS_SC_PATH}    ${case}    ${CMS_SC_TIMEOUT}
    ELSE
        ${got}=    Cms.Cms Sc Wait Uploads    ${CMS_SC_SERVER}    ${case}    ${CMS_SC_REAL_DIR}    ${CMS_SC_TIMEOUT}
    END
    Log    [CMS] SC 수신 — ${got}[data][path] (${got}[data][size]바이트), ${got}[fin][path]    console=True
    RETURN    ${got}

PG Should Not Download File From CMSWEB
    [Documentation]    ${CMS_QUIET_WINDOW}초 동안 PG 가 이 파일을 가져가지 않는지 본다(음성 판정).
    [Arguments]    ${case}
    Cms.Cms Sftp Should Stay Quiet    ${CMS_SFTP_SERVER}    ${case}[file_name]    ${CMS_QUIET_WINDOW}    kind=download

PG Should Not Upload FIN To CMSWEB
    [Documentation]    ${CMS_QUIET_WINDOW}초 동안 이 NTI 에 대한 FIN 이 올라오지 않는지 본다(음성 판정, ${CMS_FIN_MODE} 모드).
    [Arguments]    ${case}
    IF    $CMS_FIN_MODE == 'sshd'
        Cms.Cms Fin Ssh Should Stay Quiet    ${CMS_FIN_SSH_HOST}    ${CMS_FIN_SSH_PORT}    ${CMS_FIN_SSH_USER}
        ...    ${CMS_REMOTE_DIR}    ${case}[fin_prefix]    ${CMS_QUIET_WINDOW}
    ELSE
        Cms.Cms Sftp Should Stay Quiet    ${CMS_SFTP_SERVER}    ${case}[fin_prefix]    ${CMS_QUIET_WINDOW}    kind=upload
    END

# ══════════════════════════════════════════════════════════════════
# PDB — T_CMSWEB_ZONE
# ══════════════════════════════════════════════════════════════════

Verify CMSWEB Zone Row In PDB
    [Documentation]
    ...    MSG_ID 로 T_CMSWEB_ZONE 행을 찾아 STATUS/REASON 등을 본다. PG 가 넣기까지 시간이 걸려
    ...    ${CMS_DB_WAIT} 동안 다시 본다. 두 번째 DB 가 있으면 그쪽도 같은 판정을 한다
    ...    (PG 는 ALTIBASE_USE=Y 면 두 DB 모두에 넣는다).
    [Arguments]    ${case}    ${status}    ${reason}    ${file_name}=${NONE}    ${file_size}=${NONE}
    ...            ${zone_code}=${NONE}    ${service_code}=${NONE}
    Ensure CMS DB Connection
    Wait Until Keyword Succeeds    ${CMS_DB_WAIT}    ${CMS_DB_WAIT_INTERVAL}
    ...    CMSWEB Zone Row Should Match    ${CMS_DB_CONN}    DB1    ${case}    ${status}    ${reason}
    ...    ${file_name}    ${file_size}    ${zone_code}    ${service_code}
    IF    $CMS_DB_CONN_2 is not None
        Wait Until Keyword Succeeds    ${CMS_DB_WAIT}    ${CMS_DB_WAIT_INTERVAL}
        ...    CMSWEB Zone Row Should Match    ${CMS_DB_CONN_2}    DB2    ${case}    ${status}    ${reason}
        ...    ${file_name}    ${file_size}    ${zone_code}    ${service_code}
    END

CMSWEB Zone Row Should Match
    [Documentation]    한 DB 에서 한 번 조회해 판정한다. 재시도는 호출부가 한다.
    [Arguments]    ${conn}    ${db}    ${case}    ${status}    ${reason}    ${file_name}
    ...            ${file_size}    ${zone_code}    ${service_code}
    ${rows}=    CmsDb.Db Rows    ${conn}    ${CMS_DB_SQL_ZONE_BY_MSG}    ${case}[message_id]
    Cms.Cms Zone Row Should Match    ${rows}    ${status}    ${reason}    ${file_name}    ${file_size}
    ...    ${zone_code}    ${service_code}    label=${CMS_DB_TBL_ZONE}(${db}, MSG_ID=${case}[message_id])
