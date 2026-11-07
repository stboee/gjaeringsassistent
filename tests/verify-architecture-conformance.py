#!/usr/bin/env python3
from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[1]
views_sql=(ROOT/'sql/20-views.sql').read_text(encoding='utf-8')
flow=json.loads((ROOT/'nodered/flows.template.json').read_text(encoding='utf-8'))
by={n.get('id'):n for n in flow}
errors=[];passed=[]
def ok(c,l): (passed if c else errors).append(l)
def fn(i): return str(by[i].get('func',''))
def method(src,name,next_name=None):
    start=src.find(f'  {name}(')
    if start<0:return ''
    if next_name:
        end=src.find(f'\n  {next_name}(',start+1)
        return src[start:end if end>=0 else None]
    return src[start:]

allfunc='\n'.join(str(n.get('func','')) for n in flow if n.get('type')=='function')
# MariaDB-only persistence invariant.
ok('flow.set(' not in allfunc and 'global.set(' not in allfunc and 'context.set(' not in allfunc,'no flow/global/context domain writes')
users=[n.get('id') for n in flow if n.get('type')=='function' and 'global.get(' in str(n.get('func',''))]
allowed={'p24r16_ha_publication_retry_result','p20_systemcheck_result','p20_test_tech_state','p20_technical_export_result','p21_ha_registry_result'}
ok(set(users)<=allowed,f'global.get confined to technical/integration allowlist: {users}')

# Evaluators use persisted DB horizon and no wall-clock fallback.
for i in ['p20_bio_eval_result','p20_process_eval_result']:
    s=fn(i)
    ok('evaluationHorizon' in s and 'last_import_cutoff_at' in s and 'database_now' in s,f'{i} has explicit DB-backed evaluation horizon')
    ok('p22r5-declarative-engine' in s,f'{i} identifies p22r5 declarative engine')
    ok('Date.now()' not in s,f'{i} has no Node.js wall-clock fallback')
ps=fn('p20_process_eval_result')
ok("Number(x.enabled)!==0&&Number(x.process_order)>state.process_order" in ps,'historical P replay only traverses enabled session steps')

# Measurement-source state has exactly one domain producer: MariaDB view -> transport -> HA.
q=fn('p21_measurement_source_read_query'); ms=fn('p21_measurement_source_read_result')
ok('v_measurement_source_ha_projection' in q,'measurement-source HA projection reads finished MariaDB read-model')
ok("source=rows.find(x=>x&&x._set==='measurement_status')" in ms and 'new Date' not in ms and 'Math.' not in ms,'measurement-source result only normalizes mysql result shape and transports DB fields')
ok('latest_sg_display' not in ms and 'poll_interval_display' not in ms,'measurement-source display content is not constructed in Node-RED')
ctx=fn('p21_live_ingest_context_result')
ok('database_now' in ctx and 'poll_interval_seconds' in ctx and 'gap_threshold_seconds' in ctx,'ingest context uses DB time/configuration')
ok('||300' not in ctx and "||'home_assistant'" not in ctx and 'Date.now()' not in ctx,'ingest context has no guessed source/timing defaults')
wr=fn('p21_live_ingest_write_result')
ok('ga_measurement_source_refresh' in wr and 'new Date().toISOString' not in wr,'ingest write only triggers DB read-model refresh')
sc=by['p24_ha_technical_result']
ok(len(sc.get('wires',[]))>8 and sc['wires'][8]==['p21_measurement_source_read_query'],'Systemkontroll refreshes the same DB measurement-source read-model')
ok('v_measurement_source_status' in fn('p20_systemcheck_query'),'Systemkontroll reads the same measurement-source DB view')

# Registered metrics are computed by the engine/DB once, never recomputed by overview/frontend.
ok('CALL ga_read_overview' in fn('p20_overview_query'),'overview routes to DB compiled reader')
ovq=(ROOT/'tools/overview_reads.sql').read_text(); ovr=fn('p20_overview_result')
ok('v_current_metric_value' in ovq,'overview reads persisted current metric values')
ok('apparent_attenuation_percent' in ovq and 'sg_rate_points_per_day' in ovq,'overview requests authoritative attenuation and SG-rate metrics')
for forbidden in ['(s0.og-', '/(s0.og-', 'expected_fg_min)*100', 'expected_fg_min) * 100']:
    ok(forbidden not in ovr,f'overview has no local FG formula: {forbidden}')
ok('attenuationMetric?.actual_display' in ovr and 'sgRateMetric?.actual_display' in ovr,'overview transports DB metric display values')

# Criterion evidence/window/status/actual/requirement are database-owned display fields.
views=(ROOT/'sql/20-views.sql').read_text(encoding='utf-8')
for v in ['v_biological_evaluation_criterion_read_model','v_process_evaluation_criterion_read_model','v_current_metric_value','v_measurement_source_status','v_active_session_report_summary']:
    ok(f'CREATE OR REPLACE VIEW {v}' in views,f'{v} exists as MariaDB read-model')
ok(all(x in views for x in ['data_window_display','actual_display','requirement_display','status_display']),'criterion read-model owns finished display fields')
ok('c.data_window_display' in ovr and 'c.actual_display' in ovr and 'c.requirement_display' in ovr,'overview transports criterion display fields from DB')
ok('dataWindowText' not in ovr and 'requirementText' not in ovr,'overview has no criterion display fallback builders')

# Transition evidence is authoritative.
for v in ['v_biological_transition_evidence','v_current_biological_candidate_evaluation','v_process_transition_evidence','v_current_process_candidate_evaluation']:
    ok(v in ovq,f'overview reads {v}')
ok('transition_evidence' in ovr and 'evidence_kind' in ovr,'overview exposes transition evidence/current evaluation separately')

# Active report is DB snapshot based; it does not change lifecycle.
ok('CALL ga_read_report' in fn('p22_active_report_query'),'active report routes to the same DB reader')
arq=(ROOT/'tools/report_reads.sql').read_text()+'\n'+fn('p22_active_report_query'); arb=fn('p22_active_report_result'); arr=fn('p22_active_report_register_query')
ok('v_session_report_summary' in arq and 'UTC_TIMESTAMP(3)' in arq,'active report reads DB-owned snapshot/display time')
ok(all(x not in arb for x in ['fg_progress_min_percent','sg_rate_points_per_day','current_to_peak_rate_ratio','(session.og-','expected_fg_min)*100','expected_fg_max)*100']),'active report HTML builder does not calculate registered/domain metrics')
ok(all(v in arq for v in ['v_session_report_session','v_session_report_process','v_session_report_observations','v_session_report_gaps','v_session_report_criterion_corrections','v_session_report_process_exceptions','v_session_report_timeline','v_session_report_actions']),'active report text/domain content is selected from MariaDB report read-models')
ok('const val=' not in arb and "Number(x.historical_replay_auto_transition_allowed)" not in arb and "Number(x.accepted)" not in arb,'active report renderer contains no domain fallback or status mapping')
ok('CASE ' not in arq.upper(),'active report query reads DB report views without Node-RED-owned domain CASE mappings')
ok(all(v in views for v in ['historical_replay_policy_display','accepted_display','duration_display','parameters_display','exception_type_display']),'MariaDB report read-models own report status/display mappings')
# ASCII identifiers are converted explicitly at the MariaDB presentation boundary before
# concatenation with utf8mb4 operator text. This guards the p22r5 collation regression.
for expr,label in [
    ('CONVERT(x.candidate_process_id USING utf8mb4)', 'current process candidate ID'),
    ('CONVERT(e.candidate_process_id USING utf8mb4)', 'report next-process ID'),
    ('CONVERT(s.current_biological_phase_id USING utf8mb4)', 'report biological phase ID'),
    ('CONVERT(s.current_process_id USING utf8mb4)', 'report process ID'),
    ('CONVERT(p.parameter_id USING utf8mb4)', 'report parameter ID'),
    ('CONVERT(t.to_process_id USING utf8mb4)', 'report transition target ID'),
    ('CONVERT(b.phase_id USING utf8mb4)', 'report timeline biological ID'),
    ('CONVERT(v.process_id USING utf8mb4)', 'report timeline process ID'),
]:
    ok(expr in views,f'{label} is explicitly converted to utf8mb4 in DB display views')
verification=(ROOT/'sql/90-schema-verification.sql').read_text(encoding='utf-8')
for smoke in ['current_process_candidate_display_queryable','active_report_summary_display_queryable','active_report_session_display_queryable','active_report_corrections_display_queryable','active_report_transitions_display_queryable','active_report_timeline_display_queryable']:
    ok(smoke in verification,f'release schema verification executes {smoke} read-model smoke')
register_routine=(ROOT/'sql/11-runtime-routines.sql').read_text().split('CREATE PROCEDURE ga_register_active_report_tx',1)[1].split('END//',1)[0]
ok('CALL ga_register_active_report_tx' in arr and "'active_report'" in register_routine and 'session_exports' in register_routine and 'session_lifecycle_events' not in register_routine,'active report registers export metadata atomically without lifecycle mutation')

# Runtime frontend views touched by p22r5 only display prepared metric/report/measurement-source fields.
card=(ROOT/'dashboard/gjaeringsassistent-card.js').read_text(encoding='utf-8')
report=method(card,'_renderReport','_renderHistory')
system=method(card,'_renderSystem','_render')
ok('report_summary' in report and all(x not in report for x in ['Math.','Number(','.toFixed(','_time(']),'active report card only renders DB report_summary fields')
ok(all(x in system for x in ['latest_sg_display','import_cutoff_display','last_success_display','gap_status_display']),'Technical/Tilt renders DB supplied display fields')
ok(all(x not in system for x in ['toFixed(', 'Math.round(', '_ageSeconds(']),'Technical/Tilt does not recalculate measurement-source domain values')
systemcheck=fn('p20_systemcheck_write_result')
ok('v_ha_technical_payloads' in systemcheck and all(x in views_sql for x in ['measurement_age_state','latest_measurement_state','data_quality_display']),'Systemkontroll publishes DB-prepared measurement display states')
ok(all(x not in systemcheck for x in ["??'unknown'",'??"unknown"','age===null?0','age == null ? 0']),'Systemkontroll has no measurement-state fallback values')
# Regression gate for the specific duplicate FG bug.
ok('(OG -' not in card and 'expected_fg_min)*100' not in card and 'fg_progress_percent=' not in card,'frontend contains no FG-progress calculation')


# p22r5 historical process replay policy is normalized template/session data.
schema=(ROOT/'sql/00-template-schema.sql').read_text(encoding='utf-8')+'\n'+(ROOT/'sql/10-runtime-schema.sql').read_text(encoding='utf-8')
seed=(ROOT/'sql/03-w3470-template-seed.sql').read_text(encoding='utf-8')
start_sql=(ROOT/'sql/start-session.sql').read_text(encoding='utf-8')
start_routine=(ROOT/'sql/11-runtime-routines.sql').read_text(encoding='utf-8')
start_bundle=start_sql+'\n'+start_routine
ok('historical_replay_auto_transition_allowed' in schema and 'historical_replay_auto_transition_allowed' in start_bundle,'historical replay auto-transition policy is normalized and frozen to session')
ok(bool(re.search(r"'P1',1,1,1,",seed)) and bool(re.search(r"'P2',2,1,1,",seed)),'W-34/70 permits historical automatic establishment of P1/P2')
ok(all(bool(re.search(rf"'P{i}',{i},[01],0,",seed)) for i in range(3,16)),'W-34/70 P3-P15 require manual transition during replay')
ok('historical_replay_auto_transition_allowed' in ps and "!==1" in ps,'process evaluator enforces frozen replay policy generically')
ok("candidate.process_id==='P3'" not in ps and "candidate.process_order>2" not in ps,'process evaluator has no W-34/70/P3 hardcoded replay cutoff')

# p22r5 backfill is sequential through B then P before next chunk.
bw=fn('p20_bio_eval_write_result'); pw=fn('p20_process_eval_write_result')
ok('ga_ingest_continue' in wr and 'retry' in wr and 'return [' in wr,'ingest acknowledgement carries persisted continuation token')
ok('ga_ingest_continue' in bw,'biology acknowledgement propagates historical continuation to process evaluator')
ok('msg.ga_ingest_continue||null' in pw and by['p20_process_eval_write_result'].get('wires',[[],[],[]])[2]==['p21_live_ingest_context_query'],'next history chunk starts only after process evaluation acknowledgement')
# Output 3 of ingest may remain physically wired for legacy topology but must not return retry directly.
ok(',analysis,null,refresh,startStatus,scheduled,syscheck]' in wr,'ingest write routes through generic analysis and does not directly start next history chunk')

# IDs are DB-owned and collision resistant; Node-RED does not use wall clock/random suffixes.
for i in ['p20_bio_eval_query','p20_process_eval_query','p20_process_guidance_query']:
    ok('UUID()' in fn(i) or (i=='p20_process_guidance_query' and 'v_process_recommendation_presentation' in fn(i) and 'UUID()' in views_sql.split('CREATE OR REPLACE VIEW v_process_recommendation_presentation AS',1)[1].split(';',1)[0]),f'{i} obtains operation identity from MariaDB UUID')
for i in ['p20_bio_eval_result','p20_process_eval_result','p20_process_guidance_result']:
    ok('Date.now()' not in fn(i) and 'Math.random' not in fn(i),f'{i} does not invent evaluation/recommendation identity locally')

# Gap state has one authority: measurement_data_gaps.
runtime_schema=(ROOT/'sql/10-runtime-schema.sql').read_text(encoding='utf-8')
sm_match=re.search(r'CREATE TABLE IF NOT EXISTS\s+session_measurement_sources\s*\((.*?)\n\)\s*ENGINE',runtime_schema,re.S|re.I)
ok(bool(sm_match) and 'open_gap_id' not in sm_match.group(1) and 'open_gap_started_at' not in sm_match.group(1),'session_measurement_sources does not cache open gap state')
msv=re.search(r'CREATE OR REPLACE VIEW v_measurement_source_status AS(.*?);',views,re.S).group(1)
ok('measurement_data_gaps' in msv and 'sm.open_gap' not in msv,'measurement-source status derives gap state only from measurement_data_gaps')
ok('CREATE OR REPLACE VIEW v_measurement_source_ha_projection' in views,'finished HA measurement-source projection exists in MariaDB')

# Active report DB acknowledgement must tolerate mysql multi-result shapes.
arrres=fn('p22_active_report_register_result')
ok('walk' in arrres and "_set==='active_report'" in arrres,'active report confirmation recursively locates DB acknowledgement in mysql multi-results')

# Dashboard placement/layout: report at top and process transition controls before candidate table.
yaml=(ROOT/'dashboard/gjaeringsassistent-dashboard.yaml').read_text(encoding='utf-8')
btn=yaml.find('entity: button.gjaeringsassistent_generer_aktiv_rapport'); ok(btn>=0 and 'columns: 6' in yaml[max(0,btn-300):btn+100],'active report action uses half-column grid width')
process=method(card,'_renderProcess','_renderMeasurements')
ok(process.find('Overgang')>=0 and process.find('Vurdering av neste prosesstrinn')>=0 and process.find('Overgang')<process.find('Vurdering av neste prosesstrinn'),'process transition controls are immediately upstream of candidate criteria assessment')



# p23r2: source freshness is one evaluation-readiness gate, not duplicated phase/process criteria.
for eid in ['p20_bio_eval_query','p20_process_eval_query']:
    ok('fresh_age_minutes' in fn(eid) and 'measurement_source_profiles' in fn(eid),f'{eid} reads DB-owned measurement freshness for evaluation readiness')
for eid in ['p20_bio_eval_result','p20_process_eval_result']:
    ok('liveEvaluationReady' in fn(eid) and 'liveMeasurementAgeMinutes' in fn(eid),f'{eid} blocks live decisions when source data are stale without adding freshness criteria')

# p22r7: measurement validation and analysis presentation are metadata/session driven.
validation_seed=(ROOT/'sql/23-measurement-source-seed.sql').read_text(encoding='utf-8')
registry_seed=(ROOT/'sql/01-template-registry-seed.sql').read_text(encoding='utf-8')
analysis_fn=fn('p22_analysis_result'); ingest_fn=fn('p21_live_history_process')
analysis_card=method(card,'_analysisChart','_renderAnalysis')
for table in ['measurement_validation_models','measurement_validation_model_parameters','template_analysis_graphs','template_analysis_graph_series','measurement_source_validation_rules','measurement_source_validation_rule_parameter_values','session_measurement_validation_rules','session_measurement_validation_rule_parameter_values','measurement_ingest_quality_events','session_analysis_graphs','session_analysis_graph_series','analysis_series_values','analysis_validation_events']:
    ok(table in schema,f'p22r7 normalized schema contains {table}')
ok(all(x in start_bundle for x in ['session_analysis_graphs','session_analysis_graph_series','session_measurement_validation_rules','session_measurement_validation_rule_parameter_values']),'Start freezes graph and measurement-validation metadata into the session')
ok(all(x in validation_seed for x in ['hard_range_v1','robust_mad_v1','max_jump_v1','minimum_acceptance_v1']),'Tilt source validation is declared through generic DB models')
ok(all(x in ingest_fn for x in ['hard_range_v1','robust_mad_v1','max_jump_v1','minimum_acceptance_v1','ga_store_ingest_tx']),'ingest executes generic DB-selected validation models and persists quality facts')
ok('accepted=[];agg=null' in ingest_fn and 'Math.min(max' not in ingest_fn and 'Math.max(min' not in ingest_fn,'invalid measurement values are rejected rather than clamped into invented values')
ok('previousAt,currentAt' in ingest_fn and 'currentAt-prevMs' in ingest_fn,'max-jump validation is applied only across contiguous measurement intervals')
ok(all(x in analysis_fn for x in ['minimum_samples','minimum_coverage_fraction','warmup_minutes','valid_minimum_value','valid_maximum_value','analysis_validation_events']),'analysis series enforce generic warm-up, coverage and output validation metadata')
ok('INSERT IGNORE INTO analysis_series_values' in analysis_fn and 'UPDATE analysis_series_values' not in analysis_fn and 'DELETE FROM analysis_series_values' not in analysis_fn,'analysis history is append-only from the engine')
ok('metric-apparent-attenuation-v1' in registry_seed and "('apparent_attenuation_percent','metric-apparent-attenuation-v1','series_sg'" in registry_seed and "('apparent_attenuation_percent','metric-apparent-attenuation-v1','og'" in registry_seed,'apparent attenuation is an explicit registry-selected metric model')
legacy_metrics=['fg_progress_min_percent','fg_progress_percent','fg_progress_max_percent','current_to_peak_rate_ratio','absolute_sg_rate_points_per_day']
ok(all(m not in registry_seed for m in legacy_metrics),'p23r2 registry removes legacy FG-progress/rate-ratio/absolute-rate metrics')
ok(all(m not in (ROOT/'sql/03-w3470-template-seed.sql').read_text(encoding='utf-8') for m in legacy_metrics),'p23r2 W-34/70 template has no legacy percentage/rate-ratio criteria')
ok(all(x in schema for x in ['metric_runtime_rules','template_metric_runtime_rules','session_metric_runtime_rules','valid_minimum_value','valid_maximum_value']),'metric output validity is normalized and frozen from registry through template/session')
ok('valid_minimum_value,valid_maximum_value' in start_bundle,'Start freezes authoritative metric output bounds into session rules')
for eid in ['p20_bio_eval_query','p20_process_eval_query']:
    ok('r.valid_minimum_value,r.valid_maximum_value' in fn(eid),f'{eid} reads frozen metric output validity')
for eid in ['p20_bio_eval_result','p20_process_eval_result']:
    ef=fn(eid)
    ok('metric_output_outside_declared_range' in ef and 'valid_minimum_value' in ef and 'valid_maximum_value' in ef,f'{eid} rejects out-of-range metric output before criterion decisions')
    ok('metric-raw-attenuation-v1' in ef and 'metric-manual-attenuation-v1' in ef,f'{eid} executes registry-selected apparent-attenuation model')
ok("('metric-relative-sg-drop-v1','og'" not in registry_seed and "'relative_sg_drop_points','metric-relative-sg-drop-v1','og'" not in registry_seed,'relative SG-drop model no longer declares unused OG input')
for graph_id in ['attenuation','sg-rate','sg-stability']:
    ok(re.search(rf"(['\"]){re.escape(graph_id)}\1",analysis_fn) is None,f'generic analysis engine has no graph-ID-specific branch for {graph_id}')
for metric_id in ['relative_sg_drop_points','apparent_attenuation_percent','sg_rate_points_per_day']:
    ok(metric_id not in analysis_fn,f'generic analysis engine has no metric-ID-specific branch for {metric_id}')
ok('graph.description' in analysis_card and 'graph.unit' in analysis_card and 'axisTicks' in (ROOT/'tools/graph_renderer.js').read_text(),'Analyse header/axis presentation is driven by DB graph metadata')
for forbidden in ['relative-sg-drop','fg-progress','rate-to-peak','absolute-sg-rate','fg_progress_min_percent','current_to_peak_rate_ratio','absolute_sg_rate_points_per_day']:
    ok(forbidden not in analysis_card,f'Analyse frontend has no per-graph/domain special case for {forbidden}')
for v in ['v_graph_definitions','v_graph_series','v_graph_time_markers','v_active_analysis_requirements','v_active_analysis_biological_markers','v_active_analysis_process_markers']:
    ok(v in ovq,f'overview reads generic analysis read-model {v}')
projection=re.search(r'CREATE OR REPLACE VIEW v_measurement_source_ha_projection AS(.*?);',views,re.S).group(1)
for raw_nullable in ['\n  session_id,','\n  last_success_at,','\n  last_error,','\n  open_gap_id,','\n  open_gap_started_at,','\n  latest_bucket_at,']:
    ok(raw_nullable not in projection,f'HA measurement-source projection excludes nullable raw attribute {raw_nullable.strip().rstrip(",")}')
ok(all(x in projection for x in ['session_display','last_success_display','gap_status_display','last_error_display','updated_at_display']),'HA measurement-source projection exposes non-null prepared display attributes')
catch=by['p20_technical_catch'];ok(catch.get('scope') is None and catch.get('uncaught') is True,'Technical error sink is tab-wide uncaught catch rather than a finite node list')
start_result=by['p20_start_result'];ok(len(start_result.get('wires',[]))>=6 and start_result['wires'][5]==['p24r7_ha_check_request'] and 'post_start' in fn('p20_start_result'),'successful Start triggers a fresh Systemkontroll snapshot')
ingest_result=by['p21_live_ingest_write_result'];ok(len(ingest_result.get('wires',[]))>=7 and ingest_result['wires'][6]==['p24r7_ha_check_request'] and 'measurement_source_live' in fn('p21_live_ingest_write_result'),'transition from history catch-up to LIVE triggers a fresh Systemkontroll snapshot')


# p22r7-revised2: analysis visit markers must obtain owner IDs from visit tables, not revision-only views.
views_sql=(ROOT/'sql/20-views.sql').read_text(encoding='utf-8')
ok('JOIN biological_visits b ON b.session_id=g.session_id' in views_sql and 'JOIN v_biological_visit_timing r ON r.visit_id=b.visit_id' in views_sql,'analysis biological markers join biological_visits')
ok('JOIN process_visits p ON p.session_id=g.session_id' in views_sql and 'JOIN v_process_visit_timing r ON r.visit_id=p.visit_id' in views_sql,'analysis process markers join process_visits')
bio_marker_sql=views_sql[views_sql.find('CREATE OR REPLACE VIEW v_active_analysis_biological_markers'):views_sql.find('CREATE OR REPLACE VIEW v_active_analysis_process_markers')]
proc_marker_sql=views_sql.split('CREATE OR REPLACE VIEW v_active_analysis_process_markers',1)[1].split(';',1)[0]
ok('v.phase_id' not in bio_marker_sql and 'v.process_id' not in proc_marker_sql,'analysis marker views do not read owner ids from revision alias')


# p22r8: Technical measurement-source display, Analyse requirement table and compact criterion editor.
measurement_view=views_sql[views_sql.find('CREATE OR REPLACE VIEW v_measurement_source_status'):views_sql.find('CREATE OR REPLACE VIEW v_active_session_report_summary')]
for field in ['m.bucket_at','sm.last_import_cutoff_at','sm.last_success_at','g.gap_started_at']:
    ok(f"CONVERT_TZ({field},'+00:00','Europe/Oslo')" in measurement_view,f'measurement-source display converts {field} from UTC to Europe/Oslo before DATE_FORMAT')
projection_sql=views_sql[views_sql.find('CREATE OR REPLACE VIEW v_measurement_source_ha_projection'):views_sql.find('CREATE OR REPLACE VIEW v_active_session_report_summary')]
ok("CONVERT_TZ(source_started_at,'+00:00','Europe/Oslo')" in projection_sql and "CONVERT_TZ(updated_at,'+00:00','Europe/Oslo')" in projection_sql,'HA measurement-source projection owns local source/update display times')
ok(len(by['p21_live_ingest_write_result'].get('wires',[]))>3 and by['p21_live_ingest_write_result']['wires'][3]==['p21_measurement_source_read_query'],'every committed live-ingest result triggers measurement-source HA projection refresh')
ok('FROM_UTC_TIMESTAMP' not in views_sql,'MariaDB views do not use non-existent FROM_UTC_TIMESTAMP function')
ok(views_sql.count("CONVERT_TZ(")>=8 and "'Europe/Oslo'" in views_sql,'DB-owned local display timestamps use MariaDB CONVERT_TZ with Europe/Oslo')

system_card=method(card,'_renderSystem','_render')
ok('updated_at_display' in system_card and 'Målekilde / Tilt' in system_card,'Technical measurement-source panel exposes DB projection refresh timestamp')

analysis_view=views_sql[views_sql.find('CREATE OR REPLACE VIEW v_active_analysis_requirements'):views_sql.find('CREATE OR REPLACE VIEW v_active_analysis_biological_markers')]
ok(all(x in analysis_view for x in ['owner_type_display','role_display','met_status_display']),'analysis requirements read-model owns owner/role/met presentation fields')
analysis_req_table=method(card,'_analysisRequirementTable','_analysisChart')
ok(all(x in analysis_req_table for x in ['owner_display','owner_type_display','role_display','requirement_display','met_status_display']),'Analyse requirement table renders only DB-owned requirement presentation fields')
ok('_analysisRequirementTable(this._analysisRequirements(graph.graph_id))' in analysis_card and 'criterion-line' in (ROOT/'tools/graph_renderer.js').read_text() and 'r.met_at' in (ROOT/'tools/graph_renderer.js').read_text(),'same Analyse requirements collection drives table, threshold lines and met-at markers')

template_matrix=method(card,'_criterionMatrix','_criterionEditor')
template_bind=method(card,'_bindTemplateEditor','_templateMeta')
ok('Ubrukte kriterietyper' in template_matrix and 'matrix-metric-select' in template_matrix and 'Vis kriterietype' in template_matrix,'template matrices collect unused registry criteria in a dropdown')
ok('_matrixExtraMetrics[root].delete(metric)' in template_bind and 'stillUsed' in template_bind,'deleting last criterion occurrence returns metric to unused dropdown')
ok('this._templateDraftKey=key;this._templateDirty=false;this._matrixExtraMetrics={};' in card,'template reload clears transient revealed-unused criterion rows')


# p23r1: full MariaDB-backed template library/admin lifecycle independent of runtime.
template_schema=(ROOT/'sql/00-template-schema.sql').read_text(encoding='utf-8')
ok("status IN ('draft','published','retired')" in template_schema and 'CREATE TABLE IF NOT EXISTS template_editor_state' in template_schema,'template schema defines draft/published/retired lifecycle and persistent editor selection')
qfn=fn('p20_template_editor_query'); rfn=fn('p20_template_editor_read_result'); sfn=fn('p20_template_save_query'); cfn=fn('p20_template_clone_query')+'\n'+(ROOT/'sql/11-runtime-routines.sql').read_text().split('CREATE PROCEDURE ga_clone_template_tx')[1].split('END//',1)[0]; dfn=fn('p20_template_discard_query'); lfn=fn('p22_template_lifecycle_query')
ok(all(x in qfn for x in ['active_session_version_id','start_selected_version_id','admin_selected_version_id','template_editor_state']),'template read path separates active-session source, Start selection and admin selection')
ok("ctx.admin_selected_version_id||ctx.start_selected_version_id" in rfn and "mode=versionById[selectedVersion].status" in rfn,'template read-model uses DB admin selection and actual lifecycle status rather than runtime lock mode')
ok('active_session_id' in rfn and 'is_active_session_source' in rfn,'active session is exposed as informational template-library metadata only')
ok("NOT EXISTS(SELECT 1 FROM v_current_session)" not in sfn+cfn+dfn+lfn,'template draft/lifecycle administration remains available during active fermentation')
ok('UPDATE session_setup_draft' not in sfn,'template publishing cannot silently change Start selection')
ok("status IN ('published','retired')" in cfn and 'template_analysis_graphs' in cfn and 'template_analysis_graph_series' in cfn,'immutable published/retired versions can seed drafts and all analysis metadata is cloned')
ok("Ny template-ID finnes allerede" in cfn and "p_new_template<>'' AND EXISTS" in cfn,'new-template clone cannot fall through to an existing unrelated draft when identity is already occupied')
ok(cfn.find('INSERT INTO template_editor_state') < cfn.find('COMMIT;'),'template clone persists editor selection inside the same transaction')
ok("status='retired'" in lfn and "status='published'" in lfn and 'retired_at' in lfn,'template lifecycle implements retire and reactivation as explicit DB transitions')
ok('DELETE FROM session_setup_draft' in lfn,'retiring a Start-selected version clears that pre-start selection instead of leaving an invalid Start reference')
# Start selector invariant is checked across function source because the physical node retains its legacy id.
start_selector=(ROOT/'sql/11-runtime-routines.sql').read_text().split('CREATE PROCEDURE ga_select_start_template_tx',1)[1].split('END//',1)[0]
ok('ga_select_start_template_tx' in fn('p20_template_select') and "tv.status='published'" in start_selector,'Start template selection accepts only published versions')
card_template=method(card,'_renderTemplate','_bindTemplateEditor')
ok(all(x in card for x in ['Templatebibliotek','Opprett ny template fra eksisterende versjon','Sett utgått','Aktiver igjen','Sammenlign mot','uavhengig av templatevalget på Start','uten å påvirke den aktive sessionen']),'Template UI exposes library, new identity, reversible retirement, comparison and runtime-separation cues')
ok(all(x in card for x in ['gjaeringsassistent_template_admin_select','gjaeringsassistent_template_lifecycle']),'Template UI commands admin selection/lifecycle through HA events rather than local domain state')
metadata=(ROOT/'sql/21-system-metadata-seed.sql').read_text(encoding='utf-8')
ok(all(x in metadata for x in ['gjaeringsassistent_template_admin_select','gjaeringsassistent_template_lifecycle','table:template_editor_state']),'template admin events and editor-state lineage are registered in MariaDB metadata')

for x in passed: print('PASS',x)
for x in errors: print('FAIL',x)
if errors: raise SystemExit(1)
print(f'RESULT: PASS ({len(passed)} architecture-conformance checks)')
