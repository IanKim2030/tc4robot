"""dev 환경 — 개발 (192.168.15.x 시험 PG).

`bash run_tests.sh nag` 처럼 **환경 인자가 없어도 이 파일을 읽는다** — IP 만 준
경우(`nag 192.168.1.1`)도 이 파일 + PG_HOST 덮기다. 그래서 여기 채운 값이 dev 의
실제 값이고, `resources/*_variables.robot` 은 그 아래 기본값이다.
git 에 들어 있다(stg.py 도 들어 있다. prd.py · local.py 는 .gitignore) — 원격 시험 호스트와 같은 값을 쓰기 위해서다.

이 파일의 역할은 두 가지다:
  1) dev 에서 실제로 쓰는 값(노드별 대상 번호, PDB, UPM FTP 등)을 쥔다
  2) 주석 목록이 **환경별로 덮을 수 있는 값의 전체 카탈로그** 역할을 한다

값을 덮으려면 주석을 풀고 값을 넣는다. 자세한 설명은 docs/ENVIRONMENTS.md.
"""

# ── 접속 ─────────────────────────────────────────────────────────
PG_HOST = '192.168.15.141'      # 모든 노드가 상속하는 기본 호스트
TOOL_HOST = '192.168.15.142'    # 도구가 도는 호스트 — PG 가 되돌아 접속하는 주소(SBI Noti 등)

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
LRS_SERVER_HOST = TOOL_HOST           # LRS -> tool PCF listener (dev: 192.168.15.142)
LRS_SERVER_PORT = 8890                # LRS-PCF prerequisite for NAG; also used by LRS suite

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

# PG.CDS <-> CDS
CDS_MDN              = '01090020001'     # CDS 기본 가입자
CDS_NEW_MDN          = '01090020002'     # CDS D3 번호변경 신규 번호
CDS_MIN              = CDS_MDN[1:]
CDS_NEW_MIN          = CDS_NEW_MDN[1:]
CDS_SESSION_IMSI     = '45005' + CDS_MIN
CDS_SESSION_IMSI_NEW = '45005' + CDS_NEW_MIN


# PG.RDS <-> RDS
RTS_MDN              = CDS_MDN           # RTS 로밍 데이터 차단 (${RTS_TEST_MDN}) — 11자리 유지


# PG.BNOTI <-> NAG/PCF 
NAG_MDN              = '01090030001'   # HFC 가입
NAG_MDN_NO_HFC       = '01090030002'   # HFC 미가입
NAG_MDN_NO_SESSION   = '01090030003'   # 세션 없음
NAG_MIN              = NAG_MDN[1:]          # db_seed/dev.sql 세션 MSISDN 등에 쓴다
NAG_MIN_NO_HFC       = NAG_MDN_NO_HFC[1:]
NAG_MOBILE_IP        = '2001:0d88:131f:0000::/64'   # NAG LTE 세션 IMSI 45005+1090020001

PCF_MDN              = NAG_MDN         


# PG.LRS <-> LRS
LRS_MDN              = CDS_MDN        


# PG.CMS <-> CMSWEB (도구가 CMSWEB 서버) — tests/cms/SPEC.md
# 포트·세션키·타임아웃은 기동 시 PG_V2.cfg [CMS] 에서 읽는다(config/remote_settings.json).
# SFTP 계정은 PG.CMS 가 쓰는 CMSWEB 계정과 같아야 한다(dev: pg, 2026-11-24 사용자 확인).
# 비밀번호는 파일에 적지 않는다 — 다운로드(시뮬레이터 SFTP)용 PG_PWD_CMS_SFTP,
# SC 수신(업로드)용 PG_PWD_CMS_SFTP_UPLOAD, FIN 확인(도구 호스트 실제 sshd 의 pg)용 PG_PWD_CMS_FIN_SSH.
CMS_SFTP_USER      = 'pg'
# SC(NWDAF) 전달 수신 — PG 가 [CMS] SC_PATH 로 올리는 파일이 이 실제 디렉터리에 쌓인다(사용자 지정 2026-11-24).
# 비밀번호는 PG_PWD_CMS_SFTP_UPLOAD. 실제 sshd FIN 확인 비밀번호는 PG_PWD_CMS_FIN_SSH.
CMS_SC_UPLOAD_DIR  = '/home/kky/ROBOT/cmsweb/upload'


# PG.NWQOS <-> NWDAF
NWDAF_MDN            = '01090040001'          # NWDAF QoS 알림 (${NWDAF_TEST_MDN}) — NAG 세션 선등록과 같은 번호
NWDAF_MIN            = NWDAF_MDN[1:]
NWDAF_MDN_5G         = '01090040002'          # NWDAF 5G QoS 알림 (${NWDAF_TEST_MDN_5G}) — NAG 세션 선등록과 같은 번호
NWDAF_MIN_5G         = NWDAF_MDN_5G[1:]


# UPM
UPM_MDN              = '01090050001'   # UPM FTP 업로드용 가입자 번호
UPM_MIN              = UPM_MDN[1:]     # db_seed/dev.sql 세션 MSISDN 등에 쓴다

UPM_BRANCH_NAME      = 'SS'
UPM_FTP_PORT         = 2222
UPM_FTP_USER         = 'ncnalarm'
# UPM_FTP_PASSWORD 는 없앴다 — 환경변수 PG_PWD_UPM_FTP (PG 설정 PASSWORD_04 와 같은 값)
UPM_FTP_HOME_DIR     = '/home/kky/FTP'
#UPM_SYS_ID           = 'UPM-R1'    # FTP SYSID
#UPM_FTP_REMOTE_PATH  = '/UPM-R1'
#UPM_FTP_USE_SFTP     = False # or True
UPM_SYS_ID           = 'UPM-R2'    # SFTP SYSID
UPM_FTP_REMOTE_PATH  = '/UPM-R2'
UPM_FTP_USE_SFTP     = True   # or True


# ── 가입자 데이터 (공용 축) ──────────────────────────────────────
# 위 노드별 번호의 기본값이 상속하는 값. 노드별로 갈리면 위 *_MDN 을 쓴다.
# ★ 필수 — variables.robot 에 기본값이 없다(환경값은 환경 파일에만 둔다).
SUBS_MDN_LTE         = '01020300553'   # NAG/PCF/LRS/NWDAF 기본
SUBS_MIN_LTE         = '1020300553'
SUBS_MDN_5G          = '01093742433'
SUBS_MIN_5G          = '1093742433'
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

# ── PDB 접속 (CDS · RTS · 시드 공용) ─────────────────────────────
# 완성된 ODBC 문자열을 통째로 준다 — 도구가 조립하지 않는다(예전 CDS_DB_KIND/DSN/
# HOST/... 조립 변수는 제거됐다). 비밀번호(PWD)는 파일에 적지 않는다 — 환경변수 PG_PWD_PDB_1 (DB2 는 PG_PWD_PDB_2).
#   DSN 방식      : 'DSN=PDB;UID=pdb;'
#   DSN-less 방식 : 'DRIVER=<.so 절대경로>;HOST=...;PORT=...;UID=...;CHARSET=UHC;'
PDB_CONNSTR       = 'DRIVER=/PG/goldilocks_home/lib/libgoldilockscs-ul64.so;HOST=192.168.15.185;PORT=22581;UID=pdb;CHARSET=UHC;'   # PWD 는 환경변수 PG_PWD_PDB_1

# 두 번째 DB (선택) — CDS 세션 사전 적재만 두 DB 모두에 넣고 싶을 때(예: 골디락스+
# 알티베이스 이중화). 비우면(기본) 한 DB에만 넣는다. docs/shared/PDB.md "두 번째 DB" 절.
# PDB_CONNSTR_2   = 'Server=...;PORT=...;DBName=...;UID=...;'   # 알티베이스 예시 (PWD 는 PG_PWD_PDB_2)

# PDB_TIMEOUT     = 10             # 접속·쿼리 타임아웃(초) — 구 이름 CDS_DB_TIMEOUT 도 먹는다
#
# CDS 반영 판정
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

# DB 시드가 INSERT 를 1건 이상 했을 때 PG 서버에 SSH 로 차례로 실행할 명령
# (명령 사이 DB_SEED_SSH_GAP 대기). 비우면 건너뛴다 — variables.robot 참조.
# PG 가 새로 넣은 설정 행을 다시 읽게 app 을 내렸다 올린다.
# ★ dev 는 끔 — 명령 목록은 남겨 두었으니 한 번만 돌리려면 --db-seed-ssh 로 켠다.
DB_SEED_SSH_ENABLE = False
DB_SEED_SSH_CMDS   = ['stopMP app', 'startMP app']
DB_SEED_SSH_GAP    = '5s'

# CDS / RTS — 대상 번호는 위 "노드별 대상 번호" 절로 옮겼다.
#CDS_NOTI_PORT      = 11301
#RDS_NOTI_PORT      = 11301


