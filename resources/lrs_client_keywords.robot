*** Settings ***
Documentation
...    LRS 클라이언트 모드 키워드 (도구 → PG.LRS 접속)
...
...    [인터페이스]
...      방향   : 테스트 도구(LRS 역할 / Client) → PG.LRS (Server, Port 기본 10204)
...      포트   : ${PG_LRS_PG_V2_LISTEN_PORT}(config) → 없으면 ${LRS_CLIENT_DEFAULT_PORT}
...
...    [두 프로토콜 — 같은 포트 공유]
...      1) Health Check (raw TCP)        : "REQ" 송신 → "ANS" 수신 (주기 기본 30초)
...      2) SESSION-INFO-RETRIEVAL (HTTP) : POST /SESSION-INFO-RETRIEVAL → AIMS_RES
...
...    [Suite 정책 — Single Socket]
...      Suite Setup    : Suite Connect LRS Client (Health Check 용 지속 연결)
...      Test Setup     : Check LRS Client Socket (닫히면 Fatal Error)
...      Suite Teardown : Suite Disconnect LRS Client
...      ※ SESSION-INFO(HTTP) 는 요청마다 독립 연결을 사용한다(HttpHelper).

Library    Collections
Library    String
Library    BuiltIn
Library    ${CURDIR}/TcpHelper.py     WITH NAME    Tcp
Library    ${CURDIR}/HttpHelper.py    WITH NAME    Http
Resource   ${CURDIR}/common_keywords.robot

*** Variables ***
${LRS_CLIENT_SOCK}    ${NONE}
${LRS_CLIENT_PORT}    ${NONE}
${LRS_HC_INTERVAL}    ${NONE}


*** Keywords ***

# ══════════════════════════════════════════════════════════════════
# LRS 클라이언트 Suite 연결 관리 (단일 소켓)
# ══════════════════════════════════════════════════════════════════

Resolve LRS Client Port
    [Documentation]
    ...    접속 포트 결정: config(${PG_LRS_PG_V2_LISTEN_PORT}) 가 주입돼 있으면 그 값,
    ...    아니면 기본값 ${LRS_CLIENT_DEFAULT_PORT}(10204).
    ${port}=    Get Variable Value    ${PG_LRS_PG_V2_LISTEN_PORT}    ${LRS_CLIENT_DEFAULT_PORT}
    RETURN    ${port}

Resolve LRS HC Interval
    [Documentation]
    ...    Health Check 주기 결정: config(${PG_LRS_PG_V2_TIMEOUT}) 가 있으면 그 값,
    ...    아니면 기본값 ${LRS_HC_DEFAULT_INTERVAL}(30초).
    ${interval}=    Get Variable Value    ${PG_LRS_PG_V2_TIMEOUT}    ${LRS_HC_DEFAULT_INTERVAL}
    RETURN    ${interval}

Suite Connect LRS Client
    [Documentation]
    ...    LRS 클라이언트 Suite Setup 전용.
    ...    PG.LRS 로 TCP 연결(Health Check 용 지속 소켓) → ${LRS_CLIENT_SOCK} 공유.
    ...    포트/주기는 config 우선, 없으면 기본값.
    [Arguments]    ${host}=${LRS_CLIENT_HOST}    ${timeout}=${LRS_CLIENT_TIMEOUT}
    ${port}=        Resolve LRS Client Port
    ${interval}=    Resolve LRS HC Interval
    Set Suite Variable    ${LRS_CLIENT_PORT}    ${port}
    Set Suite Variable    ${LRS_HC_INTERVAL}    ${interval}
    Log    [Suite] LRS 클라이언트 연결 시작 → ${host}:${port} (HC 주기 ${interval}s)    console=True
    ${sock}=    Tcp.Tcp Connect    ${host}    ${port}    ${timeout}
    Set Suite Variable    ${LRS_CLIENT_SOCK}    ${sock}

Suite Disconnect LRS Client
    [Documentation]    LRS 클라이언트 Suite Teardown 전용. 소켓 종료.
    Run Keyword If    $LRS_CLIENT_SOCK is not None    Tcp.Tcp Close    ${LRS_CLIENT_SOCK}
    Log    [Suite] LRS 클라이언트 연결 종료    console=True

Check LRS Client Socket
    [Documentation]    LRS 클라이언트 Test Setup 전용. 소켓이 닫히면 Fatal Error.
    ${ok}=    Tcp.Is Connected    ${LRS_CLIENT_SOCK}
    Run Keyword If    not ${ok}
    ...    Fatal Error    LRS 클라이언트 소켓이 닫혀 있습니다. 이후 TC를 실행할 수 없습니다.


# ══════════════════════════════════════════════════════════════════
# Health Check (raw TCP "REQ" → "ANS")
# ══════════════════════════════════════════════════════════════════

Send LRS Health Check
    [Documentation]    "REQ" 송신 → 3바이트 수신("ANS" 기대) 반환
    Tcp.Send Text    ${LRS_CLIENT_SOCK}    ${LRS_HC_REQ}
    Log    [TX→PG.LRS] Health Check ${LRS_HC_REQ}
    ${ans}=    Tcp.Recv Text    ${LRS_CLIENT_SOCK}    3
    Log    [RX←PG.LRS] Health Check ${ans}
    RETURN    ${ans}

Health Check Should Succeed
    [Documentation]    수신값이 "ANS" 인지 검증
    [Arguments]    ${ans}
    Should Be Equal As Strings    ${ans}    ${LRS_HC_ANS}
    ...    msg=Health Check 응답 기대="${LRS_HC_ANS}", 실제="${ans}"


# ══════════════════════════════════════════════════════════════════
# Ping (주기적 keepalive — 지속 소켓에서 REQ/ANS 반복)
# ══════════════════════════════════════════════════════════════════

Send LRS Ping
    [Documentation]    Ping 1회 = Health Check REQ→ANS 1회 (지속 소켓 keepalive). ANS 반환.
    ${ans}=    Send LRS Health Check
    RETURN    ${ans}

Ping Keepalive Should Succeed
    [Documentation]
    ...    ${count}회 연속 Ping(REQ→ANS)을 ${gap}초 간격으로 송수신.
    ...    매 회 소켓이 살아 있는지 확인하고 응답이 "ANS" 인지 검증한다.
    [Arguments]    ${count}=${LRS_PING_COUNT}    ${gap}=${LRS_PING_GAP}
    FOR    ${i}    IN RANGE    1    ${count} + 1
        Check LRS Client Socket
        ${ans}=    Send LRS Ping
        Health Check Should Succeed    ${ans}
        Log    [Ping ${i}/${count}] ANS 정상, 소켓 유지    console=True
        Run Keyword If    ${i} < ${count}    Sleep    ${gap}
    END


# ══════════════════════════════════════════════════════════════════
# SESSION-INFO-RETRIEVAL (HTTP/1.1, 요청마다 독립 연결)
# ══════════════════════════════════════════════════════════════════

Send Session Info Retrieval
    [Documentation]
    ...    AIMS_REQ 구성 → HTTP POST 송신 → 응답 dict 반환
    ...    반환 dict: status / reason / headers / body / fields
    [Arguments]
    ...    ${req_id}=${LRS_SI_REQ_ID}
    ...    ${pgw_group_id}=${LRS_SI_PGW_GROUP_ID}
    ...    ${client_ip}=${LRS_SI_CLIENT_IP}
    ...    ${min}=${LRS_SI_MIN}    ${mdn}=${LRS_SI_MDN}    ${imsi}=${LRS_SI_IMSI}
    ...    ${from_ip}=${LRS_SI_FROM_IP}
    ${port}=    Set Variable If    $LRS_CLIENT_PORT is not None    ${LRS_CLIENT_PORT}    ${LRS_CLIENT_DEFAULT_PORT}
    ${xml}=    Http.Build Aims Req    ${req_id}    ${pgw_group_id}    ${client_ip}
    ...        min_=${min}    mdn=${mdn}    imsi=${imsi}
    ${res}=    Http.Post Session Info
    ...    ${LRS_CLIENT_HOST}    ${port}    ${LRS_SI_PATH}    ${from_ip}    ${xml}
    ...    timeout=${LRS_CLIENT_TIMEOUT}
    Log    [HTTP] SESSION-INFO status=${res}[status] ${res}[reason]
    RETURN    ${res}

Send Session Info Request
    [Documentation]
    ...    Session-Info(HTTP POST) 를 raw 소켓으로 "송신만" 한다(비블로킹).
    ...    PG 가 요청 처리 중 LRS-PCF 채널로 보내는 Location-Info-Request(0x05)를
    ...    그 사이에 처리하기 위함 — TC-NAG-007 의 송신/수신 분리 방식과 동일.
    ...    HttpHelper 는 수정하지 않고 Build Aims Req(기존 함수)만 재사용한다.
    ...    반환된 소켓은 Receive Session Info Response 로 응답을 회수/종료한다.
    [Arguments]
    ...    ${req_id}=${LRS_SI_REQ_ID}
    ...    ${pgw_group_id}=${LRS_SI_PGW_GROUP_ID}
    ...    ${client_ip}=${LRS_SI_CLIENT_IP}
    ...    ${min}=${LRS_SI_MIN}    ${mdn}=${LRS_SI_MDN}    ${imsi}=${LRS_SI_IMSI}
    ...    ${from_ip}=${LRS_SI_FROM_IP}
    ${port}=    Set Variable If    $LRS_CLIENT_PORT is not None    ${LRS_CLIENT_PORT}    ${LRS_CLIENT_DEFAULT_PORT}
    ${xml}=    Http.Build Aims Req    ${req_id}    ${pgw_group_id}    ${client_ip}
    ...        min_=${min}    mdn=${mdn}    imsi=${imsi}
    ${clen}=    Evaluate    len($xml.encode('utf-8'))
    # CRLF 를 식에 리터럴로 넣으면 Robot 이 실제 개행으로 바꿔 문자열이 깨지므로 chr() 로 만든다.
    ${crlf}=    Evaluate    chr(13)+chr(10)
    ${req}=    Catenate    SEPARATOR=${crlf}
    ...    POST ${LRS_SI_PATH} HTTP/1.1
    ...    Host: ${LRS_CLIENT_HOST}:${port}
    ...    From: ${from_ip}
    ...    Accept: text/xml
    ...    Content-Type: text/xml
    ...    Content-Length: ${clen}
    ...    Connection: close
    ...    ${EMPTY}
    ...    ${xml}
    ${sock}=    Tcp.Tcp Connect    ${LRS_CLIENT_HOST}    ${port}    ${LRS_CLIENT_TIMEOUT}
    Tcp.Send Text    ${sock}    ${req}
    Log    [HTTP TX] SESSION-INFO 요청 송신 → ${LRS_CLIENT_HOST}:${port} (LRS-PCF 응답 대기)
    RETURN    ${sock}

Receive Session Info Response
    [Documentation]
    ...    Send Session Info Request 가 반환한 소켓에서 HTTP 응답 전체를 수신·파싱한다.
    ...    반환 dict: status(int) / body(str) / fields(dict, AIMS_RES 파싱)
    ...    파싱은 Http.Parse Xml Fields(기존 함수) 재사용. 수신 후 소켓을 닫는다.
    [Arguments]    ${sock}    ${timeout}=${LRS_CLIENT_TIMEOUT}
    ${raw}=    Tcp.Recv Until Close    ${sock}    ${timeout}
    Tcp.Tcp Close    ${sock}
    ${crlf}=    Evaluate    chr(13)+chr(10)
    ${sep}=    Evaluate    $crlf+$crlf
    ${first}=    Evaluate    $raw.split($crlf, 1)[0]
    ${status}=    Evaluate    int($first.split()[1]) if len($first.split()) > 1 else 0
    ${parts}=    Evaluate    $raw.split($sep, 1)
    ${body}=    Evaluate    $parts[1] if len($parts) > 1 else ''
    ${fields}=    Http.Parse Xml Fields    ${body}
    ${res}=    Create Dictionary    status=${status}    body=${body}    fields=${fields}
    Log    [HTTP RX] SESSION-INFO status=${status}
    RETURN    ${res}

Session Info Status Should Be
    [Arguments]    ${res}    ${expected}
    Should Be Equal As Integers    ${res}[status]    ${expected}
    ...    msg=HTTP status 기대=${expected}, 실제=${res}[status]

Session Info Should Succeed
    [Documentation]
    ...    200 OK + AIMS_RES 핵심 필드 검증
    ...    (REQ_ID 에코 일치, CLIENT_ID-MDN / NETWORK_TOPOLOGY / LOCATION / TAC 존재)
    [Arguments]    ${res}    ${req_id}=${LRS_SI_REQ_ID}
    Session Info Status Should Be    ${res}    ${LRS_SI_CODE_OK}
    ${fields}=    Set Variable    ${res}[fields]
    Dictionary Should Contain Key    ${fields}    REQ_ID
    Should Be Equal As Strings    ${fields}[REQ_ID]    ${req_id}
    ...    msg=REQ_ID 에코 불일치: 요청=${req_id}, 응답=${fields}[REQ_ID]
    Dictionary Should Contain Key    ${fields}    CLIENT_ID-MDN
    Dictionary Should Contain Key    ${fields}    NETWORK_TOPOLOGY
    Dictionary Should Contain Key    ${fields}    LOCATION
    Dictionary Should Contain Key    ${fields}    TAC
