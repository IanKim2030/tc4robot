"""
RtsHelper.py  —  RTS(로밍 데이터/mVoIP 차단) 인터페이스 헬퍼
===============================================================

PG 내부 공식 명칭은 **RTS**다(PG 소스 `RTS/` 디렉토리, 클래스 `CRts`/`CRtsDB`/
`CRtsPacket`, 로그 태그 "RTS" — 전부 소스로 확인). CDS 문서에 등장하는 "PG.RDS"
(쿠폰 예약작업 폴러, `RDS/`/`RDS_5G/`, K1→K3 만료 처리)와는 **완전히 별개**의
인터페이스다 — 이름이 비슷해서 혼동하기 쉬우니 절대 같은 것으로 취급하지 말 것.

  방향   : 도구(RTS) → PG.RTS 접속 (능동 Connector, PG=서버)
  헤더   : 32 Byte 고정 (RTS/RtsDefine.hpp `stNePacket`)
  포트   : ${RTS_PG_PORT} — PG_V2.cfg [RTS] 섹션의 런타임 설정값이라 소스에
           하드코딩이 없다. 실측 전까지는 미검증 추정치를 쓴다(확인 필요).

이번 구현 범위는 실제 운영에서 쓰인다고 확인된 **SVC_CODE=L1(로밍 데이터 차단
ON)/L2(차단 해제)뿐**이다. L3/L4(mVoIP 차단)·L5~LE(QoS)는 PG 소스에 처리 분기가
살아있으나 미사용 확인됨 — TODO 로만 남긴다.

[32B 헤더 구조 — RTS/RtsDefine.hpp `stNePacket` / `struct.pack('>I8sI6s6sI', ...)`]
  Message ID            (4,  uint32 BE)
  Transaction ID Date    (8,  char, YYYYMMDD — 바이트스왑 없이 그대로)
  Transaction ID Seq     (4,  uint32 BE)
  Source System ID       (6,  char, 공백 패딩)
  Destination System ID  (6,  char, 공백 패딩)
  Data Size              (4,  uint32 BE)

  msg_id: 1=Connect Req, 2=Connect Ack, 5=Keepalive Req, 6=Keepalive Ack,
          9=Release, 11=Order Req, 12=Order Ack (RtsDefine.hpp)

[★ 이중 오프셋 구조 — 이 헬퍼의 핵심 함정, PG 소스로 확정]
  RTS/CDownMessage.cpp `RecvCommandRequest` 가 서로 다른 두 버퍼를 다룬다.

  1) 와이어(수신) 오프셋 — 도구가 보내는 Order Body 그대로. GenRts.py 레거시
     시뮬레이터의 레이아웃과 100% 일치한다:
       offset 0  SVC_CODE   (2B ASCII "L1"/"L2")
       offset 2  MDN        (12B, 공백 우측 패딩)
       offset 14 로밍 차단  (1B, L1/L2 전용)
       offset 15 mVoIP 차단 (1B, L3/L4 전용 — 이번 범위 아님)
       offset 16 QoS Param  (1B, L5~LE 전용 — 이번 범위 아님)

  2) DB 저장 오프셋 — PG 가 265B(RTS_DATA_SIZE)로 재조립해
     `T_RTS_ORDER_HIST.ORDER_DATA` 컬럼에 넣을 때 쓰는 **별도 버퍼**의 위치
     (RtsDefine.hpp `LOC_DATA_*`):
       offset 85  로밍 차단
       offset 86  mVoIP 차단
       offset 110 QoS Param
     SVC_CODE(0)/MDN(2)만 두 레이어의 오프셋이 우연히 같다.

  두 상수 세트는 이름부터 분리한다 — 절대 섞지 말 것
  (`RTS_WIRE_LOC_*` = 우리가 보내는 값, `RTS_DB_OFS_*` = PDB 조회 시 잘라볼 위치).

[MDN 함정]
  RTS/CDownMessage.cpp `attachMDN`: 11번째 문자(인덱스 10)가 공백이면 10자리
  MDN 을 11자리로 재배치하는 분기를 탄다. TC 데이터는 **11자리 MDN**(01+9자리)
  으로 통일해 이 분기를 피한다.

소켓 수명주기/수신 헬퍼는 TcpHelper(클라이언트 모드)를 재사용한다.
"""

import socket
import struct

from TcpHelper import (          # 소켓 생성/종료/상태/정확수신 재사용
    tcp_connect,
    tcp_close,
    is_connected,
    _recv_exact,
    ConnectionClosed,
)

HEADER_SIZE = 32

# ── 와이어(수신) 오프셋 — Order Body 안에서 도구가 채우는 위치 ─────────
RTS_WIRE_LOC_SVC     = 0    # 2B
RTS_WIRE_LOC_MDN     = 2    # 12B
RTS_WIRE_LOC_ROAMING = 14   # 1B (L1/L2)
RTS_WIRE_LOC_MVOIP   = 15   # 1B (L3/L4, 범위 밖)
RTS_WIRE_LOC_QOS     = 16   # 1B (L5~LE, 범위 밖)
RTS_WIRE_BODY_SIZE   = 17   # L1/L2 송신에는 이 폭이면 충분

# ── DB 저장 오프셋 — T_RTS_ORDER_HIST.ORDER_DATA(265B) 내부 위치 ───────
# 절대 위 와이어 오프셋과 섞지 말 것. PDB 검증(Verify RTS Order In PDB)에서만 쓴다.
RTS_DB_OFS_ROAMING = 85
RTS_DB_OFS_MVOIP   = 86
RTS_DB_OFS_QOS     = 110


# ── 내부: char 고정길이 필드 패킹/언패킹 ──────────────────────────

def _pack_char(value, size, encoding='ascii'):
    """고정길이 필드: size 초과는 자르고, 미만은 공백 패딩."""
    s = '' if value is None else str(value)
    enc = s.encode(encoding, errors='replace')
    if len(enc) >= size:
        return enc[:size]
    return enc + b' ' * (size - len(enc))


def _unpack_char(data, encoding='ascii'):
    """고정길이 char 필드 → strip 한 문자열."""
    return data.decode(encoding, errors='replace').replace('\x00', '').strip()


# ── 32B 헤더 패킹/파싱 ────────────────────────────────────────────

def pack_rts_header(msg_id, tid_date, tid_seq, src_sys, dst_sys, data_size=0):
    """
    32 Byte RTS 헤더 생성 (big-endian 정수 필드).
    tid_date : 'YYYYMMDD' (8자) / tid_seq : 정수(최초 접속시 0)
    """
    buf = bytearray()
    # CdsHelper.py / TcpHelper.py 와 동일 컨벤션: htonl/htons 후 '<' 로 패킹
    buf += struct.pack('<I', socket.htonl(int(msg_id)))      # Message ID
    buf += _pack_char(tid_date, 8)                           # TID date(8)
    buf += struct.pack('<I', socket.htonl(int(tid_seq)))     # TID seq(4)
    buf += _pack_char(src_sys, 6)                             # Source System ID
    buf += _pack_char(dst_sys, 6)                             # Destination System ID
    buf += struct.pack('<I', socket.htonl(int(data_size)))   # Data Size
    return bytes(buf)


def parse_rts_header(header_bytes):
    """32 Byte RTS 헤더 파싱 → dict."""
    if len(header_bytes) != HEADER_SIZE:
        raise ConnectionClosed(
            f"RTS 헤더 크기 오류: {len(header_bytes)} bytes (expected {HEADER_SIZE})"
        )
    msg_id   = socket.ntohl(struct.unpack('<I', header_bytes[0:4])[0])
    tid_date = _unpack_char(header_bytes[4:12])
    tid_seq  = socket.ntohl(struct.unpack('<I', header_bytes[12:16])[0])
    src_sys  = _unpack_char(header_bytes[16:22])
    dst_sys  = _unpack_char(header_bytes[22:28])
    data_size = socket.ntohl(struct.unpack('<I', header_bytes[28:32])[0])
    return {
        'msg_id':    msg_id,
        'tid_date':  tid_date,
        'tid_seq':   tid_seq,
        'src_sys':   src_sys,
        'dst_sys':   dst_sys,
        'data_size': data_size,
    }


# ── 송수신 (헤더 32B + Data) ──────────────────────────────────────

def send_rts(sock, msg_id, tid_date, tid_seq, src_sys, dst_sys, data=b''):
    """RTS 메시지 송신. Data Size 는 data 길이로 자동 계산."""
    if not is_connected(sock):
        raise ConnectionClosed("소켓이 이미 닫혀 있습니다")
    if data is None:
        data = b''
    if isinstance(data, str):
        data = data.encode('ascii', errors='replace')
    header = pack_rts_header(
        msg_id, tid_date, tid_seq, src_sys, dst_sys, data_size=len(data),
    )
    try:
        sock.sendall(header + data)
    except (OSError, BrokenPipeError) as e:
        raise ConnectionClosed(f"소켓 전송 오류: {e}") from e


def receive_rts(sock):
    """RTS 메시지 수신 → (header_dict, data_bytes). 32B 헤더는 항상 붙는다."""
    hdr_bytes = _recv_exact(sock, HEADER_SIZE)
    hdr = parse_rts_header(hdr_bytes)
    data = _recv_exact(sock, hdr['data_size']) if hdr['data_size'] > 0 else b''
    return hdr, data


# ── Order Body(요청) 패킹 — 와이어 오프셋 0/2/14 ──────────────────

def pack_rts_order_body(svc_code, mdn, roaming_block):
    """
    Order(11) Data 생성. L1/L2 전용 — mvoip/qos 는 공백으로 채운다.
      svc_code      : "L1" / "L2"
      mdn           : 11자리 권장 (attachMDN 10자리 재배치 분기 회피)
      roaming_block : 'Y'/'N' 1글자
    """
    buf = bytearray(b' ' * RTS_WIRE_BODY_SIZE)
    buf[RTS_WIRE_LOC_SVC:RTS_WIRE_LOC_SVC + 2] = _pack_char(svc_code, 2)
    buf[RTS_WIRE_LOC_MDN:RTS_WIRE_LOC_MDN + 12] = _pack_char(mdn, 12)
    buf[RTS_WIRE_LOC_ROAMING:RTS_WIRE_LOC_ROAMING + 1] = _pack_char(roaming_block, 1)
    return bytes(buf)


def unpack_rts_order_body(data):
    """Order Body 파싱(자체 검증/build TC 용) → dict(svc_code, mdn, roaming_block)."""
    return {
        'svc_code':      _unpack_char(data[RTS_WIRE_LOC_SVC:RTS_WIRE_LOC_SVC + 2]),
        'mdn':           _unpack_char(data[RTS_WIRE_LOC_MDN:RTS_WIRE_LOC_MDN + 12]),
        'roaming_block': _unpack_char(
            data[RTS_WIRE_LOC_ROAMING:RTS_WIRE_LOC_ROAMING + 1]),
    }


# ── Ack Body 파싱 — msg_id 별로 폭이 다르므로 분리 ─────────────────

def unpack_connect_ack(data):
    """
    Connect Ack(2) Data 파싱 → dict. 16B = RESULT(2)+REASON(2)+tid_date(8)+tid_seq(4).
    """
    if len(data) < 16:
        raise ConnectionClosed(f"Connect Ack Data 크기 오류: {len(data)} bytes (expected 16)")
    return {
        'result':   _unpack_char(data[0:2]),
        'reason':   socket.ntohs(struct.unpack('<H', data[2:4])[0]),
        'tid_date': _unpack_char(data[4:12]),
        'tid_seq':  socket.ntohl(struct.unpack('<I', data[12:16])[0]),
    }


def unpack_order_ack(data):
    """Order Ack(12) Data 파싱 → dict. 4B = RESULT(2)+REASON(2)."""
    if len(data) < 4:
        raise ConnectionClosed(f"Order Ack Data 크기 오류: {len(data)} bytes (expected 4)")
    return {
        'result': _unpack_char(data[0:2]),
        'reason': socket.ntohs(struct.unpack('<H', data[2:4])[0]),
    }


def unpack_keepalive_ack(data):
    """
    Keepalive Ack(6) Data 파싱 → dict. **2B, REASON 만 있고 RESULT 문자열은 없다**
    (RTS/CDownMessage.cpp `SetBody(0, 2)` 한 줄 — Order Ack 과 폭이 다르다).
    """
    if len(data) < 2:
        raise ConnectionClosed(f"Keepalive Ack Data 크기 오류: {len(data)} bytes (expected 2)")
    return {
        'reason': socket.ntohs(struct.unpack('<H', data[0:2])[0]),
    }
