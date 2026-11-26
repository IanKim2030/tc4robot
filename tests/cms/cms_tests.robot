*** Settings ***
Documentation
...    CMS(CMSWEB) 연동 기능 검증 — 도구(ROBOT)가 CMSWEB 서버, PG.CMS(CMS201)가 클라이언트
...
...    [테스트 대상]
...    PG.CMS → 도구로 Port:${CMS_LISTEN_PORT}로 접속 (13B 헤더 + EUC-KR JSON, 규격 v1.9)
...    PG.CMS → 도구 파일 서버 (NTI 파일 GET) — [CMS] CMSWEB_SFTP (Y:SFTP, N:FTP) 로 기동 시 고른다
...      SFTP(기본): ${CMS_SFTP_PORT}([CMS] CMS_SFTP_PORT), .FIN 은 도구 호스트 실제 ssh ${CMS_FIN_SSH_PORT}
...      FTP(CMSWEB_SFTP=N): ${CMS_FTP_PORT}(PG.CMS 21포트 고정), .FIN 도 같은 FTP 세션으로 온다
...    PG.CMS → PDB T_CMSWEB_ZONE (처리 결과)
...
...    [전제 — PG 설정, ${PG_HOST} SSH 연결후 설정파일 다운로드 후 적용]
...    PG_V2.cfg 설정 적용: [CMS] CMSWEB_ADDR=${TOOL_HOST}, CMSWEB_SFTP(SFTP 모드), CMS_SFTP_PORT=1024 이상(도구 SFTP 포트).
...    FTP 모드에서는 도구가 무조건 21 을 열어야 한다(root 또는 리다이렉트 + --variable CMS_FTP_PORT).
...    다르면 Suite Setup 이 무엇을 바꿔야 하는지 알려 주고 중단한다.
...    파일 계정(SFTP/FTP 공통) = 환경 파일 CMS_SFTP_USER + 환경변수 PG_PWD_CMS_SFTP(시뮬레이터 다운로드)
...    / PG_PWD_CMS_FIN_SSH(도구 호스트 실제 pg 계정 — FIN 확인, 없으면 PG_PWD_CMS_SFTP). ${CMS_REMOTE_DIR} 는 그 계정이 쓸 수 있어야 한다.
...    T_ZONE_LIST 는 조회만 한다(이미 등록된 행을 쓴다). Suite Setup 이 시작 전에
...    세트 서비스코드(${CMS_SERVICE_CODES_SC})와 ${CMS_SERVICE_CODE} 의 SC_FTP_YN 등을 조회해 보여 준다.
...    SC 쪽도 Suite Setup 에서 준비한다 — [SC] SC_PRIIP 가 도구(${TOOL_HOST})면 업로드(SC 수신) 서버를 띄우고,
...    다른 IP 면 그 SC 서버에 SC 계정으로 접속해 확인한다(비밀번호 PG_PWD_CMS_SFTP_UPLOAD). [CMS] NWDAF_SFTP 가
...    'N' 이면 FTP(NWDAF_FTP_PORT), 아니면 SFTP(NWDAF_SFTP_PORT)로 받는다.
...    PG 는 SC_PATH(${CMS_SC_PATH})로 올리고 도구는 그것을 ${CMS_SC_UPLOAD_DIR} 에 받는다(비밀번호 PG_PWD_CMS_SFTP_UPLOAD).
...
...    [Suite 정책]
...    Suite Setup    : Prepare CMSWEB (T_ZONE_LIST 값 표시 → REG 수신 → REG_OK 까지). 설정값 없음·서버 기동 실패·
...                     PG.CMS 미접속이면 TC 를 수행하지 않고 실패(CMS TC 미수행)
...    Test Setup     : Check CMS Session (파일 서버 이력 초기화)
...    Suite Teardown : Close CMSWEB (이번 실행 MSG_ID 의 T_CMSWEB_ZONE 행 정리 — FIN·SC 파일은 남김)
...
...    [TC 번호 체계]
...    001       REG 세션키
...    002       HBC HeartBeat
...    003 ~ 005 NTI LTE 세트(TRAP_LTE_EQP_INFO) — ANS / CMSWEB 다운로드 → FIN / SC_FTP_YN 분기
...    006 ~ 008 NTI 5G 세트(TRAP_5G_EQP_INFO)  — 위와 같은 3개
...              (SC_FTP_YN 분기: Y → SC 업로드·FIN 확인 / N → T_CMSWEB_ZONE 확인 + SC 업로드 없음 확인)
...    009 ~ 011 T_CMSWEB_ZONE 기록(SC_FTP_YN=N, ROBOT 시험 코드 — DB 시드)
...              NOTI_YN=Y 크기 > 0 → C/OK / NOTI_YN=Y 크기 0 → W/Waiting State / NOTI_YN=N → F/Err ZoneCode
...    012 ~ 013 NTI 이상 — 필수 필드 누락 / 미등록 서비스코드
...    014       세션 — REG_NOK 재접속

Resource    ../../resources/variables.robot
Resource    ../../resources/common_keywords.robot
Resource    ../../resources/cms_keywords.robot

Suite Setup      Prepare CMSWEB
Suite Teardown   Close CMSWEB
Test Setup       Check CMS Session


*** Test Cases ***

# ════════════════════════════════════════════════════════════════
# 세션 등록 (규격 3.1 / 4.3)
# ════════════════════════════════════════════════════════════════

TC-CMS-001 REG - PG 세션키 확인 → REG_OK
    [Documentation]    접속 직후 PG.CMS 가 보낸 REG 의 sourceSessionKey 가 PG_V2.cfg [CMS] GROUP/KEY 인지 확인한다(Suite Setup 에서 수신).
    [Tags]    cms    reg
    REG Should Carry PG Session Key

# ════════════════════════════════════════════════════════════════
# Heartbeat (규격 3.3 / 4.5)
# ════════════════════════════════════════════════════════════════

TC-CMS-002 HBC - CMSWEB (요청) → PG.CMS (응답) → CMSWEB 응답확인
    [Documentation]    도구(CMSWEB)가 HBC 를 보내면 PG.CMS 가 sourceSessionKey / dateTime / result=HBC_OK 응답을 확인한다.
    [Tags]    cms    hbc
    ${reply}=    Send CMS HBC And Expect Reply
    HBC Reply Should Be Valid    ${reply}

# ════════════════════════════════════════════════════════════════
# NTI 파일 연동 — LTE 세트 (TRAP_LTE_EQP_INFO)
# ════════════════════════════════════════════════════════════════

TC-CMS-003 NTI(LTE) - ANS 수신 (messageId 에코, NTI_OK)
    [Documentation]    도구(CMSWEB)가 TRAP_LTE_EQP_INFO NTI(Report) 를 보내면 PG.CMS 가 같은 messageId 와 data=NTI_OK 로 ANS 를 보낸다.
    [Tags]    cms    nti    lte
    Send CMS NTI    service_code=TRAP_LTE_EQP_INFO

TC-CMS-004 NTI(LTE) - CMSWEB 파일 다운로드 → FIN 생성
    [Documentation]
    ...    PG.CMS 가 CMSWEB 에서 COLUMN_DATA 경로의 파일을 ${CMS_FILE_PROTO} 로 다운로드하고, 같은 디렉터리에
    ...    빈 파일 <serviceCode>_<dateTime>_<GROUP><KEY>_<시각>.FIN 이 생겼는지 본다(규격 5.1 / 5.4.2).
    [Tags]    cms    sftp    lte
    ${case}=    Send CMS NTI    service_code=TRAP_LTE_EQP_INFO
    PG Should Download File From CMSWEB    ${case}
    PG Should Upload FIN To CMSWEB    ${case}

TC-CMS-005 NTI(LTE) - SC_FTP_YN 분기 (Y → SC 업로드·FIN / N → T_CMSWEB_ZONE 반영)
    [Documentation]
    ...    시작 전 조회한 TRAP_LTE_EQP_INFO 의 T_ZONE_LIST.SC_FTP_YN 으로 판정을 나눈다. 먼저 CMSWEB FIN 업로드를 확인한 뒤
    ...    - Y : PG 가 받은 파일(크기 자리를 뗀 이름)과 빈 .FIN 을 SC(NWDAF_SFTP=Y → SFTP, N → FTP)의 SC_PATH 로
    ...          올렸는지 본다. 데이터 파일 크기가 같아야 한다. PG 는 T_CMSWEB_ZONE 에 기록하지 않는다.
    ...    - N : T_CMSWEB_ZONE 행(FILENAME=크기 자리를 뗀 이름, ZONE_CODE=T_ZONE_LIST 값)을 본 뒤 SC 로 업로드하지 않았는지 본다.
    ...          NOTI_YN=N → F / 'Err ZoneCode' / 0, NOTI_YN=Y 크기 0 → W / 'Waiting State' / 0,
    ...          NOTI_YN=Y 크기 > 0 → C(E 허용) / 'OK' / 실제 크기.
    ...    T_ZONE_LIST 에 등록이 없거나 조회하지 못했으면 FAIL.
    [Tags]    cms    db    sc    lte
    ${zone}=    CMS Zone Info    TRAP_LTE_EQP_INFO
    ${case}=    Send CMS NTI    service_code=TRAP_LTE_EQP_INFO
    PG Should Upload FIN To CMSWEB    ${case}
    PG Should Forward By SC_FTP_YN    ${case}    ${zone}

# ════════════════════════════════════════════════════════════════
# NTI 파일 연동 — 5G 세트 (TRAP_5G_EQP_INFO)
# ════════════════════════════════════════════════════════════════

TC-CMS-006 NTI(5G) - ANS 수신 (messageId 에코, NTI_OK)
    [Documentation]    도구(CMSWEB)가 TRAP_5G_EQP_INFO NTI(Report) 를 보내면 PG.CMS 가 같은 messageId 와 data=NTI_OK 로 ANS 를 보낸다.
    [Tags]    cms    nti    5g
    Send CMS NTI    service_code=TRAP_5G_EQP_INFO

TC-CMS-007 NTI(5G) - CMSWEB 파일 다운로드 → FIN 생성
    [Documentation]
    ...    PG.CMS 가 CMSWEB 에서 COLUMN_DATA 경로의 파일을 ${CMS_FILE_PROTO} 로 다운로드하고, 같은 디렉터리에
    ...    빈 파일 <serviceCode>_<dateTime>_<GROUP><KEY>_<시각>.FIN 이 생겼는지 본다(규격 5.1 / 5.4.2).
    [Tags]    cms    sftp    5g
    ${case}=    Send CMS NTI    service_code=TRAP_5G_EQP_INFO
    PG Should Download File From CMSWEB    ${case}
    PG Should Upload FIN To CMSWEB    ${case}

TC-CMS-008 NTI(5G) - SC_FTP_YN 분기 (Y → SC 업로드·FIN / N → T_CMSWEB_ZONE 반영)
    [Documentation]
    ...    시작 전 조회한 TRAP_5G_EQP_INFO 의 T_ZONE_LIST.SC_FTP_YN 으로 판정을 나눈다. 먼저 CMSWEB FIN 업로드를 확인한 뒤
    ...    - Y : PG 가 받은 파일(크기 자리를 뗀 이름)과 빈 .FIN 을 SC(NWDAF_SFTP=Y → SFTP, N → FTP)의 SC_PATH 로
    ...          올렸는지 본다. 데이터 파일 크기가 같아야 한다. PG 는 T_CMSWEB_ZONE 에 기록하지 않는다.
    ...    - N : T_CMSWEB_ZONE 행(FILENAME=크기 자리를 뗀 이름, ZONE_CODE=T_ZONE_LIST 값)을 본 뒤 SC 로 업로드하지 않았는지 본다.
    ...          NOTI_YN=N → F / 'Err ZoneCode' / 0, NOTI_YN=Y 크기 0 → W / 'Waiting State' / 0,
    ...          NOTI_YN=Y 크기 > 0 → C(E 허용) / 'OK' / 실제 크기.
    ...    T_ZONE_LIST 에 등록이 없거나 조회하지 못했으면 FAIL.
    [Tags]    cms    db    sc    5g
    ${zone}=    CMS Zone Info    TRAP_5G_EQP_INFO
    ${case}=    Send CMS NTI    service_code=TRAP_5G_EQP_INFO
    PG Should Upload FIN To CMSWEB    ${case}
    PG Should Forward By SC_FTP_YN    ${case}    ${zone}

# ════════════════════════════════════════════════════════════════
# T_CMSWEB_ZONE 기록 — SC_FTP_YN=N (ROBOT 시험 코드, config/db_seed/dev.sql 이 넣는다)
# ════════════════════════════════════════════════════════════════

TC-CMS-009 NTI(SC_FTP_YN=N, NOTI_YN=Y) - 파일 크기 > 0 → T_CMSWEB_ZONE C / OK
    [Documentation]
    ...    TRAP_ROBOT_ZONE_TEST(SC_FTP_YN=N, NOTI_YN=Y)로 ${CMS_FILE_BYTES}바이트 파일을 보내면 PG 가 받아 FIN 을 올리고
    ...    T_CMSWEB_ZONE 에 STATUS 'C'(ZONE 처리 후 'E' 허용) / REASON 'OK' / FILESIZE 실제 크기 / ZONE_CODE ZN999999 로
    ...    기록한다. SC 로는 올리지 않는다.
    [Tags]    cms    db    zone
    ${zone}=    CMS Zone Info    TRAP_ROBOT_ZONE_TEST    sc_ftp_yn=N    noti_yn=Y
    ${case}=    Send CMS NTI    service_code=TRAP_ROBOT_ZONE_TEST
    PG Should Upload FIN To CMSWEB    ${case}
    PG Should Forward By SC_FTP_YN    ${case}    ${zone}

TC-CMS-010 NTI(SC_FTP_YN=N, NOTI_YN=Y) - 파일 크기 0 → T_CMSWEB_ZONE W / Waiting State
    [Documentation]
    ...    TRAP_ROBOT_ZONE_TEST(SC_FTP_YN=N, NOTI_YN=Y)로 0바이트 파일(이름 _0.dat)을 보내면 PG 가 받아 FIN 을 올리고
    ...    크기 0 을 이상 파일로 보아 T_CMSWEB_ZONE 에 STATUS 'W' / REASON 'Waiting State' / FILESIZE 0 으로 기록한다
    ...    (CCMSWeb::setData ERR_ABNORMAL_FILE). SC 로는 올리지 않는다.
    [Tags]    cms    db    zone
    ${zone}=    CMS Zone Info    TRAP_ROBOT_ZONE_TEST    sc_ftp_yn=N    noti_yn=Y
    ${case}=    Send CMS NTI    service_code=TRAP_ROBOT_ZONE_TEST    size=${0}
    PG Should Upload FIN To CMSWEB    ${case}
    PG Should Forward By SC_FTP_YN    ${case}    ${zone}

TC-CMS-011 NTI(SC_FTP_YN=N, NOTI_YN=N) - T_CMSWEB_ZONE F / Err ZoneCode
    [Documentation]
    ...    TRAP_ROBOT_ZONE_NOTI_N(SC_FTP_YN=N, NOTI_YN=N)로 보내면 PG 가 파일을 받아 FIN 을 올린 뒤
    ...    T_CMSWEB_ZONE 에 STATUS 'F' / REASON 'Err ZoneCode' / FILESIZE 0 / ZONE_CODE ZN999997 로 기록한다.
    ...    SC 로는 올리지 않는다.
    [Tags]    cms    db    zone
    ${zone}=    CMS Zone Info    TRAP_ROBOT_ZONE_NOTI_N    sc_ftp_yn=N    noti_yn=N
    ${case}=    Send CMS NTI    service_code=TRAP_ROBOT_ZONE_NOTI_N
    PG Should Upload FIN To CMSWEB    ${case}
    PG Should Forward By SC_FTP_YN    ${case}    ${zone}

# ════════════════════════════════════════════════════════════════
# NTI 파일 연동 — 이상
# ════════════════════════════════════════════════════════════════

TC-CMS-012 NTI - 필수 필드(serviceCode) 누락 → ANS 는 오고 수집 안 함
    [Documentation]    PG 는 필드 검증 전에 ANS 를 보낸다. serviceCode 가 없으면 알람만 남기고 파일을 가져가지 않는다.
    [Tags]    cms    nti    negative
    ${case}=    Send CMS NTI    omit=serviceCode
    PG Should Not Download File From CMSWEB    ${case}

TC-CMS-013 NTI - T_ZONE_LIST 미등록 서비스코드 → Err ZoneCode
    [Documentation]
    ...    등록되지 않은 서비스코드도 PG 는 파일을 가져가고 FIN 을 올린다. 기록은 ZONE_CODE='NO',
    ...    STATUS='F', REASON='Err ZoneCode', FILESIZE=0 이다(dev 실측 행과 같은 형태).
    [Tags]    cms    db    negative
    ${case}=    Send CMS NTI    service_code=${CMS_SERVICE_CODE_UNREG}
    PG Should Upload FIN To CMSWEB    ${case}
    Verify CMSWEB Zone Row In PDB    ${case}    ${CMS_STATUS_FAILED}    ${CMS_REASON_ZONE}
    ...    file_size=${0}    zone_code=NO    service_code=${CMS_SERVICE_CODE_UNREG}

# ════════════════════════════════════════════════════════════════
# 세션 관리
# ════════════════════════════════════════════════════════════════

TC-CMS-014 REG_NOK → PG 재접속 후 REG 재수신
    [Documentation]    REG_NOK 를 받으면 PG 가 연결을 닫고 다시 접속해 REG 를 보낸다(약 10초 주기).
    [Tags]    cms    reg    negative
    Reject PG Registration
    Restore CMS Session
    REG Should Carry PG Session Key
    [Teardown]    Run Keyword If Test Failed    Run Keyword And Ignore Error    Restore CMS Session
