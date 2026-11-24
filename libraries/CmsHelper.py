# -*- coding: utf-8 -*-
"""
CmsHelper.py — CMSWEB(SKT 통합 구성관리 시스템) 시뮬레이터용 메시지·파일 헬퍼
==========================================================================

도구가 **CMSWEB 서버** 역할을 한다. PG 의 CMS 프로세스(`CmsMain`, 프로세스명
`CMS201`)가 `PG_V2.cfg [CMS] CMSWEB_ADDR:CMSWEB_PORT` 로 접속해 온다.
근거: CMS 연동 규격서 v1.9 + PG 소스 `Online/CMS.vGL.SFTP/CCMSWeb.cpp`.

[전문 — 규격 2.2]
  Header 13B = Cmd 3B (REG/DRG/HBC/NTI/ANS) + Length 10B (ASCII, `%010d`)
  Body       = JSON, EUC-KR. PG 는 본문 앞에 `\\n` 을 붙여 보낸다.

[★ JSON 은 공백 없이(compact) 보내야 한다 — PG 파서 제약]
  PG 의 `CParseJson::GetValue` 는 진짜 JSON 파서가 아니다. 키를 strstr 로 찾고,
  `:` **바로 다음 글자**가 `"`(문자열) 또는 `["`(배열)인지 본다. `"key": "v"` 처럼
  콜론 뒤에 공백이 있으면 값을 못 읽고 "Wrong Value" 로 처리한다. 그래서 이 모듈은
  항상 `separators=(',', ':')` 로 직렬화한다. COLUMN_DATA 는 추가로 `["/` 로
  시작해야 한다(경로가 `/` 로 시작).

[메시지 방향 — CCMSWeb::Run]
  PG → 도구 : REG(접속 직후), HBC(도구 HBC 에 대한 응답), ANS(NTI 수신 확인), DRG(종료)
  도구 → PG : REG 결과(REG_OK/REG_NOK), HBC(먼저 보낸다), NTI(파일 알림), DRG 결과
  · PG 는 NTI 를 받으면 **필드 검증 전에** ANS 부터 보낸다.
  · `CMSWEB_TIMEOUT` 초 동안 아무것도 못 받으면 PG 가 끊는다 → 도구가 HBC 로 깨운다.

[NTI 파일 처리 — PG 쪽]
  COLUMN_DATA[0] = "/<dir>/<파일>.dat" → SFTP GET → 같은 dir 에 빈 `.FIN` PUT
  ★ GET 만 `CMS_SFTP_PORT`(이 도구의 SFTP 시뮬레이터)로 간다. FIN PUT(`SFTPUploader`)은
    `.port()` 를 주지 않아 SFTP 기본 포트 22 — 도구 호스트의 **실제 sshd** — 로 간다.
    그래서 FIN 은 도구 호스트 실제 파일시스템의 `<dir>` 에 실제 OS 계정으로 떨어진다.
    이 모듈은 그 FIN 을 SFTP 클라이언트로 sshd 에 붙어 확인한다(cms_fin_ssh_*).
    FIN PUT 이 실패하면 PG 는 RunSFtpCMS → Run() 이 false 로 끝나 CmsMain 이 종료된다.

[FTP / SFTP 선택 — CCMSEnv::ReadConfig, CCMSWeb::Run]
  [CMS] CMSWEB_SFTP 첫 글자가 'N' 이면 FTP(RunFtpCMS), 아니면(기본 Y) SFTP(RunSFtpCMS).
  [CMS] NWDAF_SFTP 도 같은 규칙으로 SC 전달을 FTP(RunFtpSC)/SFTP(RunSFtpSC) 중에 고른다.
  포트: CMS SFTP = [CMS] CMS_SFTP_PORT(없으면 22), CMS FTP = **21 고정**(소스 FTP_PORT,
        cfg 키 없음), SC SFTP = [CMS] NWDAF_SFTP_PORT(없으면 22), SC FTP = [CMS] NWDAF_FTP_PORT
        (없으면 21). 계정은 SFTP 와 같다(CMSWEB 다운로드 계정 / SC 업로드 계정).
  FTP 모드의 FIN 은 GET 과 **같은 FTP 세션**에서 CWD 한 디렉터리로 PUT 한다 → 도구의 FTP
  서버로 온다(실제 sshd 로 가지 않는다). FTP 모드는 FIN PUT 실패를 로그만 남긴다.
  PG 는 FTP 에서 TYPE A(SetAscii)를 쓴다 — 그래서 시험 파일에는 줄바꿈을 넣지 않는다
  (ASCII 변환으로 크기가 바뀌면 PG 의 크기 비교가 틀어진다).

[SC(NWDAF) 전달 — T_ZONE_LIST.SC_FTP_YN='Y' 인 serviceCode, CCMSWeb::RunSFtpSC / RunFtpSC]
  위 GET·FIN 이 끝난 뒤 PG 가 받은 파일(이름 바뀐 `<이름>_<일시>.dat`)과 빈
  `<이름>_<일시>.FIN` 을 `sftp://[SC] SC_PRIIP:[CMS] NWDAF_SFTP_PORT[CMS] SC_PATH/<파일>` 로
  올린다(계정 scUserId_/scPassWd_). 그 뒤 setData 없이 끝난다(T_CMSWEB_ZONE 행 없음).
  이 모듈의 SC 수신 서버(cms_sc_sftp_start)는 가상 경로 SC_PATH 를 실제 디렉터리
  (CMS_SC_UPLOAD_DIR)에 마운트해 받는다.
  파일명이 `<이름>_<YYYYMMDDHHMISS>_<크기>.dat` 면 `<이름>_<일시>.dat` 로 바꾸고
  실제 크기와 비교한다(다르면 3회 재시도 후 실패). FIN 이름:
  `<serviceCode>_<NTI dateTime 숫자만>_<GROUP><KEY>_<YYYYMMDDhhmmss>.FIN`

이 모듈은 Python 3.6 에서도 돌아야 한다(시험 호스트 192.168.15.142).
"""

import datetime
import json
import os
import re
import socket
import threading
import time

_HEADER_SIZE = 13
_CMD_SIZE = 3
_COMMANDS = ('REG', 'DRG', 'HBC', 'NTI', 'ANS')
_ENCODING = 'euc-kr'
_SFTP_PWD_ENV = 'PG_PWD_CMS_SFTP'                 # 시뮬레이터 SFTP(GET) 비밀번호 — 필수
_SC_PWD_ENV = 'PG_PWD_CMS_SFTP_UPLOAD'           # SC 수신 SFTP(업로드) 비밀번호 — SC 전달 시험에 필수
_FIN_PWD_ENV = 'PG_PWD_CMS_FIN_SSH'              # 도구 호스트 실제 sshd 의 FIN 계정(pg) 비밀번호

_seq_lock = threading.Lock()
_seq = [0]
_sftp_module = None
_ftp_module = None
_TMP_PREFIX = 'cms_files_'                        # 시뮬레이터 임시 루트 — 서버 종료 때 지운다


# ── 전문 ─────────────────────────────────────────────────────────────

def cms_pack(cmd: str, body=None) -> bytes:
    """CMS 전문 한 건을 만든다. body 는 dict(→ compact JSON) 또는 문자열(그대로).

    PG 와 같게 본문 앞에 `\\n` 을 붙인다. 길이는 EUC-KR 바이트 수다.
    """
    cmd = str(cmd)
    if cmd not in _COMMANDS:
        raise AssertionError('CMS 명령은 %s 중 하나여야 합니다: %r' % ('/'.join(_COMMANDS), cmd))
    if body is None:
        payload = b''
    else:
        text = body if isinstance(body, str) else json.dumps(body, ensure_ascii=False,
                                                              separators=(',', ':'))
        payload = ('\n' + text).encode(_ENCODING)
    return cmd.encode('ascii') + ('%010d' % len(payload)).encode('ascii') + payload


def cms_unpack(data: bytes) -> dict:
    """전문 바이트를 {'cmd', 'length', 'text', 'body'} 로 푼다. body 는 JSON 이 아니면 None."""
    if len(data) < _HEADER_SIZE:
        raise AssertionError('CMS 헤더는 13바이트입니다 — 받은 %d바이트' % len(data))
    cmd = data[:_CMD_SIZE].decode('ascii', 'replace')
    length_text = data[_CMD_SIZE:_HEADER_SIZE].decode('ascii', 'replace')
    if not length_text.isdigit():
        raise AssertionError('CMS 헤더 길이 필드가 숫자가 아닙니다: %r' % length_text)
    length = int(length_text)
    payload = data[_HEADER_SIZE:_HEADER_SIZE + length]
    if len(payload) != length:
        raise AssertionError('CMS 본문이 잘렸습니다 — 헤더 %d바이트, 실제 %d바이트' % (length, len(payload)))
    text = payload.decode(_ENCODING, 'replace')
    try:
        body = json.loads(text) if text.strip() else None
    except ValueError:
        body = None
    return {'cmd': cmd, 'length': length, 'text': text, 'body': body}


def _recv_exact(sock, size, deadline):
    buf = b''
    while len(buf) < size:
        remaining = deadline - time.time()
        if remaining <= 0:
            raise AssertionError('CMS 수신 타임아웃 — %d/%d 바이트에서 멈춤' % (len(buf), size))
        sock.settimeout(remaining)
        try:
            chunk = sock.recv(size - len(buf))
        except socket.timeout:
            continue
        if not chunk:
            raise ConnectionError('PG.CMS 가 연결을 닫았습니다 (수신 %d/%d 바이트)' % (len(buf), size))
        buf += chunk
    return buf


def cms_send(sock, cmd: str, body=None) -> str:
    """전문을 보내고, 보낸 내용을 로그용 문자열로 돌려준다."""
    data = cms_pack(cmd, body)
    sock.sendall(data)
    return data.decode(_ENCODING, 'replace')


def cms_recv(sock, timeout=10) -> dict:
    """전문 한 건을 받는다 → cms_unpack 결과. 연결이 닫히면 ConnectionError."""
    deadline = time.time() + float(timeout)
    header = _recv_exact(sock, _HEADER_SIZE, deadline)
    length_text = header[_CMD_SIZE:].decode('ascii', 'replace')
    if not length_text.isdigit():
        raise AssertionError('CMS 헤더 길이 필드가 숫자가 아닙니다: %r (헤더 %r)' % (length_text, header))
    payload = _recv_exact(sock, int(length_text), deadline) if int(length_text) else b''
    return cms_unpack(header + payload)


def cms_expect(sock, cmd: str, timeout=10) -> dict:
    """전문 한 건을 받아 명령이 cmd 인지 확인한다. 아니면 AssertionError."""
    msg = cms_recv(sock, timeout)
    if msg['cmd'] != cmd:
        raise AssertionError('CMS 수신 명령 기대=%s, 실제=%s — 본문 %s' % (cmd, msg['cmd'], msg['text']))
    if msg['body'] is None and msg['length']:
        raise AssertionError('CMS %s 본문이 JSON 이 아닙니다: %r' % (cmd, msg['text']))
    return msg


def cms_should_be_connected(sock) -> None:
    """제어 채널이 아직 열려 있는지 기다리지 않고 본다(MSG_PEEK — 받은 데이터는 건드리지 않는다).

    PG 가 이미 끊었으면(EOF/RST) AssertionError. "PG 가 닫는지" 보는 시험이 이미 닫힌
    연결로 바로 통과하지 않도록 시작 전에 부른다.
    """
    if sock is None:
        raise AssertionError('PG.CMS 제어 채널이 없습니다')
    hint = '(CMSWEB_TIMEOUT 이 앞 시험의 대기보다 짧은지 PG 로그로 확인하십시오)'
    previous = sock.gettimeout()
    try:
        sock.settimeout(0.0)
        try:
            peeked = sock.recv(1, socket.MSG_PEEK)
        except (BlockingIOError, socket.timeout):
            return  # 읽을 것이 없을 뿐 — 살아 있다
        except OSError as exc:
            raise AssertionError('PG.CMS 제어 채널이 시험 전에 이미 끊겼습니다 — %s %s' % (exc, hint))
        if not peeked:
            raise AssertionError('PG.CMS 제어 채널이 시험 전에 이미 닫혀 있습니다(EOF) %s' % hint)
    finally:
        try:
            sock.settimeout(previous)
        except OSError:
            pass


def cms_wait_closed(sock, timeout=30) -> float:
    """PG 가 연결을 닫을 때까지 기다린다(그 사이 온 전문은 버린다). 걸린 초를 돌려준다."""
    start = time.time()
    deadline = start + float(timeout)
    while time.time() < deadline:
        sock.settimeout(max(0.1, min(1.0, deadline - time.time())))
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            continue
        except OSError:
            return round(time.time() - start, 2)
        if not chunk:
            return round(time.time() - start, 2)
    raise AssertionError('PG.CMS 가 %s초 안에 연결을 닫지 않았습니다' % timeout)


# ── 본문 ─────────────────────────────────────────────────────────────

def cms_now() -> str:
    """규격 dateTime 형식 `YYYY-MM-DD HH:MI:SS`."""
    return datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')


def cms_digits(date_time: str) -> str:
    """dateTime 에서 숫자만 남긴다 — PG `GetConvDate` 와 같다(FIN 파일명에 쓰인다)."""
    return re.sub(r'[-/: ]', '', str(date_time))


def cms_message_id(group='CMS') -> str:
    """messageId 18자리 = GROUP 3자리 + YYMMDDHHMISS + 순번 3자리(규격 4.6.1)."""
    group = str(group)
    if len(group) != 3:
        raise AssertionError('messageId 의 GROUP 은 3자리여야 합니다: %r' % group)
    with _seq_lock:
        _seq[0] = _seq[0] % 999 + 1
        seq = _seq[0]
    return '%s%s%03d' % (group, datetime.datetime.now().strftime('%y%m%d%H%M%S'), seq)


def cms_reg_result(ok=True) -> dict:
    """REG 응답 본문 — `{"result":"REG_OK"}` / `REG_NOK`."""
    return {'result': 'REG_OK' if _truthy(ok) else 'REG_NOK'}


def cms_drg_result(ok=True) -> dict:
    """DRG 응답 본문 — `{"result":"DRG_OK"}` / `DRG_NOK`."""
    return {'result': 'DRG_OK' if _truthy(ok) else 'DRG_NOK'}


def cms_hbc(date_time=None) -> dict:
    """도구 → PG HBC 본문(규격 4.5.1)."""
    return {'result': 'HBC_OK', 'dateTime': date_time or cms_now()}


def cms_nti(service_code: str, path: str, message_id: str, target_group: str, target_key: str,
            source_group='CMS', source_key='CMS', date_time=None, message_type='Report',
            omit=None) -> dict:
    """NTI 파일 알림 본문(규격 5.2). omit 에 키 이름을 주면 그 필드를 뺀다(음성 시험용).

    키 순서는 규격 예시를 따른다. 값은 PG 파서 제약상 공백 없이 직렬화된다(cms_pack).
    """
    body = {
        'sourceSessionKey': [source_group, source_key],
        'targetSessionKey': [[target_group, target_key]],
        'messageType': message_type,
        'serviceCode': service_code,
        'messageId': message_id,
        'dateTime': date_time or cms_now(),
        'data': {'COLUMN_HEAD': ['DATA'], 'COLUMN_DATA': [path]},
    }
    for key in _as_list(omit):
        if key in ('COLUMN_HEAD', 'COLUMN_DATA'):
            body['data'].pop(key, None)
        else:
            body.pop(key, None)
    return body


def cms_field(msg: dict, name: str):
    """수신 전문 본문에서 필드 하나를 꺼낸다. 없으면 AssertionError."""
    body = msg.get('body') or {}
    if name not in body:
        raise AssertionError('CMS %s 본문에 %s 필드가 없습니다: %s' % (msg.get('cmd'), name, msg.get('text')))
    return body[name]


def cms_session_key_should_be(msg: dict, group: str, key: str) -> None:
    """sourceSessionKey 가 [group, key] 인지 확인한다(PG.CMS 의 PG_V2.cfg [CMS] GROUP/KEY)."""
    actual = cms_field(msg, 'sourceSessionKey')
    if list(actual) != [str(group), str(key)]:
        raise AssertionError('sourceSessionKey 기대=%s, 실제=%s' % ([group, key], actual))


def cms_date_time_should_be_valid(value: str) -> None:
    """dateTime 이 `YYYY-MM-DD HH:MI:SS` 형식인지 확인한다."""
    try:
        datetime.datetime.strptime(str(value), '%Y-%m-%d %H:%M:%S')
    except ValueError:
        raise AssertionError('dateTime 형식 기대=YYYY-MM-DD HH:MI:SS, 실제=%r' % value)


# ── 파일 ─────────────────────────────────────────────────────────────

def cms_data_file_name(service_code: str, stamp=None, size=None) -> str:
    """CMS 데이터 파일명. size 를 주면 `<svc>_<stamp>_<size>.dat`(PG 가 크기 비교),
    안 주면 `<svc>_<stamp>.dat`(비교 안 함)."""
    stamp = stamp or datetime.datetime.now().strftime('%Y%m%d%H%M%S')
    if size in (None, ''):
        return '%s_%s.dat' % (service_code, stamp)
    return '%s_%s_%d.dat' % (service_code, stamp, int(size))


def cms_renamed_file_name(file_name: str) -> str:
    """PG `ProcFtpFile` 이 크기 비교 후 붙이는 이름 — 마지막 `_<크기>` 를 뗀다."""
    stem, ext = os.path.splitext(file_name)
    parts = stem.rsplit('_', 2)
    if len(parts) == 3 and parts[1].isdigit() and int(parts[1]) != 0 and parts[2].isdigit():
        return '%s_%s%s' % (parts[0], parts[1], ext)
    return file_name


def cms_fin_prefix(service_code: str, date_time: str, group: str, key: str) -> str:
    """PG 가 올리는 FIN 파일명의 고정 앞부분 — 뒤에 업로드 시각 14자리 + `.FIN` 이 붙는다."""
    return '%s_%s_%s%s_' % (service_code, cms_digits(date_time), group, key)


# ── SFTP 서버 (도구 = CMSWEB 파일 서버) ──────────────────────────────

def _load_sftp():
    """SftpServerHelper.py 를 __file__ 기준으로 로드한다(FtpServerHelper 와 같은 이유)."""
    global _sftp_module
    if _sftp_module is None:
        import importlib.util
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'SftpServerHelper.py')
        spec = importlib.util.spec_from_file_location('SftpServerHelper', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        _sftp_module = module
    return _sftp_module


def _load_ftp():
    """FtpServerHelper.py 를 __file__ 기준으로 로드한다(_load_sftp 와 같은 이유)."""
    global _ftp_module
    if _ftp_module is None:
        import importlib.util
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'FtpServerHelper.py')
        spec = importlib.util.spec_from_file_location('FtpServerHelper', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        _ftp_module = module
    return _ftp_module


def cms_use_sftp(flag) -> bool:
    """PG 와 같은 판정 — cfg 값 첫 글자가 'N' 이면 FTP(False), 그 밖(빈 값 포함)은 SFTP(True).

    CCMSEnv::ReadConfig: `if (Sftp_CmsWeb[0] == 'N') bUseSftpCmsWeb_ = false; else true;`
    (대소문자를 가린다 — 'n' 은 SFTP 다.)
    """
    return not str(flag if flag is not None else '').startswith('N')


def cms_file_protocol(flag) -> str:
    """cfg 값 → 'SFTP' / 'FTP' (로그·분기용)."""
    return 'SFTP' if cms_use_sftp(flag) else 'FTP'


def _start_listening(server, kind, port, cfg_hint):
    """server.start() — 포트를 못 열면 원인과 고칠 방법을 담은 AssertionError."""
    try:
        return server.start()
    except OSError as exc:
        _discard_owned_dir(server)
        if _is_permission_error(exc):
            raise AssertionError(
                '%s 포트 %d 를 열 권한이 없습니다 — %s. %s 1024 미만 포트는 root 나 '
                'net.ipv4.ip_unprivileged_port_start 조정이 필요합니다. 또는 도구 호스트에서 '
                '%d → 다른 포트로 리다이렉트(iptables REDIRECT)하고 --variable 로 그 포트를 주십시오.'
                % (kind, port, exc, cfg_hint, port))
        raise AssertionError('%s 포트 %d 를 열 수 없습니다 — %s (이미 쓰는 프로세스가 있는지 확인: ss -ltnp)'
                             % (kind, port, exc))


def _is_permission_error(exc):
    """bind 권한 오류인지 — pyftpdlib 는 PermissionError 를 일반 socket.error(OSError(err)) 로 감싸 다시 던진다."""
    import errno
    if isinstance(exc, PermissionError) or getattr(exc, 'errno', None) in (errno.EACCES, errno.EPERM):
        return True
    return any(isinstance(arg, PermissionError) or getattr(arg, 'errno', None) in (errno.EACCES, errno.EPERM)
               for arg in getattr(exc, 'args', ()))


def _owned_tmp_dir():
    import tempfile
    return tempfile.mkdtemp(prefix=_TMP_PREFIX)


def _discard_owned_dir(server):
    owned = getattr(server, 'cms_owned_dir', '')
    if owned and os.path.basename(owned).startswith(_TMP_PREFIX):
        import shutil
        shutil.rmtree(owned, ignore_errors=True)


def cms_ftp_start(port, host='0.0.0.0', user='', remote_dir='/', passive_ports='', password=None):
    """CMSWEB FTP(다운로드) 서버를 띄운다 → 서버 핸들. CMSWEB_SFTP=N 일 때 쓴다.

    PG(RunFtpCMS)는 CMSWEB_ADDR:21(소스 고정)에 CMSWEB 계정으로 로그인 → TYPE A → CWD <dir>
    → 파일 목록 → GET → 같은 디렉터리에 FIN PUT 한다. 그래서 FIN 도 이 서버 업로드 이력에 남는다.
    비밀번호는 SFTP 와 같은 환경변수 PG_PWD_CMS_SFTP(CMSWEB 다운로드 계정)에서만 읽는다.
    """
    port = int(port)
    if not user:
        raise AssertionError('CMS FTP 계정이 없습니다 — 환경 파일에 CMS_SFTP_USER 를 넣으십시오 '
                             '(PG.CMS 가 SFTP/FTP 모두에 쓰는 CMSWEB 계정).')
    pwd = password or os.environ.get(_SFTP_PWD_ENV, '')
    if not pwd:
        raise AssertionError("CMS FTP 비밀번호가 없습니다 — 환경변수 %s 를 설정하십시오. 예: export %s='...'"
                             % (_SFTP_PWD_ENV, _SFTP_PWD_ENV))
    ftp = _load_ftp()
    passive = ftp._parse_port_range(passive_ports)      # 형식 오류면 임시 디렉터리를 만들기 전에 실패
    server = ftp.FtpServer(port, host, user, pwd, directory=_owned_tmp_dir(),
                           passive_ports=passive,
                           remote_path=remote_dir, own_ioloop=True)
    server.cms_owned_dir = server.directory
    return _start_listening(server, 'CMS FTP', port,
                            'PG.CMS 의 FTP 포트는 소스 고정값(21)이라 cfg 로 바꿀 수 없습니다.')


def cms_sftp_start(port, host='0.0.0.0', user='', remote_dir='/', password=None):
    """CMSWEB SFTP(다운로드) 서버를 띄운다 → 서버 핸들.

    PG.CMS 가 NTI 데이터 파일을 GET 하는 곳이다. 실제 PG 의 FIN 업로드는 이 서버가 아니라
    도구 호스트의 실제 sshd 로 간다(cms_fin_ssh_*). 비밀번호는 환경변수 PG_PWD_CMS_SFTP
    에서만 읽는다(로그·인자에 남기지 않는다). password 인자는 Robot 밖 직접 호출용이다.
    """
    port = int(port)
    if port < 1024:
        raise AssertionError(
            'CMS SFTP 포트 %d 는 쓸 수 없습니다 — 도구 호스트의 실제 sshd/특권 포트입니다. '
            'PG_V2.cfg [CMS] CMS_SFTP_PORT 를 1024 이상(예: 2322)으로 바꾸거나 '
            '--variable CMS_SFTP_PORT:<포트> 로 맞추십시오.' % port)
    if not user:
        raise AssertionError('CMS SFTP 계정이 없습니다 — 환경 파일에 CMS_SFTP_USER 를 넣으십시오 '
                             '(PG.CMS 가 SYSTEM_TYPE 별로 쓰는 CMSWEB 계정).')
    pwd = password or os.environ.get(_SFTP_PWD_ENV, '')
    if not pwd:
        raise AssertionError("CMS SFTP 비밀번호가 없습니다 — 환경변수 %s 를 설정하십시오. 예: export %s='...'"
                             % (_SFTP_PWD_ENV, _SFTP_PWD_ENV))
    server = _load_sftp().SftpServer(port, host, user, pwd, directory=_owned_tmp_dir(),
                                     remote_path=remote_dir)
    server.cms_owned_dir = server.directory
    return _start_listening(server, 'CMS SFTP', port, '')


def cms_sftp_stop(server) -> None:
    """SFTP/FTP 서버를 멈추고, 이 모듈이 만든 임시 루트(cms_files_*)를 지운다. None 이면 아무것도 안 한다."""
    if server is None:
        return
    try:
        server.stop()
    finally:
        _discard_owned_dir(server)


def cms_sftp_put(server, remote_dir: str, file_name: str, size=128) -> str:
    """SFTP 서버 가상 경로 `<remote_dir>/<file_name>` 에 size 바이트 시험 파일을 만든다.

    반환: PG 에 알릴 절대 경로(`/<dir>/<file>`) — NTI COLUMN_DATA 값.
    """
    rel = str(remote_dir).strip('/')
    local_dir = os.path.join(server.directory, rel.replace('/', os.sep)) if rel else server.directory
    if not os.path.isdir(local_dir):
        os.makedirs(local_dir)
    # 줄바꿈 없음 — PG 의 FTP 는 TYPE A 라 서버가 LF→CRLF 로 바꾸면 크기가 달라진다.
    line = b'ROBOT CMSWEB TEST DATA '
    size = int(size)
    content = (line * (size // len(line) + 1))[:size]
    with open(os.path.join(local_dir, file_name), 'wb') as stream:
        stream.write(content)
    return '/%s/%s' % (rel, file_name) if rel else '/%s' % file_name


def cms_sftp_clear(server) -> None:
    """업로드·다운로드·오류 이력을 비운다(접속 이력은 남긴다). TC 마다 Test Setup 에서 부른다."""
    if server is not None:
        server.clear()


def cms_sftp_downloads(server, name_contains='') -> list:
    """PG 가 SFTP 로 읽어 간 파일 이력(서버 기동 후 / clear 후)."""
    return [d for d in server.downloads() if name_contains in d['filename']]


def cms_sftp_uploads(server, name_contains='') -> list:
    """PG 가 SFTP 로 올린 파일 이력."""
    return [f for f in server.files() if name_contains in f['filename']]


def cms_sftp_wait_upload(server, name_prefix: str, timeout=30, poll=0.5) -> dict:
    """name_prefix 로 시작하는 업로드(FIN)가 생길 때까지 기다린다 → 업로드 기록."""
    deadline = time.time() + float(timeout)
    while time.time() < deadline:
        for item in server.files():
            if item['filename'].startswith(name_prefix):
                return item
        time.sleep(float(poll))
    raise AssertionError('%s초 안에 FIN 업로드가 없었습니다 — 기대 접두사 %s, 업로드 %s, 오류 %s'
                         % (timeout, name_prefix, [f['filename'] for f in server.files()],
                            server.errors()[-3:]))


def cms_sftp_wait_download(server, file_name: str, timeout=30, poll=0.5) -> dict:
    """file_name 을 PG 가 읽어 갈 때까지 기다린다 → 다운로드 기록."""
    deadline = time.time() + float(timeout)
    while time.time() < deadline:
        for item in server.downloads():
            if item['filename'] == file_name:
                return item
        time.sleep(float(poll))
    raise AssertionError('%s초 안에 PG 가 %s 를 가져가지 않았습니다 — 접속 %d건, 오류 %s'
                         % (timeout, file_name, len(server.connections()), server.errors()[-3:]))


def cms_sftp_should_stay_quiet(server, name_contains: str, window=10, poll=0.5,
                               kind='upload') -> None:
    """window 초 동안 name_contains 를 포함한 업로드/다운로드가 **없는지** 지켜본다(음성 판정)."""
    source = server.files if kind == 'upload' else server.downloads
    deadline = time.time() + float(window)
    while time.time() < deadline:
        hits = [i['filename'] for i in source() if name_contains in i['filename']]
        if hits:
            raise AssertionError('%s 가 없어야 하는데 생겼습니다: %s' % (kind, hits))
        time.sleep(float(poll))


# ── SC(NWDAF) 수신 SFTP — PG 가 받은 파일을 다시 올린다 ─────────────────

def cms_sc_sftp_start(port, host='0.0.0.0', user='', sc_path='/', upload_dir='', password=None):
    """SC 수신 SFTP 서버를 띄운다 → 서버 핸들. 가상 경로 sc_path 를 실제 upload_dir 로 마운트한다.

    PG 는 `sftp://SC_PRIIP:NWDAF_SFTP_PORT<SC_PATH>/<파일>` 절대 경로로 올린다 — 그래서
    sc_path(예: /PG/FTP/CMS) 아래로 오는 파일이 upload_dir 에 그대로 쌓인다. upload_dir 이
    없으면 만든다. 비밀번호는 환경변수 PG_PWD_CMS_SFTP_UPLOAD 에서만 읽는다
    (password 인자는 Robot 밖 직접 호출용).
    """
    port = int(port)
    if port < 1024:
        raise AssertionError('SC SFTP 포트 %d 는 쓸 수 없습니다 — 도구 호스트의 실제 sshd/특권 포트입니다. '
                             'PG_V2.cfg [CMS] NWDAF_SFTP_PORT 를 1024 이상으로 두십시오.' % port)
    if not user:
        raise AssertionError('SC SFTP 계정이 없습니다 — CMS_SC_SFTP_USER 를 넣으십시오')
    if not upload_dir:
        raise AssertionError('SC 업로드 디렉터리가 없습니다 — CMS_SC_UPLOAD_DIR 를 넣으십시오')
    if not str(sc_path).startswith('/'):
        raise AssertionError('SC_PATH 는 절대 경로여야 합니다: %r' % sc_path)
    pwd = password or os.environ.get(_SC_PWD_ENV, '')
    if not pwd:
        raise AssertionError("SC SFTP 비밀번호가 없습니다 — 환경변수 %s 를 설정하십시오. 예: export %s='...'"
                             % (_SC_PWD_ENV, _SC_PWD_ENV))
    upload_dir = os.path.abspath(str(upload_dir))
    if not os.path.isdir(upload_dir):
        os.makedirs(upload_dir)
    server = _load_sftp().SftpServer(port, host, user, pwd, directory=_owned_tmp_dir(),
                                     mounts={str(sc_path): upload_dir})
    server.cms_owned_dir = server.directory
    return _start_listening(server, 'SC SFTP', port, '')


def cms_sc_ftp_start(port, host='0.0.0.0', user='', sc_path='/', upload_dir='', passive_ports='',
                     password=None):
    """SC 수신 FTP 서버를 띄운다 → 서버 핸들. NWDAF_SFTP=N 일 때 쓴다(CCMSWeb::RunFtpSC).

    PG 는 SC_PRIIP:NWDAF_FTP_PORT 에 SC 계정으로 로그인 → TYPE A → CWD SC_PATH → 파일·FIN PUT.
    가상 경로 sc_path 를 실제 upload_dir 로 마운트한다(cms_sc_sftp_start 와 같다).
    비밀번호는 환경변수 PG_PWD_CMS_SFTP_UPLOAD 에서만 읽는다.
    """
    port = int(port)
    if not user:
        raise AssertionError('SC FTP 계정이 없습니다 — CMS_SC_SFTP_USER 를 넣으십시오')
    if not upload_dir:
        raise AssertionError('SC 업로드 디렉터리가 없습니다 — CMS_SC_UPLOAD_DIR 를 넣으십시오')
    if not str(sc_path).startswith('/'):
        raise AssertionError('SC_PATH 는 절대 경로여야 합니다: %r' % sc_path)
    pwd = password or os.environ.get(_SC_PWD_ENV, '')
    if not pwd:
        raise AssertionError("SC FTP 비밀번호가 없습니다 — 환경변수 %s 를 설정하십시오. 예: export %s='...'"
                             % (_SC_PWD_ENV, _SC_PWD_ENV))
    upload_dir = os.path.abspath(str(upload_dir))
    if not os.path.isdir(upload_dir):
        os.makedirs(upload_dir)
    ftp = _load_ftp()
    passive = ftp._parse_port_range(passive_ports)      # 형식 오류면 임시 디렉터리를 만들기 전에 실패
    server = ftp.FtpServer(port, host, user, pwd, directory=_owned_tmp_dir(),
                           passive_ports=passive,
                           mounts={str(sc_path): upload_dir}, own_ioloop=True)
    server.cms_owned_dir = server.directory
    return _start_listening(server, 'SC FTP', port,
                            'PG_V2.cfg [CMS] NWDAF_FTP_PORT 를 1024 이상으로 두면 피할 수 있습니다.')


def cms_sc_wait_uploads(server, case: dict, upload_dir: str, timeout=30, poll=0.5) -> dict:
    """SC 수신 서버에 이 시험의 데이터 파일과 FIN 이 모두 올라올 때까지 기다린다.

    데이터 파일(case['sc_data'])은 크기가 case['size'] 와 같아야 하고 FIN(case['sc_fin'])은
    비어 있어야 한다. 두 파일 모두 실제 upload_dir 안에 있어야 한다.
    반환: {'data': 업로드 기록, 'fin': 업로드 기록}
    """
    upload_dir = os.path.abspath(str(upload_dir))
    want = {'data': case['sc_data'], 'fin': case['sc_fin']}
    deadline = time.time() + float(timeout)
    found = {}
    while True:
        for item in server.files():
            for kind, name in want.items():
                if item['filename'] == name and kind not in found:
                    found[kind] = item
        if len(found) == len(want):
            break
        if time.time() >= deadline:
            raise AssertionError('%s초 안에 SC 업로드가 다 오지 않았습니다 — 기대 %s, 받은 것 %s, 업로드 %s, 오류 %s'
                                 % (timeout, sorted(want.values()), sorted(f['filename'] for f in found.values()),
                                    [f['filename'] for f in server.files()][-10:], server.errors()[-3:]))
        time.sleep(float(poll))
    problems = []
    for kind, item in found.items():
        real = os.path.abspath(item['path'])
        if os.path.dirname(real) != upload_dir:
            problems.append('%s 가 %s 가 아닌 %s 에 저장됐습니다' % (item['filename'], upload_dir, real))
        elif not os.path.isfile(real):
            problems.append('%s 가 %s 에 없습니다' % (item['filename'], upload_dir))
    if found['data']['size'] != int(case['size']):
        problems.append('데이터 파일 크기 기대=%s 실제=%s' % (case['size'], found['data']['size']))
    if found['fin']['size'] != 0:
        problems.append('FIN 은 빈 파일이어야 합니다: %s바이트' % found['fin']['size'])
    if problems:
        raise AssertionError('SC 업로드 판정 실패 — %s' % '; '.join(problems))
    return found


def cms_sc_cleanup(upload_dir: str, names) -> dict:
    """upload_dir 에서 이름이 정확히 names 인 파일만 지운다 → {'removed': [...], 'failed': [...]}.

    이번 실행이 만든 파일만 지우려고 이름 목록을 받는다. 예외를 내지 않는다(Suite Teardown 용).
    """
    result = {'removed': [], 'failed': []}
    base = os.path.abspath(str(upload_dir)) if upload_dir else ''
    for name in _as_list(names):
        name = str(name)
        if not base or os.path.basename(name) != name:
            result['failed'].append('%s: 디렉터리/이름이 올바르지 않습니다' % name)
            continue
        path = os.path.join(base, name)
        if not os.path.exists(path):
            continue
        try:
            os.remove(path)
            result['removed'].append(name)
        except OSError as exc:
            result['failed'].append('%s: %s' % (name, exc))
    return result


# ── FIN — 실제 PG 는 도구 호스트의 실제 sshd(22)로 올린다 ────────────────

def _fin_open(host, port, user, timeout=10):
    """FIN 확인용 SFTP 클라이언트를 연다 → (transport, sftp). 비밀번호는 환경변수에서만.

    접속 대상은 도구 자신의 호스트(기본 127.0.0.1:22)라 호스트 키는 검증하지 않는다
    (SshHelper 의 StrictHostKeyChecking=no 와 같다).
    """
    paramiko = _load_sftp()._load_paramiko()
    if not user:
        raise AssertionError('FIN 확인 계정이 없습니다 — CMS_FIN_SSH_USER 를 넣으십시오')
    # PG 는 FIN 을 CMSWEB 다운로드 계정으로 올린다 — 그래서 따로 주지 않으면 다운로드 비밀번호를 쓴다
    # (dev 142 의 실제 pg 비밀번호가 다운로드 비밀번호와 같음을 2026-11-24 로그인으로 확인).
    pwd = os.environ.get(_FIN_PWD_ENV, '') or os.environ.get(_SFTP_PWD_ENV, '')
    if not pwd:
        raise AssertionError("FIN 확인용 비밀번호가 없습니다 — 환경변수 %s(없으면 %s)에 도구 호스트 실제 계정 "
                             "%s 의 비밀번호를 설정하십시오. 예: export %s='...'"
                             % (_FIN_PWD_ENV, _SFTP_PWD_ENV, user, _SFTP_PWD_ENV))
    timeout = float(timeout)
    try:
        sock = socket.create_connection((str(host), int(port)), timeout=timeout)
    except OSError as exc:
        raise AssertionError('FIN 확인용 sshd %s:%s 접속 실패 — %s' % (host, port, exc))
    transport = paramiko.Transport(sock)
    transport.banner_timeout = timeout
    try:
        transport.connect(username=str(user), password=pwd)
        sftp = paramiko.SFTPClient.from_transport(transport)
    except paramiko.AuthenticationException:
        transport.close()
        raise AssertionError('FIN 확인용 sshd %s:%s 로그인 실패 — 계정 %s / 환경변수 %s 를 확인하십시오'
                             % (host, port, user, _FIN_PWD_ENV))
    except Exception as exc:
        transport.close()
        raise AssertionError('FIN 확인용 sshd %s:%s SFTP 세션 실패 — %s' % (host, port, exc))
    sftp.get_channel().settimeout(timeout)
    return transport, sftp


def _fin_list(sftp, remote_dir, prefixes):
    """remote_dir 에서 prefixes 중 하나로 시작하는 `.FIN` → [(이름, 크기)]."""
    try:
        entries = sftp.listdir_attr(str(remote_dir))
    except IOError as exc:
        raise AssertionError('FIN 디렉터리 %s 를 읽을 수 없습니다 — %s' % (remote_dir, exc))
    return sorted((e.filename, e.st_size) for e in entries
                  if e.filename.endswith('.FIN') and any(e.filename.startswith(p) for p in prefixes))


def _fin_path(remote_dir, name):
    return '%s/%s' % (str(remote_dir).rstrip('/'), name)


def cms_fin_ssh_check(host: str, port, user: str, remote_dir: str, timeout=10) -> str:
    """FIN 이 떨어질 디렉터리를 실제 sshd 로 미리 확인한다(Suite Setup).

    PG 의 FIN PUT 이 실패하면 CmsMain 이 종료되므로(공유 PG 영향) 시험 전에 막는다:
    계정 로그인 → remote_dir 존재 → 빈 탐침 파일 쓰기·삭제. 문제가 있으면 AssertionError.
    """
    transport, sftp = _fin_open(host, port, user, timeout)
    probe = _fin_path(remote_dir, '.robot_fin_probe_%d_%d' % (os.getpid(), int(time.time())))
    try:
        try:
            sftp.stat(str(remote_dir))
        except IOError as exc:
            raise AssertionError('FIN 디렉터리 %s 가 %s:%s 에 없습니다 — %s. 이대로면 PG 의 FIN PUT 이 실패해 '
                                 'CmsMain 이 종료됩니다. 계정 %s 가 쓸 수 있는 디렉터리로 CMS_REMOTE_DIR 을 '
                                 '맞추거나 관리자에게 만들어 달라고 하십시오.' % (remote_dir, host, port, exc, user))
        try:
            with sftp.open(probe, 'w'):
                pass
            sftp.remove(probe)
        except IOError as exc:
            raise AssertionError('계정 %s 가 FIN 디렉터리 %s 에 쓸 수 없습니다 — %s. 이대로면 PG 의 FIN PUT 이 '
                                 '실패해 CmsMain 이 종료됩니다.' % (user, remote_dir, exc))
    finally:
        transport.close()
    return 'sftp://%s@%s:%s%s 쓰기 가능' % (user, host, port, remote_dir)


def cms_fin_ssh_wait(host: str, port, user: str, remote_dir: str, name_prefix: str,
                     timeout=30, poll=1.0) -> dict:
    """실제 sshd 의 remote_dir 에 name_prefix 로 시작하는 `.FIN` 이 생길 때까지 기다린다.

    반환: {'filename', 'size', 'path'}. 시간 안에 없으면 그 디렉터리의 FIN 목록과 함께 AssertionError.
    """
    deadline = time.time() + float(timeout)
    transport, sftp = _fin_open(host, port, user)
    try:
        while True:
            hits = _fin_list(sftp, remote_dir, [str(name_prefix)])
            if hits:
                name, size = hits[0]
                return {'filename': name, 'size': size, 'path': _fin_path(remote_dir, name)}
            if time.time() >= deadline:
                seen = sorted(e for e in sftp.listdir(str(remote_dir)) if e.endswith('.FIN'))
                break
            time.sleep(float(poll))
    finally:
        transport.close()
    raise AssertionError('%s초 안에 FIN 이 %s:%s %s 에 없었습니다 — 기대 접두사 %s, 그 디렉터리의 FIN %s'
                         ' (PG 의 FIN PUT 이 실패했다면 CmsMain 이 종료됐을 수 있습니다 — PG 로그 확인)'
                         % (timeout, host, port, remote_dir, name_prefix, seen[-10:]))


def cms_fin_ssh_should_stay_quiet(host: str, port, user: str, remote_dir: str, name_prefix: str,
                                  window=10, poll=1.0) -> None:
    """window 초 동안 실제 sshd 의 remote_dir 에 name_prefix FIN 이 **생기지 않는지** 본다(음성 판정)."""
    deadline = time.time() + float(window)
    transport, sftp = _fin_open(host, port, user)
    try:
        while True:
            hits = _fin_list(sftp, remote_dir, [str(name_prefix)])
            if hits:
                raise AssertionError('FIN 이 없어야 하는데 생겼습니다: %s' % [h[0] for h in hits])
            if time.time() >= deadline:
                return
            time.sleep(float(poll))
    finally:
        transport.close()


def cms_fin_ssh_cleanup(host: str, port, user: str, remote_dir: str, prefixes) -> dict:
    """이번 실행의 FIN 접두사와 맞는 `.FIN` 만 지운다 → {'removed': [...], 'failed': [...]}.

    Suite Teardown 용이라 예외를 내지 않는다 — 못 지운 것은 'failed' 에 이유와 함께 남긴다.
    """
    prefixes = [str(p) for p in _as_list(prefixes)]
    result = {'removed': [], 'failed': []}
    if not prefixes:
        return result
    try:
        transport, sftp = _fin_open(host, port, user)
    except AssertionError as exc:
        result['failed'].append(str(exc))
        return result
    try:
        for name, _size in _fin_list(sftp, remote_dir, prefixes):
            try:
                sftp.remove(_fin_path(remote_dir, name))
                result['removed'].append(name)
            except IOError as exc:
                result['failed'].append('%s: %s' % (name, exc))
    except AssertionError as exc:
        result['failed'].append(str(exc))
    finally:
        transport.close()
    return result


# ── 시험 1건 준비 / 판정 ─────────────────────────────────────────────

def cms_new_case(server, remote_dir: str, service_code: str, target_group: str, target_key: str,
                 size=128, size_in_name=True, declared_size=None, omit=None,
                 source_group='CMS', source_key='CMS', id_group='CMS') -> dict:
    """NTI 시험 1건을 준비한다 — SFTP 서버에 파일을 만들고 NTI 본문을 짠다.

    size_in_name=True 면 파일명에 크기를 넣는다(PG 가 이름을 바꾸고 크기를 비교한다).
    declared_size 를 주면 파일명에는 그 값을 쓴다 — 실제 크기와 다르게 줘서 PG 의
    크기 불일치 처리를 시험한다.
    반환 dict: message_id, date_time, file_name(보낸 이름), renamed(PG 가 바꿀 이름),
              path(COLUMN_DATA), size, body(NTI 본문), fin_prefix
    """
    size = int(size)
    # 시각을 시험마다 다르게 — 파일명과 FIN 접두사(NTI dateTime 기반)가 겹치면 앞 시험의
    # 늦은 GET/FIN 을 다음 시험의 것으로 착각한다(같은 초에 두 시험이 돌면 실제로 겹쳤다).
    moment = _unique_moment()
    stamp = moment.strftime('%Y%m%d%H%M%S')
    name_size = None
    if _truthy(size_in_name):
        name_size = size if declared_size in (None, '') else int(declared_size)
    file_name = cms_data_file_name(service_code, stamp, name_size)
    path = cms_sftp_put(server, remote_dir, file_name, size)
    date_time = moment.strftime('%Y-%m-%d %H:%M:%S')
    message_id = cms_message_id(id_group)
    body = cms_nti(service_code, path, message_id, target_group, target_key,
                   source_group, source_key, date_time, omit=omit)
    return {
        'message_id': message_id,
        'date_time': date_time,
        'file_name': file_name,
        'renamed': cms_renamed_file_name(file_name),
        'path': path,
        'size': size,
        'service_code': service_code,
        'body': body,
        'fin_prefix': cms_fin_prefix(service_code, date_time, target_group, target_key),
        # SC 전달(RunSFtpSC) 때 PG 가 올리는 두 파일 — 이름 바뀐 데이터 파일과 `<첫 '.' 앞>.FIN`
        'sc_data': cms_renamed_file_name(file_name),
        'sc_fin': cms_renamed_file_name(file_name).split('.', 1)[0] + '.FIN',
    }


def cms_ans_should_match(msg: dict, case: dict, group: str, key: str) -> None:
    """PG ANS 가 NTI 의 messageId 를 에코하고 data=NTI_OK 인지 확인한다(규격 4.7)."""
    if msg.get('cmd') != 'ANS':
        raise AssertionError('ANS 를 기대했는데 %s 가 왔습니다: %s' % (msg.get('cmd'), msg.get('text')))
    cms_session_key_should_be(msg, group, key)
    if cms_field(msg, 'messageId') != case['message_id']:
        raise AssertionError('ANS messageId 기대=%s, 실제=%s'
                             % (case['message_id'], cms_field(msg, 'messageId')))
    if cms_field(msg, 'data') != 'NTI_OK':
        raise AssertionError('ANS data 기대=NTI_OK, 실제=%r' % cms_field(msg, 'data'))
    cms_date_time_should_be_valid(cms_field(msg, 'dateTime'))


def cms_zone_row_should_match(rows: list, status, reason: str, file_name=None, file_size=None,
                              zone_code=None, service_code=None, label='T_CMSWEB_ZONE') -> dict:
    """MSG_ID 로 조회한 T_CMSWEB_ZONE 행이 기대와 같은지 본다 → 그 행.

    status 는 한 글자 또는 여러 글자 목록(예: 'C' / ['C', 'E']) — PG 가 넣은 직후는
    'C' 지만 ZONE 프로세스가 곧바로 바꿀 수 있어 허용 목록을 받는다.
    """
    if not rows:
        raise AssertionError('%s 행이 없습니다' % label)
    if len(rows) != 1:
        raise AssertionError('%s 행이 %d건입니다 — 1건이어야 합니다: %s' % (label, len(rows), rows))
    row = rows[0]
    allowed = _as_list(status)
    problems = []
    if row.get('STATUS') not in allowed:
        problems.append('STATUS 기대=%s 실제=%r' % ('/'.join(allowed), row.get('STATUS')))
    if row.get('REASON') != reason:
        problems.append('REASON 기대=%r 실제=%r' % (reason, row.get('REASON')))
    if file_name is not None and row.get('FILENAME') != file_name:
        problems.append('FILENAME 기대=%r 실제=%r' % (file_name, row.get('FILENAME')))
    if file_size is not None and int(row.get('FILESIZE') or 0) != int(file_size):
        problems.append('FILESIZE 기대=%s 실제=%r' % (file_size, row.get('FILESIZE')))
    if zone_code is not None and row.get('ZONE_CODE') != zone_code:
        problems.append('ZONE_CODE 기대=%r 실제=%r' % (zone_code, row.get('ZONE_CODE')))
    if service_code is not None and row.get('SERVICE_CODE') != service_code:
        problems.append('SERVICE_CODE 기대=%r 실제=%r' % (service_code, row.get('SERVICE_CODE')))
    if problems:
        raise AssertionError('%s 불일치 — %s / 행 %s' % (label, '; '.join(problems), row))
    return row


_last_moment = [None]


def _unique_moment():
    """지금 시각(초 단위). 앞에 쓴 시각과 같거나 이르면 1초씩 민다 — 시험마다 고유."""
    with _seq_lock:
        moment = datetime.datetime.now().replace(microsecond=0)
        last = _last_moment[0]
        if last is not None and moment <= last:
            moment = last + datetime.timedelta(seconds=1)
        _last_moment[0] = moment
        return moment


def _as_list(value):
    if value in (None, ''):
        return []
    if isinstance(value, (list, tuple)):
        return list(value)
    return [v for v in str(value).replace(',', ' ').split() if v]


def _truthy(value):
    return str(value).lower() not in ('false', '0', 'no', 'n', 'off', 'none', '')
