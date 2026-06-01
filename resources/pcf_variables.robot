*** Settings ***
Documentation
...    PCF 인터페이스 변수 (접속 정보 / 메시지 타입)
...
...    PCF 슈트는 NAG 세션을 선등록하므로 NAG 변수(접속 정보)와
...    NAG·PCF 공용 응답 코드/테스트 데이터에 의존한다.
...    (pcf_keywords.robot → nag_keywords.robot 구조와 동일)
Resource   ${CURDIR}/nag_variables.robot

*** Variables ***

# ════════════════════════════════════════════
# PCF PG 접속 정보 (클라이언트 모드, Port 8011)
# ════════════════════════════════════════════
${PCF_PG_HOST}         192.168.15.141
${PCF_PG_PORT}         8011
${PCF_TIMEOUT}         10
${PCF_SYS_ID}          LTE-PCRF01
${PCF_BRANCH_NAME}     SS

# ════════════════════════════════════════════
# PCF 전용 메시지 타입 (Zone-InOut, 헤더 Byte1)
# ════════════════════════════════════════════
${MSG_PCF_ZONE_REQ}           ${5}     # 0x05  PCF → PG
${MSG_PCF_ZONE_RESP}          ${6}     # 0x06  PG → PCF
