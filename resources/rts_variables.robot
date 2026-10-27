*** Settings ***
Documentation
...    RTS 인터페이스 변수 (접속 정보 / msg_id / 오프셋 상수 / 테스트 데이터)
...
...    로밍 데이터 차단(L1/L2) 연동. PG = Server, RTS = Client.
...    PG 내부 공식 명칭은 RTS 다 — CDS 문서의 PG.RDS(쿠폰 예약작업 폴러)와는
...    별개 인터페이스이므로 혼동하지 말 것 (docs/nodes/RTS.md 참조).
...
...    이번 범위는 SVC_CODE=L1(WCDMA)/L2(LTE) 로밍 데이터 차단·해제(플래그 Y/N)뿐이다.
...    L3/L4(mVoIP 차단)·L5~LE(QoS)는 PG 소스에 분기가 있으나 미사용 확인됨 — TODO.

*** Variables ***

# ════════════════════════════════════════════
# RTS PG 접속 정보 (클라이언트 모드)
# PG = Server, RTS = Client (로밍 데이터 차단 연동)
# ════════════════════════════════════════════
${RTS_PG_HOST}         ${PG_HOST}
${RTS_PG_PORT}         6003             # 현재는 의도적으로 하드코딩(레거시 rts_sim.py 값).
                                         # PG 는 PG_V2.cfg [RTS] 런타임 설정으로 읽지만
                                         # (RTS/CEnv.cpp GetRTSPort()), 도구 쪽 설정파일
                                         # 연동은 TODO — 나중에 붙일 예정.
${RTS_TIMEOUT}         10

# System ID — rts_sim.py(레거시 시뮬레이터) 실코드에서 그대로 확인된 값.
# SCSL00 은 cds_variables.robot 의 ${CDS_SRC_SYS_ID} 와 동일 — 이 도구(로봇)의 공용 식별자.
${RTS_SRC_SYS_ID}      SCSL00           # 로봇(RTS) 자신의 System ID (6자)
${RTS_DST_SYS_ID}      PCRF             # PG.RTS SYSTEM_ID (rts_sim.py 실코드 확인)

# ════════════════════════════════════════════
# RTS msg_id 상수 (RTS/RtsDefine.hpp 그대로, PG 소스로 확정)
# ════════════════════════════════════════════
${MSG_RTS_CONNECT_REQ}      ${1}
${MSG_RTS_CONNECT_ACK}      ${2}
${MSG_RTS_KEEPALIVE_REQ}    ${5}
${MSG_RTS_KEEPALIVE_ACK}    ${6}
${MSG_RTS_RELEASE_REQ}      ${9}
${MSG_RTS_ORDER_REQ}        ${11}
${MSG_RTS_ORDER_ACK}        ${12}

# ════════════════════════════════════════════
# RESULT / REASON (RTS/RtsDefine.hpp 그대로)
# ════════════════════════════════════════════
${RTS_RESULT_SUCCESS}   SC
${RTS_RESULT_FAIL}      FA

${RTS_REASON_NO_ERROR}          ${0}     # E_NO_ERROR
${RTS_REASON_NOT_EXIST}         ${1}     # E_NOT_EXIST
${RTS_REASON_INTERNAL_ERROR}    ${2}     # E_INTERNAL_ERROR
${RTS_REASON_REVERSE_TID}       ${3}     # E_REVERSE_TID_ERROR
${RTS_REASON_DUP_TID}           ${4}     # E_DUP_TID_ERROR
${RTS_REASON_WRONG_SIZE}        ${12}    # E_WRONG_SIZE
${RTS_REASON_NOT_DEFINE}        ${54}    # E_NOT_DEFINE
${RTS_REASON_NO_COUNT}          ${99}    # E_NO_COUNT

# ════════════════════════════════════════════
# SVC_CODE — 이번 범위(L1/L2)만 정식 지원
# 업무단 반영(T_5G_SUBS_SERVICE INSERT) 대상 SVC_ID 는 사용자 확인 — 코드별로 다르다.
# L1/L2 는 ON/OFF 쌍이 아니라 **망 종류**다(사용자 확인, 2026-10-27) —
#  L1 = WCDMA(W_), L2 = LTE(L_). 차단/해제는 코드가 아니라 로밍 플래그(Y/N)로 가른다.
# ════════════════════════════════════════════
${RTS_SVC_L1}   L1    # WCDMA → T_5G_SUBS_SERVICE SVC_ID=W_DATA_ROAMING_BLOCK
${RTS_SVC_L2}   L2    # LTE   → T_5G_SUBS_SERVICE SVC_ID=L_DATA_ROAMING_BLOCK
# L3/L4 = mVoIP 차단, L5/L7/L9/LD/LJ/LL = QoS Param — PG 소스엔 분기가 있으나
# 미사용 확인됨(사용자 확인). TODO — 필요해지면 RtsHelper.pack_rts_order_body 를
# offset15(mvoip)/offset16(qos) 까지 채우도록 확장할 것.

${RTS_SVC_ID_W_DATA_ROAMING_BLOCK}   W_DATA_ROAMING_BLOCK   # L1 반영 SVC_ID (사용자 확인)
${RTS_SVC_ID_L_DATA_ROAMING_BLOCK}   L_DATA_ROAMING_BLOCK   # L2 반영 SVC_ID (사용자 확인)

${RTS_ROAMING_BLOCK_ON}    Y
${RTS_ROAMING_BLOCK_OFF}   N

# ════════════════════════════════════════════
# 테스트 데이터
# ════════════════════════════════════════════
# 11자리 유지 — attachMDN 의 10자리 재배치 분기(RtsHelper.py 모듈 docstring 참조)를 피한다.
${RTS_TEST_MDN}   01090010001

# 패킷 크기 검증(E_WRONG_SIZE=12) negative TC 전용 — 헤더 Data Size 필드만 이 값으로
# 거짓 신고하고 실제 Body(17B, RTS_WIRE_BODY_SIZE)는 그대로 보낸다. 512 초과로 잡는다.
${RTS_DATA_SIZE_OVERSIZED}   600

# ════════════════════════════════════════════
# PDB 접속 문자열은 여기 없다 — CDS 와 **같은 DB** 라(사용자 확인)
# variables.robot 의 ${PDB_CONNSTR} 하나를 같이 쓴다.
# 예전에는 같은 값이 두 벌이라 한쪽만 고치면 어긋났다.

# T_5G_SUBS_SERVICE 반영은 비동기(운영 폴러 경유 추정 — CDS 의 SDM 과 같은 성격)라
# 재조회로 기다린다. CDS 의 ${CDS_DB_WAIT}/${CDS_DB_WAIT_INTERVAL} 과 같은 기본값.
${RTS_DB_WAIT}            10s
${RTS_DB_WAIT_INTERVAL}   2s

# 사전 확인 / 종료 시 정리 — CDS 의 ${CDS_CLEANUP_ON_TEARDOWN} 과 같은 목적이다.
# ★ RTS 도 PROFILE 을 건드린다(사용자 확인, 2026-10-19) — "RTS 는 가입자를
#   안 만든다"던 처음 추정은 틀렸다. PG 가 L1/L2 를 반영할 때 T_5G_SUBS_PROFILE
#   도 같이 upsert 하는 것으로 보인다. 그래서 CDS 와 동형으로 PROFILE/SERVICE
#   둘 다 지운다 — 다만 RTS 는 MDN 이 하나뿐이라(D3 같은 번호변경이 없다)
#   SVC_ID 조건은 SERVICE 쪽에만, PROFILE 쪽은 MDN 하나로 건다.
# SQL 은 CDS 와 같은 관례대로 리터럴을 여기 두고 키워드는 변수만 참조한다.
${RTS_CLEANUP_ON_TEARDOWN}   ${TRUE}
# `run_tests.sh rts --no-cleanup`(CDS 와 공용 플래그)로 끌 수 있다.

${RTS_DB_SQL_PRECHECK_SERVICE}
...    SELECT COUNT(*) FROM T_5G_SUBS_SERVICE WHERE MDN = ? AND SVC_ID IN (?, ?)

${RTS_DB_SQL_PRECHECK_PROFILE}
...    SELECT COUNT(*) FROM T_5G_SUBS_PROFILE WHERE MDN = ?

# 삭제 순서 주의 — SERVICE(자식) 먼저, PROFILE(부모) 나중. CDS 의 Cleanup CDS
# Subscriber Rows 도 같은 순서다(FK 로 추정, cds_variables.robot 참조).
${RTS_DB_SQL_DELETE_SERVICE}
...    DELETE FROM T_5G_SUBS_SERVICE WHERE MDN = ? AND SVC_ID IN (?, ?)

${RTS_DB_SQL_DELETE_PROFILE}
...    DELETE FROM T_5G_SUBS_PROFILE WHERE MDN = ?

# ════════════════════════════════════════════
# PCF SBI Noti 수신 검증 — CDS 와 같은 메커니즘/대상 포트(사용자 확인: RTS 의
# L1/L2 도 SBI Noti 를 유발한다). 도구가 PCF 역할로 Listen 하는 h2c 포트는
# PG 설정에 upstream 별로 안 갈리고 하나다.
#
# 켜고 끄는 손잡이는 **공용**이다 — variables.robot 의 ${SNOTI_PCF_NOTI}.
# 아래 대기 시간만 RTS 가 따로 쥔다(CDS 보다 짧다).
# ════════════════════════════════════════════
${RTS_NOTI_HOST}              0.0.0.0          # bind 주소 — PG 에서 닿는 주소가 아니다
${RTS_NOTI_PORT}              16101            # CDS 의 ${CDS_NOTI_PORT} 와 동일값 (같은 서버를 쓴다)
${RTS_NOTI_WAIT}              12s              # Noti 도착 대기 시간
${RTS_NOTI_MONITOR_INTERVAL}  1s

# TC-RTS-001 전체 재시도(2026-10-01) — Noti/PDB 업무 계층 반영은 비동기라
# ${RTS_NOTI_WAIT}/${RTS_DB_WAIT} 가 추정치다. 타이밍이 빠듯해 실패하면 한 번 더
# 통째로 재시도한다(Send RTS L1 Order And Verify Reflection 전체를 다시 수행).
# 간격을 0s 로 둔 이유: 각 시도 자체가 이미 위 두 대기 시간만큼 기다리므로
# 시도 사이에 추가로 쉴 필요가 없다.
${RTS_TC001_RETRY_COUNT}      2x
${RTS_TC001_RETRY_INTERVAL}   0s
