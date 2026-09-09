#!/usr/bin/env python3
"""Read the single project in the current directory for Make (PyYAML required)."""
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("ERROR: PyYAML is missing in this Python. Set PYTHON to the Silicon Labs Python or install PyYAML; see README.")


def token(value, label):
    value = str(value) if value is not None else ""
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", value):
        raise ValueError(f"{label} must be a nonempty name using letters, digits, _, . or -")
    return value


def main():
    paths = sorted(Path('.').glob('*.slcp'))
    if len(paths) != 1:
        raise ValueError(f"expected exactly one .slcp in the project directory; found {len(paths)}")
    path = paths[0]
    token(path.name, '.slcp filename')
    data = yaml.safe_load(path.read_text())
    if not isinstance(data, dict):
        raise ValueError(f"{path}: expected a YAML mapping")
    project = token(data.get('project_name'), 'project_name')
    sdk = data.get('sdk')
    if not isinstance(sdk, dict) or sdk.get('id') != 'simplicity_sdk':
        raise ValueError('sdk.id must be simplicity_sdk; other SDK families are not verified')
    version = token(sdk.get('version'), 'sdk.version')
    components = data.get('component', [])
    if not isinstance(components, list) or any(not isinstance(c, dict) for c in components):
        raise ValueError('component must be a YAML list of mappings')
    parts = [c for c in components if str(c.get('id', '')).upper().startswith('EFR32')]
    if len(parts) != 1 or parts[0].get('condition') or parts[0].get('unless'):
        raise ValueError('select exactly one unconditional EFR32 part in component (not autoselected_components)')
    part = token(parts[0]['id'], 'EFR32 part').upper()
    print(path.name, project, version, part)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, yaml.YAMLError) as error:
        sys.exit(f'ERROR: {error}')
