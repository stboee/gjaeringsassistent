#!/usr/bin/env python3
"""Run shipped integration suites on a new, disposable localhost MariaDB.

Accepts binaries/dependencies, never an existing datadir or a remote database.
Native package installation and target HA/Docker UAT are separate operations.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import pwd
import resource
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mariadb-basedir', required=True, type=Path)
parser.add_argument('--palette-dir', required=True, type=Path)
parser.add_argument('--chromium', type=Path)
parser.add_argument('--suite', choices=['start', 'operator', 'full', 'remainder', 'tail', 'archive', 'metadata', 'ui', 'upgrade'], default='full')
args = parser.parse_args()
base = args.mariadb_basedir.resolve()
palette = args.palette_dir.resolve()
scratch = Path(tempfile.mkdtemp(prefix='ga-native-test-'))
data = scratch/'data'
env = os.environ.copy()
env.update({
    'LD_LIBRARY_PATH': ':'.join([str(base/'lib/x86_64-linux-gnu'), str(base.parent/'lib/x86_64-linux-gnu'), env.get('LD_LIBRARY_PATH', '')]),
    'NODE_PATH': os.pathsep.join([str(palette/'node_modules'), env.get('CODEX_PRIMARY_RUNTIME_NODE_MODULES', ''), env.get('NODE_PATH', '')]),
    'GA_HA_PLUGIN_DIR': str(palette/'node_modules/node-red-contrib-home-assistant-websocket'),
    'GA_HA_AUDIT_DEPS': str(palette/'node_modules'),
    'GA_PALETTE_DIR': str(palette),
    'GA_MARIADB_CLIENT': str(base/'bin/mariadb'),
    'GA_MARIADB_DUMP': str(base/'bin/mariadb-dump'),
    'GA_MARIADB_SERVER': str(base/'sbin/mariadbd'),
    'GA_MARIADB_BASEDIR': str(base),
    'PYTHONDONTWRITEBYTECODE': '1', 'TZ': 'UTC', 'MALLOC_ARENA_MAX': '2',
})
if args.chromium:
    env['GA_CHROMIUM_BINARY'] = str(args.chromium.resolve())
server = None
log_path = ROOT/'verification'/('native-'+args.suite+'.log')

def limits():
    resource.setrlimit(resource.RLIMIT_AS, (4*1024**3, 4*1024**3))

def run(command, log):
    print('RUN', ' '.join(command), flush=True)
    log.write('RUN '+' '.join(command)+'\n'); log.flush()
    result = subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=900)
    log.flush()
    if result.returncode:
        print(log_path.read_text()[-6000:], flush=True)
        raise RuntimeError('Failed: '+' '.join(command))
    print('PASS', command[-1], flush=True)

try:
    version = subprocess.check_output([str(base/'sbin/mariadbd'), '--no-defaults', '--version'], env=env, text=True)
    if '12.3.3-' not in version:
        raise RuntimeError('Pinned MariaDB 12.3.3 required: '+version)
    subprocess.run([str(base/'bin/mariadb-install-db'), '--no-defaults', '--auth-root-authentication-method=normal', '--basedir='+str(base), '--datadir='+str(data)], env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    with (scratch/'server.log').open('w') as serverlog, log_path.open('w') as log:
        server = subprocess.Popen([
            str(base/'sbin/mariadbd'), '--no-defaults', '--user='+pwd.getpwuid(os.geteuid()).pw_name,
            '--basedir='+str(base), '--datadir='+str(data), '--socket=', '--pid-file='+str(scratch/'server.pid'),
            '--port=13310', '--bind-address=127.0.0.1', '--innodb-buffer-pool-size=128M', '--performance-schema=OFF',
            '--max-heap-table-size=32M', '--tmp-table-size=32M', '--max-connections=16', '--table-open-cache=256',
            '--innodb-use-native-aio=0', '--innodb-flush-method=fsync', '--max-allowed-packet=64M', '--max-statement-time=120',
        ], env=env, stdout=serverlog, stderr=subprocess.STDOUT, preexec_fn=limits)
        for attempt in range(80):
            if server.poll() is not None:
                raise RuntimeError((scratch/'server.log').read_text())
            probe = subprocess.run(['node', '-e', 'require("mysql2/promise").createConnection({host:"127.0.0.1",port:13310,user:"root"}).then(async c=>{console.log((await c.query("SELECT @@datadir d"))[0][0].d);await c.end()}).catch(()=>process.exitCode=1)'], env=env, capture_output=True, text=True)
            if probe.returncode == 0:
                if Path(probe.stdout.strip()).resolve() != data.resolve():
                    raise RuntimeError('Port 13310 belongs to another server; no test has run')
                break
            time.sleep(.2)
        else:
            raise RuntimeError('Isolated MariaDB did not become ready')
        tz = subprocess.check_output([str(base/'bin/mariadb-tzinfo-to-sql'), '/usr/share/zoneinfo/Europe/Oslo', 'Europe/Oslo'], env=env)
        subprocess.run([str(base/'bin/mariadb'), '--no-defaults', '--host=127.0.0.1', '--port=13310', '-uroot', 'mysql'], input=tz, env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        suites = {
            'start': ['tests/test-start-control-live.js'],
            'operator': ['tests/test-operator-config-live.js', 'tests/test-operator-ui.js'],
            'upgrade': ['tests/test-install-upgrade-live.js'],
            'ui': ['tests/test-operator-ui.js'],
            'metadata': ['tests/test-operator-config-live.js', 'tests/test-p24r15-live.js', 'tests/test-operator-ui.js'],
            'archive': ['tests/test-sqlite-live.js', 'tests/test-p24r15-historical-live.js', 'tests/test-p24r15-live.js', 'tests/test-operator-ui.js'],
            'tail': ['tests/test-p24r15-performance-live.js', 'tests/test-p24r15-historical-live.js', 'tests/test-p24r15-live.js'],
            'remainder': ['tests/test-p24r15-graphs-live.js', 'tests/test-p24r15-performance-live.js', 'tests/test-p24r15-historical-live.js', 'tests/test-p24r15-live.js'],
            'full': ['tests/test-start-control-live.js', 'tests/test-operator-config-live.js', 'tests/test-p24r16-system-live.js', 'tests/test-p24r15-graphs-live.js', 'tests/test-p24r15-performance-live.js', 'tests/test-p24r15-historical-live.js', 'tests/test-p24r15-live.js', 'tests/test-operator-ui.js'],
        }[args.suite]
        if args.suite == 'full':
            run(['python3', 'tests/test-mariadb-p24.py', '--binary', str(base/'sbin/mariadbd'), '--basedir', str(base), '--datadir', str(data), '--port', '13310'], log)
        for suite in suites:
            run(['node', 'tests/reset-isolated-db.js'], log)
            run(['node', suite], log)
            if suite == 'tests/test-p24r15-graphs-live.js':
                run(['node', 'tests/test-sqlite-live.js'], log)
        if args.suite in ('full', 'remainder', 'tail', 'archive', 'metadata', 'ui'):
            if args.suite in ('remainder', 'tail', 'archive', 'metadata', 'ui'):
                for name in ['start-control-regression.json','operator-config-regression.json','operator-ui-regression.json','p24r16-system-regression.json']:
                    proof=json.loads((ROOT/'verification'/name).read_text())
                    if proof['status']!='pass' or proof['application_version']!=(ROOT/'VERSION').read_text().strip():
                        raise RuntimeError('Missing current prior native proof: '+name)
                    for source,digest in proof['source_fingerprints'].items():
                        if hashlib.sha256((ROOT/source).read_bytes()).hexdigest()!=digest:
                            raise RuntimeError('Prior native source changed: '+source)
                (ROOT/'verification/native-integration.log').write_text('\nFOLLOWUP NATIVE GROUP\n'.join(p.read_text() for p in [ROOT/'verification/native-full.log', ROOT/'verification/native-remainder.log', ROOT/'verification/native-tail.log', ROOT/'verification/native-archive.log', ROOT/'verification/native-ui.log', ROOT/'verification/native-metadata.log'] if p.exists()))
            else:
                shutil.copyfile(log_path, ROOT/'verification/native-integration.log')
            observed = subprocess.check_output([str(base/'bin/mariadb'), '--no-defaults', '--host=127.0.0.1', '--port=13310', '-uroot', '-N', '-e', 'SELECT VERSION()'], env=env, text=True).strip()
            evidence = {'application_version': (ROOT/'VERSION').read_text().strip(), 'completed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'server_version': observed, 'server_binary_sha256': hashlib.sha256((base/'sbin/mariadbd').read_bytes()).hexdigest(), 'node_version': subprocess.check_output(['node','--version'],env=env,text=True).strip(), 'plugin_version': '0.80.3', 'test_transport': 'isolated localhost SQL/NR; controlled HA transport and actual Chromium shell; target HA UAT not run', 'native_dateStrings_timezone': 'UTC', 'buffer_pool_bytes': 134217728, 'address_space_limit_bytes': 4*1024**3, 'malloc_arena_max': 2, 'target_ha_uat': 'not_run', 'log': 'verification/native-integration.log', 'status': 'pass'}
            (ROOT/'verification/native-environment.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n')
        print('RESULT: PASS native '+args.suite, flush=True)
finally:
    if server is not None:
        server.terminate()
        try:
            server.wait(timeout=10)
        except subprocess.TimeoutExpired:
            server.kill(); server.wait()
        if (scratch/'server.log').exists():
            shutil.copyfile(scratch/'server.log', ROOT/'verification'/('native-'+args.suite+'-server.log'))
    shutil.rmtree(scratch, ignore_errors=True)
