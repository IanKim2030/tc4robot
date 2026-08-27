# -*- coding: utf-8 -*-
"""
PG → 도구 방향 HTTP/2(h2c) 알림 수신 서버.

PG 는 SA(5G) 가입자에 대해 PCF 로 **SBI Noti** 를 보낸다(docs/INTERFACES.md).
도구가 PCF 역할로 이 서버를 띄워 두면, CDS 전문이 유발한 알림이 실제로 도착했는지
전문·PDB 와 별개로 확인할 수 있다.

  · SNOTI → PCF : 가입자 정보 변경 통보
  · BSUBS → PCF : Cell List 전송 (1X 에서 UPM 0x08 응답 뒤에 나간다)

★ 왜 표준 라이브러리를 안 쓰는가
  3GPP SBI 는 HTTP/2 다. `http.server` 는 HTTP/1.1 전용이라 h2c 요청을 파싱조차
  하지 못한다(첫 프리페이스 `PRI * HTTP/2.0` 에서 400 을 준다). 그래서 sans-IO
  스택인 `h2` 패키지로 프레임을 직접 처리한다. 의존성: h2, hpack, hyperframe.

★ h2c 는 두 가지 진입 방식이 있는데 **prior knowledge** 만 지원한다.
  PG 가 HTTP/1.1 Upgrade(`Connection: Upgrade, HTTP2-Settings`)로 붙으면 여기서
  받지 못한다 — 그 경우 로그에 남기고 무시하므로, 알림이 안 잡히면 이걸 의심할 것.

수신한 요청은 메모리 큐에 쌓고, Robot 키워드가 꺼내 판정한다. 서버는 데몬 스레드로
돌며 accept 루프를 유지한다(여러 연결 동시 수용).
"""

import json
import socket
import threading
import time
import traceback

# HTTP/2 클라이언트 프리페이스. prior-knowledge h2c 는 이 24바이트로 시작한다.
_PREFACE = b'PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n'

# ── h2 는 지연 임포트한다 ──────────────────────────────────────────
# 최상단에서 import 하면 h2 가 없는 환경에서 **라이브러리 자체가 안 올라오고**,
# Robot 은 그 결과를 "No keyword with name 'Noti.Noti Server Start' found" 로
# 보고한다 — 진짜 원인(미설치)이 메시지에 전혀 안 드러난다. 실제로 그렇게 헤맨
# 전례가 있다(2026-08-12).
#
# 그래서 h2 는 **서버를 실제로 띄울 때만** 부른다. 덕분에
#   · ${SNOTI_PCF_NOTI}=False 면 h2 없이도 슈트가 그대로 돈다
#   · 켠 채로 h2 가 없으면 "pip install h2" 라고 정확히 알려주고 실패한다
# CdsDbHelper 가 pyodbc 를 지연 임포트하는 것과 같은 이유·같은 방식이다.
_h2 = None


def _load_h2():
    """h2 모듈 3종을 한 번만 임포트해 캐시한다. 없으면 안내 메시지로 실패."""
    global _h2
    if _h2 is None:
        try:
            import h2.config
            import h2.connection
            import h2.events
        except ImportError as e:
            raise RuntimeError(
                'PCF Noti 수신 서버에는 h2 패키지가 필요합니다 — pip install h2 '
                '(또는 pip install -r requirements.txt). '
                'Noti 검증이 필요 없으면 SNOTI_PCF_NOTI 를 False 로 두면 됩니다. '
                '원본 오류: %s' % e)
        _h2 = (h2.config, h2.connection, h2.events)
    return _h2


class _Request(dict):
    """수신 요청 1건. dict 라 Robot 에서 ${req}[path] 로 바로 꺼내 쓴다."""


class NotiServer(object):
    def __init__(self, port, host='0.0.0.0', backlog=16):
        self.host = host
        self.port = int(port)
        self.backlog = backlog
        self._srv = None
        self._thread = None
        self._stop = threading.Event()
        self._lock = threading.Lock()
        self._requests = []          # 수신 순서대로 쌓인다
        self._errors = []            # accept/파싱 중 난 예외 (진단용)
        # h2c 핸드셰이크까지 성공한 접속 이력. **요청과 별개로** 센다 —
        # PG 는 붙어만 두고 알림은 나중에 보내므로, "붙었는가" 와 "보냈는가" 는
        # 다른 사건이다. CDS 슈트는 전자를 기다렸다 시작한다.
        self._conns = []
        # ── 링크 감시 ────────────────────────────────────────────
        # 위 _conns 는 **누적 이력**이라 "지금 붙어 있는가" 를 답하지 못한다.
        # 슈트 중간에 PG 가 끊으면 이후 TC 는 알림을 못 받는데, 이력만 보면
        # "접속 1건 있음" 이라 멀쩡해 보인다 — 그래서 살아 있는 수를 따로 센다.
        self._live = 0               # 지금 열려 있는 h2c 연결 수
        self._events = []            # 상태 전이 (t, 'up'|'down', peer, live)
        self._samples = []           # 감시 스레드가 뜬 표본 (t, live)
        self._monitor = None
        self._monitor_stop = threading.Event()
        self._monitor_interval = 1.0

    # ── 수명 관리 ────────────────────────────────────────────────
    def start(self):
        _load_h2()      # 없으면 여기서 "pip install h2" 안내와 함께 실패한다
        self._srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._srv.bind((self.host, self.port))
        self._srv.listen(self.backlog)
        self._srv.settimeout(0.5)    # stop 이벤트를 주기적으로 보게 한다
        self._stop.clear()
        self._thread = threading.Thread(target=self._accept_loop, daemon=True)
        self._thread.start()
        self.start_monitor(self._monitor_interval)
        return self

    def start_monitor(self, interval=1.0):
        """링크 감시 스레드를 띄운다 (accept 루프와 **별개 스레드**).

        하는 일은 표본을 뜨는 것뿐이다 — 상태 전이(up/down) 자체는 _serve 가
        정확한 시점에 기록하므로, 이 스레드는 "그 사이에 계속 붙어 있었는가" 를
        답할 수 있게 주기 표본을 남긴다. 알림 수신을 방해하지 않는다(읽기만 한다).
        """
        if self._monitor is not None and self._monitor.is_alive():
            return self._monitor
        self._monitor_interval = float(interval)
        self._monitor_stop.clear()
        self._monitor = threading.Thread(target=self._monitor_loop, daemon=True)
        self._monitor.start()
        return self._monitor

    def _monitor_loop(self):
        # 표본은 무한정 쌓지 않는다 — 긴 슈트에서 메모리를 먹는다.
        limit = 7200
        while not self._monitor_stop.is_set():
            with self._lock:
                self._samples.append((time.time(), self._live))
                if len(self._samples) > limit:
                    del self._samples[:len(self._samples) - limit]
            self._monitor_stop.wait(self._monitor_interval)

    def stop(self):
        self._monitor_stop.set()
        if self._monitor is not None:
            self._monitor.join(timeout=3)
            self._monitor = None
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=3)
        if self._srv is not None:
            try:
                self._srv.close()
            except OSError:
                pass
        self._srv = None
        self._thread = None

    def is_running(self):
        return self._thread is not None and self._thread.is_alive()

    # ── 수신 루프 ────────────────────────────────────────────────
    def _accept_loop(self):
        while not self._stop.is_set():
            try:
                conn, addr = self._srv.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            threading.Thread(target=self._serve, args=(conn, addr),
                             daemon=True).start()

    def _serve(self, conn, addr):
        counted = False          # 이 연결을 살아 있는 것으로 셌는가
        try:
            conn.settimeout(30)
            first = self._recv_exact(conn, len(_PREFACE))
            if first != _PREFACE:
                # HTTP/1.1 Upgrade 나 평문 HTTP/1.1 요청. 지원하지 않는다.
                self._note_error(
                    'h2c prior-knowledge 가 아닌 접속 (%s) — 앞 24바이트=%r'
                    % (addr[0], first[:24]))
                return
            h2config, h2conn, _ = _load_h2()
            c = h2conn.H2Connection(
                config=h2config.H2Configuration(client_side=False))
            c.initiate_connection()
            conn.sendall(c.data_to_send())
            # 프리페이스가 맞고 서버 SETTINGS 까지 나갔다 = h2c 접속 성립.
            with self._lock:
                self._conns.append({'peer': addr[0], 'port': addr[1],
                                    'at': time.time()})
                self._live += 1
                self._events.append((time.time(), 'up', addr[0], self._live))
            counted = True
            streams = {}
            # ★ 위에서 프리페이스를 직접 읽어 버렸으므로 h2 에 **되돌려 줘야** 한다.
            #   h2 는 클라이언트 프리페이스를 자기가 receive_data 로 봐야 상태가 열린다.
            #   이걸 빠뜨리면 첫 SETTINGS 프레임에서 ProtocolError 로 끊긴다.
            for ev in c.receive_data(first):
                self._on_event(c, ev, streams, addr)
            out = c.data_to_send()
            if out:
                conn.sendall(out)
            while not self._stop.is_set():
                data = conn.recv(65535)
                if not data:
                    break
                for ev in c.receive_data(data):
                    self._on_event(c, ev, streams, addr)
                out = c.data_to_send()
                if out:
                    conn.sendall(out)
        except Exception:
            self._note_error(traceback.format_exc())
        finally:
            if counted:
                with self._lock:
                    self._live -= 1
                    self._events.append(
                        (time.time(), 'down', addr[0], self._live))
            try:
                conn.close()
            except OSError:
                pass

    def _recv_exact(self, conn, n):
        buf = b''
        while len(buf) < n:
            chunk = conn.recv(n - len(buf))
            if not chunk:
                break
            buf += chunk
        return buf

    def _on_event(self, c, ev, streams, addr):
        _, _, h2events = _load_h2()
        if isinstance(ev, h2events.RequestReceived):
            streams[ev.stream_id] = {
                'headers': {k.decode('utf-8', 'replace'): v.decode('utf-8', 'replace')
                            for k, v in ev.headers},
                'body': b'',
                'peer': addr[0],
            }
        elif isinstance(ev, h2events.DataReceived):
            st = streams.get(ev.stream_id)
            if st is not None:
                st['body'] += ev.data
            c.acknowledge_received_data(ev.flow_controlled_length, ev.stream_id)
        elif isinstance(ev, h2events.StreamEnded):
            st = streams.pop(ev.stream_id, None)
            if st is not None:
                self._complete(c, ev.stream_id, st)

    def _complete(self, c, stream_id, st):
        hdrs = st['headers']
        body = st['body']
        text = body.decode('utf-8', 'replace')
        try:
            parsed = json.loads(text) if text.strip() else None
        except ValueError:
            parsed = None
        req = _Request({
            'method': hdrs.get(':method', ''),
            'path': hdrs.get(':path', ''),
            'authority': hdrs.get(':authority', ''),
            'headers': hdrs,
            'body': text,
            'json': parsed,
            'peer': st['peer'],
            'received_at': time.time(),
        })
        with self._lock:
            self._requests.append(req)
        # 3GPP SBI 알림은 204 No Content 로 답하는 것이 일반적이다.
        # 본문을 주지 않으므로 END_STREAM 을 헤더에 실어 바로 닫는다.
        c.send_headers(stream_id,
                       [(':status', '204'), ('server', 'tc4robot-noti')],
                       end_stream=True)

    def _note_error(self, msg):
        with self._lock:
            self._errors.append(msg)

    # ── 조회 ─────────────────────────────────────────────────────
    def requests(self):
        with self._lock:
            return list(self._requests)

    def errors(self):
        with self._lock:
            return list(self._errors)

    def connections(self):
        return list(self._conns)

    def live(self):
        """지금 열려 있는 h2c 연결 수. 누적 이력(connections)과 다르다."""
        with self._lock:
            return self._live

    def events(self, since=None):
        """상태 전이 이력 [(t, 'up'|'down', peer, live), ...]."""
        with self._lock:
            evs = list(self._events)
        if since is not None:
            s = float(since)
            evs = [e for e in evs if e[0] >= s]
        return evs

    def link_report(self, since=None):
        """링크가 어떠했는지 한 덩어리로 — 알림이 안 왔을 때 원인을 가른다.

        since 를 주면 그 시각 이후만 본다(TC 시작 시각을 주면 "이 TC 동안" 이 된다).
        """
        with self._lock:
            live = self._live
            total = len(self._conns)
            samples = [x for x in self._samples
                       if since is None or x[0] >= float(since)]
        evs = self.events(since)
        downs = [e for e in evs if e[1] == 'down']
        ups = [e for e in evs if e[1] == 'up']
        # 표본 중 한 번이라도 0 이었으면 그 구간에 끊겨 있었다는 뜻이다.
        zero = [x for x in samples if x[1] == 0]
        return {
            'live': live,
            'connected': live > 0,
            'total_connects': total,
            'connects_since': len(ups),
            'disconnects_since': len(downs),
            'samples': len(samples),
            'samples_with_no_link': len(zero),
            'monitor_running': bool(self._monitor is not None
                                    and self._monitor.is_alive()),
        }

    def clear(self):
        """요청·오류만 비운다. **접속 이력은 남긴다** — TC 마다 초기화하면
        'PG 가 붙어 있다' 는 사실까지 지워지기 때문이다."""
        with self._lock:
            self._requests = []
            self._errors = []


# ══════════════════════════════════════════════════════════════════
# Robot 이 직접 부르는 함수들 (라이브러리 인터페이스)
# ══════════════════════════════════════════════════════════════════

def noti_server_start(port, host='0.0.0.0', monitor_interval=1):
    """h2c 수신 서버 기동 → 서버 핸들 반환. 핸들은 Suite Variable 로 들고 다닌다.

    accept 루프 스레드와 **별개로** 링크 감시 스레드가 같이 뜬다
    (monitor_interval 초마다 연결 수 표본을 뜬다).
    """
    srv = NotiServer(port, host)
    srv._monitor_interval = _seconds(monitor_interval)
    return srv.start()


def noti_server_stop(server):
    """서버 종료. None 이면 아무것도 하지 않는다."""
    if server is not None:
        server.stop()


def noti_server_is_running(server):
    return bool(server is not None and server.is_running())


def noti_clear(server):
    """쌓인 요청·오류를 비운다. TC 시작 전에 불러 이전 TC 의 알림과 섞이지 않게 한다."""
    if server is not None:
        server.clear()


def noti_count(server, path_contains=None, since=None):
    """수신 건수. path_contains / since 로 거를 수 있다."""
    return len(noti_list(server, path_contains, since))


def noti_list(server, path_contains=None, since=None):
    """
    수신 요청 목록(dict 리스트).

    path_contains : :path 부분 일치 필터
    since         : 이 epoch 시각 **이후**에 받은 것만. 경로를 모르는 상태에서
                    "이 동작 뒤에 온 알림"만 보고 싶을 때 쓴다. noti_now() 로 뜬다.
    """
    if server is None:
        return []
    reqs = server.requests()
    if path_contains:
        reqs = [r for r in reqs if path_contains in r['path']]
    if since is not None:
        s = float(since)
        reqs = [r for r in reqs if r['received_at'] >= s]
    return reqs


def noti_now():
    """현재 epoch 시각. noti_wait/noti_list 의 since 기준점으로 쓴다."""
    return time.time()


def noti_connection_count(server):
    """지금까지 성립한 h2c 접속 수. 요청 건수와 별개다."""
    return len(server.connections()) if server is not None else 0


def noti_connections(server):
    """h2c 접속 이력 목록 — dict(peer, port, at)."""
    return server.connections() if server is not None else []


def noti_wait_connection(server, timeout=60, poll=0.5):
    """
    PG 가 h2c 로 **붙을 때까지** 기다린다. 성립하면 접속 이력 목록을, 시간 안에
    안 붙으면 빈 리스트를 반환한다(실패 판정은 호출한 키워드가 한다).

    CDS 슈트가 Suite Setup 에서 이걸 기다렸다 시작한다 — 접속 전에 전문을 보내면
    PG 가 알림을 보낼 상대가 없어 그냥 흘러가기 때문이다.
    """
    deadline = time.time() + _seconds(timeout)
    step = _seconds(poll)
    while True:
        conns = noti_connections(server)
        if conns:
            return conns
        if time.time() >= deadline:
            return []
        time.sleep(step)


def noti_errors(server):
    """accept/파싱 중 난 오류 문자열 목록. 알림이 안 잡힐 때 여기부터 볼 것."""
    return server.errors() if server is not None else []


def noti_wait(server, timeout=30, path_contains=None, body_contains=None,
              since=None, poll=0.2):
    """
    조건에 맞는 요청이 **1건 이상** 들어올 때까지 기다렸다가 그 목록을 반환한다.
    시간 안에 안 오면 빈 리스트를 준다(실패 판정은 호출한 키워드가 한다).

    since 를 주면 그 시각 이후 도착분만 본다 — 경로를 모르는 상태에서 앞선
    알림을 다시 집어 "통과"해 버리는 것을 막는 유일한 수단이다.

    timeout/poll 은 초. Robot 이 '30s' 같은 문자열을 넘길 수 있어 숫자로 강제한다.
    """
    deadline = time.time() + _seconds(timeout)
    step = _seconds(poll)
    while True:
        found = noti_list(server, path_contains, since)
        if body_contains:
            found = [r for r in found if body_contains in r['body']]
        if found:
            return found
        if time.time() >= deadline:
            return []
        time.sleep(step)


def _seconds(v):
    """'30s' / '1.5' / 30 을 초(float)로."""
    if isinstance(v, (int, float)):
        return float(v)
    s = str(v).strip().lower()
    if s.endswith('ms'):
        return float(s[:-2]) / 1000.0
    if s.endswith('s'):
        return float(s[:-1])
    if s.endswith('m'):
        return float(s[:-1]) * 60.0
    return float(s)


# ── 링크 감시 (Robot 인터페이스) ───────────────────────────────────
#
# accept 루프와 별개로 도는 감시 스레드가 주기 표본을 남긴다. 목적은 하나 —
# **알림이 안 왔을 때 "전문이 문제였나, 링크가 끊겼었나" 를 가르는 것**이다.
# 누적 접속 이력(noti_connection_count)만으로는 답이 안 나온다. 슈트 중간에
# PG 가 끊어도 이력은 그대로 남아 "접속 있음" 으로 보이기 때문이다.

def noti_is_connected(server):
    """지금 PG 가 h2c 로 붙어 있는가 (열려 있는 연결 ≥ 1)."""
    return bool(server is not None and server.live() > 0)


def noti_live_count(server):
    """지금 열려 있는 h2c 연결 수."""
    return server.live() if server is not None else 0


def noti_link_report(server, since=None):
    """링크 상태 요약 dict. since 를 주면 그 시각 이후만 본다.

    TC 시작 시각을 since 로 주면 **그 TC 동안** 링크가 어땠는지가 나온다.
      connected            지금 붙어 있는가
      connects_since       그 사이 새로 붙은 횟수
      disconnects_since    그 사이 끊긴 횟수
      samples_with_no_link 감시 표본 중 연결이 0이었던 횟수
    """
    if server is None:
        return {'live': 0, 'connected': False, 'total_connects': 0,
                'connects_since': 0, 'disconnects_since': 0,
                'samples': 0, 'samples_with_no_link': 0,
                'monitor_running': False}
    return server.link_report(since)


def noti_monitor_running(server):
    """감시 스레드가 살아 있는가."""
    return bool(server is not None and server.link_report()['monitor_running'])
