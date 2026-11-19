# -*- coding: utf-8 -*-
'docs/callflow/cds_callflow.md generator (11 business codes in one file).\n\nThe field set is **picked directly from CdsHelper** — if you move it by hand, it will be out of alignment.\nOther facts (TC number/notification route/judgment criteria) are listed in the table below.\n'
import io
import os
import sys

sys.path.insert(0, 'libraries')
import CdsHelper as H  # noqa: E402

OUT = 'docs/callflow'
SIZES = dict(H._CMD_LAYOUT)


def fields_of(code):
    'Returns the field names filled by this task code in wire order.'
    f = {name: '' for name, _ in H._CMD_LAYOUT}
    kw = {name: '@' for name, _ in H._CMD_LAYOUT}
    H._fill_command_fields(code, kw, f)
    return [n for n, _ in H._CMD_LAYOUT if f[n] != '']


# 코드 → (이름, TC, 경로규칙, 판정, 비고)
#   경로: 'BSUBS-always' | 'BSUBS-if-hfc' | 'SDM'
T = {
 'A1': ('New sign up', 'TC-CDS-002', 'SDM',
        ['`T_5G_SUBS_PROFILE` (MDN) = **1 case**',
         '`T_5G_SUBS_SERVICE` (MDN, `DATA_USAGE_LEVEL`) = **1 case**',
         '`T_5G_SUBS_SERVICE` (MDN, `DATA_USAGE_LEVEL_2`) = **1 case**'],
        'Create a target subscriber for the entire suite to use — if this TC fails, everything falls apart.'),
 '1X': ('Sign up for HFC service', 'TC-CDS-003', 'BSUBS-always',
        ['`T_5G_SUBS_SERVICE` (MDN, `ZONE_SVC_D`, `SVC_TYPE=D`, `JOB_CODE=1X`) = **1 or more cases**'],
        'UPM `0x07` reception → `0x08` response is required to complete.'),
 '1Y': ('Termination of HFC service', 'TC-CDS-004', 'BSUBS-always',
        ['`T_5G_SUBS_SERVICE` (MDN, `ZONE_SVC_D`) = **0 cases** — `SVC_TYPE`/`JOB_CODE` '
         'It does not matter (if it remains in any form, it is less likely to be cancelled)'],
        'Take UPM like 1X — Even if you cancel, you need to organize cell information.'),
 'I2': ('Additional service application', 'TC-CDS-005', 'SDM',
        ['`T_5G_SUBS_SERVICE` (MDN, `YOUNG_HARM_INFO_BLOCK`, `SVC_TYPE=N`, '
         '`JOB_CODE=I2`, `"LIMIT"=Y`) = **1 or more cases**'],
        '`LIMIT` is a reserved word, so it is enclosed in double quotation marks in SQL. `TIME_PERIOD_ID` is '
        'Removed from WHERE clause (2026-09-29) — It is not a decision condition.'),
 'I3': ('Cancellation of additional services', 'TC-CDS-006', 'SDM',
        ['`T_5G_SUBS_SERVICE` (MDN, `YOUNG_HARM_INFO_BLOCK`) = **0 cases**'], ''),
 'C1': ('Change device', 'TC-CDS-007 / 008~014', 'BSUBS-if-hfc',
        ['Number of rows per **Before** `SVC_ID` == Aggregation of rows loaded with **After** `JOB_CODE=C1`'],
        'Because it is a before-and-after comparison type, the `Command Download Flow` **front** baseline is drawn first. '
        'The legacy implementation fills in `min ← mdn`.'),
 'G1': ('Change information', 'TC-CDS-015 / 016~017', 'BSUBS-if-hfc',
        ['Number of rows per **Before** `SVC_ID` == Aggregation of rows loaded with **After** `JOB_CODE=G1`'],
        'The field set is exactly the same as A1 (confirmed on 2026-08-03).'),
 'K1': ('Sign up for Data(Time) coupon', 'TC-CDS-018 / 020', 'SDM',
        ['`T_5G_SUBS_SERVICE` (MDN, `R17`, `SVC_TYPE=N`, `JOB_CODE=K1`, '
         '`"LIMIT"=1`, `LIMIT_VALID_TIME`, `CNUM=COUPON_PIN`) = **1 or more cases** '
         '(PG also stores `TIME_PERIOD_ID=113`, but removes it from the decision WHERE clause, 2026-09-29)',
         '`T_5G_RESERVED_JOB` (MDN, `JOB_CODE=K3`, COUPON_PIN) = **1 or more**'],
        'As soon as you sign up, your reservation will expire. **The entry code (K1) and reservation code (K3) are different.** '
        'K3 is not a message sent by CDS — **PG.RDS makes the reservation when the coupon expires. '
        'Look at the cue and make it yourself.** So K3 does not have a seat. Watching until expiration '
        'With `TC-CDS-020`, it does not send a message and waits until RDS clears it. '
        '`START_TIME` must be in the future — if it is in the past, it expires immediately after joining and the check fails.'),
 'K2': ('Data(Time) Coupon Cancellation', 'TC-CDS-019', 'SDM',
        ['`T_5G_SUBS_SERVICE` (MDN, `R17`, `CNUM=K1_COUPON_PIN`) = **0 cases**'],
        'The criteria for K2/K3/K4/K6 are **literally the same** — they are not distinct from each other, so '
        'Divide pins by task.'),
 'D3': ('Change number', 'TC-CDS-021', 'BSUBS-if-hfc',
        ['Perform **Before** (old number) `SVC_ID` Number of rows per == Perform **After** (new number, `JOB_CODE=D3`) Aggregate'],
        'If successful, `${CDS_ACTIVE_MDN}` is updated with a new number → Z1 behind it is canceled with that number.'),
 'Z1': ('Cancel subscription', 'TC-CDS-028', 'BSUBS-if-hfc',
        ['`T_5G_SUBS_PROFILE` (MDN) = **0 cases**',
         '`T_5G_SUBS_SERVICE` (regardless of MDN, `SVC_ID`) = **0 cases**'],
        'end of the chain. **You can pass even if you have never signed up** — 0 cases are “deleted” and “never existed before” '
        "Can't tell the difference. If HFC (`ZONE_SVC_D`) is attached, **Cell arrangement is included** — "
        'The subscriber table is organized only after BSUBS deletes the CellList.'),
}

# 알림이 아예 나가지 않는 코드 — RBUS NOTI / SNOTI / SBI Noti 를 그리지 않는다.
NO_NOTI = ('Z1',)

# 도구가 현재 알림 판정을 건너뛰는 코드 (@{CDS_NOTI_EXEMPT_CODES})
EXEMPT = ('A1', 'Z1')

ROUTE_LABEL = {
 'BSUBS-always': ('Via BSUBS (**Unconditionally**)', 'Rule 1'),
 'BSUBS-if-hfc': ('HFC **Subscribed** status → BSUBS / **Not subscribed** → SDM', 'Rule 2'),
 'SDM': ('Via SDM', 'Rule 3'),
}

# ── 다이어그램에 그릴 PDB 판정 단계 ──────────────────────────────
# 일반 문구("SELECT COUNT(*) — 반영 판정") 대신 **코드별 실제 조회**를 그린다.
# PRE 는 전문보다 **먼저** 나가는 조회다(전후 비교형 C1/G1/D3 의 기준선).
PDB_PRE = {
 'C1': ['Aggregate number of rows by SVC_ID before performing (MDN)'],
 'G1': ['Aggregate number of rows by SVC_ID before performing (MDN)'],
 'D3': ['Aggregate number of rows by SVC_ID before performing (MDN)'],
}
PDB_POST = {
 # 같은 표를 SVC_ID 만 바꿔 두 번 보므로 화살표는 하나로 합친다.
 # (슈트는 실제로 두 번 조회한다 — 아래 "판정 기준" 절에 각각 적혀 있다)
 'A1': ['Confirm saving T_5G_SUBS_PROFILE (MDN)',
        'Confirm saving T_5G_SUBS_SERVICE (MDN + SVC_ID=DATA_USAGE_LEVEL, DATA_USAGE_LEVEL_2)'],
 '1X': ['Confirm saving T_5G_SUBS_SERVICE (MDN + ZONE_SVC_D + SVC_TYPE=D + JOB_CODE=1X)'],
 '1Y': ['Confirm deletion of T_5G_SUBS_SERVICE (MDN + ZONE_SVC_D) — 0 cases'],
 'I2': ['Confirm saving T_5G_SUBS_SERVICE (MDN + YOUNG_HARM_INFO_BLOCK + N + I2 + TPID=56 + LIMIT=Y)'],
 'I3': ['Confirm deletion of T_5G_SUBS_SERVICE (MDN + YOUNG_HARM_INFO_BLOCK) — 0 cases'],
 'C1': ['Aggregate rows loaded with JOB_CODE=C1 after execution (MDN)'],
 'G1': ['Aggregate rows loaded with JOB_CODE=G1 after execution (MDN)'],
 'K1': ['Confirm saving T_5G_SUBS_SERVICE (MDN + R17 + N + K1 + TPID=113 + LIMIT=1 + LIMIT_VALID_TIME + CNUM)',
        'T_5G_RESERVED_JOB Save Confirmation (MDN + JOB_CODE=K3 + COUPON_PIN)'],
 'K2': ['Confirm deletion of T_5G_SUBS_SERVICE (MDN + R17 + CNUM) — 0 cases'],
 'D3': ['Aggregate rows loaded with JOB_CODE=D3 after execution (NEW MDN)'],
 'Z1': ['Confirm deletion of T_5G_SUBS_PROFILE (MDN) — 0',
        'Confirm deletion of T_5G_SUBS_SERVICE (regardless of MDN, SVC_ID) — 0 cases'],
}

# 판정 구간 배경. 알파를 낮게 둬야 라이트/다크 양쪽에서 글자가 읽힌다.
BAND = 'rgba(255, 176, 32, 0.14)'

# HFC 가 붙어 있으면 PG.CDS 가 전문을 받은 자리에서 BAROD 쪽 지시를 하나 더 넣는다.
# 판정(SELECT)과 지시(INSERT)가 한 덩어리라 opt 는 이 둘만 감싼다.
HFC_ORDER = {
 'C1': 'INSERT T_BAROD_ORDER_HIST',
 'G1': 'INSERT T_BAROD_ORDER_HIST',
 'D3': 'INSERT T_BAROD_ORDER_HIST',
 'Z1': 'INSERT T_BAROD_ORDER_HIST (cancellation instruction)',
}

# 전문 처리가 끝난 **한참 뒤**에 PG.RDS 가 예약 큐를 보고 스스로 하는 일.
# 슈트가 판정하는 구간이 아니라 그림에만 남긴다.
# (2026-08-24 c2c4526 에서 손으로 그려 넣은 것을 생성기로 옮겼다 — 재생성해도 유실되지 않는다.)
RDS_EXPIRY = {
 'K1': ['    RDS->>PDB: SELECT T_5G_RESERVED_JOB(Polling)',
        '    opt START_TIME > NOW() AND STATUS = N',
        '    RDS->>PDB: INSERT T_5G_RESERVED_ORDER_HIST (STATUS=1) create K3 (coupon expired)',
        '    SDM->>PDB: SELECT T_5G_RESERVED_ORDER_HIST(Polling)',
        '    SDM->>PDB: SELECT T_5G_SUBS_PROFILE and SERVICE',
        '    SDM->>PDB: DELETE T_5G_SUBS_SERVICE (MDN, SVC_ID=R17, SVC_TYPE=N, CNUM=COUPON_PIN)',
        '    SDM->>SNOTI: RBUS NOTI',
        '    SDM->>PDB: UPDATE T_RESERVED_ORDER_TID SET TID...',
        '    SNOTI->>PDB: SELECT T_SESSION_INFO (MDN)',
        '    SNOTI->>PDB: SELECT T_SMF_SESSION_INFO (MDN)',
        '    SNOTI->>PCF: SBI Noti (h2c)',
        '    end'],
}

# SDM 의 TID 갱신 위치. 대부분은 반영 직후지만, 아래 코드들은 RBUS NOTI 뒤다.
# 시트(수동 편집)를 그대로 옮긴 것 — I2/I3/K2 는 반대(반영 직후)라 서로 어긋나 있다.
# 어느 쪽이 맞는지 PG 소스로 확인 필요.
TID_AFTER_NOTI = {'A1', '1X', '1Y', 'K1'}

# BSUBS 가 폴링한 뒤 추가로 하는 일. 모르는 코드는 비워 둔다 — 지어내지 않는다.
BSUBS_EXTRA = {
 'Z1': 'DELETE T_BAROD_SUBS_CELLINFO (Delete CellList)',
}

# BSUBS 가 폴링 뒤 UPM 과 왕복하는 코드. PG 소스로 확정(2026-08-24) —
# BSUBS/SIF.cpp processInfoChgReq/Res/processSubsChgReq, BSUBS/BaroDSubDB.sc
# UpdateInfoChg(). (db_step, upm_req, upm_resp)
#
# PG.SDM 은 이 코드들에 대해 doNoti() 를 **무조건** 부른다(HFC 가입 여부와
# 무관하게) — PG 소스 확인(2026-08-28, SDM_5G/SubsProcessing.cpp doNoti(),
# Do() 의 else 가지에서 job code 가 "91"/"92" 가 아니면 호출).
#
# BSUBS 자신은 이 코드들에 대해 **SNOTI 로 알리지 않는다.**
# `processInfoChgReq`/`processInfoChgRes`(`C1`/`G1`), `processSubsChgReq`
# (`D3`) 모두 끝까지 읽어도 `sendnotiByRbus`/`sendnotiByHttp` 호출이 없다 —
# PG 소스로 확인(2026-08-24), 사용자가 재확인(2026-10-16, `D3` 포함).
# **"`D3` 는 BSUBS 경유로도 알려 HFC 가입 상태에서 SBI Noti 가 두 번
# 나간다"던 이전 메모(2026-08-28)는 틀렸다** — BSUBS 가 UPM 왕복만 하고
# 알리지 않는 것은 `C1`/`G1`과 같다. HFC 가입 여부와 무관하게 SBI Noti 는
# SDM 경유 **한 번뿐**이다.
NOTIFY_SDM_ONLY = {'C1', 'G1', 'D3'}

UPM_ROUNDTRIP = {
 'C1': ('UPDATE T_BAROD_SUBS_CELLINFO (MIN/model/status)',
        '0x0d Info-Change-Request', '0x0e Info-Change-Response'),
 'G1': ('UPDATE T_BAROD_SUBS_CELLINFO (model/status)',
        '0x0d Info-Change-Request', '0x0e Info-Change-Response'),
 'D3': (['SELECT T_BAROD_SUBS_CELLINFO (MDN)', 'INSERT T_BAROD_SUBS_CELLINFO (NEW MDN)'],
        '0x05 Subs-Change-Request', '0x06 Subs-Change-Response'),
}

# 값이 리스트면 여러 줄로 나눠 그린다 — C1 은 PROFILE/SERVICE 를 따로 적재한다
# (사용자가 2026-08-24 15:27 수동 커밋 4dab4d9 로 지정, 재생성 때 유실되어 복구).
# SNOTI 가 세션을 조회할 때 붙는 MDN 라벨. 기본은 그냥 MDN — D3 는 번호가
# 이미 바뀐 뒤라 새 번호로 찾는다는 것을 명시해야 한다.
SNOTI_MDN_LABEL = {'D3': 'NEW MDN'}


def snoti_mdn(code):
    return SNOTI_MDN_LABEL.get(code, 'MDN')


# SDM 이 삭제를 실행하기 전에 같은 MDN 의 다른 예약(다른 핀)이 아직
# 대기 중인지 보던 가드. K2 는 PG 소스 수정으로 이 가드가 없어졌다(2026-08-28) —
# 지금은 DELETE T_5G_SUBS_SERVICE 가 무조건 실행된다. 코드 자체는 다른 코드가
# 같은 패턴을 다시 쓸 수 있어 남겨 둔다.
DELETE_GUARD = {}


SDM_APPLY = {
 '1X': 'INSERT T_5G_SUBS_SERVICE (SVC_ID=ZONE_SVC_D)',
 '1Y': 'DELETE FROM T_5G_SUBS_SERVICE WHERE SVC_ID=ZONE_SVC_D',
 'C1': ['INSERT INTO SELECT T_5G_SUBS_PROFILE', 'INSERT INTO SELECT T_5G_SUBS_SERVICE'],
 'G1': ['INSERT INTO SELECT T_5G_SUBS_PROFILE', 'INSERT INTO SELECT T_5G_SUBS_SERVICE', 'UPDATE T_5G_SUBS_SERVICE (SVC_ID=DATA_USAGE_LEVEL, DATA_USAGE_LEVEL_2)'],
 'D3': ['INSERT INTO SELECT T_5G_SUBS_PROFILE (MDN)', 'INSERT INTO SELECT T_5G_SUBS_SERVICE (MDN)'],
 'Z1': 'DELETE T_5G_SUBS_*',
 'I2': 'INSERT T_5G_SUBS_SERVICE (SVC_ID=YOUNG_HARM_INFO_BLOCK)',
 'I3': 'DELETE T_5G_SUBS_SERVICE (SVC_ID=YOUNG_HARM_INFO_BLOCK)',
 'K1': ['INSERT T_5G_RESERVED_JOB (JOB_CODE=K3, CNUM=COUPON_PIN)',
        'INSERT T_5G_SUBS_SERVICE (SVC_ID=R17, SVC_TYPE=N, JOB_CODE=K1, TPID=113, LIMIT=1, CNUM=COUPON_PIN)'],
 'K2': 'DELETE T_5G_SUBS_SERVICE (SVC_ID=R17, CNUM=COUPON_PIN)',
}

# BSUBS 가 Cell 정보에 하는 일. 가입(1X)은 저장, 해지(1Y)는 삭제다.
CELL_STEP = {
 '1X': 'Save T_BAROD_SUBS_CELLINFO',
 '1Y': 'DELETE FROM T_BAROD_SUBS_CELLINFO',
}


def apply_steps(code):
    v = SDM_APPLY.get(code, 'Reflect T_5G_SUBS_*')
    return v if isinstance(v, list) else [v]


HDR = 'participant TOOL as ROBOT (CDS role)\n    participant PCDS as PG.CDS\n    participant PDB as PDB'


def mermaid(code, route):
    L = ['```mermaid', 'sequenceDiagram', '    autonumber', '    ' + HDR]
    if route == 'SDM':
        L.append('    participant SDM as PG.SDM')
        if code in RDS_EXPIRY:
            L.append('    participant RDS as PG.RDS')
    elif route == 'BSUBS-always':
        # 1X/1Y 도 SDM 은 돈다 — 안 하는 것은 RBUS NOTI 뿐이다.
        L.append('    participant SDM as PG.SDM')
        L.append('    participant BSUBS as PG.BSUBS')
        L.append('    participant UPM as ROBOT')
    else:
        L.append('    participant SDM as PG.SDM')
        L.append('    participant BSUBS as PG.BSUBS')
        if code in UPM_ROUNDTRIP:
            L.append('    participant UPM as ROBOT')
    if code not in NO_NOTI:
        L.append('    participant SNOTI as PG.SNOTI')
        L.append('    participant PCF as ROBOT (PCF role)')
    L.append('')
    if code in PDB_PRE:
        L.append('    rect %s' % BAND)
        L.append('    Note over TOOL,PDB: ★ Judgment baseline — must appear before sending a message')
        for step in PDB_PRE[code]:
            L.append('        TOOL->>PDB: %s' % step)
        L.append('    end')
    L.append('    TOOL->>PCDS: 0015 CommandRequest (%s) — Body 327B' % code)
    # 0016 은 **받았다는 확인**이라 처리보다 먼저 나간다. 결과는 0017 이 나른다.
    L.append('    PCDS-->>TOOL: 0016 CommandRequestACK (SC) — Schannel, acknowledgment of receipt')
    L.append('    PCDS->>PDB: INSERT T_CDS_ORDER_HIST')
    if code in ('1X', '1Y'):
        L.append('    PCDS->>PDB: INSERT T_BAROD_ORDER_HIST (address encryption)')
    # 이력 적재의 성패가 0017 의 SC/FA 를 가른다.
    L.append('    alt INSERT success')
    L.append('        PCDS->>PDB: UPDATE T_CDS_ORDER_TID SET TID...')
    if code in HFC_ORDER:
        # PG.CDS 가 답하기 전에 끝내는 일이라 0017 보다 위다.
        # 조회는 분기를 **가르는** 쪽이라 opt 밖이다 — 조건이 어긋나도 나간다.
        L.append('        PCDS->>PDB: SELECT T_5G_SUBS_SERVICE (SVC_ID=ZONE_SVC_D)')
        L.append('        opt ZONE_SVC_D present — Join HFC')
        L.append('            PCDS->>PDB: %s' % HFC_ORDER[code])
        L.append('        end')
    L.append('        PCDS-->>TOOL: 0017 CommandResult (SC) — Rchannel')
    L.append('    else INSERT failed')
    L.append('        PCDS-->>TOOL: 0017 CommandResult (FA) — Rchannel')
    L.append('    end')
    L.append('    TOOL->>PCDS: 0018 CommandResultACK (TID echo)')
    L.append('    Note over TOOL,PCDS: 0017 History loading result — Subscriber reflection is confirmed by PDB judgment below')
    L.append('')
    if route == 'BSUBS-always':
        # 가입자 테이블 반영은 1X/1Y 도 SDM 이 한다. PDB 판정이 보는 행이
        # 여기서 생긴다 — 이 블록이 빠지면 판정 대상이 어디서 왔는지 사라진다.
        L.append('    SDM->>PDB: SELECT T_CDS_ORDER_HIST(Polling)')
        [L.append('    SDM->>PDB: %s' % _s) for _s in apply_steps(code)]
        tid = '    SDM->>PDB: UPDATE T_CDS_ORDER_TID SET TID...'
        if code not in TID_AFTER_NOTI:
            L.append(tid)
        L.append('    SDM--xSNOTI: No RBUS NOTI')
        L.append('    Note over SDM, SNOTI: In case of 1X/1Y, PG.SDM does not do RBUS NOTI — PG.BSUBS does RBUS NOTI')
        if code in TID_AFTER_NOTI:
            L.append(tid)
        L.append('')
        L.append('    BSUBS->>PDB: SELECT T_BAROD_ORDER_HIST(Polling)')
        L.append('    BSUBS->>UPM: 0x07 Subs-Info-Request')
        L.append('    UPM->>BSUBS: 0x08 Subs-Info-Response (Cell List)')
        L.append('    BSUBS->>PDB: %s' % CELL_STEP[code])
        L.append('    BSUBS->>SNOTI: RBUS NOTI')
        if code not in NO_NOTI:
            L.append('    SNOTI->>PDB: SELECT T_SESSION_INFO (%s)' % snoti_mdn(code))
            L.append('    SNOTI->>PDB: SELECT T_SMF_SESSION_INFO (%s)' % snoti_mdn(code))
            L.append('    SNOTI->>PCF: SBI Noti (h2c)')
    elif route == 'SDM':
        L.append('    SDM->>PDB: SELECT T_CDS_ORDER_HIST(Polling)')
        if code in DELETE_GUARD:
            L.append('    SDM->>PDB: %s' % DELETE_GUARD[code])
            L.append('    opt COUNT = 0 — No other reservations pending')
            [L.append('        SDM->>PDB: %s' % _s) for _s in apply_steps(code)]
            L.append('    end')
        else:
            [L.append('    SDM->>PDB: %s' % _s) for _s in apply_steps(code)]
        # 가입자 반영을 끝낸 뒤 SDM 도 TID 를 갱신한다 — PG.CDS 것과 별개로 한 번 더다.
        tid = '    SDM->>PDB: UPDATE T_CDS_ORDER_TID SET TID...'
        if code not in TID_AFTER_NOTI:
            L.append(tid)
        L.append('    SDM->>SNOTI: RBUS NOTI')
        if code in TID_AFTER_NOTI:
            L.append(tid)
        if code not in NO_NOTI:
            L.append('    SNOTI->>PDB: SELECT T_SESSION_INFO (%s)' % snoti_mdn(code))
            L.append('    SNOTI->>PDB: SELECT T_SMF_SESSION_INFO (%s)' % snoti_mdn(code))
            L.append('    SNOTI->>PCF: SBI Noti (h2c)')
    else:
        # C1/G1/D3/Z1 공통. HFC 지시는 위(PG.CDS)에서 이미 나갔고, 여기는
        # BSUBS 가 그것을 집어 처리하는 자리다.
        # SDM 은 HFC 여부와 무관하게 가입자 테이블을 갱신한다 — 먼저 그린다.
        L.append('    SDM->>PDB: SELECT T_CDS_ORDER_HIST(Polling)')
        [L.append('    SDM->>PDB: %s' % _s) for _s in apply_steps(code)]
        L.append('    SDM->>PDB: UPDATE T_CDS_ORDER_TID SET TID...')

        def _bsubs_pre_lines(indent):
            # UPM 응답(0x_e/0x06) 은 코드마다 위치가 달라 여기서 뺀다 — 아래서 각자 넣는다.
            out = []
            out.append('%sBSUBS->>PDB: SELECT T_BAROD_ORDER_HIST(Polling)' % indent)
            if code in BSUBS_EXTRA:
                # Cell 정리를 먼저 끝내고 가입자 테이블을 지운다. 순서가 뒤집히면
                # ZONE_SVC_D 가 먼저 사라져 BSUBS 가 지울 대상을 잃는다.
                out.append('%sBSUBS->>PDB: %s' % (indent, BSUBS_EXTRA[code]))
            if code in UPM_ROUNDTRIP:
                db_step, req, resp = UPM_ROUNDTRIP[code]
                for s in (db_step if isinstance(db_step, list) else [db_step]):
                    out.append('%sBSUBS->>PDB: %s' % (indent, s))
                out.append('%sBSUBS->>UPM: %s' % (indent, req))
            return out

        def _upm_resp_line(indent):
            if code not in UPM_ROUNDTRIP:
                return None
            _, _, resp = UPM_ROUNDTRIP[code]
            return '%sUPM->>BSUBS: %s' % (indent, resp)

        if code in NOTIFY_SDM_ONLY:
            # SDM 은 위와 똑같이 무조건 알린다. BSUBS 는 HFC 가입 상태면
            # UPM 왕복(CellInfo 갱신)을 하지만 **SNOTI 로는 알리지 않는다** —
            # processInfoChgReq/Res 에 sendnotiByRbus/Http 호출이 없다(PG 소스
            # 확인, 2026-08-24 / 2026-10-16 재확인). SBI Noti 는 SDM 경유
            # 한 번뿐이다.
            L.append('    SDM->>SNOTI: RBUS NOTI')
            if code not in NO_NOTI:
                L.append('    SNOTI->>PDB: SELECT T_SESSION_INFO (%s)' % snoti_mdn(code))
                L.append('    SNOTI->>PDB: SELECT T_SMF_SESSION_INFO (%s)' % snoti_mdn(code))
                L.append('    SNOTI->>PCF: SBI Noti (h2c)')
            L.append('    opt ZONE_SVC_D present — Join HFC')
            L.extend(_bsubs_pre_lines('        '))
            resp_line = _upm_resp_line('        ')
            if resp_line:
                L.append(resp_line)
            L.append('        Note over BSUBS,SNOTI: BSUBS does not notify through SNOTI (no sendnotiByRbus/Http call)')
            L.append('    end')
        else:
            # 위 opt 에서 지시가 들어갔을 때만 BSUBS 가 집을 것이 생긴다.
            L.append('    opt ZONE_SVC_D present — Join HFC')
            L.extend(_bsubs_pre_lines('        '))
            resp_line = _upm_resp_line('        ')
            if resp_line:
                L.append(resp_line)
            L.append('    end')
            if code not in NO_NOTI:
                # 보내는 쪽은 갈린다(규칙 2) — 여기는 진짜 alt 다.
                L.append('    alt Join HFC')
                L.append('        BSUBS->>SNOTI: RBUS NOTI')
                L.append('    else Not enrolled in HFC')
                L.append('        SDM->>SNOTI: RBUS NOTI')
                L.append('    end')
            if code not in NO_NOTI:
                L.append('    SNOTI->>PDB: SELECT T_SESSION_INFO (%s)' % snoti_mdn(code))
                L.append('    SNOTI->>PDB: SELECT T_SMF_SESSION_INFO (%s)' % snoti_mdn(code))
                L.append('    SNOTI->>PCF: SBI Noti (h2c)')
    if code in RDS_EXPIRY:
        # 전문 처리가 끝난 한참 뒤, 쿠폰 만료 시각에 PG.RDS 가 스스로 하는 일.
        # 슈트가 판정하는 구간이 아니라 그림에만 남긴다.
        L.append('')
        L.extend(RDS_EXPIRY[code])
        L.append('')
    # TC 의 성패가 갈리는 자리. 위의 전문 왕복과 눈으로 구분되게 밴드로 감싼다.
    L.append('    rect %s' % BAND)
    L.append('    Note over TOOL, PDB: ★ Judgment — Wait for settle after ResultAck → Re-query until reflected')
    for step in PDB_POST.get(code, ['SELECT COUNT(*) — Reflection judgment']):
        L.append('        TOOL->>PDB: %s' % step)
    if code in PDB_PRE:
        L.append('        Note over TOOL,PDB: Success if two aggregates are equal.')
    L.append('    end')
    if code in RDS_EXPIRY:
        L.append('')
    L.append('```')
    return '\n'.join(L)


def anchor(code):
    "Section anchor. Don't rely on automatic anchors for titles with mixed Korean/backticks."
    return 'cds-%s' % code.lower()


def section(code):
    'Business Code One clause. Since the entire document is one file, it starts from h2.'
    name, tc, route, checks, note = T[code]
    label, rule = ROUTE_LABEL[route]
    fs = fields_of(code)
    L = []
    L.append('---')
    L.append('')
    L.append('<a id="%s"></a>' % anchor(code))
    L.append('')
    L.append('## `%s` — %s' % (code, name))
    L.append('')
    L.append('| Item | value |')
    L.append('|---|---|')
    L.append('| Business Code | `%s` |' % code)
    L.append('| test case | %s |' % (
        '`%s`' % tc if tc else '**None** — There is no TC sending this code yet'))
    L.append('| Notification Path | %s — %s |' % (label, rule))
    L.append('| Notification Judgment | %s |' % (
        '**Skip** — in exception list (⚠️ below)' if code in EXEMPT
        else '`Verify SBI Noti Sent` confirms arrival'))
    L.append('| UPM integration | %s |' % ('Receive `0x07` → Reply `0x08`' if code in ('1X', '1Y') else 'None'))
    L.append('| Loading reservation queue | %s |' % (
        'Yes' if code in ('K1', 'K5', 'Y9') else 'None'))
    L.append('| Body field count | %d units / total 327B (fixed) |' % len(fs))
    L.append('')
    if note:
        L.append('> %s' % note)
        L.append('')
    L.append('### Callflow — `%s`' % code)
    L.append('')
    L.append(mermaid(code, route))
    L.append('')
    L.append('### message Body field — `%s`' % code)
    L.append('')
    L.append('Fill in only %d below and leave the rest blank ([Common Rule](#body-common)).' % len(fs))
    L.append('')
    L.append('| # | field | Width (B) |')
    L.append('|---|---|---|')
    for i, n in enumerate(fs, 1):
        L.append('| %d | `%s` | %d |' % (i, n, SIZES[n]))
    L.append('')
    L.append('### Judgment criteria — `%s`' % code)
    L.append('')
    L.append('It is not judged by message round trip (`0016`/`0017`) — [See common rule ](#assertions-common).')
    L.append('')
    for c in checks:
        L.append('- %s' % c)
    L.append('')
    if code in EXEMPT:
        L.append("#### ⚠️ `%s`'s notification judgment is currently turned off" % code)
        L.append('')
        L.append('This code is in `@{CDS_NOTI_EXEMPT_CODES}`(A1 / Z1) '
                 '`Verify SBI Noti Sent` is **skipped**')
        L.append('')
        L.append('However, if the above path rule (2026-08-19) is followed, this code will also be notified — '
                 '**Two instructions are out of sync.** Exception if the rule replaces the previous one. '
                 'You can remove this code from the list, the path is determined, but SNOTI is converted to PCF. '
                 "If you don't want to send it, now is the time.")
        L.append('')
        L.append('**Judgment was not turned on until confirmed** — If you turn it on and get it wrong, TC will make a decision without reason. '
                 'Since it is the one that fails, it is difficult to turn back.')
        L.append('')
    else:
        L.append('The notification is viewed by `Verify SBI Noti Sent %s` (arrival or not). '
                 'Since the path is not distinguished only by reception, it is calculated by rule and included in the failure message.' % code)
        L.append('')
    L.append('<sub>[↑ List of business codes](#code-list)</sub>')
    L.append('')
    return '\n'.join(L)


# TC 번호 순 = 슈트 실행 순서. 바꾸면 목차 표의 순서도 같이 바뀐다.
# 슈트 실행 순서 = 이 순서. **CDS 로 인입되는 코드만** 여기 있다.
# K3(쿠폰 만료)는 PG.RDS 가 만료 시각에 스스로 만드는 것이라 절이 없다(K1 참조).
order = ['A1', '1X', '1Y', 'I2', 'I3', 'C1', 'G1', 'K1', 'K2', 'D3', 'Z1']

# ── 머리말 ────────────────────────────────────────────────────────
# 코드마다 똑같이 반복되던 설명(327B Body / 0016·0017 의 의미)은 여기 한 번만 둔다.
doc = ['# Call flow by CDS business code', '',
       'This developer reference describes PG processing and validation evidence for each CDS business code.',
       '**Field sets are extracted directly from `libraries/CdsHelper.py` `_fill_command_fields()`**,',
       'so the implementation, rather than the specification table, defines the generated layout.', '',
       '> Generated by `gen_callflow.py`. **Do not edit this file directly.**',
       '> Update the generator tables (`T`, `PDB_*`, `SDM_APPLY`, and related data), then regenerate:',
       '> `python docs/callflow/gen_callflow.py` from the repository root.', '',
       '## PG process list', '',
       'These PG processes participate in the flow. **Confirm they are running before integration execution.**',
       'A stopped downstream process can leave message exchanges apparently successful (`0017` returns `SC`)',
       'while DB assertions fail. Process names come from `/PG/CFG/ST.cfg`.', '',
       '| Process | Diagram participant | Responsibility |', '|---|---|---|',
       '| `CDS201` | `PG.CDS` | Receive message, load `T_CDS_ORDER_HIST` / `T_BAROD_ORDER_HIST`, reply `0016`·`0017` |',
       '| `P_SDM601` | `PG.SDM` | **Main Processing** (Goldilocks) — History polling → `T_5G_SUBS_*` reflection → RBUS NOTI |',
       '| `R_SDM601` | `PG.SDM` | **Coupon expiration processing** (Goldilocks) — Pick up and reflect expiration cases created by `RDS601` |',
       '| `P_SDM501` | `PG.SDM` | **For Altibase** with the same role as `P_SDM601` — Runs in the `PCRF_SUPPORT=Y` environment |',
       '| `S_SDM501` | `PG.SDM` | SDM process for Altibase — role unknown, needs confirmation with PG source |',
       '| `R_SDM501` | `PG.SDM` | Coupon expiration processing **for Altibase** with the same role as `R_SDM601` — Runs in the `PCRF_SUPPORT=Y` environment |',
       '| `SNOTI501` | `PG.SNOTI` | SBI Noti to PCF after session inquiry |',
       '| `BSUBS201` | `PG.BSUBS` | BAROD (HFC) processing, UPM round trip, CellList load/delete |',
       '| `RDS601` | `PG.RDS` | Poll reservation queue (`T_5G_RESERVED_JOB`) — generate coupon expiration (`K3`) |', '',
       'The diagram combines SDM into one participant, but two or four processes can be involved.',
       'Business-code application uses `P_SDM601`/`P_SDM501`; only coupon expiration in the K1 section',
       'uses `R_SDM601`/`R_SDM501`. The Altibase `5xx` processes are not running in the current DEV/TB',
       'environments because both have `PCRF_SUPPORT=N`. See the two-HIST-table section of `../../tests/cds/SPEC.md`.',
       '',
       '> Coupon expiration (`K3`) uses `RDS601` followed by `R_SDM601`, unlike other business codes.',
       '> If `TC-CDS-020` fails after its three-minute wait, inspect these two processes.',
       '> If the reservation changes only to `STATUS=E` and there is no expiration message in `T_5G_RESERVED_ORDER_HIST`,',
       '> `R_SDM601` has nothing to consume, so the coupon row remains indefinitely (observed 2026-08-27).', '',

       '## HIST Rules (2026-08-19)', '',
       'The HIST table written by PG.CDS determines whether BSUBS processes a business code.',
       'See the two-HIST-table section of `../../tests/cds/SPEC.md` for write conditions on',
       '`T_CDS_ORDER_HIST` and `T_BAROD_ORDER_HIST`. Apply the following rules from top to bottom.', '',
       '**Processing and SNOTI notification are separate.** BSUBS processes `1X`/`1Y` and notifies SNOTI directly.',
       'For `C1`/`G1`/`D3`, BSUBS polls `T_BAROD_ORDER_HIST` and performs the UPM round trip',
       'to update CellInfo, but **does not notify SNOTI**. SDM sends its own unconditional notification',
       'through a separate path. See the detailed note below.', '',
       '| Rule | Business-code condition | HIST path |', '|---|---|---|',
       '| 1 | `1X`, `1Y` | Always **CDS → BSUBS** (`T_BAROD_ORDER_HIST`) |',
       '| 2 | HFC already subscribed, and `D3`, `C1`, `G1`, or `Z1` | **CDS → BSUBS** (`T_BAROD_ORDER_HIST`) |',
       '| 3 | All codes | Always **CDS → SDM** (`T_CDS_ORDER_HIST`) |', '',
       'Rules 1 and 3 depend only on the business code; rule 2 also depends on HFC subscription state.',
       'Without an HFC subscription, no matching BAROD history is written for rule 2, so BSUBS has',
       'nothing to poll and processing follows the SDM path.', '',
       'The notification paths converge at `PG.SNOTI`; received SBI payloads alone do not identify the origin.',
       'The suite therefore calculates the expected route from these rules and includes it in failures.', '',
       '> Historical observation before the dedicated HFC chain: rule 2 was not exercised while HFC was subscribed.',
       '> `1Y` (004) cancels HFC before `C1` (007), `G1` (015), `D3` (027), and `Z1` (028),',
       '> That earlier ordering exercised SDM paths. Current cases 024–027 explicitly restore HFC before C1/G1/D3; see the CDS node specification.', '',
       '> **BSUBS does not notify SNOTI for `C1`/`G1`/`D3` (confirmed 2026-10-16).**',
       '> `processInfoChgReq`/`processInfoChgRes` (`C1`/`G1`) and `processSubsChgReq` (`D3`)',
       '> contain no `sendnotiByRbus` or `sendnotiByHttp` calls. Even for HFC subscribers, BSUBS',
       '> completes only the UPM CellInfo update. The SBI notification is sent **once**, through SDM',
       '> `doNoti()`. The previous 2026-08-28 note claiming that HFC `D3` sends two SBI notifications',
       '> was incorrect. BSUBS directly notifies SNOTI only for rule 1,',
       '> namely unconditional `1X`/`1Y` processing.', '',
       '> **BSUBS polling and CDS writes may target different DB sets; intent still needs confirmation.**',
       '> With `bSelectAltibase_ == true`, BSUBS `PollingMgr::service` polls only Altibase,',
       '> not Goldilocks. `UpdateCdsHist`, which writes `T_BAROD_ORDER_HIST`, may insert into',
       '> both databases. If read-side selection does not match the write-side configuration,',
       '> updates in the database that BSUBS does not poll can remain unprocessed.',
       '> Check both settings together when changing this configuration.', '',
       '> | Environment | `PCRF_SUPPORT` | `ALTIBASE_USE` | Impact |',
       '> |---|---|---|---|',
       '> | DEV | `N` | `N` | Goldilocks for both writing and reading — matching, no symptoms |',
       '> | TB | `N` | `Y` | Writes both DBs, reads Goldilocks only; no observed symptom because Goldilocks receives every write |', '',
       '> Both current environments use `PCRF_SUPPORT=N`; no resulting symptoms have been observed.',
       '> Check `ALTIBASE_USE` as well whenever an environment switches to `PCRF_SUPPORT=Y`.', '',
       '## How to read diagrams', '',
       'Orange bands (`★ Assertions`) identify the assertions that determine TC success or failure.',
       'Unshaded message exchanges and internal processing provide context. `0017=SC` does not override a failed assertion.',
       'Before/after checks (`C1`, `G1`, `D3`) have two bands: the pre-send baseline and the post-send aggregate.', '',
       '<a id="assertions-common"></a>', '',
       '## Common rule for judgment — judgment is not made through message round trip', '',
       'These rules apply to all 11 codes. Each code section adds its specific acceptance criteria.', '',
       '`0016 CommandRequestACK` acknowledges receipt before processing and cannot prove business success.', '',
       'What `0017 CommandResult` carries is **the success or failure of loading message history**. '
       'If INSERT fails, it is `FA`. If it succeeds, the body content is `SC`, regardless of whether it is business-wise or not.',
       'PG.SDM applies subscriber changes asynchronously, so verify application through PDB assertions.', '',
       '<a id="body-common"></a>', '',
       '## Common rules for message body — always 327B', '',
       'The body is always 327B. Each code fills its own fields and leaves all others space-padded.', '',
       'The source is the `_fill_command_fields()` branch of `libraries/CdsHelper.py` — '
       '**This code, not the specifications, is the standard for the wire.**',
       'Fields not handled by a code branch are silently discarded even when supplied.', '',
       '<a id="code-list"></a>', '',
       '## Business code', '',
       'All 11 listed codes are actually sent by the suite. `K3` is not a CDS input code:',
       'PG.RDS creates it when the reservation queue reaches coupon expiration time.',
       'See the final two steps in [K1](#cds-k1).', '',
       '| Business code | Description | TC | Route | Notification assertion |', '|---|---|---|---|---|']
for c in order:
    name, tc, route, _, _ = T[c]
    lbl = {'BSUBS-always': 'BSUBS (unconditional)',
           'BSUBS-if-hfc': 'BSUBS/SDM (HFC status)',
           'SDM': 'SDM'}[route]
    mark = 'Skip ⚠️' if c in EXEMPT else 'OK'
    doc.append('| [`%s`](#%s) | %s | %s | %s | %s |' % (
        c, anchor(c), name, '`%s`' % tc if tc else '— (no TC)', lbl, mark))
doc += ['', '⚠️ = Skip the judgment in `@{CDS_NOTI_EXEMPT_CODES}`. '
        'This is a point that violates the above route rules, so confirmation is required (see ⚠️ in the relevant section).', '']

# ── 코드별 절 ─────────────────────────────────────────────────────
for code in order:
    doc.append(section(code))
    print('  %-4s %2d fields' % (code, len(fields_of(code))))

doc += ['---', '', '## Other documents', '',
        '- [../../tests/cds/SPEC.md](../../tests/cds/SPEC.md) — CDS node specifications (encoding table, pitfalls, LTE/SA differences)',
        '- `tests/cds/cds_tests.robot` — TCs in the table above',
        '- `libraries/CdsHelper.py` — `_fill_command_fields()` (source of field set)', '']

out = os.path.join(OUT, 'cds_callflow.md')
io.open(out, 'w', encoding='utf-8', newline='').write(chr(10).join(doc))
print('%s : merged %d codes' % (out, len(order)))
