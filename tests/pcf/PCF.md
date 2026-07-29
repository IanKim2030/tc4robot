# PCF 노드 스펙

규격: `PCRF-PG 간 ZONE 알림 정보 처리 연동 규격서_20210329`
파일: [`pcf_tests.robot`](pcf_tests.robot) · [`pcf_keywords.robot`](../../resources/pcf_keywords.robot) · [`pcf_variables.robot`](../../resources/pcf_variables.robot)

## 접속

| 항목 | 값 |
|---|---|
| 도구 역할 | PCF (Client) |
| 방향 | 도구 → PG |
| 포트 | `${PCF_PG_PORT}` = 8011 |
| 헤더 | 8-옥텟 공통, Byte0 `0x00` |
| Body | JSON |
| 타임아웃 | `${PCF_TIMEOUT}` = 10초 |

## 듀얼 소켓 — NAG 세션 선등록

`Suite Connect With NAG` 가 PCF 테스트 전에 소켓 **두 개**를 연다.

```
① NAG 소켓(8012) 연결 + Hello  → 가입자 세션 선등록용
② PCF 소켓(8011) 연결 + Hello  → ${PCF_SOCK}
```

PG 가 ZONE 알림을 내리려면 해당 가입자의 세션이 먼저 등록돼 있어야 하므로 NAG 채널이 필요하다.
두 소켓 모두 슈트가 끝날 때까지 살아 있어야 하며, `Check PCF And NAG Socket` 이
하나라도 닫히면 `Fatal Error` 로 중단한다.

## 메시지 타입

| opcode | 상수 | 방향 |
|---|---|---|
| `0x01` / `0x02` | `${MSG_HELLO_REQ}` / `${MSG_HELLO_RESP}` | PCF → PG |
| `0x03` / `0x04` | `${MSG_PING_REQ}` / `${MSG_PING_RESP}` | PCF → PG |
| `0x05` / `0x06` | `${MSG_PCF_ZONE_REQ}` / `${MSG_PCF_ZONE_RESP}` | PCF → PG |

`0x05`/`0x06` 은 LRS·UPM 에서 전혀 다른 의미다. **반드시 `${MSG_PCF_ZONE_*}` 상수명을 쓸 것.**

NAG 채널에서 `0x07` ZION 을 수동 수신하는 TC 도 이 슈트에 있다
(`TC-NAG-011` 등 — PCF 슈트 안에 NAG 번호의 TC 가 섞여 있다).

## TC

현재 **10건**. 태그: `pcf` `nag` `hello` `ping` `zion` `zone-inout` `smoke` `validation`

슈트 로컬 변수: `${PCF_TEST_MDN}` = `01020300553`, `${PCF_SERVICE_ID}` = `ZN100001`

## 함정

- **TC 번호가 슈트명과 다르다.** PCF 슈트 안에 `TC-NAG-008` 처럼 NAG 번호를 쓰는 TC 가 있다.
  NAG 채널을 함께 검증하기 때문인데, 번호만 보고 파일을 찾으면 헤맨다.
- ZION(`0x07`) 은 **PG 가 먼저 보내는** 메시지다. `Receive ZION Request` → `Send ZION Response`
  순으로 처리하며, 응답은 요청의 txn 을 echo 하고 `code=200` 을 넣는다.
