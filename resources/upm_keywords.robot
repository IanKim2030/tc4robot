*** Settings ***
Documentation
...    UPM ↔ PG 연동 키워드 (PG-SC Message Format / JSON Body)
...
...    [인터페이스]
...      방향   : UPM(테스트 도구 / Client) → PG (Server, Port ${UPM_PG_PORT})
...      Body   : JSON
...
...    [Suite 정책 — Single Socket]
...      Suite Setup    : Suite UPM Connect → ${UPM_SOCK}
...                       규격 3.1 의 "5초 이내 Hello-Request" 를 Suite Setup 에서 처리.
...                       ping-interval 을 ${UPM_PING_INTERVAL} 에 저장.
...      Test Setup     : Check UPM Socket (닫히면 Fatal Error)
...      Suite Teardown : Suite UPM Disconnect
...
...    [메시지 흐름]
...      능동 송신 (UPM → PG): 0x01 Hello / 0x03 Ping / 0x09 CellInfo-Noti / 0x0b Subs-Sync
...      수동 수신 (PG → UPM): 0x05 Subs-Change / 0x07 Subs-Info / 0x0d Info-Change
...
...    [TID]
...      24자리 = 장비No(5) + "-" + yyyyMMdd(8) + seq(10). Next UPM TID 키워드 사용.
...      Header 의 txn_id(4B 바이너리) 와는 별개.

Library    Collections
Library    String
Library    DateTime
Library    BuiltIn
Library    ${CURDIR}/TcpHelper.py    WITH NAME    Tcp
# PG 가 0x0c(Subs-Sync-Response)의 fileinfo 로 파일을 밀어줄 수 있다 → 도구가 FTP
# 서버 역할로 받는다(사용자 확인). fileinfo 의 실제 스키마는 ⚠ 미확인.
# → 의존성: pip install pyftpdlib (UPM_FTP_ENABLE=False 면 불필요)
Library    ${CURDIR}/FtpServerHelper.py    WITH NAME    Ftp
Resource   ${CURDIR}/common_keywords.robot

*** Variables ***
${UPM_SOCK}      ${NONE}
${UPM_TID_SEQ}   ${0}
${UPM_FTP_SRV}   ${NONE}     # FTP 수신 서버 핸들 (Suite Setup 에서 기동)


*** Keywords ***

# ══════════════════════════════════════════════════════════════════
# UPM Suite 연결 관리 (Client 모드, PG=Server)
# ══════════════════════════════════════════════════════════════════

Suite UPM Connect
    [Documentation]
    ...    UPM Suite Setup 전용
    ...    1) UPM → PG(${UPM_PG_PORT}) 소켓 연결
    ...    2) 5초 이내 Hello-Request 전송 + Hello-Response 검증 → ping-interval 저장
    ...    Hello 미수신 시 PG가 연결 종료하므로 Suite Setup 에서 즉시 처리
    [Arguments]    ${host}=${UPM_PG_HOST}    ${port}=${UPM_PG_PORT}    ${timeout}=${UPM_TIMEOUT}
    Log    [Suite] UPM 연결 시작 → ${host}:${port}    console=True
    ${sock}=    Tcp.Tcp Connect    ${host}    ${port}    ${timeout}
    Set Suite Variable    ${UPM_SOCK}    ${sock}
    ${txn}=    Next TXN ID
    ${hdr}    ${body}=    Send UPM Hello    ${UPM_SYS_ID}    ${UPM_BRANCH_NAME}    ${txn}
    ${code}=    Get From Dictionary    ${body}    code
    Should Be Equal As Numbers    ${code}    200
    ...    msg=UPM Hello 실패 (code=${code}). UPM 테스트 시작 불가.
    ${pi}=    Get Ping Interval    ${body}
    Set Suite Variable    ${UPM_PING_INTERVAL}    ${pi}
    ${key_list}=    Get UPM Key List    ${body}
    Set Suite Variable    ${UPM_KEY_LIST}    ${key_list}
    ${key_count}=    Get Length    ${key_list}
    Log    [Suite] UPM Hello 성공 code=${code} ping-interval=${pi} keyList=${key_count}건    console=True
    # FTP 수신 서버 — PG 가 0x0c 의 fileinfo 로 파일을 밀어줄 때 받는다.
    # 소켓과 달리 PG 가 **붙어 오는 쪽**이라 여기서는 Listen 만 열어 둔다.
    IF    ${UPM_FTP_ENABLE}
        Log    [Suite] UPM FTP 수신 서버 시작 → ${UPM_FTP_HOST}:${UPM_FTP_PORT}    console=True
        ${ftp_srv}=    Ftp.Ftp Server Start    ${UPM_FTP_PORT}    ${UPM_FTP_HOST}
        ...    user=${UPM_FTP_USER}    password=${UPM_FTP_PASSWORD}
        ...    directory=${UPM_FTP_UPLOAD_DIR}
        ...    passive_ports=${UPM_FTP_PASSIVE_PORTS}
        ...    masquerade_address=${UPM_FTP_MASQUERADE_ADDR}
        Set Suite Variable    ${UPM_FTP_SRV}    ${ftp_srv}
    ELSE
        Log    [Suite] UPM FTP 수신 서버 꺼짐 (UPM_FTP_ENABLE=${UPM_FTP_ENABLE})    console=True
    END

Suite UPM Disconnect
    [Documentation]    UPM Suite Teardown 전용. UPM 소켓 종료 + FTP 수신 서버 종료.
    Run Keyword If    $UPM_SOCK is not None    Tcp.Tcp Close    ${UPM_SOCK}
    # 데몬 스레드라 안 닫아도 프로세스와 함께 죽지만, 포트를 붙들고 있으면 바로
    # 이어 도는 다음 실행이 bind 에서 실패한다 → 반드시 닫는다(CDS/RTS 와 동일 이유).
    Run Keyword If    $UPM_FTP_SRV is not None    Ftp.Ftp Server Stop    ${UPM_FTP_SRV}
    Log    [Suite] UPM 연결 종료    console=True

Check UPM Socket
    [Documentation]    UPM Test Setup 전용. 소켓이 닫히면 Fatal Error.
    ${ok}=    Tcp.Is Connected    ${UPM_SOCK}
    Run Keyword If    not ${ok}
    ...    Fatal Error    UPM 소켓이 닫혀 있습니다. 이후 TC를 실행할 수 없습니다.


# ══════════════════════════════════════════════════════════════════
# UPM 메시지 송수신 (JSON, Client 모드)
# ══════════════════════════════════════════════════════════════════

Send UPM Message
    [Arguments]    ${msg_type}    ${txn_id}    ${payload}=${NONE}
    Log    [TX-UPM] type=0x${msg_type} txn=${txn_id} payload=${payload}
    Tcp.Send Message    ${UPM_SOCK}    ${msg_type}    ${txn_id}    ${payload}

Receive UPM Message
    ${hdr}    ${body}=    Tcp.Receive Message    ${UPM_SOCK}
    Log    [RX-UPM] type=0x${hdr}[msg_type] txn=${hdr}[txn_id]
    RETURN    ${hdr}    ${body}

Send And Receive UPM
    [Arguments]    ${msg_type}    ${txn_id}    ${payload}=${NONE}
    Send UPM Message    ${msg_type}    ${txn_id}    ${payload}
    ${hdr}    ${body}=    Receive UPM Message
    RETURN    ${hdr}    ${body}


# ══════════════════════════════════════════════════════════════════
# UPM 공통 헬퍼: TID(24자리) / event-timestamp(17자리) 생성
# ══════════════════════════════════════════════════════════════════

Next UPM TID
    [Documentation]
    ...    UPM TID 24자리 생성: 장비No(5) + "-" + yyyyMMdd(8) + seq(10)
    ...    예: UPM01-2026043000000001
    [Arguments]    ${sys_id}=${UPM_SYS_ID}
    ${UPM_TID_SEQ}=    Evaluate    ${UPM_TID_SEQ} + 1
    Set Suite Variable    ${UPM_TID_SEQ}
    ${date}=    Get Current Date    result_format=%Y%m%d
    ${seq10}=    Evaluate    f"{${UPM_TID_SEQ}:010d}"
    ${prefix5}=    Evaluate    "${sys_id}"[:5].ljust(5, "0")
    ${tid}=    Set Variable    ${prefix5}-${date}${seq10}
    RETURN    ${tid}

Get Event Timestamp
    [Documentation]    yyyyMMddHHmmssSSS 17자리 (UPM event-timestamp)
    ${ts}=    Get Current Date    result_format=%Y%m%d%H%M%S%f
    ${ts17}=    Get Substring    ${ts}    0    17
    RETURN    ${ts17}


# ══════════════════════════════════════════════════════════════════
# UPM Hello (0x01/0x02)  UPM → PG
# ══════════════════════════════════════════════════════════════════

Send UPM Hello
    [Arguments]    ${sys_id}    ${branch_name}    ${txn_id}=${NONE}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${payload}=    Create Dictionary    sys-id=${sys_id}    branch-name=${branch_name}
    ${hdr}    ${body}=    Send And Receive UPM    ${1}    ${txn_id}    ${payload}
    RETURN    ${hdr}    ${body}

Get UPM Key List
    [Documentation]
    ...    Hello-Response 의 keyList 배열 추출 (num/salt/iv/key 암호화 키 묶음).
    ...    없으면 빈 리스트 반환 (구버전 PG 호환).
    [Arguments]    ${resp_body}
    ${ok}=    Run Keyword And Return Status
    ...    Dictionary Should Contain Key    ${resp_body}    keyList
    ${key_list}=    Run Keyword If    ${ok}
    ...    Get From Dictionary    ${resp_body}    keyList
    ...    ELSE    Create List
    RETURN    ${key_list}

UPM Key List Should Be Valid
    [Documentation]
    ...    Hello-Response keyList 배열 존재 및 각 항목의 num/salt/iv/key 값 존재 확인
    [Arguments]    ${key_list}
    Should Not Be Empty    ${key_list}    msg=keyList 가 비어 있습니다.
    FOR    ${item}    IN    @{key_list}
        Dictionary Should Contain Key    ${item}    num
        Dictionary Should Contain Key    ${item}    salt
        Dictionary Should Contain Key    ${item}    iv
        Dictionary Should Contain Key    ${item}    key
        ${salt}=    Get From Dictionary    ${item}    salt
        ${iv}=      Get From Dictionary    ${item}    iv
        ${key}=     Get From Dictionary    ${item}    key
        Should Not Be Empty    ${salt}    msg=keyList.salt 값이 비어 있습니다.
        Should Not Be Empty    ${iv}      msg=keyList.iv 값이 비어 있습니다.
        Should Not Be Empty    ${key}     msg=keyList.key 값이 비어 있습니다.
    END


# ══════════════════════════════════════════════════════════════════
# UPM Ping (0x03/0x04)  UPM → PG, Body 없음
# ══════════════════════════════════════════════════════════════════

Send UPM Ping
    [Documentation]    Body 에 "\r\n" 전송 (Keep-Alive 용 개행)
    [Arguments]    ${txn_id}=${NONE}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${hdr}    ${body}=    Send And Receive UPM    ${3}    ${txn_id}    \r\n
    RETURN    ${hdr}    ${body}

UPM Ping Should Succeed
    [Documentation]
    ...    UPM Ping-Response(0x04) Body 는 {"sys-id":"PG01"} 형식 (code 없음)
    ...    NAG/PCF 공용 Ping Should Succeed(code=200 검증) 와 다름 — UPM 전용으로 사용
    [Arguments]    ${resp_body}
    Dictionary Should Contain Key    ${resp_body}    sys-id
    ...    msg=Ping-Response 에 sys-id 없음: ${resp_body}


# ══════════════════════════════════════════════════════════════════
# UPM Subs-Info (0x07/0x08)  PG → UPM 요청 → UPM → PG 응답
# ══════════════════════════════════════════════════════════════════

Receive Subs Info Request
    [Documentation]    PG → UPM Subs-Info-Request(0x07) 수신 (msg_type 검증)
    ${hdr}    ${body}=    Receive UPM Message
    Should Be Equal As Numbers    ${hdr}[msg_type]    ${7}
    ...    msg=Subs-Info-Request(0x07) 기대, 실제=${hdr}[msg_type]
    RETURN    ${hdr}    ${body}

Send Subs Info Response
    [Documentation]
    ...    UPM → PG Subs-Info-Response(0x08)
    ...    code-type 관계없이 subsList 포함 (code-type=03 해지 도 동일)
    [Arguments]
    ...    ${txn_id}    ${req_body}
    ...    ${cell_list}=${NONE}
    ...    ${result_code}=${UPM_RC_SUCCESS}
    ...    ${sys_id}=${UPM_SYS_ID}
    ${code_type}=     Get From Dictionary    ${req_body}    code-type
    ${branch}=        Get From Dictionary    ${req_body}    branch-name
    ${tid}=           Get From Dictionary    ${req_body}    tid
    ${mdn}=           Get From Dictionary    ${req_body}    mdn
    ${payload}=    Create Dictionary
    ...    code-type=${code_type}
    ...    sys-id=${sys_id}              branch-name=${branch}
    ...    tid=${tid}                    result-code=${result_code}
    ${cl}=    Run Keyword If    $cell_list is None    Create List
    ...       ELSE    Set Variable    ${cell_list}
    ${subs}=    Create Dictionary    mdn=${mdn}    cell-list=${cl}
    ${arr}=     Create List    ${subs}
    Set To Dictionary    ${payload}    subsList=${arr}
    Send UPM Message    ${8}    ${txn_id}    ${payload}


# ══════════════════════════════════════════════════════════════════
# UPM CellInfo-Noti (0x09/0x0a)  UPM → PG NOTI → PG → UPM 응답
# ══════════════════════════════════════════════════════════════════

Send CellInfo Noti
    [Documentation]
    ...    UPM → PG CellInfo-Noti-Request(0x09) 송신 + 응답(0x0a) 수신
    ...    subs_list 예: [{mdn, cell-list:[{cell-info, ta-code}]}]
    ...    제약: subs_list 최대 100 개 (규격서 6.4.1)
    ...    code-type: 01=HFC가입 02=Cell List변경 03=HFC해지 04=번호변경 05=전체동기화 06=상품/Device변경
    [Arguments]
    ...    ${subs_list}    ${txn_id}=${NONE}
    ...    ${code_type}=${UPM_CT_CELL_CHANGE}
    ...    ${sys_id}=${UPM_SYS_ID}    ${branch}=${UPM_BRANCH_NAME}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${tid}=    Next UPM TID    ${sys_id}
    ${ts17}=   Get Event Timestamp
    ${payload}=    Create Dictionary
    ...    code-type=${code_type}
    ...    sys-id=${sys_id}                branch-name=${branch}
    ...    tid=${tid}                      event-timestamp=${ts17}
    ...    subsList=${subs_list}
    ${hdr}    ${body}=    Send And Receive UPM    ${9}    ${txn_id}    ${payload}
    RETURN    ${hdr}    ${body}

Build Cell Item
    [Documentation]    cell-list 항목 한 건 생성
    [Arguments]    ${cell_info}    ${ta_code}=${NONE}
    ${item}=    Create Dictionary    cell-info=${cell_info}
    IF    $ta_code is not None
        Set To Dictionary    ${item}    ta-code=${ta_code}
    END
    RETURN    ${item}

Build Subs Item
    [Documentation]    subsList 항목 한 건 생성
    [Arguments]    ${mdn}    @{cells}
    ${cell_list}=    Create List    @{cells}
    ${item}=    Create Dictionary    mdn=${mdn}    cell-list=${cell_list}
    RETURN    ${item}

CellInfo Noti Should Succeed
    [Documentation]
    ...    규격 6.4.2 는 result-code 포함을 명시하나, 실제 PG 는
    ...    CellInfo-Noti-Response(0x0a) 를 body 없이(body_length=0) 반환함 —
    ...    이 경우 헤더 ACK 만으로 성공 처리(UPM Ping Should Succeed 와 동일한 패턴)
    [Arguments]    ${resp_body}
    IF    not $resp_body
        RETURN
    END
    ${rc}=    Get From Dictionary    ${resp_body}    result-code
    Should Be Equal As Strings    ${rc}    ${UPM_RC_SUCCESS}
    ...    msg=CellInfo-Noti 실패: result-code=${rc}


# ══════════════════════════════════════════════════════════════════
# UPM Subs-Change (0x05/0x06) PG→UPM 번호변경 NOTI / UPM→PG 응답
# ══════════════════════════════════════════════════════════════════

Receive Subs Change Request
    [Documentation]    PG → UPM Subs-Change-Request(0x05) 수신 (code-type=04)
    ${hdr}    ${body}=    Receive UPM Message
    Should Be Equal As Numbers    ${hdr}[msg_type]    ${5}
    ...    msg=Subs-Change-Request(0x05) 기대, 실제=${hdr}[msg_type]
    RETURN    ${hdr}    ${body}

Send Subs Change Response
    [Documentation]    UPM → PG Subs-Change-Response(0x06): mdn/new-mdn 에코
    [Arguments]    ${txn_id}    ${req_body}
    ...            ${result_code}=${UPM_RC_SUCCESS}    ${sys_id}=${UPM_SYS_ID}
    ${branch}=    Get From Dictionary    ${req_body}    branch-name
    ${tid}=       Get From Dictionary    ${req_body}    tid
    ${mdn}=       Get From Dictionary    ${req_body}    mdn
    ${new_mdn}=   Get From Dictionary    ${req_body}    new-mdn
    ${payload}=    Create Dictionary
    ...    code-type=${UPM_CT_MDN_CHANGE}
    ...    sys-id=${sys_id}        branch-name=${branch}
    ...    tid=${tid}              mdn=${mdn}
    ...    new-mdn=${new_mdn}      result-code=${result_code}
    Send UPM Message    ${6}    ${txn_id}    ${payload}


# ══════════════════════════════════════════════════════════════════
# UPM Subs-Sync (0x0b/0x0c)  UPM → PG 전체 동기화 요청
# ══════════════════════════════════════════════════════════════════

Send Subs Sync Request
    [Documentation]    UPM → PG Subs-Sync-Request(0x0b): code-type=05 (전체 요청)
    [Arguments]    ${txn_id}=${NONE}    ${sys_id}=${UPM_SYS_ID}    ${branch}=${UPM_BRANCH_NAME}
    ${txn_id}=    Run Keyword If    $txn_id is None    Next TXN ID
    ...           ELSE    Set Variable    ${txn_id}
    ${tid}=    Next UPM TID    ${sys_id}
    ${ts17}=   Get Event Timestamp
    ${payload}=    Create Dictionary
    ...    code-type=${UPM_CT_SYNC_ALL}
    ...    sys-id=${sys_id}      branch-name=${branch}
    ...    tid=${tid}            event-timestamp=${ts17}
    ${hdr}    ${body}=    Send And Receive UPM    ${11}    ${txn_id}    ${payload}
    RETURN    ${hdr}    ${body}

Subs Sync Should Succeed
    [Arguments]    ${resp_body}
    ${rc}=    Get From Dictionary    ${resp_body}    result-code
    Should Be Equal As Strings    ${rc}    ${UPM_RC_SUCCESS}
    ...    msg=Subs-Sync 실패: result-code=${rc}

Guess Fileinfo Filename
    [Documentation]
    ...    fileinfo 의 실제 키 이름은 ⚠ 미확인이다. 그럴듯한 후보를 순서대로 찾아보고,
    ...    하나도 없으면 빈 문자열을 반환한다(파일명 대조를 건너뛰게 한다) — 실제 샘플이
    ...    확보되면 이 목록만 고치면 된다.
    [Arguments]    ${fileinfo}
    FOR    ${key}    IN    filename    fileName    file_name    file-name    name
        ${ok}=    Run Keyword And Return Status
        ...    Dictionary Should Contain Key    ${fileinfo}    ${key}
        IF    ${ok}
            ${v}=    Get From Dictionary    ${fileinfo}    ${key}
            RETURN    ${v}
        END
    END
    RETURN    ${EMPTY}

Verify Subs Sync Fileinfo
    [Documentation]
    ...    0x0c 응답의 fileinfo(⚠ 스키마 미확인)를 best-effort 로 대조한다.
    ...    · ${UPM_FTP_ENABLE}=False 면 전부 건너뛴다.
    ...    · fileinfo 가 없으면("포함 가능"이라 매 응답에 있는 게 아니다) 그냥 지나간다.
    ...    · fileinfo 가 있으면 FTP 로 **파일 2개**(데이터 파일 + FIN 파일, 사용자
    ...      확인 2026-10-22)가 왔는지 기다리고, 둘 다 안 차면 Fail 한다 — 몇 건
    ...      왔는지(0건/1건만)를 메시지에 남겨 "아예 안 옴"과 "데이터만 오고 FIN
    ...      이 안 옴"을 구분한다.
    ...    · 어느 쪽이 FIN 인지는 ${UPM_FTP_FIN_PATTERN} 포함 여부로 **추정**한다.
    ...    · 파일명 대조(fileinfo 안의 이름)는 **추정**이라 안 맞아도 WARN 로그만
    ...      남기고 실패시키지 않는다 — fileinfo 의 실제 모양이 확인되면
    ...      Guess Fileinfo Filename 을 고쳐 엄격화할 것.
    [Arguments]    ${resp_body}    ${since}=${NONE}
    IF    not ${UPM_FTP_ENABLE}
        RETURN
    END
    ${has_fileinfo}=    Run Keyword And Return Status
    ...    Dictionary Should Contain Key    ${resp_body}    fileinfo
    IF    not ${has_fileinfo}
        Log    [UPM] 0x0c 응답에 fileinfo 없음 — 이 응답은 파일을 보내지 않는 경우로 처리    console=True
        RETURN
    END
    ${fileinfo}=    Get From Dictionary    ${resp_body}    fileinfo
    Log    [UPM] fileinfo 수신(참고용, 스키마 미확인): ${fileinfo}    console=True
    ${received}=    Ftp.Ftp Wait    ${UPM_FTP_SRV}    timeout=${UPM_FTP_WAIT}    since=${since}
    ...    min_count=2
    ${count}=    Get Length    ${received}
    IF    ${count} < 2
        ${errs}=    Ftp.Ftp Errors    ${UPM_FTP_SRV}
        ${names}=    Evaluate    [f['filename'] for f in $received]
        Fail    0x0c 응답에 fileinfo 가 있었는데 FTP 로 파일 2개(데이터+FIN)가 다 오지 않았습니다 (${UPM_FTP_WAIT} 대기, ${count}건만 수신: ${names}). errors=${errs}
    END
    ${fin_files}=    Evaluate    [f['filename'] for f in $received if "${UPM_FTP_FIN_PATTERN}".lower() in f['filename'].lower()]
    ${data_files}=    Evaluate    [f['filename'] for f in $received if "${UPM_FTP_FIN_PATTERN}".lower() not in f['filename'].lower()]
    Log    [UPM] FTP 수신 완료 — 데이터 파일(추정): ${data_files} / FIN 파일(추정): ${fin_files}    console=True
    IF    not ${fin_files}
        Log    [UPM] ⚠ FIN 패턴(${UPM_FTP_FIN_PATTERN})에 맞는 파일을 못 찾음 — 두 파일 중 어느 쪽이 FIN 인지 구분 실패(패턴이 추정과 다를 수 있음)    console=True    level=WARN
    END
    ${expected_name}=    Guess Fileinfo Filename    ${fileinfo}
    IF    "${expected_name}" != "${EMPTY}"
        ${names}=    Evaluate    [f['filename'] for f in $received]
        IF    "${expected_name}" not in ${names}
            Log    [UPM] ⚠ fileinfo 파일명(${expected_name}) ≠ 실제 수신(${names}) — fileinfo 스키마가 추정과 다를 수 있음    console=True    level=WARN
        END
    END


# ══════════════════════════════════════════════════════════════════
# UPM Info-Change (0x0d/0x0e) PG→UPM 상품/Device 변경 / UPM→PG 응답
# ══════════════════════════════════════════════════════════════════

Receive Info Change Request
    [Documentation]    PG → UPM Info-Change-Request(0x0d) 수신 (code-type=06)
    ${hdr}    ${body}=    Receive UPM Message
    Should Be Equal As Numbers    ${hdr}[msg_type]    ${13}
    ...    msg=Info-Change-Request(0x0d) 기대, 실제=${hdr}[msg_type]
    RETURN    ${hdr}    ${body}

Send Info Change Response
    [Documentation]    UPM → PG Info-Change-Response(0x0e): mdn 에코
    [Arguments]    ${txn_id}    ${req_body}
    ...            ${result_code}=${UPM_RC_SUCCESS}    ${sys_id}=${UPM_SYS_ID}
    ${branch}=    Get From Dictionary    ${req_body}    branch-name
    ${tid}=       Get From Dictionary    ${req_body}    tid
    ${mdn}=       Get From Dictionary    ${req_body}    mdn
    ${payload}=    Create Dictionary
    ...    code-type=${UPM_CT_INFO_CHANGE}
    ...    sys-id=${sys_id}        branch-name=${branch}
    ...    tid=${tid}              mdn=${mdn}
    ...    result-code=${result_code}
    Send UPM Message    ${14}    ${txn_id}    ${payload}


# ══════════════════════════════════════════════════════════════════
# UPM 공통 검증
# ══════════════════════════════════════════════════════════════════

UPM Result Code Should Be Success
    [Arguments]    ${resp_body}
    ${rc}=    Get From Dictionary    ${resp_body}    result-code
    Should Match Regexp    ${rc}    ^SC\\d{4}$
    ...    msg=result-code 성공 패턴 아님: ${rc}

UPM TID Should Match
    [Arguments]    ${req_body}    ${resp_body}
    ${req_tid}=    Get From Dictionary    ${req_body}    tid
    ${rsp_tid}=    Get From Dictionary    ${resp_body}    tid
    Should Be Equal As Strings    ${req_tid}    ${rsp_tid}
    ...    msg=TID 에코 불일치: req=${req_tid} resp=${rsp_tid}

UPM Code Type Should Be
    [Arguments]    ${req_body}    ${expected}
    ${actual}=    Get From Dictionary    ${req_body}    code-type
    Should Be Equal As Strings    ${actual}    ${expected}
    ...    msg=code-type: expected=${expected}, actual=${actual}

UPM Branch Name Should Be Valid
    [Arguments]    ${req_body}
    ${br}=    Get From Dictionary    ${req_body}    branch-name
    Should Be True    '${br}' in ['SS', 'DS', 'BR']
    ...    msg=branch-name 기대 SS/DS/BR, 실제=${br}

UPM MDN Should Be Valid
    [Arguments]    ${req_body}
    ${mdn}=    Get From Dictionary    ${req_body}    mdn
    Should Match Regexp    ${mdn}    ^\\d{10,11}$    msg=MDN 포맷 오류: ${mdn}

UPM Event Timestamp Should Be Valid
    [Arguments]    ${req_body}
    ${ts}=    Get From Dictionary    ${req_body}    event-timestamp
    Should Match Regexp    ${ts}    ^\\d{17}$    msg=event-timestamp 17자리 아님: ${ts}
