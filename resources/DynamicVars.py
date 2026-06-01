"""
DynamicVars.py  —  Robot Framework 동적 변수 파일 (클래스 기반)
==================================================================

여러 개일 수 있는 PG 프로세스 설정 파일(.cfg)과 DB 조회 값을 읽어
Robot Framework ${변수} 로 주입한다.

생성되는 변수명 규칙
--------------------
    {PREFIX}_{파일접두사}_{키}
        PREFIX      : 모든 변수에 공통으로 붙는 접두사 (기본 "CFG")
        파일접두사  : 설정 파일명(확장자 제외)을 대문자로 변환 → 파일 간 충돌 방지
        키          : 설정 파일의 KEY 그대로

    예) PREFIX=CFG, PG01.cfg 의 FILE_LOG_PATH
        → ${CFG_PG01_FILE_LOG_PATH}

사용법 (export 불필요, 인자로 파일명 전달)
------------------------------------------
  *** Settings ***
  # 파일 여러 개
  Variables    ../resources/DynamicVars.py    /PG/CFG/PG01.cfg    /PG/CFG/PG02.cfg
  # 디렉터리 (안의 *.cfg 자동 수집)
  Variables    ../resources/DynamicVars.py    /PG/CFG
  # PREFIX / 섹션 / DB환경 지정 (위치 무관)
  Variables    ../resources/DynamicVars.py    /PG/CFG/PG01.cfg    prefix=PG    section=COMMON    env=prod

  # CLI (인자 구분자는 콜론 ':')
  robot --variablefile resources/DynamicVars.py:/PG/CFG/PG01.cfg:/PG/CFG/PG02.cfg tests/

  # 단독 실행 (주입될 값 미리보기)
  python DynamicVars.py /PG/CFG/PG01.cfg /PG/CFG/PG02.cfg

PG 설정 파일 포맷 (INI 유사)
----------------------------
    [COMMON]
    SYSTEM_NAME=PG01
    BRANCH_NAME=SS
    FILE_LOG_PATH=/LOG
    DB_CONNOPT=DSN=192.168.10.35;CONNTYPE=1;...   ← 값에 = ; 포함돼도 보존
    #HA_PEER=...                                  ← 주석처리 라인은 자동 무시
"""

import os
import re
import glob
import configparser


class PgConfigVariables:
    """PG 설정 파일 + DB 값을 읽어 Robot 변수 dict 로 만들어주는 클래스."""

    DEFAULT_PREFIX = "CFG"     # 모든 변수명에 붙는 공통 접두사
    DEFAULT_SECTION = "COMMON"
    DEFAULT_ENV = "dev"

    def __init__(self, *config_paths, prefix=None, section=None, env=None):
        # ── 방어 처리 ──
        # RF 버전에 따라 prefix=/section=/env= 가 named 가 아닌
        # 위치 문자열("env=prod")로 넘어올 수 있어, 경로에서 분리해 흡수한다.
        paths = []
        opts = {"prefix": prefix, "section": section, "env": env}
        for arg in config_paths:
            arg = str(arg)
            base = arg.replace("\\", "/").split("/")[-1]   # 파일명 부분만 검사
            if "=" in base:
                key, _, val = arg.partition("=")
                key = key.strip().lower()
                if key in opts:
                    opts[key] = val.strip()
                    continue
            paths.append(arg)

        self.config_paths = paths
        self.prefix = opts["prefix"] if opts["prefix"] is not None else self.DEFAULT_PREFIX
        self.section = opts["section"] or self.DEFAULT_SECTION
        self.env = opts["env"] or self.DEFAULT_ENV

    # ── 입력 경로 펼치기 ───────────────────────────────────────────
    def _expand_inputs(self):
        """
        입력 인자를 실제 파일 목록으로 펼친다.
          - 파일 경로  → 그대로
          - 디렉터리   → 그 안의 *.cfg 전부
          - 와일드카드 → glob 검색
        """
        paths = []
        for item in self.config_paths:
            item = item.strip()
            if not item:
                continue
            if os.path.isdir(item):
                paths.extend(sorted(glob.glob(os.path.join(item, "*.cfg"))))
            elif any(ch in item for ch in "*?["):
                paths.extend(sorted(glob.glob(item)))
            else:
                paths.append(item)
        return paths

    # ── 파일명 → 접두사 ────────────────────────────────────────────
    @staticmethod
    def _prefix_from_path(path):
        """
        파일명(확장자 제외)을 대문자 접두사로 변환.
          /PG/CFG/PG01.cfg    → PG01
          /PG/CFG/pg-nag.conf → PG_NAG
        """
        stem = os.path.splitext(os.path.basename(path))[0]
        return re.sub(r"[^0-9A-Za-z]+", "_", stem).upper().strip("_")

    # ── 파일 1개 파싱 ──────────────────────────────────────────────
    def _parse_one_config(self, path, file_prefix):
        """
        설정 파일 1개를 파싱해 {파일접두사_키: 값} dict 로 반환.
        (공통 PREFIX 는 마지막 _apply_prefix 단계에서 일괄 적용)

        주의:
          - optionxform=str → 키 대소문자 보존 (안 하면 소문자화됨)
          - 인라인 주석 끔 → DB_CONNOPT 의 ';' 가 잘리지 않게
          - 주석(#) 라인은 configparser 가 자동 무시
        """
        one = {}
        if not os.path.exists(path):
            print(f"[dynamic_vars] config 파일 없음, 건너뜀: {path}")
            return one

        parser = configparser.ConfigParser()
        parser.optionxform = str
        parser.read(path, encoding="utf-8")

        if not parser.has_section(self.section):
            print(f"[dynamic_vars] [{self.section}] 섹션 없음, 건너뜀: {path}")
            return one

        for key, value in parser.items(self.section):
            one[f"{file_prefix}_{key}"] = value

        print(f"[dynamic_vars] config 파싱: {len(one)}개 [{file_prefix}] ({path})")
        return one

    # ── config 파일 전체 ───────────────────────────────────────────
    def _load_from_process_config(self):
        result = {}
        paths = self._expand_inputs()
        if not paths:
            print("[dynamic_vars] config 입력 없음, 건너뜀")
            return result

        used_prefixes = {}   # 파일접두사 → 사용 횟수
        for path in paths:
            file_prefix = self._prefix_from_path(path)

            # 파일접두사 충돌 방지: 같은 접두사가 또 나오면 _2, _3... 을 붙인다.
            # (예: PG01.cfg 와 pg01.conf 가 둘 다 PG01 로 변환되는 경우)
            count = used_prefixes.get(file_prefix, 0) + 1
            used_prefixes[file_prefix] = count
            if count > 1:
                new_prefix = f"{file_prefix}_{count}"
                print(f"[dynamic_vars] ⚠ 파일접두사 '{file_prefix}' 중복 → "
                      f"'{new_prefix}' 로 분리: {path}")
                file_prefix = new_prefix

            result.update(self._parse_one_config(path, file_prefix))

        print(f"[dynamic_vars] config 총 {len(result)}개, 파일 {len(paths)}개")
        return result

    # ── DB 조회 ────────────────────────────────────────────────────
    def _load_from_db(self):
        """
        설정 테이블에서 환경별 값을 조회. (테이블/스키마는 실제 환경에 맞게 수정)
        예상 스키마: rf_test_config(env, config_key, config_value)
        DB 미연결/dryrun 에서도 죽지 않도록 경고만 출력하고 빈 dict 반환.
        """
        result = {}
        try:
            import pymysql  # pip install pymysql

            conn = pymysql.connect(
                host=os.getenv("DB_HOST", "127.0.0.1"),
                port=int(os.getenv("DB_PORT", "3306")),
                user=os.getenv("DB_USER", "rf_reader"),
                password=os.getenv("DB_PASS", ""),
                database=os.getenv("DB_NAME", "pg_config"),
                charset="utf8mb4",
                connect_timeout=5,
            )
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT config_key, config_value "
                    "FROM rf_test_config WHERE env = %s",
                    (self.env,),
                )
                for key, value in cur.fetchall():
                    result[key] = value
            conn.close()
            print(f"[dynamic_vars] DB 조회 성공: {len(result)}개 (env={self.env})")
        except Exception as e:
            print(f"[dynamic_vars] DB 조회 건너뜀 ({type(e).__name__}: {e})")
        return result

    # ── 공통 PREFIX 적용 ───────────────────────────────────────────
    def _apply_prefix(self, raw):
        """모든 변수명 앞에 공통 PREFIX 를 붙인다. PREFIX 가 비면 그대로."""
        if not self.prefix:
            return dict(raw)
        return {f"{self.prefix}_{key}": value for key, value in raw.items()}

    # ── 최종 결과 ──────────────────────────────────────────────────
    def get_variables(self):
        """
        병합 우선순위 (뒤가 우선): config 파일 < DB 조회
        병합 후 모든 키에 공통 PREFIX 적용.
        """
        merged = {}
        merged.update(self._load_from_process_config())  # 1차: config
        merged.update(self._load_from_db())              # 2차: DB(override)

        result = self._apply_prefix(merged)
        print(f"[dynamic_vars] 최종 주입 {len(result)}개 "
              f"(prefix={self.prefix or '없음'}, section={self.section}, env={self.env})")
        return result


# ── Robot Framework 모듈 진입점 ───────────────────────────────────
# RF 는 모듈의 get_variables() 함수를 먼저 찾으므로, 여기서 클래스에 위임한다.
# (모든 RF 버전에서 안정적으로 동작)
def get_variables(*config_paths, **options):
    return PgConfigVariables(*config_paths, **options).get_variables()


# 단독 실행: python dynamic_vars.py <file_or_dir> [...] [prefix=..] [section=..]
if __name__ == "__main__":
    import sys
    import json
    print(json.dumps(get_variables(*sys.argv[1:]), ensure_ascii=False, indent=2))
