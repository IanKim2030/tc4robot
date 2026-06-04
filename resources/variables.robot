*** Settings ***
Documentation
...    PG 연동 통합 테스트 공통 변수 (NAG / PCF / LRS / UPM / NWDAF 가 모두 공유)
...
...    인터페이스별 변수는 각각의 *_variables.robot 으로 분리되어 있음:
...      resources/nag_variables.robot    ← NAG 접속/메시지/응답코드 + NAG·PCF 공용 테스트 데이터
...      resources/pcf_variables.robot    ← PCF 접속/메시지 (NAG 변수 의존)
...      resources/lrs_variables.robot    ← LRS 서버 정보/메시지/RESULT_CODE/테스트 데이터
...      resources/upm_variables.robot    ← UPM 접속/메시지/code-type/테스트 데이터
...      resources/nwdaf_variables.robot  ← NWDAF 접속/TLV TAG/테스트 데이터
...
...    여기에는 모든 인터페이스가 공유하는 메시지 타입 상수만 둔다.

*** Variables ***

# ════════════════════════════════════════════
# 메시지 타입 상수 (헤더 Byte1) — NAG / PCF / LRS / UPM 공통
# ════════════════════════════════════════════
${MSG_HELLO_REQ}              ${1}     # 0x01
${MSG_HELLO_RESP}             ${2}     # 0x02
${MSG_PING_REQ}               ${3}     # 0x03
${MSG_PING_RESP}              ${4}     # 0x04

# ════════════════════════════════════════════
# DynamicVars 원격(SSH) cfg 읽기용 인증 정보
# 사용: 각 슈트의 Variables 임포트에 `pass=${PG_ROBOT_SSH_PASS}` 로 전달
#   (이 Resource 가 Variables 줄보다 먼저 임포트돼야 치환됨)
# 비우면 OS 환경변수 PG_ROBOT_SSH_PASS 로 폴백한다.
# 주의: 값을 채우면 RF 로그에 남으므로, 운영 환경에선 환경변수 사용 권장.
# ════════════════════════════════════════════
${PG_ROBOT_SSH_PASS}         pg1234    # TODO: 실환경 SSH 비밀번호
