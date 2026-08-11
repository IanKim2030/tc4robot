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
...                     → 두 소켓 생존 확인 → PDB 접속 (접속은 TC 가 아니다)
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
...    판정 대상은 대부분 가입자 테이블(T_5G_SUBS_*)이고, 가입 계열 3개(009/010/014)만
...    예약 큐(T_5G_RESERVED_JOB) 적재를 **한 건 더** 본다.
...      002 A1 신규가입 : PROFILE 1건 + SERVICE 2건(DATA_USAGE_LEVEL / _2) — 모두 1
...      003 1X HFC가입  : SERVICE(SVC_ID=ZONE_SVC_D, SVC_TYPE=D, JOB_CODE=1X) 1건 이상
...      004 1Y HFC해지  : SERVICE(SVC_ID=ZONE_SVC_D) 0건
...      005 I2 부가신청 : SERVICE(YOUNG_HARM_INFO_BLOCK, N, I2, 56, LIMIT=Y) 1건 이상
...      006 I3 부가해지 : SERVICE(SVC_ID=YOUNG_HARM_INFO_BLOCK) 0건
...      007 C1 기기변경 : 수행 전 SVC_ID 별 행 수 == 수행 후 JOB_CODE=C1 집계
...      008 G1 정보변경 : 위와 같음 (JOB_CODE=G1)
...      009 Y9 Zone쿠폰  : SERVICE(ZONE_SVC_B, Z, Y9, 25, LIMIT=0, LIMIT_VALID_TIME) 1건 이상
...                        + RESERVED_JOB(JOB_CODE=Y6, 핀) 1건 이상
...      010 K1 쿠폰가입  : SERVICE(R17, N, K1, 113, LIMIT=1, LIMIT_VALID_TIME, CNUM=핀) 1건 이상
...                        + RESERVED_JOB(JOB_CODE=K3, 핀) 1건 이상
...      011 K2 쿠폰해지  : 010 의 핀으로 SERVICE(R17, CNUM) 0건
...      012 K3 쿠폰만료  : TC 안에서 K1 로 가입시킨 뒤 만료 → 그 핀으로 0건
...      013 K4 쿠폰취소  : 012 와 같은 구조 (핀만 다름)
...      014 K5 쿠폰가입  : SERVICE(R17, N, K5, 0, LIMIT=2, LIMIT_VALID_TIME, CNUM=핀) 1건 이상
...                        + RESERVED_JOB(JOB_CODE=K7, 핀) 1건 이상
...      015 K6 쿠폰해지  : 014 의 핀으로 SERVICE(R17, CNUM) 0건
...      016 SS 옵션가입  : SERVICE(TIME_SVC_I, T, SS, TIME_PERIOD_ID=SS_+START_TIME, LIMIT=0, CNUM=0) 1건 이상
...      017 ST 옵션해지  : SERVICE(SVC_ID=TIME_SVC_I) 0건
...      018 D3 번호변경 : 007 과 같은 전후 비교 (옛 번호 기준 → 새 번호 + JOB_CODE=D3)
...      019 Z1 가입해지 : PROFILE / SERVICE(SVC_ID 무관) 모두 0건
...      "1건 이상"은 건수를 못 박지 않는다는 뜻이다 — 존·부가 서비스가 여러 건일 수 있다.
...      전후 비교형(007/008/018)은 `Command Download Flow` **앞**에서 기준선을 먼저 뜬다.
...      ★ 예약 큐에 적재되는 JOB_CODE 는 인입 코드와 다르다 — K1→K3, K5→K7, Y9→Y6.
...        인입 코드로 조회하면 한 건도 나오지 않는다.
...      ★ K2/K3/K4/K6 은 판정 기준이 **글자 그대로 같다**(MDN+R17+CNUM 삭제) — 해지·만료·
...        취소가 서로 구분되지 않는다. 그래서 012/013 은 자기 핀으로 가입을 먼저 만든다.
...      ★ 시간 컬럼은 전부 전문의 START_TIME 에서 나온다 — PDB 의 필드 정의 테이블
...        T_5G_CDS_ORDER_CFG 에서 START_TIME 의 별칭(SUBTITLE)이 LIMIT_VALID_TIME 이다.
...        다만 **폭이 다르다** — 전문은 12자리인데 DB 는 초 '00' 이 붙은 14자리다.
...          009/010/014 : LIMIT_VALID_TIME = START_TIME+'00'         (${CDS_LIMIT_VALID_TIME})
...          016         : TIME_PERIOD_ID   = 'SS_' + START_TIME+'00' (${CDS_DB_TPID_SS})
...        형식이 또 어긋나면 저 두 변수만 고치면 된다 — SQL·키워드는 그대로다.
...      접속 정보는 cds_variables.robot 의
...      ${CDS_DB_CONNSTR}(완성된 ODBC 문자열) 하나다 — 환경변수 PG_CDS_DB_CONNSTR 가 우선.
...      DB 접속은 **Suite Setup 에서 소켓과 함께 1회** 붙고 Suite Teardown 에서 끊는다
...      (TC별 접속 없음). autocommit 은 꺼져 있다(${CDS_DB_AUTOCOMMIT}=${FALSE}).
...      ★ 접속 정보가 틀리면 이 TC 뿐 아니라 **슈트 전체가 서지 않는다** — Suite Setup
...        이 실패하기 때문이다. --exclude db 로도 피할 수 없다.
...
...    [TC 간 의존성] 슈트 전체가 002(A1 신규가입)로 만든 가입자 하나를 이어 쓴다.
...      002 A1 신규가입  : 이후 모든 TC 의 대상 가입자를 만든다
...      010 K1 → 011 K2  : 같은 핀(${CDS_COUPON_PIN_K1})의 쿠폰 가입 → 해지 쌍
...      014 K5 → 015 K6  : 같은 핀(${CDS_COUPON_PIN_K5})의 쿠폰 가입 → 해지 쌍
...      016 SS → 017 ST  : 옵션 가입 → 해지 쌍 (핀 없음, SVC_ID 로만 식별)
...      018 D3 번호변경  : 성공하면 ${CDS_ACTIVE_MDN} 을 ${CDS_NEW_MDN} 으로 갱신
...      019 Z1 해지      : 가입자 자체를 해지 (체인의 끝). PDB 에서 사라졌는지까지 본다
...    쿠폰 쌍은 핀이 서로 다르다 — 삭제 판정이 `MDN + R17 + CNUM` 으로만 걸려 핀을
...    합치면 한 TC 가 지운 행을 다른 TC 가 자기 결과로 착각한다.
...    해지 TC(011/015/017)를 단독 실행하면 짝이 되는 가입이 없어 "0건"으로 그냥 통과한다.
...    012/013(K3 만료 / K4 취소)은 그 함정을 피하려고 **TC 안에서 K1 가입을 먼저** 돌린다.
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

TC-CDS-003 1X (HFC가입)
    [Documentation]
    ...    0015(1X HFC 서비스 가입) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...
    ...    [성공 판단 기준] PDB 에 존 서비스 행이 **1건 이상** 생겨야 성공이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...       WHERE MDN='${CDS_MDN}' AND SVC_ID='ZONE_SVC_D' AND SVC_TYPE='D' AND JOB_CODE='1X'
    [Tags]    cds    command    validation    db
    Command Download Flow    ${CDS_CODE_1X}    addr=${CDS_ADDR}
    Verify Zone Service Subscribed In PDB    ${CDS_MDN}

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
    ...    이 쿠폰은 TC-CDS-011(K2)이 같은 핀으로 해지해 정리한다.
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
    ...    [성공 판단 기준] TC-CDS-010(K1)이 넣은 쿠폰 행이 **0건**이어야 성공이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...       WHERE MDN='${CDS_MDN}' AND SVC_ID='${CDS_DB_SVC_COUPON}' AND CNUM='${CDS_COUPON_PIN_K1}'
    ...
    ...    ※ 0건은 "해지됐다"와 "원래 없었다"를 구분하지 못한다 — TC-CDS-010 이 같은 핀으로
    ...       먼저 도는 것을 전제로 한다. 단독 실행하면 그냥 통과한다.
    [Tags]    cds    command    validation    db    coupon
    Command Download Flow    ${CDS_CODE_K2}    coupon_pin=${CDS_COUPON_PIN_K1}
    Verify Coupon Service Released In PDB    ${CDS_MDN}    ${CDS_COUPON_PIN_K1}

TC-CDS-011 K3 (Data(Time) 쿠폰 만료)
    [Documentation]
    ...    0015(K3) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    필드: mdn / limit / coupon_pin
    ...
    ...    **이 TC 는 자기 전제를 직접 만든다.** 만료시킬 쿠폰이 없으면 삭제 판정이
    ...    "원래 없었다"로 그냥 통과하기 때문이다. 그래서 앞에 K1 을 전용 핀
    ...    (${CDS_COUPON_PIN_K1})으로 한 번 보내 쿠폰을 만들어 둔다. 이 선행 송신은
    ...    검증 대상이 아니라 준비 동작이지만, 실패하면 뒤의 판정이 무의미해지므로
    ...    가입까지 확인하고 넘어간다.
    ...
    ...    [성공 판단 기준] 만료 후 그 핀의 쿠폰 행이 **0건**이어야 성공이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...       WHERE MDN='${CDS_MDN}' AND SVC_ID='${CDS_DB_SVC_COUPON}' AND CNUM='${CDS_COUPON_PIN_K1}'
    ...    K2(해지)·K4(취소)와 **판정 기준이 완전히 같다** — 세 코드를 서로 구분하지 못한다.
    [Tags]    cds    command    validation    db    coupon
    # 준비: 만료 대상이 될 쿠폰을 K1 으로 가입시킨다
    Command Download Flow    ${CDS_CODE_K1}
    ...    start_time=${CDS_START_TIME}            coupon_type=${CDS_COUPON_TYPE}
    ...    coupon_pin=${CDS_COUPON_PIN_K1}         coupon_category=${CDS_COUPON_CATEGORY}
    Verify Coupon Service Subscribed In PDB
    ...    ${CDS_MDN}    ${CDS_CODE_K1}    ${CDS_DB_TPID_K1}    ${CDS_DB_LIMIT_K1}    ${CDS_COUPON_PIN_K1}
    # 검증: K3 로 만료
    Command Download Flow    ${CDS_CODE_K3}    coupon_pin=${CDS_COUPON_PIN_K1}
    Verify Coupon Service Released In PDB    ${CDS_MDN}    ${CDS_COUPON_PIN_K1}

TC-CDS-012 K4 (Data(Time) 쿠폰 취소)
    [Documentation]
    ...    0015(K4) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    필드: mdn / limit / coupon_pin
    ...
    ...    TC-CDS-012(K3)와 같은 구조다 — 취소 대상을 K1 으로 먼저 만든 뒤 취소한다.
    ...    핀만 ${CDS_COUPON_PIN_K1} 로 다르다.
    ...
    ...    [성공 판단 기준] 취소 후 그 핀의 쿠폰 행이 **0건**이어야 성공이다.
    ...      SELECT COUNT(*) FROM T_5G_SUBS_SERVICE
    ...       WHERE MDN='${CDS_MDN}' AND SVC_ID='${CDS_DB_SVC_COUPON}' AND CNUM='${CDS_COUPON_PIN_K1}'
    [Tags]    cds    command    validation    db    coupon
    # 준비: 취소 대상이 될 쿠폰을 K1 으로 가입시킨다
    Command Download Flow    ${CDS_CODE_K1}
    ...    start_time=${CDS_START_TIME}            coupon_type=${CDS_COUPON_TYPE}
    ...    coupon_pin=${CDS_COUPON_PIN_K1}         coupon_category=${CDS_COUPON_CATEGORY}
    Verify Coupon Service Subscribed In PDB
    ...    ${CDS_MDN}    ${CDS_CODE_K1}    ${CDS_DB_TPID_K1}    ${CDS_DB_LIMIT_K1}    ${CDS_COUPON_PIN_K1}
    # 검증: K4 로 취소
    Command Download Flow    ${CDS_CODE_K4}    coupon_pin=${CDS_COUPON_PIN_K1}
    Verify Coupon Service Released In PDB    ${CDS_MDN}    ${CDS_COUPON_PIN_K1}

TC-CDS-013 K5 (Data(Time) 3Mbps 쿠폰 가입)
    [Documentation]
    ...    0015(K5) 송신 → 0016 ACK(SC) → 0017 Result → 0018 ResultACK
    ...    전문 필드 집합은 K1 과 같다(GenCds gen() 에서 K1 과 한 분기).
    ...
    ...    [성공 판단 기준] K1(TC-CDS-010)과 같은 2건 조회인데 **기대값이 다르다.**
    ...      1. 서비스 저장 — JOB_CODE='${CDS_CODE_K5}', TIME_PERIOD_ID='${CDS_DB_TPID_K5}',
    ...         "LIMIT"='${CDS_DB_LIMIT_K5}', LIMIT_VALID_TIME='${CDS_LIMIT_VALID_TIME}',
    ...         CNUM='${CDS_COUPON_PIN_K5}' (K1 은 113/1)
    ...      2. 예약 큐 적재 — JOB_CODE='${CDS_DB_RSV_JOB_K5}' (K1 은 K3)
    ...
    ...    핀을 K1 과 달리 쓰는 이유는 해지 판정이 `MDN + R17 + CNUM` 으로만 걸려
    ...    핀을 공유하면 TC-CDS-011 이 지운 행을 이 TC 의 결과로 착각하기 때문이다.
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
    ...    [성공 판단 기준] TC-CDS-014(K5)가 넣은 쿠폰 행이 **0건**이어야 성공이다.
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
    ...    SS 는 별도 LIMIT_VALID_TIME 컬럼이 없고 **TIME_PERIOD_ID 가 시간을 담는다** —
    ...    'SS_' 접두 + 14자리 LIMIT_VALID_TIME(전문 START_TIME + 초 '00') 이다.
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
