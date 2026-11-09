#!/usr/bin/env python3
"""Test double for container transport only; SQL/dump use native MariaDB 12.3.3.

This cannot target production: host, port and database are fixed test values.
"""
import json
import os
import shlex
import re
import subprocess
import sys
from pathlib import Path

state = Path(os.environ['GA_INSTALLER_SIMULATOR_STATE'])
data = Path(os.environ['GA_INSTALLER_SIMULATOR_DATA'])
args = sys.argv[1:]
database=os.environ.get('GA_INSTALLER_SIMULATOR_DATABASE','ga_p24_release_test')
if not re.fullmatch(r'ga_(?:p24_release|upgrade_[a-f0-9]{12})_test',database):
    raise SystemExit('Invalid isolated database name')
if args[0] == 'inspect':
    fmt = args[args.index('--format')+1] if '--format' in args else next((x.split('=',1)[1] for x in args if x.startswith('--format=')), '')
    if 'Mounts' in fmt:
        print(data)
    elif 'State.Health' in fmt:
        print('healthy')
    elif 'State.Status' in fmt:
        print(state.read_text().strip())
elif args[0] in ('stop', 'start'):
    state.write_text('running' if args[0] == 'start' else 'exited')
elif args[0] in ('network', 'logs'):
    pass
elif args[0] == 'exec':
    command = args[args.index('-lc')+1] if '-lc' in args else args[-1]
    if 'id -u' in command:
        print('0:0')
    elif 'mariadb-dump' in command:
        if os.environ.get('GA_SIMULATE_DUMP_FAILURE')=='1':
            raise SystemExit(2)
        sys.exit(subprocess.run([os.environ['GA_MARIADB_DUMP'], '--no-defaults', '--host=127.0.0.1', '--port=13310', '-uroot', '--single-transaction', '--quick', '--routines', '--triggers', '--events', '--hex-blob', '--default-character-set=utf8mb4', *[a for a in args if a.startswith('--ignore-table=')], database]).returncode)
    elif command.startswith('mariadb '):
        parts = shlex.split(command)
        sql = parts[parts.index('-e')+1] if '-e' in parts else sys.stdin.read()
        client = [os.environ['GA_MARIADB_CLIENT'], '--no-defaults', '--host=127.0.0.1', '--port=13310', '-uroot', database]
        if '-N' in parts:
            client += ['-N', '-B', '-r']
        sys.exit(subprocess.run(client, input=sql, text=True).returncode)
    elif 'node' in args or 'npm list' in command:
        pass
    else:
        raise SystemExit('Unsupported simulated docker operation: '+repr(args))
else:
    raise SystemExit('Unsupported simulated docker command')
