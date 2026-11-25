"""CmsHelper offline checks — wire format, PG parser compatibility, file naming. No PG/SFTP."""
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import threading
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import CmsHelper as C


def pg_get_value(text, key, flag):
    """Port of PG CParseJson::GetValue (0=string, 1=COLUMN_DATA, 2=first array item)."""
    i = text.find(key)
    if i < 0:
        return ''
    while i < len(text) and text[i] != ':':
        i += 1
    if flag == 0 and text[i + 1:i + 2] != '"':
        return ''
    if flag == 1 and text[i + 1:i + 4] != '["/':
        return ''
    if flag == 2 and text[i + 1:i + 3] != '["':
        return ''
    start = text.index('"', i) + 1
    return text[start:text.index('"', start)]


class FakeServer(object):
    def __init__(self, directory):
        self.directory = directory


class CmsHelperTests(unittest.TestCase):
    def test_header_is_cmd_plus_ten_digit_euckr_length(self):
        data = C.cms_pack('REG', {'sourceSessionKey': ['한글', 'K']})
        self.assertEqual(data[:3], b'REG')
        self.assertEqual(int(data[3:13]), len(data) - 13)
        self.assertEqual(data[13:14], b'\n')
        msg = C.cms_unpack(data)
        self.assertEqual(msg['body']['sourceSessionKey'], ['한글', 'K'])

    def test_unknown_command_and_truncated_body_are_rejected(self):
        with self.assertRaises(AssertionError):
            C.cms_pack('XXX', {})
        with self.assertRaises(AssertionError):
            C.cms_unpack(C.cms_pack('ANS', {'data': 'NTI_OK'})[:-2])

    def test_nti_is_readable_by_pg_parser(self):
        body = C.cms_nti('TRAP_X', '/CMS/ROBOT/TRAP_X_20261123120000_128.dat', 'CMS261123120000001',
                         'PGN', 'PGN99', date_time='2026-11-23 12:00:00')
        text = C.cms_unpack(C.cms_pack('NTI', body))['text']
        self.assertEqual(pg_get_value(text, 'messageType', 0), 'Report')
        self.assertEqual(pg_get_value(text, 'dateTime', 0), '2026-11-23 12:00:00')
        self.assertEqual(pg_get_value(text, 'serviceCode', 0), 'TRAP_X')
        self.assertEqual(pg_get_value(text, 'messageId', 0), 'CMS261123120000001')
        self.assertEqual(pg_get_value(text, 'sourceSessionKey', 2), 'CMS')
        self.assertEqual(pg_get_value(text, 'COLUMN_HEAD', 2), 'DATA')
        self.assertEqual(pg_get_value(text, 'COLUMN_DATA', 1), '/CMS/ROBOT/TRAP_X_20261123120000_128.dat')

    def test_omitted_field_is_missing_for_pg(self):
        body = C.cms_nti('TRAP_X', '/d/f.dat', 'CMS261123120000001', 'PGN', 'PGN99', omit='serviceCode')
        text = C.cms_unpack(C.cms_pack('NTI', body))['text']
        self.assertEqual(pg_get_value(text, 'serviceCode', 0), '')

    def test_message_id_is_18_chars(self):
        mid = C.cms_message_id('CMS')
        self.assertEqual(len(mid), 18)
        self.assertTrue(mid.startswith('CMS') and mid[3:].isdigit())

    def test_file_names_follow_pg_rename_and_fin_rules(self):
        name = C.cms_data_file_name('TRAP_ROBOT_ZONE_TEST', '20261123120000', 128)
        self.assertEqual(name, 'TRAP_ROBOT_ZONE_TEST_20261123120000_128.dat')
        self.assertEqual(C.cms_renamed_file_name(name), 'TRAP_ROBOT_ZONE_TEST_20261123120000.dat')
        plain = C.cms_data_file_name('TRAP_ROBOT_ZONE_TEST', '20261123120000')
        self.assertEqual(C.cms_renamed_file_name(plain), plain)
        self.assertEqual(C.cms_fin_prefix('TRAP_X', '2026-11-23 12:00:00', 'PGN', 'PGN99'),
                         'TRAP_X_20261123120000_PGNPGN99_')

    def test_cases_get_unique_names_and_paths(self):
        with tempfile.TemporaryDirectory() as root:
            server = FakeServer(root)
            first = C.cms_new_case(server, '/CMS/ROBOT', 'TRAP_X', 'PGN', 'PGN99', size=50)
            second = C.cms_new_case(server, '/CMS/ROBOT', 'TRAP_X', 'PGN', 'PGN99', size=50,
                                    declared_size=51)
            self.assertNotEqual(first['file_name'], second['file_name'])
            self.assertNotEqual(first['fin_prefix'], second['fin_prefix'])
            self.assertTrue(second['file_name'].endswith('_51.dat'))
            local = Path(root, 'CMS', 'ROBOT', first['file_name'])
            self.assertEqual(local.stat().st_size, 50)
            self.assertEqual(first['path'], '/CMS/ROBOT/' + first['file_name'])
            self.assertEqual(first['sc_data'], first['renamed'])
            self.assertEqual(first['sc_fin'], first['renamed'][:-len('.dat')] + '.FIN')

    def test_sample_file_is_copied_and_its_real_size_is_used(self):
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as data:
            sample = Path(data, 'TRAP_5G_EQP_INFO.dat')
            sample.write_bytes(b'a|b|c\r\n1|2|3\n' * 10)
            self.assertEqual(C.cms_sample_file(data, 'TRAP_5G_EQP_INFO'), str(sample))
            self.assertEqual(C.cms_sample_file(data, 'TRAP_LTE_EQP_INFO'), '')
            self.assertEqual(C.cms_sample_file('', 'TRAP_5G_EQP_INFO'), '')
            server = FakeServer(root)
            case = C.cms_new_case(server, '/CMS', 'TRAP_5G_EQP_INFO', 'PGN', 'PGN99',
                                  size=128, source=str(sample))
            real = sample.stat().st_size
            self.assertEqual(case['size'], real)
            self.assertEqual(case['source'], str(sample))
            self.assertTrue(case['file_name'].endswith('_%d.dat' % real))
            self.assertEqual(Path(root, 'CMS', case['file_name']).read_bytes(), sample.read_bytes())
            bad = C.cms_new_case(server, '/CMS', 'TRAP_5G_EQP_INFO', 'PGN', 'PGN99',
                                 source=str(sample), declared_offset='1')
            self.assertTrue(bad['file_name'].endswith('_%d.dat' % (real + 1)))
            self.assertEqual(bad['size'], real)
            gen = C.cms_new_case(server, '/CMS', 'TRAP_X', 'PGN', 'PGN99', size=40,
                                 source='', declared_offset='')
            self.assertEqual((gen['size'], gen['source']), (40, ''))
            self.assertTrue(gen['file_name'].endswith('_40.dat'))

    def test_zone_row_assertion_reports_every_mismatch(self):
        row = {'STATUS': 'F', 'REASON': 'Err ZoneCode', 'FILENAME': 'a.dat', 'FILESIZE': 0,
               'ZONE_CODE': 'NO', 'SERVICE_CODE': 'X'}
        C.cms_zone_row_should_match([row], 'F', 'Err ZoneCode', zone_code='NO', file_size=0)
        C.cms_zone_row_should_match([dict(row, STATUS='E', REASON='OK')], ['C', 'E'], 'OK')
        with self.assertRaisesRegex(AssertionError, 'STATUS.*REASON'):
            C.cms_zone_row_should_match([row], 'C', 'OK')
        with self.assertRaisesRegex(AssertionError, '행이 없습니다'):
            C.cms_zone_row_should_match([], 'C', 'OK')

    def test_recv_reads_one_message_over_a_socket(self):
        a, b = socket.socketpair()
        try:
            payload = C.cms_pack('HBC', {'sourceSessionKey': ['PGN', 'PGN99'], 'result': 'HBC_OK',
                                         'dateTime': '2026-11-23 12:00:00'})
            threading.Thread(target=lambda: [b.sendall(payload[:5]), b.sendall(payload[5:])]).start()
            msg = C.cms_expect(a, 'HBC', 2)
            C.cms_session_key_should_be(msg, 'PGN', 'PGN99')
            C.cms_date_time_should_be_valid(C.cms_field(msg, 'dateTime'))
            b.close()
            self.assertGreaterEqual(C.cms_wait_closed(a, 2), 0)
        finally:
            a.close()

    def test_sftp_start_refuses_privileged_port_and_missing_secret(self):
        with self.assertRaisesRegex(AssertionError, 'sshd'):
            C.cms_sftp_start(22, user='u', password='p')
        with self.assertRaisesRegex(AssertionError, 'CMS_SFTP_USER'):
            C.cms_sftp_start(2223, user='', password='p')


    def test_should_be_connected_peeks_without_consuming(self):
        a, b = socket.socketpair()
        try:
            a.settimeout(3)
            C.cms_should_be_connected(a)
            b.sendall(b'HBC')
            time_limit = 50
            while time_limit and not _readable(a):
                time_limit -= 1
            C.cms_should_be_connected(a)
            self.assertEqual(a.recv(3), b'HBC')
            self.assertEqual(a.gettimeout(), 3)
            b.close()
            with self.assertRaisesRegex(AssertionError, '이미'):
                C.cms_should_be_connected(a)
        finally:
            a.close()
        with self.assertRaises(AssertionError):
            C.cms_should_be_connected(None)


def _readable(sock):
    import select
    return bool(select.select([sock], [], [], 0.05)[0])


def _free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    port = s.getsockname()[1]
    s.close()
    return port


try:
    import paramiko  # noqa: F401
    HAVE_PARAMIKO = True
except ImportError:
    HAVE_PARAMIKO = False


@unittest.skipUnless(HAVE_PARAMIKO, 'paramiko 필요(142 venv)')
class CmsFinSshTests(unittest.TestCase):
    """FIN 확인 SFTP 클라이언트 — 로컬 paramiko SFTP 서버를 실제 sshd 대신 쓴다."""
    DIR = '/PG/FTP/CMS'

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.port = _free_port()
        self.server = C._load_sftp().SftpServer(self.port, '127.0.0.1', 'pg', 'fin-secret',
                                                directory=self.tmp.name, remote_path=self.DIR).start()
        self.local = Path(self.tmp.name, 'PG', 'FTP', 'CMS')
        env = mock.patch.dict(os.environ, {'PG_PWD_CMS_FIN_SSH': 'fin-secret'})
        env.start()
        self.addCleanup(env.stop)

    def tearDown(self):
        C.cms_sftp_stop(self.server)
        self.tmp.cleanup()

    def args(self, remote_dir=DIR):
        return ('127.0.0.1', self.port, 'pg', remote_dir)

    def test_check_accepts_writable_dir_and_leaves_no_probe(self):
        self.assertIn('쓰기 가능', C.cms_fin_ssh_check(*self.args()))
        self.assertEqual(list(self.local.iterdir()), [])
        with self.assertRaisesRegex(AssertionError, 'CmsMain'):
            C.cms_fin_ssh_check(*self.args('/CMS/ROBOT'))

    def test_wrong_or_missing_password_fails_clearly(self):
        with mock.patch.dict(os.environ, {'PG_PWD_CMS_FIN_SSH': 'wrong'}):
            with self.assertRaisesRegex(AssertionError, '로그인 실패'):
                C.cms_fin_ssh_check(*self.args())
        with mock.patch.dict(os.environ, {'PG_PWD_CMS_FIN_SSH': '', 'PG_PWD_CMS_SFTP': ''}):
            with self.assertRaisesRegex(AssertionError, 'PG_PWD_CMS_FIN_SSH'):
                C.cms_fin_ssh_check(*self.args())

    def test_fin_password_falls_back_to_download_password(self):
        # PG 는 FIN 을 CMSWEB 다운로드 계정으로 올린다 — FIN 전용 값이 없으면 다운로드 비밀번호를 쓴다
        with mock.patch.dict(os.environ, {'PG_PWD_CMS_FIN_SSH': '', 'PG_PWD_CMS_SFTP': 'fin-secret'}):
            self.assertIn('쓰기 가능', C.cms_fin_ssh_check(*self.args()))
        with mock.patch.dict(os.environ, {'PG_PWD_CMS_FIN_SSH': 'wrong', 'PG_PWD_CMS_SFTP': 'fin-secret'}):
            with self.assertRaisesRegex(AssertionError, '로그인 실패'):   # 따로 주면 그 값이 우선
                C.cms_fin_ssh_check(*self.args())

    def test_wait_quiet_and_cleanup_by_prefix(self):
        prefix = 'TRAP_X_20261124120000_PGNPGN99_'
        (self.local / 'OTHER_20261124120000_PGNPGN99_20261124120001.FIN').write_bytes(b'')
        with self.assertRaisesRegex(AssertionError, 'OTHER_'):
            C.cms_fin_ssh_wait(*self.args(), name_prefix=prefix, timeout=1, poll=0.2)
        C.cms_fin_ssh_should_stay_quiet(*self.args(), name_prefix=prefix, window=0.5, poll=0.2)
        fin = prefix + '20261124120005.FIN'
        (self.local / fin).write_bytes(b'')
        got = C.cms_fin_ssh_wait(*self.args(), name_prefix=prefix, timeout=3, poll=0.2)
        self.assertEqual((got['filename'], got['size']), (fin, 0))
        self.assertEqual(got['path'], self.DIR + '/' + fin)
        with self.assertRaisesRegex(AssertionError, '없어야'):
            C.cms_fin_ssh_should_stay_quiet(*self.args(), name_prefix=prefix, window=1, poll=0.2)
        result = C.cms_fin_ssh_cleanup(*self.args(), prefixes=[prefix])
        self.assertEqual(result, {'removed': [fin], 'failed': []})
        self.assertEqual([p.name for p in self.local.iterdir()],
                         ['OTHER_20261124120000_PGNPGN99_20261124120001.FIN'])
        self.assertEqual(C.cms_fin_ssh_cleanup(*self.args(), prefixes=[]), {'removed': [], 'failed': []})
        bad = C.cms_fin_ssh_cleanup(*self.args('/nope'), prefixes=[prefix])
        self.assertEqual(bad['removed'], [])
        self.assertTrue(bad['failed'])


@unittest.skipUnless(HAVE_PARAMIKO, 'paramiko 필요(142 venv)')
class CmsScSftpTests(unittest.TestCase):
    """SC 수신 SFTP — 가상 SC_PATH 를 실제 디렉터리로 마운트해 받는다(PG RunSFtpSC 흉내)."""
    SC_PATH = '/PG/FTP/CMS'

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.upload = os.path.join(self.tmp.name, 'cmsweb', 'upload')  # 없는 디렉터리 — 서버가 만든다
        self.port = _free_port()
        env = mock.patch.dict(os.environ, {'PG_PWD_CMS_SFTP_UPLOAD': 'sc-secret'})
        env.start()
        self.addCleanup(env.stop)
        self.server = C.cms_sc_sftp_start(self.port, '127.0.0.1', 'pg', self.SC_PATH, self.upload)

    def tearDown(self):
        C.cms_sftp_stop(self.server)
        self.tmp.cleanup()

    def _put(self, remote, data):
        import paramiko
        t = paramiko.Transport(('127.0.0.1', self.port))
        t.connect(username='pg', password='sc-secret')
        sftp = paramiko.SFTPClient.from_transport(t)
        try:
            with sftp.open(remote, 'w') as f:
                f.write(data)
        finally:
            t.close()

    def test_refuses_bad_settings(self):
        with self.assertRaisesRegex(AssertionError, 'sshd'):
            C.cms_sc_sftp_start(22, user='pg', sc_path='/x', upload_dir=self.upload)
        with self.assertRaisesRegex(AssertionError, '절대 경로'):
            C.cms_sc_sftp_start(2299, user='pg', sc_path='x', upload_dir=self.upload)
        with mock.patch.dict(os.environ, {'PG_PWD_CMS_SFTP_UPLOAD': ''}):
            with self.assertRaisesRegex(AssertionError, 'PG_PWD_CMS_SFTP_UPLOAD'):
                C.cms_sc_sftp_start(2299, user='pg', sc_path='/x', upload_dir=self.upload)

    def test_mount_maps_sc_path_to_upload_dir_and_wait_checks_both_files(self):
        self.assertTrue(os.path.isdir(self.upload))
        case = {'sc_data': 'TRAP_ROBOT_ZONE_SC_20261124120000.dat',
                'sc_fin': 'TRAP_ROBOT_ZONE_SC_20261124120000.FIN', 'size': 40}
        with self.assertRaisesRegex(AssertionError, 'SC 업로드가 다 오지'):
            C.cms_sc_wait_uploads(self.server, case, self.upload, timeout=0.5, poll=0.1)
        self._put(self.SC_PATH + '/' + case['sc_data'], b'x' * 40)
        self._put(self.SC_PATH + '/' + case['sc_fin'], b'')
        self._put('/elsewhere.txt', b'y')     # 마운트 밖은 가상 루트로 간다
        got = C.cms_sc_wait_uploads(self.server, case, self.upload, timeout=3, poll=0.1)
        self.assertEqual(got['data']['size'], 40)
        self.assertEqual(sorted(os.listdir(self.upload)), sorted([case['sc_data'], case['sc_fin']]))
        self.assertTrue(os.path.isfile(os.path.join(self.server.directory, 'elsewhere.txt')))
        with self.assertRaisesRegex(AssertionError, '크기'):
            C.cms_sc_wait_uploads(self.server, dict(case, size=41), self.upload, timeout=1, poll=0.1)
        keep = os.path.join(self.upload, 'OTHER.dat')
        Path(keep).write_bytes(b'')
        result = C.cms_sc_cleanup(self.upload, [case['sc_data'], case['sc_fin'], 'missing.dat', '../x'])
        self.assertEqual(sorted(result['removed']), sorted([case['sc_data'], case['sc_fin']]))
        self.assertEqual(len(result['failed']), 1)
        self.assertEqual(os.listdir(self.upload), ['OTHER.dat'])


class SftpServerMountDefaultTests(unittest.TestCase):
    def test_no_mounts_by_default(self):
        server = C._load_sftp().SftpServer(2299, directory=tempfile.gettempdir())
        self.assertEqual(server.mounts, [])


class CmsScZoneListTests(unittest.TestCase):
    """T_ZONE_LIST 표시 — PG deleteVersion 과 같은 조회 키, 판정 없이 값만 요약."""

    def test_lookup_code_strips_version_suffix_like_pg(self):
        self.assertEqual(C.cms_zone_lookup_code('TRAP_5G_EQP_INFO_V1'), 'TRAP_5G_EQP_INFO')
        self.assertEqual(C.cms_zone_lookup_code('TRAP_5G_EQP_INFO'), 'TRAP_5G_EQP_INFO')
        self.assertEqual(C.cms_zone_lookup_code('TRAP_LTE_EQP_INFO'), 'TRAP_LTE_EQP_INFO')
        self.assertEqual(C.cms_zone_lookup_code('TRAP_LTE_EQP_INFO_CO'), 'TRAP_LTE_EQP_INFO_CO')
        self.assertEqual(C.cms_zone_lookup_code('NOUNDERSCORE'), 'NOUNDERSCORE')

    def test_summary_found_row(self):
        got = C.cms_zone_summary('TRAP_LTE_EQP_INFO',
                                 [{'SC_FTP_YN': 'Y', 'NOTI_YN': 'Y', 'ZONE_CODE': 'ZN000123'}])
        self.assertTrue(got['found'])
        self.assertEqual(got['sc_ftp_yn'], 'Y')
        self.assertIn('SC_FTP_YN=Y NOTI_YN=Y ZONE_CODE=ZN000123', got['text'])

    def test_summary_missing_row_shows_lookup_key(self):
        got = C.cms_zone_summary('TRAP_5G_EQP_INFO_V1', [])
        self.assertFalse(got['found'])
        self.assertEqual(got['sc_ftp_yn'], '')
        self.assertIn('TRAP_5G_EQP_INFO_V1(조회 키 TRAP_5G_EQP_INFO)', got['text'])
        self.assertIn('행 없음', got['text'])

    def test_summary_joins_multiple_rows_and_none(self):
        got = C.cms_zone_summary('X', [{'SC_FTP_YN': 'Y'}, {'SC_FTP_YN': None}])
        self.assertEqual(got['sc_ftp_yn'], 'Y,')


class CmsProtocolSelectionTests(unittest.TestCase):
    def test_same_rule_as_pg_first_char_capital_n_means_ftp(self):
        # CCMSEnv::ReadConfig — Sftp_CmsWeb[0] == 'N' → FTP, 그 밖(빈 값·'n' 포함) → SFTP
        for flag, proto in [('Y', 'SFTP'), ('N', 'FTP'), ('NO', 'FTP'), ('', 'SFTP'),
                            (None, 'SFTP'), ('n', 'SFTP'), ('y', 'SFTP')]:
            self.assertEqual(C.cms_file_protocol(flag), proto, flag)

    def test_test_file_has_no_newline_so_ascii_mode_keeps_size(self):
        with tempfile.TemporaryDirectory() as root:
            path = C.cms_sftp_put(FakeServer(root), '/PG/FTP/CMS', 'a.dat', 300)
            data = Path(root, 'PG', 'FTP', 'CMS', 'a.dat').read_bytes()
        self.assertEqual(path, '/PG/FTP/CMS/a.dat')
        self.assertEqual(len(data), 300)
        self.assertNotIn(b'\n', data)
        self.assertNotIn(b'\r', data)


try:
    import pyftpdlib  # noqa: F401
    HAVE_PYFTPDLIB = True
except ImportError:
    HAVE_PYFTPDLIB = False


@unittest.skipUnless(HAVE_PYFTPDLIB, 'pyftpdlib 필요(142 venv)')
class CmsFtpTests(unittest.TestCase):
    """CMSWEB_SFTP=N — PG RunFtpCMS 흉내: TYPE A → CWD → 목록 → RETR → 같은 디렉터리에 FIN STOR."""
    DIR = '/PG/FTP/CMS'

    def setUp(self):
        self.port = _free_port()
        env = mock.patch.dict(os.environ, {'PG_PWD_CMS_SFTP': 'dl-secret', 'PG_PWD_CMS_SFTP_UPLOAD': 'sc-secret'})
        env.start()
        self.addCleanup(env.stop)
        self.server = C.cms_ftp_start(self.port, '127.0.0.1', 'pg', self.DIR)

    def tearDown(self):
        C.cms_sftp_stop(self.server)

    def _login(self, port, password):
        import ftplib
        ftp = ftplib.FTP()
        ftp.connect('127.0.0.1', port, timeout=5)
        ftp.login('pg', password)
        ftp.voidcmd('TYPE A')
        return ftp

    @staticmethod
    def _raw(ftp, cmd, data=None):
        # TYPE A 그대로 바이트를 주고받는다(ftplib retr/storlines 는 줄 끝을 바꾼다) — PG NLCFTP 흉내
        conn = ftp.transfercmd(cmd)
        out = b''
        try:
            if data is None:
                while True:
                    chunk = conn.recv(8192)
                    if not chunk:
                        break
                    out += chunk
            else:
                conn.sendall(data)
        finally:
            conn.close()
        ftp.voidresp()
        return out

    def test_pg_style_get_and_fin_put_are_recorded(self):
        case_path = C.cms_sftp_put(self.server, self.DIR, 'SVC_20261124120000_200.dat', 200)
        ftp = self._login(self.port, 'dl-secret')
        try:
            ftp.cwd(self.DIR)
            self.assertIn('SVC_20261124120000_200.dat', ftp.nlst('SVC_20261124120000_200.dat')[0])
            got = bytearray()
            ftp.retrbinary('RETR SVC_20261124120000_200.dat', got.extend)   # TYPE 는 RETR 전에 다시 I 가 된다
            ftp.voidcmd('TYPE A')
            ascii_data = self._raw(ftp, 'RETR SVC_20261124120000_200.dat')
            self._raw(ftp, 'STOR SVC_20261124120000_PGNPGN99_20261124120001.FIN', b'')
        finally:
            ftp.quit()
        self.assertEqual(case_path, self.DIR + '/SVC_20261124120000_200.dat')
        self.assertEqual(len(got), 200)
        self.assertEqual(len(ascii_data), 200)          # ASCII 모드여도 크기가 그대로
        C.cms_sftp_wait_download(self.server, 'SVC_20261124120000_200.dat', timeout=3, poll=0.1)
        fin = C.cms_sftp_wait_upload(self.server, 'SVC_20261124120000_PGNPGN99_', timeout=3, poll=0.1)
        self.assertEqual(fin['size'], 0)
        self.assertEqual(os.path.dirname(fin['path']),
                         os.path.join(self.server.directory, 'PG', 'FTP', 'CMS'))
        C.cms_sftp_clear(self.server)
        self.assertEqual((C.cms_sftp_downloads(self.server), C.cms_sftp_uploads(self.server)), ([], []))

    def test_wrong_password_is_refused(self):
        import ftplib
        with self.assertRaises(ftplib.error_perm):
            self._login(self.port, 'wrong')

    def test_stop_removes_owned_temp_root(self):
        root = self.server.directory
        self.assertTrue(os.path.basename(root).startswith('cms_files_'))
        C.cms_sftp_stop(self.server)
        self.assertFalse(os.path.exists(root))

    def test_port_in_use_and_missing_secret_fail_clearly(self):
        with self.assertRaisesRegex(AssertionError, '열 수 없습니다'):
            C.cms_ftp_start(self.port, '127.0.0.1', 'pg', self.DIR)
        with mock.patch.dict(os.environ, {'PG_PWD_CMS_SFTP': ''}):
            with self.assertRaisesRegex(AssertionError, 'PG_PWD_CMS_SFTP'):
                C.cms_ftp_start(_free_port(), '127.0.0.1', 'pg', self.DIR)

    @unittest.skipIf(hasattr(os, 'geteuid') and os.geteuid() == 0, 'root 는 21 을 열 수 있다')
    def test_privileged_port_gives_permission_guidance(self):
        before = set(os.listdir(tempfile.gettempdir()))
        with self.assertRaisesRegex(AssertionError, '권한이 없습니다.*고정값\\(21\\)'):
            C.cms_ftp_start(21, '127.0.0.1', 'pg', self.DIR)
        with self.assertRaises(ValueError):
            C.cms_ftp_start(_free_port(), '127.0.0.1', 'pg', self.DIR, passive_ports='a-b')
        leaked = [d for d in set(os.listdir(tempfile.gettempdir())) - before if d.startswith('cms_files_')]
        self.assertEqual(leaked, [])

    def test_sc_ftp_mount_puts_files_in_upload_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            upload = os.path.join(tmp, 'cmsweb', 'upload')
            port = _free_port()
            sc = C.cms_sc_ftp_start(port, '127.0.0.1', 'pg', self.DIR, upload)
            try:
                case = {'sc_data': 'SVC_20261124120000.dat', 'sc_fin': 'SVC_20261124120000.FIN', 'size': 50}
                ftp = self._login(port, 'sc-secret')
                try:
                    ftp.cwd(self.DIR)                                  # RunFtpSC: CWD SC_PATH → 상대 PUT
                    self.assertEqual(ftp.pwd(), self.DIR)
                    self._raw(ftp, 'STOR ' + case['sc_data'], b'z' * 50)
                    self._raw(ftp, 'STOR ' + case['sc_fin'], b'')
                finally:
                    ftp.quit()
                got = C.cms_sc_wait_uploads(sc, case, upload, timeout=3, poll=0.1)
                self.assertEqual(got['data']['size'], 50)
                self.assertEqual(sorted(os.listdir(upload)), sorted([case['sc_data'], case['sc_fin']]))
            finally:
                C.cms_sftp_stop(sc)


class _RemoteScMixin(object):
    """[SC] SC_PRIIP 가 다른 서버일 때 — 그 서버에 SC 계정으로 붙어 SC_PATH 를 확인한다."""
    SC_PATH = '/PG/FTP/CMS'
    PROTO = 'SFTP'

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.port = _free_port()
        env = mock.patch.dict(os.environ, {'PG_PWD_CMS_SFTP_UPLOAD': 'sc-secret'})
        env.start()
        self.addCleanup(env.stop)
        self.server = self.start_server()
        self.dir = Path(self.tmp.name, 'PG', 'FTP', 'CMS')
        self.dir.mkdir(parents=True, exist_ok=True)
        self.case = {'sc_data': 'SVC_20261125100000.dat', 'sc_fin': 'SVC_20261125100000.FIN', 'size': 30}

    def tearDown(self):
        self.server.stop()
        self.tmp.cleanup()

    def args(self):
        return (self.PROTO, '127.0.0.1', self.port, 'pg', self.SC_PATH)

    def test_check_wait_and_cleanup_on_remote_sc(self):
        self.assertIn('읽기 가능', C.cms_sc_remote_check(*self.args()))
        with self.assertRaisesRegex(AssertionError, '업로드가 다 오지'):
            C.cms_sc_remote_wait_uploads(*self.args(), self.case, timeout=0.5, poll=0.1)
        (self.dir / self.case['sc_data']).write_bytes(b'x' * 30)
        (self.dir / self.case['sc_fin']).write_bytes(b'')
        (self.dir / 'OTHER.dat').write_bytes(b'')
        got = C.cms_sc_remote_wait_uploads(*self.args(), self.case, timeout=3, poll=0.1)
        self.assertEqual((got['data']['size'], got['fin']['size']), (30, 0))
        with self.assertRaisesRegex(AssertionError, '크기'):
            C.cms_sc_remote_wait_uploads(*self.args(), dict(self.case, size=31), timeout=1, poll=0.1)
        result = C.cms_sc_remote_cleanup(*self.args(), [self.case['sc_data'], self.case['sc_fin'], '../x'])
        self.assertEqual(sorted(result['removed']), sorted([self.case['sc_data'], self.case['sc_fin']]))
        self.assertEqual(sorted(os.listdir(self.dir)), ['OTHER.dat'])

    def test_wrong_password_and_missing_dir_fail_clearly(self):
        with mock.patch.dict(os.environ, {'PG_PWD_CMS_SFTP_UPLOAD': 'wrong'}):
            with self.assertRaisesRegex(AssertionError, '로그인 실패'):
                C.cms_sc_remote_check(*self.args())
        with mock.patch.dict(os.environ, {'PG_PWD_CMS_SFTP_UPLOAD': ''}):
            with self.assertRaisesRegex(AssertionError, 'PG_PWD_CMS_SFTP_UPLOAD'):
                C.cms_sc_remote_check(*self.args())
        with self.assertRaisesRegex(AssertionError, '읽을 수 없습니다'):
            C.cms_sc_remote_check(self.PROTO, '127.0.0.1', self.port, 'pg', '/no/such/dir')
        self.assertTrue(C.cms_sc_remote_cleanup(self.PROTO, '127.0.0.1', _free_port(), 'pg', '/x', ['a'])['failed'])


@unittest.skipUnless(HAVE_PARAMIKO, 'paramiko 필요(142 venv)')
class CmsScRemoteSftpTests(_RemoteScMixin, unittest.TestCase):
    PROTO = 'SFTP'

    def start_server(self):
        return C._load_sftp().SftpServer(self.port, '127.0.0.1', 'pg', 'sc-secret',
                                         directory=self.tmp.name).start()


@unittest.skipUnless(HAVE_PYFTPDLIB, 'pyftpdlib 필요(142 venv)')
class CmsScRemoteFtpTests(_RemoteScMixin, unittest.TestCase):
    PROTO = 'FTP'

    def start_server(self):
        return C._load_ftp().FtpServer(self.port, '127.0.0.1', 'pg', 'sc-secret',
                                       directory=self.tmp.name, own_ioloop=True).start()


class FtpServerDefaultTests(unittest.TestCase):
    def test_upm_ftp_server_has_no_mounts_by_default(self):
        server = C._load_ftp().FtpServer(2121, directory=tempfile.gettempdir())
        self.assertEqual(server.mounts, [])
        self.assertEqual(server.downloads(), [])


if __name__ == '__main__':
    unittest.main()
