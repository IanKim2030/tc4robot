"""
CdsHelper.py  —  CDS 표준 인터페이스(SKT Ver6.0) 헬퍼
======================================================

CDS(Customer data Distributed Server) 연동 전용.
도구(로봇=CDS)가 클라이언트로 PG.CDS 에 접속(Schannel/Rchannel 듀얼 소켓)해
48바이트 고정 헤더 + Data 전문을 주고받는다.

  방향   : 도구(CDS) → PG.CDS 접속 (능동 Connector)
  채널   : Schannel(기본 9200) / Rchannel(기본 9201)
  헤더   : 48 Byte 고정 (DownLoad 용 메시지 구조, 규격 3.1.1)
  엔디안 : big-endian(network order). 정수 필드는 htonl/htons 로 송신
           (PG.CDS 수신부가 ntohl/ntohs 로 변환)

[DownLoad 48B 헤더 구조 — 규격 3.1.1 / 3.2.1]
  Message ID            (4,  uint32 BE)
  Transaction ID        (12 = YYYYMMDD char(8) + Sequence Number uint32 BE(4))
  Source System ID      (6,  char, 공백 패딩)
  Destination System ID (6,  char)
  Source Application ID (6,  char)
  Destination App ID    (6,  char)
  Continue Flag         (2,  uint16 BE; 0x00=연속, 0x01=비연속)
  Serial No             (2,  uint16 BE)
  Data Size             (4,  uint32 BE)
  Data                  (Data Size 바이트)

소켓 수명주기/수신 헬퍼는 TcpHelper(클라이언트 모드)를 재사용한다.
"""

import struct

from TcpHelper import (          # 소켓 생성/종료/상태/정확수신 재사용
    tcp_connect,
    tcp_close,
    is_connected,
    _recv_exact,
    ConnectionClosed,
)

HEADER_SIZE = 48


# ── 내부: char 고정길이 필드 패킹/언패킹 ──────────────────────────

def _pack_char(value, size):
    """ASCII 고정길이 필드: size 초과는 자르고, 미만은 공백 패딩."""
    s = '' if value is None else str(value)
    enc = s.encode('ascii', errors='replace')
    if len(enc) >= size:
        return enc[:size]
    return enc + b' ' * (size - len(enc))


def _unpack_char(data):
    """고정길이 char 필드 → strip 한 문자열."""
    return data.decode('ascii', errors='replace').replace('\x00', '').strip()


# ── 48B 헤더 패킹/파싱 ────────────────────────────────────────────

def pack_cds_header(msg_id, tid_date, tid_seq,
                    src_sys, dst_sys, src_app, dst_app,
                    cont_flag=0, serial_no=0, data_size=0):
    """
    48 Byte CDS 헤더 생성 (big-endian 정수 필드).
    tid_date : 'YYYYMMDD' (8자) / tid_seq : 정수(최초 접속시 0)
    """
    buf = bytearray()
    buf += struct.pack('>I', int(msg_id))            # Message ID
    buf += _pack_char(tid_date, 8)                   # TID date(8)
    buf += struct.pack('>I', int(tid_seq))           # TID seq(4)
    buf += _pack_char(src_sys, 6)                     # Source System ID
    buf += _pack_char(dst_sys, 6)                     # Destination System ID
    buf += _pack_char(src_app, 6)                     # Source Application ID
    buf += _pack_char(dst_app, 6)                     # Destination Application ID
    buf += struct.pack('>H', int(cont_flag))         # Continue Flag
    buf += struct.pack('>H', int(serial_no))         # Serial No
    buf += struct.pack('>I', int(data_size))         # Data Size
    return bytes(buf)


def parse_cds_header(header_bytes):
    """48 Byte CDS 헤더 파싱 → dict."""
    if len(header_bytes) != HEADER_SIZE:
        raise ConnectionClosed(
            f"CDS 헤더 크기 오류: {len(header_bytes)} bytes (expected {HEADER_SIZE})"
        )
    msg_id   = struct.unpack('>I', header_bytes[0:4])[0]
    tid_date = _unpack_char(header_bytes[4:12])
    tid_seq  = struct.unpack('>I', header_bytes[12:16])[0]
    src_sys  = _unpack_char(header_bytes[16:22])
    dst_sys  = _unpack_char(header_bytes[22:28])
    src_app  = _unpack_char(header_bytes[28:34])
    dst_app  = _unpack_char(header_bytes[34:40])
    cont_flag = struct.unpack('>H', header_bytes[40:42])[0]
    serial_no = struct.unpack('>H', header_bytes[42:44])[0]
    data_size = struct.unpack('>I', header_bytes[44:48])[0]
    return {
        'msg_id':     msg_id,
        'tid_date':   tid_date,
        'tid_seq':    tid_seq,
        'src_sys':    src_sys,
        'dst_sys':    dst_sys,
        'src_app':    src_app,
        'dst_app':    dst_app,
        'cont_flag':  cont_flag,
        'serial_no':  serial_no,
        'data_size':  data_size,
    }


# ── 송수신 (헤더 48B + Data) ──────────────────────────────────────

def send_cds(sock, msg_id, tid_date, tid_seq,
             src_sys, dst_sys, src_app='', dst_app='',
             data=b'', cont_flag=0, serial_no=0):
    """
    CDS 메시지 송신. Data Size 는 data 길이로 자동 계산.
    data 가 문자열이면 ASCII 로 인코딩한다.
    """
    if not is_connected(sock):
        raise ConnectionClosed("소켓이 이미 닫혀 있습니다")
    if data is None:
        data = b''
    if isinstance(data, str):
        data = data.encode('ascii', errors='replace')
    header = pack_cds_header(
        msg_id, tid_date, tid_seq, src_sys, dst_sys, src_app, dst_app,
        cont_flag=cont_flag, serial_no=serial_no, data_size=len(data),
    )
    try:
        sock.sendall(header + data)
    except (OSError, BrokenPipeError) as e:
        raise ConnectionClosed(f"소켓 전송 오류: {e}") from e


def receive_cds(sock):
    """
    CDS 메시지 수신 → (header_dict, data_bytes).
    48B 헤더 수신 후 Data Size 만큼 Data 수신.
    """
    hdr_bytes = _recv_exact(sock, HEADER_SIZE)
    hdr = parse_cds_header(hdr_bytes)
    data = _recv_exact(sock, hdr['data_size']) if hdr['data_size'] > 0 else b''
    return hdr, data


# ── Data 섹션 패킹/언패킹 ─────────────────────────────────────────

def pack_ack(result, reason=0, tid_date=None, tid_seq=None):
    """
    ACK Data 생성.
      - Result char(2) + Reason uint16(2)                         → 4B
      - ConnectionRequestACK 는 뒤에 TID(date char8 + seq uint32) → 16B
        (tid_date/tid_seq 를 주면 포함)
    """
    buf = bytearray()
    buf += _pack_char(result, 2)
    buf += struct.pack('>H', int(reason))
    if tid_date is not None or tid_seq is not None:
        buf += _pack_char(tid_date, 8)
        buf += struct.pack('>I', int(tid_seq or 0))
    return bytes(buf)


def unpack_ack(data):
    """
    ACK Data 파싱 → dict(result, reason[, tid_date, tid_seq]).
    길이에 따라 4B(Result/Reason) 또는 16B(+TID) 처리.
    """
    result = {}
    if len(data) >= 4:
        result['result'] = _unpack_char(data[0:2])
        result['reason'] = struct.unpack('>H', data[2:4])[0]
    if len(data) >= 16:
        result['tid_date'] = _unpack_char(data[4:12])
        result['tid_seq']  = struct.unpack('>I', data[12:16])[0]
    return result


def pack_process_state(state):
    """ProcessStateRequestACK Data: Process State uint16(2)."""
    return struct.pack('>H', int(state))


def unpack_process_state(data):
    """ProcessStateRequestACK Data 파싱 → 정수(1=Normal, 2=Abnormal)."""
    if len(data) < 2:
        raise ConnectionClosed(f"ProcessState Data 크기 오류: {len(data)} bytes")
    return struct.unpack('>H', data[0:2])[0]


def pack_result_data(result, payload=b''):
    """
    CommandResult / *Result 류 Data: Result char(2) + 가변 payload.
    """
    if payload is None:
        payload = b''
    if isinstance(payload, str):
        payload = payload.encode('ascii', errors='replace')
    return _pack_char(result, 2) + payload


def unpack_result_data(data):
    """Result char(2) + 가변 payload → dict(result, payload)."""
    return {
        'result':  _unpack_char(data[0:2]) if len(data) >= 2 else '',
        'payload': data[2:] if len(data) > 2 else b'',
    }
