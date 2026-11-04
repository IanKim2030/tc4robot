# SBI_NOTI — PCF SBI Noti 수신 (CDS · RTS 공용)

SA(5G) 가입자 처리 중 PG 는 PCF 로 **SBI Noti**(HTTP/2) 를 보낸다. 도구가 **PCF 역할로 Listen**
해 그 도착을 판정한다 — 전문(SC)·PDB 어느 쪽으로도 보이지 않는 구간이라서다.
서버는 [resources/HttpNotiServer.py](../../resources/HttpNotiServer.py) 하나이고, CDS 와 RTS 가
**같은 포트·같은 서버**를 쓴다.

| 사용처 | 무엇을 기다리나 | 상세 |
|---|---|---|
| CDS | `1X`/`1Y` 뒤 `PG.BSUBS` → PCF Cell List (`TC-CDS-003`) | [nodes/CDS.md](../nodes/CDS.md#pcf-sbi-noti-수신--무엇을-기다리나) |
| RTS | L1/L2 차단 뒤 가입자 Noti | [nodes/RTS.md](../nodes/RTS.md) |

## 변수

| 변수 | 기본값 | 설명 |
|---|---|---|
| `${SNOTI_PCF_NOTI}` | `${TRUE}` | 끄면 Listen 자체를 안 한다(`h2` 없이도 슈트가 돈다). `--no-sbi` |
| `${SBI_NOTI_PORT}` | `16101` | Listen 포트 — **PG 설정과 일치해야 한다.** 노드 변수 `${CDS_NOTI_PORT}` / `${RTS_NOTI_PORT}` 의 기본값 |
| `${SBI_NOTI_HOST}` | `0.0.0.0` | bind 주소. 노드 변수 `${CDS_NOTI_HOST}` / `${RTS_NOTI_HOST}` 의 기본값 |
| `${TOOL_HOST}` | **없음 (환경 파일 필수)** | PG 가 **닿는** 도구 주소. CDS 세션 `RES_URI`/`UDR_NOTI_URI` 호스트가 된다 |

대기 시간(`${CDS_NOTI_WAIT}` 30s / `${RTS_NOTI_WAIT}` 12s)과 링크 표본 주기는 노드별로 따로 쥔다.
구 이름(`CDS_NOTI_PORT` 등)으로 환경 파일에서 덮어도 계속 먹는다.

★ **PG 가 이 주소로 보내도록 설정돼 있어야 한다.** 도구가 붙는 게 아니라 PG 가 붙어 오는
방향이라, 포트만 열어 둔다고 오지 않는다. `0.0.0.0` 은 bind 주소라 세션 URI 에 못 쓴다 —
그래서 `${TOOL_HOST}` 가 따로 있다. `config/db_seed/<env>.sql` 의 URI 리터럴은 Robot 변수를
못 쓰므로 `TOOL_HOST`·포트가 바뀌면 거기도 같이 고친다.

## 프로토콜 — HTTP/2 평문(h2c), prior-knowledge 만

**프로토콜이 HTTP/2 평문(h2c)이다.** 3GPP SBI 라 표준 `http.server` 로는 첫 프리페이스에서
막힌다 — `h2` 패키지(sans-IO 스택)로 프레임을 직접 처리한다. `pip install h2`.

> **`No keyword with name 'Noti.Noti Server Start' found`** 가 뜬다면 `h2` 미설치다.
> 예전에는 `HttpNotiServer.py` 가 최상단에서 `import h2` 를 해서, 패키지가 없으면
> **라이브러리 자체가 안 올라오고** Robot 이 저 메시지로 보고했다 — 진짜 원인이 전혀
> 드러나지 않았다. 지금은 지연 임포트라 서버를 띄울 때 `pip install h2` 안내와 함께
> 실패하고, `${SNOTI_PCF_NOTI}=False` 면 `h2` 없이도 슈트가 그대로 돈다.
> 시험 장비가 개발 PC 와 다르면 **그 장비에** 설치해야 한다.
지원하는 건 **prior-knowledge** 방식뿐이라, PG 가 HTTP/1.1 Upgrade 로 붙으면 받지 못하고
`noti_errors()` 에 "h2c prior-knowledge 가 아닌 접속" 이 남는다 — 알림이 안 잡히면 여기부터 볼 것.

접속 성립(프리페이스 + 서버 SETTINGS)은 요청 수신과 **따로 센다** — PG 가 붙어만
두고 알림은 나중에 보내는 경우도 구분해야 하기 때문이다.

## 링크 감시 — 별도 스레드

accept 루프와 무관하게 도는 감시 스레드가
`${CDS_NOTI_MONITOR_INTERVAL}`(기본 1s)마다 "지금 몇 개 붙어 있는지" 표본을 뜬다.
누적 접속 이력만으로는 **슈트 중간에 PG 가 끊긴 것을 알 수 없기 때문**이다 — 이력은
그대로 남아 "접속 있음" 으로 보인다. 알림이 안 오면 `Verify PCF Noti Received` 가
**그 TC 동안의 링크 상태**를 실패 메시지에 붙인다.

```
{'live': 0, 'connected': False, 'total_connects': 1,
 'connects_since': 0, 'disconnects_since': 1, 'samples_with_no_link': 3, ...}
```

`disconnects_since` 가 0이 아니면 전문이 아니라 **링크가 끊겼던 것**이다.

`${CDS_NOTI_REQUIRE_LINK}`(기본 `${FALSE}`)를 켜면 알림을 기다리기 전에 링크가
살아 있는지부터 본다. 기본이 꺼짐인 이유는 **PG 가 알림마다 새로 붙는 구현일 수
있어서**다 — 그러면 평소 연결 수가 0이라 켜 두면 멀쩡한 흐름을 막는다.

(RTS 는 같은 역할의 `${RTS_NOTI_MONITOR_INTERVAL}` 을 쓴다.)

## 수신 상태는 TC 마다 리셋된다

`Test Setup`(`CDS Test Setup`)이 소켓 생존 확인과
함께 쌓인 알림·오류를 비우고 TC 시작 시각을 찍는다. **알림을 판정하는 TC 는 일부뿐
이지만 리셋은 전 TC 에서 한다** — 판정 TC 안에서만 비우면 그 전에 다른 TC 가 유발한
알림이 큐에 남아 자기 결과로 오인된다. 접속 이력은 지우지 않는다(지우면 링크 진단이
불가능해진다).

## 함정 — LTE 가입자면 아무것도 안 온다

LTE 는 SBI 가 아니라 RBUS 로 나간다([nodes/CDS.md](../nodes/CDS.md) LTE/SA 대조표).
이 판정은 **SA 전제**다.
