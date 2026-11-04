# SSH — PG 서버 원격 조작 (프로세스 기동 보장 · 시드 후속 명령)

도구가 PG 서버(`${PG_HOST}`)에 SSH 로 붙어 명령을 실행하는 곳은 둘이다. 접속 경로는 하나다 —
[resources/SshHelper.py](../../resources/SshHelper.py) 가 **시스템 `ssh` 를 subprocess 로 그대로 부른다**
(파이썬 SSH 라이브러리 없음, pip 설치 없음).

| 용도 | 언제 | 키워드 / 함수 |
|---|---|---|
| PG 프로세스 기동 보장 | 각 슈트 Suite Setup | `Ensure PG Process Running` ([ssh_keywords.robot](../../resources/ssh_keywords.robot)) → `ensure_pg_process_running` |
| 시드 INSERT 후 원격 명령 | `setup/db_seed.robot` 끝 | `Run Seed SSH Commands` → `run_remote_command` |

## 계정 · 인증

| 변수 | 기본값 | 설명 |
|---|---|---|
| `${PG_SSH_USER}` | 빈 값 | 비어 있으면 기동 보장을 **조용히 건너뛴다**. dev/stg 는 `pg` |
| `${PG_SSH_KEY_FILE}` | 빈 값 | 채우면 키 인증(`-i`, `BatchMode=yes`). 키가 우선이다 |
| 환경변수 `PG_SSH_PASSWORD` | — | 비밀번호 인증. **Robot 변수로 받지 않는다**(log.html 에 평문으로 남기 때문) |

비밀번호는 `sshpass` 없이 OpenSSH 내장 `SSH_ASKPASS` 로 주입한다 — 폐쇄망이라 패키지를 추가로
설치하기 어려워서다. 비밀번호 리터럴은 임시 askpass 스크립트에도 남지 않고, 스크립트는
실행 직후 지운다. 호스트 키 확인은 생략한다(`StrictHostKeyChecking=no`).

> ⚠ 예전에 SSH 비밀번호가 평문으로 커밋된 사고가 있었다 — [ENVIRONMENTS.md](../ENVIRONMENTS.md#자격증명).

## PG 프로세스 기동 보장 — `.RUN` touch

슈트가 의존하는 PG 프로세스마다 `${PG_SSH_RUN_DIR}/<이름>.RUN`(기본 `/PG/BIN/PDB_RUN`)을
touch 한다. 전문은 정상으로 오가는데 뒤쪽 프로세스가 죽어 있으면, 응답은 `SC` 인데
PDB/알림 판정만 조용히 실패하기 때문이다.

| 슈트 | 프로세스 | 근거 |
|---|---|---|
| NAG | `G_BNOTI201` `G_LRS201` `CDS201` | [callflow/nag_callflow.md](../callflow/nag_callflow.md) |
| PCF | `CDS201` | [callflow/pcf_callflow.md](../callflow/pcf_callflow.md) |
| LRS | `G_LRS201` `CDS201` | [callflow/lrs_callflow.md](../callflow/lrs_callflow.md) |
| CDS | `CDS201` `P_SDM601` `R_SDM601` `SNOTI501` `BSUBS201` `RDS601` | [callflow/cds_callflow.md](../callflow/cds_callflow.md) |
| RTS | `RTS201` `P_SDM601` `SNOTI501` | [callflow/rts_callflow.md](../callflow/rts_callflow.md) |

UPM/NWDAF 는 `.RUN` 경로가 확인되지 않아 부르지 않는다 — 지어내지 않는다.

NAG/PCF/LRS 는 touch 뒤 `${PG_SSH_SETTLE}`(기본 3s)만큼 쉬고 소켓을 연다. touch 는 신호일 뿐이라
PG 가 기동을 끝낼 시간이 더 필요하다(2026-10-20). CDS/RTS 는 그 사이 PDB 접속 등이 끼어 있어 따로 쉬지 않는다.

**설정 안 함과 실패를 구분한다.** `${PG_SSH_USER}` 가 비어 있거나 `--no-ssh-ensure`
(`${PG_SSH_ENSURE}=${FALSE}`)면 건너뛴다. 계정을 채운 뒤에 `ssh` 가 없거나 접속·명령이
실패하면 `SshEnsureError` 가 Suite Setup 을 실패시켜 **그 슈트의 TC 가 한 건도 돌지 않는다**
— 프로세스가 죽은 채로 TC 가 돌아 9999/Connection reset 으로 헤매는 것을 막기 위해서다.

## 시드 INSERT 후 원격 명령

[실행 전 DB 설정 시드](PDB.md#실행-전-db-설정-시드-configdb_seedenvsql)가 INSERT 를 한 블록이라도
했으면(DB1+DB2 합산) `${DB_SEED_SSH_CMDS}` 를 차례로 실행한다. PG 가 새로 들어간 설정 행을
다시 읽게 하려는 것이다. 명령마다 ssh 세션을 따로 열고, 명령 사이에 `${DB_SEED_SSH_GAP}` 만큼 쉰다.

```python
# config/env/dev.py
DB_SEED_SSH_CMDS = ['stopMP app', 'startMP app']
DB_SEED_SSH_GAP  = '5s'
```

| 변수 | 기본값 | 설명 |
|---|---|---|
| `@{DB_SEED_SSH_CMDS}` | 비어 있음 | 비어 있으면 건너뛴다 |
| `${DB_SEED_SSH_GAP}` | `5s` | 명령 사이 대기(마지막 명령 뒤에는 안 쉰다) |
| `${DB_SEED_SSH_TIMEOUT}` | `60` | 명령 하나의 ssh 타임아웃(초) |
| `${DB_SEED_SSH_ENABLE}` | `${TRUE}` | `--no-db-seed-ssh` 로 끈다 |

INSERT 0건이거나 확인만 모드(`--db-seed-check`)면 실행하지 않는다. 여기서는 `${PG_SSH_USER}`
가 비어 있으면 **실패**다 — 명령을 채워 쓰기로 한 뒤라서다. 명령이 실패(종료코드≠0)하면
시드가 실패하고 본 실행을 하지 않는다.

★ 비대화형 `ssh host cmd` 는 `.profile`/`.bash_profile` 을 읽지 않는 경우가 많다. `stopMP` 가
PATH 나 alias 로만 잡히는 명령이면 `command not found`(종료코드 127)가 난다 — 그때는
`bash -lc 'stopMP app'` 처럼 로그인 셸로 감싸거나 절대경로를 쓴다.
