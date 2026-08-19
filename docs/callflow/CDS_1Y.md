# CDS `1Y` — HFC 서비스 해지

| 항목 | 값 |
|---|---|
| 업무 코드 | `1Y` |
| 테스트 케이스 | `TC-CDS-004` |
| 알림 경로 | BSUBS 경유 (**무조건**) — 규칙 1 |
| 알림 판정 | **건너뜀** — 예외 목록에 있음 (아래 ⚠️) |
| UPM 연동 | `0x07` 수신 → `0x08` 응답 |
| 예약 큐 적재 | 없음 |
| Body 필드 수 | 3개 / 총 327B (고정) |

> 1X 과 같이 UPM 을 탄다 — 해지도 Cell 정보를 정리해야 한다.

## 콜플로우

```mermaid
sequenceDiagram
    autonumber
    participant TOOL as 도구 (CDS 역할)
    participant PCDS as PG.CDS
    participant PDB as PDB
    participant BSUBS as PG.BSUBS
    participant UPM as 도구 (UPM 역할)
    participant SNOTI as PG.SNOTI
    participant PCF as 도구 (PCF 역할)

    TOOL->>PCDS: 0015 CommandRequest (1Y) — Body 327B
    PCDS->>PDB: INSERT T_CDS_ORDER_HIST
    PCDS->>PDB: INSERT T_BAROD_ORDER_HIST (주소 암호화)
    opt INSERT 성공 시
        PCDS->>PDB: UPDATE T_CDS_ORDER_TID SET TID = ?, UPDATE_TIME = SYSDATE WHERE NAME = ?
    end
    PCDS-->>TOOL: 0016 CommandRequestACK (SC) — Schannel
    PCDS-->>TOOL: 0017 CommandResult (SC) — Rchannel
    TOOL->>PCDS: 0018 CommandResultACK (TID 에코)
    Note over TOOL,PCDS: 0017 의 SC 는 접수 결과다 — 반영은 PDB 로만 판정된다

    BSUBS->>PDB: T_BAROD_ORDER_HIST 주기 폴링
    BSUBS->>UPM: 0x07 Subs-Info-Request
    UPM->>BSUBS: 0x08 Subs-Info-Response (Cell List)
    BSUBS->>PDB: T_BAROD_SUBS_CELLINFO 저장
    BSUBS->>SNOTI: RBUS NOTI
    Note over BSUBS,SNOTI: SDM 은 1X/1Y 에 RBUS NOTI 를 보내지 않는다 — 깨우는 쪽은 BSUBS 다
    SNOTI->>PCF: SBI Noti (h2c)
    Note over TOOL,PDB: ResultAck 뒤 settle 대기 → 반영될 때까지 재조회
    TOOL->>PDB: T_5G_SUBS_SERVICE 삭제 확인 (MDN + ZONE_SVC_D) — 0건
```

## 전문 Body 필드

Body 는 업무 코드와 무관하게 **항상 327B** 다. 아래 필드만 채우고 나머지는 공백이다.

| # | 필드 | 폭(B) |
|---|---|---|
| 1 | `mdn` | 12 |
| 2 | `prod_id` | 10 |
| 3 | `product_type` | 2 |

출처는 `resources/CdsHelper.py` 의 `_fill_command_fields()` 분기다 — **규격서가 아니라 이 코드가 와이어의 기준이다.**
★ 분기가 선언하지 않은 필드는 값을 넘겨도 **조용히 버려진다.**

## 판정 기준

`CommandResult(0017)` 는 Body 내용과 무관하게 `SC` 를 준다. 실제 반영은 PDB 로만 판정된다.

- `T_5G_SUBS_SERVICE` (MDN, `ZONE_SVC_D`) = **0건** — `SVC_TYPE`/`JOB_CODE` 를 가리지 않는다(어떤 형태로든 남으면 해지가 덜 된 것)

### ⚠️ 알림 판정은 현재 꺼져 있다

이 코드는 `@{CDS_NOTI_EXEMPT_CODES}`(A1 / 1Y / Z1)에 들어 있어 `Verify SBI Noti Sent` 가 **건너뛴다.**

그런데 위 경로 규칙(2026-08-19)대로면 이 코드도 알림이 나간다 — **두 지시가 어긋나 있다.** 규칙이 앞의 것을 대체하는 것이면 예외 목록에서 이 코드를 빼면 되고, 경로는 정해지지만 SNOTI 가 PCF 로 보내지 않는 것이면 지금이 맞다.

확인되기 전까지 **판정을 켜지 않았다** — 켜서 틀리면 TC 가 이유 없이 실패하는 쪽이라 되돌리기 어렵다.

## 관련 문서

- [CDS 노드 스펙](../nodes/CDS.md) — 인코딩 표, 함정, LTE/SA 차이
- [1X 전문 End-to-End](CDS_X1.md) — PG 내부 프로세스 상세
- `tests/cds/cds_tests.robot` — `TC-CDS-004`
