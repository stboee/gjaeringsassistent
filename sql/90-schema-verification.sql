-- Gjæringsassistent – schema verification after install
-- Expected against a clean p23r2 installation; exact release version is stamped and verified by installer.

SELECT 'timezone_europe_oslo_available' AS test,
       IF(
         CONVERT_TZ('2026-01-15 12:00:00','+00:00','Europe/Oslo')='2026-01-15 13:00:00'
         AND CONVERT_TZ('2026-07-15 12:00:00','+00:00','Europe/Oslo')='2026-07-15 14:00:00',
         'PASS',
         'FAIL: MariaDB timezone tables mangler Europe/Oslo eller DST-regler'
       ) AS result;

SELECT 'base_table_count' AS test,
       IF(COUNT(*)=202,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result
FROM information_schema.tables
WHERE table_schema=DATABASE() AND table_type='BASE TABLE';

SELECT 'measurement_input_draft_present' AS test,
       IF(COUNT(*)=1,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result
FROM information_schema.tables
WHERE table_schema=DATABASE()
  AND table_type='BASE TABLE'
  AND table_name='measurement_input_draft';

SELECT 'session_lifecycle_events_present' AS test,
       IF(COUNT(*)=1,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result
FROM information_schema.tables
WHERE table_schema=DATABASE()
  AND table_type='BASE TABLE'
  AND table_name='session_lifecycle_events';


SELECT 'session_release_events_present' AS test,
       IF(COUNT(*)=1,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result
FROM information_schema.tables
WHERE table_schema=DATABASE()
  AND table_type='BASE TABLE'
  AND table_name='session_release_events';

SELECT 'p21_current_session_views_present' AS test,
       IF(COUNT(*)=2,'PASS',CONCAT('FAIL: ',COUNT(*),'/2')) AS result
FROM information_schema.views
WHERE table_schema=DATABASE()
  AND table_name IN ('v_current_session','v_current_session_summary');

SELECT 'session_identity_has_no_mutable_lifecycle_columns' AS test,
       IF(COUNT(*)=0,'PASS',CONCAT('FAIL: ',GROUP_CONCAT(column_name))) AS result
FROM information_schema.columns
WHERE table_schema=DATABASE() AND table_name='sessions'
  AND column_name IN ('status','active_guard','activity_started_at','completed_at','completion_note');

SELECT 'view_count' AS test,
       IF(COUNT(*)=178,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result
FROM information_schema.views
WHERE table_schema=DATABASE();


SELECT 'evaluation_status_columns_present' AS test,
       IF(COUNT(*)=2,'PASS',CONCAT('FAIL: ',COUNT(*),'/2')) AS result
FROM information_schema.columns
WHERE table_schema=DATABASE() AND table_name IN ('biological_evaluation_criteria','process_evaluation_criteria') AND column_name='evaluation_status';

SELECT 'demo_reference_profile_present' AS test,
       IF(COUNT(*)=1,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result
FROM demo_reference_profiles WHERE profile_id='tilt-pro-blue-20260925';

SELECT 'demo_reference_measurements_dense' AS test,
       IF(COUNT(*)>=650,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result
FROM demo_reference_measurements_5m WHERE profile_id='tilt-pro-blue-20260925';

SELECT 'demo_reference_gap_preserved' AS test,
       IF(COUNT(*)>=1 AND MAX(duration_seconds)>36000,'PASS',CONCAT('FAIL: gaps=',COUNT(*),' max=',COALESCE(MAX(duration_seconds),0))) AS result
FROM demo_reference_data_gaps WHERE profile_id='tilt-pro-blue-20260925';

SELECT 'demo_reference_gap_has_no_full_bucket_rows' AS test,
       IF(COUNT(*)=0,'PASS',CONCAT('FAIL: ',COUNT(*),' rows inside full gap buckets')) AS result
FROM demo_reference_measurements_5m r
JOIN demo_reference_data_gaps g ON g.profile_id=r.profile_id
WHERE r.profile_id='tilt-pro-blue-20260925'
  AND r.offset_seconds >= CEIL(g.gap_start_offset_seconds/300)*300
  AND r.offset_seconds < FLOOR(g.gap_end_offset_seconds/300)*300;

SELECT 'ha_entity_registry_count' AS test,
       IF(COUNT(*)=75,'PASS',CONCAT('FAIL: ',COUNT(*),'/75')) AS result
FROM ha_entity_registry WHERE status='active';

SELECT 'ha_bootstrap_contract_complete' AS test,
       IF(COUNT(*)=0,'PASS',CONCAT('FAIL: ',COUNT(*),' invalid rows')) AS result
FROM ha_entity_registry
WHERE status='active' AND ((entity_type='button' AND bootstrap_mode<>'registration_only') OR (entity_type<>'button' AND (bootstrap_slot IS NULL OR bootstrap_node_id IS NULL OR bootstrap_value IS NULL)));

SELECT 'system_function_lineage_no_orphans' AS test,
       IF(COUNT(*)=0,'PASS',CONCAT('FAIL: ',COUNT(*),' functions without dependencies')) AS result
FROM v_metadata_lineage_gaps WHERE gap_type='no_dependency';

SELECT 'required_information_chain_complete' AS test,
       IF(COUNT(*)=0,'PASS',CONCAT('FAIL: ',COUNT(*),' required objects disconnected')) AS result
FROM v_metadata_lineage_gaps WHERE gap_type IN ('missing_producer','missing_consumer');

SELECT 'all_tables_innodb' AS test,
       IF(COUNT(*)=0,'PASS',CONCAT('FAIL: ',COUNT(*),' non-InnoDB')) AS result
FROM information_schema.tables
WHERE table_schema=DATABASE()
  AND table_type='BASE TABLE'
  AND engine<>'InnoDB';

SELECT 'no_json_named_columns' AS test,
       IF(COUNT(*)=0,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result
FROM information_schema.columns
WHERE table_schema=DATABASE()
  AND LOWER(column_name) LIKE '%json%';

SELECT 'no_legacy_generic_state_tables' AS test,
       IF(COUNT(*)=0,'PASS',CONCAT('FAIL: ',GROUP_CONCAT(table_name))) AS result
FROM information_schema.tables
WHERE table_schema=DATABASE()
  AND table_name IN ('session_events','runtime_projection','session_process_state','session_biological_state','system_check_state');

SELECT 'p18_rich_history_core_present' AS test,
       IF(COUNT(*)=11,'PASS',CONCAT('FAIL: ',COUNT(*),'/11')) AS result
FROM information_schema.tables
WHERE table_schema=DATABASE()
  AND table_type='BASE TABLE'
  AND table_name IN (
    'process_visits','process_visit_revisions',
    'biological_visits','biological_visit_revisions',
    'process_evaluations','process_evaluation_criteria','process_criterion_exceptions',
    'recommendations','recommendation_resolutions',
    'process_transitions','biological_transitions'
  );

SELECT 'measurement_5m_required_columns' AS test,
       IF(COUNT(*)=5,'PASS',CONCAT('FAIL: ',COUNT(*),'/5')) AS result
FROM information_schema.columns
WHERE table_schema=DATABASE()
  AND table_name='measurements_5m'
  AND column_name IN ('sample_count','sg_min','sg_mean','sg_median','sg_max');

SELECT 'runtime_calculation_models_registered' AS test,
       IF(COUNT(*)=5,'PASS',CONCAT('FAIL: ',COUNT(*),'/5')) AS result
FROM calculation_models
WHERE model_id IN (
 'hydrometer-temperature-correction-sg-v1',
 'refractometer-sg-before-fermentation-v1',
 'refractometer-alcohol-correction-sg-to-sg-v2',
 'cutaia-apparent-abv-v1',
 'expected-attenuation-midpoint-v1'
);

SELECT 'criterion_parameter_typed_key' AS test,
       IF(COUNT(*)=3 AND GROUP_CONCAT(column_name ORDER BY seq_in_index SEPARATOR ',')='model_id,parameter_id,data_type',
          'PASS',
          CONCAT('FAIL: ',COUNT(*),' columns')) AS result
FROM information_schema.statistics
WHERE table_schema=DATABASE()
  AND table_name='criterion_model_parameters'
  AND index_name='uq_criterion_model_parameters__typed';

SELECT 'data_gap_default_900s' AS test,
       IF(COUNT(*)=1,'PASS',CONCAT('FAIL: default=',COALESCE(MAX(column_default),'NULL'))) AS result
FROM information_schema.columns
WHERE table_schema=DATABASE()
  AND table_name='measurement_data_gaps'
  AND column_name='threshold_seconds'
  AND CAST(column_default AS CHAR) IN ('900','900.000000');

-- retained p20/p21 compatibility checks -------------------------------------------------------
SELECT 'p20r1_database_metadata' AS test,
       IF(COUNT(*)=1,'PASS','FAIL') AS result
FROM database_metadata
WHERE metadata_id=1 AND schema_version=9 AND application_version IS NOT NULL AND application_version<>'';

SELECT 'p20r1_draft_pitch_timing_columns' AS test,
       IF(COUNT(*)=2,'PASS',CONCAT('FAIL: ',COUNT(*),'/2')) AS result
FROM information_schema.columns
WHERE table_schema=DATABASE() AND table_name='session_setup_draft'
  AND column_name IN ('pitched_at','pitch_time_mode');


SELECT 'p20r1_revised1_start_measurement_columns' AS test,
       IF(COUNT(*)=19,'PASS',CONCAT('FAIL: ',COUNT(*),'/19')) AS result
FROM information_schema.columns
WHERE table_schema=DATABASE() AND table_name='session_setup_draft'
  AND column_name IN (
    'measurement_method_id','measured_sg','sample_temperature_c','calibration_temperature_c',
    'manual_temperature_c','pressure_bar','cooler_setpoint_c','cooler_calibration_offset_c',
    'airlock_activity','acetaldehyde_level','diacetyl_level','wort_like_level','sulfur_so2_level',
    'sulfur_h2s_level','clarity_level','settling_yeast_level','settling_minutes','user_conclusion','measurement_note'
  );


SELECT 'template_lifecycle_statuses' AS test,
       IF(COUNT(*)>=1,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result
FROM information_schema.check_constraints
WHERE constraint_schema=DATABASE()
  AND table_name='template_versions'
  AND check_clause LIKE '%status%'
  AND check_clause LIKE '%draft%'
  AND check_clause LIKE '%published%'
  AND check_clause LIKE '%retired%';
SELECT 'template_editor_state_present' AS test,
       IF(COUNT(*)=1,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result
FROM information_schema.tables
WHERE table_schema=DATABASE() AND table_type='BASE TABLE' AND table_name='template_editor_state';
SELECT 'w3470_published_template' AS test,
       IF(COUNT(*)=1,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result
FROM template_versions
WHERE version_id='w3470-standard@3.0' AND status='published';

SELECT 'w3470_six_biological_phases' AS test,
       IF(COUNT(*)=6,'PASS',CONCAT('FAIL: ',COUNT(*),'/6')) AS result
FROM template_biological_phases
WHERE version_id='w3470-standard@3.0';

SELECT 'w3470_fifteen_process_slots' AS test,
       IF(COUNT(*)=15,'PASS',CONCAT('FAIL: ',COUNT(*),'/15')) AS result
FROM template_process_steps
WHERE version_id='w3470-standard@3.0';

SELECT 'w3470_ten_enabled_process_steps' AS test,
       IF(COUNT(*)=10,'PASS',CONCAT('FAIL: ',COUNT(*),'/10')) AS result
FROM template_process_steps
WHERE version_id='w3470-standard@3.0' AND enabled=1;

SELECT 'demo_reference_state_markers count' AS test,
       IF((SELECT COUNT(*) FROM demo_reference_state_markers WHERE profile_id='tilt-pro-blue-20260925')=3,'PASS','FAIL') AS result;
SELECT 'demo state remains B3/P2' AS test,
       IF((SELECT COUNT(*) FROM demo_reference_state_markers WHERE profile_id='tilt-pro-blue-20260925' AND marker_kind='biological_phase' AND state_id IN ('B2','B3'))=2
          AND (SELECT COUNT(*) FROM demo_reference_state_markers WHERE profile_id='tilt-pro-blue-20260925' AND marker_kind='process_step' AND state_id='P2')=1
          AND (SELECT COUNT(*) FROM demo_reference_state_markers WHERE profile_id='tilt-pro-blue-20260925' AND state_id IN ('B4','P3'))=0,'PASS','FAIL') AS result;


SELECT 'measurement_source_profile_present' AS test,
       IF((SELECT COUNT(*) FROM measurement_source_profiles WHERE source_profile_id='tilt-pro-blue-ha' AND status='active')=1,'PASS','FAIL') AS result;
SELECT 'measurement_source_profile_complete' AS test,
       IF((SELECT COUNT(*) FROM measurement_source_profiles WHERE source_profile_id='tilt-pro-blue-ha' AND sg_entity_id<>'' AND temperature_entity_id<>'' AND heartbeat_entity_id<>'')=1,'PASS','FAIL') AS result;

-- p22r5-revised1: compile/query smoke for database-owned display/read-models.
-- These are schema/read-model checks only. They deliberately execute the
-- display expressions so charset/collation errors fail installation instead
-- of first surfacing from the 15-second runtime overview refresh.
SELECT 'current_process_candidate_display_queryable' AS test,
       IF(COALESCE((SELECT CHAR_LENGTH(operator_status_display) FROM v_current_process_candidate_evaluation LIMIT 1),0)>=0,'PASS','FAIL') AS result;
SELECT 'active_report_summary_display_queryable' AS test,
       IF(COALESCE((SELECT CHAR_LENGTH(CONCAT_WS('|',biology_display,process_display,next_process_display)) FROM v_active_session_report_summary LIMIT 1),0)>=0,'PASS','FAIL') AS result;
SELECT 'active_report_session_display_queryable' AS test,
       IF(COALESCE((SELECT CHAR_LENGTH(CONCAT_WS('|',biology_display,process_display,expected_fg_display)) FROM v_active_session_report_session LIMIT 1),0)>=0,'PASS','FAIL') AS result;
SELECT 'active_report_corrections_display_queryable' AS test,
       IF(COALESCE((SELECT CHAR_LENGTH(parameters_display) FROM v_active_session_report_criterion_corrections LIMIT 1),0)>=0,'PASS','FAIL') AS result;
SELECT 'active_report_transitions_display_queryable' AS test,
       IF(COALESCE((SELECT CHAR_LENGTH(transition_display) FROM v_active_session_report_process_transitions LIMIT 1),0)>=0,'PASS','FAIL') AS result;
SELECT 'active_report_timeline_display_queryable' AS test,
       IF(COALESCE((SELECT CHAR_LENGTH(event_display) FROM v_active_session_report_timeline LIMIT 1),0)>=0,'PASS','FAIL') AS result;


-- p22r7 analysis/validation contract smoke -----------------------------------
SELECT 'p22r7_analysis_tables_present' AS test, IF(COUNT(*)=6,'PASS',CONCAT('FAIL: ',COUNT(*),'/6')) AS result FROM information_schema.tables WHERE table_schema=DATABASE() AND table_type='BASE TABLE' AND table_name IN ('template_analysis_graphs','template_analysis_graph_series','session_analysis_graphs','session_analysis_graph_series','analysis_series_values','analysis_validation_events');
SELECT 'p22r7_validation_tables_present' AS test, IF(COUNT(*)=7,'PASS',CONCAT('FAIL: ',COUNT(*),'/7')) AS result FROM information_schema.tables WHERE table_schema=DATABASE() AND table_type='BASE TABLE' AND table_name IN ('measurement_validation_models','measurement_validation_model_parameters','measurement_source_validation_rules','measurement_source_validation_rule_parameter_values','session_measurement_validation_rules','session_measurement_validation_rule_parameter_values','measurement_ingest_quality_events');
SELECT 'p23r2_analysis_readmodels_queryable' AS test, IF(COUNT(*)=6,'PASS',CONCAT('FAIL: ',COUNT(*),'/6')) AS result FROM information_schema.views WHERE table_schema=DATABASE() AND table_name IN ('v_active_analysis_graphs','v_active_analysis_series','v_active_analysis_requirements','v_active_analysis_biological_markers','v_active_analysis_process_markers','v_active_analysis_time_markers');
SELECT 'p22r7_measurement_projection_queryable' AS test, IF(COALESCE((SELECT CHAR_LENGTH(CONCAT_WS('|',state,session_display,last_success_display,gap_status_display,last_error_display)) FROM v_measurement_source_ha_projection LIMIT 1),0)>=0,'PASS','FAIL') AS result;
SELECT 'p23r2_three_analysis_graphs' AS test, IF(COUNT(*)=3,'PASS',CONCAT('FAIL: ',COUNT(*),'/3')) AS result FROM template_analysis_graphs WHERE version_id='w3470-standard@3.0' AND enabled=1;
SELECT 'p22r7_source_validation_seeded' AS test, IF(COUNT(*)>=10,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result FROM measurement_source_validation_rules WHERE source_profile_id='tilt-pro-blue-ha' AND enabled=1;
SELECT 'p22r7_metric_output_bounds_seeded' AS test,
       IF(COUNT(*)=3,'PASS',CONCAT('FAIL: ',COUNT(*),'/3')) AS result
FROM metric_runtime_rules
WHERE valid_minimum_value IS NOT NULL AND valid_maximum_value IS NOT NULL
  AND metric_id IN ('relative_sg_drop_points','sg_rate_points_per_day','apparent_attenuation_percent');
SELECT 'p22r7_metric_output_bounds_materialized_to_template' AS test,
       IF(COUNT(*)=3,'PASS',CONCAT('FAIL: ',COUNT(*),'/3')) AS result
FROM template_metric_runtime_rules
WHERE version_id='w3470-standard@3.0'
  AND valid_minimum_value IS NOT NULL AND valid_maximum_value IS NOT NULL
  AND metric_id IN ('relative_sg_drop_points','sg_rate_points_per_day','apparent_attenuation_percent');
SELECT 'p24r6_raw_sg_drop_has_explicit_og_input' AS test,
       IF((SELECT COUNT(*) FROM calculation_model_inputs WHERE model_id='metric-raw-sg-drop-v1' AND input_id='og')=1
          AND (SELECT COUNT(*) FROM metric_runtime_inputs WHERE metric_id='relative_sg_drop_points' AND input_id='og')=1,
          'PASS','FAIL') AS result;


-- p23 structured verification ------------------------------------------------
SELECT 'p23_verification_metadata_tables_present' AS test,
       IF(COUNT(*)=8,'PASS',CONCAT('FAIL: ',COUNT(*),'/8')) AS result
FROM information_schema.tables
WHERE table_schema=DATABASE() AND table_type='BASE TABLE' AND table_name IN (
 'verification_requirements_catalog','verification_decisions_catalog','verification_definitions','verification_requirement_links',
 'verification_decision_requirement_links','verification_tests','verification_test_links','verification_uat_steps');

SELECT 'p23_verification_runtime_tables_present' AS test,
       IF(COUNT(*)=2,'PASS',CONCAT('FAIL: ',COUNT(*),'/2')) AS result
FROM information_schema.tables
WHERE table_schema=DATABASE() AND table_type='BASE TABLE' AND table_name IN ('verification_test_runs','verification_test_results');

SELECT 'p23_verification_views_present' AS test,
       IF(COUNT(*)=7,'PASS',CONCAT('FAIL: ',COUNT(*),'/7')) AS result
FROM information_schema.views
WHERE table_schema=DATABASE() AND table_name IN ('v_current_verification_test_result','v_verification_definition_status','v_requirement_verification_status','v_verification_summary','v_verification_uat_pending','v_verification_unlinked_items','v_verification_test_history');

SELECT 'p23_verification_test_catalog_seeded' AS test,
       IF(COUNT(*)>=29,'PASS',CONCAT('FAIL: ',COUNT(*),'/29+')) AS result
FROM verification_tests WHERE status='active';

SELECT 'p23_verification_release_results_seeded' AS test,
       IF(COUNT(*)>=1,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result
FROM verification_test_runs WHERE source='release_build' AND application_version=(SELECT application_version FROM database_metadata WHERE metadata_id=1);
