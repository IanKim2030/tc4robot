*** Settings ***
Documentation
...    NAG 인터페이스 변수 (접속 정보 / 메시지 타입 / 응답 코드 / NAG·PCF 공용 테스트 데이터)
...
...    NAG 슈트는 LRS-PCF 서버 소켓(8890)을 함께 사용하므로 LRS 변수에 의존한다.
...    (nag_keywords.robot → lrs_keywords.robot 구조와 동일)
Resource   ${CURDIR}/lrs_variables.robot

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
# NAG 전용 메시지 타입 (헤더 Byte1)
# ════════════════════════════════════════════
${MSG_ZION_REQ}               ${7}     # 0x07  PG → NAG (수신)
${MSG_ZION_RESP}              ${8}     # 0x08  NAG → PG
${MSG_SUBS_ZONE_STATUS_REQ}   ${9}     # 0x09  NAG → PG
${MSG_SUBS_ZONE_STATUS_RESP}  ${10}    # 0x0a  PG → NAG
${MSG_SUBS_CELLID_REQ}        ${11}    # 0x0b  NAG → PG (ADOT)
${MSG_SUBS_CELLID_RESP}       ${12}    # 0x0c  PG → NAG (ADOT)

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
# NAG/PCF 테스트 데이터
# ════════════════════════════════════════════
${TEST_MDN_NORMAL}        01020300553
${TEST_MDN_NO_SS}         00000000000    # HFC 미가입 → code=402
${TEST_MDN_NO_SESSION}    99999999999    # 세션 없음 → code=403
${TEST_MOBILE_IP}         2001:0d88:131f:0000::/64
${TEST_CELL_INFO}         9999:99
${TEST_APN}               lte.sktelecom.com
${TEST_CLIENT_HOST}       ltepgw01.sktelecom.com
