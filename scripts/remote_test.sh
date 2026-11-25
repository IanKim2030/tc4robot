#!/bin/bash
# remote_test.sh — 로컬 작업 트리(커밋 안 한 변경 포함)를 시험 호스트로 보내 실행하고 결과를 가져온다.
#
# git commit/push → 시험 호스트에서 pull → 수동 실행 을 대신한다. 시험 호스트의 저장소
# (~/ROBOT/tc4robot)는 건드리지 않고, 매번 새 임시 디렉터리에 풀어서 돌린 뒤 지운다.
#
# 사용법 (Git Bash / Linux, 저장소 어디서든):
#   bash scripts/remote_test.sh <대상> [run_tests.sh 인자...]
#       단위 테스트(libraries/tests) → 시험 호스트에서 `run_tests.sh <대상> ...` (실제 PG).
#       예) bash scripts/remote_test.sh cms
#           bash scripts/remote_test.sh cms --include sftp
#   bash scripts/remote_test.sh unit
#       단위 테스트만.
#   옵션 --no-unit : 단위 테스트를 건너뛴다.
#
# 설정 (환경변수, 괄호는 기본값):
#   REMOTE_HOST (192.168.15.142)  REMOTE_USER (kky)  REMOTE_PORT (22)
#   REMOTE_VENV (~/venv)          — 있으면 activate 한다(python3 = venv 파이썬)
#   REMOTE_BASE (/tmp)            — 임시 작업 디렉터리를 만들 곳
#   REMOTE_SSH_PWD                — 키 인증이 없을 때만. 화면·파일·인자에 남기지 않는다(SSH_ASKPASS)
#   PG_PWD_*                      — 로컬에 설정된 것을 원격 실행 환경으로 넘긴다(stdin 으로, 명령행 아님).
#                                   로컬에 없으면 원격 계정의 셸 환경(~/.bashrc 등) 값을 그대로 쓴다.
#
# 결과: results/remote/<시각>_<대상>/ (output.xml, log.html, report.html). 종료 코드 = 시험 결과.

set -u
cd "$(dirname "$0")/.." || exit 2

REMOTE_HOST=${REMOTE_HOST:-192.168.15.142}
REMOTE_USER=${REMOTE_USER:-kky}
REMOTE_PORT=${REMOTE_PORT:-22}
REMOTE_VENV=${REMOTE_VENV:-'~/venv'}
REMOTE_BASE=${REMOTE_BASE:-/tmp}

usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

TARGET=${1:-}
case "$TARGET" in ''|-h|--help|help) usage ;; esac
shift
UNIT=1; EXTRA=()
for a in "$@"; do
    if [ "$a" = --no-unit ]; then UNIT=0; else EXTRA+=("$a"); fi
done

STAMP=$(date +%Y%m%d_%H%M%S)
W="${REMOTE_BASE%/}/tc4robot_remote_${REMOTE_USER}_${STAMP}_$$"
LOCAL_OUT="results/remote/${STAMP}_${TARGET}"

# ── ssh (키 인증 우선, REMOTE_SSH_PWD 가 있으면 askpass) ─────────────────
SSH_OPTS=(-p "$REMOTE_PORT" -o ConnectTimeout=10 -o ServerAliveInterval=30)
ASKPASS=""
cleanup_local() { [ -n "$ASKPASS" ] && rm -f "$ASKPASS"; }
trap cleanup_local EXIT
if [ -n "${REMOTE_SSH_PWD:-}" ]; then
    ASKPASS=$(mktemp "${TMPDIR:-/tmp}/rt_askpass.XXXXXX") || exit 2
    printf '#!/bin/sh\nprintf "%%s\\n" "$REMOTE_SSH_PWD"\n' > "$ASKPASS"
    chmod 700 "$ASKPASS"
    export SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force DISPLAY=${DISPLAY:-:0} REMOTE_SSH_PWD
    SSH_OPTS+=(-o PreferredAuthentications=keyboard-interactive,password -o NumberOfPasswordPrompts=1)
else
    SSH_OPTS+=(-o BatchMode=yes)
fi
rssh() { ssh "${SSH_OPTS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" "$@"; }

# ── 1) 작업 트리 전송: 추적 파일 + 무시되지 않은 새 파일(.gitignore 존중 — results/, local.py 제외) ──
echo "[remote] ${REMOTE_USER}@${REMOTE_HOST}:${W} 로 작업 트리 전송"
git ls-files -co --exclude-standard | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done \
    | tar -czf - -T - \
    | rssh "mkdir -p '$W/repo' && tar -xzf - -C '$W/repo' --warning=no-timestamp" \
    || { echo "[remote] 전송 실패 — ssh 접속(키 또는 REMOTE_SSH_PWD)을 확인하십시오." >&2; exit 2; }

# ── 2) 실행: 스크립트를 stdin 으로 보낸다(비밀번호가 원격 명령행·ps 에 남지 않는다) ──
remote_script() {
    printf 'set -u\nW=%q\nTARGET=%q\nUNIT=%q\nVENV=%s\n' "$W" "$TARGET" "$UNIT" "$REMOTE_VENV"
    printf 'EXTRA=('; for a in "${EXTRA[@]+"${EXTRA[@]}"}"; do printf '%q ' "$a"; done; printf ')\n'
    while IFS='=' read -r name _; do
        case "$name" in PG_PWD_*) printf 'export %s=%q\n' "$name" "${!name}" ;; esac
    done < <(env)
    cat <<'REMOTE'
cd "$W/repo" || exit 2
# venv activate 는 set -u 에서 미정의 변수($1 등)로 죽는다 — 그동안만 끈다
if [ -f "${VENV/#\~/$HOME}/bin/activate" ]; then set +u; . "${VENV/#\~/$HOME}/bin/activate"; set -u; fi
# Windows 작업 트리(autocrlf)에서 온 텍스트 파일의 CR 제거
find . -type f \( -name '*.py' -o -name '*.robot' -o -name '*.sh' -o -name '*.json' -o -name '*.sql' \
    -o -name '*.cfg' -o -name '*.txt' -o -name '*.md' \) -exec sed -i 's/\r$//' {} +
mkdir -p results
echo "[remote] $(hostname) / $(python3 --version 2>&1) / robot $(python3 -c 'import robot;print(robot.__version__)' 2>/dev/null)"
urc=0; rc=0
if [ "$UNIT" = 1 ] || [ "$TARGET" = unit ]; then
    echo "[remote] ── 단위 테스트 (libraries/tests) ──"
    python3 -m unittest discover -s libraries/tests -p 'test_*.py' 2>&1 \
        | grep -v -e CryptographyDeprecationWarning -e 'from cryptography' -e '^\[I '
    urc=${PIPESTATUS[0]}
fi
if [ "$TARGET" != unit ]; then
    echo "[remote] ── run_tests.sh $TARGET ${EXTRA[*]+${EXTRA[*]}} ──"
    bash run_tests.sh "$TARGET" "${EXTRA[@]+"${EXTRA[@]}"}"
    rc=$?
fi
[ $rc -eq 0 ] && rc=$urc
exit $rc
REMOTE
}
remote_script | rssh "bash -s"
RC=$?

# ── 3) 결과 회수 + 원격 임시 디렉터리 삭제 ─────────────────────────────
mkdir -p "$LOCAL_OUT"
rssh "cd '$W/repo' 2>/dev/null && tar -czf - results; rm -rf '$W'" \
    | tar -xzf - -C "$LOCAL_OUT" --strip-components=1 2>/dev/null
echo "[remote] 결과: $LOCAL_OUT"
find "$LOCAL_OUT" -name log.html | sed 's/^/  /'
echo "[remote] 종료 코드 $RC ($([ $RC -eq 0 ] && echo 통과 || echo 실패))"
exit $RC
