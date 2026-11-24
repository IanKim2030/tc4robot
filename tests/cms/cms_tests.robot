*** Settings ***
Documentation
...    CMS(CMSWEB) 연동 기능 검증 — 도구가 CMSWEB 서버, PG.CMS(CMS201)가 클라이언트
...
...    [테스트 대상]
...    PG.CMS → 도구 ${CMS_LISTEN_PORT} (13B 헤더 + EUC-KR JSON, 규격 v1.9)
...    PG.CMS → 도구 파일 서버 (NTI 파일 GET) — [CMS] CMSWEB_SFTP 로 기동 시 고른다
...      SFTP(기본): ${CMS_SFTP_PORT}([CMS] CMS_SFTP_PORT), .FIN 은 도구 호스트 실제 sshd ${CMS_FIN_SSH_PORT}
...      FTP(CMSWEB_SFTP=N): ${CMS_FTP_PORT}(PG 고정 21), .FIN 도 같은 FTP 세션으로 온다
...    PG.CMS → PDB T_CMSWEB_ZONE (처리 결과)
...
...    [전제 — PG 설정, 슈트가 고치지 않는다]
...    PG_V2.cfg [CMS] CMSWEB_ADDR=${TOOL_HOST}, (SFTP 모드) CMS_SFTP_PORT=1024 이상(도구 SFTP 포트).
...    FTP 모드는 도구가 21 을 열어야 한다(root 또는 리다이렉트 + --variable CMS_FTP_PORT).
...    다르면 Suite Setup 이 무엇을 바꿔야 하는지 알려 주고 중단한다.
...    파일 계정(SFTP/FTP 공통) = 환경 파일 CMS_SFTP_USER + 환경변수 PG_PWD_CMS_SFTP(시뮬레이터 다운로드)
...    / PG_PWD_CMS_FIN_SSH(도구 호스트 실제 pg 계정 — FIN 확인). ${CMS_REMOTE_DIR} 는 그 계정이 쓸 수 있어야 한다.
...    시험 서비스코드 ${CMS_SERVICE_CODE} · ${CMS_SERVICE_CODE_SC}(SC_FTP_YN=Y) 의 T_ZONE_LIST 행은 DB 시드가 넣는다.
...    SC 전달(006)은 [SC] SC_PRIIP=${TOOL_HOST} 가 전제다 — 틀리면 그 TC 만 실패한다. [CMS] NWDAF_SFTP 가
...    'N' 이면 FTP(NWDAF_FTP_PORT), 아니면 SFTP(NWDAF_SFTP_PORT)로 받는다.
...    PG 는 SC_PATH(${CMS_SC_PATH})로 올리고 도구는 그것을 ${CMS_SC_UPLOAD_DIR} 에 받는다(비밀번호 PG_PWD_CMS_SFTP_UPLOAD).
...
...    [Suite 정책]
...    Suite Setup    : Prepare CMSWEB Simulator (REG 수신 → REG_OK 까지)
...    Test Setup     : Check CMS Session (파일 서버 이력 초기화)
...    Suite Teardown : Close CMSWEB Simulator (T_CMSWEB_ZONE 시험 행·이번 실행 FIN 정리)
...
...    [TC 번호 체계]
...    001       REG 세션키
...    002       HBC
...    003 ~ 005 NTI 정상 — ANS / 파일 GET·FIN / T_CMSWEB_ZONE
...    006       NTI SC 전달 — SC_FTP_YN=Y 서비스코드 → SC(SFTP/FTP) 로 데이터 파일·FIN 업로드
...    007 ~ 009 NTI 이상 — 크기 불일치 / 필수 필드 누락 / 미등록 서비스코드
...    010 ~ 011 세션 — REG_NOK 재접속 / 무수신 타임아웃(slow)

Resource    ../../resources/variables.robot
Resource    ../../resources/common_keywords.robot
Resource    ../../resources/cms_keywords.robot

Suite Setup      Prepare CMSWEB Simulator
Suite Teardown   Close CMSWEB Simulator
Test Setup       Check CMS Session


*** Test Cases ***

# ════════════════════════════════════════════════════════════════
# 세션 등록 (규격 3.1 / 4.3)
# ════════════════════════════════════════════════════════════════

TC-CMS-001 REG - PG 세션키 확인 → REG_OK
    [Documentation]    접속 직후 PG 가 보낸 REG 의 sourceSessionKey 가 PG_V2.cfg [CMS] GROUP/KEY 인지 본다(Suite Setup 에서 수신).
    [Tags]    cms    reg
    REG Should Carry PG Session Key

# ════════════════════════════════════════════════════════════════
# Heartbeat (규격 3.3 / 4.5)
# ════════════════════════════════════════════════════════════════

TC-CMS-002 HBC - 도구 HBC → PG HBC 응답
    [Documentation]    도구가 HBC 를 보내면 PG 가 sourceSessionKey / dateTime / result=HBC_OK 로 답한다.
    [Tags]    cms    hbc
    ${reply}=    Send CMS HBC And Expect Reply
    HBC Reply Should Be Valid    ${reply}

# ════════════════════════════════════════════════════════════════
# NTI 파일 연동 — 정상 (규격 3.2 / 5)
# ════════════════════════════════════════════════════════════════

TC-CMS-003 NTI - ANS 수신 (messageId 에코, NTI_OK)
    [Documentation]    NTI(Report) 를 보내면 PG 가 같은 messageId 와 data=NTI_OK 로 ANS 를 보낸다.
    [Tags]    cms    nti
    Send CMS NTI

TC-CMS-004 NTI - 파일 수집 후 FIN 업로드
    [Documentation]
    ...    PG 가 COLUMN_DATA 경로의 파일을 ${CMS_FILE_PROTO} 로 가져가고, 같은 디렉터리에 빈 파일
    ...    <serviceCode>_<dateTime>_<GROUP><KEY>_<시각>.FIN 을 올린다(규격 5.1 / 5.4.2).
    [Tags]    cms    sftp
    ${case}=    Send CMS NTI
    PG Should Fetch CMS File    ${case}
    PG Should Upload CMS FIN    ${case}

TC-CMS-005 NTI - T_CMSWEB_ZONE 반영 (STATUS·REASON·FILESIZE)
    [Documentation]
    ...    정상 수집이면 PG 가 T_CMSWEB_ZONE 에 REASON='OK', FILESIZE=실제 크기, FILENAME=크기 자리를
    ...    뗀 이름, ZONE_CODE=T_ZONE_LIST 값으로 기록한다. STATUS 는 'C'(ZONE 처리 후 'E' 허용).
    [Tags]    cms    db
    ${case}=    Send CMS NTI
    PG Should Upload CMS FIN    ${case}
    Verify CMSWEB Zone Row In PDB    ${case}    ${CMS_STATUS_OK}    ${CMS_REASON_OK}
    ...    file_name=${case}[renamed]    file_size=${case}[size]
    ...    zone_code=${CMS_ZONE_CODE}    service_code=${CMS_SERVICE_CODE}

# ════════════════════════════════════════════════════════════════
# NTI 파일 연동 — SC(NWDAF) 전달 (CCMSWeb::RunSFtpSC / RunFtpSC)
# ════════════════════════════════════════════════════════════════

TC-CMS-006 NTI - SC_FTP_YN=Y → SC 로 데이터 파일·FIN 업로드
    [Documentation]
    ...    T_ZONE_LIST.SC_FTP_YN='Y' 인 서비스코드면 PG 가 CMSWEB 에서 받은 파일(크기 자리를 뗀 이름)과
    ...    빈 .FIN 을 SC(${CMS_SC_FILE_PROTO})의 SC_PATH 로 올린다 → ${CMS_SC_UPLOAD_DIR} 에 두 파일이
    ...    생기고 데이터 파일 크기가 같아야 한다. 이 경로는 T_CMSWEB_ZONE 에 행을 남기지 않는다.
    [Tags]    cms    sftp    sc
    Ensure CMS SC Server
    ${case}=    Send CMS NTI    service_code=${CMS_SERVICE_CODE_SC}
    PG Should Fetch CMS File    ${case}
    PG Should Upload CMS FIN    ${case}
    PG Should Forward CMS File To SC    ${case}

# ════════════════════════════════════════════════════════════════
# NTI 파일 연동 — 이상
# ════════════════════════════════════════════════════════════════

TC-CMS-007 NTI - 파일명 크기 ≠ 실제 크기 → FIN 없음, Waiting State
    [Documentation]
    ...    파일명의 크기 자리를 실제보다 1 크게 보내면 PG 가 크기 비교에 실패해 3회 재시도 후
    ...    FIN 을 올리지 않고, T_CMSWEB_ZONE 에 STATUS='W' / REASON='Waiting State' 로 남긴다.
    [Tags]    cms    sftp    db    negative
    ${declared}=    Evaluate    int(${CMS_FILE_BYTES}) + 1
    ${case}=    Send CMS NTI    declared_size=${declared}
    PG Should Fetch CMS File    ${case}
    PG Should Not Upload CMS FIN    ${case}
    Verify CMSWEB Zone Row In PDB    ${case}    ${CMS_STATUS_WAITING}    ${CMS_REASON_WAITING}
    ...    file_size=${0}

TC-CMS-008 NTI - 필수 필드(serviceCode) 누락 → ANS 는 오고 수집 안 함
    [Documentation]    PG 는 필드 검증 전에 ANS 를 보낸다. serviceCode 가 없으면 알람만 남기고 파일을 가져가지 않는다.
    [Tags]    cms    nti    negative
    ${case}=    Send CMS NTI    omit=serviceCode
    PG Should Not Fetch CMS File    ${case}

TC-CMS-009 NTI - T_ZONE_LIST 미등록 서비스코드 → Err ZoneCode
    [Documentation]
    ...    등록되지 않은 서비스코드도 PG 는 파일을 가져가고 FIN 을 올린다. 기록은 ZONE_CODE='NO',
    ...    STATUS='F', REASON='Err ZoneCode', FILESIZE=0 이다(dev 실측 행과 같은 형태).
    [Tags]    cms    db    negative
    ${case}=    Send CMS NTI    service_code=${CMS_SERVICE_CODE_UNREG}
    PG Should Upload CMS FIN    ${case}
    Verify CMSWEB Zone Row In PDB    ${case}    ${CMS_STATUS_FAILED}    ${CMS_REASON_ZONE}
    ...    file_size=${0}    zone_code=NO    service_code=${CMS_SERVICE_CODE_UNREG}

# ════════════════════════════════════════════════════════════════
# 세션 관리
# ════════════════════════════════════════════════════════════════

TC-CMS-010 REG_NOK → PG 재접속 후 REG 재수신
    [Documentation]    REG_NOK 를 받으면 PG 가 연결을 닫고 다시 접속해 REG 를 보낸다(약 10초 주기).
    [Tags]    cms    reg    negative
    Reject PG Registration
    Restore CMS Session
    REG Should Carry PG Session Key
    [Teardown]    Run Keyword If Test Failed    Run Keyword And Ignore Error    Restore CMS Session

TC-CMS-011 무수신 → CMSWEB_TIMEOUT 뒤 PG 종료 후 재접속
    [Documentation]    도구가 아무것도 보내지 않으면 PG 가 CMSWEB_TIMEOUT(dev 900초) 뒤 연결을 닫고 다시 접속한다.
    [Tags]    cms    reg    slow
    Wait PG Idle Disconnect
    Restore CMS Session
    REG Should Carry PG Session Key
    [Teardown]    Run Keyword If Test Failed    Run Keyword And Ignore Error    Restore CMS Session
