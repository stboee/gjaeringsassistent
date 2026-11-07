#!/usr/bin/env python3
from pathlib import Path
import re,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from system_metadata import load_system_metadata
m=load_system_metadata(ROOT)
version=(ROOT/'VERSION').read_text().strip()
errs=[]; passed=[]
def ok(c,label): (passed if c else errs).append(label)
entities=[e for e in m['entities'] if e['status']=='active']
events=[e for e in m['events'] if e['status']=='active']
functions=[f for f in m['functions'] if f['status']=='active']
allowed_registry_status={'active','planned','deprecated'}
ok(all(e.get('status') in allowed_registry_status for e in m['entities']),'all HA entity registry statuses satisfy DDL CHECK constraint')
ok(all(e.get('status') in allowed_registry_status for e in m['events']),'all HA event registry statuses satisfy DDL CHECK constraint')
ok(all(f.get('status') in allowed_registry_status for f in m['functions']),'all system function registry statuses satisfy DDL CHECK constraint')
deps=m['dependencies']; check_defs=m['system_check_definitions']; check_exps=m['system_check_expectations']
ok(len(entities)==75,'75 active HA entities in MariaDB metadata seed')
ok(len(events)==21,'21 active HA events in MariaDB metadata seed')
ok(len(check_defs)==15 and {d['check_id'] for d in check_defs}>={'frontend_publishing','measurement_source','schema','runtime_issues'},'15 DB-defined Systemkontroll checks include Frontendpublisering, Målekilde and Aktive driftsfeil')
expmap={(e['check_id'],e['expectation_key']):(e.get('expected_text'),e.get('expected_number')) for e in check_exps}
ok(expmap.get(('schema','base_tables'))==(None,202) and expmap.get(('schema','views'))==(None,178) and expmap.get(('frontend_publishing','application_version'))==(version,None),'Systemkontroll expectations are DB-seeded for schema and frontend release')
ok(len({e['entity_id'] for e in entities})==75 and len({e['config_id'] for e in entities})==75,'HA entity/config identities are unique')
buttons=[e for e in entities if e['entity_type']=='button']; states=[e for e in entities if e['entity_type']!='button']
ok(len(buttons)==11 and len(states)==64,'HA registry separates 11 registration-only buttons and 64 state-bearing entities')
ok(all(e['bootstrap_mode']=='registration_only' and e['bootstrap_slot'] is None for e in buttons),'buttons are registration-only')
ok(sorted(int(e['bootstrap_slot']) for e in states)==list(range(1,65)) and all(e['bootstrap_value'] is not None or e['bootstrap_mode']=='runtime' for e in states),'all state-bearing entities have DB bootstrap values and stable slots')
# Physical DB objects referenced by dependencies must exist in active DDL/views.
ddl=(ROOT/'sql/00-template-schema.sql').read_text(encoding='utf-8')+'\n'+(ROOT/'sql/10-runtime-schema.sql').read_text(encoding='utf-8')
views=(ROOT/'sql/20-views.sql').read_text(encoding='utf-8')
tables=set(re.findall(r'CREATE TABLE IF NOT EXISTS\s+([A-Za-z0-9_]+)',ddl,re.I))
viewnames=set(re.findall(r'CREATE OR REPLACE VIEW\s+([A-Za-z0-9_]+)',views,re.I))
known={'table:'+x for x in tables}|{'view:'+x for x in viewnames}|{'ha:'+e['entity_id'] for e in entities}|{'event:'+e['event_type'] for e in events}|{'frontend:fermentation-overview','frontend:verification-overview','frontend:verification-export-json','frontend:verification-export-html'}
missing=sorted({d['object_id'] for d in deps}-known)
ok(not missing,'all seeded dependency object IDs resolve to physical/registered information objects')
# Every active function participates in at least one chain.
dep_by_func={f['function_id']:[] for f in functions}
for d in deps:
    if d['function_id'] in dep_by_func: dep_by_func[d['function_id']].append(d)
ok(all(dep_by_func.values()),'every active system function has an information dependency')
demo_rel={(d['object_id'],d['relation_type']) for d in dep_by_func.get('start_demo',[])}
expected_demo_rel={
 ('table:demo_reference_profiles','reads'),
 ('table:demo_reference_measurements_5m','reads'),
 ('table:demo_reference_data_gaps','reads'),
 ('table:measurements_5m','writes'),
 ('table:measurement_data_gaps','writes'),
}
ok(expected_demo_rel<=demo_rel,'reference demo lineage covers fixture reads and runtime measurement/gap writes')
live_rel={(d['object_id'],d['relation_type']) for d in dep_by_func.get('ingest_home_assistant_measurements',[])}
expected_live_rel={('table:measurement_source_profiles','reads'),('table:session_measurement_sources','reads'),('table:session_measurement_sources','writes'),('table:measurements_5m','writes'),('table:measurement_data_gaps','writes')}
ok(expected_live_rel<=live_rel,'Home Assistant live-ingestion lineage covers source config, cursor, measurements and gaps')

report_rel={(d['object_id'],d['relation_type']) for d in dep_by_func.get('export_active_session_report',[])}
expected_report_views={
 'v_active_session_report_summary','v_active_session_report_session','v_active_session_report_series',
 'v_active_session_report_biology','v_active_session_report_process','v_active_session_report_observations',
 'v_active_session_report_gaps','v_active_session_report_biological_criteria','v_active_session_report_process_criteria',
 'v_active_session_report_criterion_corrections','v_active_session_report_process_exceptions',
 'v_active_session_report_process_transitions','v_active_session_report_notes','v_active_session_report_timeline',
 'v_active_session_report_actions','v_active_overview_graph_axes','v_active_analysis_graphs',
 'v_active_analysis_series','v_active_analysis_requirements','v_active_analysis_biological_markers',
 'v_active_analysis_process_markers','v_active_analysis_time_markers'
}
ok({('view:'+v,'reads') for v in expected_report_views}<=report_rel,'active report lineage declares all MariaDB report read-models')

completed_rel={(d['object_id'],d['relation_type']) for d in dep_by_func.get('export_completed_session',[])}
ok({('view:v_session_overview_graph_axes','reads'),('view:v_session_analysis_graphs','reads'),('view:v_session_analysis_requirements','reads')}<=completed_rel,'completed report lineage declares shared MariaDB graph read-models')

runcheck_rel={(d['object_id'],d['relation_type']) for d in dep_by_func.get('run_system_check',[])}
ok({('view:v_metadata_lineage_gaps','reads'),('view:v_information_object_usage','reads'),('view:v_function_producer_consumer','reads')}<=runcheck_rel,'Systemkontroll lineage reads are declared in function_information_dependencies')

# Directional HA lineage: outputs need a producer; inputs need a consumer.
dep_by_obj={}
for d in deps: dep_by_obj.setdefault(d['object_id'],[]).append(d)
producer={'writes','publishes'}; consumer={'reads','consumes','validates'}
bad=[]
for e in entities:
    rel={d['relation_type'] for d in dep_by_obj.get('ha:'+e['entity_id'],[])}
    if e['direction'] in ('nodered_to_home_assistant','bidirectional') and not (rel&producer): bad.append(e['entity_id']+':producer')
    if e['direction'] in ('home_assistant_to_nodered','bidirectional') and not (rel&consumer): bad.append(e['entity_id']+':consumer')
ok(not bad,'all HA entities are connected to the expected producer/consumer function chain')
# Events are command inputs and must have consumers.
bad_events=[e['event_type'] for e in events if not ({d['relation_type'] for d in dep_by_obj.get('event:'+e['event_type'],[])}&consumer)]
ok(not bad_events,'all active HA events have a functional consumer')
# Metadata read-models exist and Systemkontroll queries the gap view.
ok({'v_system_function_information_chain','v_metadata_lineage_gaps','v_information_object_usage','v_function_producer_consumer'}<=viewnames,'metadata lineage read-models exist')
flow=(ROOT/'nodered/flows.template.json').read_text(encoding='utf-8')
ok(all(x in flow for x in ['v_metadata_lineage_gaps','v_information_object_usage','v_function_producer_consumer','ha_entity_registry']),'Systemkontroll/bootstrap consume MariaDB metadata read paths')
# Regression: every system_functions INSERT must use physical DDL column `label`, never obsolete `name`.
seed_text=(ROOT/'sql/21-system-metadata-seed.sql').read_text(encoding='utf-8')
ok('system_functions(function_id,name' not in seed_text,'system_functions metadata seed uses physical label column, not obsolete name')
for x in passed: print('PASS',x)
for x in errs: print('FAIL',x)
if errs: raise SystemExit(1)
print(f'RESULT: PASS ({len(passed)} system-metadata/lineage checks)')
