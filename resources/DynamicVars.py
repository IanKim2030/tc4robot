"""
DynamicVars.py  —  Robot Framework 동적 변수 파일 (클래스 기반)
==================================================================

여러 개일 수 있는 PG 프로세스 설정 파일(.cfg)을 읽어
Robot Framework ${변수} 로 주입한다.

생성되는 변수명 규칙
--------------------
    {FILE_PREFIX}_{SECTION_PREFIX}_{KEY}
        FILE_PREFIX    : prefix= 명시 시 그 값, 아니면 파일명에서 도출
                         (PG.cfg → PG, PG01.cfg → PG01)
        SECTION_PREFIX : 섹션명을 대문자로 ([COMMON] → COMMON)
        KEY            : 설정 파일의 KEY 그대로

    예) PG.cfg 의 [COMMON] PACKAGE_ID → ${PG_COMMON_PACKAGE_ID}
        PG.cfg 의 [NAG]    PORT       → ${PG_NAG_PORT}

    파일의 모든 섹션을 읽는다. 특정 섹션/키만 읽으려면 section= 지정.
        section=COMMON                  → COMMON 섹션 전체
        section=COMMON:ORACLE_SID,PORT  → COMMON 섹션의 그 키들만
        (미지정이면 전체 섹션·전체 키)
    파일이 여러 개면 각 파일명이 FILE_PREFIX 가 되어 충돌하지 않는다.

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


class PgConfigLoader:
    """PG 설정 파일을 읽어 Robot 변수 dict 로 만들어주는 클래스."""

    DEFAULT_PREFIX = ""        # prefix 미지정 시 접두사 없음 (키 그대로)
    DEFAULT_SECTION = ""       # 빈 값 = 파일의 모든 섹션을 읽음
    # 인코딩 자동 감지 시도 순서.
    # 한국 레거시 통신 환경: 대부분 ASCII 거나 EUC-KR/CP949.
    # file 명령이 'ISO-8859' 로 보는 건 비ASCII 바이트가 섞였다는 뜻이라
    # euc-kr → cp949 를 먼저 시도하고, 마지막에 latin-1(절대 실패 안 함) 로 폴백.
    # 인코딩 strict 시도 순서. latin-1 은 의도적으로 제외:
    # latin-1 은 모든 바이트를 받아들여 '성공'해버려서 한글이 깨진 채 읽히고
    # replace 폴백에 도달하지 못한다. strict 로 전부 실패하면 cp949/replace 로 간다.
    FALLBACK_ENCODINGS = ("utf-8", "euc-kr", "cp949")

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
        self.section = opts["section"] if opts["section"] is not None else self.DEFAULT_SECTION
        # section 스펙 파싱: "COMMON:ORACLE_SID,PORT" → (섹션명, {키집합})
        self.want_section, self.want_keys = self._parse_section_spec(self.section)
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
        없으면 FALLBACK_ENCODINGS 를 순서대로 깨끗이(strict) 시도한다.

        모든 인코딩이 strict 로 실패하면(= 파일에 손상/혼합 바이트가 있으면),
        cp949 + errors='replace' 로 손상 바이트만 치환해 읽는다.
        설정값(KEY=VALUE)은 대부분 ASCII 라 영향이 없고,
        깨지는 건 한글 주석/설명 줄 정도다. 이렇게 해서 절대 죽지 않게 한다.
        """
        if self.encoding:
            # 명시 인코딩도 손상 대비해 replace 허용
            with open(path, encoding=self.encoding, errors="replace") as f:
                return f.read(), self.encoding

        for enc in self.FALLBACK_ENCODINGS:
            try:
                with open(path, encoding=enc) as f:
                    text = f.read()
                if enc != "utf-8":
                    print(f"[DynamicVars] 인코딩 자동감지: {enc} ({path})")
                return text, enc
            except UnicodeDecodeError:
                continue

        # 전부 실패 → 손상/혼합 바이트가 섞인 파일. replace 로 강제 디코딩.
        print(f"[DynamicVars] ⚠ 인코딩 strict 실패 → cp949/replace 로 읽음 "
              f"(손상 바이트 치환, 설정값엔 영향 적음): {path}")
        with open(path, encoding="cp949", errors="replace") as f:
            return f.read(), "cp949(replace)"

    # ── 이름 정규화 / 파일명 → 접두사 ──────────────────────────────
    @staticmethod
    def _normalize(name):
        """문자열을 변수명 조각으로 정규화: 대문자화, 영숫자 외는 '_'."""
        return re.sub(r"[^0-9A-Za-z]+", "_", name).upper().strip("_")

    @classmethod
    def _parse_section_spec(cls, spec):
        """
        section= 스펙을 (섹션명, 키집합) 으로 파싱한다.

          ""                       → (None, None)        전체 섹션, 전체 키
          "COMMON"                 → ("COMMON", None)    COMMON 섹션 전체 키
          "COMMON:ORACLE_SID,PORT" → ("COMMON", {"ORACLE_SID","PORT"})
                                                          COMMON 의 그 키들만

        섹션명/키는 변수명과 같게 _normalize 로 맞춰 비교한다.
        (키 집합이 None 이면 키 필터 없음 = 전체)
        """
        if not spec:
            return None, None
        sec_part, sep, keys_part = spec.partition(":")
        section = cls._normalize(sec_part) if sec_part else None
        keys = None
        if sep and keys_part.strip():
            keys = {cls._normalize(k) for k in keys_part.split(",") if k.strip()}
        return section, keys

    @classmethod
    def _prefix_from_path(cls, path):
        """
        파일명(확장자 제외)을 대문자 접두사로 변환.
          /PG/CFG/PG.cfg      → PG
          /PG/CFG/PG01.cfg    → PG01
          /PG/CFG/pg-nag.conf → PG_NAG
        """
        stem = os.path.splitext(os.path.basename(path))[0]
        return cls._normalize(stem)

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
        설정 파일 1개의 모든 섹션을 관대하게(lenient) 파싱해
        {파일접두사_섹션접두사_키: 값} dict 로 반환.

        변수명:
          {FILE_PREFIX}_{SECTION_PREFIX}_{KEY}
            예) PG.cfg 의 [COMMON] PACKAGE_ID → ${PG_COMMON_PACKAGE_ID}
                PG.cfg 의 [NAG]    PORT       → ${PG_NAG_PORT}

          - FILE_PREFIX    : prefix= 명시 시 그 값, 아니면 파일명에서 도출
          - SECTION_PREFIX : 섹션명을 대문자로 ([COMMON] → COMMON)
                             섹션 헤더가 없으면 빈 값
          - section= 로 섹션/키 필터:
              미지정              → 전체 섹션·전체 키
              section=COMMON      → COMMON 섹션 전체
              section=COMMON:K1,K2→ COMMON 섹션의 K1,K2 키만

        configparser 대신 직접 줄 단위로 파싱하는 이유:
          실제 운영 파일(PG_V2.cfg)에 인코딩이 혼합/손상된 한글 주석 줄이 있어
          configparser 의 엄격한 파싱이 ParsingError 로 죽는다.
          여기서는 'KEY=VALUE' 와 '[SECTION]' 만 인식하고,
          형식에 안 맞거나 깨진 줄은 조용히 건너뛴다.

        규칙:
          - 빈 줄, '#' / '//' / ';' 로 시작하는 줄 → 주석/무시
          - '[이름]' → 섹션 헤더
          - 첫 '=' 기준으로 KEY=VALUE 분리 (값에 '=' 가 더 있어도 보존)
          - '=' 없는 줄(깨진 한글 설명 등) → 건너뜀
          - KEY 는 대문자/숫자/_ 로만 이뤄진 정상적인 키만 인정
            (깨진 바이트가 섞인 줄을 값으로 오인하지 않도록)
        """
        one = {}
        if not os.path.exists(path):
            print(f"[DynamicVars] config 파일 없음, 건너뜀: {path}")
            return one

        text, _ = self._read_text(path)
        file_prefix = self._resolve_prefix(path)
        want_section = self.want_section   # None 이면 전체 섹션
        want_keys = self.want_keys         # None 이면 전체 키

        cur_section = ""          # 섹션 헤더 이전 줄도 허용(섹션 없는 파일 대비)
        seen_sections = set()
        skipped = 0
        for raw in text.splitlines():
            line = raw.strip()
            if not line or line[0] in "#;" or line.startswith("//"):
                continue
            # 섹션 헤더
            if line.startswith("[") and line.endswith("]"):
                cur_section = self._normalize(line[1:-1])
                continue
            # KEY=VALUE
            if "=" not in line:
                skipped += 1
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            # 정상 키만 인정: 영문/숫자/_/- 등. 깨진 바이트가 섞인 키는 거른다.
            if not re.match(r"^[A-Za-z0-9_.\-]+$", key):
                skipped += 1
                continue

            # 섹션 필터
            if want_section is not None and cur_section != want_section:
                continue
            key_norm = self._normalize(key)
            # 키 필터 (section=COMMON:KEY1,KEY2 형태일 때만 적용)
            if want_keys is not None and key_norm not in want_keys:
                continue

            seen_sections.add(cur_section)
            parts = [p for p in (file_prefix, cur_section, key_norm) if p]
            one["_".join(parts)] = value.strip()

        note = f"섹션 {len(seen_sections)}개" if seen_sections else "섹션0"
        if skipped:
            note += f", 건너뛴 줄 {skipped}개"
        print(f"[DynamicVars] config 파싱: {len(one)}개 "
              f"[{file_prefix or '접두사없음'}] {note} ({path})")
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
              f"(prefix={mode}, section={self.section or '전체'})")
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
