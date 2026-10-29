"""dev 환경 — 개발 (192.168.15.x 시험 PG).

`bash run_tests.sh nag` 처럼 **환경 인자가 없어도 이 파일을 읽는다** — IP 만 준
경우(`nag 192.168.1.1`)도 이 파일 + PG_HOST 덮기다. 그래서 여기 채운 값이 dev 의
실제 값이고, `resources/*_variables.robot` 은 그 아래 기본값이다.
git 에 들어 있다(다른 환경 파일은 .gitignore) — 원격 시험 호스트와 같은 값을 쓰기 위해서다.

이 파일의 역할은 두 가지다:
  1) dev 에서 실제로 쓰는 값(노드별 대상 번호, PDB, UPM FTP 등)을 쥔다
  2) 주석 목록이 **환경별로 덮을 수 있는 값의 전체 카탈로그** 역할을 한다

값을 덮으려면 주석을 풀고 값을 넣는다. 자세한 설명은 docs/ENVIRONMENTS.md.
"""

# ── 접속 ─────────────────────────────────────────────────────────
PG_HOST = '192.168.15.141'      # 모든 노드가 상속하는 기본 호스트

# 노드별 호스트가 갈릴 때만 개별 지정 (기본은 PG_HOST 상속)
# CDS_PG_HOST      = '...'
# LRS_CLIENT_HOST  = '...'
# NAG_PG_HOST      = '...'
# PCF_PG_HOST      = '...'
# UPM_PG_HOST      = '...'
# NWDAF_HOST       = '...'

# ── 노드별 포트 ──────────────────────────────────────────────────
# NAG_PG_PORT             = 8012
# PCF_PG_PORT             = 8011
# UPM_PG_PORT             = 10506
# NWDAF_PORT              = 10305
# CDS_SCH_PORT            = 9200      # PG_V2.cfg [CDS] O_PORT
# CDS_RCH_PORT            = 9201      # PG_V2.cfg [CDS] R_PORT
# LRS_CLIENT_DEFAULT_PORT = 10204
# LRS_SERVER_PORT         = 8890      # LRS-PCF 채널 (NAG 슈트도 사용)

# ── 노드별 식별자 ────────────────────────────────────────────────
# NAG_SYS_ID       = 'NAG01'
# NAG_BRANCH_NAME  = 'BR'
# PCF_SYS_ID       = 'LTE-PCRF01'
# PCF_BRANCH_NAME  = 'SS'
# UPM_SYS_ID       = 'UPMSIM'
# UPM_BRANCH_NAME  = 'DS'          # SS=성수, DS=둔산, BR=보라매
# LRS_SYS_ID       = 'PG01'
# LRS_BRANCH_NAME  = 'SS'
# CDS_DST_SYS_ID   = 'PG01'        # PG.CDS SYSTEM_ID
# CDS_SRC_SYS_ID   = 'SCSL00'      # 도구 자신의 System ID

# ── 노드별 대상 번호 (MDN) ───────────────────────────────────────
# 노드마다 시험에 쓰는 가입자 번호를 **여기 한 곳에서** 정한다.
# 기본값(*_variables.robot): NAG/PCF/LRS = ${SUBS_MDN_LTE}(01020300553),
#                            CDS/RTS     = 01090010001
# 주석으로 둔 노드는 기본값을 쓴다.
# NAG_MDN            = '01020300553'   # NAG Subs-Cellid 등 (${NAG_MDN_NORMAL})
# PCF_MDN            = '01020300553'   # PCF ZONE 알림 (${PCF_TEST_MDN}) — NAG 세션 선등록과 같은 번호
# LRS_MDN            = '01020300553'   # LRS SESSION-INFO 조회 + 8890 LTE 세션 (${LRS_SI_MDN}/${LRS_MDN_LTE})

CDS_MDN            = '01090020001'     # CDS 기본 가입자
CDS_NEW_MDN        = '01090020002'     # CDS D3 번호변경 신규 번호
RTS_MDN            = '01090020001'     # RTS 로밍 데이터 차단 (${RTS_TEST_MDN}) — 11자리 유지

NAG_MDN            = '01090020001'   # NAG Subs-Cellid 등 (${NAG_MDN_NORMAL})
PCF_MDN            = '01090020001'   # PCF ZONE 알림 (${PCF_TEST_MDN}) — NAG 세션 선등록과 같은 번호
LRS_MDN            = '01090020001'   # LRS SESSION-INFO 조회 + 8890 LTE 세션 (${LRS_SI_MDN}/${LRS_MDN_LTE})

# CDS 의 MIN / 세션 IMSI 는 위 MDN 에서 만든다 — MDN 만 바꾸면 따라온다.
#   MIN  = MDN 앞자리 0 을 뺀 10자리      (01090020001 → 1090020001)
#   IMSI = 45005(MCC+MNC) + MIN           (cds_variables.robot 의 규칙과 같다)
# 실환경 IMSI 가 이 규칙과 다르면 아래 줄을 지우고 값을 직접 쓴다.
CDS_MIN              = CDS_MDN[1:]
CDS_NEW_MIN          = CDS_NEW_MDN[1:]
CDS_SESSION_IMSI     = '45005' + CDS_MIN
CDS_SESSION_IMSI_NEW = '45005' + CDS_NEW_MIN



NAG_MOBILE_IP      = '2001:0d88:131f:0000::/64'   # NAG LTE 세션 IMSI 45005+1090020001


# ── 가입자 데이터 (공용 축) ──────────────────────────────────────
# 위 노드별 번호의 기본값이 상속하는 값. 노드별로 갈리면 위 *_MDN 을 쓴다.
# SUBS_MDN_LTE         = '01020300553'   # NAG/PCF/LRS/NWDAF 기본
# SUBS_MIN_LTE         = '1020300553'
# SUBS_MDN_5G          = '01093742433'
# SUBS_MIN_5G          = '1093742433'
# SUBS_MDN_NO_HFC      = '00000000000'   # HFC 미가입 → code 402
# SUBS_MDN_NO_SESSION  = '99999999999'   # 세션 없음 → code 403

# ── CDS 테스트 데이터 ────────────────────────────────────────────
# MDN/MIN 은 위 "노드별 대상 번호" 절에 있다.
# CDS_SUBS_MIN         = '01100001234'   # SubsData 요구 MIN (011+XXXX+YYYYY)
# CDS_PROD_ID          = 'NA00003479'
# CDS_LIMIT            = '0'             # limitSubsFlag

# ── CDS 단말·망 필드 (업무 코드 공용) ────────────────────────────
# A1 / Z1 / C1 / G1 / D3 이 같은 집합을 쓴다. 기본값은 전부 비어 있다(공백 전송).
# 여기 채우면 해당 필드를 선언한 모든 업무 코드에 반영된다.
# 필드 의미·규격표와의 차이는 tests/cds/CDS.md 참조.
# CDS_NETWORK          = '...'   # netId(8)         WCDMA CDMA WiBro LTE 5G 플래그
# CDS_TABLET_YN        = '...'   # tabPcYn(1)       0=아니오 1=예
# CDS_OS_VER           = '...'   # osVer(2)
# CDS_DEVICE_MODEL     = '...'   # termModelCode(4)
# CDS_CA               = '...'   # CA(1)            3=L3 4=L4
# CDS_APRF             = '...'   # aprfTermAttri(1) 0=N/A 1=Support
# CDS_IMSI             = '...'   # IMSI(15)         450+05+국번호(5)+Serial(5)
# CDS_MVNO             = '...'   # mvnoCompa(1)
# CDS_MS_TYPE          = '...'   # catMsType(1)     0=해당없음 1=Cat.M1 2=Cat.M1+HDV
# CDS_CATEGORY_LTE     = '...'   # lteCatgy(2)      규격 Default 10 (실 전문은 공백)
# CDS_CATEGORY_5G      = '...'   # 5gCatgy(2)       규격 Default 10 (실 전문은 공백)
# CDS_DEVICE_TYPE      = '...'   # devceType(1)     W=3G L=LTE N=NSA S=SA
# CDS_PROD_TYPE        = '...'   # produGenType(2)  01=3G 02=LTE 03=5G

# ── CDS PDB 조회 (전문 반영 판정, TC-CDS-002) ────────────────────
# 대상 DB 는 환경에 따라 골디락스 또는 알티베이스다.
# 접속 방식 3가지 중 **하나만** 채운다 (우선순위: CONNSTR > DSN > DRIVER/HOST/PORT).
# CDS_DB_KIND     = 'goldilocks'   # goldilocks | altibase — 세 방식 모두에서 필요
#
# 2) DSN 방식 (골디락스 권장) — odbc.ini / ODBC 데이터 원본 관리자에 등록된 이름
# CDS_DB_DSN      = 'PDB'
#
# 3) DSN-less — DSN 없이 직접 조립
# CDS_DB_DRIVER   = '/PG/goldilocks_home/lib/libgoldilockscs-ul64.so'
# CDS_DB_HOST     = '192.168.15.185'
# CDS_DB_PORT     = '22581'
# CDS_DB_NAME     = 'PDB'
#
# 공용
# CDS_DB_USER     = '...'          # odbc.ini 에 UID 가 있으면 DSN 방식에선 생략 가능
# CDS_DB_PASSWORD = '...'          # ★ 여기 적지 말고 환경변수 PG_CDS_DB_PASSWORD 권장
# CDS_DB_EXTRA    = '...'          # 덧붙일 키워드. 비우면 종류별 기본값(골디락스 CHARSET=UHC)
#
# 1) 최종 우회 — 이 값이 있으면 위 값은 전부 무시된다
# PDB_CONNSTR     = 'DSN=PDB;UID=pdb;PWD=...;'   # CDS·RTS 공용
PDB_CONNSTR       = 'DRIVER=/PG/goldilocks_home/lib/libgoldilockscs-ul64.so;HOST=192.168.15.185;PORT=22581;UID=pdb;PWD=pdb1234;CHARSET=UHC;'

# 두 번째 DB (선택) — CDS 세션 사전 적재만 두 DB 모두에 넣고 싶을 때(예: 골디락스+
# 알티베이스 이중화). 비우면(기본) 한 DB에만 넣는다. docs/nodes/CDS.md "두 번째 DB" 절.
# PDB_CONNSTR_2   = 'Server=...;PORT=...;DBName=...;UID=...;PWD=...;'   # 알티베이스 예시

# CDS_DB_TIMEOUT  = 10             # 접속·쿼리 타임아웃(초)
#
# 조회 동작 — 드라이버가 `?` 바인딩/와이드 문자를 못 받을 때 쓴다
# CDS_DB_BIND     = 'auto'         # auto | param | literal
# CDS_DB_ENCODING = 'utf-8'        # ★ 비우지 말 것 — 비우면 pyodbc 가 와이드(UTF-16)로
#                                  #   보내는데 두 DB 드라이버가 이를 못 받는 경우가 있다
# CDS_DB_WAIT     = '30s'          # 반영 대기 (SDM 폴링이 늦을 수 있다)
# CDS_DB_WAIT_INTERVAL = '2s'
# CDS_DB_TBL_PROFILE = 'T_5G_SUBS_PROFILE'
# CDS_DB_TBL_SERVICE = 'T_5G_SUBS_SERVICE'

# ── 망 데이터 ────────────────────────────────────────────────────
# SUBS_APN_LTE     = 'lte.sktelecom.com'
# SUBS_APN_5G      = '5g.sktelecom.com'
# SUBS_MOBILE_IP   = '2001:0d88:131f:0000::/64'
# NET_CELL_ID      = '123456:0'
# NET_PGW_IP       = '60.50.10.2'
# NET_SI_FROM_IP   = '112.172.129.68'    # PG 에 등록된 IP 여야 함 (아니면 403)

PG_SSH_USER        = 'pg'

# CDS / RTS — 대상 번호는 위 "노드별 대상 번호" 절로 옮겼다.
#CDS_NOTI_PORT      = 11301
#RDS_NOTI_PORT      = 11301

# UPM
UPM_SYS_ID         = 'UPM-R0'
UPM_BRANCH_NAME    = 'SS'
UPM_FTP_PORT       = 2222
UPM_FTP_USER       = 'test'
UPM_FTP_PASSWORD   = 'test123'
UPM_FTP_HOME_DIR    = '/home/kky/FTP'
UPM_FTP_REMOTE_PATH = '/UPM-R0'
UPM_FTP_USE_SFTP   = False   # or True

