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
resources/ssh_keywords.robot          ← PG 프로세스 기동 보장 (.RUN touch)
resources/variables.robot             ← 공용 변수 (Hello/Ping opcode, PDB·SBI·SSH 설정). 환경값은 없다
        │ 사용 (WITH NAME …)
        ▼
resources/*.py                        ← Python 헬퍼 11종 (아래 표)
```

임포트 순서가 중요하다. 노드별 변수 파일이 `variables.robot` 의 공용 변수(`${SBI_NOTI_PORT}` 등)와
환경 파일의 환경값(`${PG_HOST}` 등)을 참조하므로 **`variables.robot` 을 항상 먼저 임포트**한다.
모든 슈트가 이 순서를 지킨다.

## Python 헬퍼 11종

성격이 셋이다 — **전문 헬퍼**(PG 로 전문을 만들어 보낸다) 6종, **수신 서버**(PG 가 붙어 오는 것을
받는다) 3종, **인프라**(DB 시드·SSH) 2종.

### 전문 헬퍼

| 모듈 | Robot 별칭 | 담당 | 주요 함수 |
|---|---|---|---|
| `TcpHelper.py` | `Tcp` | 소켓 + 8옥텟 헤더. 서버 모드도 여기 | `tcp_connect` `server_start` `server_accept` `build_header` `parse_header` `send_message` `receive_message` `pack_fields` `unpack_fields` `send_lrs_message` `receive_lrs_message` `send_text` `recv_text` `recv_http_response` |
| `CdsHelper.py` | `Cds` | 48옥텟 CDS 고정전문. 소켓은 `TcpHelper` 재사용 | `pack_cds_header` `parse_cds_header` `send_cds` `receive_cds` `pack_ack` `unpack_ack` `pack_command_body` `unpack_command_body` |
| `TlvHelper.py` | `Tlv` | NWDAF TLV. 소켓까지 자체 구현 | `build_nwdaf_header` `parse_nwdaf_header` `pack_tlv` `unpack_tlv_stream` `tlv_find` `tlv_find_all` `build_common1` `build_pcef_qos_ctrl` `build_dpi_qos_ctrl` `build_enb_qos_ctrl` `build_common2` `send_nwdaf_notification` `send_nwdaf_raw` `receive_nwdaf_message` `hex_dump` |
| `HttpHelper.py` | — | LRS Session-Info 전용 | `build_aims_req` `parse_xml_fields` `post_session_info` |
| `PdbHelper.py` | `CdsDb` · `RtsDb` · `SeedDb` | PDB(골디락스/알티베이스) 조회 + 쓰기(세션 사전 적재 INSERT, 종료 시 정리 DELETE). ODBC. CDS·RTS·시드가 같은 모듈을 별칭만 달리 쓴다. `${PDB_CONNSTR_2}` 로 두 번째 DB 도 지원. 예외 `PdbError`(구 `CdsDbError` 별칭) | `masked_conn_str` `db_connect` `db_end_transaction` `db_close` `db_count` `db_group_counts` `db_execute` `session_insert_sql` `has_second_db` |
| `RtsHelper.py` | `Rts` | 32옥텟 RTS 고정전문(로밍 데이터 차단 L1/L2). 소켓은 `TcpHelper` 재사용 | `pack_rts_header` `parse_rts_header` `send_rts` `receive_rts` `pack_rts_order_body` `unpack_rts_order_body` `unpack_connect_ack` `unpack_order_ack` `unpack_keepalive_ack` |

`PdbHelper` 만 성격이 다르다 — 전문을 만들지 않고 **PG 가 DB 에 반영했는지를 본다**.
접속 문자열(조립하지 않음, 비밀번호를 인자로 받지 않음, 마스킹)·함정은 [shared/PDB.md](shared/PDB.md).
`pyodbc` 는 **지연 임포트**한다(모듈 최상단에 두면 pyodbc 없는 환경에서 슈트 전체가 로드되지 않는다).

### 수신 서버 — PG 가 도구로 붙어 온다

| 모듈 | Robot 별칭 | 담당 | 주요 함수 |
|---|---|---|---|
| `HttpNotiServer.py` | `Noti` | PCF SBI Noti(h2c) Listen — CDS·RTS 공용. `h2` 지연 임포트 | `noti_server_start` `noti_server_stop` `noti_wait` `noti_count` `noti_list` `noti_errors` `noti_clear` `noti_wait_connection` `noti_link_report` |
| `FtpServerHelper.py` | `Ftp` | UPM `0x0c` fileinfo 에 대응하는 FTP 수신 서버(`pyftpdlib`). `use_sftp=True` 면 아래 SFTP 서버를 대신 띄운다 | `ftp_server_start` `ftp_server_stop` `ftp_wait` `ftp_count` `ftp_list` `ftp_errors` `ftp_clear` |
| `SftpServerHelper.py` | (직접 import 안 함) | SFTP 수신 서버(`paramiko`). `FtpServerHelper` 가 파일 경로로 로드한다 — 이름 import 가 실환경에서 `ModuleNotFoundError` 였다 | `SftpServer.start` `stop` `files` `errors` |

LRS 8890 곁채널 Listen 은 별도 모듈이 아니라 `TcpHelper` 의 서버 모드(`server_start`/`server_accept`)다.
SBI Noti 상세는 [shared/SBI_NOTI.md](shared/SBI_NOTI.md).

### 인프라

| 모듈 | Robot 별칭 | 담당 | 주요 함수 |
|---|---|---|---|
| `DbSeedHelper.py` | `Seed` | 실행 전 DB 설정 시드 — `config/db_seed/<env>.sql` 을 "확인 SELECT + INSERT/UPDATE" 블록으로 나누고 `${변수}` 를 Robot 변수 값으로 치환한다. 접속·실행은 `PdbHelper` | `load_seed_blocks` `describe_statement` `describe_check` |
| `SshHelper.py` | `Ssh` | `.RUN` touch 는 시스템 `ssh`(비밀번호는 `SSH_ASKPASS` 주입), 시드 후속 명령(stopMP/startMP)은 `paramiko`(지연 임포트) | `ensure_pg_process_running` `run_remote_command` |

시드 형식은 [shared/PDB.md](shared/PDB.md#실행-전-db-설정-시드-configdb_seedenvsql), SSH 는 [shared/SSH.md](shared/SSH.md).

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

공용 단일 소스. **값 변경은 TC 가 아니라 이 파일(또는 환경 파일)에서 한다.**

- **환경 축 변수** — `${PG_HOST}`, `${TOOL_HOST}`, `${PDB_CONNSTR}`, 가입자(`${SUBS_MDN_LTE}` 등)는
  **이름만 공용이고 값은 `config/env/<env>.py` 에만 있다**(이 파일엔 기본값이 없다).
  망 데이터(`${NET_CELL_ID}` 등)는 여기 기본값이 있다. 노드별 변수 파일이 이를 **참조만**
  하므로 하나를 바꾸면 관련 노드 전부에 전파된다. **기준은 "두 노드 이상이 공유하는 값"** 이다.
  한 노드 전용 값은 해당 `<iface>_variables.robot` 에 직접 둔다(예: CDS 가입자 `${CDS_MDN}`).
  규칙과 구 이름 대응표는 [ENVIRONMENTS.md](ENVIRONMENTS.md)
- **공용 설정** — PDB(`${PDB_TIMEOUT}` `${PDB_AUTOCOMMIT}` `${PDB_CONNSTR_2}`),
  SBI Noti(`${SNOTI_PCF_NOTI}` `${SBI_NOTI_PORT}` `${SBI_NOTI_HOST}`), SSH(`${PG_SSH_*}`),
  시드(`${DB_SEED_*}`)
- `${MSG_HELLO_REQ}`(0x01) / `${MSG_HELLO_RESP}`(0x02) / `${MSG_PING_REQ}`(0x03) /
  `${MSG_PING_RESP}`(0x04) — 여기 있는 4개만 노드 공용이다

`0x05` 이상은 노드마다 의미가 달라 각 `<iface>_variables.robot` 에 따로 있다.
충돌표는 [INTERFACES.md](INTERFACES.md#opcode-충돌--노드별-상수명을-그대로-써라).

## 소켓 공유 규칙 (절대)

소켓은 **슈트당 1회만** 열리고 모든 TC 가 Suite Variable 로 공유한다:
`${NAG_SOCK}` `${PCF_SOCK}` `${LRS_CONN}` `${LRS_SRV_SOCK}` `${UPM_SOCK}`
`${CDS_SCH_SOCK}` `${CDS_RCH_SOCK}` `${NWDAF_SOCK}` `${RTS_SOCK}`

각 `Test Setup` 의 `Check ... Socket` 이 닫힘을 감지하면 **`Fatal Error` 로 슈트 전체를 중단**한다.
연결이 없으면 이후 TC 도 의미가 없기 때문이다.

**TC 별 connect/disconnect 로직을 추가하지 말 것.**

CDS 의 PDB connection(`${CDS_DB_CONN}`)도 **똑같이** 슈트당 1회다 — `Suite CDS Connect`
가 소켓에 이어 붙이고 `Suite CDS Disconnect` 가 닫는다. 그래서 DB 접속 정보가 틀리면
전문 송수신 TC 까지 포함해 **슈트 전체가 서지 않는다**(`--exclude db` 로도 피할 수 없다 —
Suite Setup 은 태그와 무관하게 실행된다).

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
`${RTS_TIMEOUT}` `${LRS_CLIENT_TIMEOUT}` 모두 기본 10초. `${LRS_ACCEPT_TIMEOUT}` 만 30초다.

더 오래 기다려야 하면 그 구간에서만 올렸다 되돌린다 —
NWDAF Health Check(30초 규격)가 `Tlv.Nwdaf Set Timeout` + `TRY/FINALLY` 로 이 패턴을 쓴다.
