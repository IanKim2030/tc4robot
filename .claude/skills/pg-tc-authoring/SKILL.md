---
name: pg-tc-authoring
description: PG 연동 Robot Framework 테스트 슈트(NAG/PCF/LRS/UPM/CDS/NWDAF)에 TC를 추가·수정·비활성화하거나 TC 번호를 재정리할 때 사용한다. tests/*/\*_tests.robot 을 편집하거나, 새 인터페이스 값을 검증하는 테스트 케이스를 작성하거나, TC-<IFACE>-NNN 번호 체계를 손볼 때 적용된다.
---

# PG 테스트 슈트 TC 작성

## 먼저 읽을 것

1. [docs/TC_CONVENTION.md](../../../docs/TC_CONVENTION.md) — 명명·태그·템플릿·비활성화 규칙
2. `tests/<iface>/<IFACE>.md` — 대상 노드의 메시지 타입과 wire 인코딩
3. [docs/INTERFACES.md](../../../docs/INTERFACES.md) — opcode 충돌 여부 확인

## 절차

**1. 값 상수 확인**
TC 본문에 리터럴을 쓰지 말 것. `resources/<iface>_variables.robot` 에 상수가 있는지 보고
없으면 먼저 추가한다. NWDAF 는 TLV 태그가 `TlvHelper.py` 와 **이중 관리**되므로 양쪽을 고친다.

**2. 채번**
파일 순서 = 번호 순서. 중간 삽입 시 뒤를 전부 밀고 상단 `[TC 번호 체계]` 블록도 고친다.

번호 대역이 겹치면 순차 치환이 충돌한다(`005→007` 을 먼저 하면 기존 `007` 과 부딪힘).
파일 순서대로 한 번에 재부여한다:

```python
import re
path = 'tests/<iface>/<iface>_tests.robot'
lines = open(path, encoding='utf-8', newline='').read().split('\n')
pat = re.compile(r'^(#?)(TC-<IFACE>-)(\d+)(\s+.*)$')   # 주석 TC(#)도 함께
seq = 0
for i, l in enumerate(lines):
    m = pat.match(l)
    if m:
        seq += 1
        lines[i] = f'{m.group(1)}{m.group(2)}{seq:03d}{m.group(4)}'
open(path, 'w', encoding='utf-8', newline='').write('\n'.join(lines))
```

`newline=''` 로 열고 쓴다 — 안 그러면 줄바꿈이 통째로 바뀌어 diff 가 오염된다.

**3. 소켓 규칙**
TC 별 connect/disconnect 를 넣지 말 것. Suite Variable 로 공유되는 소켓을 쓴다.

**4. 판정 가능한지 따져라**
그 TC 가 **실패할 수 있는가?** 단방향 Notification(NWDAF)은 PG 응답이 없어
"송신 성공" 외에는 자동 판정이 불가능하다. 인코딩이 걸린 변경이면
**송신 없는 build 단위 TC 를 함께 추가**한다 — 이게 유일한 자동 회귀 검출 수단이다.

**5. 검증**

```bash
python -m robot --dryrun tests/<iface>/            # TC 수 + 키워드 해석
python -m robot --dryrun --include <tag> tests/    # 태그 필터
```

번호를 만졌으면 연속성을 확인한다:

```python
import re
nums = [int(m) for m in re.findall(r'^#?TC-<IFACE>-(\d+)', open(path, encoding='utf-8').read(), re.M)]
assert sorted(nums) == list(range(1, len(nums)+1)), '결번/중복'
```

## `--dryrun` 의 한계 — 반드시 알 것

**드라이런은 Python 을 실행하지 않는다.** 키워드 이름만 해석하므로:
- 헬퍼 함수의 런타임 버그
- Robot 의 **인자 타입 강제 변환** 실패

를 잡지 못한다. 실제로 `${NONE}` 을 `body: bytes` 힌트 파라미터에 넘겨 죽는 버그가
드라이런을 통과한 전례가 있다. Robot 은 타입 힌트를 보고 인자를 변환하므로,
`None` 을 받을 수 있는 파라미터에는 **타입 힌트를 붙이지 않는다.**

송수신이 걸린 TC 는 가짜 PG 를 띄워 실제로 돌려본다:

```bash
python fake_pg.py &                        # 헤더 읽고 응답 회신하는 최소 서버
python -m robot --variable <IFACE>_HOST:127.0.0.1 --variable <IFACE>_PORT:10999 \
       --include <tag> tests/<iface>/
```

## 비활성화

지우지 말고 `#` 주석 + **사유 명시**. 번호는 재정렬하지 않고 자리를 비워둬
주석만 풀면 연속이 복원되게 한다. 섹션 헤더에도 `— TC-0NN ~ 0NN (현재 비활성)` 을 남긴다.

## 한글 스타일

테스트명·Documentation·`msg=` 실패 메시지 모두 한글. 기존 톤을 그대로 따를 것.
