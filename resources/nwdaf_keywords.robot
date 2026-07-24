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
    [Documentation]    NWDAF Test Setup 전용. 소켓 닫히면 Fatal Error.
    ${ok}=    Tlv.Nwdaf Is Connected    ${NWDAF_SOCK}
    Run Keyword If    not ${ok}
    ...    Fatal Error    NWDAF 소켓이 닫혀 있습니다. 이후 TC를 실행할 수 없습니다.


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
    ...    pcefQoSCtrl (2절, PCEF_TYPE=0x01) TLV bytes 리스트 반환.
    [Arguments]
    ...    ${qos_policy}=${NWDAF_TEST_QOS_POLICY}
    ...    ${status}=${NWDAF_STATUS_NORMAL}
    ...    ${timer}=${NWDAF_TEST_TIMER}
    ...    ${quick_support}=${NWDAF_QUICK_NOW}
    ${tlvs}=    Tlv.Build Pcef Qos Ctrl    ${qos_policy}    ${status}    ${timer}    ${quick_support}
    Log TLV Section    pcefQoSCtrl    ${tlvs}
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
    [Arguments]    ${tlv_bytes_list}    ${service_id}=${NWDAF_SID_SUBSCRIBER}    ${message_id}=${NONE}
    ${mid}=    Run Keyword If    $message_id is None    Next NWDAF Msg Id
    ...        ELSE    Set Variable    ${message_id}
    ${sent}=    Tlv.Send Nwdaf Notification    ${NWDAF_SOCK}    ${service_id}    ${mid}    ${tlv_bytes_list}
    Log    [TX→NWDAF] sid=${service_id} mid=${mid} bytes=${sent}
    RETURN    ${mid}


# ══════════════════════════════════════════════════════════════════
# 고수준 시나리오: 가입자 QoS Notification (PGW / eNB)
# ══════════════════════════════════════════════════════════════════

Send Subscriber QoS Notification PGW
    [Documentation]
    ...    PCEF_TYPE=0x01 (P-GW/SMF). COMMON1 + pcefQoSCtrl + COMMON2 송신.
    [Arguments]
    ...    ${mdn}=${NWDAF_TEST_MDN}
    ...    ${qos_policy}=${NWDAF_TEST_QOS_POLICY}
    ...    ${status}=${NWDAF_STATUS_NORMAL}
    ...    ${quick_support}=${NWDAF_QUICK_NOW}
    ...    ${cell_id}=${NWDAF_TEST_CELL_ID}
    ${c1}=    Build COMMON1     ${NWDAF_PCEF_PGW}    mdn=${mdn}
    ${qc}=    Build pcefQoSCtrl    qos_policy=${qos_policy}    status=${status}    quick_support=${quick_support}
    ${c2}=    Build COMMON2     cell_id=${cell_id}
    ${body}=    Tlv.Build Notification Body    ${c1}    ${qc}    ${c2}
    ${mid}=    Send NWDAF Notification    ${body}
    RETURN    ${mid}

Send Subscriber QoS Notification ENB
    [Documentation]
    ...    PCEF_TYPE=0x10 (eNB). COMMON1 + enodebQoSCtl + COMMON2 송신.
    [Arguments]
    ...    ${mdn}=${NWDAF_TEST_MDN}
    ...    ${support_type}=${NWDAF_SUPPORT_APPLY}
    ...    ${arp_qci_flag}=${NWDAF_ARPQCI_QCI}
    ...    ${enb_arp}=${NWDAF_ENB_ARP_BAND_35}
    ...    ${qci}=${NWDAF_TEST_QCI}
    ...    ${cell_id}=${NWDAF_TEST_CELL_ID}
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_ENB}    mdn=${mdn}
    ${qc}=    Build enodebQoSCtl    support_type=${support_type}    arp_qci_flag=${arp_qci_flag}
    ...    enb_arp=${enb_arp}    qci=${qci}
    ${c2}=    Build COMMON2    cell_id=${cell_id}
    ${body}=    Tlv.Build Notification Body    ${c1}    ${qc}    ${c2}
    ${mid}=    Send NWDAF Notification    ${body}
    RETURN    ${mid}


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
