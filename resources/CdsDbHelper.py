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

[접속 문자열]
  DB 별 ODBC 키워드가 달라 `_CONNSTR_TEMPLATES` 로 분기한다.
  ※ 아래 템플릿은 **실환경 ODBC 드라이버로 검증되지 않았다.** 접속이 안 되면
     `${CDS_DB_CONNSTR}` 에 완성된 문자열을 통째로 넣어 우회할 것
     (config/env/<env>.py 에서 오버라이드).

[비밀번호]
  `${CDS_DB_PASSWORD}` 를 Robot 키워드 인자로 넘기면 log.html 의 Arguments 에
  평문으로 남는다. 그래서 비밀번호만은 **인자로 받지 않고** 아래 순서로 직접 읽는다.
    1) 환경변수 `PG_CDS_DB_PASSWORD`
    2) Robot 변수 `${CDS_DB_PASSWORD}`
  로그에 남기는 접속 문자열은 항상 마스킹한다(`_mask`).
"""

import os
import re

# ── DB 종류별 ODBC 접속 문자열 템플릿 ─────────────────────────────
# TODO: 실환경 ODBC 드라이버로 키워드명 확인 (Server/Port/User/Password 표기가
#       드라이버 버전마다 다르다). 어긋나면 ${CDS_DB_CONNSTR} 로 통째 오버라이드.
_CONNSTR_TEMPLATES = {
    'goldilocks': 'DRIVER={{{driver}}};SERVER={host};PORT={port};'
                  'DATABASE={database};UID={user};PWD={password};',
    'altibase':   'DRIVER={{{driver}}};Server={host};Port={port};'
                  'User={user};Password={password};NLS_USE=UTF8;',
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


def build_conn_str(kind, driver, host, port, database, user):
    """DB 종류별 ODBC 접속 문자열 조립. 비밀번호는 여기서 직접 읽는다.

    kind : 'goldilocks' | 'altibase'
    """
    key = str(kind).strip().lower()
    if key not in _CONNSTR_TEMPLATES:
        raise CdsDbError(
            "알 수 없는 DB 종류입니다: '%s' (사용 가능: %s). "
            "${CDS_DB_KIND} 를 확인하십시오."
            % (kind, ', '.join(sorted(_CONNSTR_TEMPLATES)))
        )
    return _CONNSTR_TEMPLATES[key].format(
        driver=driver, host=host, port=port,
        database=database, user=user, password=_resolve_password(),
    )


# ── 접속 / 해제 ───────────────────────────────────────────────────

def db_connect(kind='goldilocks', driver='', host='', port='',
               database='', user='', conn_str='', timeout=10):
    """PDB 에 접속해 connection 객체를 반환한다.

    conn_str 이 있으면 그대로 쓰고(비밀번호까지 포함된 완성 문자열),
    없으면 kind 별 템플릿으로 조립한다.
    """
    try:
        import pyodbc
    except ImportError as exc:
        raise CdsDbError(
            'pyodbc 가 설치돼 있지 않아 PDB 를 조회할 수 없습니다. '
            '`pip install pyodbc` 후 다시 실행하십시오. (원인: %s)' % exc
        )

    cs = conn_str or build_conn_str(kind, driver, host, port, database, user)
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
                    database='', user='', conn_str=''):
    """로그용 마스킹된 접속 문자열. 비밀번호가 log.html 로 새지 않는다."""
    cs = conn_str or build_conn_str(kind, driver, host, port, database, user)
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
