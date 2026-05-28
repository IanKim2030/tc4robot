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

SERVICE_ID_SUBSCRIBER = 0x0305    # 가입자 단위 (QOS_CONTROL_TYPE=0x01) — 주 사용


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
# TLV 태그 catalog — 규격 4개 섹션에서 사용하는 태그만 정의.
# 본 catalog 외 태그는 운영 PG 가 인식하지 않을 수 있음.
# ──────────────────────────────────────────────────────────────────
# COMMON1 (필수) — 가입자 식별 + 사용량
TAG_MIN                = 0x01    # string, 가입자 MIN
TAG_MDN                = 0x02    # string, 가입자 MDN
TAG_CREATE_DATE        = 0x08    # string 'YYYYMMDD'
TAG_CREATE_TIME        = 0x09    # string 'HHmmss'
TAG_PCEF_TYPE          = 0x0D    # uint8 0x01=P-GW/SMF, 0x10=eNB
TAG_QOS_CONTROL_TYPE   = 0x0E    # uint8 0x01=가입자 단위
TAG_PGW_IP_ADDRESS     = 0x0F    # string, PGW IP
TAG_RCT_3M_USAGE       = 0x38    # uint32, 0~9,999,999 KB
TAG_RCT_1M_USAGE       = 0x39    # uint32, 0~9,999,999 KB

# pcefQoSCtrl (PCEF_TYPE=0x01) sub-fields
TAG_QOS_HDR            = 0x3A    # uint8 flag: 0x01=PGW, 0x10=eNB (값으로 분기)
TAG_QOS_POLICY         = 0x10    # string, NWDAF→PCRF rule
TAG_STATUS             = 0x0C    # string '0'=Normal '1'=Minor '2'=Major '3'=Critical
TAG_TIMER              = 0x20    # pcef=uint16 sec, enb=string sec (규격 그대로)
TAG_QUICK_SUPPORT      = 0x3B    # string '0'=즉시제어 '1'=update 후

# enodebQoSCtl (PCEF_TYPE=0x10) sub-fields (QOS_HDR/TIMER 는 위와 공유)
TAG_QCI                = 0x11    # uint8
TAG_ENB_ARP            = 0x3C    # uint8 12=Band 3->5/1, 13=Band 1/5->3
TAG_ARP_QCI_FLAG       = 0x3F    # uint8 0=ARP, 1=QCI, 2=ARP&QCI
TAG_SUPPORT_TYPE       = 0x41    # uint8 1=제어, 2=해지
TAG_ARP_CAPABILITY     = 0x42    # uint8 0=Enable, 1=Disable
TAG_ARP_VULNERABILITY  = 0x43    # uint8 0=Enable, 1=Disable

# COMMON2 (필수) — Cell 통계
TAG_CELL_ID            = 0x0B    # string e.g. '123456:0'
TAG_USING_USER         = 0x1A    # uint32 동시 가입자 수
TAG_NETWORK            = 0x1F    # uint8 0=2G,1=WCDMA,2=LTE,3=5G
TAG_DN_USAGE           = 0x31    # uint32, 0~9,999,999 KB
TAG_HEAVY_USER         = 0x32    # uint32
TAG_CELL_AVG_USAGE     = 0x35    # uint32, 0~9,999,999 KB
TAG_USER_USAGE         = 0x36    # uint32, Heavy/Medium/Light 합 KB
TAG_USER_RATIO         = 0x37    # uint8 0=Enable, 1=Disable
TAG_CONTROL_UNIT       = 0x40    # uint8 1=Cell..6=WMSC

# Body wrapper
TAG_MULTI_MESSAGE      = 0xFF

# PCEF_TYPE / QOS_HDR 값 (규격 1.1, 2.1, 3.1)
PCEF_PGW   = 0x01    # P-GW / SMF (pcefQoSCtrl 사용)
PCEF_ENB   = 0x10    # eNB        (enodebQoSCtl 사용)


# ══════════════════════════════════════════════════════════════════
# Section 별 TLV 묶음 빌더
# ──────────────────────────────────────────────────────────────────
# 규격상 Body 구조 = COMMON1 + (pcefQoSCtrl | enodebQoSCtl) + COMMON2
# QOS_HDR(0x3A) 은 wrapper 가 아니라 flat 한 numeric 플래그 TLV 이며,
# 그 값으로 뒤따르는 sub-field 묶음의 의미를 분기한다.
# ══════════════════════════════════════════════════════════════════

def build_common1(pcef_type: int, qos_control_type: int,
                  create_date: str, create_time: str,
                  pgw_ip: str, min_val: str, mdn: str,
                  rct_3m_usage: int, rct_1m_usage: int) -> list:
    """
    COMMON1 (1절, 필수) TLV bytes 리스트.

    pcef_type        : 0x01=P-GW/SMF, 0x10=eNB — 이후 QoSCtrl 분기 결정
    qos_control_type : 0x01=가입자 단위
    create_date      : 'YYYYMMDD'
    create_time      : 'HHmmss'
    pgw_ip           : PGW IP (PG 의 PCRF 선택 입력)
    min_val          : 가입자 MIN
    mdn              : 가입자 MDN
    rct_3m_usage     : 최근 3분 사용량 (KB, 0~9,999,999)
    rct_1m_usage     : 최근 1분 사용량 (KB, 0~9,999,999)
    """
    return [
        pack_uint8 (TAG_PCEF_TYPE,        pcef_type),
        pack_uint8 (TAG_QOS_CONTROL_TYPE, qos_control_type),
        pack_string(TAG_CREATE_DATE,      create_date),
        pack_string(TAG_CREATE_TIME,      create_time),
        pack_string(TAG_PGW_IP_ADDRESS,   pgw_ip),
        pack_string(TAG_MIN,              min_val),
        pack_string(TAG_MDN,              mdn),
        pack_uint32(TAG_RCT_3M_USAGE,     rct_3m_usage),
        pack_uint32(TAG_RCT_1M_USAGE,     rct_1m_usage),
    ]


def build_pcef_qos_ctrl(qos_policy: str, status: str,
                        timer: int, quick_support: str) -> list:
    """
    pcefQoSCtrl (2절, PCEF_TYPE=0x01) TLV bytes 리스트.

    qos_policy    : NWDAF→PCRF rule 문자열
    status        : '0'=Normal '1'=Minor '2'=Major '3'=Critical
    timer         : 0=미사용, >0 이면 sec
    quick_support : '0'=즉시제어, '1'=update 수신 후 제어
    """
    return [
        pack_uint8 (TAG_QOS_HDR,       PCEF_PGW),     # 0x01 flag
        pack_string(TAG_QOS_POLICY,    qos_policy),
        pack_string(TAG_STATUS,        status),
        pack_uint16(TAG_TIMER,         timer),
        pack_string(TAG_QUICK_SUPPORT, quick_support),
    ]


def build_enb_qos_ctrl(support_type: int, arp_qci_flag: int, enb_arp: int,
                       arp_capability: int, arp_vulnerability: int,
                       qci: int, timer: int) -> list:
    """
    enodebQoSCtl (3절, PCEF_TYPE=0x10) TLV bytes 리스트.

    support_type     : 1=제어, 2=해지
    arp_qci_flag     : 0=ARP, 1=QCI, 2=ARP&QCI
    enb_arp          : 12=Band 3->5/1, 13=Band 1/5->3
    arp_capability   : 0=Enable, 1=Disable
    arp_vulnerability: 0=Enable, 1=Disable
    qci              : QCI 값
    timer            : sec (규격 3.8 은 string 명시 → ASCII 십진수로 인코딩)
    """
    return [
        pack_uint8 (TAG_QOS_HDR,           PCEF_ENB),    # 0x10 flag
        pack_uint8 (TAG_SUPPORT_TYPE,      support_type),
        pack_uint8 (TAG_ARP_QCI_FLAG,      arp_qci_flag),
        pack_uint8 (TAG_ENB_ARP,           enb_arp),
        pack_uint8 (TAG_ARP_CAPABILITY,    arp_capability),
        pack_uint8 (TAG_ARP_VULNERABILITY, arp_vulnerability),
        pack_uint8 (TAG_QCI,               qci),
        pack_string(TAG_TIMER,             str(int(timer))),
    ]


def build_common2(network: int, control_unit: int, cell_id: str,
                  dn_usage: int, using_user: int, cell_avg_usage: int,
                  heavy_user: int, user_usage: int, user_ratio: int) -> list:
    """
    COMMON2 (4절, 필수) TLV bytes 리스트.

    network        : 0=2G, 1=WCDMA, 2=LTE, 3=5G
    control_unit   : 1=Cell, 2=eNodeB, 3=Sector, 4=NodeB, 5=RNC, 6=WMSC
    cell_id        : '123456:0' 형식
    dn_usage       : 기지국 단위 Download 사용량 (KB)
    using_user     : 동시 가입자 수
    cell_avg_usage : 셀 평균 사용량 (KB)
    heavy_user     : Heavy 가입자 수
    user_usage     : Heavy/Medium/Light 가입자 사용량 합 (KB)
    user_ratio     : 0=Enable, 1=Disable (규격 4.9 원문)
    """
    return [
        pack_uint8 (TAG_NETWORK,        network),
        pack_uint8 (TAG_CONTROL_UNIT,   control_unit),
        pack_string(TAG_CELL_ID,        cell_id),
        pack_uint32(TAG_DN_USAGE,       dn_usage),
        pack_uint32(TAG_USING_USER,     using_user),
        pack_uint32(TAG_CELL_AVG_USAGE, cell_avg_usage),
        pack_uint32(TAG_HEAVY_USER,     heavy_user),
        pack_uint32(TAG_USER_USAGE,     user_usage),
        pack_uint8 (TAG_USER_RATIO,     user_ratio),
    ]


def build_notification_body(common1: list, qos_ctrl: list, common2: list) -> list:
    """
    Notification Body 의 inner TLV 리스트 조립.
    COMMON1 + (pcefQoSCtrl | enodebQoSCtl) + COMMON2 순서.
    반환된 리스트를 send_nwdaf_notification 의 tlvs 인자로 그대로 넘기면 됨.
    """
    return list(common1) + list(qos_ctrl) + list(common2)


# ══════════════════════════════════════════════════════════════════
# 고수준 메시지 빌더 / 송수신
# ══════════════════════════════════════════════════════════════════

def build_nwdaf_packet(msg_type: int, service_id: int, message_id: int,
                       tlvs) -> bytes:
    """
    완전한 NWDAF 패킷(헤더 + Body) 생성.
    Body 는 inner TLV 들을 MULTI_MESSAGE(0xFF) TLV 하나로 감싼다 (규격).
    즉 Body = [0xFF][Length(2B,BE)][inner TLV 스트림] 단일 TLV.
    tlvs: build_notification_body() 가 반환한 리스트, 또는
          build_common1 / build_pcef_qos_ctrl / build_enb_qos_ctrl /
          build_common2 가 반환한 리스트를 이어붙인 bytes 시퀀스.
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
