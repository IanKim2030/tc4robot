#!/bin/bash
# run_tests.sh - PG 연동 통합 테스트 실행 스크립트
#
# 인터페이스:
#   NAG    클라이언트 모드 → PG 서버 (Port 8012)
#   PCF    클라이언트 모드 → PG 서버 (Port 8011)
#   LRS    클라이언트 모드 → PG.LRS 서버 (Port 10204, Health Check/Ping + SESSION-INFO)
#   UPM    클라이언트 모드 → PG 서버 (Port 10506, HFC 가입자 Cell List 연동)
#   NWDAF  클라이언트 모드 → PG 서버 (Port ${NWDAF_PORT}, TLV Notification 주력)
#   CDS    클라이언트 듀얼소켓 → PG.CDS (Schannel 9200 / Rchannel 9201, 48B 고정전문)
#
# 사용법:
#   bash run_tests.sh nag              # NAG 전체
#   bash run_tests.sh pcf              # PCF 전체
#   bash run_tests.sh lrs              # LRS 전체 (클라이언트 모드, PG.LRS:10204 접속)
#   bash run_tests.sh upm              # UPM 전체 (PG.BSUBS 연동)
#   bash run_tests.sh nwdaf            # NWDAF 전체 (TLV Notification)
#   bash run_tests.sh cds              # CDS 전체 (PG.CDS 듀얼소켓 접속)
#   bash run_tests.sh all              # NAG + PCF + LRS + UPM + NWDAF + CDS 전체
#   bash run_tests.sh smoke            # smoke 태그만
#   bash run_tests.sh nag --log-msg    # REQ/RESP 시각 출력 ON
#
# CDS 곁가지 연동 켜고 끄기 (기본은 둘 다 켜짐 — cds_variables.robot):
#   bash run_tests.sh cds --no-upm          # UPM(10506) 접속·0x07 검증 생략
#   bash run_tests.sh cds --no-sbi          # PCF SBI Listen(16101) 자체를 안 함
#   bash run_tests.sh cds --no-upm --no-sbi     # CDS 전문 + PDB 만
#   bash run_tests.sh cds --sbi-wait         # PG 가 붙을 때까지 기다렸다 시작(기본은 안 기다림)
#   bash run_tests.sh cds --no-session      # 세션 사전 적재(INSERT) 생략
#
# CDS 사전 확인 — 두 대상 번호에 앞선 실행의 행이 남아 있는지 본다(기본: 물어본다):
#   bash run_tests.sh cds --precheck-warn   # 화면 없는 환경 — WARN 만 남기고 진행
#   bash run_tests.sh cds --precheck-fail   # 잔존 데이터면 무조건 중단
#   bash run_tests.sh cds --no-precheck     # 확인 자체를 생략
#   ★ 기본(ask)은 Tkinter 창을 띄운다 — SSH 등 화면이 없으면 중단되고 안내가 나온다.
#   --upm / --sbi / --sbi-wait / --session 은 반대로 강제로 켠다.
#   별칭: --no-http / --no-noti 도 --no-sbi 로 받는다(예전 이름).
#
#   ★ PDB 는 이 플래그로 못 끈다 — Suite Setup 이 무조건 붙는다.
#     접속 문자열이 없으면 전문 TC 까지 포함해 슈트 전체가 서지 않는다.
#
# 환경 지정 (2번째 인자):
#   bash run_tests.sh nag              # dev (기본)
#   bash run_tests.sh nag stg          # config/env/stg.py 적용
#   bash run_tests.sh all prd          # PG_ALLOW_PRD=1 필요
#   bash run_tests.sh all 192.168.1.1  # IP 직접 지정 (PG_HOST 오버라이드)
#
# 단일 TC 실행:
#   robot --test "TC-NAG-010*"   tests/nag/
#   robot --test "TC-LRS-006*"   tests/lrs/
#   robot --test "TC-UPM-005*"   tests/upm/
#   robot --test "TC-NWDAF-001*" tests/nwdaf/
#
# 변수 지정:
#   robot --test "TC-CDS-011*" --variable CDS_ACTIVE_MDN:01090010002 tests/cds/

TARGET=${1:-smoke}
EXTRA_ARGS=()

# CDS 슈트의 곁가지 연동을 켜고 끄는 플래그 → --variable 로 변환한다.
# 기본값은 cds_variables.robot 이 쥔다(둘 다 ${TRUE}). 여기서는 **준 것만** 덮는다.
TOGGLE_VARS=()

for arg in "${@:2}"; do
    case "${arg}" in
        --log-msg)      export PG_LOG_MSG=1 ;;
        # UPM — TC-CDS-003(1X)의 Subs-Info(0x07/0x08) 구간.
        # 끄면 Suite Setup 이 UPM(${UPM_PG_PORT})에 접속조차 하지 않는다.
        --no-upm)       TOGGLE_VARS+=(--variable CDS_UPM_VERIFY:False) ;;
        --upm)          TOGGLE_VARS+=(--variable CDS_UPM_VERIFY:True) ;;
        # PCF SBI — 도구가 PCF 역할로 여는 SBI Noti 수신 서버(${CDS_NOTI_PORT}).
        # 끄면 Listen 도 접속 대기도 안 한다 → h2 패키지 없이도 슈트가 돈다.
        # (전송은 HTTP/2 평문이다. 프로토콜 얘기는 HttpNotiServer.py 를 볼 것)
        --no-sbi|--no-http|--no-noti)
                        TOGGLE_VARS+=(--variable CDS_NOTI_VERIFY:False) ;;
        --sbi|--http|--noti)
                        TOGGLE_VARS+=(--variable CDS_NOTI_VERIFY:True) ;;
        # 사전 확인 — 잔존 데이터가 있을 때의 처리 방식.
        # 기본은 ask(대화창). 화면이 없는 환경에서는 --precheck-warn 을 줘야 한다.
        --no-precheck)     TOGGLE_VARS+=(--variable CDS_PRECHECK:False) ;;
        --precheck-warn)   TOGGLE_VARS+=(--variable CDS_PRECHECK_MODE:warn) ;;
        --precheck-fail)   TOGGLE_VARS+=(--variable CDS_PRECHECK_MODE:fail) ;;
        --precheck-ask)    TOGGLE_VARS+=(--variable CDS_PRECHECK_MODE:ask) ;;
        # 세션 사전 적재 — T_SMF_SESSION_INFO 에 5G 세션 1건을 넣는다(멱등).
        # 이 슈트에서 유일하게 PDB 에 쓰는 자리다. 없으면 PG 가 알림 상대를 못 찾는다.
        --no-session)   TOGGLE_VARS+=(--variable CDS_SESSION_CREATE:False) ;;
        --session)      TOGGLE_VARS+=(--variable CDS_SESSION_CREATE:True) ;;
        # PCF SBI 를 켜 두되 PG 가 붙기를 기다리지 않는다(Listen 만 하고 바로 시작).
        --no-sbi-wait|--no-http-wait|--no-noti-wait)
                        TOGGLE_VARS+=(--variable CDS_NOTI_WAIT_CONNECT:False) ;;
        --sbi-wait|--http-wait|--noti-wait)
                        TOGGLE_VARS+=(--variable CDS_NOTI_WAIT_CONNECT:True) ;;
        *)              EXTRA_ARGS+=("${arg}") ;;
    esac
done

TS=$(date +%Y%m%d_%H%M%S)
OUT="results/${TS}"
mkdir -p "${OUT}"

# 2번째 인자: 환경명(dev|stg|prd|local) 또는 IP
VAR_OVERRIDE=()
ENV_NAME="dev"
if [ -n "${EXTRA_ARGS[0]}" ]; then
    case "${EXTRA_ARGS[0]}" in
        dev|stg|prd|local)
            ENV_NAME="${EXTRA_ARGS[0]}"
            ENV_FILE="config/env/${ENV_NAME}.py"
            if [ ! -f "${ENV_FILE}" ]; then
                echo "★ 환경 파일이 없습니다: ${ENV_FILE}" >&2
                exit 2
            fi
            VAR_OVERRIDE=("--variablefile" "${ENV_FILE}")
            EXTRA_ARGS=("${EXTRA_ARGS[@]:1}")
            ;;
        [0-9]*)
            # 각 노드 HOST 는 ${PG_HOST} 를 상속하므로 하나만 넘기면 된다
            ENV_NAME="host=${EXTRA_ARGS[0]}"
            VAR_OVERRIDE=("--variable" "PG_HOST:${EXTRA_ARGS[0]}")
            EXTRA_ARGS=("${EXTRA_ARGS[@]:1}")
            ;;
    esac
fi

echo "══════════════════════════════════════"
echo " TARGET : ${TARGET}"
echo " ENV    : ${ENV_NAME}"
echo " OUTPUT : ${OUT}"
echo " LOG_MSG: ${PG_LOG_MSG:-0}"
if [ ${#TOGGLE_VARS[@]} -gt 0 ]; then
    echo " TOGGLE : ${TOGGLE_VARS[*]}"
fi
echo "══════════════════════════════════════"

# ── 골디락스 ODBC 드라이버 탐색 경로 ──────────────────────────────
# CDS 슈트의 PDB 조회가 여기 걸린다. 드라이버 본체는 접속 문자열의 DRIVER= 절대경로로
# 로드되지만, **문자셋 변환 라이브러리(libgoldilockscvtUHC_64.so)는 런타임에 이름만으로
# dlopen** 되므로 탐색 경로에 없으면 못 연다. 그러면 접속은 성립하는데 SELECT 가 전부
# 실패한다 — 증상은 ('HY000', 'The driver did not supply an error!') 다.
#
# ★ Python 안에서 os.environ 으로 넣어 봐야 소용없다. glibc 가 프로세스 시작 시점에
#   LD_LIBRARY_PATH 를 읽어 두므로 **robot 을 띄우기 전에** 설정돼 있어야 한다.
#   그래서 여기다.
#
# 이미 설정돼 있으면 건드리지 않는다. 경로가 다르면 GOLDILOCKS_HOME 을 먼저 export 할 것.
: "${GOLDILOCKS_HOME:=/PG/goldilocks_home}"
if [ -d "${GOLDILOCKS_HOME}/lib" ]; then
    export GOLDILOCKS_HOME
    case ":${LD_LIBRARY_PATH}:" in
        *":${GOLDILOCKS_HOME}/lib:"*) ;;
        *) export LD_LIBRARY_PATH="${GOLDILOCKS_HOME}/lib:${LD_LIBRARY_PATH}" ;;
    esac
fi

BASE_CMD=(python3 -m robot
    --outputdir "${OUT}"
    --loglevel DEBUG
    "${VAR_OVERRIDE[@]}"
    "${TOGGLE_VARS[@]}"
    "${EXTRA_ARGS[@]}"
)

case "${TARGET}" in
    nag)        "${BASE_CMD[@]}" tests/nag/ ;;
    pcf)        "${BASE_CMD[@]}" tests/pcf/ ;;
    lrs)        "${BASE_CMD[@]}" tests/lrs/ ;;
    upm)        "${BASE_CMD[@]}" tests/upm/ ;;
    nwdaf)      "${BASE_CMD[@]}" tests/nwdaf/ ;;
    cds)        "${BASE_CMD[@]}" tests/cds/ ;;
    all)        "${BASE_CMD[@]}" tests/ ;;
    smoke)      "${BASE_CMD[@]}" --include smoke tests/ ;;
    negative)   "${BASE_CMD[@]}" --include negative tests/ ;;
    validation) "${BASE_CMD[@]}" --include validation tests/ ;;
    lte)        "${BASE_CMD[@]}" --include lte tests/ ;;
    5g)         "${BASE_CMD[@]}" --include 5g tests/ ;;
    *)          "${BASE_CMD[@]}" --include "${TARGET}" tests/ ;;
esac

RC=$?
echo ""
echo "▶ 리포트: ${OUT}/report.html"
echo "▶ 로그:   ${OUT}/log.html"
exit ${RC}
