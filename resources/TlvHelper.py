"""
TlvHelper.py  —  NWDAF 연동 헬퍼 (TLV 바이너리 Body)
=====================================================

[NWDAF 인터페이스 개요]
  - 방향   : NWDAF → PG (Notification 주력, 응답 사실상 없음)
  - 포트   : ${NWDAF_PORT} (실환경 확인 필요)
  - 헤더   : 8 Octet, Big Endian (SKT PG-SC Message Format 규격)
  - Body   : MULTI_MESSAGE(0xFF) TLV 하나로 inner TLV 스트림을 감싼 형태

[헤더 구조 (8 Octet, Big Endian)]
  Byte 0      : bitfield
                ├─ a: Extension Header (1 bit)   보통 0
                ├─ b: Protocol Version (2 bit)   보통 0b00
                ├─ c: Header Type      (2 bit)   보통 0b00
                └─ d: Message Type     (3 bit)
                      0b001(0x01) = Request
                      0b100(0x04) = Response
                      0b010(0x02) = Notification  ← NWDAF 주력
  Byte 1-2    : Service Id    (2 octet, Big Endian)
  Byte 3-5    : Message Id    (3 octet, Big Endian, 0x000~0xFFF 순환)
  Byte 6-7    : Body Length   (2 octet, Big Endian)

[TLV 인코딩 두 모드]
  일반 TLV (Tag MSB=0, 0x00~0x7F)
      [Tag(1B)] [Length(1B)]   [Value(Length B)]
  Multi TLV (Tag MSB=1, 0x80~0xFF)
      [Tag(1B)] [Length(2B,BE)] [Value(TLV 스트림)]

[기존 TcpHelper.py 와의 관계]
  - 소켓 송수신 자체는 NWDAF Client 모드에서도 동일한 패턴(create_connection/sendall/recv)
    이지만 헤더/Body 포맷이 NAG/PCF/LRS/UPM 과 완전히 다르므로 별도 모듈로 분리한다.
  - Notification 단방향이라 send 만 본격 구현. 응답 수신은 호환을 위해 제공.
"""

import socket
import struct


# ── 예외 ──────────────────────────────────────────────────────────

class NwdafConnectionClosed(RuntimeError):
    """NWDAF 소켓이 닫혔거나 에러 발생"""
    pass


class TlvParseError(RuntimeError):
    """TLV 파싱 실패"""
    pass


# ── Message Type / Service Id 상수 ────────────────────────────────

MSG_TYPE_REQ  = 0b001  # 0x01
MSG_TYPE_RESP = 0b100  # 0x04
MSG_TYPE_NOTI = 0b010  # 0x02

SERVICE_ID_SUBSCRIBER = 0x0305
SERVICE_ID_CELL       = 0x0306
SERVICE_ID_SERVICE    = 0x0307


# ── 소켓 (NAG/PCF/UPM 과 동일한 Client 패턴) ─────────────────────

def nwdaf_connect(host: str, port, timeout=30):
    """NWDAF Client → PG TCP 연결"""
    return socket.create_connection((host, int(port)), timeout=float(timeout))


def nwdaf_close(sock):
    """NWDAF 소켓 종료"""
    try:
        sock.close()
    except Exception:
        pass


def nwdaf_is_connected(sock) -> bool:
    """소켓 연결 여부 확인"""
    try:
        return sock.fileno() != -1
    except Exception:
        return False


def _recv_exact(sock, n: int) -> bytes:
    """정확히 n 바이트 수신. 연결 끊기면 NwdafConnectionClosed."""
    buf = bytearray()
    n = int(n)
    while len(buf) < n:
        try:
            chunk = sock.recv(n - len(buf))
        except (OSError, ConnectionResetError) as e:
            raise NwdafConnectionClosed(f"소켓 수신 오류: {e}") from e
        if not chunk:
            raise NwdafConnectionClosed(
                f"연결이 종료됐습니다 (수신 {len(buf)}/{n} bytes)"
            )
        buf.extend(chunk)
    return bytes(buf)


# ── 헤더 ──────────────────────────────────────────────────────────

def build_nwdaf_header(msg_type: int, service_id: int, message_id: int,
                       body_length: int, ext: int = 0,
                       proto_ver: int = 0, header_type: int = 0) -> bytes:
    """
    8 Octet NWDAF 헤더 생성 (Big Endian)

    msg_type    : 0b001/0b100/0b010 (Request/Response/Notification)
    service_id  : 0x0305 / 0x0306 / 0x0307
    message_id  : 0x000~0xFFF (호출자가 순환 관리)
    body_length : Body(TLV stream) 총 바이트
    """
    msg_type    = int(msg_type)    & 0b111
    ext         = int(ext)         & 0b1
    proto_ver   = int(proto_ver)   & 0b11
    header_type = int(header_type) & 0b11
    byte0 = (ext << 7) | (proto_ver << 5) | (header_type << 3) | msg_type

    service_id = int(service_id) & 0xFFFF
    message_id = int(message_id) & 0xFFFFFF
    body_length = int(body_length) & 0xFFFF

    return struct.pack(
        '>BHBHH',
        byte0,
        service_id,
        (message_id >> 16) & 0xFF,        # MsgId high byte
        message_id & 0xFFFF,              # MsgId low 2 bytes
        body_length,
    )


def parse_nwdaf_header(buf: bytes) -> dict:
    """8 Octet NWDAF 헤더 파싱 (Big Endian)"""
    if len(buf) != 8:
        raise TlvParseError(f"헤더 크기 오류: {len(buf)} bytes (expected 8)")
    byte0, service_id, mid_hi, mid_lo, body_length = struct.unpack(
        '>BHBHH', buf
    )
    message_id = (mid_hi << 16) | mid_lo
    return {
        'byte0':       byte0,
        'ext':         (byte0 >> 7) & 0b1,
        'proto_ver':   (byte0 >> 5) & 0b11,
        'header_type': (byte0 >> 3) & 0b11,
        'msg_type':    byte0 & 0b111,
        'service_id':  service_id,
        'message_id':  message_id,
        'body_length': body_length,
    }


# ── TLV pack/unpack (Tag MSB 자동 분기) ──────────────────────────

def pack_tlv(tag: int, value: bytes) -> bytes:
    """
    일반 TLV 또는 Multi TLV 인코딩 (Tag MSB 로 자동 판정)
      - Tag MSB=0 (0x00~0x7F): Length 1B
      - Tag MSB=1 (0x80~0xFF): Length 2B Big Endian
    """
    tag = int(tag) & 0xFF
    value = bytes(value)
    if tag & 0x80:
        if len(value) > 0xFFFF:
            raise ValueError(f"Multi TLV value too long: {len(value)}")
        return struct.pack('>BH', tag, len(value)) + value
    else:
        if len(value) > 0xFF:
            raise ValueError(f"TLV value too long for 1B length: {len(value)}")
        return struct.pack('>BB', tag, len(value)) + value


def unpack_tlv(buf: bytes, offset: int = 0) -> tuple:
    """
    한 개 TLV 디코딩. Tag MSB 로 자동 판정.
    반환: (tag, length, value, new_offset)
    """
    if offset >= len(buf):
        raise TlvParseError(f"버퍼 끝 도달 (offset={offset}, len={len(buf)})")
    tag = buf[offset]
    if tag & 0x80:
        if offset + 3 > len(buf):
            raise TlvParseError("Multi TLV 헤더 부족")
        length = struct.unpack('>H', buf[offset+1:offset+3])[0]
        v_start = offset + 3
    else:
        if offset + 2 > len(buf):
            raise TlvParseError("TLV 헤더 부족")
        length = buf[offset+1]
        v_start = offset + 2
    v_end = v_start + length
    if v_end > len(buf):
        raise TlvParseError(
            f"TLV value 길이 부족: need {length}, have {len(buf) - v_start}"
        )
    return tag, length, buf[v_start:v_end], v_end


def unpack_tlv_stream(buf: bytes) -> list:
    """TLV 스트림 전체 디코딩 → [(tag, length, value), ...]"""
    out = []
    off = 0
    while off < len(buf):
        tag, length, value, off = unpack_tlv(buf, off)
        out.append((tag, length, value))
    return out


# ── Typed packers (Value 인코딩 별로) ────────────────────────────

def pack_uint8(tag: int, val: int) -> bytes:
    return pack_tlv(tag, struct.pack('>B', int(val) & 0xFF))


def pack_uint16(tag: int, val: int) -> bytes:
    return pack_tlv(tag, struct.pack('>H', int(val) & 0xFFFF))


def pack_uint24(tag: int, val: int) -> bytes:
    v = int(val) & 0xFFFFFF
    return pack_tlv(tag, struct.pack('>BH', (v >> 16) & 0xFF, v & 0xFFFF))


def pack_uint32(tag: int, val: int) -> bytes:
    return pack_tlv(tag, struct.pack('>I', int(val) & 0xFFFFFFFF))


def pack_string(tag: int, val: str) -> bytes:
    """가변 길이 ASCII 문자열 (NULL 종결 미포함)"""
    s = '' if val is None else str(val)
    return pack_tlv(tag, s.encode('ascii', errors='replace'))


def pack_string_fixed(tag: int, val: str, length: int) -> bytes:
    """고정 길이 문자열 (부족하면 공백 패딩, 초과하면 자름)"""
    s = '' if val is None else str(val)
    encoded = s.encode('ascii', errors='replace')
    length = int(length)
    if len(encoded) >= length:
        encoded = encoded[:length]
    else:
        encoded = encoded + b' ' * (length - len(encoded))
    return pack_tlv(tag, encoded)


def pack_bytes(tag: int, val: bytes) -> bytes:
    """원시 바이트 값을 그대로 TLV 로 감싸기"""
    return pack_tlv(tag, bytes(val))


# ── Multi TLV (Tag MSB=1, 대표적으로 0xFF MULTI_MESSAGE) ─────────

def pack_multi_message(tlv_list) -> bytes:
    """
    MULTI_MESSAGE(0xFF) TLV 생성.
    tlv_list: 이미 pack_tlv 등으로 인코딩된 bytes 리스트
    """
    inner = b''.join(bytes(t) for t in tlv_list)
    return pack_tlv(0xFF, inner)


def unpack_multi_message(value: bytes) -> list:
    """MULTI_MESSAGE value(=TLV 스트림) 를 [(tag, length, value), ...] 로 분해"""
    return unpack_tlv_stream(value)


# ══════════════════════════════════════════════════════════════════
# QOS_HDR (TAG=0x3A) PCEF 별 빌더
# ──────────────────────────────────────────────────────────────────
# 주의:
#   PCEF별 내부 서브 TLV 순서/태그는 C++ 코드(CNWQosGateway::ParsingPacket)
#   기반 "추정"이며 규격서에 명시되지 않음. 운영 PG 대상 검증 후 확정 필요.
#   - PGW: QOS_POLICY(0x10) → STATUS(0x0C, LoadStatus 의미)
#          → TIMER(0x20)    → QUICK_SUPPORT(0x3B)
#   - DPI: (CATEGORY(0x3E) + QOS_POLICY(0x10)) × N
#          → STATUS(0x0C)   → TIMER(0x20) → QUICK_SUPPORT(0x3B)
#   - ENB: SUPPORT_TYPE(0x41) → ARP_QCI_FLAG(0x3F) → ENB_ARP(0x3C)
#          → ARP_CAPABILITY(0x42) → ARP_VULNERABILITY(0x43)
#          → QCI(0x11)      → TIMER(0x20)
#   - VOMS/APRS: 규격 추가 확인 필요 (placeholder)
# ══════════════════════════════════════════════════════════════════

# TLV 태그 상수 (5절 catalog)
TAG_MIN                = 0x01
TAG_MDN                = 0x02
TAG_MSISDN             = 0x03
TAG_IMSI               = 0x04
TAG_PRODUCT_ID         = 0x05
TAG_PRODUCT_NAME       = 0x06
TAG_DATA_USAGE_LEVEL   = 0x07
TAG_CREATE_DATE        = 0x08
TAG_CREATE_TIME        = 0x09
TAG_PROCESS_TYPE       = 0x0A
TAG_LOCATION_ID        = 0x0B
TAG_STATUS             = 0x0C
TAG_PCEF_TYPE          = 0x0D
TAG_QOS_CONTROL_TYPE   = 0x0E
TAG_PGW_IP_ADDRESS     = 0x0F
TAG_QOS_POLICY         = 0x10
TAG_QCI                = 0x11
TAG_APP_TYPE           = 0x12
TAG_PGW_HOST_NAME      = 0x13
TAG_TOTAL_USAGE        = 0x14
TAG_TOTAL_USER         = 0x15
TAG_IN_USER            = 0x16
TAG_OUT_USER           = 0x17
TAG_TRY_USER           = 0x18
TAG_TRY_COUNT          = 0x19
TAG_CONCURRENT_USER    = 0x1A
TAG_UP_TOTAL_USAGE     = 0x1B
TAG_UP_TOTAL_USER      = 0x1C
TAG_DN_TOTAL_USAGE     = 0x1D
TAG_DN_TOTAL_USER      = 0x1E
TAG_NETWORK            = 0x1F
TAG_TIMER              = 0x20
TAG_TIMESTAMP          = 0x21
TAG_IMSI_MCC_MNC       = 0x22
TAG_DEVICE_IP          = 0x23
TAG_USER_OPERATION     = 0x24
TAG_RESULT             = 0x25
TAG_REASON             = 0x26
TAG_IP_VERSION         = 0x27
TAG_PGW_GROUP_ID       = 0x28
TAG_CA_SUPPORTED_DEV   = 0x29
TAG_CA_CATEGORY        = 0x2A
TAG_RULE_BASED_NAME    = 0x2B
TAG_LIMIT_OVER         = 0x2C
TAG_PCRF_HOST_NAME     = 0x2D
TAG_ROAMING            = 0x2E
TAG_NAT_IP             = 0x2F
TAG_TRANSACTION_ID     = 0x30
TAG_DN_USAGE           = 0x31
TAG_HEAVY_USER         = 0x32
TAG_MEDIUM_USER        = 0x33
TAG_LIGHT_USER         = 0x34
TAG_CELL_AVG_USAGE     = 0x35
TAG_USER_USAGE         = 0x36
TAG_USER_RATIO         = 0x37
TAG_RCT_3M_USAGE       = 0x38
TAG_RCT_1M_USAGE       = 0x39
TAG_QOS_HDR            = 0x3A
TAG_QUICK_SUPPORT      = 0x3B
TAG_ENB_ARP            = 0x3C
TAG_SERVICE_TYPE       = 0x3D
TAG_CATEGORY           = 0x3E
TAG_ARP_QCI_FLAG       = 0x3F
TAG_CONTROL_UNIT       = 0x40
TAG_SUPPORT_TYPE       = 0x41
TAG_ARP_CAPABILITY     = 0x42
TAG_ARP_VULNERABILITY  = 0x43

TAG_MULTI_MESSAGE      = 0xFF

# PCEF Type (QOS_HDR 첫 서브 필드 / PCEF_TYPE 값)
PCEF_PGW   = 0x01
PCEF_DPI   = 0x02
PCEF_VOMS  = 0x04
PCEF_APRS  = 0x08
PCEF_ENB   = 0x10


def pack_qos_hdr_pgw(qos_policy: str, load_status: int,
                     valid_timer: int, quick_support: int) -> bytes:
    """
    QOS_HDR(0x3A) PGW(0x01) 서브 TLV 구성 (추정).
    TODO: 운영 PG 검증 후 서브 구조/순서 확정.
    """
    inner = b''.join([
        pack_uint8(TAG_PCEF_TYPE,    PCEF_PGW),
        pack_string(TAG_QOS_POLICY,  qos_policy),
        pack_uint8(TAG_STATUS,       load_status),
        pack_uint16(TAG_TIMER,       valid_timer),
        pack_uint8(TAG_QUICK_SUPPORT, quick_support),
    ])
    return pack_tlv(TAG_QOS_HDR, inner)


def pack_qos_hdr_dpi(categories, policies, load_status: int,
                     valid_timer: int, quick_support: int) -> bytes:
    """
    QOS_HDR(0x3A) DPI(0x02) 서브 TLV 구성 (추정).
    categories: ['cat1', 'cat2', ...]   (최대 6개, 규격 추정)
    policies  : ['QoS200K', ...]        (categories 와 같은 길이)
    TODO: 6쌍 미만일 때 채움/생략 규칙 운영 PG 검증.
    """
    if len(categories) != len(policies):
        raise ValueError(
            f"DPI categories/policies 길이 불일치: {len(categories)} vs {len(policies)}"
        )
    pairs = b''
    for cat, pol in zip(categories, policies):
        pairs += pack_string(TAG_CATEGORY,    cat)
        pairs += pack_string(TAG_QOS_POLICY,  pol)
    inner = (
        pack_uint8(TAG_PCEF_TYPE, PCEF_DPI)
        + pairs
        + pack_uint8(TAG_STATUS,       load_status)
        + pack_uint16(TAG_TIMER,       valid_timer)
        + pack_uint8(TAG_QUICK_SUPPORT, quick_support)
    )
    return pack_tlv(TAG_QOS_HDR, inner)


def pack_qos_hdr_voms(qos_policy: str, load_status: int,
                      valid_timer: int, quick_support: int) -> bytes:
    """
    QOS_HDR(0x3A) VOMS(0x04) — 규격 추가 확인 필요.
    TODO: 임시로 PGW 구조 재사용. 실제 VOMS 서브 필드 확정 후 교체.
    """
    inner = (
        pack_uint8(TAG_PCEF_TYPE,     PCEF_VOMS)
        + pack_string(TAG_QOS_POLICY, qos_policy)
        + pack_uint8(TAG_STATUS,      load_status)
        + pack_uint16(TAG_TIMER,      valid_timer)
        + pack_uint8(TAG_QUICK_SUPPORT, quick_support)
    )
    return pack_tlv(TAG_QOS_HDR, inner)


def pack_qos_hdr_aprs(qos_policy: str, load_status: int,
                      valid_timer: int, quick_support: int) -> bytes:
    """
    QOS_HDR(0x3A) APRS(0x08) — 규격 추가 확인 필요.
    TODO: 임시로 PGW 구조 재사용. 실제 APRS 서브 필드 확정 후 교체.
    """
    inner = (
        pack_uint8(TAG_PCEF_TYPE,     PCEF_APRS)
        + pack_string(TAG_QOS_POLICY, qos_policy)
        + pack_uint8(TAG_STATUS,      load_status)
        + pack_uint16(TAG_TIMER,      valid_timer)
        + pack_uint8(TAG_QUICK_SUPPORT, quick_support)
    )
    return pack_tlv(TAG_QOS_HDR, inner)


def pack_qos_hdr_enb(support_type: int, arp_qci_flag: int, enb_arp: int,
                     capability: int, vulnerability: int,
                     qci: str, valid_timer: int) -> bytes:
    """
    QOS_HDR(0x3A) eNB(0x10) 서브 TLV 구성 (추정).
    TODO: 운영 PG 검증 후 서브 구조/순서 확정.
    """
    inner = b''.join([
        pack_uint8(TAG_PCEF_TYPE,        PCEF_ENB),
        pack_uint8(TAG_SUPPORT_TYPE,     support_type),
        pack_uint8(TAG_ARP_QCI_FLAG,     arp_qci_flag),
        pack_uint8(TAG_ENB_ARP,          enb_arp),
        pack_uint8(TAG_ARP_CAPABILITY,   capability),
        pack_uint8(TAG_ARP_VULNERABILITY, vulnerability),
        pack_string(TAG_QCI,             qci),
        pack_uint16(TAG_TIMER,           valid_timer),
    ])
    return pack_tlv(TAG_QOS_HDR, inner)


# ══════════════════════════════════════════════════════════════════
# 고수준 메시지 빌더 / 송수신
# ══════════════════════════════════════════════════════════════════

def build_nwdaf_packet(msg_type: int, service_id: int, message_id: int,
                       tlvs) -> bytes:
    """
    완전한 NWDAF 패킷(헤더 + Body) 생성.
    Body 는 inner TLV 들을 MULTI_MESSAGE(0xFF) TLV 하나로 감싼다 (규격).
    즉 Body = [0xFF][Length(2B,BE)][inner TLV 스트림] 단일 TLV.
    tlvs: pack_tlv / pack_uintXX / pack_string / pack_qos_hdr_xxx 등으로 만든
          bytes 들의 시퀀스
    """
    body = pack_multi_message(tlvs)
    header = build_nwdaf_header(msg_type, service_id, message_id, len(body))
    return header + body


def build_nwdaf_notification(service_id: int, message_id: int, tlvs) -> bytes:
    """Notification(0b010) 전용 단축 빌더"""
    return build_nwdaf_packet(MSG_TYPE_NOTI, service_id, message_id, tlvs)


def send_nwdaf_packet(sock, packet: bytes) -> None:
    """이미 직렬화된 NWDAF 패킷을 통째로 송신"""
    if not nwdaf_is_connected(sock):
        raise NwdafConnectionClosed("소켓이 이미 닫혀 있습니다")
    try:
        sock.sendall(bytes(packet))
    except (OSError, BrokenPipeError) as e:
        raise NwdafConnectionClosed(f"소켓 전송 오류: {e}") from e


def send_nwdaf_notification(sock, service_id: int, message_id: int,
                            tlvs) -> int:
    """
    Notification 송신 단축 헬퍼. 실제 송신한 패킷 길이를 반환.
    """
    packet = build_nwdaf_notification(service_id, message_id, tlvs)
    send_nwdaf_packet(sock, packet)
    return len(packet)


def receive_nwdaf_message(sock) -> tuple:
    """
    NWDAF 메시지(Header+Body) 수신.
    반환: (header_dict, body_bytes, tlv_list)
      tlv_list = [(tag, length, value), ...]  (Body 가 비어있으면 [])
    Notification 단방향이라 실사용은 디버그/예외 케이스 한정.
    """
    hdr_bytes = _recv_exact(sock, 8)
    hdr = parse_nwdaf_header(hdr_bytes)
    body_len = hdr['body_length']
    if body_len > 0:
        body = _recv_exact(sock, body_len)
        tlvs = unpack_tlv_stream(body)
    else:
        body = b''
        tlvs = []
    return hdr, body, tlvs


# ══════════════════════════════════════════════════════════════════
# Robot 친화 헬퍼 (Robot 측에서 16진수 문자열로 검증할 때)
# ══════════════════════════════════════════════════════════════════

def hex_dump(data: bytes) -> str:
    """바이트열을 'AA BB CC ...' 형태로 변환 (로그/검증용)"""
    return ' '.join(f'{b:02X}' for b in bytes(data))


def tlv_find(tlvs_or_buf, tag: int):
    """
    첫 매칭 TLV value(bytes) 반환. 없으면 None.
    인자: unpack_tlv_stream 결과 [(tag, length, value), ...] 또는 raw bytes/bytearray.
    Robot 측에서 어느 형태로 넘겨도 동작하도록 양쪽 모두 허용.
    """
    if isinstance(tlvs_or_buf, (bytes, bytearray)):
        tlvs = unpack_tlv_stream(bytes(tlvs_or_buf))
    else:
        tlvs = tlvs_or_buf
    tag = int(tag) & 0xFF
    for t, _l, v in tlvs:
        if t == tag:
            return v
    return None
