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
...    [Service Id]
...      0x0305 가입자 단위 / 0x0306 기지국 단위 / 0x0307 서비스 단위(P-GW 제외)
...
...    [주의]
...      QOS_HDR(0x3A) 내부 서브 TLV 구조는 추정. 운영 PG 검증 후 확정 필요.
...      자세한 미해결 항목은 NWDAF_HANDOVER.md 11절 참고.

Resource    ../../resources/variables.robot
Resource    ../../resources/common_keywords.robot
Resource    ../../resources/nwdaf_keywords.robot

Suite Setup      Suite NWDAF Connect
Suite Teardown   Suite NWDAF Disconnect
Test Setup       Check NWDAF Socket

*** Test Cases ***

# ════════════════════════════════════════════════════════════════
# Smoke: Service Id 별 최소 Notification 1건
# ════════════════════════════════════════════════════════════════

TC-NWDAF-0305 Send Subscriber QoS Notification - 최소 구성 (Smoke)
    [Documentation]
    ...    Service Id=0x0305, MsgType=Notification
    ...    헤더 + 최소 가입자 식별 TLV + QOS_HDR(PGW) 송신 → 송신 성공 검증
    [Tags]    nwdaf    nwdaf_smoke    nwdaf_0305
    ${mid}=    Send Subscriber QoS Notification
    Should Be True    0 <= ${mid} <= 0xFFF
    ...    msg=Message Id 범위 위반: ${mid}

TC-NWDAF-0306 Send Cell QoS Notification - 최소 구성 (Smoke)
    [Documentation]
    ...    Service Id=0x0306, MsgType=Notification
    ...    LOCATION_ID + CONTROL_UNIT + 통계 + QOS_HDR(eNB) 송신
    [Tags]    nwdaf    nwdaf_smoke    nwdaf_0306
    ${mid}=    Send Cell QoS Notification
    Should Be True    0 <= ${mid} <= 0xFFF

TC-NWDAF-0307 Send Service QoS Notification - 최소 구성 (Smoke)
    [Documentation]
    ...    Service Id=0x0307, MsgType=Notification
    ...    APP_TYPE + QOS_HDR(DPI) 송신 (PGW 제외)
    [Tags]    nwdaf    nwdaf_smoke    nwdaf_0307
    ${mid}=    Send Service QoS Notification
    Should Be True    0 <= ${mid} <= 0xFFF


# ════════════════════════════════════════════════════════════════
# QOS_HDR PCEF별 (0x0305 기준)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-0305 PGW QoS Control (0x01)
    [Documentation]
    ...    QOS_HDR PCEF=PGW(0x01), QOS_POLICY/TIMER/QUICK_SUPPORT
    [Tags]    nwdaf    nwdaf_0305    nwdaf_qos_pgw
    ${mid}=    Send Subscriber QoS Notification    pcef=${NWDAF_PCEF_PGW}

TC-NWDAF-0305 DPI QoS Control (0x02) - Category × 6
    [Documentation]
    ...    QOS_HDR PCEF=DPI(0x02), CATEGORY+QOS_POLICY 6쌍
    ...    TODO: 6쌍 미만 케이스 운영 PG 동작 확인
    [Tags]    nwdaf    nwdaf_0305    nwdaf_qos_dpi
    ${mid}=    Send Subscriber QoS Notification    pcef=${NWDAF_PCEF_DPI}

TC-NWDAF-0305 VOMS QoS Control (0x04)
    [Documentation]    QOS_HDR PCEF=VOMS(0x04) — 규격 확인 후 서브 구조 확정 필요
    [Tags]    nwdaf    nwdaf_0305    nwdaf_qos_voms
    ${mid}=    Send Subscriber QoS Notification    pcef=${NWDAF_PCEF_VOMS}

TC-NWDAF-0305 APRS QoS Control (0x08)
    [Documentation]    QOS_HDR PCEF=APRS(0x08) — 규격 확인 후 서브 구조 확정 필요
    [Tags]    nwdaf    nwdaf_0305    nwdaf_qos_aprs
    ${mid}=    Send Subscriber QoS Notification    pcef=${NWDAF_PCEF_APRS}

TC-NWDAF-0305 eNB QoS Control (0x10)
    [Documentation]
    ...    QOS_HDR PCEF=eNB(0x10), SUPPORT_TYPE+ARP_QCI_FLAG+ENB_ARP+QCI+TIMER
    [Tags]    nwdaf    nwdaf_0305    nwdaf_qos_enb
    ${mid}=    Send Subscriber QoS Notification    pcef=${NWDAF_PCEF_ENB}


# ════════════════════════════════════════════════════════════════
# 통계/사용량 (NWDAF 핵심 데이터)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-0306 Cell Usage - 경계값 0
    [Documentation]    DN_USAGE/CELL_AVG_USAGE 모두 0
    [Tags]    nwdaf    nwdaf_0306    nwdaf_usage
    ${mid}=    Send Cell QoS Notification    dn_usage=${0}    cell_avg_usage=${0}

TC-NWDAF-0306 Cell Usage - 경계값 최대 (9,999,999)
    [Documentation]    DN_USAGE/CELL_AVG_USAGE 최대값 (KB)
    [Tags]    nwdaf    nwdaf_0306    nwdaf_usage
    ${mid}=    Send Cell QoS Notification    dn_usage=${9999999}    cell_avg_usage=${9999999}

TC-NWDAF-0306 RCT 3M/1M Usage 포함 Cell Notification
    [Documentation]    RCT_3M_USAGE(0x38) / RCT_1M_USAGE(0x39) 포함 (Append Usage TLVs 사용)
    [Tags]    nwdaf    nwdaf_0306    nwdaf_usage
    ${ts}=    Get Timestamp 14
    ${tlvs}=    New TLV List
    Add Uint8 TLV     ${tlvs}    ${NWDAF_TAG_QOS_CONTROL_TYPE}    ${NWDAF_QCT_CELL}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_LOCATION_ID}         ${NWDAF_TEST_CELL_ID}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_CONTROL_UNIT}        ${NWDAF_CU_CELL}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_TIMESTAMP}           ${ts}
    Append Usage TLVs    ${tlvs}
    ${qos}=    Build QOS HDR    ${NWDAF_PCEF_ENB}
    Append To List    ${tlvs}    ${qos}
    ${mid}=    Send NWDAF Notification    ${NWDAF_SID_CELL}    ${tlvs}


# ════════════════════════════════════════════════════════════════
# Heavy/Medium/Light User 분포 (0x32~0x34, 0x36, 0x37)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-0306 Heavy/Medium/Light User 분포
    [Documentation]
    ...    HEAVY/MEDIUM/LIGHT_USER + USER_USAGE + USER_RATIO 통합
    ...    TODO: USER_RATIO 값 형식(% 정수/실수) 규격 추가 확인
    [Tags]    nwdaf    nwdaf_0306    nwdaf_heavy
    ${ts}=    Get Timestamp 14
    ${tlvs}=    New TLV List
    Add Uint8 TLV     ${tlvs}    ${NWDAF_TAG_QOS_CONTROL_TYPE}    ${NWDAF_QCT_CELL}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_LOCATION_ID}         ${NWDAF_TEST_CELL_ID}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_CONTROL_UNIT}        ${NWDAF_CU_CELL}
    Add Uint32 TLV    ${tlvs}    ${NWDAF_TAG_HEAVY_USER}          ${100}
    Add Uint32 TLV    ${tlvs}    ${NWDAF_TAG_MEDIUM_USER}         ${300}
    Add Uint32 TLV    ${tlvs}    ${NWDAF_TAG_LIGHT_USER}          ${600}
    Add Uint32 TLV    ${tlvs}    ${NWDAF_TAG_USER_USAGE}          ${50000}
    Add Uint32 TLV    ${tlvs}    ${NWDAF_TAG_USER_RATIO}          ${30}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_TIMESTAMP}           ${ts}
    ${qos}=    Build QOS HDR    ${NWDAF_PCEF_ENB}
    Append To List    ${tlvs}    ${qos}
    ${mid}=    Send NWDAF Notification    ${NWDAF_SID_CELL}    ${tlvs}


# ════════════════════════════════════════════════════════════════
# 동시 사용자 (0x1A) / Try (0x18, 0x19)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-0306 Concurrent / Try 통계 포함
    [Documentation]    CONCURRENT_USER + TRY_USER + TRY_COUNT 포함 Notification
    [Tags]    nwdaf    nwdaf_0306    nwdaf_concurrent
    ${ts}=    Get Timestamp 14
    ${tlvs}=    New TLV List
    Add Uint8 TLV     ${tlvs}    ${NWDAF_TAG_QOS_CONTROL_TYPE}    ${NWDAF_QCT_CELL}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_LOCATION_ID}         ${NWDAF_TEST_CELL_ID}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_CONTROL_UNIT}        ${NWDAF_CU_CELL}
    Add Uint32 TLV    ${tlvs}    ${NWDAF_TAG_CONCURRENT_USER}     ${200}
    Add Uint32 TLV    ${tlvs}    ${NWDAF_TAG_TRY_USER}            ${50}
    Add Uint32 TLV    ${tlvs}    ${NWDAF_TAG_TRY_COUNT}           ${120}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_TIMESTAMP}           ${ts}
    ${qos}=    Build QOS HDR    ${NWDAF_PCEF_ENB}
    Append To List    ${tlvs}    ${qos}
    ${mid}=    Send NWDAF Notification    ${NWDAF_SID_CELL}    ${tlvs}


# ════════════════════════════════════════════════════════════════
# Message Id 순환 (0xFFF → 0x000)
# ════════════════════════════════════════════════════════════════

TC-NWDAF Message Id Wrap (0xFFF → 0x000)
    [Documentation]
    ...    Message Id 0xFFF 도달 후 0x000 으로 wrap 되는지 검증.
    ...    Suite Variable ${NWDAF_MSG_ID} 를 강제로 0xFFE 로 설정 후 2회 송신.
    [Tags]    nwdaf    nwdaf_msgid_wrap
    Set Suite Variable    ${NWDAF_MSG_ID}    ${4094}    # 0xFFE
    ${mid1}=    Send Subscriber QoS Notification
    Should Be Equal As Integers    ${mid1}    ${4095}    # 0xFFF
    ${mid2}=    Send Subscriber QoS Notification
    Should Be Equal As Integers    ${mid2}    ${0}
    Set Suite Variable    ${NWDAF_MSG_ID}    ${0}


# ════════════════════════════════════════════════════════════════
# Build 단위 검증 (송신 없이 패킷 바이트 검증)
# ════════════════════════════════════════════════════════════════

TC-NWDAF Header Build / Parse Round-trip
    [Documentation]
    ...    build_nwdaf_header → parse_nwdaf_header 왕복 일치 검증.
    ...    msg_type=Notification, sid=0x0305, mid=0x123, body_len=0x42
    [Tags]    nwdaf    nwdaf_smoke    validation
    ${hdr_bytes}=    Tlv.Build Nwdaf Header    ${NWDAF_MT_NOTI}    ${NWDAF_SID_SUBSCRIBER}    ${291}    ${66}
    Length Should Be    ${hdr_bytes}    ${8}
    NWDAF Header Should Match    ${hdr_bytes}    ${NWDAF_MT_NOTI}    ${NWDAF_SID_SUBSCRIBER}    ${291}

TC-NWDAF General TLV (Tag MSB=0) — 1B Length
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

TC-NWDAF Multi TLV (Tag MSB=1) — 2B Length
    [Documentation]    Multi TLV 인코딩: Tag MSB=1 (0xFF), Length 2B BE
    [Tags]    nwdaf    nwdaf_smoke    validation
    ${inner1}=    Tlv.Pack String    ${NWDAF_TAG_MDN}     ${NWDAF_TEST_MDN}
    ${inner2}=    Tlv.Pack String    ${NWDAF_TAG_IMSI}    ${NWDAF_TEST_IMSI}
    ${list_for_multi}=    Create List    ${inner1}    ${inner2}
    ${packet}=    Tlv.Pack Multi Message    ${list_for_multi}
    ${first_byte}=    Evaluate    $packet[0]
    Should Be Equal As Integers    ${first_byte}    ${NWDAF_TAG_MULTI_MESSAGE}
    ${tlvs}=    Tlv.Unpack Tlv Stream    ${packet}
    Length Should Be    ${tlvs}    ${1}
    Should Be Equal As Integers    ${tlvs}[0][0]    ${NWDAF_TAG_MULTI_MESSAGE}
    ${sub}=    Tlv.Unpack Multi Message    ${tlvs}[0][2]
    Length Should Be    ${sub}    ${2}

TC-NWDAF Notification Body 는 MULTI_MESSAGE(0xFF) 단일 TLV
    [Documentation]
    ...    build_nwdaf_notification 결과 Body 가 단일 MULTI_MESSAGE(0xFF) TLV 이고
    ...    그 안에 inner TLV 들이 순서대로 들어있는지 검증 (송신 없음).
    [Tags]    nwdaf    nwdaf_smoke    validation
    ${tlvs}=    New TLV List
    Add Uint8 TLV     ${tlvs}    ${NWDAF_TAG_QOS_CONTROL_TYPE}    ${NWDAF_QCT_SUBSCRIBER}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_MDN}                 ${NWDAF_TEST_MDN}
    ${packet}=    Tlv.Build Nwdaf Notification    ${NWDAF_SID_SUBSCRIBER}    ${291}    ${tlvs}
    ${hdr_bytes}=    Evaluate    $packet[:8]
    ${body}=         Evaluate    $packet[8:]
    ${hdr}=    Tlv.Parse Nwdaf Header    ${hdr_bytes}
    Length Should Be    ${body}    ${hdr}[body_length]
    ${top}=    Tlv.Unpack Tlv Stream    ${body}
    Length Should Be    ${top}    ${1}
    Should Be Equal As Integers    ${top}[0][0]    ${NWDAF_TAG_MULTI_MESSAGE}
    ${inner}=    Tlv.Unpack Multi Message    ${top}[0][2]
    Length Should Be    ${inner}    ${2}
    Should Be Equal As Integers    ${inner}[0][0]    ${NWDAF_TAG_QOS_CONTROL_TYPE}
    Should Be Equal As Integers    ${inner}[1][0]    ${NWDAF_TAG_MDN}


# ════════════════════════════════════════════════════════════════
# Negative
# ════════════════════════════════════════════════════════════════

TC-NWDAF Negative — Unknown NETWORK Value
    [Documentation]
    ...    NETWORK(0x1F) 값 = 0x03 (규격 범위 외) 송신.
    ...    규격: 0x00=2G, 0x01=WCDMA, 0x02=LTE. PG 처리 동작 확인.
    ...    TODO: 운영 PG 의 정확한 처리 코드(무시/에러) 확인.
    [Tags]    nwdaf    nwdaf_negative
    ${ts}=    Get Timestamp 14
    ${tlvs}=    New TLV List
    Add Uint8 TLV     ${tlvs}    ${NWDAF_TAG_QOS_CONTROL_TYPE}    ${NWDAF_QCT_SUBSCRIBER}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_MDN}                 ${NWDAF_TEST_MDN}
    Add Uint8 TLV     ${tlvs}    ${NWDAF_TAG_NETWORK}             ${3}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_TIMESTAMP}           ${ts}
    ${qos}=    Build QOS HDR    ${NWDAF_PCEF_PGW}
    Append To List    ${tlvs}    ${qos}
    ${mid}=    Send NWDAF Notification    ${NWDAF_SID_SUBSCRIBER}    ${tlvs}

TC-NWDAF Negative — Unknown TAG (0xFE)
    [Documentation]
    ...    규격 미정의 TAG(0xFE) 송신. 규격: nfwOk 로 무시되어야 함.
    ...    TODO: PG 무시 동작이 실제로 일어나는지 운영 환경에서 검증.
    [Tags]    nwdaf    nwdaf_negative    nwdaf_unknown_tag
    ${ts}=    Get Timestamp 14
    ${tlvs}=    New TLV List
    Add Uint8 TLV     ${tlvs}    ${NWDAF_TAG_QOS_CONTROL_TYPE}    ${NWDAF_QCT_SUBSCRIBER}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_MDN}                 ${NWDAF_TEST_MDN}
    Add String TLV    ${tlvs}    ${254}                           DUMMY    # 0xFE 미정의
    Add String TLV    ${tlvs}    ${NWDAF_TAG_TIMESTAMP}           ${ts}
    ${qos}=    Build QOS HDR    ${NWDAF_PCEF_PGW}
    Append To List    ${tlvs}    ${qos}
    ${mid}=    Send NWDAF Notification    ${NWDAF_SID_SUBSCRIBER}    ${tlvs}

TC-NWDAF Negative — Unknown Service Id (0x0308)
    [Documentation]
    ...    Service Id=0x0308 (미정의) 송신. PG 동작 확인.
    ...    TODO: 운영 PG 의 처리 코드(연결 종료/무시) 확인.
    [Tags]    nwdaf    nwdaf_negative    nwdaf_unknown_service_id
    ${tlvs}=    New TLV List
    Add String TLV    ${tlvs}    ${NWDAF_TAG_MDN}    ${NWDAF_TEST_MDN}
    ${mid}=    Send NWDAF Notification    ${776}    ${tlvs}    # 0x0308
