"""
SshHelper.py — PG 프로세스 .RUN 파일 touch 헬퍼 (SSH)
=====================================================

Suite Setup 이 슈트가 의존하는 PG 프로세스가 죽어 있으면 .RUN 파일을
touch 해 깨운다. 대상 프로세스 이름은 각 노드 콜플로우 문서의
"PG 프로세스 목록" 표를 따른다(예: docs/callflow/cds_callflow.md).

[파이썬 SSH 라이브러리를 안 쓴다 — 시스템 ssh 를 그대로 부른다]
  touch 한 줄 보내는 게 전부라 paramiko 같은 라이브러리가 필요 없다.
  `subprocess` 로 시스템 `ssh`(키 인증) / `sshpass ssh`(비밀번호 인증)를
  그대로 호출한다. 추가 pip 설치가 필요 없는 대신, 비밀번호 인증을 쓰려면
  `sshpass` 가 서버(이 슈트를 실행하는 쪽)에 깔려 있어야 한다
  (`apt install sshpass` / `yum install sshpass`). 키 인증(key_file)은
  `sshpass` 없이도 된다.

[비밀번호 — Robot 키워드 인자로 받지 않는다]
  인자로 넘기면 log.html 의 Arguments 에 평문으로 남는다(CdsDbHelper.py
  가 접속 문자열을 인자로 안 받는 것과 같은 이유). 그래서 비밀번호는
  Python 이 환경변수 PG_SSH_PASSWORD 에서 직접 읽는다 — Robot 쪽에는
  절대 넘어오지 않는다(sshpass 에도 인자가 아니라 `-e`로 넘겨 환경변수
  에서 읽게 한다 — `ps`로 커맨드라인을 보는 다른 사용자에게도 안 보인다).
  키 인증(key_file)이 있으면 키를 우선한다.

[호스트 키 확인은 생략한다]
  `-o StrictHostKeyChecking=no`로 새 호스트 키를 묻지 않고 그냥 받는다 —
  테스트 도구용 일회성 접속이라 대화형 프롬프트가 뜨면 그대로 멈춘다.
  키 인증 경로는 추가로 `-o BatchMode=yes`도 줘서, 키가 안 맞아도
  비밀번호 프롬프트로 빠지지 않고 즉시 실패하게 한다(프롬프트가 뜨면
  stdin 이 없는 subprocess 에서 그대로 멈춰버리기 때문).

[설정 안 함과 실패를 구분한다 — 2026-10-07]
  ★ 예전에는 어떤 이유든 실패하면 전부 삼키고 조용히 넘어갔다("기동 보장은
    편의 기능이지 전제조건이 아니다"). 그런데 그러면 CDS201 등이 실제로
    안 떠 있는 채로 TC 가 돌아가 9999/Connection reset 같은 증상으로
    엉뚱하게 헤매게 된다("조용히 넘어갈 문제가 아니다" — 사용자 확인).
    그래서 지금은 **둘을 구분**한다:
      · ${PG_SSH_USER} 가 비어 있음 / ${PG_SSH_ENSURE}=${FALSE}
        → 이 기능을 **쓰지 않기로 한 선택**이다. 조용히 건너뛴다(예외 없음).
      · 쓰기로 했는데(계정 있음) ssh/sshpass 가 없거나, 접속·명령이
        실패함 → **CdsDbError 류와 같은 성격의 실패**다. `SshEnsureError`
        를 올린다. 이 함수를 부르는 `Ensure PG Process Running` 이
        Suite Setup 안에서 호출되므로, 예외가 그대로 Setup 을 실패시켜
        **그 슈트의 TC 가 한 건도 돌지 않는다**(Robot 의 기본 동작 — 따로
        Fatal Error 를 쓸 필요가 없다).
"""
import os
import shutil
import subprocess

_SSH_TIMEOUT = 15          # subprocess 전체 타임아웃(초) — 접속 타임아웃보다 여유를 둔다
_SSH_CONNECT_TIMEOUT = 10  # ssh -o ConnectTimeout


class SshEnsureError(Exception):
    """PG 프로세스 기동 보장 실패 — ${PG_SSH_USER} 를 설정해 **쓰기로 한 뒤**의 실패만

    해당한다(설정을 안 한 경우는 예외가 아니라 조용한 skip 이다). Suite Setup
    에서 이 예외가 올라가면 그 슈트의 TC 는 한 건도 돌지 않는다 — 의도된 동작이다.
    """


def _build_ssh_command(host, user, key_file):
    """(실행할 argv 리스트, 비밀번호를 환경변수로 넘겨야 하는지) 를 돌려준다.

    키 인증이면 `ssh -i ...` 그대로, 아니면 `sshpass -e ssh ...` 로 감싼다
    (비밀번호는 환경변수 SSHPASS 로 전달 — 호출부가 채운다).
    """
    ssh_cmd = [
        'ssh',
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'ConnectTimeout=%d' % _SSH_CONNECT_TIMEOUT,
    ]
    if key_file:
        ssh_cmd += ['-i', key_file, '-o', 'BatchMode=yes']
        return ssh_cmd, False

    ssh_cmd += ['-o', 'PubkeyAuthentication=no']
    return ['sshpass', '-e'] + ssh_cmd, True


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

    ssh_cmd, needs_sshpass = _build_ssh_command(host, user, key_file)
    if needs_sshpass and not shutil.which('sshpass'):
        raise SshEnsureError(
            'sshpass 가 설치돼 있지 않습니다 (apt/yum install sshpass). '
            '키 인증을 쓰려면 ${PG_SSH_KEY_FILE} 을 채우십시오.'
        )

    # 파일마다 개별 접속하지 않고 한 세션에서 전부 touch 한다. `;` 로 이어서
    # 하나가 실패해도(권한 등) 나머지는 계속 시도한다 — 단, 전체 결과가 하나라도
    # 실패했는지는 아래에서 ssh 세션 exit code 로 가늠한다(완벽하진 않지만
    # 실패를 숨기지 않는 쪽을 택했다).
    remote_cmd = '; '.join(
        'touch %s/%s.RUN' % (run_dir, name) for name in processes
    )
    argv = ssh_cmd + ['%s@%s' % (user, host), remote_cmd]

    env = dict(os.environ)
    if needs_sshpass:
        env['SSHPASS'] = os.environ.get('PG_SSH_PASSWORD', '')

    try:
        result = subprocess.run(
            argv, env=env, timeout=_SSH_TIMEOUT,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
    except Exception as e:
        raise SshEnsureError('PG 프로세스 기동 보장 실패 — %s' % e)

    if result.returncode != 0:
        raise SshEnsureError(
            'PG 프로세스 기동 보장 실패(종료코드 %d) — %s'
            % (result.returncode, result.stderr.decode(errors='replace').strip())
        )
    for name in processes:
        print('[SSH] touch %s/%s.RUN' % (run_dir, name))
