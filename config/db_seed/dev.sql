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
-- ★ 값은 리터럴로 쓴다 — 바인드 파라미터(?)는 지원하지 않는다.
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

SELECT COUNT(*) FROM T_SESSION_INFO WHERE MDN='01090020001';
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
'1090020001_S',
'01090020001',
'821090020001',
'821090020001',
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
'mp01.lb01-pcf01',
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
'010900200012001:0d88:131f:0000::/64',
'01090020001lte.sktelecom.com',
NULL,
'http://192.168.15.142:16101/npcf-event-exposure/v1/nudr-gxp-notify/gxpa/01010105000-01-0-00-',
NULL
);


-- @name: PCF 접속 정보 ROBOT01
SELECT COUNT(*) FROM T_PCF_CONN_INFO WHERE PACKAGE_ID='01' AND PCF_NAME = 'ROBOT01';
INSERT INTO T_PCF_CONN_INFO
 (PACKAGE_ID, PCF_NAME, SBI_URL, FALLBACK_PCF, WRITE_DATE, WRITE_TIME)
VALUES('01',
    'ROBOT01',
    'http://192.168.15.142:16101',
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

