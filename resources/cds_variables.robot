*** Settings ***
Documentation
...    CDS 인터페이스 변수 (접속 정보 / 메시지 ID / Result / 테스트 데이터)
...
...    CDS 표준 인터페이스 규격(SKT Ver6.0), TCP 고정길이 48B 헤더.
...    로봇(CDS) 이 PG.CDS 로 능동 접속(Schannel/Rchannel 듀얼 소켓).
...    포트/SYSTEM_ID 기본값은 아래 값이며, 환경별로 다르면 config/env/<env>.py 에서 오버라이드한다.
...
...    ※ upm_variables.robot 을 함께 들여온다 — 1X(HFC 가입)가 PG.BSUBS→UPM
...      Subs-Info(0x07)를 유발해 TC-CDS-003 이 UPM 쪽 값을 쓰기 때문이다.
...      (PCF 슈트가 nag_variables 를 들여오는 것과 같은 구조)

Resource   ${CURDIR}/upm_variables.robot

*** Variables ***

# ════════════════════════════════════════════
# CDS PG.CDS 접속 정보 (클라이언트 듀얼 소켓)
#   Schannel : 9200 (Client→Server 전송용)
#   Rchannel : 9201 (Server→Client 전송용)
# ════════════════════════════════════════════
${CDS_PG_HOST}            ${PG_HOST}       # 다르면 환경 파일에서 개별 지정
${CDS_SCH_PORT}           9200             # Schannel 포트
${CDS_RCH_PORT}           9201             # Rchannel 포트
${CDS_TIMEOUT}            10               # 송수신 타임아웃(초)

# UpLoad 별도 Activation 포트 (규격 예시 6100/6101)
# TODO: 실환경 UpLoad 포트 미지정 → 미사용 시 Schannel/Rchannel(9200/9201) 재사용
${CDS_UP_SCH_PORT}        6100
${CDS_UP_RCH_PORT}        6101

# ════════════════════════════════════════════
# UPM 연동 (TC-CDS-003 1X 전용)
#
# 1X(HFC 서비스 가입)를 받으면 PG.BSUBS 가 **UPM 으로 Subs-Info-Request(0x07)를
# 밀어준다.** 그래서 TC-CDS-003 은 CDS 전문·PDB 만으로는 절반만 보는 셈이고,
# UPM 쪽 0x07 수신 + 0x08 응답까지 해야 흐름 전체가 검증된다
# (UPM 슈트의 TC-UPM-301 은 트리거가 없어 주석 처리돼 있다).
#
# ★ 켜면 **CDS 슈트가 UPM 포트(${UPM_PG_PORT})에도 의존한다.** Suite Setup 에서
#   붙으므로 UPM 이 안 뜨면 PDB 와 마찬가지로 슈트 전체가 서지 않는다.
#   CDS 전문만 돌리려면 ${FALSE} 로 끄면 된다 — TC-CDS-003 의 UPM 단계만 건너뛴다.
#     python -m robot --variable CDS_UPM_VERIFY:False tests/cds/
${CDS_UPM_VERIFY}         ${TRUE}          # 1X → UPM Subs-Info(0x07/0x08) 검증 여부

# ════════════════════════════════════════════
# PCF Noti 수신 (도구가 PCF 역할로 HTTP/2 Listen)
#
# SA(5G) 가입자는 PG 가 PCF 로 **SBI Noti** 를 보낸다(docs/INTERFACES.md).
# 1X 흐름에서 PCF 방향 화살표가 둘이다.
#   SNOTI → PCF : 가입자 정보 변경 통보 (SDM 반영 뒤)
#   BSUBS → PCF : Cell List 전송 (UPM 0x08 응답 뒤)
# 도구가 이 포트로 Listen 하면 전문·PDB 와 별개로 "실제로 나갔는지"를 볼 수 있다.
#
# ★ 프로토콜은 **HTTP/2 평문(h2c)** 이다. 표준 http.server 로는 안 되고
#   HttpNotiServer.py 가 h2 패키지로 처리한다(prior-knowledge 방식만 지원).
#   → 의존성: pip install h2
#
# ★ PG 가 이 주소로 보내도록 설정돼 있어야 한다. 포트가 다르면 여기서 맞출 것.
#   LTE 가입자는 SBI 가 아니라 RBUS 라 아무것도 안 들어온다(docs/nodes/CDS.md).
${CDS_NOTI_VERIFY}        ${TRUE}          # PCF Noti 수신 검증 여부
${CDS_NOTI_PORT}          16101            # 도구가 Listen 할 포트 (PG 설정과 일치해야 함)
${CDS_NOTI_HOST}          0.0.0.0          # 모든 인터페이스 Listen
${CDS_NOTI_WAIT}          30s              # Noti 도착 대기 시간

# ★ Suite Setup 은 **PG 가 h2c 로 붙을 때까지 기다린 뒤** TC 를 시작한다.
#   접속 전에 전문을 보내면 PG 가 알림을 보낼 상대가 없어 그냥 흘러가고,
#   TC-CDS-003 은 "안 왔다" 로 실패한다 — 원인이 전문이 아니라 타이밍인데
#   로그만 봐서는 구분되지 않는다. 그래서 시작 자체를 접속에 맞춘다.
#   이 시간 안에 안 붙으면 슈트가 서지 않는다(PG 설정·포트를 의심할 것).
${CDS_NOTI_ACCEPT_TIMEOUT}    60s          # PG 의 h2c 접속을 기다리는 시간

# 알림 종류를 :path 로 가른다. **기본은 빈 값 = 경로를 가리지 않음**이다 —
# 실제 PG 가 쓰는 경로가 확인되지 않았기 때문이다. 확인되면 여기에 채워 넣으면
# 그때부터 종류별로 구분해 판정한다(SQL 이나 키워드는 손대지 않아도 된다).
#   예) ${CDS_NOTI_PATH_SUBS}    /npcf-smpolicycontrol/v1/
#       ${CDS_NOTI_PATH_CELL}    /cell-list
${CDS_NOTI_PATH_SUBS}     ${EMPTY}         # SNOTI→PCF 가입자 Noti 의 :path 조각
${CDS_NOTI_PATH_CELL}     ${EMPTY}         # BSUBS→PCF Cell List 의 :path 조각

# ════════════════════════════════════════════
# 시스템 / Application 식별자 (헤더 char(6) 필드)
# ${CDS_DST_SYS_ID} 는 PG.CDS 의 SYSTEM_ID 로, 헤더 Destination System ID 에 쓴다.
# 환경별로 다르면 config/env/<env>.py 에서 오버라이드한다.
# ════════════════════════════════════════════
${CDS_DST_SYS_ID}         PG01             # PG.CDS SYSTEM_ID
${CDS_SRC_SYS_ID}         SCSL00           # 로봇(CDS) 자신의 System ID (6자)
${CDS_SRC_APP_ID}         TEMP             # Source Application ID (6자 패딩 → 'TEMP  ')
${CDS_DST_APP_ID}         TEMP             # Destination Application ID (6자 패딩 → 'TEMP  ')

# ════════════════════════════════════════════
# Transaction ID — 와이어는 12B(char(8) + uint32 BE)지만
# PG 는 이를 **16자 문자열**로 렌더링해 DB PK 로 쓴다.
#
#   CDS/CDownMessage.cpp:70
#     sprintf(strTid, "%8.8s%08d", GetTid()->tidDate, GetTid()->seqNo);
#   CDS/sql.txt:6,14
#     TRANSACTION_ID char(16) NOT NULL, PRIMARY KEY(TRANSACTION_ID)
#
# 그래서 seq 를 `HHMMSS * 100 + 일련번호` 로 만들면 PG 가 찍는 16자가
# 정확히 **YYYYMMDD HHMMSS NN** 이 된다.
#
#   date=20260731, 09:30:00 의 1번째 → seq = 93000*100 + 1 = 9300001
#   PG 렌더링       "20260731" + "09300001" = 2026073109300001
#                    └날짜8┘     └HHMMSS┘└NN┘
#
# ★ ${CDS_TID_SEQ_MOD} 는 자유롭게 못 바꾼다.
#   PG 의 `%08d` 가 8자리이고 HHMMSS 가 6자리를 쓰므로 일련번호 몫은 2자리뿐이다.
#   1000 으로 올리면 9자리가 되어 날짜 자리를 침범한다.
# ════════════════════════════════════════════
${CDS_TID_SEQ_MOD}        ${100}           # 초당 일련번호 폭 (00~99). PG %08d 제약상 고정

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
${CDS_CODE_G1}      G1     # 정보변경 (필드 집합은 A1 과 동일 — 2026-08-03 확인)
${CDS_CODE_Z1}      Z1     # 직권해지
${CDS_CODE_Z2}      Z2     # 가입해지
${CDS_CODE_1X}      1X     # HFC 서비스 가입
${CDS_CODE_1Y}      1Y     # HFC 서비스 해지

# ── 쿠폰 / 옵션 계열 업무 코드 ──────────────────────────────────
# 가입자 서비스 테이블(${CDS_DB_TBL_SERVICE})에 반영되는 것은 앞의 코드들과 같다.
# 다른 점은 **가입 계열 3개(K1/K5/Y9)가 예약 큐에 후속 예약을 함께 건다**는 것이다
# — 쿠폰은 유효기간이 끝나면 만료돼야 하므로 PG.RDS 가 그때까지 들고 있는다.
# 근거: PG SDM/Syncer/Syncer.cpp SyncReservedJobTBL() 의 jobCode 분기.
#
#   K1 → 예약 큐 JOB_CODE='K3'   K5 → 'K7'   Y9 → 'Y6' (COUPON_TYPE 숫자면 'Y8')
#
# ★ 인입 코드와 예약 큐 적재 코드가 다르다. K3/K7 은 인입 업무 코드이면서 동시에
#   K1/K5 가 만들어 넣는 예약 코드이기도 하다.
${CDS_CODE_Y9}      Y9     # Data(Zone) 부가서비스(쿠폰) 사용시점 알림 → 예약 큐에 Y6
${CDS_CODE_K1}      K1     # Data(Time) 쿠폰 가입      → 예약 큐에 K3
${CDS_CODE_K2}      K2     # Data(Time) 쿠폰 해지
${CDS_CODE_K3}      K3     # Data(Time) 쿠폰 만료
${CDS_CODE_K4}      K4     # Data(Time) 쿠폰 취소
${CDS_CODE_K5}      K5     # Data(Time) 3Mbps 쿠폰 가입 → 예약 큐에 K7
${CDS_CODE_K6}      K6     # Data(Time) 3Mbps 쿠폰 해지
${CDS_CODE_SS}      SS     # 0플랜 옵션(3시간 프리) 가입
${CDS_CODE_ST}      ST     # 0플랜 옵션(3시간 프리) 해지

# ════════════════════════════════════════════
# 테스트 데이터
# TODO: 실환경 명령어/가입자 데이터 값으로 교체
# ════════════════════════════════════════════
# CommandRequest body — 공통 5개 필드 (스펙: mdn / product_id / limitSubsFlag / produGenType / device_type)
# ${CDS_PROD_TYPE}/${CDS_DEVICE_TYPE} 는 전 코드 공용 기본값이라 비워 둔다.
# 단말·망 필드는 아래 별도 블록에 있고, 둘 다 Send Command Request 기본 인자로 쓰인다.
#
# 가입자(MDN/MIN)는 CDS 슈트만 쓰므로 여기 직접 둔다 — 공용 variables.robot 의
# ${SUBS_*} 축은 두 노드 이상이 공유하는 값만 담는다.
${CDS_CMD_CODE}                ${CDS_CODE_A1}           # 기본 업무 코드 (신규 A1)
${CDS_MDN}                     01090010001              # mdn        (12자) — CDS 는 가입자가 다르다
${CDS_PROD_ID}                 NA00003479               # product_id (10자, prod_id)
${CDS_LIMIT}                   0                        # limitSubsFlag (1자, TODO: 실환경 값)
${CDS_PROD_TYPE}               02                       # produGenType  (2자, 코드별로 다름)
${CDS_DEVICE_TYPE}             L                        # device_type   (1자, 코드별로 다름)
# 코드별 추가 필드 (Send Command Request &{extra} 로 전달)
${CDS_NEW_MDN}                 01090010002              # new_mdn (D3 번호변경 신규 번호, TODO: 실환경 예비 번호)
${CDS_MIN}                     1090010001               # min     (10자, A1/D3 등)

# D3(번호변경) 이후 가입자를 가리키는 번호. Z1(해지)처럼 "현재 번호"로 보내야 하는
# 코드가 쓴다. 기본값은 원래 번호이고, TC-CDS-018(D3)이 성공하면 그 TC 가
# Set Suite Variable 로 ${CDS_NEW_MDN} 을 덮어쓴다.
# → D3 를 건너뛰거나 실패하면 기본값이 남아 **원래 번호로 해지**한다.
${CDS_ACTIVE_MDN}              ${CDS_MDN}               # 현재 유효 MDN (D3 성공 시 new_mdn 으로 교체)
${CDS_NEW_MIN}                 1090010002               # new_min (C1 기기변경 시)
${CDS_SUBS_MIN}                01100001234              # SubsData 요구 MIN (011+XXXX+YYYYY)

# ── 예약(쿠폰) 계열 필드 — Y9 / K1~K6 / SS / ST ─────────────────
# 필드 집합은 시뮬레이터 GenCds.py gen() 의 각 분기에서 뽑았다(2026-08-10 대조).
#   Y9       : mdn limit zone_code start_time coupon_type coupon_pin
#   K1/K5    : mdn limit start_time coupon_type coupon_pin coupon_category
#   K2/K3/K4/K6 : mdn limit coupon_pin
#   SS/ST    : mdn limit start_time coupon_type
#
# ★ START_TIME 은 반드시 **미래**여야 한다.
#   K1/K5 가입은 서비스 행을 넣는 동시에 예약 큐에 만료(K3/K7) 예약을 건다. PG.RDS 가
#   START_TIME 이 지난 예약을 집어 실행하므로, 과거 시각을 넣으면 **가입하자마자 만료가
#   실행돼** 서비스 행이 사라진다 → 가입 판정(TC-CDS-010/014)이 이유 없이 실패한다.
#   이 값이 과거가 되면 여기를 먼저 볼 것.
${CDS_START_TIME}              203712312359             # 예약 시작 시각 YYYYMMDDHH24MI (미래여야 함)

# 만료(K3) TC 는 위 고정값 대신 **현재 시각 기준**으로 보낸다 — 유효기간이 찬 쿠폰을
# 다뤄야 하기 때문이다. 그 시각을 현재에서 몇 분 옮길지가 이 값이다(`Current CDS Start Time`).
#   0  = 지금. 이번 분이 이미 시작돼 있어 PG.RDS 가 곧 만료 예약을 집어간다.
#   양수 = 그만큼 뒤. RDS 가 먼저 지워버려 가입 확인이 실패하면 1~2 로 올려 여유를 준다.
#   음수 = 그만큼 전. 이미 지난 예약으로 만들고 싶을 때.
# 전문 형식이 분까지만 담아서 단위가 분이다(초 자리가 없다).
${CDS_K3_START_OFFSET_MIN}     ${0}                     # K3 만료 TC 의 START_TIME 오프셋(분)

# 판정 기준표의 $LIMIT_VALID_TIME — 서비스 테이블 LIMIT_VALID_TIME 컬럼의 기대값이다.
# 전문의 START_TIME 에서 나오지만 **폭이 다르다.**
#
#   전문 START_TIME    : 12자리 YYYYMMDDHH24MI      (T_5G_CDS_ORDER_CFG ID=25,
#                                                    SUBTITLE 이 LIMIT_VALID_TIME)
#   DB LIMIT_VALID_TIME: CHAR(14) YYYYMMDDHH24MISS  ← 뒤에 초 '00' 이 붙는다
#
# ★ 그래서 ${CDS_START_TIME} 을 그대로 비교하면 **안 맞는다.** CHAR 는 고정폭이라
#   12자리로 조회하면 가입 판정(K1/K5/Y9)만 0건이 나와 실패한다. 이 변수를 쓸 것.
#   컬럼 타입은 docs/nodes/CDS.md 의 T_5G_SUBS_SERVICE 스키마 절 참조.
${CDS_LIMIT_VALID_TIME}        ${CDS_START_TIME}00      # 14자리 (전문 12자리 + 초 '00')

# SS 의 TIME_PERIOD_ID 는 **'SS_' 접두 + 전문 START_TIME(12자리)** 이다.
#   예) SS_203712312359
#
# ★ 기준표 표기가 TIME_PERIOD_ID(SS_$LIMIT_VALID_TIME) 이라 K1 행의
#   LIMIT_VALID_TIME($LIMIT_VALID_TIME) 과 같은 값(14자리)으로 읽기 쉬운데 **아니다.**
#   같은 토큰이지만 SS 쪽은 초 '00' 이 붙지 않은 12자리 원본이 들어간다
#   (2026-08-11 실값 확인). 위 ${CDS_LIMIT_VALID_TIME} 을 붙이면 14자리가 되어 안 맞는다.
${CDS_DB_TPID_SS}              SS_${CDS_START_TIME}     # SS TIME_PERIOD_ID (접두 + 12자리)

# COUPON_TYPE='T' 는 Y9 의 분기를 가른다 — 'T' 면 예약 큐에 Y6, 숫자면 Y8 이 들어간다.
# TC 는 Y6 을 기대하므로 'T' 로 고정한다.
${CDS_COUPON_TYPE}             T                        # coupon_type(2)
# COUPON_CATEGORY 는 K1/K5 에서 'T'(Time) 또는 'P'(Period) 가 아니면 Syncer 가
# Invalid 로그를 남기고 **예약을 넣지 않는다** → 반드시 T 나 P 여야 한다.
${CDS_COUPON_CATEGORY}         T                        # coupon_category(1) T=Time P=Period
${CDS_ZONE_CODE}               0002                     # zone_code(4) → 예약 큐 ZONE_SVC_CODE

# COUPON_PIN 은 업무별로 **다른 값을 쓴다.**
# 쿠폰 행이 서비스 테이블에서 `MDN + SVC_ID + CNUM(=핀)` 으로 식별되고, 해지·만료·취소
# (K2/K3/K4/K6)가 모두 그 조합으로 지우기 때문이다 — 핀을 공유하면 한 TC 가 지운 행을
# 다른 TC 가 자기 결과로 착각한다("0건"은 지워졌는지 원래 없었는지 구분하지 못한다).
${CDS_COUPON_PIN}              00000000020              # coupon_pin(11) 공용 기본값
${CDS_COUPON_PIN_Y9}           00000000091              # Y9 전용
${CDS_COUPON_PIN_K1}           00000000011              # K1 가입 → K2 해지 쌍 전용
${CDS_COUPON_PIN_K3}           00000000031              # K3 만료 검증 전용 (TC 안에서 K1 로 먼저 가입)
${CDS_COUPON_PIN_K4}           00000000041              # K4 취소 검증 전용 (TC 안에서 K1 로 먼저 가입)
${CDS_COUPON_PIN_K5}           00000000051              # K5 가입 → K6 해지 쌍 전용
${CDS_ADDR}                    서울특별시 강남구 테헤란로 123      # addr (1X HFC 가입 시, 170byte, cp949 인코딩, TODO: 실환경 값)
#${CDS_ADDR}                    가나다라마바사아자타가나다라마바사아자타가나다라마바사아자타가나다라마바사아자타가나다라마바사아자타가나다라마바사아자타가나다라마바사아자타가나다라마바사아자타가나다라마

# ════════════════════════════════════════════
# PDB 조회 (전문 반영 판정) — ODBC / pyodbc
#
# CommandResult(0017)는 Body 내용과 무관하게 SC 를 주므로, 전문이 실제로 가입자
# 테이블에 반영됐는지는 PDB 를 봐야 판정된다(docs/nodes/CDS.md "도구 관점에서의 함의").
#
# 대상 DB 는 환경에 따라 골디락스 또는 알티베이스다.
# ★ 접속 문자열을 채우지 않으면 **슈트 전체가 서지 않는다**(Suite Setup 에서 붙는다).
#    config/env/<env>.py 에서 오버라이드하는 것이 정석이다.
#
# ════════════════════════════════════════════
# DSN 방식
#${CDS_DB_CONNSTR}         DSN=GOLD_GLOBAL;UID=pdb;PWD=pdb1234
# DSN-less 방식
${CDS_DB_CONNSTR}         DRIVER=/PG/goldilocks_home/lib/libgoldilockscs-ul64.so;HOST=192.168.15.185;PORT=22581;UID=pdb;PWD=pdb1234;CHARSET=UHC;

${CDS_DB_TIMEOUT}         5               # 접속·쿼리 타임아웃(초)

# 트랜잭션 자동 커밋. **기본은 끔(${FALSE})**
# 나중에 TC가 끝나면 Rollback 할지 결정 필요 
${CDS_DB_AUTOCOMMIT}      ${FALSE}

# ── 조회 동작 ────────────────────────────────────────────────────
# 환경변수 : export GOLDILOCKS_HOME=/PG/goldilocks_home
#
# 바인딩·인코딩에는 변수가 없다. 둘 다 손잡이를 없앴다.
#   · 바인딩 : `?` 파라미터 바인딩 **고정**. setinputsizes 로 SQLDescribeParam 호출을
#              피한다. 리터럴 모드와 ${CDS_DB_BIND} 는 제거됐다.
#   · 인코딩 : 위 ${CDS_DB_CONNSTR} 의 **CHARSET=** 으로 지정한다 (골디락스는 UHC).
#              pyodbc 쪽 setencoding/setdecoding(구 ${CDS_DB_ENCODING})은 제거됐다.
#
# ★ 둘 다 예전에 ('HY000', 'The driver did not supply an error!') 의 원인으로 지목된
#   자리다(골디락스, 2026-08-06). 그 증상이 다시 나오면 CHARSET 값을 먼저 의심할 것 —
#   폴백이 없으므로 조회는 그대로 실패한다. 상세는 docs/nodes/CDS.md 의 함정 절.


# 반영 대기 — PG.SDM 이 T_CDS_ORDER_HIST 를 주기적으로 폴링해 가입자 테이블에
# 반영하므로, CommandResult(0017) 수신 시점에는 아직 반영 전일 수 있다.
# 그래서 조회를 한 번만 하지 않고 아래 시간 동안 재시도한다.
#
# 시간 축이 둘이다. ResultAck(0018) 송신 직후부터 세면:
#   ┌ SETTLE ┬─ WAIT (INTERVAL 간격 재조회) ─────────────┐
#   ResultAck   1차 조회                              판정 종료
#
# SETTLE : **첫 조회 전에 무조건 쉬는 시간.** 반영이 시작되기도 전에 조회해서
#          "없음"을 보고 재시도 루프를 도는 낭비를 줄인다. 0 또는 0s 면 안 쉰다.
#          업무 코드마다 반영이 더 느리면 TC 에서 settle= 로 덮어쓸 수 있다
#          (예: Verify Zone Service Subscribed In PDB    ${mdn}    settle=10s).
# WAIT   : SETTLE 이 끝난 뒤 재조회를 반복하는 총 시간. **SETTLE 과 별개로 센다**
#          — 최대 대기는 SETTLE + WAIT 다.
${CDS_DB_SETTLE}          1s               # ResultAck 수신 → 1차 조회까지의 대기
${CDS_DB_WAIT}            10s              # 반영 대기 총 시간 (SETTLE 이후)
${CDS_DB_WAIT_INTERVAL}   2s               # 재조회 간격

# 조회 대상 테이블 / 서비스 ID
${CDS_DB_TBL_PROFILE}     T_5G_SUBS_PROFILE
${CDS_DB_TBL_SERVICE}     T_5G_SUBS_SERVICE
${CDS_DB_SVC_DATA_USAGE}      DATA_USAGE_LEVEL
${CDS_DB_SVC_DATA_USAGE_2}    DATA_USAGE_LEVEL_2

# 업무 코드별 판정에 쓰는 컬럼 값 (2026-08-07 지정)
${CDS_DB_SVC_ZONE_D}          ZONE_SVC_D               # 1X 가입 / 1Y 해지 대상 SVC_ID
${CDS_DB_SVC_YOUNG_HARM}      YOUNG_HARM_INFO_BLOCK    # I2 신청 / I3 해지 대상 SVC_ID
${CDS_DB_SVC_TYPE_D}          D                        # 1X 의 SVC_TYPE
${CDS_DB_SVC_TYPE_N}          N                        # I2 의 SVC_TYPE
${CDS_DB_TIME_PERIOD_ID}      56                       # I2 의 TIME_PERIOD_ID
${CDS_DB_LIMIT_FLAG}          Y                        # I2 의 LIMIT

# COUNT 조회 SQL — `?` 는 pyodbc 바인딩 자리표시자다(값을 문자열로 잇지 않는다)
${CDS_DB_SQL_PROFILE}     SELECT COUNT(*) FROM ${CDS_DB_TBL_PROFILE} WHERE MDN = ?
${CDS_DB_SQL_SERVICE}     SELECT COUNT(*) FROM ${CDS_DB_TBL_SERVICE} WHERE MDN = ? AND SVC_ID = ?
# 해지(Z1) 판정용 — SVC_ID 를 가리지 않는다. 서비스 행이 **하나라도** 남아 있으면
# 해지가 덜 된 것이므로, 특정 SVC_ID 두 개만 보는 위 SQL 로는 부족하다.
${CDS_DB_SQL_SERVICE_ANY}    SELECT COUNT(*) FROM ${CDS_DB_TBL_SERVICE} WHERE MDN = ?

# 1X(HFC/ZONE 가입) — SVC_ID + SVC_TYPE + JOB_CODE 를 모두 만족하는 행이 1건 이상이어야 한다.
# 해지(1Y) 판정은 위 ${CDS_DB_SQL_SERVICE}(MDN+SVC_ID) 를 그대로 쓰고 0 을 기대한다.
${CDS_DB_SQL_SERVICE_1X}
...    SELECT COUNT(*) FROM ${CDS_DB_TBL_SERVICE} WHERE MDN = ? AND SVC_ID = ? AND SVC_TYPE = ? AND JOB_CODE = ?

# I2(부가서비스신청) — 조건이 6개다. LIMIT 은 **예약어와 겹쳐 큰따옴표로 감쌌다**
# (골디락스/알티베이스 모두 LIMIT 절이 있다). 큰따옴표 식별자는 대소문자를 구분하므로
# 컬럼이 대문자로 만들어져 있어야 맞는다 — 안 맞으면 "컬럼 없음"으로 실패한다.
# 그때는 따옴표를 빼 보고, 그래도 구문 오류면 실제 컬럼명을 확인할 것.
# 해지(I3) 판정은 ${CDS_DB_SQL_SERVICE}(MDN+SVC_ID) 로 0 을 기대한다.
${CDS_DB_SQL_SERVICE_I2}
...    SELECT COUNT(*) FROM ${CDS_DB_TBL_SERVICE} WHERE MDN = ? AND SVC_ID = ? AND SVC_TYPE = ? AND JOB_CODE = ? AND TIME_PERIOD_ID = ? AND "LIMIT" = ?

# C1/G1/D3 — 업무 수행 **전후의 SVC_ID 별 행 수가 같아야** 한다.
#   전: MDN 의 모든 서비스 행을 SVC_ID 로 묶어 센다
#   후: 같은 집계를 **그 업무 코드로 적재된 행만** 대상으로 다시 낸다
# 즉 "기존 서비스가 하나도 빠짐없이 이번 업무 코드로 다시 쓰였는가" 를 본다.
${CDS_DB_SQL_SERVICE_GROUP}
...    SELECT SVC_ID, COUNT(*) FROM ${CDS_DB_TBL_SERVICE} WHERE MDN = ? GROUP BY SVC_ID
${CDS_DB_SQL_SERVICE_GROUP_JOB}
...    SELECT SVC_ID, COUNT(*) FROM ${CDS_DB_TBL_SERVICE} WHERE MDN = ? AND JOB_CODE = ? GROUP BY SVC_ID

# ── 쿠폰/옵션 계열 (Y9 / K1~K6 / SS / ST) ────────────────────────
# 판정 기준은 2026-08-10 에 지정된 표를 그대로 옮긴 것이다.
#
# **주 판정 대상은 가입자 서비스 테이블(${CDS_DB_TBL_SERVICE})이다.**
# K1/K5/Y9 만 예약 큐(${CDS_DB_TBL_RESERVED}) 적재를 **추가로** 본다 — 가입과 동시에
# 만료/사용시점 예약이 걸리기 때문이다.
#
#   코드  동작                    서비스 테이블            예약 큐
#   ----  ----------------------  ----------------------  ---------------
#   K1    Data(Time) 쿠폰 가입    R17 저장 (K1/113/1)      JOB_CODE=K3
#   K2    Data(Time) 쿠폰 해지    R17 삭제 (핀)            —
#   K3    Data(Time) 쿠폰 만료    R17 삭제 (핀)            —
#   K4    Data(Time) 쿠폰 취소    R17 삭제 (핀)            —
#   K5    3Mbps 쿠폰 가입         R17 저장 (K5/0/2)        JOB_CODE=K7
#   K6    3Mbps 쿠폰 해지         R17 삭제 (핀)            —
#   Y9    Zone 쿠폰 사용시점 알림 ZONE_SVC_B 저장 (Y9/25/0) JOB_CODE=Y6
#   SS    0플랜 3시간프리 가입    TIME_SVC_I 저장 (SS/0)   —
#   ST    0플랜 3시간프리 해지    TIME_SVC_I 삭제          —
#
# ★ K2/K3/K4/K6 은 판정 기준이 **완전히 같다**(MDN+R17+CNUM 삭제). 서로 구분되지
#   않으므로 각 TC 는 자기 핀으로 가입을 먼저 만든 뒤 지워지는 것을 봐야 한다.
${CDS_DB_SVC_COUPON}          R17          # K1~K6 쿠폰 SVC_ID
${CDS_DB_SVC_ZONE_B}          ZONE_SVC_B   # Y9 SVC_ID (1X 의 ZONE_SVC_D 와 다르다)
${CDS_DB_SVC_TIME_I}          TIME_SVC_I   # SS/ST SVC_ID

# K1/K5 의 SVC_TYPE 은 I2 와 같은 'N' 이라 위 ${CDS_DB_SVC_TYPE_N} 을 재사용한다.
${CDS_DB_SVC_TYPE_Z}          Z            # Y9 SVC_TYPE
${CDS_DB_SVC_TYPE_T}          T            # SS SVC_TYPE

# TIME_PERIOD_ID / LIMIT — 코드마다 다르다. LIMIT 은 I2 의 'Y' 와 달리 숫자다.
${CDS_DB_TPID_K1}             113          # K1 TIME_PERIOD_ID
${CDS_DB_TPID_K5}             0            # K5 TIME_PERIOD_ID
${CDS_DB_TPID_Y9}             25           # Y9 TIME_PERIOD_ID
${CDS_DB_LIMIT_K1}            1            # K1 LIMIT
${CDS_DB_LIMIT_K5}            2            # K5 LIMIT
${CDS_DB_LIMIT_Y9}            0            # Y9 LIMIT
${CDS_DB_LIMIT_SS}            0            # SS LIMIT
${CDS_DB_CNUM_SS}             0            # SS CNUM (쿠폰이 아니라 0 고정)

# ※ 시간 컬럼은 전부 판정에 들어가 있는데 **폭이 서로 다르다.**
#    K1/K5/Y9 : LIMIT_VALID_TIME = START_TIME + 초 '00'  → 14자리
#    SS       : TIME_PERIOD_ID   = 'SS_' + START_TIME     → 접두 + 12자리
#    기준표가 둘 다 $LIMIT_VALID_TIME 으로 표기해 헷갈리는 자리다.

# 예약 큐 — 테이블 이름이 LTE 와 SA 가 다르다(docs/nodes/CDS.md "LTE / SA 차이"):
#   LTE = T_RESERVED_JOB   /   SA(5G) = T_5G_RESERVED_JOB
# 이 슈트는 가입자 테이블을 T_5G_* 로 보고 있으므로 SA 쪽 이름을 기본값으로 둔다.
${CDS_DB_TBL_RESERVED}        T_5G_RESERVED_JOB

# 인입 업무 코드 → 예약 큐에 실제로 적재되는 JOB_CODE (같지 않다!)
# PG SDM/Syncer/Syncer.cpp SyncReservedJobTBL() 의 INSERT 문에서 확인했다.
${CDS_DB_RSV_JOB_K1}          K3       # K1 가입 → 만료(K3) 예약
${CDS_DB_RSV_JOB_K5}          K7       # K5 가입 → 만료(K7) 예약
${CDS_DB_RSV_JOB_Y9}          Y6       # Y9 + COUPON_TYPE='T' → Y6 (숫자 권종이면 Y8)

# ── 쿠폰 계열 판정 SQL ───────────────────────────────────────────
# 쿠폰 가입 (K1/K5) — 8개 조건. "LIMIT" 은 예약어라 큰따옴표로 감쌌다(I2 SQL 주석 참조).
${CDS_DB_SQL_SERVICE_COUPON}
...    SELECT COUNT(*) FROM ${CDS_DB_TBL_SERVICE} WHERE MDN = ? AND SVC_ID = ? AND SVC_TYPE = ? AND JOB_CODE = ? AND TIME_PERIOD_ID = ? AND "LIMIT" = ? AND LIMIT_VALID_TIME = ? AND CNUM = ?

# Y9 — CNUM 을 걸지 않는 7개 조건.
${CDS_DB_SQL_SERVICE_ZONE_B}
...    SELECT COUNT(*) FROM ${CDS_DB_TBL_SERVICE} WHERE MDN = ? AND SVC_ID = ? AND SVC_TYPE = ? AND JOB_CODE = ? AND TIME_PERIOD_ID = ? AND "LIMIT" = ? AND LIMIT_VALID_TIME = ?

# SS — 7개 조건. 시간을 LIMIT_VALID_TIME 이 아니라 **TIME_PERIOD_ID 로 본다**
# (컬럼 자체는 있지만 SS 판정 기준에 들어 있지 않다 — 'SS_' 접두가 붙은 쪽을 본다).
${CDS_DB_SQL_SERVICE_OPTION}
...    SELECT COUNT(*) FROM ${CDS_DB_TBL_SERVICE} WHERE MDN = ? AND SVC_ID = ? AND SVC_TYPE = ? AND JOB_CODE = ? AND TIME_PERIOD_ID = ? AND "LIMIT" = ? AND CNUM = ?

# 쿠폰 해지/만료/취소 (K2/K3/K4/K6) — MDN + SVC_ID + CNUM 으로 0건.
# ST 해지는 CNUM 이 없으므로 기존 ${CDS_DB_SQL_SERVICE}(MDN+SVC_ID)를 그대로 쓴다.
${CDS_DB_SQL_SERVICE_CNUM}
...    SELECT COUNT(*) FROM ${CDS_DB_TBL_SERVICE} WHERE MDN = ? AND SVC_ID = ? AND CNUM = ?

# 예약 큐 적재 (K1/K5/Y9) — STATUS 는 걸지 않는다. 판정 기준표가 예약 건에 대해
# "시간 확인 필요"로만 남겨 둬 대기/실행 상태를 못 박을 근거가 없기 때문이다.
${CDS_DB_SQL_RESERVED_JOB}
...    SELECT COUNT(*) FROM ${CDS_DB_TBL_RESERVED} WHERE MDN = ? AND JOB_CODE = ? AND COUPON_PIN = ?

# ════════════════════════════════════════════
# 단말·망 필드 (코드 공용) — TODO: 실환경 값으로 교체
#
# A1(신규) / Z1(해지) / C1(기기변경) / G1(정보변경) / D3(번호변경) 이 같은 집합을 쓴다.
# A1 만 min·addSvc 를 추가로 쓴다. Command Download Flow 의 기본 인자로 올라가 있어
# 여기 값을 채우면 해당 필드를 선언한 모든 업무 코드에 반영된다.
#
# ※ 비어 있으면 해당 필드는 공백으로 전송되고, PG 는 그래도 SC 를 돌려준다
#    → 값을 채우지 않으면 이 필드들은 실질적으로 검증되지 않는다.
# ※ ${CDS_DEVICE_TYPE} / ${CDS_PROD_TYPE} 는 위 공통 블록에 있다(중복 정의 금지).
# ════════════════════════════════════════════
${CDS_NETWORK}                 ${EMPTY}    # netId(8)         WCDMA CDMA WiBro LTE 5G 순 플래그
${CDS_TABLET_YN}               ${EMPTY}    # tabPcYn(1)       0=아니오 1=예
${CDS_OS_VER}                  ${EMPTY}    # osVer(2)
${CDS_DEVICE_MODEL}            ${EMPTY}    # termModelCode(4)
${CDS_CA}                      ${EMPTY}    # CA(1)            3=L3 4=L4 (실 전문은 그 밖의 값도 온다)
${CDS_APRF}                    ${EMPTY}    # aprfTermAttri(1) 0=APRF N/A 1=Support
${CDS_IMSI}                    ${EMPTY}    # IMSI(15)         450(MCC)+05(MNC)+국번호(5)+Serial(5)
# 아래 4개는 규격상 A1·Z1 필수(lteCatgy/5gCatgy 는 Default 10)지만
# 실 A1 전문에서 공백으로 관측됐다 → 임의로 채우면 실 전문과 어긋난다. 손잡이만 둔다.
${CDS_MVNO}                    ${EMPTY}    # mvnoCompa(1)
${CDS_MS_TYPE}                 ${EMPTY}    # catMsType(1)     0=해당없음 1=Cat.M1 2=Cat.M1+HDV
${CDS_CATEGORY_LTE}            ${EMPTY}    # lteCatgy(2)      규격 Default 10
${CDS_CATEGORY_5G}             ${EMPTY}    # 5gCatgy(2)       규격 Default 10

