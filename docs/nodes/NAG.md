# NAG — 노드 스펙

규격: `PG_NAG HFC_ADOT 서비스 연동 규격서_20230718`
파일: [`nag_tests.robot`](../../tests/nag/nag_tests.robot) · [`nag_keywords.robot`](../../resources/nag_keywords.robot) · [`nag_variables.robot`](../../resources/nag_variables.robot)

## 접속

| 항목 | 값 |
|---|---|
| 도구 역할 | NAG (Client) |
| 방향 | 도구 → PG |
| 포트 | `${NAG_PG_PORT}` = 8012 |
| 헤더 | 8-옥텟 공통, Byte0 `0x00` |
| Body | JSON |
| 타임아웃 | `${NAG_TIMEOUT}` = 10초 |

포트 기본값은 `nag_variables.robot` 의 8012 이며, 환경별로 다르면
`config/env/<env>.py` 에서 오버라이드한다.

### 듀얼 소켓 — LRS-PCF 채널이 필수다

NAG 슈트는 소켓 두 개를 쓴다.

```
① Suite Connect NAG      : NAG 클라이언트 소켓(8012) 연결       → ${NAG_SOCK}
② Suite LRS Accept       : LRS-PCF 서버 소켓(8890) Listen/accept → ${LRS_CONN}
③ Handle LRS Hello       : PG 의 Hello-Request(0x01) 수신 → Hello-Response(0x02) 회신
```

**왜 필요한가** — Subs-Cellid TC 가 `0x0b` 를 보내면 PG 는 응답을 바로 주지 않고
**LRS-PCF 채널로 `0x05` Location-Info-Request 를 되돌려 보낸다.** 도구가 `0x06` 으로
위치를 답해야 PG 가 비로소 `0x0c` 응답을 완성한다. 그래서 ②③ 이 TC 실행 전에 끝나 있어야 한다.

리포에 스레드가 없으므로 이 왕복은 **송신과 수신을 분리**해 처리한다:
```robot
${txn}=    Send Subs Cellid Request    ...     # 송신만
Handle LRS Location Info                       # 다른 소켓에서 0x05 응답
${hdr}    ${body}=    Receive Subs Cellid Response
```

**주의** — NAG-Barod 의 LRS-PCF 채널은 응답 헤더 Byte0 가 `0x00` 이다(표준 LRS 의 `0x20` 이 아님).
슈트가 `${LRS_TX_BYTE0} = ${0}` 으로 오버라이드한다.

NAG Hello 는 Suite Setup 이 아니라 **TC-NAG-001 에서 직접** 수행한다 — 다른 슈트와 다른 점이다.

## 메시지 타입

| opcode | 상수 | 방향 |
|---|---|---|
| `0x01` / `0x02` | `${MSG_HELLO_REQ}` / `${MSG_HELLO_RESP}` | NAG → PG |
| `0x03` / `0x04` | `${MSG_PING_REQ}` / `${MSG_PING_RESP}` | NAG → PG |
| `0x07` / `0x08` | `${MSG_ZION_REQ}` / `${MSG_ZION_RESP}` | **PG → NAG** (수동 수신) |
| `0x09` / `0x0a` | `${MSG_SUBS_ZONE_STATUS_REQ}` / `_RESP` | NAG → PG |
| `0x0b` / `0x0c` | `${MSG_SUBS_CELLID_REQ}` / `_RESP` | NAG → PG (ADOT) |

LRS-PCF 채널에서는 `0x01/0x02`(Hello) 와 `0x05/0x06`(Location-Info) 를 쓴다.

`0x07`·`0x09`·`0x0b` 는 다른 노드에서 다른 의미다 — [opcode 충돌표](../INTERFACES.md#opcode-충돌--노드별-상수명을-그대로-써라).

### 응답 코드

`${CODE_*}` (`nag_variables.robot`): 400 UNSUPPORT_MSG / 401 UNEXPECTED_DATA /
402 (HFC 미가입·세션 없음) / 429 RETRY_AFTER / 502 PEER_NODE_DOWN /
504 GATEWAY_TIMEOUT / 9999 HAVE_TO_FAILOVER

negative TC 는 에러 코드와 `cause` 키 존재를 검증한다:
```robot
Response Code Should Be    ${body}    402
Dictionary Should Contain Key    ${body}    cause
```

## TC

현재 **7건**. 태그: `nag` `hello` `ping` `zion` `subs-zone` `subs-cellid` `adot` `smoke` `negative` `validation`

bad-input MDN 은 전용 변수를 쓴다 — `${TEST_MDN_NO_SS}`(HFC 미가입) / `${TEST_MDN_NO_SESSION}`(세션 없음).

## 함정

- **두 소켓 중 하나라도 닫히면 슈트를 중단해야 한다.** 다만 현재 `Check NAG Socket` 은
  `${NAG_SOCK}` 만 확인한다 — LRS-PCF 채널 닫힘은 감지하지 못한다.
- `Tcp.Is Connected` 는 로컬 fd 만 본다. PG 가 끊어도 통과한다.
