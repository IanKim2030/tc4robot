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

TARGET=${1:-smoke}
EXTRA_ARGS=()

for arg in "${@:2}"; do
    if [ "${arg}" = "--log-msg" ]; then
        export PG_LOG_MSG=1
    else
        EXTRA_ARGS+=("${arg}")
    fi
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
echo "══════════════════════════════════════"

BASE_CMD=(python3 -m robot
    --outputdir "${OUT}"
    --loglevel DEBUG
    "${VAR_OVERRIDE[@]}"
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
