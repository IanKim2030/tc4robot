# -*- coding: utf-8 -*-
"""docs/callflow/CDS_<업무코드>.md 생성기.

필드 집합은 **CdsHelper 에서 직접 뽑는다** — 손으로 옮기면 어긋난다.
그 밖의 사실(TC 번호 / 알림 경로 / 판정 기준)은 아래 표가 쥔다.
"""
import io
import os
import sys

sys.path.insert(0, 'resources')
import CdsHelper as H  # noqa: E402

OUT = 'docs/callflow'
SIZES = dict(H._CMD_LAYOUT)


def fields_of(code):
    """이 업무 코드가 채우는 필드 이름을 wire 순서로 돌려준다."""
    f = {name: '' for name, _ in H._CMD_LAYOUT}
    kw = {name: '@' for name, _ in H._CMD_LAYOUT}
    H._fill_command_fields(code, kw, f)
    return [n for n, _ in H._CMD_LAYOUT if f[n] != '']


# 코드 → (이름, TC, 경로규칙, 판정, 비고)
#   경로: 'BSUBS-always' | 'BSUBS-if-hfc' | 'SDM'
T = {
 'A1': ('신규가입', 'TC-CDS-002', 'SDM',
        ['`T_5G_SUBS_PROFILE` (MDN) = **1건**',
         '`T_5G_SUBS_SERVICE` (MDN, `DATA_USAGE_LEVEL`) = **1건**',
         '`T_5G_SUBS_SERVICE` (MDN, `DATA_USAGE_LEVEL_2`) = **1건**'],
        '슈트 전체가 쓰는 대상 가입자를 만든다 — 이 TC 가 실패하면 뒤가 전부 흔들린다.'),
 '1X': ('HFC 서비스 가입', 'TC-CDS-003', 'BSUBS-always',
        ['`T_5G_SUBS_SERVICE` (MDN, `ZONE_SVC_D`, `SVC_TYPE=D`, `JOB_CODE=1X`) = **1건 이상**'],
        'UPM `0x07` 수신 → `0x08` 응답까지 해야 완결된다. PG 내부 상세는 '
        '[CDS_X1.md](CDS_X1.md).'),
 '1Y': ('HFC 서비스 해지', 'TC-CDS-004', 'BSUBS-always',
        ['`T_5G_SUBS_SERVICE` (MDN, `ZONE_SVC_D`) = **0건** — `SVC_TYPE`/`JOB_CODE` 를 '
         '가리지 않는다(어떤 형태로든 남으면 해지가 덜 된 것)'],
        '1X 과 같이 UPM 을 탄다 — 해지도 Cell 정보를 정리해야 한다.'),
 'I2': ('부가서비스신청', 'TC-CDS-005', 'SDM',
        ['`T_5G_SUBS_SERVICE` (MDN, `YOUNG_HARM_INFO_BLOCK`, `SVC_TYPE=N`, '
         '`JOB_CODE=I2`, `TIME_PERIOD_ID=56`, `"LIMIT"=Y`) = **1건 이상**'],
        '`LIMIT` 은 예약어라 SQL 에서 큰따옴표로 감싼다.'),
 'I3': ('부가서비스해지', 'TC-CDS-006', 'SDM',
        ['`T_5G_SUBS_SERVICE` (MDN, `YOUNG_HARM_INFO_BLOCK`) = **0건**'], ''),
 'C1': ('기기변경', 'TC-CDS-007', 'BSUBS-if-hfc',
        ['수행 **전** `SVC_ID` 별 행 수 == 수행 **후** `JOB_CODE=C1` 로 적재된 행의 집계'],
        '전후 비교형이라 `Command Download Flow` **앞에서** 기준선을 먼저 뜬다. '
        '레거시 구현이 `min ← mdn` 으로 채운다.'),
 'G1': ('정보변경', 'TC-CDS-008', 'BSUBS-if-hfc',
        ['수행 **전** `SVC_ID` 별 행 수 == 수행 **후** `JOB_CODE=G1` 로 적재된 행의 집계'],
        '필드 집합이 A1 과 완전히 같다(2026-08-03 확인).'),
 'K1': ('Data(Time) 쿠폰 가입', 'TC-CDS-011', 'SDM',
        ['`T_5G_SUBS_SERVICE` (MDN, `R17`, `SVC_TYPE=N`, `JOB_CODE=K1`, '
         '`TIME_PERIOD_ID=113`, `"LIMIT"=1`, `LIMIT_VALID_TIME`, `CNUM=핀`) = **1건 이상**',
         '`T_5G_RESERVED_JOB` (MDN, `JOB_CODE=K3`, 핀) = **1건 이상**'],
        '가입과 동시에 만료 예약이 걸린다. **인입 코드(K1)와 예약 코드(K3)가 다르다.** '
        '`START_TIME` 은 반드시 미래여야 한다 — 과거면 가입 직후 만료돼 판정이 실패한다.'),
 'K2': ('Data(Time) 쿠폰 해지', 'TC-CDS-012', 'SDM',
        ['`T_5G_SUBS_SERVICE` (MDN, `R17`, `CNUM=K1 의 핀`) = **0건**'],
        'K2/K3/K4/K6 은 판정 기준이 **글자 그대로 같다** — 서로 구분되지 않으므로 '
        '핀을 업무별로 나눠 쓴다.'),
 'K4': ('Data(Time) 쿠폰 취소', 'TC-CDS-013', 'SDM',
        ['`T_5G_SUBS_SERVICE` (MDN, `R17`, `CNUM=K4 전용 핀`) = **0건**'],
        'TC 안에서 K1 으로 먼저 가입시킨 뒤 취소한다 — "0건" 이 "지워졌다" 인지 '
        '"원래 없었다" 인지 구분되지 않기 때문이다.'),
 'K3': ('Data(Time) 쿠폰 만료', 'TC-CDS-014', 'SDM',
        ['`T_5G_SUBS_SERVICE` (MDN, `R17`, `CNUM=K3 전용 핀`) = **0건**'],
        'K4 와 같은 구조. 다만 준비용 K1 의 `START_TIME` 이 **현재 시각**이다 — '
        '유효기간이 찬 쿠폰이 필요하기 때문이다.'),
 'K5': ('Data(Time) 3Mbps 쿠폰 가입', 'TC-CDS-009', 'SDM',
        ['`T_5G_SUBS_SERVICE` (MDN, `R17`, `SVC_TYPE=N`, `JOB_CODE=K5`, '
         '`TIME_PERIOD_ID=0`, `"LIMIT"=2`, `LIMIT_VALID_TIME`, `CNUM=핀`) = **1건 이상**',
         '`T_5G_RESERVED_JOB` (MDN, `JOB_CODE=K7`, 핀) = **1건 이상**'],
        'K1 과 같은 구조. 예약 큐 코드는 K7 이다.'),
 'K6': ('Data(Time) 3Mbps 쿠폰 해지', 'TC-CDS-010', 'SDM',
        ['`T_5G_SUBS_SERVICE` (MDN, `R17`, `CNUM=K5 의 핀`) = **0건**'], ''),
 'Y9': ('Data(Zone) 쿠폰 사용시점 알림', 'TC-CDS-015', 'SDM',
        ['`T_5G_SUBS_SERVICE` (MDN, `ZONE_SVC_B`, `SVC_TYPE=Z`, `JOB_CODE=Y9`, '
         '`TIME_PERIOD_ID=25`, `"LIMIT"=0`, `LIMIT_VALID_TIME`) = **1건 이상**',
         '`T_5G_RESERVED_JOB` (MDN, `JOB_CODE=Y6`, 핀) = **1건 이상**'],
        '`SVC_ID` 가 1X 의 `ZONE_SVC_D` 와 다르다(`ZONE_SVC_B`). '
        '`COUPON_TYPE=T` 여야 예약 큐에 Y6 이 들어간다 — 숫자면 Y8 이다.'),
 'SS': ('0플랜 옵션(3시간 프리) 가입', 'TC-CDS-016', 'SDM',
        ['`T_5G_SUBS_SERVICE` (MDN, `TIME_SVC_I`, `SVC_TYPE=T`, `JOB_CODE=SS`, '
         "`TIME_PERIOD_ID='SS_' + START_TIME(12자리)`, `\"LIMIT\"=0`, `CNUM=0`) = **1건 이상**"],
        '시간을 `LIMIT_VALID_TIME` 이 아니라 **`TIME_PERIOD_ID` 로 본다.** '
        'K1/K5/Y9 처럼 초 `00` 이 붙지 않는 12자리다 — 헷갈리는 자리다.'),
 'ST': ('0플랜 옵션(3시간 프리) 해지', 'TC-CDS-017', 'SDM',
        ['`T_5G_SUBS_SERVICE` (MDN, `TIME_SVC_I`) = **0건**'],
        'CNUM 이 없어 `MDN + SVC_ID` 로만 판정한다.'),
 'D3': ('번호변경', 'TC-CDS-018', 'BSUBS-if-hfc',
        ['수행 **전**(옛 번호) `SVC_ID` 별 행 수 == 수행 **후**(새 번호, `JOB_CODE=D3`) 집계'],
        '성공하면 `${CDS_ACTIVE_MDN}` 을 새 번호로 갱신한다 → 뒤의 Z1 이 그 번호로 해지한다.'),
 'Z1': ('가입해지', 'TC-CDS-019', 'BSUBS-if-hfc',
        ['`T_5G_SUBS_PROFILE` (MDN) = **0건**',
         '`T_5G_SUBS_SERVICE` (MDN, `SVC_ID` 무관) = **0건**'],
        '체인의 끝. **가입한 적이 없어도 통과한다** — 0건은 "지워졌다"와 "원래 없었다"를 '
        '구분하지 못한다.'),
}

# 도구가 현재 알림 판정을 건너뛰는 코드 (@{CDS_NOTI_EXEMPT_CODES})
EXEMPT = ('A1', '1Y', 'Z1')

ROUTE_LABEL = {
 'BSUBS-always': ('BSUBS 경유 (**무조건**)', '규칙 1'),
 'BSUBS-if-hfc': ('HFC **가입** 상태 → BSUBS / **미가입** → SDM', '규칙 2'),
 'SDM': ('SDM 경유', '규칙 3'),
}

# ── 다이어그램에 그릴 PDB 판정 단계 ──────────────────────────────
# 일반 문구("SELECT COUNT(*) — 반영 판정") 대신 **코드별 실제 조회**를 그린다.
# PRE 는 전문보다 **먼저** 나가는 조회다(전후 비교형 C1/G1/D3 의 기준선).
PDB_PRE = {
 'C1': ['수행 전 SVC_ID 별 행 수 집계 (MDN)'],
 'G1': ['수행 전 SVC_ID 별 행 수 집계 (MDN)'],
 'D3': ['수행 전 SVC_ID 별 행 수 집계 (옛 MDN)'],
}
PDB_POST = {
 'A1': ['T_5G_SUBS_PROFILE 저장 확인 (MDN)',
        'T_5G_SUBS_SERVICE 저장 확인 (MDN + SVC_ID=DATA_USAGE_LEVEL)',
        'T_5G_SUBS_SERVICE 저장 확인 (MDN + SVC_ID=DATA_USAGE_LEVEL_2)'],
 '1X': ['T_5G_SUBS_SERVICE 저장 확인 (MDN + ZONE_SVC_D + SVC_TYPE=D + JOB_CODE=1X)'],
 '1Y': ['T_5G_SUBS_SERVICE 삭제 확인 (MDN + ZONE_SVC_D) — 0건'],
 'I2': ['T_5G_SUBS_SERVICE 저장 확인 (MDN + YOUNG_HARM_INFO_BLOCK + N + I2 + TPID=56 + LIMIT=Y)'],
 'I3': ['T_5G_SUBS_SERVICE 삭제 확인 (MDN + YOUNG_HARM_INFO_BLOCK) — 0건'],
 'C1': ['수행 후 JOB_CODE=C1 로 적재된 행 집계 (MDN)'],
 'G1': ['수행 후 JOB_CODE=G1 로 적재된 행 집계 (MDN)'],
 'K1': ['T_5G_SUBS_SERVICE 저장 확인 (MDN + R17 + N + K1 + TPID=113 + LIMIT=1 + LIMIT_VALID_TIME + CNUM)',
        'T_5G_RESERVED_JOB 저장 확인 (MDN + JOB_CODE=K3 + 핀)'],
 'K2': ['T_5G_SUBS_SERVICE 삭제 확인 (MDN + R17 + CNUM) — 0건'],
 'K3': ['T_5G_SUBS_SERVICE 삭제 확인 (MDN + R17 + CNUM) — 0건'],
 'K4': ['T_5G_SUBS_SERVICE 삭제 확인 (MDN + R17 + CNUM) — 0건'],
 'K5': ['T_5G_SUBS_SERVICE 저장 확인 (MDN + R17 + N + K5 + TPID=0 + LIMIT=2 + LIMIT_VALID_TIME + CNUM)',
        'T_5G_RESERVED_JOB 저장 확인 (MDN + JOB_CODE=K7 + 핀)'],
 'K6': ['T_5G_SUBS_SERVICE 삭제 확인 (MDN + R17 + CNUM) — 0건'],
 'Y9': ['T_5G_SUBS_SERVICE 저장 확인 (MDN + ZONE_SVC_B + Z + Y9 + TPID=25 + LIMIT=0 + LIMIT_VALID_TIME)',
        'T_5G_RESERVED_JOB 저장 확인 (MDN + JOB_CODE=Y6 + 핀)'],
 'SS': ['T_5G_SUBS_SERVICE 저장 확인 (MDN + TIME_SVC_I + T + SS + TPID=SS_+START_TIME + LIMIT=0 + CNUM=0)'],
 'ST': ['T_5G_SUBS_SERVICE 삭제 확인 (MDN + TIME_SVC_I) — 0건'],
 'D3': ['수행 후 JOB_CODE=D3 로 적재된 행 집계 (새 MDN)'],
 'Z1': ['T_5G_SUBS_PROFILE 삭제 확인 (MDN) — 0건',
        'T_5G_SUBS_SERVICE 삭제 확인 (MDN, SVC_ID 무관) — 0건'],
}

HDR = """participant TOOL as 도구 (CDS 역할)
    participant PCDS as PG.CDS
    participant PDB as PDB"""


def mermaid(code, route):
    L = ['```mermaid', 'sequenceDiagram', '    autonumber', '    ' + HDR]
    if route == 'SDM':
        L.append('    participant SDM as PG.SDM')
    elif route == 'BSUBS-always':
        L.append('    participant BSUBS as PG.BSUBS')
        L.append('    participant UPM as 도구 (UPM 역할)')
    else:
        L.append('    participant SDM as PG.SDM')
        L.append('    participant BSUBS as PG.BSUBS')
    L.append('    participant SNOTI as PG.SNOTI')
    L.append('    participant PCF as 도구 (PCF 역할)')
    L.append('')
    for step in PDB_PRE.get(code, []):
        L.append('    TOOL->>PDB: %s' % step)
    if code in PDB_PRE:
        L.append('    Note over TOOL,PDB: 기준선은 전문을 보내기 전에 떠야 한다')
    L.append('    TOOL->>PCDS: 0015 CommandRequest (%s) — Body 327B' % code)
    L.append('    PCDS->>PDB: INSERT T_CDS_ORDER_HIST')
    if code in ('1X', '1Y'):
        L.append('    PCDS->>PDB: INSERT T_BAROD_ORDER_HIST (주소 암호화)')
    L.append('    PCDS-->>TOOL: 0016 CommandRequestACK (SC) — Schannel')
    L.append('    PCDS-->>TOOL: 0017 CommandResult (SC) — Rchannel')
    L.append('    TOOL->>PCDS: 0018 CommandResultACK (TID 에코)')
    L.append('    Note over TOOL,PCDS: 0017 의 SC 는 접수 결과다 — 반영은 PDB 로만 판정된다')
    L.append('')
    if route == 'BSUBS-always':
        L.append('    BSUBS->>PDB: T_BAROD_ORDER_HIST 주기 폴링')
        L.append('    BSUBS->>UPM: 0x07 Subs-Info-Request')
        L.append('    UPM->>BSUBS: 0x08 Subs-Info-Response (Cell List)')
        L.append('    BSUBS->>PDB: T_BAROD_SUBS_CELLINFO 저장')
        L.append('    BSUBS->>SNOTI: RBUS NOTI')
        L.append('    Note over BSUBS,SNOTI: SDM 은 1X/1Y 에 RBUS NOTI 를 보내지 않는다 — 깨우는 쪽은 BSUBS 다')
    elif route == 'SDM':
        L.append('    SDM->>PDB: T_CDS_ORDER_HIST 조회 (폴링)')
        L.append('    SDM->>PDB: T_5G_SUBS_* 반영')
        L.append('    SDM->>SNOTI: RBUS NOTI')
    else:
        L.append('    alt HFC 가입 상태')
        L.append('        BSUBS->>PDB: T_BAROD_ORDER_HIST 주기 폴링')
        L.append('        BSUBS->>SNOTI: RBUS NOTI')
        L.append('    else HFC 미가입')
        L.append('        SDM->>PDB: T_5G_SUBS_* 반영')
        L.append('        SDM->>SNOTI: RBUS NOTI')
        L.append('    end')
    L.append('    SNOTI->>PCF: SBI Noti (h2c)')
    L.append('    Note over TOOL,PDB: ResultAck 뒤 settle 대기 → 반영될 때까지 재조회')
    for step in PDB_POST.get(code, ['SELECT COUNT(*) — 반영 판정']):
        L.append('    TOOL->>PDB: %s' % step)
    if code in PDB_PRE:
        L.append('    Note over TOOL,PDB: 두 집계가 같으면 성공')
    L.append('```')
    return '\n'.join(L)


def render(code):
    name, tc, route, checks, note = T[code]
    label, rule = ROUTE_LABEL[route]
    fs = fields_of(code)
    L = []
    L.append('# CDS `%s` — %s' % (code, name))
    L.append('')
    L.append('| 항목 | 값 |')
    L.append('|---|---|')
    L.append('| 업무 코드 | `%s` |' % code)
    L.append('| 테스트 케이스 | `%s` |' % tc)
    L.append('| 알림 경로 | %s — %s |' % (label, rule))
    L.append('| 알림 판정 | %s |' % (
        '**건너뜀** — 예외 목록에 있음 (아래 ⚠️)' if code in EXEMPT
        else '`Verify SBI Noti Sent` 가 도착을 확인'))
    L.append('| UPM 연동 | %s |' % ('`0x07` 수신 → `0x08` 응답' if code in ('1X', '1Y') else '없음'))
    L.append('| 예약 큐 적재 | %s |' % (
        '있음' if code in ('K1', 'K5', 'Y9') else '없음'))
    L.append('| Body 필드 수 | %d개 / 총 327B (고정) |' % len(fs))
    L.append('')
    if note:
        L.append('> %s' % note)
        L.append('')
    L.append('## 콜플로우')
    L.append('')
    L.append(mermaid(code, route))
    L.append('')
    L.append('## 전문 Body 필드')
    L.append('')
    L.append('Body 는 업무 코드와 무관하게 **항상 327B** 다. 아래 필드만 채우고 나머지는 공백이다.')
    L.append('')
    L.append('| # | 필드 | 폭(B) |')
    L.append('|---|---|---|')
    for i, n in enumerate(fs, 1):
        L.append('| %d | `%s` | %d |' % (i, n, SIZES[n]))
    L.append('')
    L.append('출처는 `resources/CdsHelper.py` 의 `_fill_command_fields()` 분기다 — '
             '**규격서가 아니라 이 코드가 와이어의 기준이다.**')
    L.append('★ 분기가 선언하지 않은 필드는 값을 넘겨도 **조용히 버려진다.**')
    L.append('')
    L.append('## 판정 기준')
    L.append('')
    L.append('`CommandResult(0017)` 는 Body 내용과 무관하게 `SC` 를 준다. 실제 반영은 PDB 로만 판정된다.')
    L.append('')
    for c in checks:
        L.append('- %s' % c)
    L.append('')
    if code in EXEMPT:
        L.append('### ⚠️ 알림 판정은 현재 꺼져 있다')
        L.append('')
        L.append('이 코드는 `@{CDS_NOTI_EXEMPT_CODES}`(A1 / 1Y / Z1)에 들어 있어 '
                 '`Verify SBI Noti Sent` 가 **건너뛴다.**')
        L.append('')
        L.append('그런데 위 경로 규칙(2026-08-19)대로면 이 코드도 알림이 나간다 — '
                 '**두 지시가 어긋나 있다.** 규칙이 앞의 것을 대체하는 것이면 예외 '
                 '목록에서 이 코드를 빼면 되고, 경로는 정해지지만 SNOTI 가 PCF 로 '
                 '보내지 않는 것이면 지금이 맞다.')
        L.append('')
        L.append('확인되기 전까지 **판정을 켜지 않았다** — 켜서 틀리면 TC 가 이유 없이 '
                 '실패하는 쪽이라 되돌리기 어렵다.')
        L.append('')
    else:
        L.append('알림은 `Verify SBI Noti Sent %s` 가 본다(도착 여부). '
                 '경로는 수신만으로 구분되지 않아 규칙으로 계산해 실패 메시지에 싣는다.' % code)
        L.append('')
    L.append('## 관련 문서')
    L.append('')
    L.append('- [CDS 노드 스펙](../nodes/CDS.md) — 인코딩 표, 함정, LTE/SA 차이')
    L.append('- [1X 전문 End-to-End](CDS_X1.md) — PG 내부 프로세스 상세')
    L.append('- `tests/cds/cds_tests.robot` — `%s`' % tc)
    L.append('')
    return '\n'.join(L)


# TC 번호 순 = 슈트 실행 순서. 바꾸면 인덱스 표의 순서도 같이 바뀐다.
order = ['A1', '1X', '1Y', 'I2', 'I3', 'C1', 'G1',
         'K5', 'K6', 'K1', 'K2', 'K4', 'K3', 'Y9', 'SS', 'ST', 'D3', 'Z1']
for code in order:
    path = os.path.join(OUT, 'CDS_%s.md' % code)
    io.open(path, 'w', encoding='utf-8', newline='').write(render(code))
    print('%-28s %2d 필드' % (path, len(fields_of(code))))
print('\n총 %d개' % len(order))


# ── 인덱스 ────────────────────────────────────────────────────────
idx = ['# CDS 업무 코드별 콜플로우', '',
       '전문 하나가 PG 안에서 어떤 경로로 흐르고 무엇으로 판정되는지를 업무 코드별로 정리했다.',
       '**필드 집합은 `resources/CdsHelper.py` 의 `_fill_command_fields()` 에서 뽑은 것**이라',
       '규격서가 아니라 코드가 기준이다.', '',
       '## 알림 경로 규칙 (2026-08-19)', '',
       '위에서부터 차례로 적용한다.', '',
       '| # | 조건 | 경로 |', '|---|---|---|',
       '| 1 | `1X` · `1Y` | 무조건 **BSUBS** |',
       '| 2 | HFC 가입 상태 + `D3` `C1` `G1` `Z1` | **BSUBS** |',
       '| 3 | 그 외 전부 | **SDM** |', '',
       '두 경로는 `PG.SNOTI` 에서 합류해 같은 SBI Noti 로 나간다 — **수신만으로는 구분되지 않는다.**',
       '그래서 슈트는 규칙으로 예상 경로를 계산해 실패 메시지에 싣는다.', '',
       '> ⚠️ 지금 슈트 순서로는 **규칙 2 의 BSUBS 분기를 타는 TC 가 하나도 없다.**',
       '> `1Y`(004)가 HFC 를 해지한 뒤에 `C1`(007) · `G1`(008) · `D3`(018) · `Z1`(019)이',
       '> 돌기 때문에 넷 다 SDM 경유로 판정된다.', '',
       '## 업무 코드', '',
       '| 업무 코드 | 내용 | TC | 경로 | 알림 판정 |', '|---|---|---|---|---|']
for c in order:
    name, tc, route, _, _ = T[c]
    lbl = {'BSUBS-always': 'BSUBS (무조건)',
           'BSUBS-if-hfc': 'BSUBS / SDM (HFC 상태)',
           'SDM': 'SDM'}[route]
    mark = '건너뜀 ⚠️' if c in EXEMPT else '확인'
    idx.append('| [`%s`](CDS_%s.md) | %s | `%s` | %s | %s |' % (c, c, name, tc, lbl, mark))
idx += ['', '⚠️ = `@{CDS_NOTI_EXEMPT_CODES}` 에 있어 판정을 건너뛴다. '
        '위 경로 규칙과 어긋나는 지점이라 확인이 필요하다(각 문서의 해당 절 참조).', '',
        '## 그 밖의 문서', '',
        '- [CDS_X1.md](CDS_X1.md) — 1X 전문의 PG 내부 End-to-End (SDM/SNOTI 계열 + BSUBS 계열 병행)',
        '- [../nodes/CDS.md](../nodes/CDS.md) — CDS 노드 스펙 (인코딩 표, 함정, LTE/SA 차이)', '']
io.open('docs/callflow/README.md', 'w', encoding='utf-8', newline='').write(chr(10).join(idx))
print('docs/callflow/README.md  (인덱스)')
