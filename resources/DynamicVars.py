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
        section=COMMON                  → COMMON 섹션 전체 (접두사 적용)
        section=COMMON:ORACLE_SID,PORT  → 그 키들만, 변수명=키 이름
                                          (${ORACLE_SID}, ${PORT}, 접두사 없음)
        section=COMMON:ORACLE_SID=DB_SID→ 그 키만, 변수명=별칭 (${DB_SID})
        (미지정이면 전체 섹션·전체 키, 접두사 적용)
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

리모트(SSH) 파일
----------------
  경로를 'user@host:/path' 또는 'host:/path' 형태로 주면 SSH 로 읽는다.
  시스템의 ssh 명령(subprocess)을 쓰므로 paramiko 등 추가 설치가 필요 없다.
  (Python 3.6.8 등 구버전 환경에서도 동작)
  Variables    ../resources/DynamicVars.py    pg@192.168.10.44:/PG/CFG/PG.cfg    prefix=PG

  인증 (보안상 Variables 인자에 비밀번호를 넣지 않는다 — RF 로그에 남음):
    PG_ROBOT_SSH_USER   사용자 (경로의 user@ 가 우선, 없으면 이 값, 없으면 OS 계정)
    PG_ROBOT_SSH_PORT   포트 (기본 22)
    PG_ROBOT_SSH_KEY    개인키 파일 경로 (미지정 시 ~/.ssh 기본 키 / ssh-agent 사용)
    PG_ROBOT_SSH_PASS   비밀번호 (sshpass 불필요 — pty 로 프롬프트에 응답)
  예) export PG_ROBOT_SSH_PASS='pg1234'
      robot tests/
  접속/읽기 실패 시 그 파일만 건너뛰고 경고를 남긴다(전체 테스트는 계속).
  로컬·원격 파일을 같은 줄에 섞어 써도 된다.

  전제: 실행 머신에 ssh 클라이언트가 있어야 한다(리눅스엔 기본 설치).
        비밀번호 인증은 PG_ROBOT_SSH_PASS, 키 인증은 PG_ROBOT_SSH_KEY 로.
        둘 다 없으면 ~/.ssh 기본 키/ssh-agent 로 키 인증을 시도한다.

PG 설정 파일 포맷 (INI 유사)
----------------------------
    [COMMON]
    SYSTEM_NAME=PG01
    BRANCH_NAME=SS
    FILE_LOG_PATH=/LOG
    DB_CONNOPT=DSN=192.168.10.35;CONNTYPE=1;...   ← 값에 = ; 포함돼도 보존
    #HA_PEER=...                                  ← 주석(#, //) 라인은 자동 무시

인코딩
------
    encoding 미지정 → utf-8 → euc-kr → cp949 순서로 strict 시도,
    전부 실패하면 cp949+replace 로 손상 바이트만 치환해 읽는다.
    (한국 레거시 통신 환경의 ISO-8859/EUC-KR/혼합·손상 파일 대응)
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
        # section 스펙 파싱: "COMMON:ORACLE_SID=DB_SID" → ("COMMON", {키:별칭})
        self.want_section, self.want_keys = self._parse_section_spec(self.section)
        # encoding 미지정 → 자동 감지(FALLBACK_ENCODINGS 순서대로 시도)
        self.encoding = opts["encoding"] or None

    # ── 입력 경로 펼치기 ───────────────────────────────────────────
    def _expand_inputs(self):
        """
        입력 인자를 실제 파일 목록으로 펼친다.
          - 원격 경로(user@host:/path) → 그대로 (glob/디렉터리 처리 안 함)
          - 로컬 디렉터리   → 그 안의 *.cfg 전부
          - 로컬 와일드카드 → glob 검색
          - 로컬 파일       → 그대로
        """
        paths = []
        for item in self.config_paths:
            item = item.strip()
            if not item:
                continue
            if self._is_remote(item):
                paths.append(item)               # 원격은 그대로 (SSH 에서 처리)
            elif os.path.isdir(item):
                paths.extend(sorted(glob.glob(os.path.join(item, "*.cfg"))))
            elif any(ch in item for ch in "*?["):
                paths.extend(sorted(glob.glob(item)))
            else:
                paths.append(item)
        return paths

    # ── 원격(SSH) 경로 처리 ────────────────────────────────────────
    @staticmethod
    def _is_remote(path):
        """
        원격 경로인지 판별: 'user@host:/path' 또는 'host:/path' 형태.
        윈도우 드라이브 경로(C:\\..., C:/...)와 헷갈리지 않게,
        host 는 '@' 를 포함하거나, 점(.)을 포함하거나, 2글자 이상인 경우만 인정.
        (드라이브 문자는 보통 1글자라 C:/... 는 로컬로 처리됨)
        """
        m = re.match(r"^(?:[^@/\s]+@)?([A-Za-z0-9._\-]+):(/.*)$", path)
        if not m:
            return False
        host = m.group(1)
        # user@ 가 있으면 무조건 원격. 없으면 host 가 점 포함 or 2글자 이상일 때만.
        if "@" in path.split(":", 1)[0]:
            return True
        return ("." in host) or (len(host) >= 2)

    @staticmethod
    def _split_remote(path):
        """
        'user@host:/path' → (user, host, '/path')
        user 가 없으면 None (SSH 기본/환경변수 사용).
        """
        userhost, _, remote_path = path.partition(":")
        if "@" in userhost:
            user, _, host = userhost.partition("@")
        else:
            user, host = None, userhost
        return user or None, host, remote_path

    def _read_remote_bytes(self, path):
        """
        시스템의 ssh 명령으로 원격 파일 바이트를 읽어 반환.
        외부 라이브러리(paramiko, sshpass 등) 없이 표준 라이브러리만 사용하므로
        Python 3.6.8 환경에서도 추가 설치 없이 동작한다.

        인증 방식:
          - PG_ROBOT_SSH_PASS 가 있으면 → pty 로 ssh 의 password 프롬프트에 응답
                                          (sshpass 불필요)
          - 없으면                     → 키 인증(BatchMode) subprocess

        옵션:
          - 사용자  : 경로의 user@ → env PG_ROBOT_SSH_USER → OS 계정
          - 포트    : env PG_ROBOT_SSH_PORT (기본 22)
          - 키      : env PG_ROBOT_SSH_KEY (있으면 -i 로 지정)
          - 호스트키: 운영 편의를 위해 StrictHostKeyChecking=no

        파일 내용 추출:
          pty 에서는 프롬프트/에코가 출력에 섞이므로,
          원격 명령을 'echo MARKER; cat 파일; echo MARKER' 로 감싸
          두 마커 사이만 정확히 추출한다.
        """
        import shlex

        user, host, remote_path = self._split_remote(path)
        user = user or os.getenv("PG_ROBOT_SSH_USER") or os.getenv("USER") or "root"
        port = os.getenv("PG_ROBOT_SSH_PORT", "22")
        key_path = os.getenv("PG_ROBOT_SSH_KEY")
        password = os.getenv("PG_ROBOT_SSH_PASS")

        ssh_cmd = [
            "ssh",
            "-p", str(port),
            "-o", "StrictHostKeyChecking=no",
            "-o", "ConnectTimeout=10",
        ]
        if key_path:
            ssh_cmd += ["-i", os.path.expanduser(key_path)]

        print(f"[DynamicVars] SSH 접속: {user}@{host}:{port} → {remote_path}")

        if password:
            # 비밀번호 인증: pty 로 프롬프트에 응답. base64 마커로 내용 구분.
            marker = "__DVMARK_%d__" % os.getpid()
            # cat 결과를 base64 로 감싸 출력 → 바이너리/개행/터미널 변환 문제 회피
            remote = (
                "echo %s; base64 < %s; echo %s"
                % (marker, shlex.quote(remote_path), marker)
            )
            ssh_cmd += ["-o", "NumberOfPasswordPrompts=1",
                        "-tt",                       # pty 강제(프롬프트 받기)
                        "%s@%s" % (user, host), remote]
            raw = self._run_ssh_with_password(ssh_cmd, password)
            return self._extract_marked_base64(raw, marker, password)
        else:
            # 키 인증: 일반 subprocess, cat 바이너리 그대로
            import subprocess
            ssh_cmd += ["-o", "BatchMode=yes",
                        "%s@%s" % (user, host),
                        "cat -- " + shlex.quote(remote_path)]
            proc = subprocess.run(
                ssh_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=30,
            )
            if proc.returncode != 0:
                err = proc.stderr.decode("utf-8", "replace").strip()
                raise RuntimeError("ssh 실패(rc=%d): %s" % (proc.returncode, err))
            return proc.stdout

    @staticmethod
    def _run_ssh_with_password(cmd, password, timeout=30):
        """
        pty 로 ssh 를 실행하고 password 프롬프트가 뜨면 비밀번호를 써넣는다.
        ssh 의 전체 출력(bytes)을 반환. (sshpass 없이 표준 pty 만 사용)
        """
        import pty
        import select
        import re
        import time

        pid, fd = pty.fork()
        if pid == 0:  # 자식: ssh 실행
            try:
                os.execvp(cmd[0], cmd)
            except Exception:
                os._exit(127)
        # 부모: 출력 읽으며 프롬프트에 응답
        out = b""
        buf = b""
        sent = False
        deadline = time.time() + timeout
        prompt_re = re.compile(rb"[Pp]assword:|passphrase")
        try:
            while True:
                if time.time() > deadline:
                    break
                r, _, _ = select.select([fd], [], [], 0.5)
                if fd in r:
                    try:
                        chunk = os.read(fd, 4096)
                    except OSError:
                        break
                    if not chunk:
                        break
                    out += chunk
                    buf += chunk
                    if not sent and prompt_re.search(buf):
                        os.write(fd, password.encode() + b"\n")
                        sent = True
                        buf = b""
                else:
                    wpid, _ = os.waitpid(pid, os.WNOHANG)
                    if wpid != 0:
                        # 자식 종료: 남은 출력 흡수
                        while True:
                            r, _, _ = select.select([fd], [], [], 0.2)
                            if fd not in r:
                                break
                            try:
                                c = os.read(fd, 4096)
                            except OSError:
                                break
                            if not c:
                                break
                            out += c
                        break
        finally:
            try:
                os.close(fd)
            except OSError:
                pass
        return out

    @staticmethod
    def _extract_marked_base64(raw, marker, password=None):
        """
        ssh 출력(raw bytes)에서 두 marker 사이의 base64 를 찾아 디코딩.
        프롬프트 에코/CR 등이 섞여 있어도 마커 기준으로 정확히 추출한다.
        에러 메시지에 비밀번호가 에코됐을 수 있으니 마스킹한다.
        """
        import base64
        import re

        def _mask(text):
            if password:
                text = text.replace(password, "***")
            return text

        mark = marker.encode()
        # 마커가 2번 나타남: 사이의 내용만
        parts = raw.split(mark)
        if len(parts) < 3:
            # 인증 실패 등으로 마커가 안 나온 경우 → 에러 메시지 추출
            text = _mask(raw.decode("utf-8", "replace"))
            if re.search(r"[Pp]ermission denied|denied|No route|refused|timeout",
                         text):
                raise RuntimeError("ssh 비밀번호 인증/접속 실패: %s"
                                   % text.strip()[-200:])
            raise RuntimeError("원격 출력에서 파일 내용을 찾지 못함 "
                               "(마커 누락). 출력 일부: %s"
                               % text.strip()[-200:])
        b64 = parts[1]
        # base64 외 문자(개행, CR, 공백) 제거
        b64_clean = re.sub(rb"[^A-Za-z0-9+/=]", b"", b64)
        return base64.b64decode(b64_clean)

    def _read_bytes(self, path):
        """경로가 원격이면 SSH 로, 아니면 로컬 파일에서 바이트를 읽는다."""
        if self._is_remote(path):
            return self._read_remote_bytes(path)
        with open(path, "rb") as f:
            return f.read()

    # ── 인코딩 자동 감지 읽기 ──────────────────────────────────────
    def _read_text(self, path):
        """
        파일 바이트(_read_bytes: 로컬/원격 공통)를 읽어
        (텍스트, 사용된인코딩) 튜플 반환.

        encoding 이 지정돼 있으면 그것만 사용하고(손상 대비 replace),
        없으면 FALLBACK_ENCODINGS 를 순서대로 깨끗이(strict) 시도한다.

        모든 인코딩이 strict 로 실패하면(= 손상/혼합 바이트가 있으면),
        cp949 + errors='replace' 로 손상 바이트만 치환해 읽는다.
        설정값(KEY=VALUE)은 대부분 ASCII 라 영향이 없다.
        """
        data = self._read_bytes(path)

        if self.encoding:
            return data.decode(self.encoding, errors="replace"), self.encoding

        for enc in self.FALLBACK_ENCODINGS:
            try:
                text = data.decode(enc)
                if enc != "utf-8":
                    print(f"[DynamicVars] 인코딩 자동감지: {enc} ({path})")
                return text, enc
            except UnicodeDecodeError:
                continue

        # 전부 실패 → 손상/혼합 바이트가 섞인 파일. replace 로 강제 디코딩.
        print(f"[DynamicVars] ⚠ 인코딩 strict 실패 → cp949/replace 로 읽음 "
              f"(손상 바이트 치환, 설정값엔 영향 적음): {path}")
        return data.decode("cp949", errors="replace"), "cp949(replace)"

    # ── 이름 정규화 / 파일명 → 접두사 ──────────────────────────────
    @staticmethod
    def _normalize(name):
        """문자열을 변수명 조각으로 정규화: 대문자화, 영숫자 외는 '_'."""
        return re.sub(r"[^0-9A-Za-z]+", "_", name).upper().strip("_")

    @classmethod
    def _parse_section_spec(cls, spec):
        """
        section= 스펙을 (섹션명, 키별칭맵) 으로 파싱한다.

          ""                          → (None, None)
                                         전체 섹션, 전체 키 (접두사 적용)
          "COMMON"                    → ("COMMON", None)
                                         COMMON 섹션 전체 키 (접두사 적용)
          "COMMON:ORACLE_SID,PORT"    → ("COMMON", {"ORACLE_SID":"ORACLE_SID",
                                                     "PORT":"PORT"})
                                         그 키들만, 변수명 = 키 이름(접두사 없음)
          "COMMON:ORACLE_SID=DB_SID"  → ("COMMON", {"ORACLE_SID":"DB_SID"})
                                         그 키만, 변수명 = 별칭 DB_SID(접두사 없음)
          혼합도 가능:
          "COMMON:ORACLE_SID=DB_SID,PORT"
                                      → ("COMMON", {"ORACLE_SID":"DB_SID",
                                                    "PORT":"PORT"})

        반환 맵의 key 는 매칭용(_normalize 된 원본 키),
        value 는 최종 변수명(_normalize 된 별칭 또는 키 이름).
        키 맵이 None 이면 키 필터 없음(= 전체, 접두사 적용).
        """
        if not spec:
            return None, None
        sec_part, sep, keys_part = spec.partition(":")
        section = cls._normalize(sec_part) if sec_part else None
        if not (sep and keys_part.strip()):
            return section, None

        key_map = {}
        for item in keys_part.split(","):
            item = item.strip()
            if not item:
                continue
            # "원본키=별칭" 또는 "원본키"
            raw_key, eq, alias = item.partition("=")
            k = cls._normalize(raw_key)
            if not k:
                continue
            # 별칭 주면 별칭, 안 주면 키 이름 그대로
            key_map[k] = cls._normalize(alias) if (eq and alias.strip()) else k
        return section, (key_map or None)

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
          - section= 로 섹션/키 필터 및 변수명 지정:
              미지정              → 전체 섹션·전체 키 (접두사 적용)
              section=COMMON      → COMMON 섹션 전체 (접두사 적용)
              section=COMMON:K1,K2→ 그 키들만, 변수명=키 이름(접두사 없음)
              section=COMMON:K1=A → 그 키만, 변수명=별칭 A(접두사 없음)

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
        remote = self._is_remote(path)
        if not remote and not os.path.exists(path):
            print(f"[DynamicVars] config 파일 없음, 건너뜀: {path}")
            return one

        try:
            text, _ = self._read_text(path)
        except Exception as e:
            # 원격 접속 실패/파일 없음 등에서 전체 테스트가 죽지 않도록 건너뜀
            print(f"[DynamicVars] ⚠ 읽기 실패, 건너뜀 ({type(e).__name__}: {e}): {path}")
            return one
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
            # 키 필터 (section=COMMON:KEY... 형태일 때만 적용)
            if want_keys is not None and key_norm not in want_keys:
                continue

            seen_sections.add(cur_section)
            if want_keys is not None:
                # 키를 명시적으로 지정한 경우:
                # 변수명 = 별칭(or 키 이름) 그대로, 파일/섹션 접두사 안 붙임
                var_name = want_keys[key_norm]
            else:
                # 전체/섹션 단위: 기존대로 접두사 적용
                parts = [p for p in (file_prefix, cur_section, key_norm) if p]
                var_name = "_".join(parts)
            one[var_name] = value.strip()

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
