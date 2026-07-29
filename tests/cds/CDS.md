# CDS 노드 스펙

규격: `CDS 표준 인터페이스 규격 Ver6.0`
파일: [`cds_tests.robot`](cds_tests.robot) · [`cds_keywords.robot`](../../resources/cds_keywords.robot) · [`cds_variables.robot`](../../resources/cds_variables.robot) · [`CdsHelper.py`](../../resources/CdsHelper.py)

## 접속 — 듀얼 소켓, Rchannel 이 먼저

| 항목 | 값 |
|---|---|
| 도구 역할 | CDS (능동 Connector) |
| 방향 | 도구 → PG.CDS |
| Schannel | `${CDS_SCH_PORT}` = 9200 |
| Rchannel | `${CDS_RCH_PORT}` = 9201 |
| 헤더 | **48-옥텟** 빅엔디안 |
| Body | 고정전문 |
| 타임아웃 | `${CDS_TIMEOUT}` = 10초 |

**접속 순서가 정해져 있다 — Rchannel 을 먼저 연다.**

| 순서 | 채널 | 송신 | 기대 |
|---|---|---|---|
| 1 | Rchannel 9201 | `0003` RchannelConnectionRequest | `0004` ACK |
| 2 | Schannel 9200 | `0001` SchannelConnectionRequest | `0002` ACK |

Teardown 은 역순이 아니라 Schannel→Rchannel 순으로 Release 를 보낸 뒤 닫는다.
Release 는 `Run Keyword And Ignore Error` 로 감싸 **PG 가 ACK 없이 끊어도 실패로 보지 않는다.**

포트와 `${CDS_DST_SYS_ID}`(PG.CDS SYSTEM_ID, 기본 `PG01`)는 `cds_variables.robot` 기본값이며
환경별로 다르면 `config/env/<env>.py` 에서 오버라이드한다.
업로드 전용 포트 `${CDS_UP_SCH_PORT}`(6100) / `${CDS_UP_RCH_PORT}`(6101) 도 정의돼 있다.

## 48-옥텟 헤더

```
Message ID / Transaction ID(date + seq) / System ID / Application ID
/ Continue Flag / Serial No / Data Size
```

정수 필드는 `htonl`/`htons` 로 **빅엔디안 송신**한다. `pack_cds_header` / `parse_cds_header` 참조.

8-옥텟 공통 헤더를 쓰지 않는 유일한 노드다(NWDAF 는 8옥텟이되 필드 구성이 다름).
소켓 자체는 `TcpHelper` 의 클라이언트 함수를 재사용한다.

## 메시지 ID

| ID | 이름 | ID | 이름 |
|---|---|---|---|
| `0001`/`0002` | SchannelConnectionRequest / ACK | `0017`/`0018` | CommandResult / ACK |
| `0003`/`0004` | RchannelConnectionRequest / ACK | `0025`/`0026` | UploadRequest / ACK |
| `0005`/`0006` | SchannelReleaseRequest / ACK | `0027`/`0028` | UploadResult / ACK |
| `0007`/`0008` | RchannelReleaseRequest / ACK | `0029`/`0030` | SubsDataRequest / ACK |
| `0013`/`0014` | ProcessStateRequest / ACK | `0031`/`0032` | SubsDataResult / ACK |
| `0015`/`0016` | CommandRequest / ACK | | |

Process State 값: `${CDS_PS_NORMAL}`=1 / `${CDS_PS_ABNORMAL}`=2, `uint16` 빅엔디안
(`pack_process_state` / `unpack_process_state`).

## CommandRequest(0015) Body — 327 옥텟 고정 레코드

업무 코드(`svc_code`) 와 무관하게 **항상 35필드 327B 전체를 보낸다.** 해당 코드가 쓰지
않는 필드는 공백으로 채운다. 채울 필드는 `CdsHelper._fill_command_fields(code)` 가 정한다.

**레이아웃은 실 A1 전문 샘플 327B + 규격표 35필드로 이중 검증됐다** — 추정이 아니다.
`_CMD_LAYOUT` 의 순서·길이를 바꾸면 `TC-CDS-012` 가 잡는다.

| off | 내부 필드명 | 규격명 (TCP / JSON) | Size | 값 | A1 샘플 |
|---|---|---|---|---|---|
| 0 | `svc_code` | JOB_CODE / opCode | 2 | 업무 코드 | `A1` |
| 2 | `mdn` | MDN / mdn | 12 | | `01020304053` |
| 14 | `new_mdn` | NEW_MDN | 12 | | |
| 26 | `min` | MIN / min | 10 | | `1020304053` |
| 36 | `new_min` | NEW_MIN | 10 | | |
| 46 | `prod_id` | PRODUCT_ID / produId | 10 | 상품 ID | `NA00003054` |
| 56 | `data_prod_id` | ADD_SVC / addSvc | 10 | 안심데이터상품ID | |
| 66 | `network` | NETWORK_ID / netId | 8 | WCDMA CDMA WiBro LTE 5G 플래그 | `10011` |
| 74 | `block_data_roaming_id` | ROADMING_STOP | 1 | 0=해당없음 1=가입/해지 | |
| 75 | `block_data_roaming_provider_id` | ROADMING_STOP_PROVIDER | 1 | 0/1 | |
| 76 | `allow_mvoip_yn` | MVOIP_APPLY_FG | 1 | 0/1 | |
| 77 | `tablet_yn` | TABLET_PC_YN / tabPcYn | 1 | 0=아니오 1=예 | `0` |
| 78 | `os_ver` | OS_VERSION / osVer | 2 | | `01` |
| 80 | `device_model` | TERMINAL_MODEL_CODE / termModelCode | 4 | | `SSTE` |
| 84 | `block_harmful_yn` | YOUNG_HARM_INFO_BLOCK | 1 | 청소년 유해정보 차단 | |
| 85 | `block_roaming_data_yn` | ROAMING_DATA | 1 | 0=허용 1=차단 2=VOMS제휴망 | |
| 86 | `block_roaming_mvoip_yn` | ROAMING_MVOIP | 1 | 0=허용 1=차단 | |
| 87 | `zone_code` | ZONE_CODE | 4 | 0000~9999 | |
| 91 | `ca` | CA | 1 | CA 단말 속성 3=L3 4=L4 | `7` |
| 92 | `aprf` | APRF / aprfTermAttri | 1 | 0=N/A 1=Support | `0` |
| 93 | `imsi` | IMSI | 15 | 450+05+국번호(5)+Serial(5) | `450057110046420` |
| 108 | `mvno` | MVNO_COMPANY / mvnoCompa | 1 | | |
| 109 | `limit` | LIMIT_SUBS_FG / limitSubsFlag | 1 | 한도형 가입자 | `0` |
| 110 | `qos_param` | ROAMING_QOS_PARAM | 1 | | |
| 111 | `start_time` | START_TIME | 12 | 쿠폰 종료 시간 / 시간프리 Start | |
| 123 | `coupon_type` | COUPON_TYPE | 2 | 쿠폰 권종 / 시간프리 End | |
| 125 | `coupon_pin` | COUPON_PIN | 11 | | |
| 136 | `ms_type` | MS_TYPE / catMsType | 1 | Cat.M1 단말 타입 | |
| 137 | `category_lte` | CATEGORY_LTE / lteCatgy | 2 | Default 10 | |
| 139 | `category_5g` | CATEGORY_5G / 5gCatgy | 2 | Default 10 | |
| 141 | `device_type` | DEVICE_TYPE / devceType | 1 | W=3G L=LTE N=NSA S=SA (Null=LTE) | `S` |
| 142 | `coupon_category` | COUPON_CATEGORY | 1 | T=Time P=Period | |
| 143 | `real_start_time` | REAL_START_TIME | 12 | 쿠폰 시작 시간 | |
| 155 | `addr` | ADDR | 170 | 주소 (**cp949**) | |
| 325 | `product_type` | PRODUCT_GEN_TYPE / produGenType | 2 | 01=3G 02=LTE 03=5G | `03` |

`addr` 만 한글이 들어가 cp949 로 인코딩한다(`_FIELD_ENCODING`). 나머지는 ASCII.

### A1(신규)이 쓰는 필드

규격 기준 17개 — `opCode` `mdn` `min` `produId` `addSvc`(**옵션**) `netId` `tabPcYn`
`osVer` `termModelCode` `aprfTermAttri` `mvnoCompa` `limitSubsFlag` `catMsType`
`lteCatgy` `5gCatgy` `devceType` `produGenType`. `addSvc` 외에는 전부 필수.

실 전문은 여기에 `CA` 와 `IMSI` 를 **더** 채워 보낸다(아래 함정 참조).

### 업무 코드

규격 `JOB_CODE` 허용 목록: `A1` `D3` `Z1` `G1` `C1` `Q1~Q9` `H1~H6`.

`cds_variables.robot` 은 레거시 도구에서 옮겨온 29개(`C2~C5` `D2` `D4` `D5` `E1` `E2`
`F1~F6` `I1~I3` `M1` `Y3~Y5` `Z2` `1X` `1Y`)를 더 정의하고 `_fill_command_fields` 도
이들을 처리한다. 그중 **`1X` `1Y` `I2` `I3` 는 위 규격 목록에 없지만** TC 로 유지 중이다
— 규격표가 이미 여러 곳 낡은 것이 확인돼 목록도 불완전할 수 있어서다. 실제 가부는
PG 응답(`SC`/`FA`)으로 판단한다.

## TC

현재 **활성 13건 / 주석 2건**. 태그: `cds` `connect` `process-state` `command` `release` `smoke` `validation`
(+ 주석 TC 에 `subs-data` `upload`)

`TC-CDS-012` 만 송신하지 않는 build 단위 TC 다. CDS 는 PG 가 Body 내용과 무관하게 `SC` 를
돌려주므로 **인코딩 회귀를 자동 판정하는 수단은 이 TC 가 유일하다.**

## 함정

- **Upload 는 PG 가 먼저 보낸다.** `Receive Upload Request` → `Send Upload Request Ack`
  → `Send Upload Result` 순. 해당 TC 는 PG 이벤트가 필요해 주석 처리돼 있다.
- Release 시 PG 가 ACK 없이 끊는 경우가 정상 동작으로 취급된다
  (`Send Release And Validate` 가 `Run Keyword And Return Status` 로 처리).

### 규격표와 실 전문이 어긋난다 — 실 전문이 기준이다

`CLAUDE.md` 의 *"규격서 표를 그대로 믿지 말 것"* 이 CDS 에서도 성립한다.
아래 6건은 **문서가 낡은 쪽**으로 판단해 실 전문을 채택했다.

| 필드 | 규격 문서 | 실 A1 전문 | 채택 |
|---|---|---|---|
| `netId`(8B) | WCDMA/CDMA/WiBro/LTE **4자리** + space(4) | `10011` + 공백3 → **5자리** | 실 전문 (5번째 = 5G/NR) |
| `CA`(1B) | `0~4` 만 열거 (3=L3, 4=L4) | **`7`** | 실 전문 (7 = L7 단말) |
| `CA` | A1 필드 목록에 **없음** | 값 있음 | 실 전문 — 채워 보낸다 |
| `IMSI` | A1 필드 목록에 **없음** | 값 있음 | 실 전문 — 채워 보낸다 |
| `mvnoCompa` `catMsType` | A1 **필수** | 공백 | 실 전문 — 공백 유지 |
| `lteCatgy` `5gCatgy` | A1 **필수**, Default `10` | 공백 | 실 전문 — 공백 유지 |

`CA`·`IMSI` 는 오프셋 오독이 아니다. 필드 위치는 코드와 무관한 절대 오프셋이고,
`zone_code`(87~91) 가 공백으로 끝난 직후 바이트가 `7`, 그 뒤 15B 가 정확히 SKT IMSI
형식(`450`+`05`+`71100`+`46420`)이다. 같은 샘플의 `devceType`=`S`(SA) /
`produGenType`=`03`(5G) 와도 "5G SA 가입자"로 일관된다.

바뀐 값은 `${CDS_A1_*}`(`cds_variables.robot`)에 있고, 골든 기준은
`CdsHelper.GOLDEN_A1_SAMPLE` / `GOLDEN_A1_FIELDS` 다. **골든은 환경 변수와 독립이며
`_CMD_LAYOUT` 으로 재생성하면 안 된다** — 그러면 대조 기준이 사라진다.
