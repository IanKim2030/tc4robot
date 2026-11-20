"""Offline precedence and pre-seed configuration checks; no SSH or DB access."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import RuntimeConfig


class RuntimeConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.env = Path(self.temp.name) / 'env.py'
        self.env.write_text((RuntimeConfig._ROOT / 'config/env/dev.py').read_text())
        self.options = {'variablefile': [str(self.env)]}
        self.calls = []

    def reader(self, *args, **kwargs):
        self.calls.append((args, kwargs))
        return {key: '9100' if key.endswith('NAG') else '9200' for key in args[4]}

    def test_remote_beats_node_defaults(self):
        values = RuntimeConfig._resolve(self.options, 'nag', self.reader)
        self.assertEqual((values['NAG_PG_PORT'], values['PCF_PG_PORT']), (9100, 9200))
        self.assertEqual(len(self.calls), 2)
        self.assertNotIn('LRS_TX_BYTE0', values)

    def test_explicit_env_default_value_still_beats_remote(self):
        with self.env.open('a') as stream:
            stream.write('\nNAG_PG_PORT = 8012\n')
        values = RuntimeConfig._resolve(self.options, 'nag', self.reader)
        self.assertEqual(values['NAG_PG_PORT'], 8012)
        self.assertEqual(self.calls[0][0][4], ['Barod.IF.Port.PCF'])

    def test_cli_beats_env_and_remote(self):
        with self.env.open('a') as stream:
            stream.write('\nNAG_PG_PORT = 9300\n')
        self.options['variable'] = ['NAG_PG_PORT:9400']
        values = RuntimeConfig._resolve(self.options, 'nag', self.reader)
        self.assertEqual(values['NAG_PG_PORT'], '9400')
        self.assertEqual(values['PCF_PG_PORT'], 9200)

    def test_disabled_remote_keeps_defaults(self):
        self.options['variable'] = ['BNOTI_CFG_PATH:']
        values = RuntimeConfig._resolve(self.options, 'nag', self.reader)
        self.assertEqual(str(values['NAG_PG_PORT']), '8012')
        self.assertEqual(len(self.calls), 1)

    def test_dryrun_and_disabled_remote_do_not_contact_ssh(self):
        RuntimeConfig._resolve(dict(self.options, dryrun=True), 'nag', self.reader)
        RuntimeConfig._resolve(dict(self.options, variable=['REMOTE_CONFIG_ENABLED:False']), 'cds', self.reader)
        self.assertEqual(self.calls, [])

    def test_invalid_remote_port_blocks_resolution(self):
        with self.assertRaises(AssertionError):
            RuntimeConfig._resolve(self.options, 'nag', lambda *a, **kw: {k: '65536' for k in a[4]})

    def test_remote_failure_is_not_silently_ignored(self):
        def fail(*args, **kwargs):
            raise AssertionError('remote read failed')
        with self.assertRaisesRegex(AssertionError, 'remote read failed'):
            RuntimeConfig._resolve(self.options, 'nag', fail)

    def test_runner_seed_and_tests_share_final_snapshot(self):
        shim = Path(self.temp.name) / 'python3'
        log = Path(self.temp.name) / 'calls.jsonl'
        capture = Path(self.temp.name) / 'capture.py'
        capture.write_text(
            'import json,os,sys\n'
            'with open(os.environ["CONFIG_TEST_CALLS"], "a") as f:\n'
            '    f.write(json.dumps(sys.argv[1:]) + "\\n")\n')
        shim.write_text('#!/bin/bash\nif [ "$1" = "-m" ] && [ "$2" = "robot" ]; then\n'
                        'shift 2\nexec "' + sys.executable + '" "' + str(capture) + '" "$@"\n'
                        'fi\nexec "' + sys.executable + '" "$@"\n')
        shim.chmod(0o700)
        env = dict(os.environ, PATH=self.temp.name + os.pathsep + os.environ['PATH'],
                   CONFIG_TEST_CALLS=str(log))
        subprocess.run(['bash', 'run_tests.sh', 'nag', '--no-remote-config',
                        '-v', 'NAG_PG_PORT:9400', '-v', 'SUBS_MDN_LTE:01012345678',
                        '-v', 'DB_SEED_FILE:custom-seed.sql', '--no-ssh-ensure',
                        '-v', 'PG_SSH_ENSURE:True'],
                       cwd=RuntimeConfig._ROOT, env=env, check=True, stdout=subprocess.DEVNULL)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        self.assertEqual(len(calls), 2)
        specs = [call[call.index('--variablefile') + 1] for call in calls]
        self.assertEqual(specs[0], specs[1])
        snapshot = RuntimeConfig._ROOT / specs[0].split(':', 1)[1]
        values = RuntimeConfig.get_variables(str(snapshot))
        self.assertEqual(values['NAG_PG_PORT'], '9400')
        self.assertEqual(values['SUBS_MDN_LTE'], '01012345678')
        self.assertEqual(values['DB_SEED_FILE'], 'custom-seed.sql')
        self.assertEqual(values['PG_SSH_ENSURE'], 'True')
        self.assertNotIn('PG_SSH_ENSURE:False', calls[0])

    def test_every_runner_target_reads_mapped_server_settings(self):
        for target in ['nag', 'pcf', 'lrs', 'upm', 'cds', 'nwdaf', 'rts', 'all']:
            self.calls.clear()
            values = RuntimeConfig._resolve(self.options, target, self.reader)
            self.assertEqual(len(self.calls), 2)
            self.assertEqual(values['CDS_SCH_PORT'], 9200)
            self.assertEqual(values['CDS_RCH_PORT'], 9200)
            self.assertEqual(values['NAG_PG_PORT'], 9100)

    def test_custom_mapping_applies_typed_settings(self):
        mapping = Path(self.temp.name) / 'mapping.json'
        mapping.write_text(json.dumps([
            {'variable': 'UPM_PG_PORT', 'path': '/confirmed.cfg', 'section': 'CONFIRMED',
             'key': 'port', 'type': 'port'},
            {'variable': 'UPM_FTP_ENABLE', 'path': '/confirmed.cfg', 'section': 'CONFIRMED',
             'key': 'enabled', 'type': 'boolean'}]))
        options = dict(self.options, variable=['REMOTE_CONFIG_MAP_PATH:' + str(mapping)])
        values = RuntimeConfig._resolve(options, 'upm',
                                       lambda *a, **kw: {'port': '10507', 'enabled': 'yes'})
        self.assertEqual(values['UPM_PG_PORT'], 10507)
        self.assertIs(values['UPM_FTP_ENABLE'], True)

    def test_missing_ssh_account_blocks_enabled_remote_resolution(self):
        options = dict(self.options, variable=['PG_SSH_USER:'])
        with self.assertRaisesRegex(AssertionError, 'PG_SSH_USER is required'):
            RuntimeConfig._resolve(options, 'nag', self.reader)
        self.assertEqual(self.calls, [])

    def test_snapshot_preserves_final_values_and_is_private(self):
        output = Path(self.temp.name) / 'runtime.json'
        subprocess.run([sys.executable, str(Path(RuntimeConfig.__file__)), str(output), 'nag', 'config/db_seed/dev.sql',
                        '-V', str(self.env), '-v', 'NAG_PG_PORT:9400', '--dryrun'], check=True)
        self.assertEqual(RuntimeConfig.get_variables(str(output))['NAG_PG_PORT'], '9400')
        self.assertEqual(output.stat().st_mode & 0o777, 0o600)
        self.assertEqual(json.loads(output.read_text())['LRS_SERVER_PORT'], 8890)

    def test_report_names_origin_of_every_value(self):
        sources = {}
        self.options['variable'] = ['UPM_PG_PORT:10599']
        values = RuntimeConfig._resolve(self.options, 'nag', self.reader, sources)
        self.assertEqual(sources['UPM_PG_PORT'], 'CLI --variable')
        self.assertEqual(sources['PG_HOST'], '환경 파일 env.py')
        self.assertIn('BarodNoti.cfg [Barod.IF] Barod.IF.Port.NAG', sources['NAG_PG_PORT'])
        self.assertIn('기본값 8012 와 다름', sources['NAG_PG_PORT'])
        self.assertIn('기본값과 같음', sources['CDS_SCH_PORT'])
        report = RuntimeConfig.format_report(values, sources)
        self.assertIn('원격 cfg 적용 4개', report)
        self.assertTrue(set(values) - {'RUNTIME_CONFIG_RESOLVED', 'RUNTIME_CONFIG_DRYRUN'}
                        <= set(sources))

    def test_report_marks_skipped_remote_and_masks_credentials(self):
        sources = {}
        values = RuntimeConfig._resolve(dict(self.options, dryrun=True), 'nag', self.reader, sources)
        self.assertIn('dryrun', sources['NAG_PG_PORT'])
        self.assertIn('dryrun', sources['CDS_RCH_PORT'])
        values['PDB_CONNSTR'] = 'DSN=PDB;UID=pdb;PWD=topsecret;'
        values['UPM_FTP_PASSWORD'] = 'topsecret'
        report = RuntimeConfig.format_report(values, sources)
        self.assertNotIn('topsecret', report)
        self.assertIn('PWD=****', report)

    def test_runner_report_file_is_written_next_to_snapshot(self):
        output = Path(self.temp.name) / 'runtime.json'
        result = subprocess.run([sys.executable, str(Path(RuntimeConfig.__file__)), str(output), 'nag',
                                 'config/db_seed/dev.sql', '-V', str(self.env), '--dryrun'],
                                check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                env=dict(os.environ, PYTHONIOENCODING='utf-8'))
        report = Path(self.temp.name) / 'runtime-report.txt'
        self.assertIn('[Config]', result.stdout.decode('utf-8'))
        text = report.read_text(encoding='utf-8')
        self.assertIn('DB_SEED_FILE', text)
        self.assertIn('러너 (환경별 시드 파일)', text)


if __name__ == '__main__':
    unittest.main()
