#!/usr/bin/env python3
from pathlib import Path
import json,hashlib,re,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from package_files import package_files
errors=[]
required=[
'VERSION','README.md','RELEASE-NOTES.md','TEST-RESULTS.md','BUILD-INFO.json','RELEASE-MANIFEST.json','SHA256SUMS',
'dashboard/gjaeringsassistent-dashboard.yaml','dashboard/gjaeringsassistent-card.js','dashboard/gjaeringsassistent-card-loader.js',
'nodered/flows.template.json','nodered/package.json','installer/install.sh','installer/build-installed-flow.py',
'tests/verify-static.py','tests/verify-architecture-conformance.py','tests/verify-read-model-contract.py','tests/verify-package.py','tests/verify-ha-contract.py','tests/verify-system-metadata.py','tests/verify-docs-current.py','tests/verify-verification-model.py','tests/test-build-flow.py','tests/test-runtime-functions.js',
'tools/doc-builder.json','tools/install_doc_builder.py','tools/build_runtime.py','tools/documentation_metadata.py','tests/verify-document-preservation.py','tests/verify-interface-contracts.py','tests/test-interface-contracts.js','contracts/interface-catalog.json','contracts/publication-job.schema.json','docs/sources/document-policy.json','docs/sources/requirements-history.json','docs/sources/document-revision.json','tools/run-tests.sh','tools/build-package.py','tools/build_docs.py','tools/build_verification_registry.py','tools/write_release_verification_results.py','tools/publish_frontend.js','tools/system_metadata.py',
'compose/mariadb-service.yaml','reference/BASELINES.json','contracts/ha-node-red-contract.json',
'verification/test-catalog.json','verification/verification-model.json','verification/release-results.json',
'sql/11-runtime-routines.sql','sql/24-verification-metadata-seed.sql','sql/25-release-verification-results-seed.sql',
'docs/index.md','docs/00-DOKUMENTKART-OG-STATUS.md','docs/generated/verification-model.json']
for rel in required:
    if not (ROOT/rel).is_file(): errors.append('mangler obligatorisk fil: '+rel)
if (ROOT/'reference/docs').exists() and any((ROOT/'reference/docs').rglob('*')):
    errors.append('p23-release skal ikke inneholde komplett historisk reference/docs-dokumentasjon')

version=(ROOT/'VERSION').read_text(encoding='utf-8').strip() if (ROOT/'VERSION').exists() else ''
if not version: errors.append('VERSION mangler/er tom')
def load(rel):
    try: return json.loads((ROOT/rel).read_text(encoding='utf-8'))
    except Exception as e: errors.append(f'ugyldig {rel}: {e}'); return {}
man=load('RELEASE-MANIFEST.json'); build=load('BUILD-INFO.json'); pkg=load('nodered/package.json'); contract=load('contracts/ha-node-red-contract.json')
for name,obj in [('RELEASE-MANIFEST',man),('BUILD-INFO',build),('HA-kontrakt',contract)]:
    if obj and obj.get('version')!=version: errors.append(f'{name} versjon {obj.get("version")!r} != VERSION {version!r}')
match=re.fullmatch(r'(\d{4})\.(\d{2})\.(\d{2})-([1-9]\d*)',version)
if not match: errors.append('VERSION må bruke ÅÅÅÅ.MM.DD-N')
else:
    import datetime
    try: datetime.date(*map(int,match.groups()[:3]))
    except ValueError: errors.append('VERSION inneholder ugyldig dato')
    npm_version='.'.join(str(int(x)) for x in match.groups()[:3])+'-'+match[4]
    if pkg.get('version')!=npm_version or pkg.get('gjaeringsassistentVersion')!=version:
        errors.append('npm-versjon/prosjektversjon samsvarer ikke med datoversjonen')
for rel in man.get('required_files',[]):
    if not (ROOT/rel).is_file(): errors.append('RELEASE-MANIFEST peker på manglende fil: '+rel)
try:
    flow=json.loads((ROOT/'nodered/flows.template.json').read_text(encoding='utf-8'))
    sw=next((n.get('swVersion') for n in flow if n.get('swVersion')),None)
    if sw!=version: errors.append(f'Node-RED swVersion {sw!r} != VERSION {version!r}')
except Exception as e: errors.append('ugyldig flow: '+str(e))
pub=(ROOT/'tools/publish_frontend.js').read_text(encoding='utf-8')
m=re.search(r"const VERSION='([^']+)'",pub)
if not m or m.group(1)!=version: errors.append('publish_frontend.js VERSION samsvarer ikke med VERSION')
seed=(ROOT/'sql/21-system-metadata-seed.sql').read_text(encoding='utf-8')
for check in ('configuration','frontend_publishing'):
    if f"('{check}','application_version','{version}'" not in seed: errors.append(f'system_check_expectations {check}.application_version samsvarer ikke med VERSION')
readme=(ROOT/'README.md').read_text(encoding='utf-8')
if '[VERSION](VERSION)' not in readme or '[BUILD-INFO](BUILD-INFO.json)' not in readme: errors.append('README må lenke til autoritativ leveranseidentitet')

for group in ['dashboard','nodered','installer','sql','tests','tools','docs','compose','reference','contracts','verification']:
    d=ROOT/group
    if not d.is_dir() or not any(p.is_file() for p in d.rglob('*')): errors.append('tom/manglende komponentgruppe: '+group)

# Every Markdown documentation source must have generated HTML, without enforcing a fixed count.
for md in (ROOT/'docs').glob('*.md'):
    if not md.with_suffix('.html').is_file(): errors.append('mangler generert HTML for '+md.name)

# SHA verification for all package files except SHA itself and transient install reports.
sha=ROOT/'SHA256SUMS'
if sha.exists():
    listed={}
    for line in sha.read_text(encoding='utf-8').splitlines():
        if line.strip():
            h,rel=line.split('  ',1); listed[rel]=h
    def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
    expected=[p for p in package_files(ROOT) if p.name!='SHA256SUMS']
    expected_set={p.relative_to(ROOT).as_posix() for p in expected}
    for p in expected:
        rel=p.relative_to(ROOT).as_posix()
        if rel not in listed: errors.append('SHA256SUMS mangler '+rel)
        elif listed[rel]!=digest(p): errors.append('SHA mismatch '+rel)
    extras=sorted(set(listed)-expected_set)
    if extras: errors.append('SHA256SUMS har ukjente filer: '+', '.join(extras[:12]))

if errors:
    print('RESULT: FAIL – releasepakken er ikke komplett')
    for e in errors: print('FAIL',e)
    raise SystemExit(1)
print('RESULT: PASS – komplett p24-releasepakke uten historisk p19-dokumentsett; versjon/SHA/artefakter konsistente')
