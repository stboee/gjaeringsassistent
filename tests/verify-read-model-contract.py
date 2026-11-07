#!/usr/bin/env python3
from pathlib import Path
import json,re,sys
ROOT=Path(__file__).resolve().parents[1]
errors=[]; passed=[]
def ok(cond,label): (passed if cond else errors).append(label)

# Parse base-table columns from the active DDL.
schema='\n'.join((ROOT/'sql'/name).read_text(encoding='utf-8') for name in ['00-template-schema.sql','10-runtime-schema.sql'])
tables={}
for m in re.finditer(r'CREATE TABLE IF NOT EXISTS\s+([A-Za-z0-9_]+)\s*\(',schema,re.I):
    name=m.group(1); i=m.end(); depth=1; j=i; quote=None
    while j<len(schema) and depth:
        ch=schema[j]
        if quote:
            if ch==quote and schema[j-1] != '\\': quote=None
        else:
            if ch in "'\"`": quote=ch
            elif ch=='(': depth+=1
            elif ch==')': depth-=1
        j+=1
    body=schema[i:j-1]
    cols=set()
    for line in body.splitlines():
        s=line.strip().rstrip(',')
        if not s or re.match(r'(?i)(PRIMARY|UNIQUE|KEY|CONSTRAINT|CHECK|FOREIGN)\b',s):
            continue
        cm=re.match(r'`?([A-Za-z_][A-Za-z0-9_]*)`?\s+',s)
        if cm: cols.add(cm.group(1))
    tables[name]=cols

views_sql=(ROOT/'sql/20-views.sql').read_text(encoding='utf-8')
def view_def(name):
    m=re.search(rf'CREATE OR REPLACE VIEW\s+{re.escape(name)}\s+AS\s+',views_sql,re.I)
    if not m: return ''
    start=m.end(); depth=0; quote=None; j=start
    while j<len(views_sql):
        ch=views_sql[j]
        if quote:
            if ch==quote and views_sql[j-1] != '\\': quote=None
        else:
            if ch in "'\"`": quote=ch
            elif ch=='(': depth+=1
            elif ch==')': depth-=1
            elif ch==';' and depth==0: break
        j+=1
    return views_sql[start:j]

# Runtime view contracts. For star-views the actual table DDL owns the columns;
# explicit/derived views list the columns promised to Node-RED read-model queries.
viewcols={
 'v_current_session_timing':tables['session_timing_revisions'],
 'v_current_fermentation_target':{'session_id','expected_attenuation_min_percent','expected_attenuation_max_percent','expected_fg_min','expected_fg_max','source','target_revision_id','revision_no','action','note','operation_id','created_at','effective_at'},
 'v_current_biological_criterion_revision':tables['session_biological_criterion_revisions'],
 'v_current_process_criterion_revision':tables['session_process_criterion_revisions'],
 'v_effective_biological_criterion_parameters':{'session_id','phase_id','criterion_id','model_id','parameter_id','data_type','real_value','integer_value','boolean_value','text_value','criterion_revision_id'},
 'v_effective_process_criterion_parameters':{'session_id','process_id','criterion_id','model_id','parameter_id','data_type','real_value','integer_value','boolean_value','text_value','criterion_revision_id'},
 'v_current_observation_revision':tables['observation_round_revisions'],
 'v_recommendations_effective':tables['recommendations']|{'effective_status','latest_resolution_id','resolved_at'},
 'v_session_lifecycle':tables['session_lifecycle_events'],
 'v_current_session':{'session_id','batch_name','is_demo','created_at','pitched_at','activity_started_at','og','volume_l','yeast_profile_id','pitch_mode_id','pitch_temperature_c','lifecycle','lifecycle_at','completed_at'},
 'v_active_session':{'session_id','batch_name','is_demo','created_at','pitched_at','activity_started_at','og','volume_l','yeast_profile_id','pitch_mode_id','pitch_temperature_c'},
 'v_current_process_visit_revision':tables['process_visit_revisions'],
 'v_current_biological_visit_revision':tables['biological_visit_revisions'],
 'v_current_process_visit':{'session_id','visit_id','process_id','visit_no','process_order','process_name','visit_revision_id','revision_no','started_at','ended_at','timing_source','revision_reason','duration_seconds','visit_seq','session_rn'},
 'v_current_biological_visit':{'session_id','visit_id','phase_id','visit_no','phase_order','phase_name','visit_revision_id','revision_no','started_at','ended_at','timing_source','confidence','evaluation_id','revision_reason','duration_seconds','visit_seq','session_rn'},
 'v_latest_observation':{'session_id','observation_id','observation_revision_id','revision_no','recorded_at','measurement_method_id','measured_sg','corrected_sg','manual_temperature_c','pressure_bar','cooler_setpoint_c','cooler_calibration_offset_c','estimated_abv_percent','estimated_finished_abv_percent','airlock_activity','user_conclusion','calculated_conclusion','process_gate_status','note','rn'},
 'v_latest_process_evaluation':tables['process_evaluations']|{'rn'},
 'v_latest_biological_evaluation':tables['biological_evaluations']|{'rn'},
 'v_latest_system_check':tables['system_check_runs']|{'rn'},
 'v_active_technical_issues':tables['technical_events']|{'rn'},
 'v_current_session_summary':{'session_id','batch_name','is_demo','pitched_at','activity_started_at','completed_at','lifecycle','lifecycle_at','og','volume_l','expected_attenuation_min_percent','expected_attenuation_max_percent','expected_fg_min','expected_fg_max','expected_attenuation_display','expected_fg_display','current_process_visit_id','current_process_id','current_process_order','current_process_name','current_process_started_at','current_process_ended_at','current_biological_visit_id','current_biological_phase_id','current_biological_phase_order','current_biological_phase_name','current_biological_started_at','current_biological_ended_at','latest_observation_id','latest_observation_at','latest_manual_sg','latest_process_evaluation_id','latest_process_readiness','recommended_next_process_id','recommended_temperature_c','recommended_pressure_bar','latest_biological_evaluation_id','latest_biological_candidate_phase_id','latest_biological_confidence'},
 'v_active_session_summary':{'session_id','batch_name','is_demo','pitched_at','activity_started_at','completed_at','lifecycle','lifecycle_at','og','volume_l','current_process_visit_id','current_process_id','current_process_order','current_process_name','current_process_started_at','current_process_ended_at','current_biological_visit_id','current_biological_phase_id','current_biological_phase_order','current_biological_phase_name','current_biological_started_at','current_biological_ended_at','latest_observation_id','latest_observation_at','latest_manual_sg','latest_process_evaluation_id','latest_process_readiness','recommended_next_process_id','recommended_temperature_c','recommended_pressure_bar','latest_biological_evaluation_id','latest_biological_candidate_phase_id','latest_biological_confidence'},
 'v_system_function_information_chain':{'function_id','function_label','subsystem','function_status','relation_type','dependency_required','object_id','object_type','object_name','object_status','requires_producer','requires_consumer'},
 'v_metadata_lineage_gaps':{'subject_type','subject_id','gap_type','description'},
 'v_information_object_usage':{'object_id','object_type','object_name','object_status','requires_producer','requires_consumer','producer_count','consumer_count','participating_function_count'},
 'v_function_producer_consumer':{'producer_function_id','producer_relation','object_id','object_type','object_name','consumer_function_id','consumer_relation'},
 'v_biological_transition_evidence':tables['biological_evaluations']|{'transition_id','transitioned_at','from_phase_id','to_phase_id','transition_action','operation_id','candidate_phase_order','candidate_phase_name','evaluation_created_at'},
 'v_current_biological_candidate_evaluation':tables['biological_evaluations']|{'candidate_phase_order','candidate_phase_name','rn'},
 'v_process_transition_evidence':tables['process_evaluations']|{'transition_id','transitioned_at','from_process_id','to_process_id','transition_action','operation_id','candidate_process_order','candidate_process_name','evaluation_created_at'},
 'v_current_process_candidate_evaluation':tables['process_evaluations']|{'candidate_process_order','candidate_process_name','historical_replay_auto_transition_allowed','rn','operator_status_display'},
 'v_biological_evaluation_criterion_requirement':{'evaluation_id','criterion_id','requirement_display'},
 'v_process_evaluation_criterion_requirement':{'evaluation_id','criterion_id','requirement_display'},
 'v_biological_evaluation_criterion_read_model':tables['biological_evaluation_criteria']|{'evaluated_at','evaluation_created_at','label','metric_label','metric_unit','requirement_display','status_display','actual_display','data_window_display'},
 'v_process_evaluation_criterion_read_model':tables['process_evaluation_criteria']|{'evaluated_at','evaluation_created_at','label','metric_label','metric_unit','requirement_display','status_display','actual_display','data_window_display'},
 'v_current_metric_value':{'session_id','evaluation_id','metric_id','actual_value','actual_text','actual_display','evaluation_status','status_display','measured_at','evaluated_at','evaluation_created_at','source_scope','rn'},
 'v_measurement_source_status':{'state','message','source_profile_id','name','source_type','sg_entity_id','temperature_entity_id','heartbeat_entity_id','rssi_entity_id','poll_interval_seconds','gap_threshold_seconds','fresh_age_minutes','stale_age_minutes','session_id','is_demo','batch_name','lifecycle','source_started_at','last_import_cutoff_at','last_success_at','last_error','latest_bucket_at','latest_sample_count','sg_min','sg_mean','sg_median','sg_max','temperature_mean_c','rssi_mean_dbm','open_gap_id','open_gap_started_at','measurement_age_minutes','measurement_age_state','latest_measurement_state','data_quality_display','updated_at','latest_measurement_at_display','latest_bucket_display','latest_sg_display','latest_sg_detail_display','latest_temperature_display','latest_rssi_display','import_cutoff_display','last_success_display','poll_interval_display','gap_threshold_display','gap_status_display','gap_started_display','last_error_display','authority'},
 'v_measurement_source_ha_projection':{'state','message','source_profile_id','name','source_type','sg_entity_id','temperature_entity_id','heartbeat_entity_id','rssi_entity_id','poll_interval_display','gap_threshold_display','session_display','batch_display','lifecycle_display','source_started_display','import_cutoff_display','last_success_display','latest_bucket_display','latest_sample_count_display','latest_sg_display','latest_sg_detail_display','latest_temperature_display','latest_rssi_display','measurement_age_state','latest_measurement_state','data_quality_display','gap_status_display','gap_started_display','last_error_display','authority','updated_at_display'},
 'v_active_analysis_graphs':tables['session_analysis_graphs'],
 'v_active_analysis_series':{'session_id','graph_id','series_id','sort_order','label','source_kind','metric_id','owner_id','criterion_id','minimum_samples','minimum_coverage_fraction','warmup_minutes','valid_minimum_value','valid_maximum_value','sample_at','actual_value','range_min_value','range_max_value','measured_at','sample_count','window_started_at','window_ended_at','requested_window_seconds','coverage_seconds','value_source_kind'},
 'v_active_analysis_requirements':{'session_id','graph_id','owner_type','owner_id','criterion_id','label','role_id','minimum_value','maximum_value','met_at','owner_display','owner_type_display','role_display','requirement_display','met_at_display','met_status_display'},
 'v_active_analysis_biological_markers':{'session_id','graph_id','phase_id','label','started_at','ended_at'},
 'v_active_analysis_process_markers':{'session_id','graph_id','process_id','label','started_at','ended_at'},
 'v_active_analysis_time_markers':{'session_id','graph_id','marker_at','relative_day','axis_label'},
 'v_active_session_report_summary':{'session_id','batch_display','yeast_display','expected_attenuation_display','expected_fg_display','process_evaluated_display','process_duration_display','pitched_display','biology_display','process_display','latest_tilt_sg_display','attenuation_display','sg_rate_display','manual_measurements_display','latest_manual_sg_display','notes_display','datapoints_display','next_process_display','active_report_url','active_report_generated_display'},
 'v_active_session_report_session':{'session_id','batch_name','og','volume_l','pitched_display','pitched_ms','expected_attenuation_min_percent','expected_attenuation_max_percent','expected_fg_min','expected_fg_max','expected_fg_display','expected_attenuation_display','biology_display','process_display','template_name','version_label','latest_abv_display','estimated_finished_abv_display'},
 'v_active_session_report_biology':{'session_id','phase_id','name','started_ms','ended_ms','started_display','ended_display','timing_source_display','confidence'},
 'v_active_session_report_process':{'session_id','process_id','name','historical_replay_auto_transition_allowed','started_ms','ended_ms','started_display','ended_display','timing_source_display','historical_replay_policy_display'},
 'v_active_session_report_observations':{'session_id','at_ms','at_display','measured_sg','corrected_sg','manual_temperature_c','measurement_method_display','measured_sg_display','corrected_sg_display','manual_temperature_display','pressure_display','cooler_setpoint_display','airlock_activity_display','acetaldehyde_display','diacetyl_display','wort_like_display','sulfur_so2_display','sulfur_h2s_display','clarity_display','settling_yeast_display','settling_minutes_display','estimated_abv_display','estimated_finished_abv_display','user_conclusion_display','note_display','sg_marker_label','temperature_marker_label'},
 'v_active_session_report_gaps':{'session_id','started_display','ended_display','duration_display','source_display','gap_started_at'},
 'v_active_session_report_criterion_corrections':{'session_id','created_at','created_display','area_display','owner_id','criterion_label','action_display','parameters_display','note_display'},
 'v_active_session_report_process_exceptions':{'session_id','created_at','created_display','owner_id','criterion_label','action_display','exception_type_display','note_display'},
 'v_active_session_report_process_transitions':{'session_id','transitioned_at','transitioned_display','transition_display','action_display','note_display'},
 'v_active_session_report_actions':{'session_id','completed_at','completed_display','label','accepted_display','outcome_display','detail_display'},
 'v_active_session_report_timeline':{'session_id','happened_at','happened_display','type_display','event_display','note_display'},
 'v_active_session_report_series':{'session_id','at_ms','at_display','sg_min','sg_mean','sg_median','sg_max','temperature_min_c','temperature_mean_c','temperature_max_c','pressure_min_bar','pressure_mean_bar','pressure_max_bar','rssi_min_dbm','rssi_mean_dbm','rssi_max_dbm','sample_count','bucket_at'},
 'v_active_session_report_biological_criteria':{'session_id','evaluated_at','owner_id','evaluated_display','criterion_order','label','role_id','status_display','requirement_display','actual_display','data_window_display','explanation'},
 'v_active_session_report_process_criteria':{'session_id','evaluated_at','owner_id','evaluated_display','criterion_order','label','role_id','status_display','requirement_display','actual_display','data_window_display','explanation'},
 'v_active_session_report_notes':{'session_id','noted_at','noted_display','note_text'},
}


# p23r2-revised7 DB-owned dynamic graph-axis/read-range models.
viewcols.update({
 'v_session_overview_graph_extents':{'session_id','graph_id','data_min','data_max','include_zero'},
 'v_session_overview_graph_axes':{'session_id','graph_id','y_axis_min','y_axis_max','y_axis_tick_step'},
 'v_active_overview_graph_extents':{'session_id','graph_id','data_min','data_max','include_zero'},
 'v_active_overview_graph_axes':{'session_id','graph_id','y_axis_min','y_axis_max','y_axis_tick_step'},
 'v_session_analysis_graph_extents':{'session_id','graph_id','display_decimals','y_axis_include_zero','data_min','data_max'},
 'v_session_analysis_graph_axes':{'session_id','graph_id','y_axis_min','y_axis_max','y_axis_tick_step'},
 'v_session_analysis_graphs':{'session_id','graph_id','sort_order','label','description','unit','display_decimals','y_axis_min','y_axis_max','y_axis_tick_step','y_axis_include_zero','x_axis_mode','enabled','show_biological_bands','show_process_markers','show_criterion_markers','gap_policy','created_at'},
 'v_session_analysis_requirements':{'session_id','graph_id','owner_type','owner_id','criterion_id','label','role_id','minimum_value','maximum_value','met_at','owner_display','owner_type_display','role_display','requirement_display','met_at_display','met_status_display'},
 'v_active_analysis_graph_extents':{'session_id','graph_id','display_decimals','y_axis_include_zero','data_min','data_max'},
 'v_active_analysis_graph_axes':{'session_id','graph_id','y_axis_min','y_axis_max','y_axis_tick_step'},
})


# p23 structured verification read-models.
viewcols.update({
 'v_current_verification_test_result':{'result_id','run_id','test_id','result_status','observed_at','executor','note','evidence_ref','created_at','application_version','run_type','environment','source','started_at','completed_at','overall_status'},
 'v_verification_definition_status':{'verification_id','verification_type','title','acceptance_criterion','required_test_count','pass_count','fail_count','blocked_count','not_run_count','verification_status'},
 'v_requirement_verification_status':{'requirement_id','document_id','requirement_class','statement','source_ref','verification_count','pass_count','fail_count','blocked_count','pending_count','verification_status'},
 'v_verification_summary':{'test_type','test_count','pass_count','fail_count','blocked_count','not_run_count','latest_observed_at'},
 'v_verification_uat_pending':{'test_id','title','description','method_type','implementation_ref','current_status','observed_at','executor','note','evidence_ref'},
 'v_verification_unlinked_items':{'item_type','item_id','item_label'},
 'v_verification_test_history':{'result_id','run_id','test_id','test_type','title','result_status','observed_at','executor','note','evidence_ref','application_version','run_type','environment','source','started_at','completed_at','overall_status'},
})

# p24r1 shared presentation contract.
viewcols.update({
 'v_session_biological_exception_read_model':tables['biological_criterion_exceptions']|{'label','owner_id','created_display','action_display','exception_type_display','note_display'},
 'v_session_graph_time_axis':{'session_id','x_axis_started_at','x_axis_ended_at','x_axis_start_display','x_axis_end_display'},
 'v_session_analysis_series':viewcols['v_active_analysis_series']|set(tables['session_analysis_graph_series'])|{'value_status','value_status_display','basis_display','coverage_fraction','line_color','line_dasharray','actual_value_display','standard_basis_met'},
 'v_session_analysis_time_markers':viewcols['v_active_analysis_time_markers'],
 'v_criterion_default_operator_policy':{'metric_id','model_id','correctable_parameters_json','exception_allowed'},
 'v_session_analysis_axis_ticks':{'session_id','graph_id','tick_value','axis_label'},
 'v_session_overview_axis_ticks':{'session_id','graph_id','tick_value','axis_label'},
})
viewcols['v_active_analysis_series']=viewcols['v_session_analysis_series']
for v in ['v_session_overview_graph_axes','v_active_overview_graph_axes','v_session_analysis_graphs','v_active_analysis_graphs']:
 viewcols[v]|=viewcols['v_session_graph_time_axis']
# p24r6 archive and latest-value read models.
viewcols.update({
 'v_session_archive_status':{'session_id','archive_attempt_no','archive_requested_at','archive_error_message','archive_status','archive_status_display'},
 'v_session_analysis_latest':{'session_id','graph_id','series_id','sort_order','label','actual_value','measured_at','latest_value_display'},
 'v_session_history':{'session_id','batch_name','pitched_at','original_pitched_at','is_demo','template_version_id','template_name','version_label','lifecycle','completed_at','released_at','archive_path','archive_sha256','report_path','archive_url','report_url'},
})
viewcols['v_session_analysis_series']|={'source_observation_revision_id','basis_revision_key','basis_pitched_at'}
viewcols['v_active_analysis_series']=viewcols['v_session_analysis_series']
for name in ['v_current_session_summary','v_active_session_summary']:
 viewcols[name]|=viewcols['v_session_archive_status']
# Explicit MariaDB 12.3.3 column contract for p24r7.
viewcols.update({name:set(columns) for name,columns in json.loads((ROOT/'contracts/read-model-columns.json').read_text()).items()})
ok(set(viewcols)==set(re.findall(r'CREATE OR REPLACE VIEW\s+([A-Za-z0-9_]+)',views_sql,re.I)),'read-model contract covers every active runtime view')

# p23r2 target is immutable session data derived from OG + expected attenuation.
# Keep stable audit-shaped columns for consumers, but there is no active correction chain.
fg=view_def('v_current_fermentation_target')
for col in ['expected_attenuation_min_percent','expected_attenuation_max_percent','expected_fg_min','expected_fg_max','operation_id','created_at']:
    ok(bool(re.search(rf'\b{col}\b',fg)),f'v_current_fermentation_target projects {col}')

flow=json.loads((ROOT/'nodered/flows.template.json').read_text(encoding='utf-8'))
problems=[]; checked=0
for node in flow:
    if node.get('type')!='function': continue
    source=str(node.get('func',''))
    # Runtime SQL statements are separated by semicolons. For every direct view alias
    # in a statement, verify all qualified alias.column references against the view contract.
    for stmt in source.split(';'):
        aliases=[]
        for m in re.finditer(r'\b(?:FROM|JOIN|LEFT JOIN|RIGHT JOIN|INNER JOIN)\s+(v_[A-Za-z0-9_]+)\s+([A-Za-z_][A-Za-z0-9_]*)',stmt,re.I):
            view,alias=m.group(1),m.group(2)
            if view in viewcols: aliases.append((view,alias))
        for view,alias in aliases:
            refs=set(re.findall(rf'\b{re.escape(alias)}\.([A-Za-z_][A-Za-z0-9_]*)',stmt))
            if refs: checked+=1
            for col in sorted(refs-viewcols[view]):
                problems.append(f"{node.get('id')} references {alias}.{col}, absent from {view}")
ok(not problems,f'qualified runtime SELECT references match active view contracts ({checked} alias checks)')
if problems:
    errors.extend(problems)

sysq=next(n for n in flow if n.get('id')=='p20_systemcheck_query').get('func','')
ok("SELECT 'active_sessions' AS check_id,COUNT(*) AS n FROM v_active_session;" in sysq and "FROM sessions WHERE status='active'" not in sysq,'Systemkontroll reads derived active-session view, not removed sessions.status')

for label in passed: print('PASS',label)
for label in errors: print('FAIL',label)
if errors: raise SystemExit(1)
print(f'RESULT: PASS ({len(passed)} read-model/schema contract checks)')
