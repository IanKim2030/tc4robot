# -*- coding: utf-8 -*-
"""
UPM SFTP 수신 서버 — FtpServerHelper.py 의 대안 전송방식.

PG 쪽 FTP 타겟 설정(SYSTEM_ID_04=UPM-R0, 2026-10-28 UPMROB 에서 변경)의 `USE_SFTP_04` 항목이 2026-10-22
확인 당시 `N`(평문 FTP)이라 주 구현은 FtpServerHelper.py(pyftpdlib) 다. 이
모듈은 다른 환경(stg/prd)에서 그 값이 `Y` 로 바뀌는 경우에 대비한 SFTP
버전이다 — `${UPM_FTP_USE_SFTP}` 를 True 로 두면 FtpServerHelper.ftp_server_start()
가 FtpServer 대신 이 SftpServer 를 띄운다(upm_variables.robot 참조).

★ pyftpdlib 같은 성숙한 SFTP **서버** 전용 라이브러리가 없어, paramiko 의
  저수준 SFTPServerInterface 를 직접 구현한다 — paramiko 공식 데모
  (demos/demo_sftp.py + stub_sftp.py)와 같은 구조: 로컬 디렉터리 하나를
  가상 루트로 매핑하는 최소 구현이다.

★ FtpServer 와 같은 duck-typing 계약을 지킨다 — files()/errors()/
  connections()/clear()/stop()/is_running() 메서드만 맞으면 FtpServerHelper.py
  의 ftp_list/ftp_wait/ftp_errors/ftp_connections/ftp_clear/ftp_server_stop/
  ftp_server_is_running 이 전송방식과 무관하게 그대로 동작한다. 그래서
  upm_keywords.robot 은 FTP 든 SFTP 든 같은 `Ftp.Ftp *` 키워드만 쓴다.

★ remote_path 해석도 FtpServerHelper.py 와 동일하게 "가상 루트 기준 상대
  경로"로 맞춘다 — PG 가 (FTP 와 마찬가지로) 로그인 후 REMOTE_PATH_04 로
  절대경로 접근을 한다고 가정하고, 그 서브디렉터리를 미리 만들어 둔다.

★ pyftpdlib 처럼 지연 임포트한다 — ${UPM_FTP_USE_SFTP}=False(기본)면
  paramiko 가 없어도 슈트가 돈다.

⚠ 2026-10-22 기준 **실제로 구동해 검증하지 못했다** — 이 작업 환경에 로컬
  Python 이 없어 `python -c "import paramiko"` 조차 돌릴 수 없었다. PG 가
  실제로 USE_SFTP_04=Y 로 붙는 환경을 쓰게 되면, 그 전에 반드시 로컬에서
  (예: 표준 `sftp`/`paramiko.SFTPClient` 로) 업로드 왕복을 먼저 확인할 것
  (CLAUDE.md "--dryrun 은 Python 을 실행하지 않는다" 규칙과 같은 이유).
"""

import os
import socket
import tempfile
import threading
import time
import traceback

_paramiko = None
_SFTP_OK = 0  # paramiko.SFTP_OK 값(SFTP 프로토콜 상 고정값) — 임포트 의존 줄이려 직접 둔다


def _load_paramiko():
    """paramiko 를 한 번만 임포트해 캐시한다. 없으면 안내 메시지로 실패."""
    global _paramiko
    if _paramiko is None:
        try:
            import paramiko
        except ImportError as e:
            raise RuntimeError(
                'UPM SFTP 수신 서버에는 paramiko 패키지가 필요합니다 — pip install paramiko '
                '(또는 pip install -r requirements.txt). '
                'SFTP 가 필요 없으면 UPM_FTP_USE_SFTP 를 False 로 두면 됩니다(기본값). '
                '원본 오류: %s' % e)
        _paramiko = paramiko
    return _paramiko


class SftpServer(object):
    def __init__(self, port, host='0.0.0.0', user='upm', password='upm',
                 directory=None, remote_path=None):
        self.host = host
        self.port = int(port)
        self.user = user
        self.password = password
        self.directory = os.path.abspath(directory or tempfile.mkdtemp(prefix='upm_sftp_'))
        self.remote_path = remote_path
        self._host_key = None
        self._sock = None
        self._accept_thread = None
        self._stopping = threading.Event()
        self._lock = threading.Lock()
        self._transports = []     # 접속 중인 Transport — stop() 에서 강제로 닫는다
        self._files = []          # 수신 완료 이력 — FtpServer._files 와 같은 스키마
        self._errors = []
        self._connections = []    # 접속 이력 — clear() 해도 안 지운다(FtpServer 와 같은 계약)

    def start(self):
        paramiko = _load_paramiko()

        if self.remote_path:
            rel = self.remote_path.lstrip('/').replace('/', os.sep)
            os.makedirs(os.path.join(self.directory, rel), exist_ok=True)

        self._host_key = paramiko.RSAKey.generate(2048)

        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.bind((self.host, self.port))
        self._sock.listen(5)
        self._sock.settimeout(1.0)  # accept 루프가 stop() 신호를 주기적으로 보게

        self._accept_thread = threading.Thread(target=self._accept_loop, daemon=True)
        self._accept_thread.start()
        return self

    def _accept_loop(self):
        while not self._stopping.is_set():
            try:
                conn, addr = self._sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            threading.Thread(target=self._handle_client, args=(conn, addr), daemon=True).start()

    def _handle_client(self, conn, addr):
        paramiko = _load_paramiko()
        outer = self
        peer, peer_port = addr[0], addr[1]
        root = outer.directory

        class _Server(paramiko.ServerInterface):
            def check_channel_request(self, kind, chanid):
                if kind == 'session':
                    return paramiko.OPEN_SUCCEEDED
                return paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

            def get_allowed_auths(self, username):
                return 'password'

            def check_auth_password(self, username, password):
                if username == outer.user and password == outer.password:
                    outer._note_connect(peer, peer_port)
                    return paramiko.AUTH_SUCCESSFUL
                outer._note_error('SFTP 로그인 실패 user=%s peer=%s' % (username, peer))
                return paramiko.AUTH_FAILED

        class _Handle(paramiko.SFTPHandle):
            def stat(self):
                try:
                    return paramiko.SFTPAttributes.from_stat(os.fstat(self.readfile.fileno()))
                except OSError as e:
                    return paramiko.SFTPServer.convert_errno(e.errno)

            def chattr(self, attr):
                try:
                    paramiko.SFTPServer.set_file_attr(self.filename, attr)
                    return _SFTP_OK
                except OSError as e:
                    return paramiko.SFTPServer.convert_errno(e.errno)

            def close(self):
                result = super(_Handle, self).close()
                # 업로드(쓰기) 핸들이 닫히는 시점 = 전송 완료 — pyftpdlib 의
                # on_file_received 와 같은 지점이다.
                if getattr(self, '_is_write', False):
                    try:
                        outer._note_file(self.filename, peer, peer_port)
                    except Exception:
                        outer._note_error(traceback.format_exc())
                return result

        class _Sftp(paramiko.SFTPServerInterface):
            def _realpath(self, path):
                # canonicalize() 는 유닉스 스타일 '/' 로 돌려준다 — os.sep 가 다른
                # 플랫폼(Windows)에서도 os.* 호출이 먹게 normpath 로 정리한다.
                return os.path.normpath(root + self.canonicalize(path))

            def list_folder(self, path):
                p = self._realpath(path)
                try:
                    out = []
                    for fname in os.listdir(p):
                        attr = paramiko.SFTPAttributes.from_stat(os.stat(os.path.join(p, fname)))
                        attr.filename = fname
                        out.append(attr)
                    return out
                except OSError as e:
                    return paramiko.SFTPServer.convert_errno(e.errno)

            def stat(self, path):
                p = self._realpath(path)
                try:
                    return paramiko.SFTPAttributes.from_stat(os.stat(p))
                except OSError as e:
                    return paramiko.SFTPServer.convert_errno(e.errno)

            def lstat(self, path):
                p = self._realpath(path)
                try:
                    return paramiko.SFTPAttributes.from_stat(os.lstat(p))
                except OSError as e:
                    return paramiko.SFTPServer.convert_errno(e.errno)

            def open(self, path, flags, attr):
                p = self._realpath(path)
                try:
                    binary_flag = getattr(os, 'O_BINARY', 0)
                    mode = getattr(attr, 'st_mode', None)
                    fd = os.open(p, flags | binary_flag, mode if mode is not None else 0o666)
                except OSError as e:
                    return paramiko.SFTPServer.convert_errno(e.errno)
                if flags & os.O_WRONLY:
                    fstr = 'ab' if (flags & os.O_APPEND) else 'wb'
                elif flags & os.O_RDWR:
                    fstr = 'a+b' if (flags & os.O_APPEND) else 'r+b'
                else:
                    fstr = 'rb'
                try:
                    f = os.fdopen(fd, fstr)
                except OSError as e:
                    return paramiko.SFTPServer.convert_errno(e.errno)
                handle = _Handle(flags)
                handle.filename = p
                handle.readfile = f
                handle.writefile = f
                handle._is_write = bool(flags & (os.O_WRONLY | os.O_RDWR))
                return handle

            def remove(self, path):
                try:
                    os.remove(self._realpath(path))
                except OSError as e:
                    return paramiko.SFTPServer.convert_errno(e.errno)
                return _SFTP_OK

            def rename(self, oldpath, newpath):
                try:
                    os.rename(self._realpath(oldpath), self._realpath(newpath))
                except OSError as e:
                    return paramiko.SFTPServer.convert_errno(e.errno)
                return _SFTP_OK

            def mkdir(self, path, attr):
                try:
                    os.mkdir(self._realpath(path))
                except OSError as e:
                    return paramiko.SFTPServer.convert_errno(e.errno)
                return _SFTP_OK

            def rmdir(self, path):
                try:
                    os.rmdir(self._realpath(path))
                except OSError as e:
                    return paramiko.SFTPServer.convert_errno(e.errno)
                return _SFTP_OK

            def chattr(self, path, attr):
                try:
                    paramiko.SFTPServer.set_file_attr(self._realpath(path), attr)
                except OSError as e:
                    return paramiko.SFTPServer.convert_errno(e.errno)
                return _SFTP_OK

        transport = None
        try:
            transport = paramiko.Transport(conn)
            with self._lock:
                self._transports.append(transport)
            transport.add_server_key(self._host_key)
            transport.set_subsystem_handler('sftp', paramiko.SFTPServer, sftp_si=_Sftp)
            transport.start_server(server=_Server())
            # demo_sftp.py 와 같은 패턴 — 세션 채널을 받아 두지 않으면 접속
            # 이력에만 남고 subsystem 요청이 실제로 안 올 수 있다(미검증 영역,
            # 모듈 docstring 의 ⚠ 참조).
            chan = transport.accept(20)
            if chan is None:
                outer._note_error('SFTP 채널 열기 실패(타임아웃) peer=%s' % peer)
                return
            while transport.is_active() and not outer._stopping.is_set():
                time.sleep(0.5)
        except Exception:
            outer._note_error(traceback.format_exc())
        finally:
            if transport is not None:
                with self._lock:
                    if transport in self._transports:
                        self._transports.remove(transport)
                try:
                    transport.close()
                except Exception:
                    pass

    def stop(self):
        self._stopping.set()
        if self._sock is not None:
            try:
                self._sock.close()
            except Exception:
                pass
        with self._lock:
            transports = list(self._transports)
        for t in transports:
            try:
                t.close()
            except Exception:
                pass
        if self._accept_thread is not None:
            self._accept_thread.join(timeout=3)
        self._sock = None
        self._accept_thread = None

    def is_running(self):
        return self._accept_thread is not None and self._accept_thread.is_alive()

    def _note_connect(self, peer, peer_port):
        with self._lock:
            self._connections.append({'peer': peer, 'port': peer_port, 'at': time.time()})

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
        """FtpServer.clear() 와 같은 계약 — 수신 이력·오류만 비우고 접속 이력은 남긴다."""
        with self._lock:
            self._files = []
            self._errors = []
