# UPM — 노드 스펙

규격: `UPM ↔ PG.BSUBS HFC 서비스 연동 규격 v1.1 (2025-12-02)`
파일: [`upm_tests.robot`](../../tests/upm/upm_tests.robot) · [`upm_keywords.robot`](../../resources/upm_keywords.robot) · [`upm_variables.robot`](../../resources/upm_variables.robot)

## 접속

| 항목 | 값 |
|---|---|
| 도구 역할 | UPM (Client) |
| 방향 | 도구 → PG |
| 포트 | `${UPM_PG_PORT}` = 10506 |
| 헤더 | 8-옥텟 공통, Byte0 `0x00` |
| Body | JSON |
| 타임아웃 | `${UPM_TIMEOUT}` = 10초 |
| 소켓 | **단일** |

### Suite Setup 이 Hello 까지 한다

**규격 3.1: 연결 후 5초 이내에 Hello 를 보내지 않으면 PG 가 연결을 끊는다.**
그래서 `Suite UPM Connect` 가 연결 직후 Hello 를 처리한다.

```
연결 → Hello-Request(0x01) 송신 → Response(0x02) 검증(code=200)
     → ping-interval 을 ${UPM_PING_INTERVAL} 에 저장
     → key list 를 ${UPM_KEY_LIST} 에 저장
```

Hello 가 실패하면 `Fatal Error` 로 슈트를 시작조차 하지 않는다.

## 메시지 타입 — 양방향

| 방향 | opcode | 상수 | 의미 |
|---|---|---|---|
| **UPM → PG** | `0x01` / `0x02` | `${MSG_HELLO_REQ}` / `_RESP` | Hello |
| | `0x03` / `0x04` | `${MSG_PING_REQ}` / `_RESP` | Ping |
| | `0x09` / `0x0a` | `${MSG_UPM_CELLINFO_NOTI_REQ}` / `_RESP` | 변경 Cell Info 통보 |
| | `0x0b` / `0x0c` | `${MSG_UPM_SUBS_SYNC_REQ}` / `_RESP` | 전체 동기화 요청 |
| **PG → UPM** | `0x05` / `0x06` | `${MSG_UPM_SUBS_CHANGE_REQ}` / `_RESP` | 번호 변경 |
| | `0x07` / `0x08` | `${MSG_UPM_SUBS_INFO_REQ}` / `_RESP` | 가입자 Cell Info 요청 |
| | `0x0d` / `0x0e` | `${MSG_UPM_INFO_CHANGE_REQ}` / `_RESP` | 상품/Device 변경 |

`0x05`·`0x07`·`0x09`·`0x0b` 는 다른 노드에서 전혀 다른 의미다 —
[opcode 충돌표](../INTERFACES.md#opcode-충돌--노드별-상수명을-그대로-써라).

수동 수신 3종은 모두 같은 모양이다: 요청 Body 의 `code-type`/`branch-name`/`tid`/`mdn` 을 echo 하고
`result-code=${UPM_RC_SUCCESS}` 를 붙여 `${hdr}[txn_id]` 로 회신한다.

### tid — txn_id 와 별개다

JSON Body 안의 `tid`(24자리)는 **헤더의 `txn_id`(4바이트 바이너리)와 완전히 별개**다.
`Next UPM TID` 키워드가 생성한다:

```
장비No(5) + "-" + yyyyMMdd(8) + seq(10)
```

### code-type

`${UPM_CT_*}` — `01` 가입 / … / `06` 상품·Device 변경. 문자열이다.
`UPM Code Type Should Be` 로 검증한다.

## TC

현재 **활성 4건 / 주석 1건**. 태그: `upm` `hello` `ping` `cellinfo-noti` `subs-sync` `smoke` `validation`
(+ 주석 TC 에 `subs-info` `subs-change` `info-change`)

## 함정

**수동 수신 TC 는 대부분 주석 처리돼 있다.** PG 측에서 실제 이벤트(가입·해지·번호 변경)가
발생해야 동작하기 때문이다. 키워드(`Receive Subs Info Request` 등)는 전부 구현돼 있으므로
PG 이벤트 트리거가 가능해지면 주석만 풀면 된다.
