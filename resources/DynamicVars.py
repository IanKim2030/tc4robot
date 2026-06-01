"""
DynamicVars.py  —  Robot Framework 동적 변수 파일 (클래스 기반)
==================================================================

여러 개일 수 있는 PG 프로세스 설정 파일(.cfg)을 읽어
Robot Framework ${변수} 로 주입한다.

생성되는 변수명 규칙
--------------------
    PREFIX 미지정 → 파일명을 접두사로 사용 (파일마다 다름)
        예) PG.cfg 의 PACKAGE_ID    → ${PG_PACKAGE_ID}
            PG01.cfg 의 PACKAGE_ID  → ${PG01_PACKAGE_ID}
    PREFIX 지정   → 그 값을 모든 파일에 공통 적용
        예) prefix=PG, 어느 파일이든 PACKAGE_ID → ${PG_PACKAGE_ID}

    파일명 기반이면 파일마다 접두사가 달라 같은 키도 충돌하지 않는다.
        Variables  DynamicVars.py  /PG/CFG/NAG.cfg  /PG/CFG/PCF.cfg
        → ${NAG_PACKAGE_ID}, ${PCF_PACKAGE_ID}

사용법 (export 불필요, 인자로 파일명 전달)
------------------------------------------
  *** Settings ***
  # 파일 여러 개
  Variables    ../resources/DynamicVars.py    /PG/CFG/PG01.cfg    /PG/CFG/PG02.cfg
  # 디렉터리 (안의 *.cfg 자동 수집)
  Variables    ../resources/DynamicVars.py    /PG/CFG
  # PREFIX / 섹션 / 인코딩 지정 (위치 무관)
  Variables    ../resources/DynamicVars.py    /PG/CFG/PG01.cfg    prefix=PG    section=COMMON    encoding=euc-kr

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

인코딩
------
    encoding 미지정 → utf-8 → euc-kr → cp949 → latin-1 순서로 자동 시도.
    (한국 레거시 통신 환경의 ISO-8859/EUC-KR 파일 자동 대응)
    encoding=euc-kr 처럼 명시하면 그 인코딩만 사용.
"""

import os
import re
import glob
import configparser


class PgConfigLoader:
    """PG 설정 파일을 읽어 Robot 변수 dict 로 만들어주는 클래스."""

    DEFAULT_PREFIX = ""        # prefix 미지정 시 접두사 없음 (키 그대로)
    DEFAULT_SECTION = "COMMON"
    # 인코딩 자동 감지 시도 순서.
    # 한국 레거시 통신 환경: 대부분 ASCII 거나 EUC-KR/CP949.
    # file 명령이 'ISO-8859' 로 보는 건 비ASCII 바이트가 섞였다는 뜻이라
    # euc-kr → cp949 를 먼저 시도하고, 마지막에 latin-1(절대 실패 안 함) 로 폴백.
    FALLBACK_ENCODINGS = ("utf-8", "euc-kr", "cp949", "latin-1")

    def __init__(self, *config_paths, prefix=None, section=None, encoding=None):
        # ── 방어 처리 ──
        # RF 버전에 따라 prefix=/section=/encoding= 가 named 가 아닌
        # 위치 문자열("prefix=PG")로 넘어올 수 있어, 경로에서 분리해 흡수한다.
        paths = []
        opts = {"prefix": prefix, "section": section, "encoding": encoding}
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
        # encoding 미지정 → 자동 감지(FALLBACK_ENCODINGS 순서대로 시도)
        self.encoding = opts["encoding"] or None

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

    # ── 인코딩 자동 감지 읽기 ──────────────────────────────────────
    def _read_text(self, path):
        """
        파일을 읽어 (텍스트, 사용된인코딩) 튜플 반환.
        encoding 이 지정돼 있으면 그것만 사용하고,
        없으면 FALLBACK_ENCODINGS 를 순서대로 시도한다.
        latin-1 은 모든 바이트를 받아들이므로 최종 폴백으로 항상 성공한다.
        """
        if self.encoding:
            with open(path, encoding=self.encoding) as f:
                return f.read(), self.encoding

        last_err = None
        for enc in self.FALLBACK_ENCODINGS:
            try:
                with open(path, encoding=enc) as f:
                    text = f.read()
                if enc != "utf-8":
                    print(f"[DynamicVars] 인코딩 자동감지: {enc} ({path})")
                return text, enc
            except UnicodeDecodeError as e:
                last_err = e
                continue
        # 여기 도달하면 latin-1 도 실패한 것(사실상 불가) → 원본 에러 전달
        raise last_err

    # ── 파일명 → 접두사 ────────────────────────────────────────────
    @staticmethod
    def _prefix_from_path(path):
        """
        파일명(확장자 제외)을 대문자 접두사로 변환.
          /PG/CFG/PG.cfg      → PG
          /PG/CFG/PG01.cfg    → PG01
          /PG/CFG/pg-nag.conf → PG_NAG
        """
        stem = os.path.splitext(os.path.basename(path))[0]
        return re.sub(r"[^0-9A-Za-z]+", "_", stem).upper().strip("_")

    def _resolve_prefix(self, path):
        """
        이 파일에 쓸 접두사를 결정한다.
          - prefix= 가 명시돼 있으면  → 그 값 (모든 파일 공통)
          - 명시 안 돼 있으면        → 파일명에서 도출 (파일마다 다름)
        """
        if self.prefix:
            return self.prefix
        return self._prefix_from_path(path)

    # ── 파일 1개 파싱 ──────────────────────────────────────────────
    def _parse_one_config(self, path):
        """
        설정 파일 1개를 파싱해 {접두사_키: 값} dict 로 반환.

        접두사:
          - prefix= 명시 시 그 값, 아니면 파일명에서 도출
            (PG.cfg → PG_ , PG01.cfg → PG01_)

        주의:
          - optionxform=str → 키 대소문자 보존 (안 하면 소문자화됨)
          - 인라인 주석 끔 → DB_CONNOPT 의 ';' 가 잘리지 않게
          - 주석(#) 라인은 configparser 가 자동 무시
          - 인코딩은 _read_text 가 자동 감지 (ISO-8859/EUC-KR 등 레거시 대응)
        """
        one = {}
        if not os.path.exists(path):
            print(f"[DynamicVars] config 파일 없음, 건너뜀: {path}")
            return one

        text, _ = self._read_text(path)
        parser = configparser.ConfigParser()
        parser.optionxform = str
        parser.read_string(text, source=path)

        if not parser.has_section(self.section):
            print(f"[DynamicVars] [{self.section}] 섹션 없음, 건너뜀: {path}")
            return one

        prefix = self._resolve_prefix(path)
        for key, value in parser.items(self.section):
            var_name = f"{prefix}_{key}" if prefix else key
            one[var_name] = value

        print(f"[DynamicVars] config 파싱: {len(one)}개 [{prefix or '접두사없음'}] ({path})")
        return one

    # ── config 파일 전체 ───────────────────────────────────────────
    def _load_from_process_config(self):
        result = {}
        paths = self._expand_inputs()
        if not paths:
            print("[DynamicVars] config 입력 없음, 건너뜀")
            return result

        for path in paths:
            one = self._parse_one_config(path)
            # 파일접두사 없이 키를 그대로 쓰므로, 여러 파일에 같은 키가 있으면
            # 나중 파일이 앞 파일을 덮어쓴다. 조용히 사라지지 않게 경고를 띄운다.
            # (구분이 필요하면 파일마다 다른 prefix= 를 주면 됨)
            dup = set(result) & set(one)
            for k in dup:
                if result[k] != one[k]:
                    print(f"[DynamicVars] ⚠ 키 '{k}' 중복: "
                          f"'{result[k]}' → '{one[k]}' 로 덮어씀 ({path})")
            result.update(one)

        print(f"[DynamicVars] config 총 {len(result)}개, 파일 {len(paths)}개")
        return result

    # ── 최종 결과 ──────────────────────────────────────────────────
    def get_variables(self):
        """설정 파일들을 읽어 병합해 반환. (접두사는 파일별 파싱에서 이미 적용됨)"""
        result = self._load_from_process_config()
        mode = self.prefix if self.prefix else "파일명 기반"
        print(f"[DynamicVars] 최종 주입 {len(result)}개 "
              f"(prefix={mode}, section={self.section})")
        return result


# ── Robot Framework 모듈 진입점 ───────────────────────────────────
# RF 는 모듈의 get_variables() 함수를 먼저 찾으므로, 여기서 클래스에 위임한다.
# 주의: RF 의 인자 개수 판별 때문에 **kwargs 를 쓰면
#       "expected 0 arguments" 오류가 난다. 순수 *args 로만 받고,
#       prefix=/section=/encoding= 는 클래스 __init__ 의 방어 로직이
#       위치 문자열에서 분리해 흡수한다.
def get_variables(*args):
    return PgConfigLoader(*args).get_variables()


# 단독 실행: python DynamicVars.py <file_or_dir> [...] [prefix=..] [section=..] [encoding=..]
if __name__ == "__main__":
    import sys
    import json
    print(json.dumps(get_variables(*sys.argv[1:]), ensure_ascii=False, indent=2))
