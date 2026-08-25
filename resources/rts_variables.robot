*** Settings ***
Documentation
...    RTS 인터페이스 변수 (접속 정보 / msg_id / 오프셋 상수 / 테스트 데이터)
...
...    로밍 데이터 차단(L1/L2) 연동. PG = Server, RTS = Client.
...    PG 내부 공식 명칭은 RTS 다 — CDS 문서의 PG.RDS(쿠폰 예약작업 폴러)와는
...    별개 인터페이스이므로 혼동하지 말 것 (docs/nodes/RTS.md 참조).
...
...    이번 범위는 SVC_CODE=L1(로밍 데이터 차단 ON)/L2(차단 해제)뿐이다.
...    L3/L4(mVoIP 차단)·L5~LE(QoS)는 PG 소스에 분기가 있으나 미사용 확인됨 — TODO.

*** Variables ***

# ════════════════════════════════════════════
# RTS PG 접속 정보 (클라이언트 모드)
# PG = Server, RTS = Client (로밍 데이터 차단 연동)
# ════════════════════════════════════════════
${RTS_PG_HOST}         ${PG_HOST}
${RTS_PG_PORT}         6003             # ★ 확인 필요 — PG_V2.cfg [RTS] 섹션 런타임 설정값.
                                         #   소스(RTS/CEnv.cpp GetRTSPort())엔 하드코딩이 없어
                                         #   레거시 rts_sim.py 의 예시값을 그대로 쓴 미검증 추정치다.
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
# (L1/L2 를 단순 ON/OFF 토글 쌍으로 단정하지 않는다 — SVC_ID 가 서로 다른 걸 보면
#  코드마다 별개의 차단 유형일 가능성이 있다. 정확한 의미는 확인 필요.)
# ════════════════════════════════════════════
${RTS_SVC_L1}   L1    # → T_5G_SUBS_SERVICE INSERT (SVC_ID=W_DATA_ROAMING_BLOCK)
${RTS_SVC_L2}   L2    # → T_5G_SUBS_SERVICE INSERT (SVC_ID=L_DATA_ROAMING_BLOCK)
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

# ════════════════════════════════════════════
# PDB 접속 문자열 — ★ 확인 필요
# T_RTS_ORDER_HIST 가 CDS 와 같은 DSN/계정으로 조회 가능한지 미확인
# (라우팅 키 "SUBSCRIBER" 는 CDS 와 같음을 PG 소스로 확인했으나, tc4robot 외부
#  접속 계정이 같은지는 별개 문제 — docs/nodes/RTS.md 확인 필요 절 참조).
# 비워 두면 `Verify RTS Order In PDB` 가 ${CDS_DB_CONNSTR} 를 시도하고, 그것도
# 없으면 TC 를 Skip 한다(CDS 처럼 Suite 전체를 막지 않는다).
${RTS_DB_CONNSTR}   ${EMPTY}

# T_5G_SUBS_SERVICE 반영은 비동기(운영 폴러 경유 추정 — CDS 의 SDM 과 같은 성격)라
# 재조회로 기다린다. CDS 의 ${CDS_DB_WAIT}/${CDS_DB_WAIT_INTERVAL} 과 같은 기본값.
${RTS_DB_WAIT}            10s
${RTS_DB_WAIT_INTERVAL}   2s
