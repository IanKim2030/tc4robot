*** Settings ***
Documentation
...    CMSWEB 시뮬레이터 변수 — 도구가 SKT 통합 구성관리 시스템(CMSWEB) 서버 역할을 한다.
...
...    PG.CMS(CmsMain, 프로세스명 CMS201)가 PG_V2.cfg [CMS] CMSWEB_ADDR:CMSWEB_PORT 로
...    접속해 온다. ★ 표시 값은 기동 시 PG_V2.cfg [CMS] 에서 읽어 덮는다
...    (config/remote_settings.json, run_tests.sh cms). 여기 값은 dev(141) 실측 기본값이다.
...    근거: CMS 연동 규격서 v1.9 + PG 소스 Online/CMS.vGL.SFTP/CCMSWeb.cpp — tests/cms/SPEC.md


*** Variables ***
# ════════════════════════════════════════════
# 접속 — 도구가 Listen, PG.CMS 가 접속
# ════════════════════════════════════════════
${CMS_LISTEN_HOST}         0.0.0.0
${CMS_LISTEN_PORT}         9980                   # ★ [CMS] CMSWEB_PORT
${CMS_ALLOWED_PEER_IPS}    ${PG_HOST}             # 이 IP 에서 온 접속만 받는다
${CMS_ACCEPT_TIMEOUT}      40                     # PG 재접속 주기(약 10초)보다 넉넉히
${CMS_RECV_TIMEOUT}        10

# PG 가 접속하려는 주소 — 도구 호스트(${TOOL_HOST})여야 시험이 성립한다.
${CMS_PG_TARGET_ADDR}      ${EMPTY}               # ★ [CMS] CMSWEB_ADDR (비면 확인 생략)

# PG.CMS 세션키 — REG/HBC/ANS 의 sourceSessionKey 로 온다.
${CMS_PG_GROUP}            PGN                    # ★ [CMS] GROUP
${CMS_PG_KEY}              PGN99                  # ★ [CMS] KEY
${CMS_PG_TIMEOUT}          900                    # ★ [CMS] CMSWEB_TIMEOUT — 무수신 시 PG 가 끊는 초
${CMS_PG_USE_SFTP}         Y                      # ★ [CMS] CMSWEB_SFTP — 'N' 이면 FTP, 그 밖(없음 포함)은 SFTP

# 도구(CMSWEB) 자신의 세션키 / messageId GROUP(3자리)
${CMS_SRC_GROUP}           CMS
${CMS_SRC_KEY}             CMS
${CMS_MSG_ID_GROUP}        CMS
${CMS_PROCESS}             CMS201                 # .RUN touch 대상 (ST.cfg 이름)

# ════════════════════════════════════════════
# 파일 서버 — 도구가 다운로드 서버, PG.CMS 가 GET 한다
# ════════════════════════════════════════════
# 프로토콜은 기동 시 ${CMS_PG_USE_SFTP}([CMS] CMSWEB_SFTP)로 정한다 — PG 와 같이 'N' 이면 FTP.
${CMS_SFTP_HOST}           0.0.0.0
${CMS_SFTP_PORT}           2322                   # ★ [CMS] CMS_SFTP_PORT (없으면 PG 기본 22) — SFTP 모드
# FTP 모드 — PG 소스(RunFtpCMS)가 FTP_PORT=21 을 **고정**으로 쓴다(cfg 키 없음).
# 142 의 일반 계정은 1024 미만 포트를 못 연다 → root 로 돌리거나, 21 을 다른 포트로
# 리다이렉트하고 --variable CMS_FTP_PORT:<포트> 로 맞춘다.
${CMS_FTP_HOST}            0.0.0.0
${CMS_FTP_PORT}            21
${CMS_FTP_PASSIVE_PORTS}   ${EMPTY}               # 예: 60000-60050 (비우면 pyftpdlib 임의 포트)
# 계정은 SFTP/FTP 공통(CMSWEB 다운로드 계정). 비밀번호는 환경변수 PG_PWD_CMS_SFTP 로만 받는다.
${CMS_SFTP_USER}           ${EMPTY}               # 환경 파일에서 채운다(dev: pg)
# NTI COLUMN_DATA 의 디렉터리. 시뮬레이터 가상 루트에 만들고(GET), PG 의 FIN 은 도구 호스트
# 실제 파일시스템의 같은 절대 경로로 간다 — 그래서 실제 FIN 계정이 쓸 수 있어야 한다.
# 근거(2026-11-24, 142 조회): pg:x:500:500::/PG, /PG/FTP/CMS = pg:pg drwxr-xr-x(비어 있음).
${CMS_REMOTE_DIR}          /PG/FTP/CMS
${CMS_FILE_BYTES}          128                    # 샘플 파일이 없을 때 만드는 시험 파일 크기(바이트)
# 실제 샘플 파일 디렉터리 — <serviceCode>.dat 가 있으면 그 파일을 그대로 올리고 크기도 실제 크기를 쓴다.
${CMS_DATA_DIR}            ${CURDIR}/../tests/cms/data
${CMS_FIN_TIMEOUT}         30                     # NTI 후 FIN 업로드까지 대기(초)
${CMS_QUIET_WINDOW}        10                     # "안 일어나야 하는" 판정의 관찰 시간(초)

# ════════════════════════════════════════════
# FIN — PG.CMS 가 GET 성공 후 빈 .FIN 을 PUT 한다
# ════════════════════════════════════════════
# sshd      : 실제 PG 동작. CCMSWeb.cpp RunSFtpCMS 의 SFTPUploader 는 .port() 를 주지 않아
#             SFTP 기본 22(도구 호스트의 실제 sshd)로 올린다. 슈트는 그 sshd 에 SFTP 로 붙어 확인한다.
# simulator : FIN 도 시뮬레이터 SFTP 로 오는 경우(포트를 고친 PG, 가짜 PG).
# ※ FTP 모드(CMSWEB_SFTP=N)는 FIN 을 GET 과 같은 FTP 세션으로 올리므로 기동 시 simulator 로 바뀐다.
${CMS_FIN_MODE}            sshd
${CMS_FIN_SSH_HOST}        127.0.0.1              # 슈트가 도구 호스트(142)에서 돈다 — PG 는 CMSWEB_ADDR:22 로 올린다
${CMS_FIN_SSH_PORT}        22                     # SFTP 기본 포트(DEV/Common SFTPCurlBase.h)
# PG 는 GET 과 FIN PUT 에 같은 CMSWEB 계정(userId_/passWd_)을 쓴다. 슈트의 확인용 비밀번호는
# 환경변수 PG_PWD_CMS_FIN_SSH(도구 호스트 실제 pg 계정) — 없으면 PG_PWD_CMS_SFTP(같은 값, dev 142 확인).
${CMS_FIN_SSH_USER}        ${CMS_SFTP_USER}
${CMS_FIN_CLEANUP}         ${FALSE}               # 기본은 남긴다. ${TRUE} 면 Suite Teardown 이 이번 실행의 FIN 만 지운다

# ════════════════════════════════════════════
# SC(NWDAF) 전달 — SC_FTP_YN='Y' 서비스코드면 PG 가 받은 파일과 .FIN 을 다시 올린다
# ════════════════════════════════════════════
# CCMSWeb::RunSFtpSC — sftp://[SC] SC_PRIIP:[CMS] NWDAF_SFTP_PORT[CMS] SC_PATH/<파일>, 계정 scUserId_.
# NWDAF_SFTP 가 'N' 이면 RunFtpSC — ftp://SC_PRIIP:[CMS] NWDAF_FTP_PORT, CWD SC_PATH 후 PUT(같은 계정).
# dev(141 PG_V2.cfg, 2026-11-24 조회): SC_PRIIP=192.168.15.142, NWDAF_SFTP=Y, NWDAF_SFTP_PORT=32001,
# SC_PATH=/PG/FTP/CMS (중복 키는 마지막 값).
${CMS_SC_SFTP_HOST}        0.0.0.0
${CMS_SC_SFTP_PORT}        32001                  # ★ [CMS] NWDAF_SFTP_PORT (없으면 PG 기본 22)
${CMS_SC_FTP_PORT}         21                     # ★ [CMS] NWDAF_FTP_PORT (없으면 PG 기본 21) — FTP 모드
${CMS_SC_FTP_PASSIVE_PORTS}    ${EMPTY}
${CMS_SC_PG_ADDR}          ${EMPTY}               # ★ [SC] SC_PRIIP — ${TOOL_HOST} 여야 한다(비면 확인 생략)
${CMS_SC_USE_SFTP}         Y                      # ★ [CMS] NWDAF_SFTP — 'N' 이면 FTP, 그 밖은 SFTP
${CMS_SC_PATH}             /PG/FTP/CMS            # ★ [CMS] SC_PATH — PG 가 올리는 절대 경로(가상 경로)
# SC_PATH 를 이 실제 디렉터리로 받는다. 비면 임시 디렉터리. dev 는 환경 파일에서 채운다.
${CMS_SC_UPLOAD_DIR}       ${EMPTY}
# 비밀번호는 환경변수 PG_PWD_CMS_SFTP_UPLOAD 로만 받는다.
${CMS_SC_SFTP_USER}        pg
${CMS_SC_TIMEOUT}          60                     # NTI 후 SC 업로드 두 파일까지 대기(초) — GET·FIN 뒤에 온다
${CMS_SC_CLEANUP}          ${FALSE}               # 기본은 SC 로 올라온 데이터 파일·FIN 을 남긴다. ${TRUE} 면 이번 실행 것만 지운다

# ════════════════════════════════════════════
# 서비스코드 / PDB
# ════════════════════════════════════════════
# 기본 서비스코드(필드 누락 시험 등). 시드가 T_ZONE_LIST 에 SC_FTP_YN=N, NOTI_YN=Y 로 넣는다.
${CMS_SERVICE_CODE}        TRAP_ROBOT_ZONE_TEST
# T_ZONE_LIST 에 없는 서비스코드 — PG 가 ZONE_CODE='NO', STATUS='F' 로 기록한다.
${CMS_SERVICE_CODE_UNREG}    TRAP_ROBOT_ZONE_UNREG
# 실제 코드 목록 — Suite Setup 이 시작 전에 각 코드의 T_ZONE_LIST 값(SC_FTP_YN 등)을 조회해 보여 준다(막지 않는다).
# PG 는 조회 전에 마지막 '_V..' 를 뗀다(deleteVersion) — 버전 붙은 코드를 넣어도 조회 키는 PG 와 같다.
# NTI 정상 세트 서비스코드는 TC 에 고정돼 있다(TC-003~005 TRAP_LTE_EQP_INFO, TC-006~008 TRAP_5G_EQP_INFO).
# 이 목록은 시작 전 조회·표시용이다 — TC 의 코드를 바꾸면 여기도 맞춘다. 슈트는 T_ZONE_LIST 를 INSERT/UPDATE 하지 않는다.
@{CMS_SERVICE_CODES_SC}    TRAP_LTE_EQP_INFO    TRAP_5G_EQP_INFO
# T_CMSWEB_ZONE 기록 시험 전용 코드(TC 에 고정) — config/db_seed/dev.sql 이 이 두 코드만 T_ZONE_LIST 에 넣는다.
#   TRAP_ROBOT_ZONE_TEST   SC_FTP_YN=N NOTI_YN=Y ZN999999 (C/OK)
#   TRAP_ROBOT_ZONE_NOTI_N SC_FTP_YN=N NOTI_YN=N ZN999997 (F/Err ZoneCode)
@{CMS_SERVICE_CODES_ROBOT}    TRAP_ROBOT_ZONE_TEST    TRAP_ROBOT_ZONE_NOTI_N
${CMS_ZONE_SHOW}           ${TRUE}                # ${FALSE} 면 시작 전 T_ZONE_LIST 조회를 건너뛴다(PDB 없는 가짜 PG 시험)

${CMS_DB_TBL_ZONE}         T_CMSWEB_ZONE
${CMS_DB_SQL_ZONE_BY_MSG}    SELECT ZONE_CODE, FILE_TYPE, SERVICE_CODE, FILENAME, STATUS, REASON, FILESIZE FROM T_CMSWEB_ZONE WHERE MSG_ID = ?
${CMS_DB_SQL_ZONE_LIST}    SELECT SERVICE_CODE, ZONE_CODE, SC_FTP_YN, NOTI_YN FROM T_ZONE_LIST WHERE SERVICE_CODE = ?
# 이번 실행에서 보낸 NTI 의 MSG_ID 행만 지운다 — 실제 코드의 운용 행은 건드리지 않는다.
${CMS_DB_SQL_CLEANUP}      DELETE FROM T_CMSWEB_ZONE WHERE MSG_ID = ?
${CMS_DB_WAIT}             30s
${CMS_DB_WAIT_INTERVAL}    2s
${CMS_CLEANUP_ON_TEARDOWN}    ${TRUE}

# PG 상태 코드 (CCMSWeb::setFileStatus)
${CMS_STATUS_APPLIED}      C                      # 정상 수집 — REASON 'OK'
# 정상 수집 판정에 허용하는 STATUS — PG 는 'C' 로 넣지만 ZONE 프로세스가 곧 'E' 로
# 바꿀 수 있다(dev 실측: 정상 행이 'E'/'OK' 로 남아 있다).
@{CMS_STATUS_OK}           C    E
${CMS_STATUS_FAILED}       F                      # 'Err ZoneCode' / 'Err Get File' …
${CMS_STATUS_WAITING}      W                      # 크기 0/불일치 — REASON 'Waiting State'
${CMS_REASON_OK}           OK
${CMS_REASON_ZONE}         Err ZoneCode
${CMS_REASON_WAITING}      Waiting State
