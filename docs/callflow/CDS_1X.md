# CDS `1X` — HFC 서비스 가입

| 항목 | 값 |
|---|---|
| 업무 코드 | `1X` |
| 테스트 케이스 | `TC-CDS-003` |
| 알림 경로 | BSUBS 경유 (**무조건**) — 규칙 1 |
| 알림 판정 | `Verify SBI Noti Sent` 가 도착을 확인 |
| UPM 연동 | `0x07` 수신 → `0x08` 응답 |
| 예약 큐 적재 | 없음 |
| Body 필드 수 | 5개 / 총 327B (고정) |

> UPM `0x07` 수신 → `0x08` 응답까지 해야 완결된다. PG 내부 상세는 [CDS_X1.md](CDS_X1.md).

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

    TOOL->>PCDS: 0015 CommandRequest (1X) — Body 327B
    PCDS->>PDB: INSERT T_CDS_ORDER_HIST
    PCDS->>PDB: INSERT T_BAROD_ORDER_HIST (주소 암호화)
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
    TOOL->>PDB: SELECT COUNT(*) — 반영 판정 (재조회)
```

## 전문 Body 필드

Body 는 업무 코드와 무관하게 **항상 327B** 다. 아래 필드만 채우고 나머지는 공백이다.

| # | 필드 | 폭(B) |
|---|---|---|
| 1 | `mdn` | 12 |
| 2 | `prod_id` | 10 |
| 3 | `limit` | 1 |
| 4 | `addr` | 170 |
| 5 | `product_type` | 2 |

출처는 `resources/CdsHelper.py` 의 `_fill_command_fields()` 분기다 — **규격서가 아니라 이 코드가 와이어의 기준이다.**
★ 분기가 선언하지 않은 필드는 값을 넘겨도 **조용히 버려진다.**

## 판정 기준

`CommandResult(0017)` 는 Body 내용과 무관하게 `SC` 를 준다. 실제 반영은 PDB 로만 판정된다.

- `T_5G_SUBS_SERVICE` (MDN, `ZONE_SVC_D`, `SVC_TYPE=D`, `JOB_CODE=1X`) = **1건 이상**

알림은 `Verify SBI Noti Sent 1X` 가 본다(도착 여부). 경로는 수신만으로 구분되지 않아 규칙으로 계산해 실패 메시지에 싣는다.

## 관련 문서

- [CDS 노드 스펙](../nodes/CDS.md) — 인코딩 표, 함정, LTE/SA 차이
- [1X 전문 End-to-End](CDS_X1.md) — PG 내부 프로세스 상세
- `tests/cds/cds_tests.robot` — `TC-CDS-003`
