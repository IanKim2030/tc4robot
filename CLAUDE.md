# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 저장소 개요

SK텔레콤 **PG(Policy Gateway)** 연동을 검증하는 Robot Framework 테스트 슈트. 네 가지 인터페이스(**NAG**, **PCF**, **LRS**, **UPM**)를 다루며, 모두 동일한 8-옥텟 바이너리 헤더를 사용하지만 역할(클라이언트/서버), Body 인코딩(JSON/고정길이 ASCII), 메시지 타입이 다르다. 테스트명·문서·로그 메시지는 모두 한글로 작성되어 있으므로 수정 시 동일한 스타일을 유지할 것.

## 자주 쓰는 명령

```bash
bash run_tests.sh nag                       # NAG 슈트 (클라이언트 → PG:8012)
bash run_tests.sh pcf                       # PCF 슈트 (클라이언트 → PG:8011, NAG 세션 선등록 포함)
bash run_tests.sh lrs                       # LRS 슈트 (서버 모드, :8890 Listen)
bash run_tests.sh upm                       # UPM 슈트 (클라이언트 → PG:10506, HFC 가입자 Cell List)
bash run_tests.sh cds                       # CDS 슈트 (클라이언트 듀얼소켓 → PG.CDS Schannel:9200/Rchannel:9201, 48B 고정전문)
bash run_tests.sh nwdaf                     # NWDAF 슈트 (클라이언트 → PG:10305, TLV 바이너리 Notification)
bash run_tests.sh all                       # 전체 슈트
bash run_tests.sh smoke                     # --include smoke 만
bash run_tests.sh nag --log-msg             # PG_LOG_MSG=1 → REQ/RESP 추적 로그 ON
bash run_tests.sh all 192.168.1.1           # NAG/PCF/UPM_PG_HOST 일괄 오버라이드

# 단일 TC 실행 (run_tests.sh 우회)
python -m robot --test "TC-NAG-010*" tests/nag/
python -m robot --test "TC-LRS-006*" tests/lrs/
python -m robot --test "TC-UPM-005*" tests/upm/
python -m robot --test "TC-CDS-001*" tests/cds/

# 태그 필터
python -m robot --include negative tests/
python -m robot --include lte tests/
```

결과물은 `results/<YYYYMMDD_HHMMSS>/` 아래에 `report.html`, `log.html` 형태로 생성된다.

## 아키텍처

### 네 개의 인터페이스, 하나의 공통 헤더

`resources/TcpHelper.py`가 유일한 Python 모듈이며, 네 인터페이스가 공통으로 쓰는 8-옥텟 빅엔디안 헤더(`build_header`/`parse_header`)를 구현한다. 헤더의 첫 바이트로 인터페이스 계열을 구분한다:

- `0x00` — NAG/PCF/UPM (ProtoVer=0), Body는 JSON
- `0x20` — LRS (ProtoVer=01'B), Body는 `pack_fields` / `unpack_fields`로 다루는 고정길이 ASCII

`txn_id`는 절대 0이 될 수 없다(규격 명시). `Next TXN ID` 키워드가 이 제약을 강제한다.

**CDS는 예외다.** CDS 인터페이스(CDS 표준 인터페이스 규격 Ver6.0)는 8-옥텟 공통 헤더를 쓰지 않고 **48-옥텟 빅엔디안 헤더**(Message ID/Transaction ID(date+seq)/System·Application ID/Continue Flag/Serial No/Data Size)를 쓰며, 별도 모듈 `resources/CdsHelper.py`(`pack_cds_header`/`parse_cds_header`/`send_cds`/`receive_cds`)가 이를 구현한다. 정수 필드는 `htonl/htons`(big-endian) 송신. 도구는 **CDS 역할로 PG.CDS에 능동 접속**하며 Schannel(9200)/Rchannel(9201) **듀얼 소켓**을 쓴다(NAG 듀얼소켓과 유사). 포트/`SYSTEM_ID`는 `PG_V2.cfg [CDS]`에서 `DynamicVars`로 읽고 미수신 시 기본값(9200/9201, `PG01`)을 쓴다.

**NWDAF도 예외다.** NWDAF 인터페이스는 8-옥텟 헤더를 쓰되 필드 구성이 다르고(Byte0 비트필드 = Extension/ProtoVer/HeaderType/MessageType, Byte1-2 Service Id, Byte3-5 Message Id, Byte6-7 Body Length), **Body가 JSON도 고정길이 ASCII도 아닌 TLV 바이너리**다. 전용 모듈은 `resources/TlvHelper.py`(`WITH NAME Tlv`)이며 `build_nwdaf_header`/`pack_tlv`/`build_*_qos_ctrl`을 제공한다. 도구가 클라이언트로 PG:10305에 접속한다. Service Id는 규격상 `0x0305` 하나뿐이고, Message Id는 0x000~0xFFF 순환이다.

NWDAF에서 특히 헷갈리는 지점 네 가지:

- **`PCEF_TYPE`(0x0D)은 배타적 enum이 아니라 비트마스크다.** PG 참조 구현이 `if (pcef_type & 0x02)` 형태로 비트를 검사한다. `0x01` P-GW / `0x02` DPI / `0x04` DPI / `0x08` APRS / `0x10` eNB이며 **조합값이 유효**하다 — LTE DPI 케이스는 `0x01|0x02 = 0x03`이고, 이때 pcefQoSCtrl과 dpiQoSCtrl이 **한 전문에 함께** 실린다. `build_notification_body(..., dpi_qos_ctrl=)`가 이를 담당한다.
- **TAG `0x0C`는 다의적이다.** pcefQoSCtrl에서는 STATUS 한 번이지만, dpiQoSCtrl에서는 `(CATEGORY + QOS_POLICY)` 쌍으로 5회 반복된 뒤 마지막에 STATUS가 한 번 더 온다(0x0C 총 6개). 따라서 첫 매칭만 반환하는 `tlv_find`로는 검증할 수 없고 **`tlv_find_all`을 써야 한다.**
- **"numeric" 규격 필드가 전부 바이너리인 게 아니다.** `NETWORK`(0x1F)는 4바이트 바이너리지만, `CONTROL_UNIT`(0x40)·`CATEGORY`·`STATUS`는 ASCII 숫자 1바이트다(`'1'`=0x31, `'0'`=0x30). `TlvHelper.CONTROL_UNIT_AS_ASCII` 스위치로 전환한다. 값(1~6)과 wire 인코딩은 분리해 두었으니 **변수에 0x31 같은 인코딩된 값을 넣지 말 것.**
- **TIMER(0x20)는 섹션마다 타입이 다르다.** pcef/dpi는 uint32 BE 4바이트, eNB는 규격 명시대로 ASCII 문자열이다.

Notification은 PG가 응답을 주지 않는다. 따라서 **Robot 테스트가 자동 판정할 수 있는 것은 전문 조립 결과(송신 없는 build 단위 TC), TCP 송신 성공, `Check NWDAF Socket`의 FIN/RST 감지뿐**이다. "PG가 값을 올바로 해석했는가"는 구조적으로 도구 단독 판정이 불가능하며 PG 로그(`CNWQosGateway.cpp`의 `Header Info` / `BodyInfo` 덤프) 대조가 유일한 수단이다. 그래서 `Send NWDAF Notification`이 매 송신마다 전체 패킷 hexdump를 `log.html`에 남긴다 — PG 로그와 바이트 단위로 대조하라. 이 판정 공백 때문에 **인코딩이 처음부터 맞아야 하고, build 단위 TC 비중이 높다.**

TLV 태그 카탈로그는 `resources/TlvHelper.py`(Python)와 `resources/nwdaf_variables.robot`(Robot) **양쪽에 의도적으로 이중 관리**된다. 태그를 추가하면 둘 다 고쳐야 한다.

### 접속 방향이 인터페이스마다 다르다

- **NAG / PCF / UPM**: 도구가 **클라이언트**로 PG에 접속. `tcp_connect` / `send_message` / `receive_message` (JSON) 사용.
- **LRS**: 도구가 **서버** 역할이고 LRS(PG)가 들어오는 접속을 건다. `server_start` / `server_accept` / `send_lrs_message` / `receive_lrs_message` (고정길이 ASCII) 사용.

NAG 슈트와 PCF 슈트는 모두 듀얼 소켓 구조다.

- **NAG 슈트**: `Suite Connect With LRS PCF`가 NAG 클라이언트 소켓(8012)을 열어 Hello로 세션을 등록한 뒤, **LRS-PCF 서버 소켓(8890)** 을 Listen하고 LRS(PG)가 접속해 보낸 Hello-Request(0x01)에 Hello-Response(0x02)까지 처리한다. Subs-Cellid TC가 `0x0b` Request를 보내면 PG는 LRS-PCF 채널로 `0x05` Location-Info-Request를 전달하므로, 이 채널이 미리 살아 있어야 한다. 두 소켓 중 하나라도 닫히면 `Check LRS PCF And NAG Socket`이 `Fatal Error`로 슈트를 즉시 중단한다.
- **PCF 슈트**: `Suite Connect With NAG`가 PCF 테스트를 시작하기 전에 NAG 소켓(8012, 세션 선등록용)과 PCF 소켓(8011)을 둘 다 연다. 두 소켓 모두 슈트가 끝날 때까지 살아 있어야 하며, 하나라도 닫히면 `Check PCF And NAG Socket`이 `Fatal Error`로 슈트를 즉시 중단한다.
- **UPM 슈트**: `Suite UPM Connect`가 UPM → PG(10506) 소켓을 1회 연결하고, 규격(3.1)이 요구하는 "5초 이내 Hello-Request 송신"을 Suite Setup 단계에서 처리해 ping-interval을 `${UPM_PING_INTERVAL}`에 저장한다. UPM은 단일 소켓 구조이며 `Check UPM Socket`이 닫힘 감지 시 `Fatal Error`로 중단한다.

### Suite 단위 소켓 공유

소켓은 **슈트당 1회만** 열리고 모든 TC가 Suite Variable(`${NAG_SOCK}`, `${PCF_SOCK}`, `${LRS_CONN}`, `${LRS_SRV_SOCK}`, `${UPM_SOCK}`)을 통해 공유한다. 각 `Test Setup`의 `Check ... Socket` 키워드는 소켓이 닫혀 있으면 **`Fatal Error`**를 발생시켜 슈트 전체를 즉시 중단한다 — 연결이 없으면 이후 TC도 의미가 없기 때문이다. TC별 connect/disconnect 로직을 추가하지 말 것.

LRS의 경우 `Suite LRS Accept`가 `Server Accept`에서 LRS(PG)의 접속을 블로킹 대기한다(타임아웃 `${LRS_ACCEPT_TIMEOUT}` = 30초). LRS 슈트를 돌릴 때는 그 윈도우 안에 LRS(PG)가 접속을 시도하도록 운용자가 준비해야 한다.

### 레이어 구조

```
tests/<iface>/<iface>_tests.robot     ← 테스트 케이스 (TC-NAG-xxx, TC-PCF-xxx, TC-LRS-xxx, TC-UPM-xxx)
        │ 사용
        ▼
resources/common_keywords.robot       ← Robot 키워드: Suite setup/teardown, 송수신, 검증
        │ 사용 (WITH NAME Tcp)
        ▼
resources/TcpHelper.py                ← 원시 소켓 + 헤더 pack/unpack
```

`resources/variables.robot`는 호스트·포트, 메시지 타입 상수(`${MSG_HELLO_REQ}` 등), 응답 코드(`${CODE_*}`, `${LRS_CODE_*}`), 테스트 데이터(MDN·APN·TID)를 한곳에 모아둔다. 값 변경은 TC가 아닌 이 파일에서 한다. `${LRS_*}` 변수 다수에는 `# TODO: 실환경 ...` 주석이 달려 있고, 운영 PG 대상 LRS 슈트가 통과하려면 실제 환경값으로 교체해야 한다.

### 의도된 메시지 타입 상수 충돌

같은 opcode가 인터페이스별로 다른 의미를 갖는 케이스가 다수 있어, **인터페이스별 상수 이름을 그대로 사용해야** 한다.

- `0x05` — `${MSG_PCF_ZONE_REQ}` (PCF) / `${MSG_LOC_INFO_REQ}` (LRS) / `${MSG_UPM_SUBS_CHANGE_REQ}` (UPM)
- `0x06` — `${MSG_PCF_ZONE_RESP}` (PCF) / `${MSG_LOC_INFO_RESP}` (LRS) / `${MSG_UPM_SUBS_CHANGE_RESP}` (UPM)
- `0x07` — `${MSG_ZION_REQ}` (NAG) / `${MSG_UPM_SUBS_INFO_REQ}` (UPM)
- `0x09` — `${MSG_SUBS_ZONE_STATUS_REQ}` (NAG) / `${MSG_UPM_CELLINFO_NOTI_REQ}` (UPM)
- `0x0b` — `${MSG_SUBS_CELLID_REQ}` (NAG, ADOT) / `${MSG_UPM_SUBS_SYNC_REQ}` (UPM)

### UPM 메시지 흐름 요약

UPM은 능동 송신과 수동 수신이 모두 있는 양방향 인터페이스다.

- **능동 송신 (UPM → PG)**: Hello(0x01), Ping(0x03), CellInfo-Noti(0x09), Subs-Sync(0x0b)
- **수동 수신 (PG → UPM)**: Subs-Change(0x05, 번호 변경), Subs-Info(0x07, Cell Info 요청), Info-Change(0x0d, 상품/Device 변경)

수동 수신 TC는 PG 측 실제 이벤트(가입/해지/번호 변경 등)가 발생해야 동작하므로 운영 환경 미준비 시 주석 처리되어 있다. JSON Body 내 `tid`(24자리)는 헤더의 `txn_id`(4바이트 바이너리)와 별개이며, `Next UPM TID` 키워드가 `장비No(5)+"-"+yyyyMMdd(8)+seq(10)` 포맷으로 생성한다.

### --include 로 쓰이는 태그

`smoke`, `negative`, `validation`, `lte`, `5g`, 인터페이스별(`nag`, `pcf`, `lrs`, `upm`, `cds`), 기능별(`hello`, `ping`, `subs-zone`, `subs-cellid`, `location`, `adot`, `cellinfo-noti`, `subs-sync`, `subs-info`, `subs-change`, `info-change`, `connect`, `process-state`, `command`, `subs-data`, `upload`, `release`).
