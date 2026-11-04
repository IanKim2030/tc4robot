"""stg 환경 — 검증계.

환경값(PG_HOST · TOOL_HOST · PDB_CONNSTR · SUBS_MDN/MIN_*)은 **반드시** 적는다 —
resources/variables.robot 에 기본값이 없다. 그 밖에는 resources/*_variables.robot
기본값과 **다른 값만** 적는다. 덮을 수 있는 값의 전체 목록은 config/env/dev.py 주석 참조.

TODO: 아래 값을 실제 stg 환경 값으로 교체할 것. 현재는 자리표시자다.
"""
PG_HOST = '60.30.133.120'      # TODO: stg PG IP
PG_SSH_USER = 'pg'
PDB_CONNSTR     = 'DSN=GOLD_GLOBAL_SS;UID=gold_ss;CHARSET=UHC;'   # PWD 는 환경변수 PG_PWD_PDB_1
TOOL_HOST = '60.30.133.121'    # 도구가 도는 호스트 — PG 가 되돌아 접속하는 주소 (CDS_SESSION_*_ADDR 가 이 값을 쓴다)

# DB 시드 INSERT 후 원격 명령 — stg 는 켬 (dev 는 끔). paramiko 필요(docs/shared/SSH.md).
DB_SEED_SSH_ENABLE = True
DB_SEED_SSH_CMDS   = ['stopMP app', 'startMP app']
DB_SEED_SSH_GAP    = '5s'


# CDS
CDS_MDN              = '01090020001'     # CDS 기본 가입자
CDS_NEW_MDN          = '01090020002'     # CDS D3 번호변경 신규 번호
CDS_MIN              = CDS_MDN[1:]
CDS_NEW_MIN          = CDS_NEW_MDN[1:]
CDS_SESSION_IMSI     = '45005' + CDS_MIN
CDS_SESSION_IMSI_NEW = '45005' + CDS_NEW_MIN
CDS_SCH_PORT         = 9300
CDS_RCH_PORT         = 9301
CDS_NOTI_PORT        = 11301

CDS_DST_SYS_ID       = 'PG001'
CDS_SESSION_PCF_ADDR = f'{TOOL_HOST}:{CDS_NOTI_PORT}'
CDS_SESSION_SMF_ADDR = f'{TOOL_HOST}:80'

CDS_SESSION_DB1 = False
CDS_SESSION_DB2 = False
CDS_DB_AUTOCOMMIT = True

# PG.RDS <-> RDS
RTS_MDN              = CDS_MDN           # RTS 로밍 데이터 차단 (${RTS_TEST_MDN}) — 11자리 유지


# PG.BNOTI <-> NAG/PCF
NAG_MDN              = '01090030001'   # HFC 가입
NAG_MDN_NO_HFC       = '01090030002'   # HFC 미가입
NAG_MDN_NO_SESSION   = '01090030003'   # 세션 없음
NAG_MOBILE_IP        = '2001:0d88:131f:0000::/64'   # NAG LTE 세션 IMSI 45005+1090020001

PCF_MDN              = NAG_MDN


# PG.LRS <-> LRS
LRS_MDN              = CDS_MDN


# PG.NWQOS <-> NWDAF
NWDAF_MDN            = '01090040001'          # NWDAF QoS 알림 (${NWDAF_TEST_MDN}) — NAG 세션 선등록과 같은 번호
NWDAF_MIN            = NWDAF_MDN[1:]
NWDAF_MDN_5G         = '01090040002'          # NWDAF 5G QoS 알림 (${NWDAF_TEST_MDN_5G}) — NAG 세션 선등록과 같은 번호
NWDAF_MIN_5G         = NWDAF_MDN_5G[1:]


# UPM
UPM_MDN              = '01090050001'   # UPM FTP 업로드용 가입자 번호

UPM_BRANCH_NAME      = 'SS'
UPM_FTP_PORT         = 2222
UPM_FTP_USER         = 'upm'
# UPM_FTP_PASSWORD 는 없앴다 — 환경변수 PG_PWD_UPM_FTP
UPM_FTP_HOME_DIR     = '/PG/USER/kky/FTP'
UPM_SYS_ID           = 'UPM-R2'
UPM_FTP_REMOTE_PATH  = '/UPM-R2'
UPM_FTP_USE_SFTP     = True # or True

#######################################################
#RTS
RTS_PG_PORT = 7001
RTS_NOTI_PORT = 11301

#NAG
SUBS_MDN_LTE = '01099010001'
SUBS_MIN_LTE = '1099010001'
SUBS_MDN_5G  = '01099010002'
SUBS_MIN_5G  = '1099010002'
LRS_ALLOWED_PEER_IPS = '100.100.150.31'

NAG_BRANCH_NAME = 'SS'

