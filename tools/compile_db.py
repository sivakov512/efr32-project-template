#!/usr/bin/env python3
"""Add GCC's sysroot to the compilation database for clangd / clang-tidy."""
import json
from pathlib import Path
import shlex
import subprocess
import sys


def main():
    build = Path(sys.argv[1])
    entries = json.loads((build / 'compile_commands.json').read_text())
    result, sysroots = [], {}
    for entry in entries:
        if Path(entry['file']).suffix.lower() == '.s':
            continue
        args = entry.get('arguments') or shlex.split(entry['command'])
        compiler = args[0]
        if compiler not in sysroots:
            sysroots[compiler] = subprocess.check_output(
                [compiler, '-print-sysroot'], text=True).strip()
            if not sysroots[compiler]:
                raise ValueError(f'{compiler}: empty sysroot')
        entry.pop('command', None)
        entry['arguments'] = [compiler, f'--sysroot={sysroots[compiler]}', *args[1:]]
        result.append(entry)
    output = build / 'tidy/compile_commands.json'
    output.parent.mkdir(exist_ok=True)
    temporary = output.with_suffix('.tmp')
    temporary.write_text(json.dumps(result, indent=2) + '\n')
    temporary.replace(output)
    link = Path('compile_commands.json')
    link.unlink(missing_ok=True)
    link.symlink_to(output)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(f'ERROR: compilation database: {error}')
