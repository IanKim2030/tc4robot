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
${UPM_PG_HOST}         192.168.15.141
${UPM_PG_PORT}         10506            # 규격서 10. 서비스 접속 정보
${UPM_TIMEOUT}         10
${UPM_SYS_ID}          UPMSIM           # 5자리 이내 Peer Name
${UPM_BRANCH_NAME}     DS               # SS=성수, DS=둔산, BR=보라매
${UPM_HELLO_TIMEOUT}   5                # 규격서 3.1: 연결 후 5초 이내 Hello 송신

# ════════════════════════════════════════════
# UPM 전용 메시지 타입 (HFC 가입자 Cell List 연동, 헤더 Byte1)
# ════════════════════════════════════════════
${MSG_UPM_SUBS_CHANGE_REQ}    ${5}     # 0x05  PG → UPM (번호 변경 NOTI)
${MSG_UPM_SUBS_CHANGE_RESP}   ${6}     # 0x06  UPM → PG
${MSG_UPM_SUBS_INFO_REQ}      ${7}     # 0x07  PG → UPM (가입자 Cell Info 요청)
${MSG_UPM_SUBS_INFO_RESP}     ${8}     # 0x08  UPM → PG
${MSG_UPM_CELLINFO_NOTI_REQ}  ${9}     # 0x09  UPM → PG (변경 Cell Info NOTI)
${MSG_UPM_CELLINFO_NOTI_RESP}  ${10}    # 0x0a  PG → UPM
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
${UPM_TEST_MDN}            01053543393
${UPM_TEST_MDN_NEW}        01053543333        # 번호 변경 후 신규 MDN
${UPM_TEST_SERVICE_ID}     ZN100001
${UPM_TEST_DEVICE_TYPE}    S                  # W=3G, L=LTE, N=NSA, S=SA
${UPM_TEST_PRODUCT_TYPE}   03                 # 01=3G, 02=LTE, 03=5G
${UPM_TEST_CELL_INFO}      9999:99
${UPM_TEST_TA_CODE}        11111
${UPM_TEST_ADDR}           서울시 강남구 청담동 77 1
${UPM_TEST_ADDR_SI}        서울시
${UPM_TEST_ADDR_GU}        강남구
${UPM_TEST_ADDR_DONG}      청담동
${UPM_TEST_ADDR_BUNJI1}    77
${UPM_TEST_ADDR_BUNJI2}    1
