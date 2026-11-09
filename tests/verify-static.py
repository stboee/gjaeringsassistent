#!/usr/bin/env python3
from pathlib import Path
import json,re,subprocess,tempfile,shutil,os
ROOT=Path(__file__).resolve().parents[1]
errors=[]; passed=[]
def ok(cond,label): (passed if cond else errors).append(label)

def node_by_id(flow,id_):
    return next(n for n in flow if n.get('id')==id_)

version=(ROOT/'VERSION').read_text().strip()
ok(re.fullmatch(r'\d{4}\.\d{2}\.\d{2}-[1-9]\d*',version) is not None,'release uses the agreed calendar version')
schema_verify=(ROOT/'sql/90-schema-verification.sql').read_text(encoding='utf-8')
measurement_5m_verify=re.search(r"SELECT 'measurement_5m_required_columns'.*?IF\(COUNT\(\*\)=([0-9]+).*?column_name IN \(([^)]*)\);",schema_verify,re.S)
if measurement_5m_verify:
    expected=int(measurement_5m_verify.group(1))
    named=[x for x in re.findall(r"'([^']+)'",measurement_5m_verify.group(2))]
    ok(expected==len(named)==5 and named==['sample_count','sg_min','sg_mean','sg_median','sg_max'],'measurement_5m schema verification count matches its five canonical required columns')
else:
    ok(False,'measurement_5m schema verification count matches its five canonical required columns')
flow=json.loads((ROOT/'nodered/flows.template.json').read_text(encoding='utf-8'))
ids=[n.get('id') for n in flow]; idset=set(ids)
ok(len(ids)==len(idset),'all Node-RED node ids are unique')
missing=[]
for n in flow:
    for group in n.get('wires',[]) or []:
        for target in group:
            if target not in idset: missing.append((n.get('id'),target))
ok(not missing,'all Node-RED wires resolve')
ok(sum(n.get('type')=='mysql' for n in flow)==1,'exactly one runtime mysql node')
ok(not any('sqlite' in str(n.get('type','')).lower() for n in flow),'no SQLite nodes')
func='\n'.join(str(n.get('func','')) for n in flow if n.get('type')=='function')
ok('flow.set(' not in func and 'global.set(' not in func,'no persistent domain writes to flow/global context')
ok("global.get('homeassistant')" not in node_by_id(flow,'p20_start_context_result').get('func','') and 'ga_visible_sg' not in node_by_id(flow,'p20_start_context_result').get('func',''),'Start validates only persisted DB draft; no HA SG fallback')

# Technical surface and read-model pipeline.
tech_ids={'p20_systemcheck_query','p20_systemcheck_result','p20_systemcheck_write_result','p20_technical_event_writer','p20_technical_event_result','p20_technical_catch','p20_technical_error_normalize'}
ok(tech_ids <= idset,'Technical/Systemkontroll pipeline exists')
ok({'haec_syscheck_overall_v1','haec_button_systemcheck_v1','haec_active_issues_v1','haec_tech_event_1_v1'} <= idset,'Technical HA entities exist')
ok(node_by_id(flow,'h_systemcheck_v1').get('wires')==[['p24r7_ha_check_request']],'manual Systemkontroll button uses real DB check path')
scw=node_by_id(flow,'p20_systemcheck_write_result')
scout=node_by_id(flow,'p24_ha_technical_result')
teout=node_by_id(flow,'p24_ha_event_result')
technical_views=(ROOT/'sql/20-views.sql').read_text().split('CREATE OR REPLACE VIEW v_technical_event_presentation AS',1)[1]
tew=node_by_id(flow,'p20_technical_event_result')
ok(scw.get('outputs')==1 and scout.get('outputs')==len(scout.get('wires',[]))==24,'Systemkontroll writer declares all 24 wired outputs')
ok(tew.get('outputs')==1 and teout.get('outputs')==len(teout.get('wires',[]))==8,'Technical Event result declares all 8 wired outputs including archive issue acknowledgement')
ok('LIMIT 50' in (ROOT/'sql/11-runtime-routines.sql').read_text() and 'ga_store_system_check_tx' in node_by_id(flow,'p20_systemcheck_result').get('func',''),'Systemkontroll projects up to 50 technical events')
ok('LIMIT 50' in node_by_id(flow,'p20_technical_event_writer').get('func',''),'Technical Event writer projects up to 50 events')
ok('v_ha_technical_payloads' in scw.get('func','') and all(x in technical_views for x in ["'items'","'checks'","'events'",'occurred_at_local']),'Systemkontroll publishes rich Technical read-model attributes with local timestamps')
ok('v_ha_technical_payloads' in tew.get('func','') and 'events_payload' in technical_views and 'occurred_at_local' in technical_views,'Technical Event refresh publishes rich event-list attribute with local timestamps')
ok('p20_systemcheck_startup' in idset,'Systemkontroll runs automatically after Node-RED startup')
ok(node_by_id(flow,'p20_restore_inject').get('repeat')=='' and node_by_id(flow,'p20_restore_inject').get('once') is True and 'p20_restore_retry_delay' in idset and node_by_id(flow,'p20_restore_retry_delay').get('wires')==[['p20_restore_query']],'p23r2 authoritative MariaDB startup restore retries idempotently on actual DB unavailability without periodic editable-field overwrite')
ok(node_by_id(flow,'p20_restore_result').get('wires',[[],[],[],[],[]])[4]==[],'periodic restore/reconcile does not create evaluator/systemcheck domain side effects')
ok(node_by_id(flow,'p23_live_history_retry_catch').get('scope')==['p21_live_get_history'] and node_by_id(flow,'p23_live_history_retry_catch').get('wires')==[['p21_live_poll_delay']],'p23r2 HA-history failure retries through the active-session ingest delay')
ok('NOT EXISTS' in node_by_id(flow,'p20_technical_event_writer').get('func','') and 'INTERVAL 60 SECOND' in node_by_id(flow,'p20_technical_event_writer').get('func',''),'p23r2 identical technical events are storage-deduplicated during infrastructure outages')
ok(node_by_id(flow,'p23_technical_export_reconcile').get('repeat')=='300' and 'gjaeringsassistent-teknisk-status-latest.json' in str(node_by_id(flow,'p23_technical_export_reconcile').get('payload')) and node_by_id(flow,'p23_technical_export_reconcile').get('wires')==[['p20_technical_export_query']],'p23r2 keeps a periodic DB-generated technical-status snapshot independent of manual HA event ingress')

ok("legacyPresent.length?'warning':'ok'" not in node_by_id(flow,'p20_systemcheck_result').get('func',''),'legacy HA IDs are informational when contracted entities are present')
ok({'p20_note_event_v1','p20_note_save_query','p20_note_save_result'} <= idset,'p18 Technical Notes path exists on p20 runtime')
note_event=node_by_id(flow,'p20_note_event_v1')
ok(note_event.get('type')=='server-events' and note_event.get('eventType')=='gjaeringsassistent_note_save','Technical Notes listens to the p18-compatible HA event')
router=node_by_id(flow,'p20_db_router')
ok(router.get('outputs')==len(router.get('wires',[]))==78 and all(x in router.get('func','') for x in ['note_save:8','template_editor_read:9','technical_export:13','demo_seed:15','overview_read:16','bio_time_correction:17','measurement_context:18','measurement_write:19','measurement_status:20','observation_time_correction:21','bio_eval_query:22','bio_eval_write:23','bio_criterion_context:24','bio_criterion_write:25','fg_target_context:26','fg_target_write:27','process_eval_query:28','process_eval_write:29','process_criterion_context:30','process_criterion_write:31','process_exception_context:32','process_exception_write:33','process_guidance_query:34','process_guidance_write:35','process_next_context:36','process_next_write:37','process_back_context:38','process_back_write:39','session_end_context:40','session_end_write:41','session_prepare_context:42','session_prepare_write:43','ha_registry_startup:44','session_export_read:45','session_export_verify:46','session_history_read:47','ha_ingest_context:48','ha_ingest_write:49','frontend_publish_write:50','measurement_source_read:51','draft_write:52','active_report_read:53','active_report_register:54','analysis_query:55','analysis_write:56','verification_read:57','verification_uat_context:58','verification_uat_write:59','verification_export:60','biological_exception_context:63','biological_exception_write:64','measurement_export:62','library_read:68','library_write:69','start_status_read:70']),'DB router has explicit Notes, Template, Technical export, demo, overview, measurement, evaluator, correction and HA-ingestion routes')
ok('session_notes' in node_by_id(flow,'p20_note_save_query').get('func','') and 'START TRANSACTION' in node_by_id(flow,'p20_note_save_query').get('func',''),'Technical Notes are persisted transactionally in session_notes')
ok('session_notes' in node_by_id(flow,'p20_restore_query').get('func','') and 'notes' in node_by_id(flow,'p20_restore_result').get('func',''),'Technical Notes are restored from MariaDB')
pub=node_by_id(flow,'p20_publish_status').get('func','')
ok('v_ha_status_payloads' in pub and 'JSON_MERGE_PATCH' in (ROOT/'sql/20-views.sql').read_text() and 'Ingen valgt' not in pub,'HA status publisher omits null completed_at and guarantees a valid template label')

# Current HA contract / registry handling remains stable.
tech_cfg={'haec_syscheck_writable_v1','haec_syscheck_frontend_v1','haec_syscheck_nodered_v1','haec_measurement_source_v1','haec_syscheck_runtime_v1','haec_syscheck_config_v1','haec_syscheck_time_v1','haec_datakvalitet_v1','haec_siste_maaling_v1','haec_maalingsalder_v1','haec_attention_v1'}
ok(tech_cfg <= idset,'full agreed Technical HA config set exists')
ok(node_by_id(flow,'haec_field_template_v1').get('name')=='Gjæringsassistent template','documented template entity display name is stable')
ok({'p21_ha_registry_startup','p21_ha_registry_query','p21_ha_registry_result','p21_ha_registry_api','p21_ha_bootstrap_dispatch'} <= idset,'MariaDB-driven HA registry/bootstrap pipeline exists')
ok(not ({'p20_ha_contract_reconcile_inject','p20_ha_contract_reconcile_fn','p20_ha_contract_reconcile_api','p20_ha_contract_reconcile_sg_api'} & idset),'old hard-coded HA reconciliation pipeline is removed')
ok('FROM ha_entity_registry' in node_by_id(flow,'p21_ha_registry_query').get('func','') and 'FROM ha_entity_aliases' in node_by_id(flow,'p21_ha_registry_query').get('func',''),'HA bootstrap reads entity and alias metadata from MariaDB')
ok(node_by_id(flow,'p21_ha_bootstrap_dispatch').get('outputs')==64 and len(node_by_id(flow,'p21_ha_bootstrap_dispatch').get('wires',[]))==64,'all 64 state-bearing HA entities have physical bootstrap outputs')
ok('payload.data'==node_by_id(flow,'p21_ha_registry_api').get('data') and node_by_id(flow,'p21_ha_registry_api').get('dataType')=='jsonata','generic HA registry reconcile API is message-driven')

# Complete first-measurement surface remains untouched by this Technical revision.
required_measurement_configs={'haec_field_control_method_v1','haec_field_measured_sg_v1','haec_field_sample_temp_v1','haec_field_calibration_temp_v1','haec_field_manual_temperature_v1','haec_field_pressure_v1','haec_field_cooler_setpoint_v1','haec_field_cooler_calibration_v1','haec_field_airlock_v1','haec_field_acetaldehyde_v1','haec_field_diacetyl_v1','haec_field_wort_like_v1','haec_field_sulfur_so2_v1','haec_field_sulfur_h2s_v1','haec_field_clarity_v1','haec_field_settling_yeast_v1','haec_field_settling_minutes_v1','haec_field_control_conclusion_v1','haec_field_control_note_v1'}
ok(required_measurement_configs <= idset,'complete p18 first-measurement HA entity set remains present')
ok({'haec_button_measurement_save_p19','h_measurement_save_v1','haec_corrected_sg_v1','ha_corrected_sg_v1'} <= idset and 'haec_control_error_v1' not in idset and 'ha_control_error_v1' not in idset,'Måleresultater has contracted save button and corrected-SG sensor without duplicate validation state')
ok(node_by_id(flow,'h_measurement_save_v1').get('wires')==[['p20_measurement_context_query']],'Lagre målinger has one contracted ha-button ingress')
ok({'p20_measurement_context_query','p20_measurement_context_result','p20_measurement_write_result','p20_measurement_status_event','p20_measurement_status_query','p20_measurement_status_result','p20_observation_time_result'} <= idset,'measurement save/status/time-revision pipeline exists')
ok('INSERT INTO observation_rounds' in node_by_id(flow,'p20_measurement_context_result').get('func','') and 'INSERT INTO observation_round_revisions' in node_by_id(flow,'p20_measurement_context_result').get('func',''),'manual measurement saves normalized observation + revision')
ok('supersedes_revision_id' in node_by_id(flow,'p20_measurement_status_query').get('func','') and "'status_change'" in node_by_id(flow,'p20_measurement_status_query').get('func',''),'measurement activation/deactivation is revision-based')
ok("['biological','process','pitch','observation'].includes(kind)" in node_by_id(flow,'p20_bio_time_correction_query').get('func','') and 'timeline_correction' in node_by_id(flow,'p20_bio_time_correction_query').get('func',''),'timeline correction reuses one parameterized event for biological/process/pitch/observation revisions')
ok('haec_field_og_v1' not in idset,'separate duplicate OG operator entity remains removed')
start_sql=(ROOT/'sql/start-session.sql').read_text(encoding='utf-8')
start_fn=node_by_id(flow,'p20_start_context_result').get('func','')
m=re.search(r"msg\.ga_route='start_write';msg\.topic=(\"(?:[^\"\\]|\\.)*\");",start_fn,re.S)
embedded_sql=json.loads(m.group(1)) if m else None
ok(embedded_sql==start_sql,'Node-RED Start uses packaged start-session.sql verbatim')
ok('@ga_expected_fg_min=ROUND(1 + (@ga_og - 1) * (1 - @ga_expected_attenuation_max / 100),5)' in start_sql and '@ga_expected_fg_max=ROUND(1 + (@ga_og - 1) * (1 - @ga_expected_attenuation_min / 100),5)' in start_sql,'Start derives expected FG in MariaDB from corrected OG and expected attenuation range')
ok(start_sql.count('?')==44,'Start SQL parameter count is 44 including optional historical cutoff; expected FG is derived in MariaDB from corrected OG + frozen attenuation target')
routine_sql=(ROOT/'sql/11-runtime-routines.sql').read_text(encoding='utf-8')
start_mutation_sql=start_sql+'\n'+routine_sql
ok('INSERT INTO observation_rounds' in start_mutation_sql and 'INSERT INTO observation_round_revisions' in start_mutation_sql,'Start persists initial measurement as normalized observation/revision')
ok('CALL ga_start_session_tx();' in start_sql and 'START TRANSACTION;' in routine_sql and 'COMMIT;' in routine_sql and 'DECLARE EXIT HANDLER FOR SQLEXCEPTION' in routine_sql and 'ROLLBACK;' in routine_sql and 'RESIGNAL;' in routine_sql,'Start mutation has a MariaDB-side atomic rollback boundary')
schema=(ROOT/'sql/10-runtime-schema.sql').read_text(encoding='utf-8')
schema_code='\n'.join(line for line in schema.splitlines() if not line.lstrip().startswith('--'))
ok(not re.search(r'\bJSON\b|_json\b',schema_code,re.I),'runtime schema has no JSON domain columns')

# Dashboard recreates p18 Technical operator surface, not old p18 runtime implementation.
dashboard=(ROOT/'dashboard/gjaeringsassistent-dashboard.yaml').read_text(encoding='utf-8')
card=(ROOT/'dashboard/gjaeringsassistent-card.js').read_text(encoding='utf-8')
ok('title: Måleresultater' in dashboard and 'view: measurementaction' in dashboard and 'view: measurements' in dashboard and 'correction_kind: observation' in dashboard,'dashboard recreates p17r12 Måleresultater surface')
ok(all(x in dashboard for x in ['Manuell SG','Prosessmålinger','Sensorikk 0–5','Klarhet og utfelling','Målehistorikk']),'Måleresultater includes p17r12 operator sections')
ok(all(x in card for x in ['save-measurements','measurement-status','gjaeringsassistent_measurement_status','Korriger måletidspunkt']),'measurement custom-card functions are present')
loader=(ROOT/'dashboard/gjaeringsassistent-card-loader.js').read_text(encoding='utf-8')
ok('title: Teknisk' in dashboard and 'type: custom:gjaeringsassistent-card' in dashboard and 'view: system' in dashboard and 'view: notes' in dashboard,'dashboard recreates p18 Technical system + conditional Notes cards')
ok(all(x in card for x in ['Aktive problemer','Teknisk hendelseslogg','Systemkontroll','Kjør systemkontroll','Runtime/datagrunnlag','Notater','Lagre notat','gjaeringsassistent_note_save']),'Technical card contains p18 system and Notes operator functions')
ok("callService('button','press'" in card and 'button.gjaeringsassistent_kjor_systemkontroll' in card,'Technical card invokes the contracted HA button entity')
ok('p20_systemcheck_event_v1' not in idset and not any(n.get('type')=='server-events' and n.get('eventType')=='gjaeringsassistent_system_check' for n in flow),'Systemkontroll has exactly one Node-RED command ingress: contracted ha-button')
ok(all(x in card for x in ['Eksporter Teknisk','gjaeringsassistent_technical_export','gjaeringsassistent-teknisk-status.json','_localFileStamp']),'Technical card provides local timestamp-prefixed structured JSON export')
ok({'p20_technical_export_event','p20_technical_export_query','p20_technical_export_result','p20_technical_export_file'} <= idset,'Technical export pipeline exists')
ok('/data/gjaeringsassistent/ha-public/exports/' in node_by_id(flow,'p20_technical_export_result').get('func',''),'Technical export writes through HA-public mount')
ok('ha_entity_registry' in node_by_id(flow,'p20_technical_export_query').get('func','') and 'dashboard_entities:gaHaRuntime' in node_by_id(flow,'p20_technical_export_result').get('func',''),'Technical export derives the HA runtime entity set from MariaDB registry')

# p18 Template dashboard functionality recreated on current MariaDB authority.
ok('title: Template' in dashboard and 'view: template' in dashboard and '/local/gjaeringsassistent/template-editor.json' in dashboard,'dashboard contains p18-style Template tab/read-model')
template_ids={'p20_template_editor_refresh_event','p20_template_editor_query','p20_template_editor_read_result','p20_template_editor_file','p20_template_clone_event','p20_template_clone_query','p20_template_save_event','p20_template_save_query','p20_template_discard_event','p20_template_discard_query','p20_template_editor_after_write','p20_template_editor_startup','p22_template_admin_select_event','p22_template_admin_select_query','p22_template_lifecycle_event','p22_template_lifecycle_query'}
ok(template_ids <= idset,'Template library/editor/admin pipeline exists')
ok(all(x in card for x in ['Templatebibliotek','Opprett ny template fra eksisterende versjon','Lag / åpne draft','Lagre draft','Valider','Publiser','Forkast draft','Sett utgått','Aktiver igjen','B-kriterier','P-kriterier','Ubrukte kriterietyper','gjaeringsassistent_template_draft_save']),'Template card contains full library, lifecycle and editor workflow')
ok(all(x in card for x in ['gjaeringsassistent_template_admin_select','gjaeringsassistent_template_lifecycle','new_template_id','new_name']),'Template admin UI emits DB-backed selection/lifecycle/new-identity commands')
ok('template-editor.json' in node_by_id(flow,'p20_template_editor_read_result').get('func',''),'Template read-model is published to HA-public')
query_fn=node_by_id(flow,'p20_template_editor_query').get('func','')
ok('template_editor_state' in query_fn and 'start_selected_version_id' in query_fn and 'admin_selected_version_id' in query_fn and 'active_session_version_id' in query_fn,'Template read-model reads admin selection, Start selection and active-session source as separate DB facts')
save_fn=node_by_id(flow,'p20_template_save_query').get('func','')
clone_fn=node_by_id(flow,'p20_template_clone_query').get('func','')+'\n'+(ROOT/'sql/11-runtime-routines.sql').read_text().split('CREATE PROCEDURE ga_clone_template_tx')[1].split('END//',1)[0]
discard_fn=node_by_id(flow,'p20_template_discard_query').get('func','')
lifecycle_fn=node_by_id(flow,'p22_template_lifecycle_query').get('func','')
ok('START TRANSACTION' in save_fn and 'template_versions' in save_fn and 'template_process_targets' in save_fn and 'template_biological_criteria' in save_fn,'Template draft save is a normalized MariaDB transaction')
ok("NOT EXISTS(SELECT 1 FROM v_current_session)" not in save_fn+clone_fn+discard_fn+lifecycle_fn,'Template administration is not blocked by an active session')
ok('UPDATE session_setup_draft' not in save_fn,'Publishing a template does not change Start selection')
ok("status IN ('published','retired')" in clone_fn and 'template_analysis_graphs' in clone_fn and 'template_analysis_graph_series' in clone_fn,'Draft/new-template clone accepts immutable source and preserves analysis metadata')
ok("status='retired'" in lifecycle_fn and "status='published'" in lifecycle_fn and 'DELETE FROM session_setup_draft' in lifecycle_fn,'Template lifecycle supports retire/reactivate and clears retired Start selection')
ok('p20_template_select_restore_delay' in idset and node_by_id(flow,'p20_restore_result').get('outputs')==6,'Template select is restored from authoritative DB state after option refresh')
ok('UPDATE template_versions SET status=' in save_fn and 'published' in save_fn and 'published_at=UTC_TIMESTAMP(3)' in save_fn,'Template publish makes the draft immutable/published')
ok('frontend-manifest.json' in loader and 'sha256' in loader,'frontend loader resolves the published card through runtime manifest and SHA cache busting')
frontend_ids={'p20_frontend_publish_startup','p20_frontend_publish_exec','p20_frontend_publish_json','p20_frontend_publish_ok','p20_frontend_publish_error'}
ok(frontend_ids <= idset,'p18-style Node-RED frontend publication pipeline exists')
ok(node_by_id(flow,'p20_frontend_publish_startup').get('once') is True,'frontend publisher runs automatically at Node-RED startup')
ok(node_by_id(flow,'p20_frontend_publish_exec').get('command')=='node /data/gjaeringsassistent/runtime/publish_frontend.js','frontend publisher executes staged runtime publisher')
publisher=(ROOT/'tools/publish_frontend.js').read_text(encoding='utf-8')
ok(all(x in publisher for x in ["SOURCE_DIR='/data/gjaeringsassistent/frontend-source'","PUBLIC_DIR='/data/gjaeringsassistent/ha-public'",'exactMountPoint','atomicWrite','frontend-manifest.json']),'publisher uses p18 mount-safe atomic publication model')

# Installer has install-only responsibility.
installer=(ROOT/'installer/install.sh').read_text(encoding='utf-8')
ok('frontend-source' in installer and 'runtime/publish_frontend.js' in installer,'installer stages frontend sources and publisher for Node-RED')
ok('gjaeringsassistent/ha-public/gjaeringsassistent-dashboard.yaml' not in installer and 'dashboard/frontend-manifest.json' not in installer,'installer does not bypass the HA-public mount by publishing frontend directly')
ok('91-runtime-smoke-test' not in installer and '92-negative-fk-test' not in installer,'installer does not run runtime/negative DB tests')
ok('p20_test_' not in installer and 'inject_node' not in installer,'installer does not drive synthetic Node-RED test nodes')
ok('docker restart' not in installer,'installer does not perform repeated restart cycles')
ok('button.press' not in installer and 'select.select_option' not in installer,'installer does not perform HA function tests')

# Function-node and frontend JavaScript syntax.
js_fail=[]
node_cmd=shutil.which('node')
nr_container=os.environ.get('GA_NODERED_CONTAINER','').strip()
for n in flow:
    if n.get('type')!='function': continue
    src='function __ga(msg,flow,global,node){\n'+n.get('func','')+'\n}\n'
    if node_cmd:
        with tempfile.NamedTemporaryFile('w',suffix='.js',delete=False) as tf:
            tf.write(src); p=Path(tf.name)
        r=subprocess.run([node_cmd,'--check',str(p)],capture_output=True,text=True); p.unlink(missing_ok=True)
    elif nr_container and shutil.which('docker'):
        r=subprocess.run(['docker','exec','-i',nr_container,'node','--check','-'],input=src,capture_output=True,text=True)
    else:
        js_fail.append((n.get('id'),'verken host-node eller GA_NODERED_CONTAINER er tilgjengelig')); continue
    if r.returncode: js_fail.append((n.get('id'),r.stderr.strip()))
if node_cmd:
    for rel in ['dashboard/gjaeringsassistent-card.js','dashboard/gjaeringsassistent-card-loader.js','tools/publish_frontend.js']:
        r=subprocess.run([node_cmd,'--check',str(ROOT/rel)],capture_output=True,text=True)
        if r.returncode: js_fail.append((rel,r.stderr.strip()))
ok(not js_fail,'all Function nodes and frontend JavaScript pass syntax check')

seed=(ROOT/'sql/03-w3470-template-seed.sql').read_text(encoding='utf-8')
process_rows=re.findall(r"INSERT IGNORE INTO template_process_steps\([^\n]+VALUES \('w3470-standard@3\.0'",seed)
bio_rows=re.findall(r"INSERT IGNORE INTO template_biological_phases\([^\n]+VALUES \('w3470-standard@3\.0'",seed)
ok(len(process_rows)==15,'W-34/70 seed has 15 process slots')
ok(len(bio_rows)==6,'W-34/70 seed has 6 biological phases')
schema_verify=(ROOT/'sql/90-schema-verification.sql').read_text(encoding='utf-8')
ok("w3470_six_biological_phases" in schema_verify and "IF(COUNT(*)=6,'PASS',CONCAT('FAIL: ',COUNT(*),'/6'))" in schema_verify,'release schema verification expects exactly the same 6 W-34/70 biological phases as the canonical seed')



# revised11: p17r12 visual/functional Gjæring + Biologi on p20 MariaDB/read-model.
ok("['demo','archive-action','system','notes','template','overview','report','history','biology','process','timecorrection','starttime','startaction','measurementaction','measurements','analysis','verification','verification-summary']" in card and 'view:overview' not in card,'custom card explicitly supports overview, biology, process, timecorrection and measurement views')
ok('_templateOpenDetails' in card and 'data-detail-key' in card and "addEventListener('toggle'" in card,'Template B/P details preserve expanded state across legitimate rerenders')
ok("if(this._config.view==='template'){" in card and "if(changed&&!this._templateDirty) this._loadTemplate();" in card,'Template does not rerender on unrelated HA state ticks')
ok('occurred_at_local' in card and 'Tid · Europe/Oslo' in card and 'Sist sett · lokal tid' in card,'Technical tables explicitly render local Europe/Oslo timestamps')
ok('occurred_at_local' in technical_views and "CONVERT_TZ(e.occurred_at,'+00:00','Europe/Oslo')" in technical_views,'Systemkontroll read-model includes local timestamps')
contract=json.loads((ROOT/'contracts/ha-node-red-contract.json').read_text(encoding='utf-8'))
records=contract.get('entities',contract if isinstance(contract,list) else [])
ok(any(x.get('entity_id')=='button.gjaeringsassistent_start_demo' and x.get('status','active')=='active' for x in records),'HA contract includes explicit demo button')
ok({'haec_button_demo_v1','h_demo_v1','p20_demo_prepare_query','p20_demo_prepare_result','p20_demo_seed_query','p20_demo_seed_result','p20_overview_startup','p20_overview_query','p20_overview_result','p20_overview_file'} <= idset,'Gjæring overview and explicit demo pipelines exist')
ok('Aktiv gjæring' in dashboard and 'view: overview' in dashboard and 'fermentation-overview.json' in dashboard,'Gjæring tab contains full-width p17r12-style overview card')
ok('view: demo' in dashboard and 'button.gjaeringsassistent_start_demo' in card,'Gjæring tab exposes explicit demo button before Start')
demo_prepare=node_by_id(flow,'p20_demo_prepare_result').get('func','')
ok('msg.ga_demo=true' in demo_prepare and node_by_id(flow,'p20_demo_prepare_result').get('wires',[[]])[0]==['p20_start_guard'],'demo enters the ordinary Start chain')
demo_seed=node_by_id(flow,'p20_demo_seed_query').get('func','')+'\n'+(ROOT/'sql/11-runtime-routines.sql').read_text().split('CREATE PROCEDURE ga_seed_demo_tx',1)[1]
ok(all(x in demo_seed for x in ['session_timing_revisions','measurements_5m','process_visit_revisions','biological_visit_revisions','observation_rounds']) and 'UPDATE sessions' not in demo_seed,'demo seeds deterministic MariaDB history after normal Start')
ok('is_demo TINYINT' in schema,'session schema records explicit demo provenance')
overview_route=node_by_id(flow,'p20_overview_query').get('func','')
ok('CALL ga_read_overview' in overview_route and 'CALL ga_poll_overview' in overview_route,'overview uses compiled read and DB polling decision')
overview_q=(ROOT/'tools/overview_reads.sql').read_text()
ok(all(x in overview_q for x in ['v_active_session_summary','v_session_display_measurement_series','session_process_targets','biological_visits','recommendations']),'Gjæring overview read-model is sourced from current MariaDB history/targets')
ok("/data/gjaeringsassistent/ha-public/fermentation-overview.json" in node_by_id(flow,'p20_overview_result').get('func',''),'Gjæring overview is published through HA-public mount')
ok(all(x in card for x in ['Biologisk forløp','Sensorikk og kommentarer','Neste prosesstrinn','show_in_overview','_analysisChart','bio-band']),'Gjæring overview renders p17r12-style KPI/timeline/SG/temperature/pressure/observation surfaces')

# revised11: p17r12 Biologi view and revision-based biological timeline correction.
ok('title: Biologi' in dashboard and 'view: biology' in dashboard and 'view: timecorrection' in dashboard and 'correction_kind: biological' in dashboard,'dashboard contains p17r12-style Biologi tab with biological view and time correction')
ok('title: Status' not in dashboard and 'Tetthet registreres kun som SG.' not in dashboard,'redundant Gjæring Status and SG-only information cards are removed')
ok(all(x in card for x in ['Biologisk vurderingsgrunnlag','Biologisk status og historikk','Korriger starttidspunkt for biologisk fase','gjaeringsassistent_timeline_correction']),'Biologi custom-card surface includes p17r12 evaluation/history and time-correction operator functions')
bio_ids={'p20_bio_time_correction_event','p20_bio_time_correction_query','p20_bio_time_correction_result'}
ok(bio_ids <= idset,'biological timeline correction pipeline exists')
bio_event=node_by_id(flow,'p20_bio_time_correction_event')
ok(bio_event.get('type')=='server-events' and bio_event.get('eventType')=='gjaeringsassistent_timeline_correction','Biologi correction listens to timeline-correction HA event')
bio_corr=node_by_id(flow,'p20_bio_time_correction_query').get('func','')
ok('CALL ga_correct_visit_time_tx(?,?,?,?,?)' in bio_corr and all(x in routine_sql for x in ['INSERT INTO biological_visit_revisions','supersedes_revision_id','operator_correction']) and 'UPDATE biological_visit_revisions' not in routine_sql,'Biological start-time correction creates a new current revision instead of overwriting historical timing')
ok('UPDATE biological_visit_revisions SET started_at' not in bio_corr,'Biological time correction never mutates historical started_at in place')
ok(all(x in overview_q for x in ['session_biological_criteria','session_biological_criterion_parameter_values','v_biological_transition_evidence','v_current_biological_candidate_evaluation','v_biological_evaluation_criterion_read_model']),'Biologi read-model is sourced from frozen criteria and authoritative transition/current evaluation evidence')
overview_result=node_by_id(flow,'p20_overview_result').get('func','')
ok(all(x in overview_result for x in ['transition_evaluations','candidate_phase_id']) and 'Ingen biologisk evaluering er registrert ennå.' not in overview_result,'Biologi read-model exposes persisted evidence without fabricating missing evaluator output')

# revised7/revised8 field fixes from target exports.
tpl_query=node_by_id(flow,'p20_template_editor_query').get('func','')
ok("AS _set,* FROM" not in tpl_query and "AS _set,t.* FROM template_defaults t" in tpl_query,'Template read query uses MariaDB-valid qualified wildcards')
ok(node_by_id(flow,'cfg_mariadb_p20r1').get('tz')=='Z','MariaDB mysql2 connection uses unambiguous UTC timezone token Z')
ok(node_by_id(flow,'cfg_mariadb_p20r1').get('charset')=='UTF8MB4_UNICODE_CI','MariaDB runtime connection declares the schema collation')
ok(all('SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;' in p.read_text() for p in (ROOT/'sql').glob('*.sql') if 'SET NAMES' in p.read_text()),'SQL object creation and seed connections declare the schema collation')
ok(all("'"+x+"' COLLATE utf8mb4_unicode_ci AS gap_type" in (ROOT/'sql/20-views.sql').read_text() for x in ['no_dependency','missing_producer','missing_consumer']),'lineage gap constants have explicit collation when filtered by Systemkontroll')
sys_result=node_by_id(flow,'p20_systemcheck_result').get('func','')
ok('msg.ga_ha_states' in sys_result and node_by_id(flow,'p24r7_ha_check_api').get('type')=='ha-api','Systemkontroll uses freshly retrieved HA get_states API evidence')
ok('aliasPresent' in sys_result and 'gamle aliaser finnes også' in sys_result and "aliasPresent.length?'warning'" not in sys_result,'legacy HA aliases come from DB metadata and do not keep Systemkontroll in warning state')
sys_write=node_by_id(flow,'p20_systemcheck_write_result').get('func','')
ok('v_ha_technical_payloads' in sys_write and 'ha_projection_fields' in sys_write,'Systemkontroll reads complete DB payload and field contracts')
ok("timeZone:'Europe/Oslo'" in card,'dashboard renders operational timestamps explicitly in Europe/Oslo')

# revised8 target-log fixes: release metadata, timezone-independent clock check, robust post-Start timestamps.
installer=(ROOT/'installer/install.sh').read_text(encoding='utf-8')
ok("UPDATE database_metadata SET application_version='%s'" in installer,'installer stamps database metadata from VERSION')
ok("application_version='0.1.0-prototype20-r1-revised6'" not in (ROOT/'sql/90-schema-verification.sql').read_text(encoding='utf-8'),'schema verification no longer hardcodes stale release metadata')
ok("UNIX_TIMESTAMP() AS database_epoch" in node_by_id(flow,'p20_systemcheck_query').get('func',''),'Systemkontroll reads current UNIX epoch without interpreting UTC as local time')
ok("database_epoch" in node_by_id(flow,'p20_systemcheck_result').get('func','') and 'database_utc' not in node_by_id(flow,'p20_systemcheck_result').get('func',''),'Systemkontroll evaluator uses epoch clock source')
ok('v_ha_technical_payloads' in node_by_id(flow,'p20_systemcheck_write_result').get('func','') and 'checked_at_local' in (ROOT/'sql/20-views.sql').read_text(),'Systemkontroll projection tolerates Date/SQL timestamps and publishes local checked time')


# revised13: exact acknowledgements and restored B-phase evaluator.
restore_fn=node_by_id(flow,'p20_restore_result').get('func','')
ok('Ikke validert etter omstart' not in restore_fn and 'ha_control_error_v1' not in idset,'obsolete observation-validation sensor is absent from restore')
sys_write=node_by_id(flow,'p20_systemcheck_write_result').get('func','')
ok('checked_at_local' in technical_views and 'TIMESTAMPDIFF(MINUTE,run.checked_at' in technical_views,'Systemkontroll last-run timestamp uses valid Oslo-offset ISO state')
note_result=node_by_id(flow,'p20_note_save_result').get('func','')
ok(all(x in note_result for x in ['note_operation_id','note_status','NOTE_SAVED','NOTE_SAVE_FAILED']),'Notes use exact MariaDB acknowledgement and publish operation status')
meas_result=node_by_id(flow,'p20_measurement_write_result').get('func','')
ok(all(x in meas_result for x in ['ga_operation_id','MEASUREMENT_SAVED','correlation_id:op']) and node_by_id(flow,'p20_measurement_write_result').get('outputs')==5 and node_by_id(flow,'p20_measurement_write_result').get('wires',[[],[],[],[]])[3]==['p22_analysis_query'],'Measurement save writes DB-backed acknowledgement event and triggers biology evaluator')
bq=node_by_id(flow,'p20_bio_eval_query').get('func',''); be=node_by_id(flow,'p20_bio_eval_result').get('func','')
ok(all(x in bq for x in ['session_biological_criteria','session_biological_criterion_parameter_values','v_current_biological_criterion_revision','measurements_5m','v_current_observation_revision']),'B evaluator reads frozen criteria, revisions and persisted measurement history')
ok(all(x in be for x in ['biological_evaluations','biological_evaluation_criteria','biological_evaluation_criterion_parameter_values','biological_transitions','p22r5-declarative-engine']),'B evaluator persists criteria evidence and biological transitions in MariaDB')
ok('INSERT INTO biological_visit_revisions' in be and 'supersedes_revision_id' in be and 'UPDATE biological_visit_revisions' not in be,'automatic B transition is revision-based and history preserving')
ok(node_by_id(flow,'p20_demo_seed_result').get('wires',[[],[]])[1]==['p22_analysis_query'],'demo runs the same generic analysis pipeline before B evaluation after ordinary Start and seed')
ok('is_demo' not in node_by_id(flow,'p20_note_save_query').get('func','') and 'v_active_session' in node_by_id(flow,'p20_note_save_query').get('func',''),'notes accept demo sessions through the ordinary active-session path')
ok('is_demo' not in node_by_id(flow,'p20_measurement_context_result').get('func',''),'manual measurement save does not special-case or reject demo sessions')
card=(ROOT/'dashboard/gjaeringsassistent-card.js').read_text(encoding='utf-8')
ok(all(x in card for x in ['_waitFor','note_operation_id','measurement_feedback','systemkontroll_sist_kjort']),'frontend waits for backend/DB acknowledgement for Systemkontroll, notes and measurements')


# revised15: prototype architecture cleanup and correction model restoration.
contract=json.loads((ROOT/'contracts/ha-node-red-contract.json').read_text(encoding='utf-8'))
active_contract=[e for e in contract['entities'] if e.get('status')=='active']
ok(len(active_contract)==len(contract['entities'])==75 and contract.get('normative') is False and 'ha_entity_registry' in contract.get('generated_from',''),'generated HA contract mirrors 75 active MariaDB entities and is explicitly non-normative')
ok(any(e.get('entity_id')=='number.gjaeringsassistent_malt_sg' and e.get('config_id')=='haec_field_measured_sg_v1' for e in active_contract),'measured SG uses clean contracted entity/config ID')
ok(not any(e.get('entity_id') in {'number.gjaeringsassistent_kontroll_raverdi','sensor.gjaeringsassistent_observasjonsvalidering'} for e in contract['entities']),'legacy raw-SG and observation-validation entities are removed')
ok(not contract.get('temporary_deviations'),'temporary deviations list is empty in revised19 prototype contract')

default_schema=(ROOT/'sql/00-template-schema.sql').read_text(encoding='utf-8')
metadata_seed=(ROOT/'sql/21-system-metadata-seed.sql').read_text(encoding='utf-8')
ok(all(x in default_schema for x in ['ha_entity_registry','ha_event_registry','system_functions','information_objects','function_information_dependencies']),'system metadata tables are part of MariaDB schema')
ok(metadata_seed.count('INSERT INTO ha_entity_registry(')==75 and metadata_seed.count('INSERT INTO ha_event_registry(')==23,'system metadata seed contains 75 HA entities and 23 events including deprecated event')
ok('information_schema.tables' in metadata_seed and "CONCAT('table:',table_name)" in metadata_seed and "CONCAT('view:',table_name)" in metadata_seed,'table/view information objects are discovered from MariaDB INFORMATION_SCHEMA')
ok('function_information_dependencies' in metadata_seed and 'ha_contract_bootstrap' in metadata_seed and 'run_system_check' in metadata_seed,'function-information lineage metadata is seeded')
default_seed=(ROOT/'sql/03-w3470-template-seed.sql').read_text(encoding='utf-8')
default_fields=['og_default','sample_temperature_c_default','calibration_temperature_c_default','manual_temperature_c_default','pressure_bar_default','cooler_setpoint_c_default','cooler_calibration_offset_c_default','airlock_activity_default','acetaldehyde_level_default','diacetyl_level_default','wort_like_level_default','sulfur_so2_level_default','sulfur_h2s_level_default','clarity_level_default','settling_yeast_level_default','settling_minutes_default','user_conclusion_default','measurement_note_default']
ok(all(x in default_schema for x in default_fields) and all(x in default_seed for x in default_fields),'published template owns complete persisted start defaults including OG/SG')
ok('og_default DECIMAL(18,6) NOT NULL' in default_schema and '1.050' in default_seed,'W-34/70 has a valid persisted OG default')
start_guard=node_by_id(flow,'p20_start_guard').get('func',''); start_ctx=node_by_id(flow,'p20_start_context_result').get('func','')
ok('ga_visible_sg' not in start_guard+start_ctx and "homeassistant" not in start_guard.lower(),'Start has no HA-value fallback or SG workaround')
ok('visibleStartSg' not in sys_result and 'startReadiness.message' in sys_result and 'v_start_readiness' in node_by_id(flow,'p20_systemcheck_query').get('func',''),'Systemkontroll consumes DB-owned start readiness')
forbidden=['maximum_age_minutes??1e12','minimum_samples||0','minimum_span_hours||0','current_phase_order||1','current_visit_revision_no||1']
ok(not any(x in be for x in forbidden) and 'invalid_configuration' in be,'B evaluator rejects missing required configuration instead of guessing fallbacks')
ok(node_by_id(flow,'p20_restore_result').get('outputs')==6 and 'Ikke validert etter omstart' not in node_by_id(flow,'p20_restore_result').get('func',''),'restore has no dead observation-validation output')
ok(all(x in overview_q for x in ['MEASUREMENT_SAVED','MEASUREMENT_REJECTED','session_biological_correctable_parameters','v_current_biological_criterion_revision','v_current_fermentation_target']),'overview read-model carries DB-backed measurement feedback and correction state')
ok('Korriger kriterium for denne sessionen' in card and 'gjaeringsassistent_criterion_correction' in card and 'Korriger forventet FG for denne sessionen' not in card and 'gjaeringsassistent_fermentation_target_correction' not in card,'Biologi GUI keeps criterion correction but removes independent FG-target correction')
ok({'p20_bio_criterion_correction_event','p20_bio_criterion_correction_context','p20_bio_criterion_correction_context_result','p20_bio_criterion_correction_write_result','p20_fg_target_correction_event','p20_fg_target_correction_context','p20_fg_target_correction_context_result','p20_fg_target_correction_write_result'} <= idset,'Biologi correction backend pipelines exist')
ok(node_by_id(flow,'p20_bio_criterion_correction_event').get('eventType')=='gjaeringsassistent_criterion_correction' and node_by_id(flow,'p20_fg_target_correction_event').get('wires')==[[]],'Biology criterion correction remains active while obsolete FG-target correction listener is disconnected')
ok('c.measured_at?sqlTime(c.measured_at):null' in be,'B evaluator normalizes measured_at to MariaDB DATETIME format')
ok("this._config.view==='notes'" in card and '_notesHassSignature' in card and "classList?.contains('note-text')" in card,'Notes card remains focus-safe')


# revised16: DB-backed active measurement draft, Prosesstrinn evaluator and recommendation motor.
ok('CREATE TABLE IF NOT EXISTS measurement_input_draft' in schema,'active measurement input has a MariaDB draft table')
ok('UNIQUE KEY uq_template_biology_calculations__model (version_id,calculation_id,model_id)' in default_schema,'template biology calculation parent exposes composite key required by child foreign keys')
ok('CREATE TABLE IF NOT EXISTS ha_entity_input_bindings' in default_schema and 'CREATE TABLE IF NOT EXISTS ha_entity_input_value_mappings' in default_schema,'HA input mapping is normalized in MariaDB metadata tables')
# Release schema-verification count must follow the actual clean schema, even though it is not installer-critical.
schema_sql='\n'.join((ROOT/'sql'/name).read_text(encoding='utf-8') for name in ['00-template-schema.sql','10-runtime-schema.sql'])
actual_tables=sum(1 for line in schema_sql.splitlines() if line.startswith('CREATE TABLE IF NOT EXISTS '))
verify_sql=(ROOT/'sql/90-schema-verification.sql').read_text(encoding='utf-8')
m=re.search(r"base_table_count'[\s\S]*?COUNT\(\*\)=(\d+)",verify_sql)
ok(bool(m),'schema verification exposes expected base-table count')
expected_tables=int(m.group(1)) if m else -1
ok(expected_tables==actual_tables,f'schema verification base-table count matches DDL ({actual_tables})')
# Installer view/entity expectations must track generated release contracts as well.
views_sql=(ROOT/'sql/20-views.sql').read_text(encoding='utf-8')
actual_views=len(re.findall(r'(?im)^CREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+',views_sql))
mv=re.search(r"view_count'[\s\S]*?COUNT\(\*\)=(\d+)",verify_sql)
ok(bool(mv),'schema verification exposes expected view count')
expected_views=int(mv.group(1)) if mv else -1
ok(expected_views==actual_views,f'schema verification view count matches DDL ({actual_views})')
metadata_seed=(ROOT/'sql/21-system-metadata-seed.sql').read_text(encoding='utf-8')
msv=re.search(r"\('schema','views',NULL,(\d+),",metadata_seed)
ok(bool(msv),'Systemkontroll metadata exposes expected view count')
metadata_expected_views=int(msv.group(1)) if msv else -1
ok(metadata_expected_views==actual_views==expected_views,f'Systemkontroll/schema-verification view counts match DDL ({actual_views})')
ha_contract=json.loads((ROOT/'contracts/ha-node-red-contract.json').read_text(encoding='utf-8'))
actual_ha=len(ha_contract.get('entities',[]))
mh=re.search(r"ha_entity_registry_count'[\s\S]*?COUNT\(\*\)=(\d+)",verify_sql)
ok(bool(mh),'schema verification exposes expected HA entity count')
expected_ha=int(mh.group(1)) if mh else -1
ok(expected_ha==actual_ha,f'schema verification HA entity count matches generated contract ({actual_ha})')
ok("measurement_input_draft_present" in verify_sql,'schema verification explicitly checks active measurement draft table')
meas_query=node_by_id(flow,'p20_measurement_context_query').get('func','')
ok('measurement_input_draft' in meas_query and "global.get('homeassistant')" not in meas_query,'measurement save reads persisted MariaDB draft, never HA global state')
draft_update=node_by_id(flow,'p20_draft_update').get('func','')
draft_binding=node_by_id(flow,'p22_draft_binding_result').get('func','')
ok('ha_entity_input_bindings' in draft_update and 'ha_entity_input_value_mappings' in draft_update,'HA input binding is read from MariaDB metadata, not a local entity map')
ok('UPDATE measurement_input_draft' in draft_binding and 'UPDATE session_setup_draft' in draft_binding and 'mapped_value' in draft_binding,'DB-owned input binding drives pre-Start/active draft persistence and select conversion')
ok('const map={' not in draft_update and 'pitch_mode_id' not in draft_update,'draft ingress contains no hard-coded HA→domain mapping')
ok('ga_measurement_draft' in node_by_id(flow,'p20_restore_result').get('func','') and 'ga_read_ha_draft_projection' in node_by_id(flow,'p20_sync_draft').get('func',''),'active measurement draft round-trips MariaDB → HA through restore/sync')
ok('title: Prosesstrinn' in dashboard and 'view: process' in dashboard,'dashboard restores dedicated Prosesstrinn tab')
process_ids={'p20_process_eval_query','p20_process_eval_result','p20_process_eval_write_result','p20_process_criterion_correction_context','p20_process_criterion_correction_context_result','p20_process_criterion_correction_write_result','p20_process_exception_event','p20_process_exception_context','p20_process_exception_context_result','p20_process_exception_write_result','p20_process_guidance_query','p20_process_guidance_result','p20_process_guidance_write_result','p20_process_next_query','p20_process_next_result','p20_process_next_write_result','p20_process_back_query','p20_process_back_result','p20_process_back_write_result'}
ok(process_ids <= idset,'Prosesstrinn evaluator/correction/exception/guidance/transition pipelines exist')
pq=node_by_id(flow,'p20_process_eval_query').get('func',''); pe=node_by_id(flow,'p20_process_eval_result').get('func','')
ok(all(x in pq for x in ['session_process_criteria','session_process_criterion_parameter_values','v_current_process_criterion_revision','measurements_5m','session_process_targets']),'P evaluator reads frozen process criteria, revisions, exceptions and persisted measurements')
ok(all(x in pe for x in ['process_evaluations','process_evaluation_criteria','process_evaluation_criterion_parameter_values','recommendations','invalid_configuration']),'P evaluator persists evidence and recommendation without guessed required configuration')
ok(node_by_id(flow,'p20_process_exception_event').get('eventType')=='gjaeringsassistent_process_criterion_exception','process criterion exception has one explicit parameterized event ingress')
ok(node_by_id(flow,'h_process_next_v1').get('wires')==[['p20_process_next_query']] and node_by_id(flow,'h_process_back_v1').get('wires')==[['p20_process_back_query']],'Next/Back each have one contracted ha-button ingress')
ok(all(x in card for x in ['Korriger kriterium for denne sessionen','Håndter kriterieavvik','Klar med kriterieavvik','Kriteriekorreksjon / fravik','criterion-handling','_renderProcess','process-next','process-back']),'Prosesstrinn GUI exposes correction/exception as first-class visible handling controls')
ok(all(x in card for x in ['_refreshOverviewUntil','Bekreft kriteriekorreksjonen før den sendes.','review_message','Kriteriefravik registrert og readiness er oppdatert.']),'p21r4 process actions give immediate validation and poll for persisted read-model acknowledgement')
ok(all(x in card for x in ['_interactiveOpen','_bindInteractiveDetails','_interactiveEditing','data-detail-key']) and 'criterion-correction' in card,'interactive Biology/Process details preserve open/edit state across 15 s read-model refresh')
ok('Ingen gyldig prosessanbefaling er registrert.' in card and 'Evaluator og anbefalingsmotor er ikke tilbakeført ennå.' not in card,'Gjæring recommendation card is driven by restored process recommendation motor')
ok(all(x in overview_q for x in ['v_current_process_candidate_evaluation','v_process_transition_evidence','v_process_evaluation_criterion_read_model','process_criterion_exceptions','v_current_process_criterion_revision','v_recommendations_effective']),'shared overview read-model carries current/transition process evidence, corrections, exceptions and recommendation')

# revised18: MariaDB-native concurrency + append-only runtime history.
runtime_schema=(ROOT/'sql/10-runtime-schema.sql').read_text(encoding='utf-8')
views_sql=(ROOT/'sql/20-views.sql').read_text(encoding='utf-8')
flow_text=(ROOT/'nodered/flows.template.json').read_text(encoding='utf-8')
ok('is_current' not in runtime_schema and 'current_guard' not in runtime_schema,'runtime revision schema has no mutable current flags')
ok(all(x in runtime_schema for x in ['uq_session_timing_revisions__supersedes','uq_session_fermentation_target_revisions__supersedes','uq_session_biological_criterion_revisions__supersedes','uq_session_process_criterion_revisions__supersedes','uq_process_visit_revisions__supersedes','uq_biological_visit_revisions__supersedes','uq_observation_round_revisions__supersedes']),'revision chains enforce one direct successor with UNIQUE predecessor constraints')
ok(all(x in views_sql for x in ['v_current_session_timing','v_current_fermentation_target','v_current_observation_revision','v_current_process_visit_revision','v_current_biological_visit_revision','NOT EXISTS']),'current runtime state is derived from append-only leaf revisions')
ok('FOR UPDATE' not in flow_text and 'GET_LOCK' not in flow_text and 'RELEASE_LOCK' not in flow_text,'runtime uses no application-directed MariaDB locking')
ok('MAX(visit_no)' not in flow_text and 'visit_seq BIGINT UNSIGNED NOT NULL AUTO_INCREMENT' in runtime_schema,'visit sequencing is database-generated, not read-modify-write MAX()+1')
for table in ['biological_visit_revisions','process_visit_revisions','observation_round_revisions','session_biological_criterion_revisions','session_process_criterion_revisions','session_fermentation_target_revisions','session_fermentation_targets','recommendations']:
    ok(f'UPDATE {table}' not in flow_text,f'append-only runtime never UPDATEs {table}')
ok('UPDATE sessions SET activity_started_at' not in flow_text and 'UPDATE sessions SET is_demo' not in flow_text,'session activity/demo facts are appended or fixed at Start, not rewritten')
ok("method==='hydrometer'?sampleTemp:null" not in start_ctx and "method==='hydrometer'?m.sample_temperature_c:null" not in node_by_id(flow,'p20_measurement_context_result').get('func',''),'measurement temperatures remain complete persisted facts regardless of correction method')
ok('CREATE TABLE IF NOT EXISTS session_lifecycle_events' in runtime_schema and all(x not in runtime_schema.split('CREATE TABLE IF NOT EXISTS sessions (',1)[1].split(') ENGINE=',1)[0] for x in ['status VARCHAR','active_guard','activity_started_at','completed_at','completion_note']),'session lifecycle is append-only and removed from mutable session identity')
ok('CREATE OR REPLACE VIEW v_session_lifecycle' in views_sql and "WHERE lifecycle='active'" in views_sql,'active session is derived from append-only lifecycle events')
ok('uq_recommendation_resolutions__recommendation' in runtime_schema and 'uq_process_criterion_exceptions__supersedes' in runtime_schema,'recommendation resolution and process-exception lineage are constrained in MariaDB')
ok("WHEN EXISTS (" in views_sql and "newer.rule_id=r.rule_id" in views_sql and "THEN 'superseded'" in views_sql,'recommendation supersession is derived from newer append-only guidance')
ok("outcome IN ('executed','dismissed')" in runtime_schema and "outcome IN ('executed','dismissed','superseded')" not in runtime_schema,'recommendation resolution stores only operator outcomes; superseded is derived')
ok("'superseded',NULL,'Ny prosessevaluering'" not in pe and "'superseded',NULL,'Prosessveiledning oppdatert'" not in node_by_id(flow,'p20_process_guidance_result').get('func',''),'new recommendations do not mutate lifecycle through synthetic supersede-resolution writes')
ok('UPDATE sessions ' not in flow_text,'runtime never mutates immutable session identity/lifecycle rows')
ok(not re.search(r"AS _set\s*,\s*\*", flow_text),'all runtime SQL result sets use MariaDB-valid qualified wildcards')
ok(not any(('DELETE FROM '+t) in flow_text for t in ['sessions','session_lifecycle_events','session_timing_revisions','session_fermentation_target_revisions','biological_visit_revisions','process_visit_revisions','observation_round_revisions','biological_evaluations','process_evaluations','recommendations','recommendation_resolutions','process_transitions','biological_transitions']),'runtime does not delete persisted session history')



# p21r4: completed lifecycle + release without deleting session history.
ok('CREATE TABLE IF NOT EXISTS session_release_events' in runtime_schema,'p21 release fact table exists')
ok('CREATE OR REPLACE VIEW v_current_session AS' in views_sql and 'session_release_events' in views_sql,'current operational session excludes released sessions')
ok('CREATE OR REPLACE VIEW v_current_session_summary AS' in views_sql,'p21 current session summary view exists')
ok({'haec_button_end_v1','haec_button_prepare_new_v1','h_end_v1','h_prepare_new_v1','p21_session_end_guard','p21_session_end_context_result','p21_session_end_write_result','p21_session_prepare_guard','p21_session_prepare_context_result','p21_session_prepare_write_result'} <= idset,'p21 session lifecycle HA/Node-RED pipeline exists')
ok(node_by_id(flow,'h_end_v1').get('wires')==[['p21_session_end_guard']] and node_by_id(flow,'h_prepare_new_v1').get('wires')==[['p21_session_prepare_guard']],'Avslutt/Gjør klar have one HA-button ingress each')
end_fn=node_by_id(flow,'p21_session_end_context_result').get('func','')
prepare_fn=node_by_id(flow,'p21_session_prepare_context_result').get('func','')
ok('INSERT INTO session_lifecycle_events' in end_fn and "'completed'" in end_fn and 'INSERT INTO process_visit_revisions' in end_fn and 'INSERT INTO biological_visit_revisions' in end_fn,'Avslutt appends completed lifecycle and closes open B/P visits by revision')
ok('INSERT INTO session_release_events' in prepare_fn and 'verified_export_count' in prepare_fn and 'DELETE FROM sessions' not in prepare_fn,'Gjør klar appends release fact, enforces export gate and preserves session history')
ok('ga_read_start_context' in node_by_id(flow,'p20_start_guard').get('func','') and 'v_start_issues' in views_sql and 'ga_select_start_template_tx' in node_by_id(flow,'p20_template_select').get('func','') and 'NOT EXISTS(SELECT 1 FROM v_current_session)' in (ROOT/'sql/11-runtime-routines.sql').read_text(),'Start/template configuration are blocked by unreleased completed session')
ok('state: completed' in dashboard and 'button.gjaeringsassistent_avslutt_gjaering' in dashboard and 'view: archive-action' in dashboard and 'button.gjaeringsassistent_gjor_klar_ny_gjaering' in card and 'can_prepare_new' in card,'dashboard exposes active End and DB-gated completed Prepare-new surfaces')

# revised19: read-model contract repair + visual flow untangle without topology changes.
sys_query=node_by_id(flow,'p20_systemcheck_query').get('func','')
ok("SELECT 'active_sessions' AS check_id,COUNT(*) AS n FROM v_active_session;" in sys_query and "FROM sessions WHERE status='active'" not in sys_query,'Systemkontroll follows append-only lifecycle view instead of removed sessions.status')
fg_view=re.search(r'CREATE OR REPLACE VIEW v_current_fermentation_target AS([\s\S]*?);',views_sql,re.I)
fg_text=fg_view.group(1) if fg_view else ''
ok(all(x in fg_text for x in ['expected_attenuation_min_percent','expected_attenuation_max_percent','expected_fg_min','expected_fg_max','operation_id','created_at']),'fermentation-target view exposes immutable attenuation-derived target fields consumed by overview')
comment_ids={'p20_comment_session','p20_comment_template','p20_comment_technical','p20_comment_db','p20_comment_measurement','p20_comment_biology','p20_comment_process'}
ok(comment_ids <= idset,'Node-RED flow has visual section headers for the six operator/runtime areas plus shared DB boundary')
tech_sensor_ids=['ha_syscheck_overall_v1','ha_syscheck_db_v1','ha_syscheck_schema_v1','ha_syscheck_ha_v1','ha_syscheck_session_v1','ha_syscheck_last_v1','ha_syscheck_writable_v1','ha_syscheck_frontend_v1','ha_syscheck_nodered_v1','ha_measurement_source_v1','ha_syscheck_runtime_v1','ha_syscheck_config_v1','ha_syscheck_time_v1']
ok(max(node_by_id(flow,i).get('x',0) for i in tech_sensor_ids)<3000,'Systemkontroll HA sensors are untangled into the main readable flow area')
ok(node_by_id(flow,'p20_mysql').get('name')=='MariaDB · felles DB-adapter','shared MariaDB boundary is named without single-writer semantics')


# p21r6: compact Datavindu + simple state-changing command guard.
overview_fn=node_by_id(flow,'p20_overview_result').get('func','')
ok('dataWindowText' not in overview_fn and 'data_window_display' in overview_fn and all(v in views_sql for v in ['v_biological_evaluation_criterion_read_model','v_process_evaluation_criterion_read_model']),'p22r5 Datavindu is produced by MariaDB read-model and only transported by overview')
ok('målt ${c.measured_at}' not in overview_fn and 'window:c.measured_at?' not in overview_fn,'p21r6 Datavindu never substitutes raw criterion timestamp')

ok('evaluation_status' in be and all(x in be for x in ['missing_basis','missing_coverage','stale','invalid_configuration']),'p21r6 B evaluator persists explicit criterion status semantics')
pe=node_by_id(flow,'p20_process_eval_result').get('func','')
ok('evaluation_status' in pe and all(x in pe for x in ['missing_basis','missing_coverage','stale','invalid_configuration']),'p21r6 P evaluator persists explicit criterion status semantics')
ok(all(x in demo_seed for x in ['demo_reference_measurements_5m','demo_reference_data_gaps','measurement_data_gaps']),'p21r6 demo uses normalized real-reference measurements and preserves data gaps')
ok(all(x in card for x in ['criterion-handling-badge','Korrigert','Fravik ·','Tilt SG','ΔSG','Prøve °C','Kjøle-offset']),'p21r6 GUI exposes criterion handling and expanded measurement history')

ok(card.count('Datavindu')>=2 and 'Vindu/trend' not in card,'Biologi and Prosesstrinn label compact evidence column Datavindu')
ok('_commandAcquire(label,guardMs=8000)' in card and "_commandAcquire('lagre_malinger')" in card and "_commandAcquire('process_criterion_exception')" in card,'state-changing custom-card commands use simple 8 s global repeat guard')
ok("_commandAcquire('system_check')" not in card and "_commandAcquire('technical_export')" not in card and "_commandAcquire('template_refresh')" not in card,'read-only/technical actions are excluded from state-changing command guard')
guard_funcs='\n'.join(node_by_id(flow,i).get('func','') for i in ['p20_start_guard','p20_demo_prepare_query','p21_session_end_guard','p21_session_prepare_guard'])
ok('<8000' in guard_funcs and '<1500' not in guard_funcs and 'duplicate-guard 8 s' in guard_funcs,'Start/Demo/Avslutt/Gjør klar use matching 8 s backend repeat guard')

# p21r8: pitch/process timing correction and metadata-seed regression.
timeline_func=node_by_id(flow,'p20_bio_time_correction_query').get('func','')
ok("kind==='pitch'" in timeline_func and 'session_timing_revisions' in timeline_func and "'pitched_at'" in timeline_func,'p21r8 pitch correction appends session_timing_revisions')
ok("kind==='process'" in timeline_func and 'CALL ga_correct_visit_time_tx' in timeline_func and 'v_effective' in routine_sql and 'v_lower' in routine_sql and 'v_upper' in routine_sql,'p21r8 process-start correction appends visit revision with timeline bounds')
ok('correction_kind: pitch' in dashboard and 'correction_kind: process' in dashboard,'p21r8 dashboard exposes pitch and process-start correction cards')
ok('_pitchCorrectionItems' in card and '_processCorrectionItems' in card and "_renderSimpleTimelineCorrection('pitch')" in card and "_renderSimpleTimelineCorrection('process')" in card,'p21r8 custom card supports pitch/process time correction')
metadata_seed=(ROOT/'sql/21-system-metadata-seed.sql').read_text()
ok('system_functions(function_id,name' not in metadata_seed and "('export_completed_session'" in metadata_seed,'p21r8 report metadata seed uses valid system_functions label column')

# p21r8: reference-demo state, day markers, report/history.
demo_seed=node_by_id(flow,'p20_demo_seed_query').get('func','')+'\n'+(ROOT/'sql/11-runtime-routines.sql').read_text().split('CREATE PROCEDURE ga_seed_demo_tx',1)[1]
ok('demo_reference_state_markers' in demo_seed and "state_id='B3'" in demo_seed and "state_id='P2'" in demo_seed and 'demo-b4-' not in demo_seed and 'demo-p3-' not in demo_seed,'p21r8 reference demo remains in B3/P2 and does not hardcode B4/P3')
ok('_overviewDayMarkers' in card and 'm.axis_label' in card and 'v_session_analysis_time_markers' in views_sql,'p21r8 overview charts render day-offset/date markers')
ok(all(x in ids for x in ['p21_session_export_query','p21_session_export_read_result','p21_session_export_verify_query','p21_session_history_query','p21_session_history_result']),'p21r8 completed archive and history pipelines exist')
ok('session_exports' in node_by_id(flow,'p21_session_export_verify_query').get('func','') and 'archive_sha256' in node_by_id(flow,'p21_session_export_verify_query').get('func','') and 'SHA2' not in node_by_id(flow,'p21_session_export_verify_query').get('func',''),'p21r8 completed archive is SHA-256 registered in session_exports')
ok('view: report' in dashboard and 'view: history' in dashboard and 'Aktiv gjæringsrapport' in dashboard and 'Gjæringshistorikk og rapporter' in dashboard,'p21r8 dashboard exposes active report and historical report list')

# p21r10: ordinary Start backfills Home Assistant history and continues 5-minute ingestion.
source_seed=(ROOT/'sql/23-measurement-source-seed.sql').read_text(encoding='utf-8')
runtime_schema=(ROOT/'sql/10-runtime-schema.sql').read_text(encoding='utf-8')
ok(all(x in runtime_schema for x in ['measurement_source_profiles','session_measurement_sources','last_import_cutoff_at','heartbeat_entity_id','rssi_entity_id']),'p21r13 schema persists measurement-source configuration, RSSI and per-session ingestion cursor')
ok(all(x in source_seed for x in ['tilt-pro-blue-ha','bryggeri_tilt_pro_blue_bryggeri_tilt_pro_blue_sg','bryggeri_tilt_pro_blue_bryggeri_tilt_pro_blue_temperatur','bryggeri_tilt_pro_blue_bryggeri_tilt_pro_blue_sist_oppdatert','bryggeri_tilt_pro_blue_bryggeri_tilt_pro_blue_rssi']),'p21r13 DB seed defines configurable SG, temperature, heartbeat and RSSI source entities')
ok(all(x in ids for x in ['p21_live_poll_inject','p21_live_poll_delay','p21_live_ingest_context_query','p21_live_ingest_context_result','p21_live_get_history','p21_live_history_process','p21_live_ingest_write_result']),'p21r13 HA history/live ingestion pipeline exists')
ok(node_by_id(flow,'p21_live_poll_inject').get('repeat','')=='' and node_by_id(flow,'p21_live_poll_inject').get('once') is True and node_by_id(flow,'p21_live_poll_delay').get('timeout')=='300','p21r13 has one startup resume check and active-session-driven five-minute scheduling, not blind polling')
ok(node_by_id(flow,'p21_live_get_history').get('type')=='api-get-history' and node_by_id(flow,'p21_live_get_history').get('server')=='cfg_ha_gjaering_v1','p21r10 ingestion uses existing Home Assistant Get History connection')
live_context=node_by_id(flow,'p21_live_ingest_context_result').get('func','')
live_process=node_by_id(flow,'p21_live_history_process').get('func','')
ok('heartbeat_entity_id' in live_context and 'rssi_entity_id' in live_context and 'last_import_cutoff_at' in live_context and 'flatten:true' in live_context,'p21r13 history request is DB-driven, includes RSSI and resumes from persisted cutoff')
ok('ga_store_ingest_tx' in live_process and all(x in (ROOT/'sql/11-runtime-routines.sql').read_text() for x in ['home_assistant_heartbeat','measurement_data_gaps','measurements_5m','rssi_mean_dbm','pressure_mean_bar']),'p21r13 heartbeat drives gaps while healthy buckets persist SG/temp/RSSI and leave generic pressure nullable')
ok('session_measurement_sources' in start_mutation_sql and '@ga_source_profile' in start_mutation_sql,'p21r10 ordinary Start binds session to DB-configured HA measurement source')
ok('view: startfields' in dashboard and 'section: pitch' in dashboard and 'section: measurement' in dashboard and 'datetime-local' in views_sql,'dashboard presents DB-backed start fields including timestamp and separate demo')
ok('type="datetime-local"' in card and 'start-time-input' in card and "callService('text','set_value'" in card,'p21r10 Start fra reuses datetime-local control and persists through existing pitch-time HA text entity')
ok('name: Start fra (dato/tid)' not in dashboard,'p21r10 removes free-text Start fra entity row from ordinary Start UI')
ok('select.gjaeringsassistent_pitchtid_modus' not in dashboard,'p21r10 hides obsolete pitch-time mode selector from ordinary Start UI')
# p21r13: startup progress, measurement-source diagnostics and metadata-driven system checks.
ok('system_check_definitions' in runtime_schema and 'system_check_expectations' in runtime_schema and 'frontend_publication_runs' in runtime_schema and 'frontend_publication_artifacts' in runtime_schema,'p21r13 persists system-check catalog and frontend publication evidence')
ok('frontend_publishing' in node_by_id(flow,'p20_systemcheck_result').get('func','') and 'generated_files' not in node_by_id(flow,'p20_systemcheck_result').get('func',''),'p21r13 replaces generated_files placeholder with real frontend publication check')
ok('measurement_source' in node_by_id(flow,'p20_systemcheck_result').get('func','') and 'tilt_mqtt' not in node_by_id(flow,'p20_systemcheck_result').get('func',''),'p21r13 removes obsolete tilt_mqtt check id')
ok('view: startaction' in dashboard and 'sensor.gjaeringsassistent_startstatus' in dashboard and '_renderStartAction' in card,'p21r13 Gjæring start surface shows import progress around Start')
ok('12*3600000' in live_context and 'progress_percent' in live_context and 'target_import_end' in live_context,'p21r13 initial history import is chunked with time-based progress')
ok('Målekilde / Tilt' in card and 'heartbeat_entity_id' in card and 'rssi_entity_id' in card and 'latest_bucket_display' in card and 'latest_sg_display' in card and 'gap_status_display' in card,'p22r5 Teknisk renders only DB read-model measurement-source display fields')
tech_export_func=node_by_id(flow,'p20_technical_export_result').get('func','')
ok('measurement_source:{status:measurementStatus,profile,binding,latest_measurement_5m:latest5m' in tech_export_func and 'home_assistant:{sg:' not in tech_export_func and 'frontend_publication' in tech_export_func and 'importMode' not in tech_export_func and 'v_measurement_source_status' in node_by_id(flow,'p20_technical_export_query').get('func','') and "'export_meta' AS _set" in node_by_id(flow,'p20_technical_export_query').get('func',''),'p22r5 technical export uses DB-owned measurement-source status and DB release clock without local import-mode derivation')
syscheck_func=node_by_id(flow,'p20_systemcheck_result').get('func','')
ok("r._set==='measurement_status'" in syscheck_func and "measurementCheck.summary" in syscheck_func and 'sourceConfigured' not in syscheck_func,'p22r5 measurement-source Systemkontroll consumes the same MariaDB read-model as Technical without external Tilt fallback')

# p21r13 rule-architecture reconstruction: registry capability -> template-owned rule -> frozen session rule.
ok(all(x in default_schema for x in ['template_metric_runtime_rules','template_metric_runtime_inputs','template_metric_runtime_parameter_values','calculation_model_inputs','calculation_model_parameters']),'p21r13 template schema owns concrete metric calculation model, inputs and typed parameters')
ok(all(x in start_mutation_sql for x in ['FROM template_metric_runtime_rules WHERE version_id=@ga_template_version','FROM template_metric_runtime_inputs WHERE version_id=@ga_template_version','FROM template_metric_runtime_parameter_values WHERE version_id=@ga_template_version']) and 'FROM metric_runtime_rules WHERE' not in start_mutation_sql,'p21r13 Start freezes concrete template metric rules without registry fallback')
ok('minimum_met_duration_minutes' not in default_schema+default_seed+func+(ROOT/'docs/10-REGEL-OG-EVALUERINGSMODELL.md').read_text(encoding='utf-8'),'p21r13 does not invent a hidden minimum-duration rule from legacy freshness')
ok(all(re.search(rf"'{pid}','{pid.lower()}-biological-phase','threshold',[^\n]*NULL,'2026",default_seed) for pid in ['P3','P4','P5','P6','P7','P8']),'W-34/70 biological-phase process gates have no maximum-age freshness constraint')
ok("'template_biological_correctable_parameters'" not in '', 'placeholder') if False else None
bio_correctable='\n'.join(line for line in default_seed.splitlines() if 'template_biological_correctable_parameters' in line)
ok("'maximum_age_minutes'" not in bio_correctable,'biological criterion correction policy contains no ghost maximum-age parameter')
be_func=node_by_id(flow,'p20_bio_eval_result').get('func','')
pe_func=node_by_id(flow,'p20_process_eval_result').get('func','')
ok('state.current_phase_order+1' in be_func and 'transitionEvents.push' in be_func and 'phases.find(p=>Number(p.phase_order)===state.current_phase_order+1)' in be_func,'biological replay evaluates only the next sequential B phase')
ok('measurement_data_gaps' in node_by_id(flow,'p20_bio_eval_query').get('func','') and 'contiguousWindowStart' in be_func and 'Datagap brøt stabilitetsvinduet' in be_func,'biological stability windows reset across persisted measurement gaps')
ok('measurement_data_gaps' in node_by_id(flow,'p20_process_eval_query').get('func','') and 'contiguousWindowStart' in pe_func and 'Datagap brøt stabilitetsvinduet' in pe_func,'process stability windows reset across persisted measurement gaps')
ok('første kriteriebekreftede biologiske aktivitet' in be_func and 'første vedvarende biologiske aktivitet' not in be_func,'activity timing reason does not claim an undeclared persistence duration')
ok(not re.search(r"(?:metricId|metric_id)\s*={2,3}\s*['\"](?:relative_sg_drop_points|fg_progress_min_percent|sg_rate_points_per_day|biological_phase_order)",be_func),'B evaluator has no metric-ID-specific domain rule branches')
incoming_source={n.get('id') for n in flow for group in (n.get('wires',[]) or []) if 'ha_measurement_source_v1' in group}
ok(incoming_source=={'p21_ha_bootstrap_dispatch','p21_measurement_source_read_result'},'measurement-source HA projection has only bootstrap plus the dedicated MariaDB read-model producer')
ok('active-process-summary' in card and 'process-readiness' in card and card.index('active-process-summary')<card.index('process-readiness'),'Process view places active process summary above next-process readiness')
req_common=(ROOT/'docs/01-KRAV-FELLES.md').read_text(encoding='utf-8')
req_motor=(ROOT/'docs/02-KRAV-MOTOR-OG-INTEGRASJON.md').read_text(encoding='utf-8')
ok(all(x in req_common for x in ['REQ-COM-065','REQ-COM-067','REQ-COM-070']) and all(x in req_motor for x in ['REQ-MOTOR-021','REQ-MOTOR-022']),'normative requirements document DB-owned rules, freshness semantics, validation and sequential backfill')

# p22r3: Start observability and complete sequential historical process replay.
start_guard_node=node_by_id(flow,'p20_start_guard')
start_guard_func=start_guard_node.get('func','')
ok(start_guard_node.get('wires')==[['p20_mysql'],['p24_start_status_query'],['p20_technical_event_writer']] and 'START_REQUESTED' in start_guard_func and 'ga_operation_id' in start_guard_func,'Start ingress is audited before DB validation and refreshes the DB start projection')
technical_catch=node_by_id(flow,'p20_technical_catch')
ok(technical_catch.get('scope') is None and technical_catch.get('uncaught') is True,'p22r7 central Technical catch is tab-wide uncaught safety net, not a manually maintained node list')
db_error=node_by_id(flow,'p20_db_error')
ok(len(db_error.get('wires',[]))>=3 and db_error.get('wires',[[],[],[]])[2]==['p24_start_status_query'] and "['start_context','start_write']" in db_error.get('func',''),'Start MariaDB errors reach Technical and trigger DB status reconstruction')
proc_query=node_by_id(flow,'p20_process_eval_query').get('func','')
proc_eval=node_by_id(flow,'p20_process_eval_result').get('func','')
bio_write=node_by_id(flow,'p20_bio_eval_write_result').get('func','')
ok("'bio_history' AS _set" in proc_query and 'ga_process_eval_reason' in bio_write,'p22r3 process evaluator receives biological timeline and historical-import reason')
ok('historicalMode' in proc_eval and 'while(safety++<steps.length)' in proc_eval and "'backfill'" in proc_eval and 'historical_backfill' in proc_eval,'p22r3 historical replay advances sequentially through all eligible P steps')
ok('biologyStateAt' in proc_eval and 'observations.filter(o=>o.at<=evalAt)' in proc_eval,'p22r3 historical P evaluation uses only biological/observation facts available at each evaluation time')
live_ingest_result=node_by_id(flow,'p21_live_ingest_write_result').get('func','')
ok("g.initial_import?'ha_history_backfill':'live_ingest'" in live_ingest_result,'p22r3 HA ingest explicitly separates historical catch-up from ordinary live evaluation')
ok("['ha_history_backfill','start','start_continue','catchup']" in proc_eval and "'live_ingest'" not in re.search(r"const historicalMode=([^;]+);",proc_eval).group(1),'p22r3 sequential P backfill cannot run during ordinary live five-minute ingest')


# p23r2-revised4 regressions.
restore_inject=node_by_id(flow,'p20_restore_inject')
ok(str(restore_inject.get('repeat',''))=='', 'startup restore has no periodic editable-field refresh')
ok('p20_restore_retry_delay' in idset, 'startup restore retries MariaDB readiness through transient delay')
ok('number.gjaeringsassistent_pitchtemperatur_c' not in (ROOT/'dashboard'/'gjaeringsassistent-dashboard.yaml').read_text(encoding='utf-8'), 'pitch temperature removed as separate Start input')
start_node=node_by_id(flow,'p20_start_context_result')
ok("corrected,volume,pitchMode,manualTemp" in start_node.get('func',''), 'Start derives pitch-temperature snapshot from manual temperature')

ok(all(x not in json.dumps(flow,ensure_ascii=False) for x in ['metric-fg-progress-v1','metric-absolute-value-v1','metric-rate-to-peak-ratio-v1','metric-rate-to-peak-ratio-v2']),'obsolete FG-progress/absolute-rate/rate-to-peak calculation models are removed from executable flow')

# revised3 target-runtime regressions.
installer=(ROOT/'installer/install.sh').read_text(encoding='utf-8')
ok('sql/90-schema-verification.sql' not in installer and 'verify MariaDB schema' not in installer,'installer does not run detailed schema regression as an installation-critical gate')
ok(all('sql/11-runtime-routines.sql' in json.loads((ROOT/'installer/migrations.json').read_text())[key] for key in ['fresh_files','upgrade_files']),'installer installs transactional runtime routines through declared plans')
registry=(ROOT/'sql/02-runtime-registry-seed.sql').read_text(encoding='utf-8')
ok('expected-attenuation-midpoint-v1' in registry and 'expected-fg-midpoint-v1' not in registry,'finished-ABV calculation model registry matches attenuation-based runtime')
ok("LEFT JOIN v_current_fermentation_target ft" in views_sql and 'expected_attenuation_display' in views_sql,'current-session read-model exposes attenuation and derived-FG display values')

# p23r2-revised5: Systemkontroll configuration distinguishes active and mandatory HA entities.
flow_text=(ROOT/'nodered/flows.template.json').read_text(encoding='utf-8')
metadata_seed=(ROOT/'sql/21-system-metadata-seed.sql').read_text(encoding='utf-8')
ok("registry.length===expected.length" not in flow_text,
   'Systemkontroll does not equate active HA registry count with mandatory HA entity count')
ok(all(x in flow_text for x in ["ha_registry_active_count","ha_registry_required_count","published_templates_min"]),
   'Systemkontroll configuration uses MariaDB expectations for HA registry and published-template counts')
ok(all(x in metadata_seed for x in ["'ha_registry_active_count',NULL,75","'ha_registry_required_count',NULL,74","'published_templates_min',NULL,1"]),
   'MariaDB Systemkontroll metadata declares 75 active and 74 mandatory HA entities plus one published template minimum')


# p23r2-revised6: all database-owned user-facing report timestamps are rendered in Europe/Oslo.
report_sql = views_sql[views_sql.index("CREATE OR REPLACE VIEW v_active_session_report_summary"):views_sql.index('-- START FIELD READ MODEL')]
ok("DATE_FORMAT(CONVERT_TZ(s.pitched_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS pitched_display" in report_sql,
   'active-session Pitch display converts stored UTC to Europe/Oslo')
raw_report_date_formats=[line for line in report_sql.splitlines()
                         if 'DATE_FORMAT(' in line
                         and any(x in line for x in ['pitched_at','started_at','ended_at','recorded_at','created_at','transitioned_at','completed_at','happened_at','bucket_at','evaluated_at','noted_at','gap_started_at','gap_ended_at'])
                         and 'CONVERT_TZ' not in line]
ok(not raw_report_date_formats,
   'active-session report/display timestamps do not format stored UTC directly')


# p23r2-revised7: p22 correction UX, DB-owned dynamic axes, visible min/max envelopes,
# complete report graphs, manual biological correction and MariaDB measurement export.
runtime_schema=(ROOT/'sql/10-runtime-schema.sql').read_text(encoding='utf-8')
template_seed=(ROOT/'sql/03-w3470-template-seed.sql').read_text(encoding='utf-8')
routines=(ROOT/'sql/11-runtime-routines.sql').read_text(encoding='utf-8')
card=(ROOT/'dashboard/gjaeringsassistent-card.js').read_text(encoding='utf-8')
dashboard=(ROOT/'dashboard/gjaeringsassistent-dashboard.yaml').read_text(encoding='utf-8')

ok(all(x in runtime_schema for x in ['temperature_min_c','temperature_max_c','pressure_min_bar','pressure_max_bar','rssi_min_dbm','rssi_max_dbm']),
   '5-minute runtime schema persists min/max envelopes for temperature, pressure and RSSI')
demo_ref_match=re.search(r'CREATE TABLE IF NOT EXISTS demo_reference_measurements_5m\s*\((.*?)\n\) ENGINE=InnoDB',runtime_schema,re.S)
ok(bool(demo_ref_match),'demo reference 5-minute table is present in runtime schema')
if demo_ref_match:
    demo_ref_def=demo_ref_match.group(1)
    demo_declared=set(re.findall(r'^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s+(?:VARCHAR|INTEGER|DECIMAL|DATETIME|TEXT)\b',demo_ref_def,re.M))
    demo_range_refs=set(re.findall(r'\b(?:temperature|pressure|rssi)_(?:min|mean|max)_(?:c|bar|dbm)\b',demo_ref_def))
    ok(demo_range_refs <= demo_declared,
       'demo reference CHECK expressions do not reference undeclared measurement-range columns')
ok(all(x in runtime_schema for x in ['range_min_value','range_max_value']),
   'analysis runtime values persist explicit min/max range values')
ok(all(x in views_sql for x in ['v_session_overview_graph_axes','v_active_overview_graph_axes','v_session_analysis_graph_axes','v_active_analysis_graph_axes','v_session_analysis_requirements']),
   'MariaDB exposes generic and active dynamic graph-axis/read-range models')
ok("tick_step*0.30" in view_def if False else 'tick_step*0.30' in views_sql,
   'dynamic graph axes use only a small tick-relative drawing margin')
ok("JOIN process_visits pv ON pv.session_id=t.session_id AND pv.process_id=t.process_id" in views_sql,
   'overview axes include process targets only for visited/current process steps, not distant future targets')
overview_extent=views_sql[views_sql.index('CREATE OR REPLACE VIEW v_session_overview_graph_extents'):views_sql.index('CREATE OR REPLACE VIEW v_session_overview_graph_axes')]
ok("'pressure',CAST(m.pressure_min_bar AS DECIMAL(24,9)),0" in overview_extent and "'pressure',CAST(m.pressure_max_bar AS DECIMAL(24,9)),0" in overview_extent,
   'pressure overview axis is not artificially forced to zero when zero is outside displayed data')
ok("'attenuation',1," in template_seed and "NULL,NULL,NULL,0,'relative_day_date'" in template_seed and
   "'sg-rate',2," in template_seed and "'sg-stability',3," in template_seed,
   'analysis graph metadata uses DB-computed axes and does not force attenuation to zero')

generic_renderer=(ROOT/'tools/graph_renderer.js').read_text()
ok('_overviewChart(' not in card and 'overviewChart=' not in (ROOT/'tools/report_renderer.js').read_text(),
   'legacy graph-specific drawing implementations are absent')
ok('show_in_overview' in card and '_analysisChart(g,compact)' in card,
   'overview graph membership comes from DB metadata and uses the same renderer')
ok(all(x in generic_renderer for x in ['range_min_value','range_max_value','referenceBands','date_font_size','canvas_width']),
   'one renderer consumes DB axes, measured envelopes, reference bands and typography')
an_start=card.index('_analysisChart('); an_end=card.index('_renderAnalysis()',an_start)
an_func=card[an_start:an_end]+(ROOT/'tools/graph_renderer.js').read_text()
ok(all(x in an_func for x in ['range_min_value','range_max_value','y_axis_min','y_axis_max','axisTicks']),
   'analysis graphs render min/max envelopes on DB-owned dynamic Y axes')

active_report_query=node_by_id(flow,'p22_active_report_query').get('func','')+'\n'+(ROOT/'tools/report_reads.sql').read_text()
active_report_result=node_by_id(flow,'p22_active_report_result').get('func','')
completed_report_query=node_by_id(flow,'p21_session_export_query').get('func','')+'\n'+(ROOT/'tools/report_reads.sql').read_text()
completed_report_result=node_by_id(flow,'p21_session_export_read_result').get('func','')
ok(all(x in active_report_query for x in ['v_graph_definitions','v_graph_series','v_graph_axis_ticks','v_session_analysis_requirements']),
   'active report reads the same MariaDB graph axes, analysis series and requirements as dashboard')
ok(all(x in active_report_result for x in ['range_min_value','range_max_value','analysis-band','analysisHtml']),
   'active report renders all analysis graphs with min/max envelopes')
ok(all(x in completed_report_query for x in ['v_graph_definitions','v_graph_series','v_session_analysis_requirements','v_graph_axis_ticks']),
   'completed report reads generic session graph axes, analysis series and requirements')
ok(all(x in completed_report_result for x in ['range_min_value','range_max_value','analysis-band','analysisHtml']),
   'completed report renders all analysis graphs with min/max envelopes')

ok('CREATE PROCEDURE ga_correct_biological_phase_tx' not in routines and not any(n.get('id','').startswith('p23_bio_phase_correction') for n in flow),'direct biological phase setter is absent')
bio_q=node_by_id(flow,'p24_bio_exception_context').get('func','')
ok('confirmed!==true' in bio_q and "note:String(req.note||'').trim()" in bio_q,'biological criterion exception requires confirmation and accepts optional note')
ok('Notat (valgfritt)' in card and 'Obligatorisk begrunnelse' not in card and 'Obligatorisk begrunnelse' not in dashboard,
   'correction/deviation UI uses optional notes and no mandatory-justification label')

measurement_q=node_by_id(flow,'p23_measurement_export_query').get('func','')
measurement_r=node_by_id(flow,'p23_measurement_export_result').get('func','')
ok('Eksporter måledata' in card and 'gjaeringsassistent_measurement_export' in card,
   'Technical surface exposes a separate MariaDB measurement-export action')
ok(all(x in measurement_q for x in ['FROM v_session_measurement_series','FROM v_measurement_data_gaps','v_current_session_summary','temperature_min_c','pressure_min_bar','rssi_min_dbm']),
   'measurement export reads session metadata, 5-minute ranges and gaps directly from MariaDB')
ok(all(x in measurement_r for x in ['row_type','sg_min','sg_median','sg_max','temperature_min_c','temperature_max_c','pressure_min_bar','pressure_max_bar','rssi_min_dbm','rssi_max_dbm']),
   'measurement export CSV contains complete observed range columns')

for label in passed: print('PASS',label)
for label in errors: print('FAIL',label)
if js_fail:
    for item in js_fail: print('JS',item[0],item[1])
if errors or js_fail: raise SystemExit(1)
print(f'RESULT: PASS ({len(passed)} static checks)')
