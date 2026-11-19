"""
DbSeedHelper.py  —  실행 전 DB 설정 시드 파일(config/db_seed/<env>.sql) 파서
=====================================================================

`run_tests.sh` 가 본 실행 전에 `setup/db_seed.robot` 을 돌려 PG 가 읽는 설정 행이
있는지 보고, 없으면 넣는다. 이 모듈은 **SQL 파일을 블록으로 나누기만** 한다 —
접속·조회·INSERT 는 `PdbHelper.py` 의 `db_connect` / `db_count` / `db_execute`
를 그대로 쓴다(접속 문자열 해석·마스킹·commit 규칙을 두 벌로 두지 않기 위해서다).

[파일 형식]
  `;` 로 끝나는 SQL 문장을 나열한다. **SELECT 로 시작하는 문장이 블록을 연다.**
  다음 SELECT 가 나오기 전까지의 INSERT / UPDATE 문이 그 블록에 속한다.
  여러 줄에 걸쳐 써도 된다 — 문장은 `;` 로만 나뉜다.

    -- @name: NAG 클라이언트 등록
    SELECT COUNT(*) FROM T_XXX_CFG WHERE KEY_COL = 'A';
    INSERT INTO T_XXX_CFG (KEY_COL, VAL) VALUES ('A', '1');
    UPDATE T_XXX_CFG SET VAL = '1' WHERE KEY_COL = 'A';

  SELECT 는 `COUNT(*)` 처럼 **1행 1열 정수**를 돌려줘야 한다. 실행 조건은 문장
  종류로 정해진다.
    0건      → INSERT 만 실행 (UPDATE 는 건너뜀)
    1건 이상 → UPDATE 만 실행 (INSERT 는 건너뜀)
  INSERT 만 있는 블록은 "없으면 넣기", UPDATE 만 있는 블록은 "있으면 고치기",
  둘 다 있으면 upsert 다. 그 밖의 문장(DELETE 등)은 형식 오류로 거부한다.
  `-- @name:` 주석은 선택이다. 없으면 SELECT 문 앞부분을 이름으로 쓴다.

  따옴표('...' / "...") 안의 `;` 와 `--` 는 문장 구분·주석으로 보지 않는다
  (JSON 페이로드를 넣는 경우 대비). `/* */` 블록 주석은 지원하지 않는다.

[변수 — `${이름}`]
  문장 안의 `${CDS_MDN}` 처럼 쓴 자리를 Robot 변수 값으로 바꾼다 — 환경 파일
  (config/env/<env>.py) 값이 그대로 들어간다. 따옴표 안이든 밖이든 **글자 그대로**
  끼워 넣는다(이스케이프하지 않는다 — 값에 `'` 가 있으면 SQL 이 깨진다).
    SELECT COUNT(*) FROM T_SESSION_INFO WHERE MDN='${CDS_MDN}';
    ... '82${CDS_MIN}', '${CDS_MDN}lte.sktelecom.com', ...
  이름은 `${영문·숫자·_}` 만 받는다(`${X}[0]`·`${X + 1}` 같은 확장 문법은 없다).
  **없는 변수는 줄 번호와 함께 DbSeedError** — 빈 값으로 넣지 않는다.
  주석은 파싱 단계에서 버려지므로 주석 안의 `${...}` 는 치환하지 않는다.
"""

import os
import re

_VAR_RE = re.compile(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}')
_MISSING = object()
_NAME_RE = re.compile(r'^\s*--\s*@name\s*:\s*(.*?)\s*$')
_TARGET_RE = re.compile(r'^\s*(INSERT\s+INTO|UPDATE)\s+([^\s(]+)', re.IGNORECASE)
_CHECK_RE = re.compile(r'\bFROM\s+([^\s(]+)(?:\s+WHERE\s+(.*))?\Z', re.IGNORECASE | re.DOTALL)


class DbSeedError(Exception):
    """시드 파일 형식 오류."""


def _split_statements(text):
    """`;` 로 문장을 나눈다. 따옴표 안은 건드리지 않고, `--` 주석은 버린다.

    `-- @name:` 주석은 버리지 않고 바로 다음 문장의 이름으로 붙인다.
    반환: [(문장, 이름 또는 None, 시작 줄 번호)]
    """
    out = []
    buf = []
    name = None
    start_line = None
    quote = None
    line_no = 1
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if quote:
            buf.append(ch)
            if ch == quote:
                # SQL 의 '' 이스케이프 — 닫힘이 아니라 따옴표 문자 하나다
                if i + 1 < n and text[i + 1] == quote:
                    buf.append(text[i + 1])
                    i += 1
                else:
                    quote = None
        elif ch in ("'", '"'):
            quote = ch
            buf.append(ch)
        elif ch == '-' and text.startswith('--', i):
            end = text.find('\n', i)
            end = n if end < 0 else end
            m = _NAME_RE.match(text[i:end])
            if m:
                name = m.group(1) or None
            i = end
            continue
        elif ch == ';':
            stmt = ''.join(buf).strip()
            if stmt:
                out.append((stmt, name, start_line))
            buf = []
            name = None
            start_line = None
        else:
            if start_line is None and not ch.isspace():
                start_line = line_no
            buf.append(ch)
        if ch == '\n':
            line_no += 1
        i += 1
    if quote:
        raise DbSeedError('따옴표가 닫히지 않았습니다 (%s)' % quote)
    tail = ''.join(buf).strip()
    if tail:
        raise DbSeedError(
            '%d번째 줄 문장이 `;` 로 끝나지 않았습니다: %s' % (start_line, tail[:80])
        )
    return out


def _robot_lookup(name):
    """Robot 변수 `${name}` 값. Robot 밖이거나 변수가 없으면 _MISSING."""
    try:
        from robot.libraries.BuiltIn import BuiltIn
        return BuiltIn().get_variable_value('${%s}' % name, _MISSING)
    except Exception:          # Robot 밖에서 직접 호출된 경우
        return _MISSING


def _substitute(text, lookup, where):
    """text 안의 `${이름}` 을 lookup(이름) 값으로 바꾼다. 없으면 DbSeedError."""
    def repl(m):
        value = lookup(m.group(1))
        if value is _MISSING or value is None:
            raise DbSeedError(
                '%s — 변수 ${%s} 가 없습니다. config/env/<env>.py 에 정의하거나 '
                '--variable 로 주십시오.' % (where, m.group(1))
            )
        return str(value)
    return _VAR_RE.sub(repl, text)


def load_seed_blocks(path, variables=None):
    """시드 파일을 읽어 블록 목록을 돌려준다.

    반환: [{'name': str, 'check': str, 'inserts': [str, ...], 'line': int}]
    파일이 없거나 문장이 하나도 없으면 빈 목록 — 호출자는 DB 에 접속하지 않고 지나간다.
    형식이 틀리면 줄 번호를 담아 DbSeedError 를 올린다.

    문장과 `-- @name:` 의 `${이름}` 은 치환해서 돌려준다(모듈 docstring 참조).
    variables(dict)를 주면 그 값을, 안 주면 실행 중인 Robot 변수를 쓴다 —
    Robot 밖에서 직접 부를 때만 variables 를 넘긴다.
    """
    if not os.path.isfile(path):
        return []
    with open(path, encoding='utf-8') as f:
        text = f.read()
    try:
        stmts = _split_statements(text)
    except DbSeedError as exc:
        raise DbSeedError('%s — %s' % (path, exc))

    if variables is not None:
        def lookup(name):
            return variables.get(name, _MISSING)
    else:
        lookup = _robot_lookup
    stmts = [
        (_substitute(stmt, lookup, '%s:%d' % (path, line)),
         _substitute(name, lookup, '%s:%d' % (path, line)) if name else name,
         line)
        for stmt, name, line in stmts
    ]

    blocks = []
    for stmt, name, line in stmts:
        verb = stmt.split(None, 1)[0].upper()
        if verb == 'SELECT':
            check_desc = describe_check(stmt)
            blocks.append({
                'name': name or check_desc,
                'check': stmt,
                'check_desc': check_desc,
                'inserts': [],
                'updates': [],
                'line': line,
            })
        elif not blocks:
            raise DbSeedError(
                '%s:%d — 확인용 SELECT 없이 시작하는 문장입니다. 블록은 SELECT 로 '
                '열어야 합니다: %s' % (path, line, stmt[:80])
            )
        elif verb == 'INSERT':
            blocks[-1]['inserts'].append(stmt)
        elif verb == 'UPDATE':
            blocks[-1]['updates'].append(stmt)
        else:
            raise DbSeedError(
                '%s:%d — 블록 안에는 INSERT / UPDATE 만 쓸 수 있습니다 (%s): %s'
                % (path, line, verb, stmt[:80])
            )
    for b in blocks:
        if not b['inserts'] and not b['updates']:
            raise DbSeedError(
                '%s:%d — SELECT 뒤에 INSERT / UPDATE 문이 없습니다 (%s)'
                % (path, b['line'], b['name'])
            )
    return blocks


def describe_statement(sql):
    """로그용 한 줄 요약 — `INSERT INTO T_X` / `UPDATE T_X`. 못 알아보면 앞부분 60자."""
    m = _TARGET_RE.match(sql)
    if m:
        return '%s %s' % (' '.join(m.group(1).upper().split()), m.group(2))
    return ' '.join(sql.split())[:60]


def describe_check(sql):
    """확인 SELECT 의 로그용 요약 — `SELECT T_X (WHERE 조건)`. WHERE 가 없으면
    `SELECT T_X`. 못 알아보면 문장 전체(공백만 정리)를 그대로 쓴다 — 자르지 않는다.
    """
    m = _CHECK_RE.search(sql)
    if not m:
        return ' '.join(sql.split())
    if m.group(2):
        return 'SELECT %s (%s)' % (m.group(1), ' '.join(m.group(2).split()))
    return 'SELECT %s' % m.group(1)
