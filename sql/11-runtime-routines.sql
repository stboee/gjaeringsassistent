DROP PROCEDURE IF EXISTS ga_prepare_selected_demo_tx;
DROP PROCEDURE IF EXISTS ga_convert_legacy_archive_graphs;
-- Gjæringsassistent – transactional runtime command routines
-- Start uses connection-scoped variables populated by start-session.sql.
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- One pooled CALL owns the complete transaction, including rollback on errors.
DROP PROCEDURE IF EXISTS ga_store_system_check_tx;
DELIMITER //
CREATE PROCEDURE ga_store_system_check_tx(IN p_overall VARCHAR(32), IN p_checks LONGTEXT)
BEGIN
  DECLARE v_run VARCHAR(128);
  DECLARE v_now DATETIME(3);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  IF JSON_VALID(p_checks)<>1 OR JSON_LENGTH(p_checks)<>(SELECT COUNT(*) FROM system_check_definitions WHERE enabled=1) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Systemkontroll må inneholde alle definerte kontroller';
  END IF;
  SET v_run=CONCAT('syscheck-',REPLACE(UUID(),'-',''));
  SET v_now=UTC_TIMESTAMP(3);
  START TRANSACTION;
  INSERT INTO system_check_runs(check_run_id,session_id,overall_status,checked_at,operation_id,created_at)
    VALUES(v_run,NULL,p_overall,v_now,v_run,v_now);
  INSERT INTO system_check_results(check_run_id,check_id,check_order,status,severity,summary,created_at)
    SELECT v_run,j.check_id,j.check_order,j.status,j.severity,j.summary,v_now
    FROM JSON_TABLE(p_checks,'$[*]' COLUMNS(check_order FOR ORDINALITY,check_id VARCHAR(128) PATH '$.id',status VARCHAR(32) PATH '$.status',severity VARCHAR(16) PATH '$.severity',summary TEXT PATH '$.summary')) j;
  IF EXISTS(SELECT 1 FROM system_check_results r LEFT JOIN system_check_definitions d ON d.check_id=r.check_id AND d.enabled=1 WHERE r.check_run_id=v_run AND d.check_id IS NULL) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Systemkontroll inneholder ukjent kontroll';
  END IF;
  INSERT INTO technical_events(event_id,schema_version,occurred_at,severity,event_type,code,issue_key,subsystem,source_component,message,recoverable,blocks_operation,created_at)
    SELECT CONCAT(v_run,'-raise-',r.check_order),'1.0',v_now,r.severity,'issue_raised',CONCAT('SYSTEM_CHECK_',UPPER(r.check_id)),CONCAT('system_check:',r.check_id),'system_check','ga_store_system_check_tx',r.summary,1,IF(r.severity IN ('error','critical'),1,0),v_now
    FROM system_check_results r WHERE r.check_run_id=v_run AND r.status IN ('error','warning')
    AND NOT EXISTS(SELECT 1 FROM v_active_technical_issues a WHERE a.issue_key=CONCAT('system_check:',r.check_id) AND a.message=r.summary);
  INSERT INTO technical_events(event_id,schema_version,occurred_at,severity,event_type,code,issue_key,subsystem,source_component,message,recoverable,blocks_operation,created_at)
    SELECT CONCAT(v_run,'-clear-',r.check_order),'1.0',v_now,'info','issue_cleared',CONCAT('SYSTEM_CHECK_',UPPER(r.check_id),'_CLEARED'),CONCAT('system_check:',r.check_id),'system_check','ga_store_system_check_tx',CONCAT('Kontroll OK · ',r.summary),1,0,v_now
    FROM system_check_results r WHERE r.check_run_id=v_run AND r.status='ok'
    AND EXISTS(SELECT 1 FROM v_active_technical_issues a WHERE a.issue_key=CONCAT('system_check:',r.check_id));
  INSERT INTO technical_events(event_id,schema_version,occurred_at,severity,event_type,code,issue_key,subsystem,source_component,message,recoverable,blocks_operation,created_at)
    SELECT CONCAT(v_run,'-db-recovered'),'1.0',v_now,'info','issue_cleared','MARIADB_RUNTIME_RECOVERED','mariadb-runtime','database','ga_store_system_check_tx','MariaDB svarer igjen',1,0,v_now
    WHERE EXISTS(SELECT 1 FROM v_active_technical_issues WHERE issue_key='mariadb-runtime');
  COMMIT;
  SELECT * FROM system_check_runs WHERE check_run_id=v_run;
  SELECT * FROM system_check_results WHERE check_run_id=v_run ORDER BY check_order;
  SELECT * FROM v_active_technical_issues ORDER BY occurred_at DESC;
  SELECT * FROM v_technical_event_presentation ORDER BY occurred_at DESC,created_at DESC LIMIT 50;
END//
DELIMITER ;

DROP PROCEDURE IF EXISTS ga_request_archive_tx;
DELIMITER //
CREATE PROCEDURE ga_request_archive_tx(IN p_session VARCHAR(128), IN p_resume BOOLEAN)
BEGIN
  DECLARE v_sid VARCHAR(128);
  DECLARE v_aid VARCHAR(128);
  DECLARE v_no BIGINT UNSIGNED;
  DECLARE v_decision VARCHAR(32) DEFAULT 'missing';
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  SET v_sid=(SELECT session_id FROM v_current_session WHERE lifecycle='completed' AND (p_session IS NULL OR session_id=p_session) LIMIT 1);
  IF v_sid IS NOT NULL THEN
    IF EXISTS(SELECT 1 FROM session_exports WHERE session_id=v_sid AND export_kind='completed_archive' AND status='verified') THEN
      SET v_decision='verified';
    ELSE
      SET v_aid=(SELECT a.attempt_id FROM session_export_attempts a WHERE a.session_id=v_sid AND a.export_kind='completed_archive' AND NOT EXISTS(SELECT 1 FROM session_exports e WHERE e.session_id=a.session_id AND e.export_kind=a.export_kind AND e.attempt_no=a.attempt_no) ORDER BY a.attempt_no DESC LIMIT 1);
      IF v_aid IS NOT NULL AND NOT p_resume THEN SET v_decision='pending';
      ELSE
        IF v_aid IS NULL THEN
          SET v_aid=CONCAT('archive-',REPLACE(UUID(),'-',''));
          INSERT INTO session_export_attempts(attempt_id,session_id,export_kind,requested_at) VALUES(v_aid,v_sid,'completed_archive',UTC_TIMESTAMP(3));
          SET v_no=(SELECT attempt_no FROM session_export_attempts WHERE attempt_id=v_aid);
        END IF;
        SET v_decision='started';
      END IF;
    END IF;
  END IF;
  COMMIT;
  SELECT 'archive_decision' AS _set,v_decision AS decision,v_sid AS session_id;
  SELECT 'export_attempt' AS _set,a.* FROM session_export_attempts a WHERE a.attempt_id=v_aid AND v_decision='started';
END//
DELIMITER ;

DROP PROCEDURE IF EXISTS ga_start_session_tx;
DELIMITER //
CREATE PROCEDURE ga_start_session_tx()
MODIFIES SQL DATA
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;
  IF @ga_history_end IS NOT NULL AND (@ga_is_demo<>0 OR @ga_history_end<=@ga_pitched_at OR @ga_history_end>UTC_TIMESTAMP(3)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Ugyldig historisk fra–til';
  END IF;
  INSERT INTO sessions(
   session_id,batch_name,is_demo,created_at,pitched_at,
   og,volume_l,yeast_profile_id,pitch_mode_id,pitch_temperature_c,oxygenation_note
  )
  SELECT
   @ga_session_id,@ga_batch_name,@ga_is_demo,@ga_created_at,@ga_pitched_at,
   @ga_og,@ga_volume_l,td.yeast_profile_id,@ga_pitch_mode,@ga_pitch_temperature_c,@ga_oxygenation_note
  FROM template_versions tv
  JOIN template_defaults td ON td.version_id=tv.version_id
  WHERE tv.version_id=@ga_template_version AND tv.status='published';
  INSERT INTO session_history_windows(session_id,ended_at,operation_id,created_at)
  SELECT @ga_session_id,@ga_history_end,@ga_operation_id,@ga_created_at WHERE @ga_history_end IS NOT NULL;
  INSERT INTO session_dry_pitches(session_id,pitch_mode_id,yeast_amount_g)
  SELECT @ga_session_id,'dry',@ga_yeast_amount_g WHERE @ga_pitch_mode='dry';
  INSERT INTO session_slurry_pitches(session_id,pitch_mode_id,slurry_volume_ml,slurry_source_batch,slurry_generation)
  SELECT @ga_session_id,'slurry',@ga_slurry_volume_ml,@ga_slurry_source_batch,@ga_slurry_generation WHERE @ga_pitch_mode='slurry';
  
  INSERT INTO session_lifecycle_events(
   lifecycle_event_id,session_id,lifecycle,occurred_at,note,operation_id,created_at
  ) VALUES (
   CONCAT('lifecycle-',@ga_session_id,'-active'),@ga_session_id,'active',IF(@ga_history_end IS NULL,@ga_created_at,@ga_pitched_at),NULL,@ga_operation_id,@ga_created_at
  );
  
  INSERT INTO session_timing_revisions(
   timing_revision_id,session_id,timing_field,revision_no,supersedes_revision_id,
   value_at,source,reason,operation_id,created_at
  ) VALUES (
   CONCAT('timing-',@ga_session_id,'-pitch-r1'),@ga_session_id,'pitched_at',1,NULL,
   @ga_pitched_at,'start',NULL,@ga_operation_id,@ga_created_at
  );
  
  INSERT INTO session_fermentation_targets(session_id,expected_attenuation_min_percent,expected_attenuation_max_percent,expected_fg_min,expected_fg_max,source,created_at)
  VALUES (@ga_session_id,@ga_expected_attenuation_min,@ga_expected_attenuation_max,@ga_expected_fg_min,@ga_expected_fg_max,'attenuation_derived',@ga_created_at);
  
  INSERT INTO measurement_input_draft(
   session_id,measurement_method_id,measured_sg,sample_temperature_c,calibration_temperature_c,manual_temperature_c,pressure_bar,
   cooler_setpoint_c,cooler_calibration_offset_c,airlock_activity,acetaldehyde_level,diacetyl_level,wort_like_level,sulfur_so2_level,sulfur_h2s_level,
   clarity_level,settling_yeast_level,settling_minutes,user_conclusion,measurement_note,created_at,updated_at
  ) VALUES (
   @ga_session_id,@ga_measurement_method,@ga_measured_sg,@ga_sample_temperature_c,@ga_calibration_temperature_c,@ga_manual_temperature_c,@ga_pressure_bar,
   @ga_cooler_setpoint_c,@ga_cooler_calibration_offset_c,@ga_airlock_activity,@ga_acetaldehyde_level,@ga_diacetyl_level,@ga_wort_like_level,@ga_sulfur_so2_level,@ga_sulfur_h2s_level,
   @ga_clarity_level,@ga_settling_yeast_level,@ga_settling_minutes,@ga_user_conclusion,@ga_measurement_note,@ga_created_at,@ga_created_at
  );
  
  INSERT INTO session_template_snapshots(
   session_id,template_id,template_version_id,template_version_label,template_store_schema_version,
   snapshot_format_version,snapshot_sha256,source_published_at,created_at
  )
  SELECT
   @ga_session_id,tv.template_id,tv.version_id,tv.version_label,(SELECT schema_version FROM template_database_metadata WHERE metadata_id=1),'1.0',
   SHA2(CONCAT_WS('|','relational-p20r1',tv.version_id,tv.template_id,tv.name,
                 COALESCE(DATE_FORMAT(tv.published_at,'%Y-%m-%d %H:%i:%s.%f'),'')),256),
   tv.published_at,@ga_created_at
  FROM template_versions tv
  WHERE tv.version_id=@ga_template_version AND tv.status='published';
  
  INSERT INTO session_template_defaults(
   session_id,batch_name_default,volume_l_default,og_default,expected_attenuation_min_percent,expected_attenuation_max_percent,expected_fg_min,expected_fg_max,
   pitch_temperature_c_default,pitch_mode_id,yeast_profile_id,yeast_amount_g_default,measurement_method_id,
   sample_temperature_c_default,calibration_temperature_c_default,manual_temperature_c_default,pressure_bar_default,
   cooler_setpoint_c_default,cooler_calibration_offset_c_default,airlock_activity_default,
   acetaldehyde_level_default,diacetyl_level_default,wort_like_level_default,sulfur_so2_level_default,sulfur_h2s_level_default,
   clarity_level_default,settling_yeast_level_default,settling_minutes_default,user_conclusion_default,measurement_note_default,created_at
  )
  SELECT @ga_session_id,td.batch_name_default,td.volume_l_default,td.og_default,td.expected_attenuation_min_percent,td.expected_attenuation_max_percent,td.expected_fg_min,td.expected_fg_max,
         td.pitch_temperature_c_default,td.pitch_mode_id,td.yeast_profile_id,td.yeast_amount_g_default,td.measurement_method_id,
         td.sample_temperature_c_default,td.calibration_temperature_c_default,td.manual_temperature_c_default,td.pressure_bar_default,
         td.cooler_setpoint_c_default,td.cooler_calibration_offset_c_default,td.airlock_activity_default,
         td.acetaldehyde_level_default,td.diacetyl_level_default,td.wort_like_level_default,td.sulfur_so2_level_default,td.sulfur_h2s_level_default,
         td.clarity_level_default,td.settling_yeast_level_default,td.settling_minutes_default,td.user_conclusion_default,td.measurement_note_default,@ga_created_at
  FROM template_defaults td WHERE td.version_id=@ga_template_version;
  
  INSERT INTO session_biology_calculations(session_id,calculation_id,model_id,created_at)
  SELECT @ga_session_id,calculation_id,model_id,@ga_created_at
  FROM template_biology_calculations WHERE version_id=@ga_template_version;
  
  INSERT INTO session_biology_calculation_inputs(session_id,calculation_id,model_id,input_id,source_kind,source_id,created_at)
  SELECT @ga_session_id,calculation_id,model_id,input_id,source_kind,source_id,@ga_created_at
  FROM template_biology_calculation_inputs WHERE version_id=@ga_template_version;
  
  INSERT INTO session_biology_calculation_parameter_values(session_id,calculation_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at)
  SELECT @ga_session_id,calculation_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,@ga_created_at
  FROM template_biology_calculation_parameter_values WHERE version_id=@ga_template_version;
  
  
  INSERT INTO session_biology_calculation_median_first_samples(session_id,calculation_id,model_id,sample_count,created_at)
  SELECT @ga_session_id,calculation_id,model_id,sample_count,@ga_created_at
  FROM template_biology_calculation_median_first_samples WHERE version_id=@ga_template_version;
  
  INSERT INTO session_biology_calculation_linear_regression(session_id,calculation_id,model_id,window_hours,minimum_samples,created_at)
  SELECT @ga_session_id,calculation_id,model_id,window_hours,minimum_samples,@ga_created_at
  FROM template_biology_calculation_linear_regression WHERE version_id=@ga_template_version;
  
  INSERT INTO session_metric_runtime_rules(session_id,metric_id,calculation_model_id,freshness_mode,valid_minimum_value,valid_maximum_value,created_at)
  SELECT @ga_session_id,metric_id,calculation_model_id,freshness_mode,valid_minimum_value,valid_maximum_value,@ga_created_at
  FROM template_metric_runtime_rules WHERE version_id=@ga_template_version;
  
  INSERT INTO session_metric_runtime_inputs(session_id,metric_id,model_id,input_id,source_kind,source_id,created_at)
  SELECT @ga_session_id,metric_id,model_id,input_id,source_kind,source_id,@ga_created_at
  FROM template_metric_runtime_inputs WHERE version_id=@ga_template_version;
  
  INSERT INTO session_metric_runtime_parameter_values(session_id,metric_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at)
  SELECT @ga_session_id,metric_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,@ga_created_at
  FROM template_metric_runtime_parameter_values WHERE version_id=@ga_template_version;
  
  INSERT INTO session_biological_phases(session_id,phase_id,phase_order,name,description,created_at)
  SELECT @ga_session_id,phase_id,phase_order,name,description,@ga_created_at
  FROM template_biological_phases WHERE version_id=@ga_template_version;
  
  INSERT INTO session_biological_criteria(
   session_id,phase_id,criterion_id,criterion_order,enabled,metric_id,model_id,role_id,label,exception_allowed,created_at
  )
  SELECT @ga_session_id,phase_id,criterion_id,criterion_order,enabled,metric_id,model_id,role_id,label,exception_allowed,@ga_created_at
  FROM template_biological_criteria WHERE version_id=@ga_template_version;
  
  -- Normalized biological criterion parameters.
  INSERT INTO session_biological_criterion_parameter_values
  (session_id,phase_id,criterion_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at)
  SELECT @ga_session_id,phase_id,criterion_id,model_id,'minimum_value','real',minimum_value,NULL,NULL,NULL,@ga_created_at
  FROM template_biological_criterion_threshold WHERE version_id=@ga_template_version AND minimum_value IS NOT NULL
  UNION ALL
  SELECT @ga_session_id,phase_id,criterion_id,model_id,'maximum_value','real',maximum_value,NULL,NULL,NULL,@ga_created_at
  FROM template_biological_criterion_threshold WHERE version_id=@ga_template_version AND maximum_value IS NOT NULL
  UNION ALL
  SELECT @ga_session_id,phase_id,criterion_id,model_id,'maximum_age_minutes','integer',NULL,maximum_age_minutes,NULL,NULL,@ga_created_at
  FROM template_biological_criterion_threshold WHERE version_id=@ga_template_version AND maximum_age_minutes IS NOT NULL
  UNION ALL
  SELECT @ga_session_id,phase_id,criterion_id,model_id,'maximum_age_minutes','integer',NULL,maximum_age_minutes,NULL,NULL,@ga_created_at
  FROM template_biological_criterion_observation WHERE version_id=@ga_template_version AND maximum_age_minutes IS NOT NULL
  UNION ALL
  SELECT @ga_session_id,phase_id,criterion_id,model_id,'window_minutes','integer',NULL,window_minutes,NULL,NULL,@ga_created_at
  FROM template_biological_criterion_window_median_range WHERE version_id=@ga_template_version
  UNION ALL
  SELECT @ga_session_id,phase_id,criterion_id,model_id,'minimum_samples','integer',NULL,minimum_samples,NULL,NULL,@ga_created_at
  FROM template_biological_criterion_window_median_range WHERE version_id=@ga_template_version
  UNION ALL
  SELECT @ga_session_id,phase_id,criterion_id,model_id,'maximum_age_minutes','integer',NULL,maximum_age_minutes,NULL,NULL,@ga_created_at
  FROM template_biological_criterion_window_median_range WHERE version_id=@ga_template_version AND maximum_age_minutes IS NOT NULL
  UNION ALL
  SELECT @ga_session_id,phase_id,criterion_id,model_id,'minimum_value','real',minimum_value,NULL,NULL,NULL,@ga_created_at
  FROM template_biological_criterion_window_median_range WHERE version_id=@ga_template_version
  UNION ALL
  SELECT @ga_session_id,phase_id,criterion_id,model_id,'maximum_value','real',maximum_value,NULL,NULL,NULL,@ga_created_at
  FROM template_biological_criterion_window_median_range WHERE version_id=@ga_template_version
  UNION ALL
  SELECT @ga_session_id,phase_id,criterion_id,model_id,'window_hours','real',window_hours,NULL,NULL,NULL,@ga_created_at
  FROM template_biological_criterion_stability_window WHERE version_id=@ga_template_version
  UNION ALL
  SELECT @ga_session_id,phase_id,criterion_id,model_id,'maximum_range_points','real',maximum_range_points,NULL,NULL,NULL,@ga_created_at
  FROM template_biological_criterion_stability_window WHERE version_id=@ga_template_version
  UNION ALL
  SELECT @ga_session_id,phase_id,criterion_id,model_id,'minimum_samples','integer',NULL,minimum_samples,NULL,NULL,@ga_created_at
  FROM template_biological_criterion_stability_window WHERE version_id=@ga_template_version
  UNION ALL
  SELECT @ga_session_id,phase_id,criterion_id,model_id,'minimum_span_hours','real',minimum_span_hours,NULL,NULL,NULL,@ga_created_at
  FROM template_biological_criterion_stability_window WHERE version_id=@ga_template_version
  UNION ALL
  SELECT @ga_session_id,phase_id,criterion_id,model_id,'maximum_age_minutes','integer',NULL,maximum_age_minutes,NULL,NULL,@ga_created_at
  FROM template_biological_criterion_stability_window WHERE version_id=@ga_template_version AND maximum_age_minutes IS NOT NULL
  UNION ALL
  SELECT @ga_session_id,phase_id,criterion_id,model_id,'since_current_process_start','boolean',NULL,NULL,since_current_process_start,NULL,@ga_created_at
  FROM template_biological_criterion_stability_window WHERE version_id=@ga_template_version;
  
  INSERT INTO session_biological_correctable_parameters(session_id,phase_id,criterion_id,model_id,parameter_id,created_at)
  SELECT @ga_session_id,phase_id,criterion_id,model_id,parameter_id,@ga_created_at
  FROM template_biological_correctable_parameters WHERE version_id=@ga_template_version;
  
  INSERT INTO session_process_steps(
   session_id,process_id,slot_no,process_order,name,description,enabled,historical_replay_auto_transition_allowed,
   anchor_type,anchor_biological_phase_id,anchor_offset_hours,created_at
  )
  SELECT @ga_session_id,process_id,process_order,process_order,name,description,enabled,historical_replay_auto_transition_allowed,NULL,NULL,NULL,@ga_created_at
  FROM template_process_steps WHERE version_id=@ga_template_version;
  
  INSERT INTO session_process_targets(session_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at)
  SELECT @ga_session_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,@ga_created_at
  FROM template_process_targets WHERE version_id=@ga_template_version;
  
  INSERT INTO session_process_target_exact(session_id,process_id,target_id,model_id,target_value,created_at)
  SELECT @ga_session_id,process_id,target_id,model_id,target_value,@ga_created_at
  FROM template_process_target_exact WHERE version_id=@ga_template_version;
  
  INSERT INTO session_process_target_range(session_id,process_id,target_id,model_id,minimum_value,maximum_value,created_at)
  SELECT @ga_session_id,process_id,target_id,model_id,minimum_value,maximum_value,@ga_created_at
  FROM template_process_target_range WHERE version_id=@ga_template_version;
  
  INSERT INTO session_process_actions(session_id,process_id,action_id,action_order,action_type_id,label,created_at)
  SELECT @ga_session_id,process_id,action_id,action_order,action_type_id,label,@ga_created_at
  FROM template_process_actions WHERE version_id=@ga_template_version;
  
  INSERT INTO session_process_action_set_target(session_id,process_id,action_id,action_type_id,target_id,created_at)
  SELECT @ga_session_id,process_id,action_id,action_type_id,target_id,@ga_created_at
  FROM template_process_action_set_target WHERE version_id=@ga_template_version;
  
  INSERT INTO session_process_action_operator(session_id,process_id,action_id,action_type_id,operator_operation_id,created_at)
  SELECT @ga_session_id,process_id,action_id,action_type_id,operation_id,@ga_created_at
  FROM template_process_action_operator WHERE version_id=@ga_template_version;
  
  INSERT INTO session_process_criteria(
   session_id,process_id,criterion_id,criterion_order,enabled,metric_id,model_id,role_id,label,exception_allowed,created_at
  )
  SELECT @ga_session_id,process_id,criterion_id,criterion_order,enabled,metric_id,model_id,role_id,label,exception_allowed,@ga_created_at
  FROM template_process_criteria WHERE version_id=@ga_template_version;
  
  -- Normalized process criterion parameters.
  INSERT INTO session_process_criterion_parameter_values
  (session_id,process_id,criterion_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at)
  SELECT @ga_session_id,process_id,criterion_id,model_id,'minimum_value','real',minimum_value,NULL,NULL,NULL,@ga_created_at
  FROM template_process_criterion_threshold WHERE version_id=@ga_template_version AND minimum_value IS NOT NULL
  UNION ALL
  SELECT @ga_session_id,process_id,criterion_id,model_id,'maximum_value','real',maximum_value,NULL,NULL,NULL,@ga_created_at
  FROM template_process_criterion_threshold WHERE version_id=@ga_template_version AND maximum_value IS NOT NULL
  UNION ALL
  SELECT @ga_session_id,process_id,criterion_id,model_id,'maximum_age_minutes','integer',NULL,maximum_age_minutes,NULL,NULL,@ga_created_at
  FROM template_process_criterion_threshold WHERE version_id=@ga_template_version AND maximum_age_minutes IS NOT NULL
  UNION ALL
  SELECT @ga_session_id,process_id,criterion_id,model_id,'maximum_age_minutes','integer',NULL,maximum_age_minutes,NULL,NULL,@ga_created_at
  FROM template_process_criterion_observation WHERE version_id=@ga_template_version AND maximum_age_minutes IS NOT NULL
  UNION ALL
  SELECT @ga_session_id,process_id,criterion_id,model_id,'window_minutes','integer',NULL,window_minutes,NULL,NULL,@ga_created_at
  FROM template_process_criterion_window_median_range WHERE version_id=@ga_template_version
  UNION ALL
  SELECT @ga_session_id,process_id,criterion_id,model_id,'minimum_samples','integer',NULL,minimum_samples,NULL,NULL,@ga_created_at
  FROM template_process_criterion_window_median_range WHERE version_id=@ga_template_version
  UNION ALL
  SELECT @ga_session_id,process_id,criterion_id,model_id,'maximum_age_minutes','integer',NULL,maximum_age_minutes,NULL,NULL,@ga_created_at
  FROM template_process_criterion_window_median_range WHERE version_id=@ga_template_version AND maximum_age_minutes IS NOT NULL
  UNION ALL
  SELECT @ga_session_id,process_id,criterion_id,model_id,'minimum_value','real',minimum_value,NULL,NULL,NULL,@ga_created_at
  FROM template_process_criterion_window_median_range WHERE version_id=@ga_template_version
  UNION ALL
  SELECT @ga_session_id,process_id,criterion_id,model_id,'maximum_value','real',maximum_value,NULL,NULL,NULL,@ga_created_at
  FROM template_process_criterion_window_median_range WHERE version_id=@ga_template_version
  UNION ALL
  SELECT @ga_session_id,process_id,criterion_id,model_id,'window_hours','real',window_hours,NULL,NULL,NULL,@ga_created_at
  FROM template_process_criterion_stability_window WHERE version_id=@ga_template_version
  UNION ALL
  SELECT @ga_session_id,process_id,criterion_id,model_id,'maximum_range_points','real',maximum_range_points,NULL,NULL,NULL,@ga_created_at
  FROM template_process_criterion_stability_window WHERE version_id=@ga_template_version
  UNION ALL
  SELECT @ga_session_id,process_id,criterion_id,model_id,'minimum_samples','integer',NULL,minimum_samples,NULL,NULL,@ga_created_at
  FROM template_process_criterion_stability_window WHERE version_id=@ga_template_version
  UNION ALL
  SELECT @ga_session_id,process_id,criterion_id,model_id,'minimum_span_hours','real',minimum_span_hours,NULL,NULL,NULL,@ga_created_at
  FROM template_process_criterion_stability_window WHERE version_id=@ga_template_version
  UNION ALL
  SELECT @ga_session_id,process_id,criterion_id,model_id,'maximum_age_minutes','integer',NULL,maximum_age_minutes,NULL,NULL,@ga_created_at
  FROM template_process_criterion_stability_window WHERE version_id=@ga_template_version AND maximum_age_minutes IS NOT NULL
  UNION ALL
  SELECT @ga_session_id,process_id,criterion_id,model_id,'since_current_process_start','boolean',NULL,NULL,since_current_process_start,NULL,@ga_created_at
  FROM template_process_criterion_stability_window WHERE version_id=@ga_template_version;
  
  INSERT INTO session_process_correctable_parameters(session_id,process_id,criterion_id,model_id,parameter_id,created_at)
  SELECT @ga_session_id,process_id,criterion_id,model_id,parameter_id,@ga_created_at
  FROM template_process_correctable_parameters WHERE version_id=@ga_template_version;
  
  INSERT INTO session_demo_sources(session_id,profile_id,interval_seconds,created_at) SELECT @ga_session_id,demo_reference_profile_id,(SELECT interval_seconds FROM demo_reference_profiles WHERE profile_id=demo_reference_profile_id),@ga_created_at FROM session_setup_draft WHERE @ga_is_demo=1 AND draft_key='current' AND demo_reference_profile_id IS NOT NULL;
  INSERT INTO session_measurement_sources(session_id,source_profile_id,source_started_at,last_import_cutoff_at,last_success_at,last_error,created_at,updated_at) SELECT @ga_session_id,@ga_source_profile,@ga_pitched_at,@ga_pitched_at,NULL,NULL,@ga_created_at,@ga_created_at WHERE @ga_is_demo=0;
  IF EXISTS(SELECT 1 FROM session_measurement_sources WHERE session_id=@ga_session_id) THEN CALL ga_freeze_source_configuration(@ga_session_id,@ga_source_profile,@ga_pitched_at); END IF;
  
  
  INSERT INTO session_analysis_graphs(session_id,graph_id,sort_order,label,description,unit,display_decimals,y_axis_min,y_axis_max,y_axis_tick_step,y_axis_include_zero,x_axis_mode,enabled,show_biological_bands,show_process_markers,show_criterion_markers,gap_policy,created_at)
  SELECT @ga_session_id,graph_id,sort_order,label,description,unit,display_decimals,y_axis_min,y_axis_max,y_axis_tick_step,y_axis_include_zero,x_axis_mode,enabled,show_biological_bands,show_process_markers,show_criterion_markers,gap_policy,@ga_created_at
  FROM template_analysis_graphs WHERE version_id=@ga_template_version;
  INSERT INTO session_analysis_graph_series(session_id,graph_id,series_id,sort_order,label,source_kind,metric_id,owner_id,criterion_id,minimum_samples,minimum_coverage_fraction,warmup_minutes,valid_minimum_value,valid_maximum_value,provisional_allowed,provisional_minimum_samples,provisional_minimum_span_minutes,render_mode,band_model,band_description,standard_color,provisional_color,standard_dasharray,provisional_dasharray,band_opacity,created_at)
  SELECT @ga_session_id,graph_id,series_id,sort_order,label,source_kind,metric_id,owner_id,criterion_id,minimum_samples,minimum_coverage_fraction,warmup_minutes,valid_minimum_value,valid_maximum_value,provisional_allowed,provisional_minimum_samples,provisional_minimum_span_minutes,render_mode,band_model,band_description,standard_color,provisional_color,standard_dasharray,provisional_dasharray,band_opacity,@ga_created_at
  FROM template_analysis_graph_series WHERE version_id=@ga_template_version;
  
  INSERT INTO session_measurement_validation_rules(session_id,rule_id,signal_id,rule_order,model_id,enabled,created_at)
  SELECT @ga_session_id,rule_id,signal_id,rule_order,model_id,enabled,@ga_created_at
  FROM measurement_source_validation_rules WHERE source_profile_id=@ga_source_profile AND @ga_is_demo=0;
  INSERT INTO session_measurement_validation_rule_parameter_values(session_id,rule_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at)
  SELECT @ga_session_id,p.rule_id,p.parameter_id,p.data_type,p.real_value,p.integer_value,p.boolean_value,p.text_value,@ga_created_at
  FROM measurement_source_validation_rule_parameter_values p
  WHERE p.source_profile_id=@ga_source_profile AND @ga_is_demo=0;
  
  SET @ga_first_process=(SELECT process_id FROM session_process_steps WHERE session_id=@ga_session_id AND enabled=1 ORDER BY process_order LIMIT 1);
  SET @ga_first_phase=(SELECT phase_id FROM session_biological_phases WHERE session_id=@ga_session_id ORDER BY phase_order LIMIT 1);
  SET @ga_process_visit=CONCAT('process-visit-',@ga_session_id,'-1');
  SET @ga_bio_visit=CONCAT('biological-visit-',@ga_session_id,'-1');
  
  INSERT INTO process_visits(visit_id,session_id,process_id,created_at)
  VALUES (@ga_process_visit,@ga_session_id,@ga_first_process,@ga_created_at);
  INSERT INTO process_visit_revisions(
   visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,
   timing_source,revision_reason,operation_id,created_at
  ) VALUES (
   CONCAT(@ga_process_visit,'-r1'),@ga_process_visit,1,NULL,@ga_pitched_at,NULL,
   'start',NULL,@ga_operation_id,@ga_created_at
  );
  
  INSERT INTO biological_visits(visit_id,session_id,phase_id,created_at)
  VALUES (@ga_bio_visit,@ga_session_id,@ga_first_phase,@ga_created_at);
  INSERT INTO biological_visit_revisions(
   visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,
   timing_source,confidence,evaluation_id,revision_reason,operation_id,created_at
  ) VALUES (
   CONCAT(@ga_bio_visit,'-r1'),@ga_bio_visit,1,NULL,@ga_pitched_at,NULL,
   'pitch','pitch',NULL,NULL,@ga_operation_id,@ga_created_at
  );
  
  
  SET @ga_observation_id=CONCAT('observation-',@ga_session_id,'-start');
  INSERT INTO observation_rounds(observation_id,session_id,created_at)
  VALUES (@ga_observation_id,@ga_session_id,@ga_created_at);
  INSERT INTO observation_round_revisions(
   observation_revision_id,observation_id,session_id,revision_no,supersedes_revision_id,status,
   recorded_at,measurement_method_id,measured_sg,sample_temperature_c,calibration_temperature_c,corrected_sg,
   manual_temperature_c,pressure_bar,cooler_setpoint_c,cooler_calibration_offset_c,estimated_abv_percent,
   estimated_finished_abv_percent,airlock_activity,acetaldehyde_level,diacetyl_level,wort_like_level,sulfur_so2_level,
   sulfur_h2s_level,clarity_level,settling_yeast_level,settling_minutes,user_conclusion,calculated_conclusion,
   process_gate_status,corrected_sg_model_id,abv_now_model_id,estimated_finished_abv_model_id,actual_og_used,note,
   revision_reason,operation_id,created_at
  ) VALUES (
   CONCAT(@ga_observation_id,'-r1'),@ga_observation_id,@ga_session_id,1,NULL,'active',@ga_pitched_at,
   @ga_measurement_method,@ga_measured_sg,@ga_sample_temperature_c,@ga_calibration_temperature_c,@ga_corrected_sg,
   @ga_manual_temperature_c,@ga_pressure_bar,@ga_cooler_setpoint_c,@ga_cooler_calibration_offset_c,@ga_abv_now,
   @ga_finished_abv,@ga_airlock_activity,@ga_acetaldehyde_level,@ga_diacetyl_level,@ga_wort_like_level,@ga_sulfur_so2_level,
   @ga_sulfur_h2s_level,@ga_clarity_level,@ga_settling_yeast_level,@ga_settling_minutes,@ga_user_conclusion,NULL,
   'not_evaluated',@ga_corrected_sg_model,'cutaia-apparent-abv-v1',@ga_finished_abv_model,@ga_og,@ga_measurement_note,
   'initial',@ga_operation_id,@ga_created_at
  );
  
  INSERT INTO session_overview_graph_policy(session_id,graph_id,band_model,band_description,band_opacity,created_at)
  SELECT @ga_session_id,graph_id,band_model,band_description,band_opacity,@ga_created_at
  FROM template_overview_graph_policy WHERE version_id=@ga_template_version;

  COMMIT;

END//
DELIMITER ;


DROP PROCEDURE IF EXISTS ga_correct_biological_phase_tx;

-- p24r1: atomic normalised template cloning. Explicit columns prevent schema drift;
-- FK/UNIQUE constraints arbitrate concurrent drafts, and every SQL error rolls back.
DROP PROCEDURE IF EXISTS ga_clone_template_tx;
DELIMITER //
CREATE PROCEDURE ga_clone_template_tx(IN p_source VARCHAR(128),IN p_draft VARCHAR(128),IN p_new_template VARCHAR(128),IN p_new_name VARCHAR(255))
MODIFIES SQL DATA
main: BEGIN
  DECLARE v_source_template VARCHAR(128);
  DECLARE v_target_template VARCHAR(128);
  DECLARE v_existing_draft VARCHAR(128);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  SELECT template_id INTO v_source_template FROM template_versions WHERE version_id=p_source AND status IN ('published','retired');
  IF v_source_template IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Kloning krever published eller retired kilde'; END IF;
  IF p_new_template='' AND EXISTS(SELECT 1 FROM template_origins WHERE template_id=v_source_template AND origin_kind='imported') THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Importert original krever ny template-ID ved kopiering'; END IF;
  SET v_target_template=IF(p_new_template='',v_source_template,p_new_template);
  SELECT version_id INTO v_existing_draft FROM template_versions WHERE template_id=v_target_template AND status='draft' LIMIT 1;
  IF p_new_template<>'' AND EXISTS(SELECT 1 FROM templates WHERE template_id=p_new_template) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Ny template-ID finnes allerede'; END IF;
  IF v_existing_draft IS NULL THEN
    IF p_new_template<>'' THEN INSERT INTO templates(template_id,created_at) VALUES(p_new_template,UTC_TIMESTAMP(3)); END IF;
    INSERT INTO template_versions(version_id,template_id,status,version_label,based_on_version_id,name,revision_note,created_at,published_at,retired_at)
    SELECT p_draft,v_target_template,'draft',NULL,version_id,IF(p_new_name='',name,p_new_name),NULL,UTC_TIMESTAMP(3),NULL,NULL FROM template_versions WHERE version_id=p_source;
  INSERT INTO template_defaults(version_id,batch_name_default,volume_l_default,og_default,expected_attenuation_min_percent,expected_attenuation_max_percent,pitch_temperature_c_default,pitch_mode_id,yeast_profile_id,yeast_amount_g_default,measurement_method_id,sample_temperature_c_default,calibration_temperature_c_default,manual_temperature_c_default,pressure_bar_default,cooler_setpoint_c_default,cooler_calibration_offset_c_default,airlock_activity_default,acetaldehyde_level_default,diacetyl_level_default,wort_like_level_default,sulfur_so2_level_default,sulfur_h2s_level_default,clarity_level_default,settling_yeast_level_default,settling_minutes_default,user_conclusion_default,measurement_note_default,created_at) SELECT p_draft,batch_name_default,volume_l_default,og_default,expected_attenuation_min_percent,expected_attenuation_max_percent,pitch_temperature_c_default,pitch_mode_id,yeast_profile_id,yeast_amount_g_default,measurement_method_id,sample_temperature_c_default,calibration_temperature_c_default,manual_temperature_c_default,pressure_bar_default,cooler_setpoint_c_default,cooler_calibration_offset_c_default,airlock_activity_default,acetaldehyde_level_default,diacetyl_level_default,wort_like_level_default,sulfur_so2_level_default,sulfur_h2s_level_default,clarity_level_default,settling_yeast_level_default,settling_minutes_default,user_conclusion_default,measurement_note_default,UTC_TIMESTAMP(3) FROM template_defaults WHERE version_id=p_source;
  INSERT INTO template_metric_runtime_rules(version_id,metric_id,calculation_model_id,freshness_mode,valid_minimum_value,valid_maximum_value,created_at) SELECT p_draft,metric_id,calculation_model_id,freshness_mode,valid_minimum_value,valid_maximum_value,UTC_TIMESTAMP(3) FROM template_metric_runtime_rules WHERE version_id=p_source;
  INSERT INTO template_metric_runtime_inputs(version_id,metric_id,model_id,input_id,source_kind,source_id,created_at) SELECT p_draft,metric_id,model_id,input_id,source_kind,source_id,UTC_TIMESTAMP(3) FROM template_metric_runtime_inputs WHERE version_id=p_source;
  INSERT INTO template_metric_runtime_parameter_values(version_id,metric_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) SELECT p_draft,metric_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,UTC_TIMESTAMP(3) FROM template_metric_runtime_parameter_values WHERE version_id=p_source;
  INSERT INTO template_biology_calculations(version_id,calculation_id,model_id,created_at) SELECT p_draft,calculation_id,model_id,UTC_TIMESTAMP(3) FROM template_biology_calculations WHERE version_id=p_source;
  INSERT INTO template_biology_calculation_inputs(version_id,calculation_id,model_id,input_id,source_kind,source_id,created_at) SELECT p_draft,calculation_id,model_id,input_id,source_kind,source_id,UTC_TIMESTAMP(3) FROM template_biology_calculation_inputs WHERE version_id=p_source;
  INSERT INTO template_biology_calculation_parameter_values(version_id,calculation_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) SELECT p_draft,calculation_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,UTC_TIMESTAMP(3) FROM template_biology_calculation_parameter_values WHERE version_id=p_source;
  INSERT INTO template_biology_calculation_median_first_samples(version_id,calculation_id,model_id,sample_count,created_at) SELECT p_draft,calculation_id,model_id,sample_count,UTC_TIMESTAMP(3) FROM template_biology_calculation_median_first_samples WHERE version_id=p_source;
  INSERT INTO template_biology_calculation_linear_regression(version_id,calculation_id,model_id,window_hours,minimum_samples,created_at) SELECT p_draft,calculation_id,model_id,window_hours,minimum_samples,UTC_TIMESTAMP(3) FROM template_biology_calculation_linear_regression WHERE version_id=p_source;
  INSERT INTO template_biological_phases(version_id,phase_id,phase_order,name,description,created_at) SELECT p_draft,phase_id,phase_order,name,description,UTC_TIMESTAMP(3) FROM template_biological_phases WHERE version_id=p_source;
  INSERT INTO template_biological_criteria(version_id,phase_id,criterion_id,criterion_order,enabled,metric_id,model_id,role_id,label,exception_allowed,created_at) SELECT p_draft,phase_id,criterion_id,criterion_order,enabled,metric_id,model_id,role_id,label,exception_allowed,UTC_TIMESTAMP(3) FROM template_biological_criteria WHERE version_id=p_source;
  INSERT INTO template_biological_criterion_threshold(version_id,phase_id,criterion_id,model_id,minimum_value,maximum_value,maximum_age_minutes,created_at) SELECT p_draft,phase_id,criterion_id,model_id,minimum_value,maximum_value,maximum_age_minutes,UTC_TIMESTAMP(3) FROM template_biological_criterion_threshold WHERE version_id=p_source;
  INSERT INTO template_biological_criterion_observation(version_id,phase_id,criterion_id,model_id,maximum_age_minutes,created_at) SELECT p_draft,phase_id,criterion_id,model_id,maximum_age_minutes,UTC_TIMESTAMP(3) FROM template_biological_criterion_observation WHERE version_id=p_source;
  INSERT INTO template_biological_criterion_window_median_range(version_id,phase_id,criterion_id,model_id,window_minutes,minimum_samples,maximum_age_minutes,minimum_value,maximum_value,created_at) SELECT p_draft,phase_id,criterion_id,model_id,window_minutes,minimum_samples,maximum_age_minutes,minimum_value,maximum_value,UTC_TIMESTAMP(3) FROM template_biological_criterion_window_median_range WHERE version_id=p_source;
  INSERT INTO template_biological_criterion_stability_window(version_id,phase_id,criterion_id,model_id,window_hours,maximum_range_points,minimum_samples,minimum_span_hours,maximum_age_minutes,since_current_process_start,created_at) SELECT p_draft,phase_id,criterion_id,model_id,window_hours,maximum_range_points,minimum_samples,minimum_span_hours,maximum_age_minutes,since_current_process_start,UTC_TIMESTAMP(3) FROM template_biological_criterion_stability_window WHERE version_id=p_source;
  INSERT INTO template_biological_correctable_parameters(version_id,phase_id,criterion_id,model_id,parameter_id,created_at) SELECT p_draft,phase_id,criterion_id,model_id,parameter_id,UTC_TIMESTAMP(3) FROM template_biological_correctable_parameters WHERE version_id=p_source;
  INSERT INTO template_process_steps(version_id,process_id,process_order,enabled,historical_replay_auto_transition_allowed,name,description,created_at) SELECT p_draft,process_id,process_order,enabled,historical_replay_auto_transition_allowed,name,description,UTC_TIMESTAMP(3) FROM template_process_steps WHERE version_id=p_source;
  INSERT INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) SELECT p_draft,process_id,target_id,target_order,metric_id,model_id,label,purpose,UTC_TIMESTAMP(3) FROM template_process_targets WHERE version_id=p_source;
  INSERT INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) SELECT p_draft,process_id,target_id,model_id,target_value,UTC_TIMESTAMP(3) FROM template_process_target_exact WHERE version_id=p_source;
  INSERT INTO template_process_target_range(version_id,process_id,target_id,model_id,minimum_value,maximum_value,created_at) SELECT p_draft,process_id,target_id,model_id,minimum_value,maximum_value,UTC_TIMESTAMP(3) FROM template_process_target_range WHERE version_id=p_source;
  INSERT INTO template_process_actions(version_id,process_id,action_id,action_order,action_type_id,label,created_at) SELECT p_draft,process_id,action_id,action_order,action_type_id,label,UTC_TIMESTAMP(3) FROM template_process_actions WHERE version_id=p_source;
  INSERT INTO template_process_action_set_target(version_id,process_id,action_id,action_type_id,target_id,created_at) SELECT p_draft,process_id,action_id,action_type_id,target_id,UTC_TIMESTAMP(3) FROM template_process_action_set_target WHERE version_id=p_source;
  INSERT INTO template_process_action_operator(version_id,process_id,action_id,action_type_id,operation_id,created_at) SELECT p_draft,process_id,action_id,action_type_id,operation_id,UTC_TIMESTAMP(3) FROM template_process_action_operator WHERE version_id=p_source;
  INSERT INTO template_process_criteria(version_id,process_id,criterion_id,criterion_order,enabled,metric_id,model_id,role_id,label,exception_allowed,created_at) SELECT p_draft,process_id,criterion_id,criterion_order,enabled,metric_id,model_id,role_id,label,exception_allowed,UTC_TIMESTAMP(3) FROM template_process_criteria WHERE version_id=p_source;
  INSERT INTO template_process_criterion_threshold(version_id,process_id,criterion_id,model_id,minimum_value,maximum_value,maximum_age_minutes,created_at) SELECT p_draft,process_id,criterion_id,model_id,minimum_value,maximum_value,maximum_age_minutes,UTC_TIMESTAMP(3) FROM template_process_criterion_threshold WHERE version_id=p_source;
  INSERT INTO template_process_criterion_observation(version_id,process_id,criterion_id,model_id,maximum_age_minutes,created_at) SELECT p_draft,process_id,criterion_id,model_id,maximum_age_minutes,UTC_TIMESTAMP(3) FROM template_process_criterion_observation WHERE version_id=p_source;
  INSERT INTO template_process_criterion_window_median_range(version_id,process_id,criterion_id,model_id,window_minutes,minimum_samples,maximum_age_minutes,minimum_value,maximum_value,created_at) SELECT p_draft,process_id,criterion_id,model_id,window_minutes,minimum_samples,maximum_age_minutes,minimum_value,maximum_value,UTC_TIMESTAMP(3) FROM template_process_criterion_window_median_range WHERE version_id=p_source;
  INSERT INTO template_process_criterion_stability_window(version_id,process_id,criterion_id,model_id,window_hours,maximum_range_points,minimum_samples,minimum_span_hours,maximum_age_minutes,since_current_process_start,created_at) SELECT p_draft,process_id,criterion_id,model_id,window_hours,maximum_range_points,minimum_samples,minimum_span_hours,maximum_age_minutes,since_current_process_start,UTC_TIMESTAMP(3) FROM template_process_criterion_stability_window WHERE version_id=p_source;
  INSERT INTO template_process_correctable_parameters(version_id,process_id,criterion_id,model_id,parameter_id,created_at) SELECT p_draft,process_id,criterion_id,model_id,parameter_id,UTC_TIMESTAMP(3) FROM template_process_correctable_parameters WHERE version_id=p_source;
  INSERT INTO template_analysis_graphs(version_id,graph_id,sort_order,label,description,unit,display_decimals,y_axis_min,y_axis_max,y_axis_tick_step,y_axis_include_zero,x_axis_mode,enabled,show_biological_bands,show_process_markers,show_criterion_markers,gap_policy,created_at) SELECT p_draft,graph_id,sort_order,label,description,unit,display_decimals,y_axis_min,y_axis_max,y_axis_tick_step,y_axis_include_zero,x_axis_mode,enabled,show_biological_bands,show_process_markers,show_criterion_markers,gap_policy,UTC_TIMESTAMP(3) FROM template_analysis_graphs WHERE version_id=p_source;
  INSERT INTO template_analysis_graph_series(version_id,graph_id,series_id,sort_order,label,source_kind,metric_id,owner_id,criterion_id,minimum_samples,minimum_coverage_fraction,warmup_minutes,valid_minimum_value,valid_maximum_value,provisional_allowed,provisional_minimum_samples,provisional_minimum_span_minutes,render_mode,band_model,band_description,standard_color,provisional_color,standard_dasharray,provisional_dasharray,band_opacity,created_at) SELECT p_draft,graph_id,series_id,sort_order,label,source_kind,metric_id,owner_id,criterion_id,minimum_samples,minimum_coverage_fraction,warmup_minutes,valid_minimum_value,valid_maximum_value,provisional_allowed,provisional_minimum_samples,provisional_minimum_span_minutes,render_mode,band_model,band_description,standard_color,provisional_color,standard_dasharray,provisional_dasharray,band_opacity,UTC_TIMESTAMP(3) FROM template_analysis_graph_series WHERE version_id=p_source;
  INSERT INTO template_overview_graph_policy(version_id,graph_id,band_model,band_description,band_opacity,created_at) SELECT p_draft,graph_id,band_model,band_description,band_opacity,UTC_TIMESTAMP(3) FROM template_overview_graph_policy WHERE version_id=p_source;
    SET v_existing_draft=p_draft;
  END IF;
  INSERT INTO template_editor_state(state_key,selected_version_id,updated_at) VALUES('current',v_existing_draft,UTC_TIMESTAMP(3))
  ON DUPLICATE KEY UPDATE selected_version_id=VALUES(selected_version_id),updated_at=VALUES(updated_at);
  COMMIT;
  SELECT 1 AS changed,v_existing_draft AS selected_version_id;
END//
DELIMITER ;

DROP PROCEDURE IF EXISTS ga_store_ingest_tx;
DELIMITER //
CREATE PROCEDURE ga_store_ingest_tx(IN p_sid VARCHAR(128),IN p_end DATETIME(3),IN p_threshold INTEGER,IN p_error TEXT,IN p_job LONGTEXT)
BEGIN
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 IF NOT EXISTS(SELECT 1 FROM v_active_session a JOIN session_measurement_sources m ON m.session_id=a.session_id WHERE a.session_id=p_sid AND p_end>=m.last_import_cutoff_at AND (a.historical_ended_at IS NULL OR p_end<=a.historical_ended_at)) THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Import avvist: inaktiv sesjon eller utenfor DB-tidsrom';
 END IF;
 IF EXISTS(SELECT 1 FROM JSON_TABLE(p_job,'$.rows[*]' COLUMNS(bt DATETIME(3) PATH '$.bt')) j JOIN v_active_session a ON a.session_id=p_sid WHERE j.bt<a.pitched_at OR j.bt>=p_end)
 OR EXISTS(SELECT 1 FROM JSON_TABLE(p_job,'$.hourly[*]' COLUMNS(a DATETIME(3) PATH '$.start',z DATETIME(3) PATH '$.end')) j JOIN v_active_session a ON a.session_id=p_sid WHERE j.a<a.pitched_at OR j.z>p_end) THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Importdata utenfor DB-tidsrom';
 END IF;
 INSERT IGNORE INTO measurements_5m(session_id,bucket_at,sample_count,sg_min,sg_mean,sg_median,sg_max,temperature_min_c,temperature_mean_c,temperature_max_c,pressure_min_bar,pressure_mean_bar,pressure_max_bar,rssi_min_dbm,rssi_mean_dbm,rssi_max_dbm,created_at,updated_at) SELECT p_sid,j.bucket_at,j.sample_count,j.sg_min,j.sg_mean,j.sg_median,j.sg_max,j.temperature_min_c,j.temperature_mean_c,j.temperature_max_c,j.pressure_min_bar,j.pressure_mean_bar,j.pressure_max_bar,j.rssi_min_dbm,j.rssi_mean_dbm,j.rssi_max_dbm,UTC_TIMESTAMP(3),UTC_TIMESTAMP(3) FROM JSON_TABLE(p_job,'$.rows[*]' COLUMNS(bucket_at DATETIME(3) PATH '$.bt' NULL ON EMPTY,sample_count INT PATH '$.count' NULL ON EMPTY,sg_min DECIMAL(7,5) PATH '$.sgmin' NULL ON EMPTY,sg_mean DECIMAL(7,5) PATH '$.sgmean' NULL ON EMPTY,sg_median DECIMAL(7,5) PATH '$.sgmedian' NULL ON EMPTY,sg_max DECIMAL(7,5) PATH '$.sgmax' NULL ON EMPTY,temperature_min_c DECIMAL(8,3) PATH '$.tempmin' NULL ON EMPTY,temperature_mean_c DECIMAL(8,3) PATH '$.temp' NULL ON EMPTY,temperature_max_c DECIMAL(8,3) PATH '$.tempmax' NULL ON EMPTY,pressure_min_bar DECIMAL(8,4) PATH '$.pressuremin' NULL ON EMPTY,pressure_mean_bar DECIMAL(8,4) PATH '$.pressure' NULL ON EMPTY,pressure_max_bar DECIMAL(8,4) PATH '$.pressuremax' NULL ON EMPTY,rssi_min_dbm DECIMAL(8,3) PATH '$.rssimin' NULL ON EMPTY,rssi_mean_dbm DECIMAL(8,3) PATH '$.rssi' NULL ON EMPTY,rssi_max_dbm DECIMAL(8,3) PATH '$.rssimax' NULL ON EMPTY)) j;
 INSERT IGNORE INTO measurement_statistics_hourly(statistic_import_id,session_id,start_at,end_at,sg_min,sg_mean,sg_max,temperature_min_c,temperature_mean_c,temperature_max_c,rssi_min_dbm,rssi_mean_dbm,rssi_max_dbm,created_at) SELECT SHA2(CONCAT(p_sid,'|',CONCAT_WS('|',COALESCE(CAST(j.start_at AS CHAR),'NULL'),COALESCE(CAST(j.end_at AS CHAR),'NULL'),COALESCE(CAST(j.sg_min AS CHAR),'NULL'),COALESCE(CAST(j.sg_mean AS CHAR),'NULL'),COALESCE(CAST(j.sg_max AS CHAR),'NULL'),COALESCE(CAST(j.temperature_min_c AS CHAR),'NULL'),COALESCE(CAST(j.temperature_mean_c AS CHAR),'NULL'),COALESCE(CAST(j.temperature_max_c AS CHAR),'NULL'),COALESCE(CAST(j.rssi_min_dbm AS CHAR),'NULL'),COALESCE(CAST(j.rssi_mean_dbm AS CHAR),'NULL'),COALESCE(CAST(j.rssi_max_dbm AS CHAR),'NULL'))),256),p_sid,j.start_at,j.end_at,j.sg_min,j.sg_mean,j.sg_max,j.temperature_min_c,j.temperature_mean_c,j.temperature_max_c,j.rssi_min_dbm,j.rssi_mean_dbm,j.rssi_max_dbm,UTC_TIMESTAMP(3) FROM JSON_TABLE(p_job,'$.hourly[*]' COLUMNS(start_at DATETIME(3) PATH '$.start' NULL ON EMPTY,end_at DATETIME(3) PATH '$.end' NULL ON EMPTY,sg_min DOUBLE PATH '$.sg_min' NULL ON EMPTY,sg_mean DOUBLE PATH '$.sg_mean' NULL ON EMPTY,sg_max DOUBLE PATH '$.sg_max' NULL ON EMPTY,temperature_min_c DOUBLE PATH '$.temperature_min' NULL ON EMPTY,temperature_mean_c DOUBLE PATH '$.temperature_mean' NULL ON EMPTY,temperature_max_c DOUBLE PATH '$.temperature_max' NULL ON EMPTY,rssi_min_dbm DOUBLE PATH '$.rssi_min' NULL ON EMPTY,rssi_mean_dbm DOUBLE PATH '$.rssi_mean' NULL ON EMPTY,rssi_max_dbm DOUBLE PATH '$.rssi_max' NULL ON EMPTY)) j;
 INSERT IGNORE INTO measurement_ingest_quality_events(session_id,bucket_at,signal_id,received_count,accepted_count,rejected_count,status,reason_code,created_at)
 SELECT p_sid,j.bt,j.signal_id,j.received,j.accepted,GREATEST(0,j.received-j.accepted),j.status,j.reason,UTC_TIMESTAMP(3) FROM JSON_TABLE(p_job,'$.quality[*]' COLUMNS(bt DATETIME(3) PATH '$.bt',signal_id VARCHAR(128) PATH '$.signal',received INT PATH '$.received',accepted INT PATH '$.accepted',status VARCHAR(32) PATH '$.status',reason VARCHAR(64) PATH '$.reason' NULL ON EMPTY)) j;
 INSERT IGNORE INTO measurement_data_gaps(gap_id,session_id,source,gap_started_at,gap_ended_at,duration_seconds,threshold_seconds,detected_at,created_at)
 SELECT j.id,p_sid,'home_assistant_heartbeat',j.start_at,NULL,NULL,p_threshold,UTC_TIMESTAMP(3),UTC_TIMESTAMP(3) FROM JSON_TABLE(p_job,'$.gap_inserts[*]' COLUMNS(id VARCHAR(128) PATH '$.id',start_at DATETIME(3) PATH '$.start')) j;
 INSERT IGNORE INTO measurement_gap_closures(gap_id,gap_ended_at,duration_seconds,created_at)
 SELECT j.id,j.end_at,j.duration,UTC_TIMESTAMP(3) FROM JSON_TABLE(p_job,'$.gap_closes[*]' COLUMNS(id VARCHAR(128) PATH '$.id',end_at DATETIME(3) PATH '$.end',duration INT PATH '$.duration')) j;
 UPDATE session_measurement_sources SET last_import_cutoff_at=p_end,last_success_at=UTC_TIMESTAMP(3),last_error=p_error,updated_at=UTC_TIMESTAMP(3) WHERE session_id=p_sid;
 COMMIT;
 SELECT 'active' AS _set,s.*,sts.template_version_id,tv.template_id,tv.name AS template_name,tv.version_label FROM v_active_session_summary s JOIN session_template_snapshots sts ON sts.session_id=s.session_id LEFT JOIN template_versions tv ON tv.version_id=sts.template_version_id WHERE s.session_id=p_sid;
 SELECT 'ingest' AS _set,sm.*,JSON_LENGTH(p_job,'$.rows') AS inserted_buckets,COALESCE(JSON_VALUE(p_job,'$.partial_count'),0) AS partial_buckets FROM session_measurement_sources sm WHERE sm.session_id=p_sid;
 SELECT 'latest_5m' AS _set,m.* FROM measurements_5m m WHERE m.session_id=p_sid ORDER BY m.bucket_at DESC LIMIT 1;
END//
DELIMITER ;

DROP PROCEDURE IF EXISTS ga_seed_demo_tx;
DELIMITER //
CREATE PROCEDURE ga_seed_demo_tx(IN p_sid VARCHAR(128))
BEGIN
 DECLARE v_profile VARCHAR(128);
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 SET v_profile=(SELECT profile_id FROM session_demo_sources WHERE session_id=p_sid);
 IF v_profile IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Demo mangler fryst referanseprofil'; END IF;
 START TRANSACTION;
 SET @s=p_sid;SET @p=(SELECT pitched_at FROM sessions WHERE session_id=@s);
 IF v_profile='tilt-pro-blue-20260925' THEN
SET @p2off=(SELECT offset_seconds FROM demo_reference_state_markers WHERE profile_id=v_profile AND marker_kind='process_step' AND state_id='P2');
SET @b2off=(SELECT offset_seconds FROM demo_reference_state_markers WHERE profile_id=v_profile AND marker_kind='biological_phase' AND state_id='B2');
SET @b3off=(SELECT offset_seconds FROM demo_reference_state_markers WHERE profile_id=v_profile AND marker_kind='biological_phase' AND state_id='B3');
SET @p1visit=(SELECT pv.visit_id FROM process_visits pv WHERE pv.session_id=@s AND pv.process_id='P1' ORDER BY pv.created_at LIMIT 1);
SET @b1visit=(SELECT bv.visit_id FROM biological_visits bv WHERE bv.session_id=@s AND bv.phase_id='B1' ORDER BY bv.created_at LIMIT 1);

INSERT INTO session_timing_revisions(timing_revision_id,session_id,timing_field,revision_no,supersedes_revision_id,value_at,source,reason,operation_id,created_at)
VALUES(CONCAT('timing-',@s,'-activity-r1'),@s,'activity_started_at',1,NULL,TIMESTAMPADD(SECOND,@b2off,@p),'reference_demo','B2-kriterier oppfylt i referanseserien',NULL,UTC_TIMESTAMP(3));

INSERT INTO process_visit_revisions(visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,timing_source,revision_reason,operation_id,created_at)
SELECT CONCAT(pvr.visit_revision_id,'-demo-close'),pvr.visit_id,pvr.revision_no+1,pvr.visit_revision_id,@p,TIMESTAMPADD(SECOND,@p2off,@p),'reference_demo','P2-kriterier oppfylt i referanseserien',NULL,UTC_TIMESTAMP(3)
FROM v_current_process_visit_revision pvr JOIN process_visits pv ON pv.visit_id=pvr.visit_id WHERE pv.session_id=@s AND pv.process_id='P1';

INSERT IGNORE INTO process_visits(visit_id,session_id,process_id,created_at)
VALUES(CONCAT('demo-p2-',@s),@s,'P2',UTC_TIMESTAMP(3));
INSERT IGNORE INTO process_visit_revisions(visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,timing_source,revision_reason,operation_id,created_at)
VALUES(CONCAT('demo-p2-r1-',@s),CONCAT('demo-p2-',@s),1,NULL,TIMESTAMPADD(SECOND,@p2off,@p),NULL,'reference_demo','P2-kriterier oppfylt i referanseserien',NULL,UTC_TIMESTAMP(3));
INSERT IGNORE INTO process_transitions(transition_id,session_id,transitioned_at,from_visit_id,to_visit_id,from_process_id,to_process_id,action,evaluation_id,recommendation_id,operation_id,recommended_temperature_c,recommended_pressure_bar,operator_temperature_setting_c,operator_pressure_setting_bar,note,created_at)
VALUES(CONCAT('demo-process-transition-p2-',@s),@s,TIMESTAMPADD(SECOND,@p2off,@p),@p1visit,CONCAT('demo-p2-',@s),'P1','P2','reference_demo',NULL,NULL,CONCAT('demo-process-p2-',@s),8.0,0.0,8.0,0.0,'Referansedemo: P2 startet ved første oppfylte P2-inngangsvindu.',UTC_TIMESTAMP(3));

INSERT INTO biological_visit_revisions(visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,timing_source,confidence,evaluation_id,revision_reason,operation_id,created_at)
SELECT CONCAT(bvr.visit_revision_id,'-demo-close'),bvr.visit_id,bvr.revision_no+1,bvr.visit_revision_id,@p,TIMESTAMPADD(SECOND,@b2off,@p),'reference_demo','criteria_met',NULL,'B2-kriterier oppfylt i referanseserien',NULL,UTC_TIMESTAMP(3)
FROM v_current_biological_visit_revision bvr JOIN biological_visits bv ON bv.visit_id=bvr.visit_id WHERE bv.session_id=@s AND bv.phase_id='B1';

INSERT IGNORE INTO biological_visits(visit_id,session_id,phase_id,created_at)
VALUES(CONCAT('demo-b2-',@s),@s,'B2',UTC_TIMESTAMP(3)),(CONCAT('demo-b3-',@s),@s,'B3',UTC_TIMESTAMP(3));
INSERT IGNORE INTO biological_visit_revisions(visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,timing_source,confidence,evaluation_id,revision_reason,operation_id,created_at) VALUES
(CONCAT('demo-b2-r1-',@s),CONCAT('demo-b2-',@s),1,NULL,TIMESTAMPADD(SECOND,@b2off,@p),TIMESTAMPADD(SECOND,@b3off,@p),'reference_demo','criteria_met',NULL,'B2-kriterier oppfylt i referanseserien',NULL,UTC_TIMESTAMP(3)),
(CONCAT('demo-b3-r1-',@s),CONCAT('demo-b3-',@s),1,NULL,TIMESTAMPADD(SECOND,@b3off,@p),NULL,'reference_demo','criteria_met',NULL,'B3-kriterier oppfylt i referanseserien',NULL,UTC_TIMESTAMP(3));

INSERT IGNORE INTO biological_transitions(transition_id,session_id,transitioned_at,from_visit_id,to_visit_id,from_phase_id,to_phase_id,transition_source,confidence,evaluation_id,reason,operation_id,created_at) VALUES
(CONCAT('demo-bio-transition-b2-',@s),@s,TIMESTAMPADD(SECOND,@b2off,@p),@b1visit,CONCAT('demo-b2-',@s),'B1','B2','automatic','criteria_met',NULL,'Referansedemo: B2-kriteriene ble første gang oppfylt.',CONCAT('demo-bio-b2-',@s),UTC_TIMESTAMP(3)),
(CONCAT('demo-bio-transition-b3-',@s),@s,TIMESTAMPADD(SECOND,@b3off,@p),CONCAT('demo-b2-',@s),CONCAT('demo-b3-',@s),'B2','B3','automatic','criteria_met',NULL,'Referansedemo: B3-kriteriene ble første gang oppfylt.',CONCAT('demo-bio-b3-',@s),UTC_TIMESTAMP(3));


INSERT IGNORE INTO observation_rounds(observation_id,session_id,created_at)
VALUES(CONCAT('demo-obs-24-',@s),@s,DATE_ADD(@p,INTERVAL 24 HOUR)),(CONCAT('demo-obs-48-',@s),@s,DATE_ADD(@p,INTERVAL 48 HOUR)),(CONCAT('demo-obs-66-',@s),@s,DATE_ADD(@p,INTERVAL 66 HOUR));
INSERT IGNORE INTO observation_round_revisions(observation_revision_id,observation_id,session_id,revision_no,supersedes_revision_id,status,recorded_at,measurement_method_id,measured_sg,corrected_sg,manual_temperature_c,pressure_bar,cooler_setpoint_c,cooler_calibration_offset_c,airlock_activity,acetaldehyde_level,diacetyl_level,wort_like_level,sulfur_so2_level,sulfur_h2s_level,clarity_level,settling_yeast_level,settling_minutes,user_conclusion,process_gate_status,actual_og_used,note,revision_reason,created_at) VALUES
(CONCAT('demo-obs-24-r1-',@s),CONCAT('demo-obs-24-',@s),@s,1,NULL,'active',DATE_ADD(@p,INTERVAL 24 HOUR),'hydrometer',1.0405,1.0405,8.6,0.30,8.0,0.0,'high',0,1,1,1,0,1,1,15,'uncertain','not_evaluated',1.0463,'Referanseobservasjon · 24 t','reference_demo',UTC_TIMESTAMP(3)),
(CONCAT('demo-obs-48-r1-',@s),CONCAT('demo-obs-48-',@s),@s,1,NULL,'active',DATE_ADD(@p,INTERVAL 48 HOUR),'hydrometer',1.0351,1.0351,8.7,0.60,9.0,0.0,'moderate',0,1,0,0,0,2,2,20,'uncertain','not_evaluated',1.0463,'Referanseobservasjon · 48 t','reference_demo',UTC_TIMESTAMP(3)),
(CONCAT('demo-obs-66-r1-',@s),CONCAT('demo-obs-66-',@s),@s,1,NULL,'active',DATE_ADD(@p,INTERVAL 66 HOUR),'hydrometer',1.0309,1.0309,8.6,0.80,9.0,0.0,'low',0,0,0,0,0,3,3,30,'uncertain','not_evaluated',1.0463,'Referanseobservasjon · 66 t','reference_demo',UTC_TIMESTAMP(3));

 END IF;

 IF v_profile='ipl-synthetic-p17r12' THEN
INSERT INTO process_visit_revisions(visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,timing_source,revision_reason,operation_id,created_at) SELECT CONCAT('ipl-close-process-',@s),r.visit_id,r.revision_no+1,r.visit_revision_id,TIMESTAMPADD(SECOND,0,@p),TIMESTAMPADD(SECOND,86400,@p),'synthetic_p17r12','Opprinnelig syntetisk forløp',NULL,UTC_TIMESTAMP(3) FROM v_current_process_visit_revision r WHERE r.visit_id=(SELECT visit_id FROM process_visits WHERE session_id=@s AND process_id='P1' LIMIT 1);
INSERT INTO process_visits(visit_id,session_id,process_id,created_at) VALUES(CONCAT('ipl-process-P2-',@s),@s,'P2',UTC_TIMESTAMP(3));
INSERT INTO process_visit_revisions(visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,timing_source,revision_reason,operation_id,created_at) VALUES(CONCAT('ipl-process-P2-r1-',@s),CONCAT('ipl-process-P2-',@s),1,NULL,TIMESTAMPADD(SECOND,86400,@p),TIMESTAMPADD(SECOND,518400,@p),'synthetic_p17r12','Opprinnelig syntetisk forløp',NULL,UTC_TIMESTAMP(3));
INSERT INTO process_visits(visit_id,session_id,process_id,created_at) VALUES(CONCAT('ipl-process-P3-',@s),@s,'P3',UTC_TIMESTAMP(3));
INSERT INTO process_visit_revisions(visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,timing_source,revision_reason,operation_id,created_at) VALUES(CONCAT('ipl-process-P3-r1-',@s),CONCAT('ipl-process-P3-',@s),1,NULL,TIMESTAMPADD(SECOND,518400,@p),TIMESTAMPADD(SECOND,604800,@p),'synthetic_p17r12','Opprinnelig syntetisk forløp',NULL,UTC_TIMESTAMP(3));
INSERT INTO process_visits(visit_id,session_id,process_id,created_at) VALUES(CONCAT('ipl-process-P4-',@s),@s,'P4',UTC_TIMESTAMP(3));
INSERT INTO process_visit_revisions(visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,timing_source,revision_reason,operation_id,created_at) VALUES(CONCAT('ipl-process-P4-r1-',@s),CONCAT('ipl-process-P4-',@s),1,NULL,TIMESTAMPADD(SECOND,604800,@p),TIMESTAMPADD(SECOND,691200,@p),'synthetic_p17r12','Opprinnelig syntetisk forløp',NULL,UTC_TIMESTAMP(3));
INSERT INTO process_visits(visit_id,session_id,process_id,created_at) VALUES(CONCAT('ipl-process-P5-',@s),@s,'P5',UTC_TIMESTAMP(3));
INSERT INTO process_visit_revisions(visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,timing_source,revision_reason,operation_id,created_at) VALUES(CONCAT('ipl-process-P5-r1-',@s),CONCAT('ipl-process-P5-',@s),1,NULL,TIMESTAMPADD(SECOND,691200,@p),NULL,'synthetic_p17r12','Opprinnelig syntetisk forløp',NULL,UTC_TIMESTAMP(3));
INSERT INTO biological_visit_revisions(visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,timing_source,confidence,evaluation_id,revision_reason,operation_id,created_at) SELECT CONCAT('ipl-close-biological-',@s),r.visit_id,r.revision_no+1,r.visit_revision_id,TIMESTAMPADD(SECOND,0,@p),TIMESTAMPADD(SECOND,54000,@p),'synthetic_p17r12','criteria_met',NULL,'Opprinnelig syntetisk forløp',NULL,UTC_TIMESTAMP(3) FROM v_current_biological_visit_revision r WHERE r.visit_id=(SELECT visit_id FROM biological_visits WHERE session_id=@s AND phase_id='B1' LIMIT 1);
INSERT INTO biological_visits(visit_id,session_id,phase_id,created_at) VALUES(CONCAT('ipl-biological-B2-',@s),@s,'B2',UTC_TIMESTAMP(3));
INSERT INTO biological_visit_revisions(visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,timing_source,confidence,evaluation_id,revision_reason,operation_id,created_at) VALUES(CONCAT('ipl-biological-B2-r1-',@s),CONCAT('ipl-biological-B2-',@s),1,NULL,TIMESTAMPADD(SECOND,54000,@p),TIMESTAMPADD(SECOND,169200,@p),'synthetic_p17r12','criteria_met',NULL,'Opprinnelig syntetisk forløp',NULL,UTC_TIMESTAMP(3));
INSERT INTO biological_visits(visit_id,session_id,phase_id,created_at) VALUES(CONCAT('ipl-biological-B3-',@s),@s,'B3',UTC_TIMESTAMP(3));
INSERT INTO biological_visit_revisions(visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,timing_source,confidence,evaluation_id,revision_reason,operation_id,created_at) VALUES(CONCAT('ipl-biological-B3-r1-',@s),CONCAT('ipl-biological-B3-',@s),1,NULL,TIMESTAMPADD(SECOND,169200,@p),TIMESTAMPADD(SECOND,518400,@p),'synthetic_p17r12','criteria_met',NULL,'Opprinnelig syntetisk forløp',NULL,UTC_TIMESTAMP(3));
INSERT INTO biological_visits(visit_id,session_id,phase_id,created_at) VALUES(CONCAT('ipl-biological-B4-',@s),@s,'B4',UTC_TIMESTAMP(3));
INSERT INTO biological_visit_revisions(visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,timing_source,confidence,evaluation_id,revision_reason,operation_id,created_at) VALUES(CONCAT('ipl-biological-B4-r1-',@s),CONCAT('ipl-biological-B4-',@s),1,NULL,TIMESTAMPADD(SECOND,518400,@p),NULL,'synthetic_p17r12','criteria_met',NULL,'Opprinnelig syntetisk forløp',NULL,UTC_TIMESTAMP(3));
INSERT INTO session_timing_revisions(timing_revision_id,session_id,timing_field,revision_no,value_at,source,reason,created_at) VALUES(CONCAT('ipl-activity-',@s),@s,'activity_started_at',1,TIMESTAMPADD(SECOND,54000,@p),'synthetic_p17r12','Opprinnelig syntetisk aktivitet',UTC_TIMESTAMP(3));
INSERT INTO session_notes(note_id,session_id,noted_at,note_text,created_at) VALUES(CONCAT('ipl-note-0-',@s),@s,TIMESTAMPADD(SECOND,0,@p),'200 g W-34/70 tilsatt',UTC_TIMESTAMP(3));
INSERT INTO session_notes(note_id,session_id,noted_at,note_text,created_at) VALUES(CONCAT('ipl-note-1-',@s),@s,TIMESTAMPADD(SECOND,54000,@p),'Aktivitet registrert',UTC_TIMESTAMP(3));
INSERT INTO session_notes(note_id,session_id,noted_at,note_text,created_at) VALUES(CONCAT('ipl-note-2-',@s),@s,TIMESTAMPADD(SECOND,169200,@p),'Aktiv hovedgjæring automatisk registrert',UTC_TIMESTAMP(3));
INSERT INTO session_notes(note_id,session_id,noted_at,note_text,created_at) VALUES(CONCAT('ipl-note-3-',@s),@s,TIMESTAMPADD(SECOND,367200,@p),'Datagap i Tilt-serien',UTC_TIMESTAMP(3));
INSERT INTO session_notes(note_id,session_id,noted_at,note_text,created_at) VALUES(CONCAT('ipl-note-4-',@s),@s,TIMESTAMPADD(SECOND,604800,@p),'Temperaturheving registrert',UTC_TIMESTAMP(3));
INSERT INTO session_notes(note_id,session_id,noted_at,note_text,created_at) VALUES(CONCAT('ipl-note-5-',@s),@s,TIMESTAMPADD(SECOND,774000,@p),'Manuell SG 1.012',UTC_TIMESTAMP(3));
INSERT INTO session_notes(note_id,session_id,noted_at,note_text,created_at) VALUES(CONCAT('ipl-setpoint-0-',@s),@s,TIMESTAMPADD(SECOND,518400,@p),'Temperaturtiltak P3 · kjølesettpunkt 10.0 °C',UTC_TIMESTAMP(3));
INSERT INTO session_notes(note_id,session_id,noted_at,note_text,created_at) VALUES(CONCAT('ipl-setpoint-1-',@s),@s,TIMESTAMPADD(SECOND,604800,@p),'Temperaturtiltak P4 · kjølesettpunkt 12.0 °C',UTC_TIMESTAMP(3));
INSERT INTO session_notes(note_id,session_id,noted_at,note_text,created_at) VALUES(CONCAT('ipl-setpoint-2-',@s),@s,TIMESTAMPADD(SECOND,691200,@p),'Temperaturtiltak P5 · kjølesettpunkt 14.0 °C',UTC_TIMESTAMP(3));
INSERT INTO observation_rounds(observation_id,session_id,created_at) VALUES(CONCAT('ipl-final-obs-',@s),@s,TIMESTAMPADD(SECOND,774000,@p));
INSERT INTO observation_round_revisions(observation_revision_id,observation_id,session_id,revision_no,status,recorded_at,measurement_method_id,measured_sg,sample_temperature_c,calibration_temperature_c,corrected_sg,manual_temperature_c,pressure_bar,cooler_setpoint_c,cooler_calibration_offset_c,estimated_abv_percent,estimated_finished_abv_percent,airlock_activity,acetaldehyde_level,diacetyl_level,wort_like_level,sulfur_so2_level,sulfur_h2s_level,clarity_level,settling_yeast_level,settling_minutes,user_conclusion,process_gate_status,corrected_sg_model_id,actual_og_used,note,revision_reason,created_at)
SELECT CONCAT('ipl-final-obs-r1-',@s),CONCAT('ipl-final-obs-',@s),@s,1,'active',TIMESTAMPADD(SECOND,774000,@p),'refractometer',1.026,td.sample_temperature_c_default,td.calibration_temperature_c_default,1.012,14.1,0.0,14.0,0.2,4.94,5.26,'none',1,1,1,1,0,2,2,30,'uncertain','not_evaluated','refractometer-alcohol-correction-sg-to-sg-v2',1.049,'Syntetisk målesett – rediger og lagre for funksjonstest','Opprinnelig p17r12: SG og sensorikk bevart; prøvetemperatur/kalibrering bruker registreringsdefault fordi kilden manglet disse feltene',UTC_TIMESTAMP(3) FROM session_template_defaults td WHERE td.session_id=@s;
 END IF;
INSERT INTO measurements_5m(session_id,bucket_at,sample_count,sg_min,sg_mean,sg_median,sg_max,temperature_min_c,temperature_mean_c,temperature_max_c,pressure_min_bar,pressure_mean_bar,pressure_max_bar,rssi_min_dbm,rssi_mean_dbm,rssi_max_dbm,created_at,updated_at)
SELECT @s,TIMESTAMPADD(SECOND,r.offset_seconds,@p),r.sample_count,r.sg_min,r.sg_mean,r.sg_median,r.sg_max,COALESCE(detail.temperature_min_c,r.temperature_mean_c),r.temperature_mean_c,COALESCE(detail.temperature_max_c,r.temperature_mean_c),synth.pressure_bar,synth.pressure_bar,synth.pressure_bar,detail.rssi_min_dbm,detail.rssi_mean_dbm,detail.rssi_max_dbm,UTC_TIMESTAMP(3),UTC_TIMESTAMP(3)
FROM demo_reference_measurements_5m r LEFT JOIN demo_reference_measurement_details detail ON detail.profile_id=r.profile_id AND detail.offset_seconds=r.offset_seconds LEFT JOIN demo_reference_synthetic_details synth ON synth.profile_id=r.profile_id AND synth.offset_seconds=r.offset_seconds WHERE r.profile_id=v_profile ORDER BY r.offset_seconds;
INSERT INTO measurement_data_gaps(gap_id,session_id,source,gap_started_at,gap_ended_at,duration_seconds,threshold_seconds,detected_at,created_at)
SELECT CONCAT('demo-gap-',g.gap_no,'-',@s),@s,g.source,TIMESTAMPADD(SECOND,g.gap_start_offset_seconds,@p),TIMESTAMPADD(SECOND,g.gap_end_offset_seconds,@p),g.duration_seconds,g.threshold_seconds,UTC_TIMESTAMP(3),UTC_TIMESTAMP(3)
FROM demo_reference_data_gaps g WHERE g.profile_id=v_profile;


 COMMIT;
 SELECT s.*,sts.template_version_id,tv.template_id,tv.name AS template_name,tv.version_label FROM v_active_session_summary s JOIN session_template_snapshots sts ON sts.session_id=s.session_id LEFT JOIN template_versions tv ON tv.version_id=sts.template_version_id WHERE s.session_id=p_sid;
END//
DELIMITER ;

DROP PROCEDURE IF EXISTS ga_register_active_report_tx;
DELIMITER //
CREATE PROCEDURE ga_register_active_report_tx(IN p_session VARCHAR(128),IN p_operation VARCHAR(128),IN p_path TEXT,IN p_sha CHAR(64))
BEGIN
 DECLARE v_seq BIGINT UNSIGNED;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 IF p_operation IS NULL OR p_operation='' OR p_sha NOT REGEXP '^[0-9a-f]{64}$' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Rapportkvittering mangler ID eller kontrollsum'; END IF;
 START TRANSACTION;
 INSERT INTO active_report_requests(operation_id,session_id,requested_at) VALUES(p_operation,p_session,UTC_TIMESTAMP(3)) ON DUPLICATE KEY UPDATE operation_id=operation_id;
 SELECT report_seq INTO v_seq FROM active_report_requests WHERE operation_id=p_operation AND session_id=p_session;
 IF v_seq IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Operasjons-ID tilhører en annen sesjon'; END IF;
 IF EXISTS(SELECT 1 FROM session_exports WHERE export_id=CONCAT('active-report-',v_seq) AND (archive_path<>p_path OR archive_sha256<>p_sha)) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Rapportforsøk har en annen filkvittering'; END IF;
 INSERT INTO session_exports(export_id,session_id,export_kind,attempt_no,status,archive_path,archive_sha256,operation_id,completed_at,created_at)
 VALUES(CONCAT('active-report-',v_seq),p_session,'active_report',v_seq,'verified',p_path,p_sha,p_operation,UTC_TIMESTAMP(3),UTC_TIMESTAMP(3)) ON DUPLICATE KEY UPDATE export_id=export_id;
 COMMIT;
 SELECT 'active_report' AS _set,e.*,CONCAT('/local/gjaeringsassistent/exports/',SUBSTRING_INDEX(e.archive_path,'/',-1)) AS public_url,DATE_FORMAT(e.completed_at,'%d.%m.%Y %H:%i') AS generated_display FROM session_exports e WHERE e.export_id=CONCAT('active-report-',v_seq);
END//
DELIMITER ;

DROP PROCEDURE IF EXISTS ga_read_ha_draft_projection;
DELIMITER //
CREATE PROCEDURE ga_read_ha_draft_projection(IN p_context VARCHAR(24))
READS SQL DATA
BEGIN
 DECLARE v_query LONGTEXT;
 IF p_context NOT IN('start','measurement') THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Ukjent kladdkontekst'; END IF;
 IF EXISTS(SELECT 1 FROM ha_draft_output_bindings b WHERE IF(p_context='start',b.start_enabled,b.measurement_enabled)=1 AND NOT EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS c WHERE c.TABLE_SCHEMA=DATABASE() AND c.TABLE_NAME=IF(p_context='start','session_setup_draft','measurement_input_draft') AND c.COLUMN_NAME=b.field_name)) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB-feltbinding peker på manglende kolonne'; END IF;
 SET SESSION group_concat_max_len=1048576;
 SELECT GROUP_CONCAT(CONCAT(
 'SELECT b.output_slot,b.field_name,b.absence_policy,IF(b.converter_id IN(''number'',''integer''),''number'',''string'') AS value_type,',
 'IF(d.`',b.field_name,'` IS NULL AND b.absence_policy<>''clear'',''not_available'',''present'') AS availability,',
 CASE b.converter_id
 WHEN 'select' THEN CONCAT('(SELECT m.ha_value FROM ha_entity_input_value_mappings m WHERE m.entity_id=b.entity_id AND m.database_value=d.`',b.field_name,'`)')
 WHEN 'datetime' THEN CONCAT('COALESCE(DATE_FORMAT(CONVERT_TZ(d.`',b.field_name,'`,''+00:00'',''Europe/Oslo''),''%Y-%m-%dT%H:%i:%s''),'''')')
 WHEN 'text' THEN CONCAT('COALESCE(d.`',b.field_name,'`,'''')')
 ELSE CONCAT('CAST(d.`',b.field_name,'` AS CHAR)') END,
 ' AS ha_value FROM ha_draft_output_bindings b JOIN ',
 IF(p_context='start','session_setup_draft','measurement_input_draft'),
 ' d ON ',IF(p_context='start','d.draft_key=''current''','EXISTS(SELECT 1 FROM v_active_session a WHERE a.session_id=d.session_id)'),
 ' WHERE b.output_slot=',b.output_slot) ORDER BY b.output_slot SEPARATOR ' UNION ALL ') INTO v_query
 FROM ha_draft_output_bindings b
 WHERE IF(p_context='start',b.start_enabled,b.measurement_enabled)=1
 AND EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS c WHERE c.TABLE_SCHEMA=DATABASE() AND c.TABLE_NAME=IF(p_context='start','session_setup_draft','measurement_input_draft') AND c.COLUMN_NAME=b.field_name);
 IF v_query IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB-feltbindinger mangler'; END IF;
 SET @ga_draft_projection_sql=v_query;
 PREPARE ga_draft_projection FROM @ga_draft_projection_sql; EXECUTE ga_draft_projection; DEALLOCATE PREPARE ga_draft_projection;
END//
DELIMITER ;


DROP TRIGGER IF EXISTS ga_lifecycle_pitch_facts;
DELIMITER //
CREATE TRIGGER ga_lifecycle_pitch_facts BEFORE INSERT ON session_lifecycle_events
FOR EACH ROW
BEGIN
 IF NOT EXISTS(SELECT 1 FROM sessions s LEFT JOIN session_dry_pitches d ON d.session_id=s.session_id LEFT JOIN session_slurry_pitches l ON l.session_id=s.session_id WHERE s.session_id=NEW.session_id AND ((s.pitch_mode_id='dry' AND d.session_id IS NOT NULL) OR (s.pitch_mode_id='slurry' AND l.session_id IS NOT NULL))) THEN
 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Obligatoriske pitchfakta mangler';
 END IF;
END//
DELIMITER ;

DROP PROCEDURE IF EXISTS ga_select_start_template_tx;
DELIMITER //
CREATE PROCEDURE ga_select_start_template_tx(IN p_selected VARCHAR(128))
MODIFIES SQL DATA
BEGIN
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
START TRANSACTION;
IF p_selected IS NULL OR p_selected='' OR p_selected=(SELECT option_value FROM ha_entity_select_options WHERE entity_id='select.gjaeringsassistent_template' ORDER BY option_order LIMIT 1) THEN
 DELETE FROM session_setup_draft WHERE draft_key='current' AND NOT EXISTS(SELECT 1 FROM v_current_session);
ELSE

INSERT INTO session_setup_draft(
 draft_key,template_version_id,pitched_at,pitch_time_mode,batch_name,og,expected_attenuation_min_percent,expected_attenuation_max_percent,
 volume_l,pitch_mode_id,pitch_temperature_c,yeast_amount_g,slurry_volume_ml,slurry_source_batch,
 slurry_generation,oxygenation_note,measurement_method_id,measured_sg,sample_temperature_c,calibration_temperature_c,
 manual_temperature_c,pressure_bar,cooler_setpoint_c,cooler_calibration_offset_c,airlock_activity,
 acetaldehyde_level,diacetyl_level,wort_like_level,sulfur_so2_level,sulfur_h2s_level,clarity_level,
 settling_yeast_level,settling_minutes,user_conclusion,measurement_note,note,saved_at,created_at,updated_at)
SELECT 'current',tv.version_id,NULL,(SELECT m.database_value FROM ha_entity_registry e JOIN ha_entity_input_value_mappings m ON m.entity_id=e.entity_id AND m.ha_value=e.bootstrap_value WHERE e.entity_id='select.gjaeringsassistent_pitchtid_modus'),td.batch_name_default,td.og_default,td.expected_attenuation_min_percent,td.expected_attenuation_max_percent,
 td.volume_l_default,td.pitch_mode_id,td.manual_temperature_c_default,td.yeast_amount_g_default,NULL,NULL,NULL,NULL,
 td.measurement_method_id,td.og_default,td.sample_temperature_c_default,td.calibration_temperature_c_default,td.manual_temperature_c_default,td.pressure_bar_default,td.cooler_setpoint_c_default,td.cooler_calibration_offset_c_default,td.airlock_activity_default,
 td.acetaldehyde_level_default,td.diacetyl_level_default,td.wort_like_level_default,td.sulfur_so2_level_default,td.sulfur_h2s_level_default,td.clarity_level_default,td.settling_yeast_level_default,td.settling_minutes_default,td.user_conclusion_default,td.measurement_note_default,NULL,UTC_TIMESTAMP(3),UTC_TIMESTAMP(3),UTC_TIMESTAMP(3)
FROM template_versions tv JOIN template_defaults td ON td.version_id=tv.version_id
WHERE tv.version_id=p_selected AND tv.status='published' AND NOT EXISTS(SELECT 1 FROM v_current_session)
ON DUPLICATE KEY UPDATE
 template_version_id=VALUES(template_version_id),pitched_at=NULL,pitch_time_mode=VALUES(pitch_time_mode),batch_name=VALUES(batch_name),
 og=VALUES(og),expected_attenuation_min_percent=VALUES(expected_attenuation_min_percent),expected_attenuation_max_percent=VALUES(expected_attenuation_max_percent),volume_l=VALUES(volume_l),
 pitch_mode_id=VALUES(pitch_mode_id),pitch_temperature_c=VALUES(pitch_temperature_c),yeast_amount_g=VALUES(yeast_amount_g),
 slurry_volume_ml=NULL,slurry_source_batch=NULL,slurry_generation=NULL,oxygenation_note=NULL,
 measurement_method_id=VALUES(measurement_method_id),measured_sg=VALUES(measured_sg),sample_temperature_c=VALUES(sample_temperature_c),
 calibration_temperature_c=VALUES(calibration_temperature_c),manual_temperature_c=VALUES(manual_temperature_c),pressure_bar=VALUES(pressure_bar),
 cooler_setpoint_c=VALUES(cooler_setpoint_c),cooler_calibration_offset_c=VALUES(cooler_calibration_offset_c),airlock_activity=VALUES(airlock_activity),acetaldehyde_level=VALUES(acetaldehyde_level),
 diacetyl_level=VALUES(diacetyl_level),wort_like_level=VALUES(wort_like_level),sulfur_so2_level=VALUES(sulfur_so2_level),sulfur_h2s_level=VALUES(sulfur_h2s_level),clarity_level=VALUES(clarity_level),settling_yeast_level=VALUES(settling_yeast_level),
 settling_minutes=VALUES(settling_minutes),user_conclusion=VALUES(user_conclusion),measurement_note=VALUES(measurement_note),note=NULL,saved_at=UTC_TIMESTAMP(3),updated_at=UTC_TIMESTAMP(3);
END IF;
COMMIT;
SELECT COUNT(*) AS active_count FROM v_current_session;
SELECT d.*,CONCAT(CAST(ROUND(d.expected_attenuation_min_percent,1) AS CHAR),'–',CAST(ROUND(d.expected_attenuation_max_percent,1) AS CHAR),' %') AS expected_attenuation_display,CONCAT(REPLACE(REPLACE(FORMAT(d.expected_fg_min,4),',',''),'.',','),'–',REPLACE(REPLACE(FORMAT(d.expected_fg_max,4),',',''),'.',',')) AS expected_fg_display,tv.template_id,tv.name AS template_name,tv.version_label,tv.status AS template_status
FROM session_setup_draft d JOIN template_versions tv ON tv.version_id=d.template_version_id WHERE d.draft_key='current';
END//
DELIMITER ;

DELIMITER //
CREATE PROCEDURE ga_prepare_selected_demo_tx()
BEGIN
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;

DELETE FROM session_setup_draft WHERE draft_key='current' AND NOT EXISTS(SELECT 1 FROM v_current_session);
INSERT INTO session_setup_draft(
 draft_key,template_version_id,is_demo,demo_reference_profile_id,pitched_at,pitch_time_mode,batch_name,og,expected_attenuation_min_percent,expected_attenuation_max_percent,volume_l,pitch_mode_id,pitch_temperature_c,yeast_amount_g,
 slurry_volume_ml,slurry_source_batch,slurry_generation,oxygenation_note,measurement_method_id,measured_sg,sample_temperature_c,calibration_temperature_c,
 manual_temperature_c,pressure_bar,cooler_setpoint_c,cooler_calibration_offset_c,airlock_activity,acetaldehyde_level,diacetyl_level,wort_like_level,sulfur_so2_level,sulfur_h2s_level,
 clarity_level,settling_yeast_level,settling_minutes,user_conclusion,measurement_note,note,saved_at,created_at,updated_at)
SELECT 'current',tv.version_id,1,dr.profile_id,TIMESTAMPADD(SECOND,-dr.span_seconds,UTC_TIMESTAMP(3)),'specified',dr.name,dr.og,
 td.expected_attenuation_min_percent,td.expected_attenuation_max_percent,td.volume_l_default,'dry',12.0,200,NULL,NULL,NULL,'Referansedemo',
 'refractometer',dr.og,td.sample_temperature_c_default,td.calibration_temperature_c_default,12.0,0.0,8.0,0.0,'moderate',0,0,0,0,0,1,1,20,'uncertain','Referansedemo basert på reell Tilt-serie','Referansedemo',UTC_TIMESTAMP(3),UTC_TIMESTAMP(3),UTC_TIMESTAMP(3)
FROM template_versions tv JOIN template_defaults td ON td.version_id=tv.version_id JOIN demo_reference_profiles dr ON dr.profile_id=(SELECT profile_id FROM demo_profile_selection_events ORDER BY selection_seq DESC LIMIT 1)
WHERE tv.version_id='w3470-standard@3.0' AND tv.status='published' AND NOT EXISTS(SELECT 1 FROM v_current_session);
COMMIT;
SELECT session_id,batch_name FROM v_current_session LIMIT 1;
SELECT d.*,tv.template_id,tv.name AS template_name,tv.version_label,tv.status AS template_status FROM session_setup_draft d LEFT JOIN template_versions tv ON tv.version_id=d.template_version_id WHERE d.draft_key='current';
END//
DELIMITER ;

DELIMITER //
CREATE PROCEDURE ga_convert_legacy_archive_graphs(IN p_version VARCHAR(128),IN p_session VARCHAR(128))
BEGIN
 IF NOT EXISTS(SELECT 1 FROM template_analysis_graph_series WHERE version_id=p_version AND source_kind='measurement')
 AND EXISTS(SELECT 1 FROM template_overview_graph_policy WHERE version_id=p_version) THEN
  IF EXISTS(SELECT 1 FROM template_overview_graph_policy p JOIN template_analysis_graphs g ON g.version_id=p.version_id AND g.graph_id=p.graph_id WHERE p.version_id=p_version) THEN
   SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Eldre arkiv har en tvetydig graf-ID';
  END IF;
  UPDATE template_analysis_graphs SET sort_order=sort_order+(SELECT MAX(sort_order) FROM legacy_measurement_graph_models) WHERE version_id=p_version ORDER BY sort_order DESC;
  INSERT INTO template_analysis_graphs(version_id,graph_id,sort_order,label,description,unit,display_decimals,y_axis_min,y_axis_max,y_axis_tick_step,y_axis_include_zero,x_axis_mode,enabled,show_biological_bands,show_process_markers,show_criterion_markers,gap_policy,created_at) SELECT p_version,m.graph_id,m.sort_order,m.label,m.description,m.unit,m.display_decimals,m.y_axis_min,m.y_axis_max,m.y_axis_tick_step,m.y_axis_include_zero,m.x_axis_mode,m.enabled,m.show_biological_bands,m.show_process_markers,m.show_criterion_markers,m.gap_policy,m.created_at FROM legacy_measurement_graph_models m JOIN template_overview_graph_policy p ON p.graph_id=m.graph_id AND p.version_id=p_version;
  INSERT INTO template_analysis_graph_series(version_id,graph_id,series_id,sort_order,label,source_kind,metric_id,owner_id,criterion_id,minimum_samples,minimum_coverage_fraction,warmup_minutes,valid_minimum_value,valid_maximum_value,provisional_allowed,provisional_minimum_samples,provisional_minimum_span_minutes,render_mode,band_model,band_description,standard_color,provisional_color,standard_dasharray,provisional_dasharray,band_opacity,created_at) SELECT p_version,m.graph_id,m.series_id,m.sort_order,m.label,m.source_kind,m.metric_id,m.owner_id,m.criterion_id,m.minimum_samples,m.minimum_coverage_fraction,m.warmup_minutes,m.valid_minimum_value,m.valid_maximum_value,m.provisional_allowed,m.provisional_minimum_samples,m.provisional_minimum_span_minutes,m.render_mode,CASE WHEN m.source_kind='measurement' THEN p.band_model ELSE m.band_model END,CASE WHEN m.source_kind='measurement' THEN p.band_description ELSE m.band_description END,m.standard_color,m.provisional_color,m.standard_dasharray,m.provisional_dasharray,CASE WHEN m.source_kind='measurement' THEN p.band_opacity ELSE m.band_opacity END,m.created_at FROM legacy_measurement_graph_series_models m JOIN template_overview_graph_policy p ON p.graph_id=m.graph_id AND p.version_id=p_version;
 END IF;
 IF p_session IS NOT NULL AND NOT EXISTS(SELECT 1 FROM session_analysis_graph_series WHERE session_id=p_session AND source_kind='measurement')
 AND EXISTS(SELECT 1 FROM session_overview_graph_policy WHERE session_id=p_session) THEN
  IF EXISTS(SELECT 1 FROM session_overview_graph_policy p JOIN session_analysis_graphs g ON g.session_id=p.session_id AND g.graph_id=p.graph_id WHERE p.session_id=p_session) THEN
   SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Eldre gjæringsarkiv har en tvetydig graf-ID';
  END IF;
  UPDATE session_analysis_graphs SET sort_order=sort_order+(SELECT MAX(sort_order) FROM legacy_measurement_graph_models) WHERE session_id=p_session ORDER BY sort_order DESC;
  INSERT INTO session_analysis_graphs(session_id,graph_id,sort_order,label,description,unit,display_decimals,y_axis_min,y_axis_max,y_axis_tick_step,y_axis_include_zero,x_axis_mode,enabled,show_biological_bands,show_process_markers,show_criterion_markers,gap_policy,created_at) SELECT p_session,m.graph_id,m.sort_order,m.label,m.description,m.unit,m.display_decimals,m.y_axis_min,m.y_axis_max,m.y_axis_tick_step,m.y_axis_include_zero,m.x_axis_mode,m.enabled,m.show_biological_bands,m.show_process_markers,m.show_criterion_markers,m.gap_policy,m.created_at FROM legacy_measurement_graph_models m JOIN session_overview_graph_policy p ON p.graph_id=m.graph_id AND p.session_id=p_session;
  INSERT INTO session_analysis_graph_series(session_id,graph_id,series_id,sort_order,label,source_kind,metric_id,owner_id,criterion_id,minimum_samples,minimum_coverage_fraction,warmup_minutes,valid_minimum_value,valid_maximum_value,provisional_allowed,provisional_minimum_samples,provisional_minimum_span_minutes,render_mode,band_model,band_description,standard_color,provisional_color,standard_dasharray,provisional_dasharray,band_opacity,created_at) SELECT p_session,m.graph_id,m.series_id,m.sort_order,m.label,m.source_kind,m.metric_id,m.owner_id,m.criterion_id,m.minimum_samples,m.minimum_coverage_fraction,m.warmup_minutes,m.valid_minimum_value,m.valid_maximum_value,m.provisional_allowed,m.provisional_minimum_samples,m.provisional_minimum_span_minutes,m.render_mode,CASE WHEN m.source_kind='measurement' THEN p.band_model ELSE m.band_model END,CASE WHEN m.source_kind='measurement' THEN p.band_description ELSE m.band_description END,m.standard_color,m.provisional_color,m.standard_dasharray,m.provisional_dasharray,CASE WHEN m.source_kind='measurement' THEN p.band_opacity ELSE m.band_opacity END,m.created_at FROM legacy_measurement_graph_series_models m JOIN session_overview_graph_policy p ON p.graph_id=m.graph_id AND p.session_id=p_session;
 END IF;
END//
DELIMITER ;


DROP PROCEDURE IF EXISTS ga_correct_visit_time_tx;
DELIMITER //
CREATE PROCEDURE ga_correct_visit_time_tx(IN p_kind VARCHAR(32),IN p_target VARCHAR(128),IN p_action VARCHAR(16),IN p_requested DATETIME(3),IN p_operation VARCHAR(128))
BEGIN

 DECLARE v_sid VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin;
 DECLARE v_old VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin;
 DECLARE v_seq BIGINT; DECLARE v_n INTEGER;
 DECLARE v_start DATETIME(3); DECLARE v_original DATETIME(3);
 DECLARE v_lower DATETIME(3); DECLARE v_upper DATETIME(3); DECLARE v_end DATETIME(3); DECLARE v_effective DATETIME(3);
 DECLARE v_conf VARCHAR(64); DECLARE v_eval VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin;
 DECLARE v_ok BOOLEAN DEFAULT FALSE;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 IF p_kind='biological' THEN

 SELECT r.visit_revision_id,v.session_id,v.visit_seq,r.revision_no,r.started_at,r.ended_at,r.confidence,r.evaluation_id INTO v_old,v_sid,v_seq,v_n,v_start,v_end,v_conf,v_eval
 FROM biological_visits v JOIN v_current_biological_visit_revision r ON r.visit_id=v.visit_id JOIN v_active_session a ON a.session_id=v.session_id WHERE v.visit_id=p_target;
 SET v_original=(SELECT r.started_at FROM biological_visit_revisions r WHERE r.visit_id=p_target ORDER BY r.revision_no LIMIT 1);
 SET v_lower=COALESCE((SELECT MAX(r.started_at) FROM biological_visits v JOIN v_current_biological_visit_revision r ON r.visit_id=v.visit_id WHERE v.session_id=v_sid AND (r.started_at<v_start OR r.started_at=v_start AND v.visit_seq<v_seq)),(SELECT a.pitched_at FROM v_active_session a WHERE a.session_id=v_sid));
 SET v_upper=COALESCE((SELECT MIN(r.started_at) FROM biological_visits v JOIN v_current_biological_visit_revision r ON r.visit_id=v.visit_id WHERE v.session_id=v_sid AND (r.started_at>v_start OR r.started_at=v_start AND v.visit_seq>v_seq)),(SELECT a.domain_now FROM v_active_session a WHERE a.session_id=v_sid));
 SET v_effective=IF(p_action='clear',v_original,p_requested);
 SET v_ok=v_old IS NOT NULL AND p_action IN('set','clear') AND v_effective IS NOT NULL AND v_effective BETWEEN v_lower AND v_upper;
 INSERT INTO biological_visit_revisions(visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,timing_source,confidence,evaluation_id,revision_reason,operation_id,created_at)
 SELECT CONCAT('time-',REPLACE(UUID(),'-','')),p_target,v_n+1,v_old,v_effective,IF(v_end IS NULL,NULL,v_upper),'operator_correction',v_conf,v_eval,IF(p_action='clear','Tilbakestilt fasestart','Korrigert fasestart'),p_operation,UTC_TIMESTAMP(3) WHERE v_ok=1;
 ELSEIF p_kind='process' THEN

 SELECT r.visit_revision_id,v.session_id,v.visit_seq,r.revision_no,r.started_at,r.ended_at INTO v_old,v_sid,v_seq,v_n,v_start,v_end
 FROM process_visits v JOIN v_current_process_visit_revision r ON r.visit_id=v.visit_id JOIN v_active_session a ON a.session_id=v.session_id WHERE v.visit_id=p_target;
 SET v_original=(SELECT r.started_at FROM process_visit_revisions r WHERE r.visit_id=p_target ORDER BY r.revision_no LIMIT 1);
 SET v_lower=COALESCE((SELECT MAX(r.started_at) FROM process_visits v JOIN v_current_process_visit_revision r ON r.visit_id=v.visit_id WHERE v.session_id=v_sid AND (r.started_at<v_start OR r.started_at=v_start AND v.visit_seq<v_seq)),(SELECT a.pitched_at FROM v_active_session a WHERE a.session_id=v_sid));
 SET v_upper=COALESCE((SELECT MIN(r.started_at) FROM process_visits v JOIN v_current_process_visit_revision r ON r.visit_id=v.visit_id WHERE v.session_id=v_sid AND (r.started_at>v_start OR r.started_at=v_start AND v.visit_seq>v_seq)),(SELECT a.domain_now FROM v_active_session a WHERE a.session_id=v_sid));
 SET v_effective=IF(p_action='clear',v_original,p_requested);
 SET v_ok=v_old IS NOT NULL AND p_action IN('set','clear') AND v_effective IS NOT NULL AND v_effective BETWEEN v_lower AND v_upper;
 INSERT INTO process_visit_revisions(visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,timing_source,revision_reason,operation_id,created_at)
 SELECT CONCAT('time-',REPLACE(UUID(),'-','')),p_target,v_n+1,v_old,v_effective,IF(v_end IS NULL,NULL,v_upper),'operator_correction',IF(p_action='clear','Tilbakestilt fasestart','Korrigert fasestart'),p_operation,UTC_TIMESTAMP(3) WHERE v_ok=1;
 END IF;
 IF NOT v_ok THEN INSERT INTO technical_events(event_id,schema_version,occurred_at,severity,event_type,code,subsystem,source_component,operation,correlation_id,session_id,message,recoverable,blocks_operation,created_at) VALUES(CONCAT('phase-time-',REPLACE(UUID(),'-','')),'1.0',UTC_TIMESTAMP(3),'warning','event','PHASE_TIME_REJECTED','timeline','MariaDB',p_kind,p_operation,v_sid,'Fasetid avvist: kontroller sesjon, fase og nabogrenser',1,0,UTC_TIMESTAMP(3)); END IF;
 COMMIT;
 SELECT v_ok AS correction_applied,p_target AS target_id,p_kind AS kind,v_effective AS effective_at,v_lower AS minimum_at,v_upper AS maximum_at;
END//
DELIMITER ;

DROP PROCEDURE IF EXISTS ga_register_historical_phase_tx;
DELIMITER //
CREATE PROCEDURE ga_register_historical_phase_tx(IN p_kind VARCHAR(32),IN p_owner VARCHAR(128),IN p_started DATETIME(3),IN p_operation VARCHAR(128))
BEGIN
 DECLARE v_sid VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin;
 DECLARE v_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin;
 DECLARE v_order INTEGER; DECLARE v_lower DATETIME(3); DECLARE v_upper DATETIME(3); DECLARE v_ok BOOLEAN DEFAULT FALSE;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION;
 SET v_sid=(SELECT a.session_id FROM v_active_session a WHERE a.is_historical=1 LIMIT 1);
 SET v_id=CONCAT('historical-',LEFT(SHA2(CONCAT_WS('|',v_sid,p_kind,p_owner),256),48));
 IF p_kind='biological' THEN

 SET v_order=(SELECT p.phase_order FROM session_biological_phases p WHERE p.session_id=v_sid AND p.phase_id=p_owner);
 SET v_lower=COALESCE((SELECT MAX(r.started_at) FROM biological_visits v JOIN v_current_biological_visit_revision r ON r.visit_id=v.visit_id JOIN session_biological_phases p ON p.session_id=v.session_id AND p.phase_id=v.phase_id WHERE v.session_id=v_sid AND p.phase_order<v_order),(SELECT a.pitched_at FROM v_active_session a WHERE a.session_id=v_sid));
 SET v_upper=COALESCE((SELECT MIN(r.started_at) FROM biological_visits v JOIN v_current_biological_visit_revision r ON r.visit_id=v.visit_id JOIN session_biological_phases p ON p.session_id=v.session_id AND p.phase_id=v.phase_id WHERE v.session_id=v_sid AND p.phase_order>v_order),(SELECT a.domain_now FROM v_active_session a WHERE a.session_id=v_sid));
 SET v_ok=v_sid IS NOT NULL AND v_order IS NOT NULL AND p_started BETWEEN v_lower AND v_upper AND NOT EXISTS(SELECT 1 FROM biological_visits v WHERE v.session_id=v_sid AND v.phase_id=p_owner);
 IF v_ok THEN
  INSERT INTO biological_visits(visit_id,session_id,phase_id,created_at) VALUES(v_id,v_sid,p_owner,UTC_TIMESTAMP(3));
  INSERT INTO biological_visit_revisions(visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,timing_source,confidence,evaluation_id,revision_reason,operation_id,created_at)
  VALUES(CONCAT(v_id,'-r1'),v_id,1,NULL,p_started,NULL,'operator_historical','operator_registered',NULL,'Etterregistrert historisk fase',p_operation,UTC_TIMESTAMP(3));
 END IF;
 ELSEIF p_kind='process' THEN

 SET v_order=(SELECT p.process_order FROM session_process_steps p WHERE p.session_id=v_sid AND p.process_id=p_owner AND p.enabled=1);
 SET v_lower=COALESCE((SELECT MAX(r.started_at) FROM process_visits v JOIN v_current_process_visit_revision r ON r.visit_id=v.visit_id JOIN session_process_steps p ON p.session_id=v.session_id AND p.process_id=v.process_id WHERE v.session_id=v_sid AND p.process_order<v_order),(SELECT a.pitched_at FROM v_active_session a WHERE a.session_id=v_sid));
 SET v_upper=COALESCE((SELECT MIN(r.started_at) FROM process_visits v JOIN v_current_process_visit_revision r ON r.visit_id=v.visit_id JOIN session_process_steps p ON p.session_id=v.session_id AND p.process_id=v.process_id WHERE v.session_id=v_sid AND p.process_order>v_order),(SELECT a.domain_now FROM v_active_session a WHERE a.session_id=v_sid));
 SET v_ok=v_sid IS NOT NULL AND v_order IS NOT NULL AND p_started BETWEEN v_lower AND v_upper AND NOT EXISTS(SELECT 1 FROM process_visits v WHERE v.session_id=v_sid AND v.process_id=p_owner);
 IF v_ok THEN
  INSERT INTO process_visits(visit_id,session_id,process_id,created_at) VALUES(v_id,v_sid,p_owner,UTC_TIMESTAMP(3));
  INSERT INTO process_visit_revisions(visit_revision_id,visit_id,revision_no,supersedes_revision_id,started_at,ended_at,timing_source,revision_reason,operation_id,created_at)
  VALUES(CONCAT(v_id,'-r1'),v_id,1,NULL,p_started,NULL,'operator_historical','Etterregistrert historisk fase',p_operation,UTC_TIMESTAMP(3));
 END IF;
 END IF;
 IF NOT v_ok THEN INSERT INTO technical_events(event_id,schema_version,occurred_at,severity,event_type,code,subsystem,source_component,operation,correlation_id,session_id,message,recoverable,blocks_operation,created_at) VALUES(CONCAT('phase-time-',REPLACE(UUID(),'-','')),'1.0',UTC_TIMESTAMP(3),'warning','event','PHASE_TIME_REJECTED','timeline','MariaDB',p_kind,p_operation,v_sid,'Fasetid avvist: kontroller sesjon, fase og nabogrenser',1,0,UTC_TIMESTAMP(3)); END IF;
 COMMIT;
 SELECT v_ok AS correction_applied,v_id AS target_id,p_kind AS kind,p_started AS effective_at,v_lower AS minimum_at,v_upper AS maximum_at;
END//
DELIMITER ;

DROP PROCEDURE IF EXISTS ga_read_start_context;
DELIMITER //
CREATE PROCEDURE ga_read_start_context(IN p_attempt_id VARCHAR(128),IN p_historical_end DATETIME(3))
MODIFIES SQL DATA
BEGIN
 DECLARE v_ready TINYINT; DECLARE v_message TEXT;
 DECLARE v_template VARCHAR(128); DECLARE v_pitch VARCHAR(128); DECLARE v_fields LONGTEXT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 START TRANSACTION WITH CONSISTENT SNAPSHOT;
 SELECT ready_to_start,message INTO v_ready,v_message FROM v_start_readiness;
 IF p_historical_end IS NOT NULL AND NOT EXISTS(SELECT 1 FROM session_setup_draft d WHERE d.is_demo=0 AND d.pitch_time_mode='specified' AND p_historical_end>CASE d.pitch_time_mode WHEN 'now' THEN UTC_TIMESTAMP(3) ELSE d.pitched_at END AND p_historical_end<=UTC_TIMESTAMP(3)) THEN SET v_ready=0; SET v_message='Ugyldig historisk fra–til-periode'; END IF;
 SELECT d.template_version_id,d.pitch_mode_id INTO v_template,v_pitch FROM session_setup_draft d WHERE d.draft_key='current';
 SELECT JSON_ARRAYAGG(JSON_OBJECT('entity_id',entity_id,'observed',database_value,'status',validation_status,'message',validation_message)) INTO v_fields FROM v_start_fields;
 INSERT INTO session_start_attempts(attempt_id,requested_at,ready_to_start,validation_message,template_version_id,pitch_mode_id)
 VALUES(p_attempt_id,UTC_TIMESTAMP(3),v_ready,v_message,v_template,v_pitch);
 INSERT INTO session_start_attempt_fields(attempt_id,entity_id,observed_value,validation_status,validation_message)
 SELECT p_attempt_id,j.entity_id,j.observed_value,j.validation_status,j.validation_message
 FROM JSON_TABLE(COALESCE(v_fields,'[]'),'$[*]' COLUMNS(entity_id VARCHAR(255) PATH '$.entity_id',observed_value TEXT PATH '$.observed',validation_status VARCHAR(24) PATH '$.status',validation_message TEXT PATH '$.message')) j;
 SELECT d.*,p_historical_end AS historical_ended_at,UTC_TIMESTAMP(3) AS database_now,
 CASE d.pitch_time_mode WHEN 'now' THEN UTC_TIMESTAMP(3) WHEN 'specified' THEN d.pitched_at END AS resolved_pitched_at,
 CONCAT(DATE_FORMAT(UTC_TIMESTAMP(3),'%Y%m%d%H%i%s'),LPAD(MICROSECOND(UTC_TIMESTAMP(3)) DIV 1000,3,'0'),'-',tv.template_id) AS session_id_candidate,tv.template_id,tv.name AS template_name,tv.version_label,tv.status AS template_status
 FROM session_setup_draft d LEFT JOIN template_versions tv ON tv.version_id=d.template_version_id WHERE d.draft_key='current';
 SELECT session_id,batch_name FROM v_current_session LIMIT 1;
 SELECT 'measurement_source' AS _set,p.* FROM v_measurement_source_profiles p WHERE p.status='active' ORDER BY p.source_profile_id LIMIT 1;
 SELECT 'start_fields' AS _set,f.* FROM v_start_fields f;
 SELECT 'start_validation' AS _set,p_attempt_id AS attempt_id,v_ready AS ready_to_start,v_message AS message;
 COMMIT;
END//
DELIMITER ;

-- BEGIN GENERATED READ BASIS
DROP PROCEDURE IF EXISTS ga_overview_source_key;
DROP PROCEDURE IF EXISTS ga_drop_read_basis;
DROP PROCEDURE IF EXISTS ga_init_read_basis_part_1;
DROP PROCEDURE IF EXISTS ga_init_read_basis_part_2;
DROP PROCEDURE IF EXISTS ga_init_read_basis_part_3;
DROP PROCEDURE IF EXISTS ga_init_read_basis_part_4;
DROP PROCEDURE IF EXISTS ga_init_read_basis_part_5;
DROP PROCEDURE IF EXISTS ga_init_read_basis_part_6;
DROP PROCEDURE IF EXISTS ga_init_read_basis_part_7;
DROP PROCEDURE IF EXISTS ga_init_read_basis;
DROP PROCEDURE IF EXISTS ga_fill_read_basis_part_1;
DROP PROCEDURE IF EXISTS ga_fill_read_basis_part_2;
DROP PROCEDURE IF EXISTS ga_fill_read_basis_part_3;
DROP PROCEDURE IF EXISTS ga_fill_read_basis_part_4;
DROP PROCEDURE IF EXISTS ga_fill_read_basis_part_5;
DROP PROCEDURE IF EXISTS ga_fill_read_basis_part_6;
DROP PROCEDURE IF EXISTS ga_fill_read_basis_part_7;
DROP PROCEDURE IF EXISTS ga_fill_read_basis_part_8;
DROP PROCEDURE IF EXISTS ga_fill_read_basis_part_9;
DROP PROCEDURE IF EXISTS ga_fill_read_basis;
DROP PROCEDURE IF EXISTS ga_read_overview;
DROP PROCEDURE IF EXISTS ga_read_report;
DROP PROCEDURE IF EXISTS ga_poll_overview;
DROP PROCEDURE IF EXISTS ga_ack_overview;
-- Generated by tools/build_read_queries.py from normalized sources and view SQL.
DELIMITER //
CREATE PROCEDURE ga_overview_source_key(OUT p_key CHAR(64)) BEGIN DECLARE v_session VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin; DECLARE v_reference VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin; SELECT session_id INTO v_session FROM v_active_session; SELECT reference_session_id INTO v_reference FROM v_graph_display_selection WHERE source_kind='session'; SELECT SHA2(CONCAT_WS('|',  (SELECT COALESCE(MAX(`created_at`), '') FROM `analysis_series_values` WHERE session_id=v_session), (SELECT COALESCE(MAX(`created_at`), '') FROM `analysis_series_values` WHERE session_id=v_reference), (SELECT COALESCE(MAX(`sample_at`), '') FROM `analysis_series_values` WHERE session_id=v_session), (SELECT COALESCE(MAX(`sample_at`), '') FROM `analysis_series_values` WHERE session_id=v_reference), (SELECT COALESCE(MAX(`created_at`), '') FROM `analysis_validation_events` WHERE session_id=v_session), (SELECT COALESCE(MAX(`created_at`), '') FROM `analysis_validation_events` WHERE session_id=v_reference), (SELECT COALESCE(MAX(`sample_at`), '') FROM `analysis_validation_events` WHERE session_id=v_session), (SELECT COALESCE(MAX(`sample_at`), '') FROM `analysis_validation_events` WHERE session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `biological_criterion_exceptions` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `biological_evaluation_criteria` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `biological_evaluations` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `biological_transitions` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `biological_visits` WHERE session_id=v_session OR session_id=v_reference), (SELECT COALESCE(MAX(`selection_seq`), 0) FROM `graph_display_selection_events`), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `measurement_data_gaps` WHERE session_id=v_session OR session_id=v_reference), (SELECT COALESCE(MAX(`created_at`), '') FROM `measurement_statistics_hourly` WHERE session_id=v_session), (SELECT COALESCE(MAX(`created_at`), '') FROM `measurement_statistics_hourly` WHERE session_id=v_reference), (SELECT COALESCE(MAX(`start_at`), '') FROM `measurement_statistics_hourly` WHERE session_id=v_session), (SELECT COALESCE(MAX(`start_at`), '') FROM `measurement_statistics_hourly` WHERE session_id=v_reference), (SELECT COALESCE(MAX(`updated_at`), '') FROM `measurements_5m` WHERE session_id=v_session), (SELECT COALESCE(MAX(`updated_at`), '') FROM `measurements_5m` WHERE session_id=v_reference), (SELECT COALESCE(MAX(`bucket_at`), '') FROM `measurements_5m` WHERE session_id=v_session), (SELECT COALESCE(MAX(`bucket_at`), '') FROM `measurements_5m` WHERE session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `observation_round_revisions` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `observation_rounds` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `operator_actions` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `process_criterion_exceptions` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `process_evaluation_criteria` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `process_evaluations` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `process_transitions` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `process_visits` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `recommendation_resolutions` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `recommendations` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_analysis_graph_series` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_analysis_graphs` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_biological_correctable_parameters` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_biological_criteria` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_biological_criterion_parameter_values` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_biological_criterion_revisions` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_biological_phases` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_biology_calculation_parameter_values` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_demo_sources` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_fermentation_targets` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_history_windows` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_lifecycle_events` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_measurement_source_configurations` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`updated_at`), '')) FROM `session_measurement_sources` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_metric_runtime_inputs` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_metric_runtime_parameter_values` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_metric_runtime_rules` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_notes` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_process_action_operator` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_process_action_set_target` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_process_actions` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_process_correctable_parameters` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_process_criteria` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_process_criterion_parameter_values` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_process_criterion_revisions` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_process_steps` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_process_target_exact` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_process_target_range` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_process_targets` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_template_defaults` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_template_snapshots` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `session_timing_revisions` WHERE session_id=v_session OR session_id=v_reference), (SELECT CONCAT(COUNT(*), ':', COALESCE(MAX(`created_at`), '')) FROM `sessions` WHERE session_id=v_session OR session_id=v_reference), (SELECT COALESCE(MAX(event_seq), 0) FROM technical_events), (SELECT COUNT(*) FROM sessions), (SELECT COALESCE(MAX(selection_seq), 0) FROM graph_display_selection_events), (SELECT COALESCE(MAX(selection_seq), 0) FROM demo_profile_selection_events), COALESCE(v_session, '')), 256) INTO p_key; END//
CREATE PROCEDURE ga_drop_read_basis() BEGIN DROP TEMPORARY TABLE IF EXISTS `ga_rb_v_session_runtime_presentation`, `ga_rb_v_session_report_timeline`, `ga_rb_v_session_report_session`, `ga_rb_v_session_report_process_transitions`, `ga_rb_v_session_report_process_exceptions`, `ga_rb_v_session_report_process_criteria`, `ga_rb_v_session_report_process`, `ga_rb_v_session_report_observations`, `ga_rb_v_session_report_notes`, `ga_rb_v_session_report_gaps`, `ga_rb_v_session_report_criterion_corrections`, `ga_rb_v_session_report_biology`, `ga_rb_v_session_report_biological_criteria`, `ga_rb_v_session_report_actions`, `ga_rb_v_session_biological_exception_read_model`, `ga_rb_v_recommendations_effective`, `ga_rb_v_process_transition_evidence`, `ga_rb_v_process_evaluation_criterion_read_model`, `ga_rb_v_template_process_criterion_requirement`, `ga_rb_v_process_evaluation_criterion_requirement`, `ga_rb_v_effective_process_criterion_requirement`, `ga_rb_v_phase_duration_presentation`, `ga_rb_v_historical_phase_options`, `ga_rb_v_graph_time_markers`, `ga_rb_v_graph_latest`, `ga_rb_v_graph_definitions`, `ga_rb_v_report_graph_time_axis`, `ga_rb_v_graph_axis_ticks`, `ga_rb_v_graph_axes`, `ga_rb_v_graph_extents`, `ga_rb_v_graph_series`, `ga_rb_v_graph_raw_series`, `ga_rb_v_graph_source_values`, `ga_rb_v_session_display_measurement_series`, `ga_rb_v_graph_process_plan`, `ga_rb_v_graph_comparison_display`, `ga_rb_v_dashboard_analysis_series`, `ga_rb_v_session_graph_time_axis`, `ga_rb_v_graph_reference_measurement_series`, `ga_rb_v_session_measurement_segments`, `ga_rb_v_dashboard_analysis_segments`, `ga_rb_v_dashboard_analysis_source`, `ga_rb_v_primary_analysis_source`, `ga_rb_v_session_hourly_analysis_series`, `ga_rb_v_session_hourly_analysis_values`, `ga_rb_v_session_hourly_analysis_aggregate`, `ga_rb_v_session_hourly_analysis_policy`, `ga_rb_v_graph_reference_analysis_series`, `ga_rb_v_session_analysis_series`, `ga_rb_v_graph_reference_bands`, `ga_rb_v_dashboard_graph_labels`, `ga_rb_v_session_measurement_series`, `ga_rb_v_graph_display_selection`, `ga_rb_v_current_process_guidance`, `ga_rb_v_process_guidance_effective`, `ga_rb_v_process_guidance_counts`, `ga_rb_v_current_biological_candidate_evaluation`, `ga_rb_v_criterion_correction_receipts`, `ga_rb_v_biological_transition_evidence`, `ga_rb_v_biological_evaluation_criterion_read_model`, `ga_rb_v_template_biological_criterion_requirement`, `ga_rb_v_effective_biological_criterion_requirement`, `ga_rb_v_biological_evaluation_criterion_requirement`, `ga_rb_v_active_technical_issues`, `ga_rb_v_active_session_summary`, `ga_rb_v_active_session_report_summary`, `ga_rb_v_session_report_summary`, `ga_rb_v_measurement_source_status`, `ga_rb_v_session_measurement_source_profiles`, `ga_rb_v_session_source_configuration_values`, `ga_rb_v_current_session_measurement_source_configuration`, `ga_rb_v_session_import_coverage`, `ga_rb_v_current_measurement_statistics_hourly`, `ga_rb_v_measurement_source_profiles`, `ga_rb_v_source_configuration_values`, `ga_rb_v_current_measurement_source_configuration`, `ga_rb_v_measurement_data_gaps`, `ga_rb_v_current_session_summary`, `ga_rb_v_current_process_candidate_evaluation`, `ga_rb_v_current_metric_value`, `ga_rb_v_all_session_summary`, `ga_rb_v_session_archive_status`, `ga_rb_v_latest_process_evaluation`, `ga_rb_v_latest_observation`, `ga_rb_v_current_observation_revision`, `ga_rb_v_latest_biological_evaluation`, `ga_rb_v_current_process_visit`, `ga_rb_v_current_fermentation_target`, `ga_rb_v_current_biological_visit`, `ga_rb_v_active_analysis_requirements`, `ga_rb_v_session_analysis_requirements`, `ga_rb_v_effective_process_criterion_parameters`, `ga_rb_v_effective_biological_criterion_parameters`, `ga_rb_v_current_process_criterion_revision`, `ga_rb_v_current_biological_criterion_revision`, `ga_rb_v_active_session`, `ga_rb_v_current_session`, `ga_rb_v_active_analysis_process_markers`, `ga_rb_v_process_visit_timing`, `ga_rb_v_current_process_visit_revision`, `ga_rb_v_active_analysis_biological_markers`, `ga_rb_v_biological_visit_timing`, `ga_rb_v_current_biological_visit_revision`, `ga_rb_v_all_session`, `ga_rb_v_session_lifecycle`, `ga_rb_v_current_session_timing`, `ga_rb_t_yeast_profiles`, `ga_rb_t_template_versions`, `ga_rb_t_technical_events`, `ga_rb_t_sessions`, `ga_rb_t_session_timing_revisions`, `ga_rb_t_session_template_snapshots`, `ga_rb_t_session_template_defaults`, `ga_rb_t_session_release_events`, `ga_rb_t_session_process_targets`, `ga_rb_t_session_process_target_range`, `ga_rb_t_session_process_target_exact`, `ga_rb_t_session_process_steps`, `ga_rb_t_session_process_criterion_revision_parameter_values`, `ga_rb_t_session_process_criterion_revisions`, `ga_rb_t_session_process_criterion_parameter_values`, `ga_rb_t_session_process_criteria`, `ga_rb_t_session_process_correctable_parameters`, `ga_rb_t_session_process_actions`, `ga_rb_t_session_process_action_set_target`, `ga_rb_t_session_process_action_operator`, `ga_rb_t_session_notes`, `ga_rb_t_session_metric_runtime_rules`, `ga_rb_t_session_metric_runtime_parameter_values`, `ga_rb_t_session_metric_runtime_inputs`, `ga_rb_t_session_measurement_sources`, `ga_rb_t_session_measurement_source_configurations`, `ga_rb_t_session_measurement_signal_bindings`, `ga_rb_t_session_lifecycle_events`, `ga_rb_t_session_history_windows`, `ga_rb_t_session_fermentation_targets`, `ga_rb_t_session_exports`, `ga_rb_t_session_export_attempts`, `ga_rb_t_session_demo_sources`, `ga_rb_t_session_biology_calculation_parameter_values`, `ga_rb_t_session_biological_phases`, `ga_rb_t_session_biological_criterion_revision_parameter_values`, `ga_rb_t_session_biological_criterion_revisions`, `ga_rb_t_session_biological_criterion_parameter_values`, `ga_rb_t_session_biological_criteria`, `ga_rb_t_session_biological_correctable_parameters`, `ga_rb_t_session_analysis_graphs`, `ga_rb_t_session_analysis_graph_series`, `ga_rb_t_recommendations`, `ga_rb_t_recommendation_resolutions`, `ga_rb_t_process_visit_revisions`, `ga_rb_t_process_visits`, `ga_rb_t_process_transitions`, `ga_rb_t_process_evaluations`, `ga_rb_t_process_evaluation_criterion_parameter_values`, `ga_rb_t_process_evaluation_criteria`, `ga_rb_t_process_criterion_exceptions`, `ga_rb_t_operator_actions`, `ga_rb_t_observation_rounds`, `ga_rb_t_observation_round_revisions`, `ga_rb_t_metrics`, `ga_rb_t_measurements_5m`, `ga_rb_t_measurement_statistics_hourly`, `ga_rb_t_measurement_source_units`, `ga_rb_t_measurement_source_signals`, `ga_rb_t_measurement_source_signal_bindings`, `ga_rb_t_measurement_source_profiles`, `ga_rb_t_measurement_source_configurations`, `ga_rb_t_measurement_methods`, `ga_rb_t_measurement_gap_closures`, `ga_rb_t_measurement_data_gaps`, `ga_rb_t_graph_render_policy`, `ga_rb_t_graph_display_selection_events`, `ga_rb_t_demo_reference_synthetic_details`, `ga_rb_t_demo_reference_profiles`, `ga_rb_t_demo_reference_measurements_5m`, `ga_rb_t_demo_reference_measurement_details`, `ga_rb_t_demo_reference_data_gaps`, `ga_rb_t_demo_reference_analysis_values`, `ga_rb_t_criterion_roles`, `ga_rb_t_criterion_model_parameters`, `ga_rb_t_biological_visit_revisions`, `ga_rb_t_biological_visits`, `ga_rb_t_biological_transitions`, `ga_rb_t_biological_evaluations`, `ga_rb_t_biological_evaluation_criterion_parameter_values`, `ga_rb_t_biological_evaluation_criteria`, `ga_rb_t_biological_criterion_exceptions`, `ga_rb_t_analysis_validation_events`, `ga_rb_t_analysis_series_values`, `ga_rb_scope`; END//
CREATE PROCEDURE ga_init_read_basis_part_1() BEGIN
 CREATE TEMPORARY TABLE ga_rb_scope(session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY) ENGINE=InnoDB;
 CREATE TEMPORARY TABLE `ga_rb_t_analysis_series_values`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `series_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `sample_at` datetime(3) NOT NULL, `basis_pitched_at` datetime(3) NOT NULL, `actual_value` decimal(24, 9) NOT NULL, `value_status` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `standard_basis_met` tinyint(4) NOT NULL, `range_min_value` decimal(24, 9) NULL, `range_max_value` decimal(24, 9) NULL, `measured_at` datetime(3) NULL, `sample_count` int(11) NULL, `window_started_at` datetime(3) NULL, `window_ended_at` datetime(3) NULL, `requested_window_seconds` int(11) NULL, `coverage_seconds` int(11) NULL, `source_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `created_at` datetime(3) NOT NULL, `source_observation_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `basis_revision_key` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, PRIMARY KEY(`session_id`, `graph_id`, `series_id`, `sample_at`, `basis_pitched_at`, `basis_revision_key`), KEY ga_i1(`source_observation_revision_id`), KEY ga_i2(`session_id`, `created_at`), KEY ga_i3(`session_id`, `graph_id`, `series_id`, `basis_pitched_at`, `sample_at`), KEY ga_i4(`session_id`, `sample_at`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_analysis_validation_events`(`validation_event_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `series_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `sample_at` datetime(3) NOT NULL, `basis_pitched_at` datetime(3) NOT NULL, `reason_code` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`validation_event_id`), KEY ga_i1(`session_id`, `sample_at`), KEY ga_i2(`session_id`, `graph_id`, `series_id`, `sample_at`, `basis_pitched_at`, `reason_code`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_biological_criterion_exceptions`(`exception_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `revision_no` int(11) NOT NULL, `supersedes_exception_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `action` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `exception_type` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `confirmed` tinyint(4) NOT NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`exception_id`), KEY ga_i1(`session_id`, `evaluation_id`, `criterion_id`), KEY ga_i2(`session_id`, `phase_id`, `criterion_id`, `supersedes_exception_id`), KEY ga_i3(`session_id`, `created_at`), KEY ga_i4(`session_id`, `phase_id`, `criterion_id`, `exception_id`), KEY ga_i5(`session_id`, `phase_id`, `criterion_id`, `revision_no`), KEY ga_i6(`supersedes_exception_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_biological_evaluation_criteria`(`evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `applied_exception_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_order` int(11) NOT NULL, `role_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `met` tinyint(4) NULL, `valid` tinyint(4) NOT NULL, `evaluation_status` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `actual_value` decimal(18, 6) NULL, `actual_text` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `measured_at` datetime(3) NULL, `source` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `data_window_started_at` datetime(3) NULL, `data_window_ended_at` datetime(3) NULL, `requested_window_seconds` int(11) NULL, `sample_count` int(11) NULL, `coverage_seconds` int(11) NULL, `latest_sample_at` datetime(3) NULL, `explanation` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`evaluation_id`, `criterion_id`), KEY ga_i1(`session_id`, `phase_id`, `criterion_id`, `applied_exception_id`), KEY ga_i2(`session_id`, `phase_id`, `criterion_id`, `model_id`), KEY ga_i3(`criterion_revision_id`), KEY ga_i4(`role_id`), KEY ga_i5(`session_id`, `evaluation_id`, `criterion_id`), KEY ga_i6(`evaluation_id`, `criterion_id`, `model_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_biological_evaluation_criterion_parameter_values`(`evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `parameter_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `data_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `real_value` decimal(18, 6) NULL, `integer_value` bigint(20) NULL, `boolean_value` tinyint(4) NULL, `text_value` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `is_unset` tinyint(4) NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`evaluation_id`, `criterion_id`, `parameter_id`), KEY ga_i1(`evaluation_id`, `criterion_id`, `model_id`), KEY ga_i2(`model_id`, `parameter_id`, `data_type`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_biological_evaluations`(`evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `current_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `candidate_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `active_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluated_at` datetime(3) NOT NULL, `outcome` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `confidence` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `data_quality` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `summary` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `engine_version` varchar(96) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`evaluation_id`), KEY ga_i1(`session_id`, `candidate_phase_id`), KEY ga_i2(`session_id`, `current_phase_id`, `active_visit_id`), KEY ga_i3(`session_id`, `evaluated_at`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_biological_transitions`(`transition_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `transitioned_at` datetime(3) NOT NULL, `from_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `to_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `from_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `to_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `transition_source` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `confidence` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`transition_id`), KEY ga_i1(`evaluation_id`), KEY ga_i2(`session_id`, `from_phase_id`, `from_visit_id`), KEY ga_i3(`session_id`, `to_phase_id`, `to_visit_id`), KEY ga_i4(`session_id`, `transitioned_at`), KEY ga_i5(`operation_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_biological_visits`(`visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `visit_seq` bigint(20) unsigned NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`visit_id`), KEY ga_i1(`session_id`, `phase_id`), KEY ga_i2(`session_id`, `phase_id`, `visit_id`), KEY ga_i3(`visit_seq`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_biological_visit_revisions`(`visit_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `revision_no` int(11) NOT NULL, `supersedes_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `started_at` datetime(3) NOT NULL, `ended_at` datetime(3) NULL, `timing_source` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `confidence` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `revision_reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`visit_revision_id`), KEY ga_i1(`evaluation_id`), KEY ga_i2(`visit_id`, `supersedes_revision_id`), KEY ga_i3(`visit_id`, `created_at`), KEY ga_i4(`visit_id`, `revision_no`), KEY ga_i5(`supersedes_revision_id`), KEY ga_i6(`visit_id`, `visit_revision_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_criterion_model_parameters`(`model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `parameter_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `sort_order` int(11) NOT NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `data_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `unit_source` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `fixed_unit` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`model_id`, `parameter_id`), KEY ga_i1(`model_id`, `sort_order`), KEY ga_i2(`model_id`, `parameter_id`, `data_type`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_criterion_roles`(`role_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`role_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_demo_reference_analysis_values`(`profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `series_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `offset_seconds` int(11) NOT NULL, `actual_value` decimal(18, 9) NOT NULL, `sample_count` int(11) NOT NULL, `coverage_seconds` int(11) NOT NULL, `window_seconds` int(11) NOT NULL, `basis_display` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, PRIMARY KEY(`profile_id`, `graph_id`, `series_id`, `offset_seconds`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_demo_reference_data_gaps`(`profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `gap_no` int(11) NOT NULL, `gap_start_offset_seconds` int(11) NOT NULL, `gap_end_offset_seconds` int(11) NOT NULL, `duration_seconds` int(11) NOT NULL, `threshold_seconds` int(11) NOT NULL, `source` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, PRIMARY KEY(`profile_id`, `gap_no`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_demo_reference_measurement_details`(`profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `offset_seconds` int(11) NOT NULL, `temperature_min_c` decimal(8, 3) NULL, `temperature_max_c` decimal(8, 3) NULL, `rssi_min_dbm` decimal(8, 3) NULL, `rssi_mean_dbm` decimal(8, 3) NULL, `rssi_max_dbm` decimal(8, 3) NULL, `source_kind` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, PRIMARY KEY(`profile_id`, `offset_seconds`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_demo_reference_measurements_5m`(`profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `offset_seconds` int(11) NOT NULL, `sample_count` int(11) NOT NULL, `sg_min` decimal(7, 5) NOT NULL, `sg_mean` decimal(7, 5) NOT NULL, `sg_median` decimal(7, 5) NOT NULL, `sg_max` decimal(7, 5) NOT NULL, `temperature_mean_c` decimal(8, 3) NOT NULL, PRIMARY KEY(`profile_id`, `offset_seconds`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_demo_reference_profiles`(`profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `span_seconds` int(11) NOT NULL, `og` decimal(7, 5) NOT NULL, `source_kind` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `source_note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `interval_seconds` int(11) NOT NULL, `selectable` tinyint(4) NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`profile_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_demo_reference_synthetic_details`(`profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `offset_seconds` int(11) NOT NULL, `pressure_bar` decimal(8, 3) NULL, PRIMARY KEY(`profile_id`, `offset_seconds`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_graph_display_selection_events`(`selection_seq` bigint(20) unsigned NOT NULL, `source_kind` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `reference_profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `reference_session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `interval_seconds` int(11) NOT NULL, `window_hours` int(11) NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `selected_at` datetime(3) NOT NULL, PRIMARY KEY(`selection_seq`), KEY ga_i1(`reference_profile_id`), KEY ga_i2(`reference_session_id`), KEY ga_i3(`operation_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_graph_render_policy`(`policy_id` int(11) NOT NULL, `canvas_width` int(11) NOT NULL, `canvas_height` int(11) NOT NULL, `compact_height` int(11) NOT NULL, `margin_left` int(11) NOT NULL, `margin_right` int(11) NOT NULL, `margin_top` int(11) NOT NULL, `margin_bottom` int(11) NOT NULL, `date_font_size` int(11) NOT NULL, `axis_font_size` int(11) NOT NULL, `marker_font_size` int(11) NOT NULL, `font_family` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `line_width` decimal(6, 3) NOT NULL, `time_marker_spacing` int(11) NOT NULL, `point_radius` decimal(6, 3) NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`policy_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_measurement_data_gaps`(`gap_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `source` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `gap_started_at` datetime(3) NOT NULL, `gap_ended_at` datetime(3) NULL, `duration_seconds` int(11) NULL, `threshold_seconds` int(11) NOT NULL, `detected_at` datetime(3) NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`gap_id`), KEY ga_i1(`session_id`, `gap_started_at`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_measurement_gap_closures`(`gap_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `gap_ended_at` datetime(3) NOT NULL, `duration_seconds` int(11) NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`gap_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_measurement_methods`(`measurement_method_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`measurement_method_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_measurement_source_configurations`(`configuration_id` bigint(20) unsigned NOT NULL, `source_profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `parent_configuration_id` bigint(20) unsigned NULL, `parent_key` bigint(20) unsigned NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`configuration_id`), KEY ga_i1(`source_profile_id`, `parent_configuration_id`), KEY ga_i2(`operation_id`), KEY ga_i3(`source_profile_id`, `configuration_id`), KEY ga_i4(`source_profile_id`, `parent_key`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_measurement_source_profiles`(`source_profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `source_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `poll_interval_seconds` int(11) NOT NULL, `gap_threshold_seconds` int(11) NOT NULL, `fresh_age_minutes` int(11) NOT NULL, `stale_age_minutes` int(11) NOT NULL, `status` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, `updated_at` datetime(3) NOT NULL, PRIMARY KEY(`source_profile_id`), KEY ga_i1(`name`, `status`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_measurement_source_signal_bindings`(`configuration_id` bigint(20) unsigned NOT NULL, `signal_id` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `input_mode` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `unit_id` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, PRIMARY KEY(`configuration_id`, `signal_id`), KEY ga_i1(`signal_id`, `unit_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_measurement_source_signals`(`signal_id` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `label` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `observation_kind` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `sensor_required` tinyint(4) NOT NULL, `operator_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `display_order` int(11) NOT NULL, `show_on_start` tinyint(4) NOT NULL, `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, PRIMARY KEY(`signal_id`), KEY ga_i1(`operator_entity_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_measurement_source_units`(`signal_id` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `unit_id` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `ha_unit` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `label` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `multiplier` decimal(24, 12) NOT NULL, `additive_offset` decimal(24, 12) NOT NULL, `is_canonical` tinyint(4) NOT NULL, `canonical_signal` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NULL, PRIMARY KEY(`signal_id`, `unit_id`), KEY ga_i1(`canonical_signal`), KEY ga_i2(`signal_id`, `ha_unit`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_measurement_statistics_hourly`(`statistic_seq` bigint(20) unsigned NOT NULL, `statistic_import_id` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `start_at` datetime(3) NOT NULL, `end_at` datetime(3) NOT NULL, `sg_min` double NULL, `sg_mean` double NULL, `sg_max` double NULL, `temperature_min_c` double NULL, `temperature_mean_c` double NULL, `temperature_max_c` double NULL, `rssi_min_dbm` double NULL, `rssi_mean_dbm` double NULL, `rssi_max_dbm` double NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`statistic_seq`), KEY ga_i1(`session_id`, `start_at`, `statistic_seq`), KEY ga_i2(`statistic_import_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_measurements_5m`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `bucket_at` datetime(3) NOT NULL, `sample_count` int(11) NOT NULL, `sg_min` decimal(7, 5) NOT NULL, `sg_mean` decimal(7, 5) NOT NULL, `sg_median` decimal(7, 5) NOT NULL, `sg_max` decimal(7, 5) NOT NULL, `temperature_min_c` decimal(8, 3) NOT NULL, `temperature_mean_c` decimal(8, 3) NOT NULL, `temperature_max_c` decimal(8, 3) NOT NULL, `pressure_min_bar` decimal(8, 4) NULL, `pressure_mean_bar` decimal(8, 4) NULL, `pressure_max_bar` decimal(8, 4) NULL, `rssi_min_dbm` decimal(8, 3) NULL, `rssi_mean_dbm` decimal(8, 3) NULL, `rssi_max_dbm` decimal(8, 3) NULL, `created_at` datetime(3) NOT NULL, `updated_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `bucket_at`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_metrics`(`metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `sort_order` int(11) NOT NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `unit` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `display_decimals` int(11) NOT NULL, `source_class` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`metric_id`), KEY ga_i1(`sort_order`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_observation_round_revisions`(`observation_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `observation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `revision_no` int(11) NOT NULL, `supersedes_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `status` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `recorded_at` datetime(3) NOT NULL, `measurement_method_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `measured_sg` decimal(7, 5) NOT NULL, `sample_temperature_c` decimal(8, 3) NOT NULL, `calibration_temperature_c` decimal(8, 3) NOT NULL, `corrected_sg` decimal(7, 5) NOT NULL, `manual_temperature_c` decimal(8, 3) NOT NULL, `pressure_bar` decimal(8, 4) NOT NULL, `cooler_setpoint_c` decimal(8, 3) NOT NULL, `cooler_calibration_offset_c` decimal(8, 3) NOT NULL, `estimated_abv_percent` decimal(8, 3) NULL, `estimated_finished_abv_percent` decimal(8, 3) NULL, `airlock_activity` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `acetaldehyde_level` int(11) NOT NULL, `diacetyl_level` int(11) NOT NULL, `wort_like_level` int(11) NOT NULL, `sulfur_so2_level` int(11) NOT NULL, `sulfur_h2s_level` int(11) NOT NULL, `clarity_level` int(11) NOT NULL, `settling_yeast_level` int(11) NOT NULL, `settling_minutes` decimal(12, 3) NOT NULL, `user_conclusion` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `calculated_conclusion` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `process_gate_status` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `corrected_sg_model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `abv_now_model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `estimated_finished_abv_model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `actual_og_used` decimal(7, 5) NOT NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `revision_reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`observation_revision_id`), KEY ga_i1(`abv_now_model_id`), KEY ga_i2(`corrected_sg_model_id`), KEY ga_i3(`estimated_finished_abv_model_id`), KEY ga_i4(`measurement_method_id`), KEY ga_i5(`observation_id`, `supersedes_revision_id`), KEY ga_i6(`session_id`, `recorded_at`), KEY ga_i7(`observation_id`, `observation_revision_id`), KEY ga_i8(`observation_id`, `revision_no`), KEY ga_i9(`session_id`, `observation_id`, `observation_revision_id`), KEY ga_i10(`supersedes_revision_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_observation_rounds`(`observation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`observation_id`), KEY ga_i1(`session_id`, `created_at`), KEY ga_i2(`session_id`, `observation_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_operator_actions`(`action_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `action_name` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `entity_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `pressed_at` datetime(3) NOT NULL, `completed_at` datetime(3) NOT NULL, `outcome` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `accepted` tinyint(4) NOT NULL, `state_before` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `state_after` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `technical_error` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `field_error` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `detail_text` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`action_id`), KEY ga_i1(`operation_id`), KEY ga_i2(`session_id`, `completed_at`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_process_criterion_exceptions`(`exception_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `revision_no` int(11) NOT NULL, `supersedes_exception_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `action` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `exception_type` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `confirmed` tinyint(4) NOT NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`exception_id`), KEY ga_i1(`session_id`, `evaluation_id`, `criterion_id`), KEY ga_i2(`evaluation_id`, `criterion_id`, `supersedes_exception_id`), KEY ga_i3(`session_id`, `created_at`), KEY ga_i4(`evaluation_id`, `criterion_id`, `exception_id`), KEY ga_i5(`evaluation_id`, `criterion_id`, `revision_no`), KEY ga_i6(`supersedes_exception_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_process_evaluation_criteria`(`evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `candidate_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `criterion_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_order` int(11) NOT NULL, `role_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `met` tinyint(4) NULL, `valid` tinyint(4) NOT NULL, `evaluation_status` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `actual_value` decimal(18, 6) NULL, `actual_text` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `measured_at` datetime(3) NULL, `source` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `data_window_started_at` datetime(3) NULL, `data_window_ended_at` datetime(3) NULL, `requested_window_seconds` int(11) NULL, `sample_count` int(11) NULL, `coverage_seconds` int(11) NULL, `latest_sample_at` datetime(3) NULL, `explanation` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`evaluation_id`, `criterion_id`), KEY ga_i1(`session_id`, `candidate_process_id`, `criterion_id`, `model_id`), KEY ga_i2(`criterion_revision_id`), KEY ga_i3(`role_id`), KEY ga_i4(`evaluation_id`, `criterion_id`, `model_id`), KEY ga_i5(`session_id`, `evaluation_id`, `criterion_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_process_evaluation_criterion_parameter_values`(`evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `parameter_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `data_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `real_value` decimal(18, 6) NULL, `integer_value` bigint(20) NULL, `boolean_value` tinyint(4) NULL, `text_value` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `is_unset` tinyint(4) NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`evaluation_id`, `criterion_id`, `parameter_id`), KEY ga_i1(`evaluation_id`, `criterion_id`, `model_id`), KEY ga_i2(`model_id`, `parameter_id`, `data_type`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_process_evaluations`(`evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `current_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `candidate_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `active_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `observation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `observation_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluated_at` datetime(3) NOT NULL, `readiness` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `data_quality` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `summary` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `recommended_temperature_c` decimal(8, 3) NULL, `recommended_pressure_bar` decimal(8, 4) NULL, `engine_version` varchar(96) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`evaluation_id`), KEY ga_i1(`session_id`, `candidate_process_id`), KEY ga_i2(`session_id`, `observation_id`, `observation_revision_id`), KEY ga_i3(`session_id`, `current_process_id`, `active_visit_id`), KEY ga_i4(`session_id`, `evaluated_at`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_process_transitions`(`transition_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `transitioned_at` datetime(3) NOT NULL, `from_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `to_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `from_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `to_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `action` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `recommendation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `recommended_temperature_c` decimal(8, 3) NULL, `recommended_pressure_bar` decimal(8, 4) NULL, `operator_temperature_setting_c` decimal(8, 3) NULL, `operator_pressure_setting_bar` decimal(8, 4) NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`transition_id`), KEY ga_i1(`evaluation_id`), KEY ga_i2(`session_id`, `from_process_id`, `from_visit_id`), KEY ga_i3(`recommendation_id`), KEY ga_i4(`session_id`, `to_process_id`, `to_visit_id`), KEY ga_i5(`session_id`, `transitioned_at`), KEY ga_i6(`operation_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_process_visits`(`visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `visit_seq` bigint(20) unsigned NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`visit_id`), KEY ga_i1(`session_id`, `process_id`), KEY ga_i2(`session_id`, `process_id`, `visit_id`), KEY ga_i3(`visit_seq`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_process_visit_revisions`(`visit_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `revision_no` int(11) NOT NULL, `supersedes_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `started_at` datetime(3) NOT NULL, `ended_at` datetime(3) NULL, `timing_source` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `revision_reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`visit_revision_id`), KEY ga_i1(`visit_id`, `supersedes_revision_id`), KEY ga_i2(`visit_id`, `created_at`), KEY ga_i3(`visit_id`, `revision_no`), KEY ga_i4(`supersedes_revision_id`), KEY ga_i5(`visit_id`, `visit_revision_id`)) ENGINE=Aria TRANSACTIONAL=0;
END//
CREATE PROCEDURE ga_init_read_basis_part_2() BEGIN
 CREATE TEMPORARY TABLE `ga_rb_t_recommendation_resolutions`(`resolution_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `recommendation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `outcome` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `actual_action` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`resolution_id`), KEY ga_i1(`session_id`), KEY ga_i2(`recommendation_id`, `created_at`), KEY ga_i3(`operation_id`), KEY ga_i4(`recommendation_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_recommendations`(`recommendation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `observation_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `severity` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `rule_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `recommendation_type` varchar(96) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `model_version` varchar(96) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `explanation` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `uncertainty` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `supersedes_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`recommendation_id`), KEY ga_i1(`evaluation_id`), KEY ga_i2(`observation_revision_id`), KEY ga_i3(`session_id`, `rule_id`, `supersedes_id`), KEY ga_i4(`session_id`, `created_at`), KEY ga_i5(`session_id`, `rule_id`, `recommendation_id`), KEY ga_i6(`supersedes_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_analysis_graph_series`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `series_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `sort_order` int(11) NOT NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `source_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `minimum_samples` int(11) NULL, `minimum_coverage_fraction` decimal(8, 6) NULL, `warmup_minutes` int(11) NULL, `valid_minimum_value` decimal(18, 6) NULL, `valid_maximum_value` decimal(18, 6) NULL, `provisional_allowed` tinyint(4) NOT NULL, `provisional_minimum_samples` int(11) NOT NULL, `provisional_minimum_span_minutes` decimal(18, 6) NOT NULL, `render_mode` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `band_model` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `band_description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `standard_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `provisional_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `standard_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `provisional_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `band_opacity` decimal(4, 3) NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `graph_id`, `series_id`), KEY ga_i1(`metric_id`), KEY ga_i2(`session_id`, `graph_id`, `sort_order`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_analysis_graphs`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `sort_order` int(11) NOT NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `unit` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `display_decimals` int(11) NOT NULL, `y_axis_min` decimal(18, 6) NULL, `y_axis_max` decimal(18, 6) NULL, `y_axis_tick_step` decimal(18, 6) NULL, `y_axis_include_zero` tinyint(4) NOT NULL, `x_axis_mode` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `enabled` tinyint(4) NOT NULL, `show_biological_bands` tinyint(4) NOT NULL, `show_process_markers` tinyint(4) NOT NULL, `show_criterion_markers` tinyint(4) NOT NULL, `gap_policy` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `graph_id`), KEY ga_i1(`session_id`, `sort_order`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_biological_correctable_parameters`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `parameter_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `phase_id`, `criterion_id`, `parameter_id`), KEY ga_i1(`session_id`, `phase_id`, `criterion_id`, `model_id`), KEY ga_i2(`model_id`, `parameter_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_biological_criteria`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `criterion_order` int(11) NOT NULL, `enabled` tinyint(4) NOT NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `role_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `exception_allowed` tinyint(4) NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `phase_id`, `criterion_id`), KEY ga_i1(`role_id`), KEY ga_i2(`metric_id`, `model_id`), KEY ga_i3(`session_id`, `phase_id`, `criterion_id`, `model_id`), KEY ga_i4(`session_id`, `phase_id`, `criterion_order`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_biological_criterion_parameter_values`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `parameter_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `data_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `real_value` decimal(18, 6) NULL, `integer_value` bigint(20) NULL, `boolean_value` tinyint(4) NULL, `text_value` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `phase_id`, `criterion_id`, `parameter_id`), KEY ga_i1(`session_id`, `phase_id`, `criterion_id`, `model_id`), KEY ga_i2(`model_id`, `parameter_id`, `data_type`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_biological_criterion_revisions`(`criterion_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `revision_no` int(11) NOT NULL, `supersedes_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `action` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `confirmed` tinyint(4) NOT NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`criterion_revision_id`), KEY ga_i1(`session_id`, `phase_id`, `criterion_id`, `model_id`), KEY ga_i2(`session_id`, `phase_id`, `criterion_id`, `supersedes_revision_id`), KEY ga_i3(`session_id`, `created_at`), KEY ga_i4(`session_id`, `phase_id`, `criterion_id`, `criterion_revision_id`), KEY ga_i5(`criterion_revision_id`, `model_id`), KEY ga_i6(`session_id`, `phase_id`, `criterion_id`, `revision_no`), KEY ga_i7(`supersedes_revision_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_biological_criterion_revision_parameter_values`(`criterion_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `parameter_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `data_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `is_unset` tinyint(4) NOT NULL, `real_value` decimal(18, 6) NULL, `integer_value` bigint(20) NULL, `boolean_value` tinyint(4) NULL, `text_value` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`criterion_revision_id`, `parameter_id`), KEY ga_i1(`model_id`, `parameter_id`, `data_type`), KEY ga_i2(`criterion_revision_id`, `model_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_biological_phases`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `phase_order` int(11) NOT NULL, `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `phase_id`), KEY ga_i1(`session_id`, `phase_order`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_biology_calculation_parameter_values`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `calculation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `parameter_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `data_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `real_value` decimal(18, 6) NULL, `integer_value` bigint(20) NULL, `boolean_value` tinyint(4) NULL, `text_value` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `calculation_id`, `parameter_id`), KEY ga_i1(`session_id`, `calculation_id`, `model_id`), KEY ga_i2(`model_id`, `parameter_id`, `data_type`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_demo_sources`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `interval_seconds` int(11) NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`), KEY ga_i1(`profile_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_export_attempts`(`attempt_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `export_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `attempt_no` bigint(20) unsigned NOT NULL, `requested_at` datetime(3) NOT NULL, PRIMARY KEY(`attempt_id`), KEY ga_i1(`attempt_no`), KEY ga_i2(`session_id`, `export_kind`, `attempt_no`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_exports`(`export_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `export_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `attempt_no` int(11) NOT NULL, `status` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `archive_path` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `archive_sha256` char(64) CHARACTER SET ascii COLLATE ascii_bin NULL, `archive_bytes` bigint(20) unsigned NULL, `report_path` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `report_sha256` char(64) CHARACTER SET ascii COLLATE ascii_bin NULL, `report_bytes` bigint(20) unsigned NULL, `template_path` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `template_sha256` char(64) CHARACTER SET ascii COLLATE ascii_bin NULL, `template_bytes` bigint(20) unsigned NULL, `error_message` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `completed_at` datetime(3) NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`export_id`), KEY ga_i1(`session_id`, `completed_at`), KEY ga_i2(`session_id`, `export_kind`, `attempt_no`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_fermentation_targets`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `expected_attenuation_min_percent` decimal(8, 4) NOT NULL, `expected_attenuation_max_percent` decimal(8, 4) NOT NULL, `expected_fg_min` decimal(7, 5) NOT NULL, `expected_fg_max` decimal(7, 5) NOT NULL, `source` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_history_windows`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `ended_at` datetime(3) NOT NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`), KEY ga_i1(`operation_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_lifecycle_events`(`lifecycle_event_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `lifecycle` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `occurred_at` datetime(3) NOT NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`lifecycle_event_id`), KEY ga_i1(`session_id`, `created_at`), KEY ga_i2(`session_id`, `lifecycle`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_measurement_signal_bindings`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `configuration_id` bigint(20) unsigned NOT NULL, `signal_id` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `input_mode` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `unit_id` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `minimum_value` decimal(24, 8) NULL, `maximum_value` decimal(24, 8) NULL, PRIMARY KEY(`session_id`, `configuration_id`, `signal_id`), KEY ga_i1(`signal_id`, `unit_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_measurement_source_configurations`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `configuration_id` bigint(20) unsigned NOT NULL, `effective_from` datetime(3) NOT NULL, `profile_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `configuration_id`), KEY ga_i1(`session_id`, `effective_from`, `configuration_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_measurement_sources`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `source_profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `source_started_at` datetime(3) NOT NULL, `last_import_cutoff_at` datetime(3) NOT NULL, `last_success_at` datetime(3) NULL, `last_error` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, `updated_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`), KEY ga_i1(`source_profile_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_metric_runtime_inputs`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `input_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `source_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `source_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `metric_id`, `input_id`), KEY ga_i1(`model_id`, `input_id`), KEY ga_i2(`session_id`, `metric_id`, `model_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_metric_runtime_parameter_values`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `parameter_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `data_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `real_value` decimal(18, 6) NULL, `integer_value` bigint(20) NULL, `boolean_value` tinyint(4) NULL, `text_value` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `metric_id`, `parameter_id`), KEY ga_i1(`model_id`, `parameter_id`, `data_type`), KEY ga_i2(`session_id`, `metric_id`, `model_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_metric_runtime_rules`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `calculation_model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `freshness_mode` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `valid_minimum_value` decimal(18, 6) NULL, `valid_maximum_value` decimal(18, 6) NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `metric_id`), KEY ga_i1(`calculation_model_id`), KEY ga_i2(`metric_id`), KEY ga_i3(`session_id`, `metric_id`, `calculation_model_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_notes`(`note_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `noted_at` datetime(3) NOT NULL, `note_text` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`note_id`), KEY ga_i1(`session_id`, `noted_at`), KEY ga_i2(`operation_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_process_action_operator`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `action_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `action_type_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `operator_operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `process_id`, `action_id`), KEY ga_i1(`session_id`, `process_id`, `action_id`, `action_type_id`), KEY ga_i2(`operator_operation_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_process_action_set_target`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `action_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `action_type_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `target_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `process_id`, `action_id`), KEY ga_i1(`session_id`, `process_id`, `action_id`, `action_type_id`), KEY ga_i2(`session_id`, `process_id`, `target_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_process_actions`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `action_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `action_order` int(11) NOT NULL, `action_type_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `process_id`, `action_id`), KEY ga_i1(`action_type_id`), KEY ga_i2(`session_id`, `process_id`, `action_order`), KEY ga_i3(`session_id`, `process_id`, `action_id`, `action_type_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_process_correctable_parameters`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `parameter_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `process_id`, `criterion_id`, `parameter_id`), KEY ga_i1(`session_id`, `process_id`, `criterion_id`, `model_id`), KEY ga_i2(`model_id`, `parameter_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_process_criteria`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `criterion_order` int(11) NOT NULL, `enabled` tinyint(4) NOT NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `role_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `exception_allowed` tinyint(4) NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `process_id`, `criterion_id`), KEY ga_i1(`role_id`), KEY ga_i2(`metric_id`, `model_id`), KEY ga_i3(`session_id`, `process_id`, `criterion_id`, `model_id`), KEY ga_i4(`session_id`, `process_id`, `criterion_order`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_process_criterion_parameter_values`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `parameter_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `data_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `real_value` decimal(18, 6) NULL, `integer_value` bigint(20) NULL, `boolean_value` tinyint(4) NULL, `text_value` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `process_id`, `criterion_id`, `parameter_id`), KEY ga_i1(`session_id`, `process_id`, `criterion_id`, `model_id`), KEY ga_i2(`model_id`, `parameter_id`, `data_type`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_process_criterion_revisions`(`criterion_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `revision_no` int(11) NOT NULL, `supersedes_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `action` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `confirmed` tinyint(4) NOT NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`criterion_revision_id`), KEY ga_i1(`session_id`, `process_id`, `criterion_id`, `model_id`), KEY ga_i2(`session_id`, `process_id`, `criterion_id`, `supersedes_revision_id`), KEY ga_i3(`session_id`, `created_at`), KEY ga_i4(`session_id`, `process_id`, `criterion_id`, `criterion_revision_id`), KEY ga_i5(`criterion_revision_id`, `model_id`), KEY ga_i6(`session_id`, `process_id`, `criterion_id`, `revision_no`), KEY ga_i7(`supersedes_revision_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_process_criterion_revision_parameter_values`(`criterion_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `parameter_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `data_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `is_unset` tinyint(4) NOT NULL, `real_value` decimal(18, 6) NULL, `integer_value` bigint(20) NULL, `boolean_value` tinyint(4) NULL, `text_value` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`criterion_revision_id`, `parameter_id`), KEY ga_i1(`model_id`, `parameter_id`, `data_type`), KEY ga_i2(`criterion_revision_id`, `model_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_process_steps`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `slot_no` int(11) NOT NULL, `process_order` int(11) NOT NULL, `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `enabled` tinyint(4) NOT NULL, `historical_replay_auto_transition_allowed` tinyint(4) NOT NULL, `anchor_type` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `anchor_biological_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `anchor_offset_hours` decimal(12, 4) NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `process_id`), KEY ga_i1(`session_id`, `anchor_biological_phase_id`), KEY ga_i2(`session_id`, `process_order`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_process_target_exact`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `target_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `target_value` decimal(18, 6) NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `process_id`, `target_id`), KEY ga_i1(`session_id`, `process_id`, `target_id`, `model_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_process_target_range`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `target_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `minimum_value` decimal(18, 6) NOT NULL, `maximum_value` decimal(18, 6) NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `process_id`, `target_id`), KEY ga_i1(`session_id`, `process_id`, `target_id`, `model_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_process_targets`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `target_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `target_order` int(11) NOT NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `purpose` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`, `process_id`, `target_id`), KEY ga_i1(`metric_id`, `model_id`), KEY ga_i2(`session_id`, `process_id`, `target_id`, `model_id`), KEY ga_i3(`session_id`, `process_id`, `target_order`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_release_events`(`release_event_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `released_at` datetime(3) NOT NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`release_event_id`), KEY ga_i1(`released_at`), KEY ga_i2(`operation_id`), KEY ga_i3(`session_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_template_defaults`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `batch_name_default` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `volume_l_default` decimal(10, 3) NOT NULL, `og_default` decimal(7, 5) NOT NULL, `expected_attenuation_min_percent` decimal(8, 4) NOT NULL, `expected_attenuation_max_percent` decimal(8, 4) NOT NULL, `expected_fg_min` decimal(7, 5) NOT NULL, `expected_fg_max` decimal(7, 5) NOT NULL, `pitch_temperature_c_default` decimal(8, 3) NOT NULL, `pitch_mode_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `yeast_profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `yeast_amount_g_default` decimal(10, 3) NULL, `measurement_method_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `sample_temperature_c_default` decimal(8, 3) NOT NULL, `calibration_temperature_c_default` decimal(8, 3) NOT NULL, `manual_temperature_c_default` decimal(8, 3) NOT NULL, `pressure_bar_default` decimal(8, 3) NOT NULL, `cooler_setpoint_c_default` decimal(8, 3) NOT NULL, `cooler_calibration_offset_c_default` decimal(8, 3) NOT NULL, `airlock_activity_default` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `acetaldehyde_level_default` int(11) NOT NULL, `diacetyl_level_default` int(11) NOT NULL, `wort_like_level_default` int(11) NOT NULL, `sulfur_so2_level_default` int(11) NOT NULL, `sulfur_h2s_level_default` int(11) NOT NULL, `clarity_level_default` int(11) NOT NULL, `settling_yeast_level_default` int(11) NOT NULL, `settling_minutes_default` decimal(10, 3) NOT NULL, `user_conclusion_default` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `measurement_note_default` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`), KEY ga_i1(`measurement_method_id`), KEY ga_i2(`pitch_mode_id`), KEY ga_i3(`yeast_profile_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_template_snapshots`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `template_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `template_version_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `template_version_label` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `template_store_schema_version` int(11) NOT NULL, `snapshot_format_version` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `snapshot_sha256` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `source_published_at` datetime(3) NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`session_id`), KEY ga_i1(`template_id`), KEY ga_i2(`template_version_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_session_timing_revisions`(`timing_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `timing_field` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `revision_no` int(11) NOT NULL, `supersedes_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `value_at` datetime(3) NOT NULL, `source` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`timing_revision_id`), KEY ga_i1(`session_id`, `timing_field`, `supersedes_revision_id`), KEY ga_i2(`session_id`, `created_at`), KEY ga_i3(`session_id`, `timing_field`, `revision_no`), KEY ga_i4(`supersedes_revision_id`), KEY ga_i5(`session_id`, `timing_field`, `timing_revision_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_sessions`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `batch_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `is_demo` tinyint(4) NOT NULL, `created_at` datetime(3) NOT NULL, `pitched_at` datetime(3) NOT NULL, `og` decimal(7, 5) NOT NULL, `volume_l` decimal(10, 3) NOT NULL, `yeast_profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `pitch_mode_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `pitch_temperature_c` decimal(8, 3) NOT NULL, `oxygenation_note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, PRIMARY KEY(`session_id`), KEY ga_i1(`pitch_mode_id`), KEY ga_i2(`yeast_profile_id`), KEY ga_i3(`session_id`, `pitch_mode_id`)) ENGINE=Aria TRANSACTIONAL=0;
END//
CREATE PROCEDURE ga_init_read_basis_part_3() BEGIN
 CREATE TEMPORARY TABLE `ga_rb_t_technical_events`(`event_seq` bigint(20) unsigned NOT NULL, `event_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `schema_version` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `occurred_at` datetime(3) NOT NULL, `severity` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `event_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `code` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `issue_key` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `subsystem` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `source_component` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_node_id` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_node_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_type` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `process_step` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `correlation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `message` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `recoverable` tinyint(4) NOT NULL, `blocks_operation` tinyint(4) NOT NULL, `related_event_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`event_id`), KEY ga_i1(`event_seq`), KEY ga_i2(`related_event_id`), KEY ga_i3(`correlation_id`), KEY ga_i4(`issue_key`, `occurred_at`), KEY ga_i5(`occurred_at`), KEY ga_i6(`session_id`, `occurred_at`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_template_versions`(`version_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `template_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `status` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `version_label` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `based_on_version_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `revision_note` varchar(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NOT NULL, `published_at` datetime(3) NULL, `retired_at` datetime(3) NULL, `draft_guard` tinyint(4) NULL, PRIMARY KEY(`version_id`), KEY ga_i1(`based_on_version_id`), KEY ga_i2(`template_id`, `status`), KEY ga_i3(`template_id`, `version_label`), KEY ga_i4(`template_id`, `draft_guard`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_t_yeast_profiles`(`yeast_profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL, `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL, `created_at` datetime(3) NOT NULL, PRIMARY KEY(`yeast_profile_id`)) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_v_current_session_timing`(`timing_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `timing_field` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `revision_no` int(11) NULL, `supersedes_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `value_at` datetime(3) NULL, `source` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_current_session_timing` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_lifecycle`(`lifecycle_event_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `lifecycle` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `occurred_at` datetime(3) NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_lifecycle` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_all_session`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `batch_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `is_demo` tinyint(4) NULL, `created_at` datetime(3) NULL, `pitched_at` datetime(3)  NULL, `activity_started_at` datetime(3) NULL, `og` decimal(7, 5) NULL, `volume_l` decimal(10, 3) NULL, `yeast_profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `pitch_mode_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `pitch_temperature_c` decimal(8, 3) NULL, `lifecycle` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `lifecycle_at` datetime(3) NULL, `completed_at` datetime(3)  NULL, `historical_ended_at` datetime(3) NULL, `is_historical` int(2) NULL, `domain_now` datetime(3)  NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_all_session` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_current_biological_visit_revision`(`visit_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `revision_no` int(11) NULL, `supersedes_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `started_at` datetime(3) NULL, `ended_at` datetime(3) NULL, `timing_source` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `confidence` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `revision_reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_current_biological_visit_revision` ADD INDEX ga_i1(`evaluation_id`);
 ALTER TABLE `ga_rb_v_current_biological_visit_revision` ADD INDEX ga_i2(`visit_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_biological_visit_timing`(`visit_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `revision_no` int(11) NULL, `supersedes_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `started_at` datetime(3) NULL, `ended_at` datetime(3)  NULL, `timing_source` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `confidence` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `revision_reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `visit_seq` bigint(20) unsigned NULL, `duration_seconds` bigint(21) NULL, `duration_display` varchar(35) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `started_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `ended_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_biological_visit_timing` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_biological_visit_timing` ADD INDEX ga_i2(`evaluation_id`);
 ALTER TABLE `ga_rb_v_biological_visit_timing` ADD INDEX ga_i3(`visit_id`);
 ALTER TABLE `ga_rb_v_biological_visit_timing` ADD INDEX ga_i4(`session_id`, `phase_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_active_analysis_biological_markers`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `label` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `started_at` datetime(3) NULL, `ended_at` datetime(3)  NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_active_analysis_biological_markers` ADD INDEX ga_i1(`session_id`, `graph_id`);
 ALTER TABLE `ga_rb_v_active_analysis_biological_markers` ADD INDEX ga_i2(`session_id`);
 ALTER TABLE `ga_rb_v_active_analysis_biological_markers` ADD INDEX ga_i3(`session_id`, `phase_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_current_process_visit_revision`(`visit_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `revision_no` int(11) NULL, `supersedes_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `started_at` datetime(3) NULL, `ended_at` datetime(3) NULL, `timing_source` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `revision_reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_current_process_visit_revision` ADD INDEX ga_i1(`visit_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_process_visit_timing`(`visit_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `revision_no` int(11) NULL, `supersedes_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `started_at` datetime(3) NULL, `ended_at` datetime(3)  NULL, `timing_source` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `revision_reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `visit_seq` bigint(20) unsigned NULL, `duration_seconds` bigint(21) NULL, `duration_display` varchar(35) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `started_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `ended_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_process_visit_timing` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_process_visit_timing` ADD INDEX ga_i2(`visit_id`);
 ALTER TABLE `ga_rb_v_process_visit_timing` ADD INDEX ga_i3(`session_id`, `process_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_active_analysis_process_markers`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `label` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `started_at` datetime(3) NULL, `ended_at` datetime(3)  NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_active_analysis_process_markers` ADD INDEX ga_i1(`session_id`, `graph_id`);
 ALTER TABLE `ga_rb_v_active_analysis_process_markers` ADD INDEX ga_i2(`session_id`);
 ALTER TABLE `ga_rb_v_active_analysis_process_markers` ADD INDEX ga_i3(`session_id`, `process_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_current_session`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `batch_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `is_demo` tinyint(4) NULL, `created_at` datetime(3) NULL, `pitched_at` datetime(3)  NULL, `activity_started_at` datetime(3) NULL, `og` decimal(7, 5) NULL, `volume_l` decimal(10, 3) NULL, `yeast_profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `pitch_mode_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `pitch_temperature_c` decimal(8, 3) NULL, `lifecycle` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `lifecycle_at` datetime(3) NULL, `completed_at` datetime(3)  NULL, `historical_ended_at` datetime(3) NULL, `is_historical` int(2) NULL, `domain_now` datetime(3)  NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_current_session` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_active_session`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `batch_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `is_demo` tinyint(4) NULL, `created_at` datetime(3) NULL, `pitched_at` datetime(3)  NULL, `activity_started_at` datetime(3) NULL, `og` decimal(7, 5) NULL, `volume_l` decimal(10, 3) NULL, `yeast_profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `pitch_mode_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `pitch_temperature_c` decimal(8, 3) NULL, `historical_ended_at` datetime(3) NULL, `is_historical` int(2) NULL, `domain_now` datetime(3)  NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_active_session` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_current_biological_criterion_revision`(`criterion_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `revision_no` int(11) NULL, `supersedes_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `action` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `confirmed` tinyint(4) NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_current_biological_criterion_revision` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_current_biological_criterion_revision` ADD INDEX ga_i2(`criterion_id`);
 ALTER TABLE `ga_rb_v_current_biological_criterion_revision` ADD INDEX ga_i3(`criterion_revision_id`);
 ALTER TABLE `ga_rb_v_current_biological_criterion_revision` ADD INDEX ga_i4(`session_id`, `phase_id`, `criterion_id`);
 ALTER TABLE `ga_rb_v_current_biological_criterion_revision` ADD INDEX ga_i5(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_current_process_criterion_revision`(`criterion_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `revision_no` int(11) NULL, `supersedes_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `action` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `confirmed` tinyint(4) NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_current_process_criterion_revision` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_current_process_criterion_revision` ADD INDEX ga_i2(`criterion_id`);
 ALTER TABLE `ga_rb_v_current_process_criterion_revision` ADD INDEX ga_i3(`criterion_revision_id`);
 ALTER TABLE `ga_rb_v_current_process_criterion_revision` ADD INDEX ga_i4(`session_id`, `criterion_id`);
 ALTER TABLE `ga_rb_v_current_process_criterion_revision` ADD INDEX ga_i5(`session_id`, `process_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_effective_biological_criterion_parameters`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `parameter_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `data_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `real_value` decimal(18, 6) NULL, `integer_value` bigint(20) NULL, `boolean_value` tinyint(4) NULL, `text_value` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `is_unset` int(4) NULL, `criterion_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_effective_biological_criterion_parameters` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_effective_biological_criterion_parameters` ADD INDEX ga_i2(`criterion_id`);
 ALTER TABLE `ga_rb_v_effective_biological_criterion_parameters` ADD INDEX ga_i3(`criterion_revision_id`, `parameter_id`);
 ALTER TABLE `ga_rb_v_effective_biological_criterion_parameters` ADD INDEX ga_i4(`session_id`, `phase_id`, `criterion_id`);
 ALTER TABLE `ga_rb_v_effective_biological_criterion_parameters` ADD INDEX ga_i5(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_effective_process_criterion_parameters`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `parameter_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `data_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `real_value` decimal(18, 6) NULL, `integer_value` bigint(20) NULL, `boolean_value` tinyint(4) NULL, `text_value` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `is_unset` int(4) NULL, `criterion_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_effective_process_criterion_parameters` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_effective_process_criterion_parameters` ADD INDEX ga_i2(`criterion_id`);
 ALTER TABLE `ga_rb_v_effective_process_criterion_parameters` ADD INDEX ga_i3(`criterion_revision_id`, `parameter_id`);
 ALTER TABLE `ga_rb_v_effective_process_criterion_parameters` ADD INDEX ga_i4(`session_id`, `criterion_id`);
 ALTER TABLE `ga_rb_v_effective_process_criterion_parameters` ADD INDEX ga_i5(`session_id`, `process_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_analysis_requirements`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `owner_type` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `role_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `minimum_value` decimal(18, 6) NULL, `maximum_value` decimal(18, 6) NULL, `met_at` datetime(3)  NULL, `owner_display` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `owner_type_display` varchar(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `role_display` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `requirement_display` varchar(180) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `met_at_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `met_status_display` varchar(29) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_analysis_requirements` ADD INDEX ga_i1(`session_id`, `graph_id`);
 ALTER TABLE `ga_rb_v_session_analysis_requirements` ADD INDEX ga_i2(`session_id`);
 ALTER TABLE `ga_rb_v_session_analysis_requirements` ADD INDEX ga_i3(`criterion_id`);
 ALTER TABLE `ga_rb_v_session_analysis_requirements` ADD INDEX ga_i4(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_active_analysis_requirements`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `owner_type` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `role_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `minimum_value` decimal(18, 6) NULL, `maximum_value` decimal(18, 6) NULL, `met_at` datetime(3)  NULL, `owner_display` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `owner_type_display` varchar(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `role_display` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `requirement_display` varchar(180) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `met_at_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `met_status_display` varchar(29) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_active_analysis_requirements` ADD INDEX ga_i1(`session_id`, `graph_id`);
 ALTER TABLE `ga_rb_v_active_analysis_requirements` ADD INDEX ga_i2(`session_id`);
 ALTER TABLE `ga_rb_v_active_analysis_requirements` ADD INDEX ga_i3(`criterion_id`);
 ALTER TABLE `ga_rb_v_active_analysis_requirements` ADD INDEX ga_i4(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_current_biological_visit`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `visit_no` bigint(21) NULL, `phase_order` int(11) NULL, `phase_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `visit_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `revision_no` int(11) NULL, `started_at` datetime(3) NULL, `ended_at` datetime(3) NULL, `timing_source` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `confidence` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `revision_reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `duration_seconds` bigint(21) NULL, `visit_seq` bigint(20) unsigned NULL, `session_rn` bigint(21) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_current_biological_visit` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_current_biological_visit` ADD INDEX ga_i2(`evaluation_id`);
 ALTER TABLE `ga_rb_v_current_biological_visit` ADD INDEX ga_i3(`visit_id`);
 ALTER TABLE `ga_rb_v_current_biological_visit` ADD INDEX ga_i4(`session_id`, `phase_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_current_fermentation_target`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `expected_attenuation_min_percent` decimal(8, 4) NULL, `expected_attenuation_max_percent` decimal(8, 4) NULL, `expected_fg_min` decimal(7, 5) NULL, `expected_fg_max` decimal(7, 5) NULL, `source` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `target_revision_id` binary(0) NULL, `revision_no` binary(0) NULL, `action` binary(0) NULL, `note` binary(0) NULL, `operation_id` binary(0) NULL, `created_at` datetime(3) NULL, `effective_at` datetime(3) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_current_fermentation_target` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_current_process_visit`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `visit_no` bigint(21) NULL, `process_order` int(11) NULL, `process_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `visit_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `revision_no` int(11) NULL, `started_at` datetime(3) NULL, `ended_at` datetime(3) NULL, `timing_source` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `revision_reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `duration_seconds` bigint(21) NULL, `visit_seq` bigint(20) unsigned NULL, `session_rn` bigint(21) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_current_process_visit` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_current_process_visit` ADD INDEX ga_i2(`visit_id`);
 ALTER TABLE `ga_rb_v_current_process_visit` ADD INDEX ga_i3(`session_id`, `process_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_latest_biological_evaluation`(`evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `candidate_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `active_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluated_at` datetime(3) NULL, `outcome` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `confidence` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `data_quality` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `summary` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `engine_version` varchar(96) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NULL, `rn` bigint(21) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_latest_biological_evaluation` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_latest_biological_evaluation` ADD INDEX ga_i2(`evaluation_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_current_observation_revision`(`observation_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `observation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `revision_no` int(11) NULL, `supersedes_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `status` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `recorded_at` datetime(3) NULL, `measurement_method_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `measured_sg` decimal(7, 5) NULL, `sample_temperature_c` decimal(8, 3) NULL, `calibration_temperature_c` decimal(8, 3) NULL, `corrected_sg` decimal(7, 5) NULL, `manual_temperature_c` decimal(8, 3) NULL, `pressure_bar` decimal(8, 4) NULL, `cooler_setpoint_c` decimal(8, 3) NULL, `cooler_calibration_offset_c` decimal(8, 3) NULL, `estimated_abv_percent` decimal(8, 3) NULL, `estimated_finished_abv_percent` decimal(8, 3) NULL, `airlock_activity` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `acetaldehyde_level` int(11) NULL, `diacetyl_level` int(11) NULL, `wort_like_level` int(11) NULL, `sulfur_so2_level` int(11) NULL, `sulfur_h2s_level` int(11) NULL, `clarity_level` int(11) NULL, `settling_yeast_level` int(11) NULL, `settling_minutes` decimal(12, 3) NULL, `user_conclusion` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `calculated_conclusion` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `process_gate_status` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `corrected_sg_model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `abv_now_model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `estimated_finished_abv_model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `actual_og_used` decimal(7, 5) NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `revision_reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_current_observation_revision` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_latest_observation`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `observation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `observation_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `revision_no` int(11) NULL, `recorded_at` datetime(3) NULL, `measurement_method_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `measured_sg` decimal(7, 5) NULL, `corrected_sg` decimal(7, 5) NULL, `manual_temperature_c` decimal(8, 3) NULL, `pressure_bar` decimal(8, 4) NULL, `cooler_setpoint_c` decimal(8, 3) NULL, `cooler_calibration_offset_c` decimal(8, 3) NULL, `estimated_abv_percent` decimal(8, 3) NULL, `estimated_finished_abv_percent` decimal(8, 3) NULL, `airlock_activity` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `user_conclusion` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `calculated_conclusion` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `process_gate_status` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `rn` bigint(21) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_latest_observation` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_latest_process_evaluation`(`evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `candidate_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `active_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `observation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `observation_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluated_at` datetime(3) NULL, `readiness` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `data_quality` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `summary` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `recommended_temperature_c` decimal(8, 3) NULL, `recommended_pressure_bar` decimal(8, 4) NULL, `engine_version` varchar(96) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NULL, `rn` bigint(21) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_latest_process_evaluation` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_latest_process_evaluation` ADD INDEX ga_i2(`evaluation_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_archive_status`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `can_prepare_new` int(1) NULL, `prepare_action_display` varchar(24) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `archive_attempt_no` bigint(20) unsigned NULL, `archive_requested_at` datetime(3) NULL, `archive_error_message` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `archive_status` varchar(14) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `archive_status_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_archive_status` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_all_session_summary`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `batch_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `is_demo` tinyint(4) NULL, `is_historical` int(2) NULL, `historical_ended_at` datetime(3) NULL, `domain_now` datetime(3)  NULL, `pitched_at` datetime(3)  NULL, `activity_started_at` datetime(3) NULL, `completed_at` datetime(3)  NULL, `lifecycle` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `lifecycle_at` datetime(3) NULL, `archive_status` varchar(14) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `archive_status_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `archive_error_message` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `archive_attempt_no` bigint(20) unsigned NULL, `archive_requested_at` datetime(3) NULL, `can_prepare_new` int(1) NULL, `prepare_action_display` varchar(24) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `og` decimal(7, 5) NULL, `volume_l` decimal(10, 3) NULL, `expected_attenuation_min_percent` decimal(8, 4) NULL, `expected_attenuation_max_percent` decimal(8, 4) NULL, `expected_fg_min` decimal(7, 5) NULL, `expected_fg_max` decimal(7, 5) NULL, `expected_attenuation_display` varchar(19) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `expected_fg_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `current_process_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_process_order` int(11) NULL, `current_process_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `current_process_started_at` datetime(3) NULL, `current_process_ended_at` datetime(3) NULL, `current_biological_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_biological_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_biological_phase_order` int(11) NULL, `current_biological_phase_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `current_biological_started_at` datetime(3) NULL, `current_biological_ended_at` datetime(3) NULL, `latest_observation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `latest_observation_at` datetime(3) NULL, `latest_manual_sg` decimal(7, 5) NULL, `latest_process_evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `latest_process_readiness` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `recommended_next_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `recommended_temperature_c` decimal(8, 3) NULL, `recommended_pressure_bar` decimal(8, 4) NULL, `latest_biological_evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `latest_biological_candidate_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `latest_biological_confidence` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_all_session_summary` ADD INDEX ga_i1(`session_id`);
END//
CREATE PROCEDURE ga_init_read_basis_part_4() BEGIN
 CREATE TEMPORARY TABLE `ga_rb_v_current_metric_value`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluation_id` varchar(137) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `actual_value` decimal(24, 9) NULL, `actual_text` binary(0) NULL, `actual_display` varchar(126) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `evaluation_status` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `status_display` varchar(73) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `measured_at` datetime(3) NULL, `evaluated_at` datetime(3) NULL, `evaluation_created_at` datetime(3) NULL, `source_scope` varchar(8) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `rn` bigint(21) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_current_metric_value` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_current_metric_value` ADD INDEX ga_i2(`session_id`, `metric_id`);
 ALTER TABLE `ga_rb_v_current_metric_value` ADD INDEX ga_i3(`evaluation_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_current_process_candidate_evaluation`(`evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `candidate_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `active_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `observation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `observation_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluated_at` datetime(3) NULL, `readiness` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `data_quality` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `summary` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `recommended_temperature_c` decimal(8, 3) NULL, `recommended_pressure_bar` decimal(8, 4) NULL, `engine_version` varchar(96) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NULL, `candidate_process_order` int(11) NULL, `candidate_process_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `historical_replay_auto_transition_allowed` tinyint(4) NULL, `rn` bigint(21) NULL, `operator_status_display` varchar(195) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_current_process_candidate_evaluation` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_current_process_candidate_evaluation` ADD INDEX ga_i2(`evaluation_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_current_session_summary`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `batch_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `is_demo` tinyint(4) NULL, `is_historical` int(2) NULL, `historical_ended_at` datetime(3) NULL, `domain_now` datetime(3)  NULL, `pitched_at` datetime(3)  NULL, `activity_started_at` datetime(3) NULL, `completed_at` datetime(3)  NULL, `lifecycle` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `lifecycle_at` datetime(3) NULL, `archive_status` varchar(14) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `archive_status_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `archive_error_message` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `archive_attempt_no` bigint(20) unsigned NULL, `archive_requested_at` datetime(3) NULL, `can_prepare_new` int(1) NULL, `prepare_action_display` varchar(24) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `og` decimal(7, 5) NULL, `volume_l` decimal(10, 3) NULL, `expected_attenuation_min_percent` decimal(8, 4) NULL, `expected_attenuation_max_percent` decimal(8, 4) NULL, `expected_fg_min` decimal(7, 5) NULL, `expected_fg_max` decimal(7, 5) NULL, `expected_attenuation_display` varchar(19) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `expected_fg_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `current_process_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_process_order` int(11) NULL, `current_process_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `current_process_started_at` datetime(3) NULL, `current_process_ended_at` datetime(3) NULL, `current_biological_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_biological_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_biological_phase_order` int(11) NULL, `current_biological_phase_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `current_biological_started_at` datetime(3) NULL, `current_biological_ended_at` datetime(3) NULL, `latest_observation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `latest_observation_at` datetime(3) NULL, `latest_manual_sg` decimal(7, 5) NULL, `latest_process_evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `latest_process_readiness` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `recommended_next_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `recommended_temperature_c` decimal(8, 3) NULL, `recommended_pressure_bar` decimal(8, 4) NULL, `latest_biological_evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `latest_biological_candidate_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `latest_biological_confidence` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_current_session_summary` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_measurement_data_gaps`(`gap_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `source` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `gap_started_at` datetime(3) NULL, `gap_ended_at` datetime(3)  NULL, `duration_seconds` bigint(21) NULL, `threshold_seconds` int(11) NULL, `detected_at` datetime(3) NULL, `created_at` datetime(3) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_measurement_data_gaps` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_current_measurement_source_configuration`(`configuration_id` bigint(20) unsigned NULL, `source_profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `parent_configuration_id` bigint(20) unsigned NULL, `parent_key` bigint(20) unsigned NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NULL) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_v_source_configuration_values`(`configuration_id` bigint(20) unsigned NULL, `sg_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `temperature_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `heartbeat_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `rssi_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `pressure_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_v_measurement_source_profiles`(`source_profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `poll_interval_seconds` int(11) NULL, `gap_threshold_seconds` int(11) NULL, `fresh_age_minutes` int(11) NULL, `stale_age_minutes` int(11) NULL, `status` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NULL, `updated_at` datetime(3) NULL, `configuration_id` bigint(20) unsigned NULL, `sg_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `temperature_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `heartbeat_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `rssi_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `pressure_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_v_current_measurement_statistics_hourly`(`statistic_seq` bigint(20) unsigned NULL, `statistic_import_id` char(64) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `start_at` datetime(3) NULL, `end_at` datetime(3) NULL, `sg_min` double NULL, `sg_mean` double NULL, `sg_max` double NULL, `temperature_min_c` double NULL, `temperature_mean_c` double NULL, `temperature_max_c` double NULL, `rssi_min_dbm` double NULL, `rssi_mean_dbm` double NULL, `rssi_max_dbm` double NULL, `created_at` datetime(3) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_current_measurement_statistics_hourly` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_import_coverage`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `source_started_at` datetime(3) NULL, `processed_to` datetime(3) NULL, `historical_ended_at` datetime(3) NULL, `detail_count` bigint(21) NULL, `detail_first_at` datetime(3)  NULL, `detail_last_at` datetime(3)  NULL, `hourly_count` bigint(21) NULL, `hourly_first_at` datetime(3)  NULL, `hourly_last_at` datetime(3)  NULL, `gap_count` bigint(21) NULL, `counts_display` varchar(122) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `coverage_display` varchar(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `summary_display` varchar(146) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_import_coverage` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_current_session_measurement_source_configuration`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `configuration_id` bigint(20) unsigned NULL, `effective_from` datetime(3) NULL, `profile_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_current_session_measurement_source_configuration` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_source_configuration_values`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `configuration_id` bigint(20) unsigned NULL, `sg_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `temperature_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `heartbeat_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `rssi_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `pressure_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `signal_bindings` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_source_configuration_values` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_measurement_source_profiles`(`source_profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `poll_interval_seconds` int(11) NULL, `gap_threshold_seconds` int(11) NULL, `fresh_age_minutes` int(11) NULL, `stale_age_minutes` int(11) NULL, `status` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NULL, `updated_at` datetime(3) NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `configuration_id` bigint(20) unsigned NULL, `configuration_started_at` datetime(3) NULL, `sg_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `temperature_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `heartbeat_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `rssi_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `pressure_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `signal_bindings` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `next_configuration_at` datetime(3)  NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_measurement_source_profiles` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_measurement_source_status`(`state` varchar(9) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `message` varchar(76) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `sg_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `temperature_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `heartbeat_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `rssi_entity_id` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NULL, `poll_interval_seconds` int(11) NULL, `gap_threshold_seconds` int(11) NULL, `fresh_age_minutes` int(11) NULL, `stale_age_minutes` int(11) NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `is_demo` tinyint(4) NULL, `batch_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `lifecycle` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_started_at` datetime(3) NULL, `last_import_cutoff_at` datetime(3) NULL, `last_success_at` datetime(3) NULL, `last_error` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `latest_bucket_at` datetime(3) NULL, `latest_sample_count` int(11) NULL, `sg_min` decimal(7, 5) NULL, `sg_mean` decimal(7, 5) NULL, `sg_median` decimal(7, 5) NULL, `sg_max` decimal(7, 5) NULL, `temperature_mean_c` decimal(8, 3) NULL, `rssi_mean_dbm` decimal(8, 3) NULL, `open_gap_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `open_gap_started_at` datetime(3) NULL, `measurement_age_minutes` bigint(21) NULL, `measurement_age_state` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `latest_measurement_state` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `data_quality_display` varchar(18) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `updated_at` datetime(3)  NULL, `latest_measurement_at_display` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `latest_bucket_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `latest_sg_display` varchar(17) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `latest_sg_detail_display` varchar(52) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `latest_temperature_display` varchar(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `latest_rssi_display` varchar(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `import_cutoff_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `last_success_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `poll_interval_display` varchar(13) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `gap_threshold_display` varchar(13) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `gap_status_display` varchar(23) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `gap_started_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `last_error_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `authority` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `import_counts_display` varchar(122) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `import_coverage_display` varchar(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `import_summary_display` varchar(146) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_measurement_source_status` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_report_summary`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `batch_display` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `yeast_display` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `expected_attenuation_display` varchar(19) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `expected_fg_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `pitched_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `biology_display` varchar(386) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `process_display` varchar(386) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `latest_tilt_sg_display` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `attenuation_display` varchar(126) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `sg_rate_display` varchar(126) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `sg_rate_basis_display` varchar(73) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `attenuation_basis_display` varchar(73) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `stability_24h_display` varchar(126) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `stability_48h_display` varchar(126) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `stability_24h_basis_display` varchar(73) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `stability_48h_basis_display` varchar(73) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `og_volume_display` varchar(27) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `elapsed_display` varchar(42) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `phase_duration_display` varchar(38) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `process_duration_display` varchar(47) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `abv_now_display` varchar(54) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `abv_basis_display` varchar(73) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `manual_measurements_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `latest_manual_sg_display` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `notes_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `datapoints_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `next_process_display` varchar(195) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `process_evaluated_display` varchar(29) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `active_report_url` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `active_report_generated_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_report_summary` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_active_session_report_summary`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `batch_display` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `yeast_display` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `expected_attenuation_display` varchar(19) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `expected_fg_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `pitched_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `biology_display` varchar(386) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `process_display` varchar(386) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `latest_tilt_sg_display` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `attenuation_display` varchar(126) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `sg_rate_display` varchar(126) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `sg_rate_basis_display` varchar(73) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `attenuation_basis_display` varchar(73) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `stability_24h_display` varchar(126) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `stability_48h_display` varchar(126) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `stability_24h_basis_display` varchar(73) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `stability_48h_basis_display` varchar(73) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `og_volume_display` varchar(27) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `elapsed_display` varchar(42) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `phase_duration_display` varchar(38) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `process_duration_display` varchar(47) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `abv_now_display` varchar(54) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `abv_basis_display` varchar(73) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `manual_measurements_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `latest_manual_sg_display` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `notes_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `datapoints_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `next_process_display` varchar(195) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `process_evaluated_display` varchar(29) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `active_report_url` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `active_report_generated_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_active_session_report_summary` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_active_session_summary`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `batch_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `is_demo` tinyint(4) NULL, `is_historical` int(2) NULL, `historical_ended_at` datetime(3) NULL, `domain_now` datetime(3)  NULL, `pitched_at` datetime(3)  NULL, `activity_started_at` datetime(3) NULL, `completed_at` datetime(3)  NULL, `lifecycle` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `lifecycle_at` datetime(3) NULL, `archive_status` varchar(14) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `archive_status_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `archive_error_message` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `archive_attempt_no` bigint(20) unsigned NULL, `archive_requested_at` datetime(3) NULL, `can_prepare_new` int(1) NULL, `prepare_action_display` varchar(24) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `og` decimal(7, 5) NULL, `volume_l` decimal(10, 3) NULL, `expected_attenuation_min_percent` decimal(8, 4) NULL, `expected_attenuation_max_percent` decimal(8, 4) NULL, `expected_fg_min` decimal(7, 5) NULL, `expected_fg_max` decimal(7, 5) NULL, `expected_attenuation_display` varchar(19) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `expected_fg_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `current_process_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_process_order` int(11) NULL, `current_process_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `current_process_started_at` datetime(3) NULL, `current_process_ended_at` datetime(3) NULL, `current_biological_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_biological_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_biological_phase_order` int(11) NULL, `current_biological_phase_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `current_biological_started_at` datetime(3) NULL, `current_biological_ended_at` datetime(3) NULL, `latest_observation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `latest_observation_at` datetime(3) NULL, `latest_manual_sg` decimal(7, 5) NULL, `latest_process_evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `latest_process_readiness` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `recommended_next_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `recommended_temperature_c` decimal(8, 3) NULL, `recommended_pressure_bar` decimal(8, 4) NULL, `latest_biological_evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `latest_biological_candidate_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `latest_biological_confidence` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_active_session_summary` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_active_technical_issues`(`event_seq` bigint(20) unsigned NULL, `event_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `schema_version` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `occurred_at` datetime(3) NULL, `severity` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `event_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `code` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `issue_key` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `subsystem` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_component` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_node_id` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_node_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_type` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `process_step` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `correlation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `message` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `recoverable` tinyint(4) NULL, `blocks_operation` tinyint(4) NULL, `related_event_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NULL, `rn` bigint(21) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_active_technical_issues` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_biological_evaluation_criterion_requirement`(`evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `requirement_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_biological_evaluation_criterion_requirement` ADD INDEX ga_i1(`evaluation_id`, `criterion_id`);
 ALTER TABLE `ga_rb_v_biological_evaluation_criterion_requirement` ADD INDEX ga_i2(`criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_effective_biological_criterion_requirement`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `requirement_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_effective_biological_criterion_requirement` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_effective_biological_criterion_requirement` ADD INDEX ga_i2(`criterion_id`);
 ALTER TABLE `ga_rb_v_effective_biological_criterion_requirement` ADD INDEX ga_i3(`session_id`, `phase_id`, `criterion_id`);
 ALTER TABLE `ga_rb_v_effective_biological_criterion_requirement` ADD INDEX ga_i4(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_template_biological_criterion_requirement`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `requirement_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_template_biological_criterion_requirement` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_template_biological_criterion_requirement` ADD INDEX ga_i2(`criterion_id`);
 ALTER TABLE `ga_rb_v_template_biological_criterion_requirement` ADD INDEX ga_i3(`session_id`, `phase_id`, `criterion_id`);
 ALTER TABLE `ga_rb_v_template_biological_criterion_requirement` ADD INDEX ga_i4(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_biological_evaluation_criterion_read_model`(`evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `applied_exception_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_order` int(11) NULL, `role_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `met` tinyint(4) NULL, `valid` tinyint(4) NULL, `evaluation_status` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `actual_value` decimal(18, 6) NULL, `actual_text` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `measured_at` datetime(3) NULL, `source` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `data_window_started_at` datetime(3) NULL, `data_window_ended_at` datetime(3) NULL, `requested_window_seconds` int(11) NULL, `sample_count` int(11) NULL, `coverage_seconds` int(11) NULL, `latest_sample_at` datetime(3) NULL, `explanation` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NULL, `evaluated_at` datetime(3) NULL, `evaluation_created_at` datetime(3) NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `exception_allowed` tinyint(4) NULL, `exception_type` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `exception_note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `exception_register_allowed` int(2) NULL, `metric_label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `metric_unit` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `requirement_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `template_requirement_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `effective_requirement_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `criterion_basis_current` int(1) NULL, `status_display` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `actual_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `data_window_display` varchar(67) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_biological_evaluation_criterion_read_model` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_biological_evaluation_criterion_read_model` ADD INDEX ga_i2(`session_id`, `metric_id`);
 ALTER TABLE `ga_rb_v_biological_evaluation_criterion_read_model` ADD INDEX ga_i3(`evaluation_id`, `criterion_id`);
 ALTER TABLE `ga_rb_v_biological_evaluation_criterion_read_model` ADD INDEX ga_i4(`criterion_revision_id`);
 ALTER TABLE `ga_rb_v_biological_evaluation_criterion_read_model` ADD INDEX ga_i5(`session_id`, `phase_id`, `criterion_id`);
 ALTER TABLE `ga_rb_v_biological_evaluation_criterion_read_model` ADD INDEX ga_i6(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_biological_transition_evidence`(`transition_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `transitioned_at` datetime(3) NULL, `from_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `to_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `transition_source` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `transition_confidence` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `transition_reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `candidate_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `active_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluated_at` datetime(3) NULL, `outcome` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `confidence` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `data_quality` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `summary` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `engine_version` varchar(96) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `evaluation_created_at` datetime(3) NULL, `candidate_phase_order` int(11) NULL, `candidate_phase_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_biological_transition_evidence` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_biological_transition_evidence` ADD INDEX ga_i2(`evaluation_id`);
END//
CREATE PROCEDURE ga_init_read_basis_part_5() BEGIN
 CREATE TEMPORARY TABLE `ga_rb_v_criterion_correction_receipts`(`scope` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `revision_no` int(11) NULL, `action` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `note` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3)  NULL, `evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `review_state` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `review_message` varchar(87) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_criterion_correction_receipts` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_criterion_correction_receipts` ADD INDEX ga_i2(`evaluation_id`, `criterion_id`);
 ALTER TABLE `ga_rb_v_criterion_correction_receipts` ADD INDEX ga_i3(`criterion_revision_id`);
 ALTER TABLE `ga_rb_v_criterion_correction_receipts` ADD INDEX ga_i4(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_current_biological_candidate_evaluation`(`evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `candidate_phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `active_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluated_at` datetime(3) NULL, `outcome` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `confidence` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `data_quality` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `summary` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `engine_version` varchar(96) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NULL, `candidate_phase_order` int(11) NULL, `candidate_phase_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `rn` bigint(21) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_current_biological_candidate_evaluation` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_current_biological_candidate_evaluation` ADD INDEX ga_i2(`evaluation_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_process_guidance_counts`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `required_total` bigint(21) NULL, `required_met` bigint(21) NULL, `required_handled` bigint(21) NULL, `exception_count` bigint(21) NULL, `outdated_criteria` bigint(21) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_process_guidance_counts` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_process_guidance_counts` ADD INDEX ga_i2(`evaluation_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_process_guidance_effective`(`evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `current_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `candidate_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `active_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `observation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `observation_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluated_at` datetime(3) NULL, `readiness` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `data_quality` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `summary` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `recommended_temperature_c` decimal(8, 3) NULL, `recommended_pressure_bar` decimal(8, 4) NULL, `engine_version` varchar(96) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NULL, `candidate_process_order` int(11) NULL, `candidate_process_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `historical_replay_auto_transition_allowed` tinyint(4) NULL, `rn` bigint(21) NULL, `operator_status_display` varchar(195) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `required_total` bigint(21) NULL, `required_met` bigint(21) NULL, `required_handled` bigint(21) NULL, `blocking_required` bigint(22) NULL, `exception_count` bigint(21) NULL, `outdated_criteria` bigint(21) NULL, `effective_readiness` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_process_guidance_effective` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_process_guidance_effective` ADD INDEX ga_i2(`evaluation_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_current_process_guidance`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `raw_readiness` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `readiness` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `next_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `next_process_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `trigger_summary` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `reason` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `required_total` bigint(21) NULL, `required_met` bigint(21) NULL, `required_handled` bigint(21) NULL, `blocking_required` bigint(22) NULL, `exception_count` bigint(21) NULL, `recommended_temperature_c` decimal(8, 3) NULL, `recommended_pressure_bar` decimal(8, 4) NULL, `evaluation_status` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_current_process_guidance` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_current_process_guidance` ADD INDEX ga_i2(`evaluation_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_graph_display_selection`(`selection_seq` bigint(20) unsigned NULL, `source_kind` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `reference_profile_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `reference_session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `interval_seconds` int(11) NULL, `window_hours` int(11) NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `selected_at` datetime(3) NULL) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_v_session_measurement_series`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `bucket_at` datetime(3)  NULL, `interval_ended_at` datetime(3)  NULL, `sample_count` int(11) NULL, `sg_min` double NULL, `sg_mean` double NULL, `sg_median` decimal(7, 5) NULL, `sg_value` double NULL, `sg_max` double NULL, `temperature_min_c` double NULL, `temperature_mean_c` double NULL, `temperature_max_c` double NULL, `pressure_min_bar` decimal(8, 4) NULL, `pressure_mean_bar` decimal(8, 4) NULL, `pressure_max_bar` decimal(8, 4) NULL, `rssi_min_dbm` double NULL, `rssi_mean_dbm` double NULL, `rssi_max_dbm` double NULL, `source_kind` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_display` varchar(35) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `interval_seconds` int(11) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_measurement_series` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_dashboard_graph_labels`(`selection_seq` bigint(20) unsigned NULL, `graph_basis_display` varchar(82) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `measurement_source_labels` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `comparison_display` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 CREATE TEMPORARY TABLE `ga_rb_v_graph_reference_bands`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `series_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `minimum_value` decimal(7, 5) NULL, `maximum_value` decimal(7, 5) NULL, `line_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_opacity` decimal(4, 3) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_graph_reference_bands` ADD INDEX ga_i1(`session_id`, `graph_id`, `series_id`);
 ALTER TABLE `ga_rb_v_graph_reference_bands` ADD INDEX ga_i2(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_analysis_series`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `series_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `sort_order` int(11) NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `minimum_samples` int(11) NULL, `minimum_coverage_fraction` decimal(8, 6) NULL, `warmup_minutes` int(11) NULL, `valid_minimum_value` decimal(18, 6) NULL, `valid_maximum_value` decimal(18, 6) NULL, `provisional_allowed` tinyint(4) NULL, `provisional_minimum_samples` int(11) NULL, `provisional_minimum_span_minutes` decimal(18, 6) NULL, `render_mode` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_model` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_opacity` decimal(4, 3) NULL, `standard_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `provisional_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `standard_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `provisional_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `actual_value_display` varchar(126) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `sample_at` datetime(3) NULL, `basis_pitched_at` datetime(3) NULL, `source_observation_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `basis_revision_key` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `actual_value` decimal(24, 9) NULL, `range_min_value` decimal(24, 9) NULL, `range_max_value` decimal(24, 9) NULL, `measured_at` datetime(3) NULL, `sample_count` int(11) NULL, `window_started_at` datetime(3) NULL, `window_ended_at` datetime(3) NULL, `requested_window_seconds` int(11) NULL, `coverage_seconds` int(11) NULL, `value_source_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `value_status` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `standard_basis_met` tinyint(4) NULL, `value_status_display` varchar(13) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_color` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `basis_display` varchar(106) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `coverage_fraction` decimal(14, 4) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_analysis_series` ADD INDEX ga_i1(`session_id`, `graph_id`, `series_id`, `sample_at`);
 ALTER TABLE `ga_rb_v_session_analysis_series` ADD INDEX ga_i2(`session_id`, `metric_id`);
 ALTER TABLE `ga_rb_v_session_analysis_series` ADD INDEX ga_i3(`criterion_id`);
 ALTER TABLE `ga_rb_v_session_analysis_series` ADD INDEX ga_i4(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_graph_reference_analysis_series`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `series_id` varchar(139) CHARACTER SET ascii COLLATE ascii_bin NULL, `sort_order` int(11) NULL, `label` varchar(513) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `minimum_samples` int(11) NULL, `minimum_coverage_fraction` decimal(8, 6) NULL, `warmup_minutes` int(11) NULL, `valid_minimum_value` decimal(18, 6) NULL, `valid_maximum_value` decimal(18, 6) NULL, `provisional_allowed` tinyint(4) NULL, `provisional_minimum_samples` int(11) NULL, `provisional_minimum_span_minutes` decimal(18, 6) NULL, `render_mode` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_model` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_description` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_opacity` decimal(4, 3) NULL, `standard_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `provisional_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `standard_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `provisional_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `actual_value_display` varchar(126) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `sample_at` datetime(3)  NULL, `basis_pitched_at` datetime(3)  NULL, `source_observation_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `basis_revision_key` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `actual_value` decimal(24, 9) NULL, `range_min_value` decimal(24, 9) NULL, `range_max_value` decimal(24, 9) NULL, `measured_at` datetime(3)  NULL, `sample_count` int(11) NULL, `window_started_at` datetime(3)  NULL, `window_ended_at` datetime(3)  NULL, `requested_window_seconds` int(11) NULL, `coverage_seconds` int(11) NULL, `value_source_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `value_status` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `standard_basis_met` int(4) NULL, `value_status_display` varchar(13) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_color` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_dasharray` varchar(3) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `basis_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `coverage_fraction` decimal(14, 4) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_graph_reference_analysis_series` ADD INDEX ga_i1(`session_id`, `graph_id`, `series_id`, `sample_at`);
 ALTER TABLE `ga_rb_v_graph_reference_analysis_series` ADD INDEX ga_i2(`session_id`, `metric_id`);
 ALTER TABLE `ga_rb_v_graph_reference_analysis_series` ADD INDEX ga_i3(`criterion_id`);
 ALTER TABLE `ga_rb_v_graph_reference_analysis_series` ADD INDEX ga_i4(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_hourly_analysis_policy`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `series_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `sort_order` int(11) NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `minimum_samples` int(11) NULL, `minimum_coverage_fraction` decimal(8, 6) NULL, `warmup_minutes` int(11) NULL, `valid_minimum_value` decimal(18, 6) NULL, `valid_maximum_value` decimal(18, 6) NULL, `provisional_allowed` tinyint(4) NULL, `provisional_minimum_samples` int(11) NULL, `provisional_minimum_span_minutes` decimal(18, 6) NULL, `render_mode` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_model` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `standard_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `provisional_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `standard_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `provisional_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_opacity` decimal(4, 3) NULL, `created_at` datetime(3) NULL, `display_decimals` int(11) NULL, `unit` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `calculation_model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `window_hours` decimal(25, 6) NULL, `minimum_span_minutes` decimal(27, 6) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_hourly_analysis_policy` ADD INDEX ga_i1(`session_id`, `graph_id`, `series_id`);
 ALTER TABLE `ga_rb_v_session_hourly_analysis_policy` ADD INDEX ga_i2(`session_id`, `metric_id`);
 ALTER TABLE `ga_rb_v_session_hourly_analysis_policy` ADD INDEX ga_i3(`criterion_id`);
 ALTER TABLE `ga_rb_v_session_hourly_analysis_policy` ADD INDEX ga_i4(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_hourly_analysis_aggregate`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `series_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `sample_at` datetime(3)  NULL, `window_started_at` datetime(3)  NULL, `window_ended_at` datetime(3)  NULL, `sample_count` bigint(21) NULL, `coverage_seconds` bigint(21) NULL, `value_min` double NULL, `value_max` double NULL, `current_sg` double NULL, `first_sg` double NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_hourly_analysis_aggregate` ADD INDEX ga_i1(`session_id`, `graph_id`, `series_id`, `sample_at`);
 ALTER TABLE `ga_rb_v_session_hourly_analysis_aggregate` ADD INDEX ga_i2(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_hourly_analysis_values`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `series_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `sample_at` datetime(3)  NULL, `actual_value` double NULL, `sample_count` bigint(21) NULL, `coverage_seconds` bigint(21) NULL, `requested_window_seconds` decimal(29, 6) NULL, `window_started_at` datetime(3)  NULL, `window_ended_at` datetime(3)  NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_hourly_analysis_values` ADD INDEX ga_i1(`session_id`, `graph_id`, `series_id`, `sample_at`);
 ALTER TABLE `ga_rb_v_session_hourly_analysis_values` ADD INDEX ga_i2(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_hourly_analysis_series`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `series_id` varchar(138) CHARACTER SET ascii COLLATE ascii_bin NULL, `sort_order` int(11) NULL, `label` varchar(272) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `minimum_samples` int(11) NULL, `minimum_coverage_fraction` decimal(8, 6) NULL, `warmup_minutes` int(11) NULL, `valid_minimum_value` decimal(18, 6) NULL, `valid_maximum_value` decimal(18, 6) NULL, `provisional_allowed` tinyint(4) NULL, `provisional_minimum_samples` int(11) NULL, `provisional_minimum_span_minutes` decimal(18, 6) NULL, `render_mode` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_model` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_opacity` decimal(4, 3) NULL, `standard_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `provisional_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `standard_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `provisional_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `actual_value_display` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `sample_at` datetime(3)  NULL, `basis_pitched_at` datetime(3)  NULL, `source_observation_revision_id` binary(0) NULL, `basis_revision_key` varchar(9) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `actual_value` double NULL, `range_min_value` binary(0) NULL, `range_max_value` binary(0) NULL, `measured_at` datetime(3)  NULL, `sample_count` bigint(21) NULL, `window_started_at` datetime(3)  NULL, `window_ended_at` datetime(3)  NULL, `requested_window_seconds` decimal(29, 6) NULL, `coverage_seconds` bigint(21) NULL, `value_source_kind` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `value_status` varchar(8) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `standard_basis_met` int(1) NULL, `value_status_display` varchar(14) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_color` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_dasharray` varchar(3) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `basis_display` varchar(83) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `coverage_fraction` decimal(30, 4) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_hourly_analysis_series` ADD INDEX ga_i1(`session_id`, `graph_id`, `series_id`, `sample_at`);
 ALTER TABLE `ga_rb_v_session_hourly_analysis_series` ADD INDEX ga_i2(`session_id`, `metric_id`);
 ALTER TABLE `ga_rb_v_session_hourly_analysis_series` ADD INDEX ga_i3(`criterion_id`);
 ALTER TABLE `ga_rb_v_session_hourly_analysis_series` ADD INDEX ga_i4(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_primary_analysis_source`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `series_id` varchar(138) CHARACTER SET ascii COLLATE ascii_bin NULL, `sort_order` int(11) NULL, `label` varchar(272) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `minimum_samples` int(11) NULL, `minimum_coverage_fraction` decimal(8, 6) NULL, `warmup_minutes` int(11) NULL, `valid_minimum_value` decimal(18, 6) NULL, `valid_maximum_value` decimal(18, 6) NULL, `provisional_allowed` tinyint(4) NULL, `provisional_minimum_samples` int(11) NULL, `provisional_minimum_span_minutes` decimal(18, 6) NULL, `render_mode` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_model` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_description` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_opacity` decimal(4, 3) NULL, `standard_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `provisional_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `standard_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `provisional_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `actual_value_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `sample_at` datetime(3)  NULL, `basis_pitched_at` datetime(3)  NULL, `source_observation_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `basis_revision_key` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `actual_value` double NULL, `range_min_value` decimal(24, 9) NULL, `range_max_value` decimal(24, 9) NULL, `measured_at` datetime(3)  NULL, `sample_count` bigint(21) NULL, `window_started_at` datetime(3)  NULL, `window_ended_at` datetime(3)  NULL, `requested_window_seconds` decimal(29, 6) NULL, `coverage_seconds` bigint(21) NULL, `value_source_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `value_status` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `standard_basis_met` int(11) NULL, `value_status_display` varchar(14) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_color` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `basis_display` varchar(106) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `coverage_fraction` decimal(30, 4) NULL, `series_role` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `interval_seconds` int(5) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_primary_analysis_source` ADD INDEX ga_i1(`session_id`, `graph_id`, `series_id`, `sample_at`);
 ALTER TABLE `ga_rb_v_primary_analysis_source` ADD INDEX ga_i2(`session_id`, `metric_id`);
 ALTER TABLE `ga_rb_v_primary_analysis_source` ADD INDEX ga_i3(`criterion_id`);
 ALTER TABLE `ga_rb_v_primary_analysis_source` ADD INDEX ga_i4(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_dashboard_analysis_source`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `series_id` varchar(139) CHARACTER SET ascii COLLATE ascii_bin NULL, `sort_order` int(11) NULL, `label` varchar(513) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `minimum_samples` int(11) NULL, `minimum_coverage_fraction` decimal(8, 6) NULL, `warmup_minutes` int(11) NULL, `valid_minimum_value` decimal(18, 6) NULL, `valid_maximum_value` decimal(18, 6) NULL, `provisional_allowed` tinyint(4) NULL, `provisional_minimum_samples` int(11) NULL, `provisional_minimum_span_minutes` decimal(18, 6) NULL, `render_mode` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_model` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_description` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_opacity` decimal(4, 3) NULL, `standard_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `provisional_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `standard_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `provisional_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `actual_value_display` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `sample_at` datetime(3)  NULL, `basis_pitched_at` datetime(3)  NULL, `source_observation_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `basis_revision_key` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `actual_value` double NULL, `range_min_value` decimal(24, 9) NULL, `range_max_value` decimal(24, 9) NULL, `measured_at` datetime(3)  NULL, `sample_count` bigint(21) NULL, `window_started_at` datetime(3)  NULL, `window_ended_at` datetime(3)  NULL, `requested_window_seconds` decimal(29, 6) NULL, `coverage_seconds` bigint(21) NULL, `value_source_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `value_status` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `standard_basis_met` int(11) NULL, `value_status_display` varchar(14) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_color` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `basis_display` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `coverage_fraction` decimal(30, 4) NULL, `series_role` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `interval_seconds` int(11) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_dashboard_analysis_source` ADD INDEX ga_i1(`session_id`, `graph_id`, `series_id`, `sample_at`);
 ALTER TABLE `ga_rb_v_dashboard_analysis_source` ADD INDEX ga_i2(`session_id`, `metric_id`);
 ALTER TABLE `ga_rb_v_dashboard_analysis_source` ADD INDEX ga_i3(`criterion_id`);
 ALTER TABLE `ga_rb_v_dashboard_analysis_source` ADD INDEX ga_i4(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_dashboard_analysis_segments`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `series_id` varchar(139) CHARACTER SET ascii COLLATE ascii_bin NULL, `sort_order` int(11) NULL, `label` varchar(513) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `minimum_samples` int(11) NULL, `minimum_coverage_fraction` decimal(8, 6) NULL, `warmup_minutes` int(11) NULL, `valid_minimum_value` decimal(18, 6) NULL, `valid_maximum_value` decimal(18, 6) NULL, `provisional_allowed` tinyint(4) NULL, `provisional_minimum_samples` int(11) NULL, `provisional_minimum_span_minutes` decimal(18, 6) NULL, `render_mode` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_model` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_description` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_opacity` decimal(4, 3) NULL, `standard_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `provisional_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `standard_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `provisional_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `actual_value_display` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `sample_at` datetime(3)  NULL, `basis_pitched_at` datetime(3)  NULL, `source_observation_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `basis_revision_key` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `actual_value` double NULL, `range_min_value` decimal(24, 9) NULL, `range_max_value` decimal(24, 9) NULL, `measured_at` datetime(3)  NULL, `sample_count` bigint(21) NULL, `window_started_at` datetime(3)  NULL, `window_ended_at` datetime(3)  NULL, `requested_window_seconds` decimal(29, 6) NULL, `coverage_seconds` bigint(21) NULL, `value_source_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `value_status` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `standard_basis_met` int(11) NULL, `value_status_display` varchar(14) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_color` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `basis_display` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `coverage_fraction` decimal(30, 4) NULL, `series_role` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `interval_seconds` int(11) NULL, `previous_at` datetime(3)  NULL, `new_segment` int(2) NULL, `segment_id` decimal(32, 0) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_dashboard_analysis_segments` ADD INDEX ga_i1(`session_id`, `graph_id`, `series_id`, `sample_at`);
 ALTER TABLE `ga_rb_v_dashboard_analysis_segments` ADD INDEX ga_i2(`session_id`, `metric_id`);
 ALTER TABLE `ga_rb_v_dashboard_analysis_segments` ADD INDEX ga_i3(`criterion_id`);
 ALTER TABLE `ga_rb_v_dashboard_analysis_segments` ADD INDEX ga_i4(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_measurement_segments`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `bucket_at` datetime(3)  NULL, `interval_ended_at` datetime(3)  NULL, `sample_count` int(11) NULL, `sg_min` double NULL, `sg_mean` double NULL, `sg_median` decimal(7, 5) NULL, `sg_value` double NULL, `sg_max` double NULL, `temperature_min_c` double NULL, `temperature_mean_c` double NULL, `temperature_max_c` double NULL, `pressure_min_bar` decimal(8, 4) NULL, `pressure_mean_bar` decimal(8, 4) NULL, `pressure_max_bar` decimal(8, 4) NULL, `rssi_min_dbm` double NULL, `rssi_mean_dbm` double NULL, `rssi_max_dbm` double NULL, `source_kind` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_display` varchar(35) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `interval_seconds` int(11) NULL, `new_segment` int(2) NULL, `segment_id` decimal(32, 0) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_measurement_segments` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_graph_reference_measurement_series`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `bucket_at` datetime(3)  NULL, `sample_count` int(11) NULL, `sg_min` double NULL, `sg_mean` double NULL, `sg_median` decimal(7, 5) NULL, `sg_value` double NULL, `sg_max` double NULL, `temperature_min_c` double NULL, `temperature_mean_c` double NULL, `temperature_max_c` double NULL, `pressure_min_bar` decimal(9, 4) NULL, `pressure_mean_bar` decimal(9, 4) NULL, `pressure_max_bar` decimal(9, 4) NULL, `segment_id` decimal(32, 0) NULL, `source_display` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_graph_reference_measurement_series` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_graph_time_axis`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `x_axis_started_at` datetime(3)  NULL, `x_axis_ended_at` datetime(3)  NULL, `x_axis_start_display` varchar(53) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `x_axis_end_display` varchar(53) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_graph_time_axis` ADD INDEX ga_i1(`session_id`);
END//
CREATE PROCEDURE ga_init_read_basis_part_6() BEGIN
 CREATE TEMPORARY TABLE `ga_rb_v_dashboard_analysis_series`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `series_id` varchar(139) CHARACTER SET ascii COLLATE ascii_bin NULL, `sort_order` int(11) NULL, `label` varchar(513) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `minimum_samples` int(11) NULL, `minimum_coverage_fraction` decimal(8, 6) NULL, `warmup_minutes` int(11) NULL, `valid_minimum_value` decimal(18, 6) NULL, `valid_maximum_value` decimal(18, 6) NULL, `provisional_allowed` tinyint(4) NULL, `provisional_minimum_samples` int(11) NULL, `provisional_minimum_span_minutes` decimal(18, 6) NULL, `render_mode` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_model` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_description` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_opacity` decimal(4, 3) NULL, `standard_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `provisional_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `standard_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `provisional_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `actual_value_display` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `sample_at` datetime(3)  NULL, `basis_pitched_at` datetime(3)  NULL, `source_observation_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `basis_revision_key` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `actual_value` double NULL, `range_min_value` decimal(24, 9) NULL, `range_max_value` decimal(24, 9) NULL, `measured_at` datetime(3)  NULL, `sample_count` bigint(21) NULL, `window_started_at` datetime(3)  NULL, `window_ended_at` datetime(3)  NULL, `requested_window_seconds` decimal(29, 6) NULL, `coverage_seconds` bigint(21) NULL, `value_source_kind` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `value_status` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `standard_basis_met` int(11) NULL, `value_status_display` varchar(14) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_color` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `basis_display` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `coverage_fraction` decimal(30, 4) NULL, `series_role` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `interval_seconds` int(11) NULL, `previous_at` datetime(3)  NULL, `new_segment` int(2) NULL, `segment_id` decimal(32, 0) NULL, `first_rank` bigint(21) NULL, `last_rank` bigint(21) NULL, `min_rank` bigint(21) NULL, `max_rank` bigint(21) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_dashboard_analysis_series` ADD INDEX ga_i1(`session_id`, `graph_id`, `series_id`, `sample_at`);
 ALTER TABLE `ga_rb_v_dashboard_analysis_series` ADD INDEX ga_i2(`session_id`, `metric_id`);
 ALTER TABLE `ga_rb_v_dashboard_analysis_series` ADD INDEX ga_i3(`criterion_id`);
 ALTER TABLE `ga_rb_v_dashboard_analysis_series` ADD INDEX ga_i4(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_graph_comparison_display`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `bucket_at` datetime(3)  NULL, `sg_min` double NULL, `sg_value` double NULL, `sg_max` double NULL, `temperature_min_c` double NULL, `temperature_mean_c` double NULL, `temperature_max_c` double NULL, `pressure_min_bar` decimal(9, 4) NULL, `pressure_mean_bar` decimal(13, 8) NULL, `pressure_max_bar` decimal(9, 4) NULL, `segment_id` decimal(32, 0) NULL, `source_display` varchar(283) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_graph_comparison_display` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_graph_process_plan`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `started_at` datetime(3)  NULL, `ended_at` datetime(3)  NULL, `actual_value` decimal(23, 10) NULL, `minimum_value` decimal(18, 6) NULL, `maximum_value` decimal(18, 6) NULL, `label` varchar(283) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_graph_process_plan` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_graph_process_plan` ADD INDEX ga_i2(`session_id`, `metric_id`);
 ALTER TABLE `ga_rb_v_graph_process_plan` ADD INDEX ga_i3(`visit_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_display_measurement_series`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `bucket_at` datetime(3)  NULL, `interval_ended_at` datetime(3)  NULL, `sample_count` decimal(32, 0) NULL, `sg_min` double NULL, `sg_mean` double NULL, `sg_median` decimal(7, 5) NULL, `sg_value` double NULL, `sg_max` double NULL, `temperature_min_c` double NULL, `temperature_mean_c` double NULL, `temperature_max_c` double NULL, `pressure_min_bar` decimal(8, 4) NULL, `pressure_mean_bar` decimal(12, 8) NULL, `pressure_max_bar` decimal(8, 4) NULL, `source_kind` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_display` varchar(74) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `interval_seconds` int(11) NULL, `segment_id` decimal(32, 0) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_display_measurement_series` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_graph_source_values`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `source_kind` varchar(14) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `sample_at` datetime(3)  NULL, `actual_value` decimal(25, 10) NULL, `range_min_value` decimal(24, 9) NULL, `range_max_value` decimal(24, 9) NULL, `basis_display` varchar(283) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `segment_id` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_graph_source_values` ADD INDEX ga_i1(`session_id`, `sample_at`);
 ALTER TABLE `ga_rb_v_graph_source_values` ADD INDEX ga_i2(`session_id`, `metric_id`);
 ALTER TABLE `ga_rb_v_graph_source_values` ADD INDEX ga_i3(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_graph_raw_series`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `series_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `sort_order` int(11) NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `sample_at` datetime(3)  NULL, `actual_value` decimal(25, 10) NULL, `range_min_value` decimal(24, 9) NULL, `range_max_value` decimal(24, 9) NULL, `actual_value_display` varchar(126) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `basis_display` varchar(307) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_color` char(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_model` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_opacity` decimal(4, 3) NULL, `render_mode` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `segment_id` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_graph_raw_series` ADD INDEX ga_i1(`session_id`, `graph_id`, `series_id`, `sample_at`);
 ALTER TABLE `ga_rb_v_graph_raw_series` ADD INDEX ga_i2(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_graph_series`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `series_id` varchar(139) CHARACTER SET ascii COLLATE ascii_bin NULL, `sort_order` int(11) NULL, `label` varchar(513) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `sample_at` datetime(3)  NULL, `actual_value` double NULL, `range_min_value` decimal(24, 9) NULL, `range_max_value` decimal(24, 9) NULL, `actual_value_display` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `basis_display` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_color` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_dasharray` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_model` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_description` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `band_opacity` decimal(4, 3) NULL, `render_mode` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `segment_id` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_graph_series` ADD INDEX ga_i1(`session_id`, `graph_id`, `series_id`, `sample_at`);
 ALTER TABLE `ga_rb_v_graph_series` ADD INDEX ga_i2(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_graph_extents`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `display_decimals` int(11) NULL, `y_axis_include_zero` tinyint(4) NULL, `data_min` double NULL, `data_max` double NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_graph_extents` ADD INDEX ga_i1(`session_id`, `graph_id`);
 ALTER TABLE `ga_rb_v_graph_extents` ADD INDEX ga_i2(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_graph_axes`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `y_axis_min` double NULL, `y_axis_max` double NULL, `y_axis_tick_step` double NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_graph_axes` ADD INDEX ga_i1(`session_id`, `graph_id`);
 ALTER TABLE `ga_rb_v_graph_axes` ADD INDEX ga_i2(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_graph_axis_ticks`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `tick_value` double NULL, `axis_label` varchar(453) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_graph_axis_ticks` ADD INDEX ga_i1(`session_id`, `graph_id`);
 ALTER TABLE `ga_rb_v_graph_axis_ticks` ADD INDEX ga_i2(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_report_graph_time_axis`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `x_axis_started_at` datetime(3)  NULL, `x_axis_ended_at` datetime(3)  NULL, `x_axis_start_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `x_axis_end_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_report_graph_time_axis` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_graph_definitions`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `render_scope` varchar(9) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `sort_order` int(11) NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `unit` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `display_decimals` int(11) NULL, `y_axis_min` double NULL, `y_axis_max` double NULL, `y_axis_tick_step` double NULL, `x_axis_started_at` datetime(3)  NULL, `x_axis_ended_at` datetime(3)  NULL, `x_axis_start_display` varchar(53) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `x_axis_end_display` varchar(53) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `enabled` tinyint(4) NULL, `show_biological_bands` tinyint(4) NULL, `show_process_markers` tinyint(4) NULL, `show_criterion_markers` tinyint(4) NULL, `gap_policy` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `show_in_overview` int(1) NULL, `canvas_width` int(11) NULL, `canvas_height` int(11) NULL, `compact_height` int(11) NULL, `margin_left` int(11) NULL, `margin_right` int(11) NULL, `margin_top` int(11) NULL, `margin_bottom` int(11) NULL, `date_font_size` int(11) NULL, `axis_font_size` int(11) NULL, `marker_font_size` int(11) NULL, `font_family` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `line_width` decimal(6, 3) NULL, `point_radius` decimal(6, 3) NULL, `time_marker_spacing` int(11) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_graph_definitions` ADD INDEX ga_i1(`session_id`, `graph_id`);
 ALTER TABLE `ga_rb_v_graph_definitions` ADD INDEX ga_i2(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_graph_latest`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `series_id` varchar(139) CHARACTER SET ascii COLLATE ascii_bin NULL, `sort_order` int(11) NULL, `sample_at` datetime(3)  NULL, `actual_value` double NULL, `latest_value_display` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_graph_latest` ADD INDEX ga_i1(`session_id`, `graph_id`, `series_id`, `sample_at`);
 ALTER TABLE `ga_rb_v_graph_latest` ADD INDEX ga_i2(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_graph_time_markers`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `graph_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `render_scope` varchar(9) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `marker_at` datetime(3)  NULL, `relative_day` bigint(20) unsigned NULL, `axis_label` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_graph_time_markers` ADD INDEX ga_i1(`session_id`, `graph_id`);
 ALTER TABLE `ga_rb_v_graph_time_markers` ADD INDEX ga_i2(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_historical_phase_options`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `kind` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `sort_order` int(11) NULL, `label` varchar(386) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_historical_phase_options` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_phase_duration_presentation`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `kind` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `duration_seconds` decimal(42, 0) NULL, `duration_display` varchar(57) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_phase_duration_presentation` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_effective_process_criterion_requirement`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `requirement_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_effective_process_criterion_requirement` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_effective_process_criterion_requirement` ADD INDEX ga_i2(`criterion_id`);
 ALTER TABLE `ga_rb_v_effective_process_criterion_requirement` ADD INDEX ga_i3(`session_id`, `criterion_id`);
 ALTER TABLE `ga_rb_v_effective_process_criterion_requirement` ADD INDEX ga_i4(`session_id`, `process_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_process_evaluation_criterion_requirement`(`evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `requirement_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_process_evaluation_criterion_requirement` ADD INDEX ga_i1(`evaluation_id`, `criterion_id`);
 ALTER TABLE `ga_rb_v_process_evaluation_criterion_requirement` ADD INDEX ga_i2(`criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_template_process_criterion_requirement`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `requirement_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_template_process_criterion_requirement` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_template_process_criterion_requirement` ADD INDEX ga_i2(`criterion_id`);
 ALTER TABLE `ga_rb_v_template_process_criterion_requirement` ADD INDEX ga_i3(`session_id`, `criterion_id`);
 ALTER TABLE `ga_rb_v_template_process_criterion_requirement` ADD INDEX ga_i4(`session_id`, `process_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_process_evaluation_criterion_read_model`(`evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `candidate_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_order` int(11) NULL, `role_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `metric_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `model_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `met` tinyint(4) NULL, `valid` tinyint(4) NULL, `evaluation_status` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `actual_value` decimal(18, 6) NULL, `actual_text` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `measured_at` datetime(3) NULL, `source` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `data_window_started_at` datetime(3) NULL, `data_window_ended_at` datetime(3) NULL, `requested_window_seconds` int(11) NULL, `sample_count` int(11) NULL, `coverage_seconds` int(11) NULL, `latest_sample_at` datetime(3) NULL, `explanation` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `created_at` datetime(3) NULL, `evaluated_at` datetime(3) NULL, `evaluation_created_at` datetime(3) NULL, `exception_register_allowed` int(2) NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `metric_label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `metric_unit` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `requirement_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `template_requirement_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `effective_requirement_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `criterion_basis_current` int(1) NULL, `status_display` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `actual_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `data_window_display` varchar(67) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_process_evaluation_criterion_read_model` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_process_evaluation_criterion_read_model` ADD INDEX ga_i2(`session_id`, `metric_id`);
 ALTER TABLE `ga_rb_v_process_evaluation_criterion_read_model` ADD INDEX ga_i3(`evaluation_id`, `criterion_id`);
 ALTER TABLE `ga_rb_v_process_evaluation_criterion_read_model` ADD INDEX ga_i4(`criterion_revision_id`);
 ALTER TABLE `ga_rb_v_process_evaluation_criterion_read_model` ADD INDEX ga_i5(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_process_transition_evidence`(`transition_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `transitioned_at` datetime(3) NULL, `from_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `to_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `action` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `recommendation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `transition_recommended_temperature_c` decimal(8, 3) NULL, `transition_recommended_pressure_bar` decimal(8, 4) NULL, `transition_note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `current_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `candidate_process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `active_visit_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `observation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `observation_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluated_at` datetime(3) NULL, `readiness` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `data_quality` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `summary` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `recommended_temperature_c` decimal(8, 3) NULL, `recommended_pressure_bar` decimal(8, 4) NULL, `engine_version` varchar(96) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `evaluation_created_at` datetime(3) NULL, `candidate_process_order` int(11) NULL, `candidate_process_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_process_transition_evidence` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_process_transition_evidence` ADD INDEX ga_i2(`evaluation_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_recommendations_effective`(`recommendation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `observation_revision_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `severity` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `rule_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `recommendation_type` varchar(96) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `model_version` varchar(96) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `explanation` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `uncertainty` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `supersedes_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NULL, `effective_status` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `latest_resolution_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `resolved_at` datetime(3) NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_recommendations_effective` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_recommendations_effective` ADD INDEX ga_i2(`evaluation_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_biological_exception_read_model`(`exception_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `revision_no` int(11) NULL, `supersedes_exception_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `action` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `exception_type` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `confirmed` tinyint(4) NULL, `note` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `operation_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `action_display` varchar(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `exception_type_display` varchar(26) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `note_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_biological_exception_read_model` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_session_biological_exception_read_model` ADD INDEX ga_i2(`evaluation_id`, `criterion_id`);
 ALTER TABLE `ga_rb_v_session_biological_exception_read_model` ADD INDEX ga_i3(`session_id`, `phase_id`, `criterion_id`);
 ALTER TABLE `ga_rb_v_session_biological_exception_read_model` ADD INDEX ga_i4(`session_id`, `criterion_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_report_actions`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `completed_at` datetime(3) NULL, `completed_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `accepted_display` varchar(3) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `outcome_display` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `detail_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_report_actions` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_report_biological_criteria`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluated_at` datetime(3) NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluated_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `criterion_order` int(11) NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `role_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `status_display` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `requirement_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `actual_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `data_window_display` varchar(67) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `explanation` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_report_biological_criteria` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_report_biology`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `phase_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `started_ms` decimal(23, 3) NULL, `ended_ms` decimal(23, 3) NULL, `started_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `ended_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `timing_source_display` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `confidence` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `duration_display` varchar(35) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_report_biology` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_session_report_biology` ADD INDEX ga_i2(`session_id`, `phase_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_report_criterion_corrections`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3)  NULL, `created_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `area_display` varchar(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `owner_id` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `criterion_label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `action_display` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `parameters_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `note_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_report_criterion_corrections` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_report_gaps`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `started_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `ended_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `duration_display` varchar(23) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `source_display` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `gap_started_at` datetime(3) NULL, `gap_ended_at` datetime(3)  NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_report_gaps` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_report_notes`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `noted_at` datetime(3) NULL, `noted_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `note_text` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_report_notes` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_report_observations`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `at_ms` decimal(23, 3) NULL, `at_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `measured_sg` decimal(7, 5) NULL, `corrected_sg` decimal(7, 5) NULL, `manual_temperature_c` decimal(8, 3) NULL, `measurement_method_display` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `measured_sg_display` varchar(9) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `corrected_sg_display` varchar(9) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `manual_temperature_display` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `pressure_display` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `cooler_setpoint_display` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `airlock_activity_display` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `acetaldehyde_display` varchar(11) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `diacetyl_display` varchar(11) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `wort_like_display` varchar(11) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `sulfur_so2_display` varchar(11) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `sulfur_h2s_display` varchar(11) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `clarity_display` varchar(11) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `settling_yeast_display` varchar(11) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `settling_minutes_display` varchar(14) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `estimated_abv_display` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `estimated_finished_abv_display` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `user_conclusion_display` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `note_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `sg_marker_label` varchar(44) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `temperature_marker_label` varchar(56) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_report_observations` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_report_process`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `process_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `historical_replay_auto_transition_allowed` tinyint(4) NULL, `started_ms` decimal(23, 3) NULL, `ended_ms` decimal(23, 3) NULL, `started_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `ended_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `timing_source_display` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `historical_replay_policy_display` varchar(19) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `duration_display` varchar(35) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_report_process` ADD INDEX ga_i1(`session_id`);
 ALTER TABLE `ga_rb_v_session_report_process` ADD INDEX ga_i2(`session_id`, `process_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_report_process_criteria`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluated_at` datetime(3) NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `evaluated_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `criterion_order` int(11) NULL, `label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `role_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `status_display` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `requirement_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `actual_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `data_window_display` varchar(67) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `explanation` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_report_process_criteria` ADD INDEX ga_i1(`session_id`);
END//
CREATE PROCEDURE ga_init_read_basis_part_7() BEGIN
 CREATE TEMPORARY TABLE `ga_rb_v_session_report_process_exceptions`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `created_at` datetime(3) NULL, `created_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `owner_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `criterion_label` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `action_display` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `exception_type_display` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `note_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_report_process_exceptions` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_report_process_transitions`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `transitioned_at` datetime(3) NULL, `transitioned_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `transition_display` varchar(259) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `action_display` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `note_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_report_process_transitions` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_report_session`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `batch_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `og` decimal(7, 5) NULL, `volume_l` decimal(10, 3) NULL, `report_kind_display` varchar(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `lifecycle_display` varchar(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `pitched_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `pitched_ms` decimal(23, 3) NULL, `expected_attenuation_min_percent` decimal(8, 4) NULL, `expected_attenuation_max_percent` decimal(8, 4) NULL, `expected_fg_min` decimal(7, 5) NULL, `expected_fg_max` decimal(7, 5) NULL, `expected_fg_display` varchar(19) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `expected_attenuation_display` varchar(23) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `biology_display` varchar(386) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `process_display` varchar(386) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `template_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `version_label` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `latest_abv_display` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL, `estimated_finished_abv_display` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_report_session` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_report_timeline`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `happened_at` datetime(3)  NULL, `happened_display` varchar(21) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `type_display` varchar(26) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `event_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `note_display` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_report_timeline` ADD INDEX ga_i1(`session_id`);
 CREATE TEMPORARY TABLE `ga_rb_v_session_runtime_presentation`(`session_id` varchar(128) CHARACTER SET ascii COLLATE ascii_bin NULL, `yeast` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `active_process_order` int(11) NULL, `active_process_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `attention` int(2) NULL, `recommended_process_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL, `elapsed_hours` decimal(24, 4) NULL, `active_phase_elapsed_hours` decimal(24, 4) NULL, `completed_at` datetime(3)  NULL, `active_phase_duration_display` varchar(35) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL) ENGINE=Aria TRANSACTIONAL=0;
 ALTER TABLE `ga_rb_v_session_runtime_presentation` ADD INDEX ga_i1(`session_id`);
END//
CREATE PROCEDURE ga_init_read_basis() BEGIN
 CALL ga_drop_read_basis();
 CALL ga_init_read_basis_part_1();
 CALL ga_init_read_basis_part_2();
 CALL ga_init_read_basis_part_3();
 CALL ga_init_read_basis_part_4();
 CALL ga_init_read_basis_part_5();
 CALL ga_init_read_basis_part_6();
 CALL ga_init_read_basis_part_7();
END//
CREATE PROCEDURE ga_fill_read_basis_part_1() BEGIN
 DECLARE v_stage LONGTEXT; DECLARE v_expected BIGINT; DECLARE v_step VARCHAR(128); DECLARE v_error TEXT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_error=MESSAGE_TEXT; SET v_error=CONCAT(v_step, ': ', LEFT(v_error, 350)); RESIGNAL SET MESSAGE_TEXT=v_error; END;
 SET v_step='source:analysis_series_values';
 BEGIN
 DECLARE ga_done BOOLEAN DEFAULT FALSE;
 DECLARE ga_chunks CURSOR FOR SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`graph_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`series_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`sample_at`, a.`basis_pitched_at`, CONVERT(CAST(a.`actual_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`value_status` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`standard_basis_met`, CONVERT(CAST(a.`range_min_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`range_max_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`measured_at`, a.`sample_count`, a.`window_started_at`, a.`window_ended_at`, a.`requested_window_seconds`, a.`coverage_seconds`, CONVERT(a.`source_kind` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`, CONVERT(a.`source_observation_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`basis_revision_key` USING utf8mb4) COLLATE utf8mb4_unicode_ci)), COUNT(*) FROM `analysis_series_values` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope) GROUP BY DATE(a.`sample_at`), a.session_id;
 DECLARE CONTINUE HANDLER FOR NOT FOUND SET ga_done=TRUE;
 OPEN ga_chunks;
 ga_days: LOOP
 FETCH ga_chunks INTO v_stage, v_expected;
 IF ga_done THEN LEAVE ga_days; END IF;
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_analysis_series_values`(`session_id`, `graph_id`, `series_id`, `sample_at`, `basis_pitched_at`, `actual_value`, `value_status`, `standard_basis_met`, `range_min_value`, `range_max_value`, `measured_at`, `sample_count`, `window_started_at`, `window_ended_at`, `requested_window_seconds`, `coverage_seconds`, `source_kind`, `created_at`, `source_observation_revision_id`, `basis_revision_key`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 datetime(3) PATH '$[3]', c4 datetime(3) PATH '$[4]', c5 decimal(24, 9) PATH '$[5]', c6 varchar(16) PATH '$[6]', c7 tinyint(4) PATH '$[7]', c8 decimal(24, 9) PATH '$[8]', c9 decimal(24, 9) PATH '$[9]', c10 datetime(3) PATH '$[10]', c11 int(11) PATH '$[11]', c12 datetime(3) PATH '$[12]', c13 datetime(3) PATH '$[13]', c14 int(11) PATH '$[14]', c15 int(11) PATH '$[15]', c16 varchar(32) PATH '$[16]', c17 datetime(3) PATH '$[17]', c18 varchar(128) PATH '$[18]', c19 varchar(128) PATH '$[19]')) j;
 END LOOP;
 CLOSE ga_chunks;
 END;
 SET v_step='source:analysis_validation_events';
 BEGIN
 DECLARE ga_done BOOLEAN DEFAULT FALSE;
 DECLARE ga_chunks CURSOR FOR SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`validation_event_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`graph_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`series_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`sample_at`, a.`basis_pitched_at`, CONVERT(a.`reason_code` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) FROM `analysis_validation_events` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope) GROUP BY DATE(a.`sample_at`), a.session_id;
 DECLARE CONTINUE HANDLER FOR NOT FOUND SET ga_done=TRUE;
 OPEN ga_chunks;
 ga_days: LOOP
 FETCH ga_chunks INTO v_stage, v_expected;
 IF ga_done THEN LEAVE ga_days; END IF;
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_analysis_validation_events`(`validation_event_id`, `session_id`, `graph_id`, `series_id`, `sample_at`, `basis_pitched_at`, `reason_code`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 datetime(3) PATH '$[4]', c5 datetime(3) PATH '$[5]', c6 varchar(128) PATH '$[6]', c7 datetime(3) PATH '$[7]')) j;
 END LOOP;
 CLOSE ga_chunks;
 END;
 SET v_step='source:biological_criterion_exceptions';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`exception_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`phase_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`evaluation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`criterion_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`revision_no`, CONVERT(a.`supersedes_exception_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`action` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`exception_type` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`confirmed`, CONVERT(a.`note` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `biological_criterion_exceptions` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_biological_criterion_exceptions`(`exception_id`, `session_id`, `phase_id`, `evaluation_id`, `criterion_id`, `revision_no`, `supersedes_exception_id`, `action`, `exception_type`, `confirmed`, `note`, `operation_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 int(11) PATH '$[5]', c6 varchar(128) PATH '$[6]', c7 varchar(16) PATH '$[7]', c8 varchar(64) PATH '$[8]', c9 tinyint(4) PATH '$[9]', c10 text PATH '$[10]', c11 varchar(128) PATH '$[11]', c12 datetime(3) PATH '$[12]')) j;
 END IF;
 SET v_step='source:biological_evaluation_criteria';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`evaluation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`phase_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`criterion_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`applied_exception_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`criterion_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`criterion_order`, CONVERT(a.`role_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`metric_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`met`, a.`valid`, CONVERT(a.`evaluation_status` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`actual_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`actual_text` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`measured_at`, CONVERT(a.`source` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`data_window_started_at`, a.`data_window_ended_at`, a.`requested_window_seconds`, a.`sample_count`, a.`coverage_seconds`, a.`latest_sample_at`, CONVERT(a.`explanation` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `biological_evaluation_criteria` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_biological_evaluation_criteria`(`evaluation_id`, `session_id`, `phase_id`, `criterion_id`, `applied_exception_id`, `criterion_revision_id`, `criterion_order`, `role_id`, `metric_id`, `model_id`, `met`, `valid`, `evaluation_status`, `actual_value`, `actual_text`, `measured_at`, `source`, `data_window_started_at`, `data_window_ended_at`, `requested_window_seconds`, `sample_count`, `coverage_seconds`, `latest_sample_at`, `explanation`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 varchar(128) PATH '$[5]', c6 int(11) PATH '$[6]', c7 varchar(128) PATH '$[7]', c8 varchar(128) PATH '$[8]', c9 varchar(128) PATH '$[9]', c10 tinyint(4) PATH '$[10]', c11 tinyint(4) PATH '$[11]', c12 varchar(32) PATH '$[12]', c13 decimal(18, 6) PATH '$[13]', c14 text PATH '$[14]', c15 datetime(3) PATH '$[15]', c16 varchar(128) PATH '$[16]', c17 datetime(3) PATH '$[17]', c18 datetime(3) PATH '$[18]', c19 int(11) PATH '$[19]', c20 int(11) PATH '$[20]', c21 int(11) PATH '$[21]', c22 datetime(3) PATH '$[22]', c23 text PATH '$[23]', c24 datetime(3) PATH '$[24]')) j;
 END IF;
 SET v_step='source:biological_evaluation_criterion_parameter_values';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`evaluation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`criterion_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`parameter_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`data_type` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`real_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`integer_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`boolean_value`, CONVERT(a.`text_value` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`is_unset`, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `biological_evaluation_criterion_parameter_values` a WHERE EXISTS(SELECT 1 FROM `ga_rb_t_biological_evaluation_criteria` p WHERE p.`evaluation_id`=a.`evaluation_id` AND p.`criterion_id`=a.`criterion_id` AND p.`model_id`=a.`model_id`);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_biological_evaluation_criterion_parameter_values`(`evaluation_id`, `criterion_id`, `model_id`, `parameter_id`, `data_type`, `real_value`, `integer_value`, `boolean_value`, `text_value`, `is_unset`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(32) PATH '$[4]', c5 decimal(18, 6) PATH '$[5]', c6 bigint(20) PATH '$[6]', c7 tinyint(4) PATH '$[7]', c8 text PATH '$[8]', c9 tinyint(4) PATH '$[9]', c10 datetime(3) PATH '$[10]')) j;
 END IF;
 SET v_step='source:biological_evaluations';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`evaluation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`current_phase_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`candidate_phase_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`active_visit_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`evaluated_at`, CONVERT(a.`outcome` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`confidence` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`data_quality` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`summary` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`engine_version` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `biological_evaluations` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_biological_evaluations`(`evaluation_id`, `session_id`, `current_phase_id`, `candidate_phase_id`, `active_visit_id`, `evaluated_at`, `outcome`, `confidence`, `data_quality`, `summary`, `engine_version`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 datetime(3) PATH '$[5]', c6 varchar(32) PATH '$[6]', c7 varchar(64) PATH '$[7]', c8 varchar(64) PATH '$[8]', c9 text PATH '$[9]', c10 varchar(96) PATH '$[10]', c11 datetime(3) PATH '$[11]')) j;
 END IF;
 SET v_step='source:biological_transitions';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`transition_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`transitioned_at`, CONVERT(a.`from_visit_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`to_visit_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`from_phase_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`to_phase_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`transition_source` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`confidence` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`evaluation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`reason` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `biological_transitions` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_biological_transitions`(`transition_id`, `session_id`, `transitioned_at`, `from_visit_id`, `to_visit_id`, `from_phase_id`, `to_phase_id`, `transition_source`, `confidence`, `evaluation_id`, `reason`, `operation_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 datetime(3) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 varchar(128) PATH '$[5]', c6 varchar(128) PATH '$[6]', c7 varchar(32) PATH '$[7]', c8 varchar(64) PATH '$[8]', c9 varchar(128) PATH '$[9]', c10 text PATH '$[10]', c11 varchar(128) PATH '$[11]', c12 datetime(3) PATH '$[12]')) j;
 END IF;
 SET v_step='source:biological_visits';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`visit_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`phase_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`visit_seq` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `biological_visits` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_biological_visits`(`visit_id`, `session_id`, `phase_id`, `visit_seq`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 bigint(20) unsigned PATH '$[3]', c4 datetime(3) PATH '$[4]')) j;
 END IF;
 SET v_step='source:biological_visit_revisions';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`visit_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`visit_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`revision_no`, CONVERT(a.`supersedes_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`started_at`, a.`ended_at`, CONVERT(a.`timing_source` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`confidence` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`evaluation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`revision_reason` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `biological_visit_revisions` a WHERE EXISTS(SELECT 1 FROM `ga_rb_t_biological_visits` p WHERE p.`visit_id`=a.`visit_id`);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_biological_visit_revisions`(`visit_revision_id`, `visit_id`, `revision_no`, `supersedes_revision_id`, `started_at`, `ended_at`, `timing_source`, `confidence`, `evaluation_id`, `revision_reason`, `operation_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 int(11) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 datetime(3) PATH '$[4]', c5 datetime(3) PATH '$[5]', c6 varchar(64) PATH '$[6]', c7 varchar(64) PATH '$[7]', c8 varchar(128) PATH '$[8]', c9 text PATH '$[9]', c10 varchar(128) PATH '$[10]', c11 datetime(3) PATH '$[11]')) j;
 END IF;
 SET v_step='source:criterion_model_parameters';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`parameter_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`sort_order`, CONVERT(a.`label` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`data_type` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`unit_source` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`fixed_unit` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `criterion_model_parameters` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_criterion_model_parameters`(`model_id`, `parameter_id`, `sort_order`, `label`, `data_type`, `unit_source`, `fixed_unit`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 int(11) PATH '$[2]', c3 varchar(255) PATH '$[3]', c4 varchar(32) PATH '$[4]', c5 varchar(32) PATH '$[5]', c6 varchar(64) PATH '$[6]', c7 datetime(3) PATH '$[7]')) j;
 END IF;
 SET v_step='source:criterion_roles';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`role_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`label` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`description` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `criterion_roles` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_criterion_roles`(`role_id`, `label`, `description`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(255) PATH '$[1]', c2 text PATH '$[2]', c3 datetime(3) PATH '$[3]')) j;
 END IF;
 SET v_step='source:demo_reference_analysis_values';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`profile_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`graph_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`series_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`offset_seconds`, CONVERT(CAST(a.`actual_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`sample_count`, a.`coverage_seconds`, a.`window_seconds`, CONVERT(a.`basis_display` USING utf8mb4) COLLATE utf8mb4_unicode_ci)), COUNT(*) INTO v_stage, v_expected FROM `demo_reference_analysis_values` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_demo_reference_analysis_values`(`profile_id`, `graph_id`, `series_id`, `offset_seconds`, `actual_value`, `sample_count`, `coverage_seconds`, `window_seconds`, `basis_display`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 int(11) PATH '$[3]', c4 decimal(18, 9) PATH '$[4]', c5 int(11) PATH '$[5]', c6 int(11) PATH '$[6]', c7 int(11) PATH '$[7]', c8 text PATH '$[8]')) j;
 END IF;
 SET v_step='source:demo_reference_data_gaps';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`profile_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`gap_no`, a.`gap_start_offset_seconds`, a.`gap_end_offset_seconds`, a.`duration_seconds`, a.`threshold_seconds`, CONVERT(a.`source` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`note` USING utf8mb4) COLLATE utf8mb4_unicode_ci)), COUNT(*) INTO v_stage, v_expected FROM `demo_reference_data_gaps` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_demo_reference_data_gaps`(`profile_id`, `gap_no`, `gap_start_offset_seconds`, `gap_end_offset_seconds`, `duration_seconds`, `threshold_seconds`, `source`, `note`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 int(11) PATH '$[1]', c2 int(11) PATH '$[2]', c3 int(11) PATH '$[3]', c4 int(11) PATH '$[4]', c5 int(11) PATH '$[5]', c6 varchar(64) PATH '$[6]', c7 text PATH '$[7]')) j;
 END IF;
 SET v_step='source:demo_reference_measurement_details';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`profile_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`offset_seconds`, CONVERT(CAST(a.`temperature_min_c` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`temperature_max_c` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`rssi_min_dbm` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`rssi_mean_dbm` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`rssi_max_dbm` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`source_kind` USING utf8mb4) COLLATE utf8mb4_unicode_ci)), COUNT(*) INTO v_stage, v_expected FROM `demo_reference_measurement_details` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_demo_reference_measurement_details`(`profile_id`, `offset_seconds`, `temperature_min_c`, `temperature_max_c`, `rssi_min_dbm`, `rssi_mean_dbm`, `rssi_max_dbm`, `source_kind`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 int(11) PATH '$[1]', c2 decimal(8, 3) PATH '$[2]', c3 decimal(8, 3) PATH '$[3]', c4 decimal(8, 3) PATH '$[4]', c5 decimal(8, 3) PATH '$[5]', c6 decimal(8, 3) PATH '$[6]', c7 varchar(64) PATH '$[7]')) j;
 END IF;
 SET v_step='source:demo_reference_measurements_5m';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`profile_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`offset_seconds`, a.`sample_count`, CONVERT(CAST(a.`sg_min` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`sg_mean` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`sg_median` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`sg_max` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`temperature_mean_c` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci)), COUNT(*) INTO v_stage, v_expected FROM `demo_reference_measurements_5m` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_demo_reference_measurements_5m`(`profile_id`, `offset_seconds`, `sample_count`, `sg_min`, `sg_mean`, `sg_median`, `sg_max`, `temperature_mean_c`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 int(11) PATH '$[1]', c2 int(11) PATH '$[2]', c3 decimal(7, 5) PATH '$[3]', c4 decimal(7, 5) PATH '$[4]', c5 decimal(7, 5) PATH '$[5]', c6 decimal(7, 5) PATH '$[6]', c7 decimal(8, 3) PATH '$[7]')) j;
 END IF;
 SET v_step='source:demo_reference_profiles';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`profile_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`name` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`description` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`span_seconds`, CONVERT(CAST(a.`og` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`source_kind` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`source_note` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`interval_seconds`, a.`selectable`, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `demo_reference_profiles` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_demo_reference_profiles`(`profile_id`, `name`, `description`, `span_seconds`, `og`, `source_kind`, `source_note`, `interval_seconds`, `selectable`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(255) PATH '$[1]', c2 text PATH '$[2]', c3 int(11) PATH '$[3]', c4 decimal(7, 5) PATH '$[4]', c5 varchar(64) PATH '$[5]', c6 text PATH '$[6]', c7 int(11) PATH '$[7]', c8 tinyint(4) PATH '$[8]', c9 datetime(3) PATH '$[9]')) j;
 END IF;
 SET v_step='source:demo_reference_synthetic_details';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`profile_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`offset_seconds`, CONVERT(CAST(a.`pressure_bar` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci)), COUNT(*) INTO v_stage, v_expected FROM `demo_reference_synthetic_details` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_demo_reference_synthetic_details`(`profile_id`, `offset_seconds`, `pressure_bar`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 int(11) PATH '$[1]', c2 decimal(8, 3) PATH '$[2]')) j;
 END IF;
 SET v_step='source:graph_display_selection_events';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(CAST(a.`selection_seq` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`source_kind` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`reference_profile_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`reference_session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`interval_seconds`, a.`window_hours`, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`selected_at`)), COUNT(*) INTO v_stage, v_expected FROM `graph_display_selection_events` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_graph_display_selection_events`(`selection_seq`, `source_kind`, `reference_profile_id`, `reference_session_id`, `interval_seconds`, `window_hours`, `operation_id`, `selected_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 bigint(20) unsigned PATH '$[0]', c1 varchar(16) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 int(11) PATH '$[4]', c5 int(11) PATH '$[5]', c6 varchar(128) PATH '$[6]', c7 datetime(3) PATH '$[7]')) j;
 END IF;
 SET v_step='source:graph_render_policy';
SELECT JSON_ARRAYAGG(JSON_ARRAY(a.`policy_id`, a.`canvas_width`, a.`canvas_height`, a.`compact_height`, a.`margin_left`, a.`margin_right`, a.`margin_top`, a.`margin_bottom`, a.`date_font_size`, a.`axis_font_size`, a.`marker_font_size`, CONVERT(a.`font_family` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`line_width` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`time_marker_spacing`, CONVERT(CAST(a.`point_radius` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `graph_render_policy` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_graph_render_policy`(`policy_id`, `canvas_width`, `canvas_height`, `compact_height`, `margin_left`, `margin_right`, `margin_top`, `margin_bottom`, `date_font_size`, `axis_font_size`, `marker_font_size`, `font_family`, `line_width`, `time_marker_spacing`, `point_radius`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 int(11) PATH '$[0]', c1 int(11) PATH '$[1]', c2 int(11) PATH '$[2]', c3 int(11) PATH '$[3]', c4 int(11) PATH '$[4]', c5 int(11) PATH '$[5]', c6 int(11) PATH '$[6]', c7 int(11) PATH '$[7]', c8 int(11) PATH '$[8]', c9 int(11) PATH '$[9]', c10 int(11) PATH '$[10]', c11 varchar(64) PATH '$[11]', c12 decimal(6, 3) PATH '$[12]', c13 int(11) PATH '$[13]', c14 decimal(6, 3) PATH '$[14]', c15 datetime(3) PATH '$[15]')) j;
 END IF;
 SET v_step='source:measurement_data_gaps';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`gap_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`source` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`gap_started_at`, a.`gap_ended_at`, a.`duration_seconds`, a.`threshold_seconds`, a.`detected_at`, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `measurement_data_gaps` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_measurement_data_gaps`(`gap_id`, `session_id`, `source`, `gap_started_at`, `gap_ended_at`, `duration_seconds`, `threshold_seconds`, `detected_at`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(64) PATH '$[2]', c3 datetime(3) PATH '$[3]', c4 datetime(3) PATH '$[4]', c5 int(11) PATH '$[5]', c6 int(11) PATH '$[6]', c7 datetime(3) PATH '$[7]', c8 datetime(3) PATH '$[8]')) j;
 END IF;
 SET v_step='source:measurement_gap_closures';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`gap_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`gap_ended_at`, a.`duration_seconds`, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `measurement_gap_closures` a WHERE EXISTS(SELECT 1 FROM `ga_rb_t_measurement_data_gaps` p WHERE p.`gap_id`=a.`gap_id`);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_measurement_gap_closures`(`gap_id`, `gap_ended_at`, `duration_seconds`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 datetime(3) PATH '$[1]', c2 int(11) PATH '$[2]', c3 datetime(3) PATH '$[3]')) j;
 END IF;
 SET v_step='source:measurement_methods';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`measurement_method_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`label` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `measurement_methods` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_measurement_methods`(`measurement_method_id`, `label`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(255) PATH '$[1]', c2 datetime(3) PATH '$[2]')) j;
 END IF;
 SET v_step='source:measurement_source_configurations';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(CAST(a.`configuration_id` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`source_profile_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`parent_configuration_id` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`parent_key` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`note` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `measurement_source_configurations` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_measurement_source_configurations`(`configuration_id`, `source_profile_id`, `parent_configuration_id`, `parent_key`, `operation_id`, `note`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 bigint(20) unsigned PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 bigint(20) unsigned PATH '$[2]', c3 bigint(20) unsigned PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 text PATH '$[5]', c6 datetime(3) PATH '$[6]')) j;
 END IF;
 SET v_step='source:measurement_source_profiles';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`source_profile_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`name` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`source_type` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`poll_interval_seconds`, a.`gap_threshold_seconds`, a.`fresh_age_minutes`, a.`stale_age_minutes`, CONVERT(a.`status` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`description` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`, a.`updated_at`)), COUNT(*) INTO v_stage, v_expected FROM `measurement_source_profiles` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_measurement_source_profiles`(`source_profile_id`, `name`, `source_type`, `poll_interval_seconds`, `gap_threshold_seconds`, `fresh_age_minutes`, `stale_age_minutes`, `status`, `description`, `created_at`, `updated_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(255) PATH '$[1]', c2 varchar(32) PATH '$[2]', c3 int(11) PATH '$[3]', c4 int(11) PATH '$[4]', c5 int(11) PATH '$[5]', c6 int(11) PATH '$[6]', c7 varchar(16) PATH '$[7]', c8 text PATH '$[8]', c9 datetime(3) PATH '$[9]', c10 datetime(3) PATH '$[10]')) j;
 END IF;
 SET v_step='source:measurement_source_signal_bindings';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(CAST(a.`configuration_id` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`signal_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`input_mode` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`entity_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`unit_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci)), COUNT(*) INTO v_stage, v_expected FROM `measurement_source_signal_bindings` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_measurement_source_signal_bindings`(`configuration_id`, `signal_id`, `input_mode`, `entity_id`, `unit_id`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 bigint(20) unsigned PATH '$[0]', c1 varchar(32) PATH '$[1]', c2 varchar(16) PATH '$[2]', c3 varchar(255) PATH '$[3]', c4 varchar(32) PATH '$[4]')) j;
 END IF;
END//
CREATE PROCEDURE ga_fill_read_basis_part_2() BEGIN
 DECLARE v_stage LONGTEXT; DECLARE v_expected BIGINT; DECLARE v_step VARCHAR(128); DECLARE v_error TEXT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_error=MESSAGE_TEXT; SET v_error=CONCAT(v_step, ': ', LEFT(v_error, 350)); RESIGNAL SET MESSAGE_TEXT=v_error; END;
 SET v_step='source:measurement_source_signals';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`signal_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`label` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`observation_kind` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`sensor_required`, CONVERT(a.`operator_entity_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`display_order`, a.`show_on_start`, CONVERT(a.`description` USING utf8mb4) COLLATE utf8mb4_unicode_ci)), COUNT(*) INTO v_stage, v_expected FROM `measurement_source_signals` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_measurement_source_signals`(`signal_id`, `label`, `observation_kind`, `sensor_required`, `operator_entity_id`, `display_order`, `show_on_start`, `description`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(32) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(16) PATH '$[2]', c3 tinyint(4) PATH '$[3]', c4 varchar(255) PATH '$[4]', c5 int(11) PATH '$[5]', c6 tinyint(4) PATH '$[6]', c7 text PATH '$[7]')) j;
 END IF;
 SET v_step='source:measurement_source_units';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`signal_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`unit_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`ha_unit` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`label` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`multiplier` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`additive_offset` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`is_canonical`, CONVERT(a.`canonical_signal` USING utf8mb4) COLLATE utf8mb4_unicode_ci)), COUNT(*) INTO v_stage, v_expected FROM `measurement_source_units` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_measurement_source_units`(`signal_id`, `unit_id`, `ha_unit`, `label`, `multiplier`, `additive_offset`, `is_canonical`, `canonical_signal`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(32) PATH '$[0]', c1 varchar(32) PATH '$[1]', c2 varchar(32) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 decimal(24, 12) PATH '$[4]', c5 decimal(24, 12) PATH '$[5]', c6 tinyint(4) PATH '$[6]', c7 varchar(32) PATH '$[7]')) j;
 END IF;
 SET v_step='source:measurement_statistics_hourly';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(CAST(a.`statistic_seq` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`statistic_import_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`start_at`, a.`end_at`, a.`sg_min`, a.`sg_mean`, a.`sg_max`, a.`temperature_min_c`, a.`temperature_mean_c`, a.`temperature_max_c`, a.`rssi_min_dbm`, a.`rssi_mean_dbm`, a.`rssi_max_dbm`, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `measurement_statistics_hourly` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_measurement_statistics_hourly`(`statistic_seq`, `statistic_import_id`, `session_id`, `start_at`, `end_at`, `sg_min`, `sg_mean`, `sg_max`, `temperature_min_c`, `temperature_mean_c`, `temperature_max_c`, `rssi_min_dbm`, `rssi_mean_dbm`, `rssi_max_dbm`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 bigint(20) unsigned PATH '$[0]', c1 char(64) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 datetime(3) PATH '$[3]', c4 datetime(3) PATH '$[4]', c5 double PATH '$[5]', c6 double PATH '$[6]', c7 double PATH '$[7]', c8 double PATH '$[8]', c9 double PATH '$[9]', c10 double PATH '$[10]', c11 double PATH '$[11]', c12 double PATH '$[12]', c13 double PATH '$[13]', c14 datetime(3) PATH '$[14]')) j;
 END IF;
 SET v_step='source:measurements_5m';
 BEGIN
 DECLARE ga_done BOOLEAN DEFAULT FALSE;
 DECLARE ga_chunks CURSOR FOR SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`bucket_at`, a.`sample_count`, CONVERT(CAST(a.`sg_min` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`sg_mean` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`sg_median` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`sg_max` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`temperature_min_c` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`temperature_mean_c` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`temperature_max_c` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`pressure_min_bar` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`pressure_mean_bar` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`pressure_max_bar` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`rssi_min_dbm` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`rssi_mean_dbm` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`rssi_max_dbm` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`, a.`updated_at`)), COUNT(*) FROM `measurements_5m` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope) GROUP BY DATE(a.`bucket_at`), a.session_id;
 DECLARE CONTINUE HANDLER FOR NOT FOUND SET ga_done=TRUE;
 OPEN ga_chunks;
 ga_days: LOOP
 FETCH ga_chunks INTO v_stage, v_expected;
 IF ga_done THEN LEAVE ga_days; END IF;
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_measurements_5m`(`session_id`, `bucket_at`, `sample_count`, `sg_min`, `sg_mean`, `sg_median`, `sg_max`, `temperature_min_c`, `temperature_mean_c`, `temperature_max_c`, `pressure_min_bar`, `pressure_mean_bar`, `pressure_max_bar`, `rssi_min_dbm`, `rssi_mean_dbm`, `rssi_max_dbm`, `created_at`, `updated_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 datetime(3) PATH '$[1]', c2 int(11) PATH '$[2]', c3 decimal(7, 5) PATH '$[3]', c4 decimal(7, 5) PATH '$[4]', c5 decimal(7, 5) PATH '$[5]', c6 decimal(7, 5) PATH '$[6]', c7 decimal(8, 3) PATH '$[7]', c8 decimal(8, 3) PATH '$[8]', c9 decimal(8, 3) PATH '$[9]', c10 decimal(8, 4) PATH '$[10]', c11 decimal(8, 4) PATH '$[11]', c12 decimal(8, 4) PATH '$[12]', c13 decimal(8, 3) PATH '$[13]', c14 decimal(8, 3) PATH '$[14]', c15 decimal(8, 3) PATH '$[15]', c16 datetime(3) PATH '$[16]', c17 datetime(3) PATH '$[17]')) j;
 END LOOP;
 CLOSE ga_chunks;
 END;
 SET v_step='source:metrics';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`metric_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`sort_order`, CONVERT(a.`label` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`unit` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`display_decimals`, CONVERT(a.`source_class` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `metrics` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_metrics`(`metric_id`, `sort_order`, `label`, `unit`, `display_decimals`, `source_class`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 int(11) PATH '$[1]', c2 varchar(255) PATH '$[2]', c3 varchar(64) PATH '$[3]', c4 int(11) PATH '$[4]', c5 varchar(32) PATH '$[5]', c6 datetime(3) PATH '$[6]')) j;
 END IF;
 SET v_step='source:observation_round_revisions';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`observation_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`observation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`revision_no`, CONVERT(a.`supersedes_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`status` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`recorded_at`, CONVERT(a.`measurement_method_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`measured_sg` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`sample_temperature_c` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`calibration_temperature_c` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`corrected_sg` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`manual_temperature_c` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`pressure_bar` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`cooler_setpoint_c` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`cooler_calibration_offset_c` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`estimated_abv_percent` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`estimated_finished_abv_percent` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`airlock_activity` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`acetaldehyde_level`, a.`diacetyl_level`, a.`wort_like_level`, a.`sulfur_so2_level`, a.`sulfur_h2s_level`, a.`clarity_level`, a.`settling_yeast_level`, CONVERT(CAST(a.`settling_minutes` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`user_conclusion` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`calculated_conclusion` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`process_gate_status` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`corrected_sg_model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`abv_now_model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`estimated_finished_abv_model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`actual_og_used` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`note` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`revision_reason` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `observation_round_revisions` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_observation_round_revisions`(`observation_revision_id`, `observation_id`, `session_id`, `revision_no`, `supersedes_revision_id`, `status`, `recorded_at`, `measurement_method_id`, `measured_sg`, `sample_temperature_c`, `calibration_temperature_c`, `corrected_sg`, `manual_temperature_c`, `pressure_bar`, `cooler_setpoint_c`, `cooler_calibration_offset_c`, `estimated_abv_percent`, `estimated_finished_abv_percent`, `airlock_activity`, `acetaldehyde_level`, `diacetyl_level`, `wort_like_level`, `sulfur_so2_level`, `sulfur_h2s_level`, `clarity_level`, `settling_yeast_level`, `settling_minutes`, `user_conclusion`, `calculated_conclusion`, `process_gate_status`, `corrected_sg_model_id`, `abv_now_model_id`, `estimated_finished_abv_model_id`, `actual_og_used`, `note`, `revision_reason`, `operation_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 int(11) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 varchar(16) PATH '$[5]', c6 datetime(3) PATH '$[6]', c7 varchar(128) PATH '$[7]', c8 decimal(7, 5) PATH '$[8]', c9 decimal(8, 3) PATH '$[9]', c10 decimal(8, 3) PATH '$[10]', c11 decimal(7, 5) PATH '$[11]', c12 decimal(8, 3) PATH '$[12]', c13 decimal(8, 4) PATH '$[13]', c14 decimal(8, 3) PATH '$[14]', c15 decimal(8, 3) PATH '$[15]', c16 decimal(8, 3) PATH '$[16]', c17 decimal(8, 3) PATH '$[17]', c18 varchar(64) PATH '$[18]', c19 int(11) PATH '$[19]', c20 int(11) PATH '$[20]', c21 int(11) PATH '$[21]', c22 int(11) PATH '$[22]', c23 int(11) PATH '$[23]', c24 int(11) PATH '$[24]', c25 int(11) PATH '$[25]', c26 decimal(12, 3) PATH '$[26]', c27 varchar(128) PATH '$[27]', c28 varchar(128) PATH '$[28]', c29 varchar(64) PATH '$[29]', c30 varchar(128) PATH '$[30]', c31 varchar(128) PATH '$[31]', c32 varchar(128) PATH '$[32]', c33 decimal(7, 5) PATH '$[33]', c34 text PATH '$[34]', c35 text PATH '$[35]', c36 varchar(128) PATH '$[36]', c37 datetime(3) PATH '$[37]')) j;
 END IF;
 SET v_step='source:observation_rounds';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`observation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `observation_rounds` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_observation_rounds`(`observation_id`, `session_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 datetime(3) PATH '$[2]')) j;
 END IF;
 SET v_step='source:operator_actions';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`action_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`action_name` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`entity_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`label` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`pressed_at`, a.`completed_at`, CONVERT(a.`outcome` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`accepted`, CONVERT(a.`state_before` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`state_after` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`technical_error` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`field_error` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`detail_text` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `operator_actions` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_operator_actions`(`action_id`, `session_id`, `operation_id`, `action_name`, `entity_id`, `label`, `pressed_at`, `completed_at`, `outcome`, `accepted`, `state_before`, `state_after`, `technical_error`, `field_error`, `detail_text`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(255) PATH '$[4]', c5 varchar(255) PATH '$[5]', c6 datetime(3) PATH '$[6]', c7 datetime(3) PATH '$[7]', c8 varchar(32) PATH '$[8]', c9 tinyint(4) PATH '$[9]', c10 varchar(64) PATH '$[10]', c11 varchar(64) PATH '$[11]', c12 text PATH '$[12]', c13 text PATH '$[13]', c14 text PATH '$[14]', c15 datetime(3) PATH '$[15]')) j;
 END IF;
 SET v_step='source:process_criterion_exceptions';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`exception_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`evaluation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`criterion_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`revision_no`, CONVERT(a.`supersedes_exception_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`action` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`exception_type` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`confirmed`, CONVERT(a.`note` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `process_criterion_exceptions` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_process_criterion_exceptions`(`exception_id`, `session_id`, `evaluation_id`, `criterion_id`, `revision_no`, `supersedes_exception_id`, `action`, `exception_type`, `confirmed`, `note`, `operation_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 int(11) PATH '$[4]', c5 varchar(128) PATH '$[5]', c6 varchar(16) PATH '$[6]', c7 varchar(64) PATH '$[7]', c8 tinyint(4) PATH '$[8]', c9 text PATH '$[9]', c10 varchar(128) PATH '$[10]', c11 datetime(3) PATH '$[11]')) j;
 END IF;
 SET v_step='source:process_evaluation_criteria';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`evaluation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`candidate_process_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`criterion_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`criterion_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`criterion_order`, CONVERT(a.`role_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`metric_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`met`, a.`valid`, CONVERT(a.`evaluation_status` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`actual_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`actual_text` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`measured_at`, CONVERT(a.`source` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`data_window_started_at`, a.`data_window_ended_at`, a.`requested_window_seconds`, a.`sample_count`, a.`coverage_seconds`, a.`latest_sample_at`, CONVERT(a.`explanation` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `process_evaluation_criteria` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_process_evaluation_criteria`(`evaluation_id`, `session_id`, `candidate_process_id`, `criterion_id`, `criterion_revision_id`, `criterion_order`, `role_id`, `metric_id`, `model_id`, `met`, `valid`, `evaluation_status`, `actual_value`, `actual_text`, `measured_at`, `source`, `data_window_started_at`, `data_window_ended_at`, `requested_window_seconds`, `sample_count`, `coverage_seconds`, `latest_sample_at`, `explanation`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 int(11) PATH '$[5]', c6 varchar(128) PATH '$[6]', c7 varchar(128) PATH '$[7]', c8 varchar(128) PATH '$[8]', c9 tinyint(4) PATH '$[9]', c10 tinyint(4) PATH '$[10]', c11 varchar(32) PATH '$[11]', c12 decimal(18, 6) PATH '$[12]', c13 text PATH '$[13]', c14 datetime(3) PATH '$[14]', c15 varchar(128) PATH '$[15]', c16 datetime(3) PATH '$[16]', c17 datetime(3) PATH '$[17]', c18 int(11) PATH '$[18]', c19 int(11) PATH '$[19]', c20 int(11) PATH '$[20]', c21 datetime(3) PATH '$[21]', c22 text PATH '$[22]', c23 datetime(3) PATH '$[23]')) j;
 END IF;
 SET v_step='source:process_evaluation_criterion_parameter_values';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`evaluation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`criterion_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`parameter_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`data_type` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`real_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`integer_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`boolean_value`, CONVERT(a.`text_value` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`is_unset`, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `process_evaluation_criterion_parameter_values` a WHERE EXISTS(SELECT 1 FROM `ga_rb_t_process_evaluation_criteria` p WHERE p.`evaluation_id`=a.`evaluation_id` AND p.`criterion_id`=a.`criterion_id` AND p.`model_id`=a.`model_id`);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_process_evaluation_criterion_parameter_values`(`evaluation_id`, `criterion_id`, `model_id`, `parameter_id`, `data_type`, `real_value`, `integer_value`, `boolean_value`, `text_value`, `is_unset`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(32) PATH '$[4]', c5 decimal(18, 6) PATH '$[5]', c6 bigint(20) PATH '$[6]', c7 tinyint(4) PATH '$[7]', c8 text PATH '$[8]', c9 tinyint(4) PATH '$[9]', c10 datetime(3) PATH '$[10]')) j;
 END IF;
 SET v_step='source:process_evaluations';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`evaluation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`current_process_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`candidate_process_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`active_visit_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`observation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`observation_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`evaluated_at`, CONVERT(a.`readiness` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`data_quality` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`summary` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`recommended_temperature_c` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`recommended_pressure_bar` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`engine_version` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `process_evaluations` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_process_evaluations`(`evaluation_id`, `session_id`, `current_process_id`, `candidate_process_id`, `active_visit_id`, `observation_id`, `observation_revision_id`, `evaluated_at`, `readiness`, `data_quality`, `summary`, `recommended_temperature_c`, `recommended_pressure_bar`, `engine_version`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 varchar(128) PATH '$[5]', c6 varchar(128) PATH '$[6]', c7 datetime(3) PATH '$[7]', c8 varchar(64) PATH '$[8]', c9 varchar(64) PATH '$[9]', c10 text PATH '$[10]', c11 decimal(8, 3) PATH '$[11]', c12 decimal(8, 4) PATH '$[12]', c13 varchar(96) PATH '$[13]', c14 datetime(3) PATH '$[14]')) j;
 END IF;
 SET v_step='source:process_transitions';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`transition_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`transitioned_at`, CONVERT(a.`from_visit_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`to_visit_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`from_process_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`to_process_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`action` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`evaluation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`recommendation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`recommended_temperature_c` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`recommended_pressure_bar` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`operator_temperature_setting_c` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`operator_pressure_setting_bar` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`note` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `process_transitions` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_process_transitions`(`transition_id`, `session_id`, `transitioned_at`, `from_visit_id`, `to_visit_id`, `from_process_id`, `to_process_id`, `action`, `evaluation_id`, `recommendation_id`, `operation_id`, `recommended_temperature_c`, `recommended_pressure_bar`, `operator_temperature_setting_c`, `operator_pressure_setting_bar`, `note`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 datetime(3) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 varchar(128) PATH '$[5]', c6 varchar(128) PATH '$[6]', c7 varchar(32) PATH '$[7]', c8 varchar(128) PATH '$[8]', c9 varchar(128) PATH '$[9]', c10 varchar(128) PATH '$[10]', c11 decimal(8, 3) PATH '$[11]', c12 decimal(8, 4) PATH '$[12]', c13 decimal(8, 3) PATH '$[13]', c14 decimal(8, 4) PATH '$[14]', c15 text PATH '$[15]', c16 datetime(3) PATH '$[16]')) j;
 END IF;
 SET v_step='source:process_visits';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`visit_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`process_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`visit_seq` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `process_visits` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_process_visits`(`visit_id`, `session_id`, `process_id`, `visit_seq`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 bigint(20) unsigned PATH '$[3]', c4 datetime(3) PATH '$[4]')) j;
 END IF;
 SET v_step='source:process_visit_revisions';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`visit_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`visit_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`revision_no`, CONVERT(a.`supersedes_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`started_at`, a.`ended_at`, CONVERT(a.`timing_source` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`revision_reason` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `process_visit_revisions` a WHERE EXISTS(SELECT 1 FROM `ga_rb_t_process_visits` p WHERE p.`visit_id`=a.`visit_id`);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_process_visit_revisions`(`visit_revision_id`, `visit_id`, `revision_no`, `supersedes_revision_id`, `started_at`, `ended_at`, `timing_source`, `revision_reason`, `operation_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 int(11) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 datetime(3) PATH '$[4]', c5 datetime(3) PATH '$[5]', c6 varchar(64) PATH '$[6]', c7 text PATH '$[7]', c8 varchar(128) PATH '$[8]', c9 datetime(3) PATH '$[9]')) j;
 END IF;
 SET v_step='source:recommendation_resolutions';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`resolution_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`recommendation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`outcome` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`actual_action` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`note` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `recommendation_resolutions` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_recommendation_resolutions`(`resolution_id`, `recommendation_id`, `session_id`, `outcome`, `actual_action`, `note`, `operation_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(16) PATH '$[3]', c4 text PATH '$[4]', c5 text PATH '$[5]', c6 varchar(128) PATH '$[6]', c7 datetime(3) PATH '$[7]')) j;
 END IF;
 SET v_step='source:recommendations';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`recommendation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`evaluation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`observation_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`severity` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`rule_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`recommendation_type` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_version` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`title` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`explanation` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`source` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`uncertainty` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`supersedes_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `recommendations` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_recommendations`(`recommendation_id`, `session_id`, `evaluation_id`, `observation_revision_id`, `severity`, `rule_id`, `recommendation_type`, `model_version`, `title`, `explanation`, `source`, `uncertainty`, `supersedes_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(32) PATH '$[4]', c5 varchar(128) PATH '$[5]', c6 varchar(96) PATH '$[6]', c7 varchar(96) PATH '$[7]', c8 varchar(255) PATH '$[8]', c9 text PATH '$[9]', c10 varchar(255) PATH '$[10]', c11 varchar(64) PATH '$[11]', c12 varchar(128) PATH '$[12]', c13 datetime(3) PATH '$[13]')) j;
 END IF;
 SET v_step='source:session_analysis_graph_series';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`graph_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`series_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`sort_order`, CONVERT(a.`label` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`source_kind` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`metric_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`owner_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`criterion_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`minimum_samples`, CONVERT(CAST(a.`minimum_coverage_fraction` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`warmup_minutes`, CONVERT(CAST(a.`valid_minimum_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`valid_maximum_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`provisional_allowed`, a.`provisional_minimum_samples`, CONVERT(CAST(a.`provisional_minimum_span_minutes` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`render_mode` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`band_model` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`band_description` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`standard_color` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`provisional_color` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`standard_dasharray` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`provisional_dasharray` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`band_opacity` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_analysis_graph_series` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_analysis_graph_series`(`session_id`, `graph_id`, `series_id`, `sort_order`, `label`, `source_kind`, `metric_id`, `owner_id`, `criterion_id`, `minimum_samples`, `minimum_coverage_fraction`, `warmup_minutes`, `valid_minimum_value`, `valid_maximum_value`, `provisional_allowed`, `provisional_minimum_samples`, `provisional_minimum_span_minutes`, `render_mode`, `band_model`, `band_description`, `standard_color`, `provisional_color`, `standard_dasharray`, `provisional_dasharray`, `band_opacity`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 int(11) PATH '$[3]', c4 varchar(255) PATH '$[4]', c5 varchar(32) PATH '$[5]', c6 varchar(128) PATH '$[6]', c7 varchar(128) PATH '$[7]', c8 varchar(128) PATH '$[8]', c9 int(11) PATH '$[9]', c10 decimal(8, 6) PATH '$[10]', c11 int(11) PATH '$[11]', c12 decimal(18, 6) PATH '$[12]', c13 decimal(18, 6) PATH '$[13]', c14 tinyint(4) PATH '$[14]', c15 int(11) PATH '$[15]', c16 decimal(18, 6) PATH '$[16]', c17 varchar(16) PATH '$[17]', c18 varchar(32) PATH '$[18]', c19 text PATH '$[19]', c20 char(7) PATH '$[20]', c21 char(7) PATH '$[21]', c22 varchar(32) PATH '$[22]', c23 varchar(32) PATH '$[23]', c24 decimal(4, 3) PATH '$[24]', c25 datetime(3) PATH '$[25]')) j;
 END IF;
END//
CREATE PROCEDURE ga_fill_read_basis_part_3() BEGIN
 DECLARE v_stage LONGTEXT; DECLARE v_expected BIGINT; DECLARE v_step VARCHAR(128); DECLARE v_error TEXT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_error=MESSAGE_TEXT; SET v_error=CONCAT(v_step, ': ', LEFT(v_error, 350)); RESIGNAL SET MESSAGE_TEXT=v_error; END;
 SET v_step='source:session_analysis_graphs';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`graph_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`sort_order`, CONVERT(a.`label` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`description` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`unit` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`display_decimals`, CONVERT(CAST(a.`y_axis_min` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`y_axis_max` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`y_axis_tick_step` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`y_axis_include_zero`, CONVERT(a.`x_axis_mode` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`enabled`, a.`show_biological_bands`, a.`show_process_markers`, a.`show_criterion_markers`, CONVERT(a.`gap_policy` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_analysis_graphs` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_analysis_graphs`(`session_id`, `graph_id`, `sort_order`, `label`, `description`, `unit`, `display_decimals`, `y_axis_min`, `y_axis_max`, `y_axis_tick_step`, `y_axis_include_zero`, `x_axis_mode`, `enabled`, `show_biological_bands`, `show_process_markers`, `show_criterion_markers`, `gap_policy`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 int(11) PATH '$[2]', c3 varchar(255) PATH '$[3]', c4 text PATH '$[4]', c5 varchar(64) PATH '$[5]', c6 int(11) PATH '$[6]', c7 decimal(18, 6) PATH '$[7]', c8 decimal(18, 6) PATH '$[8]', c9 decimal(18, 6) PATH '$[9]', c10 tinyint(4) PATH '$[10]', c11 varchar(32) PATH '$[11]', c12 tinyint(4) PATH '$[12]', c13 tinyint(4) PATH '$[13]', c14 tinyint(4) PATH '$[14]', c15 tinyint(4) PATH '$[15]', c16 varchar(32) PATH '$[16]', c17 datetime(3) PATH '$[17]')) j;
 END IF;
 SET v_step='source:session_biological_correctable_parameters';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`phase_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`criterion_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`parameter_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_biological_correctable_parameters` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_biological_correctable_parameters`(`session_id`, `phase_id`, `criterion_id`, `model_id`, `parameter_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 datetime(3) PATH '$[5]')) j;
 END IF;
 SET v_step='source:session_biological_criteria';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`phase_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`criterion_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`criterion_order`, a.`enabled`, CONVERT(a.`metric_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`role_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`label` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`exception_allowed`, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_biological_criteria` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_biological_criteria`(`session_id`, `phase_id`, `criterion_id`, `criterion_order`, `enabled`, `metric_id`, `model_id`, `role_id`, `label`, `exception_allowed`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 int(11) PATH '$[3]', c4 tinyint(4) PATH '$[4]', c5 varchar(128) PATH '$[5]', c6 varchar(128) PATH '$[6]', c7 varchar(128) PATH '$[7]', c8 varchar(255) PATH '$[8]', c9 tinyint(4) PATH '$[9]', c10 datetime(3) PATH '$[10]')) j;
 END IF;
 SET v_step='source:session_biological_criterion_parameter_values';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`phase_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`criterion_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`parameter_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`data_type` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`real_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`integer_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`boolean_value`, CONVERT(a.`text_value` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_biological_criterion_parameter_values` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_biological_criterion_parameter_values`(`session_id`, `phase_id`, `criterion_id`, `model_id`, `parameter_id`, `data_type`, `real_value`, `integer_value`, `boolean_value`, `text_value`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 varchar(32) PATH '$[5]', c6 decimal(18, 6) PATH '$[6]', c7 bigint(20) PATH '$[7]', c8 tinyint(4) PATH '$[8]', c9 text PATH '$[9]', c10 datetime(3) PATH '$[10]')) j;
 END IF;
 SET v_step='source:session_biological_criterion_revisions';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`criterion_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`phase_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`criterion_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`revision_no`, CONVERT(a.`supersedes_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`action` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`confirmed`, CONVERT(a.`note` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_biological_criterion_revisions` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_biological_criterion_revisions`(`criterion_revision_id`, `session_id`, `phase_id`, `criterion_id`, `model_id`, `revision_no`, `supersedes_revision_id`, `action`, `confirmed`, `note`, `operation_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 int(11) PATH '$[5]', c6 varchar(128) PATH '$[6]', c7 varchar(16) PATH '$[7]', c8 tinyint(4) PATH '$[8]', c9 text PATH '$[9]', c10 varchar(128) PATH '$[10]', c11 datetime(3) PATH '$[11]')) j;
 END IF;
 SET v_step='source:session_biological_criterion_revision_parameter_values';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`criterion_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`parameter_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`data_type` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`is_unset`, CONVERT(CAST(a.`real_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`integer_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`boolean_value`, CONVERT(a.`text_value` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_biological_criterion_revision_parameter_values` a WHERE EXISTS(SELECT 1 FROM `ga_rb_t_session_biological_criterion_revisions` p WHERE p.`criterion_revision_id`=a.`criterion_revision_id` AND p.`model_id`=a.`model_id`);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_biological_criterion_revision_parameter_values`(`criterion_revision_id`, `model_id`, `parameter_id`, `data_type`, `is_unset`, `real_value`, `integer_value`, `boolean_value`, `text_value`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(32) PATH '$[3]', c4 tinyint(4) PATH '$[4]', c5 decimal(18, 6) PATH '$[5]', c6 bigint(20) PATH '$[6]', c7 tinyint(4) PATH '$[7]', c8 text PATH '$[8]', c9 datetime(3) PATH '$[9]')) j;
 END IF;
 SET v_step='source:session_biological_phases';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`phase_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`phase_order`, CONVERT(a.`name` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`description` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_biological_phases` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_biological_phases`(`session_id`, `phase_id`, `phase_order`, `name`, `description`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 int(11) PATH '$[2]', c3 varchar(255) PATH '$[3]', c4 text PATH '$[4]', c5 datetime(3) PATH '$[5]')) j;
 END IF;
 SET v_step='source:session_biology_calculation_parameter_values';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`calculation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`parameter_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`data_type` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`real_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`integer_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`boolean_value`, CONVERT(a.`text_value` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_biology_calculation_parameter_values` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_biology_calculation_parameter_values`(`session_id`, `calculation_id`, `model_id`, `parameter_id`, `data_type`, `real_value`, `integer_value`, `boolean_value`, `text_value`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(32) PATH '$[4]', c5 decimal(18, 6) PATH '$[5]', c6 bigint(20) PATH '$[6]', c7 tinyint(4) PATH '$[7]', c8 varchar(255) PATH '$[8]', c9 datetime(3) PATH '$[9]')) j;
 END IF;
 SET v_step='source:session_demo_sources';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`profile_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`interval_seconds`, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_demo_sources` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_demo_sources`(`session_id`, `profile_id`, `interval_seconds`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 int(11) PATH '$[2]', c3 datetime(3) PATH '$[3]')) j;
 END IF;
 SET v_step='source:session_export_attempts';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`attempt_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`export_kind` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`attempt_no` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`requested_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_export_attempts` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_export_attempts`(`attempt_id`, `session_id`, `export_kind`, `attempt_no`, `requested_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(32) PATH '$[2]', c3 bigint(20) unsigned PATH '$[3]', c4 datetime(3) PATH '$[4]')) j;
 END IF;
 SET v_step='source:session_exports';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`export_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`export_kind` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`attempt_no`, CONVERT(a.`status` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`archive_path` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`archive_sha256` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`archive_bytes` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`report_path` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`report_sha256` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`report_bytes` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`template_path` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`template_sha256` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`template_bytes` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`error_message` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`completed_at`, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_exports` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_exports`(`export_id`, `session_id`, `export_kind`, `attempt_no`, `status`, `archive_path`, `archive_sha256`, `archive_bytes`, `report_path`, `report_sha256`, `report_bytes`, `template_path`, `template_sha256`, `template_bytes`, `error_message`, `operation_id`, `completed_at`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(32) PATH '$[2]', c3 int(11) PATH '$[3]', c4 varchar(16) PATH '$[4]', c5 text PATH '$[5]', c6 char(64) PATH '$[6]', c7 bigint(20) unsigned PATH '$[7]', c8 text PATH '$[8]', c9 char(64) PATH '$[9]', c10 bigint(20) unsigned PATH '$[10]', c11 text PATH '$[11]', c12 char(64) PATH '$[12]', c13 bigint(20) unsigned PATH '$[13]', c14 text PATH '$[14]', c15 varchar(128) PATH '$[15]', c16 datetime(3) PATH '$[16]', c17 datetime(3) PATH '$[17]')) j;
 END IF;
 SET v_step='source:session_fermentation_targets';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`expected_attenuation_min_percent` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`expected_attenuation_max_percent` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`expected_fg_min` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`expected_fg_max` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`source` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_fermentation_targets` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_fermentation_targets`(`session_id`, `expected_attenuation_min_percent`, `expected_attenuation_max_percent`, `expected_fg_min`, `expected_fg_max`, `source`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 decimal(8, 4) PATH '$[1]', c2 decimal(8, 4) PATH '$[2]', c3 decimal(7, 5) PATH '$[3]', c4 decimal(7, 5) PATH '$[4]', c5 varchar(64) PATH '$[5]', c6 datetime(3) PATH '$[6]')) j;
 END IF;
 SET v_step='source:session_history_windows';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`ended_at`, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_history_windows` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_history_windows`(`session_id`, `ended_at`, `operation_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 datetime(3) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 datetime(3) PATH '$[3]')) j;
 END IF;
 SET v_step='source:session_lifecycle_events';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`lifecycle_event_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`lifecycle` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`occurred_at`, CONVERT(a.`note` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_lifecycle_events` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_lifecycle_events`(`lifecycle_event_id`, `session_id`, `lifecycle`, `occurred_at`, `note`, `operation_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(32) PATH '$[2]', c3 datetime(3) PATH '$[3]', c4 text PATH '$[4]', c5 varchar(128) PATH '$[5]', c6 datetime(3) PATH '$[6]')) j;
 END IF;
 SET v_step='source:session_measurement_signal_bindings';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`configuration_id` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`signal_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`input_mode` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`entity_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`unit_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`minimum_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`maximum_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci)), COUNT(*) INTO v_stage, v_expected FROM `session_measurement_signal_bindings` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_measurement_signal_bindings`(`session_id`, `configuration_id`, `signal_id`, `input_mode`, `entity_id`, `unit_id`, `minimum_value`, `maximum_value`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 bigint(20) unsigned PATH '$[1]', c2 varchar(32) PATH '$[2]', c3 varchar(16) PATH '$[3]', c4 varchar(255) PATH '$[4]', c5 varchar(32) PATH '$[5]', c6 decimal(24, 8) PATH '$[6]', c7 decimal(24, 8) PATH '$[7]')) j;
 END IF;
 SET v_step='source:session_measurement_source_configurations';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`configuration_id` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`effective_from`, CONVERT(a.`profile_name` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`note` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_measurement_source_configurations` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_measurement_source_configurations`(`session_id`, `configuration_id`, `effective_from`, `profile_name`, `note`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 bigint(20) unsigned PATH '$[1]', c2 datetime(3) PATH '$[2]', c3 varchar(255) PATH '$[3]', c4 text PATH '$[4]', c5 datetime(3) PATH '$[5]')) j;
 END IF;
 SET v_step='source:session_measurement_sources';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`source_profile_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`source_started_at`, a.`last_import_cutoff_at`, a.`last_success_at`, CONVERT(a.`last_error` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`, a.`updated_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_measurement_sources` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_measurement_sources`(`session_id`, `source_profile_id`, `source_started_at`, `last_import_cutoff_at`, `last_success_at`, `last_error`, `created_at`, `updated_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 datetime(3) PATH '$[2]', c3 datetime(3) PATH '$[3]', c4 datetime(3) PATH '$[4]', c5 text PATH '$[5]', c6 datetime(3) PATH '$[6]', c7 datetime(3) PATH '$[7]')) j;
 END IF;
 SET v_step='source:session_metric_runtime_inputs';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`metric_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`input_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`source_kind` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`source_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_metric_runtime_inputs` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_metric_runtime_inputs`(`session_id`, `metric_id`, `model_id`, `input_id`, `source_kind`, `source_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(32) PATH '$[4]', c5 varchar(128) PATH '$[5]', c6 datetime(3) PATH '$[6]')) j;
 END IF;
 SET v_step='source:session_metric_runtime_parameter_values';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`metric_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`parameter_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`data_type` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`real_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`integer_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`boolean_value`, CONVERT(a.`text_value` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_metric_runtime_parameter_values` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_metric_runtime_parameter_values`(`session_id`, `metric_id`, `model_id`, `parameter_id`, `data_type`, `real_value`, `integer_value`, `boolean_value`, `text_value`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(32) PATH '$[4]', c5 decimal(18, 6) PATH '$[5]', c6 bigint(20) PATH '$[6]', c7 tinyint(4) PATH '$[7]', c8 varchar(255) PATH '$[8]', c9 datetime(3) PATH '$[9]')) j;
 END IF;
 SET v_step='source:session_metric_runtime_rules';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`metric_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`calculation_model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`freshness_mode` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`valid_minimum_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`valid_maximum_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_metric_runtime_rules` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_metric_runtime_rules`(`session_id`, `metric_id`, `calculation_model_id`, `freshness_mode`, `valid_minimum_value`, `valid_maximum_value`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(32) PATH '$[3]', c4 decimal(18, 6) PATH '$[4]', c5 decimal(18, 6) PATH '$[5]', c6 datetime(3) PATH '$[6]')) j;
 END IF;
 SET v_step='source:session_notes';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`note_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`noted_at`, CONVERT(a.`note_text` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_notes` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_notes`(`note_id`, `session_id`, `noted_at`, `note_text`, `operation_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 datetime(3) PATH '$[2]', c3 text PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 datetime(3) PATH '$[5]')) j;
 END IF;
 SET v_step='source:session_process_action_operator';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`process_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`action_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`action_type_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operator_operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_process_action_operator` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_process_action_operator`(`session_id`, `process_id`, `action_id`, `action_type_id`, `operator_operation_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 datetime(3) PATH '$[5]')) j;
 END IF;
 SET v_step='source:session_process_action_set_target';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`process_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`action_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`action_type_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`target_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_process_action_set_target` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_process_action_set_target`(`session_id`, `process_id`, `action_id`, `action_type_id`, `target_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 datetime(3) PATH '$[5]')) j;
 END IF;
 SET v_step='source:session_process_actions';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`process_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`action_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`action_order`, CONVERT(a.`action_type_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`label` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_process_actions` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_process_actions`(`session_id`, `process_id`, `action_id`, `action_order`, `action_type_id`, `label`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 int(11) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 varchar(255) PATH '$[5]', c6 datetime(3) PATH '$[6]')) j;
 END IF;
 SET v_step='source:session_process_correctable_parameters';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`process_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`criterion_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`parameter_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_process_correctable_parameters` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_process_correctable_parameters`(`session_id`, `process_id`, `criterion_id`, `model_id`, `parameter_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 datetime(3) PATH '$[5]')) j;
 END IF;
 SET v_step='source:session_process_criteria';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`process_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`criterion_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`criterion_order`, a.`enabled`, CONVERT(a.`metric_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`role_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`label` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`exception_allowed`, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_process_criteria` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_process_criteria`(`session_id`, `process_id`, `criterion_id`, `criterion_order`, `enabled`, `metric_id`, `model_id`, `role_id`, `label`, `exception_allowed`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 int(11) PATH '$[3]', c4 tinyint(4) PATH '$[4]', c5 varchar(128) PATH '$[5]', c6 varchar(128) PATH '$[6]', c7 varchar(128) PATH '$[7]', c8 varchar(255) PATH '$[8]', c9 tinyint(4) PATH '$[9]', c10 datetime(3) PATH '$[10]')) j;
 END IF;
END//
CREATE PROCEDURE ga_fill_read_basis_part_4() BEGIN
 DECLARE v_stage LONGTEXT; DECLARE v_expected BIGINT; DECLARE v_step VARCHAR(128); DECLARE v_error TEXT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_error=MESSAGE_TEXT; SET v_error=CONCAT(v_step, ': ', LEFT(v_error, 350)); RESIGNAL SET MESSAGE_TEXT=v_error; END;
 SET v_step='source:session_process_criterion_parameter_values';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`process_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`criterion_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`parameter_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`data_type` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`real_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`integer_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`boolean_value`, CONVERT(a.`text_value` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_process_criterion_parameter_values` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_process_criterion_parameter_values`(`session_id`, `process_id`, `criterion_id`, `model_id`, `parameter_id`, `data_type`, `real_value`, `integer_value`, `boolean_value`, `text_value`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 varchar(32) PATH '$[5]', c6 decimal(18, 6) PATH '$[6]', c7 bigint(20) PATH '$[7]', c8 tinyint(4) PATH '$[8]', c9 text PATH '$[9]', c10 datetime(3) PATH '$[10]')) j;
 END IF;
 SET v_step='source:session_process_criterion_revisions';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`criterion_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`process_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`criterion_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`revision_no`, CONVERT(a.`supersedes_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`action` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`confirmed`, CONVERT(a.`note` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_process_criterion_revisions` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_process_criterion_revisions`(`criterion_revision_id`, `session_id`, `process_id`, `criterion_id`, `model_id`, `revision_no`, `supersedes_revision_id`, `action`, `confirmed`, `note`, `operation_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 int(11) PATH '$[5]', c6 varchar(128) PATH '$[6]', c7 varchar(16) PATH '$[7]', c8 tinyint(4) PATH '$[8]', c9 text PATH '$[9]', c10 varchar(128) PATH '$[10]', c11 datetime(3) PATH '$[11]')) j;
 END IF;
 SET v_step='source:session_process_criterion_revision_parameter_values';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`criterion_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`parameter_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`data_type` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`is_unset`, CONVERT(CAST(a.`real_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`integer_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`boolean_value`, CONVERT(a.`text_value` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_process_criterion_revision_parameter_values` a WHERE EXISTS(SELECT 1 FROM `ga_rb_t_session_process_criterion_revisions` p WHERE p.`criterion_revision_id`=a.`criterion_revision_id` AND p.`model_id`=a.`model_id`);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_process_criterion_revision_parameter_values`(`criterion_revision_id`, `model_id`, `parameter_id`, `data_type`, `is_unset`, `real_value`, `integer_value`, `boolean_value`, `text_value`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(32) PATH '$[3]', c4 tinyint(4) PATH '$[4]', c5 decimal(18, 6) PATH '$[5]', c6 bigint(20) PATH '$[6]', c7 tinyint(4) PATH '$[7]', c8 text PATH '$[8]', c9 datetime(3) PATH '$[9]')) j;
 END IF;
 SET v_step='source:session_process_steps';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`process_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`slot_no`, a.`process_order`, CONVERT(a.`name` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`description` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`enabled`, a.`historical_replay_auto_transition_allowed`, CONVERT(a.`anchor_type` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`anchor_biological_phase_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`anchor_offset_hours` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_process_steps` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_process_steps`(`session_id`, `process_id`, `slot_no`, `process_order`, `name`, `description`, `enabled`, `historical_replay_auto_transition_allowed`, `anchor_type`, `anchor_biological_phase_id`, `anchor_offset_hours`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 int(11) PATH '$[2]', c3 int(11) PATH '$[3]', c4 varchar(255) PATH '$[4]', c5 text PATH '$[5]', c6 tinyint(4) PATH '$[6]', c7 tinyint(4) PATH '$[7]', c8 varchar(64) PATH '$[8]', c9 varchar(128) PATH '$[9]', c10 decimal(12, 4) PATH '$[10]', c11 datetime(3) PATH '$[11]')) j;
 END IF;
 SET v_step='source:session_process_target_exact';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`process_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`target_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`target_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_process_target_exact` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_process_target_exact`(`session_id`, `process_id`, `target_id`, `model_id`, `target_value`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 decimal(18, 6) PATH '$[4]', c5 datetime(3) PATH '$[5]')) j;
 END IF;
 SET v_step='source:session_process_target_range';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`process_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`target_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`minimum_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`maximum_value` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_process_target_range` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_process_target_range`(`session_id`, `process_id`, `target_id`, `model_id`, `minimum_value`, `maximum_value`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 decimal(18, 6) PATH '$[4]', c5 decimal(18, 6) PATH '$[5]', c6 datetime(3) PATH '$[6]')) j;
 END IF;
 SET v_step='source:session_process_targets';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`process_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`target_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`target_order`, CONVERT(a.`metric_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`model_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`label` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`purpose` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_process_targets` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_process_targets`(`session_id`, `process_id`, `target_id`, `target_order`, `metric_id`, `model_id`, `label`, `purpose`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 int(11) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 varchar(128) PATH '$[5]', c6 varchar(255) PATH '$[6]', c7 text PATH '$[7]', c8 datetime(3) PATH '$[8]')) j;
 END IF;
 SET v_step='source:session_release_events';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`release_event_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`released_at`, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_release_events` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_release_events`(`release_event_id`, `session_id`, `released_at`, `operation_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 datetime(3) PATH '$[2]', c3 varchar(128) PATH '$[3]', c4 datetime(3) PATH '$[4]')) j;
 END IF;
 SET v_step='source:session_template_defaults';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`batch_name_default` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`volume_l_default` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`og_default` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`expected_attenuation_min_percent` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`expected_attenuation_max_percent` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`expected_fg_min` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`expected_fg_max` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`pitch_temperature_c_default` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`pitch_mode_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`yeast_profile_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`yeast_amount_g_default` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`measurement_method_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`sample_temperature_c_default` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`calibration_temperature_c_default` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`manual_temperature_c_default` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`pressure_bar_default` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`cooler_setpoint_c_default` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`cooler_calibration_offset_c_default` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`airlock_activity_default` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`acetaldehyde_level_default`, a.`diacetyl_level_default`, a.`wort_like_level_default`, a.`sulfur_so2_level_default`, a.`sulfur_h2s_level_default`, a.`clarity_level_default`, a.`settling_yeast_level_default`, CONVERT(CAST(a.`settling_minutes_default` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`user_conclusion_default` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`measurement_note_default` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_template_defaults` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_template_defaults`(`session_id`, `batch_name_default`, `volume_l_default`, `og_default`, `expected_attenuation_min_percent`, `expected_attenuation_max_percent`, `expected_fg_min`, `expected_fg_max`, `pitch_temperature_c_default`, `pitch_mode_id`, `yeast_profile_id`, `yeast_amount_g_default`, `measurement_method_id`, `sample_temperature_c_default`, `calibration_temperature_c_default`, `manual_temperature_c_default`, `pressure_bar_default`, `cooler_setpoint_c_default`, `cooler_calibration_offset_c_default`, `airlock_activity_default`, `acetaldehyde_level_default`, `diacetyl_level_default`, `wort_like_level_default`, `sulfur_so2_level_default`, `sulfur_h2s_level_default`, `clarity_level_default`, `settling_yeast_level_default`, `settling_minutes_default`, `user_conclusion_default`, `measurement_note_default`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(255) PATH '$[1]', c2 decimal(10, 3) PATH '$[2]', c3 decimal(7, 5) PATH '$[3]', c4 decimal(8, 4) PATH '$[4]', c5 decimal(8, 4) PATH '$[5]', c6 decimal(7, 5) PATH '$[6]', c7 decimal(7, 5) PATH '$[7]', c8 decimal(8, 3) PATH '$[8]', c9 varchar(128) PATH '$[9]', c10 varchar(128) PATH '$[10]', c11 decimal(10, 3) PATH '$[11]', c12 varchar(128) PATH '$[12]', c13 decimal(8, 3) PATH '$[13]', c14 decimal(8, 3) PATH '$[14]', c15 decimal(8, 3) PATH '$[15]', c16 decimal(8, 3) PATH '$[16]', c17 decimal(8, 3) PATH '$[17]', c18 decimal(8, 3) PATH '$[18]', c19 varchar(32) PATH '$[19]', c20 int(11) PATH '$[20]', c21 int(11) PATH '$[21]', c22 int(11) PATH '$[22]', c23 int(11) PATH '$[23]', c24 int(11) PATH '$[24]', c25 int(11) PATH '$[25]', c26 int(11) PATH '$[26]', c27 decimal(10, 3) PATH '$[27]', c28 varchar(32) PATH '$[28]', c29 varchar(255) PATH '$[29]', c30 datetime(3) PATH '$[30]')) j;
 END IF;
 SET v_step='source:session_template_snapshots';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`template_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`template_version_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`template_version_label` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`template_store_schema_version`, CONVERT(a.`snapshot_format_version` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`snapshot_sha256` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`source_published_at`, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_template_snapshots` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_template_snapshots`(`session_id`, `template_id`, `template_version_id`, `template_version_label`, `template_store_schema_version`, `snapshot_format_version`, `snapshot_sha256`, `source_published_at`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(128) PATH '$[2]', c3 varchar(64) PATH '$[3]', c4 int(11) PATH '$[4]', c5 varchar(32) PATH '$[5]', c6 char(64) PATH '$[6]', c7 datetime(3) PATH '$[7]', c8 datetime(3) PATH '$[8]')) j;
 END IF;
 SET v_step='source:session_timing_revisions';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`timing_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`timing_field` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`revision_no`, CONVERT(a.`supersedes_revision_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`value_at`, CONVERT(a.`source` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`reason` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `session_timing_revisions` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_session_timing_revisions`(`timing_revision_id`, `session_id`, `timing_field`, `revision_no`, `supersedes_revision_id`, `value_at`, `source`, `reason`, `operation_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(32) PATH '$[2]', c3 int(11) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 datetime(3) PATH '$[5]', c6 varchar(64) PATH '$[6]', c7 text PATH '$[7]', c8 varchar(128) PATH '$[8]', c9 datetime(3) PATH '$[9]')) j;
 END IF;
 SET v_step='source:sessions';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`batch_name` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`is_demo`, a.`created_at`, a.`pitched_at`, CONVERT(CAST(a.`og` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`volume_l` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`yeast_profile_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`pitch_mode_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CAST(a.`pitch_temperature_c` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`oxygenation_note` USING utf8mb4) COLLATE utf8mb4_unicode_ci)), COUNT(*) INTO v_stage, v_expected FROM `sessions` a WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope);
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_sessions`(`session_id`, `batch_name`, `is_demo`, `created_at`, `pitched_at`, `og`, `volume_l`, `yeast_profile_id`, `pitch_mode_id`, `pitch_temperature_c`, `oxygenation_note`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(255) PATH '$[1]', c2 tinyint(4) PATH '$[2]', c3 datetime(3) PATH '$[3]', c4 datetime(3) PATH '$[4]', c5 decimal(7, 5) PATH '$[5]', c6 decimal(10, 3) PATH '$[6]', c7 varchar(128) PATH '$[7]', c8 varchar(128) PATH '$[8]', c9 decimal(8, 3) PATH '$[9]', c10 text PATH '$[10]')) j;
 END IF;
 SET v_step='source:technical_events';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(CAST(a.`event_seq` AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`event_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`schema_version` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`occurred_at`, CONVERT(a.`severity` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`event_type` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`code` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`issue_key` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`subsystem` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`source_component` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`source_node_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`source_node_name` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`source_type` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`operation` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`session_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`process_step` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`correlation_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`message` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`recoverable`, a.`blocks_operation`, CONVERT(a.`related_event_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `technical_events` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_technical_events`(`event_seq`, `event_id`, `schema_version`, `occurred_at`, `severity`, `event_type`, `code`, `issue_key`, `subsystem`, `source_component`, `source_node_id`, `source_node_name`, `source_type`, `operation`, `session_id`, `process_step`, `correlation_id`, `message`, `recoverable`, `blocks_operation`, `related_event_id`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 bigint(20) unsigned PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(32) PATH '$[2]', c3 datetime(3) PATH '$[3]', c4 varchar(16) PATH '$[4]', c5 varchar(32) PATH '$[5]', c6 varchar(128) PATH '$[6]', c7 varchar(255) PATH '$[7]', c8 varchar(128) PATH '$[8]', c9 varchar(128) PATH '$[9]', c10 varchar(128) PATH '$[10]', c11 varchar(255) PATH '$[11]', c12 varchar(128) PATH '$[12]', c13 varchar(128) PATH '$[13]', c14 varchar(128) PATH '$[14]', c15 varchar(128) PATH '$[15]', c16 varchar(128) PATH '$[16]', c17 text PATH '$[17]', c18 tinyint(4) PATH '$[18]', c19 tinyint(4) PATH '$[19]', c20 varchar(128) PATH '$[20]', c21 datetime(3) PATH '$[21]')) j;
 END IF;
 SET v_step='source:template_versions';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`version_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`template_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`status` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`version_label` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`based_on_version_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`name` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`revision_note` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`, a.`published_at`, a.`retired_at`, a.`draft_guard`)), COUNT(*) INTO v_stage, v_expected FROM `template_versions` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_template_versions`(`version_id`, `template_id`, `status`, `version_label`, `based_on_version_id`, `name`, `revision_note`, `created_at`, `published_at`, `retired_at`, `draft_guard`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(128) PATH '$[1]', c2 varchar(32) PATH '$[2]', c3 varchar(64) PATH '$[3]', c4 varchar(128) PATH '$[4]', c5 varchar(255) PATH '$[5]', c6 varchar(1000) PATH '$[6]', c7 datetime(3) PATH '$[7]', c8 datetime(3) PATH '$[8]', c9 datetime(3) PATH '$[9]', c10 tinyint(4) PATH '$[10]')) j;
 END IF;
 SET v_step='source:yeast_profiles';
SELECT JSON_ARRAYAGG(JSON_ARRAY(CONVERT(a.`yeast_profile_id` USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(a.`name` USING utf8mb4) COLLATE utf8mb4_unicode_ci, a.`created_at`)), COUNT(*) INTO v_stage, v_expected FROM `yeast_profiles` a;
 IF v_stage IS NOT NULL THEN
 IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;
 INSERT INTO `ga_rb_t_yeast_profiles`(`yeast_profile_id`, `name`, `created_at`) SELECT j.* FROM JSON_TABLE(v_stage,  '$[*]' COLUMNS(c0 varchar(128) PATH '$[0]', c1 varchar(255) PATH '$[1]', c2 datetime(3) PATH '$[2]')) j;
 END IF;
 SET v_step='view:v_current_session_timing';
 INSERT INTO `ga_rb_v_current_session_timing` SELECT r.*
FROM ga_rb_t_session_timing_revisions r
WHERE NOT EXISTS (
    SELECT 1 FROM ga_rb_t_session_timing_revisions n
    WHERE n.supersedes_revision_id=r.timing_revision_id
);
 SET v_step='view:v_session_lifecycle';
 INSERT INTO `ga_rb_v_session_lifecycle` SELECT e.*
FROM ga_rb_t_session_lifecycle_events e
WHERE NOT EXISTS (
    SELECT 1 FROM ga_rb_t_session_lifecycle_events n
    WHERE n.session_id=e.session_id
      AND (n.occurred_at>e.occurred_at OR (n.occurred_at=e.occurred_at AND n.lifecycle_event_id>e.lifecycle_event_id))
);
 SET v_step='view:v_all_session';
 INSERT INTO `ga_rb_v_all_session` SELECT
    s.session_id, 
    s.batch_name, 
    s.is_demo, 
    s.created_at, 
    COALESCE(tp.value_at, s.pitched_at) AS pitched_at, 
    ta.value_at AS activity_started_at, 
    s.og, 
    s.volume_l, 
    s.yeast_profile_id, 
    s.pitch_mode_id, 
    s.pitch_temperature_c, 
    sl.lifecycle, 
    sl.occurred_at AS lifecycle_at, 
    CASE WHEN sl.lifecycle='completed' THEN sl.occurred_at ELSE NULL END AS completed_at, 
 h.ended_at AS historical_ended_at, 
 IF(h.session_id IS NULL, 0, 1) AS is_historical, 
 COALESCE(h.ended_at, IF(sl.lifecycle='completed', sl.occurred_at, NULL), UTC_TIMESTAMP(3)) AS domain_now
FROM ga_rb_t_sessions s LEFT JOIN ga_rb_t_session_history_windows h ON h.session_id=s.session_id
JOIN ga_rb_v_session_lifecycle sl ON sl.session_id=s.session_id
LEFT JOIN ga_rb_t_session_release_events sr ON sr.session_id=s.session_id
LEFT JOIN ga_rb_v_current_session_timing tp
  ON tp.session_id=s.session_id AND tp.timing_field='pitched_at'
LEFT JOIN ga_rb_v_current_session_timing ta
  ON ta.session_id=s.session_id AND ta.timing_field='activity_started_at';
 SET v_step='view:v_current_biological_visit_revision';
 INSERT INTO `ga_rb_v_current_biological_visit_revision` SELECT r.*
FROM ga_rb_t_biological_visit_revisions r
WHERE NOT EXISTS (
    SELECT 1 FROM ga_rb_t_biological_visit_revisions n
    WHERE n.supersedes_revision_id=r.visit_revision_id
);
 SET v_step='view:v_biological_visit_timing';
 INSERT INTO `ga_rb_v_biological_visit_timing` SELECT q.*,  TIMESTAMPDIFF(SECOND, q.started_at, q.ended_at) AS duration_seconds, CONCAT(FLOOR((TIMESTAMPDIFF(SECOND, q.started_at, q.ended_at))/86400), IF(FLOOR((TIMESTAMPDIFF(SECOND, q.started_at, q.ended_at))/86400)=1, ' dag, ', ' dager, '), LPAD(FLOOR(MOD((TIMESTAMPDIFF(SECOND, q.started_at, q.ended_at)), 86400)/3600), 2, '0'), ':', LPAD(FLOOR(MOD((TIMESTAMPDIFF(SECOND, q.started_at, q.ended_at)), 3600)/60), 2, '0')) AS duration_display, DATE_FORMAT(CONVERT_TZ(q.started_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS started_display, DATE_FORMAT(CONVERT_TZ(q.ended_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS ended_display FROM (SELECT r.visit_revision_id, r.visit_id, r.revision_no, r.supersedes_revision_id, r.started_at, COALESCE(LEAD(r.started_at) OVER(PARTITION BY v.session_id ORDER BY r.started_at, v.visit_seq), a.domain_now) AS ended_at, r.timing_source, r.confidence, r.evaluation_id, r.revision_reason, r.operation_id, r.created_at, v.session_id, v.phase_id, v.visit_seq FROM ga_rb_t_biological_visits v JOIN ga_rb_v_current_biological_visit_revision r ON r.visit_id=v.visit_id JOIN ga_rb_v_all_session a ON a.session_id=v.session_id) q;
 SET v_step='view:v_active_analysis_biological_markers';
 INSERT INTO `ga_rb_v_active_analysis_biological_markers` SELECT g.session_id, g.graph_id, b.phase_id, CONVERT(b.phase_id USING utf8mb4) AS label, r.started_at, r.ended_at
FROM ga_rb_t_session_analysis_graphs g
JOIN ga_rb_t_biological_visits b ON b.session_id=g.session_id
JOIN ga_rb_v_biological_visit_timing r ON r.visit_id=b.visit_id
WHERE g.enabled=1 AND g.show_biological_bands=1;
 SET v_step='view:v_current_process_visit_revision';
 INSERT INTO `ga_rb_v_current_process_visit_revision` SELECT r.*
FROM ga_rb_t_process_visit_revisions r
WHERE NOT EXISTS (
    SELECT 1 FROM ga_rb_t_process_visit_revisions n
    WHERE n.supersedes_revision_id=r.visit_revision_id
);
 SET v_step='view:v_process_visit_timing';
 INSERT INTO `ga_rb_v_process_visit_timing` SELECT q.*,  TIMESTAMPDIFF(SECOND, q.started_at, q.ended_at) AS duration_seconds, CONCAT(FLOOR((TIMESTAMPDIFF(SECOND, q.started_at, q.ended_at))/86400), IF(FLOOR((TIMESTAMPDIFF(SECOND, q.started_at, q.ended_at))/86400)=1, ' dag, ', ' dager, '), LPAD(FLOOR(MOD((TIMESTAMPDIFF(SECOND, q.started_at, q.ended_at)), 86400)/3600), 2, '0'), ':', LPAD(FLOOR(MOD((TIMESTAMPDIFF(SECOND, q.started_at, q.ended_at)), 3600)/60), 2, '0')) AS duration_display, DATE_FORMAT(CONVERT_TZ(q.started_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS started_display, DATE_FORMAT(CONVERT_TZ(q.ended_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS ended_display FROM (SELECT r.visit_revision_id, r.visit_id, r.revision_no, r.supersedes_revision_id, r.started_at, COALESCE(LEAD(r.started_at) OVER(PARTITION BY v.session_id ORDER BY r.started_at, v.visit_seq), a.domain_now) AS ended_at, r.timing_source, r.revision_reason, r.operation_id, r.created_at, v.session_id, v.process_id, v.visit_seq FROM ga_rb_t_process_visits v JOIN ga_rb_v_current_process_visit_revision r ON r.visit_id=v.visit_id JOIN ga_rb_v_all_session a ON a.session_id=v.session_id) q;
 SET v_step='view:v_active_analysis_process_markers';
 INSERT INTO `ga_rb_v_active_analysis_process_markers` SELECT g.session_id, g.graph_id, p.process_id, CONVERT(p.process_id USING utf8mb4) AS label, r.started_at, r.ended_at
FROM ga_rb_t_session_analysis_graphs g
JOIN ga_rb_t_process_visits p ON p.session_id=g.session_id
JOIN ga_rb_v_process_visit_timing r ON r.visit_id=p.visit_id
WHERE g.enabled=1 AND g.show_process_markers=1;
 SET v_step='view:v_current_session';
 INSERT INTO `ga_rb_v_current_session` SELECT s.* FROM ga_rb_v_all_session s LEFT JOIN ga_rb_t_session_release_events r ON r.session_id=s.session_id WHERE r.session_id IS NULL;
 SET v_step='view:v_active_session';
 INSERT INTO `ga_rb_v_active_session` SELECT
    session_id, batch_name, is_demo, created_at, pitched_at, activity_started_at, 
    og, volume_l, yeast_profile_id, pitch_mode_id, pitch_temperature_c, historical_ended_at, is_historical, domain_now
FROM ga_rb_v_current_session
WHERE lifecycle='active';
 SET v_step='view:v_current_biological_criterion_revision';
 INSERT INTO `ga_rb_v_current_biological_criterion_revision` SELECT r.*
FROM ga_rb_t_session_biological_criterion_revisions r
WHERE NOT EXISTS (
    SELECT 1 FROM ga_rb_t_session_biological_criterion_revisions n
    WHERE n.supersedes_revision_id=r.criterion_revision_id
);
 SET v_step='view:v_current_process_criterion_revision';
 INSERT INTO `ga_rb_v_current_process_criterion_revision` SELECT r.*
FROM ga_rb_t_session_process_criterion_revisions r
WHERE NOT EXISTS (
    SELECT 1 FROM ga_rb_t_session_process_criterion_revisions n
    WHERE n.supersedes_revision_id=r.criterion_revision_id
);
 SET v_step='view:v_effective_biological_criterion_parameters';
 INSERT INTO `ga_rb_v_effective_biological_criterion_parameters` SELECT k.session_id, k.phase_id, k.criterion_id, c.model_id, k.parameter_id, 
       COALESCE(b.data_type, p.data_type) AS data_type, 
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.real_value ELSE b.real_value END AS real_value, 
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.integer_value ELSE b.integer_value END AS integer_value, 
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.boolean_value ELSE b.boolean_value END AS boolean_value, 
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.text_value ELSE b.text_value END AS text_value, 
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.is_unset ELSE 0 END AS is_unset, 
       r.criterion_revision_id
FROM (
    SELECT session_id, phase_id, criterion_id, parameter_id FROM ga_rb_t_session_biological_criterion_parameter_values
    UNION
    SELECT r.session_id, r.phase_id, r.criterion_id, p.parameter_id
    FROM ga_rb_v_current_biological_criterion_revision r
    JOIN ga_rb_t_session_biological_criterion_revision_parameter_values p ON p.criterion_revision_id=r.criterion_revision_id
    WHERE r.action='override'
) k
JOIN ga_rb_t_session_biological_criteria c ON c.session_id=k.session_id AND c.phase_id=k.phase_id AND c.criterion_id=k.criterion_id
LEFT JOIN ga_rb_t_session_biological_criterion_parameter_values b ON b.session_id=k.session_id AND b.phase_id=k.phase_id AND b.criterion_id=k.criterion_id AND b.parameter_id=k.parameter_id
LEFT JOIN ga_rb_v_current_biological_criterion_revision r ON r.session_id=k.session_id AND r.phase_id=k.phase_id AND r.criterion_id=k.criterion_id
LEFT JOIN ga_rb_t_session_biological_criterion_revision_parameter_values p ON p.criterion_revision_id=r.criterion_revision_id AND p.parameter_id=k.parameter_id;
END//
CREATE PROCEDURE ga_fill_read_basis_part_5() BEGIN
 DECLARE v_stage LONGTEXT; DECLARE v_expected BIGINT; DECLARE v_step VARCHAR(128); DECLARE v_error TEXT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_error=MESSAGE_TEXT; SET v_error=CONCAT(v_step, ': ', LEFT(v_error, 350)); RESIGNAL SET MESSAGE_TEXT=v_error; END;
 SET v_step='view:v_effective_process_criterion_parameters';
 INSERT INTO `ga_rb_v_effective_process_criterion_parameters` SELECT k.session_id, k.process_id, k.criterion_id, c.model_id, k.parameter_id, 
       COALESCE(b.data_type, p.data_type) AS data_type, 
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.real_value ELSE b.real_value END AS real_value, 
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.integer_value ELSE b.integer_value END AS integer_value, 
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.boolean_value ELSE b.boolean_value END AS boolean_value, 
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.text_value ELSE b.text_value END AS text_value, 
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.is_unset ELSE 0 END AS is_unset, 
       r.criterion_revision_id
FROM (
    SELECT session_id, process_id, criterion_id, parameter_id FROM ga_rb_t_session_process_criterion_parameter_values
    UNION
    SELECT r.session_id, r.process_id, r.criterion_id, p.parameter_id
    FROM ga_rb_v_current_process_criterion_revision r
    JOIN ga_rb_t_session_process_criterion_revision_parameter_values p ON p.criterion_revision_id=r.criterion_revision_id
    WHERE r.action='override'
) k
JOIN ga_rb_t_session_process_criteria c ON c.session_id=k.session_id AND c.process_id=k.process_id AND c.criterion_id=k.criterion_id
LEFT JOIN ga_rb_t_session_process_criterion_parameter_values b ON b.session_id=k.session_id AND b.process_id=k.process_id AND b.criterion_id=k.criterion_id AND b.parameter_id=k.parameter_id
LEFT JOIN ga_rb_v_current_process_criterion_revision r ON r.session_id=k.session_id AND r.process_id=k.process_id AND r.criterion_id=k.criterion_id
LEFT JOIN ga_rb_t_session_process_criterion_revision_parameter_values p ON p.criterion_revision_id=r.criterion_revision_id AND p.parameter_id=k.parameter_id;
 SET v_step='view:v_session_analysis_requirements';
 INSERT INTO `ga_rb_v_session_analysis_requirements` SELECT q.*, 
       CONVERT(q.owner_id USING utf8mb4) AS owner_display, 
       CASE q.owner_type WHEN 'biology' THEN 'Biologi' WHEN 'process' THEN 'Prosesstrinn' ELSE CONVERT(q.owner_type USING utf8mb4) END COLLATE utf8mb4_unicode_ci AS owner_type_display, 
       COALESCE(cr.label, CONVERT(q.role_id USING utf8mb4)) AS role_display, 
       CASE
         WHEN q.minimum_value IS NOT NULL AND q.maximum_value IS NOT NULL THEN CONCAT(REPLACE(REPLACE(FORMAT(q.minimum_value, g.display_decimals) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), '–', REPLACE(REPLACE(FORMAT(q.maximum_value, g.display_decimals) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), ' ', g.unit)
         WHEN q.minimum_value IS NOT NULL THEN CONCAT('≥ ', REPLACE(REPLACE(FORMAT(q.minimum_value, g.display_decimals) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), ' ', g.unit)
         WHEN q.maximum_value IS NOT NULL THEN CONCAT('≤ ', REPLACE(REPLACE(FORMAT(q.maximum_value, g.display_decimals) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), ' ', g.unit)
         ELSE 'Krav uten numerisk terskel' END COLLATE utf8mb4_unicode_ci AS requirement_display, 
       CASE WHEN q.met_at IS NULL THEN NULL ELSE DATE_FORMAT(CONVERT_TZ(q.met_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') END COLLATE utf8mb4_unicode_ci AS met_at_display, 
       CASE WHEN q.met_at IS NULL THEN 'Ikke oppfylt' ELSE CONCAT('Oppfylt ', DATE_FORMAT(CONVERT_TZ(q.met_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i')) END COLLATE utf8mb4_unicode_ci AS met_status_display
FROM (
  SELECT gs.session_id, gs.graph_id, 'biology' AS owner_type, gs.owner_id, gs.criterion_id, c.label, c.role_id, 
         MAX(CASE WHEN p.parameter_id='minimum_value' THEN p.real_value END) AS minimum_value, 
         MAX(CASE WHEN p.parameter_id IN ('maximum_value', 'maximum_range_points') THEN p.real_value END) AS maximum_value, 
         (SELECT MIN(e.evaluated_at) FROM ga_rb_t_biological_evaluations e JOIN ga_rb_t_biological_evaluation_criteria ec ON ec.evaluation_id=e.evaluation_id
           WHERE e.session_id=gs.session_id AND e.candidate_phase_id=gs.owner_id AND ec.criterion_id=gs.criterion_id AND ec.met=1 AND (ec.criterion_revision_id <=> (SELECT r.criterion_revision_id FROM ga_rb_v_current_biological_criterion_revision r WHERE r.session_id=gs.session_id AND r.phase_id=gs.owner_id AND r.criterion_id=gs.criterion_id))) AS met_at
  FROM ga_rb_t_session_analysis_graph_series gs
  JOIN ga_rb_t_session_biological_criteria c ON c.session_id=gs.session_id AND c.phase_id=gs.owner_id AND c.criterion_id=gs.criterion_id
  LEFT JOIN ga_rb_v_effective_biological_criterion_parameters p ON p.session_id=c.session_id AND p.phase_id=c.phase_id AND p.criterion_id=c.criterion_id
  WHERE gs.source_kind='biological_criterion'
  GROUP BY gs.session_id, gs.graph_id, gs.owner_id, gs.criterion_id, c.label, c.role_id
  UNION ALL
  SELECT gs.session_id, gs.graph_id, 'process', gs.owner_id, gs.criterion_id, c.label, c.role_id, 
         MAX(CASE WHEN p.parameter_id='minimum_value' THEN p.real_value END), 
         MAX(CASE WHEN p.parameter_id IN ('maximum_value', 'maximum_range_points') THEN p.real_value END), 
         (SELECT MIN(e.evaluated_at) FROM ga_rb_t_process_evaluations e JOIN ga_rb_t_process_evaluation_criteria ec ON ec.evaluation_id=e.evaluation_id
           WHERE e.session_id=gs.session_id AND e.candidate_process_id=gs.owner_id AND ec.criterion_id=gs.criterion_id AND ec.met=1 AND (ec.criterion_revision_id <=> (SELECT r.criterion_revision_id FROM ga_rb_v_current_process_criterion_revision r WHERE r.session_id=gs.session_id AND r.process_id=gs.owner_id AND r.criterion_id=gs.criterion_id)))
  FROM ga_rb_t_session_analysis_graph_series gs
  JOIN ga_rb_t_session_process_criteria c ON c.session_id=gs.session_id AND c.process_id=gs.owner_id AND c.criterion_id=gs.criterion_id
  LEFT JOIN ga_rb_v_effective_process_criterion_parameters p ON p.session_id=c.session_id AND p.process_id=c.process_id AND p.criterion_id=c.criterion_id
  WHERE gs.source_kind='process_criterion'
  GROUP BY gs.session_id, gs.graph_id, gs.owner_id, gs.criterion_id, c.label, c.role_id
  UNION ALL
  SELECT g.session_id, g.graph_id, 'biology', c.phase_id, c.criterion_id, c.label, c.role_id, 
         MAX(CASE WHEN p.parameter_id='minimum_value' THEN p.real_value END), MAX(CASE WHEN p.parameter_id IN ('maximum_value', 'maximum_range_points') THEN p.real_value END), 
         (SELECT MIN(e.evaluated_at) FROM ga_rb_t_biological_evaluations e JOIN ga_rb_t_biological_evaluation_criteria ec ON ec.evaluation_id=e.evaluation_id WHERE e.session_id=g.session_id AND e.candidate_phase_id=c.phase_id AND ec.criterion_id=c.criterion_id AND ec.met=1 AND (ec.criterion_revision_id <=> (SELECT r.criterion_revision_id FROM ga_rb_v_current_biological_criterion_revision r WHERE r.session_id=g.session_id AND r.phase_id=c.phase_id AND r.criterion_id=c.criterion_id)))
  FROM ga_rb_t_session_analysis_graphs g
  JOIN ga_rb_t_session_analysis_graph_series gs ON gs.session_id=g.session_id AND gs.graph_id=g.graph_id AND gs.source_kind='metric'
  JOIN ga_rb_t_session_biological_criteria c ON c.session_id=g.session_id AND c.enabled=1 AND (c.metric_id=gs.metric_id OR (c.model_id='stability_window' AND EXISTS(
 SELECT 1 FROM ga_rb_t_session_metric_runtime_inputs mi JOIN ga_rb_t_session_metric_runtime_parameter_values mp ON mp.session_id=mi.session_id AND mp.metric_id=mi.metric_id AND mp.parameter_id='window_hours'
 JOIN ga_rb_v_effective_biological_criterion_parameters cp ON cp.session_id=c.session_id AND cp.phase_id=c.phase_id AND cp.criterion_id=c.criterion_id AND cp.parameter_id='window_hours' AND cp.real_value=mp.real_value
 WHERE mi.session_id=gs.session_id AND mi.metric_id=gs.metric_id AND mi.source_kind='series' AND mi.source_id=c.metric_id)))
  LEFT JOIN ga_rb_v_effective_biological_criterion_parameters p ON p.session_id=c.session_id AND p.phase_id=c.phase_id AND p.criterion_id=c.criterion_id
  GROUP BY g.session_id, g.graph_id, c.phase_id, c.criterion_id, c.label, c.role_id
  UNION ALL
  SELECT g.session_id, g.graph_id, 'process', c.process_id, c.criterion_id, c.label, c.role_id, 
         MAX(CASE WHEN p.parameter_id='minimum_value' THEN p.real_value END), MAX(CASE WHEN p.parameter_id IN ('maximum_value', 'maximum_range_points') THEN p.real_value END), 
         (SELECT MIN(e.evaluated_at) FROM ga_rb_t_process_evaluations e JOIN ga_rb_t_process_evaluation_criteria ec ON ec.evaluation_id=e.evaluation_id WHERE e.session_id=g.session_id AND e.candidate_process_id=c.process_id AND ec.criterion_id=c.criterion_id AND ec.met=1 AND (ec.criterion_revision_id <=> (SELECT r.criterion_revision_id FROM ga_rb_v_current_process_criterion_revision r WHERE r.session_id=g.session_id AND r.process_id=c.process_id AND r.criterion_id=c.criterion_id)))
  FROM ga_rb_t_session_analysis_graphs g
  JOIN ga_rb_t_session_analysis_graph_series gs ON gs.session_id=g.session_id AND gs.graph_id=g.graph_id AND gs.source_kind='metric'
  JOIN ga_rb_t_session_process_criteria c ON c.session_id=g.session_id AND c.enabled=1 AND (c.metric_id=gs.metric_id OR (c.model_id='stability_window' AND EXISTS(
 SELECT 1 FROM ga_rb_t_session_metric_runtime_inputs mi JOIN ga_rb_t_session_metric_runtime_parameter_values mp ON mp.session_id=mi.session_id AND mp.metric_id=mi.metric_id AND mp.parameter_id='window_hours'
 JOIN ga_rb_v_effective_process_criterion_parameters cp ON cp.session_id=c.session_id AND cp.process_id=c.process_id AND cp.criterion_id=c.criterion_id AND cp.parameter_id='window_hours' AND cp.real_value=mp.real_value
 WHERE mi.session_id=gs.session_id AND mi.metric_id=gs.metric_id AND mi.source_kind='series' AND mi.source_id=c.metric_id)))
  LEFT JOIN ga_rb_v_effective_process_criterion_parameters p ON p.session_id=c.session_id AND p.process_id=c.process_id AND p.criterion_id=c.criterion_id
  GROUP BY g.session_id, g.graph_id, c.process_id, c.criterion_id, c.label, c.role_id
) q
JOIN ga_rb_t_session_analysis_graphs g ON g.session_id=q.session_id AND g.graph_id=q.graph_id
LEFT JOIN ga_rb_t_criterion_roles cr ON cr.role_id=q.role_id;
 SET v_step='view:v_active_analysis_requirements';
 INSERT INTO `ga_rb_v_active_analysis_requirements` SELECT r.session_id, r.graph_id, r.owner_type, r.owner_id, r.criterion_id, r.label, r.role_id, 
       r.minimum_value, r.maximum_value, r.met_at, 
       r.owner_display, r.owner_type_display, r.role_display, r.requirement_display, r.met_at_display, r.met_status_display
FROM ga_rb_v_session_analysis_requirements r
JOIN ga_rb_v_active_session a ON a.session_id=r.session_id;
 SET v_step='view:v_current_biological_visit';
 INSERT INTO `ga_rb_v_current_biological_visit` SELECT x.*
FROM (
    SELECT
        bv.session_id, 
        bv.visit_id, 
        bv.phase_id, 
        ROW_NUMBER() OVER (
            PARTITION BY bv.session_id, bv.phase_id
            ORDER BY bv.visit_seq
        ) AS visit_no, 
        bp.phase_order, 
        bp.name AS phase_name, 
        bvr.visit_revision_id, 
        bvr.revision_no, 
        bvr.started_at, 
        bvr.ended_at, 
        bvr.timing_source, 
        bvr.confidence, 
        bvr.evaluation_id, 
        bvr.revision_reason, 
        TIMESTAMPDIFF(SECOND, bvr.started_at, COALESCE(bvr.ended_at, (SELECT a.domain_now FROM ga_rb_v_all_session a WHERE a.session_id=bv.session_id))) AS duration_seconds, 
        bv.visit_seq, 
        ROW_NUMBER() OVER (
            PARTITION BY bv.session_id
            ORDER BY bvr.started_at DESC, bv.visit_seq DESC, bvr.created_at DESC, bvr.visit_revision_id DESC
        ) AS session_rn
    FROM ga_rb_t_biological_visits bv
    JOIN ga_rb_v_current_biological_visit_revision bvr
      ON bvr.visit_id=bv.visit_id
    JOIN ga_rb_t_session_biological_phases bp
      ON bp.session_id=bv.session_id
     AND bp.phase_id=bv.phase_id
    WHERE bvr.ended_at IS NULL
) x
WHERE x.session_rn=1;
 SET v_step='view:v_current_fermentation_target';
 INSERT INTO `ga_rb_v_current_fermentation_target` SELECT
    b.session_id, 
    b.expected_attenuation_min_percent, 
    b.expected_attenuation_max_percent, 
    b.expected_fg_min, 
    b.expected_fg_max, 
    b.source, 
    NULL AS target_revision_id, 
    NULL AS revision_no, 
    NULL AS action, 
    NULL AS note, 
    NULL AS operation_id, 
    b.created_at, 
    b.created_at AS effective_at
FROM ga_rb_t_session_fermentation_targets b;
 SET v_step='view:v_current_process_visit';
 INSERT INTO `ga_rb_v_current_process_visit` SELECT x.*
FROM (
    SELECT
        pv.session_id, 
        pv.visit_id, 
        pv.process_id, 
        ROW_NUMBER() OVER (
            PARTITION BY pv.session_id, pv.process_id
            ORDER BY pv.visit_seq
        ) AS visit_no, 
        ps.process_order, 
        ps.name AS process_name, 
        pvr.visit_revision_id, 
        pvr.revision_no, 
        pvr.started_at, 
        pvr.ended_at, 
        pvr.timing_source, 
        pvr.revision_reason, 
        TIMESTAMPDIFF(SECOND, pvr.started_at, COALESCE(pvr.ended_at, (SELECT a.domain_now FROM ga_rb_v_all_session a WHERE a.session_id=pv.session_id))) AS duration_seconds, 
        pv.visit_seq, 
        ROW_NUMBER() OVER (
            PARTITION BY pv.session_id
            ORDER BY pvr.started_at DESC, pv.visit_seq DESC, pvr.created_at DESC, pvr.visit_revision_id DESC
        ) AS session_rn
    FROM ga_rb_t_process_visits pv
    JOIN ga_rb_v_current_process_visit_revision pvr
      ON pvr.visit_id=pv.visit_id
    JOIN ga_rb_t_session_process_steps ps
      ON ps.session_id=pv.session_id
     AND ps.process_id=pv.process_id
    WHERE pvr.ended_at IS NULL
) x
WHERE x.session_rn=1;
 SET v_step='view:v_latest_biological_evaluation';
 INSERT INTO `ga_rb_v_latest_biological_evaluation` SELECT x.*
FROM (
    SELECT be.*, 
           ROW_NUMBER() OVER (
               PARTITION BY be.session_id
               ORDER BY be.created_at DESC, be.evaluation_id DESC
           ) AS rn
    FROM ga_rb_t_biological_evaluations be
) x
WHERE x.rn=1;
 SET v_step='view:v_current_observation_revision';
 INSERT INTO `ga_rb_v_current_observation_revision` SELECT r.*
FROM ga_rb_t_observation_round_revisions r
WHERE NOT EXISTS (
    SELECT 1 FROM ga_rb_t_observation_round_revisions n
    WHERE n.supersedes_revision_id=r.observation_revision_id
);
 SET v_step='view:v_latest_observation';
 INSERT INTO `ga_rb_v_latest_observation` SELECT x.*
FROM (
    SELECT
        o.session_id, 
        r.observation_id, 
        r.observation_revision_id, 
        r.revision_no, 
        r.recorded_at, 
        r.measurement_method_id, 
        r.measured_sg, 
        r.corrected_sg, 
        r.manual_temperature_c, 
        r.pressure_bar, 
        r.cooler_setpoint_c, 
        r.cooler_calibration_offset_c, 
        r.estimated_abv_percent, 
        r.estimated_finished_abv_percent, 
        r.airlock_activity, 
        r.user_conclusion, 
        r.calculated_conclusion, 
        r.process_gate_status, 
        r.note, 
        ROW_NUMBER() OVER (
            PARTITION BY o.session_id
            ORDER BY r.recorded_at DESC, r.created_at DESC, r.observation_revision_id DESC
        ) AS rn
    FROM ga_rb_t_observation_rounds o
    JOIN ga_rb_v_current_observation_revision r
      ON r.observation_id=o.observation_id
     AND r.status='active'
) x
WHERE x.rn=1;
 SET v_step='view:v_latest_process_evaluation';
 INSERT INTO `ga_rb_v_latest_process_evaluation` SELECT x.*
FROM (
    SELECT pe.*, 
           ROW_NUMBER() OVER (
               PARTITION BY pe.session_id
               ORDER BY pe.created_at DESC, pe.evaluation_id DESC
           ) AS rn
    FROM ga_rb_t_process_evaluations pe
) x
WHERE x.rn=1;
 SET v_step='view:v_session_archive_status';
 INSERT INTO `ga_rb_v_session_archive_status` SELECT s.session_id, (s.lifecycle='completed' AND (s.is_demo=1 OR EXISTS(SELECT 1 FROM ga_rb_t_session_exports e WHERE e.session_id=s.session_id AND e.export_kind='completed_archive' AND e.status='verified'))) AS can_prepare_new, 'Gjør klar for ny gjæring' AS prepare_action_display, a.attempt_no AS archive_attempt_no, a.requested_at AS archive_requested_at, 
       e.error_message AS archive_error_message, 
       CASE WHEN s.lifecycle<>'completed' THEN 'not_applicable'
            WHEN EXISTS(SELECT 1 FROM ga_rb_t_session_exports v WHERE v.session_id=s.session_id AND v.export_kind='completed_archive' AND v.status='verified') THEN 'verified'
            WHEN e.status='failed' THEN 'failed' WHEN a.attempt_id IS NOT NULL THEN 'pending' ELSE 'missing' END AS archive_status, 
       CASE WHEN s.lifecycle<>'completed' THEN 'Sluttarkiv opprettes ved Avslutt gjæring'
            WHEN EXISTS(SELECT 1 FROM ga_rb_t_session_exports v WHERE v.session_id=s.session_id AND v.export_kind='completed_archive' AND v.status='verified') THEN 'Gjæring avsluttet · arkiv og rapport verifisert'
            WHEN e.status='failed' THEN CONCAT('Gjæring avsluttet · arkivering feilet · ', e.error_message)
            WHEN a.attempt_id IS NOT NULL THEN 'Gjæring avsluttet · arkivering startet, men mangler fullføringskvittering'
            ELSE 'Gjæring avsluttet · verifisert arkiv mangler' END COLLATE utf8mb4_unicode_ci AS archive_status_display
FROM ga_rb_v_current_session s
LEFT JOIN ga_rb_t_session_export_attempts a ON a.session_id=s.session_id AND a.export_kind='completed_archive' AND a.attempt_no=(SELECT MAX(x.attempt_no) FROM ga_rb_t_session_export_attempts x WHERE x.session_id=s.session_id AND x.export_kind='completed_archive')
LEFT JOIN ga_rb_t_session_exports e ON e.operation_id=a.attempt_id AND e.export_kind='completed_archive';
 SET v_step='view:v_all_session_summary';
 INSERT INTO `ga_rb_v_all_session_summary` SELECT DISTINCT
    s.session_id, 
    s.batch_name, 
    s.is_demo, s.is_historical, s.historical_ended_at, s.domain_now, 
    s.pitched_at, 
    s.activity_started_at, 
    s.completed_at, 
    s.lifecycle, 
    s.lifecycle_at, 
    ar.archive_status, ar.archive_status_display, ar.archive_error_message, ar.archive_attempt_no, ar.archive_requested_at, ar.can_prepare_new, ar.prepare_action_display, 
    s.og, 
    s.volume_l, 
    ft.expected_attenuation_min_percent, 
    ft.expected_attenuation_max_percent, 
    ft.expected_fg_min, 
    ft.expected_fg_max, 
    CASE WHEN ft.expected_attenuation_min_percent IS NULL OR ft.expected_attenuation_max_percent IS NULL THEN NULL
         ELSE CONCAT(CAST(ROUND(ft.expected_attenuation_min_percent, 1) AS CHAR), '–', CAST(ROUND(ft.expected_attenuation_max_percent, 1) AS CHAR), ' %') END COLLATE utf8mb4_unicode_ci AS expected_attenuation_display, 
    CASE WHEN ft.expected_fg_min IS NULL OR ft.expected_fg_max IS NULL THEN NULL
         ELSE CONCAT(REPLACE(REPLACE(FORMAT(ft.expected_fg_min, 4) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), '–', REPLACE(REPLACE(FORMAT(ft.expected_fg_max, 4) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ',')) END COLLATE utf8mb4_unicode_ci AS expected_fg_display, 
    cp.visit_id AS current_process_visit_id, 
    cp.process_id AS current_process_id, 
    cp.process_order AS current_process_order, 
    cp.process_name AS current_process_name, 
    cp.started_at AS current_process_started_at, 
    cp.ended_at AS current_process_ended_at, 
    cb.visit_id AS current_biological_visit_id, 
    cb.phase_id AS current_biological_phase_id, 
    cb.phase_order AS current_biological_phase_order, 
    cb.phase_name AS current_biological_phase_name, 
    cb.started_at AS current_biological_started_at, 
    cb.ended_at AS current_biological_ended_at, 
    lo.observation_id AS latest_observation_id, 
    lo.recorded_at AS latest_observation_at, 
    lo.corrected_sg AS latest_manual_sg, 
    lpe.evaluation_id AS latest_process_evaluation_id, 
    lpe.readiness AS latest_process_readiness, 
    lpe.candidate_process_id AS recommended_next_process_id, 
    lpe.recommended_temperature_c, 
    lpe.recommended_pressure_bar, 
    lbe.evaluation_id AS latest_biological_evaluation_id, 
    lbe.candidate_phase_id AS latest_biological_candidate_phase_id, 
    lbe.confidence AS latest_biological_confidence
FROM ga_rb_v_all_session s
LEFT JOIN ga_rb_v_session_archive_status ar ON ar.session_id=s.session_id
LEFT JOIN ga_rb_v_current_fermentation_target ft ON ft.session_id=s.session_id
LEFT JOIN ga_rb_v_current_process_visit cp ON cp.session_id=s.session_id
LEFT JOIN ga_rb_v_current_biological_visit cb ON cb.session_id=s.session_id
LEFT JOIN ga_rb_v_latest_observation lo ON lo.session_id=s.session_id
LEFT JOIN ga_rb_v_latest_process_evaluation lpe ON lpe.session_id=s.session_id
LEFT JOIN ga_rb_v_latest_biological_evaluation lbe ON lbe.session_id=s.session_id;
 SET v_step='view:v_current_metric_value';
 INSERT INTO `ga_rb_v_current_metric_value` SELECT x.session_id, x.evaluation_id, x.metric_id, 
 CASE WHEN x.current_basis_ok THEN x.actual_value ELSE NULL END AS actual_value, 
 NULL AS actual_text, 
 CASE WHEN x.current_basis_ok THEN CONCAT(REPLACE(REPLACE(FORMAT(x.actual_value, x.display_decimals) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), ' ', x.unit) ELSE 'Utilgjengelig' END COLLATE utf8mb4_unicode_ci AS actual_display, 
 CASE WHEN x.current_basis_ok THEN x.value_status ELSE 'missing_basis' END COLLATE utf8mb4_unicode_ci AS evaluation_status, 
 CASE WHEN x.current_basis_ok THEN CONCAT(CASE x.value_status WHEN 'provisional' THEN 'Foreløpig' ELSE 'Ordinær' END, ' · ', x.sample_count, ' målepunkter / ', ROUND(x.coverage_seconds/60), ' min · ', DATE_FORMAT(CONVERT_TZ(x.measured_at, '+00:00', 'Europe/Oslo'), '%d.%m %H:%i'))
 ELSE CASE x.reason_code WHEN 'regression_insufficient_span' THEN 'For kort sammenhengende datavindu' WHEN 'regression_uncertainty_too_large' THEN 'For stor usikkerhet i SG-rate' WHEN 'regression_excessive_outliers' THEN 'For mange avvikende målinger' WHEN 'baseline_missing_near_pitch' THEN 'Mangler målinger nær pitch for SG-kalibrering' WHEN 'baseline_unstable_at_pitch' THEN 'SG ved pitch var for ustabil til kalibrering' WHEN 'baseline_insufficient_contiguous_pitch_data' THEN 'For lite sammenhengende SG-grunnlag ved pitch' ELSE 'Mangler fersk, godkjent analyseverdi' END END COLLATE utf8mb4_unicode_ci AS status_display, 
 x.measured_at, x.measured_at AS evaluated_at, x.created_at AS evaluation_created_at, 'analysis' AS source_scope, x.rn
FROM (
 SELECT d.session_id, d.metric_id, v.actual_value, v.measured_at, v.sample_count, v.coverage_seconds, v.value_status, v.created_at, 
 CONCAT('analysis-', CONVERT(d.metric_id USING utf8mb4)) AS evaluation_id, m.display_decimals, m.unit, 
 (SELECT e.reason_code FROM ga_rb_t_analysis_validation_events e WHERE e.session_id=d.session_id AND e.graph_id=d.graph_id AND e.series_id=d.series_id AND e.basis_pitched_at=(SELECT pitched_at FROM ga_rb_v_current_session WHERE session_id=d.session_id) AND e.reason_code<>'band_outside_declared_output_range' AND (v.sample_at IS NULL OR e.sample_at>v.sample_at) ORDER BY e.sample_at DESC LIMIT 1) AS reason_code, 
 v.sample_at IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM ga_rb_t_analysis_validation_events e WHERE e.session_id=d.session_id AND e.graph_id=d.graph_id AND e.series_id=d.series_id AND e.basis_pitched_at=(SELECT pitched_at FROM ga_rb_v_current_session WHERE session_id=d.session_id) AND e.reason_code<>'band_outside_declared_output_range' AND e.sample_at>v.sample_at)
 AND (sess.is_demo=1 OR (TIMESTAMPDIFF(MINUTE, v.measured_at, (SELECT a.domain_now FROM ga_rb_v_all_session a WHERE a.session_id=d.session_id))<=COALESCE((SELECT p.integer_value FROM ga_rb_t_session_metric_runtime_parameter_values p WHERE p.session_id=d.session_id AND p.metric_id=d.metric_id AND p.parameter_id='maximum_age_minutes'), sp.fresh_age_minutes) AND TIMESTAMPDIFF(MINUTE, v.measured_at, COALESCE((SELECT MAX(mm.bucket_at) FROM ga_rb_t_measurements_5m mm WHERE mm.session_id=d.session_id), v.measured_at))<=COALESCE((SELECT p.integer_value FROM ga_rb_t_session_metric_runtime_parameter_values p WHERE p.session_id=d.session_id AND p.metric_id=d.metric_id AND p.parameter_id='maximum_age_minutes'), sp.fresh_age_minutes))) AS current_basis_ok, 
 ROW_NUMBER() OVER(PARTITION BY d.session_id, d.metric_id ORDER BY v.sample_at DESC) AS rn
 FROM ga_rb_t_session_analysis_graph_series d
 JOIN ga_rb_t_sessions sess ON sess.session_id=d.session_id
 JOIN ga_rb_t_metrics m ON m.metric_id=d.metric_id
 LEFT JOIN ga_rb_t_analysis_series_values v ON v.session_id=d.session_id AND v.graph_id=d.graph_id AND v.series_id=d.series_id AND v.basis_pitched_at=(SELECT pitched_at FROM ga_rb_v_current_session WHERE session_id=d.session_id) AND (v.source_observation_revision_id IS NULL OR EXISTS(SELECT 1 FROM ga_rb_v_current_observation_revision o WHERE o.observation_revision_id=v.source_observation_revision_id AND o.session_id=v.session_id AND o.status='active')) AND v.sample_at=(SELECT MAX(last.sample_at) FROM ga_rb_t_analysis_series_values last WHERE last.session_id=d.session_id AND last.graph_id=d.graph_id AND last.series_id=d.series_id AND last.basis_pitched_at=(SELECT pitched_at FROM ga_rb_v_current_session WHERE session_id=d.session_id) AND (last.source_observation_revision_id IS NULL OR EXISTS(SELECT 1 FROM ga_rb_v_current_observation_revision obs WHERE obs.observation_revision_id=last.source_observation_revision_id AND obs.session_id=last.session_id AND obs.status='active')))
 LEFT JOIN ga_rb_t_session_measurement_sources sm ON sm.session_id=d.session_id
 LEFT JOIN ga_rb_t_measurement_source_profiles sp ON sp.source_profile_id=sm.source_profile_id
 WHERE d.source_kind='metric'
) x WHERE x.rn=1;
 SET v_step='view:v_current_process_candidate_evaluation';
 INSERT INTO `ga_rb_v_current_process_candidate_evaluation` SELECT x.*, 
       CASE
         WHEN x.candidate_process_id IS NULL THEN 'Prosessplan fullført'
         WHEN x.readiness IN ('ready', 'ready_with_exceptions') THEN CONCAT(CONVERT(x.candidate_process_id USING utf8mb4), ' kriterier oppfylt · venter på manuell overgang')
         WHEN x.readiness='waiting' THEN CONCAT(CONVERT(x.candidate_process_id USING utf8mb4), ' · venter på kriterier')
         WHEN x.readiness='invalid_configuration' THEN CONCAT(CONVERT(x.candidate_process_id USING utf8mb4), ' · konfigurasjonsfeil')
         ELSE CONCAT(CONVERT(x.candidate_process_id USING utf8mb4), ' · ', COALESCE(x.readiness, 'ikke vurdert'))
       END COLLATE utf8mb4_unicode_ci AS operator_status_display
FROM (
    SELECT
        e.*, 
        ps.process_order AS candidate_process_order, 
        ps.name AS candidate_process_name, 
        ps.historical_replay_auto_transition_allowed, 
        ROW_NUMBER() OVER (
            PARTITION BY e.session_id
            ORDER BY e.created_at DESC, e.evaluation_id DESC
        ) AS rn
    FROM ga_rb_t_process_evaluations e
    JOIN ga_rb_v_current_process_visit cp ON cp.session_id=e.session_id
    LEFT JOIN ga_rb_t_session_process_steps ps
      ON ps.session_id=e.session_id AND ps.process_id=e.candidate_process_id
    WHERE (
        (
            e.candidate_process_id IS NOT NULL
            AND ps.enabled=1
            AND ps.process_order=(
                SELECT MIN(n.process_order)
                FROM ga_rb_t_session_process_steps n
                WHERE n.session_id=e.session_id
                  AND n.enabled=1
                  AND n.process_order>cp.process_order
            )
        )
        OR (
            e.candidate_process_id IS NULL
            AND NOT EXISTS (
                SELECT 1
                FROM ga_rb_t_session_process_steps n
                WHERE n.session_id=e.session_id
                  AND n.enabled=1
                  AND n.process_order>cp.process_order
            )
        )
    )
) x
WHERE x.rn=1;
 SET v_step='view:v_current_session_summary';
 INSERT INTO `ga_rb_v_current_session_summary` SELECT DISTINCT
    s.session_id, 
    s.batch_name, 
    s.is_demo, s.is_historical, s.historical_ended_at, s.domain_now, 
    s.pitched_at, 
    s.activity_started_at, 
    s.completed_at, 
    s.lifecycle, 
    s.lifecycle_at, 
    ar.archive_status, ar.archive_status_display, ar.archive_error_message, ar.archive_attempt_no, ar.archive_requested_at, ar.can_prepare_new, ar.prepare_action_display, 
    s.og, 
    s.volume_l, 
    ft.expected_attenuation_min_percent, 
    ft.expected_attenuation_max_percent, 
    ft.expected_fg_min, 
    ft.expected_fg_max, 
    CASE WHEN ft.expected_attenuation_min_percent IS NULL OR ft.expected_attenuation_max_percent IS NULL THEN NULL
         ELSE CONCAT(CAST(ROUND(ft.expected_attenuation_min_percent, 1) AS CHAR), '–', CAST(ROUND(ft.expected_attenuation_max_percent, 1) AS CHAR), ' %') END COLLATE utf8mb4_unicode_ci AS expected_attenuation_display, 
    CASE WHEN ft.expected_fg_min IS NULL OR ft.expected_fg_max IS NULL THEN NULL
         ELSE CONCAT(REPLACE(REPLACE(FORMAT(ft.expected_fg_min, 4) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), '–', REPLACE(REPLACE(FORMAT(ft.expected_fg_max, 4) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ',')) END COLLATE utf8mb4_unicode_ci AS expected_fg_display, 
    cp.visit_id AS current_process_visit_id, 
    cp.process_id AS current_process_id, 
    cp.process_order AS current_process_order, 
    cp.process_name AS current_process_name, 
    cp.started_at AS current_process_started_at, 
    cp.ended_at AS current_process_ended_at, 
    cb.visit_id AS current_biological_visit_id, 
    cb.phase_id AS current_biological_phase_id, 
    cb.phase_order AS current_biological_phase_order, 
    cb.phase_name AS current_biological_phase_name, 
    cb.started_at AS current_biological_started_at, 
    cb.ended_at AS current_biological_ended_at, 
    lo.observation_id AS latest_observation_id, 
    lo.recorded_at AS latest_observation_at, 
    lo.corrected_sg AS latest_manual_sg, 
    lpe.evaluation_id AS latest_process_evaluation_id, 
    lpe.readiness AS latest_process_readiness, 
    lpe.candidate_process_id AS recommended_next_process_id, 
    lpe.recommended_temperature_c, 
    lpe.recommended_pressure_bar, 
    lbe.evaluation_id AS latest_biological_evaluation_id, 
    lbe.candidate_phase_id AS latest_biological_candidate_phase_id, 
    lbe.confidence AS latest_biological_confidence
FROM ga_rb_v_current_session s
LEFT JOIN ga_rb_v_session_archive_status ar ON ar.session_id=s.session_id
LEFT JOIN ga_rb_v_current_fermentation_target ft ON ft.session_id=s.session_id
LEFT JOIN ga_rb_v_current_process_visit cp ON cp.session_id=s.session_id
LEFT JOIN ga_rb_v_current_biological_visit cb ON cb.session_id=s.session_id
LEFT JOIN ga_rb_v_latest_observation lo ON lo.session_id=s.session_id
LEFT JOIN ga_rb_v_latest_process_evaluation lpe ON lpe.session_id=s.session_id
LEFT JOIN ga_rb_v_latest_biological_evaluation lbe ON lbe.session_id=s.session_id;
 SET v_step='view:v_measurement_data_gaps';
 INSERT INTO `ga_rb_v_measurement_data_gaps` SELECT g.gap_id, g.session_id, g.source, g.gap_started_at, COALESCE(c.gap_ended_at, g.gap_ended_at, IF(sm.last_import_cutoff_at>=h.ended_at, h.ended_at, NULL)) AS gap_ended_at, COALESCE(c.duration_seconds, g.duration_seconds, IF(sm.last_import_cutoff_at>=h.ended_at, TIMESTAMPDIFF(SECOND, g.gap_started_at, h.ended_at), NULL)) AS duration_seconds, g.threshold_seconds, g.detected_at, g.created_at FROM ga_rb_t_measurement_data_gaps g LEFT JOIN ga_rb_t_measurement_gap_closures c ON c.gap_id=g.gap_id LEFT JOIN ga_rb_t_session_history_windows h ON h.session_id=g.session_id LEFT JOIN ga_rb_t_session_measurement_sources sm ON sm.session_id=g.session_id;
 SET v_step='view:v_current_measurement_source_configuration';
 INSERT INTO `ga_rb_v_current_measurement_source_configuration` SELECT c.* FROM ga_rb_t_measurement_source_configurations c WHERE NOT EXISTS(SELECT 1 FROM ga_rb_t_measurement_source_configurations n WHERE n.source_profile_id=c.source_profile_id AND n.configuration_id>c.configuration_id);
 SET v_step='view:v_source_configuration_values';
 INSERT INTO `ga_rb_v_source_configuration_values` SELECT b.configuration_id, 
 MAX(CASE WHEN b.signal_id='sg' THEN b.entity_id END) AS sg_entity_id, 
 MAX(CASE WHEN b.signal_id='temperature' THEN b.entity_id END) AS temperature_entity_id, 
 MAX(CASE WHEN b.signal_id='heartbeat' THEN b.entity_id END) AS heartbeat_entity_id, 
 MAX(CASE WHEN b.signal_id='rssi' THEN b.entity_id END) AS rssi_entity_id, 
 MAX(CASE WHEN b.signal_id='pressure' THEN b.entity_id END) AS pressure_entity_id
FROM ga_rb_t_measurement_source_signal_bindings b GROUP BY b.configuration_id;
 SET v_step='view:v_measurement_source_profiles';
 INSERT INTO `ga_rb_v_measurement_source_profiles` SELECT p.*, c.configuration_id, v.sg_entity_id, v.temperature_entity_id, v.heartbeat_entity_id, v.rssi_entity_id, v.pressure_entity_id
FROM ga_rb_t_measurement_source_profiles p JOIN ga_rb_v_current_measurement_source_configuration c ON c.source_profile_id=p.source_profile_id JOIN ga_rb_v_source_configuration_values v ON v.configuration_id=c.configuration_id;
 SET v_step='view:v_current_measurement_statistics_hourly';
 INSERT INTO `ga_rb_v_current_measurement_statistics_hourly` SELECT h.* FROM ga_rb_t_measurement_statistics_hourly h WHERE NOT EXISTS(SELECT 1 FROM ga_rb_t_measurement_statistics_hourly n WHERE n.session_id=h.session_id AND n.start_at=h.start_at AND n.statistic_seq>h.statistic_seq);
 SET v_step='view:v_session_import_coverage';
 INSERT INTO `ga_rb_v_session_import_coverage` SELECT q.*, 
 CONCAT(q.detail_count, ' femminuttersbøtter · ', q.hourly_count, ' timepunkter · ', q.gap_count, ' registrerte rådatagap') AS counts_display, 
 CASE WHEN q.detail_count=0 AND q.hourly_count=0 THEN 'Ingen måledata funnet i behandlet periode'
 WHEN q.detail_count=0 THEN 'Kun HA-timesstatistikk · ingen ordinære femminuttersmålinger'
 WHEN q.gap_count>0 THEN 'Femminuttersmålinger med registrerte datagap'
 ELSE 'Femminuttersmålinger tilgjengelige' END AS coverage_display, 
 CONCAT('Behandlet til ', COALESCE(DATE_FORMAT(CONVERT_TZ(q.processed_to, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i'), 'ikke behandlet'), 
 ' · ', q.detail_count, ' femminuttersbøtter · ', q.hourly_count, ' timepunkter', 
 CASE WHEN q.detail_count=0 THEN ' · mangler ordinært målegrunnlag' WHEN q.gap_count>0 THEN ' · rådatagap finnes' ELSE '' END) AS summary_display
FROM (
 SELECT s.session_id, m.source_started_at, m.last_import_cutoff_at AS processed_to, s.historical_ended_at, 
 (SELECT COUNT(*) FROM ga_rb_t_measurements_5m d WHERE d.session_id=s.session_id) AS detail_count, 
 (SELECT MIN(bucket_at) FROM ga_rb_t_measurements_5m d WHERE d.session_id=s.session_id) AS detail_first_at, 
 (SELECT MAX(bucket_at) FROM ga_rb_t_measurements_5m d WHERE d.session_id=s.session_id) AS detail_last_at, 
 (SELECT COUNT(*) FROM ga_rb_v_current_measurement_statistics_hourly h WHERE h.session_id=s.session_id) AS hourly_count, 
 (SELECT MIN(start_at) FROM ga_rb_v_current_measurement_statistics_hourly h WHERE h.session_id=s.session_id) AS hourly_first_at, 
 (SELECT MAX(end_at) FROM ga_rb_v_current_measurement_statistics_hourly h WHERE h.session_id=s.session_id) AS hourly_last_at, 
 (SELECT COUNT(*) FROM ga_rb_v_measurement_data_gaps g WHERE g.session_id=s.session_id) AS gap_count
 FROM ga_rb_v_all_session s JOIN ga_rb_t_session_measurement_sources m ON m.session_id=s.session_id
) q;
END//
CREATE PROCEDURE ga_fill_read_basis_part_6() BEGIN
 DECLARE v_stage LONGTEXT; DECLARE v_expected BIGINT; DECLARE v_step VARCHAR(128); DECLARE v_error TEXT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_error=MESSAGE_TEXT; SET v_error=CONCAT(v_step, ': ', LEFT(v_error, 350)); RESIGNAL SET MESSAGE_TEXT=v_error; END;
 SET v_step='view:v_current_session_measurement_source_configuration';
 INSERT INTO `ga_rb_v_current_session_measurement_source_configuration` SELECT c.* FROM ga_rb_t_session_measurement_source_configurations c JOIN ga_rb_t_session_measurement_sources m ON m.session_id=c.session_id
WHERE c.effective_from<=m.last_import_cutoff_at AND NOT EXISTS(SELECT 1 FROM ga_rb_t_session_measurement_source_configurations n WHERE n.session_id=c.session_id AND n.effective_from<=m.last_import_cutoff_at AND(n.effective_from>c.effective_from OR n.effective_from=c.effective_from AND n.configuration_id>c.configuration_id));
 SET v_step='view:v_session_source_configuration_values';
 INSERT INTO `ga_rb_v_session_source_configuration_values` SELECT b.session_id, b.configuration_id, 
 MAX(CASE WHEN b.signal_id='sg' THEN b.entity_id END) AS sg_entity_id, 
 MAX(CASE WHEN b.signal_id='temperature' THEN b.entity_id END) AS temperature_entity_id, 
 MAX(CASE WHEN b.signal_id='heartbeat' THEN b.entity_id END) AS heartbeat_entity_id, 
 MAX(CASE WHEN b.signal_id='rssi' THEN b.entity_id END) AS rssi_entity_id, 
 MAX(CASE WHEN b.signal_id='pressure' THEN b.entity_id END) AS pressure_entity_id, 
 JSON_ARRAYAGG(JSON_OBJECT('signal_id', b.signal_id, 'observation_kind', s.observation_kind, 'input_mode', b.input_mode, 'entity_id', b.entity_id, 'unit_id', b.unit_id, 'sensor_required', s.sensor_required, 'minimum_value', b.minimum_value, 'maximum_value', b.maximum_value, 'multiplier', u.multiplier, 'additive_offset', u.additive_offset) ORDER BY s.display_order) AS signal_bindings
FROM ga_rb_t_session_measurement_signal_bindings b JOIN ga_rb_t_measurement_source_signals s ON s.signal_id=b.signal_id JOIN ga_rb_t_measurement_source_units u ON u.signal_id=b.signal_id AND u.unit_id=b.unit_id GROUP BY b.session_id, b.configuration_id;
 SET v_step='view:v_session_measurement_source_profiles';
 INSERT INTO `ga_rb_v_session_measurement_source_profiles` SELECT p.*, m.session_id, c.configuration_id, c.effective_from AS configuration_started_at, v.sg_entity_id, v.temperature_entity_id, v.heartbeat_entity_id, v.rssi_entity_id, v.pressure_entity_id, v.signal_bindings, 
 (SELECT MIN(n.effective_from) FROM ga_rb_t_session_measurement_source_configurations n WHERE n.session_id=m.session_id AND n.effective_from>m.last_import_cutoff_at) AS next_configuration_at
FROM ga_rb_t_measurement_source_profiles p JOIN ga_rb_t_session_measurement_sources m ON m.source_profile_id=p.source_profile_id JOIN ga_rb_v_current_session_measurement_source_configuration c ON c.session_id=m.session_id JOIN ga_rb_v_session_source_configuration_values v ON v.session_id=c.session_id AND v.configuration_id=c.configuration_id;
 SET v_step='view:v_measurement_source_status';
 INSERT INTO `ga_rb_v_measurement_source_status` SELECT
    CASE
      WHEN s.session_id IS NOT NULL AND s.is_demo=1 THEN 'DEMO'
      WHEN s.is_historical=1 AND sm.last_import_cutoff_at>=s.historical_ended_at THEN 'HISTORISK'
      WHEN s.lifecycle='active' AND sm.session_id IS NULL THEN 'ERROR'
      WHEN sm.last_error IS NOT NULL AND sm.last_error<>'' THEN 'ADVARSEL'
      WHEN g.gap_id IS NOT NULL THEN 'GAP'
      WHEN s.lifecycle='active' AND sm.session_id IS NOT NULL THEN 'LIVE'
      ELSE 'IDLE'
    END AS state, 
    CASE
      WHEN s.session_id IS NOT NULL AND s.is_demo=1 THEN 'Aktiv syntetisk demo · HA-målekilde brukes ikke'
      WHEN s.is_historical=1 AND sm.last_import_cutoff_at>=s.historical_ended_at THEN 'Historisk import avsluttet ved fast sluttid · etterregistrering tilgjengelig'
      WHEN s.lifecycle='active' AND sm.session_id IS NULL THEN 'Aktiv gjæring mangler målekildebinding i MariaDB'
      WHEN sm.last_error IS NOT NULL AND sm.last_error<>'' THEN 'HA-import har registrert feil'
      WHEN g.gap_id IS NOT NULL THEN 'HA-import aktiv · åpent datagap'
      WHEN s.lifecycle='active' AND sm.session_id IS NOT NULL THEN 'HA-import aktiv'
      ELSE 'Målekilde konfigurert · ingen aktiv gjæring'
    END AS message, 
    p.source_profile_id, p.name, p.source_type, CASE WHEN sm.session_id IS NULL THEN p.sg_entity_id ELSE active_source.sg_entity_id END AS sg_entity_id, CASE WHEN sm.session_id IS NULL THEN p.temperature_entity_id ELSE active_source.temperature_entity_id END AS temperature_entity_id, CASE WHEN sm.session_id IS NULL THEN p.heartbeat_entity_id ELSE active_source.heartbeat_entity_id END AS heartbeat_entity_id, CASE WHEN sm.session_id IS NULL THEN p.rssi_entity_id ELSE active_source.rssi_entity_id END AS rssi_entity_id, 
    p.poll_interval_seconds, p.gap_threshold_seconds, p.fresh_age_minutes, p.stale_age_minutes, 
    s.session_id, s.is_demo, s.batch_name, s.lifecycle, 
    sm.source_started_at, sm.last_import_cutoff_at, sm.last_success_at, sm.last_error, 
    m.bucket_at AS latest_bucket_at, m.sample_count AS latest_sample_count, m.sg_min, m.sg_mean, m.sg_median, m.sg_max, m.temperature_mean_c, m.rssi_mean_dbm, 
    g.gap_id AS open_gap_id, g.gap_started_at AS open_gap_started_at, 
    CASE WHEN m.bucket_at IS NULL THEN NULL ELSE GREATEST(0, TIMESTAMPDIFF(MINUTE, m.bucket_at, s.domain_now)) END AS measurement_age_minutes, 
    CASE WHEN m.bucket_at IS NULL THEN 'Ikke tilgjengelig' ELSE CAST(GREATEST(0, TIMESTAMPDIFF(MINUTE, m.bucket_at, s.domain_now)) AS CHAR) END AS measurement_age_state, 
    CASE WHEN m.bucket_at IS NULL THEN 'Ikke tilgjengelig' ELSE DATE_FORMAT(m.bucket_at, '%Y-%m-%dT%H:%i:%s+00:00') END AS latest_measurement_state, 
    CASE
      WHEN s.is_historical=1 THEN 'historisk datasett' WHEN m.bucket_at IS NULL THEN 'ingen aktiv måling'
      WHEN TIMESTAMPDIFF(MINUTE, m.bucket_at, s.domain_now)<=p.fresh_age_minutes THEN 'fersk'
      WHEN TIMESTAMPDIFF(MINUTE, m.bucket_at, s.domain_now)<=p.stale_age_minutes THEN 'aldrende'
      ELSE 'gammel'
    END COLLATE utf8mb4_unicode_ci AS data_quality_display, 
    UTC_TIMESTAMP(3) AS updated_at, 
    DATE_FORMAT(m.bucket_at, '%Y-%m-%dT%H:%i:%s+00:00') AS latest_measurement_at_display, 
    DATE_FORMAT(CONVERT_TZ(m.bucket_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS latest_bucket_display, 
    CASE WHEN m.sg_median IS NULL THEN NULL ELSE CONCAT('median ', REPLACE(REPLACE(FORMAT(m.sg_median, 4) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ',')) END COLLATE utf8mb4_unicode_ci AS latest_sg_display, 
    CASE WHEN m.sg_mean IS NULL THEN NULL ELSE CONCAT('middel ', REPLACE(REPLACE(FORMAT(m.sg_mean, 4) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), ' · min ', REPLACE(REPLACE(FORMAT(m.sg_min, 4) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), ' · maks ', REPLACE(REPLACE(FORMAT(m.sg_max, 4) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ',')) END COLLATE utf8mb4_unicode_ci AS latest_sg_detail_display, 
    CASE WHEN m.temperature_mean_c IS NULL THEN NULL ELSE CONCAT(REPLACE(REPLACE(FORMAT(m.temperature_mean_c, 2) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), ' °C') END COLLATE utf8mb4_unicode_ci AS latest_temperature_display, 
    CASE WHEN m.rssi_mean_dbm IS NULL THEN NULL ELSE CONCAT(REPLACE(REPLACE(FORMAT(m.rssi_mean_dbm, 1) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), ' dBm') END COLLATE utf8mb4_unicode_ci AS latest_rssi_display, 
    DATE_FORMAT(CONVERT_TZ(sm.last_import_cutoff_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS import_cutoff_display, 
    DATE_FORMAT(CONVERT_TZ(sm.last_success_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS last_success_display, 
    CONCAT(p.poll_interval_seconds, ' s') AS poll_interval_display, 
    CONCAT(p.gap_threshold_seconds, ' s') AS gap_threshold_display, 
    CASE WHEN s.is_historical=1 AND sm.last_import_cutoff_at>=s.historical_ended_at AND g.gap_id IS NOT NULL THEN 'Gap i historisk periode' WHEN g.gap_id IS NOT NULL THEN 'ÅPENT' ELSE 'Ingen åpent gap' END COLLATE utf8mb4_unicode_ci AS gap_status_display, 
    DATE_FORMAT(CONVERT_TZ(g.gap_started_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS gap_started_display, 
    CASE WHEN sm.last_error IS NULL OR sm.last_error='' THEN 'Ingen' ELSE sm.last_error END COLLATE utf8mb4_unicode_ci AS last_error_display, 
    'MariaDB' AS authority, 
 c.counts_display AS import_counts_display, c.coverage_display AS import_coverage_display, c.summary_display AS import_summary_display
FROM ga_rb_v_measurement_source_profiles p
LEFT JOIN ga_rb_v_current_session_summary s ON 1=1
LEFT JOIN ga_rb_t_session_measurement_sources sm ON sm.session_id=s.session_id
LEFT JOIN ga_rb_v_session_measurement_source_profiles active_source ON active_source.session_id=s.session_id
LEFT JOIN ga_rb_t_measurements_5m m
  ON m.session_id=s.session_id
 AND m.bucket_at=(SELECT MAX(m2.bucket_at) FROM ga_rb_t_measurements_5m m2 WHERE m2.session_id=s.session_id)
LEFT JOIN ga_rb_v_measurement_data_gaps g
  ON g.session_id=s.session_id
 AND g.gap_ended_at IS NULL
 AND g.gap_started_at=(SELECT MAX(g2.gap_started_at) FROM ga_rb_v_measurement_data_gaps g2 WHERE g2.session_id=s.session_id AND g2.gap_ended_at IS NULL)
LEFT JOIN ga_rb_v_session_import_coverage c ON c.session_id=s.session_id
WHERE p.status='active';
 SET v_step='view:v_session_report_summary';
 INSERT INTO `ga_rb_v_session_report_summary` SELECT DISTINCT
    s.session_id, 
    s.batch_name AS batch_display, 
    yp.name AS yeast_display, 
    s.expected_attenuation_display, 
    s.expected_fg_display, 
    DATE_FORMAT(CONVERT_TZ(s.pitched_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS pitched_display, 
    CONCAT(COALESCE(CONVERT(s.current_biological_phase_id USING utf8mb4), ''), CASE WHEN s.current_biological_phase_name IS NULL OR s.current_biological_phase_name='' THEN '' ELSE CONCAT(' · ', s.current_biological_phase_name) END) AS biology_display, 
    CONCAT(COALESCE(CONVERT(s.current_process_id USING utf8mb4), ''), CASE WHEN s.current_process_name IS NULL OR s.current_process_name='' THEN '' ELSE CONCAT(' · ', s.current_process_name) END) AS process_display, 
    (SELECT REPLACE(REPLACE(FORMAT(m.sg_median, 4), ',', ''), '.', ',') FROM ga_rb_t_measurements_5m m WHERE m.session_id=s.session_id ORDER BY m.bucket_at DESC LIMIT 1) AS latest_tilt_sg_display, 
    att.actual_display AS attenuation_display, 
    rate.actual_display AS sg_rate_display, 
    rate.status_display AS sg_rate_basis_display, 
    att.status_display AS attenuation_basis_display, 
    st24.actual_display AS stability_24h_display, 
    st48.actual_display AS stability_48h_display, 
    st24.status_display AS stability_24h_basis_display, 
    st48.status_display AS stability_48h_basis_display, 
    CONCAT(REPLACE(FORMAT(s.og, 4), '.', ','), ' · ', s.volume_l, ' L') AS og_volume_display, 
    CONCAT(ROUND(TIMESTAMPDIFF(MINUTE, s.pitched_at, s.domain_now)/60, 1), ' timer siden pitch') AS elapsed_display, 
    CONCAT(ROUND(TIMESTAMPDIFF(MINUTE, s.current_biological_started_at, s.domain_now)/60, 1), ' timer i fasen') AS phase_duration_display, 
    CONCAT(ROUND(TIMESTAMPDIFF(MINUTE, s.current_process_started_at, s.domain_now)/60, 1), ' timer i prosesstrinnet') AS process_duration_display, 
    CASE WHEN att.actual_value>=0 AND s.og<1.775 THEN CONCAT(REPLACE(FORMAT((76.08*((s.og-1)*att.actual_value/100)/(1.775-s.og))*((s.og-(s.og-1)*att.actual_value/100)/0.794), 2), '.', ','), ' % · estimert') ELSE 'Utilgjengelig' END AS abv_now_display, 
    COALESCE(att.status_display, 'Mangler kvalifisert pitch-baseline eller aktuelt SG-grunnlag') AS abv_basis_display, 
    CAST((SELECT COUNT(*) FROM ga_rb_v_current_observation_revision o WHERE o.session_id=s.session_id AND o.status='active') AS CHAR) AS manual_measurements_display, 
    (
      SELECT CASE
        WHEN o.corrected_sg IS NOT NULL THEN REPLACE(REPLACE(FORMAT(o.corrected_sg, 4) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ',')
        WHEN o.measured_sg IS NOT NULL THEN REPLACE(REPLACE(FORMAT(o.measured_sg, 4) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ',')
        ELSE NULL END
      FROM ga_rb_v_current_observation_revision o
      WHERE o.session_id=s.session_id AND o.status='active'
      ORDER BY o.recorded_at DESC, o.revision_no DESC
      LIMIT 1
    ) AS latest_manual_sg_display, 
    CAST((SELECT COUNT(*) FROM ga_rb_t_session_notes n WHERE n.session_id=s.session_id) AS CHAR) AS notes_display, 
    CAST((SELECT COUNT(*) FROM ga_rb_t_measurements_5m m WHERE m.session_id=s.session_id) AS CHAR) AS datapoints_display, 
    (
      SELECT CONCAT(CONVERT(e.candidate_process_id USING utf8mb4), ' · ', 
        CASE e.readiness
          WHEN 'waiting' THEN 'Venter'
          WHEN 'manual' THEN 'Manuell vurdering'
          WHEN 'completed' THEN 'Fullført'
          WHEN 'ready' THEN 'Klar'
          WHEN 'not_ready' THEN 'Ikke klar'
          WHEN 'blocked' THEN 'Blokkert'
          WHEN 'not_evaluated' THEN 'Ikke vurdert'
          ELSE e.readiness END)
      FROM ga_rb_v_current_process_candidate_evaluation e
      WHERE e.session_id=s.session_id
      LIMIT 1
    ) AS next_process_display, 
    (SELECT CONCAT('Vurdert ', DATE_FORMAT(CONVERT_TZ(e.evaluated_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i')) FROM ga_rb_v_current_process_candidate_evaluation e WHERE e.session_id=s.session_id LIMIT 1) AS process_evaluated_display, 
    ar.public_url AS active_report_url, 
    ar.generated_display AS active_report_generated_display
FROM ga_rb_v_all_session_summary s
LEFT JOIN ga_rb_v_all_session cs ON cs.session_id=s.session_id
LEFT JOIN ga_rb_t_yeast_profiles yp ON yp.yeast_profile_id=cs.yeast_profile_id
LEFT JOIN ga_rb_v_measurement_source_status ms ON ms.session_id=s.session_id
LEFT JOIN ga_rb_v_current_metric_value att ON att.session_id=s.session_id AND att.metric_id='apparent_attenuation_percent'
LEFT JOIN ga_rb_v_current_metric_value rate ON rate.session_id=s.session_id AND rate.metric_id='sg_rate_points_per_day'
LEFT JOIN ga_rb_v_current_metric_value st24 ON st24.session_id=s.session_id AND st24.metric_id='sg_stability_24h_points'
LEFT JOIN ga_rb_v_current_metric_value st48 ON st48.session_id=s.session_id AND st48.metric_id='sg_stability_48h_points'
LEFT JOIN (
  SELECT x.session_id, x.public_url, x.generated_display
  FROM (
    SELECT e.session_id, 
           CONCAT('/local/gjaeringsassistent/exports/', SUBSTRING_INDEX(e.archive_path, '/', -1)) AS public_url, 
           DATE_FORMAT(CONVERT_TZ(e.completed_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS generated_display, 
           ROW_NUMBER() OVER (PARTITION BY e.session_id ORDER BY e.attempt_no DESC, e.completed_at DESC) AS rn
    FROM ga_rb_t_session_exports e
    WHERE e.export_kind='active_report' AND e.status='verified'
  ) x
  WHERE x.rn=1
) ar ON ar.session_id=s.session_id;
 SET v_step='view:v_active_session_report_summary';
 INSERT INTO `ga_rb_v_active_session_report_summary` SELECT r.* FROM ga_rb_v_session_report_summary r JOIN ga_rb_v_active_session a ON a.session_id=r.session_id;
 SET v_step='view:v_active_session_summary';
 INSERT INTO `ga_rb_v_active_session_summary` SELECT * FROM ga_rb_v_current_session_summary WHERE lifecycle='active';
 SET v_step='view:v_active_technical_issues';
 INSERT INTO `ga_rb_v_active_technical_issues` SELECT x.*
FROM (
    SELECT te.*, 
           ROW_NUMBER() OVER (
               PARTITION BY te.issue_key
               ORDER BY te.occurred_at DESC, te.created_at DESC, te.event_seq DESC
           ) AS rn
    FROM ga_rb_t_technical_events te
    WHERE te.issue_key IS NOT NULL
      AND te.event_type IN ('issue_raised', 'issue_cleared')
) x
WHERE x.rn=1
  AND x.event_type='issue_raised';
 SET v_step='view:v_biological_evaluation_criterion_requirement';
 INSERT INTO `ga_rb_v_biological_evaluation_criterion_requirement` SELECT
    p.evaluation_id, 
    p.criterion_id, 
    GROUP_CONCAT(
        CONCAT(
            mp.label,  ': ', 
            CASE WHEN p.is_unset=1 THEN 'Ikke angitt' ELSE CASE p.data_type
              WHEN 'real' THEN REPLACE(REPLACE(FORMAT(p.real_value, COALESCE(m.display_decimals, 2)) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ',')
              WHEN 'integer' THEN CAST(p.integer_value AS CHAR)
              WHEN 'boolean' THEN CASE WHEN p.boolean_value=1 THEN 'Ja' ELSE 'Nei' END
              ELSE p.text_value
            END END, 
            CASE WHEN p.is_unset=1 THEN '' ELSE CASE mp.unit_source
              WHEN 'metric' THEN CASE WHEN COALESCE(m.unit, '')<>'' THEN CONCAT(' ', m.unit) ELSE '' END
              WHEN 'fixed' THEN CASE WHEN COALESCE(mp.fixed_unit, '')<>'' THEN CONCAT(' ', mp.fixed_unit) ELSE '' END
              ELSE ''
            END END
        )
        ORDER BY mp.sort_order SEPARATOR ' · '
    ) AS requirement_display
FROM ga_rb_t_biological_evaluation_criterion_parameter_values p
JOIN ga_rb_t_biological_evaluation_criteria c
  ON c.evaluation_id=p.evaluation_id AND c.criterion_id=p.criterion_id
JOIN ga_rb_t_criterion_model_parameters mp
  ON mp.model_id=p.model_id AND mp.parameter_id=p.parameter_id AND mp.data_type=p.data_type
JOIN ga_rb_t_metrics m ON m.metric_id=c.metric_id
GROUP BY p.evaluation_id, p.criterion_id;
 SET v_step='view:v_effective_biological_criterion_requirement';
 INSERT INTO `ga_rb_v_effective_biological_criterion_requirement` SELECT
    p.session_id, p.phase_id, 
    p.criterion_id, 
    GROUP_CONCAT(
        CONCAT(
            mp.label,  ': ', 
            CASE WHEN p.is_unset=1 THEN 'Ikke angitt' ELSE CASE p.data_type
              WHEN 'real' THEN REPLACE(REPLACE(FORMAT(p.real_value, COALESCE(m.display_decimals, 2)) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ',')
              WHEN 'integer' THEN CAST(p.integer_value AS CHAR)
              WHEN 'boolean' THEN CASE WHEN p.boolean_value=1 THEN 'Ja' ELSE 'Nei' END
              ELSE p.text_value
            END END, 
            CASE WHEN p.is_unset=1 THEN '' ELSE CASE mp.unit_source
              WHEN 'metric' THEN CASE WHEN COALESCE(m.unit, '')<>'' THEN CONCAT(' ', m.unit) ELSE '' END
              WHEN 'fixed' THEN CASE WHEN COALESCE(mp.fixed_unit, '')<>'' THEN CONCAT(' ', mp.fixed_unit) ELSE '' END
              ELSE ''
            END END
        )
        ORDER BY mp.sort_order SEPARATOR ' · '
    ) AS requirement_display
FROM ga_rb_v_effective_biological_criterion_parameters p
JOIN ga_rb_t_session_biological_criteria c
  ON c.session_id=p.session_id AND c.phase_id=p.phase_id AND c.criterion_id=p.criterion_id
JOIN ga_rb_t_criterion_model_parameters mp
  ON mp.model_id=p.model_id AND mp.parameter_id=p.parameter_id AND mp.data_type=p.data_type
JOIN ga_rb_t_metrics m ON m.metric_id=c.metric_id
GROUP BY p.session_id, p.phase_id, p.criterion_id;
 SET v_step='view:v_template_biological_criterion_requirement';
 INSERT INTO `ga_rb_v_template_biological_criterion_requirement` SELECT
    p.session_id, p.phase_id, 
    p.criterion_id, 
    GROUP_CONCAT(
        CONCAT(
            mp.label,  ': ', 
            CASE WHEN 0=1 THEN 'Ikke angitt' ELSE CASE p.data_type
              WHEN 'real' THEN REPLACE(REPLACE(FORMAT(p.real_value, COALESCE(m.display_decimals, 2)) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ',')
              WHEN 'integer' THEN CAST(p.integer_value AS CHAR)
              WHEN 'boolean' THEN CASE WHEN p.boolean_value=1 THEN 'Ja' ELSE 'Nei' END
              ELSE p.text_value
            END END, 
            CASE WHEN 0=1 THEN '' ELSE CASE mp.unit_source
              WHEN 'metric' THEN CASE WHEN COALESCE(m.unit, '')<>'' THEN CONCAT(' ', m.unit) ELSE '' END
              WHEN 'fixed' THEN CASE WHEN COALESCE(mp.fixed_unit, '')<>'' THEN CONCAT(' ', mp.fixed_unit) ELSE '' END
              ELSE ''
            END END
        )
        ORDER BY mp.sort_order SEPARATOR ' · '
    ) AS requirement_display
FROM ga_rb_t_session_biological_criterion_parameter_values p
JOIN ga_rb_t_session_biological_criteria c
  ON c.session_id=p.session_id AND c.phase_id=p.phase_id AND c.criterion_id=p.criterion_id
JOIN ga_rb_t_criterion_model_parameters mp
  ON mp.model_id=p.model_id AND mp.parameter_id=p.parameter_id AND mp.data_type=p.data_type
JOIN ga_rb_t_metrics m ON m.metric_id=c.metric_id
GROUP BY p.session_id, p.phase_id, p.criterion_id;
 SET v_step='view:v_biological_evaluation_criterion_read_model';
 INSERT INTO `ga_rb_v_biological_evaluation_criterion_read_model` SELECT
    c.*, 
    e.evaluated_at, 
    e.created_at AS evaluation_created_at, 
    sc.label, sc.exception_allowed, 
    bx.exception_type, bx.note AS exception_note, 
    CASE WHEN sc.exception_allowed=1 AND (c.met IS NULL OR c.met<>1) AND c.evaluation_status<>'invalid_configuration' AND (c.criterion_revision_id <=> current_rev.criterion_revision_id) THEN 1 ELSE 0 END AS exception_register_allowed, 
    m.label AS metric_label, 
    m.unit AS metric_unit, 
    r.requirement_display, 
    original.requirement_display AS template_requirement_display, 
    effective.requirement_display AS effective_requirement_display, 
    (c.criterion_revision_id <=> current_rev.criterion_revision_id) AS criterion_basis_current, 
    CASE c.evaluation_status
      WHEN 'met' THEN 'Oppfylt'
      WHEN 'not_met' THEN 'Ikke oppfylt'
      WHEN 'missing_basis' THEN 'Mangler grunnlag'
      WHEN 'missing_coverage' THEN 'Mangler dekning'
      WHEN 'stale' THEN 'Foreldet grunnlag'
      WHEN 'invalid_configuration' THEN 'Konfigurasjonsfeil'
      WHEN 'not_evaluated' THEN 'Ikke vurdert'
      ELSE c.evaluation_status
    END COLLATE utf8mb4_unicode_ci AS status_display, 
    CASE
      WHEN c.actual_text IS NOT NULL THEN c.actual_text
      WHEN c.actual_value IS NOT NULL THEN CONCAT(
        REPLACE(REPLACE(FORMAT(c.actual_value, m.display_decimals) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), 
        CASE WHEN m.unit<>'' THEN CONCAT(' ', m.unit) ELSE '' END
      )
      ELSE NULL
    END COLLATE utf8mb4_unicode_ci AS actual_display, 
    CASE
      WHEN c.model_id='stability_window' AND c.requested_window_seconds IS NOT NULL THEN CONCAT(
        REPLACE(REPLACE(FORMAT(c.requested_window_seconds/3600, 1) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), ' t · dekning ', 
        REPLACE(REPLACE(FORMAT(COALESCE(c.coverage_seconds, 0)/3600, 1) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), ' t · ', 
        COALESCE(c.sample_count, 0), ' pkt'
      )
      WHEN c.requested_window_seconds IS NOT NULL THEN CONCAT(
        CASE WHEN c.requested_window_seconds>=3600
             THEN CONCAT(REPLACE(REPLACE(FORMAT(c.requested_window_seconds/3600, 1) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), ' t')
             ELSE CONCAT(ROUND(c.requested_window_seconds/60), ' min') END, 
        ' · ', COALESCE(c.sample_count, 0), ' pkt'
      )
      WHEN c.sample_count IS NOT NULL AND c.sample_count>1 THEN CONCAT(
        c.sample_count, ' prøver', 
        CASE WHEN c.latest_sample_at IS NOT NULL THEN CONCAT(' · t.o.m. ', DATE_FORMAT(CONVERT_TZ(c.latest_sample_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i')) ELSE '' END
      )
      WHEN c.latest_sample_at IS NOT NULL THEN CONCAT('Siste verdi · ', DATE_FORMAT(CONVERT_TZ(c.latest_sample_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i'))
      WHEN c.measured_at IS NOT NULL THEN CONCAT('Siste verdi · ', DATE_FORMAT(CONVERT_TZ(c.measured_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i'))
      ELSE 'Ikke tidsserie'
    END COLLATE utf8mb4_unicode_ci AS data_window_display
FROM ga_rb_t_biological_evaluation_criteria c
JOIN ga_rb_t_biological_evaluations e ON e.evaluation_id=c.evaluation_id
LEFT JOIN ga_rb_t_biological_criterion_exceptions bx ON bx.exception_id=c.applied_exception_id
JOIN ga_rb_t_metrics m ON m.metric_id=c.metric_id
LEFT JOIN ga_rb_t_session_biological_criteria sc
  ON sc.session_id=c.session_id AND sc.phase_id=c.phase_id AND sc.criterion_id=c.criterion_id
LEFT JOIN ga_rb_v_biological_evaluation_criterion_requirement r
  ON r.evaluation_id=c.evaluation_id AND r.criterion_id=c.criterion_id
LEFT JOIN ga_rb_v_template_biological_criterion_requirement original ON original.session_id=c.session_id AND original.phase_id=c.phase_id AND original.criterion_id=c.criterion_id
LEFT JOIN ga_rb_v_effective_biological_criterion_requirement effective ON effective.session_id=c.session_id AND effective.phase_id=c.phase_id AND effective.criterion_id=c.criterion_id
LEFT JOIN ga_rb_v_current_biological_criterion_revision current_rev ON current_rev.session_id=c.session_id AND current_rev.phase_id=c.phase_id AND current_rev.criterion_id=c.criterion_id;
 SET v_step='view:v_biological_transition_evidence';
 INSERT INTO `ga_rb_v_biological_transition_evidence` SELECT
    bt.transition_id, 
    bt.session_id, 
    bt.transitioned_at, 
    bt.from_phase_id, 
    bt.to_phase_id, 
    bt.transition_source, 
    bt.confidence AS transition_confidence, 
    bt.evaluation_id, 
    bt.reason AS transition_reason, 
    bt.operation_id, 
    e.current_phase_id, 
    e.candidate_phase_id, 
    e.active_visit_id, 
    e.evaluated_at, 
    e.outcome, 
    e.confidence, 
    e.data_quality, 
    e.summary, 
    e.engine_version, 
    e.created_at AS evaluation_created_at, 
    bp.phase_order AS candidate_phase_order, 
    bp.name AS candidate_phase_name
FROM ga_rb_t_biological_transitions bt
JOIN ga_rb_t_biological_evaluations e ON e.evaluation_id=bt.evaluation_id
JOIN ga_rb_t_session_biological_phases bp
  ON bp.session_id=bt.session_id AND bp.phase_id=bt.to_phase_id;
 SET v_step='view:v_criterion_correction_receipts';
 INSERT INTO `ga_rb_v_criterion_correction_receipts` SELECT q.*, CASE q.review_state WHEN 'evaluated' THEN 'Korreksjon lagret og vurdert med gjeldende krav.' WHEN 'not_current_candidate' THEN 'Korreksjon lagret. Kravet gjelder når denne fasen eller dette trinnet vurderes på nytt.' ELSE 'Korreksjon lagret. Venter på vurdering med gjeldende krav.' END COLLATE utf8mb4_unicode_ci AS review_message
FROM (SELECT 'biological' AS scope, r.session_id, r.phase_id AS owner_id, r.criterion_id, r.model_id, r.criterion_revision_id, r.revision_no, r.action, r.note, r.operation_id, r.created_at, e.evaluation_id, CASE WHEN e.evaluation_id IS NOT NULL THEN 'evaluated' WHEN NOT (own.phase_order=visit.phase_order+1) THEN 'not_current_candidate' ELSE 'pending' END AS review_state FROM ga_rb_v_current_biological_criterion_revision r JOIN ga_rb_t_session_biological_phases own ON own.session_id=r.session_id AND own.phase_id=r.phase_id JOIN ga_rb_v_current_biological_visit visit ON visit.session_id=r.session_id LEFT JOIN ga_rb_t_biological_evaluations e ON e.evaluation_id=(SELECT matching.evaluation_id FROM ga_rb_t_biological_evaluation_criteria matching JOIN ga_rb_t_biological_evaluations recorded ON recorded.evaluation_id=matching.evaluation_id WHERE matching.criterion_revision_id=r.criterion_revision_id AND matching.criterion_id=r.criterion_id AND recorded.session_id=r.session_id AND recorded.candidate_phase_id=r.phase_id ORDER BY recorded.evaluated_at DESC, recorded.created_at DESC, recorded.evaluation_id DESC LIMIT 1)
UNION ALL
SELECT 'process' AS scope, r.session_id, r.process_id AS owner_id, r.criterion_id, r.model_id, r.criterion_revision_id, r.revision_no, r.action, r.note, r.operation_id, r.created_at, e.evaluation_id, CASE WHEN e.evaluation_id IS NOT NULL THEN 'evaluated' WHEN NOT (own.process_order=(SELECT MIN(next.process_order) FROM ga_rb_t_session_process_steps next WHERE next.session_id=r.session_id AND next.enabled=1 AND next.process_order>visit.process_order)) THEN 'not_current_candidate' ELSE 'pending' END AS review_state FROM ga_rb_v_current_process_criterion_revision r JOIN ga_rb_t_session_process_steps own ON own.session_id=r.session_id AND own.process_id=r.process_id JOIN ga_rb_v_current_process_visit visit ON visit.session_id=r.session_id LEFT JOIN ga_rb_t_process_evaluations e ON e.evaluation_id=(SELECT matching.evaluation_id FROM ga_rb_t_process_evaluation_criteria matching JOIN ga_rb_t_process_evaluations recorded ON recorded.evaluation_id=matching.evaluation_id WHERE matching.criterion_revision_id=r.criterion_revision_id AND matching.criterion_id=r.criterion_id AND recorded.session_id=r.session_id AND recorded.candidate_process_id=r.process_id ORDER BY recorded.evaluated_at DESC, recorded.created_at DESC, recorded.evaluation_id DESC LIMIT 1)) q;
 SET v_step='view:v_current_biological_candidate_evaluation';
 INSERT INTO `ga_rb_v_current_biological_candidate_evaluation` SELECT x.*
FROM (
    SELECT
        e.*, 
        bp.phase_order AS candidate_phase_order, 
        bp.name AS candidate_phase_name, 
        ROW_NUMBER() OVER (
            PARTITION BY e.session_id
            ORDER BY e.created_at DESC, e.evaluation_id DESC
        ) AS rn
    FROM ga_rb_t_biological_evaluations e
    JOIN ga_rb_v_current_biological_visit cb ON cb.session_id=e.session_id
    JOIN ga_rb_t_session_biological_phases bp
      ON bp.session_id=e.session_id AND bp.phase_id=e.candidate_phase_id
    WHERE bp.phase_order=cb.phase_order+1
) x
WHERE x.rn=1;
 SET v_step='view:v_process_guidance_counts';
 INSERT INTO `ga_rb_v_process_guidance_counts` SELECT e.session_id, e.evaluation_id, 
COUNT(CASE WHEN sc.role_id='required' THEN 1 END) AS required_total, 
COUNT(CASE WHEN sc.role_id='required' AND (c.criterion_revision_id <=> revision.criterion_revision_id) AND c.met=1 THEN 1 END) AS required_met, 
COUNT(CASE WHEN sc.role_id='required' AND (c.criterion_revision_id <=> revision.criterion_revision_id) AND (c.met=1 OR EXISTS(SELECT 1 FROM ga_rb_t_process_criterion_exceptions x WHERE x.evaluation_id=c.evaluation_id AND x.criterion_id=c.criterion_id AND x.action='register' AND NOT EXISTS(SELECT 1 FROM ga_rb_t_process_criterion_exceptions n WHERE n.evaluation_id=x.evaluation_id AND n.criterion_id=x.criterion_id AND n.revision_no>x.revision_no))) THEN 1 END) AS required_handled, 
(SELECT COUNT(*) FROM ga_rb_t_process_criterion_exceptions x WHERE x.evaluation_id=e.evaluation_id AND x.action='register' AND NOT EXISTS(SELECT 1 FROM ga_rb_t_process_criterion_exceptions n WHERE n.evaluation_id=x.evaluation_id AND n.criterion_id=x.criterion_id AND n.revision_no>x.revision_no)) AS exception_count, COUNT(CASE WHEN c.criterion_id IS NOT NULL AND NOT(c.criterion_revision_id <=> revision.criterion_revision_id) THEN 1 END) AS outdated_criteria
FROM ga_rb_t_process_evaluations e LEFT JOIN ga_rb_t_session_process_criteria sc ON sc.session_id=e.session_id AND sc.process_id=e.candidate_process_id AND sc.enabled=1 LEFT JOIN ga_rb_t_process_evaluation_criteria c ON c.evaluation_id=e.evaluation_id AND c.criterion_id=sc.criterion_id LEFT JOIN ga_rb_v_current_process_criterion_revision revision ON revision.session_id=e.session_id AND revision.process_id=e.candidate_process_id AND revision.criterion_id=sc.criterion_id GROUP BY e.session_id, e.evaluation_id;
 SET v_step='view:v_process_guidance_effective';
 INSERT INTO `ga_rb_v_process_guidance_effective` SELECT e.*, g.required_total, g.required_met, g.required_handled, g.required_total-g.required_handled AS blocking_required, g.exception_count, g.outdated_criteria, 
CASE WHEN g.outdated_criteria>0 THEN 'not_evaluated' WHEN e.readiness='waiting' AND g.required_total>0 AND g.required_total=g.required_handled THEN 'ready_with_exceptions' ELSE e.readiness END AS effective_readiness
FROM ga_rb_v_current_process_candidate_evaluation e JOIN ga_rb_v_process_guidance_counts g ON g.evaluation_id=e.evaluation_id;
 SET v_step='view:v_current_process_guidance';
 INSERT INTO `ga_rb_v_current_process_guidance` SELECT s.session_id, e.evaluation_id, COALESCE(e.readiness, 'not_evaluated') AS raw_readiness, COALESCE(e.effective_readiness, 'not_evaluated') AS readiness, 
COALESCE(e.candidate_process_id, n.process_id) AS next_process_id, COALESCE(e.candidate_process_name, n.name) AS next_process_name, 
COALESCE(IF(e.outdated_criteria>0, 'Kriteriet er endret. Venter på ny vurdering.', e.summary), IF(n.process_id IS NULL, 'Prosessplan fullført', 'Prosessevaluator er ikke tilbakeført ennå')) AS trigger_summary, 
CASE WHEN e.outdated_criteria>0 THEN 'Kriteriet er endret. Venter på ny vurdering.' WHEN e.effective_readiness IN('ready', 'ready_with_exceptions') THEN CONCAT(CONVERT(e.candidate_process_id USING utf8mb4), ' kriterier oppfylt eller håndtert · venter på manuell overgang') ELSE COALESCE(e.operator_status_display, e.summary, IF(n.process_id IS NULL, 'Prosessplan fullført', 'Prosessevaluator er ikke tilbakeført ennå')) END AS reason, 
COALESCE(e.required_total, 0) AS required_total, COALESCE(e.required_met, 0) AS required_met, COALESCE(e.required_handled, 0) AS required_handled, 
COALESCE(e.blocking_required, 0) AS blocking_required, COALESCE(e.exception_count, 0) AS exception_count, e.recommended_temperature_c, e.recommended_pressure_bar, 
IF(e.evaluation_id IS NULL, 'not_yet', 'present') AS evaluation_status
FROM ga_rb_v_current_session_summary s LEFT JOIN ga_rb_v_process_guidance_effective e ON e.session_id=s.session_id
LEFT JOIN ga_rb_t_session_process_steps n ON n.session_id=s.session_id AND n.enabled=1 AND n.process_order=(SELECT MIN(p.process_order) FROM ga_rb_t_session_process_steps p WHERE p.session_id=s.session_id AND p.enabled=1 AND p.process_order>s.current_process_order);
 SET v_step='view:v_graph_display_selection';
 INSERT INTO `ga_rb_v_graph_display_selection` SELECT g.* FROM ga_rb_t_graph_display_selection_events g WHERE selection_seq=(SELECT MAX(selection_seq) FROM ga_rb_t_graph_display_selection_events);
 SET v_step='view:v_session_measurement_series';
 INSERT INTO `ga_rb_v_session_measurement_series` SELECT m.session_id, m.bucket_at, IF(a.is_historical=1, LEAST(TIMESTAMPADD(SECOND, COALESCE(ds.interval_seconds, 300), m.bucket_at), a.domain_now), TIMESTAMPADD(SECOND, COALESCE(ds.interval_seconds, 300), m.bucket_at)) AS interval_ended_at, m.sample_count, m.sg_min, m.sg_mean, m.sg_median, m.sg_median AS sg_value, m.sg_max, m.temperature_min_c, m.temperature_mean_c, m.temperature_max_c, m.pressure_min_bar, m.pressure_mean_bar, m.pressure_max_bar, m.rssi_min_dbm, m.rssi_mean_dbm, m.rssi_max_dbm, 'detail_5m' AS source_kind, CASE WHEN ds.interval_seconds=3600 THEN 'Syntetisk original · timepunkter' ELSE 'Detaljdata · 5 minutter' END AS source_display, COALESCE(ds.interval_seconds, 300) AS interval_seconds
FROM ga_rb_t_measurements_5m m JOIN ga_rb_v_all_session a ON a.session_id=m.session_id LEFT JOIN ga_rb_t_session_demo_sources ds ON ds.session_id=m.session_id WHERE a.is_historical=0 OR m.bucket_at>=a.pitched_at AND m.bucket_at<a.domain_now
UNION ALL
SELECT h.session_id, h.start_at, h.end_at, NULL, h.sg_min, h.sg_mean, NULL, h.sg_mean, h.sg_max, h.temperature_min_c, h.temperature_mean_c, h.temperature_max_c, NULL, NULL, NULL, h.rssi_min_dbm, h.rssi_mean_dbm, h.rssi_max_dbm, 'ha_statistics_hourly', 'HA langtidsstatistikk · timeverdier', 3600
FROM ga_rb_v_current_measurement_statistics_hourly h JOIN ga_rb_v_all_session s ON s.session_id=h.session_id
WHERE h.start_at>=s.pitched_at AND (s.is_historical=0 OR h.end_at<=s.domain_now) AND NOT EXISTS(SELECT 1 FROM ga_rb_t_measurements_5m m WHERE m.session_id=h.session_id AND m.bucket_at>=h.start_at AND m.bucket_at<h.end_at);
END//
CREATE PROCEDURE ga_fill_read_basis_part_7() BEGIN
 DECLARE v_stage LONGTEXT; DECLARE v_expected BIGINT; DECLARE v_step VARCHAR(128); DECLARE v_error TEXT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_error=MESSAGE_TEXT; SET v_error=CONCAT(v_step, ': ', LEFT(v_error, 350)); RESIGNAL SET MESSAGE_TEXT=v_error; END;
 SET v_step='view:v_dashboard_graph_labels';
 INSERT INTO `ga_rb_v_dashboard_graph_labels` SELECT c.selection_seq, 
'Detaljdata lagres hvert 5. minutt. Timesstatistikk fra HA beholder sin oppløsning.' AS graph_basis_display, 
COALESCE((SELECT GROUP_CONCAT(DISTINCT source_display ORDER BY source_display SEPARATOR ' · ') FROM ga_rb_v_session_measurement_series m JOIN ga_rb_v_active_session a ON a.session_id=m.session_id), 'Ingen måledata') AS measurement_source_labels, 
CASE c.source_kind WHEN 'reference' THEN (SELECT name FROM ga_rb_t_demo_reference_profiles d WHERE d.profile_id=c.reference_profile_id) WHEN 'session' THEN (SELECT batch_name FROM ga_rb_t_sessions s WHERE s.session_id=c.reference_session_id) ELSE NULL END AS comparison_display
FROM ga_rb_v_graph_display_selection c;
 SET v_step='view:v_graph_reference_bands';
 INSERT INTO `ga_rb_v_graph_reference_bands` SELECT d.session_id, d.graph_id, d.series_id, d.label, t.expected_fg_min AS minimum_value, t.expected_fg_max AS maximum_value, d.standard_color AS line_color, d.band_opacity
FROM ga_rb_t_session_analysis_graph_series d JOIN ga_rb_v_current_fermentation_target t ON t.session_id=d.session_id WHERE d.source_kind='fermentation_target' AND d.metric_id='tilt_sg';
 SET v_step='view:v_session_analysis_series';
 INSERT INTO `ga_rb_v_session_analysis_series` SELECT s.session_id, s.graph_id, s.series_id, s.sort_order, s.label, s.source_kind, s.metric_id, s.owner_id, s.criterion_id, 
       s.minimum_samples, s.minimum_coverage_fraction, s.warmup_minutes, s.valid_minimum_value, s.valid_maximum_value, 
       s.provisional_allowed, s.provisional_minimum_samples, s.provisional_minimum_span_minutes, s.render_mode, 
       s.band_model, s.band_description, s.band_opacity, s.standard_color, s.provisional_color, s.standard_dasharray, s.provisional_dasharray, 
       CASE WHEN v.actual_value IS NULL THEN NULL ELSE CONCAT(REPLACE(REPLACE(FORMAT(v.actual_value, g.display_decimals) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), ' ', g.unit) END COLLATE utf8mb4_unicode_ci AS actual_value_display, 
       v.sample_at, v.basis_pitched_at, v.source_observation_revision_id, v.basis_revision_key, v.actual_value, v.range_min_value, v.range_max_value, v.measured_at, v.sample_count, v.window_started_at, v.window_ended_at, v.requested_window_seconds, v.coverage_seconds, v.source_kind AS value_source_kind, 
       v.value_status, v.standard_basis_met, 
       CASE v.value_status WHEN 'provisional' THEN 'Foreløpig' WHEN 'standard' THEN 'Ordinær' ELSE 'Utilgjengelig' END COLLATE utf8mb4_unicode_ci AS value_status_display, 
       CASE v.value_status WHEN 'provisional' THEN s.provisional_color WHEN 'standard' THEN s.standard_color ELSE NULL END AS line_color, 
       CASE v.value_status WHEN 'provisional' THEN s.provisional_dasharray WHEN 'standard' THEN s.standard_dasharray ELSE NULL END AS line_dasharray, 
       CASE WHEN v.sample_at IS NULL THEN NULL ELSE CONCAT(CASE v.value_status WHEN 'provisional' THEN 'Foreløpig' WHEN 'standard' THEN 'Ordinær' END, ' · ', v.sample_count, ' målepunkter · ', ROUND(v.coverage_seconds/60), ' min', CASE WHEN v.requested_window_seconds>0 THEN CONCAT(' av ', ROUND(v.requested_window_seconds/60), ' min · ', ROUND(100*v.coverage_seconds/v.requested_window_seconds), ' % tidsdekning') ELSE '' END) END COLLATE utf8mb4_unicode_ci AS basis_display, 
       CASE WHEN v.requested_window_seconds>0 THEN v.coverage_seconds/v.requested_window_seconds ELSE NULL END AS coverage_fraction
FROM ga_rb_t_session_analysis_graph_series s
JOIN ga_rb_t_session_analysis_graphs g ON g.session_id=s.session_id AND g.graph_id=s.graph_id
LEFT JOIN ga_rb_t_analysis_series_values v ON v.session_id=s.session_id AND v.graph_id=s.graph_id AND v.series_id=s.series_id AND v.basis_pitched_at=(SELECT pitched_at FROM ga_rb_v_all_session WHERE session_id=s.session_id) AND (v.source_observation_revision_id IS NULL OR EXISTS(SELECT 1 FROM ga_rb_v_current_observation_revision o WHERE o.observation_revision_id=v.source_observation_revision_id AND o.session_id=v.session_id AND o.status='active'));
 SET v_step='view:v_graph_reference_analysis_series';
 INSERT INTO `ga_rb_v_graph_reference_analysis_series` SELECT a.session_id AS session_id, 
 d.graph_id AS graph_id, 
 CONCAT('comparison-', d.series_id) AS series_id, 
 d.sort_order AS sort_order, 
 CONCAT(p.name, ' · ', d.label) AS label, 
 d.source_kind AS source_kind, 
 d.metric_id AS metric_id, 
 d.owner_id AS owner_id, 
 d.criterion_id AS criterion_id, 
 d.minimum_samples AS minimum_samples, 
 d.minimum_coverage_fraction AS minimum_coverage_fraction, 
 d.warmup_minutes AS warmup_minutes, 
 d.valid_minimum_value AS valid_minimum_value, 
 d.valid_maximum_value AS valid_maximum_value, 
 d.provisional_allowed AS provisional_allowed, 
 d.provisional_minimum_samples AS provisional_minimum_samples, 
 d.provisional_minimum_span_minutes AS provisional_minimum_span_minutes, 
 d.render_mode AS render_mode, 
 d.band_model AS band_model, 
 d.band_description AS band_description, 
 d.band_opacity AS band_opacity, 
 d.standard_color AS standard_color, 
 d.provisional_color AS provisional_color, 
 d.standard_dasharray AS standard_dasharray, 
 d.provisional_dasharray AS provisional_dasharray, 
 CONCAT(REPLACE(REPLACE(FORMAT(v.actual_value, g.display_decimals), ',', ''), '.', ','), ' ', g.unit) AS actual_value_display, 
 TIMESTAMPADD(SECOND, v.offset_seconds, a.pitched_at) AS sample_at, 
 a.pitched_at AS basis_pitched_at, 
 NULL AS source_observation_revision_id, 
 p.profile_id AS basis_revision_key, 
 v.actual_value AS actual_value, 
 NULL AS range_min_value, 
 NULL AS range_max_value, 
 TIMESTAMPADD(SECOND, v.offset_seconds, a.pitched_at) AS measured_at, 
 v.sample_count AS sample_count, 
 TIMESTAMPADD(SECOND, v.offset_seconds-v.coverage_seconds, a.pitched_at) AS window_started_at, 
 TIMESTAMPADD(SECOND, v.offset_seconds, a.pitched_at) AS window_ended_at, 
 v.window_seconds AS requested_window_seconds, 
 v.coverage_seconds AS coverage_seconds, 
 'reference' AS value_source_kind, 
 'standard' AS value_status, 
 1 AS standard_basis_met, 
 'Referanse' AS value_status_display, 
 '#ef6c00' AS line_color, 
 CASE WHEN d.sort_order=1 THEN '6 3' ELSE '2 4' END AS line_dasharray, 
 CONCAT(p.name, ' · ', v.basis_display) AS basis_display, 
 CASE WHEN v.window_seconds>0 THEN v.coverage_seconds/v.window_seconds ELSE NULL END AS coverage_fraction FROM ga_rb_v_active_session a JOIN ga_rb_v_graph_display_selection choice ON choice.source_kind='reference' JOIN ga_rb_t_demo_reference_profiles p ON p.profile_id=choice.reference_profile_id JOIN ga_rb_t_demo_reference_analysis_values v ON v.profile_id=p.profile_id JOIN ga_rb_t_session_analysis_graph_series d ON d.session_id=a.session_id AND d.graph_id=v.graph_id AND d.series_id=v.series_id JOIN ga_rb_t_session_analysis_graphs g ON g.session_id=d.session_id AND g.graph_id=d.graph_id
UNION ALL
SELECT a.session_id AS session_id, 
 v.graph_id AS graph_id, 
 CONCAT('comparison-', v.series_id) AS series_id, 
 v.sort_order AS sort_order, 
 CONCAT(s.batch_name, ' · ', v.label) AS label, 
 v.source_kind AS source_kind, 
 v.metric_id AS metric_id, 
 v.owner_id AS owner_id, 
 v.criterion_id AS criterion_id, 
 v.minimum_samples AS minimum_samples, 
 v.minimum_coverage_fraction AS minimum_coverage_fraction, 
 v.warmup_minutes AS warmup_minutes, 
 v.valid_minimum_value AS valid_minimum_value, 
 v.valid_maximum_value AS valid_maximum_value, 
 v.provisional_allowed AS provisional_allowed, 
 v.provisional_minimum_samples AS provisional_minimum_samples, 
 v.provisional_minimum_span_minutes AS provisional_minimum_span_minutes, 
 v.render_mode AS render_mode, 
 v.band_model AS band_model, 
 v.band_description AS band_description, 
 v.band_opacity AS band_opacity, 
 v.standard_color AS standard_color, 
 v.provisional_color AS provisional_color, 
 v.standard_dasharray AS standard_dasharray, 
 v.provisional_dasharray AS provisional_dasharray, 
 v.actual_value_display AS actual_value_display, 
 TIMESTAMPADD(SECOND, TIMESTAMPDIFF(SECOND, s.pitched_at, v.sample_at), a.pitched_at) AS sample_at, 
 a.pitched_at AS basis_pitched_at, 
 v.source_observation_revision_id AS source_observation_revision_id, 
 v.basis_revision_key AS basis_revision_key, 
 v.actual_value AS actual_value, 
 v.range_min_value AS range_min_value, 
 v.range_max_value AS range_max_value, 
 TIMESTAMPADD(SECOND, TIMESTAMPDIFF(SECOND, s.pitched_at, v.measured_at), a.pitched_at) AS measured_at, 
 v.sample_count AS sample_count, 
 TIMESTAMPADD(SECOND, TIMESTAMPDIFF(SECOND, s.pitched_at, v.window_started_at), a.pitched_at) AS window_started_at, 
 TIMESTAMPADD(SECOND, TIMESTAMPDIFF(SECOND, s.pitched_at, v.window_ended_at), a.pitched_at) AS window_ended_at, 
 v.requested_window_seconds AS requested_window_seconds, 
 v.coverage_seconds AS coverage_seconds, 
 v.value_source_kind AS value_source_kind, 
 v.value_status AS value_status, 
 v.standard_basis_met AS standard_basis_met, 
 v.value_status_display AS value_status_display, 
 '#ef6c00' AS line_color, 
 '6 3' AS line_dasharray, 
 CONCAT(s.batch_name, ' · ', v.basis_display) AS basis_display, 
 v.coverage_fraction AS coverage_fraction FROM ga_rb_v_active_session a JOIN ga_rb_v_graph_display_selection choice ON choice.source_kind='session' JOIN ga_rb_v_all_session s ON s.session_id=choice.reference_session_id JOIN ga_rb_v_session_analysis_series v ON v.session_id=s.session_id;
 SET v_step='view:v_session_hourly_analysis_policy';
 INSERT INTO `ga_rb_v_session_hourly_analysis_policy` SELECT d.*, g.display_decimals, g.unit, m.calculation_model_id, 
CASE WHEN m.calculation_model_id='metric-rolling-sg-range-v1' THEN (SELECT COALESCE(p.real_value, p.integer_value) FROM ga_rb_t_session_metric_runtime_parameter_values p WHERE p.session_id=d.session_id AND p.metric_id=d.metric_id AND p.parameter_id='window_hours') ELSE (SELECT COALESCE(p.real_value, p.integer_value) FROM ga_rb_t_session_biology_calculation_parameter_values p JOIN ga_rb_t_session_metric_runtime_inputs i ON i.session_id=p.session_id AND i.source_id=p.calculation_id AND i.source_kind='biology_calculation' WHERE i.session_id=d.session_id AND i.metric_id=d.metric_id AND i.input_id='calculation' AND p.parameter_id='window_hours') END AS window_hours, 
CASE WHEN m.calculation_model_id='metric-rolling-sg-range-v1' THEN 60*(SELECT COALESCE(p.real_value, p.integer_value) FROM ga_rb_t_session_metric_runtime_parameter_values p WHERE p.session_id=d.session_id AND p.metric_id=d.metric_id AND p.parameter_id='minimum_span_hours') ELSE (SELECT COALESCE(p.real_value, p.integer_value) FROM ga_rb_t_session_biology_calculation_parameter_values p JOIN ga_rb_t_session_metric_runtime_inputs i ON i.session_id=p.session_id AND i.source_id=p.calculation_id AND i.source_kind='biology_calculation' WHERE i.session_id=d.session_id AND i.metric_id=d.metric_id AND i.input_id='calculation' AND p.parameter_id='minimum_span_minutes') END AS minimum_span_minutes
FROM ga_rb_t_session_analysis_graph_series d JOIN ga_rb_t_session_analysis_graphs g ON g.session_id=d.session_id AND g.graph_id=d.graph_id JOIN ga_rb_t_session_metric_runtime_rules m ON m.session_id=d.session_id AND m.metric_id=d.metric_id WHERE d.source_kind='metric' AND m.calculation_model_id IN ('metric-raw-attenuation-v1', 'metric-calculation-output-v1', 'metric-rolling-sg-range-v1');
 SET v_step='view:v_session_hourly_analysis_aggregate';
 INSERT INTO `ga_rb_v_session_hourly_analysis_aggregate` SELECT d.session_id, d.graph_id, d.series_id, h.bucket_at AS sample_at, MIN(pr.bucket_at) AS window_started_at, MAX(pr.bucket_at) AS window_ended_at, COUNT(*) AS sample_count, TIMESTAMPDIFF(SECOND, MIN(pr.bucket_at), MAX(pr.bucket_at)) AS coverage_seconds, MIN(pr.sg_mean) AS value_min, MAX(pr.sg_mean) AS value_max, 
MAX(h.sg_mean) AS current_sg, 
(SELECT first.sg_mean FROM ga_rb_v_session_measurement_series first WHERE first.session_id=d.session_id AND first.source_kind='ha_statistics_hourly' AND first.bucket_at=MIN(pr.bucket_at) LIMIT 1) AS first_sg
FROM ga_rb_v_session_hourly_analysis_policy d JOIN ga_rb_v_session_measurement_series h ON h.session_id=d.session_id AND h.source_kind='ha_statistics_hourly' AND h.sg_mean IS NOT NULL JOIN ga_rb_v_session_measurement_series pr ON pr.session_id=d.session_id AND pr.source_kind='ha_statistics_hourly' AND pr.sg_mean IS NOT NULL AND pr.bucket_at BETWEEN TIMESTAMPADD(SECOND, -d.window_hours*3600, h.bucket_at) AND h.bucket_at
WHERE d.calculation_model_id<>'metric-raw-attenuation-v1' GROUP BY d.session_id, d.graph_id, d.series_id, h.bucket_at;
 SET v_step='view:v_session_hourly_analysis_values';
 INSERT INTO `ga_rb_v_session_hourly_analysis_values` SELECT d.session_id, d.graph_id, d.series_id, h.bucket_at AS sample_at, 100*(s.og-h.sg_mean)/(s.og-1) AS actual_value, 1 AS sample_count, 0 AS coverage_seconds, 0 AS requested_window_seconds, h.bucket_at AS window_started_at, h.bucket_at AS window_ended_at
FROM ga_rb_v_session_hourly_analysis_policy d JOIN ga_rb_v_all_session s ON s.session_id=d.session_id JOIN ga_rb_v_session_measurement_series h ON h.session_id=d.session_id AND h.source_kind='ha_statistics_hourly' WHERE d.calculation_model_id='metric-raw-attenuation-v1' AND h.sg_mean IS NOT NULL AND s.og>1
UNION ALL
SELECT d.session_id, d.graph_id, d.series_id, a.sample_at, CASE d.calculation_model_id WHEN 'metric-calculation-output-v1' THEN 1000*(a.first_sg-a.current_sg)*86400/a.coverage_seconds ELSE 1000*(a.value_max-a.value_min) END, a.sample_count, a.coverage_seconds, d.window_hours*3600, a.window_started_at, a.window_ended_at
FROM ga_rb_v_session_hourly_analysis_policy d JOIN ga_rb_v_session_hourly_analysis_aggregate a ON a.session_id=d.session_id AND a.graph_id=d.graph_id AND a.series_id=d.series_id JOIN ga_rb_v_all_session s ON s.session_id=d.session_id
WHERE a.sample_count>=2 AND a.coverage_seconds>=d.minimum_span_minutes*60 AND a.coverage_seconds>=d.window_hours*3600*d.minimum_coverage_fraction AND TIMESTAMPDIFF(MINUTE, s.pitched_at, a.sample_at)>=d.warmup_minutes AND a.coverage_seconds>0 AND a.sample_count=a.coverage_seconds/3600+1;
 SET v_step='view:v_session_hourly_analysis_series';
 INSERT INTO `ga_rb_v_session_hourly_analysis_series` SELECT d.session_id AS session_id, 
 d.graph_id AS graph_id, 
 CONCAT('ha-hourly-', d.series_id) AS series_id, 
 d.sort_order AS sort_order, 
 CONCAT('HA timeverdier · ', d.label) AS label, 
 d.source_kind AS source_kind, 
 d.metric_id AS metric_id, 
 d.owner_id AS owner_id, 
 d.criterion_id AS criterion_id, 
 d.minimum_samples AS minimum_samples, 
 d.minimum_coverage_fraction AS minimum_coverage_fraction, 
 d.warmup_minutes AS warmup_minutes, 
 d.valid_minimum_value AS valid_minimum_value, 
 d.valid_maximum_value AS valid_maximum_value, 
 d.provisional_allowed AS provisional_allowed, 
 d.provisional_minimum_samples AS provisional_minimum_samples, 
 d.provisional_minimum_span_minutes AS provisional_minimum_span_minutes, 
 d.render_mode AS render_mode, 
 d.band_model AS band_model, 
 d.band_description AS band_description, 
 d.band_opacity AS band_opacity, 
 d.standard_color AS standard_color, 
 d.provisional_color AS provisional_color, 
 d.standard_dasharray AS standard_dasharray, 
 d.provisional_dasharray AS provisional_dasharray, 
 CONCAT(REPLACE(REPLACE(FORMAT(v.actual_value, d.display_decimals), ',', ''), '.', ','), ' ', d.unit) AS actual_value_display, 
 v.sample_at AS sample_at, 
 a.pitched_at AS basis_pitched_at, 
 NULL AS source_observation_revision_id, 
 'ha-hourly' AS basis_revision_key, 
 v.actual_value AS actual_value, 
 NULL AS range_min_value, 
 NULL AS range_max_value, 
 v.sample_at AS measured_at, 
 v.sample_count AS sample_count, 
 v.window_started_at AS window_started_at, 
 v.window_ended_at AS window_ended_at, 
 v.requested_window_seconds AS requested_window_seconds, 
 v.coverage_seconds AS coverage_seconds, 
 'ha_statistics_hourly' AS value_source_kind, 
 'standard' AS value_status, 
 1 AS standard_basis_met, 
 'HA timeverdier' AS value_status_display, 
 '#00897b' AS line_color, 
 '3 3' AS line_dasharray, 
 CONCAT('HA langtidsstatistikk · ', v.sample_count, ' timeverdier · ingen MQTT-verifikasjon') AS basis_display, 
 CASE WHEN v.requested_window_seconds>0 THEN v.coverage_seconds/v.requested_window_seconds ELSE NULL END AS coverage_fraction FROM ga_rb_v_session_hourly_analysis_policy d JOIN ga_rb_v_session_hourly_analysis_values v ON v.session_id=d.session_id AND v.graph_id=d.graph_id AND v.series_id=d.series_id JOIN ga_rb_v_all_session a ON a.session_id=d.session_id WHERE (d.valid_minimum_value IS NULL OR v.actual_value>=d.valid_minimum_value) AND (d.valid_maximum_value IS NULL OR v.actual_value<=d.valid_maximum_value);
 SET v_step='view:v_primary_analysis_source';
 INSERT INTO `ga_rb_v_primary_analysis_source` SELECT s.*, 'primary' AS series_role, 300 AS interval_seconds FROM ga_rb_v_session_analysis_series s UNION ALL SELECT s.*, 'primary', 3600 FROM ga_rb_v_session_hourly_analysis_series s;
 SET v_step='view:v_dashboard_analysis_source';
 INSERT INTO `ga_rb_v_dashboard_analysis_source` SELECT * FROM ga_rb_v_primary_analysis_source UNION ALL SELECT s.*, 'comparison', CASE WHEN s.value_source_kind='ha_statistics_hourly' THEN 3600 ELSE 300 END FROM ga_rb_v_graph_reference_analysis_series s;
 SET v_step='view:v_dashboard_analysis_segments';
 INSERT INTO `ga_rb_v_dashboard_analysis_segments` SELECT q.*, SUM(q.new_segment) OVER(PARTITION BY q.session_id, q.graph_id, q.series_id ORDER BY q.sample_at) AS segment_id
FROM(SELECT x.*, CASE WHEN x.previous_at IS NULL OR TIMESTAMPDIFF(SECOND, x.previous_at, x.sample_at)>x.interval_seconds THEN 1 ELSE 0 END AS new_segment
FROM(SELECT s.*, LAG(s.sample_at) OVER(PARTITION BY s.session_id, s.graph_id, s.series_id ORDER BY s.sample_at) AS previous_at FROM ga_rb_v_dashboard_analysis_source s) x) q;
 SET v_step='view:v_session_measurement_segments';
 INSERT INTO `ga_rb_v_session_measurement_segments` SELECT q.*, SUM(q.new_segment) OVER(PARTITION BY q.session_id ORDER BY q.bucket_at) AS segment_id
FROM(SELECT m.*, CASE WHEN LAG(source_kind) OVER(PARTITION BY session_id ORDER BY bucket_at)<>source_kind OR TIMESTAMPDIFF(SECOND, LAG(bucket_at) OVER(PARTITION BY session_id ORDER BY bucket_at), bucket_at)>LAG(interval_seconds) OVER(PARTITION BY session_id ORDER BY bucket_at) THEN 1 ELSE 0 END AS new_segment FROM ga_rb_v_session_measurement_series m) q;
 SET v_step='view:v_graph_reference_measurement_series';
 INSERT INTO `ga_rb_v_graph_reference_measurement_series` SELECT a.session_id, TIMESTAMPADD(SECOND, m.offset_seconds, a.pitched_at) AS bucket_at, m.sample_count, m.sg_min, m.sg_mean, m.sg_median, m.sg_median AS sg_value, m.sg_max, COALESCE(d.temperature_min_c, m.temperature_mean_c) AS temperature_min_c, m.temperature_mean_c, COALESCE(d.temperature_max_c, m.temperature_mean_c) AS temperature_max_c, sy.pressure_bar AS pressure_min_bar, sy.pressure_bar AS pressure_mean_bar, sy.pressure_bar AS pressure_max_bar, (SELECT COUNT(*) FROM ga_rb_t_demo_reference_data_gaps gap WHERE gap.profile_id=p.profile_id AND gap.gap_end_offset_seconds<=m.offset_seconds) AS segment_id, p.name AS source_display
FROM ga_rb_v_active_session a JOIN ga_rb_v_graph_display_selection choice ON choice.source_kind='reference' JOIN ga_rb_t_demo_reference_profiles p ON p.profile_id=choice.reference_profile_id JOIN ga_rb_t_demo_reference_measurements_5m m ON m.profile_id=p.profile_id LEFT JOIN ga_rb_t_demo_reference_measurement_details d ON d.profile_id=m.profile_id AND d.offset_seconds=m.offset_seconds LEFT JOIN ga_rb_t_demo_reference_synthetic_details sy ON sy.profile_id=m.profile_id AND sy.offset_seconds=m.offset_seconds
UNION ALL
SELECT a.session_id, TIMESTAMPADD(SECOND, TIMESTAMPDIFF(SECOND, s.pitched_at, m.bucket_at), a.pitched_at), m.sample_count, m.sg_min, m.sg_mean, m.sg_median, m.sg_value, m.sg_max, m.temperature_min_c, m.temperature_mean_c, m.temperature_max_c, m.pressure_min_bar, m.pressure_mean_bar, m.pressure_max_bar, m.segment_id, s.batch_name
FROM ga_rb_v_active_session a JOIN ga_rb_v_graph_display_selection choice ON choice.source_kind='session' JOIN ga_rb_v_all_session s ON s.session_id=choice.reference_session_id JOIN ga_rb_v_session_measurement_segments m ON m.session_id=s.session_id;
 SET v_step='view:v_session_graph_time_axis';
 INSERT INTO `ga_rb_v_session_graph_time_axis` SELECT q.session_id, 
CASE WHEN c.window_hours IS NULL THEN q.pitched_at ELSE GREATEST(q.pitched_at, TIMESTAMPADD(HOUR, -c.window_hours, q.primary_end)) END AS x_axis_started_at, 
CASE WHEN c.window_hours IS NULL THEN IF(q.is_historical=1, q.primary_end, GREATEST(q.primary_end, COALESCE(ref.last_at, q.primary_end))) ELSE q.primary_end END AS x_axis_ended_at, 
CONCAT('Dag ', ROUND(TIMESTAMPDIFF(SECOND, q.pitched_at, CASE WHEN c.window_hours IS NULL THEN q.pitched_at ELSE GREATEST(q.pitched_at, TIMESTAMPADD(HOUR, -c.window_hours, q.primary_end)) END)/86400, 2), ' · ', DATE_FORMAT(CONVERT_TZ(CASE WHEN c.window_hours IS NULL THEN q.pitched_at ELSE GREATEST(q.pitched_at, TIMESTAMPADD(HOUR, -c.window_hours, q.primary_end)) END, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i')) AS x_axis_start_display, 
CONCAT('Dag ', ROUND(TIMESTAMPDIFF(SECOND, q.pitched_at, CASE WHEN c.window_hours IS NULL THEN IF(q.is_historical=1, q.primary_end, GREATEST(q.primary_end, COALESCE(ref.last_at, q.primary_end))) ELSE q.primary_end END)/86400, 2), ' · ', DATE_FORMAT(CONVERT_TZ(CASE WHEN c.window_hours IS NULL THEN IF(q.is_historical=1, q.primary_end, GREATEST(q.primary_end, COALESCE(ref.last_at, q.primary_end))) ELSE q.primary_end END, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i')) AS x_axis_end_display
FROM(SELECT s.session_id, s.pitched_at, s.is_historical, s.domain_now AS primary_end FROM ga_rb_v_all_session s LEFT JOIN(SELECT session_id, MAX(bucket_at) AS last_at FROM ga_rb_v_session_measurement_series GROUP BY session_id) m ON m.session_id=s.session_id) q JOIN ga_rb_v_graph_display_selection c LEFT JOIN(SELECT session_id, MAX(bucket_at) AS last_at FROM ga_rb_v_graph_reference_measurement_series GROUP BY session_id) ref ON ref.session_id=q.session_id;
 SET v_step='view:v_dashboard_analysis_series';
 INSERT INTO `ga_rb_v_dashboard_analysis_series` SELECT q.* FROM(SELECT s.*, 
ROW_NUMBER() OVER(PARTITION BY s.session_id, s.graph_id, s.series_id, s.segment_id, FLOOR(UNIX_TIMESTAMP(s.sample_at)/c.interval_seconds) ORDER BY s.sample_at) AS first_rank, 
ROW_NUMBER() OVER(PARTITION BY s.session_id, s.graph_id, s.series_id, s.segment_id, FLOOR(UNIX_TIMESTAMP(s.sample_at)/c.interval_seconds) ORDER BY s.sample_at DESC) AS last_rank, 
ROW_NUMBER() OVER(PARTITION BY s.session_id, s.graph_id, s.series_id, s.segment_id, FLOOR(UNIX_TIMESTAMP(s.sample_at)/c.interval_seconds) ORDER BY s.actual_value, s.sample_at) AS min_rank, 
ROW_NUMBER() OVER(PARTITION BY s.session_id, s.graph_id, s.series_id, s.segment_id, FLOOR(UNIX_TIMESTAMP(s.sample_at)/c.interval_seconds) ORDER BY s.actual_value DESC, s.sample_at) AS max_rank
FROM ga_rb_v_dashboard_analysis_segments s JOIN ga_rb_v_graph_display_selection c JOIN ga_rb_v_session_graph_time_axis t ON t.session_id=s.session_id WHERE s.sample_at IS NULL OR s.sample_at BETWEEN t.x_axis_started_at AND t.x_axis_ended_at) q
WHERE q.first_rank=1 OR q.last_rank=1 OR q.min_rank=1 OR q.max_rank=1;
 SET v_step='view:v_graph_comparison_display';
 INSERT INTO `ga_rb_v_graph_comparison_display` SELECT m.session_id, MIN(m.bucket_at) AS bucket_at, MIN(m.sg_min) AS sg_min, CASE WHEN COUNT(m.sample_count)=COUNT(*) THEN SUM(m.sg_value*m.sample_count)/SUM(m.sample_count) ELSE AVG(m.sg_value) END AS sg_value, MAX(m.sg_max) AS sg_max, 
MIN(m.temperature_min_c) AS temperature_min_c, AVG(m.temperature_mean_c) AS temperature_mean_c, MAX(m.temperature_max_c) AS temperature_max_c, 
MIN(m.pressure_min_bar) AS pressure_min_bar, AVG(m.pressure_mean_bar) AS pressure_mean_bar, MAX(m.pressure_max_bar) AS pressure_max_bar, m.segment_id, 
CONCAT(MAX(m.source_display), ' · ', c.interval_seconds/60, ' minutter') AS source_display
FROM ga_rb_v_graph_reference_measurement_series m JOIN ga_rb_v_graph_display_selection c GROUP BY m.session_id, m.segment_id, FLOOR(UNIX_TIMESTAMP(m.bucket_at)/c.interval_seconds), c.interval_seconds;
 SET v_step='view:v_graph_process_plan';
 INSERT INTO `ga_rb_v_graph_process_plan` SELECT t.session_id, t.metric_id, p.visit_id, r.started_at, LEAST(COALESCE(r.ended_at, axis.x_axis_ended_at), axis.x_axis_ended_at) AS ended_at, 
 e.target_value AS actual_value, e.target_value AS minimum_value, e.target_value AS maximum_value, t.label
FROM ga_rb_t_session_process_targets t JOIN ga_rb_t_session_process_target_exact e ON e.session_id=t.session_id AND e.process_id=t.process_id AND e.target_id=t.target_id
JOIN ga_rb_t_process_visits p ON p.session_id=t.session_id AND p.process_id=t.process_id JOIN ga_rb_v_process_visit_timing r ON r.visit_id=p.visit_id JOIN ga_rb_v_session_graph_time_axis axis ON axis.session_id=t.session_id
UNION ALL
SELECT t.session_id, t.metric_id, p.visit_id, r.started_at, LEAST(COALESCE(r.ended_at, axis.x_axis_ended_at), axis.x_axis_ended_at), 
 (e.minimum_value+e.maximum_value)/2, e.minimum_value, e.maximum_value, CONCAT(t.label, ' · midtpunkt i planintervall')
FROM ga_rb_t_session_process_targets t JOIN ga_rb_t_session_process_target_range e ON e.session_id=t.session_id AND e.process_id=t.process_id AND e.target_id=t.target_id
JOIN ga_rb_t_process_visits p ON p.session_id=t.session_id AND p.process_id=t.process_id JOIN ga_rb_v_process_visit_timing r ON r.visit_id=p.visit_id JOIN ga_rb_v_session_graph_time_axis axis ON axis.session_id=t.session_id
WHERE e.minimum_value IS NOT NULL AND e.maximum_value IS NOT NULL;
 SET v_step='view:v_session_display_measurement_series';
 INSERT INTO `ga_rb_v_session_display_measurement_series` SELECT m.session_id, MIN(m.bucket_at) AS bucket_at, MAX(m.interval_ended_at) AS interval_ended_at, SUM(m.sample_count) AS sample_count, MIN(m.sg_min) AS sg_min, SUM(CAST(m.sg_mean AS DECIMAL(24, 9))*m.sample_count)/SUM(m.sample_count) AS sg_mean, 
CASE WHEN choice.interval_seconds=300 THEN MAX(m.sg_median) ELSE NULL END AS sg_median, 
CASE WHEN choice.interval_seconds=300 THEN MAX(m.sg_value) ELSE SUM(CAST(m.sg_mean AS DECIMAL(24, 9))*m.sample_count)/SUM(m.sample_count) END AS sg_value, 
MAX(m.sg_max) AS sg_max, MIN(m.temperature_min_c) AS temperature_min_c, AVG(m.temperature_mean_c) AS temperature_mean_c, MAX(m.temperature_max_c) AS temperature_max_c, MIN(m.pressure_min_bar) AS pressure_min_bar, AVG(m.pressure_mean_bar) AS pressure_mean_bar, MAX(m.pressure_max_bar) AS pressure_max_bar, m.source_kind, 
CASE WHEN choice.interval_seconds=300 THEN MAX(m.source_display) ELSE CONCAT('Samlet detaljdata · ', choice.interval_seconds/60, ' minutter · SG middelverdi og min/maks') END AS source_display, choice.interval_seconds AS interval_seconds, m.segment_id
FROM ga_rb_v_session_measurement_segments m JOIN ga_rb_v_all_session s ON s.session_id=m.session_id JOIN ga_rb_v_graph_display_selection choice
WHERE m.source_kind='detail_5m'
GROUP BY m.session_id, m.source_kind, m.segment_id, choice.interval_seconds, FLOOR(TIMESTAMPDIFF(SECOND, s.pitched_at, m.bucket_at)/choice.interval_seconds)
UNION ALL SELECT m.session_id, m.bucket_at, m.interval_ended_at, m.sample_count, m.sg_min, m.sg_mean, m.sg_median, m.sg_value, m.sg_max, m.temperature_min_c, m.temperature_mean_c, m.temperature_max_c, m.pressure_min_bar, m.pressure_mean_bar, m.pressure_max_bar, m.source_kind, m.source_display, m.interval_seconds, m.segment_id FROM ga_rb_v_session_measurement_segments m WHERE m.source_kind='ha_statistics_hourly';
 SET v_step='view:v_graph_source_values';
 INSERT INTO `ga_rb_v_graph_source_values` SELECT m.session_id, 'measurement' AS source_kind, 'tilt_sg' AS metric_id, m.bucket_at AS sample_at, CAST(m.sg_value AS DECIMAL(24, 9)) AS actual_value, CAST(m.sg_min AS DECIMAL(24, 9)) AS range_min_value, CAST(m.sg_max AS DECIMAL(24, 9)) AS range_max_value, CONVERT(m.source_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display, CONVERT(CAST(m.segment_id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci AS segment_id FROM ga_rb_v_session_display_measurement_series m WHERE m.sg_value IS NOT NULL
UNION ALL
SELECT m.session_id, 'measurement' AS source_kind, 'beer_temperature_c' AS metric_id, m.bucket_at AS sample_at, CAST(m.temperature_mean_c AS DECIMAL(24, 9)) AS actual_value, CAST(m.temperature_min_c AS DECIMAL(24, 9)) AS range_min_value, CAST(m.temperature_max_c AS DECIMAL(24, 9)) AS range_max_value, CONVERT(m.source_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display, CONVERT(CAST(m.segment_id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci AS segment_id FROM ga_rb_v_session_display_measurement_series m WHERE m.temperature_mean_c IS NOT NULL
UNION ALL
SELECT m.session_id, 'measurement' AS source_kind, 'pressure_bar' AS metric_id, m.bucket_at AS sample_at, CAST(m.pressure_mean_bar AS DECIMAL(24, 9)) AS actual_value, CAST(m.pressure_min_bar AS DECIMAL(24, 9)) AS range_min_value, CAST(m.pressure_max_bar AS DECIMAL(24, 9)) AS range_max_value, CONVERT(m.source_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display, CONVERT(CAST(m.segment_id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci AS segment_id FROM ga_rb_v_session_display_measurement_series m WHERE m.pressure_mean_bar IS NOT NULL
UNION ALL
SELECT m.session_id, 'comparison' AS source_kind, 'tilt_sg' AS metric_id, m.bucket_at AS sample_at, CAST(m.sg_value AS DECIMAL(24, 9)) AS actual_value, CAST(m.sg_min AS DECIMAL(24, 9)) AS range_min_value, CAST(m.sg_max AS DECIMAL(24, 9)) AS range_max_value, CONVERT(m.source_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display, CONVERT(CAST(m.segment_id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci AS segment_id FROM ga_rb_v_graph_comparison_display m WHERE m.sg_value IS NOT NULL
UNION ALL
SELECT m.session_id, 'comparison' AS source_kind, 'beer_temperature_c' AS metric_id, m.bucket_at AS sample_at, CAST(m.temperature_mean_c AS DECIMAL(24, 9)) AS actual_value, CAST(m.temperature_min_c AS DECIMAL(24, 9)) AS range_min_value, CAST(m.temperature_max_c AS DECIMAL(24, 9)) AS range_max_value, CONVERT(m.source_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display, CONVERT(CAST(m.segment_id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci AS segment_id FROM ga_rb_v_graph_comparison_display m WHERE m.temperature_mean_c IS NOT NULL
UNION ALL
SELECT m.session_id, 'comparison' AS source_kind, 'pressure_bar' AS metric_id, m.bucket_at AS sample_at, CAST(m.pressure_mean_bar AS DECIMAL(24, 9)) AS actual_value, CAST(m.pressure_min_bar AS DECIMAL(24, 9)) AS range_min_value, CAST(m.pressure_max_bar AS DECIMAL(24, 9)) AS range_max_value, CONVERT(m.source_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display, CONVERT(CAST(m.segment_id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci AS segment_id FROM ga_rb_v_graph_comparison_display m WHERE m.pressure_mean_bar IS NOT NULL
UNION ALL
SELECT o.session_id, 'observation', 'tilt_sg', o.recorded_at, CAST(o.corrected_sg AS DECIMAL(24, 9)), NULL, NULL, CONVERT('Manuell registrering' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT('manual' USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_v_current_observation_revision o WHERE o.status='active' AND o.corrected_sg IS NOT NULL
UNION ALL
SELECT o.session_id, 'observation', 'beer_temperature_c', o.recorded_at, CAST(o.manual_temperature_c AS DECIMAL(24, 9)), NULL, NULL, CONVERT('Manuell registrering' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT('manual' USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_v_current_observation_revision o WHERE o.status='active' AND o.manual_temperature_c IS NOT NULL
UNION ALL
SELECT o.session_id, 'observation', 'pressure_bar', o.recorded_at, CAST(o.pressure_bar AS DECIMAL(24, 9)), NULL, NULL, CONVERT('Manuell registrering' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT('manual' USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_v_current_observation_revision o WHERE o.status='active' AND o.pressure_bar IS NOT NULL
UNION ALL
SELECT o.session_id, 'observation', 'cooler_setpoint_c', o.recorded_at, CAST(o.cooler_setpoint_c AS DECIMAL(24, 9)), NULL, NULL, CONVERT('Manuell registrering' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT('manual' USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_v_current_observation_revision o WHERE o.status='active' AND o.cooler_setpoint_c IS NOT NULL
UNION ALL
SELECT p.session_id, 'process_target', p.metric_id, p.started_at, p.actual_value, p.minimum_value, p.maximum_value, CONVERT(p.label USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(p.visit_id USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_v_graph_process_plan p WHERE p.started_at>=p.started_at
UNION ALL
SELECT p.session_id, 'process_target', p.metric_id, p.ended_at, p.actual_value, p.minimum_value, p.maximum_value, CONVERT(p.label USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(p.visit_id USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_v_graph_process_plan p WHERE p.ended_at>=p.started_at;
 SET v_step='view:v_graph_raw_series';
 INSERT INTO `ga_rb_v_graph_raw_series` SELECT d.session_id, d.graph_id, d.series_id, d.sort_order, CONVERT(d.label USING utf8mb4) COLLATE utf8mb4_unicode_ci AS label, v.sample_at, v.actual_value, v.range_min_value, v.range_max_value, 
 CONVERT(CONCAT(REPLACE(REPLACE(FORMAT(v.actual_value, g.display_decimals), ',', ''), '.', ','), ' ', g.unit) USING utf8mb4) COLLATE utf8mb4_unicode_ci AS actual_value_display, 
 CONVERT(CONCAT(v.basis_display, ' · ', DATE_FORMAT(CONVERT_TZ(v.sample_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i')) USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display, 
 d.standard_color AS line_color, d.standard_dasharray AS line_dasharray, d.band_model, d.band_description, d.band_opacity, d.render_mode, v.segment_id
FROM ga_rb_t_session_analysis_graph_series d JOIN ga_rb_t_session_analysis_graphs g ON g.session_id=d.session_id AND g.graph_id=d.graph_id
JOIN ga_rb_v_graph_source_values v ON v.session_id=d.session_id AND v.source_kind=d.source_kind AND v.metric_id=d.metric_id
WHERE g.enabled=1;
END//
CREATE PROCEDURE ga_fill_read_basis_part_8() BEGIN
 DECLARE v_stage LONGTEXT; DECLARE v_expected BIGINT; DECLARE v_step VARCHAR(128); DECLARE v_error TEXT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_error=MESSAGE_TEXT; SET v_error=CONCAT(v_step, ': ', LEFT(v_error, 350)); RESIGNAL SET MESSAGE_TEXT=v_error; END;
 SET v_step='view:v_graph_series';
 INSERT INTO `ga_rb_v_graph_series` SELECT session_id, graph_id, series_id, sort_order, CONVERT(label USING utf8mb4) COLLATE utf8mb4_unicode_ci AS label, sample_at, actual_value, range_min_value, range_max_value, CONVERT(actual_value_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS actual_value_display, CONVERT(basis_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display, CONVERT(line_color USING utf8mb4) COLLATE utf8mb4_unicode_ci AS line_color, CONVERT(line_dasharray USING utf8mb4) COLLATE utf8mb4_unicode_ci AS line_dasharray, CONVERT(band_model USING utf8mb4) COLLATE utf8mb4_unicode_ci AS band_model, CONVERT(band_description USING utf8mb4) COLLATE utf8mb4_unicode_ci AS band_description, band_opacity, CONVERT(render_mode USING utf8mb4) COLLATE utf8mb4_unicode_ci AS render_mode, CONVERT(segment_id USING utf8mb4) COLLATE utf8mb4_unicode_ci AS segment_id FROM ga_rb_v_dashboard_analysis_series
UNION ALL
SELECT session_id, graph_id, series_id, sort_order, CONVERT(label USING utf8mb4) COLLATE utf8mb4_unicode_ci AS label, sample_at, actual_value, range_min_value, range_max_value, CONVERT(actual_value_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS actual_value_display, CONVERT(basis_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display, CONVERT(line_color USING utf8mb4) COLLATE utf8mb4_unicode_ci AS line_color, CONVERT(line_dasharray USING utf8mb4) COLLATE utf8mb4_unicode_ci AS line_dasharray, CONVERT(band_model USING utf8mb4) COLLATE utf8mb4_unicode_ci AS band_model, CONVERT(band_description USING utf8mb4) COLLATE utf8mb4_unicode_ci AS band_description, band_opacity, CONVERT(render_mode USING utf8mb4) COLLATE utf8mb4_unicode_ci AS render_mode, CONVERT(segment_id USING utf8mb4) COLLATE utf8mb4_unicode_ci AS segment_id FROM ga_rb_v_graph_raw_series;
 SET v_step='view:v_graph_extents';
 INSERT INTO `ga_rb_v_graph_extents` SELECT g.session_id, g.graph_id, g.display_decimals, g.y_axis_include_zero, MIN(q.value_min) AS data_min, MAX(q.value_max) AS data_max
FROM ga_rb_t_session_analysis_graphs g LEFT JOIN (
 SELECT session_id, graph_id, CASE WHEN band_model='none' THEN actual_value ELSE COALESCE(range_min_value, actual_value) END AS value_min, CASE WHEN band_model='none' THEN actual_value ELSE COALESCE(range_max_value, actual_value) END AS value_max FROM ga_rb_v_graph_series
 UNION ALL SELECT session_id, graph_id, minimum_value, maximum_value FROM ga_rb_v_graph_reference_bands
 UNION ALL SELECT session_id, graph_id, COALESCE(minimum_value, maximum_value), COALESCE(maximum_value, minimum_value) FROM ga_rb_v_session_analysis_requirements
) q ON q.session_id=g.session_id AND q.graph_id=g.graph_id WHERE g.enabled=1 GROUP BY g.session_id, g.graph_id, g.display_decimals, g.y_axis_include_zero;
 SET v_step='view:v_graph_axes';
 INSERT INTO `ga_rb_v_graph_axes` SELECT z.session_id, z.graph_id, 
       CASE WHEN z.fixed_min IS NOT NULL THEN z.fixed_min WHEN z.y_axis_include_zero=1 AND z.base_min=0 THEN 0 ELSE FLOOR((z.base_min-z.tick_step*0.30)/z.tick_step)*z.tick_step END AS y_axis_min, 
       CASE WHEN z.fixed_max IS NOT NULL THEN z.fixed_max ELSE CEIL((z.base_max+z.tick_step*0.30)/z.tick_step)*z.tick_step END AS y_axis_max, 
       z.tick_step AS y_axis_tick_step
FROM (
 SELECT y.*, CASE WHEN y.normalized_step<=1 THEN y.magnitude WHEN y.normalized_step<=2 THEN 2*y.magnitude WHEN y.normalized_step<=5 THEN 5*y.magnitude ELSE 10*y.magnitude END AS tick_step
 FROM (
  SELECT x.*, POW(10, FLOOR(LOG10(x.rough_step))) AS magnitude, x.rough_step/POW(10, FLOOR(LOG10(x.rough_step))) AS normalized_step
  FROM (
   SELECT b.*, GREATEST((b.base_max-b.base_min)/5, POW(10, -b.display_decimals)) AS rough_step
   FROM (
    SELECT e.*, g.y_axis_min AS fixed_min, g.y_axis_max AS fixed_max, 
           COALESCE(g.y_axis_min, CASE WHEN e.y_axis_include_zero=1 THEN LEAST(0, COALESCE(e.data_min, 0)) ELSE COALESCE(e.data_min, 0) END) AS base_min, 
           COALESCE(g.y_axis_max, GREATEST(COALESCE(g.y_axis_min, 0), CASE WHEN e.y_axis_include_zero=1 THEN GREATEST(0, COALESCE(e.data_max, 0)) ELSE COALESCE(e.data_max, 0) END)) AS base_max
    FROM ga_rb_v_graph_extents e JOIN ga_rb_t_session_analysis_graphs g ON g.session_id=e.session_id AND g.graph_id=e.graph_id
   ) b
  ) x
 ) y
) z;
 SET v_step='view:v_graph_axis_ticks';
 INSERT INTO `ga_rb_v_graph_axis_ticks` SELECT a.session_id, a.graph_id, a.y_axis_min+d.seq*a.y_axis_tick_step AS tick_value, 
REPLACE(REPLACE(FORMAT(a.y_axis_min+d.seq*a.y_axis_tick_step, g.display_decimals) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ',') AS axis_label
FROM ga_rb_v_graph_axes a JOIN ga_rb_t_session_analysis_graphs g ON g.session_id=a.session_id AND g.graph_id=a.graph_id JOIN seq_0_to_60 d ON a.y_axis_min+d.seq*a.y_axis_tick_step<=a.y_axis_max+a.y_axis_tick_step/1000;
 SET v_step='view:v_report_graph_time_axis';
 INSERT INTO `ga_rb_v_report_graph_time_axis` SELECT s.session_id, s.pitched_at AS x_axis_started_at, s.domain_now AS x_axis_ended_at, DATE_FORMAT(CONVERT_TZ(s.pitched_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS x_axis_start_display, DATE_FORMAT(CONVERT_TZ(s.domain_now, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS x_axis_end_display FROM ga_rb_v_all_session s LEFT JOIN(SELECT session_id, MAX(bucket_at) AS last_at FROM ga_rb_v_session_measurement_series GROUP BY session_id) m ON m.session_id=s.session_id;
 SET v_step='view:v_graph_definitions';
 INSERT INTO `ga_rb_v_graph_definitions` SELECT g.session_id, g.graph_id, t.render_scope, g.sort_order, g.label, g.description, g.unit, g.display_decimals, 
 a.y_axis_min, a.y_axis_max, a.y_axis_tick_step, t.x_axis_started_at, t.x_axis_ended_at, t.x_axis_start_display, t.x_axis_end_display, 
 g.enabled, g.show_biological_bands, g.show_process_markers, g.show_criterion_markers, g.gap_policy, 
 EXISTS(SELECT 1 FROM ga_rb_t_session_analysis_graph_series d WHERE d.session_id=g.session_id AND d.graph_id=g.graph_id AND d.source_kind='measurement') AS show_in_overview, 
 p.canvas_width, p.canvas_height, p.compact_height, p.margin_left, p.margin_right, p.margin_top, p.margin_bottom, p.date_font_size, p.axis_font_size, p.marker_font_size, p.font_family, p.line_width, p.point_radius, p.time_marker_spacing
FROM ga_rb_t_session_analysis_graphs g JOIN ga_rb_v_graph_axes a ON a.session_id=g.session_id AND a.graph_id=g.graph_id JOIN (
 SELECT d.*, 'dashboard' AS render_scope FROM ga_rb_v_session_graph_time_axis d
 UNION ALL
 SELECT r.session_id, r.x_axis_started_at, IF((SELECT a.is_historical FROM ga_rb_v_all_session a WHERE a.session_id=r.session_id)=1, r.x_axis_ended_at, GREATEST(r.x_axis_ended_at, COALESCE(ref.last_at, r.x_axis_ended_at))) AS x_axis_ended_at, 
 CONCAT('Dag 0.00 · ', DATE_FORMAT(CONVERT_TZ(r.x_axis_started_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i')) AS x_axis_start_display, 
 CONCAT('Dag ', ROUND(TIMESTAMPDIFF(SECOND, r.x_axis_started_at, IF((SELECT a.is_historical FROM ga_rb_v_all_session a WHERE a.session_id=r.session_id)=1, r.x_axis_ended_at, GREATEST(r.x_axis_ended_at, COALESCE(ref.last_at, r.x_axis_ended_at))))/86400, 2), ' · ', DATE_FORMAT(CONVERT_TZ(IF((SELECT a.is_historical FROM ga_rb_v_all_session a WHERE a.session_id=r.session_id)=1, r.x_axis_ended_at, GREATEST(r.x_axis_ended_at, COALESCE(ref.last_at, r.x_axis_ended_at))), '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i')) AS x_axis_end_display, 
 'report' FROM ga_rb_v_report_graph_time_axis r LEFT JOIN(SELECT session_id, MAX(bucket_at) AS last_at FROM ga_rb_v_graph_reference_measurement_series GROUP BY session_id) ref ON ref.session_id=r.session_id
) t ON t.session_id=g.session_id CROSS JOIN ga_rb_t_graph_render_policy p WHERE g.enabled=1;
 SET v_step='view:v_graph_latest';
 INSERT INTO `ga_rb_v_graph_latest` SELECT v.session_id, v.graph_id, v.series_id, v.sort_order, v.sample_at, v.actual_value, 
CONCAT(v.label, ' · ', v.actual_value_display, ' · ', v.basis_display) AS latest_value_display
FROM (SELECT x.*, ROW_NUMBER() OVER(PARTITION BY session_id, graph_id, series_id ORDER BY sample_at DESC) AS latest_rank FROM ga_rb_v_graph_series x) v WHERE v.latest_rank=1;
 SET v_step='view:v_graph_time_markers';
 INSERT INTO `ga_rb_v_graph_time_markers` SELECT g.session_id, g.graph_id, g.render_scope, TIMESTAMPADD(DAY, d.seq, a.pitched_at) AS marker_at, d.seq AS relative_day, 
CASE WHEN c.source_kind<>'none' THEN CONCAT('Dag ', d.seq, ' · ', DATE_FORMAT(CONVERT_TZ(TIMESTAMPADD(DAY, d.seq, a.pitched_at), '+00:00', 'Europe/Oslo'), '%d.%m')) ELSE DATE_FORMAT(CONVERT_TZ(TIMESTAMPADD(DAY, d.seq, a.pitched_at), '+00:00', 'Europe/Oslo'), '%d.%m') END AS axis_label
FROM ga_rb_v_graph_definitions g JOIN ga_rb_v_all_session a ON a.session_id=g.session_id JOIN ga_rb_v_graph_display_selection c JOIN seq_0_to_10000 d ON TIMESTAMPADD(DAY, d.seq, a.pitched_at) BETWEEN g.x_axis_started_at AND g.x_axis_ended_at
WHERE MOD(d.seq, GREATEST(1, CEIL(TIMESTAMPDIFF(SECOND, g.x_axis_started_at, g.x_axis_ended_at)/86400/GREATEST(1, FLOOR((g.canvas_width-g.margin_left-g.margin_right)/g.time_marker_spacing)))))=0;
 SET v_step='view:v_historical_phase_options';
 INSERT INTO `ga_rb_v_historical_phase_options` SELECT a.session_id, CONVERT('biological' USING utf8mb4) COLLATE utf8mb4_unicode_ci AS kind, p.phase_id AS owner_id, p.phase_order AS sort_order, CONCAT(CONVERT(p.phase_id USING utf8mb4), ' · ', p.name) AS label
FROM ga_rb_v_active_session a JOIN ga_rb_t_session_biological_phases p ON p.session_id=a.session_id WHERE a.is_historical=1 AND NOT EXISTS(SELECT 1 FROM ga_rb_t_biological_visits v WHERE v.session_id=p.session_id AND v.phase_id=p.phase_id)
UNION ALL
SELECT a.session_id, CONVERT('process' USING utf8mb4) COLLATE utf8mb4_unicode_ci, p.process_id, p.process_order, CONCAT(CONVERT(p.process_id USING utf8mb4), ' · ', p.name)
FROM ga_rb_v_active_session a JOIN ga_rb_t_session_process_steps p ON p.session_id=a.session_id WHERE a.is_historical=1 AND p.enabled=1 AND NOT EXISTS(SELECT 1 FROM ga_rb_t_process_visits v WHERE v.session_id=p.session_id AND v.process_id=p.process_id);
 SET v_step='view:v_phase_duration_presentation';
 INSERT INTO `ga_rb_v_phase_duration_presentation` SELECT q.session_id, q.kind, q.owner_id, q.duration_seconds, CONCAT(FLOOR((q.duration_seconds)/86400), IF(FLOOR((q.duration_seconds)/86400)=1, ' dag, ', ' dager, '), LPAD(FLOOR(MOD((q.duration_seconds), 86400)/3600), 2, '0'), ':', LPAD(FLOOR(MOD((q.duration_seconds), 3600)/60), 2, '0')) AS duration_display FROM (
 SELECT session_id, CONVERT('biological' USING utf8mb4) COLLATE utf8mb4_unicode_ci AS kind, phase_id AS owner_id, SUM(duration_seconds) AS duration_seconds FROM ga_rb_v_biological_visit_timing GROUP BY session_id, phase_id
 UNION ALL SELECT session_id, CONVERT('process' USING utf8mb4) COLLATE utf8mb4_unicode_ci, process_id, SUM(duration_seconds) FROM ga_rb_v_process_visit_timing GROUP BY session_id, process_id
) q;
 SET v_step='view:v_effective_process_criterion_requirement';
 INSERT INTO `ga_rb_v_effective_process_criterion_requirement` SELECT
    p.session_id, p.process_id, 
    p.criterion_id, 
    GROUP_CONCAT(
        CONCAT(
            mp.label,  ': ', 
            CASE WHEN p.is_unset=1 THEN 'Ikke angitt' ELSE CASE p.data_type
              WHEN 'real' THEN REPLACE(REPLACE(FORMAT(p.real_value, COALESCE(m.display_decimals, 2)) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ',')
              WHEN 'integer' THEN CAST(p.integer_value AS CHAR)
              WHEN 'boolean' THEN CASE WHEN p.boolean_value=1 THEN 'Ja' ELSE 'Nei' END
              ELSE p.text_value
            END END, 
            CASE WHEN p.is_unset=1 THEN '' ELSE CASE mp.unit_source
              WHEN 'metric' THEN CASE WHEN COALESCE(m.unit, '')<>'' THEN CONCAT(' ', m.unit) ELSE '' END
              WHEN 'fixed' THEN CASE WHEN COALESCE(mp.fixed_unit, '')<>'' THEN CONCAT(' ', mp.fixed_unit) ELSE '' END
              ELSE ''
            END END
        )
        ORDER BY mp.sort_order SEPARATOR ' · '
    ) AS requirement_display
FROM ga_rb_v_effective_process_criterion_parameters p
JOIN ga_rb_t_session_process_criteria c
  ON c.session_id=p.session_id AND c.process_id=p.process_id AND c.criterion_id=p.criterion_id
JOIN ga_rb_t_criterion_model_parameters mp
  ON mp.model_id=p.model_id AND mp.parameter_id=p.parameter_id AND mp.data_type=p.data_type
JOIN ga_rb_t_metrics m ON m.metric_id=c.metric_id
GROUP BY p.session_id, p.process_id, p.criterion_id;
 SET v_step='view:v_process_evaluation_criterion_requirement';
 INSERT INTO `ga_rb_v_process_evaluation_criterion_requirement` SELECT
    p.evaluation_id, 
    p.criterion_id, 
    GROUP_CONCAT(
        CONCAT(
            mp.label,  ': ', 
            CASE WHEN p.is_unset=1 THEN 'Ikke angitt' ELSE CASE p.data_type
              WHEN 'real' THEN REPLACE(REPLACE(FORMAT(p.real_value, COALESCE(m.display_decimals, 2)) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ',')
              WHEN 'integer' THEN CAST(p.integer_value AS CHAR)
              WHEN 'boolean' THEN CASE WHEN p.boolean_value=1 THEN 'Ja' ELSE 'Nei' END
              ELSE p.text_value
            END END, 
            CASE WHEN p.is_unset=1 THEN '' ELSE CASE mp.unit_source
              WHEN 'metric' THEN CASE WHEN COALESCE(m.unit, '')<>'' THEN CONCAT(' ', m.unit) ELSE '' END
              WHEN 'fixed' THEN CASE WHEN COALESCE(mp.fixed_unit, '')<>'' THEN CONCAT(' ', mp.fixed_unit) ELSE '' END
              ELSE ''
            END END
        )
        ORDER BY mp.sort_order SEPARATOR ' · '
    ) AS requirement_display
FROM ga_rb_t_process_evaluation_criterion_parameter_values p
JOIN ga_rb_t_process_evaluation_criteria c
  ON c.evaluation_id=p.evaluation_id AND c.criterion_id=p.criterion_id
JOIN ga_rb_t_criterion_model_parameters mp
  ON mp.model_id=p.model_id AND mp.parameter_id=p.parameter_id AND mp.data_type=p.data_type
JOIN ga_rb_t_metrics m ON m.metric_id=c.metric_id
GROUP BY p.evaluation_id, p.criterion_id;
 SET v_step='view:v_template_process_criterion_requirement';
 INSERT INTO `ga_rb_v_template_process_criterion_requirement` SELECT
    p.session_id, p.process_id, 
    p.criterion_id, 
    GROUP_CONCAT(
        CONCAT(
            mp.label,  ': ', 
            CASE WHEN 0=1 THEN 'Ikke angitt' ELSE CASE p.data_type
              WHEN 'real' THEN REPLACE(REPLACE(FORMAT(p.real_value, COALESCE(m.display_decimals, 2)) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ',')
              WHEN 'integer' THEN CAST(p.integer_value AS CHAR)
              WHEN 'boolean' THEN CASE WHEN p.boolean_value=1 THEN 'Ja' ELSE 'Nei' END
              ELSE p.text_value
            END END, 
            CASE WHEN 0=1 THEN '' ELSE CASE mp.unit_source
              WHEN 'metric' THEN CASE WHEN COALESCE(m.unit, '')<>'' THEN CONCAT(' ', m.unit) ELSE '' END
              WHEN 'fixed' THEN CASE WHEN COALESCE(mp.fixed_unit, '')<>'' THEN CONCAT(' ', mp.fixed_unit) ELSE '' END
              ELSE ''
            END END
        )
        ORDER BY mp.sort_order SEPARATOR ' · '
    ) AS requirement_display
FROM ga_rb_t_session_process_criterion_parameter_values p
JOIN ga_rb_t_session_process_criteria c
  ON c.session_id=p.session_id AND c.process_id=p.process_id AND c.criterion_id=p.criterion_id
JOIN ga_rb_t_criterion_model_parameters mp
  ON mp.model_id=p.model_id AND mp.parameter_id=p.parameter_id AND mp.data_type=p.data_type
JOIN ga_rb_t_metrics m ON m.metric_id=c.metric_id
GROUP BY p.session_id, p.process_id, p.criterion_id;
 SET v_step='view:v_process_evaluation_criterion_read_model';
 INSERT INTO `ga_rb_v_process_evaluation_criterion_read_model` SELECT
    c.*, 
    e.evaluated_at, 
    e.created_at AS evaluation_created_at, 
    CASE WHEN sc.exception_allowed=1 AND (c.met IS NULL OR c.met<>1) AND c.evaluation_status<>'invalid_configuration' AND (c.criterion_revision_id <=> current_rev.criterion_revision_id) THEN 1 ELSE 0 END AS exception_register_allowed, 
    sc.label, 
    m.label AS metric_label, 
    m.unit AS metric_unit, 
    r.requirement_display, 
    original.requirement_display AS template_requirement_display, 
    effective.requirement_display AS effective_requirement_display, 
    (c.criterion_revision_id <=> current_rev.criterion_revision_id) AS criterion_basis_current, 
    CASE c.evaluation_status
      WHEN 'met' THEN 'Oppfylt'
      WHEN 'not_met' THEN 'Ikke oppfylt'
      WHEN 'missing_basis' THEN 'Mangler grunnlag'
      WHEN 'missing_coverage' THEN 'Mangler dekning'
      WHEN 'stale' THEN 'Foreldet grunnlag'
      WHEN 'invalid_configuration' THEN 'Konfigurasjonsfeil'
      WHEN 'not_evaluated' THEN 'Ikke vurdert'
      ELSE c.evaluation_status
    END COLLATE utf8mb4_unicode_ci AS status_display, 
    CASE
      WHEN c.actual_text IS NOT NULL THEN c.actual_text
      WHEN c.actual_value IS NOT NULL THEN CONCAT(
        REPLACE(REPLACE(FORMAT(c.actual_value, m.display_decimals) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), 
        CASE WHEN m.unit<>'' THEN CONCAT(' ', m.unit) ELSE '' END
      )
      ELSE NULL
    END COLLATE utf8mb4_unicode_ci AS actual_display, 
    CASE
      WHEN c.model_id='stability_window' AND c.requested_window_seconds IS NOT NULL THEN CONCAT(
        REPLACE(REPLACE(FORMAT(c.requested_window_seconds/3600, 1) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), ' t · dekning ', 
        REPLACE(REPLACE(FORMAT(COALESCE(c.coverage_seconds, 0)/3600, 1) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), ' t · ', 
        COALESCE(c.sample_count, 0), ' pkt'
      )
      WHEN c.requested_window_seconds IS NOT NULL THEN CONCAT(
        CASE WHEN c.requested_window_seconds>=3600
             THEN CONCAT(REPLACE(REPLACE(FORMAT(c.requested_window_seconds/3600, 1) COLLATE utf8mb4_unicode_ci, ',', ''), '.', ','), ' t')
             ELSE CONCAT(ROUND(c.requested_window_seconds/60), ' min') END, 
        ' · ', COALESCE(c.sample_count, 0), ' pkt'
      )
      WHEN c.sample_count IS NOT NULL AND c.sample_count>1 THEN CONCAT(
        c.sample_count, ' prøver', 
        CASE WHEN c.latest_sample_at IS NOT NULL THEN CONCAT(' · t.o.m. ', DATE_FORMAT(CONVERT_TZ(c.latest_sample_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i')) ELSE '' END
      )
      WHEN c.latest_sample_at IS NOT NULL THEN CONCAT('Siste verdi · ', DATE_FORMAT(CONVERT_TZ(c.latest_sample_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i'))
      WHEN c.measured_at IS NOT NULL THEN CONCAT('Siste verdi · ', DATE_FORMAT(CONVERT_TZ(c.measured_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i'))
      ELSE 'Ikke tidsserie'
    END COLLATE utf8mb4_unicode_ci AS data_window_display
FROM ga_rb_t_process_evaluation_criteria c
JOIN ga_rb_t_process_evaluations e ON e.evaluation_id=c.evaluation_id
JOIN ga_rb_t_metrics m ON m.metric_id=c.metric_id
LEFT JOIN ga_rb_t_session_process_criteria sc
  ON sc.session_id=c.session_id AND sc.process_id=c.candidate_process_id AND sc.criterion_id=c.criterion_id
LEFT JOIN ga_rb_v_process_evaluation_criterion_requirement r
  ON r.evaluation_id=c.evaluation_id AND r.criterion_id=c.criterion_id
LEFT JOIN ga_rb_v_template_process_criterion_requirement original ON original.session_id=c.session_id AND original.process_id=c.candidate_process_id AND original.criterion_id=c.criterion_id
LEFT JOIN ga_rb_v_effective_process_criterion_requirement effective ON effective.session_id=c.session_id AND effective.process_id=c.candidate_process_id AND effective.criterion_id=c.criterion_id
LEFT JOIN ga_rb_v_current_process_criterion_revision current_rev ON current_rev.session_id=c.session_id AND current_rev.process_id=c.candidate_process_id AND current_rev.criterion_id=c.criterion_id;
 SET v_step='view:v_process_transition_evidence';
 INSERT INTO `ga_rb_v_process_transition_evidence` SELECT
    pt.transition_id, 
    pt.session_id, 
    pt.transitioned_at, 
    pt.from_process_id, 
    pt.to_process_id, 
    pt.action, 
    pt.evaluation_id, 
    pt.recommendation_id, 
    pt.operation_id, 
    pt.recommended_temperature_c AS transition_recommended_temperature_c, 
    pt.recommended_pressure_bar AS transition_recommended_pressure_bar, 
    pt.note AS transition_note, 
    e.current_process_id, 
    e.candidate_process_id, 
    e.active_visit_id, 
    e.observation_id, 
    e.observation_revision_id, 
    e.evaluated_at, 
    e.readiness, 
    e.data_quality, 
    e.summary, 
    e.recommended_temperature_c, 
    e.recommended_pressure_bar, 
    e.engine_version, 
    e.created_at AS evaluation_created_at, 
    ps.process_order AS candidate_process_order, 
    ps.name AS candidate_process_name
FROM ga_rb_t_process_transitions pt
JOIN ga_rb_t_process_evaluations e ON e.evaluation_id=pt.evaluation_id
JOIN ga_rb_t_session_process_steps ps
  ON ps.session_id=pt.session_id AND ps.process_id=pt.to_process_id;
 SET v_step='view:v_recommendations_effective';
 INSERT INTO `ga_rb_v_recommendations_effective` SELECT
    r.*, 
    CASE
      WHEN lr.outcome IS NOT NULL THEN lr.outcome
      WHEN EXISTS (
          SELECT 1 FROM ga_rb_t_recommendations newer
          WHERE newer.session_id=r.session_id
            AND newer.rule_id=r.rule_id
            AND (newer.created_at>r.created_at OR (newer.created_at=r.created_at AND newer.recommendation_id>r.recommendation_id))
      ) THEN 'superseded'
      ELSE 'pending'
    END AS effective_status, 
    lr.resolution_id AS latest_resolution_id, 
    lr.created_at AS resolved_at
FROM ga_rb_t_recommendations r
LEFT JOIN ga_rb_t_recommendation_resolutions lr ON lr.recommendation_id=r.recommendation_id;
 SET v_step='view:v_session_biological_exception_read_model';
 INSERT INTO `ga_rb_v_session_biological_exception_read_model` SELECT x.*, c.label, e.candidate_phase_id AS owner_id, 
       DATE_FORMAT(CONVERT_TZ(x.created_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS created_display, 
       CASE x.action WHEN 'register' THEN 'Registrert' WHEN 'withdraw' THEN 'Trukket tilbake' END COLLATE utf8mb4_unicode_ci AS action_display, 
       CASE x.exception_type WHEN 'akseptert_avvik' THEN 'Akseptert avvik' WHEN 'ikke_relevant' THEN 'Ikke relevant' WHEN 'ugyldig_vurderingsgrunnlag' THEN 'Ugyldig vurderingsgrunnlag' ELSE '–' END COLLATE utf8mb4_unicode_ci AS exception_type_display, 
       COALESCE(x.note, '–') AS note_display
FROM ga_rb_t_biological_criterion_exceptions x JOIN ga_rb_t_biological_evaluations e ON e.evaluation_id=x.evaluation_id
JOIN ga_rb_t_session_biological_criteria c ON c.session_id=x.session_id AND c.phase_id=x.phase_id AND c.criterion_id=x.criterion_id;
 SET v_step='view:v_session_report_actions';
 INSERT INTO `ga_rb_v_session_report_actions` SELECT a.session_id, a.completed_at, DATE_FORMAT(CONVERT_TZ(a.completed_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS completed_display, a.label, 
       CASE WHEN a.accepted=1 THEN 'Ja' ELSE 'Nei' END COLLATE utf8mb4_unicode_ci AS accepted_display, 
       COALESCE(a.outcome, '–') AS outcome_display, 
       COALESCE(a.field_error, a.technical_error, a.detail_text, '–') AS detail_display
FROM ga_rb_t_operator_actions a JOIN ga_rb_v_all_session s ON s.session_id=a.session_id;
 SET v_step='view:v_session_report_biological_criteria';
 INSERT INTO `ga_rb_v_session_report_biological_criteria` SELECT e.session_id, e.evaluated_at, e.candidate_phase_id AS owner_id, DATE_FORMAT(CONVERT_TZ(e.evaluated_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS evaluated_display, 
       c.criterion_order, c.label, c.role_id, c.status_display, c.requirement_display, c.actual_display, c.data_window_display, c.explanation
FROM ga_rb_t_biological_evaluations e
JOIN ga_rb_v_all_session a ON a.session_id=e.session_id
JOIN ga_rb_v_biological_evaluation_criterion_read_model c ON c.evaluation_id=e.evaluation_id;
 SET v_step='view:v_session_report_biology';
 INSERT INTO `ga_rb_v_session_report_biology` SELECT b.session_id, b.phase_id, p.name, 
       UNIX_TIMESTAMP(r.started_at)*1000 AS started_ms, 
       UNIX_TIMESTAMP(r.ended_at)*1000 AS ended_ms, 
       DATE_FORMAT(CONVERT_TZ(r.started_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS started_display, 
       COALESCE(DATE_FORMAT(CONVERT_TZ(r.ended_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i'), 'Pågår') AS ended_display, 
       COALESCE(r.timing_source, '–') AS timing_source_display, 
       r.confidence, r.duration_display
FROM ga_rb_t_biological_visits b
JOIN ga_rb_v_biological_visit_timing r ON r.visit_id=b.visit_id
JOIN ga_rb_t_session_biological_phases p ON p.session_id=b.session_id AND p.phase_id=b.phase_id
JOIN ga_rb_v_all_session a ON a.session_id=b.session_id;
 SET v_step='view:v_session_report_criterion_corrections';
 INSERT INTO `ga_rb_v_session_report_criterion_corrections` SELECT x.session_id, x.created_at, x.created_display, x.area_display, x.owner_id, x.criterion_label, x.action_display, x.parameters_display, x.note_display
FROM (
  SELECT r.session_id, r.created_at, DATE_FORMAT(CONVERT_TZ(r.created_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS created_display, 'Biologi' AS area_display, CONVERT(r.phase_id USING utf8mb4) COLLATE utf8mb4_unicode_ci AS owner_id, c.label AS criterion_label, 
         CASE r.action WHEN 'override' THEN 'Korrigert' WHEN 'reset' THEN 'Tilbakestilt' ELSE CONVERT(r.action USING utf8mb4) COLLATE utf8mb4_unicode_ci END COLLATE utf8mb4_unicode_ci AS action_display, 
         COALESCE(GROUP_CONCAT(CONCAT(CONVERT(p.parameter_id USING utf8mb4), '=', CASE WHEN p.is_unset=1 THEN 'Ikke angitt' ELSE CASE p.data_type WHEN 'real' THEN CONVERT(CAST(p.real_value AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci WHEN 'integer' THEN CONVERT(CAST(p.integer_value AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci WHEN 'boolean' THEN CASE p.boolean_value WHEN 1 THEN 'true' ELSE 'false' END WHEN 'text' THEN p.text_value END END) ORDER BY p.parameter_id SEPARATOR '; '), '–') AS parameters_display, 
         COALESCE(r.note, '–') AS note_display
  FROM ga_rb_t_session_biological_criterion_revisions r
  JOIN ga_rb_v_all_session a ON a.session_id=r.session_id
  JOIN ga_rb_t_session_biological_criteria c ON c.session_id=r.session_id AND c.phase_id=r.phase_id AND c.criterion_id=r.criterion_id
  LEFT JOIN ga_rb_t_session_biological_criterion_revision_parameter_values p ON p.criterion_revision_id=r.criterion_revision_id
  GROUP BY r.criterion_revision_id, r.session_id, r.created_at, r.phase_id, c.label, r.action, r.note
  UNION ALL
  SELECT r.session_id, r.created_at, DATE_FORMAT(CONVERT_TZ(r.created_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i'), 'Prosesstrinn', CONVERT(r.process_id USING utf8mb4) COLLATE utf8mb4_unicode_ci, c.label, 
         CASE r.action WHEN 'override' THEN 'Korrigert' WHEN 'reset' THEN 'Tilbakestilt' ELSE CONVERT(r.action USING utf8mb4) COLLATE utf8mb4_unicode_ci END, 
         COALESCE(GROUP_CONCAT(CONCAT(CONVERT(p.parameter_id USING utf8mb4), '=', CASE WHEN p.is_unset=1 THEN 'Ikke angitt' ELSE CASE p.data_type WHEN 'real' THEN CONVERT(CAST(p.real_value AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci WHEN 'integer' THEN CONVERT(CAST(p.integer_value AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci WHEN 'boolean' THEN CASE p.boolean_value WHEN 1 THEN 'true' ELSE 'false' END WHEN 'text' THEN p.text_value END END) ORDER BY p.parameter_id SEPARATOR '; '), '–'), 
         COALESCE(r.note, '–')
  FROM ga_rb_t_session_process_criterion_revisions r
  JOIN ga_rb_v_all_session a ON a.session_id=r.session_id
  JOIN ga_rb_t_session_process_criteria c ON c.session_id=r.session_id AND c.process_id=r.process_id AND c.criterion_id=r.criterion_id
  LEFT JOIN ga_rb_t_session_process_criterion_revision_parameter_values p ON p.criterion_revision_id=r.criterion_revision_id
  GROUP BY r.criterion_revision_id, r.session_id, r.created_at, r.process_id, c.label, r.action, r.note
) x;
 SET v_step='view:v_session_report_gaps';
 INSERT INTO `ga_rb_v_session_report_gaps` SELECT g.session_id, DATE_FORMAT(CONVERT_TZ(g.gap_started_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS started_display, 
       COALESCE(DATE_FORMAT(CONVERT_TZ(g.gap_ended_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i'), 'ÅPENT') AS ended_display, 
       CASE WHEN g.gap_ended_at IS NULL THEN 'Pågår' ELSE CONCAT(CAST(g.duration_seconds AS CHAR), ' s') END COLLATE utf8mb4_unicode_ci AS duration_display, 
       COALESCE(g.source, '–') AS source_display, g.gap_started_at, g.gap_ended_at
FROM ga_rb_v_measurement_data_gaps g JOIN ga_rb_v_all_session a ON a.session_id=g.session_id;
 SET v_step='view:v_session_report_notes';
 INSERT INTO `ga_rb_v_session_report_notes` SELECT n.session_id, n.noted_at, DATE_FORMAT(CONVERT_TZ(n.noted_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS noted_display, n.note_text
FROM ga_rb_t_session_notes n JOIN ga_rb_v_all_session a ON a.session_id=n.session_id;
 SET v_step='view:v_session_report_observations';
 INSERT INTO `ga_rb_v_session_report_observations` SELECT o.session_id, UNIX_TIMESTAMP(o.recorded_at)*1000 AS at_ms, DATE_FORMAT(CONVERT_TZ(o.recorded_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS at_display, 
       o.measured_sg, o.corrected_sg, o.manual_temperature_c, 
       COALESCE(mm.label, '–') AS measurement_method_display, 
       COALESCE(CAST(o.measured_sg AS CHAR), '–') AS measured_sg_display, 
       COALESCE(CAST(o.corrected_sg AS CHAR), '–') AS corrected_sg_display, 
       COALESCE(CAST(o.manual_temperature_c AS CHAR), '–') AS manual_temperature_display, 
       COALESCE(CAST(o.pressure_bar AS CHAR), '–') AS pressure_display, 
       COALESCE(CAST(o.cooler_setpoint_c AS CHAR), '–') AS cooler_setpoint_display, 
       COALESCE(o.airlock_activity, '–') AS airlock_activity_display, 
       COALESCE(CAST(o.acetaldehyde_level AS CHAR), '–') AS acetaldehyde_display, 
       COALESCE(CAST(o.diacetyl_level AS CHAR), '–') AS diacetyl_display, 
       COALESCE(CAST(o.wort_like_level AS CHAR), '–') AS wort_like_display, 
       COALESCE(CAST(o.sulfur_so2_level AS CHAR), '–') AS sulfur_so2_display, 
       COALESCE(CAST(o.sulfur_h2s_level AS CHAR), '–') AS sulfur_h2s_display, 
       COALESCE(CAST(o.clarity_level AS CHAR), '–') AS clarity_display, 
       COALESCE(CAST(o.settling_yeast_level AS CHAR), '–') AS settling_yeast_display, 
       COALESCE(CAST(o.settling_minutes AS CHAR), '–') AS settling_minutes_display, 
       COALESCE(CAST(o.estimated_abv_percent AS CHAR), '–') AS estimated_abv_display, 
       COALESCE(CAST(o.estimated_finished_abv_percent AS CHAR), '–') AS estimated_finished_abv_display, 
       COALESCE(o.user_conclusion, '–') AS user_conclusion_display, 
       COALESCE(o.note, '–') AS note_display, 
       CASE WHEN COALESCE(o.corrected_sg, o.measured_sg) IS NULL THEN NULL ELSE CONCAT('Manuell SG ', CAST(COALESCE(o.corrected_sg, o.measured_sg) AS CHAR), ' · ', DATE_FORMAT(CONVERT_TZ(o.recorded_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i')) END AS sg_marker_label, 
       CASE WHEN o.manual_temperature_c IS NULL THEN NULL ELSE CONCAT('Manuell temperatur ', CAST(o.manual_temperature_c AS CHAR), ' °C · ', DATE_FORMAT(CONVERT_TZ(o.recorded_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i')) END AS temperature_marker_label
FROM ga_rb_v_current_observation_revision o
JOIN ga_rb_v_all_session a ON a.session_id=o.session_id
LEFT JOIN ga_rb_t_measurement_methods mm ON mm.measurement_method_id=o.measurement_method_id
WHERE o.status='active';
 SET v_step='view:v_session_report_process';
 INSERT INTO `ga_rb_v_session_report_process` SELECT v.session_id, v.process_id, p.name, p.historical_replay_auto_transition_allowed, 
       UNIX_TIMESTAMP(r.started_at)*1000 AS started_ms, 
       UNIX_TIMESTAMP(r.ended_at)*1000 AS ended_ms, 
       DATE_FORMAT(CONVERT_TZ(r.started_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS started_display, 
       COALESCE(DATE_FORMAT(CONVERT_TZ(r.ended_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i'), 'Pågår') AS ended_display, 
       COALESCE(r.timing_source, '–') AS timing_source_display, 
       CASE WHEN p.historical_replay_auto_transition_allowed=1 THEN 'Tillatt' ELSE 'Manuell bekreftelse' END COLLATE utf8mb4_unicode_ci AS historical_replay_policy_display, r.duration_display
FROM ga_rb_t_process_visits v
JOIN ga_rb_v_process_visit_timing r ON r.visit_id=v.visit_id
JOIN ga_rb_t_session_process_steps p ON p.session_id=v.session_id AND p.process_id=v.process_id
JOIN ga_rb_v_all_session a ON a.session_id=v.session_id;
 SET v_step='view:v_session_report_process_criteria';
 INSERT INTO `ga_rb_v_session_report_process_criteria` SELECT e.session_id, e.evaluated_at, e.candidate_process_id AS owner_id, DATE_FORMAT(CONVERT_TZ(e.evaluated_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS evaluated_display, 
       c.criterion_order, c.label, c.role_id, c.status_display, c.requirement_display, c.actual_display, c.data_window_display, c.explanation
FROM ga_rb_t_process_evaluations e
JOIN ga_rb_v_all_session a ON a.session_id=e.session_id
JOIN ga_rb_v_process_evaluation_criterion_read_model c ON c.evaluation_id=e.evaluation_id;
 SET v_step='view:v_session_report_process_exceptions';
 INSERT INTO `ga_rb_v_session_report_process_exceptions` SELECT x.session_id, x.created_at, DATE_FORMAT(CONVERT_TZ(x.created_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS created_display, e.candidate_process_id AS owner_id, c.label AS criterion_label, 
       CASE x.action WHEN 'register' THEN 'Registrert' WHEN 'withdraw' THEN 'Trukket tilbake' ELSE x.action END COLLATE utf8mb4_unicode_ci AS action_display, 
       CASE x.exception_type WHEN 'akseptert_avvik' THEN 'Akseptert avvik' WHEN 'ikke_relevant' THEN 'Ikke relevant' WHEN 'ugyldig_vurderingsgrunnlag' THEN 'Ugyldig vurderingsgrunnlag' ELSE COALESCE(x.exception_type, '–') END COLLATE utf8mb4_unicode_ci AS exception_type_display, 
       COALESCE(x.note, '–') AS note_display
FROM ga_rb_t_process_criterion_exceptions x
JOIN ga_rb_v_all_session a ON a.session_id=x.session_id
JOIN ga_rb_t_process_evaluations e ON e.evaluation_id=x.evaluation_id
JOIN ga_rb_v_process_evaluation_criterion_read_model c ON c.evaluation_id=x.evaluation_id AND c.criterion_id=x.criterion_id;
 SET v_step='view:v_session_report_process_transitions';
 INSERT INTO `ga_rb_v_session_report_process_transitions` SELECT t.session_id, t.transitioned_at, DATE_FORMAT(CONVERT_TZ(t.transitioned_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS transitioned_display, 
       CONCAT(COALESCE(CONVERT(t.from_process_id USING utf8mb4), '–'), ' → ', CONVERT(t.to_process_id USING utf8mb4)) AS transition_display, 
       CASE t.action WHEN 'next' THEN 'Neste' WHEN 'back' THEN 'Tilbake' WHEN 'backfill' THEN 'Historisk replay' ELSE t.action END COLLATE utf8mb4_unicode_ci AS action_display, 
       COALESCE(t.note, '–') AS note_display
FROM ga_rb_t_process_transitions t JOIN ga_rb_v_all_session a ON a.session_id=t.session_id;
END//
CREATE PROCEDURE ga_fill_read_basis_part_9() BEGIN
 DECLARE v_stage LONGTEXT; DECLARE v_expected BIGINT; DECLARE v_step VARCHAR(128); DECLARE v_error TEXT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_error=MESSAGE_TEXT; SET v_error=CONCAT(v_step, ': ', LEFT(v_error, 350)); RESIGNAL SET MESSAGE_TEXT=v_error; END;
 SET v_step='view:v_session_report_session';
 INSERT INTO `ga_rb_v_session_report_session` SELECT
    s.session_id, s.batch_name, s.og, s.volume_l, 
    CASE WHEN s.is_historical=1 THEN 'Historisk gjæringsrapport' WHEN s.lifecycle='active' THEN 'Aktiv gjæringsrapport' ELSE 'Avsluttet gjæringsrapport' END AS report_kind_display, 
    CASE WHEN s.is_historical=1 THEN 'Avsluttet forløp · etterregistrering' WHEN s.lifecycle='active' THEN 'Gjæringen pågår' ELSE 'Gjæringen er avsluttet' END AS lifecycle_display, 
    DATE_FORMAT(CONVERT_TZ(s.pitched_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS pitched_display, 
    UNIX_TIMESTAMP(s.pitched_at)*1000 AS pitched_ms, 
    ft.expected_attenuation_min_percent, ft.expected_attenuation_max_percent, ft.expected_fg_min, ft.expected_fg_max, 
    CONCAT(COALESCE(CAST(ft.expected_fg_min AS CHAR), '–'), '–', COALESCE(CAST(ft.expected_fg_max AS CHAR), '–')) AS expected_fg_display, 
    CONCAT(COALESCE(CAST(ft.expected_attenuation_min_percent AS CHAR), '–'), '–', COALESCE(CAST(ft.expected_attenuation_max_percent AS CHAR), '–'), ' %') AS expected_attenuation_display, 
    CONCAT(COALESCE(CONVERT(s.current_biological_phase_id USING utf8mb4), ''), CASE WHEN s.current_biological_phase_name IS NULL OR s.current_biological_phase_name='' THEN '' ELSE CONCAT(' · ', s.current_biological_phase_name) END) AS biology_display, 
    CONCAT(COALESCE(CONVERT(s.current_process_id USING utf8mb4), ''), CASE WHEN s.current_process_name IS NULL OR s.current_process_name='' THEN '' ELSE CONCAT(' · ', s.current_process_name) END) AS process_display, 
    tv.name AS template_name, tv.version_label, 
    COALESCE((SELECT CAST(o.estimated_abv_percent AS CHAR) FROM ga_rb_v_current_observation_revision o WHERE o.session_id=s.session_id AND o.status='active' ORDER BY o.recorded_at DESC, o.revision_no DESC LIMIT 1), '–') AS latest_abv_display, 
    COALESCE((SELECT CAST(o.estimated_finished_abv_percent AS CHAR) FROM ga_rb_v_current_observation_revision o WHERE o.session_id=s.session_id AND o.status='active' ORDER BY o.recorded_at DESC, o.revision_no DESC LIMIT 1), '–') AS estimated_finished_abv_display
FROM ga_rb_v_all_session_summary s
LEFT JOIN ga_rb_v_current_fermentation_target ft ON ft.session_id=s.session_id
LEFT JOIN ga_rb_t_session_template_snapshots sts ON sts.session_id=s.session_id
LEFT JOIN ga_rb_t_template_versions tv ON tv.version_id=sts.template_version_id;
 SET v_step='view:v_session_report_timeline';
 INSERT INTO `ga_rb_v_session_report_timeline` SELECT t.session_id, t.happened_at, DATE_FORMAT(CONVERT_TZ(t.happened_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS happened_display, t.type_display, t.event_display, t.note_display
FROM ( SELECT s.session_id, s.pitched_at AS happened_at, CONVERT(('Pitch') USING utf8mb4) COLLATE utf8mb4_unicode_ci AS type_display, CONVERT(('Gjær tilsatt / gjæring startet') USING utf8mb4) COLLATE utf8mb4_unicode_ci AS event_display, CONVERT(('–') USING utf8mb4) COLLATE utf8mb4_unicode_ci AS note_display FROM ga_rb_v_all_session_summary s
 
 UNION ALL
 SELECT b.session_id, r.started_at, CONVERT(('Biologisk fase') USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT((CONCAT(CONVERT(b.phase_id USING utf8mb4) COLLATE utf8mb4_unicode_ci, ' · ', p.name)) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(('–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_biological_visits b JOIN ga_rb_v_biological_visit_timing r ON r.visit_id=b.visit_id JOIN ga_rb_t_session_biological_phases p ON p.session_id=b.session_id AND p.phase_id=b.phase_id JOIN ga_rb_v_all_session a ON a.session_id=b.session_id
 
 UNION ALL
 SELECT v.session_id, r.started_at, CONVERT(('Prosesstrinn') USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT((CONCAT(CONVERT(v.process_id USING utf8mb4) COLLATE utf8mb4_unicode_ci, ' · ', p.name)) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(('–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_process_visits v JOIN ga_rb_v_process_visit_timing r ON r.visit_id=v.visit_id JOIN ga_rb_t_session_process_steps p ON p.session_id=v.session_id AND p.process_id=v.process_id JOIN ga_rb_v_all_session a ON a.session_id=v.session_id
 
 UNION ALL
 SELECT g.session_id, g.gap_started_at, CONVERT(('Datagap') USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT((CONCAT('Datagap · ', g.source)) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT((CASE WHEN g.gap_ended_at IS NULL THEN 'ÅPENT' ELSE CONCAT('Slutt ', DATE_FORMAT(CONVERT_TZ(g.gap_ended_at, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i')) END) USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_v_measurement_data_gaps g JOIN ga_rb_v_all_session a ON a.session_id=g.session_id
 
 UNION ALL
 SELECT o.session_id, CASE WHEN o.revision_no=1 THEN o.recorded_at ELSE o.created_at END, CONVERT(('Målesett') USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT((CONCAT('Målesett · revisjon ', o.revision_no, ' · ', CONVERT(o.status USING utf8mb4), ' · SG ', CONVERT(CAST(o.corrected_sg AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci)) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT((COALESCE(o.note, '–')) USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_observation_round_revisions o JOIN ga_rb_v_all_session a ON a.session_id=o.session_id
 
 UNION ALL
 SELECT n.session_id, n.noted_at, CONVERT(('Notat') USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(('Operatørnotat') USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT((n.note_text) USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_session_notes n JOIN ga_rb_v_all_session a ON a.session_id=n.session_id

 UNION ALL
 SELECT e.session_id, e.occurred_at, CONVERT('Livsløp' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CASE e.lifecycle WHEN 'active' THEN 'Gjæring startet' WHEN 'completed' THEN 'Gjæring avsluttet' ELSE e.lifecycle END USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(COALESCE(e.note, '–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_session_lifecycle_events e  
 UNION ALL
 SELECT e.session_id, e.transitioned_at, CONVERT('Prosessovergang' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CONCAT(CONVERT(e.from_process_id USING utf8mb4), ' → ', CONVERT(e.to_process_id USING utf8mb4)) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(COALESCE(e.note, '–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_process_transitions e  
 UNION ALL
 SELECT e.session_id, e.transitioned_at, CONVERT('Biologisk overgang' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CONCAT(CONVERT(e.from_phase_id USING utf8mb4), ' → ', CONVERT(e.to_phase_id USING utf8mb4)) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(COALESCE(e.reason, '–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_biological_transitions e  
 UNION ALL
 SELECT e.session_id, e.created_at, CONVERT('Tidsregistrering' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CONCAT(CONVERT(e.timing_field USING utf8mb4), ' · revisjon ', e.revision_no) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(COALESCE(e.reason, '–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_session_timing_revisions e  
 UNION ALL
 SELECT e.session_id, e.created_at, CONVERT('Kriteriekorreksjon' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CONCAT(CONVERT(e.phase_id USING utf8mb4), ' · ', CONVERT(e.criterion_id USING utf8mb4), ' · ', CONVERT(e.action USING utf8mb4)) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(COALESCE(e.note, '–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_session_biological_criterion_revisions e  
 UNION ALL
 SELECT e.session_id, e.created_at, CONVERT('Kriteriekorreksjon' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CONCAT(CONVERT(e.process_id USING utf8mb4), ' · ', CONVERT(e.criterion_id USING utf8mb4), ' · ', CONVERT(e.action USING utf8mb4)) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(COALESCE(e.note, '–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_session_process_criterion_revisions e  
 UNION ALL
 SELECT e.session_id, e.created_at, CONVERT('Kriteriefravik' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CONCAT(CONVERT(e.criterion_id USING utf8mb4), ' · ', CONVERT(e.action USING utf8mb4)) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(COALESCE(e.note, '–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_process_criterion_exceptions e  
 UNION ALL
 SELECT e.session_id, e.created_at, CONVERT('Kriteriefravik' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CONCAT(CONVERT(e.criterion_id USING utf8mb4), ' · ', CONVERT(e.action USING utf8mb4)) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(COALESCE(e.note, '–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_biological_criterion_exceptions e  
 UNION ALL
 SELECT e.session_id, e.completed_at, CONVERT('Operatørhandling' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CONCAT(CONVERT(e.label USING utf8mb4), ' · ', COALESCE(CONVERT(e.outcome USING utf8mb4), '')) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(COALESCE(COALESCE(e.field_error, e.technical_error, e.detail_text), '–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_operator_actions e  WHERE e.session_id IS NOT NULL
 UNION ALL
 SELECT e.session_id, e.occurred_at, CONVERT('Driftsmelding' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CONCAT(CONVERT(e.code USING utf8mb4), ' · ', CONVERT(e.message USING utf8mb4)) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(COALESCE(e.source_component, '–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_technical_events e  WHERE e.session_id IS NOT NULL
 UNION ALL SELECT p.session_id, e.created_at, CONVERT('Prosessens tidskorrigering' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CONCAT(CONVERT(p.process_id USING utf8mb4), ' · revisjon ', e.revision_no) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(COALESCE(e.revision_reason, '–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_process_visit_revisions e JOIN ga_rb_t_process_visits p ON p.visit_id=e.visit_id WHERE e.revision_no>1
 UNION ALL SELECT p.session_id, e.created_at, CONVERT('Biologisk tidsregistrering' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CONCAT(CONVERT(p.phase_id USING utf8mb4), ' · revisjon ', e.revision_no) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(COALESCE(e.revision_reason, '–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_biological_visit_revisions e JOIN ga_rb_t_biological_visits p ON p.visit_id=e.visit_id WHERE e.revision_no>1
 UNION ALL SELECT e.session_id, e.released_at, CONVERT('Livsløp' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT('Gjort klar for ny gjæring' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(COALESCE(NULL, '–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_session_release_events e
 UNION ALL SELECT e.session_id, e.requested_at, CONVERT('Arkivering' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CONCAT('Arkiveringsforsøk ', e.attempt_no) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(COALESCE(NULL, '–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_session_export_attempts e
 UNION ALL SELECT e.session_id, e.completed_at, CONVERT('Eksport' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CONCAT(CONVERT(e.export_kind USING utf8mb4), ' · ', CONVERT(e.status USING utf8mb4), ' · forsøk ', e.attempt_no) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(COALESCE(e.error_message, '–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_session_exports e
 UNION ALL
 SELECT c.session_id, c.effective_from, CONVERT('Målekilde' USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT(CONCAT('Sensorbindinger · ', c.profile_name, IF(c.note IS NULL, '', CONCAT(' · ', c.note))) USING utf8mb4) COLLATE utf8mb4_unicode_ci, CONVERT('source_configuration' USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM ga_rb_t_session_measurement_source_configurations c
) t;
 SET v_step='view:v_session_runtime_presentation';
 INSERT INTO `ga_rb_v_session_runtime_presentation` SELECT s.session_id, yp.name AS yeast, s.current_process_order AS active_process_order, s.current_process_name AS active_process_name, 
(SELECT COUNT(*)>0 FROM ga_rb_v_active_technical_issues) AS attention, pg.next_process_name AS recommended_process_name, 
GREATEST(0, TIMESTAMPDIFF(MICROSECOND, s.pitched_at, s.domain_now)/3600000000) AS elapsed_hours, 
GREATEST(0, TIMESTAMPDIFF(MICROSECOND, s.current_biological_started_at, s.domain_now)/3600000000) AS active_phase_elapsed_hours, 
s.completed_at, CONCAT(FLOOR((GREATEST(0, TIMESTAMPDIFF(SECOND, s.current_biological_started_at, s.domain_now)))/86400), IF(FLOOR((GREATEST(0, TIMESTAMPDIFF(SECOND, s.current_biological_started_at, s.domain_now)))/86400)=1, ' dag, ', ' dager, '), LPAD(FLOOR(MOD((GREATEST(0, TIMESTAMPDIFF(SECOND, s.current_biological_started_at, s.domain_now))), 86400)/3600), 2, '0'), ':', LPAD(FLOOR(MOD((GREATEST(0, TIMESTAMPDIFF(SECOND, s.current_biological_started_at, s.domain_now))), 3600)/60), 2, '0')) AS active_phase_duration_display
FROM ga_rb_v_current_session_summary s JOIN ga_rb_t_sessions se ON se.session_id=s.session_id JOIN ga_rb_t_yeast_profiles yp ON yp.yeast_profile_id=se.yeast_profile_id LEFT JOIN ga_rb_v_current_process_guidance pg ON pg.session_id=s.session_id;
END//
CREATE PROCEDURE ga_fill_read_basis(IN p_session VARCHAR(128)) BEGIN
 DECLARE v_stage LONGTEXT; DECLARE v_expected BIGINT; DECLARE v_old_limit BIGINT; DECLARE v_limit BIGINT; DECLARE v_step VARCHAR(128); DECLARE v_error TEXT;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_error=MESSAGE_TEXT; SET v_error=CONCAT(COALESCE(v_step, 'read basis'), ': ', LEFT(v_error, 400)); SET SESSION group_concat_max_len=v_old_limit; RESIGNAL SET MESSAGE_TEXT=v_error; END;
 SET v_old_limit=@@session.group_concat_max_len;
 SELECT json_staging_bytes INTO v_limit FROM read_model_execution_policy WHERE policy_id=1;
 IF v_limit IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB-kontrakt: read-policy mangler'; END IF;
 SET SESSION group_concat_max_len=v_limit;
 INSERT INTO ga_rb_scope SELECT session_id FROM sessions WHERE session_id=p_session;
 INSERT IGNORE INTO ga_rb_scope SELECT s.session_id FROM sessions s JOIN v_graph_display_selection d ON d.source_kind='session' AND d.reference_session_id=s.session_id;
 CALL ga_fill_read_basis_part_1();
 CALL ga_fill_read_basis_part_2();
 CALL ga_fill_read_basis_part_3();
 CALL ga_fill_read_basis_part_4();
 CALL ga_fill_read_basis_part_5();
 CALL ga_fill_read_basis_part_6();
 CALL ga_fill_read_basis_part_7();
 CALL ga_fill_read_basis_part_8();
 CALL ga_fill_read_basis_part_9();
 SET SESSION group_concat_max_len=v_old_limit;
END//
CREATE PROCEDURE ga_read_overview() BEGIN
 DECLARE v_owner BOOLEAN; DECLARE v_session VARCHAR(128); DECLARE v_source_key CHAR(64); DECLARE v_generated_at DATETIME(3); DECLARE v_operation CHAR(36);
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN IF v_owner THEN ROLLBACK; CALL ga_drop_read_basis(); END IF; RESIGNAL; END;
 SET v_owner=(@@in_transaction=0);
 IF v_owner THEN CALL ga_init_read_basis(); START TRANSACTION WITH CONSISTENT SNAPSHOT,  READ ONLY; END IF;
 SELECT session_id INTO v_session FROM v_active_session;
 CALL ga_overview_source_key(v_source_key); SET v_generated_at=UTC_TIMESTAMP(3), v_operation=UUID();
 CALL ga_fill_read_basis(v_session);
SELECT 'clock' AS _set, UTC_TIMESTAMP(3) AS database_now;
SELECT 'summary' AS _set, s.*, se.yeast_profile_id, yp.name AS yeast_name, se.is_demo, se.pitched_at AS original_pitched_at, (SELECT t.revision_no FROM ga_rb_v_current_session_timing t WHERE t.session_id=s.session_id AND t.timing_field='pitched_at' LIMIT 1) AS pitch_timing_revision_no, (SELECT t.source FROM ga_rb_v_current_session_timing t WHERE t.session_id=s.session_id AND t.timing_field='pitched_at' LIMIT 1) AS pitch_timing_source, IF((SELECT t.revision_no FROM ga_rb_v_current_session_timing t WHERE t.session_id=s.session_id AND t.timing_field='pitched_at' LIMIT 1)>1, s.pitched_at, NULL) AS manual_pitched_at, ft.expected_attenuation_min_percent, ft.expected_attenuation_max_percent, ft.expected_fg_min, ft.expected_fg_max, CONCAT(REPLACE(REPLACE(FORMAT(ft.expected_fg_min, 3), ',', ''), '.', ','), '–', REPLACE(REPLACE(FORMAT(ft.expected_fg_max, 3), ',', ''), '.', ',')) AS expected_fg_display, std.expected_fg_min AS frozen_expected_fg_min, std.expected_fg_max AS frozen_expected_fg_max, sts.template_version_id, tv.name AS template_name, tv.version_label, (SELECT COUNT(*) FROM ga_rb_v_active_technical_issues) AS active_issue_count, UTC_TIMESTAMP(3) AS database_now FROM ga_rb_v_active_session_summary s JOIN ga_rb_t_sessions se ON se.session_id=s.session_id LEFT JOIN ga_rb_t_yeast_profiles yp ON yp.yeast_profile_id=se.yeast_profile_id LEFT JOIN ga_rb_v_current_fermentation_target ft ON ft.session_id=s.session_id LEFT JOIN ga_rb_t_session_template_defaults std ON std.session_id=s.session_id LEFT JOIN ga_rb_t_session_template_snapshots sts ON sts.session_id=s.session_id LEFT JOIN ga_rb_t_template_versions tv ON tv.version_id=sts.template_version_id LIMIT 1;
SELECT 'series' AS _set, m.bucket_at AS at, m.sg_value AS sg, REPLACE(REPLACE(FORMAT(m.sg_value, 4), ',', ''), '.', ',') AS sg_display, m.sg_min, m.sg_max, m.temperature_min_c, m.temperature_mean_c AS temperature_c, m.temperature_max_c, m.pressure_min_bar, m.pressure_mean_bar AS pressure_bar, m.pressure_max_bar, m.sample_count, m.segment_id, m.source_kind, m.source_display, m.interval_seconds, 
(SELECT te.target_value FROM ga_rb_t_process_visits pv JOIN ga_rb_v_current_process_visit_revision pr ON pr.visit_id=pv.visit_id JOIN ga_rb_t_session_process_targets t ON t.session_id=pv.session_id AND t.process_id=pv.process_id JOIN ga_rb_t_session_process_target_exact te ON te.session_id=t.session_id AND te.process_id=t.process_id AND te.target_id=t.target_id WHERE pv.session_id=m.session_id AND t.metric_id='beer_temperature_c' AND pr.started_at<=m.bucket_at AND (pr.ended_at IS NULL OR pr.ended_at>=m.bucket_at) ORDER BY pr.started_at, pv.visit_id LIMIT 1) AS temperature_plan_c, 
(SELECT te.target_value FROM ga_rb_t_process_visits pv JOIN ga_rb_v_current_process_visit_revision pr ON pr.visit_id=pv.visit_id JOIN ga_rb_t_session_process_targets t ON t.session_id=pv.session_id AND t.process_id=pv.process_id JOIN ga_rb_t_session_process_target_exact te ON te.session_id=t.session_id AND te.process_id=t.process_id AND te.target_id=t.target_id WHERE pv.session_id=m.session_id AND t.metric_id='pressure_bar' AND pr.started_at<=m.bucket_at AND (pr.ended_at IS NULL OR pr.ended_at>=m.bucket_at) ORDER BY pr.started_at, pv.visit_id LIMIT 1) AS pressure_plan_bar FROM ga_rb_v_session_display_measurement_series m JOIN ga_rb_v_active_session a ON a.session_id=m.session_id JOIN ga_rb_v_session_graph_time_axis axis ON axis.session_id=m.session_id WHERE m.bucket_at BETWEEN axis.x_axis_started_at AND axis.x_axis_ended_at ORDER BY m.bucket_at;
SELECT 'overview_axes' AS _set, a.* FROM ga_rb_v_graph_definitions a JOIN ga_rb_v_active_session s ON s.session_id=a.session_id WHERE a.show_in_overview=1 AND a.render_scope='dashboard' ORDER BY a.sort_order;
SELECT 'measurement_history' AS _set, r.observation_id, r.observation_revision_id, r.revision_no, r.status, r.recorded_at, r.measurement_method_id AS measurement_method, r.measured_sg, r.sample_temperature_c, r.calibration_temperature_c, r.corrected_sg, r.manual_temperature_c, r.pressure_bar, r.cooler_setpoint_c, r.cooler_calibration_offset_c, r.airlock_activity, r.acetaldehyde_level, r.diacetyl_level, r.wort_like_level, r.sulfur_so2_level, r.sulfur_h2s_level, r.clarity_level, r.settling_yeast_level, r.settling_minutes, r.user_conclusion, r.note, (SELECT r0.recorded_at FROM ga_rb_t_observation_round_revisions r0 WHERE r0.observation_id=r.observation_id ORDER BY r0.revision_no ASC LIMIT 1) AS original_recorded_at, IF(r.revision_no>1, r.recorded_at, NULL) AS manual_recorded_at FROM ga_rb_v_current_observation_revision r JOIN ga_rb_v_active_session a ON a.session_id=r.session_id ORDER BY r.recorded_at;
SELECT 'notes' AS _set, n.note_id, n.noted_at, n.note_text, n.operation_id FROM ga_rb_t_session_notes n JOIN ga_rb_v_active_session a ON a.session_id=n.session_id ORDER BY n.noted_at;
SELECT 'observations' AS _set, r.recorded_at, r.corrected_sg, r.measured_sg, r.manual_temperature_c, r.pressure_bar, r.cooler_setpoint_c, r.airlock_activity, r.acetaldehyde_level, r.diacetyl_level, r.wort_like_level, r.sulfur_so2_level, r.sulfur_h2s_level, r.clarity_level, r.settling_yeast_level, r.settling_minutes, r.user_conclusion, r.note FROM ga_rb_v_current_observation_revision r JOIN ga_rb_v_active_session a ON a.session_id=r.session_id WHERE r.status='active' ORDER BY r.recorded_at;
SELECT 'process' AS _set, pv.visit_id, pv.process_id, ps.process_order, ps.name, ps.anchor_type, ps.anchor_biological_phase_id, ps.anchor_offset_hours, pvr.visit_revision_id, pvr.revision_no, pvr.started_at, pvr.ended_at, pvr.timing_source, pvr.revision_reason, pvr.duration_display, pvr.duration_seconds, pvr.started_display, pvr.ended_display, (SELECT r0.started_at FROM ga_rb_t_process_visit_revisions r0 WHERE r0.visit_id=pv.visit_id ORDER BY r0.revision_no ASC LIMIT 1) AS original_started_at, IF(pvr.revision_no>1, pvr.started_at, NULL) AS manual_started_at, (SELECT e.target_value FROM ga_rb_t_session_process_targets t JOIN ga_rb_t_session_process_target_exact e ON e.session_id=t.session_id AND e.process_id=t.process_id AND e.target_id=t.target_id WHERE t.session_id=pv.session_id AND t.process_id=pv.process_id AND t.metric_id='beer_temperature_c' LIMIT 1) AS target_temperature_c, (SELECT e.target_value FROM ga_rb_t_session_process_targets t JOIN ga_rb_t_session_process_target_exact e ON e.session_id=t.session_id AND e.process_id=t.process_id AND e.target_id=t.target_id WHERE t.session_id=pv.session_id AND t.process_id=pv.process_id AND t.metric_id='pressure_bar' LIMIT 1) AS target_pressure_bar FROM ga_rb_t_process_visits pv JOIN ga_rb_v_process_visit_timing pvr ON pvr.visit_id=pv.visit_id JOIN ga_rb_t_session_process_steps ps ON ps.session_id=pv.session_id AND ps.process_id=pv.process_id JOIN ga_rb_v_active_session a ON a.session_id=pv.session_id ORDER BY pvr.started_at;
SELECT 'biology' AS _set, bv.visit_id, bv.phase_id, bp.phase_order, bp.name, bp.description, bvr.visit_revision_id, bvr.revision_no, bvr.started_at, bvr.ended_at, bvr.timing_source, bvr.confidence, bvr.revision_reason, bvr.duration_display, bvr.duration_seconds, bvr.started_display, bvr.ended_display, (SELECT r0.started_at FROM ga_rb_t_biological_visit_revisions r0 WHERE r0.visit_id=bv.visit_id ORDER BY r0.revision_no ASC LIMIT 1) AS original_started_at, IF(bvr.revision_no>1, bvr.started_at, NULL) AS manual_started_at FROM ga_rb_t_biological_visits bv JOIN ga_rb_v_biological_visit_timing bvr ON bvr.visit_id=bv.visit_id JOIN ga_rb_t_session_biological_phases bp ON bp.session_id=bv.session_id AND bp.phase_id=bv.phase_id JOIN ga_rb_v_active_session a ON a.session_id=bv.session_id ORDER BY bvr.started_at;
SELECT 'bio_phases' AS _set, bp.phase_id, bp.phase_order, bp.name, bp.description FROM ga_rb_t_session_biological_phases bp JOIN ga_rb_v_active_session a ON a.session_id=bp.session_id ORDER BY bp.phase_order;
SELECT 'bio_criteria' AS _set, c.phase_id, p.phase_order, p.name AS phase_name, c.criterion_id, c.criterion_order, c.enabled, c.metric_id, c.model_id, c.role_id, c.label, c.exception_allowed FROM ga_rb_t_session_biological_criteria c JOIN ga_rb_t_session_biological_phases p ON p.session_id=c.session_id AND p.phase_id=c.phase_id JOIN ga_rb_v_active_session a ON a.session_id=c.session_id WHERE c.enabled=1 ORDER BY p.phase_order, c.criterion_order;
SELECT 'bio_params' AS _set, v.phase_id, v.criterion_id, v.model_id, v.parameter_id, v.data_type, v.real_value, v.integer_value, v.boolean_value, v.text_value FROM ga_rb_t_session_biological_criterion_parameter_values v JOIN ga_rb_v_active_session a ON a.session_id=v.session_id ORDER BY v.phase_id, v.criterion_id, v.parameter_id;

SELECT 'bio_correctable' AS _set, c.phase_id, c.criterion_id, c.model_id, c.parameter_id FROM ga_rb_t_session_biological_correctable_parameters c JOIN ga_rb_v_active_session a ON a.session_id=c.session_id ORDER BY c.phase_id, c.criterion_id, c.parameter_id;
SELECT 'bio_revisions' AS _set, r.owner_id AS phase_id, r.criterion_id, r.model_id, r.criterion_revision_id, r.revision_no, r.action, r.note, r.operation_id, r.created_at, r.evaluation_id, r.review_state, r.review_message FROM ga_rb_v_criterion_correction_receipts r JOIN ga_rb_v_active_session a ON a.session_id=r.session_id WHERE r.scope='biological' ORDER BY r.owner_id, r.criterion_id;
SELECT 'bio_revision_params' AS _set, r.phase_id, r.criterion_id, r.criterion_revision_id, p.model_id, p.parameter_id, p.data_type, p.real_value, p.integer_value, p.boolean_value, p.text_value, p.is_unset FROM ga_rb_v_current_biological_criterion_revision r JOIN ga_rb_t_session_biological_criterion_revision_parameter_values p ON p.criterion_revision_id=r.criterion_revision_id JOIN ga_rb_v_active_session a ON a.session_id=r.session_id ORDER BY r.phase_id, r.criterion_id, p.parameter_id;

SELECT 'measurement_feedback' AS _set, e.event_id, e.occurred_at, e.code, e.message, e.correlation_id FROM ga_rb_t_technical_events e JOIN ga_rb_v_active_session a ON a.session_id=e.session_id WHERE e.code IN ('MEASUREMENT_SAVED', 'MEASUREMENT_REJECTED', 'MEASUREMENT_SAVE_FAILED') ORDER BY e.occurred_at DESC, e.created_at DESC LIMIT 1;
SELECT 'bio_evals' AS _set, 'transition' AS evidence_kind, t.transition_id, t.evaluation_id, t.current_phase_id, t.candidate_phase_id, t.active_visit_id, t.evaluated_at, t.outcome, t.confidence, t.data_quality, t.summary, t.candidate_phase_order, t.candidate_phase_name FROM ga_rb_v_biological_transition_evidence t JOIN ga_rb_v_active_session a ON a.session_id=t.session_id
UNION ALL
SELECT 'bio_evals' AS _set, 'current' AS evidence_kind, NULL AS transition_id, e.evaluation_id, e.current_phase_id, e.candidate_phase_id, e.active_visit_id, e.evaluated_at, e.outcome, e.confidence, e.data_quality, e.summary, e.candidate_phase_order, e.candidate_phase_name FROM ga_rb_v_current_biological_candidate_evaluation e JOIN ga_rb_v_active_session a ON a.session_id=e.session_id
ORDER BY candidate_phase_order, evaluated_at;
SELECT 'bio_eval_criteria' AS _set, c.*, IF(c.evaluation_id=current_eval.evaluation_id, c.effective_requirement_display, c.requirement_display) AS required_display, IF(c.evaluation_id=current_eval.evaluation_id AND c.criterion_basis_current=0, 'not_evaluated', c.evaluation_status) AS display_evaluation_status, IF(c.evaluation_id=current_eval.evaluation_id AND c.criterion_basis_current=0, 'Venter på ny vurdering', c.status_display) AS display_status, IF(c.evaluation_id=current_eval.evaluation_id AND c.criterion_basis_current=0, 'Kriteriet er endret. Venter på vurdering med gjeldende krav.', c.explanation) AS display_explanation, IF(c.exception_register_allowed=1, JSON_ARRAY('register_exception'), JSON_ARRAY()) AS allowed_actions FROM ga_rb_v_biological_evaluation_criterion_read_model c LEFT JOIN ga_rb_v_current_biological_candidate_evaluation current_eval ON current_eval.session_id=c.session_id JOIN ga_rb_v_active_session a ON a.session_id=c.session_id WHERE c.evaluation_id IN (SELECT t.evaluation_id FROM ga_rb_v_biological_transition_evidence t WHERE t.session_id=a.session_id UNION SELECT e.evaluation_id FROM ga_rb_v_current_biological_candidate_evaluation e WHERE e.session_id=a.session_id) ORDER BY c.evaluation_id, c.criterion_order;
SELECT 'current_metrics' AS _set, m.* FROM ga_rb_v_current_metric_value m JOIN ga_rb_v_active_session a ON a.session_id=m.session_id WHERE m.metric_id IN ('apparent_attenuation_percent', 'sg_rate_points_per_day') ORDER BY m.metric_id;
SELECT 'next_process' AS _set, n.process_id, n.process_order, n.name, n.anchor_type, n.anchor_biological_phase_id, n.anchor_offset_hours FROM ga_rb_t_session_process_steps n JOIN ga_rb_v_active_session_summary s ON s.session_id=n.session_id WHERE n.enabled=1 AND n.process_order>s.current_process_order ORDER BY n.process_order LIMIT 1;
SELECT 'process_steps' AS _set, p.process_id, p.process_order, p.slot_no, p.name, p.description, p.enabled, p.anchor_type, p.anchor_biological_phase_id, p.anchor_offset_hours FROM ga_rb_t_session_process_steps p JOIN ga_rb_v_active_session a ON a.session_id=p.session_id ORDER BY p.process_order;
SELECT 'process_criteria' AS _set, c.process_id, c.criterion_id, c.criterion_order, c.enabled, c.metric_id, c.model_id, c.role_id, c.label, c.exception_allowed FROM ga_rb_t_session_process_criteria c JOIN ga_rb_v_active_session a ON a.session_id=c.session_id WHERE c.enabled=1 ORDER BY c.process_id, c.criterion_order;
SELECT 'process_params' AS _set, p.process_id, p.criterion_id, p.model_id, p.parameter_id, p.data_type, p.real_value, p.integer_value, p.boolean_value, p.text_value FROM ga_rb_t_session_process_criterion_parameter_values p JOIN ga_rb_v_active_session a ON a.session_id=p.session_id ORDER BY p.process_id, p.criterion_id, p.parameter_id;
SELECT 'process_correctable' AS _set, c.process_id, c.criterion_id, c.model_id, c.parameter_id FROM ga_rb_t_session_process_correctable_parameters c JOIN ga_rb_v_active_session a ON a.session_id=c.session_id ORDER BY c.process_id, c.criterion_id, c.parameter_id;
SELECT 'process_revisions' AS _set, r.owner_id AS process_id, r.criterion_id, r.model_id, r.criterion_revision_id, r.revision_no, r.action, r.note, r.operation_id, r.created_at, r.evaluation_id, r.review_state, r.review_message FROM ga_rb_v_criterion_correction_receipts r JOIN ga_rb_v_active_session a ON a.session_id=r.session_id WHERE r.scope='process' ORDER BY r.owner_id, r.criterion_id;
SELECT 'process_revision_params' AS _set, r.process_id, r.criterion_id, r.criterion_revision_id, p.model_id, p.parameter_id, p.data_type, p.real_value, p.integer_value, p.boolean_value, p.text_value, p.is_unset FROM ga_rb_v_current_process_criterion_revision r JOIN ga_rb_t_session_process_criterion_revision_parameter_values p ON p.criterion_revision_id=r.criterion_revision_id JOIN ga_rb_v_active_session a ON a.session_id=r.session_id ORDER BY r.process_id, r.criterion_id, p.parameter_id;
SELECT 'process_targets' AS _set, t.process_id, t.target_id, t.target_order, t.metric_id, t.model_id, t.label, t.purpose, e.target_value, r.minimum_value, r.maximum_value FROM ga_rb_t_session_process_targets t JOIN ga_rb_v_active_session a ON a.session_id=t.session_id LEFT JOIN ga_rb_t_session_process_target_exact e ON e.session_id=t.session_id AND e.process_id=t.process_id AND e.target_id=t.target_id LEFT JOIN ga_rb_t_session_process_target_range r ON r.session_id=t.session_id AND r.process_id=t.process_id AND r.target_id=t.target_id ORDER BY t.process_id, t.target_order;
SELECT 'process_actions' AS _set, a.process_id, a.action_id, a.action_order, a.action_type_id, a.label, st.target_id, op.operator_operation_id FROM ga_rb_t_session_process_actions a JOIN ga_rb_v_active_session v ON v.session_id=a.session_id LEFT JOIN ga_rb_t_session_process_action_set_target st ON st.session_id=a.session_id AND st.process_id=a.process_id AND st.action_id=a.action_id LEFT JOIN ga_rb_t_session_process_action_operator op ON op.session_id=a.session_id AND op.process_id=a.process_id AND op.action_id=a.action_id ORDER BY a.process_id, a.action_order;
SELECT 'process_eval' AS _set, e.*, p.name AS current_process_name FROM ga_rb_v_current_process_candidate_evaluation e JOIN ga_rb_v_active_session a ON a.session_id=e.session_id LEFT JOIN ga_rb_t_session_process_steps p ON p.session_id=e.session_id AND p.process_id=e.current_process_id LIMIT 1;
SELECT 'process_eval_criteria' AS _set, c.*, c.effective_requirement_display AS required_display, IF(c.criterion_basis_current=0, 'not_evaluated', c.evaluation_status) AS display_evaluation_status, IF(c.criterion_basis_current=0, 'Venter på ny vurdering', c.status_display) AS display_status, IF(c.criterion_basis_current=0, 'Kriteriet er endret. Venter på vurdering med gjeldende krav.', c.explanation) AS display_explanation, sc.exception_allowed, IF(c.exception_register_allowed=1, JSON_ARRAY('register_exception'), JSON_ARRAY()) AS allowed_actions FROM ga_rb_v_process_evaluation_criterion_read_model c JOIN ga_rb_v_current_process_candidate_evaluation e ON e.evaluation_id=c.evaluation_id JOIN ga_rb_v_active_session a ON a.session_id=e.session_id LEFT JOIN ga_rb_t_session_process_criteria sc ON sc.session_id=c.session_id AND sc.process_id=c.candidate_process_id AND sc.criterion_id=c.criterion_id ORDER BY c.criterion_order;
SELECT 'process_exceptions' AS _set, x.* FROM ga_rb_t_process_criterion_exceptions x JOIN ga_rb_v_current_process_candidate_evaluation e ON e.evaluation_id=x.evaluation_id JOIN ga_rb_v_active_session a ON a.session_id=x.session_id WHERE NOT EXISTS(SELECT 1 FROM ga_rb_t_process_criterion_exceptions n WHERE n.evaluation_id=x.evaluation_id AND n.criterion_id=x.criterion_id AND n.revision_no>x.revision_no);
SELECT 'process_transition_evals' AS _set, t.* FROM ga_rb_v_process_transition_evidence t JOIN ga_rb_v_active_session a ON a.session_id=t.session_id ORDER BY t.candidate_process_order, t.transitioned_at;
SELECT 'process_transition_eval_criteria' AS _set, c.*, c.requirement_display AS required_display, c.evaluation_status AS display_evaluation_status, c.status_display AS display_status, c.explanation AS display_explanation FROM ga_rb_v_process_evaluation_criterion_read_model c JOIN ga_rb_v_process_transition_evidence t ON t.evaluation_id=c.evaluation_id JOIN ga_rb_v_active_session a ON a.session_id=t.session_id ORDER BY t.candidate_process_order, c.criterion_order;
SELECT 'recommendation' AS _set, r.* FROM ga_rb_v_recommendations_effective r JOIN ga_rb_v_active_session a ON a.session_id=r.session_id WHERE r.effective_status='pending' ORDER BY r.created_at DESC LIMIT 1;
SELECT 'report_summary' AS _set, r.* FROM ga_rb_v_active_session_report_summary r LIMIT 1;

SELECT 'measurement_gaps' AS _set, g.gap_started_at, g.gap_ended_at, g.duration_seconds, g.source FROM ga_rb_v_measurement_data_gaps g JOIN ga_rb_v_active_session a ON a.session_id=g.session_id ORDER BY g.gap_started_at;
SELECT 'analysis_graphs' AS _set, g.* FROM ga_rb_v_graph_definitions g JOIN ga_rb_v_active_session a ON a.session_id=g.session_id WHERE g.render_scope='dashboard' ORDER BY g.sort_order;
SELECT 'analysis_series' AS _set, s.* FROM ga_rb_v_graph_series s JOIN ga_rb_v_active_session live ON live.session_id=s.session_id ORDER BY s.graph_id, s.series_id, s.sample_at;
SELECT 'analysis_latest' AS _set, s.* FROM ga_rb_v_graph_latest s JOIN ga_rb_v_active_session a ON a.session_id=s.session_id ORDER BY s.graph_id, s.series_id, s.sort_order;
SELECT 'analysis_time_markers' AS _set, m.* FROM ga_rb_v_graph_time_markers m JOIN ga_rb_v_active_session a ON a.session_id=m.session_id WHERE m.render_scope='dashboard' ORDER BY m.graph_id, m.marker_at;
SELECT 'analysis_requirements' AS _set, r.* FROM ga_rb_v_active_analysis_requirements r ORDER BY r.graph_id, r.owner_type, r.owner_id, r.criterion_id;
SELECT 'analysis_bio_markers' AS _set, m.* FROM ga_rb_v_active_analysis_biological_markers m JOIN ga_rb_v_active_session a ON a.session_id=m.session_id ORDER BY m.graph_id, m.started_at;
SELECT 'analysis_process_markers' AS _set, m.* FROM ga_rb_v_active_analysis_process_markers m JOIN ga_rb_v_active_session a ON a.session_id=m.session_id ORDER BY m.graph_id, m.started_at;
SELECT 'bio_exceptions' AS _set, x.* FROM ga_rb_t_biological_criterion_exceptions x JOIN ga_rb_v_current_biological_candidate_evaluation e ON e.evaluation_id=x.evaluation_id WHERE NOT EXISTS(SELECT 1 FROM ga_rb_t_biological_criterion_exceptions n WHERE n.evaluation_id=x.evaluation_id AND n.criterion_id=x.criterion_id AND n.revision_no>x.revision_no);
SELECT 'analysis_reference_bands' AS _set, r.* FROM ga_rb_v_graph_reference_bands r JOIN ga_rb_v_active_session a ON a.session_id=r.session_id;
SELECT 'analysis_axis_ticks' AS _set, t.* FROM ga_rb_v_graph_axis_ticks t WHERE t.session_id=(SELECT session_id FROM ga_rb_v_active_session LIMIT 1);
SELECT 'overview_ticks' AS _set, t.* FROM ga_rb_v_graph_axis_ticks t WHERE t.session_id=(SELECT session_id FROM ga_rb_v_active_session LIMIT 1);

SELECT 'demo_options' AS _set, d.* FROM v_dashboard_demo_options d ORDER BY d.name;SELECT 'demo_selection' AS _set, d.* FROM v_demo_profile_selection d;SELECT 'comparison_options' AS _set, d.* FROM v_dashboard_reference_options d;SELECT 'graph_selection' AS _set, d.* FROM ga_rb_v_graph_display_selection d;SELECT 'graph_view_options' AS _set, d.* FROM v_dashboard_graph_view_options d;SELECT 'comparison_series' AS _set, m.*, m.bucket_at AS at, m.sg_value AS sg, m.temperature_mean_c AS temperature_c, m.pressure_mean_bar AS pressure_bar, '#ef6c00' AS line_color FROM ga_rb_v_graph_reference_measurement_series m JOIN ga_rb_v_session_graph_time_axis axis ON axis.session_id=m.session_id WHERE m.bucket_at BETWEEN axis.x_axis_started_at AND axis.x_axis_ended_at ORDER BY m.bucket_at;
SELECT 'graph_labels' AS _set, l.* FROM ga_rb_v_dashboard_graph_labels l;
SELECT 'process_guidance' AS _set, v.* FROM ga_rb_v_current_process_guidance v JOIN ga_rb_v_active_session a ON a.session_id=v.session_id; SELECT 'runtime_presentation' AS _set, v.* FROM ga_rb_v_session_runtime_presentation v JOIN ga_rb_v_active_session a ON a.session_id=v.session_id;SELECT 'bio_pending' AS _set, p.phase_id, p.phase_order, p.name AS phase_name, 'not_evaluated' AS outcome, 'not_yet' AS availability FROM ga_rb_t_session_biological_phases p JOIN ga_rb_v_active_session_summary s ON s.session_id=p.session_id WHERE p.phase_order=(SELECT MIN(n.phase_order) FROM ga_rb_t_session_biological_phases n WHERE n.session_id=p.session_id AND n.phase_order>s.current_biological_phase_order) AND NOT EXISTS(SELECT 1 FROM ga_rb_v_current_biological_candidate_evaluation e WHERE e.session_id=p.session_id);

SELECT 'bio_effective_params' AS _set, p.* FROM ga_rb_v_effective_biological_criterion_parameters p JOIN ga_rb_v_active_session a ON a.session_id=p.session_id;

SELECT 'process_effective_params' AS _set, p.* FROM ga_rb_v_effective_process_criterion_parameters p JOIN ga_rb_v_active_session a ON a.session_id=p.session_id;

SELECT 'historical_phase_options' AS _set, o.* FROM ga_rb_v_historical_phase_options o ORDER BY o.kind, o.sort_order;

SELECT 'phase_durations' AS _set, d.* FROM ga_rb_v_phase_duration_presentation d JOIN ga_rb_v_active_session a ON a.session_id=d.session_id;

SELECT 'import_coverage' AS _set, c.* FROM ga_rb_v_session_import_coverage c WHERE EXISTS(SELECT 1 FROM ga_rb_v_active_session a WHERE a.session_id=c.session_id);

 SELECT 'overview_publication_basis' AS _set, 1 AS should_publish, v_source_key AS source_key, v_generated_at AS generated_at, v_operation AS operation_id;
 IF v_owner THEN COMMIT; CALL ga_drop_read_basis(); END IF;
END//
CREATE PROCEDURE ga_read_report(IN p_session VARCHAR(128), IN p_now DATETIME(3)) BEGIN
 DECLARE v_owner BOOLEAN; DECLARE v_session VARCHAR(128); DECLARE v_source_key CHAR(64); DECLARE v_generated_at DATETIME(3); DECLARE v_operation CHAR(36);
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN IF v_owner THEN ROLLBACK; CALL ga_drop_read_basis(); END IF; RESIGNAL; END;
 SET v_owner=(@@in_transaction=0);
 IF v_owner THEN CALL ga_init_read_basis(); START TRANSACTION WITH CONSISTENT SNAPSHOT,  READ ONLY; END IF;
 SET v_session=p_session;
 SET @ga_report_session=p_session, @ga_report_now=p_now;
 CALL ga_fill_read_basis(v_session);
SELECT 'clock' AS _set, @ga_report_now AS database_now, DATE_FORMAT(CONVERT_TZ(@ga_report_now, '+00:00', 'Europe/Oslo'), '%d.%m.%Y %H:%i') AS generated_display, DATE_FORMAT(@ga_report_now, '%Y%m%dT%H%i%sZ') AS file_stamp;
SELECT 'summary' AS _set, r.* FROM ga_rb_v_session_report_summary r WHERE r.session_id=@ga_report_session;
SELECT 'session' AS _set, r.* FROM ga_rb_v_session_report_session r WHERE r.session_id=@ga_report_session;
SELECT 'analysis_graphs' AS _set, g.* FROM ga_rb_v_graph_definitions g WHERE g.session_id=@ga_report_session AND g.render_scope='report' ORDER BY g.sort_order;
SELECT 'analysis_series' AS _set, s.* FROM ga_rb_v_graph_series s WHERE s.session_id=@ga_report_session ORDER BY s.graph_id, s.series_id, s.sample_at;
SELECT 'analysis_latest' AS _set, s.* FROM ga_rb_v_graph_latest s WHERE s.session_id=@ga_report_session ORDER BY s.graph_id, s.series_id, s.sort_order;
SELECT 'analysis_requirements' AS _set, r.* FROM ga_rb_v_session_analysis_requirements r WHERE r.session_id=@ga_report_session ORDER BY r.graph_id, r.owner_type, r.owner_id, r.criterion_id;
SELECT 'analysis_bio_markers' AS _set, m.* FROM ga_rb_v_active_analysis_biological_markers m WHERE m.session_id=@ga_report_session ORDER BY m.graph_id, m.started_at;
SELECT 'analysis_process_markers' AS _set, m.* FROM ga_rb_v_active_analysis_process_markers m WHERE m.session_id=@ga_report_session ORDER BY m.graph_id, m.started_at;
SELECT 'analysis_time_markers' AS _set, m.* FROM ga_rb_v_graph_time_markers m WHERE m.session_id=@ga_report_session AND m.render_scope='report' ORDER BY m.graph_id, m.marker_at;
SELECT 'biology' AS _set, r.* FROM ga_rb_v_session_report_biology r WHERE r.session_id=@ga_report_session ORDER BY r.started_ms;
SELECT 'process' AS _set, r.* FROM ga_rb_v_session_report_process r WHERE r.session_id=@ga_report_session ORDER BY r.started_ms;
SELECT 'observations' AS _set, r.* FROM ga_rb_v_session_report_observations r WHERE r.session_id=@ga_report_session ORDER BY r.at_ms;
SELECT 'gaps' AS _set, r.* FROM ga_rb_v_session_report_gaps r WHERE r.session_id=@ga_report_session ORDER BY r.gap_started_at;
SELECT 'bio_criteria' AS _set, r.* FROM ga_rb_v_session_report_biological_criteria r WHERE r.session_id=@ga_report_session ORDER BY r.evaluated_at, r.criterion_order;
SELECT 'process_criteria' AS _set, r.* FROM ga_rb_v_session_report_process_criteria r WHERE r.session_id=@ga_report_session ORDER BY r.evaluated_at, r.criterion_order;
SELECT 'criterion_corrections' AS _set, r.* FROM ga_rb_v_session_report_criterion_corrections r WHERE r.session_id=@ga_report_session ORDER BY r.created_at;
SELECT 'process_exceptions' AS _set, r.* FROM ga_rb_v_session_report_process_exceptions r WHERE r.session_id=@ga_report_session ORDER BY r.created_at;
SELECT 'process_transitions' AS _set, r.* FROM ga_rb_v_session_report_process_transitions r WHERE r.session_id=@ga_report_session ORDER BY r.transitioned_at;
SELECT 'notes' AS _set, r.* FROM ga_rb_v_session_report_notes r WHERE r.session_id=@ga_report_session ORDER BY r.noted_at;
SELECT 'timeline' AS _set, r.* FROM ga_rb_v_session_report_timeline r WHERE r.session_id=@ga_report_session ORDER BY r.happened_at;
SELECT 'actions' AS _set, r.* FROM ga_rb_v_session_report_actions r WHERE r.session_id=@ga_report_session ORDER BY r.completed_at;SELECT 'analysis_axis_ticks' AS _set, t.* FROM ga_rb_v_graph_axis_ticks t WHERE t.session_id=@ga_report_session;
SELECT 'bio_exceptions' AS _set, x.* FROM ga_rb_v_session_biological_exception_read_model x WHERE x.session_id=@ga_report_session ORDER BY x.created_at;
SELECT 'analysis_reference_bands' AS _set, r.* FROM ga_rb_v_graph_reference_bands r WHERE r.session_id=@ga_report_session;

SELECT 'import_coverage' AS _set, c.* FROM ga_rb_v_session_import_coverage c WHERE c.session_id=@ga_report_session;

 IF v_owner THEN COMMIT; CALL ga_drop_read_basis(); END IF;
END//
CREATE PROCEDURE ga_poll_overview() BEGIN
 DECLARE v_source_key CHAR(64); DECLARE v_previous CHAR(64); DECLARE v_generated DATETIME(3); DECLARE v_seconds INT;
 CALL ga_overview_source_key(v_source_key);
 SELECT overview_clock_refresh_seconds INTO v_seconds FROM read_model_execution_policy WHERE policy_id=1;
 IF v_seconds IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB-kontrakt: overview clock-policy mangler'; END IF;
 SELECT source_key, generated_at INTO v_previous, v_generated FROM read_model_publication_receipts ORDER BY generated_at DESC, publication_seq DESC LIMIT 1;
 IF v_previous=v_source_key AND (EXISTS(SELECT 1 FROM v_active_session a WHERE a.is_historical=1) OR UTC_TIMESTAMP(3)<v_generated+INTERVAL v_seconds SECOND) THEN SELECT 'overview_publication_basis' AS _set, 0 AS should_publish; ELSE CALL ga_read_overview(); END IF;
END//
CREATE PROCEDURE ga_ack_overview(IN p_operation CHAR(36), IN p_key CHAR(64), IN p_generated DATETIME(3)) BEGIN
 IF p_operation IS NULL OR p_key IS NULL OR p_generated IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB-kontrakt: publiseringskvittering mangler'; END IF;
 INSERT IGNORE INTO read_model_publication_receipts(operation_id, source_key, generated_at, published_at) VALUES(p_operation, p_key, p_generated, UTC_TIMESTAMP(3));
END//
DELIMITER ;
