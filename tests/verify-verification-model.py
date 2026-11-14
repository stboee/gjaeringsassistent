#!/usr/bin/env python3
from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[1]
errors=[]; checks=0

def ok(cond,msg):
    global checks
    checks+=1
    if not cond: errors.append(msg)

schema=(ROOT/'sql/00-template-schema.sql').read_text(encoding='utf-8')
runtime=(ROOT/'sql/10-runtime-schema.sql').read_text(encoding='utf-8')
views=(ROOT/'sql/20-views.sql').read_text(encoding='utf-8')
seed=(ROOT/'sql/21-system-metadata-seed.sql').read_text(encoding='utf-8')
installer=(ROOT/'installer/install.sh').read_text(encoding='utf-8')
dashboard=(ROOT/'dashboard/gjaeringsassistent-dashboard.yaml').read_text(encoding='utf-8')
card=(ROOT/'dashboard/gjaeringsassistent-card.js').read_text(encoding='utf-8')
flow=json.loads((ROOT/'nodered/flows.template.json').read_text(encoding='utf-8'))
contract=json.loads((ROOT/'contracts/ha-node-red-contract.json').read_text(encoding='utf-8'))
tests=json.loads((ROOT/'verification/test-catalog.json').read_text(encoding='utf-8'))['tests']
model=json.loads((ROOT/'verification/verification-model.json').read_text(encoding='utf-8'))

meta_tables=['verification_requirements_catalog','verification_decisions_catalog','verification_definitions','verification_requirement_links','verification_decision_requirement_links','verification_tests','verification_test_links','verification_uat_steps']
for t in meta_tables: ok(re.search(rf'CREATE TABLE(?: IF NOT EXISTS)?\s+{re.escape(t)}\b',schema,re.I) is not None,f'mangler metadata-tabell {t}')
for t in ['verification_test_runs','verification_test_results']: ok(re.search(rf'CREATE TABLE(?: IF NOT EXISTS)?\s+{re.escape(t)}\b',runtime,re.I) is not None,f'mangler resultat-tabell {t}')
for v in ['v_current_verification_test_result','v_verification_definition_status','v_requirement_verification_status','v_verification_summary','v_verification_uat_pending','v_verification_unlinked_items','v_verification_test_history']:
    ok(re.search(rf'CREATE OR REPLACE VIEW\s+{re.escape(v)}\b',views,re.I) is not None,f'mangler verification-view {v}')
ok('verification_test_results' in runtime and 'ON UPDATE' not in runtime[runtime.find('CREATE TABLE verification_test_results'):runtime.find('CREATE TABLE verification_test_results')+1800], 'testresultater skal være append-only fakta uten ON UPDATE timestamp')

# Stable IDs / referential model.
tids=[t['test_id'] for t in tests]
ok(len(tids)==len(set(tids)),'dupliserte TEST-ID-er')
for t in tests:
    ok(re.fullmatch(r'TEST-(TECH|FUNC|UAT)-\d{3}',t['test_id']) is not None,f'ugyldig TEST-ID {t["test_id"]}')
    ok(t['test_type'] in {'TECH','FUNC','UAT'},f'ugyldig test_type {t["test_id"]}')
    if t.get('automated'):
        ref=t.get('implementation_ref','').split(' :: ')[0]
        ok((ROOT/ref).is_file(),f'automatisert test peker på manglende implementasjon {t["test_id"]}: {ref}')
vids=[v['verification_id'] for v in model['verifications']]
ok(len(vids)==len(set(vids)),'dupliserte VER-ID-er')
for v in model['verifications']:
    ok(re.fullmatch(r'VER-(TECH|FUNC|UAT)-\d{3}',v['verification_id']) is not None,f'ugyldig VER-ID {v["verification_id"]}')
    for tid in v.get('tests',[]): ok(tid in tids,f'{v["verification_id"]} peker på ukjent test {tid}')
for tid in model.get('uat_steps',{}): ok(tid in tids and tid.startswith('TEST-UAT-'),f'UAT-steg peker på ukjent/ikke-UAT test {tid}')

# Build/install sources must carry metadata then result seed in dependency order.
fresh_files=json.loads((ROOT/'installer/migrations.json').read_text())['fresh_files']; pos24=fresh_files.index('sql/24-verification-metadata-seed.sql'); pos25=fresh_files.index('sql/25-release-verification-results-seed.sql')
ok(pos24!=-1 and pos25!=-1 and pos24<pos25,'installer mangler korrekt 24→25 verification seed-rekkefølge')

# HA/event/flow integration.
events={e.get('event_type'):e for e in contract.get('event_channels',[])}
for ev in ['gjaeringsassistent_verification_uat_result','gjaeringsassistent_verification_export']:
    ok(ev in events,f'HA-kontrakt mangler {ev}')
    ok(ev in seed,f'systemmetadata mangler {ev}')
nodeids={n.get('id') for n in flow}
for nid in ['p23_verification_uat_event','p23_verification_export_event','p23_verification_read_query','p23_verification_result','p23_verification_export_result']:
    ok(nid in nodeids,f'flow mangler {nid}')

# ASCII code columns must not be returned as CASE result alongside Norwegian UTF-8 labels.
# MariaDB may otherwise raise 'Illegal mix of collations for operation case' at runtime.
for nid in ['p23_verification_read_query','p23_verification_export_query']:
    n=next((x for x in flow if x.get('id')==nid),{})
    code=n.get('func','')
    for bad in ['ELSE s.test_type','ELSE t.test_type','ELSE r.verification_status','ELSE v.verification_status']:
        ok(bad not in code,f'{nid} blander ASCII-kolonne med UTF-8-label i CASE-resultat: {bad}')
    ok("ELSE 'Ukjent' END AS test_type_display" in code,f'{nid} mangler kollasjonssikker test_type_display')

# UI is presentation/ingress; DB owns summary/status.
ok('path: verifikasjon' in dashboard and 'view: verification' in dashboard,'dashboard mangler Verifikasjon-fane')
ok('view: verification-summary' in dashboard,'Teknisk mangler kompakt verifikasjonssammendrag')
ok('gjaeringsassistent_verification_uat_result' in card,'frontend mangler UAT-eventingress')
ok('gjaeringsassistent_verification_export' in card,'frontend mangler verifikasjonseksport')
ok('verification-overview.json' in card,'frontend mangler DB-publisert verifikasjonsreadmodel')
# Reject obvious frontend creation of pass/fail status from counts; filtering/formatting is allowed.
for bad in ['coveragePercent','verificationCoverage','calculateVerificationStatus','deriveVerificationStatus']:
    ok(bad not in card,f'frontend inneholder alternativ verification-statuslogikk: {bad}')

# Export must produce both formats from one query/result node.
exp=next((n for n in flow if n.get('id')=='p23_verification_export_result'),{})
ok(len(exp.get('wires',[]))==2,'export-resultat skal publisere både JSON og HTML')
code=exp.get('func','')
ok('JSON.stringify' in code and '<!doctype html>' in code.lower(),'eksport-renderer mangler JSON eller selvstendig HTML')
ok('START TRANSACTION WITH CONSISTENT SNAPSHOT' in json.dumps(flow,ensure_ascii=False),'verifikasjonseksport mangler konsistent snapshot')

if errors:
    print('RESULT: FAIL – strukturert verifikasjonsmodell')
    for e in errors: print('FAIL',e)
    raise SystemExit(1)
print(f'RESULT: PASS – strukturert verifikasjonsmodell: {checks} kontroller, {len(tests)} TEST, {len(model["verifications"])} VER')

# Installable metadata and document inspection must describe the same stable catalog.
import sys
sys.path.insert(0,str(ROOT/'tools'))
from system_metadata import insert_rows
inspection=json.loads((ROOT/'docs/generated/verification-model.json').read_text())
installed=insert_rows(ROOT/'sql/24-verification-metadata-seed.sql','verification_requirements_catalog')
fields=['requirement_id','document_id','requirement_class','status','statement','source_ref','sort_order']
assert [{k:r[k] for k in fields} for r in installed]==inspection['requirements'], 'Installer SQL requirement catalog differs from document sources'
print('PASS installable requirement catalog matches current document IDs, statements, source references and order')
