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
${CDS_SRC_SYS_ID}         SCSL00           # 로봇(CDS) 자신의 System ID (6자)
${CDS_SRC_APP_ID}         TEMP             # Source Application ID (6자 패딩 → 'TEMP  ')
${CDS_DST_APP_ID}         TEMP             # Destination Application ID (6자 패딩 → 'TEMP  ')

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
# CommandRequest(0015) Body Code 정의 (업무 코드, 2자리)
#   Body 구조: svc_code(2) 별 가변 고정길이 레코드(총 327B).
#   채울 필드는 CdsHelper._CMD_LAYOUT(=레거시 clear() 순서)/_fill_command_fields(code) 참조.
#   필드 값은 'Send Command Request' 에 키워드 인자로 전달(mdn/new_mdn/min 기본값, 그 외 &{extra}).
# ════════════════════════════════════════════
${CDS_CODE_A1}      A1     # 신규
${CDS_CODE_C1}      C1     # 기기변경
${CDS_CODE_C2}      C2     # 신호방식변경
${CDS_CODE_C3}      C3     # 코드방식변경
${CDS_CODE_C4}      C4     # 이용종류변경
${CDS_CODE_C5}      C5     # 기기대체 (A/S)
${CDS_CODE_D2}      D2     # 호출번호해지
${CDS_CODE_D3}      D3     # 호출번호신청
${CDS_CODE_D5}      D5     # 번호안내등록
${CDS_CODE_D4}      D4     # 번호안내해지
${CDS_CODE_E1}      E1     # 수용국전출
${CDS_CODE_E2}      E2     # 수용국전입
${CDS_CODE_F1}      F1     # 일시정지
${CDS_CODE_F2}      F2     # 일시정지해제
${CDS_CODE_F3}      F3     # 사용정지
${CDS_CODE_F4}      F4     # 사용정지해제
${CDS_CODE_F5}      F5     # 휴지
${CDS_CODE_F6}      F6     # 휴지해제
${CDS_CODE_I1}      I1     # 부가서비스변경
${CDS_CODE_I2}      I2     # 부가서비스신청
${CDS_CODE_I3}      I3     # 부가서비스해지
${CDS_CODE_M1}      M1     # 명의변경
${CDS_CODE_Y3}      Y3     # Voice Prompt 변경
${CDS_CODE_Y4}      Y4     # Password Reset
${CDS_CODE_Y5}      Y5    # 교환기등록정보 검색
${CDS_CODE_G1}      G1     # G1 (TODO: 규격 확인)
${CDS_CODE_Z1}      Z1     # 직권해지
${CDS_CODE_Z2}      Z2     # 가입해지
${CDS_CODE_1X}      1X     # HFC 서비스 가입
${CDS_CODE_1Y}      1Y     # HFC 서비스 해지

# ════════════════════════════════════════════
# 테스트 데이터
# TODO: 실환경 명령어/가입자 데이터 값으로 교체
# ════════════════════════════════════════════
# CommandRequest body — 공통 5개 필드 (스펙: mdn / product_id / limitSubsFlag / produGenType / device_type)
${CDS_TEST_CMD_CODE}           ${CDS_CODE_A1}          # 기본 업무 코드 (신규 A1)
${CDS_TEST_MDN}                01053543393              # mdn        (12자)
${CDS_TEST_PROD_ID}            NA00003479               # product_id (10자, prod_id)
${CDS_TEST_LIMIT}              0                        # limitSubsFlag (1자, TODO: 실환경 값)
${CDS_TEST_PROD_TYPE}          ${EMPTY}                 # produGenType  (2자, TODO: 실환경 값)
${CDS_TEST_DEVICE_TYPE}        ${EMPTY}                 # device_type   (1자, TODO: 실환경 값)
# 코드별 추가 필드 (Send Command Request &{extra} 로 전달)
${CDS_TEST_NEW_MDN}            01053543394              # new_mdn (C1 기기변경 시)
${CDS_TEST_MIN}                1053543393               # min     (A1/D3 등)
${CDS_TEST_NEW_MIN}            1053543394               # new_min (C1 기기변경 시)
${CDS_TEST_SUBS_MIN}           01100001234              # SubsData 요구 MIN (011+XXXX+YYYYY)
${CDS_TEST_ADDR}               서울특별시 강남구 테헤란로 123      # addr (1X HFC 가입 시, 170byte, cp949 인코딩, TODO: 실환경 값)
