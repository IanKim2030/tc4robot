# TC_CONVENTION — TC 작성 규칙

## 명명

```
TC-<IFACE>-NNN <한글 설명>
```

- `<IFACE>` : `NAG` `PCF` `LRS` `UPM` `CDS` `NWDAF` `RTS`
- `NNN` : 3자리 0 패딩
- 설명은 **한글**. 테스트명·Documentation·로그 메시지 모두 한글이 이 리포의 스타일이다.

**파일 순서 = 번호 순서.** 결번·중복 없이 001 부터 연속. TC 를 중간에 추가하면 그 뒤를 전부 밀고,
`[TC 번호 체계]` 문서 블록도 같이 고친다.

번호를 밀 때는 대역이 겹쳐 **단순 순차 치환이 충돌**한다(`005→007` 을 먼저 하면 기존 `007` 과 부딪힘).
파일 순서대로 한 번에 재부여하는 스크립트를 쓰거나 역순으로 치환할 것.

기능 대역(`1NN` = SubsData, `9NN` = 해제 같은 백자리 구분)은 쓰지 않는다.
전 슈트가 001 부터 연속이며, 기능 구분은 번호가 아니라 **섹션 구분선(`# ═══`)과
상단 `[TC 번호 체계]` 블록**으로 표현한다.

## 슈트 파일 구조

```robot
*** Settings ***
Documentation
...    <한 줄 요약>
...    [테스트 대상] / [Suite 정책] / [메시지 흐름] / [TC 번호 체계]

Resource    ../../resources/variables.robot
Resource    ../../resources/<iface>_variables.robot
Resource    ../../resources/common_keywords.robot
Resource    ../../resources/<iface>_keywords.robot

Suite Setup      Suite <IFACE> Connect
Suite Teardown   Suite <IFACE> Disconnect
Test Setup       Check <IFACE> Socket

*** Test Cases ***
```

상단 `[TC 번호 체계]` 블록은 대역별 요약을 담는다. **번호를 바꿨으면 여기도 반드시 고친다** —
이 블록이 실제와 어긋나는 게 가장 흔한 드리프트다.

## TC 템플릿

```robot
# ════════════════════════════════════════════════════════════════
# <그룹 제목> (규격 X.Y)
# ════════════════════════════════════════════════════════════════

TC-NWDAF-006 PGW STATUS Normal (0)
    [Documentation]    STATUS='0' (Normal)
    [Tags]    nwdaf    nwdaf_pgw    nwdaf_status
    Send Subscriber QoS Notification PGW    status=${NWDAF_STATUS_NORMAL}
```

- 값은 TC 에 리터럴로 쓰지 말고 `<iface>_variables.robot` 상수를 쓴다
- 그룹 구분선(`# ═══`)으로 기능 단위를 묶는다
- 반복되는 송수신은 `<iface>_keywords.robot` 키워드로 뺀다

## 태그

`--include` 로 걸러 쓴다. 아래는 **실측 목록**(추정 아님).

**공통** — `smoke` `negative` `validation` `lte` `5g`

`slow` — 전문 반영이 아니라 **PG 쪽 폴링을 기다리는** TC 에 붙인다. 현재 `TC-CDS-011`
(쿠폰 만료) 하나뿐이다. PG.RDS 가 예약 큐를 집어갈 때까지 최대 몇 분 걸리므로,
빠르게 돌릴 때는 `--exclude slow` 로 뺀다.

**노드별** — `nag` `pcf` `lrs` `upm` `cds` `nwdaf` `rts`

**기능별**

| 노드 | 태그 |
|---|---|
| NAG | `hello` `ping` `zion` `subs-zone` `subs-cellid` `adot` |
| PCF | `hello` `ping` `zion` `zone-inout` (+ `nag`) |
| LRS | `health-check` `session-info` |
| UPM | `hello` `ping` `cellinfo-noti` `subs-sync` `subs-info`* `subs-change`* `info-change`* |
| CDS | `connect` `process-state` `command` `db` `subs-data`* `upload`* `release` |
| NWDAF | `nwdaf_smoke` `nwdaf_pgw` `nwdaf_enb` `nwdaf_dpi` `nwdaf_5g` `nwdaf_status` `nwdaf_quick` `nwdaf_qos_policy` `nwdaf_support` `nwdaf_arpqci` `nwdaf_band` `nwdaf_cu` `nwdaf_network` `nwdaf_ratio` `nwdaf_usage` `nwdaf_common1` `nwdaf_common2` `nwdaf_msgid_wrap` `nwdaf_healthcheck` |
| RTS | `order` `roaming` `db` `noti` |

`*` = 주석 처리된 TC 에만 달려 있다. 해당 TC 를 살리면 함께 살아난다.

**NWDAF 만 `nwdaf_` 접두사 체계를 쓴다.** 다른 슈트는 접두사 없는 기능명을 쓴다.
새 TC 는 해당 슈트의 기존 방식을 따를 것 — 통일하려 들지 말 것.

## TC 비활성화

지우지 말고 `#` 주석 처리하되 **사유를 반드시 남긴다.**

```robot
#TC-NWDAF-042 COMMON2 NETWORK 2G (0)
#    [Documentation]    NETWORK=0 (2G).
#    ...    ※ 활성화 금지 — PG 수신부는 0x01/0x02/0x03 만 받고 그 외에는
#    ...       "Unknown NetType" 로그 후 return nfwError 로 전문을 버린다.
```

비활성화 사유 유형:
- **PG 측 실이벤트 필요** — 가입/해지/번호 변경 등이 있어야 동작 (UPM 수동 수신 TC)
- **PG 가 거부** — 규격에는 있으나 실제 구현이 받지 않는 값
- **운영 환경 미준비** — 실환경 데이터가 없어 통과 불가

섹션 헤더에도 `— TC-042 ~ 051 (현재 비활성)` 처럼 표기해 빈 블록의 이유를 알 수 있게 한다.
번호는 **재정렬하지 않는다.** 자리를 비워두어 주석만 풀면 연속이 복원되게 한다.

## 소켓 규칙 (절대)

소켓은 **슈트당 1회만** 열리고 모든 TC 가 Suite Variable 로 공유한다.
**TC 별 connect/disconnect 로직을 추가하지 말 것.**

`Test Setup` 의 `Check ... Socket` 이 닫힘을 감지하면 `Fatal Error` 로 슈트 전체를 중단한다.

## 무엇을 검증할 수 있는가 — 판정 한계

TC 를 쓰기 전에 **그 TC 가 실패할 수 있는지** 따져라. 실패할 수 없는 TC 는 가치가 없다.

| 흐름 | 자동 판정 가능 |
|---|---|
| 요청 → 응답 (NAG/PCF/UPM/CDS/LRS) | 응답 코드·헤더·Body 필드 전부 |
| 단방향 Notification (NWDAF) | **송신 성공과 소켓 생존뿐** |
| 응답은 오지만 내용이 무의미 (CDS `CommandResult`) | 응답만으로는 불가 → **PDB 조회로 보완** |

CDS 는 세 번째 경우다. `CommandResult`(0017)가 Body 내용과 무관하게 `SC` 를 주므로
"전문이 반영됐는가" 는 PDB 를 봐야 안다. `db` 태그가 붙은 TC 가 이 경로를 쓰며, 기준은
업무 코드마다 다르다 — 행이 **생겼는지**(A1·1X·I2), **사라졌는지**(1Y·I3·Z1), 수행
**전후 집계가 같은지**(C1·G1·D3). 코드별 SQL 과 그 기준이 놓치는 것은
[nodes/CDS.md](nodes/CDS.md) 의 PDB 판정 기준 절에 있다.

NWDAF Notification 은 PG 가 응답을 주지 않는다. 따라서 "PG 가 값을 올바로 해석했는가" 는
**도구 단독으로 판정 불가**이며, 인코딩이 틀려도 TC 는 통과한다. 실제로 eNB 섹션 8개 필드 중
7개가 틀린 상태로 모든 TC 가 PASS 했던 전례가 있다.

그래서 두 가지로 보완한다:

1. **build 단위 TC** — 송신하지 않고 조립된 바이트만 검증한다. 이게 유일하게 신뢰할 수 있는
   자동 회귀 검출 수단이므로 인코딩이 중요한 노드일수록 비중을 높인다.
   ```robot
   TC-NWDAF-035 DPI QOS_POLICY 고정길이 / TIMER 4B 인코딩
       [Tags]    nwdaf    nwdaf_dpi    validation
       ${dpi}=    Build dpiQoSCtrl
       ${timer}=    Tlv.Tlv Find    ${{ b''.join($dpi) }}    ${NWDAF_TAG_TIMER}
       Length Should Be    ${timer}    ${4}    msg=TIMER 4바이트 기대
   ```
2. **PG 로그 대조** — 송신 hexdump 가 `log.html` 에 남으므로 PG 덤프와 바이트 단위로 맞춘다.
   절차는 `pg-wire-encoding` 스킬 참조.

## 검증 절차

```bash
python -m robot --dryrun tests/<iface>/          # 키워드 해석 + TC 수 확인
python -m robot --dryrun --include <tag> tests/  # 태그 필터 동작 확인
bash run_tests.sh <iface>                        # 실 PG 대상
```

**`--dryrun` 은 Python 을 실행하지 않는다.** 키워드 이름만 해석하므로 인자 타입 변환 오류나
헬퍼 함수 버그를 잡지 못한다. 실제로 `${NONE}` 을 `bytes` 힌트 파라미터에 넘겨 죽는 버그가
드라이런을 통과한 전례가 있다. 송수신이 걸린 TC 는 가짜 PG 서버를 띄워 실행해 볼 것.

## 새 TC 를 추가할 때 순서

1. 대상 노드 스펙(`docs/nodes/<IFACE>.md`)에서 메시지 타입·인코딩 확인
2. 값 상수가 `<iface>_variables.robot` 에 있는지 확인, 없으면 추가
3. 번호 채번 → 뒤 TC 밀기 → `[TC 번호 체계]` 갱신
4. `--dryrun` 통과 확인
5. 인코딩이 새로 걸린다면 build 단위 TC 를 함께 추가
