"""
TcpHelper.py  —  PG 연동 통합 헬퍼
====================================

[인터페이스별 프로토콜]

  NAG / PCF  (클라이언트 모드)
    헤더 Byte0 = 0x00  (ProtoVer=0)
    Body       = JSON  (White Space 제거)
    접속 방향  = 테스트 도구 → PG 서버

  LRS  (서버 모드)
    헤더 Byte0 = 0x20  (ProtoVer=01'B)
    Body       = 고정길이 ASCII 패킹
    접속 방향  = LRS(PG) → 테스트 도구 서버 (Port 8890)

[헤더 구조 공통 (8 Octet, Big Endian)]
  Byte 0   : 인터페이스별 상이 (NAG/PCF=0x00, LRS=0x20)
  Byte 1   : Message Type
  Byte 2-3 : Body Length  (htons/ntohs)
  Byte 4-7 : Transaction Identifier  (htonl/ntohl, 0 금지)
"""

import socket
import struct
import json
import time


# ── 예외 ──────────────────────────────────────────────────────────

class ConnectionClosed(RuntimeError):
    """소켓이 닫혔거나 에러 발생"""
    pass


# ── 클라이언트 소켓 (NAG/PCF용) ───────────────────────────────────

def tcp_connect(host: str, port, timeout=30):
    """TCP 연결 생성 (NAG/PCF 클라이언트 모드)"""
    return socket.create_connection((host, int(port)), timeout=float(timeout))


def tcp_close(sock):
    """TCP 연결 종료"""
    try:
        sock.close()
    except Exception:
        pass


# ── 서버 소켓 (LRS용) ─────────────────────────────────────────────

def server_start(port, host='0.0.0.0', backlog=5):
    """
    서버 소켓 생성 및 Listen (LRS 서버 모드)
    SO_REUSEADDR 적용 → 재시작 시 포트 즉시 재사용
    """
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((host, int(port)))
    srv.listen(int(backlog))
    return srv


def _parse_allowed_ips(allowed_ips):
    """허용 IP 목록 정규화. None/빈 값 → 빈 set(= 전체 허용).
    list/tuple/set 또는 콤마·공백 구분 문자열을 받는다."""
    if allowed_ips is None:
        return set()
    if isinstance(allowed_ips, (list, tuple, set)):
        items = allowed_ips
    else:
        items = str(allowed_ips).replace(',', ' ').split()
    return {str(ip).strip() for ip in items if str(ip).strip()}


def server_accept(server_sock, timeout=30, allowed_ips=None):
    """
    클라이언트 접속 대기 (LRS 서버 모드)
    timeout 초 초과 시 TimeoutError 발생
    allowed_ips 지정 시 해당 출발지 IP 접속만 수락하고,
      그 외 IP 는 즉시 닫은 뒤 남은 시간 동안 계속 대기한다.
      (None/빈 값 = 모든 IP 허용, 기존 동작)
    반환: (client_socket, client_addr)
    """
    allowset = _parse_allowed_ips(allowed_ips)
    deadline = time.monotonic() + float(timeout)
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(
                f"LRS(PG) 접속 대기 타임아웃 ({timeout}초). "
                f"허용 IP({', '.join(sorted(allowset)) or '전체'}) 접속이 없었습니다."
            )
        server_sock.settimeout(remaining)
        try:
            conn, addr = server_sock.accept()
        except socket.timeout:
            raise TimeoutError(
                f"LRS(PG) 접속 대기 타임아웃 ({timeout}초). PG가 접속하지 않았습니다."
            )
        peer_ip = addr[0]
        if allowset and peer_ip not in allowset:
            print(
                f"[TcpHelper] 허용되지 않은 IP 접속 거부: {addr} "
                f"(허용: {', '.join(sorted(allowset))})"
            )
            try:
                conn.close()
            except Exception:
                pass
            continue
        conn.settimeout(float(timeout))
        return conn, addr


def server_stop(server_sock):
    """서버 소켓 종료"""
    try:
        server_sock.close()
    except Exception:
        pass


def client_close(conn):
    """클라이언트 연결 소켓 종료 (LRS 서버 모드)"""
    try:
        conn.close()
    except Exception:
        pass


def is_connected(sock) -> bool:
    """소켓 연결 여부 확인"""
    try:
        return sock.fileno() != -1
    except Exception:
        return False


# ── 내부 수신 헬퍼 ────────────────────────────────────────────────

def _recv_exact(sock, n: int) -> bytes:
    """정확히 n 바이트 수신. 연결 끊기면 ConnectionClosed 발생."""
    buf = bytearray()
    n = int(n)
    while len(buf) < n:
        try:
            chunk = sock.recv(n - len(buf))
        except (OSError, ConnectionResetError) as e:
            raise ConnectionClosed(f"소켓 수신 오류: {e}") from e
        if not chunk:
            raise ConnectionClosed(
                f"연결이 종료됐습니다 (수신 {len(buf)}/{n} bytes)"
            )
        buf.extend(chunk)
    return bytes(buf)


# ── raw 텍스트 송수신 (LRS 클라이언트 Health Check: "REQ"/"ANS") ──

def send_text(sock, text, encoding='ascii'):
    """
    헤더 없이 텍스트를 그대로 송신 (LRS Health Check "REQ" 등).
    """
    if not is_connected(sock):
        raise ConnectionClosed("소켓이 이미 닫혀 있습니다")
    try:
        sock.sendall(str(text).encode(encoding))
    except (OSError, BrokenPipeError) as e:
        raise ConnectionClosed(f"소켓 전송 오류: {e}") from e


def recv_text(sock, nbytes, encoding='ascii'):
    """
    정확히 nbytes 만큼 수신해 문자열로 반환 (LRS Health Check "ANS" 등).
    """
    data = _recv_exact(sock, int(nbytes))
    return data.decode(encoding, errors='replace')


# ── 헤더 처리 공통 ────────────────────────────────────────────────

def build_header(msg_type: int, body_length: int, txn_id: int,
                 byte0: int = 0x00) -> bytes:
    """
    8 Octet 헤더 생성
    byte0: NAG/PCF = 0x00 / LRS = 0x20 (ProtoVer=01'B)
    """
    bl_net  = socket.htons(int(body_length))
    tid_net = socket.htonl(int(txn_id))
    return bytes([int(byte0), int(msg_type)]) \
         + struct.pack('<H', bl_net) \
         + struct.pack('<I', tid_net)


def parse_header(header_bytes: bytes) -> dict:
    """8 Octet 헤더 파싱 (NAG/PCF/LRS 공통)"""
    if len(header_bytes) != 8:
        raise ConnectionClosed(f"헤더 크기 오류: {len(header_bytes)} bytes (expected 8)")
    b0       = header_bytes[0]
    msg_type = header_bytes[1]
    bl_raw   = struct.unpack('<H', header_bytes[2:4])[0]
    tid_raw  = struct.unpack('<I', header_bytes[4:8])[0]
    return {
        'byte0':       b0,
        'ext_bit':     (b0 >> 7) & 1,
        'proto_ver':   (b0 >> 5) & 3,
        'msg_type':    msg_type,
        'body_length': socket.ntohs(bl_raw),
        'txn_id':      socket.ntohl(tid_raw),
    }


# ── NAG/PCF: JSON Body 송수신 ─────────────────────────────────────

def send_message(sock, msg_type: int, txn_id: int, payload=None) -> None:
    """
    NAG/PCF/UPM용: 헤더(Byte0=0x00) + Body 전송
    payload=None       → Body 없음
    payload=str/bytes  → 그대로 raw Body 전송 (예: Ping Keep-Alive용 "\\r\\n")
    payload=dict/list  → JSON 인코딩하여 전송
    """
    if not is_connected(sock):
        raise ConnectionClosed("소켓이 이미 닫혀 있습니다")
    if payload is None:
        body_bytes = b''
    elif isinstance(payload, (bytes, bytearray)):
        body_bytes = bytes(payload)
    elif isinstance(payload, str):
        body_bytes = payload.encode('utf-8')
    else:
        body_str   = json.dumps(payload, ensure_ascii=False, separators=(',', ':'))
        body_bytes = body_str.encode('utf-8')
    header = build_header(msg_type, len(body_bytes), txn_id, byte0=0x00)
    try:
        sock.sendall(header + body_bytes)
    except (OSError, BrokenPipeError) as e:
        raise ConnectionClosed(f"소켓 전송 오류: {e}") from e


def receive_message(sock) -> tuple:
    """
    NAG/PCF용: 헤더(8B) + JSON Body 수신
    반환: (header_dict, body_dict)  Body 없으면 body_dict = {}
    """
    hdr_bytes = _recv_exact(sock, 8)
    hdr       = parse_header(hdr_bytes)
    body_len  = hdr['body_length']
    if body_len > 0:
        body_bytes = _recv_exact(sock, body_len)
        body = json.loads(body_bytes.decode('utf-8'))
    else:
        body = {}
    return hdr, body


# ── LRS: 고정길이 ASCII Body 송수신 ──────────────────────────────

def pack_fields(field_specs: list) -> bytes:
    """
    LRS용: 고정길이 ASCII Body 생성
    field_specs: [(value, size), ...]
    value=None → 공백 패딩
    """
    buf = bytearray()
    for value, size in field_specs:
        size = int(size)
        s = '' if value is None else str(value)
        encoded = s.encode('ascii', errors='replace')
        if len(encoded) >= size:
            buf.extend(encoded[:size])
        else:
            buf.extend(encoded)
            buf.extend(b' ' * (size - len(encoded)))
    return bytes(buf)


def unpack_fields(data: bytes, field_specs: list) -> dict:
    """
    LRS용: 고정길이 ASCII Body 파싱
    field_specs: [(field_name, size), ...]
    각 필드 strip() 후 반환
    """
    result = {}
    offset = 0
    for name, size in field_specs:
        size = int(size)
        chunk = data[offset:offset + size]
        decoded = chunk.decode('ascii', errors='replace').replace('\x00', '')
        result[name] = decoded.strip()
        offset += size
    return result


def send_lrs_message(sock, msg_type: int, txn_id: int,
                     body_bytes: bytes = b'') -> None:
    """
    LRS용: 헤더(Byte0=0x20) + 고정길이 ASCII Body 전송
    """
    if not is_connected(sock):
        raise ConnectionClosed("소켓이 이미 닫혀 있습니다")
    header = build_header(msg_type, len(body_bytes), txn_id, byte0=0x20)
    try:
        sock.sendall(header + body_bytes)
    except (OSError, BrokenPipeError) as e:
        raise ConnectionClosed(f"소켓 전송 오류: {e}") from e


def receive_lrs_message(sock) -> tuple:
    """
    LRS용: 헤더(8B) + 고정길이 ASCII Body 수신
    반환: (header_dict, raw_body_bytes)  Body 없으면 b''
    """
    hdr_bytes = _recv_exact(sock, 8)
    hdr       = parse_header(hdr_bytes)
    body_len  = hdr['body_length']
    body      = _recv_exact(sock, body_len) if body_len > 0 else b''
    return hdr, body
