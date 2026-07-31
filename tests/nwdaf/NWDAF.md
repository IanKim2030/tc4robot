# NWDAF 노드 스펙

규격: `PG_연동 규격서_V1.2_20240920` (PG.NWMQOS — 기지국 혼잡제어)
파일: [`nwdaf_tests.robot`](nwdaf_tests.robot) · [`nwdaf_keywords.robot`](../../resources/nwdaf_keywords.robot) · [`nwdaf_variables.robot`](../../resources/nwdaf_variables.robot) · [`TlvHelper.py`](../../resources/TlvHelper.py)

## 접속

| 항목 | 값 |
|---|---|
| 도구 역할 | NWDAF (Client) |
| 방향 | 도구 → PG |
| 포트 | `${NWDAF_PORT}` = 10305 |
| Body | **TLV 바이너리** |
| 타임아웃 | `${NWDAF_TIMEOUT}` = 10초 |
| 소켓 | 단일 |

## 헤더 — 8옥텟이되 공통 헤더가 아니다

```
Byte 0    비트필드: Extension(1) | ProtoVer(2) | HeaderType(2) | MessageType(3)
Byte 1-2  Service Id   (BE)
Byte 3-5  Message Id   (BE, 0x000~0xFFF 순환)
Byte 6-7  Body Length  (BE)
```

Message Type: `0b001` Request / `0b100` Response / `0b010` Notification(주력)

**Service Id 는 규격상 `0x0305` 하나뿐이다** — 가입자 단위 QoS 제어. `txn_id` 개념이 없고
Message Id 가 그 역할을 한다(`Next NWDAF Msg Id` 가 0xFFF→0x000 wrap 처리).

## Body 구조

```
Body = MULTI_MESSAGE(0xFF) { COMMON1 + QoSCtrl 섹션들 + COMMON2 }
```

TLV 인코딩은 Tag MSB 로 갈린다:
- Tag `0x00~0x7F` : `[Tag(1B)][Length(1B)][Value]`
- Tag `0x80~0xFF` : `[Tag(1B)][Length(2B BE)][Value]` — 0xFF MULTI_MESSAGE 가 이것

Service Id 0x0305 는 "Multi Message 처리 가능" 이므로 **한 0xFF 안에 가입자 여러 명**을
담을 수 있다(`build_multi_subscriber_body`).

## PCEF_TYPE 은 비트마스크다

`PCEF_TYPE`(0x0D)은 배타적 enum 이 **아니다.** PG 가 `if (pcef_type & 0x02)` 로 비트를 검사한다.

| 비트 | 값 | QoSCtrl 섹션 |
|---|---|---|
| `0x01` | P-GW / SMF | pcefQoSCtrl |
| `0x02` | DPI | dpiQoSCtrl |
| `0x04` | DPI (2번째) | — |
| `0x08` | APRS | — |
| `0x10` | eNB | enodebQoSCtl |

**조합값이 유효하다.** LTE DPI 케이스는 `0x01|0x02 = 0x03` 이고, 이때 pcefQoSCtrl 과
dpiQoSCtrl 이 **한 전문에 함께** 실린다 → `build_notification_body(..., dpi_qos_ctrl=)`.

## TAG 0x0C 는 다의적이다

| 섹션 | 0x0C 의미 | 개수 |
|---|---|---|
| pcefQoSCtrl | STATUS | 1 |
| dpiQoSCtrl | **CATEGORY 6회 + STATUS 1회** | **7** |

첫 매칭만 주는 `tlv_find` 로는 DPI 를 검증할 수 없다 — **`tlv_find_all` 을 쓸 것.**

## ★ wire 인코딩 — 규격 표를 믿지 마라

규격 표의 "numeric" 은 wire 형식을 알려주지 않는다. **실제 형식은 PG 소스로만 확정된다.**
아래는 PG 송신 시뮬레이터 + 수신부(`CNWQosGateway.cpp`)로 검증한 결과다.

### COMMON1 (필수)

| TAG | 필드 | wire |
|---|---|---|
| 0x0D | PCEF_TYPE | 1B 바이너리 |
| 0x0E | QOS_CONTROL_TYPE | 1B 바이너리 |
| 0x08 | CREATE_DATE | 문자열 `YYYYMMDD` |
| 0x09 | CREATE_TIME | 문자열 `HHmmss` |
| 0x0F | PGW_IP_ADDRESS | 문자열 |
| 0x01 / 0x02 | MIN / MDN | 문자열 |
| 0x38 / 0x39 | RCT_3M / 1M_USAGE | **4B BE int** |

*PG 로그 `BodyInfo` 에서 전 필드 정상 출력 확인. 송신부 소스는 미확인.*

### pcefQoSCtrl (비트 0x01)

| TAG | 필드 | wire |
|---|---|---|
| 0x3A | QOS_HDR = `0x01` | 1B 바이너리 |
| 0x10 | QOS_POLICY | **고정길이 NUL 패딩** |
| 0x0C | STATUS | 1B ASCII `'0'`~`'3'` |
| 0x20 | TIMER | **4B BE int** |
| 0x3B | QUICK_SUPPORT | 1B ASCII `'0'`/`'1'` |

*수신부 소스 미확인 — 확인 필요 항목 참조.*

### dpiQoSCtrl (비트 0x02)

```
QOS_HDR(0x3A)=0x02          1B 바이너리
(CATEGORY + QOS_POLICY) × 6  CATEGORY 는 1B ASCII 'A'~'F'
STATUS(0x0C)                1B ASCII (0x30)
TIMER(0x20)                 4B BE int (htonl)
QUICK_SUPPORT(0x3B)         1B ASCII "1"
```

**쌍 개수 6은 고정이다.** 수신부가 `for (i = 0; i < 6; i++)` 로 하드코딩돼 있어
5쌍을 보내면 6번째 반복이 STATUS·TIMER 를 쌍으로 먹어 이후가 전부 밀린다.

### enodebQoSCtl (비트 0x10)

수신부가 **TAG 를 검사하지 않고 고정 순서**로 읽는다. 순서·폭이 하나만 틀려도 뒤가 전부 밀린다.

| TAG | 필드 | 송신부 | 수신부 | wire |
|---|---|---|---|---|
| 0x3A | QOS_HDR | `temp=0x10, &temp` | `cQosHdr = *p` | 1B 바이너리 |
| 0x41 | SUPPORT_TYPE | `"1"`/`"2"` | `cSupportType = *p` | **1B ASCII** |
| 0x3F | ARP_QCI_FLAG | `htonl(v)` len 4 | `ntohl(...)` | 4B BE int |
| 0x3C | ENB_ARP | `htonl(v)` len 4 | `ntohl(...)` | 4B BE int |
| 0x42 | ARP_CAPABILITY | `"1"`/`"2"` | `cCapability = *p` | **1B ASCII** |
| 0x43 | ARP_VULNERABILITY | `"1"`/`"2"` | `cVnlnerability = *p` | **1B ASCII** |
| 0x11 | QCI | len 2, `"9"` | `memcpy(cQCI,p,len)` | **2B ASCII + NUL** |
| 0x20 | TIMER | `htonl(300)` len 4 | `ntohl(...)` | 4B BE int |

규격 표는 eNB TIMER 를 `string` 이라 적었지만 **양쪽 구현 모두 `htonl`/`ntohl`** 이다.

### COMMON2 (필수)

수신부가 태그 기반 `switch` 라 **순서에 자유롭다**(eNB 와 다른 점).

| TAG | 필드 | wire |
|---|---|---|
| 0x1F | NETWORK | 4B BE int |
| 0x40 | CONTROL_UNIT | **1B ASCII** (`cControlUnit` 를 `%c` 로 출력) |
| 0x0B | CELL_ID | 문자열 (수신부가 `RTrim`) |
| 0x31 / 0x1A / 0x35 / 0x32 / 0x36 / 0x37 | DN_USAGE / USING_USER / CELL_AVG_USAGE / HEAVY_USER / USER_USAGE / USER_RATIO | 4B BE int |

**`NETWORK = 0x00`(2G)은 PG 가 거부한다.** 수신부가 `0x01`/`0x02`/`0x03` 만 받고 그 외에는
`"Unknown NetType"` 로그 후 `return nfwError` 로 전문을 버린다. 규격 표에는 2G 가 있으나 **쓰면 안 된다.**

## Health Check

**도구가 PG 로 Request 를 보낸다.** Timeout 30초.

```
NWDAF → PG : Message Type 0x01, Body 없음(길이 0)
PG → NWDAF : Message Type 0x04, Service Id / Message Id echo, Body 없음
```

소켓 타임아웃은 접속 시 1회만 설정되므로 `Tlv.Nwdaf Set Timeout` 으로 그 구간만
`${NWDAF_HEALTHCHECK_TIMEOUT}`(35초)로 올렸다 `TRY/FINALLY` 로 되돌린다.

역방향(PG 가 먼저 보내는 경우)은 `Handle NWDAF Health Check` / `Drain NWDAF Pending Messages` 가
방어적으로 처리한다. 후자는 `Check NWDAF Socket`(Test Setup)에서 논블로킹으로 돌아
쌓인 요청을 비운다.

## 판정 공백 — 이 노드의 핵심 제약

Notification 은 PG 가 응답을 주지 않는다. 따라서 Robot 이 자동 판정할 수 있는 건
**전문 조립 결과(build 단위 TC), TCP 송신 성공, `Check NWDAF Socket` 의 FIN/RST 감지** 뿐이다.

실제로 **eNB 섹션 8개 필드 중 7개가 틀린 상태로 모든 TC 가 PASS 했던 전례**가 있다.
그래서:
- build 단위 TC 비중을 높게 유지한다
- `Send NWDAF Notification` 이 매 송신마다 전체 패킷 hexdump 를 `log.html` 에 남긴다 —
  PG 의 `Header Info`/`BodyInfo` 덤프와 바이트 단위로 대조하라

PG 의 `BodyInfo` printf 는 **COMMON1 + COMMON2 만 출력한다.** pcefQoSCtrl/eNB/DPI 필드가
로그에 안 보이는 건 파싱 실패가 아니라 **로깅 누락**이다.

## TC

현재 **36건**(001~036 연속). NWDAF 만 `nwdaf_` 접두사 태그 체계를 쓴다.

| 대역 | 내용 |
|---|---|
| 001 | Health Check |
| 002~005 | Smoke (PGW/eNB), 5G 가입자 |
| 006~013 | pcefQoSCtrl (STATUS / QUICK_SUPPORT / QOS_POLICY) |
| 014~020 | enodebQoSCtl |
| 021~030 | COMMON1 / COMMON2 |
| 031 | Message Id wrap |
| 032~036 | dpiQoSCtrl (034~036 은 송신 없는 build 검증) |

## 이중 관리

TLV 태그 카탈로그가 `TlvHelper.py`(`TAG_*`)와 `nwdaf_variables.robot`(`${NWDAF_TAG_*}`)
**양쪽에 있다.** 태그를 추가하면 둘 다 고쳐야 한다.

## PG 소스 위치 (2026-07-31 확인)

```
G:\내 드라이브\정리\work3\01_PG_GIT\SRC-remote-r133-ads-vertica\SRC-remote-r133-ads-vertica\
```

**NWDAF 수신부는 `DEV/Online/SC_Package/SCMQos/` 다.**

| 파일 | 내용 |
|---|---|
| `SCMQos/CSCMQosGateway.cpp` | 수신부 본체 |
| `SCMQos/SCMQosDefine.hpp` | 길이 매크로 · 구조체 · TAG 정의 |

이 문서가 여태 적어온 `CNWQosGateway.cpp` 라는 파일명은 **없다.** `SCMQos.vGL/` 에
같은 파일의 다른 판이 있으니 대조 시 어느 쪽인지 확인할 것.

**같은 이름의 매크로가 노드마다 값이 다르다.** `SC/CommonDef.hpp` 와
`LRS/LRS_SIM/CommonDef.hpp` 에도 `LEN_QOS_POLICY` · `LEN_QCI` 가 있지만 **값이 다르다.**
NWDAF 는 반드시 `SCMQosDefine.hpp` 를 봐야 한다.

## ★ 코드와 소스가 어긋난 상태 (미반영)

아래는 소스로 확인했으나 **코드에 아직 반영하지 않았다.** 고칠 때 이 절을 지울 것.

| 상수 | PG 소스 (`SCMQosDefine.hpp`) | 현재 `TlvHelper.py` |
|---|---|---|
| `LEN_QOS_POLICY` | **50** (`:22`, `TAG_LEN_QOS_POLICY = 0x32`) | `16` |
| `LEN_QCI` | **3** (`:23`, `cQCI[LEN_QCI+1]`) | `2` |
| `LEN_CELL_ID` | **14** (`:15`) | `LEN_LOCATION_ID = None` (가변) |

`16`/`2` 는 **다른 노드 헤더의 값**이다(`SC/CommonDef.hpp:41-42`,
`LRS/LRS_SIM/CommonDef.hpp:41-42` 가 정확히 16/2). 거기서 넘어온 것으로 보인다.

소스로 확정된 것:

- **DPI 6쌍 확정** — `ST_DPI_QOS_INFO` 가 `cCategory[6][30]` · `cQosPolicy[6][51]`
  (`SCMQosDefine.hpp:67-75`). 5쌍짜리 `ST_DPI_QOS_INFO_OLD` 가 따로 있다.
- **eNB 필드 폭 확정** — `ST_ENB_QOS_INFO`(`:97-107`) 가
  `cSupportType`/`cCapability`/`cVnlnerability` 는 `char`(1B),
  `nArpQCIFlag`/`nEnbArp`/`nValidTimer` 는 `int`(4B). 위 인코딩 표와 일치한다.

## ⚠ 확인 필요

1. **eNB / DPI 파싱 블록 미확인** — `CSCMQosGateway.cpp` 에서 아직 안 읽었다.
   "TAG 미검사 고정 순서", "6쌍 하드코딩 루프", "QOS_POLICY 상한 검사 없음" 주장이
   전부 이 블록에 걸려 있다. **여기를 읽기 전에는 위 세 주장을 확정으로 쓰지 말 것.**
2. **`ntohl` 이 항상 4B 를 읽는다는 설명은 최소한 COMMON1 에선 틀렸다.**
   `CSCMQosGateway.cpp:859-900` 의 `RCT_3M/1M_USAGE` 는 길이로 분기한다:
   ```c
   if (length > (int)sizeof(int))  memcpy(&n, p, sizeof(int));
   else if (length > 0)            memcpy(&n, p, length);   // length 만큼만
   ```
   COMMON switch 의 모든 분기가 이런 식으로 **길이 제한돼 있다.**
   eNB/DPI 블록도 그런지는 1번을 읽어야 안다. `pg-wire-encoding` 스킬의
   "ntohl 은 length 와 무관하게 항상 4바이트" 서술도 같이 손봐야 한다.
3. **버퍼 오버플로 경고의 근거가 흔들린다.** COMMON switch 의 `TAG_QOS_POLICY`
   (`:839-857`)는 상한 검사가 있을 뿐 아니라 **`memcpy` 두 줄이 주석 처리**돼 있어
   값을 버린다. 이 문서가 인용한 `memcpy(cQosPolicy[i], p, length)` 는 첨자가 있으니
   DPI 블록 쪽이다 — 1번에서 확인할 것. **아직 "문서가 틀렸다"고 단정하지 말 것.**
4. **송신 시뮬레이터 미확인** — wire 길이는 송신부가 정한다. QCI·QOS_POLICY 를
   실제로 몇 바이트로 내보내는지 확인해야 위 표의 50/3 을 그대로 쓸지 정할 수 있다.
5. **pcefQoSCtrl 수신부 미확인** — 여전히 양쪽 소스를 못 본 섹션이다.
6. **Health Check 전용 Service Id 미상** — 현재 `0x0305` 를 그대로 쓴다.
7. **CATEGORY 값 체계** — 시뮬레이터가 `'A'`~`'F'` 를 쓰나 의미 정의는 미확인.
