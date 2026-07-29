---
name: pg-wire-encoding
description: PG 연동 전문의 바이트 인코딩을 PG 참조 소스(C++ 송신 시뮬레이터 / 수신부 CNWQosGateway.cpp 등)와 대조해 검증하거나 고칠 때 사용한다. 필드 폭·ASCII vs 바이너리·고정길이 패딩이 맞는지 확인할 때, PG 로그에 값이 이상하게 찍히거나 전문이 거부될 때, TLV/고정전문 헬퍼(TlvHelper.py, CdsHelper.py, TcpHelper.py)의 pack 함수를 수정할 때 적용된다.
---

# PG 전문 인코딩 대조

## 대전제

**규격서 표의 "numeric" 은 wire 형식을 알려주지 않는다.**
같은 "numeric" 이 1B 바이너리 / 1B ASCII / 4B BE int 로 제각각이다.
wire 형식은 **PG 소스로만 확정**된다. 소스 없이 추측하지 말 것.

실적: NWDAF eNB 섹션에서 **8개 필드 중 7개가 규격 표 기준으로 잘못 구현**돼 있었고,
모든 TC 는 PASS 하고 있었다.

## 1. 수신부 파싱 방식을 먼저 판별하라

이게 위험도를 결정한다.

**(A) TAG 미검사 고정 순서** — `p++; length = *p; p++;` 를 순서대로 반복
```c
p++; length = *p; p++;
stQosInfo.stENBQosInfo.cSupportType = *p;
p = p + length;
```
→ **필드 하나만 폭이 틀려도 그 뒤가 전부 밀린다.** 순서와 폭이 모두 정확해야 한다.

**(B) 태그 기반 `switch`**
```c
switch (*p) {
    case TAG_NET_TYPE1: ...
    case TAG_CONTROL_UNIT: ...
}
```
→ 순서에 자유롭다. 폭만 맞으면 된다.

**(C) 고정 횟수 루프**
```c
for (i = 0; i < 6; i++) { /* CATEGORY + QOS_POLICY */ }
```
→ **개수가 하드코딩**이다. 5쌍을 보내면 6번째가 뒤 필드를 먹는다.

## 2. 필드 폭 단서 — 헝가리안 표기

| 접두사 | 타입 | wire |
|---|---|---|
| `c...` | `char` | 1B (`= *p`) 또는 `char[]` (`memcpy(..., length)`) |
| `n...` | `int` | **4B BE** (`ntohl` 동반) |

```c
stQosInfo.cSupportType   = *p;                          → 1B
memcpy(&tmp, p, sizeof(int)); n = ntohl(tmp);           → 4B BE
memcpy(stQosInfo.cQCI, p, length);                      → 문자열
```

`ntohl` 은 **length 와 무관하게 항상 4바이트를 읽는다.** 1B 를 보내면 뒤 TLV 의
태그·길이 바이트까지 값으로 빨려 들어간다.

## 3. ASCII vs 바이너리 — 송신부로 구분

같은 파일 안에서 두 방식이 섞여 있다.

```c
temp = 0x02;
TLVGeneration(0x3A, 1, (void*)&temp, body);      // 바이너리 0x02
TLVGeneration(0x41, 1, (void*)"2", body);        // ASCII '2' = 0x32  ← 문자열 리터럴!
temp = 0x30;
TLVGeneration(0x0C, 1, (void*)&temp, body);      // 0x30 = ASCII '0'
```

`(void*)"2"` 는 문자열 리터럴 포인터라 첫 바이트가 `0x32` 다. `&temp` 와 헷갈리지 말 것.

**로그 포맷 지정자도 단서다** — `%c` 로 출력하면 ASCII, `%d` 면 파싱된 정수다.

## 4. 고정길이 + 패딩

```c
char strQosPolicy[LEN_QOS_POLICY+1] = { 0x00, };
sprintf(strQosPolicy, "QoS400K_NoGBR");
TLVGeneration(0x10, LEN_QOS_POLICY, strQosPolicy, body);   // NUL 패딩 고정길이
```

`pack_string_fixed(tag, val, length, pad=b'\x00')` 로 재현한다.
기본 `pad` 는 공백이므로 **NUL 패딩이면 명시**해야 한다.

**⚠ 매크로 실값을 모르면 크게 보내지 말 것.** 수신부에 길이 상한 검사가 없는 필드가 있다:
```c
if (length > 0) memcpy(cQosPolicy[i], p, length);   // 상한 없음 → 오버플로 가능
if (length > LEN_CELL_ID) memcpy(..., LEN_CELL_ID); // 이건 방어됨
```
상한이 없는데 실값보다 큰 길이를 보내면 **PG 측 버퍼 오버플로**다.
확인 전에는 가변 길이(문자열 실제 길이)로 보내는 게 항상 안전하다.

## 5. 수신부를 Python 으로 재현해 왕복 검증

가장 확실한 방법. **소비 바이트 수가 전체와 일치**하는지가 핵심 지표다.

```python
import sys, struct; sys.path.insert(0, 'resources')
import TlvHelper as T

def pg_parse(buf):
    """수신부 C 코드를 그대로 옮긴다 — TAG 미검사 고정 순서"""
    p = 0
    def rd():
        nonlocal p
        p += 1; ln = buf[p]; p += 1
        v = buf[p:p+ln]; p += ln
        return ln, v
    out = {}
    _, v = rd(); out['cQosHdr']      = v[0]                       # 1B
    _, v = rd(); out['cSupportType'] = chr(v[0])                  # 1B ASCII
    _, v = rd(); out['nArpQCIFlag']  = struct.unpack('>I', v[:4])[0]
    ...
    return out, p

buf = b''.join(T.build_enb_qos_ctrl(...))
got, used = pg_parse(buf)
print('소비', used, '/ 전체', len(buf), '->', '일치' if used == len(buf) else '★밀림★')
```

송신 시뮬레이터 바이트도 재현해 **바이트 단위로 diff** 한다:

```python
def tlv(tag, length, val):
    return bytes([tag, length]) + val[:length].ljust(length, b'\x00')
sim  = b''.join([tlv(0x3A, 1, bytes([0x10])), tlv(0x41, 1, b"2"), ...])
ours = b''.join(T.build_enb_qos_ctrl(...))
assert sim == ours, (T.hex_dump(sim), T.hex_dump(ours))
```

## 6. 실 PG 로그 대조

송신 hexdump 가 `log.html` 에 남는다(`[TX→PG] packet = ...`).
PG 의 `Header Info` / `BodyInfo` 덤프와 맞춘다.

**로그에 안 보인다고 파싱 실패는 아니다.** PG 의 `BodyInfo` printf 가 일부 섹션을
아예 출력 대상에 넣지 않은 경우가 있다(NWDAF 의 pcefQoSCtrl/eNB/DPI 가 그렇다).

**all-zero 헤더 덤프는 EOF 다.** PG 가 읽기에서 0 을 받고 zero-init 버퍼를 찍은 것 —
전문이 잘못된 게 아니라 상대가 연결을 닫았다는 뜻이다.

## 7. 값 범위도 소스로 확인

규격 표에 있어도 수신부가 거부하는 값이 있다:
```c
else { gLog->Write(LOG_CRITICAL, "Unknown NetType [0x%02x]", ...); return nfwError; }
```
NWDAF `NETWORK=0x00`(2G)이 이 경우다 — 규격 표에는 있으나 PG 가 전문을 버린다.
이런 값은 TC 를 만들되 **비활성화하고 사유를 남긴다.**

## 고쳤으면

- 노드 스펙(`tests/<iface>/<IFACE>.md`)의 인코딩 표를 **같이 고친다**
- build 단위 TC 를 추가해 회귀를 잡는다 (`--dryrun` 은 인코딩을 검증하지 못한다)
- 확정 못 한 값은 **한 곳만 고치면 되는 상수**로 빼고 TODO 와 근거를 남긴다
