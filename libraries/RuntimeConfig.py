"""Resolve one configuration snapshot before DB seeding and regression execution."""
import json
import os
from pathlib import Path
import re
import sys

from robot.conf import RobotSettings
from robot.run import RobotFramework
from robot.running import ResourceFile
from robot.utils import split_args_from_name_or_path
from robot.variables.scopes import GlobalVariables

import SshHelper

_ROOT = Path(__file__).resolve().parent.parent


def get_variables(snapshot: str) -> dict:
    """Load the private, per-run JSON snapshot as a Robot variable file."""
    return json.loads(Path(snapshot).read_text(encoding='utf-8'))


def _resolve(options: dict, target: str, reader=None, sources=None) -> dict:
    """Resolve the snapshot. When ``sources`` is a dict it receives name -> origin text."""
    if sources is None:
        sources = {}
    variables = GlobalVariables(RobotSettings({}))
    names = set()
    for spec in options.get('variablefile', []):
        path, args = split_args_from_name_or_path(spec)
        for name, _ in variables.set_from_file(path, args):
            names.add(name)
            sources[name] = '환경 파일 %s' % Path(path).name
    cli = options.get('variable', [])
    variables._set_cli_variables(RobotSettings({'variable': cli}))
    for item in cli:
        name = item.split(':', 1)[0]
        names.add(name)
        sources[name] = 'CLI --variable'
    protected = {name.replace('_', '').replace(' ', '').lower() for name in names}
    for resource in ['variables', 'nag_variables', 'pcf_variables',
                     'upm_variables', 'lrs_server_variables', 'lrs_variables',
                     'cds_variables', 'nwdaf_variables', 'rts_variables']:
        path = _ROOT / 'resources' / (resource + '.robot')
        variables['${CURDIR}'] = str(path.parent)
        section = ResourceFile.from_file_system(str(path)).variables
        variables.set_from_variable_section(section)
    enabled = variables['${REMOTE_CONFIG_ENABLED}']
    enabled = str(enabled).lower() not in {'false', '0', 'no', 'off', ''}
    remote_names = set()
    if not enabled:
        remote_skip = '원격 설정 꺼짐(--no-remote-config)'
    elif options.get('dryrun'):
        remote_skip = 'dryrun — 원격 미조회'
    else:
        remote_skip = None
    if remote_skip:
        mapping_path = variables['${REMOTE_CONFIG_MAP_PATH}']
        for entry in json.loads(Path(mapping_path).read_text(encoding='utf-8')):
            sources.setdefault(entry['variable'], '기본값 (%s)' % remote_skip)
            names.add(entry['variable'])
    if enabled and not options.get('dryrun'):
        mapping_path = variables['${REMOTE_CONFIG_MAP_PATH}']
        mappings = json.loads(Path(mapping_path).read_text(encoding='utf-8'))
        groups = {}
        seen = set()
        for entry in mappings:
            name = entry['variable']
            normalized = name.replace('_', '').replace(' ', '').lower()
            if normalized in seen:
                raise AssertionError('Duplicate remote variable mapping: %s' % name)
            seen.add(normalized)
            if normalized in protected:
                sources[name] = sources.get(name, '명시값') + ' (원격 매핑보다 우선)'
                continue
            path = variables.replace_scalar(entry['path'])
            if not path:
                sources[name] = '기본값 (원격 매핑 비활성: 경로 비어 있음)'
                names.add(name)
                continue
            host = variables.replace_scalar(entry.get('host', '${PG_HOST}'))
            section = variables.replace_scalar(entry['section'])
            key = variables.replace_scalar(entry['key'])
            groups.setdefault((host, path, section), []).append((name, key, entry.get('type', 'string')))
        user = variables['${PG_SSH_USER}']
        if groups and not user:
            raise AssertionError('PG_SSH_USER is required for remote configuration; '
                                 'use --no-remote-config for an explicitly offline run.')
        read = reader or SshHelper.read_remote_cfg
        for (host, path, section), entries in groups.items():
            remote = read(host, user, path, section, list(dict.fromkeys(key for _, key, _ in entries)),
                          key_file=variables['${PG_SSH_KEY_FILE}'])
            for name, key, kind in entries:
                raw = remote[key]
                if kind in {'port', 'integer'}:
                    value = int(raw)
                    if kind == 'port' and not 1 <= value <= 65535:
                        raise AssertionError('Invalid remote port for %s: %s' % (name, value))
                elif kind == 'boolean':
                    if str(raw).lower() not in {'true', 'false', '1', '0', 'yes', 'no', 'on', 'off'}:
                        raise AssertionError('Invalid remote boolean for %s' % name)
                    value = str(raw).lower() in {'true', '1', 'yes', 'on'}
                elif kind == 'string':
                    value = str(raw)
                else:
                    raise AssertionError('Unknown remote setting type: %s' % kind)
                try:
                    previous = variables['${%s}' % name]
                except Exception:  # not defined by any resource default
                    previous = None
                variables['${%s}' % name] = value
                remote_names.add(name)
                where = '원격 %s:%s [%s] %s' % (host, path, section, key)
                if previous is None:
                    sources[name] = where
                elif str(previous) == str(value):
                    sources[name] = where + ' (기본값과 같음)'
                else:
                    sources[name] = where + ' (기본값 %s 와 다름)' % previous
    # Freeze explicit overrides and remotely resolved ports, preserving suite-local
    # protocol overrides (for example NAG's LRS_TX_BYTE0) below this layer.
    names.update(remote_names)
    names.update(('NAG_PG_PORT', 'PCF_PG_PORT'))
    for name in names:
        sources.setdefault(name, '기본값 (resources/*_variables.robot)')
    resolved = {name: variables['${%s}' % name] for name in names}
    resolved['RUNTIME_CONFIG_RESOLVED'] = True
    resolved['RUNTIME_CONFIG_DRYRUN'] = bool(options.get('dryrun'))
    return resolved


_SECRET_NAME = re.compile(r'PWD|PASSW|SECRET|TOKEN|CREDENTIAL', re.I)
_SECRET_IN_VALUE = re.compile(r'((?:PWD|PASSWORD)\s*=)[^;]*', re.I)
_ORIGIN_ORDER = ('원격', 'CLI', '환경 파일', '명시값', '러너', '기본값')


def _display(name: str, value) -> str:
    """Render one value for the report; credentials are never shown."""
    if _SECRET_NAME.search(name):
        return '****' if value not in (None, '') else '(비어 있음)'
    text = _SECRET_IN_VALUE.sub(r'\1****', str(value))
    return text if len(text) <= 48 else text[:45] + '...'


def _origin_rank(origin: str) -> int:
    for rank, prefix in enumerate(_ORIGIN_ORDER):
        if origin.startswith(prefix):
            return rank
    return len(_ORIGIN_ORDER)


def format_report(resolved: dict, sources: dict, header: str = '') -> str:
    """Return a plain-text table of every snapshot value with its origin."""
    rows = [(name, _display(name, resolved[name]), sources.get(name, '?'))
            for name in resolved if not name.startswith('RUNTIME_CONFIG_')]
    rows.sort(key=lambda row: (_origin_rank(row[2]), row[0]))
    width_name = max([4] + [len(row[0]) for row in rows])
    width_value = max([4] + [len(row[1]) for row in rows])
    remote = sum(1 for row in rows if row[2].startswith('원격'))
    lines = ['[Config] 설정값 리포트%s — %d개 (원격 cfg 적용 %d개)' % (header, len(rows), remote),
             '  %-*s  %-*s  %s' % (width_name, 'NAME', width_value, 'VALUE', 'SOURCE'),
             '  ' + '-' * (width_name + width_value + 40)]
    lines += ['  %-*s  %-*s  %s' % (width_name, n, width_value, v, o) for n, v, o in rows]
    return '\n'.join(lines)


def resolve_nag_ports() -> dict:
    """Resolve direct Robot CLI runs using the same precedence as the runner."""
    from robot.libraries.BuiltIn import BuiltIn
    builtin = BuiltIn()
    if builtin.get_variable_value('${RUNTIME_CONFIG_RESOLVED}', False):
        return {name: builtin.get_variable_value('${%s}' % name)
                for name in ('NAG_PG_PORT', 'PCF_PG_PORT')}
    options, _ = RobotFramework().parse_arguments(sys.argv[1:])
    sources = {}
    values = _resolve(options, 'nag', sources=sources)
    ports = {name: values[name] for name in ('NAG_PG_PORT', 'PCF_PG_PORT')}
    from robot.api import logger
    logger.console(format_report(ports, sources, ' (Robot CLI 직접 실행 — NAG 포트)'))
    return ports


def _main() -> None:
    snapshot, target, seed_file, *args = sys.argv[1:]
    options, _ = RobotFramework().parse_arguments(args + ['tests/'])
    sources = {}
    resolved = _resolve(options, target, sources=sources)
    if not any(name.replace("_", "").replace(" ", "").lower() == "dbseedfile"
               for name in resolved):
        resolved["DB_SEED_FILE"] = seed_file
        sources["DB_SEED_FILE"] = '러너 (환경별 시드 파일)'
    # Never print credentials or store a world-readable configuration snapshot.
    descriptor = os.open(snapshot, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
        json.dump(resolved, stream, ensure_ascii=False)
    print('[Config] Resolved configuration for DB seed and tests.')
    # The report masks credentials, but keeps the snapshot's owner-only permission
    # because it still lists hosts and subscriber numbers.
    report = format_report(resolved, sources, ' (대상: %s)' % target)
    report_path = str(Path(snapshot).with_name(Path(snapshot).stem + '-report.txt'))
    descriptor = os.open(report_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
        stream.write(report + '\n')
    print(report)
    print('[Config] Report saved: %s' % report_path)


if __name__ == '__main__':
    _main()
