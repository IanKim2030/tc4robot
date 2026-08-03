# LRS — 노드 스펙

규격: `PG_LRS_정보조회_연동규격_2021021_V1.7` · `PCRF&PCF-PG 간 RAR 경량화 연동 규격서_v0.8_20231115`
파일: [`lrs_tests.robot`](../../tests/lrs/lrs_tests.robot) · [`lrs_client_keywords.robot`](../../resources/lrs_client_keywords.robot) · [`lrs_keywords.robot`](../../resources/lrs_keywords.robot)

## 접속 — 채널이 둘이고 성격이 완전히 다르다

LRS 는 이 리포에서 가장 헷갈리는 노드다. **주력은 클라이언트 모드**다.

| 채널 | 도구 역할 | 방향 | 포트 | 프로토콜 |
|---|---|---|---|---|
| **LRS 클라이언트** (주력) | Client | 도구 → PG.LRS | `${LRS_CLIENT_DEFAULT_PORT}` = 10204 | raw TCP + HTTP |
| **LRS-PCF** (보조) | Server | PG → 도구 | `${LRS_SERVER_PORT}` = 8890 | 8-옥텟 헤더 |

포트 10204 는 `PG_V2.cfg` `[LRS] LISTEN_PORT` 에서 읽되 현재 해당 `Variables` 줄은 **주석 처리**돼
있어 항상 기본값 10204 를 쓴다.

### 10204 — 같은 포트에서 두 프로토콜

1. **Health Check** — raw TCP. 도구가 `"REQ"` 3바이트를 보내면 PG 가 `"ANS"` 로 답한다.
   헤더가 없다. 주기 기본 30초(`${LRS_HC_DEFAULT_INTERVAL}`).
2. **SESSION-INFO-RETRIEVAL** — HTTP/1.1 `POST /SESSION-INFO-RETRIEVAL`, XML `AIMS_REQ` → `AIMS_RES`.
   `HttpHelper.py` 가 담당한다.

### 8890 — Session-Info 처리에 필수

Session-Info(HTTP) 처리 중 PG 가 **8890 채널로 `0x05` Location-Info-Request 를 보내** 위치를 묻는다.
도구가 `0x06` 으로 답해야 PG 가 LOCATION/TAC 를 채워 HTTP 200 을 준다.

스레드가 없으므로 HTTP 송신과 수신을 갈라 그 사이에 처리한다:
```robot
${sock}=    Send Session Info Request        # 논블로킹 POST
Handle LRS Location Info                     # 8890 에서 0x05 → 0x06
${res}=     Receive Session Info Response    ${sock}
```

이 채널은 NAG 슈트가 쓰는 것과 **같은 8890 채널**이다.

### Suite 흐름

```
Suite Connect LRS Client   → ${LRS_CLIENT_SOCK} (10204)
Suite LRS Accept           → ${LRS_CONN}        (8890, blocking accept)
Handle LRS Hello           → 0x01 수신 → 0x02 회신
```

`Server Accept` 는 `${LRS_ACCEPT_TIMEOUT}` = **30초 블로킹 대기**한다.
LRS 슈트를 돌릴 때는 그 윈도우 안에 PG 가 접속을 시도하도록 운용자가 준비해야 한다.

`${LRS_ALLOWED_PEER_IPS}` 로 접속 허용 IP 를 제한한다.

## 메시지 타입 (8890 채널)

| opcode | 상수 | 방향 |
|---|---|---|
| `0x01` / `0x02` | Hello-Request / Response | PG → 도구 / 도구 → PG |
| `0x03` / `0x04` | Ping-Request / Response | PG → 도구 / 도구 → PG |
| `0x05` / `0x06` | `${MSG_LOC_INFO_REQ}` / `${MSG_LOC_INFO_RESP}` | PG → 도구 / 도구 → PG |

**모두 PG 가 먼저 보낸다.** Body 는 JSON 이 아니라 `pack_fields`/`unpack_fields` 로 다루는
고정길이 ASCII 다. 헤더 Byte0 는 `0x20`(ProtoVer 01'B) — 단 NAG 슈트에서는 `0x00` 으로 오버라이드.

원하는 메시지를 기다리다 중간에 낀 Ping 에 먼저 답하는 패턴이 있다:
```robot
WHILE    True    limit=10
    ${hdr}    ${raw}=    Receive From LRS PG
    IF    ${hdr}[msg_type] == ${5}    BREAK
    END
    IF    ${hdr}[msg_type] == ${3}
        Send LRS Ping Response    ${hdr}[txn_id]
        CONTINUE
    END
    Fail    Location-Info-Request(0x05) 기대, 실제 msg_type=${hdr}[msg_type]
END
```

### HTTP 응답 코드

`${LRS_SI_CODE_*}`: 404 NOT_FOUND / 403 FORBIDDEN(From IP 미등록) / 500 INTERNAL /
601 RAA_ERROR / 602 RAA_TIMEOUT

`${LRS_SI_FROM_IP}` 는 **PG 에 등록된 IP 여야 한다** — 아니면 403 이다.

## TC

현재 **2건**(활성). 태그: `lrs` `health-check` `session-info` `smoke` `negative` `validation`

negative TC 는 대부분 주석 처리돼 있다.

## 확인 필요

- `lrs_variables.robot` 의 다수 변수에 `# TODO: 실환경 ...` 이 붙어 있다.
  **운영 PG 대상 LRS 슈트가 통과하려면 실제 환경값으로 교체해야 한다.**
- `${LRS_MSG_TIMEOUT}`(10초)은 선언만 되어 있고 **어디서도 참조되지 않는다.**
