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
                        ※ 와이어는 12B 지만 PG 는 16자 문자열로 렌더링해 DB PK 로 쓴다.
                          CDS/CDownMessage.cpp:70
                            sprintf(strTid, "%8.8s%08d", tidDate, seqNo);
                          CDS/sql.txt:6  TRANSACTION_ID char(16) PRIMARY KEY
                          → seq 에 HHMMSS*100+일련번호 를 넣으면 16자가
                            YYYYMMDDHHMMSS+NN 이 된다. `Next CDS TID` 참조.
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

import socket
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


# ── 48B 헤더 패킹/파싱 ────────────────────────────────────────────

def pack_cds_header(msg_id, tid_date, tid_seq,
                    src_sys, dst_sys, src_app, dst_app,
                    cont_flag=0, serial_no=0, data_size=0):
    """
    48 Byte CDS 헤더 생성 (big-endian 정수 필드).
    tid_date : 'YYYYMMDD' (8자) / tid_seq : 정수(최초 접속시 0)
    """
    buf = bytearray()
    # 정수 필드는 htonl/htons(host→network) 후 '<' 로 패킹 → wire 는 big-endian
    # (TcpHelper.build_header 와 동일 컨벤션)
    buf += struct.pack('<I', socket.htonl(int(msg_id)))      # Message ID
    buf += _pack_char(tid_date, 8)                           # TID date(8)
    buf += struct.pack('<I', socket.htonl(int(tid_seq)))     # TID seq(4)
    buf += _pack_char(src_sys, 6)                            # Source System ID
    buf += _pack_char(dst_sys, 6)                            # Destination System ID
    buf += _pack_char(src_app, 6)                            # Source Application ID
    buf += _pack_char(dst_app, 6)                            # Destination Application ID
    buf += struct.pack('<H', socket.htons(int(cont_flag)))   # Continue Flag
    buf += struct.pack('<H', socket.htons(int(serial_no)))   # Serial No
    buf += struct.pack('<I', socket.htonl(int(data_size)))   # Data Size
    return bytes(buf)


def parse_cds_header(header_bytes):
    """48 Byte CDS 헤더 파싱 → dict."""
    if len(header_bytes) != HEADER_SIZE:
        raise ConnectionClosed(
            f"CDS 헤더 크기 오류: {len(header_bytes)} bytes (expected {HEADER_SIZE})"
        )
    # '<' 로 언패킹 후 ntohl/ntohs(network→host) — pack 의 역순
    msg_id   = socket.ntohl(struct.unpack('<I', header_bytes[0:4])[0])
    tid_date = _unpack_char(header_bytes[4:12])
    tid_seq  = socket.ntohl(struct.unpack('<I', header_bytes[12:16])[0])
    src_sys  = _unpack_char(header_bytes[16:22])
    dst_sys  = _unpack_char(header_bytes[22:28])
    src_app  = _unpack_char(header_bytes[28:34])
    dst_app  = _unpack_char(header_bytes[34:40])
    cont_flag = socket.ntohs(struct.unpack('<H', header_bytes[40:42])[0])
    serial_no = socket.ntohs(struct.unpack('<H', header_bytes[42:44])[0])
    data_size = socket.ntohl(struct.unpack('<I', header_bytes[44:48])[0])
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
    buf += struct.pack('<H', socket.htons(int(reason)))
    if tid_date is not None or tid_seq is not None:
        buf += _pack_char(tid_date, 8)
        buf += struct.pack('<I', socket.htonl(int(tid_seq or 0)))
    return bytes(buf)


def unpack_ack(data):
    """
    ACK Data 파싱 → dict(result, reason[, tid_date, tid_seq]).
    길이에 따라 4B(Result/Reason) 또는 16B(+TID) 처리.
    """
    result = {}
    if len(data) >= 4:
        result['result'] = _unpack_char(data[0:2])
        result['reason'] = socket.ntohs(struct.unpack('<H', data[2:4])[0])
    if len(data) >= 16:
        result['tid_date'] = _unpack_char(data[4:12])
        result['tid_seq']  = socket.ntohl(struct.unpack('<I', data[12:16])[0])
    return result


def pack_process_state(state):
    """ProcessStateRequestACK Data: Process State uint16(2)."""
    return struct.pack('<H', socket.htons(int(state)))


def unpack_process_state(data):
    """ProcessStateRequestACK Data 파싱 → 정수(1=Normal, 2=Abnormal)."""
    if len(data) < 2:
        raise ConnectionClosed(f"ProcessState Data 크기 오류: {len(data)} bytes")
    return socket.ntohs(struct.unpack('<H', data[0:2])[0])


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


# CommandRequest(0015) Body 전체 레이아웃 (svc_code 별 가변 채움, ASCII 공백 패딩)
# ──────────────────────────────────────────────────────────────────
#   (field_name, length) 의 순서가 곧 wire 직렬화 순서다.
#   이 순서는 레거시 CDS 도구의 clear() 필드 선언 순서를 옮긴 것인데,
#   **실 A1 전문 샘플 327B + 규격표 35필드로 이중 검증 완료**됐다.
#   (샘플의 모든 유효 바이트가 A1 대상 필드에만 정렬되고, 규격표의 순서·크기가 전부 일치)
#   → 추정이 아니다. 순서/길이를 바꾸지 말 것.
#
#   ★ 이 레이아웃을 깨뜨려도 자동으로 잡히지 않는다. PG.CDS 는 Body 내용과 무관하게
#     CommandResult 를 SC 로 돌려주므로 전 TC 가 그대로 통과한다.
#     손댔다면 실 전문 캡처와 수동 대조할 것 (pg-wire-encoding 스킬).
#
#   주석 3열: <TCP 규격 파라미터명> / <JSON 파라미터명> — <설명>
#   내부 필드명은 레거시 이름을 유지한다(대조 기준 보존). 규격명과 1:1 대응은 아래 주석 참조.
_CMD_LAYOUT = [
    ('svc_code',                       2),   # JOB_CODE / opCode — 업무 코드
    ('mdn',                           12),   # MDN / mdn
    ('new_mdn',                       12),   # NEW_MDN
    ('min',                           10),   # MIN / min
    ('new_min',                       10),   # NEW_MIN
    ('prod_id',                       10),   # PRODUCT_ID / produId — 상품 ID
    ('data_prod_id',                  10),   # ADD_SVC / addSvc — 안심데이터상품ID (A1 옵션)
    ('network',                        8),   # NETWORK_ID / netId — WCDMA CDMA WiBro LTE 5G 플래그
    ('block_data_roaming_id',          1),   # ROADMING_STOP / roamStopId — 데이터로밍차단ID
    ('block_data_roaming_provider_id', 1),   # ROADMING_STOP_PROVIDER / roamStopProviId — 데이터로밍차단사업자ID
    ('allow_mvoip_yn',                 1),   # MVOIP_APPLY_FG — mVoIP 허용
    ('tablet_yn',                      1),   # TABLET_PC_YN / tabPcYn — 0=아니오 1=예
    ('os_ver',                         2),   # OS_VERSION / osVer
    ('device_model',                   4),   # TERMINAL_MODEL_CODE / termModelCode
    ('block_harmful_yn',               1),   # YOUNG_HARM_INFO_BLOCK / YoungHarmInfoBlock — 청소년 유해정보 차단
    ('block_roaming_data_yn',          1),   # ROAMING_DATA — 0=허용 1=차단 2=허용(VOMS제휴망)
    ('block_roaming_mvoip_yn',         1),   # ROAMING_MVOIP — 0=허용 1=차단
    ('zone_code',                      4),   # ZONE_CODE — 0000~9999
    ('ca',                             1),   # CA — CA 단말 속성. 3=L3 4=L4 (실 전문은 7=L7 도 온다)
    ('aprf',                           1),   # APRF / aprfTermAttri — 0=N/A 1=Support
    ('imsi',                          15),   # IMSI — 450(MCC)+05(MNC)+국번호(5)+Serial(5)
    ('mvno',                           1),   # MVNO_COMPANY / mvnoCompa
    ('limit',                          1),   # LIMIT_SUBS_FG / limitSubsFlag — 한도형 가입자
    ('qos_param',                      1),   # ROAMING_QOS_PARAM
    ('start_time',                    12),   # START_TIME — 쿠폰 종료 시간 / 시간프리 Start
    ('coupon_type',                    2),   # COUPON_TYPE — 쿠폰 권종 / 시간프리 End
    ('coupon_pin',                    11),   # COUPON_PIN
    ('ms_type',                        1),   # MS_TYPE / catMsType — Cat.M1 단말 타입
    ('category_lte',                   2),   # CATEGORY_LTE / lteCatgy — Default 10
    ('category_5g',                    2),   # CATEGORY_5G / 5gCatgy — Default 10
    ('device_type',                    1),   # DEVICE_TYPE / devceType — W=3G L=LTE N=NSA S=SA (Null=LTE)
    ('coupon_category',                1),   # COUPON_CATEGORY — T=Time P=Period
    ('real_start_time',               12),   # REAL_START_TIME — 쿠폰 시작 시간
    ('addr',                         170),   # ADDR — 주소 (cp949)
    ('product_type',                   2),   # PRODUCT_GEN_TYPE / produGenType — 01=3G 02=LTE 03=5G
]

COMMAND_BODY_SIZE = sum(size for _, size in _CMD_LAYOUT)   # = 327

# addr(주소)만 한글 포함 가능 → DB(골디락스 UHC / 알티베이스 MS949)와 맞춰 cp949 로 인코딩.
# 그 외 필드는 전부 코드/번호류라 ASCII 그대로 둔다.
_FIELD_ENCODING = {'addr': 'cp949'}


class UnsupportedCommandCode(ValueError):
    """gen() 에서 지원하지 않는 svc_code 를 만났을 때."""


def _fill_command_fields(code, kw, f):
    """
    svc_code(=code) 별로 채울 필드를 f(dict) 에 세팅한다.
    레거시 CDS 도구의 gen(section, value) if/elif 체인을 그대로 옮긴 것이며,
    분기 평가 순서가 동작을 좌우하므로(앞 분기가 먼저 매칭) 순서를 보존한다.
    값은 kw(키워드 인자 dict) 에서 동일 이름으로 읽는다. 누락 필드는 공백 유지.

    ★ 분기가 선언하지 않은 필드는 kw 에 값이 있어도 **조용히 버려진다.**
      s() 가 호출된 이름만 f 에 들어가고 나머지는 초기 공백을 유지하기 때문이다.
      실제로 Z1 분기에 product_type 이 없어, 호출부가 값을 넘겨도 Z1 만 반영되지
      않던 전례가 있다(규격 대조로 발견). 코드별 필드 집합을 고칠 때는 규격
      목록과 이 분기를 함께 대조할 것 — 테스트로는 잡히지 않는다.
    """
    v = code

    def s(*names):
        for n in names:
            f[n] = kw.get(n, '')

    if v == 'A1':
        s('mdn', 'min', 'prod_id', 'data_prod_id', 'network', 'tablet_yn',
          'os_ver', 'device_model', 'ca', 'aprf', 'imsi', 'mvno', 'limit',
          'ms_type', 'category_lte', 'category_5g', 'device_type', 'product_type')
    elif v == '1X':
        s('mdn', 'prod_id', 'limit', 'product_type', 'addr')
    elif v == '1Y':
        s('mdn', 'prod_id', 'product_type')
    elif v == 'D3':
        s('mdn', 'new_mdn', 'min', 'new_min', 'prod_id', 'data_prod_id',
          'network', 'tablet_yn', 'os_ver', 'device_model', 'ca', 'aprf',
          'imsi', 'mvno', 'limit', 'category_lte', 'category_5g',
          'device_type', 'product_type')
    elif v == 'Z1':
        # category_lte/category_5g/product_type 은 규격 Z1 목록에 있는데 레거시 코드에
        # 빠져 있었다(2026-07 규격 대조로 발견). ca/imsi 는 규격 목록엔 없으나
        # A1 실 전문이 채워 보내는 것이 확인돼 유지한다.
        s('mdn', 'prod_id', 'network', 'tablet_yn', 'os_ver', 'device_model',
          'ca', 'aprf', 'imsi', 'mvno', 'limit', 'ms_type',
          'category_lte', 'category_5g', 'device_type', 'product_type')
    elif v == 'IU' or v == 'IX':
        s('mdn', 'imsi', 'mvno', 'limit')
    elif v in ('Y5', 'Y6', 'Y7', 'Y8'):
        s('mdn', 'limit', 'zone_code')
    elif v == 'Y9' or v == 'YX':
        s('mdn', 'limit', 'zone_code', 'start_time', 'coupon_type', 'coupon_pin')
    elif v == 'K1' or v == 'K5':
        s('mdn', 'limit', 'start_time', 'coupon_type', 'coupon_pin', 'coupon_category')
    elif v == '91' or v == '92':
        s('mdn', 'limit', 'start_time', 'coupon_type', 'coupon_pin',
          'coupon_category', 'real_start_time')
    elif v in ('SS', 'ST', 'SU', 'SV'):
        s('mdn', 'limit', 'start_time', 'coupon_type')
    elif v in ('K2', 'K3', 'K4', 'K6', 'K7'):
        s('mdn', 'limit', 'coupon_pin')
    elif v == 'QI' or v == 'QJ':
        s('mdn', 'prod_id', 'mvno', 'limit')
    elif (v[0] == 'Q' and v[1] <= 'D') or (v[0] == 'H' and v[1] <= '6') or \
         v in ('HL', 'HM', 'H9', 'HA', 'L5', 'L6', 'L9', 'LA'):
        s('mdn', 'limit', 'qos_param')
    elif (v[0] == 'Q') or (v[0] == 'H') or (v[0] == 'L' and v[1] >= '7') or \
         (v[0] == 'Y' and v[1] >= '3') or (v[0] == 'I' and v[1] >= '6') or \
         v in ('SW', 'SX', 'IC', 'ID') or v[0] in ('N', 'J', 'R', 'W', 'O'):
        s('mdn', 'limit')
    elif v == 'G1':
        s('mdn', 'prod_id', 'data_prod_id', 'network', 'tablet_yn', 'os_ver',
          'device_model', 'ca', 'aprf', 'imsi', 'mvno', 'limit', 'ms_type',
          'category_lte', 'category_5g', 'device_type', 'product_type')
    elif v == 'C1':
        f['min'] = kw.get('mdn', '')          # 레거시: min ← mdn
        s('mdn', 'new_min', 'prod_id', 'data_prod_id', 'network', 'tablet_yn',
          'os_ver', 'device_model', 'ca', 'aprf', 'imsi', 'mvno', 'limit',
          'ms_type', 'category_lte', 'category_5g', 'device_type', 'product_type')
    elif v == 'I2' or v == 'I3':
        f['min'] = kw.get('mdn', '')          # 레거시: min ← mdn
        s('mdn', 'block_data_roaming_id', 'block_data_roaming_provider_id',
          'block_harmful_yn', 'mvno', 'limit')
    elif v == 'I4' or v == 'I5':
        s('mdn', 'allow_mvoip_yn', 'mvno', 'limit')
    elif v == 'L1' or v == 'L2':
        s('mdn', 'block_roaming_data_yn', 'limit', 'qos_param')
    elif v == 'L3' or v == 'L4':
        s('mdn', 'block_roaming_mvoip_yn', 'limit', 'qos_param')
    elif v in ('Y1', 'Y2', 'YA', 'YB'):
        s('mdn', 'prod_id', 'limit')
    elif v == 'ZZ':
        s('mdn', 'prod_id', 'limit')
    elif v[0] == 'L':
        s('mdn', 'limit', 'qos_param')
    elif v in (
        'S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'S9', 'SA', 'SB', 'SC',
        'SD', 'SE', 'SF', 'SG', 'SJ', 'SK',
        'T4', 'T5', 'T6', 'T7', 'T8', 'T9', 'TA', 'TB', 'TC', 'TD', 'TE', 'TF',
        'TG', 'TH', 'TI', 'TJ', 'TK', 'TL', 'TM', 'TN', 'TO', 'TP', 'TQ', 'TR',
        'TS', 'TT', 'TU', 'TV', 'TW', 'TX', 'TY', 'TZ',
        'R5', 'R6', 'R7', 'R8', 'R9', 'RA', 'RB', 'RC', 'RD', 'RE', 'RF', 'RG',
        'RP', 'RQ', 'RR', 'RS', 'RX', 'RY',
        'U1', 'U2', 'U3', 'U4', 'IV', 'IW',
        'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7', 'M8', 'M9', 'MA', 'MB', 'MC',
        'MD', 'ME',
        'F1', 'F2', 'F3', 'F4', 'F7', 'F8', 'F9', 'FA', 'FB', 'FC', 'FI', 'FJ',
        'FK', 'FL', 'FM', 'FN', 'FO', 'FP', 'FQ', 'FR', 'FS', 'FT',
        'X1', 'P3', 'P4', 'P5', 'P6', 'P7',
        '11', '12', '13', '14', '15', '16',
        '73', '74', '75', '76', '77', '78', '7B', '7C', '7D', '7E', '7F', '7G',
        '7P', '7Q', '7R', '7S',
        '8W', '8X', '8Y', '8Z',
        'Z2', 'Z3', 'Z4', 'Z5',
        'OV', 'OW',
        '1T', '1U', '1V', '1W',
    ):
        s('mdn', 'prod_id', 'limit')
    elif v in (
        'IY', 'IZ', 'HY', 'HZ', 'HU', 'HV', 'HW', 'SY', 'SZ',
        'E1', 'E2', 'E3', 'E4', 'E5', 'E6', 'E7', 'E8', 'E9', 'EA', 'EB', 'EC',
        'ED', 'EE', 'EF', 'EG', 'EH', 'EI', 'EJ', 'EK', 'EL', 'EM', 'EN', 'EO',
        'EP', 'EQ',
    ):
        s('mdn', 'limit')
    else:
        raise UnsupportedCommandCode(code)


def pack_command_body(code, **fields):
    """
    CommandRequest(0015) Body 패킹 (svc_code 별 가변, ASCII 공백 패딩, 총 327B).

    code     : 업무 코드(svc_code, 2자). 이 값에 따라 채울 필드가 결정된다.
    fields   : 필드명=값 키워드 인자 (예: mdn=..., prod_id=..., imsi=...).
               code 와 무관한 필드를 줘도 무시되고, code 가 요구하는 필드 중
               누락된 것은 공백으로 채워진다.

    레거시 CDS 도구의 clear()+gen() 을 옮긴 것으로, 전체 고정길이 레코드를
    만든 뒤 code 에 해당하는 필드만 채운다. wire 순서는 _CMD_LAYOUT 을 따른다.
    지원하지 않는 code 면 UnsupportedCommandCode 예외.
    """
    if code is None or len(str(code)) != 2:
        raise UnsupportedCommandCode(code)
    code = str(code)
    f = {name: '' for name, _ in _CMD_LAYOUT}
    f['svc_code'] = code
    _fill_command_fields(code, fields, f)
    buf = b''.join(
        _pack_char(f.get(name, ''), size, encoding=_FIELD_ENCODING.get(name, 'ascii'))
        for name, size in _CMD_LAYOUT
    )
    return buf


def unpack_command_body(data):
    """CommandRequest Body(327B) 파싱 → 필드명→값 dict (_CMD_LAYOUT 순서)."""
    result = {}
    offset = 0
    for name, size in _CMD_LAYOUT:
        chunk = data[offset:offset + size]
        result[name] = _unpack_char(chunk, encoding=_FIELD_ENCODING.get(name, 'ascii'))
        offset += size
    return result
