*** Settings ***
Documentation
...    UPM 인터페이스 변수 (접속 정보 / 메시지 타입 / code-type / 테스트 데이터)
...
...    HFC 가입자 Cell List 연동. PG = Server, UPM = Client.
...    ${UPM_TEST_*} 는 실환경 PG/PDB 와 매칭되는 값으로 교체해야 한다.

*** Variables ***

# ════════════════════════════════════════════
# UPM PG 접속 정보 (클라이언트 모드, Port 10506)
# PG = Server, UPM = Client (HFC 가입자 Cell List 연동)
# ════════════════════════════════════════════
${UPM_PG_HOST}         ${PG_HOST}
${UPM_PG_PORT}         10506            # 규격서 10. 서비스 접속 정보
${UPM_TIMEOUT}         10
${UPM_SYS_ID}          UPM-R0          # sys-id 필드, 32자 이내 (Peer Name).
${UPM_BRANCH_NAME}     SS               # SS=성수, DS=둔산, BR=보라매
${UPM_HELLO_TIMEOUT}   5                # 규격서 3.1: 연결 후 5초 이내 Hello 송신

# ════════════════════════════════════════════
# UPM FTP 수신 서버 (0x0c Subs-Sync-Response 의 fileinfo 대응)
#
# 규격 6.6.1/6.6.2 는 0x0c 응답에 "fileinfo 포함 가능"이라고만 적혀 있다. **fileinfo
# 필드 자체의 스키마**(파일명/크기 등)는 여전히 ⚠ 미확인이지만, **FTP 접속
# 정보는 PG 쪽 FTP 타겟 설정으로 확인됐다**(2026-10-22, SYSTEM_ID_04=UPM-R0 항목 — 2026-10-28 UPMROB 에서 변경
# — 이 값이 ${UPM_SYS_ID}와 일치해 우리 쪽 항목임을 확인):
#   IP_04=192.168.15.142  PORT_04=2121  USER_ID_04=upm  PASSWORD_04=upm (2026-10-28 upm1234 에서 변경)
#   REMOTE_PATH_04=/PG/FTP/UPM-ROBOT  LOCAL_PATH_04=/PG/FTP/UPM  USE_SFTP_04=N
# "PG 가 UPM 으로 파일을 보낸다"는 PG 가 FTP Client 로 붙어 Push 한다는 뜻이었고
# (사용자 확인), 도구가 FTP **서버** 역할을 하는 것도 이 설정으로 확정됐다.
# host/port/계정/디렉터리는 fileinfo 내용과 무관하게 **여기서 고정**한다 —
# fileinfo 를 파싱해 접속 정보를 derive 하지 않는다.
# 끄려면: bash run_tests.sh upm --no-ftp (pyftpdlib 설치 없이도 슈트가 돈다)
# ════════════════════════════════════════════
${UPM_FTP_ENABLE}        ${TRUE}      # FTP(또는 SFTP) 수신 서버 기동 여부
${UPM_FTP_USE_SFTP}      ${FALSE}     # PG 설정 USE_SFTP_04 — 확인된 값은 N(평문 FTP, 2026-10-22).
${UPM_FTP_HOST}          0.0.0.0      # 모든 인터페이스 Listen (PG 는 IP_04=192.168.15.142 로 접속)
${UPM_FTP_PORT}          2121         # PG 설정 PORT_04 와 일치 확인(2026-10-22)
${UPM_FTP_USER}          upm          # PG 설정 USER_ID_04 와 일치 확인(2026-10-22, 로그인 시도 로그로 재확인)
${UPM_FTP_PASSWORD}      upm          # PG 설정 PASSWORD_04 와 일치 확인(2026-10-22)
${UPM_FTP_HOME_DIR}      ${EMPTY}     # 비우면 임시 디렉터리를 자동 생성(FtpServerHelper.py)
${UPM_FTP_REMOTE_PATH}   /PG/FTP/UPM-ROBOT   # PG 설정 REMOTE_PATH_04 — 로그인 후 CWD 로 들어오는 경로.
# FtpServerHelper.py 가 업로드 디렉터리 밑에 이 경로를 미리 만들어 둔다(없으면 CWD 가 550 으로 거부됨).
${UPM_FTP_WAIT}          30s          # 0x0c에 fileinfo 있을 때 파일 수신 대기 시간

# 전송 파일은 **2개**다(사용자 확인, 2026-10-22) — 데이터 파일 + "FIN" 파일
# (전송 완료를 알리는 트리거 파일, 레거시 배치 전송에서 흔한 관례). 어느 쪽이
# FIN 인지 구분하는 기준은 ⚠ 추정이다 — 파일명에 이 패턴(대소문자 무관)이
# 포함되면 FIN 으로 본다. 실제 명명 규칙이 확인되면 이 값만 고치면 된다.
${UPM_FTP_FIN_PATTERN}   FIN

# PG 와 도구 사이에 NAT/방화벽이 있으면 pyftpdlib 가 임의로 고르는 PASV 포트가
# 막혀 STOR 가 실패할 수 있다. 비워 두면(기본) pyftpdlib 기본 동작(임의 포트)을 쓴다.
# ※ FTP 전용이다 — ${UPM_FTP_USE_SFTP}=True 면 SFTP 는 SSH 단일 채널이라
#   PASV 개념이 없어 이 둘은 무시된다.
${UPM_FTP_PASSIVE_PORTS}      ${EMPTY}     # 예: 60000-60050
${UPM_FTP_MASQUERADE_ADDR}    ${EMPTY}     # PASV 응답에 실을 "도구가 PG 쪽에서 보이는 주소"

# ════════════════════════════════════════════
# UPM 전용 메시지 타입 (HFC 가입자 Cell List 연동, 헤더 Byte1)
# ════════════════════════════════════════════
${MSG_UPM_SUBS_CHANGE_REQ}    ${5}     # 0x05  PG → UPM (번호 변경 NOTI)
${MSG_UPM_SUBS_CHANGE_RESP}   ${6}     # 0x06  UPM → PG
${MSG_UPM_SUBS_INFO_REQ}      ${7}     # 0x07  PG → UPM (가입자 Cell Info 요청)
${MSG_UPM_SUBS_INFO_RESP}     ${8}     # 0x08  UPM → PG
${MSG_UPM_CELLINFO_NOTI_REQ}  ${9}     # 0x09  UPM → PG (변경 Cell Info NOTI)
${MSG_UPM_CELLINFO_NOTI_RESP}  ${10}   # 0x0a  PG → UPM
${MSG_UPM_SUBS_SYNC_REQ}      ${11}    # 0x0b  UPM → PG (전체 동기화 요청)
${MSG_UPM_SUBS_SYNC_RESP}     ${12}    # 0x0c  PG → UPM
${MSG_UPM_INFO_CHANGE_REQ}    ${13}    # 0x0d  PG → UPM (상품/Device 변경)
${MSG_UPM_INFO_CHANGE_RESP}   ${14}    # 0x0e  UPM → PG

# ════════════════════════════════════════════
# UPM code-type (규격서 9. 공통 필드 정의)
# ════════════════════════════════════════════
${UPM_CT_SUBSCRIBE}        01      # HFC 서비스 가입
${UPM_CT_CELL_CHANGE}      02      # Cell List 변경
${UPM_CT_TERMINATE}        03      # HFC 서비스 해지
${UPM_CT_MDN_CHANGE}       04      # 가입자 번호 변경
${UPM_CT_SYNC_ALL}         05      # 전체 가입자 정보 요청 (동기화)
${UPM_CT_INFO_CHANGE}      06      # 가입자 상품/Device 변경

# ════════════════════════════════════════════
# UPM msg-type (Body JSON 내 필드, Header 의 msg_type 과 별개)
# ════════════════════════════════════════════
${UPM_MT_CDS}              01      # CDS 수신
${UPM_MT_NOTI}             02      # 변경 가입자 NOTI

# ════════════════════════════════════════════
# UPM result-code / Hello code (규격서 9.)
# ════════════════════════════════════════════
${UPM_RC_SUCCESS}          SC0000  # 성공
${UPM_RC_FAIL}             FA0000  # 실패
${UPM_HELLO_CODE_OK}       ${200}
${UPM_HELLO_CODE_BAD_VER}  ${400}
${UPM_HELLO_CODE_FAILOVER}  ${9999} # UPM 미접속 / 종료 시 PG 가 반환

# ════════════════════════════════════════════
# UPM 테스트 데이터 (HFC 가입자)
# TODO: 실환경 PG/PDB 와 매칭되는 값으로 교체
# ════════════════════════════════════════════
${UPM_TEST_MDN}            01090010001
${UPM_TEST_SERVICE_ID}     ZN100001
${UPM_TEST_DEVICE_TYPE}    S                  # W=3G, L=LTE, N=NSA, S=SA
${UPM_TEST_PRODUCT_TYPE}   03                 # 01=3G, 02=LTE, 03=5G
${UPM_TEST_CELL_INFO}      9999:99
${UPM_TEST_TA_CODE}        11111
${UPM_TEST_ADDR}           서울시 강남구 청담동 77 1
#${UPM_TEST_ADDR_SI}        서울시
#${UPM_TEST_ADDR_GU}        강남구
#${UPM_TEST_ADDR_DONG}      청담동
#${UPM_TEST_ADDR_BUNJI1}    77
#${UPM_TEST_ADDR_BUNJI2}    1
