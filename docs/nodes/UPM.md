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

### fileinfo (0x0c) — FTP 수신 서버 (접속 정보 확인됨, fileinfo 스키마는 ⚠ 미확인)

규격 6.6.1/6.6.2 는 0x0c(Subs-Sync-Response) 응답에 "fileinfo 포함 가능"이라고만
적혀 있다. **fileinfo 필드 자체의 스키마(파일명/크기 등)는 여전히 확인되지
않았다** — 규격 원문도 이 리포에 없고, 전체 grep 결과 다른 언급도 없다.

다만 **FTP 접속 정보는 PG 쪽 FTP 타겟 설정으로 확인됐다**(2026-10-22) — PG 설정의
`SYSTEM_ID_04=UPMROB` 항목(`${UPM_SYS_ID}`와 일치해 우리 쪽 항목임을 확인)이
다음을 담고 있었다:

| 키 | 값 | 의미 |
|---|---|---|
| `IP_04` | `192.168.15.142` | PG 가 접속할 주소(도구가 도는 호스트) |
| `PORT_04` | `2121` | `${UPM_FTP_PORT}` |
| `USER_ID_04` / `PASSWORD_04` | `upm` / `upm1234` | `${UPM_FTP_USER}` / `${UPM_FTP_PASSWORD}` |
| `REMOTE_PATH_04` | `/PG/FTP/UPM-ROBOT` | 로그인 후 CWD 로 들어오는 경로 — `${UPM_FTP_REMOTE_PATH}` |
| `LOCAL_PATH_04` | `/PG/FTP/UPM` | PG 쪽 로컬 경로(원본 파일 위치, 참고용) |
| `USE_SFTP_04` | `N` | 평문 FTP (SFTP 아님) — pyftpdlib 선택과 일치 |

즉 "PG 가 UPM 으로 파일을 보낸다"는 PG 가 FTP Client 로 붙어 Push 한다는 뜻이
맞았고(사용자 확인), 도구가 **FTP 서버** 역할을 하는 것도 이 설정으로 확정됐다 —
`resources/FtpServerHelper.py`(`HttpNotiServer.py` 와 같은 구조: 지연 임포트 +
데몬 스레드 + 수신 큐, pyftpdlib 를 감싼다). `REMOTE_PATH_04` 는 pyftpdlib 가
**FTP 가상 루트(업로드 디렉터리) 기준 상대 경로**로 해석하므로, 서버 기동 시
그 서브디렉터리를 미리 만들어 둔다(없으면 로그인 후 CWD 가 550 으로 거부됨).

**전송되는 파일은 2개다(사용자 확인, 2026-10-22)** — 데이터 파일 + "FIN" 파일
(전송 완료를 알리는 트리거 파일, 레거시 배치 전송에서 흔한 관례). 어느 쪽이
FIN 인지는 파일명에 `${UPM_FTP_FIN_PATTERN}`(기본 `FIN`, 대소문자 무관) 이
포함되는지로 **추정**한다 — 실제 명명 규칙이 확인되면 그 변수만 고치면 된다.

`TC-UPM-004`가 0x0c 수신 후 `Verify Subs Sync Fileinfo`(`upm_keywords.robot`)로
다음을 best-effort 로 한다:

1. fileinfo 가 없으면 건너뛴다(규격상 "포함 가능"일 뿐 매 응답에 있는 게 아니다).
2. fileinfo 가 있으면 `${UPM_FTP_WAIT}`(기본 30s) 동안 **파일 2개**(데이터+FIN)
   가 다 오는지 기다린다 — 둘 다 못 채우면 **Fail** 한다(이건 엄격하다). 실패
   메시지에 몇 건이 왔는지(0건/1건만)와 함께 **FTP 접속 이력**도 같이 남겨
   "PG 가 접속 자체를 안 함"과 "접속은 했는데 파일을 안 보냄"을 가른다
   (2026-10-22 — 실제로 접속·수신·오류가 전부 0건인 상황이 재현돼, 그 둘을
   구분 못 하던 걸 고쳤다).
3. 수신된 두 파일 중 FIN 패턴에 맞는 게 없으면 ⚠ WARN 로그만 남긴다(어느 쪽이
   FIN 인지 구분 실패 — 패턴이 추정과 다를 수 있음).
4. fileinfo 안에서 파일명으로 추정되는 키(`filename`/`fileName`/`file_name`/
   `file-name`/`name`, `Guess Fileinfo Filename` 참조)가 있으면 수신 파일명과
   대조하되, **안 맞아도 WARN 로그만 남기고 실패시키지 않는다** — fileinfo 의
   실제 키 이름이 추정과 다를 수 있기 때문이다.

> ⚠ 실제 fileinfo 샘플과 FIN 파일 명명 규칙이 확보되면 `Guess Fileinfo
> Filename`/`${UPM_FTP_FIN_PATTERN}`(upm_keywords.robot / upm_variables.robot)과
> 이 절을 함께 갱신할 것 — 지금은 전부 추측값이다.

끄려면: `bash run_tests.sh upm --no-ftp` (pyftpdlib 없이도 슈트가 돈다).

**SFTP 대안(2026-10-22 추가)** — PG 설정의 `USE_SFTP_04` 가 확인된 값은 `N`
(평문 FTP)이지만, 다른 환경에서 `Y` 로 바뀌는 경우에 대비해 `${UPM_FTP_USE_SFTP}`
(기본 `${FALSE}`)를 True 로 두면 같은 수신 서버를 FTP 대신 SFTP 로 띄운다 —
`resources/SftpServerHelper.py`(paramiko, 지연 임포트). host/port/계정/
remote_path 변수는 FTP 와 완전히 같은 것을 재사용하고, 반환되는 서버 핸들도
FtpServer 와 같은 메서드(files/errors/connections/clear/stop/is_running)를
구현해 `upm_keywords.robot`/`Verify Subs Sync Fileinfo` 는 어느 쪽이 떠 있든
그대로 쓴다. 토글: `bash run_tests.sh upm --sftp` / `--no-sftp`.

> ⚠ **실제로 구동해 검증하지 못했다** — pyftpdlib(FTP)와 달리 성숙한 SFTP
> 서버 전용 라이브러리가 없어 paramiko 저수준 API로 직접 구현했고, 이
> 작업 환경에 로컬 Python 이 없어 `import paramiko` 조차 실행해 보지
> 못했다. USE_SFTP_04 가 실제로 `Y` 인 환경을 테스트하기 전에, 반드시
> 표준 `sftp` 클라이언트 등으로 업로드 왕복을 먼저 확인할 것.

## TC

현재 **활성 4건 / 주석 1건**. 태그: `upm` `hello` `ping` `cellinfo-noti` `subs-sync` `smoke` `validation`
(+ 주석 TC 에 `subs-info` `subs-change` `info-change`). `TC-UPM-004`는 fileinfo
수신 시 FTP 파일 수신까지 확인한다(위 "fileinfo (0x0c)" 절 참조).

## 함정

**수동 수신 TC 는 대부분 주석 처리돼 있다.** PG 측에서 실제 이벤트(가입·해지·번호 변경)가
발생해야 동작하기 때문이다. 키워드(`Receive Subs Info Request` 등)는 전부 구현돼 있으므로
PG 이벤트 트리거가 가능해지면 주석만 풀면 된다.
