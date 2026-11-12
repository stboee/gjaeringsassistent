#!/usr/bin/env python3
"""TEST-TECH-012: physical catalog, declared HA fields and current native evidence.

This checks a generated physical catalog against DDL and integration metadata.
It does not claim that catalog coverage proves a mathematical normal form.
"""
from pathlib import Path
import hashlib, json, re

ROOT = Path(__file__).resolve().parents[1]
version = (ROOT/'VERSION').read_text().strip()
physical = json.loads((ROOT/'contracts/physical-schema.json').read_text())
contract = json.loads((ROOT/'contracts/ha-node-red-contract.json').read_text())
evidence = json.loads((ROOT/'verification/p24r15-contract-regression.json').read_text())
archive = json.loads((ROOT/'verification/p24r15-archive-regression.json').read_text())
graphs = json.loads((ROOT/'verification/p24r15-graph-regression.json').read_text())
flow = {n['id']: n for n in json.loads((ROOT/'nodered/flows.template.json').read_text())}

def split_definitions(body):
    result = []; start = 0; depth = 0; quote = None; i = 0
    while i < len(body):
        ch = body[i]
        if quote:
            if ch == quote:
                if i+1 < len(body) and body[i+1] == quote: i += 1
                else: quote = None
        elif ch in "'\"`": quote = ch
        elif ch == '(': depth += 1
        elif ch == ')': depth -= 1
        elif ch == ',' and depth == 0:
            result.append(body[start:i].strip()); start = i+1
        i += 1
    return result + [body[start:].strip()]

tables = {}; declared_keys = set()
schema = '\n'.join((ROOT/'sql'/f).read_text() for f in ['00-template-schema.sql','10-runtime-schema.sql','12-operator-schema.sql'])
for m in re.finditer(r'CREATE TABLE IF NOT EXISTS (\w+) \(([\s\S]*?)\) ENGINE[^;]+;', schema):
    name, body = m.groups(); columns = []
    for definition in split_definitions(body):
        c = re.match(r'^(\w+)\s+(VARCHAR|CHAR|TEXT|LONGTEXT|DATETIME|TIMESTAMP|DECIMAL|INTEGER|BIGINT|TINYINT|SMALLINT|INT|BLOB|LONGBLOB|MEDIUMBLOB|DOUBLE)\b', definition, re.I)
        if c: columns.append(c[1])
        fk = re.match(r'CONSTRAINT\s+(\w+)\s+FOREIGN KEY', definition, re.I)
        if fk: declared_keys.add((name, fk[1]))
    tables[name] = columns
assert set(tables) == set(physical['tables']) and len(tables) == 216
views = set(re.findall(r'CREATE OR REPLACE VIEW (\w+)', (ROOT/'sql/20-views.sql').read_text()))
assert views == set(physical['views']) and len(views) == 193
assert physical['indices'] and {i['TABLE_NAME'] for i in physical['indices']} == set(tables)
catalog = {}
for c in physical['columns']:
    catalog.setdefault(c['TABLE_NAME'], []).append(c['COLUMN_NAME'])
    assert c['COLUMN_TYPE'] and c['DATA_TYPE'] and c['IS_NULLABLE'] in ['YES','NO']
for name, columns in tables.items(): assert catalog[name] == columns, name
read = json.loads((ROOT/'contracts/read-model-columns.json').read_text())
assert read == {v: catalog[v] for v in views}
nullable = {(c['TABLE_NAME'],c['COLUMN_NAME']) for c in physical['columns'] if c['TABLE_NAME'] in tables and c['IS_NULLABLE']=='YES'}
annotations = {(a['object_id'].split(':',1)[1],a['column_name']) for a in physical['absence']}
assert nullable == annotations
assert all(a['absence_kind'] and a['explanation'] for a in physical['absence'])
assert {s['object_id'] for s in physical['semantics']} == {'table:'+t for t in tables}
assert all(s['fact_scope'] and s['normalization_note'] for s in physical['semantics'])
keys = {(k['TABLE_NAME'],k['CONSTRAINT_NAME']) for k in physical['keys']}
assert declared_keys <= keys
assert {k['TABLE_NAME'] for k in physical['keys'] if k['CONSTRAINT_NAME']=='PRIMARY'} == set(tables)
for k in physical['keys']:
    assert k['COLUMN_NAME'] in tables[k['TABLE_NAME']]
    if k['REFERENCED_TABLE_NAME']:
        assert k['REFERENCED_COLUMN_NAME'] in tables[k['REFERENCED_TABLE_NAME']]
print('PASS physical types, columns, keys, all relation annotations and exact nullable-column coverage')

entities = {e['entity_id']: e for e in contract['entities']}
fields = {(f['projection_id'],f['field_path']): f for f in contract['fields']}
assert len(contract['projections']) == 38 and len(contract['draft_bindings']) == 32
for p in contract['projections']:
    assert p['source_object_id'].split(':',1)[1] in views
    assert all((p['projection_id'],f) in fields for f in ['state','attributes','attributes.source'])
    consumer = flow[p['consumer_node_id']]
    cfg = entities[p['entity_id']]['config_id']
    assert any(flow[n].get('entityConfig') == cfg for n in consumer['wires'][p['output_slot']-1]), p['projection_id']
for node_id in ['p24_start_status_result','p24_ha_status_result','p24_ha_technical_result','p24_ha_event_result']:
    assert 'field_path' in flow[node_id]['func'] and 'required' in flow[node_id]['func']
assert 'runtime_node_id' in flow['p20_systemcheck_query']['func']
assert 'ga_read_ha_draft_projection' in flow['p20_sync_draft']['func']
assert 'ga_select_start_template_tx' in flow['p20_template_select']['func']
assert 'required_handled' in flow['p20_process_guidance_result']['func']
assert 'ready_with_exceptions' in flow['p20_process_next_result']['func']
print('PASS DB projection sources, required field contracts, physical HA wires and DB draft mappings')

assert evidence['application_version'] == archive['application_version'] == physical['application_version'] == version
assert evidence['status'] == archive['status'] == 'pass'
assert graphs['application_version'] == version and graphs['status'] == 'pass'
assert graphs['server_version'].startswith('12.3.3-') and graphs['target_ha_uat'] == 'not_run'
assert len(graphs['checks']) >= 4 and any('explicit unset' in c for c in graphs['checks'])
assert any('legacy raw graph' in c for c in archive['checks'])
assert evidence['server_version'].startswith('12.3.3-') and archive['server_version'].startswith('12.3.3-')
assert evidence['plugin_version'] == '0.80.3' and evidence['target_ha_uat'] == 'not_run'
assert evidence['table_count'] == len(tables) and evidence['view_count'] == len(views)
assert any('legacy SQLite v1' in c for c in archive['checks'])
for name, digest in evidence['source_fingerprints'].items():
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest() == digest, 'Stale native evidence: '+name
assert len(evidence['source_fingerprints']) >= 18
print('PASS current native MariaDB/plugin/archive evidence; target HA UAT remains explicitly open')
performance=json.loads((ROOT/'verification/p24r15-performance-regression.json').read_text())
assert performance['status']=='pass' and performance['application_version']==version
assert performance['server_version'].startswith('12.3.3-')
assert performance['full_overview']['rows_read']<performance['baseline_graph_total']['rows_read']*.6
assert performance['unchanged_poll']['rows_read']<performance['full_overview']['rows_read']*.3
assert performance['with_three_historical_series']['rows_read']<performance['full_overview']['rows_read']*1.15
execution=json.loads((ROOT/'contracts/read-execution-schema.json').read_text())
assert execution['sql_sha256']==hashlib.sha256((ROOT/'sql/20-views.sql').read_bytes()).hexdigest()
assert set(execution['views'])==views
import subprocess,sys
before={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in ['sql/11-runtime-routines.sql','contracts/read-execution-plan.json']}
subprocess.run([sys.executable,str(ROOT/'tools/build_read_queries.py')],check=True)
assert before=={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in before},'read procedures must reproduce exactly from the authoritative SQL and catalog'
print('PASS measured read amplification, cheap unchanged polling, historical growth, typed SQL schema and reproducible DB read compiler')
historical=json.loads((ROOT/'verification/p24r15-historical-regression.json').read_text())
assert historical['status']=='pass' and historical['application_version']==version and historical['server_version'].startswith('12.3.3-')
assert historical['chunks']==5 and historical['measurement_count']==578 and len(historical['checks'])>=7
assert historical['target_ha_uat']=='not_run' and historical['test_sha256']==hashlib.sha256((ROOT/'tests/test-p24r15-historical-live.js').read_bytes()).hexdigest()
print('PASS bounded historical import, DB phase boundaries, later exceptions and SQLite round-trip native evidence')
print('RESULT: PASS – p24r15 schema and integration release contract')

current=json.loads((ROOT/'verification/p24r16-system-regression.json').read_text())
assert current['status']=='pass' and current['application_version']==version
assert current['server_version'].startswith('12.3.3-') and current['plugin_version']=='0.80.3'
assert current['target_ha_uat']=='not_run' and len(current['checks'])>=7
for name,digest in current['source_fingerprints'].items():
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,'Stale r16 system evidence: '+name
assert 'measurement_source_check_policy' in schema
assert "['IDLE','LIVE','DEMO','GAP']" not in flow['p20_systemcheck_result']['func']
assert 'ga_ha_ack_required' in flow['p24r16_ha_publication_ack']['func']
assert "if(msg.ga_defer_ha_projection)return null" in flow['p20_technical_event_result']['func']
print('PASS current native system-check, historical coverage and plugin publication acknowledgment evidence')
