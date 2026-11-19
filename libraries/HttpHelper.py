"""
HttpHelper.py  —  LRS 클라이언트 모드 HTTP/1.1 헬퍼
====================================================

SESSION-INFO-RETRIEVAL 연동 전용.
도구(ROBOT) 가 클라이언트로서 PG.LRS 에 HTTP POST 를 보내고 AIMS_RES 를 받는다.

  방향   : 도구 → PG.LRS  (POST /SESSION-INFO-RETRIEVAL HTTP/1.1)
  Body   : text/xml (요청 AIMS_REQ / 응답 AIMS_RES)
  포트   : Health Check 와 동일 포트(기본 10204) 공유

표준 라이브러리(http.client / xml.etree)만 사용하므로 추가 설치가 필요 없다.
요청마다 독립 연결(open→close)을 쓴다.
"""

import http.client
import re
import xml.etree.ElementTree as ET


def build_aims_req(req_id, pgw_group_id, client_ip,
                   min_='', mdn='', imsi=''):
    """
    SESSION-INFO-RETRIEVAL 요청 Body(AIMS_REQ XML) 생성.
    빈 식별자(MIN/MDN/IMSI)는 빈 태그로 그대로 둔다(규격 예시와 동일).
    """
    return (
        '<?xml version="1.0" encoding="UTF-8" ?>\r\n'
        '<AIMS_REQ>\r\n'
        f'<REQ_ID>{req_id}</REQ_ID>\r\n'
        f'<REQ_PGW_GROUP_ID>{pgw_group_id}</REQ_PGW_GROUP_ID>\r\n'
        f'<REQ_CLIENT_IP>{client_ip}</REQ_CLIENT_IP>\r\n'
        f'<REQ_CLIENT_ID_MIN>{min_}</REQ_CLIENT_ID_MIN>\r\n'
        f'<REQ_CLIENT_ID_MDN>{mdn}</REQ_CLIENT_ID_MDN>\r\n'
        f'<REQ_CLIENT_ID_IMSI>{imsi}</REQ_CLIENT_ID_IMSI>\r\n'
        '</AIMS_REQ>\r\n'
    )


def parse_xml_fields(xml_text):
    """
    AIMS_RES 등 단순 1-depth XML 을 {태그: 텍스트} dict 로 변환.
    ElementTree 로 파싱하고, 실패하면(손상/비표준) 정규식으로 폴백한다.
    'CLIENT_ID-MDN' 처럼 하이픈이 들어간 태그도 그대로 보존한다.
    """
    fields = {}
    if not xml_text or not xml_text.strip():
        return fields
    try:
        root = ET.fromstring(xml_text)
        for child in root:
            fields[child.tag] = (child.text or '').strip()
        return fields
    except ET.ParseError:
        for m in re.finditer(r'<([A-Za-z0-9_\-]+)>(.*?)</\1>', xml_text, re.S):
            fields[m.group(1)] = m.group(2).strip()
        return fields


def post_session_info(host, port, path, from_ip, xml_body, timeout=10):
    """
    SESSION-INFO-RETRIEVAL HTTP POST 송신 → 응답 수신/파싱.

    반환 dict:
      status   : HTTP 상태코드 (int, 예 200/404)
      reason   : Reason Phrase (str)
      headers  : 응답 헤더 (dict)
      body     : 응답 Body 원문 (str)
      fields   : 응답 XML 필드 (dict, AIMS_RES 파싱 결과)

    Content-Length 는 http.client 가 Body 바이트 길이로 자동 계산한다.
    """
    conn = http.client.HTTPConnection(host, int(port), timeout=float(timeout))
    headers = {
        'From': from_ip,
        'Accept': 'text/xml',
        'Content-Type': 'text/xml',
    }
    try:
        conn.request('POST', path, body=xml_body.encode('utf-8'), headers=headers)
        resp = conn.getresponse()
        raw = resp.read()
        body = raw.decode('utf-8', errors='replace')
        return {
            'status': resp.status,
            'reason': resp.reason,
            'headers': dict(resp.getheaders()),
            'body': body,
            'fields': parse_xml_fields(body),
        }
    finally:
        try:
            conn.close()
        except Exception:
            pass
