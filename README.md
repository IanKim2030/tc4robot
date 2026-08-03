# tc4robot

SK텔레콤 **PG(Policy Gateway)** 연동을 검증하는 Robot Framework 테스트 슈트.
**6개 노드** — NAG · PCF · LRS · UPM · CDS · NWDAF.

## 설치

```bash
python -m venv .venv
pip install robotframework
pip install robotframework-databaselibrary pyodbc
```

## 실행

```bash
bash run_tests.sh nag         # 노드별 (nag/pcf/lrs/upm/cds/nwdaf)
bash run_tests.sh all         # 전체
bash run_tests.sh smoke       # --include smoke
bash run_tests.sh nag stg     # 환경 지정 (dev 기본 / stg / prd)
```

결과물: `results/<YYYYMMDD_HHMMSS>/report.html`, `log.html`

## 문서

[docs/README.md](docs/README.md) 가 전체 인덱스다. 작업 전에 해당 문서를 읽을 것.

| 문서 | 내용 |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 4계층 구조와 모듈 배치 |
| [docs/INTERFACES.md](docs/INTERFACES.md) ★ | 노드 간 연동 매트릭스 · opcode 충돌 |
| [docs/TC_CONVENTION.md](docs/TC_CONVENTION.md) | TC 명명·태그·템플릿 |
| [docs/RESOURCES.md](docs/RESOURCES.md) | 공통 키워드·변수·Python 헬퍼 |
| [docs/ENVIRONMENTS.md](docs/ENVIRONMENTS.md) | dev/stg/prd 환경 설정 |
| [docs/nodes/](docs/nodes/) | 노드별 스펙 6종 |

---

## 📑 연동규격서 목록

| No. | PROCESS명 | 구간 | 규격서 | 상태 | 비고 |
| :--- | :--- | :--- | :--- | :---: | :--- |
| 01 | PG.BNOTI | NAG (C) → PG.BNOTI (S) | PG_NAG HFC_ADOT 서비스 연동 규격서_20230718 | 완료 | ... |
| 02 | PG.BNOTI | PCF (C) → PG.BONTI (S) | PCRF-PG 간 ZONE 알림 정보 처리 연동 규격서_20210329 | 완료 | ... |
| 03 | PG.BNOTI | BNOTI (C) → PG.LRS (S) | PG_LRS_정보조회_연동규격_2021021_V1.7 | 완료 | ... |
| 04 | PG.LRS | LRS (C) → PG.LRS (S) | PG_LRS_정보조회_연동규격_2021021_V1.7 | 완료 | ... |
| 05 | PG.LRS | PG.LRS (C) → PCF (S) | PCRF&PCF-PG 간 RAR 경량화 연동 규격서_v0.8_20231115 | 완료 | ... |
| 06 | PG.UPM | ... | UPM ↔ PG.BSUBS HFC 서비스 연동 규격 v1.1 | 작업중 | ... |
| 90 | PG.SCMQOS | ITM → PG.SCMQOS | ... | 적용필요 | 기지국 혼잡제어 |
| 91 | PG.NWMQOS | NWDAF → PG.NWMQOS | PG_연동 규격서_V1.2_20240920 | 적용필요 | 기지국 혼잡제어 |

### 💡 작성 팁

* **통신 방식:** REST API (HTTPS), gRPC, Socket, SFTP, DB Link 등
* **데이터 포맷:** JSON, XML, Fixed Length (고정길이 전문), CSV 등
* **상태:** 대기 / 설계중 / 개발중 / 테스트중 / 완료 / 보류

---

## 📑 구성 요소 및 약어 목록

| 약어 (Acronym) | 용어 (Full Name) | 주요 역할 및 설명 |
| :--- | :--- | :--- |
| PG | PCRF Gateway | ... |
| NAG | Network Access Gateway | ... |
| MSS | Mobile Switching Server/System | 통화 경로 제어 및 가입자 위치 관리 |
| ABC | A-side, B-side / Call Processing | ... |
| HD Voice | High Definition Voice | ... |
| HFC | Home-Fi Call | ... |
| LRS | Location Retrieval System | ... |
| NWDAF | Network Data Analytics Function | ... |
| CDS | Customer Data Distributed | ... |
| RDS | Reserved Data Distributed | ... |
| ITM | Integrated Traffic Manager/Management | 통신망 내에서 가입자 데이터베이스와 연동하여 트래픽 정책을 제어하고, 가입자의 서비스 품질(QoS)과 정책 정보를 실시간으로 관리하는 시스템 |
| PG.BNOTI | BaroD Noti | ... |
