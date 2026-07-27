*** Settings ***
Documentation
...    NWDAF ↔ PG 연동 기능 검증 (SKT PG-SC Message Format)
...
...    [테스트 대상]
...      테스트 도구(NWDAF 역할 / Client) → PG (Server, Port ${NWDAF_PORT})
...
...    [Suite 정책]
...      Suite Setup    : NWDAF → PG 연결 → ${NWDAF_SOCK} 공유
...      Test Setup     : Check NWDAF Socket (소켓 닫히면 Suite 즉시 중단)
...      Suite Teardown : NWDAF 연결 종료
...      각 TC          : ${NWDAF_SOCK} 공유 사용 (TC별 연결/해제 없음)
...
...    [메시지 흐름]
...      능동 송신 (NWDAF→PG): Notification(0b010) 주력
...      수동 수신          : 규격상 Response 거의 없음. 디버그용으로만 receive.
...
...    [Body 구조 — 규격 4개 섹션]
...      Body = MULTI_MESSAGE(0xFF){ COMMON1 + (pcefQoSCtrl | enodebQoSCtl) + COMMON2 }
...        - COMMON1 (1절, 필수)  : MIN/MDN/CREATE_DATE/TIME/PGW_IP/PCEF_TYPE/QCT/RCT 사용량
...        - QoSCtrl              : PCEF_TYPE 으로 분기
...                                  0x01 → pcefQoSCtrl  (QOS_POLICY/STATUS/TIMER/QUICK_SUPPORT)
...                                  0x10 → enodebQoSCtl (SUPPORT_TYPE/ARP_QCI_FLAG/ENB_ARP/QCI/...)
...        - COMMON2 (4절, 필수)  : NETWORK/CONTROL_UNIT/CELL_ID/DN_USAGE/USING_USER/...
...      QOS_HDR(0x3A) 은 wrapper 가 아니라 flat numeric 플래그 TLV.
...
...    [TC 번호 체계]
...      TC-NWDAF-001 ~ 002 : Smoke (PGW/eNB 최소 송신)
...      TC-NWDAF-003 ~ 010 : pcefQoSCtrl (STATUS / QUICK_SUPPORT / QOS_POLICY)
...      TC-NWDAF-011 ~ 017 : enodebQoSCtl (SUPPORT_TYPE / ARP_QCI_FLAG / ENB_ARP)
...      TC-NWDAF-018 ~ 019 : COMMON1 (RCT_3M/1M_USAGE 경계)
...      TC-NWDAF-021 ~ 028 : COMMON2 (NETWORK / CONTROL_UNIT / DN_USAGE / USER_RATIO)
...      TC-NWDAF-029       : Message Id wrap
...      TC-NWDAF-030 ~ 034 : Build 단위 검증 (송신 없음)
...      TC-NWDAF-035 ~ 036 : 5G 가입자 Notification (PGW/eNB, NETWORK=5G)

Resource    ../../resources/variables.robot
Resource    ../../resources/nwdaf_variables.robot
Resource    ../../resources/common_keywords.robot
Resource    ../../resources/nwdaf_keywords.robot

Suite Setup      Suite NWDAF Connect
Suite Teardown   Suite NWDAF Disconnect
Test Setup       Check NWDAF Socket

*** Test Cases ***

# ════════════════════════════════════════════════════════════════
# Smoke: PCEF_TYPE 분기 별 최소 송신
# ════════════════════════════════════════════════════════════════

TC-NWDAF-001 PGW 최소 Notification (Smoke)
    [Documentation]
    ...    PCEF_TYPE=0x01 (P-GW/SMF). COMMON1 + pcefQoSCtrl + COMMON2 송신 → 성공 검증.
    [Tags]    nwdaf    nwdaf_smoke    nwdaf_pgw
    ${mid}=    Send Subscriber QoS Notification PGW
    Should Be True    0 <= ${mid} <= 0xFFF    msg=Message Id 범위 위반: ${mid}


TC-NWDAF-002 eNB 최소 Notification (Smoke)
    [Documentation]
    ...    PCEF_TYPE=0x10 (eNB). COMMON1 + enodebQoSCtl + COMMON2 송신 → 성공 검증.
    [Tags]    nwdaf    nwdaf_smoke    nwdaf_enb
    ${mid}=    Send Subscriber QoS Notification ENB
    Should Be True    0 <= ${mid} <= 0xFFF    msg=Message Id 범위 위반: ${mid}


# ════════════════════════════════════════════════════════════════
# 5G 가입자 Notification (MIN/MDN = 5G 가입자, NETWORK=5G)
# 대응 LTE: TC-NWDAF-001/002 (기본 LTE 가입자)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-003 5G 가입자 PGW Notification
    [Documentation]
    ...    5G 가입자(MIN=${NWDAF_TEST_MIN_5G}, MDN=${NWDAF_TEST_MDN_5G}) 대상
    ...    PCEF_TYPE=0x01 (P-GW/SMF) + NETWORK=5G Notification 송신 → 성공 검증.
    [Tags]    nwdaf    nwdaf_smoke    nwdaf_pgw    nwdaf_5g
    ${mid}=    Send Subscriber QoS Notification PGW
    ...    mdn=${NWDAF_TEST_MDN_5G}    min=${NWDAF_TEST_MIN_5G}    network=${NWDAF_NET_5G}
    Should Be True    0 <= ${mid} <= 0xFFF    msg=Message Id 범위 위반: ${mid}


TC-NWDAF-004 5G 가입자 eNB Notification
    [Documentation]
    ...    5G 가입자(MIN=${NWDAF_TEST_MIN_5G}, MDN=${NWDAF_TEST_MDN_5G}) 대상
    ...    PCEF_TYPE=0x10 (eNB) + NETWORK=5G Notification 송신 → 성공 검증.
    [Tags]    nwdaf    nwdaf_smoke    nwdaf_enb    nwdaf_5g
    ${mid}=    Send Subscriber QoS Notification ENB
    ...    mdn=${NWDAF_TEST_MDN_5G}    min=${NWDAF_TEST_MIN_5G}    network=${NWDAF_NET_5G}
    Should Be True    0 <= ${mid} <= 0xFFF    msg=Message Id 범위 위반: ${mid}


# ════════════════════════════════════════════════════════════════
# pcefQoSCtrl — STATUS 부하 등급 (규격 2.3, '0'~'3')
# ════════════════════════════════════════════════════════════════

TC-NWDAF-105 PGW STATUS Normal (0)
    [Documentation]    STATUS='0' (Normal)
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_status
    Send Subscriber QoS Notification PGW    status=${NWDAF_STATUS_NORMAL}

TC-NWDAF-105 PGW STATUS Minor (1)
    [Documentation]    STATUS='1' (Minor)
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_status
    Send Subscriber QoS Notification PGW    status=${NWDAF_STATUS_MINOR}

TC-NWDAF-005 PGW STATUS Major (2)
    [Documentation]    STATUS='2' (Major)
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_status
    Send Subscriber QoS Notification PGW    status=${NWDAF_STATUS_MAJOR}

TC-NWDAF-006 PGW STATUS Critical (3)
    [Documentation]    STATUS='3' (Critical)
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_status
    Send Subscriber QoS Notification PGW    status=${NWDAF_STATUS_CRITICAL}


# ════════════════════════════════════════════════════════════════
# pcefQoSCtrl — QUICK_SUPPORT (규격 2.5)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-007 PGW QUICK_SUPPORT 즉시 (0)
    [Documentation]    QUICK_SUPPORT='0' (즉시제어)
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_quick
    Send Subscriber QoS Notification PGW    quick_support=${NWDAF_QUICK_NOW}

TC-NWDAF-008 PGW QUICK_SUPPORT Update 후 (1)
    [Documentation]    QUICK_SUPPORT='1' (update 수신 후 제어)
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_quick
    Send Subscriber QoS Notification PGW    quick_support=${NWDAF_QUICK_AFTER}


# ════════════════════════════════════════════════════════════════
# pcefQoSCtrl — QOS_POLICY (규격 2.2)
# NWDAF 가 PCRF 로 내리는 정책명. PG 는 SMF 방향일 때 변환 처리.
# ════════════════════════════════════════════════════════════════

TC-NWDAF-009 PGW QOS_POLICY QoS400K_NoGBR
    [Documentation]
    ...    QOS_POLICY='QoS400K_NoGBR' (400K Non-GBR 정책).
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_qos_policy
    Send Subscriber QoS Notification PGW    qos_policy=QoS400K_NoGBR

TC-NWDAF-010 PGW QOS_POLICY NoQoS_NoGBR
    [Documentation]
    ...    QOS_POLICY='NoQoS_NoGBR' (QoS 없음 / Non-GBR).
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_qos_policy
    Send Subscriber QoS Notification PGW    qos_policy=NoQoS_NoGBR


# ════════════════════════════════════════════════════════════════
# enodebQoSCtl — SUPPORT_TYPE (규격 3.2)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-011 eNB SUPPORT_TYPE 제어 (1)
    [Documentation]    SUPPORT_TYPE=1 (제어)
    [Tags]    nwdaf    nwdaf_enb    nwdaf_support
    Send Subscriber QoS Notification ENB    support_type=${NWDAF_SUPPORT_APPLY}

TC-NWDAF-012 eNB SUPPORT_TYPE 해지 (2)
    [Documentation]    SUPPORT_TYPE=2 (해지)
    [Tags]    nwdaf    nwdaf_enb    nwdaf_support
    Send Subscriber QoS Notification ENB    support_type=${NWDAF_SUPPORT_RELEASE}


# ════════════════════════════════════════════════════════════════
# enodebQoSCtl — ARP_QCI_FLAG (규격 3.3)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-013 eNB ARP_QCI_FLAG ARP only (0)
    [Tags]    nwdaf    nwdaf_enb    nwdaf_arpqci
    Send Subscriber QoS Notification ENB    arp_qci_flag=${NWDAF_ARPQCI_ARP}

TC-NWDAF-014 eNB ARP_QCI_FLAG QCI only (1)
    [Tags]    nwdaf    nwdaf_enb    nwdaf_arpqci
    Send Subscriber QoS Notification ENB    arp_qci_flag=${NWDAF_ARPQCI_QCI}

TC-NWDAF-015 eNB ARP_QCI_FLAG ARP&QCI (2)
    [Tags]    nwdaf    nwdaf_enb    nwdaf_arpqci
    Send Subscriber QoS Notification ENB    arp_qci_flag=${NWDAF_ARPQCI_BOTH}


# ════════════════════════════════════════════════════════════════
# enodebQoSCtl — ENB_ARP Band 코드 (규격 3.4)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-016 eNB ENB_ARP Band 3->5/1 (12)
    [Tags]    nwdaf    nwdaf_enb    nwdaf_band
    Send Subscriber QoS Notification ENB    enb_arp=${NWDAF_ENB_ARP_BAND_35}

TC-NWDAF-017 eNB ENB_ARP Band 1/5->3 (13)
    [Tags]    nwdaf    nwdaf_enb    nwdaf_band
    Send Subscriber QoS Notification ENB    enb_arp=${NWDAF_ENB_ARP_BAND_153}


# ════════════════════════════════════════════════════════════════
# COMMON1 — RCT_3M/1M_USAGE 경계값
# ════════════════════════════════════════════════════════════════

TC-NWDAF-018 COMMON1 RCT Usage 경계 0
    [Documentation]    RCT_3M/1M_USAGE 모두 0
    [Tags]    nwdaf    nwdaf_common1    nwdaf_usage
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}    rct_3m_usage=${0}    rct_1m_usage=${0}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2
    ${body}=    Tlv.Build Notification Body    ${c1}    ${qc}    ${c2}
    Send NWDAF Notification    ${body}

TC-NWDAF-019 COMMON1 RCT Usage 경계 최대 (9,999,999)
    [Documentation]    RCT_3M/1M_USAGE 규격 최대 9,999,999 KB
    [Tags]    nwdaf    nwdaf_common1    nwdaf_usage
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}    rct_3m_usage=${9999999}    rct_1m_usage=${9999999}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2
    ${body}=    Tlv.Build Notification Body    ${c1}    ${qc}    ${c2}
    Send NWDAF Notification    ${body}


# ════════════════════════════════════════════════════════════════
# COMMON2 — NETWORK 종별 (규격 4.1)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-021 COMMON2 NETWORK WCDMA (1)
    [Tags]    nwdaf    nwdaf_common2    nwdaf_network
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2    network=${NWDAF_NET_WCDMA}
    ${body}=    Tlv.Build Notification Body    ${c1}    ${qc}    ${c2}
    Send NWDAF Notification    ${body}

TC-NWDAF-022 COMMON2 NETWORK LTE (2)
    [Tags]    nwdaf    nwdaf_common2    nwdaf_network
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2    network=${NWDAF_NET_LTE}
    ${body}=    Tlv.Build Notification Body    ${c1}    ${qc}    ${c2}
    Send NWDAF Notification    ${body}

TC-NWDAF-023 COMMON2 NETWORK 5G (3)
    [Tags]    nwdaf    nwdaf_common2    nwdaf_network
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2    network=${NWDAF_NET_5G}
    ${body}=    Tlv.Build Notification Body    ${c1}    ${qc}    ${c2}
    Send NWDAF Notification    ${body}


# ════════════════════════════════════════════════════════════════
# COMMON2 — CONTROL_UNIT (규격 4.2)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-024 COMMON2 CONTROL_UNIT Cell (1)
    [Tags]    nwdaf    nwdaf_common2    nwdaf_cu
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2    control_unit=${NWDAF_CU_CELL}
    Send NWDAF Notification    ${{$c1 + $qc + $c2}}

TC-NWDAF-025 COMMON2 CONTROL_UNIT eNodeB (2)
    [Tags]    nwdaf    nwdaf_common2    nwdaf_cu
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2    control_unit=${NWDAF_CU_ENODEB}
    Send NWDAF Notification    ${{$c1 + $qc + $c2}}


# ════════════════════════════════════════════════════════════════
# COMMON2 — DN_USAGE 경계 / 통계 변형
# ════════════════════════════════════════════════════════════════

TC-NWDAF-026 COMMON2 DN_USAGE 경계값 0
    [Tags]    nwdaf    nwdaf_common2    nwdaf_usage
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2    dn_usage=${0}    cell_avg_usage=${0}    user_usage=${0}
    Send NWDAF Notification    ${{$c1 + $qc + $c2}}

TC-NWDAF-027 COMMON2 DN_USAGE 경계 최대 (9,999,999)
    [Tags]    nwdaf    nwdaf_common2    nwdaf_usage
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2    dn_usage=${9999999}    cell_avg_usage=${9999999}    user_usage=${9999999}
    Send NWDAF Notification    ${{$c1 + $qc + $c2}}

TC-NWDAF-028 COMMON2 USER_RATIO Disable (1)
    [Documentation]    USER_RATIO=1 (Disable, 규격 4.9 원문)
    [Tags]    nwdaf    nwdaf_common2    nwdaf_ratio
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2    user_ratio=${NWDAF_DISABLE}
    Send NWDAF Notification    ${{$c1 + $qc + $c2}}


# ════════════════════════════════════════════════════════════════
# Message Id 순환 (0xFFF → 0x000)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-029 Message Id Wrap (0xFFF → 0x000)
    [Documentation]
    ...    Message Id 0xFFF 도달 후 0x000 으로 wrap 되는지 검증.
    ...    Suite Variable ${NWDAF_MSG_ID} 를 강제로 0xFFE 로 설정 후 2회 송신.
    [Tags]    nwdaf    nwdaf_msgid_wrap
    Set Suite Variable    ${NWDAF_MSG_ID}    ${4094}    # 0xFFE
    ${mid1}=    Send Subscriber QoS Notification PGW
    Should Be Equal As Integers    ${mid1}    ${4095}    # 0xFFF
    ${mid2}=    Send Subscriber QoS Notification PGW
    Should Be Equal As Integers    ${mid2}    ${0}
    Set Suite Variable    ${NWDAF_MSG_ID}    ${0}


# ════════════════════════════════════════════════════════════════
# Build 단위 검증 (송신 없이 패킷 바이트 검증)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-030 Header Build / Parse Round-trip
    [Documentation]
    ...    build_nwdaf_header → parse_nwdaf_header 왕복 일치 검증.
    ...    msg_type=Notification, sid=0x0305, mid=0x123, body_len=0x42
    [Tags]    nwdaf    nwdaf_smoke    validation
    ${hdr_bytes}=    Tlv.Build Nwdaf Header    ${NWDAF_MT_NOTI}    ${NWDAF_SID_SUBSCRIBER}    ${291}    ${66}
    Length Should Be    ${hdr_bytes}    ${8}
    NWDAF Header Should Match    ${hdr_bytes}    ${NWDAF_MT_NOTI}    ${NWDAF_SID_SUBSCRIBER}    ${291}

TC-NWDAF-031 General TLV (Tag MSB=0) — 1B Length
    [Documentation]    일반 TLV 인코딩: Tag MSB=0, Length 1B
    [Tags]    nwdaf    nwdaf_smoke    validation
    ${enc}=    Tlv.Pack String    ${NWDAF_TAG_QCI}    QoS200K
    ${tlvs}=    Tlv.Unpack Tlv Stream    ${enc}
    Length Should Be    ${tlvs}    ${1}
    Should Be Equal As Integers    ${tlvs}[0][0]    ${NWDAF_TAG_QCI}
    Should Be Equal As Integers    ${tlvs}[0][1]    ${7}
    ${value_bytes}=    Set Variable    ${tlvs}[0][2]
    ${value_str}=    Evaluate    $value_bytes.decode('ascii')
    Should Be Equal    ${value_str}    QoS200K

TC-NWDAF-032 Multi TLV (Tag MSB=1) — 2B Length
    [Documentation]    Multi TLV 인코딩: Tag MSB=1 (0xFF), Length 2B BE
    [Tags]    nwdaf    nwdaf_smoke    validation
    ${inner1}=    Tlv.Pack String    ${NWDAF_TAG_MDN}    ${NWDAF_TEST_MDN}
    ${inner2}=    Tlv.Pack String    ${NWDAF_TAG_MIN}    ${NWDAF_TEST_MIN}
    ${list_for_multi}=    Create List    ${inner1}    ${inner2}
    ${packet}=    Tlv.Pack Multi Message    ${list_for_multi}
    ${first_byte}=    Evaluate    $packet[0]
    Should Be Equal As Integers    ${first_byte}    ${NWDAF_TAG_MULTI_MESSAGE}
    ${tlvs}=    Tlv.Unpack Tlv Stream    ${packet}
    Length Should Be    ${tlvs}    ${1}
    Should Be Equal As Integers    ${tlvs}[0][0]    ${NWDAF_TAG_MULTI_MESSAGE}
    ${sub}=    Tlv.Unpack Multi Message    ${tlvs}[0][2]
    Length Should Be    ${sub}    ${2}

TC-NWDAF-033 Notification Body 는 MULTI_MESSAGE(0xFF) 단일 TLV
    [Documentation]
    ...    build_nwdaf_notification 결과 Body 가 단일 MULTI_MESSAGE(0xFF) TLV 이고
    ...    그 안에 inner TLV 들이 순서대로 들어있는지 검증 (송신 없음).
    [Tags]    nwdaf    nwdaf_smoke    validation
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2
    ${body}=    Tlv.Build Notification Body    ${c1}    ${qc}    ${c2}
    ${packet}=    Tlv.Build Nwdaf Notification    ${NWDAF_SID_SUBSCRIBER}    ${291}    ${body}
    ${hdr_bytes}=    Evaluate    $packet[:8]
    ${pkt_body}=     Evaluate    $packet[8:]
    ${hdr}=    Tlv.Parse Nwdaf Header    ${hdr_bytes}
    Length Should Be    ${pkt_body}    ${hdr}[body_length]
    ${top}=    Tlv.Unpack Tlv Stream    ${pkt_body}
    Length Should Be    ${top}    ${1}
    Should Be Equal As Integers    ${top}[0][0]    ${NWDAF_TAG_MULTI_MESSAGE}
    ${inner}=    Tlv.Unpack Multi Message    ${top}[0][2]
    Length Should Be    ${inner}    ${{ len($c1) + len($qc) + len($c2) }}

TC-NWDAF-034 Body inner 순서 = COMMON1 + pcefQoSCtrl + COMMON2
    [Documentation]
    ...    inner TLV 시퀀스 첫 태그가 COMMON1.PCEF_TYPE 이고, QOS_HDR 이 COMMON1 직후,
    ...    COMMON2.NETWORK 가 pcefQoSCtrl 직후에 위치하는지 검증.
    [Tags]    nwdaf    nwdaf_smoke    validation
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2
    ${body}=    Tlv.Build Notification Body    ${c1}    ${qc}    ${c2}
    ${packet}=    Tlv.Build Nwdaf Notification    ${NWDAF_SID_SUBSCRIBER}    ${1}    ${body}
    ${pkt_body}=    Evaluate    $packet[8:]
    ${top}=    Tlv.Unpack Tlv Stream    ${pkt_body}
    ${inner}=    Tlv.Unpack Multi Message    ${top}[0][2]
    Should Be Equal As Integers    ${inner}[0][0]    ${NWDAF_TAG_PCEF_TYPE}
    Should Be Equal As Integers    ${inner}[9][0]    ${NWDAF_TAG_QOS_HDR}
    Should Be Equal As Integers    ${inner}[14][0]   ${NWDAF_TAG_NETWORK}



