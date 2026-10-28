"""
DbSeedHelper.py  —  실행 전 DB 설정 시드 파일(config/db_seed/<env>.sql) 파서
=====================================================================

`run_tests.sh` 가 본 실행 전에 `setup/db_seed.robot` 을 돌려 PG 가 읽는 설정 행이
있는지 보고, 없으면 넣는다. 이 모듈은 **SQL 파일을 블록으로 나누기만** 한다 —
접속·조회·INSERT 는 `CdsDbHelper.py` 의 `db_connect` / `db_count` / `db_execute`
를 그대로 쓴다(접속 문자열 해석·마스킹·commit 규칙을 두 벌로 두지 않기 위해서다).

[파일 형식]
  `;` 로 끝나는 SQL 문장을 나열한다. **SELECT 로 시작하는 문장이 블록을 연다.**
  다음 SELECT 가 나오기 전까지의 문장들이 그 블록의 INSERT 다.

    -- @name: NAG 클라이언트 등록
    SELECT COUNT(*) FROM T_XXX_CFG WHERE KEY_COL = 'A';
    INSERT INTO T_XXX_CFG (KEY_COL, VAL) VALUES ('A', '1');

  SELECT 는 `COUNT(*)` 처럼 **1행 1열 정수**를 돌려줘야 한다. 0 이면 INSERT 를
  실행하고, 아니면 건너뛴다(멱등).
  `-- @name:` 주석은 선택이다. 없으면 SELECT 문 앞부분을 이름으로 쓴다.

  따옴표('...' / "...") 안의 `;` 와 `--` 는 문장 구분·주석으로 보지 않는다
  (JSON 페이로드를 넣는 경우 대비). `/* */` 블록 주석은 지원하지 않는다.
"""

import os
import re

_NAME_RE = re.compile(r'^\s*--\s*@name\s*:\s*(.*?)\s*$')


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


def load_seed_blocks(path):
    """시드 파일을 읽어 블록 목록을 돌려준다.

    반환: [{'name': str, 'check': str, 'inserts': [str, ...], 'line': int}]
    파일이 없거나 문장이 하나도 없으면 빈 목록 — 호출자는 DB 에 접속하지 않고 지나간다.
    형식이 틀리면 줄 번호를 담아 DbSeedError 를 올린다.
    """
    if not os.path.isfile(path):
        return []
    with open(path, encoding='utf-8') as f:
        text = f.read()
    try:
        stmts = _split_statements(text)
    except DbSeedError as exc:
        raise DbSeedError('%s — %s' % (path, exc))

    blocks = []
    for stmt, name, line in stmts:
        if stmt.split(None, 1)[0].upper() == 'SELECT':
            blocks.append({
                'name': name or ' '.join(stmt.split())[:60],
                'check': stmt,
                'inserts': [],
                'line': line,
            })
        elif not blocks:
            raise DbSeedError(
                '%s:%d — 확인용 SELECT 없이 시작하는 문장입니다. 블록은 SELECT 로 '
                '열어야 합니다: %s' % (path, line, stmt[:80])
            )
        else:
            blocks[-1]['inserts'].append(stmt)
    for b in blocks:
        if not b['inserts']:
            raise DbSeedError(
                '%s:%d — SELECT 뒤에 넣을 문장이 없습니다 (%s)' % (path, b['line'], b['name'])
            )
    return blocks
