-- ══════════════════════════════════════════════════════════════════
-- config/db_seed/dev.sql — dev 환경 실행 전 DB 설정 정보 확인 → 없으면 INSERT
--
-- run_tests.sh 가 본 실행(nag/pcf/.../all/smoke) 전에 setup/db_seed.robot 으로
-- 한 번 돌린다. 노드와 무관한 공통 한 세트다.
-- 환경별 파일이다 — run_tests.sh 의 환경 인자로 고른다 (dev 기본, IP 지정도 dev).
--   bash run_tests.sh nag       → config/db_seed/dev.sql
--   bash run_tests.sh nag stg   → config/db_seed/stg.sql
--   (파일이 없는 환경 — prd/local — 은 DB 접속 없이 건너뛴다)
--   bash run_tests.sh nag --no-db-seed      # 생략
--   bash run_tests.sh nag --db-seed-check   # 확인만 (INSERT 안 함)
--
-- [형식] SELECT 로 시작하는 문장이 블록을 연다. 다음 SELECT 전까지의 INSERT / UPDATE
--        문이 그 블록에 속한다. 여러 줄에 걸쳐 써도 된다(문장은 `;` 로만 나뉜다).
--   -- @name: 블록 이름 (선택 — 로그에 찍힌다)
--   SELECT COUNT(*) FROM <표> WHERE <키 조건>;
--   INSERT INTO <표> (...) VALUES (...);        -- 0건일 때만 실행 (뒤에 재확인)
--   UPDATE <표> SET ... WHERE <키 조건>;         -- 1건 이상일 때만 실행
--   INSERT 만 있으면 "없으면 넣기", UPDATE 만 있으면 "있으면 고치기", 둘 다면 upsert.
--   실행한 INSERT/UPDATE 는 문장마다 콘솔(대상 표·영향 행 수)과 log.html(전체 SQL)에 남는다.
--
-- ★ 바인드 파라미터(?)는 지원하지 않는다. 값은 리터럴 또는 **`${변수}`** 로 쓴다.
--   `${CDS_MDN}` 처럼 쓰면 실행 시 환경 파일(config/env/dev.py) 값으로 바뀐다 — 번호를
--   바꿀 때 dev.py 만 고치면 된다. 글자 그대로 끼워 넣으므로 따옴표는 직접 쓴다
--   ('${CDS_MDN}', '82${CDS_MIN}'). 없는 변수면 줄 번호와 함께 실패한다(빈 값으로 안 넣는다).
--   주석 안의 ${...} 는 치환하지 않는다. 지금 쓰는 변수:
--     CDS_MDN/MIN · CDS_NEW_MDN/MIN · NAG_MDN/MIN · NAG_MDN_NO_HFC/NAG_MIN_NO_HFC ·
--     NWDAF_MDN/MIN · NWDAF_MDN_5G/MIN_5G · UPM_MDN/MIN · UPM_SYS_ID · UPM_BRANCH_NAME ·
--     TOOL_HOST · SBI_NOTI_PORT(variables.robot)
--   dev.py 에 대응 변수가 없는 값(01090050002, 192.168.15.144)은 리터럴로 남겼다.
-- ★ 표 이름에 스키마 접두사("PDB.")를 붙이지 말 것 — 실환경에서
--   schema 'PDB' does not exist 로 거부된 전례가 있다.
-- ★ 블록이 하나도 없으면 DB 에 접속하지 않고 지나간다.
-- ★ ${PDB_CONNSTR_2} 가 채워져 있으면 두 번째 DB 에도 같은 확인·INSERT·UPDATE 를 한다.
-- ══════════════════════════════════════════════════════════════════

-- 예시 (주석을 풀고 실제 표·값으로 바꿀 것)
-- -- @name: 예시 설정
-- SELECT COUNT(*) FROM T_XXX_CFG WHERE KEY_COL = 'A';
-- INSERT INTO T_XXX_CFG (KEY_COL, VAL) VALUES ('A', '1');
-- UPDATE T_XXX_CFG SET VAL = '1' WHERE KEY_COL = 'A';

-- @name: CDS 가입자 LTE 세션 (CDS_MDN)
SELECT COUNT(*) FROM T_SESSION_INFO WHERE MDN='${CDS_MDN}';
INSERT INTO T_SESSION_INFO
(
    SESSION_ID,
    MDN,
    MSISDN,
    IMSI,
    SESSION_STATUS,
    RULE_BASE_NAME1,
    RULE_BASE_NAME2,
    RULE_BASE_NAME3,
    CONTROLABLE_USER,
    OPEN_DATE,
    OPEN_TIME,
    UPDATE_DATE,
    UPDATE_TIME,
    LOCATION_ID,
    LOCATION_STATUS,
    CCR_TYPE,
    CCR_RECORD_NO,
    IP_ADDR,
    CLIENT_HOST,
    CLIENT_REALM,
    BEARER_ID,
    PROC_SYSTEM,
    QCI_LEVEL,
    DATA_USAGE_LEVEL,
    FEMTOCELL_CTRL,
    APN_TYPE,
    APN,
    RM_PROCESSING,
    SERVICE_ID,
    RAT_TYPE,
    DESTINATION_HOST,
    PRIORITY_LEVEL,
    PRE_EMPTION_CAPABILITY,
    PRE_EMPTION_VULNERABILITY,
    RULE_MADE_SOURCE,
    ZONE_INFO_AVP,
    SC_FLAG,
    R3,
    R2,
    R1,
    VOMS_POLICY_ID,
    IP_VERSION,
    SGSN_MCC_MNC,
    BIND,
    LOOKUP,
    RULE_BASE_NAME4,
    UDR_NOTI_URI,
    RULE_NAME
)
VALUES
(
    '${CDS_MIN}_S',
    '${CDS_MDN}',
    '82${CDS_MIN}',
    '82${CDS_MIN}',
    '2',
    'NoQoS_NoGBR_IMS',
    NULL,
    NULL,
    'N',
    '20221123',
    '184834',
    '20221124',
    '185659',
    '22445:15',
    '0',
    '2',
    '5',
    '2001:0d88:131f:0000::/64',
    'ltepgw47.skt.net',
    'skt.net',
    ' ',
    'P',
    '5',
    NULL,
    NULL,
    '2',
    'lte.sktelecom.com',
    'N',
    '000001',
    'L',
    'mp01.PCF-ROBOT',
    '11',
    '1',
    '1',
    NULL,
    NULL,
    '0',
    NULL,
    'L',
    NULL,
    NULL,
    '6',
    '45005',
    '${CDS_MDN}2001:0d88:131f:0000::/64',
    '${CDS_MDN}lte.sktelecom.com',
    NULL,
    'http://${TOOL_HOST}:${SBI_NOTI_PORT}/npcf-event-exposure/v1/nudr-gxp-notify/gxpa/01010105000-01-0-00-',
    NULL
);

-- @name: CDS 가입자 LTE 세션 (CDS_NEW_MDN — D3 번호변경 신규 번호)
SELECT COUNT(*) FROM T_SESSION_INFO WHERE MDN='${CDS_NEW_MDN}';
INSERT INTO T_SESSION_INFO
(
    SESSION_ID,
    MDN,
    MSISDN,
    IMSI,
    SESSION_STATUS,
    RULE_BASE_NAME1,
    RULE_BASE_NAME2,
    RULE_BASE_NAME3,
    CONTROLABLE_USER,
    OPEN_DATE,
    OPEN_TIME,
    UPDATE_DATE,
    UPDATE_TIME,
    LOCATION_ID,
    LOCATION_STATUS,
    CCR_TYPE,
    CCR_RECORD_NO,
    IP_ADDR,
    CLIENT_HOST,
    CLIENT_REALM,
    BEARER_ID,
    PROC_SYSTEM,
    QCI_LEVEL,
    DATA_USAGE_LEVEL,
    FEMTOCELL_CTRL,
    APN_TYPE,
    APN,
    RM_PROCESSING,
    SERVICE_ID,
    RAT_TYPE,
    DESTINATION_HOST,
    PRIORITY_LEVEL,
    PRE_EMPTION_CAPABILITY,
    PRE_EMPTION_VULNERABILITY,
    RULE_MADE_SOURCE,
    ZONE_INFO_AVP,
    SC_FLAG,
    R3,
    R2,
    R1,
    VOMS_POLICY_ID,
    IP_VERSION,
    SGSN_MCC_MNC,
    BIND,
    LOOKUP,
    RULE_BASE_NAME4,
    UDR_NOTI_URI,
    RULE_NAME
)
VALUES
(
    '${CDS_NEW_MIN}_S',
    '${CDS_NEW_MDN}',
    '82${CDS_NEW_MIN}',
    '82${CDS_NEW_MIN}',
    '2',
    'NoQoS_NoGBR_IMS',
    NULL,
    NULL,
    'N',
    '20221123',
    '184834',
    '20221124',
    '185659',
    '22445:15',
    '0',
    '2',
    '5',
    '2001:0d88:131f:0000::/64',
    'ltepgw47.skt.net',
    'skt.net',
    ' ',
    'P',
    '5',
    NULL,
    NULL,
    '2',
    'lte.sktelecom.com',
    'N',
    '000001',
    'L',
    'mp01.PCF-ROBOT',
    '11',
    '1',
    '1',
    NULL,
    NULL,
    '0',
    NULL,
    'L',
    NULL,
    NULL,
    '6',
    '45005',
    '${CDS_NEW_MDN}2001:0d88:131f:0000::/64',
    '${CDS_NEW_MDN}lte.sktelecom.com',
    NULL,
    'http://${TOOL_HOST}:${SBI_NOTI_PORT}/npcf-event-exposure/v1/nudr-gxp-notify/gxpa/01010105000-01-0-00-',
    NULL
);

-- NAG 세션 선등록용 가입자
SELECT COUNT(*) FROM T_SESSION_INFO WHERE MDN='${NAG_MDN}';
INSERT INTO T_SESSION_INFO
(
    SESSION_ID,
    MDN,
    MSISDN,
    IMSI,
    SESSION_STATUS,
    RULE_BASE_NAME1,
    RULE_BASE_NAME2,
    RULE_BASE_NAME3,
    CONTROLABLE_USER,
    OPEN_DATE,
    OPEN_TIME,
    UPDATE_DATE,
    UPDATE_TIME,
    LOCATION_ID,
    LOCATION_STATUS,
    CCR_TYPE,
    CCR_RECORD_NO,
    IP_ADDR,
    CLIENT_HOST,
    CLIENT_REALM,
    BEARER_ID,
    PROC_SYSTEM,
    QCI_LEVEL,
    DATA_USAGE_LEVEL,
    FEMTOCELL_CTRL,
    APN_TYPE,
    APN,
    RM_PROCESSING,
    SERVICE_ID,
    RAT_TYPE,
    DESTINATION_HOST,
    PRIORITY_LEVEL,
    PRE_EMPTION_CAPABILITY,
    PRE_EMPTION_VULNERABILITY,
    RULE_MADE_SOURCE,
    ZONE_INFO_AVP,
    SC_FLAG,
    R3,
    R2,
    R1,
    VOMS_POLICY_ID,
    IP_VERSION,
    SGSN_MCC_MNC,
    BIND,
    LOOKUP,
    RULE_BASE_NAME4,
    UDR_NOTI_URI,
    RULE_NAME
)
VALUES
(
    '${NAG_MIN}_S',
    '${NAG_MDN}',
    '82${NAG_MIN}',
    '82${NAG_MIN}',
    '2',
    'NoQoS_NoGBR_IMS',
    NULL,
    NULL,
    'N',
    '20221123',
    '184834',
    '20221124',
    '185659',
    '22445:15',
    '0',
    '2',
    '5',
    '2001:0d88:131f:0000::/64',
    'ltepgw47.skt.net',
    'skt.net',
    ' ',
    'P',
    '5',
    NULL,
    NULL,
    '2',
    'lte.sktelecom.com',
    'N',
    '000001',
    'L',
    'mp01.PCF-ROBOT',
    '11',
    '1',
    '1',
    NULL,
    '1111111111',
    '0',
    NULL,
    'L',
    NULL,
    NULL,
    '6',
    '45005',
    '${NAG_MDN}2001:0d88:131f:0000::/64',
    '${NAG_MDN}lte.sktelecom.com',
    NULL,
    'http://${TOOL_HOST}:${SBI_NOTI_PORT}/npcf-event-exposure/v1/nudr-gxp-notify/gxpa/01010105000-01-0-00-',
    NULL
);

SELECT COUNT(*) FROM T_5G_SUBS_PROFILE WHERE MDN='${NAG_MDN}';
INSERT INTO T_5G_SUBS_PROFILE
(
    MDN,
    MSISDN,
    MVNO,
    OCS,
    CREATE_TIME,
    UPDATE_TIME,
    UE_OS_VER,
    UE_MODEL,
    UE_CATEGORY_LTE,
    UE_CATEGORY_5G,
    UE_DEVICE_TYPE,
    PRODUCT_ID,
    BLACK_LIST,
    DESCRIPTION,
    UE_PRODUCT_TYPE
)
VALUES
(
    '${NAG_MDN}',
    '82${NAG_MIN}',
    '6',
    '0',
    TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDDHH24MISS'),
    TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDDHH24MISS'),
    '01',
    'SSTE',
    '06',
    '06',
    'S',
    'NA00003054',
    'N',
    'A1',
    '02'
);

SELECT COUNT(*) FROM T_5G_SUBS_SERVICE WHERE MDN='${NAG_MDN}' AND SVC_ID='DATA_USAGE_LEVEL';
INSERT INTO T_5G_SUBS_SERVICE
(
    MDN,
    SVC_ID,
    CNUM,
    SVC_TYPE,
    CREATE_TIME,
    UPDATE_TIME,
    UPDATE_TID,
    JOB_CODE,
    ACTIVE_TIME,
    EXPIRE_TIME,
    TIME_PERIOD_ID,
    "LIMIT",
    LIMIT_VALID_TIME,
    LIMIT_VALID_NOTI,
    DESCRIPTION
)
VALUES
(
    '${NAG_MDN}',
    'DATA_USAGE_LEVEL',
    '0',
    'N',
    TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDDHH24MISS'),
    TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDDHH24MISS'),
    NULL,
    'A1',
    TO_CHAR(CURRENT_TIMESTAMP - INTERVAL '1' DAY, 'YYYYMMDDHH24MISS'),
    '99991231000000',
    '0',
    '0',
    '99991231000000',
    'N',
    NULL
);

SELECT COUNT(*) FROM T_5G_SUBS_SERVICE WHERE MDN='${NAG_MDN}' AND SVC_ID='DATA_USAGE_LEVEL_2';
INSERT INTO T_5G_SUBS_SERVICE
(
    MDN,
    SVC_ID,
    CNUM,
    SVC_TYPE,
    CREATE_TIME,
    UPDATE_TIME,
    UPDATE_TID,
    JOB_CODE,
    ACTIVE_TIME,
    EXPIRE_TIME,
    TIME_PERIOD_ID,
    "LIMIT",
    LIMIT_VALID_TIME,
    LIMIT_VALID_NOTI,
    DESCRIPTION
)
VALUES
(
    '${NAG_MDN}',
    'DATA_USAGE_LEVEL_2',
    '0',
    'N',
    TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDDHH24MISS'),
    TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDDHH24MISS'),
    NULL,
    'A1',
    TO_CHAR(CURRENT_TIMESTAMP - INTERVAL '1' DAY, 'YYYYMMDDHH24MISS'),
    '99991231000000',
    '0',
    '0',
    '99991231000000',
    'N',
    NULL
);

SELECT COUNT(*) FROM T_5G_SUBS_SERVICE WHERE MDN='${NAG_MDN}' AND SVC_ID='ZONE_SVC_D';
INSERT INTO T_5G_SUBS_SERVICE
(
    MDN,
    SVC_ID,
    CNUM,
    SVC_TYPE,
    CREATE_TIME,
    UPDATE_TIME,
    UPDATE_TID,
    JOB_CODE,
    ACTIVE_TIME,
    EXPIRE_TIME,
    TIME_PERIOD_ID,
    "LIMIT",
    LIMIT_VALID_TIME,
    LIMIT_VALID_NOTI,
    DESCRIPTION
)
VALUES
(
    '${NAG_MDN}',
    'ZONE_SVC_D',
    '0',
    'D',
    TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDDHH24MISS'),
    TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDDHH24MISS'),
    NULL,
    '1X',
    TO_CHAR(CURRENT_TIMESTAMP - INTERVAL '1' DAY, 'YYYYMMDDHH24MISS'),
    '99991231000000',
    '0',
    '0',
    '99991231000000',
    'N',
    NULL
);

-- @name: NAG 세션 HFC 미가입자
SELECT COUNT(*) FROM T_SESSION_INFO WHERE MDN='${NAG_MDN_NO_HFC}';
INSERT INTO T_SESSION_INFO
(
    SESSION_ID,
    MDN,
    MSISDN,
    IMSI,
    SESSION_STATUS,
    RULE_BASE_NAME1,
    RULE_BASE_NAME2,
    RULE_BASE_NAME3,
    CONTROLABLE_USER,
    OPEN_DATE,
    OPEN_TIME,
    UPDATE_DATE,
    UPDATE_TIME,
    LOCATION_ID,
    LOCATION_STATUS,
    CCR_TYPE,
    CCR_RECORD_NO,
    IP_ADDR,
    CLIENT_HOST,
    CLIENT_REALM,
    BEARER_ID,
    PROC_SYSTEM,
    QCI_LEVEL,
    DATA_USAGE_LEVEL,
    FEMTOCELL_CTRL,
    APN_TYPE,
    APN,
    RM_PROCESSING,
    SERVICE_ID,
    RAT_TYPE,
    DESTINATION_HOST,
    PRIORITY_LEVEL,
    PRE_EMPTION_CAPABILITY,
    PRE_EMPTION_VULNERABILITY,
    RULE_MADE_SOURCE,
    ZONE_INFO_AVP,
    SC_FLAG,
    R3,
    R2,
    R1,
    VOMS_POLICY_ID,
    IP_VERSION,
    SGSN_MCC_MNC,
    BIND,
    LOOKUP,
    RULE_BASE_NAME4,
    UDR_NOTI_URI,
    RULE_NAME
)
VALUES
(
    '${NAG_MIN_NO_HFC}_S',
    '${NAG_MDN_NO_HFC}',
    '82${NAG_MIN_NO_HFC}',
    '82${NAG_MIN_NO_HFC}',
    '2',
    'NoQoS_NoGBR_IMS',
    NULL,
    NULL,
    'N',
    '20221123',
    '184834',
    '20221124',
    '185659',
    '22445:15',
    '0',
    '2',
    '5',
    '2001:0d88:131f:0000::/64',
    'ltepgw47.skt.net',
    'skt.net',
    ' ',
    'P',
    '5',
    NULL,
    NULL,
    '2',
    'lte.sktelecom.com',
    'N',
    '000001',
    'L',
    'mp01.PCF-ROBOT',
    '11',
    '1',
    '1',
    NULL,
    '1111111111',
    '0',
    NULL,
    'L',
    NULL,
    NULL,
    '6',
    '45005',
    '${NAG_MDN_NO_HFC}2001:0d88:131f:0000::/64',
    '${NAG_MDN_NO_HFC}lte.sktelecom.com',
    NULL,
    'http://${TOOL_HOST}:${SBI_NOTI_PORT}/npcf-event-exposure/v1/nudr-gxp-notify/gxpa/01010105000-01-0-00-',
    NULL
);

-- NWDAF 세션 선등록용 가입자
SELECT COUNT(*) FROM T_SESSION_INFO WHERE MDN='${NWDAF_MDN}';
INSERT INTO T_SESSION_INFO
(
    SESSION_ID,
    MDN,
    MSISDN,
    IMSI,
    SESSION_STATUS,
    RULE_BASE_NAME1,
    RULE_BASE_NAME2,
    RULE_BASE_NAME3,
    CONTROLABLE_USER,
    OPEN_DATE,
    OPEN_TIME,
    UPDATE_DATE,
    UPDATE_TIME,
    LOCATION_ID,
    LOCATION_STATUS,
    CCR_TYPE,
    CCR_RECORD_NO,
    IP_ADDR,
    CLIENT_HOST,
    CLIENT_REALM,
    BEARER_ID,
    PROC_SYSTEM,
    QCI_LEVEL,
    DATA_USAGE_LEVEL,
    FEMTOCELL_CTRL,
    APN_TYPE,
    APN,
    RM_PROCESSING,
    SERVICE_ID,
    RAT_TYPE,
    DESTINATION_HOST,
    PRIORITY_LEVEL,
    PRE_EMPTION_CAPABILITY,
    PRE_EMPTION_VULNERABILITY,
    RULE_MADE_SOURCE,
    ZONE_INFO_AVP,
    SC_FLAG,
    R3,
    R2,
    R1,
    VOMS_POLICY_ID,
    IP_VERSION,
    SGSN_MCC_MNC,
    BIND,
    LOOKUP,
    RULE_BASE_NAME4,
    UDR_NOTI_URI,
    RULE_NAME
)
VALUES
(
    '${NWDAF_MIN}_S',
    '${NWDAF_MDN}',
    '82${NWDAF_MIN}',
    '82${NWDAF_MIN}',
    '2',
    'NoQoS_NoGBR_IMS',
    NULL,
    NULL,
    'N',
    '20221123',
    '184654',
    '20221124',
    '185904',
    '22445:15',
    '0',
    '2',
    '8',
    '2001:0d88:131f:0000::/64',
    'ltepgw47.skt.net',
    'skt.net',
    ' ',
    'P',
    '5',
    NULL,
    NULL,
    '2',
    'lte.sktelecom.com',
    'N',
    '000001',
    'L',
    'mp01.PCF-ROBOT',
    '11',
    '1',
    '1',
    NULL,
    '1111111111',
    '0',
    NULL,
    'L',
    NULL,
    NULL,
    '6',
    '45005',
    '${NWDAF_MDN}:0d88:131f:0000::/64',
    '${NWDAF_MDN}lte.sktelecom.com',
    NULL,
    'http://${TOOL_HOST}:${SBI_NOTI_PORT}/npcf-event-exposure/v1/nudr-gxp-notify/gxpa/01010105000-01-0-00-',
    NULL
);

-- NWDAF 5G 세션 선등록용 가입자
SELECT COUNT(*) FROM T_SMF_SESSION_INFO WHERE MDN='${NWDAF_MDN_5G}';
INSERT INTO T_SMF_SESSION_INFO
(
    SM_POLICY_ID,
    SUPI,
    PDU_SESSION_ID,
    GPSI,
    MDN,
    IP_ADDR,
    DNN,
    S_NSSAI_SST,
    S_NSSAI_SD,
    LOC_ID,
    MCC_MNC,
    RAT_TYPE,
    OCS_SUBS_STATUS,
    IN_HTTP_HEADER,
    IN_HTTP_PAYLOAD,
    OUT_HTTP_HEADER,
    OUT_HTTP_PAYLOAD,
    RES_URI,
    NOTI_URI,
    UDR_NOTI_URI,
    TM_NOTI_URI,
    STATUS,
    SUBSCRIBE,
    AF_SUBSCRIBE,
    NODE_ID,
    PROC_ID,
    SMF_ID,
    CONN_ID,
    STREAM_ID,
    CREATE_TIME,
    UPDATE_TIME,
    DESCRIPTION
)
VALUES
(
    '${NWDAF_MDN_5G}-00-17931773150333063607370e3d0a3e0c3833',
    'imsi-4500521${NWDAF_MIN_5G}',
    5,
    'msisdn-82${NWDAF_MIN_5G}',
    '${NWDAF_MDN_5G}',
    '2001:02d8:2fa0:003b::/64',
    '5g.sktelecom.com',
    100,
    '000005',
    '45008-149842:27',
    '45005',
    'EUTRA',
    '1',
    'bl=nf-instance;nfinst=54804518-4191-46b3-955c-ac631f953ed8;nfset=setxyz.smfset.5gc.mcn012.mcc345',
    '{"sliceInfo":{"sst":100,"sd":"000005"},"smfId":"550e8400-e29b-41d4-a716-446655440002","userLocationInfo":{"eutraLocation":{"tai":{"plmnId":{"mcc":"450","mnc":"08"},"tac":"123a"},"ecgi":{"plmnId":{"mcc":"450","mnc":"08"},"eutraCellId":"249521B"}}},"pduSessionId":5,"dnn":"5g.sktelecom.com","servingNetwork":{"mcc":"450","mnc":"05"},"pduSessionType":"IPV6","accessType":"3GPP_ACCESS","ratType":"EUTRA"}',
    NULL,
    '{"pccRules":{"MELON_MEL_NoQoS":{"pccRuleId":"MELON_MEL_NoQoS"},"NoQoS_NoGBR":{"pccRuleId":"NoQoS_NoGBR"}},"zoneInfos":"0000000000","quotaNoti":0}',
    'http://${TOOL_HOST}:${SBI_NOTI_PORT}/npcf-smpolicycontrol/v1/sm-policies/01020103000-00-17931773150333063607370e3d0a3e0c3833',
    'http://${TOOL_HOST}:30011/npcf-smpolicycontrol/v1/smpc-status/200',
    'http://${TOOL_HOST}:${SBI_NOTI_PORT}/npcf-event-exposure/v1/nudr-smf-notify/01020103000-00-17931773150333063607370e3d0a3e0c3833',
    NULL,
    '3',
    NULL,
    NULL,
    'pcf01-mp02-app01',
    'SMF.MGR.01',
    '550e8400-e29b-41d4-a716-446655440002',
    0,
    1,
    SYSDATE,
    SYSDATE,
    '123A'
);


-- NWDAF

-- NWDAF 세션 선등록용 가입자
SELECT COUNT(*) FROM T_SESSION_INFO WHERE MDN='${UPM_MDN}';
INSERT INTO T_SESSION_INFO
(
    SESSION_ID,
    MDN,
    MSISDN,
    IMSI,
    SESSION_STATUS,
    RULE_BASE_NAME1,
    RULE_BASE_NAME2,
    RULE_BASE_NAME3,
    CONTROLABLE_USER,
    OPEN_DATE,
    OPEN_TIME,
    UPDATE_DATE,
    UPDATE_TIME,
    LOCATION_ID,
    LOCATION_STATUS,
    CCR_TYPE,
    CCR_RECORD_NO,
    IP_ADDR,
    CLIENT_HOST,
    CLIENT_REALM,
    BEARER_ID,
    PROC_SYSTEM,
    QCI_LEVEL,
    DATA_USAGE_LEVEL,
    FEMTOCELL_CTRL,
    APN_TYPE,
    APN,
    RM_PROCESSING,
    SERVICE_ID,
    RAT_TYPE,
    DESTINATION_HOST,
    PRIORITY_LEVEL,
    PRE_EMPTION_CAPABILITY,
    PRE_EMPTION_VULNERABILITY,
    RULE_MADE_SOURCE,
    ZONE_INFO_AVP,
    SC_FLAG,
    R3,
    R2,
    R1,
    VOMS_POLICY_ID,
    IP_VERSION,
    SGSN_MCC_MNC,
    BIND,
    LOOKUP,
    RULE_BASE_NAME4,
    UDR_NOTI_URI,
    RULE_NAME
)
VALUES
(
    '${UPM_MIN}_S',
    '${UPM_MDN}',
    '82${UPM_MIN}',
    '82${UPM_MIN}',
    '2',
    'NoQoS_NoGBR_IMS',
    NULL,
    NULL,
    'N',
    '20221123',
    '184654',
    '20221124',
    '185904',
    '22445:15',
    '0',
    '2',
    '8',
    '2001:0d88:131f:0000::/64',
    'ltepgw47.skt.net',
    'skt.net',
    ' ',
    'P',
    '5',
    NULL,
    NULL,
    '2',
    'lte.sktelecom.com',
    'N',
    '000001',
    'L',
    'mp01.PCF-ROBOT',
    '11',
    '1',
    '1',
    NULL,
    '1111111111',
    '0',
    NULL,
    'L',
    NULL,
    NULL,
    '6',
    '45005',
    '${UPM_MDN}:0d88:131f:0000::/64',
    '${UPM_MDN}lte.sktelecom.com',
    NULL,
    'http://${TOOL_HOST}:${SBI_NOTI_PORT}/npcf-event-exposure/v1/nudr-gxp-notify/gxpa/01010105000-01-0-00-',
    NULL
);

-- NWDAF 5G 세션 선등록용 가입자
SELECT COUNT(*) FROM T_SMF_SESSION_INFO WHERE MDN='01090050002';
INSERT INTO T_SMF_SESSION_INFO
(
    SM_POLICY_ID,
    SUPI,
    PDU_SESSION_ID,
    GPSI,
    MDN,
    IP_ADDR,
    DNN,
    S_NSSAI_SST,
    S_NSSAI_SD,
    LOC_ID,
    MCC_MNC,
    RAT_TYPE,
    OCS_SUBS_STATUS,
    IN_HTTP_HEADER,
    IN_HTTP_PAYLOAD,
    OUT_HTTP_HEADER,
    OUT_HTTP_PAYLOAD,
    RES_URI,
    NOTI_URI,
    UDR_NOTI_URI,
    TM_NOTI_URI,
    STATUS,
    SUBSCRIBE,
    AF_SUBSCRIBE,
    NODE_ID,
    PROC_ID,
    SMF_ID,
    CONN_ID,
    STREAM_ID,
    CREATE_TIME,
    UPDATE_TIME,
    DESCRIPTION
)
VALUES
(
    '01090050002-00-17931773150333063607370e3d0a3e0c3833',
    'imsi-45005211090050002',
    5,
    'msisdn-821090050002',
    '01090050002',
    '2001:02d8:2fa0:003b::/64',
    '5g.sktelecom.com',
    100,
    '000005',
    '45008-149842:27',
    '45005',
    'EUTRA',
    '1',
    'bl=nf-instance;nfinst=54804518-4191-46b3-955c-ac631f953ed8;nfset=setxyz.smfset.5gc.mcn012.mcc345',
    '{"sliceInfo":{"sst":100,"sd":"000005"},"smfId":"550e8400-e29b-41d4-a716-446655440002","userLocationInfo":{"eutraLocation":{"tai":{"plmnId":{"mcc":"450","mnc":"08"},"tac":"123a"},"ecgi":{"plmnId":{"mcc":"450","mnc":"08"},"eutraCellId":"249521B"}}},"pduSessionId":5,"dnn":"5g.sktelecom.com","servingNetwork":{"mcc":"450","mnc":"05"},"pduSessionType":"IPV6","accessType":"3GPP_ACCESS","ratType":"EUTRA"}',
    NULL,
    '{"pccRules":{"MELON_MEL_NoQoS":{"pccRuleId":"MELON_MEL_NoQoS"},"NoQoS_NoGBR":{"pccRuleId":"NoQoS_NoGBR"}},"zoneInfos":"0000000000","quotaNoti":0}',
    'http://${TOOL_HOST}:${SBI_NOTI_PORT}/npcf-smpolicycontrol/v1/sm-policies/01020103000-00-17931773150333063607370e3d0a3e0c3833',
    'http://${TOOL_HOST}:30011/npcf-smpolicycontrol/v1/smpc-status/200',
    'http://${TOOL_HOST}:${SBI_NOTI_PORT}/npcf-event-exposure/v1/nudr-smf-notify/01020103000-00-17931773150333063607370e3d0a3e0c3833',
    NULL,
    '3',
    NULL,
    NULL,
    'pcf01-mp02-app01',
    'SMF.MGR.01',
    '550e8400-e29b-41d4-a716-446655440002',
    0,
    1,
    SYSDATE,
    SYSDATE,
    '123A'
);


-- @name: PCF 접속 정보 ROBOT01
SELECT COUNT(*) FROM T_PCF_CONN_INFO WHERE PACKAGE_ID='01' AND PCF_NAME = 'ROBOT01';
INSERT INTO T_PCF_CONN_INFO
 (PACKAGE_ID, PCF_NAME, SBI_URL, FALLBACK_PCF, WRITE_DATE, WRITE_TIME)
VALUES('01',
    'ROBOT01',
    'http://${TOOL_HOST}:${SBI_NOTI_PORT}',
    'ROBOT02',
    TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD'),
    TO_CHAR(CURRENT_TIMESTAMP, 'HH24MISS')
);

-- @name: PCF 접속 정보 ROBOT02
SELECT COUNT(*) FROM T_PCF_CONN_INFO WHERE PACKAGE_ID='01' AND PCF_NAME = 'ROBOT02';
INSERT INTO T_PCF_CONN_INFO
 (PACKAGE_ID, PCF_NAME, SBI_URL, FALLBACK_PCF, WRITE_DATE, WRITE_TIME)
VALUES('01',
    'ROBOT02',
    'http://192.168.15.144:16101',
    'ROBOT01',
    TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD'),
    TO_CHAR(CURRENT_TIMESTAMP, 'HH24MISS')
);


SELECT COUNT(*) FROM T_BAROD_PEER_TABLE WHERE PACKAGE_ID = '01' AND BRANCH_NAME = '${UPM_BRANCH_NAME}' AND SYSTEM_ID = '${UPM_SYS_ID}' AND ACTIVE_YN = 'Y';
INSERT INTO T_BAROD_PEER_TABLE (PACKAGE_ID, PEER_TYPE, BRANCH_NAME, SYSTEM_ID, MAX_CONN_CNT, WRITE_DATE, WRITE_TIME, ACTIVE_YN)
VALUES('01', 
    'S', 
    '${UPM_BRANCH_NAME}', 
    '${UPM_SYS_ID}', 
    3, 
    TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD'),
    TO_CHAR(CURRENT_TIMESTAMP, 'HH24MISS'),
    'Y');


SELECT COUNT(*) FROM T_PCRF_CONN_LIST WHERE PCRF_NAME = 'PCF-ROBOT';
INSERT INTO T_PCRF_CONN_LIST
(
    PCRF_NAME,
    PRI_IP,
    PRI_PORT,
    PRI_VER,
    SEC_IP,
    SEC_PORT,
    SEC_VER,
    DESCRIPTION,
    PRI_OLD_NOTI_PROC,
    SEC_OLD_NOTI_PROC
)
VALUES
(
    'PCF-ROBOT',
    '${TOOL_HOST}',
    8990,
    'V2000',
    '192.168.15.144',
    8990,
    'V2000',
    'PCF-ROBOT config',
    NULL,
    NULL
);

-- FOR SDM
SELECT COUNT(*) FROM T_CDS_ORDER_HIST WHERE TRANSACTION_ID > (SELECT TID FROM T_CDS_ORDER_TID WHERE NAME = 'CDS201');
UPDATE T_CDS_ORDER_TID SET TID = (SELECT MAX(TRANSACTION_ID) FROM T_CDS_ORDER_HIST) WHERE NAME = 'CDS201' AND TID < (SELECT MAX(TRANSACTION_ID) FROM T_CDS_ORDER_HIST);

-- FOR BSUBS
SELECT COUNT(*) FROM T_BAROD_ORDER_HIST WHERE STATUS = 'N' AND MDN IN ('${CDS_MDN}', '${CDS_NEW_MDN}');
UPDATE T_BAROD_ORDER_HIST SET STATUS = 'Y' WHERE STATUS = 'N' AND MDN IN ('${CDS_MDN}', '${CDS_NEW_MDN}');
