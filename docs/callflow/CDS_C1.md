# CDS `C1` — 기기변경

| 항목 | 값 |
|---|---|
| 업무 코드 | `C1` |
| 테스트 케이스 | `TC-CDS-007` |
| 알림 경로 | HFC **가입** 상태 → BSUBS / **미가입** → SDM — 규칙 2 |
| 알림 판정 | `Verify SBI Noti Sent` 가 도착을 확인 |
| UPM 연동 | 없음 |
| 예약 큐 적재 | 없음 |
| Body 필드 수 | 19개 / 총 327B (고정) |

> 전후 비교형이라 `Command Download Flow` **앞에서** 기준선을 먼저 뜬다. 레거시 구현이 `min ← mdn` 으로 채운다.

## 콜플로우

```mermaid
sequenceDiagram
    autonumber
    participant TOOL as 도구 (CDS 역할)
    participant PCDS as PG.CDS
    participant PDB as PDB
    participant SDM as PG.SDM
    participant BSUBS as PG.BSUBS
    participant SNOTI as PG.SNOTI
    participant PCF as 도구 (PCF 역할)

    TOOL->>PCDS: 0015 CommandRequest (C1) — Body 327B
    PCDS->>PDB: INSERT T_CDS_ORDER_HIST
    PCDS-->>TOOL: 0016 CommandRequestACK (SC) — Schannel
    PCDS-->>TOOL: 0017 CommandResult (SC) — Rchannel
    TOOL->>PCDS: 0018 CommandResultACK (TID 에코)
    Note over TOOL,PCDS: 0017 의 SC 는 접수 결과다 — 반영은 PDB 로만 판정된다

    alt HFC 가입 상태
        BSUBS->>PDB: T_BAROD_ORDER_HIST 주기 폴링
        BSUBS->>SNOTI: RBUS NOTI
    else HFC 미가입
        SDM->>PDB: T_5G_SUBS_* 반영
        SDM->>SNOTI: RBUS NOTI
    end
    SNOTI->>PCF: SBI Noti (h2c)
    TOOL->>PDB: SELECT COUNT(*) — 반영 판정 (재조회)
```

## 전문 Body 필드

Body 는 업무 코드와 무관하게 **항상 327B** 다. 아래 필드만 채우고 나머지는 공백이다.

| # | 필드 | 폭(B) |
|---|---|---|
| 1 | `mdn` | 12 |
| 2 | `min` | 10 |
| 3 | `new_min` | 10 |
| 4 | `prod_id` | 10 |
| 5 | `data_prod_id` | 10 |
| 6 | `network` | 8 |
| 7 | `tablet_yn` | 1 |
| 8 | `os_ver` | 2 |
| 9 | `device_model` | 4 |
| 10 | `ca` | 1 |
| 11 | `aprf` | 1 |
| 12 | `imsi` | 15 |
| 13 | `mvno` | 1 |
| 14 | `limit` | 1 |
| 15 | `ms_type` | 1 |
| 16 | `category_lte` | 2 |
| 17 | `category_5g` | 2 |
| 18 | `device_type` | 1 |
| 19 | `product_type` | 2 |

출처는 `resources/CdsHelper.py` 의 `_fill_command_fields()` 분기다 — **규격서가 아니라 이 코드가 와이어의 기준이다.**
★ 분기가 선언하지 않은 필드는 값을 넘겨도 **조용히 버려진다.**

## 판정 기준

`CommandResult(0017)` 는 Body 내용과 무관하게 `SC` 를 준다. 실제 반영은 PDB 로만 판정된다.

- 수행 **전** `SVC_ID` 별 행 수 == 수행 **후** `JOB_CODE=C1` 로 적재된 행의 집계

알림은 `Verify SBI Noti Sent C1` 가 본다(도착 여부). 경로는 수신만으로 구분되지 않아 규칙으로 계산해 실패 메시지에 싣는다.

## 관련 문서

- [CDS 노드 스펙](../nodes/CDS.md) — 인코딩 표, 함정, LTE/SA 차이
- [1X 전문 End-to-End](CDS_X1.md) — PG 내부 프로세스 상세
- `tests/cds/cds_tests.robot` — `TC-CDS-007`
