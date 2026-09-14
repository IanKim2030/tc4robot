"""
SshHelper.py — PG 프로세스 .RUN 파일 touch 헬퍼 (SSH)
=====================================================

Suite Setup 이 슈트가 의존하는 PG 프로세스가 죽어 있으면 .RUN 파일을
touch 해 깨운다. 대상 프로세스 이름은 각 노드 콜플로우 문서의
"PG 프로세스 목록" 표를 따른다(예: docs/callflow/cds_callflow.md).

[paramiko 는 지연 임포트한다]
  `import paramiko` 를 모듈 최상단에 두면 paramiko 가 없는 환경에서
  이 리소스를 들여오는 슈트 자체가 로드되지 않는다(CdsDbHelper.py 가
  pyodbc 를 지연 임포트하는 것과 같은 이유). 그래서 함수 안에서
  임포트하고, 없으면 설치 방법을 담은 메시지만 내고 조용히 돌아온다.

[비밀번호 — Robot 키워드 인자로 받지 않는다]
  인자로 넘기면 log.html 의 Arguments 에 평문으로 남는다(CdsDbHelper.py
  가 접속 문자열을 인자로 안 받는 것과 같은 이유). 그래서 비밀번호는
  Python 이 환경변수 PG_SSH_PASSWORD 에서 직접 읽는다 — Robot 쪽에는
  절대 넘어오지 않는다. 키 인증(key_file)이 있으면 키를 우선한다.

[실패해도 예외를 던지지 않는다]
  기동 보장은 편의 기능이지 전제조건이 아니다 — SSH 가 막혀 있어도
  슈트 자체(전문 송수신)는 정상 동작해야 한다. 그래서 이 함수는 어떤
  경우에도 예외를 밖으로 내지 않고, 실패 사유만 출력한다.
"""
import os


def ensure_pg_process_running(host, user, run_dir, processes, key_file=''):
    """user 가 비어 있으면 아무 것도 하지 않고 조용히 돌아온다."""
    if not user:
        print('[SSH] PG_SSH_USER 미설정 — PG 프로세스 기동 보장을 건너뜁니다')
        return

    try:
        import paramiko
    except ImportError:
        print('[SSH] paramiko 가 설치돼 있지 않습니다 (pip install paramiko) — 건너뜁니다')
        return

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        if key_file:
            client.connect(host, username=user, key_filename=key_file, timeout=10)
        else:
            password = os.environ.get('PG_SSH_PASSWORD', '')
            client.connect(host, username=user, password=password, timeout=10)

        for name in processes:
            path = '%s/%s.RUN' % (run_dir, name)
            client.exec_command('touch %s' % path)
            print('[SSH] touch %s' % path)
    except Exception as e:
        print('[SSH] PG 프로세스 기동 보장 실패 — 무시하고 계속 진행합니다: %s' % e)
    finally:
        client.close()
