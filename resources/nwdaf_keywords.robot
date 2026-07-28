*** Settings ***
Documentation
...    NWDAF ↔ PG 연동 키워드 (SKT PG-SC Message Format 기반)
...
...    [인터페이스]
...      방향   : NWDAF(테스트 도구, Client) → PG (Server)
...      포트   : ${NWDAF_PORT} (TODO: 실환경 값 확인)
...      Body   : MULTI_MESSAGE(0xFF) TLV 하나로 inner TLV 스트림을 감싼 바이너리
...      주력   : Notification(0b010) 단방향, 응답 거의 없음
...
...    [Body 구조 — 규격 4개 섹션]
...      Body inner = COMMON1 + (pcefQoSCtrl | enodebQoSCtl) + COMMON2
...        - COMMON1 (1절, 필수)  : 가입자 식별 + 최근 사용량
...        - QoSCtrl              : PCEF_TYPE 값으로 분기
...                                  0x01 → pcefQoSCtrl  (2절)
...                                  0x10 → enodebQoSCtl (3절)
...        - COMMON2 (4절, 필수)  : Cell 통계
...      QOS_HDR(0x3A) 은 wrapper 가 아니라 flat numeric 플래그 TLV.
...
...    [Suite 정책]
...      Suite Setup    : Suite NWDAF Connect → ${NWDAF_SOCK} 공유
...      Test Setup     : Check NWDAF Socket (닫히면 Fatal Error)
...      Suite Teardown : Suite NWDAF Disconnect
...
...    [Message Id 관리]
...      0x000~0xFFF 순환. ${NWDAF_MSG_ID} Suite Variable 로 관리.
...      Next NWDAF Msg Id 키워드가 ++ 후 0xFFF 초과 시 0 으로 wrap.

Library    Collections
Library    String
Library    DateTime
Library    BuiltIn
Library    ${CURDIR}/TlvHelper.py    WITH NAME    Tlv

*** Variables ***
${NWDAF_SOCK}      ${NONE}
${NWDAF_MSG_ID}    ${-1}


*** Keywords ***

# ══════════════════════════════════════════════════════════════════
# Suite 연결 관리
# ══════════════════════════════════════════════════════════════════

Suite NWDAF Connect
    [Documentation]
    ...    NWDAF Suite Setup 전용
    ...    NWDAF(도구) → PG 소켓 연결. Hello 등 별도 핸드셰이크는 규격상 없음.
    [Arguments]    ${host}=${NWDAF_HOST}    ${port}=${NWDAF_PORT}    ${timeout}=${NWDAF_TIMEOUT}
    Log    [Suite] NWDAF 연결 시작 → ${host}:${port}    console=True
    ${sock}=    Tlv.Nwdaf Connect    ${host}    ${port}    ${timeout}
    Set Suite Variable    ${NWDAF_SOCK}    ${sock}
    Set Suite Variable    ${NWDAF_MSG_ID}    ${-1}
    Log    [Suite] NWDAF 연결 성공    console=True

Suite NWDAF Disconnect
    [Documentation]    NWDAF Suite Teardown 전용. 소켓 종료.
    Run Keyword If    $NWDAF_SOCK is not None    Tlv.Nwdaf Close    ${NWDAF_SOCK}
    Log    [Suite] NWDAF 연결 종료    console=True

Check NWDAF Socket
    [Documentation]
    ...    NWDAF Test Setup 전용. 소켓 닫히면 Fatal Error.
    ...    로컬 fd 뿐 아니라 PG 측 FIN/RST 여부(Nwdaf Peer Closed)도 확인한다 —
    ...    PG 가 직전 전문을 거부하고 끊었는데 이후 TC 가 '송신 성공' 으로
    ...    통과해버리는 것을 막기 위함.
    ${ok}=    Tlv.Nwdaf Is Connected    ${NWDAF_SOCK}
    Run Keyword If    not ${ok}
    ...    Fatal Error    NWDAF 소켓이 닫혀 있습니다. 이후 TC를 실행할 수 없습니다.
    ${closed}=    Tlv.Nwdaf Peer Closed    ${NWDAF_SOCK}
    Run Keyword If    ${closed}
    ...    Fatal Error    PG 가 NWDAF 연결을 끊었습니다 (FIN/RST). 직전 송신 전문을 PG 가 거부했을 수 있습니다.
    Drain NWDAF Pending Messages


# ══════════════════════════════════════════════════════════════════
# Message Id 순환 관리 (0x000~0xFFF)
# ══════════════════════════════════════════════════════════════════

Next NWDAF Msg Id
    [Documentation]    Message Id 증가 후 반환. 0xFFF 초과 시 0 으로 wrap.
    ${next}=    Evaluate    (${NWDAF_MSG_ID} + 1) % 0x1000
    Set Suite Variable    ${NWDAF_MSG_ID}    ${next}
    RETURN    ${next}


# ══════════════════════════════════════════════════════════════════
# 시각 헬퍼 — CREATE_DATE / CREATE_TIME (규격 1.3 / 1.4)
# ══════════════════════════════════════════════════════════════════

Get Create Date
    [Documentation]    'YYYYMMDD' 8자리 (TAG 0x08)
    ${d}=    Get Current Date    result_format=%Y%m%d
    RETURN    ${d}

Get Create Time
    [Documentation]    'HHmmss' 6자리 (TAG 0x09)
    ${t}=    Get Current Date    result_format=%H%M%S
    RETURN    ${t}


# ══════════════════════════════════════════════════════════════════
# Section 빌더 — COMMON1 / pcefQoSCtrl / enodebQoSCtl / COMMON2
# ══════════════════════════════════════════════════════════════════

Log TLV Section
    [Documentation]
    ...    TLV bytes 리스트를 '0x0d(len=1)=0x01' 형태로 로그에 남긴다.
    ...    (Robot 자동 로그의 raw 바이트 repr 예: b'\\r\\x01\\x01' 혼동 방지)
    [Arguments]    ${label}    ${tlvs}
    ${dump}=    Tlv.Format Tlvs    ${tlvs}
    Log    ${label} = ${dump}
    RETURN    ${dump}

Build COMMON1
    [Documentation]
    ...    COMMON1 (1절, 필수) TLV bytes 리스트 반환.
    ...    pcef_type 은 0x01(PGW) 또는 0x10(eNB).
    [Arguments]
    ...    ${pcef_type}
    ...    ${mdn}=${NWDAF_TEST_MDN}
    ...    ${min}=${NWDAF_TEST_MIN}
    ...    ${pgw_ip}=${NWDAF_TEST_PGW_IP}
    ...    ${qos_control_type}=${NWDAF_QCT_SUBSCRIBER}
    ...    ${rct_3m_usage}=${NWDAF_TEST_RCT_3M_USAGE}
    ...    ${rct_1m_usage}=${NWDAF_TEST_RCT_1M_USAGE}
    ...    ${create_date}=${NONE}
    ...    ${create_time}=${NONE}
    ${date}=    Run Keyword If    $create_date is None    Get Create Date
    ...         ELSE    Set Variable    ${create_date}
    ${time}=    Run Keyword If    $create_time is None    Get Create Time
    ...         ELSE    Set Variable    ${create_time}
    ${tlvs}=    Tlv.Build Common1    ${pcef_type}    ${qos_control_type}
    ...    ${date}    ${time}    ${pgw_ip}    ${min}    ${mdn}
    ...    ${rct_3m_usage}    ${rct_1m_usage}
    Log TLV Section    COMMON1    ${tlvs}
    RETURN    ${tlvs}

Build pcefQoSCtrl
    [Documentation]
    ...    pcefQoSCtrl (2절, PCEF_TYPE 비트 0x01) TLV bytes 리스트 반환.
    ...    QOS_POLICY 는 고정길이 NUL 패딩, TIMER 는 uint32 BE 로 송신된다 (PG 참조 구현 기준).
    [Arguments]
    ...    ${qos_policy}=${NWDAF_TEST_QOS_POLICY}
    ...    ${status}=${NWDAF_STATUS_NORMAL}
    ...    ${timer}=${NWDAF_TEST_TIMER}
    ...    ${quick_support}=${NWDAF_QUICK_NOW}
    ...    ${policy_len}=${NWDAF_LEN_QOS_POLICY}
    ${tlvs}=    Tlv.Build Pcef Qos Ctrl    ${qos_policy}    ${status}    ${timer}    ${quick_support}
    ...    policy_len=${policy_len}
    Log TLV Section    pcefQoSCtrl    ${tlvs}
    RETURN    ${tlvs}

Build dpiQoSCtrl
    [Documentation]
    ...    dpiQoSCtrl (PCEF_TYPE 비트 0x02) TLV bytes 리스트 반환.
    ...    PG 참조 구현의 `if (pcef_type & 0x02)` 블록 재현:
    ...      QOS_HDR(0x02) + (CATEGORY+QOS_POLICY)×6 + STATUS + TIMER(uint32) + QUICK_SUPPORT
    ...      CATEGORY 는 ASCII 'A'~'F'. 0x0C 는 CATEGORY 6 + STATUS 1 = 7개 나타난다.
    ...    CATEGORY 는 STATUS 와 같은 TAG(0x0C) 를 쓰므로 검증 시 Tlv.Tlv Find All 을 쓸 것.
    [Arguments]
    ...    ${category_policy}=${NONE}
    ...    ${status}=${NWDAF_STATUS_NORMAL}
    ...    ${timer}=${NWDAF_DPI_TEST_TIMER}
    ...    ${quick_support}=${NWDAF_QUICK_AFTER}
    ...    ${policy_len}=${NWDAF_LEN_QOS_POLICY}
    ${tlvs}=    Tlv.Build Dpi Qos Ctrl    ${category_policy}    ${status}    ${timer}
    ...    ${quick_support}    policy_len=${policy_len}
    Log TLV Section    dpiQoSCtrl    ${tlvs}
    RETURN    ${tlvs}

Build enodebQoSCtl
    [Documentation]
    ...    enodebQoSCtl (3절, PCEF_TYPE=0x10) TLV bytes 리스트 반환.
    [Arguments]
    ...    ${support_type}=${NWDAF_SUPPORT_APPLY}
    ...    ${arp_qci_flag}=${NWDAF_ARPQCI_QCI}
    ...    ${enb_arp}=${NWDAF_ENB_ARP_BAND_35}
    ...    ${arp_capability}=${NWDAF_ENABLE}
    ...    ${arp_vulnerability}=${NWDAF_ENABLE}
    ...    ${qci}=${NWDAF_TEST_QCI}
    ...    ${timer}=${NWDAF_TEST_TIMER}
    ${tlvs}=    Tlv.Build Enb Qos Ctrl    ${support_type}    ${arp_qci_flag}
    ...    ${enb_arp}    ${arp_capability}    ${arp_vulnerability}
    ...    ${qci}    ${timer}
    Log TLV Section    enodebQoSCtl    ${tlvs}
    RETURN    ${tlvs}

Build COMMON2
    [Documentation]
    ...    COMMON2 (4절, 필수) TLV bytes 리스트 반환.
    [Arguments]
    ...    ${network}=${NWDAF_NET_LTE}
    ...    ${control_unit}=${NWDAF_CU_CELL}
    ...    ${cell_id}=${NWDAF_TEST_CELL_ID}
    ...    ${dn_usage}=${NWDAF_TEST_DN_USAGE}
    ...    ${using_user}=${NWDAF_TEST_USING_USER}
    ...    ${cell_avg_usage}=${NWDAF_TEST_CELL_AVG_USAGE}
    ...    ${heavy_user}=${NWDAF_TEST_HEAVY_USER}
    ...    ${user_usage}=${NWDAF_TEST_USER_USAGE}
    ...    ${user_ratio}=${NWDAF_ENABLE}
    ${tlvs}=    Tlv.Build Common2    ${network}    ${control_unit}    ${cell_id}
    ...    ${dn_usage}    ${using_user}    ${cell_avg_usage}
    ...    ${heavy_user}    ${user_usage}    ${user_ratio}
    Log TLV Section    COMMON2    ${tlvs}
    RETURN    ${tlvs}


# ══════════════════════════════════════════════════════════════════
# 저수준 송신: 조립된 inner TLV 리스트 → Notification 패킷 송신
# ══════════════════════════════════════════════════════════════════

Send NWDAF Notification
    [Documentation]
    ...    이미 인코딩된 inner TLV bytes 리스트를 Notification Body 로 송신.
    ...    Body 는 자동으로 MULTI_MESSAGE(0xFF) TLV 로 감싸진다.
    ...    송신 직전 8B 헤더와 전체 패킷을 hexdump 로 남겨 PG 수신 로그와 대조할 수 있게 한다.
    [Arguments]    ${tlv_bytes_list}    ${service_id}=${NWDAF_SID_SUBSCRIBER}    ${message_id}=${NONE}
    ${mid}=    Run Keyword If    $message_id is None    Next NWDAF Msg Id
    ...        ELSE    Set Variable    ${message_id}
    ${packet}=    Tlv.Build Nwdaf Notification    ${service_id}    ${mid}    ${tlv_bytes_list}
    ${hdr_hex}=    Tlv.Hex Dump    ${{ $packet[:8] }}
    ${pkt_hex}=    Tlv.Hex Dump    ${packet}
    Log    [TX→PG] sid=${service_id} mid=${mid} bytes=${{ len($packet) }} hdr=[${hdr_hex}]
    Log    [TX→PG] packet = ${pkt_hex}
    Tlv.Send Nwdaf Packet    ${NWDAF_SOCK}    ${packet}
    RETURN    ${mid}


# ══════════════════════════════════════════════════════════════════
# 고수준 시나리오: 가입자 QoS Notification (PGW / eNB)
# ══════════════════════════════════════════════════════════════════

Send Subscriber QoS Notification PGW
    [Documentation]
    ...    PCEF_TYPE=0x01 (P-GW/SMF). COMMON1 + pcefQoSCtrl + COMMON2 송신.
    [Arguments]
    ...    ${mdn}=${NWDAF_TEST_MDN}
    ...    ${min}=${NWDAF_TEST_MIN}
    ...    ${qos_policy}=${NWDAF_TEST_QOS_POLICY}
    ...    ${status}=${NWDAF_STATUS_NORMAL}
    ...    ${quick_support}=${NWDAF_QUICK_NOW}
    ...    ${cell_id}=${NWDAF_TEST_CELL_ID}
    ...    ${network}=${NWDAF_NET_LTE}
    ${c1}=    Build COMMON1     ${NWDAF_PCEF_PGW}    mdn=${mdn}    min=${min}
    ${qc}=    Build pcefQoSCtrl    qos_policy=${qos_policy}    status=${status}    quick_support=${quick_support}
    ${c2}=    Build COMMON2     cell_id=${cell_id}    network=${network}
    ${body}=    Tlv.Build Notification Body    ${c1}    ${qc}    ${c2}
    ${mid}=    Send NWDAF Notification    ${body}
    RETURN    ${mid}

Send Subscriber QoS Notification LTE DPI
    [Documentation]
    ...    LTE 가입자 DPI QoS 추가 케이스.
    ...    PCEF_TYPE = 0x01|0x02 (P-GW + DPI) → COMMON1 + pcefQoSCtrl + dpiQoSCtrl + COMMON2 송신.
    ...    PCEF_TYPE 이 비트마스크이므로 두 QoS 섹션이 한 전문에 함께 실린다.
    [Arguments]
    ...    ${mdn}=${NWDAF_TEST_MDN}
    ...    ${min}=${NWDAF_TEST_MIN}
    ...    ${qos_policy}=${NWDAF_TEST_QOS_POLICY}
    ...    ${status}=${NWDAF_STATUS_NORMAL}
    ...    ${category_policy}=${NONE}
    ...    ${cell_id}=${NWDAF_TEST_CELL_ID}
    ...    ${network}=${NWDAF_NET_LTE}
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW_DPI}    mdn=${mdn}    min=${min}
    ${qc}=    Build pcefQoSCtrl    qos_policy=${qos_policy}    status=${status}
    ${dpi}=   Build dpiQoSCtrl    category_policy=${category_policy}    status=${status}
    ${c2}=    Build COMMON2    cell_id=${cell_id}    network=${network}
    ${body}=    Tlv.Build Notification Body    ${c1}    ${qc}    ${c2}    dpi_qos_ctrl=${dpi}
    ${mid}=    Send NWDAF Notification    ${body}
    RETURN    ${mid}

Send DPI Only QoS Notification
    [Documentation]
    ...    PCEF_TYPE = 0x02 (DPI 단독). COMMON1 + dpiQoSCtrl + COMMON2 송신.
    [Arguments]
    ...    ${mdn}=${NWDAF_TEST_MDN}
    ...    ${min}=${NWDAF_TEST_MIN}
    ...    ${category_policy}=${NONE}
    ...    ${cell_id}=${NWDAF_TEST_CELL_ID}
    ...    ${network}=${NWDAF_NET_LTE}
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_DPI}    mdn=${mdn}    min=${min}
    ${dpi}=   Build dpiQoSCtrl    category_policy=${category_policy}
    ${c2}=    Build COMMON2    cell_id=${cell_id}    network=${network}
    ${body}=    Tlv.Build Notification Body    ${c1}    ${dpi}    ${c2}
    ${mid}=    Send NWDAF Notification    ${body}
    RETURN    ${mid}

Send Subscriber QoS Notification ENB
    [Documentation]
    ...    PCEF_TYPE=0x10 (eNB). COMMON1 + enodebQoSCtl + COMMON2 송신.
    [Arguments]
    ...    ${mdn}=${NWDAF_TEST_MDN}
    ...    ${min}=${NWDAF_TEST_MIN}
    ...    ${support_type}=${NWDAF_SUPPORT_APPLY}
    ...    ${arp_qci_flag}=${NWDAF_ARPQCI_QCI}
    ...    ${enb_arp}=${NWDAF_ENB_ARP_BAND_35}
    ...    ${qci}=${NWDAF_TEST_QCI}
    ...    ${cell_id}=${NWDAF_TEST_CELL_ID}
    ...    ${network}=${NWDAF_NET_LTE}
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_ENB}    mdn=${mdn}    min=${min}
    ${qc}=    Build enodebQoSCtl    support_type=${support_type}    arp_qci_flag=${arp_qci_flag}
    ...    enb_arp=${enb_arp}    qci=${qci}
    ${c2}=    Build COMMON2    cell_id=${cell_id}    network=${network}
    ${body}=    Tlv.Build Notification Body    ${c1}    ${qc}    ${c2}
    ${mid}=    Send NWDAF Notification    ${body}
    RETURN    ${mid}


# ══════════════════════════════════════════════════════════════════
# Health Check
#   주 방향 : NWDAF(도구) → PG 로 Request(0x01) 송신 → PG 가 Response(0x04) 회신
#   Timeout : 30초. Body 는 Request/Response 모두 없음(길이 0).
#
# 역방향(PG 가 먼저 Request 를 보내는 경우)도 Handle NWDAF Health Check /
# Drain NWDAF Pending Messages 로 방어적으로 처리한다.
# ══════════════════════════════════════════════════════════════════

Send NWDAF Health Check
    [Documentation]
    ...    NWDAF → PG Health Check Request(Message Type 0x01, Body 없음) 송신 후
    ...    PG 의 Response(0x04) 를 수신해 검증한다. 수신한 헤더를 반환.
    ...
    ...    TODO: Health Check 전용 Service Id 확인 필요.
    ...          규격 TAG 표는 0x0305(가입자 단위 QoS 제어) 만 정의하므로 그 값을 기본으로 쓴다.
    [Arguments]
    ...    ${service_id}=${NWDAF_SID_SUBSCRIBER}
    ...    ${message_id}=${NONE}
    ...    ${timeout}=${NWDAF_HEALTHCHECK_TIMEOUT}
    ${mid}=    Run Keyword If    $message_id is None    Next NWDAF Msg Id
    ...        ELSE    Set Variable    ${message_id}
    ${sent}=    Tlv.Send Nwdaf Raw    ${NWDAF_SOCK}    ${NWDAF_MT_REQ}
    ...    ${service_id}    ${mid}    ${NONE}
    Log    [TX→PG] Health Check Request sid=${service_id} mid=${mid} bytes=${sent}
    ${prev}=    Tlv.Nwdaf Set Timeout    ${NWDAF_SOCK}    ${timeout}
    TRY
        ${hdr}    ${body}    ${tlvs}=    Receive NWDAF Message
    FINALLY
        Tlv.Nwdaf Set Timeout    ${NWDAF_SOCK}    ${prev}
    END
    Should Be Equal As Integers    ${hdr}[msg_type]    ${NWDAF_MT_RESP}
    ...    msg=Health Check Response(0x04) 기대, 실제 msg_type=${hdr}[msg_type]
    Should Be Equal As Integers    ${hdr}[message_id]    ${mid}
    ...    msg=Response 의 Message Id 가 Request 와 다름 (요청=${mid}, 응답=${hdr}[message_id])
    Should Be Equal As Integers    ${hdr}[body_length]    ${0}
    ...    msg=Health Check 는 Body 가 없어야 함. 실제 body_length=${hdr}[body_length]
    RETURN    ${hdr}

Receive NWDAF Message
    [Documentation]
    ...    PG → NWDAF 메시지 1건 수신. (header dict, body bytes, inner TLV 리스트) 반환.
    ...    소켓 타임아웃(${NWDAF_TIMEOUT}) 내에 안 오면 예외로 실패한다.
    ${hdr}    ${body}    ${tlvs}=    Tlv.Receive Nwdaf Message    ${NWDAF_SOCK}
    Log    [RX←PG] msg_type=${hdr}[msg_type] sid=${hdr}[service_id] mid=${hdr}[message_id] bodylen=${hdr}[body_length]
    RETURN    ${hdr}    ${body}    ${tlvs}

Send NWDAF Health Check Response
    [Documentation]
    ...    수신한 Health Check Request 헤더를 그대로 echo 하고 Message Type 만
    ...    Response(0b100) 로 바꿔 회신한다.
    ...    Health Check 는 **Body 가 없다** — Body Length 0 으로 헤더만 회신한다.
    [Arguments]    ${req_hdr}    ${body}=${NONE}
    ${sent}=    Tlv.Send Nwdaf Raw    ${NWDAF_SOCK}    ${NWDAF_MT_RESP}
    ...    ${req_hdr}[service_id]    ${req_hdr}[message_id]    ${body}
    Log    [TX→PG] Health Check Response sid=${req_hdr}[service_id] mid=${req_hdr}[message_id] bytes=${sent}
    RETURN    ${sent}

Handle NWDAF Health Check
    [Documentation]
    ...    ※ 역방향 전용 — 주 방향은 Send NWDAF Health Check (NWDAF → PG) 다.
    ...    PG 가 먼저 Health Check Request 를 보내오는 경우를 방어적으로 처리한다.
    ...    최대 ${timeout} 초 대기해 수신하고 Response 회신.
    ...
    ...    Health Check Request: Message Type = 0x01, **Body 없음(길이 0)**.
    ...    따라서 Body/TLV 검증은 없고 헤더의 Message Type 과 Body Length 만 확인한다.
    ...    소켓 타임아웃은 접속 시 1회만 설정되므로 이 구간에서만 늘렸다 되돌린다.
    [Arguments]    ${timeout}=${NWDAF_HEALTHCHECK_TIMEOUT}
    ${prev}=    Tlv.Nwdaf Set Timeout    ${NWDAF_SOCK}    ${timeout}
    TRY
        ${hdr}    ${body}    ${tlvs}=    Receive NWDAF Message
        Should Be Equal As Integers    ${hdr}[msg_type]    ${NWDAF_MT_REQ}
        ...    msg=Health Check Request(0x01) 기대, 실제 msg_type=${hdr}[msg_type]
        Should Be Equal As Integers    ${hdr}[body_length]    ${0}
        ...    msg=Health Check 는 Body 가 없어야 함. 실제 body_length=${hdr}[body_length]
        Send NWDAF Health Check Response    ${hdr}
    FINALLY
        Tlv.Nwdaf Set Timeout    ${NWDAF_SOCK}    ${prev}
    END
    RETURN    ${hdr}

Drain NWDAF Pending Messages
    [Documentation]
    ...    소켓에 쌓여 있는 PG 발 메시지를 논블로킹으로 확인해 비운다.
    ...    Health Check Request 면 Response 를 회신한다.
    ...    도구가 소켓을 전혀 읽지 않으면 PG 의 주기적 Health Check 가 계속 쌓이므로 필요.
    [Arguments]    ${limit}=${5}
    FOR    ${i}    IN RANGE    ${limit}
        ${pending}=    Tlv.Nwdaf Has Pending    ${NWDAF_SOCK}
        IF    not ${pending}    BREAK
        ${hdr}    ${body}    ${tlvs}=    Receive NWDAF Message
        IF    ${hdr}[msg_type] == ${NWDAF_MT_REQ}
            Send NWDAF Health Check Response    ${hdr}
        END
    END


# ══════════════════════════════════════════════════════════════════
# 검증 키워드
# ══════════════════════════════════════════════════════════════════

NWDAF Header Should Match
    [Documentation]
    ...    이미 빌드된 8B 헤더 바이트가 기대 msg_type/service_id/message_id 와 일치하는지 검증.
    [Arguments]    ${hdr_bytes}    ${expected_msg_type}    ${expected_service_id}    ${expected_msg_id}
    ${hdr}=    Tlv.Parse Nwdaf Header    ${hdr_bytes}
    Should Be Equal As Integers    ${hdr}[msg_type]      ${expected_msg_type}
    Should Be Equal As Integers    ${hdr}[service_id]    ${expected_service_id}
    Should Be Equal As Integers    ${hdr}[message_id]    ${expected_msg_id}
    RETURN    ${hdr}

NWDAF Body Should Contain Tag
    [Documentation]    Body bytes 안에 특정 TAG 의 TLV 가 존재하는지 검증
    [Arguments]    ${body_bytes}    ${expected_tag}
    ${value}=    Tlv.Tlv Find    ${body_bytes}    ${expected_tag}
    Should Not Be Equal    ${value}    ${NONE}
    ...    msg=TAG=${expected_tag} TLV 가 Body 에 없음
    RETURN    ${value}

NWDAF Inner TLVs Should Contain Tag
    [Documentation]
    ...    MULTI_MESSAGE wrapper 안쪽 inner TLV 리스트에 특정 TAG 가 있는지 검증.
    ...    body_bytes → 0xFF TLV 한 개 → inner TLV 스트림 → TAG 매칭.
    [Arguments]    ${body_bytes}    ${expected_tag}
    ${top}=    Tlv.Unpack Tlv Stream    ${body_bytes}
    Length Should Be    ${top}    ${1}    msg=Body 가 단일 MULTI_MESSAGE TLV 가 아님
    Should Be Equal As Integers    ${top}[0][0]    ${NWDAF_TAG_MULTI_MESSAGE}
    ${value}=    Tlv.Tlv Find    ${top}[0][2]    ${expected_tag}
    Should Not Be Equal    ${value}    ${NONE}
    ...    msg=TAG=${expected_tag} TLV 가 inner stream 에 없음
    RETURN    ${value}
