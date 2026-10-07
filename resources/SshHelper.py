"""
SshHelper.py — PG 프로세스 .RUN 파일 touch 헬퍼 (SSH)
=====================================================

Suite Setup 이 슈트가 의존하는 PG 프로세스가 죽어 있으면 .RUN 파일을
touch 해 깨운다. 대상 프로세스 이름은 각 노드 콜플로우 문서의
"PG 프로세스 목록" 표를 따른다(예: docs/callflow/cds_callflow.md).

[파이썬 SSH 라이브러리를 안 쓴다 — 시스템 ssh 를 그대로 부른다]
  touch 한 줄 보내는 게 전부라 paramiko 같은 라이브러리가 필요 없다.
  `subprocess` 로 시스템 `ssh` 를 그대로 호출한다 — 추가 pip 설치가 없다.

[비밀번호 인증 — sshpass 없이 SSH_ASKPASS 로 자동 주입한다, 2026-10-07]
  실행 환경이 **폐쇄망이라 sshpass 같은 패키지를 새로 설치하기 까다롭다**
  (사용자 확인). 그런데 `ssh` 는 비밀번호를 stdin 이 아니라 `/dev/tty` 에서
  직접 읽는다(보안 설계) — 그래서 `echo password | ssh ...` 식 파이핑은
  안 먹힌다. `sshpass` 는 가짜 pty 로 그 지점을 가로채는 전용 도구인데,
  **같은 효과를 패키지 설치 없이** 내는 방법이 OpenSSH 자체에 내장돼 있다 —
  `SSH_ASKPASS` 환경변수다. ssh 가 비밀번호가 필요할 때 그 경로의 실행파일을
  불러 결과(stdout)를 비밀번호로 쓴다. 여기서는 그 "실행파일"을 짧은 셸
  스크립트로 즉석에서 만든다(설치가 아니라 파일 하나 생성).
    1) 임시 스크립트(`echo "$PG_SSH_ASKPASS_SECRET"`)를 만들어 실행권한을 준다
    2) `SSH_ASKPASS=<그 스크립트>`, `SSH_ASKPASS_REQUIRE=force`(OpenSSH 8.4+,
       2020년 릴리스라 어지간한 배포판엔 있다) 를 환경변수로 준다
    3) `stdin=DEVNULL` + `start_new_session=True`(setsid) 로 자식을 제어
       터미널에서 떼어 `/dev/tty` 를 못 열게 만든다 — 8.4 미만 구버전도
       (DISPLAY 가 있고 tty 가 없으면 askpass로 간다는 옛 규칙까지) 같이
       만족시키는 안전망이다. `DISPLAY` 가 없으면 더미값을 채운다(실제 X
       서버는 필요 없다, 체크만 통과시키는 값).
  사용이 끝나면 스크립트 파일은 바로 지운다.
  키 인증(key_file)에는 이 과정이 전혀 없다 — 원래도 sshpass 가 필요 없었다.

[비밀번호 — Robot 키워드 인자로 받지 않는다]
  인자로 넘기면 log.html 의 Arguments 에 평문으로 남는다(CdsDbHelper.py
  가 접속 문자열을 인자로 안 받는 것과 같은 이유). 그래서 비밀번호는
  Python 이 환경변수 PG_SSH_PASSWORD 에서 직접 읽는다 — Robot 쪽에는
  절대 넘어오지 않는다. 그 값은 askpass 스크립트에도 **리터럴로 박지
  않고** 별도 환경변수(PG_SSH_ASKPASS_SECRET) 참조로만 넘긴다 — 스크립트
  파일 내용 자체는 비밀이 아니다. 키 인증(key_file)이 있으면 키를 우선한다.

[호스트 키 확인은 생략한다]
  `-o StrictHostKeyChecking=no`로 새 호스트 키를 묻지 않고 그냥 받는다 —
  테스트 도구용 일회성 접속이라 대화형 프롬프트가 뜨면 그대로 멈춘다.
  키 인증 경로는 추가로 `-o BatchMode=yes`도 줘서, 키가 안 맞아도
  비밀번호 프롬프트로 빠지지 않고 즉시 실패하게 한다.

[설정 안 함과 실패를 구분한다 — 2026-10-07]
  ★ 예전에는 어떤 이유든 실패하면 전부 삼키고 조용히 넘어갔다("기동 보장은
    편의 기능이지 전제조건이 아니다"). 그런데 그러면 CDS201 등이 실제로
    안 떠 있는 채로 TC 가 돌아가 9999/Connection reset 같은 증상으로
    엉뚱하게 헤매게 된다("조용히 넘어갈 문제가 아니다" — 사용자 확인).
    그래서 지금은 **둘을 구분**한다:
      · ${PG_SSH_USER} 가 비어 있음 / ${PG_SSH_ENSURE}=${FALSE}
        → 이 기능을 **쓰지 않기로 한 선택**이다. 조용히 건너뛴다(예외 없음).
      · 쓰기로 했는데(계정 있음) ssh 가 없거나, 접속·명령이 실패함
        → **CdsDbError 류와 같은 성격의 실패**다. `SshEnsureError`
        를 올린다. 이 함수를 부르는 `Ensure PG Process Running` 이
        Suite Setup 안에서 호출되므로, 예외가 그대로 Setup 을 실패시켜
        **그 슈트의 TC 가 한 건도 돌지 않는다**(Robot 의 기본 동작 — 따로
        Fatal Error 를 쓸 필요가 없다).
"""
import os
import shutil
import stat
import subprocess
import tempfile

_SSH_TIMEOUT = 15          # subprocess 전체 타임아웃(초) — 접속 타임아웃보다 여유를 둔다
_SSH_CONNECT_TIMEOUT = 10  # ssh -o ConnectTimeout
_ASKPASS_ENV = 'PG_SSH_ASKPASS_SECRET'  # 비밀번호를 담는 환경변수 — askpass 스크립트가 참조


class SshEnsureError(Exception):
    """PG 프로세스 기동 보장 실패 — ${PG_SSH_USER} 를 설정해 **쓰기로 한 뒤**의 실패만

    해당한다(설정을 안 한 경우는 예외가 아니라 조용한 skip 이다). Suite Setup
    에서 이 예외가 올라가면 그 슈트의 TC 는 한 건도 돌지 않는다 — 의도된 동작이다.
    """


def _build_ssh_command(key_file):
    """ssh argv 를 만든다. 키 인증이면 `-i`/`BatchMode=yes` 를 더한다."""
    ssh_cmd = [
        'ssh',
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'ConnectTimeout=%d' % _SSH_CONNECT_TIMEOUT,
    ]
    if key_file:
        return ssh_cmd + ['-i', key_file, '-o', 'BatchMode=yes']
    return ssh_cmd + ['-o', 'PubkeyAuthentication=no']


def _write_askpass_script():
    """비밀번호를 ${PG_SSH_ASKPASS_SECRET} 에서 읽어 echo 하는 스크립트를 만든다.

    비밀번호 리터럴은 파일에 안 남는다 — 환경변수 참조만 담는다. 호출부가
    실행 뒤 반드시 지워야 한다(일회성 파일).
    """
    fd, path = tempfile.mkstemp(prefix='pg_ssh_askpass_', suffix='.sh')
    with os.fdopen(fd, 'w') as f:
        f.write('#!/bin/sh\necho "$%s"\n' % _ASKPASS_ENV)
    os.chmod(path, stat.S_IRWXU)  # 0700 — 본인만 읽기/쓰기/실행
    return path


def ensure_pg_process_running(host, user, run_dir, processes, key_file=''):
    """user 가 비어 있으면(=이 기능을 안 쓰기로 한 것) 아무 것도 안 하고 돌아온다.

    user 가 있는데(=쓰기로 한 것) 실패하면 `SshEnsureError` 를 올린다 — 호출부
    (Suite Setup)를 그대로 실패시켜 TC 가 돌지 않게 하려는 의도다.
    """
    if not user:
        print('[SSH] PG_SSH_USER 미설정 — PG 프로세스 기동 보장을 건너뜁니다')
        return

    if not shutil.which('ssh'):
        raise SshEnsureError('ssh 명령을 찾을 수 없습니다 — PG 프로세스 기동 보장을 할 수 없습니다.')

    # 파일마다 개별 접속하지 않고 한 세션에서 전부 touch 한다. `;` 로 이어서
    # 하나가 실패해도(권한 등) 나머지는 계속 시도한다 — 단, 전체 결과가 하나라도
    # 실패했는지는 아래에서 ssh 세션 exit code 로 가늠한다(완벽하진 않지만
    # 실패를 숨기지 않는 쪽을 택했다).
    remote_cmd = '; '.join(
        'touch %s/%s.RUN' % (run_dir, name) for name in processes
    )
    argv = _build_ssh_command(key_file) + ['%s@%s' % (user, host), remote_cmd]

    env = dict(os.environ)
    askpass_path = None
    if not key_file:
        # 비밀번호 인증 — sshpass 없이 SSH_ASKPASS 로 자동 주입한다(모듈 docstring 참조).
        askpass_path = _write_askpass_script()
        env[_ASKPASS_ENV] = os.environ.get('PG_SSH_PASSWORD', '')
        env['SSH_ASKPASS'] = askpass_path
        env['SSH_ASKPASS_REQUIRE'] = 'force'
        env.setdefault('DISPLAY', ':0')  # 구버전 OpenSSH 호환용 더미값, 실제 X 서버 불필요

    try:
        try:
            result = subprocess.run(
                argv, env=env, timeout=_SSH_TIMEOUT,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                stdin=subprocess.DEVNULL, start_new_session=True,
            )
        except Exception as e:
            raise SshEnsureError('PG 프로세스 기동 보장 실패 — %s' % e)
    finally:
        if askpass_path:
            try:
                os.remove(askpass_path)
            except OSError:
                pass

    if result.returncode != 0:
        raise SshEnsureError(
            'PG 프로세스 기동 보장 실패(종료코드 %d) — %s'
            % (result.returncode, result.stderr.decode(errors='replace').strip())
        )
    for name in processes:
        print('[SSH] touch %s/%s.RUN' % (run_dir, name))
