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
...                           Health Check Request(0x01, Body 없음) — Timeout 30초,
...                           PG 가 Response(0x04) 회신
...      수동 수신          : Notification 에 대한 응답은 규격상 없음.
...
...    [Body 구조 — 규격 4개 섹션]
...      Body = MULTI_MESSAGE(0xFF){ COMMON1 + QoSCtrl 섹션들 + COMMON2 }
...        - COMMON1 (1절, 필수)  : MIN/MDN/CREATE_DATE/TIME/PGW_IP/PCEF_TYPE/QCT/RCT 사용량
...        - QoSCtrl              : PCEF_TYPE **비트마스크** 로 분기 (배타적 enum 아님)
...                                  0x01 → pcefQoSCtrl  (QOS_POLICY/STATUS/TIMER/QUICK_SUPPORT)
...                                  0x02 → dpiQoSCtrl   ((CATEGORY+QOS_POLICY)×6/STATUS/TIMER/QUICK_SUPPORT)
...                                  0x10 → enodebQoSCtl (SUPPORT_TYPE/ARP_QCI_FLAG/ENB_ARP/QCI/...)
...                                  조합 가능 — LTE DPI 는 0x01|0x02 = 0x03
...        - COMMON2 (4절, 필수)  : NETWORK/CONTROL_UNIT/CELL_ID/DN_USAGE/USING_USER/...
...      QOS_HDR(0x3A) 은 wrapper 가 아니라 flat numeric 플래그 TLV.
...      TAG 0x0C 는 다의적이다 — pcef 에서는 STATUS, dpi 에서는 CATEGORY(반복) + STATUS.
...
...    [TC 번호 체계]
...      TC-NWDAF-001       : Health Check Request 송신 / Response 수신 (NWDAF → PG)
...      TC-NWDAF-002 ~ 003 : Smoke (PGW/eNB 최소 송신)
...      TC-NWDAF-004 ~ 005 : 5G 가입자 Notification (PGW/eNB, NETWORK=5G)
...      TC-NWDAF-006 ~ 009 : pcefQoSCtrl STATUS (Normal/Minor/Major/Critical)
...      TC-NWDAF-010 ~ 011 : pcefQoSCtrl QUICK_SUPPORT
...      TC-NWDAF-012 ~ 013 : pcefQoSCtrl QOS_POLICY
...      TC-NWDAF-014 ~ 020 : enodebQoSCtl (SUPPORT_TYPE / ARP_QCI_FLAG / ENB_ARP)
...      TC-NWDAF-021 ~ 022 : COMMON1 (RCT_3M/1M_USAGE 경계)
...      TC-NWDAF-023 ~ 030 : COMMON2 (NETWORK / CONTROL_UNIT / DN_USAGE / USER_RATIO)
...      TC-NWDAF-031       : Message Id wrap
...      TC-NWDAF-032 ~ 036 : dpiQoSCtrl (LTE DPI QoS, 인코딩 검증 — 034~036 은 송신 없음)

Resource    ../../resources/variables.robot
Resource    ../../resources/nwdaf_variables.robot
Resource    ../../resources/common_keywords.robot
Resource    ../../resources/nwdaf_keywords.robot

Suite Setup      Suite NWDAF Connect
Suite Teardown   Suite NWDAF Disconnect
Test Setup       Check NWDAF Socket

*** Test Cases ***

# ════════════════════════════════════════════════════════════════
# Health Check — NWDAF(도구) 가 PG 로 Request 를 보낸다. Timeout 30초.
# ════════════════════════════════════════════════════════════════

TC-NWDAF-001 Health Check Request 송신 및 응답 수신
    [Documentation]
    ...    NWDAF → PG 로 Health Check Request(Message Type 0x01, Body 없음) 를 송신하고
    ...    PG 의 Response(0x04) 를 수신해 검증한다.
    ...    Message Id 가 요청과 동일하게 echo 되는지, Body 가 없는지까지 확인한다.
    [Tags]    nwdaf    nwdaf_healthcheck    nwdaf_smoke
    ${hdr}=    Send NWDAF Health Check
    Should Be Equal As Integers    ${hdr}[msg_type]      ${NWDAF_MT_RESP}
    Should Be Equal As Integers    ${hdr}[body_length]   ${0}


# ════════════════════════════════════════════════════════════════
# Smoke: PCEF_TYPE 분기 별 최소 송신
# ════════════════════════════════════════════════════════════════

TC-NWDAF-002 PGW 최소 Notification (Smoke)
    [Documentation]
    ...    PCEF_TYPE=0x01 (P-GW/SMF). COMMON1 + pcefQoSCtrl + COMMON2 송신 → 성공 검증.
    [Tags]    nwdaf    nwdaf_smoke    nwdaf_pgw
    ${mid}=    Send Subscriber QoS Notification PGW
    Should Be True    0 <= ${mid} <= 0xFFF    msg=Message Id 범위 위반: ${mid}


TC-NWDAF-003 eNB 최소 Notification (Smoke)
    [Documentation]
    ...    PCEF_TYPE=0x10 (eNB). COMMON1 + enodebQoSCtl + COMMON2 송신 → 성공 검증.
    [Tags]    nwdaf    nwdaf_smoke    nwdaf_enb
    ${mid}=    Send Subscriber QoS Notification ENB
    Should Be True    0 <= ${mid} <= 0xFFF    msg=Message Id 범위 위반: ${mid}


# ════════════════════════════════════════════════════════════════
# 5G 가입자 Notification (MIN/MDN = 5G 가입자, NETWORK=5G)
# 대응 LTE: TC-NWDAF-002/003 (기본 LTE 가입자)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-004 5G 가입자 PGW Notification
    [Documentation]
    ...    5G 가입자(MIN=${NWDAF_TEST_MIN_5G}, MDN=${NWDAF_TEST_MDN_5G}) 대상
    ...    PCEF_TYPE=0x01 (P-GW/SMF) + NETWORK=5G Notification 송신 → 성공 검증.
    [Tags]    nwdaf    nwdaf_smoke    nwdaf_pgw    nwdaf_5g
    ${mid}=    Send Subscriber QoS Notification PGW
    ...    mdn=${NWDAF_TEST_MDN_5G}    min=${NWDAF_TEST_MIN_5G}    network=${NWDAF_NET_5G}
    Should Be True    0 <= ${mid} <= 0xFFF    msg=Message Id 범위 위반: ${mid}


TC-NWDAF-005 5G 가입자 eNB Notification
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

TC-NWDAF-006 PGW STATUS Normal (0)
    [Documentation]    STATUS='0' (Normal)
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_status
    Send Subscriber QoS Notification PGW    status=${NWDAF_STATUS_NORMAL}

TC-NWDAF-007 PGW STATUS Minor (1)
    [Documentation]    STATUS='1' (Minor)
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_status
    Send Subscriber QoS Notification PGW    status=${NWDAF_STATUS_MINOR}

TC-NWDAF-008 PGW STATUS Major (2)
    [Documentation]    STATUS='2' (Major)
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_status
    Send Subscriber QoS Notification PGW    status=${NWDAF_STATUS_MAJOR}

TC-NWDAF-009 PGW STATUS Critical (3)
    [Documentation]    STATUS='3' (Critical)
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_status
    Send Subscriber QoS Notification PGW    status=${NWDAF_STATUS_CRITICAL}


# ════════════════════════════════════════════════════════════════
# pcefQoSCtrl — QUICK_SUPPORT (규격 2.5)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-010 PGW QUICK_SUPPORT 즉시 (0)
    [Documentation]    QUICK_SUPPORT='0' (즉시제어)
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_quick
    Send Subscriber QoS Notification PGW    quick_support=${NWDAF_QUICK_NOW}

TC-NWDAF-011 PGW QUICK_SUPPORT Update 후 (1)
    [Documentation]    QUICK_SUPPORT='1' (update 수신 후 제어)
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_quick
    Send Subscriber QoS Notification PGW    quick_support=${NWDAF_QUICK_AFTER}


# ════════════════════════════════════════════════════════════════
# pcefQoSCtrl — QOS_POLICY (규격 2.2)
# NWDAF 가 PCRF 로 내리는 정책명. PG 는 SMF 방향일 때 변환 처리.
# ════════════════════════════════════════════════════════════════

TC-NWDAF-012 PGW QOS_POLICY QoS400K_NoGBR
    [Documentation]
    ...    QOS_POLICY='QoS400K_NoGBR' (400K Non-GBR 정책).
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_qos_policy
    Send Subscriber QoS Notification PGW    qos_policy=QoS400K_NoGBR

TC-NWDAF-013 PGW QOS_POLICY NoQoS_NoGBR
    [Documentation]
    ...    QOS_POLICY='NoQoS_NoGBR' (QoS 없음 / Non-GBR).
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_qos_policy
    Send Subscriber QoS Notification PGW    qos_policy=NoQoS_NoGBR


# ════════════════════════════════════════════════════════════════
# enodebQoSCtl — SUPPORT_TYPE (규격 3.2)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-014 eNB SUPPORT_TYPE 제어 (1)
    [Documentation]    SUPPORT_TYPE=1 (제어)
    [Tags]    nwdaf    nwdaf_enb    nwdaf_support
    Send Subscriber QoS Notification ENB    support_type=${NWDAF_SUPPORT_APPLY}

TC-NWDAF-015 eNB SUPPORT_TYPE 해지 (2)
    [Documentation]    SUPPORT_TYPE=2 (해지)
    [Tags]    nwdaf    nwdaf_enb    nwdaf_support
    Send Subscriber QoS Notification ENB    support_type=${NWDAF_SUPPORT_RELEASE}


# ════════════════════════════════════════════════════════════════
# enodebQoSCtl — ARP_QCI_FLAG (규격 3.3)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-016 eNB ARP_QCI_FLAG ARP only (0)
    [Tags]    nwdaf    nwdaf_enb    nwdaf_arpqci
    Send Subscriber QoS Notification ENB    arp_qci_flag=${NWDAF_ARPQCI_ARP}

TC-NWDAF-017 eNB ARP_QCI_FLAG QCI only (1)
    [Tags]    nwdaf    nwdaf_enb    nwdaf_arpqci
    Send Subscriber QoS Notification ENB    arp_qci_flag=${NWDAF_ARPQCI_QCI}

TC-NWDAF-018 eNB ARP_QCI_FLAG ARP&QCI (2)
    [Tags]    nwdaf    nwdaf_enb    nwdaf_arpqci
    Send Subscriber QoS Notification ENB    arp_qci_flag=${NWDAF_ARPQCI_BOTH}


# ════════════════════════════════════════════════════════════════
# enodebQoSCtl — ENB_ARP Band 코드 (규격 3.4)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-019 eNB ENB_ARP Band 3->5/1 (12)
    [Tags]    nwdaf    nwdaf_enb    nwdaf_band
    Send Subscriber QoS Notification ENB    enb_arp=${NWDAF_ENB_ARP_BAND_35}

TC-NWDAF-020 eNB ENB_ARP Band 1/5->3 (13)
    [Tags]    nwdaf    nwdaf_enb    nwdaf_band
    Send Subscriber QoS Notification ENB    enb_arp=${NWDAF_ENB_ARP_BAND_153}


# ════════════════════════════════════════════════════════════════
# COMMON1 — RCT_3M/1M_USAGE 경계값
# ════════════════════════════════════════════════════════════════

TC-NWDAF-021 COMMON1 RCT Usage 경계 0
    [Documentation]    RCT_3M/1M_USAGE 모두 0
    [Tags]    nwdaf    nwdaf_common1    nwdaf_usage
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}    rct_3m_usage=${0}    rct_1m_usage=${0}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2
    ${body}=    Tlv.Build Notification Body    ${c1}    ${qc}    ${c2}
    Send NWDAF Notification    ${body}

TC-NWDAF-022 COMMON1 RCT Usage 경계 최대 (9,999,999)
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

TC-NWDAF-023 COMMON2 NETWORK WCDMA (1)
    [Tags]    nwdaf    nwdaf_common2    nwdaf_network
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2    network=${NWDAF_NET_WCDMA}
    ${body}=    Tlv.Build Notification Body    ${c1}    ${qc}    ${c2}
    Send NWDAF Notification    ${body}

TC-NWDAF-024 COMMON2 NETWORK LTE (2)
    [Tags]    nwdaf    nwdaf_common2    nwdaf_network
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2    network=${NWDAF_NET_LTE}
    ${body}=    Tlv.Build Notification Body    ${c1}    ${qc}    ${c2}
    Send NWDAF Notification    ${body}

TC-NWDAF-025 COMMON2 NETWORK 5G (3)
    [Tags]    nwdaf    nwdaf_common2    nwdaf_network
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2    network=${NWDAF_NET_5G}
    ${body}=    Tlv.Build Notification Body    ${c1}    ${qc}    ${c2}
    Send NWDAF Notification    ${body}


# ════════════════════════════════════════════════════════════════
# COMMON2 — CONTROL_UNIT (규격 4.2)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-026 COMMON2 CONTROL_UNIT Cell (1)
    [Tags]    nwdaf    nwdaf_common2    nwdaf_cu
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2    control_unit=${NWDAF_CU_CELL}
    Send NWDAF Notification    ${{$c1 + $qc + $c2}}

TC-NWDAF-027 COMMON2 CONTROL_UNIT eNodeB (2)
    [Tags]    nwdaf    nwdaf_common2    nwdaf_cu
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2    control_unit=${NWDAF_CU_ENODEB}
    Send NWDAF Notification    ${{$c1 + $qc + $c2}}


# ════════════════════════════════════════════════════════════════
# COMMON2 — DN_USAGE 경계 / 통계 변형
# ════════════════════════════════════════════════════════════════

TC-NWDAF-028 COMMON2 DN_USAGE 경계값 0
    [Tags]    nwdaf    nwdaf_common2    nwdaf_usage
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2    dn_usage=${0}    cell_avg_usage=${0}    user_usage=${0}
    Send NWDAF Notification    ${{$c1 + $qc + $c2}}

TC-NWDAF-029 COMMON2 DN_USAGE 경계 최대 (9,999,999)
    [Tags]    nwdaf    nwdaf_common2    nwdaf_usage
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2    dn_usage=${9999999}    cell_avg_usage=${9999999}    user_usage=${9999999}
    Send NWDAF Notification    ${{$c1 + $qc + $c2}}

TC-NWDAF-030 COMMON2 USER_RATIO Disable (1)
    [Documentation]    USER_RATIO=1 (Disable, 규격 4.9 원문)
    [Tags]    nwdaf    nwdaf_common2    nwdaf_ratio
    ${c1}=    Build COMMON1    ${NWDAF_PCEF_PGW}
    ${qc}=    Build pcefQoSCtrl
    ${c2}=    Build COMMON2    user_ratio=${NWDAF_DISABLE}
    Send NWDAF Notification    ${{$c1 + $qc + $c2}}


# ════════════════════════════════════════════════════════════════
# Message Id 순환 (0xFFF → 0x000)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-031 Message Id Wrap (0xFFF → 0x000)
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
# dpiQoSCtrl — LTE DPI QoS (PCEF_TYPE 비트 0x02)
# PCEF_TYPE 은 비트마스크이므로 P-GW(0x01) 와 DPI(0x02) 가 함께 실릴 수 있다.
# 구조: QOS_HDR(0x02) + (CATEGORY+QOS_POLICY)×6 + STATUS + TIMER(uint32) + QUICK_SUPPORT
#       CATEGORY 는 ASCII 'A'~'F' (PG 참조 시뮬레이터 기준)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-032 LTE DPI QoS 추가 (PCEF_TYPE=0x01|0x02)
    [Documentation]
    ...    LTE 가입자에 DPI QoS 를 추가 송신.
    ...    COMMON1 + pcefQoSCtrl + dpiQoSCtrl + COMMON2 가 한 전문에 실린다.
    [Tags]    nwdaf    nwdaf_dpi    nwdaf_pgw    lte
    ${mid}=    Send Subscriber QoS Notification LTE DPI
    Should Be True    0 <= ${mid} <= 0xFFF    msg=Message Id 범위 위반: ${mid}

TC-NWDAF-033 DPI 단독 Notification (PCEF_TYPE=0x02)
    [Documentation]    PCEF_TYPE=0x02 (DPI 단독). COMMON1 + dpiQoSCtrl + COMMON2.
    [Tags]    nwdaf    nwdaf_dpi
    ${mid}=    Send DPI Only QoS Notification
    Should Be True    0 <= ${mid} <= 0xFFF    msg=Message Id 범위 위반: ${mid}


