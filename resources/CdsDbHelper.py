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

# ── DB 종류별 ODBC 키워드 (DSN-less 전용) ─────────────────────────
# 같은 의미의 항목이 DB 마다 이름이 다르다. **DSN-less 방식에서만** 쓴다 —
# DSN 방식은 아래 _DSN_UID/_DSN_PWD(표준 ODBC 키)를 쓴다.
#
# goldilocks 값은 실환경 odbc.ini 실측이다 (2026-08-06, PG dev):
#   Driver=/PG/goldilocks_home/lib/libgoldilockscs-ul64.so
#   UID=... PWD=... HOST=... PORT=... CHARSET=UHC
#   → 호스트 키가 `SERVER` 가 아니라 **`HOST`** 다.
# altibase 값은 아직 실환경으로 확인되지 않았다.
#
# `user_keys` 가 튜플인 것은 계정을 두 개 키로 동시에 넘겨야 하는 드라이버가
# 있어서다(PG 참조 샘플이 그렇게 한다). 지금은 둘 다 하나면 충분하다.
# `extra` 는 기본으로 붙일 부가 키워드다. 비워 뒀다 — 실환경에서 붙여야 하는 값이
# 확인되면 여기 넣거나 ${CDS_DB_EXTRA} 로 준다.
_KIND_SPEC = {
    'goldilocks': {
        'host_key': 'HOST', 'db_key': 'DATABASE',
        'user_keys': ('UID',), 'pw_key': 'PWD', 'extra': (),
    },
    'altibase': {
        'host_key': 'Server', 'db_key': 'DBName',
        'user_keys': ('UID',), 'pw_key': 'PWD', 'extra': (),
    },
}

# DSN 방식에서 계정을 덮어쓸 때 쓰는 **표준 ODBC 키**. DB 종류와 무관하다
# (미지정 시 DSN 에 설정된 계정이 그대로 쓰인다).
_DSN_UID = 'UID'
_DSN_PWD = 'PWD'

# 포트는 DB 종류와 무관하게 `PORT` 다 (PG 참조 샘플 확인).
_PORT_KEY = 'PORT'

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
    갖고 있으므로 여기서는 계정만 덧붙인다. 계정 키는 DB 종류와 무관하게
    **표준 ODBC 키(UID/PWD)** 다.

    **빈 값은 아예 붙이지 않는다** — DSN 이 이미 갖고 있는 값을 빈 값으로 덮어쓰면
    안 되기 때문이다(odbc.ini 에 UID/PWD 가 있으면 계정도 생략 가능).
    """
    spec = _KIND_SPEC[_normalize_kind(kind)]      # kind 유효성만 검사한다
    password = _resolve_password()
    return _join([
        'DSN=%s' % dsn,
        ('%s=%s' % (_DSN_UID, user)) if user else '',
        ('%s=%s' % (_DSN_PWD, password)) if password else '',
        ('%s=%s' % (spec['db_key'], database)) if database else '',
        extra,
    ])


def build_dsnless_conn_str(kind='goldilocks', driver='', host='', port='',
                           database='', user='', extra=''):
    """DSN 없이 DRIVER/HOST/PORT 로 직접 조립한다.

    ※ 이 경로는 GOLDILOCKS 에서 실패한 전례가 있다 — docs/nodes/CDS.md 참조.
       접속이 안 되면 DSN 방식이나 ${CDS_DB_CONNSTR} 로 우회할 것.
    """
    spec = _KIND_SPEC[_normalize_kind(kind)]
    password = _resolve_password()
    parts = [
        'DRIVER=%s' % _fmt_driver(driver),
        '%s=%s' % (spec['host_key'], host),
        '%s=%s' % (_PORT_KEY, port),
    ]
    if database:
        parts.append('%s=%s' % (spec['db_key'], database))
    if user:
        parts += ['%s=%s' % (uk, user) for uk in spec['user_keys']]
    if password:
        parts.append('%s=%s' % (spec['pw_key'], password))
    parts += [extra] if extra else list(spec['extra'])
    return _join(parts)


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
               database='', user='', conn_str='', dsn='', extra='',
               encoding='utf-8', timeout=10):
    """PDB 에 접속해 connection 객체를 반환한다.

    접속 문자열은 conn_str(완성) → dsn(DSN 방식) → DRIVER/HOST/PORT(DSN-less)
    순으로 결정된다.

    encoding 은 pyodbc 의 문자 인코딩을 고정한다(기본 `utf-8`).
    **골디락스/알티베이스 ODBC 드라이버는 유니코드(SQL_WVARCHAR) 바인딩을 지원하지
    않는 경우가 있어**, 문자열을 ANSI(SQL_CHAR)로 처리하도록 강제해야 한다
    (PG 참조 샘플이 두 DB 모두에 무조건 적용한다). 이걸 안 하면 조회가 진단 없이
    죽는다 — `('HY000', 'The driver did not supply an error!')`.
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
        # autocommit=True 는 의도적이다 — PG 참조 샘플은 False(트랜잭션 직접 제어)지만
        # 이 헬퍼는 **조회만** 하고, `Verify Subscriber Provisioned In PDB` 가 30초간
        # 재조회한다. autocommit=False 면 첫 조회가 연 트랜잭션의 스냅샷에 갇혀
        # SDM 이 나중에 반영한 행을 영영 못 볼 수 있다.
        conn = pyodbc.connect(cs, timeout=int(timeout), autocommit=True)
    except Exception as exc:
        raise CdsDbError(
            'PDB 접속 실패 — %s / 접속문자열=%s' % (exc, _mask(cs))
        )
    if encoding:
        try:
            conn.setencoding(encoding=encoding)
            conn.setdecoding(pyodbc.SQL_CHAR, encoding=encoding)
            conn.setdecoding(pyodbc.SQL_WCHAR, encoding=encoding)
        except Exception as exc:
            db_close(conn)
            raise CdsDbError(
                "인코딩 설정 실패 (encoding='%s') — %s. "
                "${CDS_DB_ENCODING} 을 확인하십시오." % (encoding, exc)
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
                    database='', user='', conn_str='', dsn='', extra='',
                    **_ignored):
    """로그용 마스킹된 접속 문자열. 비밀번호가 log.html 로 새지 않는다.

    `db_connect` 와 **같은 인자 묶음을 그대로 받도록** `**_ignored` 를 둔다
    (호출부가 두 곳에서 인자 목록을 따로 관리하면 어긋난다).
    문자열 조립에 안 쓰이는 encoding/timeout 등은 여기서 무시된다.
    """
    cs = conn_str or build_conn_str(kind, driver, host, port, database,
                                    user, dsn, extra)
    return _mask(cs)


# ── 조회 ──────────────────────────────────────────────────────────
#
# [바인딩 방식 — `?` 가 안 먹는 드라이버가 있다]
#   pyodbc 는 `?` 를 바인딩할 때 SQLDescribeParam 으로 파라미터 타입을 묻는데,
#   이를 구현하지 않은 드라이버에서는 진단 레코드 없이 실패한다:
#     ('HY000', 'The driver did not supply an error!')
#   실제로 골디락스에서 이 증상이 나왔다(2026-08-06).
#
#   그래서 세 가지 모드를 둔다 (${CDS_DB_BIND}).
#     auto    : `?` 바인딩을 먼저 시도하고, 실패하면 리터럴로 재시도 (기본값)
#     param   : `?` 바인딩만. setinputsizes 로 SQLDescribeParam 호출을 피한다
#     literal : 값을 SQL 문자열에 직접 넣는다
#
#   리터럴이 안전한 이유는 **넣는 값이 도구가 정한 상수뿐**이기 때문이다
#   (MDN, SVC_ID). 외부 입력을 넣는 자리가 아니다. 그래도 따옴표는 이스케이프한다.

_BIND_MODES = ('auto', 'param', 'literal')


def _quote(value):
    """SQL 리터럴로 만든다. 숫자는 그대로, 그 외는 작은따옴표 + 이스케이프."""
    if isinstance(value, bool):
        raise CdsDbError('불리언은 SQL 리터럴로 넣지 않는다: %r' % (value,))
    if isinstance(value, (int, float)):
        return str(value)
    return "'%s'" % str(value).replace("'", "''")


def _inline_params(sql, params):
    """`?` 자리에 리터럴을 채워 넣는다. 개수가 안 맞으면 실패."""
    chunks = sql.split('?')
    if len(chunks) - 1 != len(params):
        raise CdsDbError(
            '자리표시자(?) 개수와 인자 개수가 다릅니다: ?=%d, 인자=%d, sql=%s'
            % (len(chunks) - 1, len(params), sql)
        )
    out = chunks[0]
    for value, chunk in zip(params, chunks[1:]):
        out += _quote(value) + chunk
    return out


def _try_setinputsizes(cur, count):
    """파라미터 타입을 못 박아 SQLDescribeParam 호출을 피한다 (best-effort).

    pyodbc 전용 기능이라 **실패해도 무시한다** — 없으면 그냥 드라이버에 맡긴다.
    여기서 예외를 올리면 바인딩 자체가 안 되는 것처럼 오진된다.
    """
    try:
        import pyodbc
        cur.setinputsizes([(pyodbc.SQL_VARCHAR, 64, 0)] * count)
    except Exception:
        pass


def _fetch_count(cur, sql, params, use_param):
    """한 번 실행하고 COUNT 값을 꺼낸다."""
    if not params:
        cur.execute(sql)
    elif use_param:
        _try_setinputsizes(cur, len(params))
        cur.execute(sql, tuple(params))
    else:
        cur.execute(_inline_params(sql, params))
    row = cur.fetchone()
    if row is None or len(row) != 1:
        raise CdsDbError(
            'COUNT 조회 결과가 1행 1열이 아닙니다: sql=%s params=%r row=%r'
            % (sql, params, row)
        )
    return int(row[0])


def db_count(conn, sql, *params, bind='auto'):
    """`SELECT COUNT(*) ...` 을 실행해 정수 하나를 반환한다.

    params 는 SQL 의 `?` 자리표시자에 순서대로 들어간다. 들어가는 방식은
    bind 로 고른다 ('auto' | 'param' | 'literal' — 위 주석 참조).
    결과가 1행 1열이 아니면 실패로 본다 — COUNT 조회 전용이다.
    """
    if conn is None:
        raise CdsDbError('PDB 에 접속돼 있지 않습니다 (connection=None).')
    mode = str(bind).strip().lower() or 'auto'
    if mode not in _BIND_MODES:
        raise CdsDbError(
            "알 수 없는 바인딩 방식입니다: '%s' (사용 가능: %s). "
            "${CDS_DB_BIND} 를 확인하십시오." % (bind, ', '.join(_BIND_MODES))
        )

    attempts = {'auto': (True, False), 'param': (True,), 'literal': (False,)}[mode]
    errors = []
    for use_param in attempts:
        cur = conn.cursor()
        try:
            return _fetch_count(cur, sql, params, use_param)
        except CdsDbError:
            raise
        except Exception as exc:
            errors.append('%s 바인딩: %s' % ('?' if use_param else '리터럴', exc))
        finally:
            cur.close()

    hint = ''
    if mode == 'auto':
        hint = (' — ? 바인딩과 리터럴이 모두 실패했습니다. 드라이버가 이 테이블을'
                ' 못 보거나 계정 권한이 없을 수 있습니다.')
    elif mode == 'param':
        hint = (" — 드라이버가 ? 바인딩을 지원하지 않을 수 있습니다."
                " ${CDS_DB_BIND} 를 literal 로 바꿔 보십시오.")
    raise CdsDbError(
        'PDB 조회 실패%s / sql=%s params=%r / %s'
        % (hint, sql, params, ' | '.join(errors))
    )
