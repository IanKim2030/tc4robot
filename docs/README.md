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

각 노드 스펙은 **접속 → 메시지 타입 → wire 인코딩 → TC → 함정 → 확인 필요** 순으로 같은 골격을 쓴다
(해당 없는 절은 생략).

## 그 밖에

- [../CLAUDE.md](../CLAUDE.md) — 개발 가이드 및 프로젝트 메인 인덱스
- 스킬 — `pg-tc-authoring`(TC 작성) / `pg-wire-encoding`(전문 인코딩 대조)
