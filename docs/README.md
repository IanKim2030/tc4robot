# tc4robot 문서 인덱스

SK텔레콤 **PG(Policy Gateway)** 연동을 검증하는 Robot Framework 테스트 슈트.
**6개 노드** — NAG · PCF · LRS · UPM · CDS · NWDAF.

## 먼저 읽을 것

| 문서 | 내용 |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | 4계층 구조와 모듈 배치 — **여기부터** |
| [INTERFACES.md](INTERFACES.md) ★ | 노드 간 연동 매트릭스 · 방향·포트·헤더·**opcode 충돌** |

## 작업할 때

| 문서 | 내용 |
|---|---|
| [TC_CONVENTION.md](TC_CONVENTION.md) | TC 명명·태그·템플릿·비활성화·판정 한계 |
| [RESOURCES.md](RESOURCES.md) | 공통 키워드·변수·Python 헬퍼 4종 카탈로그 |
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

각 노드 스펙은 **접속 → 메시지 타입 → wire 인코딩 → TC → 함정 → 확인 필요** 순의 공통 골격을 쓴다.
해당 없는 절은 생략하고, 노드 고유 내용은 그 사이에 끼운다(예: CDS 의 `Call Flow`).

## Call Flow

노드 스펙보다 깊은 PG 내부 처리 흐름. 도구에서 보이지 않는 구간이라 별도로 둔다.

| 문서 | 내용 |
|---|---|
| [callflow/CDS_X1.md](callflow/CDS_X1.md) | **1X 전문 End-to-End** — SDM/SNOTI 계열과 BSUBS 계열의 병행 처리, 주소 Masking·암호화, UPM Base64 연동, EMS 복호화 조회 |

노드 간 요약 흐름은 [INTERFACES.md](INTERFACES.md#hfc-서비스-call-flow--세-노드가-어떻게-이어지는가),
CDS 단일 노드의 즉시/예약 흐름은 [nodes/CDS.md](nodes/CDS.md#call-flow--pg-내부-처리) 에 있다.

## 그 밖에

- [../CLAUDE.md](../CLAUDE.md) — 개발 가이드 및 프로젝트 메인 인덱스
- 스킬 — `pg-tc-authoring`(TC 작성) / `pg-wire-encoding`(전문 인코딩 대조)
