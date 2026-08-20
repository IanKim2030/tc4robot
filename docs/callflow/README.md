# CDS 업무 코드별 콜플로우

전문 하나가 PG 안에서 어떤 경로로 흐르고 무엇으로 판정되는지를 업무 코드별로 정리했다.
**필드 집합은 `resources/CdsHelper.py` 의 `_fill_command_fields()` 에서 뽑은 것**이라
규격서가 아니라 코드가 기준이다.

## 알림 경로 규칙 (2026-08-19)

위에서부터 차례로 적용한다.

| # | 조건 | 경로 |
|---|---|---|
| 1 | `1X` · `1Y` | 무조건 **BSUBS** |
| 2 | HFC 가입 상태 + `D3` `C1` `G1` `Z1` | **BSUBS** |
| 3 | 그 외 전부 | **SDM** |

두 경로는 `PG.SNOTI` 에서 합류해 같은 SBI Noti 로 나간다 — **수신만으로는 구분되지 않는다.**
그래서 슈트는 규칙으로 예상 경로를 계산해 실패 메시지에 싣는다.

> ⚠️ 지금 슈트 순서로는 **규칙 2 의 BSUBS 분기를 타는 TC 가 하나도 없다.**
> `1Y`(004)가 HFC 를 해지한 뒤에 `C1`(007) · `G1`(008) · `D3`(018) · `Z1`(019)이
> 돌기 때문에 넷 다 SDM 경유로 판정된다.

## 다이어그램 읽는 법

주황 밴드(`★ 판정`)로 감싼 구간이 **TC 의 성패를 가르는 자리**다. 그 위의 전문 왕복과
PG 내부 처리는 배경이 없다 — `0017 CommandResult` 가 `SC` 여도 밴드 안이 틀리면 실패다.
전후 비교형(`C1` `G1` `D3`)은 밴드가 둘이다 — 전문 앞의 **기준선**과 뒤의 **집계**.

## 업무 코드

| 업무 코드 | 내용 | TC | 경로 | 알림 판정 |
|---|---|---|---|---|
| [`A1`](CDS_A1.md) | 신규가입 | `TC-CDS-002` | SDM | 건너뜀 ⚠️ |
| [`1X`](CDS_1X.md) | HFC 서비스 가입 | `TC-CDS-003` | BSUBS (무조건) | 확인 |
| [`1Y`](CDS_1Y.md) | HFC 서비스 해지 | `TC-CDS-004` | BSUBS (무조건) | 확인 |
| [`I2`](CDS_I2.md) | 부가서비스신청 | `TC-CDS-005` | SDM | 확인 |
| [`I3`](CDS_I3.md) | 부가서비스해지 | `TC-CDS-006` | SDM | 확인 |
| [`C1`](CDS_C1.md) | 기기변경 | `TC-CDS-007` | BSUBS / SDM (HFC 상태) | 확인 |
| [`G1`](CDS_G1.md) | 정보변경 | `TC-CDS-008` | BSUBS / SDM (HFC 상태) | 확인 |
| [`K5`](CDS_K5.md) | Data(Time) 3Mbps 쿠폰 가입 | `TC-CDS-009` | SDM | 확인 |
| [`K6`](CDS_K6.md) | Data(Time) 3Mbps 쿠폰 해지 | `TC-CDS-010` | SDM | 확인 |
| [`K1`](CDS_K1.md) | Data(Time) 쿠폰 가입 | `TC-CDS-011` | SDM | 확인 |
| [`K2`](CDS_K2.md) | Data(Time) 쿠폰 해지 | `TC-CDS-012` | SDM | 확인 |
| [`K4`](CDS_K4.md) | Data(Time) 쿠폰 취소 | `TC-CDS-013` | SDM | 확인 |
| [`K3`](CDS_K3.md) | Data(Time) 쿠폰 만료 | `TC-CDS-014` | SDM | 확인 |
| [`Y9`](CDS_Y9.md) | Data(Zone) 쿠폰 사용시점 알림 | `TC-CDS-015` | SDM | 확인 |
| [`SS`](CDS_SS.md) | 0플랜 옵션(3시간 프리) 가입 | `TC-CDS-016` | SDM | 확인 |
| [`ST`](CDS_ST.md) | 0플랜 옵션(3시간 프리) 해지 | `TC-CDS-017` | SDM | 확인 |
| [`D3`](CDS_D3.md) | 번호변경 | `TC-CDS-018` | BSUBS / SDM (HFC 상태) | 확인 |
| [`Z1`](CDS_Z1.md) | 가입해지 | `TC-CDS-019` | BSUBS / SDM (HFC 상태) | 건너뜀 ⚠️ |

⚠️ = `@{CDS_NOTI_EXEMPT_CODES}` 에 있어 판정을 건너뛴다. 위 경로 규칙과 어긋나는 지점이라 확인이 필요하다(각 문서의 해당 절 참조).

## 그 밖의 문서

- [CDS_X1.md](CDS_X1.md) — 1X 전문의 PG 내부 End-to-End (SDM/SNOTI 계열 + BSUBS 계열 병행)
- [../nodes/CDS.md](../nodes/CDS.md) — CDS 노드 스펙 (인코딩 표, 함정, LTE/SA 차이)
