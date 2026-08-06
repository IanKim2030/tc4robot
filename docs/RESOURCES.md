# RESOURCES — 공통 키워드 / 변수 / 헬퍼 카탈로그

`resources/` 아래 공용 계층. 노드별 키워드·변수는 각 노드 스펙(`docs/nodes/<IFACE>.md`) 참조.

## 레이어 구조

```
tests/<iface>/<iface>_tests.robot     ← 테스트 케이스
        │ 사용
        ▼
resources/<iface>_keywords.robot      ← 노드별 키워드 (송수신 시나리오, 검증)
resources/<iface>_variables.robot     ← 노드별 상수 / 테스트 데이터
        │ 사용
        ▼
resources/common_keywords.robot       ← 공용 키워드 (TXN ID, 응답 검증)
resources/variables.robot             ← 공용 상수 (PG_HOST, Hello/Ping opcode)
        │ 사용 (WITH NAME Tcp / Cds / CdsDb / Tlv)
        ▼
resources/TcpHelper.py                ← 원시 소켓 + 8옥텟 헤더
resources/CdsHelper.py                ← 48옥텟 CDS 전문
resources/TlvHelper.py                ← NWDAF TLV 바이너리
resources/HttpHelper.py               ← LRS Session-Info (HTTP/XML)
resources/CdsDbHelper.py              ← CDS PDB 조회 (ODBC/pyodbc)
```

임포트 순서가 중요하다. `variables.robot` 이 `${PG_HOST}` 를 정의하고 노드별 변수 파일이
이를 참조하므로 **`variables.robot` 을 항상 먼저 임포트**한다. 모든 슈트가 이 순서를 지킨다.

## Python 헬퍼 5종

| 모듈 | Robot 별칭 | 담당 | 주요 함수 |
|---|---|---|---|
| `TcpHelper.py` | `Tcp` | 소켓 + 8옥텟 헤더. 서버 모드도 여기 | `tcp_connect` `server_start` `server_accept` `build_header` `parse_header` `send_message` `receive_message` `pack_fields` `unpack_fields` `send_lrs_message` `receive_lrs_message` `send_text` `recv_text` `recv_http_response` |
| `CdsHelper.py` | `Cds` | 48옥텟 CDS 고정전문. 소켓은 `TcpHelper` 재사용 | `pack_cds_header` `parse_cds_header` `send_cds` `receive_cds` `pack_ack` `unpack_ack` `pack_command_body` `unpack_command_body` |
| `TlvHelper.py` | `Tlv` | NWDAF TLV. 소켓까지 자체 구현 | `build_nwdaf_header` `parse_nwdaf_header` `pack_tlv` `unpack_tlv_stream` `tlv_find` `tlv_find_all` `build_common1` `build_pcef_qos_ctrl` `build_dpi_qos_ctrl` `build_enb_qos_ctrl` `build_common2` `send_nwdaf_notification` `send_nwdaf_raw` `receive_nwdaf_message` `hex_dump` |
| `HttpHelper.py` | — | LRS Session-Info 전용 | `build_aims_req` `parse_xml_fields` `post_session_info` |
| `CdsDbHelper.py` | `CdsDb` | CDS PDB(골디락스/알티베이스) **조회 전용**. ODBC | `build_conn_str` `build_dsn_conn_str` `build_dsnless_conn_str` `masked_conn_str` `db_connect` `db_close` `db_count` |

`CdsDbHelper` 만 성격이 다르다 — 전문을 만들지 않고 **PG 가 DB 에 반영했는지를 본다**.
접속 방식은 3가지다(완성 문자열 / **DSN** / DSN-less). 골디락스는 DSN 방식이 정석이며
그 이유와 `IM012` 이력은 [nodes/CDS.md](nodes/CDS.md) 에 있다.
`pyodbc` 는 **지연 임포트**한다(모듈 최상단에 두면 pyodbc 없는 환경에서 CDS 슈트 전체가
로드되지 않는다). 비밀번호는 키워드 인자로 받지 않고 환경변수 `PG_CDS_DB_PASSWORD` →
Robot 변수 `${CDS_DB_PASSWORD}` 순으로 Python 이 직접 읽는다 — 인자로 넘기면 `log.html`
의 Arguments 에 평문으로 남기 때문이다. 로그에 찍는 접속 문자열은 항상 마스킹된다.

**Body 인코딩이 3계열로 갈리는 게 이 리포의 핵심 복잡도다.** JSON(NAG/PCF/UPM) /
고정길이 ASCII(LRS 8890 채널) / TLV 바이너리(NWDAF) / 48B 고정전문(CDS).
자세한 비교는 [INTERFACES.md](INTERFACES.md).

## `common_keywords.robot`

| 키워드 | 용도 |
|---|---|
| `Next TXN ID` | txn_id 채번. **0을 절대 반환하지 않는다**(규격 제약) |
| `Get KST Timestamp` / `Get Timestamp17` | 전문용 시각 문자열 |
| `Hello Should Succeed` | Hello 응답 검증 |
| `Get Ping Interval` | Hello 응답에서 ping-interval 추출 |
| `Ping Should Succeed` | Ping 응답 검증 |
| `Response Code Should Be` | JSON Body `code` 검증 |
| `Response Msg Type Should Be` | 헤더 msg_type 검증 |
| `TXN ID Should Match` | 요청/응답 txn_id 일치 |
| `Response Should Be Success` | code 200~299 |
| `Cell Info Should Be Valid` / `TA Code Should Be Valid` | Cell/TA 필드 형식 |

## `variables.robot`

공용 단일 소스. **값 변경은 TC 가 아니라 이 파일에서 한다.**

- **환경 축 변수** — `${PG_HOST}`, 가입자(`${SUBS_MDN_LTE}` 등), 망 데이터(`${NET_CELL_ID}` 등).
  노드별 변수 파일이 이를 **참조만** 하므로 여기 하나를 바꾸면 관련 노드 전부에 전파된다.
  **여기 두는 기준은 "두 노드 이상이 공유하는 값"** 이다. 한 노드 전용 환경 값은 해당
  `<iface>_variables.robot` 에 값을 직접 둔다(예: CDS 가입자 `${CDS_MDN}`).
  환경별 오버라이드는 [ENVIRONMENTS.md](ENVIRONMENTS.md) 참조
- `${MSG_HELLO_REQ}`(0x01) / `${MSG_HELLO_RESP}`(0x02) / `${MSG_PING_REQ}`(0x03) /
  `${MSG_PING_RESP}`(0x04) — 여기 있는 4개만 노드 공용이다

`0x05` 이상은 노드마다 의미가 달라 각 `<iface>_variables.robot` 에 따로 있다.
충돌표는 [INTERFACES.md](INTERFACES.md#opcode-충돌--노드별-상수명을-그대로-써라).

## 소켓 공유 규칙 (절대)

소켓은 **슈트당 1회만** 열리고 모든 TC 가 Suite Variable 로 공유한다:
`${NAG_SOCK}` `${PCF_SOCK}` `${LRS_CONN}` `${LRS_SRV_SOCK}` `${UPM_SOCK}`
`${CDS_SCH_SOCK}` `${CDS_RCH_SOCK}` `${NWDAF_SOCK}`

각 `Test Setup` 의 `Check ... Socket` 이 닫힘을 감지하면 **`Fatal Error` 로 슈트 전체를 중단**한다.
연결이 없으면 이후 TC 도 의미가 없기 때문이다.

**TC 별 connect/disconnect 로직을 추가하지 말 것.**

CDS 의 PDB connection(`${CDS_DB_CONN}`)도 같은 규칙을 따르지만 **Suite Setup 에서 열지
않는다** — 첫 조회 때 지연 접속하고 `Suite CDS Disconnect` 가 닫는다. DB 접속 정보가 없는
환경에서 슈트 전체(전문 송수신 TC 포함)가 서지 못하는 것을 막기 위한 예외다.

주의: `Tcp.Is Connected` 는 `fileno() != -1` 만 본다 — **상대가 끊은 것은 감지하지 못한다.**
NWDAF 만 `Tlv.Nwdaf Peer Closed`(논블로킹 `MSG_PEEK`)로 FIN/RST 를 잡는다.

## 이중 관리되는 카탈로그

의도적으로 두 곳에 같은 값이 있다. **한쪽만 고치면 어긋난다.**

| 대상 | 위치 1 (Python) | 위치 2 (Robot) |
|---|---|---|
| NWDAF TLV 태그 | `TlvHelper.py` `TAG_*` | `nwdaf_variables.robot` `${NWDAF_TAG_*}` |

## 타임아웃

소켓 타임아웃은 **접속 시 1회만** 설정되고 이후 모든 `recv` 가 이를 상속한다.
per-recv 타임아웃 인자도 `Wait Until` 계열 키워드도 리포에 없다.

`${NAG_TIMEOUT}` `${PCF_TIMEOUT}` `${UPM_TIMEOUT}` `${CDS_TIMEOUT}` `${NWDAF_TIMEOUT}`
`${LRS_CLIENT_TIMEOUT}` 모두 기본 10초. `${LRS_ACCEPT_TIMEOUT}` 만 30초다.

더 오래 기다려야 하면 그 구간에서만 올렸다 되돌린다 —
NWDAF Health Check(30초 규격)가 `Tlv.Nwdaf Set Timeout` + `TRY/FINALLY` 로 이 패턴을 쓴다.
