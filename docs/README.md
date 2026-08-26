# tc4robot 문서 인덱스

SK텔레콤 **PG(Policy Gateway)** 연동을 검증하는 Robot Framework 테스트 슈트.
**7개 노드** — NAG · PCF · LRS · UPM · CDS · NWDAF · RTS.

## 먼저 읽을 것

| 문서 | 내용 |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | 4계층 구조와 모듈 배치 — **여기부터** |
| [INTERFACES.md](INTERFACES.md) ★ | 노드 간 연동 매트릭스 · 방향·포트·헤더·**opcode 충돌** |

## 작업할 때

| 문서 | 내용 |
|---|---|
| [TC_CONVENTION.md](TC_CONVENTION.md) | TC 명명·태그·템플릿·비활성화·판정 한계 |
| [RESOURCES.md](RESOURCES.md) | 공통 키워드·변수·Python 헬퍼 6종 카탈로그 |
| [ENVIRONMENTS.md](ENVIRONMENTS.md) | dev/stg/prd 설정, 변수 우선순위, 환경 축 변수 |

## 노드 스펙

| 노드 | 포트 | Body | 소켓 |
|---|---|---|---|
| [NAG](nodes/NAG.md) | 8012 | JSON | 듀얼 (+8890 Listen) |
| [PCF](nodes/PCF.md) | 8011 | JSON | 듀얼 (+NAG 8012) |
| [LRS](nodes/LRS.md) | 10204 | raw `REQ`/`ANS`, HTTP AIMS | 듀얼 (+8890 Listen) |
| [UPM](nodes/UPM.md) | 10506 | JSON | 단일 |
| [CDS](nodes/CDS.md) | 9201 → 9200 | 48B 고정전문 | 듀얼 |
| [NWDAF](nodes/NWDAF.md) | 10305 | TLV 바이너리 | 단일 |
| [RTS](nodes/RTS.md) | ${RTS_PG_PORT}(6003, 설정파일 연동 TODO) | 32B 고정헤더 + 고정폭 Body | 단일 |

각 노드 스펙은 **접속 → 메시지 타입 → wire 인코딩 → TC → 함정 → 확인 필요** 순의 공통 골격을 쓴다.
해당 없는 절은 생략하고, 노드 고유 내용은 그 사이에 끼운다(예: CDS 의 `Call Flow`).

## Call Flow

노드 스펙보다 깊은 PG 내부 처리 흐름. 도구에서 보이지 않는 구간이라 별도로 둔다.

| 문서 | 내용 |
|---|---|
| [callflow/cds_callflow.md](callflow/cds_callflow.md) | **CDS 업무 코드별 콜플로우** — 알림 경로 규칙(BSUBS/SDM) + 11개 코드를 한 파일에 (`gen_callflow.py` 생성) |
| [callflow/nag_callflow.md](callflow/nag_callflow.md) | NAG(HFC/ADOT 존·셀 조회) 콜플로우 — 듀얼 소켓, LRS-PCF 교차 |
| [callflow/lrs_callflow.md](callflow/lrs_callflow.md) | LRS(세션 정보 조회) 콜플로우 — REQ/ANS + HTTP AIMS, 8890 곁채널 교차 |
| [callflow/rts_callflow.md](callflow/rts_callflow.md) | RTS L1/L2(로밍 데이터 차단) 콜플로우 |
| [callflow/nwdaf_callflow.md](callflow/nwdaf_callflow.md) | NWDAF(기지국 혼잡제어) 콜플로우 — Notification/Health Check, 판정 공백 |
| [callflow/pcf_callflow.md](callflow/pcf_callflow.md) | PCF(ZONE 알림) 콜플로우 — Zone-InOut(8011) ↔ ZION(8012) 듀얼 소켓 왕복 |
| [callflow/upm_callflow.md](callflow/upm_callflow.md) | UPM(HFC 서비스 연동) 콜플로우 — 능동 4종 / 수동 수신 3종(트리거는 CDS) |

노드 간 요약 흐름은 [INTERFACES.md](INTERFACES.md#hfc-서비스-call-flow--세-노드가-어떻게-이어지는가),
CDS 단일 노드의 즉시/예약 흐름은 [nodes/CDS.md](nodes/CDS.md#call-flow--pg-내부-처리) 에 있다.

## 그 밖에

- [../CLAUDE.md](../CLAUDE.md) — 개발 가이드 및 프로젝트 메인 인덱스
- 스킬 — `pg-tc-authoring`(TC 작성) / `pg-wire-encoding`(전문 인코딩 대조)
