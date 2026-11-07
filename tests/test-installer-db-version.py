#!/usr/bin/env python3
"""Exercise the real installer preflight without touching Docker or a database."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
helper = ROOT/'installer/check-database-version.py'
metadata = ROOT/'BUILD-INFO.json'
expected = json.loads(metadata.read_text())['runtime_dependencies']['mariadb']
for observed, allowed in [(expected+'-MariaDB-ubu2404', True), ('11.8.9-MariaDB', False), ('12.3.4-MariaDB', False), ('13.0.2-MariaDB', False), ('not a version', False)]:
    check = subprocess.run([sys.executable, str(helper), '--build-info', str(metadata), '--server-version', observed], text=True, capture_output=True)
    assert (check.returncode == 0) == allowed, (observed, check.stdout, check.stderr)
    if allowed:
        assert json.loads(check.stdout)['server_version'] == observed
    else:
        assert 'Ingen database-reset eller flowendring' in check.stderr

if os.geteuid() == 0:
    for observed, allowed, nr_state in [(expected+'-MariaDB-ubu2404', True, 'running'), ('11.8.9-MariaDB', False, 'running'), ('12.3.4-MariaDB', False, 'running'), (expected+'-MariaDB-ubu2404', True, 'exited'), (expected+'-MariaDB-ubu2404', True, 'restarting')]:
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            project = temp/'project'; (project/'installer').mkdir(parents=True)
            for relative in ('VERSION', 'BUILD-INFO.json', 'installer/install.sh', 'installer/check-database-version.py'):
                shutil.copy2(ROOT/relative, project/relative)
            bindir = temp/'bin'; bindir.mkdir()
            docker = bindir/'docker'
            docker.write_text('''#!/usr/bin/env python3
import json,os,sys
args=sys.argv[1:]
with open(os.environ['GA_TEST_DOCKER_LOG'],'a') as log:log.write(json.dumps(args)+'\\n')
if args[0]=='inspect':
    fmt=next((a.split('=',1)[1] for a in args if a.startswith('--format=')),None)
    if fmt is None and '--format' in args:fmt=args[args.index('--format')+1]
    if fmt is not None:
        print('healthy' if '.State.Health' in fmt else os.environ['GA_TEST_NODERED_STATE'] if '.State.Status' in fmt else '')
    else:print('{}')
elif args[0]=='exec' and 'SELECT VERSION()' in ' '.join(args):
    print(os.environ['GA_TEST_SERVER_VERSION'])
else:
    sys.exit('Unexpected Docker operation in read-only preflight fixture')
''')
            docker.chmod(0o755)
            env = os.environ.copy()
            env.update(PATH=str(bindir)+os.pathsep+env['PATH'], GA_TEST_DOCKER_LOG=str(temp/'docker.jsonl'), GA_TEST_SERVER_VERSION=observed, GA_TEST_NODERED_STATE=nr_state)
            result = subprocess.run(['bash', str(project/'installer/install.sh')], env=env, text=True, capture_output=True, timeout=15)
            reports = list((project/'install-reports').glob('*.json'))
            assert len(reports) == 1, result.stdout+result.stderr
            report = json.loads(reports[0].read_text())
            assert report['database_server_version'] == observed, (report, result.stdout, result.stderr)
            expected_step = 'preflight MariaDB version' if not allowed else 'preflight Node-RED running' if nr_state != 'running' else 'preflight Node-RED data mount'
            assert report['last_step'] == expected_step, report
            calls = [json.loads(line) for line in (temp/'docker.jsonl').read_text().splitlines()]
            assert not any(call[0] in ('stop', 'start', 'restart', 'cp') for call in calls), calls
            assert not any('DROP DATABASE' in ' '.join(call) for call in calls), calls
            if allowed and nr_state != 'running':
                assert 'docker start gjaeringsassistent-nodered' in result.stdout+result.stderr
                assert 'node-red-node-mysql er ikke installert' not in result.stdout+result.stderr
                assert not any(call[0] == 'exec' and 'SELECT VERSION()' not in ' '.join(call) for call in calls), calls
            assert result.returncode != 0  # Valid version stops at deliberately absent fixture mount.
print('RESULT: PASS – pinned MariaDB version and stopped Node-RED; actual installer rejects before database or flow mutation')
