#!/usr/bin/env python3
"""Current source-bound proof for DB start and data-preserving installation."""
from pathlib import Path
import hashlib
import importlib.util
import json

root = Path(__file__).resolve().parents[1]
version = (root/'VERSION').read_text().strip()
spec = importlib.util.spec_from_file_location('database_plan', root/'installer/database-plan.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
manifest = json.loads((root/'installer/migrations.json').read_text())
digest = module.migration_digest(root, manifest)
assert module.choose_plan(root, manifest, None, 0, 0, [])['mode'] == 'fresh'
for source in manifest['supported_sources']:
    assert module.choose_plan(root, manifest, source, 202, 178, [])['mode'] == 'upgrade'
for bad in [('unknown',202,178,[]),(version,207,183,[]),(version,206,183,[])]:
    try:
        module.choose_plan(root, manifest, *bad)
    except ValueError:
        pass
    else:
        raise AssertionError('Unrecognized migration input accepted')
receipt = [{'migration_id': manifest['migration_id'], 'checksum_sha256': digest}]
assert module.choose_plan(root, manifest, version, 216, 193, receipt)['mode'] == 'reinstall'
for source, expected in manifest['patch_sources'].items():
    assert module.choose_plan(root, manifest, source, 207, 183, [expected])['mode'] == 'patch'
    for history in [[], [{**expected, 'checksum_sha256': '0'*64}]]:
        try:
            module.choose_plan(root, manifest, source, 207, 183, history)
        except ValueError:
            pass
        else:
            raise AssertionError('File upgrade accepted without a verified previous receipt')
for source, expected in manifest.get('file_sources', {}).items():
    assert module.choose_plan(root, manifest, source, 216, 193, [expected])['mode'] == 'files'
    for tables, views, history in [(207,183,[expected]),(216,193,[]),(216,193,[{**expected,'checksum_sha256':'0'*64}])]:
        try:
            module.choose_plan(root, manifest, source, tables, views, history)
        except ValueError:
            pass
        else:
            raise AssertionError('Same-schema file upgrade accepted unknown structure or receipt')
installer = (root/'installer/install.sh').read_text()
assert 'DROP DATABASE' not in installer and 'reset_database' not in installer
assert installer.index('DATABASE_PLAN=') < installer.index('docker stop')
assert installer.index('backup-database.py') < installer.index('install_database\n')
for name in ['start-control-regression.json','install-upgrade-regression.json','operator-config-regression.json','operator-ui-regression.json']:
    result = json.loads((root/'verification'/name).read_text())
    assert result['status']=='pass' and result['application_version']==version
    assert result['server_version'].startswith('12.3.3-') and result['target_ha_uat']=='not_run'
    for source, expected in result['source_fingerprints'].items():
        assert hashlib.sha256((root/source).read_bytes()).hexdigest()==expected, 'Stale native proof: '+source
print('PASS current native start/upgrade/backup proof, migration planner and absence of installer reset')

ui=json.loads((root/'verification/operator-ui-regression.json').read_text())
assert ui['ha_shell']=='controlled' and len(ui['checks'])>=4 and ui['browser_version']
print('PASS current native sensor and actual Chromium evidence; installed HA UAT remains open')

publication=json.loads((root/'verification/p24r8-presentation-regression.json').read_text())
assert publication['application_version']==version and publication['status']=='pass'
assert publication['source_publication']=={'argument_contract':['stage_path','target_path'],'json_and_gzip_readback':True,'publication_errors_visible':True}
for source, expected in publication['source_fingerprints'].items():
    assert hashlib.sha256((root/source).read_bytes()).hexdigest()==expected, 'Stale source-settings publication proof: '+source
print('PASS source-settings producer/publisher contract, actual JSON/gzip readback and visible publication failures')
