# CLAUDE.md

SK텔레콤 **PG(Policy Gateway)** 연동을 검증하는 Robot Framework 테스트 슈트.
**6개 노드** — NAG · PCF · LRS · UPM · CDS · NWDAF.

## 문서 인덱스

작업 전에 해당 문서를 읽을 것. 이 파일에는 요약을 중복하지 않는다.

| 문서 | 내용 |
|---|---|
| [docs/INTERFACES.md](docs/INTERFACES.md) ★ | **노드 간 연동 매트릭스** — 방향·포트·헤더·Body·opcode 충돌 |
| [docs/ENVIRONMENTS.md](docs/ENVIRONMENTS.md) | dev/stg/prd 환경 설정, 변수 우선순위, 환경 축 변수 |
| [docs/TC_CONVENTION.md](docs/TC_CONVENTION.md) | TC 명명·태그·템플릿·비활성화·판정 한계 |
| [resources/RESOURCES.md](resources/RESOURCES.md) | 공통 키워드·변수·Python 헬퍼 5종 카탈로그 |
| [tests/nag/NAG.md](tests/nag/NAG.md) | NAG 노드 스펙 |
| [tests/pcf/PCF.md](tests/pcf/PCF.md) | PCF 노드 스펙 |
| [tests/lrs/LRS.md](tests/lrs/LRS.md) | LRS 노드 스펙 |
| [tests/upm/UPM.md](tests/upm/UPM.md) | UPM 노드 스펙 |
| [tests/cds/CDS.md](tests/cds/CDS.md) | CDS 노드 스펙 |
| [tests/nwdaf/NWDAF.md](tests/nwdaf/NWDAF.md) | NWDAF 노드 스펙 |

스킬 `pg-tc-authoring`(TC 작성) / `pg-wire-encoding`(전문 인코딩 대조)이 해당 작업에서 자동으로 걸린다.

## 명령

```bash
bash run_tests.sh nag                       # NAG   (→ PG:8012)
bash run_tests.sh pcf                       # PCF   (→ PG:8011, NAG 세션 선등록)
bash run_tests.sh lrs                       # LRS   (→ PG.LRS:10204 + 8890 Listen)
bash run_tests.sh upm                       # UPM   (→ PG:10506)
bash run_tests.sh cds                       # CDS   (듀얼 → 9201 → 9200)
bash run_tests.sh nwdaf                     # NWDAF (→ PG:10305)
bash run_tests.sh all                       # 전체
bash run_tests.sh smoke                     # --include smoke
bash run_tests.sh nag --log-msg             # PG_LOG_MSG=1 → REQ/RESP 추적 로그

bash run_tests.sh nag stg                   # 환경 지정 (dev 기본 / stg / prd)
bash run_tests.sh all prd                   # prd 는 PG_ALLOW_PRD=1 필요
bash run_tests.sh all 192.168.1.1           # PG_HOST 만 오버라이드

python -m robot --test "TC-NAG-010*" tests/nag/     # 단일 TC
python -m robot --include negative tests/           # 태그 필터
python -m robot --dryrun tests/                     # 키워드 해석만
```

결과물: `results/<YYYYMMDD_HHMMSS>/report.html`, `log.html`

## 규칙

**한글 스타일** — 테스트명·Documentation·로그·실패 메시지 모두 한글이다. 수정 시 동일하게 유지할 것.

**소켓은 슈트당 1회** — Suite Variable 로 공유한다. **TC 별 connect/disconnect 를 추가하지 말 것.**
`Test Setup` 의 `Check ... Socket` 이 닫힘을 감지하면 `Fatal Error` 로 슈트 전체를 중단한다.

**opcode 는 상수명으로** — 같은 숫자가 노드마다 다른 의미다(`0x05` = PCF ZONE / LRS Location-Info /
UPM Subs-Change). 숫자를 직접 쓰지 말고 `${MSG_<IFACE>_*}` 를 쓴다.

**`txn_id` 는 0이 될 수 없다** — 규격 제약. `Next TXN ID` 가 강제한다.

**값 변경은 `*_variables.robot` 에서** — TC 에 리터럴을 넣지 않는다.

**NWDAF TLV 태그는 이중 관리** — `TlvHelper.py` 와 `nwdaf_variables.robot` 양쪽을 고쳐야 한다.

**규격서 표를 그대로 믿지 말 것** — "numeric" 이 1B 바이너리 / 1B ASCII / 4B BE int 로 제각각이다.
wire 형식은 PG 소스로만 확정된다. 상세는 `pg-wire-encoding` 스킬.

**`--dryrun` 은 Python 을 실행하지 않는다** — 인자 타입 변환 오류나 헬퍼 버그를 잡지 못한다.
송수신이 걸린 변경은 가짜 PG 를 띄워 실제로 돌려볼 것.

## 문서 갱신 규칙

코드를 고치면 **해당 노드 스펙의 인코딩 표와 슈트 상단 `[TC 번호 체계]` 블록을 같이 고친다.**
이 리포는 실제로 그 둘이 코드와 어긋난 전례가 있다.
