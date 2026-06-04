*** Settings ***
Documentation
...    CDS 인터페이스 변수 (접속 정보 / 메시지 ID / Result / 테스트 데이터)
...
...    CDS 표준 인터페이스 규격(SKT Ver6.0), TCP 고정길이 48B 헤더.
...    로봇(CDS) 이 PG.CDS 로 능동 접속(Schannel/Rchannel 듀얼 소켓).
...    포트/SYSTEM_ID 는 PG_V2.cfg [CDS] 섹션에서 읽되, 미수신 시 아래 기본값 사용.

*** Variables ***

# ════════════════════════════════════════════
# CDS PG.CDS 접속 정보 (클라이언트 듀얼 소켓)
#   Schannel : 9200 (Client→Server 전송용)
#   Rchannel : 9201 (Server→Client 전송용)
# ════════════════════════════════════════════
${CDS_PG_HOST}            192.168.15.141   # TODO: 실환경 PG.CDS IP
${CDS_SCH_PORT}           9200             # Schannel 포트
${CDS_RCH_PORT}           9201             # Rchannel 포트
${CDS_TIMEOUT}            10               # 송수신 타임아웃(초)

# UpLoad 별도 Activation 포트 (규격 예시 6100/6101)
# TODO: 실환경 UpLoad 포트 미지정 → 미사용 시 Schannel/Rchannel(9200/9201) 재사용
${CDS_UP_SCH_PORT}        6100
${CDS_UP_RCH_PORT}        6101

# ════════════════════════════════════════════
# 시스템 / Application 식별자 (헤더 char(6) 필드)
# SYSTEM_ID 는 PG_V2.cfg [CDS] SYSTEM_ID 에서 읽음(미수신 시 PG01).
#   → ${PG_CDS_PG_V2_SYSTEM_ID} (DynamicVars 주입) / 없으면 ${CDS_SYSTEM_ID_DEFAULT}
#   PG.CDS 식별자로, 헤더 Destination System ID 로 사용.
# ════════════════════════════════════════════
${CDS_SYSTEM_ID_DEFAULT}  PG01             # config 미수신 시 기본 SYSTEM_ID
${CDS_SRC_SYS_ID}         CDS01            # TODO: 로봇(CDS) 자신의 System ID
${CDS_SRC_APP_ID}         ${EMPTY}         # TODO: Source Application ID (필요시)
${CDS_DST_APP_ID}         ${EMPTY}         # TODO: Destination Application ID (필요시)

# ════════════════════════════════════════════
# Message ID (규격 11. 메시지 식별자 요약)
# ════════════════════════════════════════════
${CDS_MSG_SCH_CONN_REQ}        ${1}      # 0001 SchannelConnectionRequest
${CDS_MSG_SCH_CONN_ACK}        ${2}      # 0002 SchannelConnectionRequestACK
${CDS_MSG_RCH_CONN_REQ}        ${3}      # 0003 RchannelConnectionRequest
${CDS_MSG_RCH_CONN_ACK}        ${4}      # 0004 RchannelConnectionRequestACK
${CDS_MSG_SCH_REL_REQ}         ${5}      # 0005 SchannelReleaseRequest
${CDS_MSG_SCH_REL_ACK}         ${6}      # 0006 SchannelReleaseRequestACK
${CDS_MSG_RCH_REL_REQ}         ${7}      # 0007 RchannelReleaseRequest
${CDS_MSG_RCH_REL_ACK}         ${8}      # 0008 RchannelReleaseRequestACK
${CDS_MSG_PROC_STATE_REQ}      ${13}     # 0013 ProcessStateRequest
${CDS_MSG_PROC_STATE_ACK}      ${14}     # 0014 ProcessStateRequestACK
${CDS_MSG_CMD_REQ}             ${15}     # 0015 CommandRequest
${CDS_MSG_CMD_REQ_ACK}         ${16}     # 0016 CommandRequestACK
${CDS_MSG_CMD_RESULT}          ${17}     # 0017 CommandResult
${CDS_MSG_CMD_RESULT_ACK}      ${18}     # 0018 CommandResultACK
${CDS_MSG_UPLOAD_REQ}          ${25}     # 0025 UploadRequest
${CDS_MSG_UPLOAD_REQ_ACK}      ${26}     # 0026 UploadRequestACK
${CDS_MSG_UPLOAD_RESULT}       ${27}     # 0027 UploadResult
${CDS_MSG_UPLOAD_RESULT_ACK}   ${28}     # 0028 UploadResultACK
${CDS_MSG_SUBS_DATA_REQ}       ${29}     # 0029 SubsDataRequest
${CDS_MSG_SUBS_DATA_REQ_ACK}   ${30}     # 0030 SubsDataRequestACK
${CDS_MSG_SUBS_DATA_RESULT}    ${31}     # 0031 SubsDataResult
${CDS_MSG_SUBS_DATA_RESULT_ACK}  ${32}   # 0032 SubsDataResultACK

# ════════════════════════════════════════════
# Result / Process State (규격 4~6장)
# ════════════════════════════════════════════
${CDS_RESULT_SC}          SC               # 성공
${CDS_RESULT_FA}          FA               # 실패
${CDS_PS_NORMAL}          ${1}             # ProcessState: Normal
${CDS_PS_ABNORMAL}        ${2}             # ProcessState: Abnormal

# ════════════════════════════════════════════
# Reason / Error 코드 (규격 10. 오류 메시지 일부)
# ════════════════════════════════════════════
${CDS_ERR_WRONG_HEADER}        ${11}     # Wrong Header
${CDS_ERR_WRONG_SIZE}          ${12}     # Wrong Size
${CDS_ERR_WRONG_DATA}          ${13}     # Wrong Data
${CDS_ERR_MISMATCH_TID}        ${14}     # Mismatch T-ID
${CDS_ERR_UNRECOG_MSG}         ${52}     # UnrecognizedMessage
${CDS_ERR_SYSTEM_FAILURE}      ${57}     # SystemFailure

# ════════════════════════════════════════════
# 테스트 데이터
# TODO: 실환경 명령어/가입자 데이터 포맷으로 교체 (규격 "추후 결정")
# ════════════════════════════════════════════
${CDS_TEST_COMMAND_DATA}       A1                       # Command Data (opCode 예시)
${CDS_TEST_SUBS_MIN}           01100001234              # SubsData 요구 MIN (011+XXXX+YYYYY)
