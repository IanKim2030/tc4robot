# -*- coding: utf-8 -*-
"""
UPM FTP 수신 서버 — PG → 도구 방향 파일 수신(0x0c Subs-Sync-Response 의 fileinfo 대응).

PG 는 UPM 의 Subs-Sync(0x0b) 요청에 대한 0x0c 응답에 "fileinfo"를 실어 보낼 수
있다(docs/callflow/upm_callflow.md, tests/upm/upm_tests.robot). 이 fileinfo 가
정확히 무엇을 의미하는지(파일명/크기/전송 방식 등)는 **⚠ 미확인**이다 — 규격
6.6.1/6.6.2 원문이 이 리포에 없고, 전체 grep 결과 다른 언급도 없다(2026-10-22).

"PG 가 UPM(도구)으로 파일을 보낸다"는 PG 가 FTP Client 로 도구에 접속해 Push
한다는 뜻으로 해석했다(사용자 확인) — 그래서 도구가 FTP **서버** 역할을 한다.
서버의 host/port/계정/업로드 디렉터리는 fileinfo 내용과 무관하게 Robot 변수
(upm_variables.robot 의 ${UPM_FTP_*})로 **고정 설정**한다 — fileinfo 를 파싱해
접속 정보를 derive 하지 않는다(파싱 대상 자체가 미확인이기 때문).

★ 왜 직접 구현하지 않는가
  HttpNotiServer.py 는 h2c 서버를 표준 라이브러리가 없어 직접 만들었지만, FTP 는
  사정이 다르다 — PASV 데이터 채널 처리 등 프로토콜 자체가 손으로 다시 짜면
  버그가 나기 쉽고, 성숙한 순수 Python 구현(pyftpdlib)이 이미 있다. 그래서 여기는
  pyftpdlib 를 감싸기만 한다.

★ pyftpdlib 는 지연 임포트한다 (HttpNotiServer.py 의 h2 지연 임포트와 같은 이유)
  최상단에서 import 하면 없는 환경에서 "No keyword with name 'Ftp.Ftp Server
  Start' found" 로만 보고돼 진짜 원인(미설치)이 드러나지 않는다. 그래서 서버를
  실제로 띄울 때만 부른다 — ${UPM_FTP_ENABLE}=False 면 pyftpdlib 없이도 슈트가
  돈다.
"""

import os
import tempfile
import threading
import time
import traceback

_pyftpdlib = None


def _load_pyftpdlib():
    """pyftpdlib 3종을 한 번만 임포트해 캐시한다. 없으면 안내 메시지로 실패."""
    global _pyftpdlib
    if _pyftpdlib is None:
        try:
            import pyftpdlib.authorizers
            import pyftpdlib.handlers
            import pyftpdlib.servers
        except ImportError as e:
            raise RuntimeError(
                'UPM FTP 수신 서버에는 pyftpdlib 패키지가 필요합니다 — pip install pyftpdlib '
                '(또는 pip install -r requirements.txt). '
                'FTP 파일 수신 검증이 필요 없으면 UPM_FTP_ENABLE 을 False 로 두면 됩니다. '
                '원본 오류: %s' % e)
        _pyftpdlib = (pyftpdlib.authorizers, pyftpdlib.handlers, pyftpdlib.servers)
    return _pyftpdlib


class FtpServer(object):
    def __init__(self, port, host='0.0.0.0', user='pg', password='pg1234',
                 directory=None, passive_ports=None, masquerade_address=None,
                 remote_path=None):
        self.host = host
        self.port = int(port)
        self.user = user
        self.password = password
        # 비우면 임시 디렉터리를 만든다 — 호출부가 업로드 경로를 몰라도 바로 쓸 수 있다.
        self.directory = directory or tempfile.mkdtemp(prefix='upm_ftp_')
        self.passive_ports = passive_ports
        self.masquerade_address = masquerade_address
        # PG 가 로그인 후 CWD 로 들어오는 경로(예: /PG/FTP/UPM-ROBOT, PG 쪽 FTP
        # 타겟 설정 REMOTE_PATH_04 로 확인됨, 2026-10-22). pyftpdlib 는 이걸
        # **FTP 가상 루트(=self.directory) 기준 상대 경로**로 해석하므로, 그
        # 서브디렉터리가 실제로 없으면 CWD 자체가 550 으로 거부된다 — 그래서
        # 여기서 미리 만들어 둔다.
        self.remote_path = remote_path
        self._server = None
        self._thread = None
        self._lock = threading.Lock()
        self._files = []          # 수신 완료 이력 (dict: path/filename/peer/size/received_at)
        self._errors = []         # 미완료 수신·로그인 실패 등 진단용
        self._connections = []    # 접속 이력 — **요청과 별개로** 쌓이고 clear() 해도 안 지운다
        # HttpNotiServer.NotiServer._conns 와 같은 이유: "붙었는가"와 "보냈는가"는
        # 다른 사건이고, 슈트 중간에 PG 가 끊겨도 이력은 진단에 남아야 한다.

    def start(self):
        auth_mod, handlers_mod, servers_mod = _load_pyftpdlib()

        if self.remote_path:
            # 선행 '/' 를 떼고 self.directory 밑에 그대로 만든다 — FTP 가상
            # 루트가 self.directory 이므로 PG 의 절대경로 CWD 가 바로 먹는다.
            rel = self.remote_path.lstrip('/').replace('/', os.sep)
            os.makedirs(os.path.join(self.directory, rel), exist_ok=True)

        _authorizer = auth_mod.DummyAuthorizer()
        _authorizer.add_user(self.user, self.password, self.directory,
                              perm='elradfmwMT')

        outer = self

        # pyftpdlib 는 핸들러를 **클래스**로 받는다(인스턴스가 아니다) — 그래서
        # start() 호출 시점에 이 FtpServer 인스턴스(outer)를 클로저로 가두는
        # 서브클래스를 그때그때 만든다. 콜백에서 outer 를 통해 수신 이력을 쌓는다.
        #
        # ★ 클래스 바디에서 `authorizer = authorizer` 처럼 **같은 이름으로** 바깥
        #   스코프 값을 읽으면 NameError 가 난다 — 클래스 바디는 함수와 달리
        #   자유 변수를 클로저로 못 받고, 같은 이름이 그 바디 안에서 대입되는
        #   순간 컴파일러가 "로컬"로 취급해 버린다(실제로 재현된 버그, 2026-10-22).
        #   그래서 바깥 변수 이름을 `_authorizer` 로 달리 둬 단순 읽기로 만든다.
        class _CaptureHandler(handlers_mod.FTPHandler):
            authorizer = _authorizer
            banner = 'tc4robot UPM FTP'

            def on_connect(self):
                outer._note_connect(self.remote_ip, self.remote_port)

            def on_disconnect(self):
                outer._note_disconnect(self.remote_ip, self.remote_port)

            def on_login_failed(self, username, password):
                outer._note_error(
                    'FTP 로그인 실패 user=%s peer=%s' % (username, self.remote_ip))

            def on_file_received(self, file):
                outer._note_file(file, self.remote_ip, self.remote_port)

            def on_incomplete_file_received(self, file):
                outer._note_error(
                    '업로드 미완료(incomplete) 파일: %s (peer=%s)'
                    % (file, self.remote_ip))

        if self.passive_ports:
            _CaptureHandler.passive_ports = self.passive_ports
        if self.masquerade_address:
            _CaptureHandler.masquerade_address = self.masquerade_address

        self._server = servers_mod.FTPServer((self.host, self.port), _CaptureHandler)
        self._thread = threading.Thread(target=self._serve, daemon=True)
        self._thread.start()
        return self

    def _serve(self):
        try:
            # serve_forever 는 close_all() 로 소켓맵이 비워질 때까지 블로킹한다
            # (pyftpdlib 공식 문서가 권장하는, 다른 스레드에서 멈추는 방법).
            self._server.serve_forever()
        except Exception:
            self._note_error(traceback.format_exc())

    def stop(self):
        if self._server is not None:
            try:
                self._server.close_all()
            except Exception:
                pass
        if self._thread is not None:
            self._thread.join(timeout=3)
        self._server = None
        self._thread = None

    def is_running(self):
        return self._thread is not None and self._thread.is_alive()

    def _note_connect(self, peer, peer_port):
        with self._lock:
            self._connections.append({'peer': peer, 'port': peer_port, 'at': time.time()})

    def _note_disconnect(self, peer, peer_port):
        pass  # 접속 이력은 "붙음"만 기록한다 — NotiServer 의 _conns 와 같은 범위.

    def _note_file(self, path, peer, peer_port):
        with self._lock:
            self._files.append({
                'path': path,
                'filename': os.path.basename(path),
                'peer': peer,
                'peer_port': peer_port,
                'size': os.path.getsize(path) if os.path.exists(path) else 0,
                'received_at': time.time(),
            })

    def _note_error(self, msg):
        with self._lock:
            self._errors.append(msg)

    def files(self):
        with self._lock:
            return list(self._files)

    def errors(self):
        with self._lock:
            return list(self._errors)

    def connections(self):
        with self._lock:
            return list(self._connections)

    def clear(self):
        """수신 이력·오류만 비운다. **접속 이력은 남긴다** — HttpNotiServer.NotiServer.clear()
        와 같은 이유: TC 마다 초기화하면 "PG 가 붙어 있다"는 사실까지 지워지기 때문이다."""
        with self._lock:
            self._files = []
            self._errors = []


# ══════════════════════════════════════════════════════════════════
# Robot 이 직접 부르는 함수들 (라이브러리 인터페이스)
# ══════════════════════════════════════════════════════════════════

def ftp_server_start(port, host='0.0.0.0', user='upm', password='upm1234',
                      directory=None, passive_ports=None, masquerade_address=None,
                      remote_path=None, use_sftp=False):
    """FTP(또는 SFTP) 수신 서버 기동 → 서버 핸들 반환. 핸들은 Suite Variable 로 들고 다닌다.

    use_sftp=True 면 SftpServerHelper.SftpServer 를 대신 띄운다 — PG 설정의
    USE_SFTP_04 가 Y 인 환경 대비(2026-10-22 확인 당시엔 N, upm_variables.robot
    참조). 반환 핸들은 files()/errors()/connections()/clear()/stop()/
    is_running() 을 똑같이 구현하므로(duck-typing), 아래 ftp_list/ftp_wait/
    ftp_errors/ftp_connections/ftp_clear/ftp_server_stop/ftp_server_is_running
    은 어느 쪽이 떠 있든 그대로 쓸 수 있다 — 호출부(upm_keywords.robot)가
    FTP 와 SFTP 를 구분할 필요가 없다.
    """
    if use_sftp:
        import SftpServerHelper
        srv = SftpServerHelper.SftpServer(port, host, user, password,
                                           directory or None, remote_path or None)
        return srv.start()
    ports = _parse_port_range(passive_ports)
    srv = FtpServer(port, host, user, password, directory or None,
                     ports, masquerade_address or None, remote_path or None)
    return srv.start()


def ftp_server_stop(server):
    """서버 종료. None 이면 아무것도 하지 않는다."""
    if server is not None:
        server.stop()


def ftp_server_is_running(server):
    return bool(server is not None and server.is_running())


def ftp_clear(server):
    """쌓인 수신 이력·오류를 비운다. TC 시작 전에 불러 이전 TC 의 파일과 섞이지 않게 한다."""
    if server is not None:
        server.clear()


def ftp_count(server, filename_contains=None, since=None):
    """수신 건수. filename_contains / since 로 거를 수 있다."""
    return len(ftp_list(server, filename_contains, since))


def ftp_list(server, filename_contains=None, since=None):
    """수신한 파일 목록(dict 리스트: path/filename/peer/peer_port/size/received_at)."""
    if server is None:
        return []
    files = server.files()
    if filename_contains:
        files = [f for f in files if filename_contains in f['filename']]
    if since is not None:
        s = float(since)
        files = [f for f in files if f['received_at'] >= s]
    return files


def ftp_now():
    """현재 epoch 시각. ftp_wait/ftp_list 의 since 기준점으로 쓴다."""
    return time.time()


def ftp_errors(server):
    """수신 중 난 오류(로그인 실패·미완료 업로드 등) 문자열 목록."""
    return server.errors() if server is not None else []


def ftp_connections(server, since=None):
    """FTP 제어 접속 이력 목록 — dict(peer, port, at). 수신 건수와 별개다.
    since 를 주면 그 시각 이후 접속만 본다(noti_list 의 since= 와 같은 용도)."""
    if server is None:
        return []
    conns = server.connections()
    if since is not None:
        s = float(since)
        conns = [c for c in conns if c['at'] >= s]
    return conns


def ftp_wait(server, timeout=30, filename_contains=None, since=None, poll=0.5,
             min_count=1):
    """
    조건에 맞는 파일이 min_count 건 이상 들어올 때까지 기다렸다가 그 목록을
    반환한다. 시간 안에 min_count 를 못 채우면 **그때까지 모인 것까지 포함해**
    빈 리스트가 아니라 **마지막으로 확인한 목록**을 돌려준다 — 몇 건이 왔는지를
    호출부가 실패 메시지에 쓸 수 있게 하기 위함이다(실패 판정 자체는 호출한
    키워드가 "min_count 를 채웠는가"로 한다).

    UPM Subs-Sync 는 데이터 파일 + FIN 파일, **2개**를 보낸다(사용자 확인,
    2026-10-22) — 그래서 min_count 기본값을 1로 둔 채 호출부(upm_keywords.robot)
    에서 2를 넘긴다.
    """
    deadline = time.time() + _seconds(timeout)
    step = _seconds(poll)
    found = []
    while True:
        found = ftp_list(server, filename_contains, since)
        if len(found) >= min_count:
            return found
        if time.time() >= deadline:
            return found
        time.sleep(step)


def _parse_port_range(v):
    """'60000-60050' 같은 문자열을 range 로. 비어 있으면 None(pyftpdlib 기본 동작)."""
    if not v:
        return None
    if isinstance(v, range):
        return v
    s = str(v).strip()
    if '-' not in s:
        return None
    lo, hi = s.split('-', 1)
    return range(int(lo), int(hi) + 1)


def _seconds(v):
    """'30s' / '1.5' / 30 을 초(float)로."""
    if isinstance(v, (int, float)):
        return float(v)
    s = str(v).strip().lower()
    if s.endswith('ms'):
        return float(s[:-2]) / 1000.0
    if s.endswith('s'):
        return float(s[:-1])
    if s.endswith('m'):
        return float(s[:-1]) * 60.0
    return float(s)
