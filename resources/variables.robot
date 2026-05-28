*** Settings ***
Documentation    PG 연동 통합 테스트 공통 변수 (NAG / PCF / LRS / UPM)

*** Variables ***

# ════════════════════════════════════════════
# NAG PG 접속 정보 (클라이언트 모드, Port 8012)
# ════════════════════════════════════════════
${NAG_PG_HOST}         192.168.15.141
${NAG_PG_PORT}         8012
${NAG_TIMEOUT}         10
${NAG_SYS_ID}          NAG01
${NAG_BRANCH_NAME}     BR

# ════════════════════════════════════════════
# PCF PG 접속 정보 (클라이언트 모드, Port 8011)
# ════════════════════════════════════════════
${PCF_PG_HOST}         192.168.15.141
${PCF_PG_PORT}         8011
${PCF_TIMEOUT}         10
${PCF_SYS_ID}          LTE-PCRF01
${PCF_BRANCH_NAME}     SS

# ════════════════════════════════════════════
# UPM PG 접속 정보 (클라이언트 모드, Port 10506)
# PG = Server, UPM = Client (HFC 가입자 Cell List 연동)
# ════════════════════════════════════════════
${UPM_PG_HOST}         192.168.15.141
${UPM_PG_PORT}         10506            # 규격서 10. 서비스 접속 정보
${UPM_TIMEOUT}         10
${UPM_SYS_ID}          UPM01            # 5자리 이내 Peer Name
${UPM_BRANCH_NAME}     BR               # SS=성수, DS=둔산, BR=보라매
${UPM_HELLO_TIMEOUT}   5                # 규격서 3.1: 연결 후 5초 이내 Hello 송신

# ════════════════════════════════════════════
# LRS 서버 정보 (서버 모드, Port 8890)
# 테스트 도구가 PCRF/PCF 역할로 Listen
# LRS(PG)가 접속하면 TC 진행
# ════════════════════════════════════════════
${LRS_SERVER_HOST}        0.0.0.0    # 모든 인터페이스 Listen
${LRS_SERVER_PORT}        8890       # 규격서 고정값
${LRS_ACCEPT_TIMEOUT}     30         # LRS(PG) 접속 대기 최대 시간(초)
${LRS_MSG_TIMEOUT}        10         # 메시지 수신 최대 대기 시간(초)

# LRS(PG)가 Hello에 실어 보내는 식별값 (검증용)
${LRS_EXPECTED_SYS_ID}      PG11
# TODO: 실환경 LRS(PG)의 BRANCH_NAME (2자리: SS=성수, DS=둔산)
${LRS_EXPECTED_BRANCH_NAME}    SS

# Hello-Response에 내려줄 Ping 주기(초)
${LRS_RESP_INTERVAL}        30

# ════════════════════════════════════════════
# 메시지 타입 상수 (헤더 Byte1)
# ════════════════════════════════════════════
# NAG / PCF / LRS 공통
${MSG_HELLO_REQ}              ${1}     # 0x01
${MSG_HELLO_RESP}             ${2}     # 0x02
${MSG_PING_REQ}               ${3}     # 0x03
${MSG_PING_RESP}              ${4}     # 0x04

# PCF 전용 (Zone-InOut)
${MSG_PCF_ZONE_REQ}           ${5}     # 0x05  PCF → PG
${MSG_PCF_ZONE_RESP}          ${6}     # 0x06  PG → PCF

# NAG 전용
${MSG_ZION_REQ}               ${7}     # 0x07  PG → NAG (수신)
${MSG_ZION_RESP}              ${8}     # 0x08  NAG → PG
${MSG_SUBS_ZONE_STATUS_REQ}   ${9}     # 0x09  NAG → PG
${MSG_SUBS_ZONE_STATUS_RESP}  ${10}    # 0x0a  PG → NAG
${MSG_SUBS_CELLID_REQ}        ${11}    # 0x0b  NAG → PG (ADOT)
${MSG_SUBS_CELLID_RESP}       ${12}    # 0x0c  PG → NAG (ADOT)

# LRS 전용 (Location-Info)
${MSG_LOC_INFO_REQ}           ${5}     # 0x05  LRS(PG) → PCRF/PCF (수신)
${MSG_LOC_INFO_RESP}          ${6}     # 0x06  PCRF/PCF → LRS(PG) (송신)

# UPM 전용 (HFC 가입자 Cell List 연동)
${MSG_UPM_SUBS_CHANGE_REQ}    ${5}     # 0x05  PG → UPM (번호 변경 NOTI)
${MSG_UPM_SUBS_CHANGE_RESP}   ${6}     # 0x06  UPM → PG
${MSG_UPM_SUBS_INFO_REQ}      ${7}     # 0x07  PG → UPM (가입자 Cell Info 요청)
${MSG_UPM_SUBS_INFO_RESP}     ${8}     # 0x08  UPM → PG
${MSG_UPM_CELLINFO_NOTI_REQ}  ${9}     # 0x09  UPM → PG (변경 Cell Info NOTI)
${MSG_UPM_CELLINFO_NOTI_RESP} ${10}    # 0x0a  PG → UPM
${MSG_UPM_SUBS_SYNC_REQ}      ${11}    # 0x0b  UPM → PG (전체 동기화 요청)
${MSG_UPM_SUBS_SYNC_RESP}     ${12}    # 0x0c  PG → UPM
${MSG_UPM_INFO_CHANGE_REQ}    ${13}    # 0x0d  PG → UPM (상품/Device 변경)
${MSG_UPM_INFO_CHANGE_RESP}   ${14}    # 0x0e  UPM → PG

# ════════════════════════════════════════════
# NAG/PCF 응답 코드
# ════════════════════════════════════════════
${CODE_SUCCESS}               ${200}
${CODE_SUCCESS_WITH_INFO}     ${201}
${CODE_UNSUPPORT_MSG}         ${400}
${CODE_UNEXPECTED_DATA}       ${401}
${CODE_NOT_FOUND_SS}          ${402}    # HFC 미가입 (NAG)
${CODE_NOT_FOUND_SESSION}     ${403}    # 세션 없음 (NAG)
${CODE_RETRY_AFTER}           ${429}    # 과부하 (NAG)
${CODE_INTERNAL_ERROR}        ${500}
${CODE_PEER_NODE_DOWN}        ${502}    # Peer 연결 없음 (NAG)
${CODE_SERVICE_UNAVAILABLE}   ${503}
${CODE_GATEWAY_TIMEOUT}       ${504}    # T-Server Timeout (NAG)
${CODE_HAVE_TO_FAILOVER}      ${9999}

# ════════════════════════════════════════════
# LRS RESULT_CODE (규격서 3.2.8)
# ════════════════════════════════════════════
${LRS_CODE_SUCCESS}            0       # 성공
${LRS_CODE_INTERNAL_ERROR}     100     # 내부 처리 Error
${LRS_CODE_SESSION_NOT_FOUND}  200     # 세션 Not Found
${LRS_CODE_PGW_RAA_TIMEOUT}    300     # PGW RAA Timeout
${LRS_CODE_PGW_RAA_ERROR}      400     # PGW RAA Error Code
${LRS_CODE_RAR_DUPLICATE}      500     # RAR 중복 전송 한도 초과
${LRS_CODE_FAILOVER}           9999    # 내부 RM 단절 / Active→Standby 절체

# ════════════════════════════════════════════
# NAG/PCF 테스트 데이터
# ════════════════════════════════════════════
${TEST_MDN_NORMAL}        01020300553
${TEST_MDN_NO_SS}         00000000000    # HFC 미가입 → code=402
${TEST_MDN_NO_SESSION}    99999999999    # 세션 없음 → code=403
${TEST_MOBILE_IP}         2001:0d88:131f:0000::/64
${TEST_CELL_INFO}         9999:99
${TEST_APN}               lte.sktelecom.com
${TEST_CLIENT_HOST}       ltepgw01.sktelecom.com

# ════════════════════════════════════════════
# LRS Location-Info-Request 테스트 데이터
# 도구 → LRS(PG) 방향
# TODO: 실환경 LRS(PG)가 처리 가능한 값으로 교체
# ════════════════════════════════════════════
${LRS_SYS_ID}              PG01            # TODO: 실환경 SYS_ID
${LRS_BRANCH_NAME}         SS              # TODO: 실환경 BRANCH_NAME

# LTE 정상 세션 (PDB T_SESSION_INFO_XX 에 존재하는 MDN)
${LRS_MDN_LTE}             01012345678     # TODO: 실환경 LTE 정상 MDN
${LRS_DST_HOST_LTE}        ltepcrf01       # TODO: T_SESSION_INFO_XX.DESTINATION_HOST
${LRS_APN_LTE}             lte.sktelecom.com
${LRS_SVC_ID_LTE}          000001

# 5G 정상 세션 (PDB T_PCF_BINDNG_INFO 에 존재하는 MDN, SBI → SERVICE_ID 미전송)
${LRS_MDN_5G}              01012345678     # TODO: 실환경 5G 정상 MDN
${LRS_DST_HOST_5G}         pcrf01-mp01-app06  # TODO: T_SMF_SESSION_INFO.NODE_ID
${LRS_APN_5G}              5g.sktelecom.com

# 세션 없는 MDN → RESULT_CODE=200 기대
${LRS_MDN_NO_SESSION}      00000000000     # TODO: PDB에 세션이 없는 MDN

# ════════════════════════════════════════════
# LRS Location-Info-Response 기대 필드값 검증용
# TODO: 실환경 응답값으로 교체
# ════════════════════════════════════════════
${LRS_MOCK_CELL_INFO_LTE}      1048575:63
${LRS_MOCK_CELL_INFO_5G}       4194303:16383
${LRS_MOCK_CELL_INFO_ROAMING}  45008-1048575:255

${LRS_MOCK_TA_CODE_LTE}        3113
${LRS_MOCK_TA_CODE_5G}         6000F0

${LRS_MOCK_NET_TP_LTE}         L
${LRS_MOCK_NET_TP_5G}          S
${LRS_MOCK_NET_TP_3G}          W

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
${UPM_HELLO_CODE_FAILOVER} ${9999} # UPM 미접속 / 종료 시 PG 가 반환

# ════════════════════════════════════════════
# UPM 테스트 데이터 (HFC 가입자)
# TODO: 실환경 PG/PDB 와 매칭되는 값으로 교체
# ════════════════════════════════════════════
${UPM_TEST_MDN}            01012345678
${UPM_TEST_MDN_NEW}        01087654321        # 번호 변경 후 신규 MDN
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

# ════════════════════════════════════════════
# NWDAF PG 접속 정보 (클라이언트 모드)
# 방향: NWDAF → PG (Notification 주력, 응답 사실상 없음)
# Body 구조: COMMON1 + (pcefQoSCtrl|enodebQoSCtl) + COMMON2
#            전체를 MULTI_MESSAGE(0xFF) TLV 로 감싼다.
# TODO: 실환경 NWDAF 서비스 IP/Port 확인 후 교체
# ════════════════════════════════════════════
${NWDAF_HOST}             192.168.15.141
${NWDAF_PORT}             10305
${NWDAF_TIMEOUT}          10

# ════════════════════════════════════════════
# NWDAF Header — Message Type (Byte0 하위 3bit)
# ════════════════════════════════════════════
${NWDAF_MT_REQ}           ${1}        # 0b001 Request
${NWDAF_MT_RESP}          ${4}        # 0b100 Response
${NWDAF_MT_NOTI}          ${2}        # 0b010 Notification ← NWDAF 주력

# ════════════════════════════════════════════
# NWDAF Service Id (Header Byte1-2)
# 규격이 QOS_CONTROL_TYPE=0x01(가입자 단위) 하나만 정의하므로 0x0305 주 사용.
# ════════════════════════════════════════════
${NWDAF_SID_SUBSCRIBER}   ${773}      # 0x0305 가입자 단위 QoS 제어

# ════════════════════════════════════════════
# PCEF_TYPE (TAG 0x0D) — 규격 1.1
# QoSHDR 묶음 분기에 사용. QOS_HDR(0x3A) flag 값과 동일.
# ════════════════════════════════════════════
${NWDAF_PCEF_PGW}         ${1}        # 0x01 P-GW / SMF → pcefQoSCtrl
${NWDAF_PCEF_ENB}         ${16}       # 0x10 eNB        → enodebQoSCtl

# ════════════════════════════════════════════
# QOS_CONTROL_TYPE (TAG 0x0E) — 규격 1.2
# ════════════════════════════════════════════
${NWDAF_QCT_SUBSCRIBER}   ${1}        # 0x01 가입자 단위 (현재 규격 정의된 유일 값)

# ════════════════════════════════════════════
# NETWORK (TAG 0x1F) — 규격 4.1
# ════════════════════════════════════════════
${NWDAF_NET_2G}           ${0}        # 0x00
${NWDAF_NET_WCDMA}        ${1}        # 0x01
${NWDAF_NET_LTE}          ${2}        # 0x02
${NWDAF_NET_5G}           ${3}        # 0x03

# ════════════════════════════════════════════
# CONTROL_UNIT (TAG 0x40, numeric) — 규격 4.2
# ════════════════════════════════════════════
${NWDAF_CU_CELL}          ${48}       # 0x31
${NWDAF_CU_ENODEB}        ${2}
${NWDAF_CU_SECTOR}        ${3}
${NWDAF_CU_NODEB}         ${4}
${NWDAF_CU_RNC}           ${5}
${NWDAF_CU_WMSC}          ${6}

# ════════════════════════════════════════════
# STATUS (TAG 0x0C, string) — 규격 2.3 부하 등급
# ════════════════════════════════════════════
${NWDAF_STATUS_NORMAL}    0
${NWDAF_STATUS_MINOR}     1
${NWDAF_STATUS_MAJOR}     2
${NWDAF_STATUS_CRITICAL}  3

# ════════════════════════════════════════════
# QUICK_SUPPORT (TAG 0x3B, string) — 규격 2.5
# ════════════════════════════════════════════
${NWDAF_QUICK_NOW}        0           # 즉시제어
${NWDAF_QUICK_AFTER}      1           # update 수신 후 제어

# ════════════════════════════════════════════
# SUPPORT_TYPE (TAG 0x41) — 규격 3.2
# ════════════════════════════════════════════
${NWDAF_SUPPORT_APPLY}    ${1}        # 제어
${NWDAF_SUPPORT_RELEASE}  ${2}        # 해지

# ════════════════════════════════════════════
# ARP_QCI_FLAG (TAG 0x3F) — 규격 3.3
# ════════════════════════════════════════════
${NWDAF_ARPQCI_ARP}       ${0}
${NWDAF_ARPQCI_QCI}       ${1}
${NWDAF_ARPQCI_BOTH}      ${2}

# ════════════════════════════════════════════
# ENB_ARP (TAG 0x3C) — 규격 3.4
# ════════════════════════════════════════════
${NWDAF_ENB_ARP_BAND_35}  ${12}       # Band 3->5/1 (=Band 5)
${NWDAF_ENB_ARP_BAND_153} ${13}       # Band 1/5->3 (=Band 1)

# ════════════════════════════════════════════
# ARP_CAPABILITY / ARP_VULNERABILITY / USER_RATIO 공통 (0=Enable, 1=Disable)
# ════════════════════════════════════════════
${NWDAF_ENABLE}           ${0}
${NWDAF_DISABLE}          ${1}

# ════════════════════════════════════════════
# NWDAF 테스트 데이터
# TODO: 실환경 PG/PDB 와 매칭되는 값으로 교체
# ════════════════════════════════════════════
${NWDAF_TEST_MIN}              1088881004
${NWDAF_TEST_MDN}              01088881004
${NWDAF_TEST_PGW_IP}           60.50.10.2
${NWDAF_TEST_CELL_ID}          123456:0
${NWDAF_TEST_QOS_POLICY}       QoS200K
${NWDAF_TEST_QCI}              ${9}
${NWDAF_TEST_TIMER}            ${300}      # 초 단위 (5분)
${NWDAF_TEST_RCT_3M_USAGE}     ${500}      # KB
${NWDAF_TEST_RCT_1M_USAGE}     ${150}      # KB
${NWDAF_TEST_DN_USAGE}         ${1000}     # KB
${NWDAF_TEST_USING_USER}       ${200}
${NWDAF_TEST_CELL_AVG_USAGE}   ${500}      # KB
${NWDAF_TEST_HEAVY_USER}       ${50}
${NWDAF_TEST_USER_USAGE}       ${50000}    # KB (Heavy+Medium+Light 합)

# ════════════════════════════════════════════
# NWDAF TLV TAG (규격 4개 섹션에서 쓰는 태그만 정의)
# ════════════════════════════════════════════
# COMMON1 (1절, 필수)
${NWDAF_TAG_MIN}                ${1}      # 0x01 string
${NWDAF_TAG_MDN}                ${2}      # 0x02 string
${NWDAF_TAG_CREATE_DATE}        ${8}      # 0x08 string 'YYYYMMDD'
${NWDAF_TAG_CREATE_TIME}        ${9}      # 0x09 string 'HHmmss'
${NWDAF_TAG_PCEF_TYPE}          ${13}     # 0x0D uint8  0x01=PGW, 0x10=eNB
${NWDAF_TAG_QOS_CONTROL_TYPE}   ${14}     # 0x0E uint8  0x01=가입자
${NWDAF_TAG_PGW_IP_ADDRESS}     ${15}     # 0x0F string
${NWDAF_TAG_RCT_3M_USAGE}       ${56}     # 0x38 uint32 KB
${NWDAF_TAG_RCT_1M_USAGE}       ${57}     # 0x39 uint32 KB

# pcefQoSCtrl (2절, PCEF_TYPE=0x01)
${NWDAF_TAG_QOS_HDR}            ${58}     # 0x3A uint8 flag (0x01=PGW, 0x10=eNB)
${NWDAF_TAG_QOS_POLICY}         ${16}     # 0x10 string
${NWDAF_TAG_STATUS}             ${12}     # 0x0C string '0'~'3'
${NWDAF_TAG_TIMER}              ${32}     # 0x20 pcef=uint16 sec, enb=string sec
${NWDAF_TAG_QUICK_SUPPORT}      ${59}     # 0x3B string '0'|'1'

# enodebQoSCtl (3절, PCEF_TYPE=0x10)
${NWDAF_TAG_QCI}                ${17}     # 0x11 uint8
${NWDAF_TAG_ENB_ARP}            ${60}     # 0x3C uint8 12|13
${NWDAF_TAG_ARP_QCI_FLAG}       ${63}     # 0x3F uint8 0|1|2
${NWDAF_TAG_SUPPORT_TYPE}       ${65}     # 0x41 uint8 1|2
${NWDAF_TAG_ARP_CAPABILITY}     ${66}     # 0x42 uint8 0|1
${NWDAF_TAG_ARP_VULNERABILITY}  ${67}     # 0x43 uint8 0|1

# COMMON2 (4절, 필수)
${NWDAF_TAG_CELL_ID}            ${11}     # 0x0B string '123456:0'
${NWDAF_TAG_USING_USER}         ${26}     # 0x1A uint32 동시 가입자 수
${NWDAF_TAG_NETWORK}            ${31}     # 0x1F uint32 0|1|2|3 (4B value)
${NWDAF_TAG_DN_USAGE}           ${49}     # 0x31 uint32 KB
${NWDAF_TAG_HEAVY_USER}         ${50}     # 0x32 uint32
${NWDAF_TAG_CELL_AVG_USAGE}     ${53}     # 0x35 uint32 KB
${NWDAF_TAG_USER_USAGE}         ${54}     # 0x36 uint32 KB
${NWDAF_TAG_USER_RATIO}         ${55}     # 0x37 uint8 0|1
${NWDAF_TAG_CONTROL_UNIT}       ${64}     # 0x40 uint8 1..6

# Body wrapper
${NWDAF_TAG_MULTI_MESSAGE}      ${255}    # 0xFF
