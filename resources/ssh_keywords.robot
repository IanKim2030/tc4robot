*** Settings ***
Documentation
...    PG 서버의 프로세스 `.RUN` 파일을 touch 해 기동을 보장하는 키워드.
...
...    [배경] 각 노드 콜플로우 문서의 "PG 프로세스 목록" 절 — 전문은 정상으로
...    오가는데 뒤쪽 프로세스가 죽어 있으면 응답은 SC 를 주고 PDB/알림 판정만
...    조용히 실패한다. Suite Setup 에서 슈트가 의존하는 프로세스를 미리
...    touch 해 두면 이 문제를 줄일 수 있다.
...
...    [계정 정보] 코드에 절대 비밀번호를 넣지 않는다 — 예전에 SSH 비밀번호가
...    평문으로 커밋됐다가 git 히스토리에 남은 사고 전례가 있다
...    (docs/ENVIRONMENTS.md "자격증명" 절). ${PG_SSH_USER} 만 변수로 두고,
...    비밀번호는 환경변수 PG_SSH_PASSWORD 로만 받는다 — SshHelper.py 가
...    Python 안에서 직접 읽으므로 Robot 키워드 인자로도, log.html 에도
...    남지 않는다. 키 인증을 쓰려면 ${PG_SSH_KEY_FILE} 을 채운다(키 우선).
...
...    [건너뛰는 조건 — "안 쓰기로 한 것"] 아래 중 하나면 SSH 자체를 시도하지
...    않고 조용히 넘어간다(예외 없음).
...      · ${PG_SSH_ENSURE} = ${FALSE} (run_tests.sh --no-ssh-ensure)
...      · ${PG_SSH_USER} 가 비어 있음 (계정 정보 미설정)
...
...    [그 외는 전부 실패로 본다 — 2026-10-07] ${PG_SSH_USER} 를 채워 **쓰기로
...    한 뒤**에는 조용히 넘어가지 않는다. `ssh`/`sshpass`(비밀번호 인증일 때)
...    명령이 없거나, 접속·인증·명령 실행이 실패하면 `SshHelper.SshEnsureError`
...    가 올라온다. 이 키워드는 각 슈트의 **Suite Setup**에서 불리므로, 이
...    예외가 그대로 Setup 을 실패시켜 **그 슈트의 TC 가 한 건도 돌지 않는다**
...    — CDS201 등이 실제로 안 떠 있는 채로 TC 가 돌아가 9999/Connection reset
...    같은 증상으로 헤매는 것을 막기 위함이다(조용히 넘어갈 문제가 아니라는
...    사용자 확인). `--no-ssh-ensure` 로 이 기능 자체를 끄는 것과는 다르다.
...
...    (SshHelper.py 는 파이썬 SSH 라이브러리가 아니라 시스템 ssh/sshpass 를
...    subprocess 로 그대로 부른다 — 둘 다 OS 명령이라 pip 설치가 없다.)
Library    ${CURDIR}/SshHelper.py    WITH NAME    Ssh


*** Keywords ***

Ensure PG Process Running
    [Documentation]
    ...    ${processes} 로 받은 프로세스 이름마다 ${PG_SSH_RUN_DIR}/<이름>.RUN 을
    ...    touch 한다(예: CDS201 → /PG/BIN/PDB_RUN/CDS201.RUN).
    ...
    ...    각 노드 콜플로우 문서의 "PG 프로세스 목록" 표에 있는 이름을 그대로 쓴다
    ...    (예: docs/callflow/nag_callflow.md, docs/callflow/cds_callflow.md,
    ...    docs/callflow/pcf_callflow.md). 표에 `.RUN` 경로가 없는 노드(UPM/NWDAF)는
    ...    아직 확인되지 않았으므로 이 키워드를 부르지 않는다 — 지어내지 않는다.
    [Arguments]    @{processes}
    IF    not ${PG_SSH_ENSURE}
        RETURN
    END
    Ssh.Ensure Pg Process Running    ${PG_HOST}    ${PG_SSH_USER}    ${PG_SSH_RUN_DIR}
    ...    ${processes}    key_file=${PG_SSH_KEY_FILE}
