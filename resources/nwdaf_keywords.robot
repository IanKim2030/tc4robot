*** Settings ***
Documentation
...    NWDAF ↔ PG 연동 키워드 (SKT PG-SC Message Format 기반)
...
...    [인터페이스]
...      방향   : NWDAF(테스트 도구, Client) → PG (Server)
...      포트   : ${NWDAF_PORT} (TODO: 실환경 값 확인)
...      Body   : MULTI_MESSAGE(0xFF) TLV 하나로 inner TLV 들을 감싼 바이너리
...      주력   : Notification(0b010) 단방향, 응답 거의 없음
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
# Body Builder Helper (TLV bytes 리스트 누적용)
# ══════════════════════════════════════════════════════════════════

New TLV List
    [Documentation]    빈 TLV bytes 리스트 생성 (가독성용 alias)
    ${lst}=    Create List
    RETURN    ${lst}

Add Uint8 TLV
    [Arguments]    ${tlvs}    ${tag}    ${value}
    ${enc}=    Tlv.Pack Uint8    ${tag}    ${value}
    Append To List    ${tlvs}    ${enc}

Add Uint16 TLV
    [Arguments]    ${tlvs}    ${tag}    ${value}
    ${enc}=    Tlv.Pack Uint16    ${tag}    ${value}
    Append To List    ${tlvs}    ${enc}

Add Uint32 TLV
    [Arguments]    ${tlvs}    ${tag}    ${value}
    ${enc}=    Tlv.Pack Uint32    ${tag}    ${value}
    Append To List    ${tlvs}    ${enc}

Add String TLV
    [Arguments]    ${tlvs}    ${tag}    ${value}
    ${enc}=    Tlv.Pack String    ${tag}    ${value}
    Append To List    ${tlvs}    ${enc}


# ══════════════════════════════════════════════════════════════════
# 저수준 송신: TLV 리스트 → Notification 패킷 송신
# ══════════════════════════════════════════════════════════════════

Send NWDAF Notification
    [Documentation]
    ...    이미 인코딩된 TLV bytes 리스트를 받아 Notification 으로 송신.
    ...    tlv_bytes_list 는 ${EMPTY} 가 아닌 진짜 bytes 객체들의 list.
    [Arguments]    ${service_id}    ${tlv_bytes_list}    ${message_id}=${NONE}
    ${mid}=    Run Keyword If    $message_id is None    Next NWDAF Msg Id
    ...        ELSE    Set Variable    ${message_id}
    ${sent}=    Tlv.Send Nwdaf Notification    ${NWDAF_SOCK}    ${service_id}    ${mid}    ${tlv_bytes_list}
    Log    [TX→NWDAF] sid=${service_id} mid=${mid} bytes=${sent}
    RETURN    ${mid}


# ══════════════════════════════════════════════════════════════════
# QOS_HDR(0x3A) PCEF별 빌더 디스패치
# ══════════════════════════════════════════════════════════════════

Build QOS HDR
    [Documentation]
    ...    PCEF Type 에 따라 적절한 pack_qos_hdr_xxx 호출 → QOS_HDR(0x3A) TLV bytes 반환.
    ...    TODO: 운영 PG 검증 후 PCEF별 서브 TLV 구조 확정.
    [Arguments]
    ...    ${pcef}
    ...    ${qos_policy}=${NWDAF_TEST_QOS_POLICY}
    ...    ${load_status}=${NWDAF_TEST_LOAD_STATUS}
    ...    ${timer}=${NWDAF_TEST_TIMER}
    ...    ${quick}=${NWDAF_QUICK_NOW}
    ...    ${categories}=${NONE}
    ...    ${policies}=${NONE}
    ...    ${support_type}=${NWDAF_SUPPORT_APPLY}
    ...    ${arp_qci_flag}=${NWDAF_ARPQCI_QCI}
    ...    ${enb_arp}=${12}
    ...    ${capability}=${0}
    ...    ${vulnerability}=${0}
    ...    ${qci}=${NWDAF_TEST_QCI}
    IF    ${pcef} == ${NWDAF_PCEF_PGW}
        ${q}=    Tlv.Pack Qos Hdr Pgw    ${qos_policy}    ${load_status}    ${timer}    ${quick}
        RETURN    ${q}
    END
    IF    ${pcef} == ${NWDAF_PCEF_DPI}
        ${cats}=    Run Keyword If    $categories is None
        ...        Split String    ${NWDAF_TEST_CATEGORY_LIST}    ,
        ...        ELSE    Set Variable    ${categories}
        ${pols}=    Run Keyword If    $policies is None
        ...        Split String    ${NWDAF_TEST_POLICY_LIST}    ,
        ...        ELSE    Set Variable    ${policies}
        ${q}=    Tlv.Pack Qos Hdr Dpi    ${cats}    ${pols}    ${load_status}    ${timer}    ${quick}
        RETURN    ${q}
    END
    IF    ${pcef} == ${NWDAF_PCEF_VOMS}
        ${q}=    Tlv.Pack Qos Hdr Voms    ${qos_policy}    ${load_status}    ${timer}    ${quick}
        RETURN    ${q}
    END
    IF    ${pcef} == ${NWDAF_PCEF_APRS}
        ${q}=    Tlv.Pack Qos Hdr Aprs    ${qos_policy}    ${load_status}    ${timer}    ${quick}
        RETURN    ${q}
    END
    IF    ${pcef} == ${NWDAF_PCEF_ENB}
        ${q}=    Tlv.Pack Qos Hdr Enb    ${support_type}    ${arp_qci_flag}    ${enb_arp}    ${capability}    ${vulnerability}    ${qci}    ${timer}
        RETURN    ${q}
    END
    Fail    알 수 없는 PCEF Type: ${pcef}


# ══════════════════════════════════════════════════════════════════
# 시나리오: 0x0305 가입자 단위 QoS Notification
# ══════════════════════════════════════════════════════════════════

Send Subscriber QoS Notification
    [Documentation]
    ...    Service Id=0x0305, Message Type=Notification
    ...    가입자 식별 TLV(MDN/IMSI/...) + QOS_HDR(PCEF별) 묶음 송신
    ...    TODO: 규격 6 (Service Id별 TLV 의무/선택) 확인 후 필수 TLV 보강.
    [Arguments]
    ...    ${mdn}=${NWDAF_TEST_MDN}
    ...    ${imsi}=${NWDAF_TEST_IMSI}
    ...    ${pgw_host}=${NWDAF_TEST_PGW_HOST}
    ...    ${qos_policy}=${NWDAF_TEST_QOS_POLICY}
    ...    ${pcef}=${NWDAF_PCEF_PGW}
    ...    ${quick}=${NWDAF_QUICK_NOW}
    ${ts}=    Get Timestamp 14
    ${tlvs}=    New TLV List
    Add Uint8 TLV     ${tlvs}    ${NWDAF_TAG_QOS_CONTROL_TYPE}    ${NWDAF_QCT_SUBSCRIBER}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_MDN}                 ${mdn}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_IMSI}                ${imsi}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_PGW_HOST_NAME}       ${pgw_host}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_TIMESTAMP}           ${ts}
    ${qos}=    Build QOS HDR    ${pcef}    qos_policy=${qos_policy}    quick=${quick}
    Append To List    ${tlvs}    ${qos}
    ${mid}=    Send NWDAF Notification    ${NWDAF_SID_SUBSCRIBER}    ${tlvs}
    RETURN    ${mid}


# ══════════════════════════════════════════════════════════════════
# 시나리오: 0x0306 기지국 단위 QoS Notification
# ══════════════════════════════════════════════════════════════════

Send Cell QoS Notification
    [Documentation]
    ...    Service Id=0x0306, Message Type=Notification
    ...    LOCATION_ID + CONTROL_UNIT + QOS_HDR + 통계 TLV 묶음
    [Arguments]
    ...    ${cell_id}=${NWDAF_TEST_CELL_ID}
    ...    ${control_unit}=${NWDAF_CU_CELL}
    ...    ${dn_usage}=${1000}
    ...    ${cell_avg_usage}=${500}
    ...    ${pcef}=${NWDAF_PCEF_ENB}
    ${ts}=    Get Timestamp 14
    ${tlvs}=    New TLV List
    Add Uint8 TLV     ${tlvs}    ${NWDAF_TAG_QOS_CONTROL_TYPE}    ${NWDAF_QCT_CELL}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_LOCATION_ID}         ${cell_id}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_CONTROL_UNIT}        ${control_unit}
    Add Uint32 TLV    ${tlvs}    ${NWDAF_TAG_DN_USAGE}            ${dn_usage}
    Add Uint32 TLV    ${tlvs}    ${NWDAF_TAG_CELL_AVG_USAGE}      ${cell_avg_usage}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_TIMESTAMP}           ${ts}
    ${qos}=    Build QOS HDR    ${pcef}
    Append To List    ${tlvs}    ${qos}
    ${mid}=    Send NWDAF Notification    ${NWDAF_SID_CELL}    ${tlvs}
    RETURN    ${mid}


# ══════════════════════════════════════════════════════════════════
# 시나리오: 0x0307 서비스 단위 QoS Notification (P-GW 제외)
# ══════════════════════════════════════════════════════════════════

Send Service QoS Notification
    [Documentation]
    ...    Service Id=0x0307, Message Type=Notification
    ...    APP_TYPE + QOS_HDR(P-GW 제외) 묶음
    [Arguments]
    ...    ${app_type}=${NWDAF_TEST_APP_TYPE}
    ...    ${pcef}=${NWDAF_PCEF_DPI}
    Run Keyword If    ${pcef} == ${NWDAF_PCEF_PGW}
    ...    Fail    0x0307(서비스 단위)는 PGW QoS 제외. pcef=${pcef} 사용 금지.
    ${ts}=    Get Timestamp 14
    ${tlvs}=    New TLV List
    Add Uint8 TLV     ${tlvs}    ${NWDAF_TAG_QOS_CONTROL_TYPE}    ${NWDAF_QCT_APP}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_APP_TYPE}            ${app_type}
    Add String TLV    ${tlvs}    ${NWDAF_TAG_TIMESTAMP}           ${ts}
    ${qos}=    Build QOS HDR    ${pcef}
    Append To List    ${tlvs}    ${qos}
    ${mid}=    Send NWDAF Notification    ${NWDAF_SID_SERVICE}    ${tlvs}
    RETURN    ${mid}


# ══════════════════════════════════════════════════════════════════
# 통계/사용량 TLV 묶음 추가 (in-place append)
# ══════════════════════════════════════════════════════════════════

Append Usage TLVs
    [Documentation]
    ...    NWDAF 통계 TLV 묶음을 기존 tlvs 리스트에 in-place 추가.
    ...    TAG 0x14~0x39 영역에서 자주 쓰이는 항목.
    [Arguments]
    ...    ${tlvs}
    ...    ${total_usage}=${1000000}
    ...    ${total_user}=${1000}
    ...    ${heavy_user}=${50}
    ...    ${medium_user}=${300}
    ...    ${light_user}=${650}
    ...    ${rct_3m}=${500}
    ...    ${rct_1m}=${150}
    Add Uint32 TLV    ${tlvs}    ${NWDAF_TAG_TOTAL_USAGE}    ${total_usage}
    Add Uint32 TLV    ${tlvs}    ${NWDAF_TAG_TOTAL_USER}     ${total_user}
    Add Uint32 TLV    ${tlvs}    ${NWDAF_TAG_HEAVY_USER}     ${heavy_user}
    Add Uint32 TLV    ${tlvs}    ${NWDAF_TAG_MEDIUM_USER}    ${medium_user}
    Add Uint32 TLV    ${tlvs}    ${NWDAF_TAG_LIGHT_USER}     ${light_user}
    Add Uint32 TLV    ${tlvs}    ${NWDAF_TAG_RCT_3M_USAGE}   ${rct_3m}
    Add Uint32 TLV    ${tlvs}    ${NWDAF_TAG_RCT_1M_USAGE}   ${rct_1m}


# ══════════════════════════════════════════════════════════════════
# 공용 헬퍼: 타임스탬프
# ══════════════════════════════════════════════════════════════════

Get Timestamp 14
    [Documentation]    yyyyMMddHHmmss 14자리 (NWDAF TIMESTAMP TAG 0x21)
    ${ts}=    Get Current Date    result_format=%Y%m%d%H%M%S
    RETURN    ${ts}


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
