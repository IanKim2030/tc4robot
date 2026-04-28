# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 저장소 개요

SK텔레콤 **PG(Policy Gateway)** 연동을 검증하는 Robot Framework 테스트 슈트. 세 가지 인터페이스(**NAG**, **PCF**, **LRS**)를 다루며, 모두 동일한 8-옥텟 바이너리 헤더를 사용하지만 역할(클라이언트/서버), Body 인코딩(JSON/고정길이 ASCII), 메시지 타입이 다르다. 테스트명·문서·로그 메시지는 모두 한글로 작성되어 있으므로 수정 시 동일한 스타일을 유지할 것.

## 자주 쓰는 명령

```bash
bash run_tests.sh nag                       # NAG 슈트 (클라이언트 → PG:8012)
bash run_tests.sh pcf                       # PCF 슈트 (클라이언트 → PG:8011, NAG 세션 선등록 포함)
bash run_tests.sh lrs                       # LRS 슈트 (서버 모드, :8890 Listen)
bash run_tests.sh all                       # 전체 슈트
bash run_tests.sh smoke                     # --include smoke 만
bash run_tests.sh nag --log-msg             # PG_LOG_MSG=1 → REQ/RESP 추적 로그 ON
bash run_tests.sh all 192.168.1.1           # NAG_PG_HOST / PCF_PG_HOST 오버라이드

# 단일 TC 실행 (run_tests.sh 우회)
python -m robot --test "TC-NAG-010*" tests/nag/
python -m robot --test "TC-LRS-006*" tests/lrs/

# 태그 필터
python -m robot --include negative tests/
python -m robot --include lte tests/
```

결과물은 `results/<YYYYMMDD_HHMMSS>/` 아래에 `report.html`, `log.html` 형태로 생성된다.

## 아키텍처

### 세 개의 인터페이스, 하나의 공통 헤더

`resources/TcpHelper.py`가 유일한 Python 모듈이며, 세 인터페이스가 공통으로 쓰는 8-옥텟 빅엔디안 헤더(`build_header`/`parse_header`)를 구현한다. 헤더의 첫 바이트로 인터페이스 계열을 구분한다:

- `0x00` — NAG/PCF (ProtoVer=0), Body는 JSON
- `0x20` — LRS (ProtoVer=01'B), Body는 `pack_fields` / `unpack_fields`로 다루는 고정길이 ASCII

`txn_id`는 절대 0이 될 수 없다(규격 명시). `Next TXN ID` 키워드가 이 제약을 강제한다.

### 접속 방향이 인터페이스마다 다르다

- **NAG / PCF**: 도구가 **클라이언트**로 PG에 접속. `tcp_connect` / `send_message` / `receive_message` (JSON) 사용.
- **LRS**: 도구가 **서버** 역할이고 LRS(PG)가 들어오는 접속을 건다. `server_start` / `server_accept` / `send_lrs_message` / `receive_lrs_message` (고정길이 ASCII) 사용.

PCF 슈트는 특수하다. `Suite Setup`(`Suite Connect With NAG`)이 PCF 테스트를 시작하기 **전에** NAG 소켓(8012, 세션 선등록용)과 PCF 소켓(8011)을 **둘 다** 연다. 두 소켓 모두 슈트가 끝날 때까지 살아 있어야 하며, 하나라도 닫히면 `Check PCF And NAG Socket`이 `Fatal Error`로 슈트를 즉시 중단시킨다.

### Suite 단위 소켓 공유

소켓은 **슈트당 1회만** 열리고 모든 TC가 Suite Variable(`${NAG_SOCK}`, `${PCF_SOCK}`, `${LRS_CONN}`, `${LRS_SRV_SOCK}`)을 통해 공유한다. 각 `Test Setup`의 `Check ... Socket` 키워드는 소켓이 닫혀 있으면 **`Fatal Error`**를 발생시켜 슈트 전체를 즉시 중단한다 — 연결이 없으면 이후 TC도 의미가 없기 때문이다. TC별 connect/disconnect 로직을 추가하지 말 것.

LRS의 경우 `Suite LRS Accept`가 `Server Accept`에서 LRS(PG)의 접속을 블로킹 대기한다(타임아웃 `${LRS_ACCEPT_TIMEOUT}` = 30초). LRS 슈트를 돌릴 때는 그 윈도우 안에 LRS(PG)가 접속을 시도하도록 운용자가 준비해야 한다.

### 레이어 구조

```
tests/<iface>/<iface>_tests.robot     ← 테스트 케이스 (TC-NAG-xxx, TC-PCF-xxx, TC-LRS-xxx)
        │ 사용
        ▼
resources/common_keywords.robot       ← Robot 키워드: Suite setup/teardown, 송수신, 검증
        │ 사용 (WITH NAME Tcp)
        ▼
resources/TcpHelper.py                ← 원시 소켓 + 헤더 pack/unpack
```

`resources/variables.robot`는 호스트·포트, 메시지 타입 상수(`${MSG_HELLO_REQ}` 등), 응답 코드(`${CODE_*}`, `${LRS_CODE_*}`), 테스트 데이터(MDN·APN·TID)를 한곳에 모아둔다. 값 변경은 TC가 아닌 이 파일에서 한다. `${LRS_*}` 변수 다수에는 `# TODO: 실환경 ...` 주석이 달려 있고, 운영 PG 대상 LRS 슈트가 통과하려면 실제 환경값으로 교체해야 한다.

### 의도된 메시지 타입 상수 충돌

`${MSG_PCF_ZONE_REQ}`와 `${MSG_LOC_INFO_REQ}`는 둘 다 `0x05`, `${MSG_PCF_ZONE_RESP}`와 `${MSG_LOC_INFO_RESP}`는 둘 다 `0x06`이다. 같은 opcode가 PCF 소켓과 LRS 소켓에서 서로 다른 의미를 갖는다. 의도를 분명히 하기 위해 인터페이스별 상수 이름을 그대로 사용할 것.

### --include 로 쓰이는 태그

`smoke`, `negative`, `validation`, `lte`, `5g`, 인터페이스별(`nag`, `pcf`, `lrs`), 기능별(`hello`, `ping`, `subs-zone`, `subs-cellid`, `location`, `adot`).
