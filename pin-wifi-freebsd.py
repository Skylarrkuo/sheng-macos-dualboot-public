"""Prepare the locked FreeBSD source before Ath12kWifi checks its dependency."""
import json
from pathlib import Path
import subprocess
import sys


wifi = Path(sys.argv[1]).resolve()
directory = wifi / 'deps/freebsd'
if not directory.exists():
    source = json.loads((wifi / 'tools/source-lock.json').read_text())['freebsd']
    directory.mkdir(parents=True)
    commands = [
        ['init', '-q'],
        ['remote', 'add', 'origin', source['url']],
        ['config', 'remote.origin.promisor', 'true'],
        ['config', 'remote.origin.partialclonefilter', 'blob:none'],
        ['sparse-checkout', 'init', '--cone'],
        ['fetch', '--depth', '1', '--filter=blob:none', 'origin', source['commit']],
        ['switch', '--detach', 'FETCH_HEAD'],
    ]
    for command in commands:
        subprocess.run(['git', '-C', str(directory), *command], check=True)
