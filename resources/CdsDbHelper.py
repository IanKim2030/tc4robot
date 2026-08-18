"""
CdsDbHelper.py  —  PG PDB 조회 헬퍼 (ODBC / pyodbc)
===================================================

CDS 전문의 **DB 반영 여부**를 판정하기 위한 조회 전용 헬퍼다.

  대상 DB : 골디락스(Goldilocks) 또는 알티베이스(Altibase) — 환경에 따라 다르다
  드라이버 : ODBC (pyodbc). 두 DB 모두 ODBC 드라이버를 제공한다
  용도    : `SELECT COUNT(*)` 계열 조회가 대부분이다. 쓰기는 **세션 사전 적재
             (`db_execute` / `session_insert_sql`) 하나뿐**이며 그것만 commit 한다
  트랜잭션 : autocommit **끔**(기본). 조회 직전마다 rollback 으로 트랜잭션을 끊어
             재조회가 새 스냅샷을 보게 한다 (`db_end_transaction`)

`CommandResult`(0017)는 Body 내용과 무관하게 `SC` 를 돌려주므로, 전문이 실제로
가입자 테이블에 반영됐는지는 PDB 를 직접 보지 않으면 판정할 수 없다
(docs/nodes/CDS.md "도구 관점에서의 함의", docs/callflow/CDS_X1.md).

[pyodbc 는 지연 임포트한다]
  `import pyodbc` 를 모듈 최상단에 두면 pyodbc 가 없는 환경에서 CDS 슈트 자체가
  로드되지 않는다(전문 송수신 TC 까지 못 돌게 된다). 그래서 `db_connect` 안에서
  임포트하고, 실패 시 설치 방법을 담은 한글 메시지를 낸다.

[접속 방식은 완성 문자열 하나뿐이다]
  `${CDS_DB_CONNSTR}` 에 완성된 ODBC 접속 문자열을 통째로 준다. **이 헬퍼는 접속
  문자열을 조립하지 않는다** — 받은 값을 그대로 pyodbc 에 넘긴다.

    CDS_DB_CONNSTR = 'DSN=GOLD_GLOBAL;UID=pdb;PWD=pdb1234'

  KIND/DSN/DRIVER/HOST/PORT 로 조립하던 경로는 제거했다. 골디락스에서 DSN-less
  조립이 `IM012 DRIVER keyword syntax error` 로 거부됐고, 실환경 odbc.ini 에
  `ALTERNATE_SERVERS`·`LOCATOR_DSN` 처럼 문자열로 옮기기 번거로운 항목이 있어
  결국 DSN 등록 + 완성 문자열로 수렴했다 (docs/nodes/CDS.md).

[비밀번호 — 접속 문자열 안에 들어간다]
  그래서 접속 문자열은 **Robot 키워드 인자로 받지 않는다.** 인자로 넘기면 log.html
  의 Arguments 에 평문으로 남는다. 아래 순서로 Python 이 직접 읽는다.
    1) 환경변수 `PG_CDS_DB_CONNSTR`   ← 파일에 안 남기려면 이쪽
    2) Robot 변수 `${CDS_DB_CONNSTR}`
  로그에 남기는 접속 문자열은 항상 마스킹한다(`_mask` → `PWD=****`).
  ※ 2) 를 쓰면 **파일에 평문으로 남는다** — 실환경 값은 커밋되는
     cds_variables.robot 이 아니라 config/env/<env>.py 에서 오버라이드할 것.
"""

import os
import re

# 접속 문자열을 읽는 곳. 환경변수가 Robot 변수보다 우선한다 —
# 비밀번호가 들어 있어 파일에 안 남기고 싶을 때 쓰는 통로다.
_CONN_STR_ENV = 'PG_CDS_DB_CONNSTR'
_CONN_STR_VAR = '${CDS_DB_CONNSTR}'


class CdsDbError(Exception):
    """PDB 접속/조회 실패."""


# ── 내부 ──────────────────────────────────────────────────────────

def _mask(conn_str):
    """접속 문자열에서 비밀번호를 가린다 (로그용)."""
    return re.sub(r'(?i)\b(PWD|Password)\s*=\s*[^;]*', r'\1=****', conn_str)


def _as_bool(value):
    """Robot 이 넘긴 값을 불리언으로. 문자열 'False'/'0'/'off'/'no' 는 거짓이다.

    Robot 변수는 `${FALSE}` 로 주면 불리언이지만 `--variable` 이나 평문으로 오면
    문자열이다 — `bool('False')` 가 True 라 그대로 쓰면 조용히 반대로 동작한다.
    """
    if isinstance(value, str):
        return value.strip().lower() not in ('', 'false', '0', 'off', 'no', 'none')
    return bool(value)


def _read_conn_str(conn_str=''):
    """접속 문자열을 인자 → 환경변수 → Robot 변수 순으로 읽는다 (없으면 빈 문자열).

    **평소에는 인자로 넘기지 않는다.** 접속 문자열에는 비밀번호가 들어 있는데,
    Robot 키워드 인자로 넘기면 log.html 의 Arguments 에 평문으로 남기 때문이다
    (예전에 비밀번호만 따로 읽던 이유와 같다). 인자는 Robot 밖에서 이 모듈을
    직접 쓸 때를 위해 남겨 뒀다.
    """
    if conn_str:
        return str(conn_str).strip()
    env = os.environ.get(_CONN_STR_ENV)
    if env:
        return env.strip()
    try:
        from robot.libraries.BuiltIn import BuiltIn
        return (BuiltIn().get_variable_value(_CONN_STR_VAR) or '').strip()
    except Exception:          # Robot 밖에서 직접 호출된 경우
        return ''


def _require_conn_str(conn_str=''):
    """접속 문자열을 읽고, 비어 있으면 어디에 채워야 하는지까지 알린다."""
    cs = _read_conn_str(conn_str)
    if not cs:
        raise CdsDbError(
            'PDB 접속 문자열이 비어 있습니다 — DB 반영을 판정할 수 없습니다.\n'
            "  ${CDS_DB_CONNSTR} 예: 'DSN=GOLD_GLOBAL;UID=pdb;PWD=...'\n"
            '  config/env/<env>.py 에 넣거나 --variable 로 지정하십시오.\n'
            '  비밀번호를 파일에 남기지 않으려면 환경변수 %s 를 쓰십시오.\n'
            '  (DSN 은 odbc.ini / ODBC 데이터 원본 관리자에 미리 등록돼 있어야 합니다.)'
            % _CONN_STR_ENV
        )
    return cs


# ── 접속 / 해제 ───────────────────────────────────────────────────

def db_connect(conn_str='', timeout=10, autocommit=False):
    """PDB 에 접속해 connection 객체를 반환한다.

    접속 문자열은 **완성된 ODBC 문자열**이며 조립하지 않고 그대로 넘긴다.
    conn_str 을 비워 두면 `PG_CDS_DB_CONNSTR` → `${CDS_DB_CONNSTR}` 순으로
    직접 읽는다 — 비밀번호가 log.html 인자에 남지 않게 하기 위함이다.

    [문자 인코딩은 접속 문자열에서 지정한다]
      예전에는 `conn.setencoding` / `setdecoding` 으로 pyodbc 쪽을 ANSI 로 못 박았다.
      지금은 그 코드가 없다 — **드라이버 쪽 `CHARSET=` 으로 지정한다.**
        CDS_DB_CONNSTR = 'DSN=GOLD_GLOBAL;UID=pdb;PWD=...;CHARSET=UHC'
      ※ 둘은 같은 것이 아니다. `CHARSET=` 은 드라이버가 서버와 주고받는 문자셋이고,
        `setencoding` 은 pyodbc 가 Python str 을 어느 SQL 타입으로 바인딩하는지다.
        `('HY000', 'The driver did not supply an error!')` 가 다시 나오면 이 차이를
        의심할 것 — 되살리는 법은 docs/nodes/CDS.md 의 해당 함정 절에 적어 뒀다.

    autocommit 은 기본 **False**(끔)다 — PG 참조 샘플과 같다.
    ★ 끈 상태에서는 SELECT 도 트랜잭션을 연다. 그대로 두면 `Verify Subscriber
      Provisioned In PDB` 의 30초 재조회가 **첫 조회가 연 트랜잭션의 스냅샷에 갇혀**
      SDM 이 나중에 반영한 행을 영영 못 본다. 그래서 `db_count` 가 조회 직전마다
      `db_end_transaction`(rollback)으로 트랜잭션을 끊어 스냅샷을 새로 뜬다.
      **autocommit 을 끄면서 이 rollback 을 빼면 재조회가 통째로 무력화된다.**
    """
    try:
        import pyodbc
    except ImportError as exc:
        raise CdsDbError(
            'pyodbc 가 설치돼 있지 않아 PDB 를 조회할 수 없습니다. '
            '`pip install pyodbc` 후 다시 실행하십시오. (원인: %s)' % exc
        )

    cs = _require_conn_str(conn_str)
    try:
        # 기본은 autocommit=False (PG 참조 샘플과 동일). 스냅샷 문제는 조회 직전
        # rollback 으로 푼다 — 위 docstring 참조.
        conn = pyodbc.connect(cs, timeout=int(timeout),
                              autocommit=_as_bool(autocommit))
    except Exception as exc:
        raise CdsDbError(
            'PDB 접속 실패 — %s / 접속문자열=%s' % (exc, _mask(cs))
        )
    conn.timeout = int(timeout)          # 쿼리 타임아웃
    return conn


def db_end_transaction(conn):
    """열려 있는 트랜잭션을 rollback 으로 끊는다 (autocommit=False 전용).

    **조회 전용 헬퍼라 rollback 으로 잃을 것이 없다** — INSERT/UPDATE/DELETE 를
    하지 않으므로 되돌릴 변경 자체가 없다. 목적은 오직 하나, 다음 SELECT 가
    **새 스냅샷**을 보게 하는 것이다. autocommit 이 켜져 있으면 아무것도 하지 않는다.

    best-effort 다 — 실패해도 예외를 올리지 않는다. 여기서 터지면 정작 조회 실패
    원인이 가려진다.
    """
    if conn is None or getattr(conn, 'autocommit', True):
        return
    try:
        conn.rollback()
    except Exception:
        pass


def db_close(conn):
    """connection 종료. 이미 닫혔거나 None 이면 조용히 넘어간다."""
    if conn is None:
        return
    db_end_transaction(conn)
    try:
        conn.close()
    except Exception:
        pass


def masked_conn_str(conn_str='', **_ignored):
    """로그용 마스킹된 접속 문자열(`PWD=****`). 비밀번호가 log.html 로 새지 않는다.

    `db_connect` 와 **같은 곳에서 같은 순서로** 읽는다(`_read_conn_str`) — 로그에
    찍힌 문자열과 실제로 접속에 쓰인 문자열이 어긋나면 진단이 무의미해진다.
    `db_connect` 와 인자 묶음을 맞추려고 `**_ignored` 를 둔다(encoding/timeout 등).
    빈 값이어도 실패하지 않는다 — 로그용이라 정작 접속 실패 진단을 가리면 안 된다.
    """
    return _mask(_read_conn_str(conn_str)) or '(비어 있음)'


# ── 조회 ──────────────────────────────────────────────────────────
#
# [바인딩은 `?` 파라미터로 고정이다]
#   pyodbc 는 `?` 를 바인딩할 때 SQLDescribeParam 으로 파라미터 타입을 묻는데,
#   이를 구현하지 않은 드라이버에서는 진단 레코드 없이 실패한다:
#     ('HY000', 'The driver did not supply an error!')
#   실제로 골디락스에서 이 증상이 나왔다(2026-08-06).
#
#   그 대응이 `_try_setinputsizes` 다 — 파라미터 타입을 미리 못 박아 드라이버에
#   SQLDescribeParam 을 묻지 않게 한다.
#
#   예전에는 값을 SQL 문자열에 직접 넣는 리터럴 모드와 `auto` 폴백이 있었고
#   ${CDS_DB_BIND} 로 골랐다. **지금은 `?` 바인딩 하나뿐이다** — 모드 선택과 리터럴
#   경로를 함께 제거했다. 조회가 위 HY000 으로 죽으면 폴백 없이 그대로 실패한다.

def _try_setinputsizes(cur, count, size=64):
    """파라미터 타입을 못 박아 SQLDescribeParam 호출을 피한다 (best-effort).

    pyodbc 전용 기능이라 **실패해도 무시한다** — 없으면 그냥 드라이버에 맡긴다.
    여기서 예외를 올리면 바인딩 자체가 안 되는 것처럼 오진된다.

    ★ size 는 **넉넉해야 한다.** 조회 파라미터(MDN/SVC_ID 등)는 64로 충분하지만
      세션 적재의 RES_URI 는 113자라 64로 못 박으면 잘리거나 거부된다.
      그래서 db_execute 는 512를 준다.
    """
    try:
        import pyodbc
        cur.setinputsizes([(pyodbc.SQL_VARCHAR, int(size), 0)] * count)
    except Exception:
        pass


def _fetch_count(cur, sql, params):
    """한 번 실행하고 COUNT 값을 꺼낸다. 값은 항상 `?` 로 바인딩한다."""
    if params:
        _try_setinputsizes(cur, len(params))
        cur.execute(sql, tuple(params))
    else:
        cur.execute(sql)
    row = cur.fetchone()
    if row is None or len(row) != 1:
        raise CdsDbError(
            'COUNT 조회 결과가 1행 1열이 아닙니다: sql=%s params=%r row=%r'
            % (sql, params, row)
        )
    return int(row[0])


def _fetch_group_counts(cur, sql, params):
    """`SELECT <key>, COUNT(*) ... GROUP BY <key>` 을 dict 로 만든다."""
    if params:
        _try_setinputsizes(cur, len(params))
        cur.execute(sql, tuple(params))
    else:
        cur.execute(sql)
    out = {}
    for row in cur.fetchall():
        if len(row) != 2:
            raise CdsDbError(
                'GROUP BY 조회 결과가 2열이 아닙니다: sql=%s params=%r row=%r'
                % (sql, params, row)
            )
        key = '' if row[0] is None else str(row[0]).strip()
        if key in out:
            raise CdsDbError(
                '같은 키가 두 번 나왔습니다 — GROUP BY 가 빠졌을 수 있습니다: '
                'key=%r sql=%s' % (key, sql)
            )
        out[key] = int(row[1])
    return out


def _query(conn, sql, params, fetch, what):
    """조회 공통 — 트랜잭션 끊기 / 커서 관리 / 실패 메시지를 한곳에 모은다."""
    if conn is None:
        raise CdsDbError('PDB 에 접속돼 있지 않습니다 (connection=None).')
    db_end_transaction(conn)
    cur = conn.cursor()
    try:
        return fetch(cur, sql, params)
    except CdsDbError:
        raise
    except Exception as exc:
        raise CdsDbError(
            'PDB %s 조회 실패 — %s / sql=%s params=%r\n'
            "  ★ ('HY000', 'The driver did not supply an error!') 처럼 진단이 없으면\n"
            '    **접속 문자열에서 CHARSET= 를 빼고 한 번 돌려 보십시오.** 골디락스는\n'
            '    CHARSET 이 있으면 진짜 오류 메시지를 삼킵니다 — 빼면 그대로 나옵니다.\n'
            '    (2026-08-18 확인. 이 함정 때문에 원인 없는 HY000 으로 두 번 헤맸습니다)\n'
            '  자주 나오는 원인 세 가지:\n'
            '    1) 문자셋 변환 라이브러리(libgoldilockscvt<CHARSET>_64.so)를 못 연다\n'
            '       → LD_LIBRARY_PATH 에 $GOLDILOCKS_HOME/lib 이 없다. run_tests.sh 가\n'
            '         넣어 주지만, robot 을 직접 부르면 셸에서 먼저 export 해야 합니다.\n'
            '         이 경우 **접속은 성공하고 SELECT 만 전부 실패**합니다.\n'
            '    2) 테이블·컬럼이 안 보이거나 계정 권한이 없다\n'
            '    3) 예약어와 겹치는 컬럼명(LIMIT 등)을 큰따옴표로 안 감쌌다'
            % (what, exc, sql, params)
        )
    finally:
        cur.close()


def db_count(conn, sql, *params):
    """`SELECT COUNT(*) ...` 을 실행해 정수 하나를 반환한다.

    params 는 SQL 의 `?` 자리표시자에 순서대로 **파라미터 바인딩**된다 (고정이다 —
    리터럴 모드와 ${CDS_DB_BIND} 는 제거됐다. 위 주석 참조).
    결과가 1행 1열이 아니면 실패로 본다 — COUNT 조회 전용이다.

    autocommit=False 인 connection 이면 **조회 직전에 트랜잭션을 끊는다**
    (`db_end_transaction`). 안 그러면 재조회가 첫 조회의 스냅샷에 갇힌다.
    """
    return _query(conn, sql, params, _fetch_count, 'COUNT')


def db_group_counts(conn, sql, *params):
    """`SELECT <key>, COUNT(*) ... GROUP BY <key>` 을 `{키: 개수}` dict 로 반환한다.

    C1/G1/D3 처럼 **업무 수행 전후의 SVC_ID 별 행 수가 같아야** 하는 판정에 쓴다.
    행이 하나도 없으면 빈 dict 다 — 그것도 유효한 결과이며 실패가 아니다.

    키는 문자열로 정규화한다(공백 제거) — 고정길이 CHAR 컬럼이면 드라이버가 오른쪽을
    공백으로 채워 돌려주는 경우가 있어, 그대로 두면 전후 비교가 어긋난다.
    """
    return _query(conn, sql, params, _fetch_group_counts, 'GROUP BY')


# ── 세션 생성 (TC 수행 전 사전 적재) ───────────────────────────────
#
# CDS 전문을 보내기 전에 대상 가입자의 5G 세션이 PDB 에 있어야 한다. PG.SNOTI 는
# T_SMF_SESSION_INFO 를 보고 알림 상대를 정하므로, 세션이 없으면 전문이 정상
# 처리돼도 PCF 로 아무것도 나가지 않는다.
#
# ★ 이 슈트에서 **유일하게 PDB 에 쓰는 경로**다. 나머지는 전부 SELECT 다.
#   autocommit 이 꺼져 있고 조회 키워드가 조회 직전마다 rollback 하므로
#   (db_end_transaction), commit 하지 않으면 **다음 조회가 방금 넣은 행을 지운다.**
#   그래서 db_execute 가 commit 까지 한다.
#
# SQL 은 Robot 변수가 아니라 여기 둔다 — IN_HTTP_PAYLOAD 의 JSON 이 1.5KB 짜리
# 한 덩어리라 .robot 의 `...` 연속 줄로 옮기면 이어 붙일 때 공백이 끼어든다.
# **바뀌는 값은 전부 ? 로 빼 놨다** — 값은 cds_variables.robot 이 쥔다.

_SESSION_IN_PAYLOAD = (
    '{"smfId":"550e8400-e29b-41d4-a716-446655440012","servNfId":{"servNfInstId":'
    '"344ab7f0-0a8c-46f5-9525-d74415ff564c","guami":{"plmnId":{"mcc":"450","mnc":'
    '"05"},"amfId":"800042"}},"qosFlowUsage":"GENERAL","pduSessionId":2,"dnn":'
    '"5g.sktelecom.com","sliceInfo":{"sst":200,"sd":"000001"},"pduSessionType":'
    '"IPV4","accessType":"3GPP_ACCESS","ratType":"NR","servingNetwork":{"mcc":'
    '"450","mnc":"05"},"userLocationInfo":{"nrLocation":{"tai":{"plmnId":{"mcc":'
    '"450","mnc":"05"},"tac":"000004"},"ncgi":{"plmnId":{"mcc":"450","mnc":"05"},'
    '"nrCellId":"0012c039e"},"ageOfLocationInformation":0,"ueLocationTimestamp":'
    '"2023-10-16T07:08:59Z","globalGnbId":{"plmnId":{"mcc":"450","mnc":"05"},'
    '"gNbId":{"bitLength":22,"gNBValue":"0004b0"}}}}}'
)
_SESSION_OUT_PAYLOAD = (
    '{"quotaNoti":0,"pccRules":{"NoQoS_NoGBR":{"pccRuleId":"NoQoS_NoGBR"}},'
    '"zoneInfos":"0000000000"}'
)

# ? 순서 — session_insert_params() 가 이 순서로 만든다. 바꾸면 양쪽을 같이 고칠 것.
SESSION_PARAM_ORDER = (
    'sm_policy_id', 'supi', 'gpsi', 'mdn', 'ip_addr',
    'res_uri', 'noti_uri', 'udr_noti_uri',
    'sm_policy_id',          # WHERE NOT EXISTS 의 같은 값
)


def session_insert_sql(table='PDB.T_SMF_SESSION_INFO'):
    """세션 1건을 넣는 INSERT ... SELECT ... WHERE NOT EXISTS 문을 만든다.

    **멱등이다** — 같은 SM_POLICY_ID 가 이미 있으면 0행을 넣는다. 그래서 슈트를
    몇 번 돌려도 중복되지 않고, 지우고 다시 넣지도 않는다(기존 세션을 존중한다).
    """
    return (
        'INSERT INTO ' + table + ' ('
        'SM_POLICY_ID, SUPI, PDU_SESSION_ID, GPSI, MDN, '
        'IP_ADDR, DNN, S_NSSAI_SST, S_NSSAI_SD, LOC_ID, '
        'MCC_MNC, RAT_TYPE, OCS_SUBS_STATUS, IN_HTTP_HEADER, IN_HTTP_PAYLOAD, '
        'OUT_HTTP_HEADER, OUT_HTTP_PAYLOAD, RES_URI, NOTI_URI, UDR_NOTI_URI, '
        'TM_NOTI_URI, STATUS, SUBSCRIBE, AF_SUBSCRIBE, NODE_ID, '
        'PROC_ID, SMF_ID, CONN_ID, STREAM_ID, CREATE_TIME, '
        'UPDATE_TIME, DESCRIPTION) '
        'SELECT '
        "?, ?, 2, ?, ?, "
        "?, '5g.sktelecom.com', 200, '000001', '1200:926', "
        "'45005', 'NR', '1', NULL, '" + _SESSION_IN_PAYLOAD + "', "
        "NULL, '" + _SESSION_OUT_PAYLOAD + "', ?, ?, ?, "
        "NULL, '3', NULL, NULL, 'ROBOT-mp01-app01', "
        "'SMF.MGR.01', '550e8400-e29b-41d4-a716-446655440012', 0, 803831, SYSDATE, "
        'SYSDATE, \'000004\' '
        'FROM DUAL '
        'WHERE NOT EXISTS (SELECT 1 FROM ' + table + ' WHERE SM_POLICY_ID = ?)'
    )


def db_execute(conn, sql, *params):
    """INSERT/UPDATE 를 실행하고 **commit 까지** 한다. 영향 행 수를 반환한다.

    ★ commit 이 핵심이다. 이 슈트는 autocommit 을 꺼 두고 조회 직전마다
      rollback 하므로(db_end_transaction), commit 하지 않으면 넣은 행이
      **다음 조회에서 사라진다.**
    실패하면 rollback 하고 CdsDbError 를 올린다.
    """
    if conn is None:
        raise CdsDbError('PDB 에 접속돼 있지 않습니다 (connection=None).')
    cur = conn.cursor()
    try:
        if params:
            _try_setinputsizes(cur, len(params), size=512)
            cur.execute(sql, tuple(params))
        else:
            cur.execute(sql)
        affected = cur.rowcount
    except Exception as exc:
        try:
            conn.rollback()
        except Exception:
            pass
        raise CdsDbError(
            'PDB 실행 실패 — %s / params=%r\n'
            "  ★ 진단이 없는 HY000 이면 접속 문자열에서 CHARSET= 을 빼고 확인할 것"
            ' (docs/nodes/CDS.md 함정 절).\n'
            '  sql=%s' % (exc, params, sql)
        )
    finally:
        cur.close()
    if not getattr(conn, 'autocommit', False):
        conn.commit()
    return int(affected) if affected is not None and affected >= 0 else 0
