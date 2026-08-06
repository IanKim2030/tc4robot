"""
CdsDbHelper.py  —  PG PDB 조회 헬퍼 (ODBC / pyodbc)
===================================================

CDS 전문의 **DB 반영 여부**를 판정하기 위한 조회 전용 헬퍼다.

  대상 DB : 골디락스(Goldilocks) 또는 알티베이스(Altibase) — 환경에 따라 다르다
  드라이버 : ODBC (pyodbc). 두 DB 모두 ODBC 드라이버를 제공한다
  용도    : `SELECT COUNT(*)` 계열 조회만. **INSERT/UPDATE/DELETE 는 하지 않는다**

`CommandResult`(0017)는 Body 내용과 무관하게 `SC` 를 돌려주므로, 전문이 실제로
가입자 테이블에 반영됐는지는 PDB 를 직접 보지 않으면 판정할 수 없다
(docs/nodes/CDS.md "도구 관점에서의 함의", docs/callflow/CDS_X1.md).

[pyodbc 는 지연 임포트한다]
  `import pyodbc` 를 모듈 최상단에 두면 pyodbc 가 없는 환경에서 CDS 슈트 자체가
  로드되지 않는다(전문 송수신 TC 까지 못 돌게 된다). 그래서 `db_connect` 안에서
  임포트하고, 실패 시 설치 방법을 담은 한글 메시지를 낸다.

[접속 방식 3가지 — 우선순위 순]
  1) `${CDS_DB_CONNSTR}`  완성된 ODBC 문자열을 통째로 준다. 나머지 값은 전부 무시된다
  2) `${CDS_DB_DSN}`      **DSN 방식.** odbc.ini(Linux) / ODBC 데이터 원본 관리자(Windows)
                          에 등록해 둔 이름을 쓴다. 호스트·포트·DB 는 DSN 이 갖고 있으므로
                          여기서는 계정만 붙인다 → `DSN=name;UID=user;PWD=pw;`
  3) DRIVER/HOST/PORT     DSN 없이 직접 조립(DSN-less). `_KIND_SPEC` 으로 분기한다

  ※ 2)·3) 의 조립 형태는 **실환경 ODBC 드라이버로 검증되지 않았다.** 접속이 안 되면
     1) 로 우회할 것 (config/env/<env>.py 에서 오버라이드).
  ※ DSN 방식에서도 `${CDS_DB_KIND}` 는 의미가 있다 — 계정 키워드가 DB 마다 달라
     골디락스는 `UID`/`PWD`, 알티베이스는 `User`/`Password` 로 붙인다(`_KIND_SPEC`).

[비밀번호]
  `${CDS_DB_PASSWORD}` 를 Robot 키워드 인자로 넘기면 log.html 의 Arguments 에
  평문으로 남는다. 그래서 비밀번호만은 **인자로 받지 않고** 아래 순서로 직접 읽는다.
    1) 환경변수 `PG_CDS_DB_PASSWORD`
    2) Robot 변수 `${CDS_DB_PASSWORD}`
  로그에 남기는 접속 문자열은 항상 마스킹한다(`_mask`).
"""

import os
import re

# ── DB 종류별 ODBC 키워드 ─────────────────────────────────────────
# 같은 의미의 항목이 DB 마다 이름이 다르다. DSN 방식·DSN-less 방식 모두 여기서
# 이름을 가져온다(한 곳에서만 관리).
#
# goldilocks 값은 실환경 odbc.ini 실측이다 (2026-08-06, PG dev):
#   Driver=/PG/goldilocks_home/lib/libgoldilockscs-ul64.so
#   UID=... PWD=... HOST=... PORT=... CHARSET=UHC
#   → 호스트 키가 `SERVER` 가 아니라 **`HOST`** 다.
# altibase 값은 아직 실환경으로 확인되지 않았다.
_KIND_SPEC = {
    'goldilocks': {
        'host': 'HOST', 'port': 'PORT', 'database': 'DATABASE',
        'uid': 'UID', 'pwd': 'PWD', 'extra': 'CHARSET=UHC',
    },
    'altibase': {
        'host': 'Server', 'port': 'Port', 'database': 'DBName',
        'uid': 'User', 'pwd': 'Password', 'extra': 'NLS_USE=UTF8',
    },
}

_PASSWORD_ENV = 'PG_CDS_DB_PASSWORD'


class CdsDbError(Exception):
    """PDB 접속/조회 실패."""


# ── 내부 ──────────────────────────────────────────────────────────

def _mask(conn_str):
    """접속 문자열에서 비밀번호를 가린다 (로그용)."""
    return re.sub(r'(?i)\b(PWD|Password)\s*=\s*[^;]*', r'\1=****', conn_str)


def _resolve_password():
    """비밀번호를 환경변수 → Robot 변수 순으로 읽는다 (인자로 받지 않는다)."""
    pw = os.environ.get(_PASSWORD_ENV)
    if pw:
        return pw
    try:
        from robot.libraries.BuiltIn import BuiltIn
        return BuiltIn().get_variable_value('${CDS_DB_PASSWORD}') or ''
    except Exception:          # Robot 밖에서 직접 호출된 경우
        return ''


def _normalize_kind(kind):
    key = str(kind).strip().lower()
    if key not in _KIND_SPEC:
        raise CdsDbError(
            "알 수 없는 DB 종류입니다: '%s' (사용 가능: %s). "
            "${CDS_DB_KIND} 를 확인하십시오."
            % (kind, ', '.join(sorted(_KIND_SPEC)))
        )
    return key


def _fmt_driver(driver):
    """`DRIVER=` 값 표기 — 중괄호를 붙일지 말지.

    ODBC 표준은 `DRIVER={이름}` 이지만 **GOLDILOCKS 드라이버 매니저는 .so 경로에
    중괄호가 붙으면 거부한다.** 실측(2026-08-06):

        DRIVER={/PG/goldilocks_home/lib/libgoldilockscs-ul64.so};SERVER=...
        → IM012 [SUNJESOFT][ODBC][GOLDILOCKS]DRIVER keyword syntax error (19043)

    그래서 값이 **경로면 그대로**, 드라이버 **이름이면 중괄호**로 감싼다
    (이름에는 공백이 흔해 중괄호가 필요하다).
    """
    d = str(driver)
    return d if ('/' in d or '\\' in d) else '{%s}' % d


def _join(parts):
    """`k=v` 조각들을 ODBC 접속 문자열로 잇는다."""
    return ';'.join(p for p in parts if p) + ';'


def build_dsn_conn_str(dsn, kind='goldilocks', user='', database='', extra=''):
    """DSN 방식 접속 문자열 조립 — `DSN=name;UID=user;PWD=pw;`

    호스트·포트·드라이버 경로는 odbc.ini / ODBC 데이터 원본 관리자에 등록된 DSN 이
    갖고 있으므로 여기서는 계정만 덧붙인다.

    **빈 값은 아예 붙이지 않는다** — DSN 이 이미 갖고 있는 값을 빈 값으로 덮어쓰면
    안 되기 때문이다(odbc.ini 에 UID/PWD 가 있으면 계정도 생략 가능).
    """
    spec = _KIND_SPEC[_normalize_kind(kind)]
    password = _resolve_password()
    return _join([
        'DSN=%s' % dsn,
        ('%s=%s' % (spec['uid'], user)) if user else '',
        ('%s=%s' % (spec['pwd'], password)) if password else '',
        ('%s=%s' % (spec['database'], database)) if database else '',
        extra,
    ])


def build_dsnless_conn_str(kind='goldilocks', driver='', host='', port='',
                           database='', user='', extra=''):
    """DSN 없이 DRIVER/HOST/PORT 로 직접 조립한다.

    ※ 이 경로는 GOLDILOCKS 에서 실패한 전례가 있다 — docs/nodes/CDS.md 참조.
       접속이 안 되면 DSN 방식이나 ${CDS_DB_CONNSTR} 로 우회할 것.
    """
    key = _normalize_kind(kind)
    spec = _KIND_SPEC[key]
    password = _resolve_password()
    return _join([
        'DRIVER=%s' % _fmt_driver(driver),
        '%s=%s' % (spec['host'], host),
        '%s=%s' % (spec['port'], port),
        ('%s=%s' % (spec['database'], database)) if database else '',
        ('%s=%s' % (spec['uid'], user)) if user else '',
        ('%s=%s' % (spec['pwd'], password)) if password else '',
        extra if extra else spec['extra'],
    ])


def build_conn_str(kind='goldilocks', driver='', host='', port='',
                   database='', user='', dsn='', extra=''):
    """ODBC 접속 문자열 조립. 비밀번호는 여기서 직접 읽는다.

    dsn 이 있으면 DSN 방식, 없으면 DSN-less(DRIVER/HOST/PORT) 방식이다.
    kind : 'goldilocks' | 'altibase'
    """
    if dsn:
        return build_dsn_conn_str(dsn, kind=kind, user=user,
                                  database=database, extra=extra)
    return build_dsnless_conn_str(kind=kind, driver=driver, host=host, port=port,
                                  database=database, user=user, extra=extra)


# ── 접속 / 해제 ───────────────────────────────────────────────────

def db_connect(kind='goldilocks', driver='', host='', port='',
               database='', user='', conn_str='', dsn='', extra='', timeout=10):
    """PDB 에 접속해 connection 객체를 반환한다.

    접속 문자열은 conn_str(완성) → dsn(DSN 방식) → DRIVER/HOST/PORT(DSN-less)
    순으로 결정된다.
    """
    try:
        import pyodbc
    except ImportError as exc:
        raise CdsDbError(
            'pyodbc 가 설치돼 있지 않아 PDB 를 조회할 수 없습니다. '
            '`pip install pyodbc` 후 다시 실행하십시오. (원인: %s)' % exc
        )

    cs = conn_str or build_conn_str(kind, driver, host, port, database,
                                    user, dsn, extra)
    try:
        conn = pyodbc.connect(cs, timeout=int(timeout), autocommit=True)
    except Exception as exc:
        raise CdsDbError(
            'PDB 접속 실패 — %s / 접속문자열=%s' % (exc, _mask(cs))
        )
    conn.timeout = int(timeout)          # 쿼리 타임아웃
    return conn


def db_close(conn):
    """connection 종료. 이미 닫혔거나 None 이면 조용히 넘어간다."""
    if conn is None:
        return
    try:
        conn.close()
    except Exception:
        pass


def masked_conn_str(kind='goldilocks', driver='', host='', port='',
                    database='', user='', conn_str='', dsn='', extra=''):
    """로그용 마스킹된 접속 문자열. 비밀번호가 log.html 로 새지 않는다."""
    cs = conn_str or build_conn_str(kind, driver, host, port, database,
                                    user, dsn, extra)
    return _mask(cs)


# ── 조회 ──────────────────────────────────────────────────────────

def db_count(conn, sql, *params):
    """`SELECT COUNT(*) ...` 을 실행해 정수 하나를 반환한다.

    params 는 SQL 의 `?` 자리표시자에 순서대로 바인딩된다.
    결과가 1행 1열이 아니면 실패로 본다 — COUNT 조회 전용이다.
    """
    if conn is None:
        raise CdsDbError('PDB 에 접속돼 있지 않습니다 (connection=None).')
    cur = conn.cursor()
    try:
        if params:
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
    except CdsDbError:
        raise
    except Exception as exc:
        raise CdsDbError(
            'PDB 조회 실패 — %s / sql=%s params=%r' % (exc, sql, params)
        )
    finally:
        cur.close()
