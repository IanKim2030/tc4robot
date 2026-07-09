*** Settings ***
Documentation
...    UPM ↔ PG.BSUBS HFC 서비스 연동 규격 v1.1 (2025-12-02) 기능 검증
...
...    [테스트 대상]
...    테스트 도구(UPM 역할 / Client) → PG (Server, Port ${UPM_PG_PORT})
...
...    [Suite 소켓 정책]
...    Suite Setup    : UPM → PG 연결 + Hello-Request(0x01)/Response(0x02) 처리
...                     → ${UPM_SOCK} 공유, ping-interval 저장
...                     ※ 규격 3.1: 연결 후 5초 이내 Hello 미송신 시 PG가 종료
...    Test Setup     : Check UPM Socket (소켓 닫히면 Suite 즉시 중단)
...    Suite Teardown : UPM 연결 종료
...    각 TC          : ${UPM_SOCK} 공유 사용 (TC별 연결/해제 없음)
...
...    [메시지 흐름 요약]
...    능동 송신 (UPM→PG): Hello(0x01), Ping(0x03), CellInfo-Noti(0x09), Subs-Sync(0x0b)
...    수동 수신 (PG→UPM): Subs-Change(0x05), Subs-Info(0x07), Info-Change(0x0d)
...
...    수동 수신 TC 는 PG 측 실제 이벤트가 발생해야 동작하므로 운영 환경 미준비 시
...    참고용으로 주석 처리되어 있음. PG 이벤트 트리거가 가능해지면 주석 해제.

Resource    ../../resources/variables.robot
Resource    ../../resources/upm_variables.robot
Resource    ../../resources/common_keywords.robot
Resource    ../../resources/upm_keywords.robot

Suite Setup      Suite UPM Connect
Suite Teardown   Suite UPM Disconnect
Test Setup       Check UPM Socket
#Test Teardown    Sleep    1s

*** Test Cases ***

# ════════════════════════════════════════════════════════════════
# 0x01/0x02  Hello (UPM → PG.BSUBS)
# ════════════════════════════════════════════════════════════════
# Suite Setup 에서 이미 Hello 1회 처리. 본 TC 는 ping-interval 응답 형식만 재확인.

TC-UPM-001 Hello - ping-interval 응답 확인
    [Documentation]
    ...    규격 6.1
    ...    Hello-Response 의 ping-interval 이 양수인지 검증
    [Tags]    upm    hello    smoke
    Should Be True    ${UPM_PING_INTERVAL} > 0
    ...    msg=ping-interval 미수신 또는 0 (실제=${UPM_PING_INTERVAL})

TC-UPM-002 Hello - keyList 암호화 키 목록 확인
    [Documentation]
    ...    Hello-Response 에 추가된 keyList 배열 검증
    ...    항목별 num(정수) / salt / iv / key(Base64 문자열) 형식 확인
    [Tags]    upm    hello    smoke
    UPM Key List Should Be Valid    ${UPM_KEY_LIST}

# ════════════════════════════════════════════════════════════════
# 0x03/0x04  Ping (UPM → PG.BSUBS)
# ════════════════════════════════════════════════════════════════

TC-UPM-003 Ping - 정상 응답
    [Documentation]
    ...    규격 6.2
    ...    0x03 송신 → 0x04 수신, TXN ID 에코
    [Tags]    upm    ping    smoke
    ${txn}=    Next TXN ID
    ${hdr}    ${body}=    Send UPM Ping    ${txn}
    Response Msg Type Should Be    ${hdr}    ${4}
    TXN ID Should Match    ${txn}    ${hdr}
    UPM Ping Should Succeed    ${body}

# ════════════════════════════════════════════════════════════════
# 0x09/0x0a  CellInfo-Noti (UPM → PG.BSUBS)  변경 가입자 Cell Info NOTI
# ════════════════════════════════════════════════════════════════

TC-UPM-101 CellInfo-Noti - code-type=02 Cell List 변경
    [Documentation]    규격 6.4.1 code-type 목록: 02=Cell List 변경
    [Tags]    upm    cellinfo-noti
    ${cell}=    Build Cell Item    ${UPM_TEST_CELL_INFO}    ${UPM_TEST_TA_CODE}
    ${subs}=    Build Subs Item    ${UPM_TEST_MDN}    ${cell}
    ${arr}=     Create List    ${subs}
    ${txn}=    Next TXN ID
    ${hdr}    ${body}=    Send CellInfo Noti    ${arr}    ${txn}    ${UPM_CT_CELL_CHANGE}
    Response Msg Type Should Be    ${hdr}    ${10}
    TXN ID Should Match    ${txn}    ${hdr}
    CellInfo Noti Should Succeed    ${body}


# ════════════════════════════════════════════════════════════════
# 0x0b/0x0c  Subs-Sync (UPM → PG.SUBS)  전체 가입자 동기화 요청
# ════════════════════════════════════════════════════════════════

TC-UPM-201 Subs-Sync - 전체 동기화 요청 (code-type=05)
    [Documentation]
    ...    규격 6.6.1 / 6.6.2
    ...    UPM → PG 0x0b 송신 → 0x0c 수신, fileinfo 포함 가능, result-code=SC0000
    [Tags]    upm    subs-sync    smoke
    ${txn}=    Next TXN ID
    ${hdr}    ${body}=    Send Subs Sync Request    ${txn}
    Response Msg Type Should Be    ${hdr}    ${12}
    TXN ID Should Match    ${txn}    ${hdr}
    Subs Sync Should Succeed    ${body}
    UPM Code Type Should Be    ${body}    ${UPM_CT_SYNC_ALL}


# ════════════════════════════════════════════════════════════════
# 0x07/0x08  Subs-Info (PG.BSUBS → UPM)  HFC 가입자 Cell Info 요청
# ════════════════════════════════════════════════════════════════

 TC-UPM-301 Subs-Info - HFC 서비스 가입(code-type=01)
     [Documentation]
     ...    CDS.1X (HFC 서비스 가입)
     ...    PG.BSUBS → UPM Subs-Info-Request(0x07) 수신 
     ...    → UPM → PG.BSUBS Subs-Info-Response(0x08) result-code=SC0000 송신
     [Tags]    upm    subs-info    smoke
     ${hdr}    ${body}=    Receive Subs Info Request
     UPM MDN Should Be Valid              ${body}
     UPM Branch Name Should Be Valid      ${body}
     UPM Event Timestamp Should Be Valid  ${body}
     Dictionary Should Contain Key    ${body}    tid
     Dictionary Should Contain Key    ${body}    service-id
     ${cell}=    Build Cell Item    ${UPM_TEST_CELL_INFO}    ${UPM_TEST_TA_CODE}
     ${cells}=   Create List    ${cell}
     Send Subs Info Response    ${hdr}[txn_id]    ${body}    cell_list=${cells}    result_code=${UPM_RC_SUCCESS}


# ════════════════════════════════════════════════════════════════
# 0x0d/0x0e  Info-Change (PG.BSUBS → UPM)  상품/Device 변경 NOTI
# ════════════════════════════════════════════════════════════════

 TC-UPM-311 Info-Change - 상품/Device 변경(code-type=06) 수신 → 정상 응답
     [Documentation]
     ...    CDS.C1(기변) CDS.G1(정보변경)
     ...    PG.BSUBS → UPM 0x0d (mdn, device-type, product-type) 수신
     ...    → 0x0e result-code=SC0000 송신
     [Tags]    upm    info-change    smoke
     ${hdr}    ${body}=    Receive Info Change Request
     UPM Code Type Should Be    ${body}    ${UPM_CT_INFO_CHANGE}
     UPM MDN Should Be Valid    ${body}
     Send Info Change Response    ${hdr}[txn_id]    ${body}


# ════════════════════════════════════════════════════════════════
# 0x05/0x06  Subs-Change (PG.BSUBS → UPM)  가입자 번호 변경 NOTI
# ※ PG 측 실제 번호 변경 이벤트 발생 필요 → 주석 처리
# ════════════════════════════════════════════════════════════════

 TC-UPM-321 Subs-Change - 번호 변경(code-type=04)
     [Documentation]
     ...    CDS.D3 (번호변경)
     ...    0x05 PG.BSUBS → UPM 0x05 (mdn, new-mdn) 
     ...    → 0x06 result-code=SC0000 송신
     [Tags]    upm    subs-change    smoke
     ${hdr}    ${body}=    Receive Subs Change Request
     UPM Code Type Should Be    ${body}    ${UPM_CT_MDN_CHANGE}
     UPM MDN Should Be Valid    ${body}
     Dictionary Should Contain Key    ${body}    new-mdn
     Send Subs Change Response    ${hdr}[txn_id]    ${body}



# ════════════════════════════════════════════════════════════════
# 0x0d/0x0e  Subs-Info (PG.BSUBS → UPM)  HFC 서비스 해지
# ════════════════════════════════════════════════════════════════
# TC-UPM-399 Subs-Info - HFC 서비스 해지(code-type=03)  ->
#     [Documentation]
#     ...    CDS.1Y (HFC 서비스 해지)
#     ...    UPM 요청/응답 없음. PG.BSUBS에서만 MSG_SUBS_DELETE_REQUEST 처리함.
#     [Tags]    upm    subs-info    validation
#     ${hdr}    ${body}=    Receive Subs Info Request
#     UPM Code Type Should Be    ${body}    ${UPM_CT_TERMINATE}
#     UPM MDN Should Be Valid    ${body}
#     ${cell}=    Build Cell Item    ${UPM_TEST_CELL_INFO}    ${UPM_TEST_TA_CODE}
#     ${cells}=   Create List    ${cell}
#     Send Subs Info Response    ${hdr}[txn_id]    ${body}    cell_list=${cells}
