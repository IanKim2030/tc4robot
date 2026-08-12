*** Settings ***
Documentation
...    CDS 인터페이스 기능 검증 (TCP 고정길이 48B, 클라이언트 듀얼 소켓)
...
...    [테스트 대상]
...    테스트 도구(CDS / 능동 Connector) → PG.CDS 접속
...    Schannel(${CDS_SCH_PORT}) / Rchannel(${CDS_RCH_PORT}) 2개 outbound 소켓
...
...    [Suite 소켓 정책]
...    Suite Setup    : Suite CDS Connect — 연결 → ConnectionRequest(0001/0003) + ACK 검증
...                     → 두 소켓 생존 확인 → PDB 접속 → UPM 접속
...                     → PCF Noti 수신 서버 Listen (접속은 TC 가 아니다)
...    Test Setup     : Check CDS Sockets (하나라도 닫히면 Suite 중단)
...    Suite Teardown : Suite CDS Disconnect — Release(0005/0007) + ACK(0006/0008) 검증 후 종료
...                     (해제도 TC 가 아니다. 슈트가 끝나면 반드시 수행돼야 한다)
...    각 TC          : ${CDS_SCH_SOCK}/${CDS_RCH_SOCK} 공유 사용 (TC별 연결/해제 없음)
...
...    포트/SYSTEM_ID 는 cds_variables.robot 기본값(9200/9201, PG01).
...    환경별로 다르면 config/env/<env>.py 에서 오버라이드한다.
...
...    [TC 번호 체계]
...      TC-CDS-001       : ProcessState 상태확인 (0013/0014)
...      TC-CDS-002 ~ 008 : Download Command (0015~0018) — 즉시 반영 업무 코드
...      TC-CDS-009 ~ 017 : Download Command — 쿠폰/옵션 계열 Y9 / K1~K6 / SS / ST
...      TC-CDS-018 ~ 019 : Download Command — 번호변경(D3) → 해지(Z1) 체인의 끝
...
...    [PDB 조회] `db` 태그가 붙은 TC 는 전문 흐름(SC)에 더해 PDB 반영까지 판정한다.
...    판정 대상은 대부분 가입자 테이블(T_5G_SUBS_*)이고, 가입 계열 3개(009/013/015)만
...    예약 큐(T_5G_RESERVED_JOB) 적재를 **한 건 더** 본다.
...      002 A1 신규가입 : PROFILE 1건 + SERVICE 2건(DATA_USAGE_LEVEL / _2) — 모두 1
...      003 1X HFC가입  : SERVICE(SVC_ID=ZONE_SVC_D, SVC_TYPE=D, JOB_CODE=1X) 1건 이상
...                        + **UPM Subs-Info(0x07) 수신 → 0x08 응답** (구 TC-UPM-301)
...                        + **PCF SBI Noti 2건 수신** (가입자 Noti / Cell List)
...      004 1Y HFC해지  : SERVICE(SVC_ID=ZONE_SVC_D) 0건
...      005 I2 부가신청 : SERVICE(YOUNG_HARM_INFO_BLOCK, N, I2, 56, LIMIT=Y) 1건 이상
...      006 I3 부가해지 : SERVICE(SVC_ID=YOUNG_HARM_INFO_BLOCK) 0건
...      007 C1 기기변경 : 수행 전 SVC_ID 별 행 수 == 수행 후 JOB_CODE=C1 집계
...      008 G1 정보변경 : 위와 같음 (JOB_CODE=G1)
...      009 K1 쿠폰가입  : SERVICE(R17, N, K1, 113, LIMIT=1, LIMIT_VALID_TIME, CNUM=핀) 1건 이상
...                        + RESERVED_JOB(JOB_CODE=K3, 핀) 1건 이상
...      010 K2 쿠폰해지  : 009 의 핀으로 SERVICE(R17, CNUM) 0건
...      011 K4 쿠폰취소  : TC 안에서 K1 로 가입시킨 뒤 취소 → 그 핀으로 0건
...      012 K3 쿠폰만료  : 011 과 같은 구조 (핀이 다르고, K1 의 START_TIME 이 현재 시각)
...      013 K5 쿠폰가입  : SERVICE(R17, N, K5, 0, LIMIT=2, LIMIT_VALID_TIME, CNUM=핀) 1건 이상
...                        + RESERVED_JOB(JOB_CODE=K7, 핀) 1건 이상
...      014 K6 쿠폰해지  : 013 의 핀으로 SERVICE(R17, CNUM) 0건
...      015 Y9 Zone쿠폰  : SERVICE(ZONE_SVC_B, Z, Y9, 25, LIMIT=0, LIMIT_VALID_TIME) 1건 이상
...                        + RESERVED_JOB(JOB_CODE=Y6, 핀) 1건 이상
...      016 SS 옵션가입  : SERVICE(TIME_SVC_I, T, SS, TIME_PERIOD_ID=SS_+START_TIME(12), LIMIT=0, CNUM=0) 1건 이상
...      017 ST 옵션해지  : SERVICE(SVC_ID=TIME_SVC_I) 0건
...      018 D3 번호변경 : 007 과 같은 전후 비교 (옛 번호 기준 → 새 번호 + JOB_CODE=D3)
...      019 Z1 가입해지 : PROFILE / SERVICE(SVC_ID 무관) 모두 0건
...      "1건 이상"은 건수를 못 박지 않는다는 뜻이다 — 존·부가 서비스가 여러 건일 수 있다.
...      전후 비교형(007/008/018)은 `Command Download Flow` **앞**에서 기준선을 먼저 뜬다.
...      ★ 예약 큐에 적재되는 JOB_CODE 는 인입 코드와 다르다 — K1→K3, K5→K7, Y9→Y6.
...        인입 코드로 조회하면 한 건도 나오지 않는다.
...      ★ K2/K3/K4/K6 은 판정 기준이 **글자 그대로 같다**(MDN+R17+CNUM 삭제) — 해지·만료·
...        취소가 서로 구분되지 않는다. 그래서 011/012 는 자기 핀으로 가입을 먼저 만든다.
...      ★ 시간 컬럼은 전부 전문의 START_TIME 에서 나온다 — PDB 의 필드 정의 테이블
...        T_5G_CDS_ORDER_CFG 에서 START_TIME 의 별칭(SUBTITLE)이 LIMIT_VALID_TIME 이다.
...        다만 **컬럼마다 폭이 다르다.** 기준표가 둘 다 $LIMIT_VALID_TIME 으로 적어
...        놔서 같은 값으로 읽기 쉬운데 아니다 — SS 만 초 '00' 이 붙지 않는다.
...          009/013/015 : LIMIT_VALID_TIME = START_TIME+'00'   14자리  (${CDS_LIMIT_VALID_TIME})
...          016         : TIME_PERIOD_ID   = 'SS_' + START_TIME 접두+12 (${CDS_DB_TPID_SS})
...        형식이 또 어긋나면 저 두 변수만 고치면 된다 — SQL·키워드는 그대로다.
...      ★ START_TIME 은 **012 만 현재 시각**이고 나머지는 먼 미래(${CDS_START_TIME})다.
...        012 는 만료 업무라 유효기간이 찬 쿠폰이 필요하기 때문이다 — 그 TC 주석 참조.
...      접속 정보는 cds_variables.robot 의
...      ${CDS_DB_CONNSTR}(완성된 ODBC 문자열) 하나다 — 환경변수 PG_CDS_DB_CONNSTR 가 우선.
...      DB 접속은 **Suite Setup 에서 소켓과 함께 1회** 붙고 Suite Teardown 에서 끊는다
...      (TC별 접속 없음). autocommit 은 꺼져 있다(${CDS_DB_AUTOCOMMIT}=${FALSE}).
...      ★ 접속 정보가 틀리면 이 TC 뿐 아니라 **슈트 전체가 서지 않는다** — Suite Setup
...        이 실패하기 때문이다. --exclude db 로도 피할 수 없다.
...
...    [UPM 연동] TC-CDS-003(1X)만 해당한다.
...      1X 는 CDS 에서 끝나지 않는다 — PG.BSUBS 가 UPM 으로 Subs-Info(0x07)를 밀고
...      UPM 이 0x08 로 답해야 완결된다. UPM 슈트의 TC-UPM-301 이 그 구간인데 1X 를
...      보낼 방법이 없어 주석 처리돼 있었고, 트리거를 쥔 이 슈트로 옮겨 왔다.
...      그래서 **CDS 슈트가 UPM 포트(${UPM_PG_PORT})에도 의존한다** — PDB 와 마찬가지로
...      Suite Setup 에서 붙으므로 UPM 이 안 뜨면 슈트 전체가 서지 않는다.
...      CDS 전문만 돌리려면: --variable CDS_UPM_VERIFY:False (UPM 접속 자체를 건너뛴다)
...
...    [PCF Noti 수신] TC-CDS-003(1X)만 해당한다. `noti` 태그.
...      SA(5G) 가입자는 PG 가 PCF 로 **SBI Noti** 를 보낸다. 도구가 PCF 역할로
...      ${CDS_NOTI_PORT} 를 Listen 해 두 건을 받는다 — SNOTI→PCF 가입자 Noti,
...      BSUBS→PCF Cell List(UPM 0x08 응답 뒤). 전문(SC)·PDB 로는 안 보이는 구간이다.
...      · 프로토콜은 **HTTP/2 평문(h2c)** 이다 → `pip install h2` 필요.
...        표준 http.server 로는 못 받는다(HttpNotiServer.py 가 처리).
...      · **PG 가 이 주소로 보내도록 설정돼 있어야 한다.** 포트가 다르면 변수에서 맞출 것.
...      · **LTE 가입자면 아무것도 안 온다** — SBI 가 아니라 RBUS 다.
...      · 실 PG 의 :path 가 확인되지 않아 ${CDS_NOTI_PATH_*} 는 비어 있다(경로 무시).
...        채우면 그때부터 종류별로 구분해 판정한다.
...      끄려면: --variable CDS_NOTI_VERIFY:False (Listen 자체를 하지 않는다)
...
...    [TC 간 의존성] 슈트 전체가 002(A1 신규가입)로 만든 가입자 하나를 이어 쓴다.
...      002 A1 신규가입  : 이후 모든 TC 의 대상 가입자를 만든다
...      009 K1 → 010 K2  : 같은 핀(${CDS_COUPON_PIN_K1})의 쿠폰 가입 → 해지 쌍
...      013 K5 → 014 K6  : 같은 핀(${CDS_COUPON_PIN_K5})의 쿠폰 가입 → 해지 쌍
...      016 SS → 017 ST  : 옵션 가입 → 해지 쌍 (핀 없음, SVC_ID 로만 식별)
...      018 D3 번호변경  : 성공하면 ${CDS_ACTIVE_MDN} 을 ${CDS_NEW_MDN} 으로 갱신
...      019 Z1 해지      : 가입자 자체를 해지 (체인의 끝). PDB 에서 사라졌는지까지 본다
...    쿠폰 쌍은 핀이 서로 다르다 — 삭제 판정이 `MDN + R17 + CNUM` 으로만 걸려 핀을
...    합치면 한 TC 가 지운 행을 다른 TC 가 자기 결과로 착각한다.
...    해지 TC(010/014/017)를 단독 실행하면 짝이 되는 가입이 없어 "0건"으로 그냥 통과한다.
...    011/012(K4 취소 / K3 만료)는 그 함정을 피하려고 **TC 안에서 K1 가입을 먼저** 돌린다.
...
...    D3 를 건너뛰거나 실패하면 ${CDS_ACTIVE_MDN} 이 기본값(${CDS_MDN})으로 남아
...    019 가 원래 번호를 대상으로 동작한다 — 단독 실행도 그대로 된다.
...    특정 번호를 지정하려면: --variable CDS_ACTIVE_MDN:01090010002

Resource    ../../resources/variables.robot
Resource    ../../resources/cds_variables.robot
Resource    ../../resources/common_keywords.robot
Resource    ../../resources/cds_keywords.robot


Suite Setup      Suite CDS Connect
Suite Teardown   Suite CDS Disconnect
Test Setup       Check CDS Sockets

*** Test Cases ***

# 접속(0001~0004)과 소켓 생존 확인은 Suite Setup(`Suite CDS Connect`)에서 수행한다.
# Setup 이 실패하면 슈트가 서지 않으므로 별도 TC 로 재확인할 필요가 없다.

# ════════════════════════════════════════════════════════════════
# 프로세스 상태 확인 (0013/0014)
# ════════════════════════════════════════════════════════════════

TC-CDS-001 상태확인 - ProcessStateReuqest(0013) S/R채널 각각 → ACK(0014)
    [Documentation]
    ...    요구/ACK 는 각 채널 내에서 완결 (규격 2.4)
    ...    Schannel: 요구(0013) → ACK(0014) / Rchannel: 요구(0013) → ACK(0014)
    ...    각 ACK 의 Process State=Normal(1) 확인
    [Tags]    cds    process-state    smoke
    # Schannel 내 요구 → ACK
    Send Process State Request    ${CDS_SCH_SOCK}
    ${state_s}=    Receive And Validate Process State Ack    ${CDS_SCH_SOCK}
    Process State Should Be Normal    ${state_s}
    # Rchannel 내 요구 → ACK
    Send Process State Request    ${CDS_RCH_SOCK}
    ${state_r}=    Receive And Validate Process State Ack    ${CDS_RCH_SOCK}
    Process State Should Be Normal    ${state_r}


# ════════════════════════════════════════════════════════════════
# DownLoad Command (0015~0018)
# ════════════════════════════════════════════════════════════════

TC-CDS-002 A1 (신규가입)
    [Documentation]
    ...    0015(A1 신규) 송신 → 0016 ACK(SC) → 0017 Result 수신 → 0018 ResultACK 송신
    ...    규격 A1 이 요구하는 17개 필드는 cds_variables.robot 기본값으로 전달된다
    ...    (Body 는 코드와 무관하게 항상 327B).
    ...    ※ 단말·망 필드(${CDS_NETWORK} 등)가 비어 있으면 공백으로 나가고 PG 는 그래도
    ...       SC 를 준다. 실환경 값을 채워야 실제 검증이 된다.
    ...
    ...    [성공 판단 기준] 전문 흐름(SC)만으로는 판정하지 않는다. PDB 조회 3건이
    ...    **모두 1** 이어야 성공이다 — PG.SDM 이 가입자 테이블에 실제로 반영했는지를 본다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_PROFILE WHERE MDN='${CDS_MDN}'
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE WHERE MDN='${CDS_MDN}' AND SVC_ID='DATA_USAGE_LEVEL'
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE WHERE MDN='${CDS_MDN}' AND SVC_ID='DATA_USAGE_LEVEL_2'
    ...    반영이 비동기라 ${CDS_DB_WAIT} 동안 재조회한다.
    ...    ※ PDB 접속 문자열(${CDS_DB_CONNSTR})이 비어 있으면 이 TC 뿐 아니라 슈트 전체가
    ...       서지 않는다(Suite Setup 에서 접속한다). config/env/<env>.py 에 채울 것.
    [Tags]    cds    command    validation    db
    Command Download Flow    ${CDS_CODE_A1}
    Verify Subscriber Provisioned In PDB    ${CDS_MDN}

TC-CDS-003 1X (HFC가입) - CDS 전문 + UPM Subs-Info + PDB
    [Documentation]
    ...    0015(1X HFC 서비스 가입) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...
    ...    **1X 는 CDS 에서 끝나지 않는다.** PG.BSUBS 가 이어서 UPM 으로
    ...    Subs-Info-Request(0x07)를 밀고, UPM 이 Cell 정보를 담아 0x08 로 답해야
    ...    흐름이 완결된다. 그래서 이 TC 는 **세 구간을 한 번에** 본다.
    ...
    ...      1) CDS    : 0015 → 0016(SC) → 0017 → 0018
    ...      2) PG.SDM : T_CDS_ORDER_HIST → T_5G_SUBS_SERVICE
    ...      3) PDB    : 존 서비스 반영 확인
    ...      4) UPM    : PG.BSUBS → 0x07 수신 → 0x08(result-code=${UPM_RC_SUCCESS}) 응답
    ...                  (구 TC-UPM-301. UPM 슈트에는 1X 를 보낼 방법이 없어 트리거를
    ...                   쥔 이쪽으로 옮겼다 — 거기서는 주석 처리돼 있다)
    ...      5) PCF    : 도구가 PCF 역할로 h2c Listen — SBI Noti 2건 수신
    ...                  SNOTI→PCF 가입자 Noti / BSUBS→PCF Cell List
    ...
    ...    [성공 판단 기준]
    ...      · UPM 0x07 의 mdn / branch-name / event-timestamp 형식이 유효하고
    ...        tid·service-id 가 있으며, mdn 이 1X 를 보낸 가입자(${CDS_MDN})와 같을 것
    ...      · PDB 에 존 서비스 행이 **1건 이상** 있을 것
    ...        SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...         WHERE MDN='${CDS_MDN}' AND SVC_ID='ZONE_SVC_D' AND SVC_TYPE='D' AND JOB_CODE='1X'
    ...
    ...      · PCF Noti 2건이 ${CDS_NOTI_WAIT} 안에 도착하고 본문에 ${CDS_MDN} 이 있을 것
    ...
    ...    ★ 0x08 응답을 보내는 것까지가 이 TC 의 일이다. 안 보내면 PG 가 UPM 응답을
    ...      기다리다 재시도로 넘어가 **뒤따르는 TC 의 PDB 판정이 흔들린다.**
    ...    ★ Cell List 판정은 `since` 로 0x08 응답 **이후 도착분**만 본다. 경로 필터
    ...      (${CDS_NOTI_PATH_CELL})가 비어 있으면 앞의 가입자 Noti 를 다시 집어
    ...      그냥 통과해 버리기 때문이다. 실 PG 경로가 확인되면 그 변수를 채울 것.
    ...    ★ 이 판정은 **SA(5G) 가입자 전제**다 — LTE 는 SBI 가 아니라 RBUS 라
    ...      아무것도 안 들어온다(docs/nodes/CDS.md).
    ...    ※ 구간별로 끌 수 있다(끄면 접속·Listen 자체를 하지 않는다).
    ...       --variable CDS_UPM_VERIFY:False    --variable CDS_NOTI_VERIFY:False
    [Tags]    cds    command    validation    db    upm    noti
    Clear PCF Noti
    Command Download Flow    ${CDS_CODE_1X}    addr=${CDS_ADDR}
    Verify Zone Service Subscribed In PDB    ${CDS_MDN}
    # SNOTI → PCF 가입자 정보 변경 통보 (SDM 이 가입자 테이블을 고친 뒤 나간다)
    #Verify PCF Noti Received    label=가입자 Noti (SNOTI→PCF)
    #...    path=${CDS_NOTI_PATH_SUBS}    body=${CDS_MDN}
    # Cell List 는 아래 0x08 응답 **뒤에** 나가므로, 그 이후 도착분만 보도록
    # 기준 시각을 먼저 뜬다 — 경로 필터가 비어 있으면 위 가입자 Noti 를 다시
    # 집어 그냥 통과해 버린다.
    ${since}=    Noti Timestamp
    Verify UPM Subs Info Notified    mdn=${CDS_MDN}
    # BSUBS → PCF Cell List (0x08 로 준 Cell 정보가 PCF 로 나간다)
    Verify PCF Noti Received    label=Cell List (BSUBS→PCF)
    ...    path=${CDS_NOTI_PATH_CELL}    body=${CDS_MDN}    since=${since}


TC-CDS-004 1Y (HFC해지)
    [Documentation]
    ...    0015(1Y HFC 서비스 해지) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...
    ...    [성공 판단 기준] TC-CDS-003 이 넣은 존 서비스가 **0건**이어야 성공이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE WHERE MDN='${CDS_MDN}' AND SVC_ID='ZONE_SVC_D'
    ...    SVC_TYPE·JOB_CODE 를 걸지 않는다 — 어떤 형태로든 남아 있으면 해지가 덜 된 것이다.
    [Tags]    cds    command    validation    db
    Command Download Flow    ${CDS_CODE_1Y}
    Verify Zone Service Released In PDB    ${CDS_MDN}

TC-CDS-005 I2 (부가서비스신청)
    [Documentation]
    ...    0015(I2 부가서비스신청) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...
    ...    [성공 판단 기준] 아래 6개 조건을 모두 만족하는 행이 **1건 이상**이어야 성공이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...       WHERE MDN='${CDS_MDN}' AND SVC_TYPE='N' AND JOB_CODE='I2'
    ...             AND TIME_PERIOD_ID='56' AND "LIMIT"='Y' AND SVC_ID='YOUNG_HARM_INFO_BLOCK'
    [Tags]    cds    command    validation    db
    Command Download Flow    ${CDS_CODE_I2}
    Verify Addon Service Subscribed In PDB    ${CDS_MDN}

TC-CDS-006 I3 (부가서비스해지)
    [Documentation]
    ...    0015(I3 부가서비스해지) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...
    ...    [성공 판단 기준] TC-CDS-005 가 넣은 부가서비스가 **0건**이어야 성공이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...       WHERE MDN='${CDS_MDN}' AND SVC_ID='YOUNG_HARM_INFO_BLOCK'
    [Tags]    cds    command    validation    db
    Command Download Flow    ${CDS_CODE_I3}
    Verify Addon Service Released In PDB    ${CDS_MDN}

TC-CDS-007 C1 (기기변경)
    [Documentation]
    ...    0015(C1 기기변경) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    C1 은 MDN 이 바뀌지 않고 단말(MIN)만 바뀌므로 new_min 만 넘긴다.
    ...    C1 분기는 min ← mdn 을 강제하고 new_mdn 을 선언하지 않는다(CdsHelper).
    ...
    ...    [성공 판단 기준] 기존 서비스가 **하나도 빠짐없이 C1 으로 다시 쓰였는지**를 본다.
    ...      수행 전: SELECT SVC_ID, COUNT(*) ... WHERE MDN=?                   GROUP BY SVC_ID
    ...      수행 후: SELECT SVC_ID, COUNT(*) ... WHERE MDN=? AND JOB_CODE='C1' GROUP BY SVC_ID
    ...    두 집계가 SVC_ID 별로 완전히 같아야 성공이다.
    [Tags]    cds    command    validation    db
    ${before}=    Capture Service Counts Per SVC_ID    ${CDS_MDN}
    Command Download Flow    ${CDS_CODE_C1}    new_min=${CDS_NEW_MIN}
    Verify Service Counts Preserved In PDB    ${CDS_MDN}    ${CDS_CODE_C1}    ${before}

TC-CDS-008 G1 (정보변경)
    [Documentation]
    ...    0015(G1 정보변경) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...
    ...    [성공 판단 기준] TC-CDS-007(C1)과 같은 방식이다 — 수행 전 SVC_ID 별 행 수와
    ...    수행 후 JOB_CODE='G1' 집계가 같아야 성공이다.
    [Tags]    cds    command    validation    db
    ${before}=    Capture Service Counts Per SVC_ID    ${CDS_MDN}
    Command Download Flow    ${CDS_CODE_G1}
    Verify Service Counts Preserved In PDB    ${CDS_MDN}    ${CDS_CODE_G1}    ${before}




# ════════════════════════════════════════════════════════════════
# 쿠폰 / 옵션 계열 — Y9 / K1~K6 / SS / ST
#
# 전문 필드 집합은 CDS 시뮬레이터 GenCds.py 의 gen() 분기에서 뽑았고(2026-08-10 대조),
# PDB 판정 기준은 같은 날 지정된 표를 따른다.
#
# 판정은 앞의 코드들과 같은 **가입자 서비스 테이블**(T_5G_SUBS_SERVICE)이 주다.
# 다만 가입 계열 3개(K1/K5/Y9)는 가입과 동시에 만료·사용시점 예약이 걸리므로
# **예약 큐**(T_5G_RESERVED_JOB) 적재를 한 건 더 본다.
#
# ★ 예약 큐에 적재되는 JOB_CODE 는 인입 코드와 다르다 — K1→K3, K5→K7, Y9→Y6.
# ★ K2/K3/K4/K6 은 판정 기준이 **글자 그대로 같다**(MDN+R17+CNUM 삭제). 서로 구분되지
#   않으므로 각 TC 가 자기 전용 핀으로 가입을 먼저 만든 뒤 지워지는 것을 본다.
# ★ ${CDS_START_TIME} 이 과거면 가입하자마자 만료 예약이 실행돼 서비스 행이 사라진다
#   → 가입 판정(010/014)이 이유 없이 실패한다(cds_variables.robot 참조).
# ════════════════════════════════════════════════════════════════

TC-CDS-009 K1 (Data(Time) 쿠폰 가입)
    [Documentation]
    ...    0015(K1) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    필드: mdn / limit / start_time / coupon_type / coupon_pin / coupon_category
    ...
    ...    [성공 판단 기준] 조회 2건이 **모두** 만족돼야 성공이다.
    ...      1. 서비스 저장 — 1건 이상
    ...         SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...          WHERE MDN='${CDS_MDN}' AND SVC_ID='${CDS_DB_SVC_COUPON}' AND SVC_TYPE='${CDS_DB_SVC_TYPE_N}'
    ...                AND JOB_CODE='${CDS_CODE_K1}' AND TIME_PERIOD_ID='${CDS_DB_TPID_K1}'
    ...                AND "LIMIT"='${CDS_DB_LIMIT_K1}' AND LIMIT_VALID_TIME='${CDS_LIMIT_VALID_TIME}'
    ...                AND CNUM='${CDS_COUPON_PIN_K1}'
    ...      2. 예약 큐 적재 — 1건 이상 (JOB_CODE='${CDS_DB_RSV_JOB_K1}', 만료 예약)
    ...
    ...    CNUM 이 쿠폰 핀이 들어가는 컬럼이다.
    ...    ※ ${CDS_COUPON_CATEGORY} 가 T/P 가 아니면 Syncer 가 Invalid 로 걸러 **예약을
    ...       넣지 않는다** — 전문 흐름은 SC 로 통과하고 조회 2번째에서만 실패한다.
    ...
    ...    이 쿠폰은 TC-CDS-010(K2)이 같은 핀으로 해지해 정리한다.
    [Tags]    cds    command    validation    db    coupon
    Command Download Flow    ${CDS_CODE_K1}
    ...    start_time=${CDS_START_TIME}            coupon_type=${CDS_COUPON_TYPE}
    ...    coupon_pin=${CDS_COUPON_PIN_K1}         coupon_category=${CDS_COUPON_CATEGORY}
    Verify Coupon Service Subscribed In PDB
    ...    ${CDS_MDN}    ${CDS_CODE_K1}    ${CDS_DB_TPID_K1}    ${CDS_DB_LIMIT_K1}    ${CDS_COUPON_PIN_K1}
    Verify Reserved Job Created In PDB    ${CDS_MDN}    ${CDS_DB_RSV_JOB_K1}    ${CDS_COUPON_PIN_K1}

TC-CDS-010 K2 (Data(Time) 쿠폰 해지)
    [Documentation]
    ...    0015(K2) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    필드: mdn / limit / coupon_pin
    ...
    ...    [성공 판단 기준] TC-CDS-009(K1)가 넣은 쿠폰 행이 **0건**이어야 성공이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...       WHERE MDN='${CDS_MDN}' AND SVC_ID='${CDS_DB_SVC_COUPON}' AND CNUM='${CDS_COUPON_PIN_K1}'
    ...
    ...    ※ 0건은 "해지됐다"와 "원래 없었다"를 구분하지 못한다 — TC-CDS-009 가 같은 핀으로
    ...       먼저 도는 것을 전제로 한다. 단독 실행하면 그냥 통과한다.
    [Tags]    cds    command    validation    db    coupon
    Command Download Flow    ${CDS_CODE_K2}    coupon_pin=${CDS_COUPON_PIN_K1}
    Verify Coupon Service Released In PDB    ${CDS_MDN}    ${CDS_COUPON_PIN_K1}


TC-CDS-011 K4 (Data(Time) 쿠폰 취소)
    [Documentation]
    ...    0015(K4) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    필드: mdn / limit / coupon_pin
    ...
    ...    **이 TC 는 자기 전제를 직접 만든다** — 취소할 쿠폰이 없으면 삭제 판정이 "원래
    ...    없었다"로 그냥 통과하기 때문이다. 그래서 앞에 K1 을 전용 핀
    ...    (${CDS_COUPON_PIN_K4})으로 보내 쿠폰을 만들어 둔다.
    ...    뒤따르는 TC-CDS-012(K3 만료)도 같은 구조인데, 그쪽은 START_TIME 을 현재
    ...    시각으로 보낸다는 점이 다르다.
    ...
    ...    [성공 판단 기준] 취소 후 그 핀의 쿠폰 행이 **0건**이어야 성공이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...       WHERE MDN='${CDS_MDN}' AND SVC_ID='${CDS_DB_SVC_COUPON}' AND CNUM='${CDS_COUPON_PIN_K4}'
    [Tags]    cds    command    validation    db    coupon
    # 준비: 취소 대상이 될 쿠폰을 K1 으로 가입시킨다
    Command Download Flow    ${CDS_CODE_K1}
    ...    start_time=${CDS_START_TIME}            coupon_type=${CDS_COUPON_TYPE}
    ...    coupon_pin=${CDS_COUPON_PIN_K4}         coupon_category=${CDS_COUPON_CATEGORY}
    Verify Coupon Service Subscribed In PDB
    ...    ${CDS_MDN}    ${CDS_CODE_K1}    ${CDS_DB_TPID_K1}    ${CDS_DB_LIMIT_K1}    ${CDS_COUPON_PIN_K4}
    # 검증: K4 로 취소
    Command Download Flow    ${CDS_CODE_K4}    coupon_pin=${CDS_COUPON_PIN_K4}
    Verify Coupon Service Released In PDB    ${CDS_MDN}    ${CDS_COUPON_PIN_K4}

TC-CDS-012 K3 (Data(Time) 쿠폰 만료)
    [Documentation]
    ...    0015(K3) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    필드: mdn / limit / coupon_pin
    ...
    ...    **이 TC 는 자기 전제를 직접 만든다.** 만료시킬 쿠폰이 없으면 삭제 판정이
    ...    "원래 없었다"로 그냥 통과하기 때문이다. 그래서 앞에 K1 을 전용 핀
    ...    (${CDS_COUPON_PIN_K3})으로 한 번 보내 쿠폰을 만들어 둔다. 이 선행 송신은
    ...    검증 대상이 아니라 준비 동작이지만, 실패하면 뒤의 판정이 무의미해지므로
    ...    가입까지 확인하고 넘어간다.
    ...
    ...    ★ 이 TC 의 K1 만 START_TIME 을 **현재 시각 기준**으로 보낸다(다른 TC 는 먼 미래인
    ...      ${CDS_START_TIME}). 만료 업무라 유효기간이 이미 찬 쿠폰을 다뤄야 하기
    ...      때문이다. 값은 `Current CDS Start Time` 이 만들고, 같은 값을 LIMIT_VALID_TIME
    ...      판정에도 그대로 쓴다 — 조회 때 다시 부르면 분이 넘어가는 순간 어긋난다.
    ...
    ...      그 대가로 **가입 확인 단계에 경합이 있다.** START_TIME 이 지나 있으면 PG.RDS 가
    ...      만료 예약을 곧 집어가므로, K3 를 보내기 전에 RDS 가 먼저 지워버릴 수 있다.
    ...      그러면 이 TC 는 가입 확인에서 실패한다(만료 자체는 정상 동작이다).
    ...      → 그때는 ${CDS_K3_START_OFFSET_MIN}(분)을 1~2 로 올려 여유를 준다.
    ...        전문 형식이 분까지만 담아서 조정 단위가 분이다. 실행 중 한 번만 바꿔 보려면
    ...        --variable CDS_K3_START_OFFSET_MIN:2 로도 된다.
    ...
    ...    [성공 판단 기준] 만료 후 그 핀의 쿠폰 행이 **0건**이어야 성공이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...       WHERE MDN='${CDS_MDN}' AND SVC_ID='${CDS_DB_SVC_COUPON}' AND CNUM='${CDS_COUPON_PIN_K3}'
    ...    K2(해지)·K4(취소)와 **판정 기준이 완전히 같다** — 세 코드를 서로 구분하지 못한다.
    [Tags]    cds    command    validation    db    coupon
    # 준비: 만료 대상이 될 쿠폰을 K1 으로 가입시킨다 (START_TIME = 현재 시각 ± 오프셋)
    ${start_time}    ${valid_time}=    Current CDS Start Time    ${CDS_K3_START_OFFSET_MIN}
    Log    [TC-012] K1 START_TIME=${start_time} → LIMIT_VALID_TIME=${valid_time}    console=True
    Command Download Flow    ${CDS_CODE_K1}
    ...    start_time=${start_time}                coupon_type=${CDS_COUPON_TYPE}
    ...    coupon_pin=${CDS_COUPON_PIN_K3}         coupon_category=${CDS_COUPON_CATEGORY}
    Verify Coupon Service Subscribed In PDB
    ...    ${CDS_MDN}    ${CDS_CODE_K1}    ${CDS_DB_TPID_K1}    ${CDS_DB_LIMIT_K1}    ${CDS_COUPON_PIN_K3}
    ...    limit_valid_time=${valid_time}
    # 검증: K3 로 만료
    Command Download Flow    ${CDS_CODE_K3}    coupon_pin=${CDS_COUPON_PIN_K3}
    Verify Coupon Service Released In PDB    ${CDS_MDN}    ${CDS_COUPON_PIN_K3}


TC-CDS-013 K5 (Data(Time) 3Mbps 쿠폰 가입)
    [Documentation]
    ...    0015(K5) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    전문 필드 집합은 K1 과 같다(GenCds gen() 에서 K1 과 한 분기).
    ...
    ...    [성공 판단 기준] K1(TC-CDS-009)과 같은 2건 조회인데 **기대값이 다르다.**
    ...      1. 서비스 저장 — JOB_CODE='${CDS_CODE_K5}', TIME_PERIOD_ID='${CDS_DB_TPID_K5}',
    ...         "LIMIT"='${CDS_DB_LIMIT_K5}', LIMIT_VALID_TIME='${CDS_LIMIT_VALID_TIME}',
    ...         CNUM='${CDS_COUPON_PIN_K5}' (K1 은 113/1)
    ...      2. 예약 큐 적재 — JOB_CODE='${CDS_DB_RSV_JOB_K5}' (K1 은 K3)
    ...
    ...    핀을 K1 과 달리 쓰는 이유는 해지 판정이 `MDN + R17 + CNUM` 으로만 걸려
    ...    핀을 공유하면 TC-CDS-010 이 지운 행을 이 TC 의 결과로 착각하기 때문이다.
    [Tags]    cds    command    validation    db    coupon
    Command Download Flow    ${CDS_CODE_K5}
    ...    start_time=${CDS_START_TIME}            coupon_type=${CDS_COUPON_TYPE}
    ...    coupon_pin=${CDS_COUPON_PIN_K5}         coupon_category=${CDS_COUPON_CATEGORY}
    Verify Coupon Service Subscribed In PDB
    ...    ${CDS_MDN}    ${CDS_CODE_K5}    ${CDS_DB_TPID_K5}    ${CDS_DB_LIMIT_K5}    ${CDS_COUPON_PIN_K5}
    Verify Reserved Job Created In PDB    ${CDS_MDN}    ${CDS_DB_RSV_JOB_K5}    ${CDS_COUPON_PIN_K5}

TC-CDS-014 K6 (Data(Time) 3Mbps 쿠폰 해지)
    [Documentation]
    ...    0015(K6) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    필드: mdn / limit / coupon_pin
    ...
    ...    [성공 판단 기준] TC-CDS-013(K5)이 넣은 쿠폰 행이 **0건**이어야 성공이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...       WHERE MDN='${CDS_MDN}' AND SVC_ID='${CDS_DB_SVC_COUPON}' AND CNUM='${CDS_COUPON_PIN_K5}'
    ...    K2(해지)와 판정 기준이 같다 — 3Mbps 쿠폰인지는 구분되지 않는다.
    [Tags]    cds    command    validation    db    coupon
    Command Download Flow    ${CDS_CODE_K6}    coupon_pin=${CDS_COUPON_PIN_K5}
    Verify Coupon Service Released In PDB    ${CDS_MDN}    ${CDS_COUPON_PIN_K5}

TC-CDS-015 Y9 (Data(Zone) 부가서비스 쿠폰 사용시점 알림)
    [Documentation]
    ...    0015(Y9) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    필드: mdn / limit / zone_code / start_time / coupon_type / coupon_pin
    ...
    ...    [성공 판단 기준] 조회 2건이 **모두** 만족돼야 성공이다.
    ...      1. 서비스 저장 — 1건 이상
    ...         SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...          WHERE MDN='${CDS_MDN}' AND SVC_ID='${CDS_DB_SVC_ZONE_B}' AND SVC_TYPE='${CDS_DB_SVC_TYPE_Z}'
    ...                AND JOB_CODE='${CDS_CODE_Y9}' AND TIME_PERIOD_ID='${CDS_DB_TPID_Y9}'
    ...                AND "LIMIT"='${CDS_DB_LIMIT_Y9}' AND LIMIT_VALID_TIME='${CDS_LIMIT_VALID_TIME}'
    ...      2. 예약 큐 적재 — 1건 이상
    ...         SELECT COUNT(*) FROM T_5G_RESERVED_JOB
    ...          WHERE MDN='${CDS_MDN}' AND JOB_CODE='${CDS_DB_RSV_JOB_Y9}' AND COUPON_PIN='${CDS_COUPON_PIN_Y9}'
    ...
    ...    SVC_ID 가 1X 의 ZONE_SVC_D 가 아니라 **ZONE_SVC_B** 다.
    ...    예약 큐의 JOB_CODE 는 Y9 가 아니라 **Y6** 이다 — Syncer 가 COUPON_TYPE='T' 를
    ...    보고 Y6 으로 적재한다(숫자 권종이면 Y8). ${CDS_COUPON_TYPE} 를 바꾸면 기대값도
    ...    같이 바뀐다.
    ...
    ...    ※ 짝이 되는 해지 코드가 없어 이 TC 는 서비스 행과 예약 행을 **남긴다.**
    [Tags]    cds    command    validation    db    coupon
    Command Download Flow    ${CDS_CODE_Y9}
    ...    zone_code=${CDS_ZONE_CODE}          start_time=${CDS_START_TIME}
    ...    coupon_type=${CDS_COUPON_TYPE}      coupon_pin=${CDS_COUPON_PIN_Y9}
    Verify Zone Coupon Service Subscribed In PDB    ${CDS_MDN}
    Verify Reserved Job Created In PDB    ${CDS_MDN}    ${CDS_DB_RSV_JOB_Y9}    ${CDS_COUPON_PIN_Y9}

TC-CDS-016 SS (0플랜 옵션 3시간프리 가입)
    [Documentation]
    ...    0015(SS) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    필드: mdn / limit / start_time / coupon_type (GenCds 는 SS/ST/SU/SV 를 한 분기로 둔다)
    ...
    ...    [성공 판단 기준] 서비스 행이 **1건 이상** 생겨야 성공이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...       WHERE MDN='${CDS_MDN}' AND SVC_ID='${CDS_DB_SVC_TIME_I}' AND SVC_TYPE='${CDS_DB_SVC_TYPE_T}'
    ...             AND JOB_CODE='${CDS_CODE_SS}' AND TIME_PERIOD_ID='${CDS_DB_TPID_SS}'
    ...             AND "LIMIT"='${CDS_DB_LIMIT_SS}' AND CNUM='${CDS_DB_CNUM_SS}'
    ...    쿠폰이 아니라 옵션이라 CNUM 이 핀이 아니라 **0 고정**이다.
    ...    예약 큐는 보지 않는다 — SS 는 예약을 걸지 않는다.
    ...
    ...    SS 는 시간을 **TIME_PERIOD_ID 로 본다** — 'SS_' 접두 + 전문 START_TIME(12자리)
    ...    이다. 예) SS_203712312359
    ...
    ...    ★ K1/K5/Y9 의 LIMIT_VALID_TIME(14자리, 초 '00' 부가)과 **값이 다르다.**
    ...      기준표가 둘 다 $LIMIT_VALID_TIME 으로 적어 놔 같은 값으로 읽기 쉬운 자리다.
    ...      LIMIT_VALID_TIME 컬럼 자체는 이 테이블에 있지만 SS 판정 기준에는 없다.
    [Tags]    cds    command    validation    db    coupon
    Command Download Flow    ${CDS_CODE_SS}
    ...    start_time=${CDS_START_TIME}    coupon_type=${CDS_COUPON_TYPE}
    Verify Option Service Subscribed In PDB    ${CDS_MDN}

TC-CDS-017 ST (0플랜 옵션 3시간프리 해지)
    [Documentation]
    ...    0015(ST) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    전문 필드 집합은 SS 와 같다(GenCds 에서 SS/ST/SU/SV 가 한 분기).
    ...
    ...    [성공 판단 기준] TC-CDS-016(SS)이 넣은 옵션 행이 **0건**이어야 성공이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...       WHERE MDN='${CDS_MDN}' AND SVC_ID='${CDS_DB_SVC_TIME_I}'
    ...    CNUM 을 걸지 않는다 — 판정 기준이 MDN + SVC_ID 뿐이다.
    [Tags]    cds    command    validation    db    coupon
    Command Download Flow    ${CDS_CODE_ST}
    ...    start_time=${CDS_START_TIME}    coupon_type=${CDS_COUPON_TYPE}
    Verify Option Service Released In PDB    ${CDS_MDN}


# ════════════════════════════════════════════════════════════════
# 번호변경 → 해지 (체인의 끝)
# ════════════════════════════════════════════════════════════════

TC-CDS-018 D3 (번호변경)
    [Documentation]
    ...    0015(D3 번호변경) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    성공하면 가입자의 현재 번호가 new_mdn 으로 바뀌므로 ${CDS_ACTIVE_MDN} 을 갱신한다.
    ...    이후 TC-CDS-019(Z1)가 이 값을 대상으로 동작한다.
    ...
    ...    [성공 판단 기준] C1/G1 과 같은 전후 비교인데 **번호가 바뀌는 것이 다르다.**
    ...      수행 전: MDN = 바뀌기 전 번호(${CDS_ACTIVE_MDN})
    ...      수행 후: MDN = 바뀐 번호(${CDS_NEW_MDN}) AND JOB_CODE='D3'
    ...    옛 번호의 서비스가 새 번호로 그대로 옮겨졌는지를 보는 셈이다.
    [Tags]    cds    command    validation    db
    ${before}=    Capture Service Counts Per SVC_ID    ${CDS_ACTIVE_MDN}
    Command Download Flow    ${CDS_CODE_D3}    new_mdn=${CDS_NEW_MDN}    new_min=${CDS_NEW_MIN}
    Set Suite Variable    ${CDS_ACTIVE_MDN}    ${CDS_NEW_MDN}
    Verify Service Counts Preserved In PDB    ${CDS_NEW_MDN}    ${CDS_CODE_D3}    ${before}

TC-CDS-019 Z1 (가입해지)
    [Documentation]
    ...    0015(Z1 해지) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    규격 Z1 필드 15개(A1 에서 min·addSvc 를 뺀 집합)를 기본값으로 전달한다.
    ...    ※ 해지 대상은 ${CDS_ACTIVE_MDN} — TC-CDS-018(D3)이 번호를 바꿨으면 바뀐 번호,
    ...       D3 를 건너뛰었거나 실패했으면 원래 번호(${CDS_MDN})다.
    ...    가입자 자체를 없애므로 이 체인의 마지막에 둔다.
    ...
    ...    [성공 판단 기준] TC-CDS-002 와 같은 이유로 전문 흐름(SC)만으로는 판정하지
    ...    않는다. 다만 **방향이 반대다** — PDB 조회 2건이 **모두 0** 이어야 성공이고,
    ...    행이 남아 있으면 실패다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_PROFILE WHERE MDN='${CDS_ACTIVE_MDN}'
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE WHERE MDN='${CDS_ACTIVE_MDN}'
    ...    서비스는 SVC_ID 를 가리지 않는다 — 해지라면 어떤 서비스도 남으면 안 된다.
    ...    반영이 비동기라 ${CDS_DB_WAIT} 동안 재조회한다.
    ...    ※ 0건은 "지워졌다"와 "원래 없었다"를 구분하지 못한다. 이 TC 는 앞선
    ...       TC-CDS-002(A1 신규가입)가 실제로 넣은 뒤에 도는 것을 전제로 한다.
    [Tags]    cds    command    validation    db
    Command Download Flow    ${CDS_CODE_Z1}    mdn=${CDS_ACTIVE_MDN}
    Verify Subscriber Removed From PDB    ${CDS_ACTIVE_MDN}

# 접속 해제(0005~0008)는 Suite Teardown(`Suite CDS Disconnect`)에서 수행한다.
# 슈트가 끝나면 반드시 해야 하는 일이라 TC 로 두면 실패·필터 시 건너뛰게 된다.
