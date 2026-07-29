# INTERFACES.md — 노드 간 연동 매트릭스

PG 연동 6개 노드의 방향·포트·전문 형식을 한 장에 모은 표. **어느 노드를 건드리든 여기부터 본다.**
상세는 각 노드 스펙(`tests/<iface>/<IFACE>.md`) 참조.

## 한눈에

| 노드 | 도구 역할 | 접속 방향 | 포트 | 헤더 | Body | 소켓 |
|---|---|---|---|---|---|---|
| [NAG](../tests/nag/NAG.md) | NAG | Client → PG | 8012 | 8B `0x00` | JSON | 듀얼 (+8890 Listen) |
| [PCF](../tests/pcf/PCF.md) | PCF | Client → PG | 8011 | 8B `0x00` | JSON | 듀얼 (+NAG 8012) |
| [LRS](../tests/lrs/LRS.md) | LRS | Client → PG.LRS | 10204 | 없음 / HTTP | raw `REQ`/`ANS`, HTTP AIMS | 듀얼 (+8890 Listen) |
| [UPM](../tests/upm/UPM.md) | UPM | Client → PG | 10506 | 8B `0x00` | JSON | 단일 |
| [CDS](../tests/cds/CDS.md) | CDS | Client 듀얼 → PG.CDS | Rch 9201 → Sch 9200 | **48B** | 고정전문 | 듀얼 |
| [NWDAF](../tests/nwdaf/NWDAF.md) | NWDAF | Client → PG | 10305 | 8B 비트필드 | **TLV 바이너리** | 단일 |

**도구는 6개 노드 모두에서 능동 접속(Client) 한다.** 서버로 대기하는 건 NAG·LRS 가 함께 여는
LRS-PCF 보조 채널(8890) 하나뿐이다.

호스트는 전부 `${PG_HOST}`(`resources/variables.robot`, 기본 `192.168.15.141`)를 상속하며
`run_tests.sh all <IP>` 로 일괄 오버라이드된다.

## 전문 형식 3계열

| 계열 | 헤더 | 모듈 | 쓰는 노드 |
|---|---|---|---|
| 8-옥텟 공통 | Byte0 `0x00`(ProtoVer 0) / `0x20`(LRS 계열) | `TcpHelper.py` (`WITH NAME Tcp`) | NAG, PCF, UPM, LRS-PCF 채널 |
| 48-옥텟 CDS | Message ID / TID(date+seq) / System·App ID / Continue / Serial / Data Size | `CdsHelper.py` (`Cds`) | CDS |
| 8-옥텟 NWDAF | Byte0 비트필드(Ext/ProtoVer/HdrType/MsgType) + SvcId(2B) + MsgId(3B) + BodyLen(2B) | `TlvHelper.py` (`Tlv`) | NWDAF |

`txn_id` 는 **절대 0이 될 수 없다**(규격 명시). `Next TXN ID` 키워드가 강제한다.
NWDAF 는 `txn_id` 대신 Message Id(0x000~0xFFF 순환)를 쓴다.

## 듀얼 소켓 구조 — 어느 노드가 어느 채널을 먼저 여는가

**NAG** — 클라이언트 8012 + 서버 8890
```
① NAG 소켓(8012) 연결 → Hello 로 세션 등록
② LRS-PCF 서버 소켓(8890) Listen → LRS(PG) 가 접속
③ PG 의 Hello-Request(0x01) 수신 → Hello-Response(0x02) 회신
```
Subs-Cellid TC 가 `0x0b` 를 보내면 PG 는 **LRS-PCF 채널로 `0x05` Location-Info-Request 를 되돌려
보낸다.** 그래서 ②③ 이 미리 끝나 있어야 한다.

**PCF** — NAG 8012(세션 선등록) + PCF 8011. 두 소켓 모두 슈트 끝까지 살아 있어야 한다.

**LRS** — 클라이언트 10204 + 서버 8890. NAG 와 같은 8890 채널을 쓴다.
Session-Info(HTTP) 처리 중 PG 가 8890 으로 `0x05` 를 보내오므로 동일한 선처리가 필요하다.

**CDS** — **Rchannel(9201) 을 먼저 연결**하고 Schannel(9200) 을 뒤에 연다. 각 채널이
ConnectionRequest 를 보내고 ACK 를 받는 핸드셰이크를 한다.

| 순서 | 채널 | 송신 | 기대 응답 |
|---|---|---|---|
| 1 | Rchannel 9201 | `0003` RchannelConnectionRequest | `0004` ACK |
| 2 | Schannel 9200 | `0001` SchannelConnectionRequest | `0002` ACK |

## opcode 충돌 — 노드별 상수명을 그대로 써라

같은 opcode 가 노드마다 다른 의미다. **숫자를 직접 쓰지 말고 상수명을 쓴다.**

| opcode | NAG | PCF | LRS(8890) | UPM |
|---|---|---|---|---|
| `0x05` | | `${MSG_PCF_ZONE_REQ}` | `${MSG_LOC_INFO_REQ}` | `${MSG_UPM_SUBS_CHANGE_REQ}` |
| `0x06` | | `${MSG_PCF_ZONE_RESP}` | `${MSG_LOC_INFO_RESP}` | `${MSG_UPM_SUBS_CHANGE_RESP}` |
| `0x07` | `${MSG_ZION_REQ}` | | | `${MSG_UPM_SUBS_INFO_REQ}` |
| `0x09` | `${MSG_SUBS_ZONE_STATUS_REQ}` | | | `${MSG_UPM_CELLINFO_NOTI_REQ}` |
| `0x0b` | `${MSG_SUBS_CELLID_REQ}` (ADOT) | | | `${MSG_UPM_SUBS_SYNC_REQ}` |

`0x01`~`0x04`(Hello/Ping)만 `resources/variables.robot` 에서 공용이다.

## 환경별 접속 정보

포트·호스트는 각 `<iface>_variables.robot` 의 기본값을 쓰고, 환경별로 다르면
`config/env/<env>.py` 에서 노드별로 오버라이드한다 — [ENVIRONMENTS.md](ENVIRONMENTS.md).

```bash
bash run_tests.sh cds stg
```

과거 SSH 로 PG 의 `PG_V2.cfg` 를 읽던 `DynamicVars` 는 제거됐다.
실측 cfg 값이 하드코딩 기본값과 전부 같아 동작 차이가 없었기 때문이다.

## 연결 실패 시 동작

전 노드 공통. `Test Setup` 의 `Check ... Socket` 계열 키워드가 소켓이 닫혀 있으면
**`Fatal Error` 로 슈트 전체를 즉시 중단**한다. 연결이 없으면 이후 TC 가 의미 없기 때문이다.
TC 별 connect/disconnect 를 추가하지 말 것 — 자세한 규칙은 [RESOURCES.md](../resources/RESOURCES.md).

NWDAF 만 `Nwdaf Peer Closed`(논블로킹 `MSG_PEEK`)로 **PG 측 FIN/RST 까지 감지**한다.
다른 노드의 `Is Connected` 는 로컬 fd 만 보므로 상대가 끊은 것을 알지 못한다.
