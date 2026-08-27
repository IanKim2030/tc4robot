# RTS — 노드 스펙

파일: [`rts_tests.robot`](../../tests/rts/rts_tests.robot) · [`rts_keywords.robot`](../../resources/rts_keywords.robot) · [`rts_variables.robot`](../../resources/rts_variables.robot) · [`RtsHelper.py`](../../resources/RtsHelper.py)

## ⚠ "RDS" 와 혼동하지 말 것

PG 내부 공식 명칭은 **RTS**다(PG 소스 `RTS/` 디렉토리, 클래스 `CRts`/`CRtsDB`/`CRtsPacket`/`CRtsSocket`,
로그 태그 "RTS" — 전부 소스로 확인).

[nodes/CDS.md](CDS.md) 에 등장하는 **"PG.RDS"는 완전히 다른 프로세스**다 — 쿠폰 예약작업
폴러(`RDS/`/`RDS_5G/` 디렉토리, K1 가입 → K3 만료 처리, 소켓 통신 없음, `T_5G_RESERVED_JOB`
폴링만 함). 두 이름이 비슷해서 생긴 혼동으로 이 노드가 추가됐다 — 절대 같은 것으로 취급하지 말 것.

## 접속

| 항목 | 값 |
|---|---|
| 도구 역할 | RTS (Client) |
| 방향 | 도구 → PG (PG=Server, accept 후 Connect Req 를 기다림) |
| 포트 | `${RTS_PG_PORT}` = 6003 — **현재는 의도적으로 하드코딩.** PG 쪽은 `RTS/CEnv.cpp GetRTSPort()` 로 `PG_V2.cfg [RTS]` 런타임 설정값을 읽지만(소스 자체엔 하드코딩 없음), 도구 쪽은 레거시 `rts_sim.py` 시뮬레이터의 값(6003)을 그대로 쓴다. 설정 파일을 읽어오는 절차는 추후 도입 예정(TODO) |
| 헤더 | **32B 고정** (`RTS/RtsDefine.hpp` `stNePacket`) |
| Body | 고정폭 (메시지마다 폭 다름, 아래 표) |
| 타임아웃 | `${RTS_TIMEOUT}` = 10초 |
| 소켓 | **단일** |
| System ID | `${RTS_SRC_SYS_ID}`=`SCSL00`(레거시 `rts_sim.py` 실코드 확인, `cds_variables.robot`의 `${CDS_SRC_SYS_ID}`와 동일값) / `${RTS_DST_SYS_ID}`=`PCRF`(동일 소스 확인) |

### 32B 헤더 구조

```
Message ID            (4,  uint32 BE)
Transaction ID Date    (8,  char, YYYYMMDD — 바이트스왑 없음)
Transaction ID Seq     (4,  uint32 BE)
Source System ID       (6,  char, 공백 패딩)
Destination System ID  (6,  char, 공백 패딩)
Data Size              (4,  uint32 BE)
```

### Suite Setup 이 Connect 핸드셰이크를 한다

```
연결 → Connect Req(1) 송신 → Connect Ack(2) 검증(RESULT=SC)
     → Ack 에 담긴 PG 의 최대 TID(SelectMaxTid) 를 채번 기준으로 저장
```

이후 Order 의 TID 는 이 값에서만 증가시킨다 — **낮은 TID 를 보내면 `E_REVERSE_TID_ERROR(3)`**.

## 메시지 타입

| msg_id | 상수 | 의미 | Body 폭 |
|---|---|---|---|
| `1` | `${MSG_RTS_CONNECT_REQ}` | Connect Req (도구→PG) | 0 |
| `2` | `${MSG_RTS_CONNECT_ACK}` | Connect Ack (PG→도구) | **16B** = RESULT(2)+REASON(2)+tid_date(8)+tid_seq(4) |
| `5` | `${MSG_RTS_KEEPALIVE_REQ}` | Keepalive Req | 0 (이번 범위에서 도구 발신 안 함) |
| `6` | `${MSG_RTS_KEEPALIVE_ACK}` | Keepalive Ack | **2B** = REASON(2) — **RESULT 문자열 없음**, Order Ack 과 폭이 다르다 |
| `9` | `${MSG_RTS_RELEASE_REQ}` | Release (도구→PG, 연결 종료 유도) | 0, PG 응답 없음(`RecvReleaseRequest` 가 `false` 반환만 함) |
| `11` | `${MSG_RTS_ORDER_REQ}` | Order Req (도구→PG, L1/L2 전문) | 가변, 이번 범위는 17B |
| `12` | `${MSG_RTS_ORDER_ACK}` | Order Ack (PG→도구) | **4B** = RESULT(2)+REASON(2) |

`0x01`~`0x0c` 대의 숫자는 다른 노드와 무관하다(RTS 는 헤더 자체가 32B 로 다른 5개 노드의
8B/48B 체계와 완전히 분리돼 있어 opcode 충돌표 대상이 아니다).

## wire 인코딩 — ★ 이중 오프셋 구조 (이 노드의 핵심 함정)

PG 소스 `RTS/CDownMessage.cpp`의 `RecvCommandRequest`가 서로 다른 두 버퍼를 다룬다.
GenRts.py(레거시 시뮬레이터)의 레이아웃과 "DB 저장 오프셋 85" 라는 보고가 서로 다르게
보였던 것의 정체다 — **둘 다 맞고, 서로 다른 레이어를 가리켰을 뿐이다.**

### 1) 와이어(수신) 오프셋 — 도구가 보내는 Order Body

| offset | 필드 | 폭 | 비고 |
|---|---|---|---|
| 0 | SVC_CODE | 2B ASCII | `"L1"`/`"L2"` — 업무단 반영 SVC_ID 가 코드마다 다르다(아래 DB 절). 단순 ON/OFF 토글 쌍으로 단정하지 않는다 |
| 2 | MDN | 12B | 공백 우측 패딩, 11자리 권장(아래 MDN 함정 참조) |
| 14 | 로밍 차단 | 1B | L1/L2 전용, `'Y'`/`'N'` |
| 15 | mVoIP 차단 | 1B | L3/L4 전용 — **이번 범위 아님** |
| 16 | QoS Param | 1B | L5/L7/L9/LD/LJ/LL 전용 — **이번 범위 아님** |

### 2) DB 저장 오프셋 — `T_RTS_ORDER_HIST.ORDER_DATA`(265B) 컬럼 내부

| offset | 필드 |
|---|---|
| 85 | 로밍 차단 |
| 86 | mVoIP 차단 |
| 110 | QoS Param |

SVC_CODE(0)/MDN(2) 만 두 레이어의 오프셋이 우연히 같다. **`RtsHelper.py` 는 이 둘을
`RTS_WIRE_LOC_*`/`RTS_DB_OFS_*` 로 이름부터 분리한다 — 절대 섞지 말 것.**
`Verify RTS Order In PDB` 키워드는 DB 오프셋(85)만 쓴다.

### RESULT / REASON

`RESULT`: `"SC"`(성공, `InsertOrder` 가 실제로 성공했을 때만) / `"FA"`(실패).

| REASON | 상수 | 의미 |
|---|---|---|
| 0 | `${RTS_REASON_NO_ERROR}` | 정상 |
| 1 | `${RTS_REASON_NOT_EXIST}` | — |
| 2 | `${RTS_REASON_INTERNAL_ERROR}` | DB insert 실패 |
| 3 | `${RTS_REASON_REVERSE_TID}` | TID 가 이전보다 낮음 |
| 4 | `${RTS_REASON_DUP_TID}` | TID 중복 |
| 12 | `${RTS_REASON_WRONG_SIZE}` | — |
| 54 | `${RTS_REASON_NOT_DEFINE}` | — |
| 99 | `${RTS_REASON_NO_COUNT}` | — |

### MDN 함정

`RTS/CDownMessage.cpp` `attachMDN`: 11번째 문자(인덱스 10)가 공백이면 10자리 MDN 을
11자리로 재배치하는 분기를 탄다. **TC 데이터는 11자리 MDN 으로 통일**해 이 분기를 피한다
(`${RTS_TEST_MDN}` 이미 11자리).

## DB

| 테이블 | 용도 |
|---|---|
| `T_RTS_ORDER_HIST` | `TRANSACTION_ID`(PK, 16자 `%8.8s%08d` 형태) / `MDN` / `MIN` / `ORDER_DATA`(265B) / `UPDATE_TIME` / `STATUS`(`InsertOrder` 가 무조건 `1`로 INSERT) — **프로토콜 계층**(PG.RTS 가 전문을 받았다는 기록) |
| `T_RTS_ORDER_TID` | `NAME`(PG 프로세스 인스턴스명 — **MDN 아님**, TC 단위 구분 불가) / `TID` — 부차 확인용 |
| `T_5G_SUBS_SERVICE` | `MDN` / `SVC_ID` — **업무 계층**(가입자 서비스 반영). `L1`→`SVC_ID=W_DATA_ROAMING_BLOCK` INSERT, `L2`→`SVC_ID=L_DATA_ROAMING_BLOCK` INSERT (사용자 확인). 비동기 반영으로 보여 재시도로 기다린다(`${RTS_DB_WAIT}`/`${RTS_DB_WAIT_INTERVAL}`, CDS 의 SDM 폴링과 같은 성격으로 추정) |

**PDB 접속은 CDS 와 같은 DB 다(사용자 확인)** — 접속 문자열은 `variables.robot` 의
공용 `${PDB_CONNSTR}` 하나뿐이다. 예전에는 `${RTS_DB_CONNSTR}` 과 `${CDS_DB_CONNSTR}` 로
**같은 값이 두 벌** 있었고 `Resolve RTS DB Connstr` 이 둘 사이에 폴백을 걸고 있었는데,
한쪽만 고치면 어긋나는 자리라 하나로 합쳤다. 그 폴백 사슬도 함께 없앴다.
환경 오버라이드로 비어 있으면 `db` 태그 TC 는 실패가 아니라 **Skip** 한다 — CDS 처럼
슈트 전체를 막지 않는다.

## PCF SBI Noti

**L1/L2 도 PCF SBI Noti 를 유발한다(사용자 확인)** — RTS 소스(`RecvCommandRequest`)만으로는
notify 호출이 안 보여 애초엔 미확인이었던 부분이다. CDS 가 이미 쓰는 메커니즘을 그대로
재사용한다: 도구가 PCF 역할로 `${RTS_NOTI_PORT}`(=`${CDS_NOTI_PORT}`=16101)를 h2c 로 Listen
하고, `Suite RTS Connect`/`Suite RTS Disconnect` 가 서버를 열고/닫는다(`HttpNotiServer.py`,
`pip install h2` 필요). `Verify RTS SBI Noti Sent` 가 판정 키워드다 — CDS 의
`Verify SBI Noti Sent`/`Verify PCF Noti Received` 와 동형이나, RTS 는 업무 코드가 L1/L2
둘뿐이라 CDS 의 예외 목록·라우팅 라벨(BSUBS/SDM) 계층은 두지 않았다.

`${SNOTI_PCF_NOTI}=${FALSE}`(`run_tests.sh rts --no-sbi`, CDS 와 공용 플래그)면 Listen
자체를 안 하고 판정도 건너뛴다 — h2 패키지 없이도 슈트가 돈다.

## TC

현재 **2건** — L1, L2 각 1건. 각각 ACK 확인 + `T_5G_SUBS_SERVICE` 업무 계층 반영 확인(`db`) +
PCF SBI Noti 도착 확인(`noti`), L1 은 추가로 `T_RTS_ORDER_HIST` 프로토콜 계층 확인도 겸한다.
태그: `rts` `order` `roaming` `db` `noti`.

판정 기준 — 4단계로 신뢰도가 올라간다:
1. **ACK RESULT="SC"+REASON=0**: `RecvCommandRequest` 는 `InsertOrder` 가 실제로 성공했을 때만 `SC`를 주므로 CDS `CommandResult`보다 신뢰도가 높다. 다만 Body 내용(SVC/로밍 플래그)이 잘못돼도 INSERT 자체는 성공하면 `SC`가 나온다는 점은 CDS 와 같다.
2. **`T_RTS_ORDER_HIST` 조회(TC-RTS-001)**: `SUBSTR(ORDER_DATA, 86, 1)`(DB 오프셋 85, SQL 1-index)로 실제 반영된 로밍 플래그를 확인한다 — 와이어 인코딩 회귀를 잡는 계층.
3. **`T_5G_SUBS_SERVICE` 조회(둘 다, 권장)**: `SELECT COUNT(*) ... WHERE MDN=? AND SVC_ID=?` 1건 이상 — "전문이 가입자에게 실제로 적용됐는가"의 가장 신뢰 가능한 근거. CDS 의 `Verify Zone Service Subscribed In PDB` 와 같은 패턴("1건 이상이면 성공", 정확한 건수는 안 박음).
4. **PCF SBI Noti 조회(둘 다, 사용자 확인)**: `Verify RTS SBI Noti Sent` — 위 PCF SBI Noti 절 참조.

## Call Flow

Order 부터 `PG.SDM_5G` 폴링·`T_5G_SUBS_SERVICE` 반영·SBI Noti 까지 한 장에 그린 시퀀스
다이어그램은 [callflow/rts_callflow.md](../callflow/rts_callflow.md) 에 있다.

## 함정

- **이중 오프셋** — 위 wire 인코딩 절 참조. 이 문서의 존재 이유다.
- **MDN 10자리 재배치** — 위 참조.
- **Keepalive Ack 는 Order Ack 과 폭이 다르다** — 2B(REASON 만) vs 4B(RESULT+REASON). `RtsHelper.py` 의 ack 파서를 msg_id 별로 분리해 둔 이유.
- **Release(9) 에 PG 응답이 없다** — `RecvReleaseRequest` 가 로그만 남기고 `false`를 반환할 뿐이라, `Suite RTS Disconnect` 는 ACK 를 기다리지 않고 바로 소켓을 닫는다.

## 확인 필요

- **L1/L2 가 `T_5G_SUBS_SERVICE` 에 반영되는 것은 사용자 확인으로 확정**(L1→`W_DATA_ROAMING_BLOCK`, L2→`L_DATA_ROAMING_BLOCK`, 위 TC 판정 기준 3 참조). 다만 `W_`/`L_` 접두사가 정확히 어떤 차단 범위를 뜻하는지, L1/L2 가 서로의 반대(ON/OFF 토글) 관계인지는 아직 불명확 — RTS 소스(`RecvCommandRequest`)는 두 코드를 대칭적으로 처리할 뿐 의미까지는 알려주지 않는다. 반영 지연 시간(비동기 폴링 주기)도 미확인 — 현재 `${RTS_DB_WAIT}`=10초는 CDS 값을 그대로 가져온 추정치다.
- **L3~LE(mVoIP/QoS)** — 코드에는 분기가 있으나 미사용 확인됨. 필요해지면 `pack_rts_order_body` 를 offset15/16 까지 채우도록 확장.
- **PCF SBI Noti 본문 내용** — L1/L2 가 SBI Noti 를 유발한다는 것 자체는 확인됐으나, 본문에 MDN 이 그대로 들어가는지는 CDS 와 마찬가지로 미확인. 확인되면 `Verify RTS SBI Noti Sent` 호출에 `body=${RTS_TEST_MDN}` 처럼 좁힐 수 있다.
