"""Resolve one configuration snapshot before DB seeding and regression execution."""
import json
import os
from pathlib import Path
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


def _resolve(options: dict, target: str, reader=None) -> dict:
    variables = GlobalVariables(RobotSettings({}))
    names = set()
    for spec in options.get('variablefile', []):
        path, args = split_args_from_name_or_path(spec)
        names.update(name for name, _ in variables.set_from_file(path, args))
    cli = options.get('variable', [])
    variables._set_cli_variables(RobotSettings({'variable': cli}))
    names.update(item.split(':', 1)[0] for item in cli)
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
                continue
            path = variables.replace_scalar(entry['path'])
            if not path:
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
                variables['${%s}' % name] = value
                remote_names.add(name)
    # Freeze explicit overrides and remotely resolved ports, preserving suite-local
    # protocol overrides (for example NAG's LRS_TX_BYTE0) below this layer.
    names.update(remote_names)
    names.update(('NAG_PG_PORT', 'PCF_PG_PORT'))
    resolved = {name: variables['${%s}' % name] for name in names}
    resolved['RUNTIME_CONFIG_RESOLVED'] = True
    resolved['RUNTIME_CONFIG_DRYRUN'] = bool(options.get('dryrun'))
    return resolved


def resolve_nag_ports() -> dict:
    """Resolve direct Robot CLI runs using the same precedence as the runner."""
    from robot.libraries.BuiltIn import BuiltIn
    builtin = BuiltIn()
    if builtin.get_variable_value('${RUNTIME_CONFIG_RESOLVED}', False):
        return {name: builtin.get_variable_value('${%s}' % name)
                for name in ('NAG_PG_PORT', 'PCF_PG_PORT')}
    options, _ = RobotFramework().parse_arguments(sys.argv[1:])
    values = _resolve(options, 'nag')
    return {name: values[name] for name in ('NAG_PG_PORT', 'PCF_PG_PORT')}


def _main() -> None:
    snapshot, target, seed_file, *args = sys.argv[1:]
    options, _ = RobotFramework().parse_arguments(args + ['tests/'])
    resolved = _resolve(options, target)
    if not any(name.replace("_", "").replace(" ", "").lower() == "dbseedfile"
               for name in resolved):
        resolved["DB_SEED_FILE"] = seed_file
    # Never print credentials or store a world-readable configuration snapshot.
    descriptor = os.open(snapshot, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
        json.dump(resolved, stream, ensure_ascii=False)
    print('[Config] Resolved configuration for DB seed and tests.')


if __name__ == '__main__':
    _main()
