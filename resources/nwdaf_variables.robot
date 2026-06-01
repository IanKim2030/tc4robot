*** Settings ***
Documentation
...    NWDAF 인터페이스 변수 (접속 정보 / Header / TLV TAG / 테스트 데이터)
...
...    방향: NWDAF → PG (Notification 주력, 응답 사실상 없음)
...    Body 구조: COMMON1 + (pcefQoSCtrl|enodebQoSCtl) + COMMON2 를
...               전체 MULTI_MESSAGE(0xFF) TLV 로 감싼다.

*** Variables ***

# ════════════════════════════════════════════
# NWDAF PG 접속 정보 (클라이언트 모드)
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
${NWDAF_CU_CELL}          ${49}       # 0x31 (ASCII '1')
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
${NWDAF_ENB_ARP_BAND_35}   ${12}      # Band 3->5/1 (=Band 5)
${NWDAF_ENB_ARP_BAND_153}  ${13}      # Band 1/5->3 (=Band 1)

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
