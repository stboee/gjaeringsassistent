-- Gjæringsassistent – derived views
-- MariaDB is authoritative. Runtime history is append-only; current state is derived.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE OR REPLACE VIEW v_measurement_data_gaps AS
SELECT g.gap_id,g.session_id,g.source,g.gap_started_at,COALESCE(c.gap_ended_at,g.gap_ended_at,IF(sm.last_import_cutoff_at>=h.ended_at,h.ended_at,NULL)) AS gap_ended_at,COALESCE(c.duration_seconds,g.duration_seconds,IF(sm.last_import_cutoff_at>=h.ended_at,TIMESTAMPDIFF(SECOND,g.gap_started_at,h.ended_at),NULL)) AS duration_seconds,g.threshold_seconds,g.detected_at,g.created_at FROM measurement_data_gaps g LEFT JOIN measurement_gap_closures c ON c.gap_id=g.gap_id LEFT JOIN session_history_windows h ON h.session_id=g.session_id LEFT JOIN session_measurement_sources sm ON sm.session_id=g.session_id;








CREATE OR REPLACE VIEW v_current_measurement_statistics_hourly AS
SELECT h.* FROM measurement_statistics_hourly h WHERE NOT EXISTS(SELECT 1 FROM measurement_statistics_hourly n WHERE n.session_id=h.session_id AND n.start_at=h.start_at AND n.statistic_seq>h.statistic_seq);










CREATE OR REPLACE VIEW v_current_session_timing AS
SELECT r.*
FROM session_timing_revisions r
WHERE NOT EXISTS (
    SELECT 1 FROM session_timing_revisions n
    WHERE n.supersedes_revision_id=r.timing_revision_id
);









CREATE OR REPLACE VIEW v_current_fermentation_target AS
SELECT
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
FROM session_fermentation_targets b;









CREATE OR REPLACE VIEW v_current_biological_criterion_revision AS
SELECT r.*
FROM session_biological_criterion_revisions r
WHERE NOT EXISTS (
    SELECT 1 FROM session_biological_criterion_revisions n
    WHERE n.supersedes_revision_id=r.criterion_revision_id
);









CREATE OR REPLACE VIEW v_current_process_criterion_revision AS
SELECT r.*
FROM session_process_criterion_revisions r
WHERE NOT EXISTS (
    SELECT 1 FROM session_process_criterion_revisions n
    WHERE n.supersedes_revision_id=r.criterion_revision_id
);









CREATE OR REPLACE VIEW v_effective_biological_criterion_parameters AS
SELECT k.session_id,k.phase_id,k.criterion_id,c.model_id,k.parameter_id,
       COALESCE(b.data_type,p.data_type) AS data_type,
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.real_value ELSE b.real_value END AS real_value,
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.integer_value ELSE b.integer_value END AS integer_value,
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.boolean_value ELSE b.boolean_value END AS boolean_value,
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.text_value ELSE b.text_value END AS text_value,
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.is_unset ELSE 0 END AS is_unset,
       r.criterion_revision_id
FROM (
    SELECT session_id,phase_id,criterion_id,parameter_id FROM session_biological_criterion_parameter_values
    UNION
    SELECT r.session_id,r.phase_id,r.criterion_id,p.parameter_id
    FROM v_current_biological_criterion_revision r
    JOIN session_biological_criterion_revision_parameter_values p ON p.criterion_revision_id=r.criterion_revision_id
    WHERE r.action='override'
) k
JOIN session_biological_criteria c ON c.session_id=k.session_id AND c.phase_id=k.phase_id AND c.criterion_id=k.criterion_id
LEFT JOIN session_biological_criterion_parameter_values b ON b.session_id=k.session_id AND b.phase_id=k.phase_id AND b.criterion_id=k.criterion_id AND b.parameter_id=k.parameter_id
LEFT JOIN v_current_biological_criterion_revision r ON r.session_id=k.session_id AND r.phase_id=k.phase_id AND r.criterion_id=k.criterion_id
LEFT JOIN session_biological_criterion_revision_parameter_values p ON p.criterion_revision_id=r.criterion_revision_id AND p.parameter_id=k.parameter_id;









CREATE OR REPLACE VIEW v_effective_process_criterion_parameters AS
SELECT k.session_id,k.process_id,k.criterion_id,c.model_id,k.parameter_id,
       COALESCE(b.data_type,p.data_type) AS data_type,
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.real_value ELSE b.real_value END AS real_value,
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.integer_value ELSE b.integer_value END AS integer_value,
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.boolean_value ELSE b.boolean_value END AS boolean_value,
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.text_value ELSE b.text_value END AS text_value,
       CASE WHEN r.action='override' AND p.parameter_id IS NOT NULL THEN p.is_unset ELSE 0 END AS is_unset,
       r.criterion_revision_id
FROM (
    SELECT session_id,process_id,criterion_id,parameter_id FROM session_process_criterion_parameter_values
    UNION
    SELECT r.session_id,r.process_id,r.criterion_id,p.parameter_id
    FROM v_current_process_criterion_revision r
    JOIN session_process_criterion_revision_parameter_values p ON p.criterion_revision_id=r.criterion_revision_id
    WHERE r.action='override'
) k
JOIN session_process_criteria c ON c.session_id=k.session_id AND c.process_id=k.process_id AND c.criterion_id=k.criterion_id
LEFT JOIN session_process_criterion_parameter_values b ON b.session_id=k.session_id AND b.process_id=k.process_id AND b.criterion_id=k.criterion_id AND b.parameter_id=k.parameter_id
LEFT JOIN v_current_process_criterion_revision r ON r.session_id=k.session_id AND r.process_id=k.process_id AND r.criterion_id=k.criterion_id
LEFT JOIN session_process_criterion_revision_parameter_values p ON p.criterion_revision_id=r.criterion_revision_id AND p.parameter_id=k.parameter_id;









CREATE OR REPLACE VIEW v_current_observation_revision AS
SELECT r.*
FROM observation_round_revisions r
WHERE NOT EXISTS (
    SELECT 1 FROM observation_round_revisions n
    WHERE n.supersedes_revision_id=r.observation_revision_id
);









CREATE OR REPLACE VIEW v_recommendations_effective AS
SELECT
    r.*,
    CASE
      WHEN lr.outcome IS NOT NULL THEN lr.outcome
      WHEN EXISTS (
          SELECT 1 FROM recommendations newer
          WHERE newer.session_id=r.session_id
            AND newer.rule_id=r.rule_id
            AND (newer.created_at>r.created_at OR (newer.created_at=r.created_at AND newer.recommendation_id>r.recommendation_id))
      ) THEN 'superseded'
      ELSE 'pending'
    END AS effective_status,
    lr.resolution_id AS latest_resolution_id,
    lr.created_at AS resolved_at
FROM recommendations r
LEFT JOIN recommendation_resolutions lr ON lr.recommendation_id=r.recommendation_id;









CREATE OR REPLACE VIEW v_session_lifecycle AS
SELECT e.*
FROM session_lifecycle_events e
WHERE NOT EXISTS (
    SELECT 1 FROM session_lifecycle_events n
    WHERE n.session_id=e.session_id
      AND (n.occurred_at>e.occurred_at OR (n.occurred_at=e.occurred_at AND n.lifecycle_event_id>e.lifecycle_event_id))
);









CREATE OR REPLACE VIEW v_all_session AS
SELECT
    s.session_id,
    s.batch_name,
    s.is_demo,
    s.created_at,
    COALESCE(tp.value_at,s.pitched_at) AS pitched_at,
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
 IF(h.session_id IS NULL,0,1) AS is_historical,
 COALESCE(h.ended_at,IF(sl.lifecycle='completed',sl.occurred_at,NULL),UTC_TIMESTAMP(3)) AS domain_now
FROM sessions s LEFT JOIN session_history_windows h ON h.session_id=s.session_id
JOIN v_session_lifecycle sl ON sl.session_id=s.session_id
LEFT JOIN session_release_events sr ON sr.session_id=s.session_id
LEFT JOIN v_current_session_timing tp
  ON tp.session_id=s.session_id AND tp.timing_field='pitched_at'
LEFT JOIN v_current_session_timing ta
  ON ta.session_id=s.session_id AND ta.timing_field='activity_started_at';









CREATE OR REPLACE VIEW v_current_session AS
SELECT s.* FROM v_all_session s LEFT JOIN session_release_events r ON r.session_id=s.session_id WHERE r.session_id IS NULL;









CREATE OR REPLACE VIEW v_active_session AS
SELECT
    session_id,batch_name,is_demo,created_at,pitched_at,activity_started_at,
    og,volume_l,yeast_profile_id,pitch_mode_id,pitch_temperature_c,historical_ended_at,is_historical,domain_now
FROM v_current_session
WHERE lifecycle='active';









CREATE OR REPLACE VIEW v_session_measurement_series AS
SELECT m.session_id,m.bucket_at,IF(a.is_historical=1,LEAST(TIMESTAMPADD(SECOND,COALESCE(ds.interval_seconds,300),m.bucket_at),a.domain_now),TIMESTAMPADD(SECOND,COALESCE(ds.interval_seconds,300),m.bucket_at)) AS interval_ended_at,m.sample_count,m.sg_min,m.sg_mean,m.sg_median,m.sg_median AS sg_value,m.sg_max,m.temperature_min_c,m.temperature_mean_c,m.temperature_max_c,m.pressure_min_bar,m.pressure_mean_bar,m.pressure_max_bar,m.rssi_min_dbm,m.rssi_mean_dbm,m.rssi_max_dbm,'detail_5m' AS source_kind,CASE WHEN ds.interval_seconds=3600 THEN 'Syntetisk original · timepunkter' ELSE 'Detaljdata · 5 minutter' END AS source_display,COALESCE(ds.interval_seconds,300) AS interval_seconds
FROM measurements_5m m JOIN v_all_session a ON a.session_id=m.session_id LEFT JOIN session_demo_sources ds ON ds.session_id=m.session_id WHERE a.is_historical=0 OR m.bucket_at>=a.pitched_at AND m.bucket_at<a.domain_now
UNION ALL
SELECT h.session_id,h.start_at,h.end_at,NULL,h.sg_min,h.sg_mean,NULL,h.sg_mean,h.sg_max,h.temperature_min_c,h.temperature_mean_c,h.temperature_max_c,NULL,NULL,NULL,h.rssi_min_dbm,h.rssi_mean_dbm,h.rssi_max_dbm,'ha_statistics_hourly','HA langtidsstatistikk · timeverdier',3600
FROM v_current_measurement_statistics_hourly h JOIN v_all_session s ON s.session_id=h.session_id
WHERE h.start_at>=s.pitched_at AND (s.is_historical=0 OR h.end_at<=s.domain_now) AND NOT EXISTS(SELECT 1 FROM measurements_5m m WHERE m.session_id=h.session_id AND m.bucket_at>=h.start_at AND m.bucket_at<h.end_at);








CREATE OR REPLACE VIEW v_session_measurement_segments AS
SELECT q.*,SUM(q.new_segment) OVER(PARTITION BY q.session_id ORDER BY q.bucket_at) AS segment_id
FROM(SELECT m.*,CASE WHEN LAG(source_kind) OVER(PARTITION BY session_id ORDER BY bucket_at)<>source_kind OR TIMESTAMPDIFF(SECOND,LAG(bucket_at) OVER(PARTITION BY session_id ORDER BY bucket_at),bucket_at)>LAG(interval_seconds) OVER(PARTITION BY session_id ORDER BY bucket_at) THEN 1 ELSE 0 END AS new_segment FROM v_session_measurement_series m) q;








CREATE OR REPLACE VIEW v_graph_display_selection AS
SELECT g.* FROM graph_display_selection_events g WHERE selection_seq=(SELECT MAX(selection_seq) FROM graph_display_selection_events);








CREATE OR REPLACE VIEW v_demo_profile_selection AS
SELECT g.* FROM demo_profile_selection_events g WHERE selection_seq=(SELECT MAX(selection_seq) FROM demo_profile_selection_events);








CREATE OR REPLACE VIEW v_graph_reference_measurement_series AS
SELECT a.session_id,TIMESTAMPADD(SECOND,m.offset_seconds,a.pitched_at) AS bucket_at,m.sample_count,m.sg_min,m.sg_mean,m.sg_median,m.sg_median AS sg_value,m.sg_max,COALESCE(d.temperature_min_c,m.temperature_mean_c) AS temperature_min_c,m.temperature_mean_c,COALESCE(d.temperature_max_c,m.temperature_mean_c) AS temperature_max_c,sy.pressure_bar AS pressure_min_bar,sy.pressure_bar AS pressure_mean_bar,sy.pressure_bar AS pressure_max_bar,(SELECT COUNT(*) FROM demo_reference_data_gaps gap WHERE gap.profile_id=p.profile_id AND gap.gap_end_offset_seconds<=m.offset_seconds) AS segment_id,p.name AS source_display
FROM v_active_session a JOIN v_graph_display_selection choice ON choice.source_kind='reference' JOIN demo_reference_profiles p ON p.profile_id=choice.reference_profile_id JOIN demo_reference_measurements_5m m ON m.profile_id=p.profile_id LEFT JOIN demo_reference_measurement_details d ON d.profile_id=m.profile_id AND d.offset_seconds=m.offset_seconds LEFT JOIN demo_reference_synthetic_details sy ON sy.profile_id=m.profile_id AND sy.offset_seconds=m.offset_seconds
UNION ALL
SELECT a.session_id,TIMESTAMPADD(SECOND,TIMESTAMPDIFF(SECOND,s.pitched_at,m.bucket_at),a.pitched_at),m.sample_count,m.sg_min,m.sg_mean,m.sg_median,m.sg_value,m.sg_max,m.temperature_min_c,m.temperature_mean_c,m.temperature_max_c,m.pressure_min_bar,m.pressure_mean_bar,m.pressure_max_bar,m.segment_id,s.batch_name
FROM v_active_session a JOIN v_graph_display_selection choice ON choice.source_kind='session' JOIN v_all_session s ON s.session_id=choice.reference_session_id JOIN v_session_measurement_segments m ON m.session_id=s.session_id;









CREATE OR REPLACE VIEW v_current_process_visit_revision AS
SELECT r.*
FROM process_visit_revisions r
WHERE NOT EXISTS (
    SELECT 1 FROM process_visit_revisions n
    WHERE n.supersedes_revision_id=r.visit_revision_id
);









CREATE OR REPLACE VIEW v_current_biological_visit_revision AS
SELECT r.*
FROM biological_visit_revisions r
WHERE NOT EXISTS (
    SELECT 1 FROM biological_visit_revisions n
    WHERE n.supersedes_revision_id=r.visit_revision_id
);









CREATE OR REPLACE VIEW v_current_process_visit AS
SELECT x.*
FROM (
    SELECT
        pv.session_id,
        pv.visit_id,
        pv.process_id,
        ROW_NUMBER() OVER (
            PARTITION BY pv.session_id,pv.process_id
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
        TIMESTAMPDIFF(SECOND,pvr.started_at,COALESCE(pvr.ended_at,(SELECT a.domain_now FROM v_all_session a WHERE a.session_id=pv.session_id))) AS duration_seconds,
        pv.visit_seq,
        ROW_NUMBER() OVER (
            PARTITION BY pv.session_id
            ORDER BY pvr.started_at DESC,pv.visit_seq DESC,pvr.created_at DESC,pvr.visit_revision_id DESC
        ) AS session_rn
    FROM process_visits pv
    JOIN v_current_process_visit_revision pvr
      ON pvr.visit_id=pv.visit_id
    JOIN session_process_steps ps
      ON ps.session_id=pv.session_id
     AND ps.process_id=pv.process_id
    WHERE pvr.ended_at IS NULL
) x
WHERE x.session_rn=1;









CREATE OR REPLACE VIEW v_current_biological_visit AS
SELECT x.*
FROM (
    SELECT
        bv.session_id,
        bv.visit_id,
        bv.phase_id,
        ROW_NUMBER() OVER (
            PARTITION BY bv.session_id,bv.phase_id
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
        TIMESTAMPDIFF(SECOND,bvr.started_at,COALESCE(bvr.ended_at,(SELECT a.domain_now FROM v_all_session a WHERE a.session_id=bv.session_id))) AS duration_seconds,
        bv.visit_seq,
        ROW_NUMBER() OVER (
            PARTITION BY bv.session_id
            ORDER BY bvr.started_at DESC,bv.visit_seq DESC,bvr.created_at DESC,bvr.visit_revision_id DESC
        ) AS session_rn
    FROM biological_visits bv
    JOIN v_current_biological_visit_revision bvr
      ON bvr.visit_id=bv.visit_id
    JOIN session_biological_phases bp
      ON bp.session_id=bv.session_id
     AND bp.phase_id=bv.phase_id
    WHERE bvr.ended_at IS NULL
) x
WHERE x.session_rn=1;









CREATE OR REPLACE VIEW v_latest_observation AS
SELECT x.*
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
            ORDER BY r.recorded_at DESC,r.created_at DESC,r.observation_revision_id DESC
        ) AS rn
    FROM observation_rounds o
    JOIN v_current_observation_revision r
      ON r.observation_id=o.observation_id
     AND r.status='active'
) x
WHERE x.rn=1;









CREATE OR REPLACE VIEW v_latest_process_evaluation AS
SELECT x.*
FROM (
    SELECT pe.*,
           ROW_NUMBER() OVER (
               PARTITION BY pe.session_id
               ORDER BY pe.created_at DESC,pe.evaluation_id DESC
           ) AS rn
    FROM process_evaluations pe
) x
WHERE x.rn=1;









CREATE OR REPLACE VIEW v_latest_biological_evaluation AS
SELECT x.*
FROM (
    SELECT be.*,
           ROW_NUMBER() OVER (
               PARTITION BY be.session_id
               ORDER BY be.created_at DESC,be.evaluation_id DESC
           ) AS rn
    FROM biological_evaluations be
) x
WHERE x.rn=1;









CREATE OR REPLACE VIEW v_latest_system_check AS
SELECT x.*
FROM (
    SELECT scr.*,
           ROW_NUMBER() OVER (
               PARTITION BY COALESCE(scr.session_id,'__system__')
               ORDER BY scr.checked_at DESC,scr.created_at DESC,scr.check_run_id DESC
           ) AS rn
    FROM system_check_runs scr
) x
WHERE x.rn=1;









CREATE OR REPLACE VIEW v_active_technical_issues AS
SELECT x.*
FROM (
    SELECT te.*,
           ROW_NUMBER() OVER (
               PARTITION BY te.issue_key
               ORDER BY te.occurred_at DESC,te.created_at DESC,te.event_seq DESC
           ) AS rn
    FROM technical_events te
    WHERE te.issue_key IS NOT NULL
      AND te.event_type IN ('issue_raised','issue_cleared')
) x
WHERE x.rn=1
  AND x.event_type='issue_raised';









-- Completed archive readiness is a persisted lifecycle condition, not a
-- transient connection health check. Pending starts survive runtime restarts.
CREATE OR REPLACE VIEW v_session_archive_status AS
SELECT s.session_id,(s.lifecycle='completed' AND (s.is_demo=1 OR EXISTS(SELECT 1 FROM session_exports e WHERE e.session_id=s.session_id AND e.export_kind='completed_archive' AND e.status='verified'))) AS can_prepare_new,'Gjør klar for ny gjæring' AS prepare_action_display,a.attempt_no AS archive_attempt_no,a.requested_at AS archive_requested_at,
       e.error_message AS archive_error_message,
       CASE WHEN s.lifecycle<>'completed' THEN 'not_applicable'
            WHEN EXISTS(SELECT 1 FROM session_exports v WHERE v.session_id=s.session_id AND v.export_kind='completed_archive' AND v.status='verified') THEN 'verified'
            WHEN e.status='failed' THEN 'failed' WHEN a.attempt_id IS NOT NULL THEN 'pending' ELSE 'missing' END AS archive_status,
       CASE WHEN s.lifecycle<>'completed' THEN 'Sluttarkiv opprettes ved Avslutt gjæring'
            WHEN EXISTS(SELECT 1 FROM session_exports v WHERE v.session_id=s.session_id AND v.export_kind='completed_archive' AND v.status='verified') THEN 'Gjæring avsluttet · arkiv og rapport verifisert'
            WHEN e.status='failed' THEN CONCAT('Gjæring avsluttet · arkivering feilet · ',e.error_message)
            WHEN a.attempt_id IS NOT NULL THEN 'Gjæring avsluttet · arkivering startet, men mangler fullføringskvittering'
            ELSE 'Gjæring avsluttet · verifisert arkiv mangler' END COLLATE utf8mb4_unicode_ci AS archive_status_display
FROM v_current_session s
LEFT JOIN session_export_attempts a ON a.session_id=s.session_id AND a.export_kind='completed_archive' AND a.attempt_no=(SELECT MAX(x.attempt_no) FROM session_export_attempts x WHERE x.session_id=s.session_id AND x.export_kind='completed_archive')
LEFT JOIN session_exports e ON e.operation_id=a.attempt_id AND e.export_kind='completed_archive';









CREATE OR REPLACE VIEW v_all_session_summary AS
SELECT DISTINCT
    s.session_id,
    s.batch_name,
    s.is_demo,s.is_historical,s.historical_ended_at,s.domain_now,
    s.pitched_at,
    s.activity_started_at,
    s.completed_at,
    s.lifecycle,
    s.lifecycle_at,
    ar.archive_status,ar.archive_status_display,ar.archive_error_message,ar.archive_attempt_no,ar.archive_requested_at,ar.can_prepare_new,ar.prepare_action_display,
    s.og,
    s.volume_l,
    ft.expected_attenuation_min_percent,
    ft.expected_attenuation_max_percent,
    ft.expected_fg_min,
    ft.expected_fg_max,
    CASE WHEN ft.expected_attenuation_min_percent IS NULL OR ft.expected_attenuation_max_percent IS NULL THEN NULL
         ELSE CONCAT(CAST(ROUND(ft.expected_attenuation_min_percent,1) AS CHAR),'–',CAST(ROUND(ft.expected_attenuation_max_percent,1) AS CHAR),' %') END COLLATE utf8mb4_unicode_ci AS expected_attenuation_display,
    CASE WHEN ft.expected_fg_min IS NULL OR ft.expected_fg_max IS NULL THEN NULL
         ELSE CONCAT(REPLACE(REPLACE(FORMAT(ft.expected_fg_min,4) COLLATE utf8mb4_unicode_ci,',',''),'.',','),'–',REPLACE(REPLACE(FORMAT(ft.expected_fg_max,4) COLLATE utf8mb4_unicode_ci,',',''),'.',',')) END COLLATE utf8mb4_unicode_ci AS expected_fg_display,
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
FROM v_all_session s
LEFT JOIN v_session_archive_status ar ON ar.session_id=s.session_id
LEFT JOIN v_current_fermentation_target ft ON ft.session_id=s.session_id
LEFT JOIN v_current_process_visit cp ON cp.session_id=s.session_id
LEFT JOIN v_current_biological_visit cb ON cb.session_id=s.session_id
LEFT JOIN v_latest_observation lo ON lo.session_id=s.session_id
LEFT JOIN v_latest_process_evaluation lpe ON lpe.session_id=s.session_id
LEFT JOIN v_latest_biological_evaluation lbe ON lbe.session_id=s.session_id;









CREATE OR REPLACE VIEW v_current_session_summary AS
SELECT DISTINCT
    s.session_id,
    s.batch_name,
    s.is_demo,s.is_historical,s.historical_ended_at,s.domain_now,
    s.pitched_at,
    s.activity_started_at,
    s.completed_at,
    s.lifecycle,
    s.lifecycle_at,
    ar.archive_status,ar.archive_status_display,ar.archive_error_message,ar.archive_attempt_no,ar.archive_requested_at,ar.can_prepare_new,ar.prepare_action_display,
    s.og,
    s.volume_l,
    ft.expected_attenuation_min_percent,
    ft.expected_attenuation_max_percent,
    ft.expected_fg_min,
    ft.expected_fg_max,
    CASE WHEN ft.expected_attenuation_min_percent IS NULL OR ft.expected_attenuation_max_percent IS NULL THEN NULL
         ELSE CONCAT(CAST(ROUND(ft.expected_attenuation_min_percent,1) AS CHAR),'–',CAST(ROUND(ft.expected_attenuation_max_percent,1) AS CHAR),' %') END COLLATE utf8mb4_unicode_ci AS expected_attenuation_display,
    CASE WHEN ft.expected_fg_min IS NULL OR ft.expected_fg_max IS NULL THEN NULL
         ELSE CONCAT(REPLACE(REPLACE(FORMAT(ft.expected_fg_min,4) COLLATE utf8mb4_unicode_ci,',',''),'.',','),'–',REPLACE(REPLACE(FORMAT(ft.expected_fg_max,4) COLLATE utf8mb4_unicode_ci,',',''),'.',',')) END COLLATE utf8mb4_unicode_ci AS expected_fg_display,
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
FROM v_current_session s
LEFT JOIN v_session_archive_status ar ON ar.session_id=s.session_id
LEFT JOIN v_current_fermentation_target ft ON ft.session_id=s.session_id
LEFT JOIN v_current_process_visit cp ON cp.session_id=s.session_id
LEFT JOIN v_current_biological_visit cb ON cb.session_id=s.session_id
LEFT JOIN v_latest_observation lo ON lo.session_id=s.session_id
LEFT JOIN v_latest_process_evaluation lpe ON lpe.session_id=s.session_id
LEFT JOIN v_latest_biological_evaluation lbe ON lbe.session_id=s.session_id;









CREATE OR REPLACE VIEW v_active_session_summary AS
SELECT * FROM v_current_session_summary WHERE lifecycle='active';









-- p21r4 system-metadata read models -------------------------------------------
CREATE OR REPLACE VIEW v_system_function_information_chain AS
SELECT
    f.function_id,
    f.label AS function_label,
    f.subsystem,
    f.status AS function_status,
    d.relation_type,
    d.required AS dependency_required,
    o.object_id,
    o.object_type,
    o.object_name,
    o.status AS object_status,
    o.requires_producer,
    o.requires_consumer
FROM system_functions f
JOIN function_information_dependencies d ON d.function_id=f.function_id
JOIN information_objects o ON o.object_id=d.object_id;









CREATE OR REPLACE VIEW v_metadata_lineage_gaps AS
SELECT
    'function' AS subject_type,
    f.function_id AS subject_id,
    'no_dependency' COLLATE utf8mb4_unicode_ci AS gap_type,
    CONCAT('Aktiv funksjon uten informasjonsavhengighet: ',f.function_id) AS description
FROM system_functions f
WHERE f.status='active'
  AND NOT EXISTS (
      SELECT 1 FROM function_information_dependencies d
      WHERE d.function_id=f.function_id
  )
UNION ALL
SELECT
    'information_object' AS subject_type,
    o.object_id AS subject_id,
    'missing_producer' COLLATE utf8mb4_unicode_ci AS gap_type,
    CONCAT('Informasjonsobjekt mangler produsent: ',o.object_id) AS description
FROM information_objects o
WHERE o.status='active' AND o.requires_producer=1
  AND NOT EXISTS (
      SELECT 1 FROM function_information_dependencies d
      WHERE d.object_id=o.object_id AND d.relation_type IN ('writes','publishes')
  )
UNION ALL
SELECT
    'information_object' AS subject_type,
    o.object_id AS subject_id,
    'missing_consumer' COLLATE utf8mb4_unicode_ci AS gap_type,
    CONCAT('Informasjonsobjekt mangler konsument: ',o.object_id) AS description
FROM information_objects o
WHERE o.status='active' AND o.requires_consumer=1
  AND NOT EXISTS (
      SELECT 1 FROM function_information_dependencies d
      WHERE d.object_id=o.object_id AND d.relation_type IN ('reads','consumes','validates')
  );









-- derived producer/consumer lineage. This is a read-model only; the
-- authoritative relations remain function_information_dependencies.
CREATE OR REPLACE VIEW v_information_object_usage AS
SELECT
    o.object_id,
    o.object_type,
    o.object_name,
    o.status AS object_status,
    o.requires_producer,
    o.requires_consumer,
    COUNT(DISTINCT CASE WHEN d.relation_type IN ('writes','publishes') THEN d.function_id END) AS producer_count,
    COUNT(DISTINCT CASE WHEN d.relation_type IN ('reads','consumes','validates') THEN d.function_id END) AS consumer_count,
    COUNT(DISTINCT d.function_id) AS participating_function_count
FROM information_objects o
LEFT JOIN function_information_dependencies d ON d.object_id=o.object_id
GROUP BY o.object_id,o.object_type,o.object_name,o.status,o.requires_producer,o.requires_consumer;









CREATE OR REPLACE VIEW v_function_producer_consumer AS
SELECT DISTINCT
    p.function_id AS producer_function_id,
    p.relation_type AS producer_relation,
    o.object_id,
    o.object_type,
    o.object_name,
    c.function_id AS consumer_function_id,
    c.relation_type AS consumer_relation
FROM information_objects o
JOIN function_information_dependencies p
  ON p.object_id=o.object_id AND p.relation_type IN ('writes','publishes')
JOIN function_information_dependencies c
  ON c.object_id=o.object_id AND c.relation_type IN ('reads','consumes','validates');










-- p22r3 authoritative evaluator evidence read-models ------------------------
-- Historical phase/process transitions are linked to the exact immutable
-- evaluation that authorized the transition. Current candidate evaluations are
-- selected by persistence order, not by the historical evaluated_at timestamp.
CREATE OR REPLACE VIEW v_biological_transition_evidence AS
SELECT
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
FROM biological_transitions bt
JOIN biological_evaluations e ON e.evaluation_id=bt.evaluation_id
JOIN session_biological_phases bp
  ON bp.session_id=bt.session_id AND bp.phase_id=bt.to_phase_id;









CREATE OR REPLACE VIEW v_current_biological_candidate_evaluation AS
SELECT x.*
FROM (
    SELECT
        e.*,
        bp.phase_order AS candidate_phase_order,
        bp.name AS candidate_phase_name,
        ROW_NUMBER() OVER (
            PARTITION BY e.session_id
            ORDER BY e.created_at DESC,e.evaluation_id DESC
        ) AS rn
    FROM biological_evaluations e
    JOIN v_current_biological_visit cb ON cb.session_id=e.session_id
    JOIN session_biological_phases bp
      ON bp.session_id=e.session_id AND bp.phase_id=e.candidate_phase_id
    WHERE bp.phase_order=cb.phase_order+1
) x
WHERE x.rn=1;









CREATE OR REPLACE VIEW v_process_transition_evidence AS
SELECT
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
FROM process_transitions pt
JOIN process_evaluations e ON e.evaluation_id=pt.evaluation_id
JOIN session_process_steps ps
  ON ps.session_id=pt.session_id AND ps.process_id=pt.to_process_id;









CREATE OR REPLACE VIEW v_current_process_candidate_evaluation AS
SELECT x.*,
       CASE
         WHEN x.candidate_process_id IS NULL THEN 'Prosessplan fullført'
         WHEN x.readiness IN ('ready','ready_with_exceptions') THEN CONCAT(CONVERT(x.candidate_process_id USING utf8mb4),' kriterier oppfylt · venter på manuell overgang')
         WHEN x.readiness='waiting' THEN CONCAT(CONVERT(x.candidate_process_id USING utf8mb4),' · venter på kriterier')
         WHEN x.readiness='invalid_configuration' THEN CONCAT(CONVERT(x.candidate_process_id USING utf8mb4),' · konfigurasjonsfeil')
         ELSE CONCAT(CONVERT(x.candidate_process_id USING utf8mb4),' · ',COALESCE(x.readiness,'ikke vurdert'))
       END COLLATE utf8mb4_unicode_ci AS operator_status_display
FROM (
    SELECT
        e.*,
        ps.process_order AS candidate_process_order,
        ps.name AS candidate_process_name,
        ps.historical_replay_auto_transition_allowed,
        ROW_NUMBER() OVER (
            PARTITION BY e.session_id
            ORDER BY e.created_at DESC,e.evaluation_id DESC
        ) AS rn
    FROM process_evaluations e
    JOIN v_current_process_visit cp ON cp.session_id=e.session_id
    LEFT JOIN session_process_steps ps
      ON ps.session_id=e.session_id AND ps.process_id=e.candidate_process_id
    WHERE (
        (
            e.candidate_process_id IS NOT NULL
            AND ps.enabled=1
            AND ps.process_order=(
                SELECT MIN(n.process_order)
                FROM session_process_steps n
                WHERE n.session_id=e.session_id
                  AND n.enabled=1
                  AND n.process_order>cp.process_order
            )
        )
        OR (
            e.candidate_process_id IS NULL
            AND NOT EXISTS (
                SELECT 1
                FROM session_process_steps n
                WHERE n.session_id=e.session_id
                  AND n.enabled=1
                  AND n.process_order>cp.process_order
            )
        )
    )
) x
WHERE x.rn=1;









-- p22r4 criterion evidence/display read-models -------------------------------
-- Evaluators persist facts/provenance. Display text is derived in MariaDB so
-- Node-RED and the frontend do not reinterpret or format domain values.
CREATE OR REPLACE VIEW v_biological_evaluation_criterion_requirement AS
SELECT
    p.evaluation_id,
    p.criterion_id,
    GROUP_CONCAT(
        CONCAT(
            mp.label, ': ',
            CASE WHEN p.is_unset=1 THEN 'Ikke angitt' ELSE CASE p.data_type
              WHEN 'real' THEN REPLACE(REPLACE(FORMAT(p.real_value,COALESCE(m.display_decimals,2)) COLLATE utf8mb4_unicode_ci,',',''),'.',',')
              WHEN 'integer' THEN CAST(p.integer_value AS CHAR)
              WHEN 'boolean' THEN CASE WHEN p.boolean_value=1 THEN 'Ja' ELSE 'Nei' END
              ELSE p.text_value
            END END,
            CASE WHEN p.is_unset=1 THEN '' ELSE CASE mp.unit_source
              WHEN 'metric' THEN CASE WHEN COALESCE(m.unit,'')<>'' THEN CONCAT(' ',m.unit) ELSE '' END
              WHEN 'fixed' THEN CASE WHEN COALESCE(mp.fixed_unit,'')<>'' THEN CONCAT(' ',mp.fixed_unit) ELSE '' END
              ELSE ''
            END END
        )
        ORDER BY mp.sort_order SEPARATOR ' · '
    ) AS requirement_display
FROM biological_evaluation_criterion_parameter_values p
JOIN biological_evaluation_criteria c
  ON c.evaluation_id=p.evaluation_id AND c.criterion_id=p.criterion_id
JOIN criterion_model_parameters mp
  ON mp.model_id=p.model_id AND mp.parameter_id=p.parameter_id AND mp.data_type=p.data_type
JOIN metrics m ON m.metric_id=c.metric_id
GROUP BY p.evaluation_id,p.criterion_id;









CREATE OR REPLACE VIEW v_process_evaluation_criterion_requirement AS
SELECT
    p.evaluation_id,
    p.criterion_id,
    GROUP_CONCAT(
        CONCAT(
            mp.label, ': ',
            CASE WHEN p.is_unset=1 THEN 'Ikke angitt' ELSE CASE p.data_type
              WHEN 'real' THEN REPLACE(REPLACE(FORMAT(p.real_value,COALESCE(m.display_decimals,2)) COLLATE utf8mb4_unicode_ci,',',''),'.',',')
              WHEN 'integer' THEN CAST(p.integer_value AS CHAR)
              WHEN 'boolean' THEN CASE WHEN p.boolean_value=1 THEN 'Ja' ELSE 'Nei' END
              ELSE p.text_value
            END END,
            CASE WHEN p.is_unset=1 THEN '' ELSE CASE mp.unit_source
              WHEN 'metric' THEN CASE WHEN COALESCE(m.unit,'')<>'' THEN CONCAT(' ',m.unit) ELSE '' END
              WHEN 'fixed' THEN CASE WHEN COALESCE(mp.fixed_unit,'')<>'' THEN CONCAT(' ',mp.fixed_unit) ELSE '' END
              ELSE ''
            END END
        )
        ORDER BY mp.sort_order SEPARATOR ' · '
    ) AS requirement_display
FROM process_evaluation_criterion_parameter_values p
JOIN process_evaluation_criteria c
  ON c.evaluation_id=p.evaluation_id AND c.criterion_id=p.criterion_id
JOIN criterion_model_parameters mp
  ON mp.model_id=p.model_id AND mp.parameter_id=p.parameter_id AND mp.data_type=p.data_type
JOIN metrics m ON m.metric_id=c.metric_id
GROUP BY p.evaluation_id,p.criterion_id;









CREATE OR REPLACE VIEW v_template_biological_criterion_requirement AS
SELECT
    p.session_id,p.phase_id,
    p.criterion_id,
    GROUP_CONCAT(
        CONCAT(
            mp.label, ': ',
            CASE WHEN 0=1 THEN 'Ikke angitt' ELSE CASE p.data_type
              WHEN 'real' THEN REPLACE(REPLACE(FORMAT(p.real_value,COALESCE(m.display_decimals,2)) COLLATE utf8mb4_unicode_ci,',',''),'.',',')
              WHEN 'integer' THEN CAST(p.integer_value AS CHAR)
              WHEN 'boolean' THEN CASE WHEN p.boolean_value=1 THEN 'Ja' ELSE 'Nei' END
              ELSE p.text_value
            END END,
            CASE WHEN 0=1 THEN '' ELSE CASE mp.unit_source
              WHEN 'metric' THEN CASE WHEN COALESCE(m.unit,'')<>'' THEN CONCAT(' ',m.unit) ELSE '' END
              WHEN 'fixed' THEN CASE WHEN COALESCE(mp.fixed_unit,'')<>'' THEN CONCAT(' ',mp.fixed_unit) ELSE '' END
              ELSE ''
            END END
        )
        ORDER BY mp.sort_order SEPARATOR ' · '
    ) AS requirement_display
FROM session_biological_criterion_parameter_values p
JOIN session_biological_criteria c
  ON c.session_id=p.session_id AND c.phase_id=p.phase_id AND c.criterion_id=p.criterion_id
JOIN criterion_model_parameters mp
  ON mp.model_id=p.model_id AND mp.parameter_id=p.parameter_id AND mp.data_type=p.data_type
JOIN metrics m ON m.metric_id=c.metric_id
GROUP BY p.session_id,p.phase_id,p.criterion_id;









CREATE OR REPLACE VIEW v_effective_biological_criterion_requirement AS
SELECT
    p.session_id,p.phase_id,
    p.criterion_id,
    GROUP_CONCAT(
        CONCAT(
            mp.label, ': ',
            CASE WHEN p.is_unset=1 THEN 'Ikke angitt' ELSE CASE p.data_type
              WHEN 'real' THEN REPLACE(REPLACE(FORMAT(p.real_value,COALESCE(m.display_decimals,2)) COLLATE utf8mb4_unicode_ci,',',''),'.',',')
              WHEN 'integer' THEN CAST(p.integer_value AS CHAR)
              WHEN 'boolean' THEN CASE WHEN p.boolean_value=1 THEN 'Ja' ELSE 'Nei' END
              ELSE p.text_value
            END END,
            CASE WHEN p.is_unset=1 THEN '' ELSE CASE mp.unit_source
              WHEN 'metric' THEN CASE WHEN COALESCE(m.unit,'')<>'' THEN CONCAT(' ',m.unit) ELSE '' END
              WHEN 'fixed' THEN CASE WHEN COALESCE(mp.fixed_unit,'')<>'' THEN CONCAT(' ',mp.fixed_unit) ELSE '' END
              ELSE ''
            END END
        )
        ORDER BY mp.sort_order SEPARATOR ' · '
    ) AS requirement_display
FROM v_effective_biological_criterion_parameters p
JOIN session_biological_criteria c
  ON c.session_id=p.session_id AND c.phase_id=p.phase_id AND c.criterion_id=p.criterion_id
JOIN criterion_model_parameters mp
  ON mp.model_id=p.model_id AND mp.parameter_id=p.parameter_id AND mp.data_type=p.data_type
JOIN metrics m ON m.metric_id=c.metric_id
GROUP BY p.session_id,p.phase_id,p.criterion_id;









CREATE OR REPLACE VIEW v_biological_evaluation_criterion_read_model AS
SELECT
    c.*,
    e.evaluated_at,
    e.created_at AS evaluation_created_at,
    sc.label,sc.exception_allowed,
    bx.exception_type,bx.note AS exception_note,
    CASE WHEN sc.exception_allowed=1 AND COALESCE(c.met,0)<>1 AND c.evaluation_status<>'invalid_configuration' THEN 1 ELSE 0 END AS exception_register_allowed,
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
        REPLACE(REPLACE(FORMAT(c.actual_value,m.display_decimals) COLLATE utf8mb4_unicode_ci,',',''),'.',','),
        CASE WHEN m.unit<>'' THEN CONCAT(' ',m.unit) ELSE '' END
      )
      ELSE NULL
    END COLLATE utf8mb4_unicode_ci AS actual_display,
    CASE
      WHEN c.model_id='stability_window' AND c.requested_window_seconds IS NOT NULL THEN CONCAT(
        REPLACE(REPLACE(FORMAT(c.requested_window_seconds/3600,1) COLLATE utf8mb4_unicode_ci,',',''),'.',','),' t · dekning ',
        REPLACE(REPLACE(FORMAT(COALESCE(c.coverage_seconds,0)/3600,1) COLLATE utf8mb4_unicode_ci,',',''),'.',','),' t · ',
        COALESCE(c.sample_count,0),' pkt'
      )
      WHEN c.requested_window_seconds IS NOT NULL THEN CONCAT(
        CASE WHEN c.requested_window_seconds>=3600
             THEN CONCAT(REPLACE(REPLACE(FORMAT(c.requested_window_seconds/3600,1) COLLATE utf8mb4_unicode_ci,',',''),'.',','),' t')
             ELSE CONCAT(ROUND(c.requested_window_seconds/60),' min') END,
        ' · ',COALESCE(c.sample_count,0),' pkt'
      )
      WHEN c.sample_count IS NOT NULL AND c.sample_count>1 THEN CONCAT(
        c.sample_count,' prøver',
        CASE WHEN c.latest_sample_at IS NOT NULL THEN CONCAT(' · t.o.m. ',DATE_FORMAT(CONVERT_TZ(c.latest_sample_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i')) ELSE '' END
      )
      WHEN c.latest_sample_at IS NOT NULL THEN CONCAT('Siste verdi · ',DATE_FORMAT(CONVERT_TZ(c.latest_sample_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i'))
      WHEN c.measured_at IS NOT NULL THEN CONCAT('Siste verdi · ',DATE_FORMAT(CONVERT_TZ(c.measured_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i'))
      ELSE 'Ikke tidsserie'
    END COLLATE utf8mb4_unicode_ci AS data_window_display
FROM biological_evaluation_criteria c
JOIN biological_evaluations e ON e.evaluation_id=c.evaluation_id
LEFT JOIN biological_criterion_exceptions bx ON bx.exception_id=c.applied_exception_id
JOIN metrics m ON m.metric_id=c.metric_id
LEFT JOIN session_biological_criteria sc
  ON sc.session_id=c.session_id AND sc.phase_id=c.phase_id AND sc.criterion_id=c.criterion_id
LEFT JOIN v_biological_evaluation_criterion_requirement r
  ON r.evaluation_id=c.evaluation_id AND r.criterion_id=c.criterion_id
LEFT JOIN v_template_biological_criterion_requirement original ON original.session_id=c.session_id AND original.phase_id=c.phase_id AND original.criterion_id=c.criterion_id
LEFT JOIN v_effective_biological_criterion_requirement effective ON effective.session_id=c.session_id AND effective.phase_id=c.phase_id AND effective.criterion_id=c.criterion_id
LEFT JOIN v_current_biological_criterion_revision current_rev ON current_rev.session_id=c.session_id AND current_rev.phase_id=c.phase_id AND current_rev.criterion_id=c.criterion_id;









CREATE OR REPLACE VIEW v_template_process_criterion_requirement AS
SELECT
    p.session_id,p.process_id,
    p.criterion_id,
    GROUP_CONCAT(
        CONCAT(
            mp.label, ': ',
            CASE WHEN 0=1 THEN 'Ikke angitt' ELSE CASE p.data_type
              WHEN 'real' THEN REPLACE(REPLACE(FORMAT(p.real_value,COALESCE(m.display_decimals,2)) COLLATE utf8mb4_unicode_ci,',',''),'.',',')
              WHEN 'integer' THEN CAST(p.integer_value AS CHAR)
              WHEN 'boolean' THEN CASE WHEN p.boolean_value=1 THEN 'Ja' ELSE 'Nei' END
              ELSE p.text_value
            END END,
            CASE WHEN 0=1 THEN '' ELSE CASE mp.unit_source
              WHEN 'metric' THEN CASE WHEN COALESCE(m.unit,'')<>'' THEN CONCAT(' ',m.unit) ELSE '' END
              WHEN 'fixed' THEN CASE WHEN COALESCE(mp.fixed_unit,'')<>'' THEN CONCAT(' ',mp.fixed_unit) ELSE '' END
              ELSE ''
            END END
        )
        ORDER BY mp.sort_order SEPARATOR ' · '
    ) AS requirement_display
FROM session_process_criterion_parameter_values p
JOIN session_process_criteria c
  ON c.session_id=p.session_id AND c.process_id=p.process_id AND c.criterion_id=p.criterion_id
JOIN criterion_model_parameters mp
  ON mp.model_id=p.model_id AND mp.parameter_id=p.parameter_id AND mp.data_type=p.data_type
JOIN metrics m ON m.metric_id=c.metric_id
GROUP BY p.session_id,p.process_id,p.criterion_id;









CREATE OR REPLACE VIEW v_effective_process_criterion_requirement AS
SELECT
    p.session_id,p.process_id,
    p.criterion_id,
    GROUP_CONCAT(
        CONCAT(
            mp.label, ': ',
            CASE WHEN p.is_unset=1 THEN 'Ikke angitt' ELSE CASE p.data_type
              WHEN 'real' THEN REPLACE(REPLACE(FORMAT(p.real_value,COALESCE(m.display_decimals,2)) COLLATE utf8mb4_unicode_ci,',',''),'.',',')
              WHEN 'integer' THEN CAST(p.integer_value AS CHAR)
              WHEN 'boolean' THEN CASE WHEN p.boolean_value=1 THEN 'Ja' ELSE 'Nei' END
              ELSE p.text_value
            END END,
            CASE WHEN p.is_unset=1 THEN '' ELSE CASE mp.unit_source
              WHEN 'metric' THEN CASE WHEN COALESCE(m.unit,'')<>'' THEN CONCAT(' ',m.unit) ELSE '' END
              WHEN 'fixed' THEN CASE WHEN COALESCE(mp.fixed_unit,'')<>'' THEN CONCAT(' ',mp.fixed_unit) ELSE '' END
              ELSE ''
            END END
        )
        ORDER BY mp.sort_order SEPARATOR ' · '
    ) AS requirement_display
FROM v_effective_process_criterion_parameters p
JOIN session_process_criteria c
  ON c.session_id=p.session_id AND c.process_id=p.process_id AND c.criterion_id=p.criterion_id
JOIN criterion_model_parameters mp
  ON mp.model_id=p.model_id AND mp.parameter_id=p.parameter_id AND mp.data_type=p.data_type
JOIN metrics m ON m.metric_id=c.metric_id
GROUP BY p.session_id,p.process_id,p.criterion_id;









CREATE OR REPLACE VIEW v_process_evaluation_criterion_read_model AS
SELECT
    c.*,
    e.evaluated_at,
    e.created_at AS evaluation_created_at,
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
        REPLACE(REPLACE(FORMAT(c.actual_value,m.display_decimals) COLLATE utf8mb4_unicode_ci,',',''),'.',','),
        CASE WHEN m.unit<>'' THEN CONCAT(' ',m.unit) ELSE '' END
      )
      ELSE NULL
    END COLLATE utf8mb4_unicode_ci AS actual_display,
    CASE
      WHEN c.model_id='stability_window' AND c.requested_window_seconds IS NOT NULL THEN CONCAT(
        REPLACE(REPLACE(FORMAT(c.requested_window_seconds/3600,1) COLLATE utf8mb4_unicode_ci,',',''),'.',','),' t · dekning ',
        REPLACE(REPLACE(FORMAT(COALESCE(c.coverage_seconds,0)/3600,1) COLLATE utf8mb4_unicode_ci,',',''),'.',','),' t · ',
        COALESCE(c.sample_count,0),' pkt'
      )
      WHEN c.requested_window_seconds IS NOT NULL THEN CONCAT(
        CASE WHEN c.requested_window_seconds>=3600
             THEN CONCAT(REPLACE(REPLACE(FORMAT(c.requested_window_seconds/3600,1) COLLATE utf8mb4_unicode_ci,',',''),'.',','),' t')
             ELSE CONCAT(ROUND(c.requested_window_seconds/60),' min') END,
        ' · ',COALESCE(c.sample_count,0),' pkt'
      )
      WHEN c.sample_count IS NOT NULL AND c.sample_count>1 THEN CONCAT(
        c.sample_count,' prøver',
        CASE WHEN c.latest_sample_at IS NOT NULL THEN CONCAT(' · t.o.m. ',DATE_FORMAT(CONVERT_TZ(c.latest_sample_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i')) ELSE '' END
      )
      WHEN c.latest_sample_at IS NOT NULL THEN CONCAT('Siste verdi · ',DATE_FORMAT(CONVERT_TZ(c.latest_sample_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i'))
      WHEN c.measured_at IS NOT NULL THEN CONCAT('Siste verdi · ',DATE_FORMAT(CONVERT_TZ(c.measured_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i'))
      ELSE 'Ikke tidsserie'
    END COLLATE utf8mb4_unicode_ci AS data_window_display
FROM process_evaluation_criteria c
JOIN process_evaluations e ON e.evaluation_id=c.evaluation_id
JOIN metrics m ON m.metric_id=c.metric_id
LEFT JOIN session_process_criteria sc
  ON sc.session_id=c.session_id AND sc.process_id=c.candidate_process_id AND sc.criterion_id=c.criterion_id
LEFT JOIN v_process_evaluation_criterion_requirement r
  ON r.evaluation_id=c.evaluation_id AND r.criterion_id=c.criterion_id
LEFT JOIN v_template_process_criterion_requirement original ON original.session_id=c.session_id AND original.process_id=c.candidate_process_id AND original.criterion_id=c.criterion_id
LEFT JOIN v_effective_process_criterion_requirement effective ON effective.session_id=c.session_id AND effective.process_id=c.candidate_process_id AND effective.criterion_id=c.criterion_id
LEFT JOIN v_current_process_criterion_revision current_rev ON current_rev.session_id=c.session_id AND current_rev.process_id=c.candidate_process_id AND current_rev.criterion_id=c.criterion_id;









-- One current persisted value per metric. Values are not recalculated here;
-- the view only selects the latest evaluator fact and applies registry-owned
-- display precision/unit.
-- Current analysis values are independent of historical criterion evaluations.
CREATE OR REPLACE VIEW v_current_metric_value AS
SELECT x.session_id,x.evaluation_id,x.metric_id,
 CASE WHEN x.current_basis_ok THEN x.actual_value ELSE NULL END AS actual_value,
 NULL AS actual_text,
 CASE WHEN x.current_basis_ok THEN CONCAT(REPLACE(REPLACE(FORMAT(x.actual_value,x.display_decimals) COLLATE utf8mb4_unicode_ci,',',''),'.',','),' ',x.unit) ELSE 'Utilgjengelig' END COLLATE utf8mb4_unicode_ci AS actual_display,
 CASE WHEN x.current_basis_ok THEN x.value_status ELSE 'missing_basis' END COLLATE utf8mb4_unicode_ci AS evaluation_status,
 CASE WHEN x.current_basis_ok THEN CONCAT(CASE x.value_status WHEN 'provisional' THEN 'Foreløpig' ELSE 'Ordinær' END,' · ',x.sample_count,' målepunkter / ',ROUND(x.coverage_seconds/60),' min · ',DATE_FORMAT(CONVERT_TZ(x.measured_at,'+00:00','Europe/Oslo'),'%d.%m %H:%i'))
 ELSE CASE x.reason_code WHEN 'regression_insufficient_span' THEN 'For kort sammenhengende datavindu' WHEN 'regression_uncertainty_too_large' THEN 'For stor usikkerhet i SG-rate' WHEN 'regression_excessive_outliers' THEN 'For mange avvikende målinger' WHEN 'baseline_missing_near_pitch' THEN 'Mangler målinger nær pitch for SG-kalibrering' WHEN 'baseline_unstable_at_pitch' THEN 'SG ved pitch var for ustabil til kalibrering' WHEN 'baseline_insufficient_contiguous_pitch_data' THEN 'For lite sammenhengende SG-grunnlag ved pitch' ELSE 'Mangler fersk, godkjent analyseverdi' END END COLLATE utf8mb4_unicode_ci AS status_display,
 x.measured_at,x.measured_at AS evaluated_at,x.created_at AS evaluation_created_at,'analysis' AS source_scope,x.rn
FROM (
 SELECT d.session_id,d.metric_id,v.actual_value,v.measured_at,v.sample_count,v.coverage_seconds,v.value_status,v.created_at,
 CONCAT('analysis-',CONVERT(d.metric_id USING utf8mb4)) AS evaluation_id,m.display_decimals,m.unit,
 (SELECT e.reason_code FROM analysis_validation_events e WHERE e.session_id=d.session_id AND e.graph_id=d.graph_id AND e.series_id=d.series_id AND e.basis_pitched_at=(SELECT pitched_at FROM v_current_session WHERE session_id=d.session_id) AND e.reason_code<>'band_outside_declared_output_range' AND (v.sample_at IS NULL OR e.sample_at>v.sample_at) ORDER BY e.sample_at DESC LIMIT 1) AS reason_code,
 v.sample_at IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM analysis_validation_events e WHERE e.session_id=d.session_id AND e.graph_id=d.graph_id AND e.series_id=d.series_id AND e.basis_pitched_at=(SELECT pitched_at FROM v_current_session WHERE session_id=d.session_id) AND e.reason_code<>'band_outside_declared_output_range' AND e.sample_at>v.sample_at)
 AND (sess.is_demo=1 OR (TIMESTAMPDIFF(MINUTE,v.measured_at,(SELECT a.domain_now FROM v_all_session a WHERE a.session_id=d.session_id))<=COALESCE((SELECT p.integer_value FROM session_metric_runtime_parameter_values p WHERE p.session_id=d.session_id AND p.metric_id=d.metric_id AND p.parameter_id='maximum_age_minutes'),sp.fresh_age_minutes) AND TIMESTAMPDIFF(MINUTE,v.measured_at,COALESCE((SELECT MAX(mm.bucket_at) FROM measurements_5m mm WHERE mm.session_id=d.session_id),v.measured_at))<=COALESCE((SELECT p.integer_value FROM session_metric_runtime_parameter_values p WHERE p.session_id=d.session_id AND p.metric_id=d.metric_id AND p.parameter_id='maximum_age_minutes'),sp.fresh_age_minutes))) AS current_basis_ok,
 ROW_NUMBER() OVER(PARTITION BY d.session_id,d.metric_id ORDER BY v.sample_at DESC) AS rn
 FROM session_analysis_graph_series d
 JOIN sessions sess ON sess.session_id=d.session_id
 JOIN metrics m ON m.metric_id=d.metric_id
 LEFT JOIN analysis_series_values v ON v.session_id=d.session_id AND v.graph_id=d.graph_id AND v.series_id=d.series_id AND v.basis_pitched_at=(SELECT pitched_at FROM v_current_session WHERE session_id=d.session_id) AND (v.source_observation_revision_id IS NULL OR EXISTS(SELECT 1 FROM v_current_observation_revision o WHERE o.observation_revision_id=v.source_observation_revision_id AND o.session_id=v.session_id AND o.status='active')) AND v.sample_at=(SELECT MAX(last.sample_at) FROM analysis_series_values last WHERE last.session_id=d.session_id AND last.graph_id=d.graph_id AND last.series_id=d.series_id AND last.basis_pitched_at=(SELECT pitched_at FROM v_current_session WHERE session_id=d.session_id) AND (last.source_observation_revision_id IS NULL OR EXISTS(SELECT 1 FROM v_current_observation_revision obs WHERE obs.observation_revision_id=last.source_observation_revision_id AND obs.session_id=last.session_id AND obs.status='active')))
 LEFT JOIN session_measurement_sources sm ON sm.session_id=d.session_id
 LEFT JOIN measurement_source_profiles sp ON sp.source_profile_id=sm.source_profile_id
 WHERE d.source_kind='metric'
) x WHERE x.rn=1;



CREATE OR REPLACE VIEW v_session_import_coverage AS
SELECT q.*,
 CONCAT(q.detail_count,' femminuttersbøtter · ',q.hourly_count,' timepunkter · ',q.gap_count,' registrerte rådatagap') AS counts_display,
 CASE WHEN q.detail_count=0 AND q.hourly_count=0 THEN 'Ingen måledata funnet i behandlet periode'
 WHEN q.detail_count=0 THEN 'Kun HA-timesstatistikk · ingen ordinære femminuttersmålinger'
 WHEN q.gap_count>0 THEN 'Femminuttersmålinger med registrerte datagap'
 ELSE 'Femminuttersmålinger tilgjengelige' END AS coverage_display,
 CONCAT('Behandlet til ',COALESCE(DATE_FORMAT(CONVERT_TZ(q.processed_to,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i'),'ikke behandlet'),
 ' · ',q.detail_count,' femminuttersbøtter · ',q.hourly_count,' timepunkter',
 CASE WHEN q.detail_count=0 THEN ' · mangler ordinært målegrunnlag' WHEN q.gap_count>0 THEN ' · rådatagap finnes' ELSE '' END) AS summary_display
FROM (
 SELECT s.session_id,m.source_started_at,m.last_import_cutoff_at AS processed_to,s.historical_ended_at,
 (SELECT COUNT(*) FROM measurements_5m d WHERE d.session_id=s.session_id) AS detail_count,
 (SELECT MIN(bucket_at) FROM measurements_5m d WHERE d.session_id=s.session_id) AS detail_first_at,
 (SELECT MAX(bucket_at) FROM measurements_5m d WHERE d.session_id=s.session_id) AS detail_last_at,
 (SELECT COUNT(*) FROM v_current_measurement_statistics_hourly h WHERE h.session_id=s.session_id) AS hourly_count,
 (SELECT MIN(start_at) FROM v_current_measurement_statistics_hourly h WHERE h.session_id=s.session_id) AS hourly_first_at,
 (SELECT MAX(end_at) FROM v_current_measurement_statistics_hourly h WHERE h.session_id=s.session_id) AS hourly_last_at,
 (SELECT COUNT(*) FROM v_measurement_data_gaps g WHERE g.session_id=s.session_id) AS gap_count
 FROM v_all_session s JOIN session_measurement_sources m ON m.session_id=s.session_id
) q;









-- p22r4 single database read-model for the Home Assistant measurement source.
CREATE OR REPLACE VIEW v_measurement_source_status AS
SELECT
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
    p.source_profile_id,p.name,p.source_type,p.sg_entity_id,p.temperature_entity_id,p.heartbeat_entity_id,p.rssi_entity_id,
    p.poll_interval_seconds,p.gap_threshold_seconds,p.fresh_age_minutes,p.stale_age_minutes,
    s.session_id,s.is_demo,s.batch_name,s.lifecycle,
    sm.source_started_at,sm.last_import_cutoff_at,sm.last_success_at,sm.last_error,
    m.bucket_at AS latest_bucket_at,m.sample_count AS latest_sample_count,m.sg_min,m.sg_mean,m.sg_median,m.sg_max,m.temperature_mean_c,m.rssi_mean_dbm,
    g.gap_id AS open_gap_id,g.gap_started_at AS open_gap_started_at,
    CASE WHEN m.bucket_at IS NULL THEN NULL ELSE GREATEST(0,TIMESTAMPDIFF(MINUTE,m.bucket_at,s.domain_now)) END AS measurement_age_minutes,
    CASE WHEN m.bucket_at IS NULL THEN 'Ikke tilgjengelig' ELSE CAST(GREATEST(0,TIMESTAMPDIFF(MINUTE,m.bucket_at,s.domain_now)) AS CHAR) END AS measurement_age_state,
    CASE WHEN m.bucket_at IS NULL THEN 'Ikke tilgjengelig' ELSE DATE_FORMAT(m.bucket_at,'%Y-%m-%dT%H:%i:%s+00:00') END AS latest_measurement_state,
    CASE
      WHEN s.is_historical=1 THEN 'historisk datasett' WHEN m.bucket_at IS NULL THEN 'ingen aktiv måling'
      WHEN TIMESTAMPDIFF(MINUTE,m.bucket_at,s.domain_now)<=p.fresh_age_minutes THEN 'fersk'
      WHEN TIMESTAMPDIFF(MINUTE,m.bucket_at,s.domain_now)<=p.stale_age_minutes THEN 'aldrende'
      ELSE 'gammel'
    END COLLATE utf8mb4_unicode_ci AS data_quality_display,
    UTC_TIMESTAMP(3) AS updated_at,
    DATE_FORMAT(m.bucket_at,'%Y-%m-%dT%H:%i:%s+00:00') AS latest_measurement_at_display,
    DATE_FORMAT(CONVERT_TZ(m.bucket_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS latest_bucket_display,
    CASE WHEN m.sg_median IS NULL THEN NULL ELSE CONCAT('median ',REPLACE(REPLACE(FORMAT(m.sg_median,4) COLLATE utf8mb4_unicode_ci,',',''),'.',',')) END COLLATE utf8mb4_unicode_ci AS latest_sg_display,
    CASE WHEN m.sg_mean IS NULL THEN NULL ELSE CONCAT('middel ',REPLACE(REPLACE(FORMAT(m.sg_mean,4) COLLATE utf8mb4_unicode_ci,',',''),'.',','),' · min ',REPLACE(REPLACE(FORMAT(m.sg_min,4) COLLATE utf8mb4_unicode_ci,',',''),'.',','),' · maks ',REPLACE(REPLACE(FORMAT(m.sg_max,4) COLLATE utf8mb4_unicode_ci,',',''),'.',',')) END COLLATE utf8mb4_unicode_ci AS latest_sg_detail_display,
    CASE WHEN m.temperature_mean_c IS NULL THEN NULL ELSE CONCAT(REPLACE(REPLACE(FORMAT(m.temperature_mean_c,2) COLLATE utf8mb4_unicode_ci,',',''),'.',','),' °C') END COLLATE utf8mb4_unicode_ci AS latest_temperature_display,
    CASE WHEN m.rssi_mean_dbm IS NULL THEN NULL ELSE CONCAT(REPLACE(REPLACE(FORMAT(m.rssi_mean_dbm,1) COLLATE utf8mb4_unicode_ci,',',''),'.',','),' dBm') END COLLATE utf8mb4_unicode_ci AS latest_rssi_display,
    DATE_FORMAT(CONVERT_TZ(sm.last_import_cutoff_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS import_cutoff_display,
    DATE_FORMAT(CONVERT_TZ(sm.last_success_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS last_success_display,
    CONCAT(p.poll_interval_seconds,' s') AS poll_interval_display,
    CONCAT(p.gap_threshold_seconds,' s') AS gap_threshold_display,
    CASE WHEN s.is_historical=1 AND sm.last_import_cutoff_at>=s.historical_ended_at AND g.gap_id IS NOT NULL THEN 'Gap i historisk periode' WHEN g.gap_id IS NOT NULL THEN 'ÅPENT' ELSE 'Ingen åpent gap' END COLLATE utf8mb4_unicode_ci AS gap_status_display,
    DATE_FORMAT(CONVERT_TZ(g.gap_started_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS gap_started_display,
    CASE WHEN sm.last_error IS NULL OR sm.last_error='' THEN 'Ingen' ELSE sm.last_error END COLLATE utf8mb4_unicode_ci AS last_error_display,
    'MariaDB' AS authority,
 c.counts_display AS import_counts_display,c.coverage_display AS import_coverage_display,c.summary_display AS import_summary_display
FROM measurement_source_profiles p
LEFT JOIN v_current_session_summary s ON 1=1
LEFT JOIN session_measurement_sources sm ON sm.session_id=s.session_id
LEFT JOIN measurements_5m m
  ON m.session_id=s.session_id
 AND m.bucket_at=(SELECT MAX(m2.bucket_at) FROM measurements_5m m2 WHERE m2.session_id=s.session_id)
LEFT JOIN v_measurement_data_gaps g
  ON g.session_id=s.session_id
 AND g.gap_ended_at IS NULL
 AND g.gap_started_at=(SELECT MAX(g2.gap_started_at) FROM v_measurement_data_gaps g2 WHERE g2.session_id=s.session_id AND g2.gap_ended_at IS NULL)
LEFT JOIN v_session_import_coverage c ON c.session_id=s.session_id
WHERE p.status='active';









-- HA-safe, finished scalar/display projection. Node-RED transports this row
-- unchanged apart from the HA state/attributes envelope.
CREATE OR REPLACE VIEW v_measurement_source_ha_projection AS
SELECT
  state,
  message,
  source_profile_id,
  name,
  source_type,
  sg_entity_id,
  temperature_entity_id,
  heartbeat_entity_id,
  rssi_entity_id,
  poll_interval_display,
  gap_threshold_display,
  COALESCE(CONVERT(session_id USING utf8mb4),'Ikke aktiv') AS session_display,
  COALESCE(batch_name,'Ingen aktiv gjæring') AS batch_display,
  COALESCE(lifecycle,'idle') AS lifecycle_display,
  COALESCE(DATE_FORMAT(CONVERT_TZ(source_started_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i'),'–') AS source_started_display,
  COALESCE(import_cutoff_display,'–') AS import_cutoff_display,
  COALESCE(last_success_display,'–') AS last_success_display,
  COALESCE(latest_bucket_display,'–') AS latest_bucket_display,
  COALESCE(CAST(latest_sample_count AS CHAR),'–') AS latest_sample_count_display,
  COALESCE(latest_sg_display,'–') AS latest_sg_display,
  COALESCE(latest_sg_detail_display,'–') AS latest_sg_detail_display,
  COALESCE(latest_temperature_display,'–') AS latest_temperature_display,
  COALESCE(latest_rssi_display,'–') AS latest_rssi_display,
  COALESCE(measurement_age_state,'Ikke tilgjengelig') AS measurement_age_state,
  COALESCE(latest_measurement_state,'Ikke tilgjengelig') AS latest_measurement_state,
  COALESCE(data_quality_display,'ingen aktiv måling') AS data_quality_display,
  COALESCE(gap_status_display,'Ingen åpent gap') AS gap_status_display,
  COALESCE(gap_started_display,'–') AS gap_started_display,
  COALESCE(last_error_display,'Ingen') AS last_error_display,
  COALESCE(import_counts_display,'Ingen operativ import') AS import_counts_display,
  COALESCE(import_coverage_display,'Ingen operativ import') AS import_coverage_display,
  COALESCE(import_summary_display,'Ingen operativ import') AS import_summary_display,
  'MariaDB' AS source,
  authority,
  DATE_FORMAT(CONVERT_TZ(updated_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i:%s') AS updated_at_display
FROM v_measurement_source_status;









-- p22r4 database-owned display model for the active-session report card/file.
CREATE OR REPLACE VIEW v_session_report_summary AS
SELECT DISTINCT
    s.session_id,
    s.batch_name AS batch_display,
    yp.name AS yeast_display,
    s.expected_attenuation_display,
    s.expected_fg_display,
    DATE_FORMAT(CONVERT_TZ(s.pitched_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS pitched_display,
    CONCAT(COALESCE(CONVERT(s.current_biological_phase_id USING utf8mb4),''),CASE WHEN s.current_biological_phase_name IS NULL OR s.current_biological_phase_name='' THEN '' ELSE CONCAT(' · ',s.current_biological_phase_name) END) AS biology_display,
    CONCAT(COALESCE(CONVERT(s.current_process_id USING utf8mb4),''),CASE WHEN s.current_process_name IS NULL OR s.current_process_name='' THEN '' ELSE CONCAT(' · ',s.current_process_name) END) AS process_display,
    (SELECT REPLACE(REPLACE(FORMAT(m.sg_median,4),',',''),'.',',') FROM measurements_5m m WHERE m.session_id=s.session_id ORDER BY m.bucket_at DESC LIMIT 1) AS latest_tilt_sg_display,
    att.actual_display AS attenuation_display,
    rate.actual_display AS sg_rate_display,
    rate.status_display AS sg_rate_basis_display,
    att.status_display AS attenuation_basis_display,
    st24.actual_display AS stability_24h_display,
    st48.actual_display AS stability_48h_display,
    st24.status_display AS stability_24h_basis_display,
    st48.status_display AS stability_48h_basis_display,
    CONCAT(REPLACE(FORMAT(s.og,4),'.',','),' · ',s.volume_l,' L') AS og_volume_display,
    CONCAT(ROUND(TIMESTAMPDIFF(MINUTE,s.pitched_at,s.domain_now)/60,1),' timer siden pitch') AS elapsed_display,
    CONCAT(ROUND(TIMESTAMPDIFF(MINUTE,s.current_biological_started_at,s.domain_now)/60,1),' timer i fasen') AS phase_duration_display,
    CONCAT(ROUND(TIMESTAMPDIFF(MINUTE,s.current_process_started_at,s.domain_now)/60,1),' timer i prosesstrinnet') AS process_duration_display,
    CASE WHEN att.actual_value>=0 AND s.og<1.775 THEN CONCAT(REPLACE(FORMAT((76.08*((s.og-1)*att.actual_value/100)/(1.775-s.og))*((s.og-(s.og-1)*att.actual_value/100)/0.794),2),'.',','),' % · estimert') ELSE 'Utilgjengelig' END AS abv_now_display,
    COALESCE(att.status_display,'Mangler kvalifisert pitch-baseline eller aktuelt SG-grunnlag') AS abv_basis_display,
    CAST((SELECT COUNT(*) FROM v_current_observation_revision o WHERE o.session_id=s.session_id AND o.status='active') AS CHAR) AS manual_measurements_display,
    (
      SELECT CASE
        WHEN o.corrected_sg IS NOT NULL THEN REPLACE(REPLACE(FORMAT(o.corrected_sg,4) COLLATE utf8mb4_unicode_ci,',',''),'.',',')
        WHEN o.measured_sg IS NOT NULL THEN REPLACE(REPLACE(FORMAT(o.measured_sg,4) COLLATE utf8mb4_unicode_ci,',',''),'.',',')
        ELSE NULL END
      FROM v_current_observation_revision o
      WHERE o.session_id=s.session_id AND o.status='active'
      ORDER BY o.recorded_at DESC,o.revision_no DESC
      LIMIT 1
    ) AS latest_manual_sg_display,
    CAST((SELECT COUNT(*) FROM session_notes n WHERE n.session_id=s.session_id) AS CHAR) AS notes_display,
    CAST((SELECT COUNT(*) FROM measurements_5m m WHERE m.session_id=s.session_id) AS CHAR) AS datapoints_display,
    (
      SELECT CONCAT(CONVERT(e.candidate_process_id USING utf8mb4),' · ',
        CASE e.readiness
          WHEN 'waiting' THEN 'Venter'
          WHEN 'manual' THEN 'Manuell vurdering'
          WHEN 'completed' THEN 'Fullført'
          WHEN 'ready' THEN 'Klar'
          WHEN 'not_ready' THEN 'Ikke klar'
          WHEN 'blocked' THEN 'Blokkert'
          WHEN 'not_evaluated' THEN 'Ikke vurdert'
          ELSE e.readiness END)
      FROM v_current_process_candidate_evaluation e
      WHERE e.session_id=s.session_id
      LIMIT 1
    ) AS next_process_display,
    (SELECT CONCAT('Vurdert ',DATE_FORMAT(CONVERT_TZ(e.evaluated_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i')) FROM v_current_process_candidate_evaluation e WHERE e.session_id=s.session_id LIMIT 1) AS process_evaluated_display,
    ar.public_url AS active_report_url,
    ar.generated_display AS active_report_generated_display
FROM v_all_session_summary s
LEFT JOIN v_all_session cs ON cs.session_id=s.session_id
LEFT JOIN yeast_profiles yp ON yp.yeast_profile_id=cs.yeast_profile_id
LEFT JOIN v_measurement_source_status ms ON ms.session_id=s.session_id
LEFT JOIN v_current_metric_value att ON att.session_id=s.session_id AND att.metric_id='apparent_attenuation_percent'
LEFT JOIN v_current_metric_value rate ON rate.session_id=s.session_id AND rate.metric_id='sg_rate_points_per_day'
LEFT JOIN v_current_metric_value st24 ON st24.session_id=s.session_id AND st24.metric_id='sg_stability_24h_points'
LEFT JOIN v_current_metric_value st48 ON st48.session_id=s.session_id AND st48.metric_id='sg_stability_48h_points'
LEFT JOIN (
  SELECT x.session_id,x.public_url,x.generated_display
  FROM (
    SELECT e.session_id,
           CONCAT('/local/gjaeringsassistent/exports/',SUBSTRING_INDEX(e.archive_path,'/',-1)) AS public_url,
           DATE_FORMAT(CONVERT_TZ(e.completed_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS generated_display,
           ROW_NUMBER() OVER (PARTITION BY e.session_id ORDER BY e.attempt_no DESC,e.completed_at DESC) AS rn
    FROM session_exports e
    WHERE e.export_kind='active_report' AND e.status='verified'
  ) x
  WHERE x.rn=1
) ar ON ar.session_id=s.session_id;









CREATE OR REPLACE VIEW v_active_session_report_summary AS
SELECT r.* FROM v_session_report_summary r JOIN v_active_session a ON a.session_id=r.session_id;









-- p22r5 report detail read-models. These views own textual/domain presentation
-- for the active report; Node-RED renders HTML/SVG but does not interpret codes
-- or invent fallback display values.
CREATE OR REPLACE VIEW v_session_report_session AS
SELECT
    s.session_id,s.batch_name,s.og,s.volume_l,
    CASE WHEN s.is_historical=1 THEN 'Historisk gjæringsrapport' WHEN s.lifecycle='active' THEN 'Aktiv gjæringsrapport' ELSE 'Avsluttet gjæringsrapport' END AS report_kind_display,
    CASE WHEN s.is_historical=1 THEN 'Avsluttet forløp · etterregistrering' WHEN s.lifecycle='active' THEN 'Gjæringen pågår' ELSE 'Gjæringen er avsluttet' END AS lifecycle_display,
    DATE_FORMAT(CONVERT_TZ(s.pitched_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS pitched_display,
    UNIX_TIMESTAMP(s.pitched_at)*1000 AS pitched_ms,
    ft.expected_attenuation_min_percent,ft.expected_attenuation_max_percent,ft.expected_fg_min,ft.expected_fg_max,
    CONCAT(COALESCE(CAST(ft.expected_fg_min AS CHAR),'–'),'–',COALESCE(CAST(ft.expected_fg_max AS CHAR),'–')) AS expected_fg_display,
    CONCAT(COALESCE(CAST(ft.expected_attenuation_min_percent AS CHAR),'–'),'–',COALESCE(CAST(ft.expected_attenuation_max_percent AS CHAR),'–'),' %') AS expected_attenuation_display,
    CONCAT(COALESCE(CONVERT(s.current_biological_phase_id USING utf8mb4),''),CASE WHEN s.current_biological_phase_name IS NULL OR s.current_biological_phase_name='' THEN '' ELSE CONCAT(' · ',s.current_biological_phase_name) END) AS biology_display,
    CONCAT(COALESCE(CONVERT(s.current_process_id USING utf8mb4),''),CASE WHEN s.current_process_name IS NULL OR s.current_process_name='' THEN '' ELSE CONCAT(' · ',s.current_process_name) END) AS process_display,
    tv.name AS template_name,tv.version_label,
    COALESCE((SELECT CAST(o.estimated_abv_percent AS CHAR) FROM v_current_observation_revision o WHERE o.session_id=s.session_id AND o.status='active' ORDER BY o.recorded_at DESC,o.revision_no DESC LIMIT 1),'–') AS latest_abv_display,
    COALESCE((SELECT CAST(o.estimated_finished_abv_percent AS CHAR) FROM v_current_observation_revision o WHERE o.session_id=s.session_id AND o.status='active' ORDER BY o.recorded_at DESC,o.revision_no DESC LIMIT 1),'–') AS estimated_finished_abv_display
FROM v_all_session_summary s
LEFT JOIN v_current_fermentation_target ft ON ft.session_id=s.session_id
LEFT JOIN session_template_snapshots sts ON sts.session_id=s.session_id
LEFT JOIN template_versions tv ON tv.version_id=sts.template_version_id;









CREATE OR REPLACE VIEW v_active_session_report_session AS
SELECT r.* FROM v_session_report_session r JOIN v_active_session a ON a.session_id=r.session_id;






CREATE OR REPLACE VIEW v_biological_visit_timing AS
SELECT q.*, TIMESTAMPDIFF(SECOND,q.started_at,q.ended_at) AS duration_seconds,CONCAT(FLOOR((TIMESTAMPDIFF(SECOND,q.started_at,q.ended_at))/86400),IF(FLOOR((TIMESTAMPDIFF(SECOND,q.started_at,q.ended_at))/86400)=1,' dag, ',' dager, '),LPAD(FLOOR(MOD((TIMESTAMPDIFF(SECOND,q.started_at,q.ended_at)),86400)/3600),2,'0'),':',LPAD(FLOOR(MOD((TIMESTAMPDIFF(SECOND,q.started_at,q.ended_at)),3600)/60),2,'0')) AS duration_display,DATE_FORMAT(CONVERT_TZ(q.started_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS started_display,DATE_FORMAT(CONVERT_TZ(q.ended_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS ended_display FROM (SELECT r.visit_revision_id,r.visit_id,r.revision_no,r.supersedes_revision_id,r.started_at,COALESCE(LEAD(r.started_at) OVER(PARTITION BY v.session_id ORDER BY r.started_at,v.visit_seq),a.domain_now) AS ended_at,r.timing_source,r.confidence,r.evaluation_id,r.revision_reason,r.operation_id,r.created_at,v.session_id,v.phase_id,v.visit_seq FROM biological_visits v JOIN v_current_biological_visit_revision r ON r.visit_id=v.visit_id JOIN v_all_session a ON a.session_id=v.session_id) q;









CREATE OR REPLACE VIEW v_session_report_biology AS
SELECT b.session_id,b.phase_id,p.name,
       UNIX_TIMESTAMP(r.started_at)*1000 AS started_ms,
       UNIX_TIMESTAMP(r.ended_at)*1000 AS ended_ms,
       DATE_FORMAT(CONVERT_TZ(r.started_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS started_display,
       COALESCE(DATE_FORMAT(CONVERT_TZ(r.ended_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i'),'Pågår') AS ended_display,
       COALESCE(r.timing_source,'–') AS timing_source_display,
       r.confidence,r.duration_display
FROM biological_visits b
JOIN v_biological_visit_timing r ON r.visit_id=b.visit_id
JOIN session_biological_phases p ON p.session_id=b.session_id AND p.phase_id=b.phase_id
JOIN v_all_session a ON a.session_id=b.session_id;









CREATE OR REPLACE VIEW v_active_session_report_biology AS
SELECT r.* FROM v_session_report_biology r JOIN v_active_session a ON a.session_id=r.session_id;






CREATE OR REPLACE VIEW v_process_visit_timing AS
SELECT q.*, TIMESTAMPDIFF(SECOND,q.started_at,q.ended_at) AS duration_seconds,CONCAT(FLOOR((TIMESTAMPDIFF(SECOND,q.started_at,q.ended_at))/86400),IF(FLOOR((TIMESTAMPDIFF(SECOND,q.started_at,q.ended_at))/86400)=1,' dag, ',' dager, '),LPAD(FLOOR(MOD((TIMESTAMPDIFF(SECOND,q.started_at,q.ended_at)),86400)/3600),2,'0'),':',LPAD(FLOOR(MOD((TIMESTAMPDIFF(SECOND,q.started_at,q.ended_at)),3600)/60),2,'0')) AS duration_display,DATE_FORMAT(CONVERT_TZ(q.started_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS started_display,DATE_FORMAT(CONVERT_TZ(q.ended_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS ended_display FROM (SELECT r.visit_revision_id,r.visit_id,r.revision_no,r.supersedes_revision_id,r.started_at,COALESCE(LEAD(r.started_at) OVER(PARTITION BY v.session_id ORDER BY r.started_at,v.visit_seq),a.domain_now) AS ended_at,r.timing_source,r.revision_reason,r.operation_id,r.created_at,v.session_id,v.process_id,v.visit_seq FROM process_visits v JOIN v_current_process_visit_revision r ON r.visit_id=v.visit_id JOIN v_all_session a ON a.session_id=v.session_id) q;









CREATE OR REPLACE VIEW v_session_report_process AS
SELECT v.session_id,v.process_id,p.name,p.historical_replay_auto_transition_allowed,
       UNIX_TIMESTAMP(r.started_at)*1000 AS started_ms,
       UNIX_TIMESTAMP(r.ended_at)*1000 AS ended_ms,
       DATE_FORMAT(CONVERT_TZ(r.started_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS started_display,
       COALESCE(DATE_FORMAT(CONVERT_TZ(r.ended_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i'),'Pågår') AS ended_display,
       COALESCE(r.timing_source,'–') AS timing_source_display,
       CASE WHEN p.historical_replay_auto_transition_allowed=1 THEN 'Tillatt' ELSE 'Manuell bekreftelse' END COLLATE utf8mb4_unicode_ci AS historical_replay_policy_display,r.duration_display
FROM process_visits v
JOIN v_process_visit_timing r ON r.visit_id=v.visit_id
JOIN session_process_steps p ON p.session_id=v.session_id AND p.process_id=v.process_id
JOIN v_all_session a ON a.session_id=v.session_id;









CREATE OR REPLACE VIEW v_active_session_report_process AS
SELECT r.* FROM v_session_report_process r JOIN v_active_session a ON a.session_id=r.session_id;









CREATE OR REPLACE VIEW v_session_report_observations AS
SELECT o.session_id,UNIX_TIMESTAMP(o.recorded_at)*1000 AS at_ms,DATE_FORMAT(CONVERT_TZ(o.recorded_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS at_display,
       o.measured_sg,o.corrected_sg,o.manual_temperature_c,
       COALESCE(mm.label,'–') AS measurement_method_display,
       COALESCE(CAST(o.measured_sg AS CHAR),'–') AS measured_sg_display,
       COALESCE(CAST(o.corrected_sg AS CHAR),'–') AS corrected_sg_display,
       COALESCE(CAST(o.manual_temperature_c AS CHAR),'–') AS manual_temperature_display,
       COALESCE(CAST(o.pressure_bar AS CHAR),'–') AS pressure_display,
       COALESCE(CAST(o.cooler_setpoint_c AS CHAR),'–') AS cooler_setpoint_display,
       COALESCE(o.airlock_activity,'–') AS airlock_activity_display,
       COALESCE(CAST(o.acetaldehyde_level AS CHAR),'–') AS acetaldehyde_display,
       COALESCE(CAST(o.diacetyl_level AS CHAR),'–') AS diacetyl_display,
       COALESCE(CAST(o.wort_like_level AS CHAR),'–') AS wort_like_display,
       COALESCE(CAST(o.sulfur_so2_level AS CHAR),'–') AS sulfur_so2_display,
       COALESCE(CAST(o.sulfur_h2s_level AS CHAR),'–') AS sulfur_h2s_display,
       COALESCE(CAST(o.clarity_level AS CHAR),'–') AS clarity_display,
       COALESCE(CAST(o.settling_yeast_level AS CHAR),'–') AS settling_yeast_display,
       COALESCE(CAST(o.settling_minutes AS CHAR),'–') AS settling_minutes_display,
       COALESCE(CAST(o.estimated_abv_percent AS CHAR),'–') AS estimated_abv_display,
       COALESCE(CAST(o.estimated_finished_abv_percent AS CHAR),'–') AS estimated_finished_abv_display,
       COALESCE(o.user_conclusion,'–') AS user_conclusion_display,
       COALESCE(o.note,'–') AS note_display,
       CASE WHEN COALESCE(o.corrected_sg,o.measured_sg) IS NULL THEN NULL ELSE CONCAT('Manuell SG ',CAST(COALESCE(o.corrected_sg,o.measured_sg) AS CHAR),' · ',DATE_FORMAT(CONVERT_TZ(o.recorded_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i')) END AS sg_marker_label,
       CASE WHEN o.manual_temperature_c IS NULL THEN NULL ELSE CONCAT('Manuell temperatur ',CAST(o.manual_temperature_c AS CHAR),' °C · ',DATE_FORMAT(CONVERT_TZ(o.recorded_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i')) END AS temperature_marker_label
FROM v_current_observation_revision o
JOIN v_all_session a ON a.session_id=o.session_id
LEFT JOIN measurement_methods mm ON mm.measurement_method_id=o.measurement_method_id
WHERE o.status='active';









CREATE OR REPLACE VIEW v_active_session_report_observations AS
SELECT r.* FROM v_session_report_observations r JOIN v_active_session a ON a.session_id=r.session_id;









CREATE OR REPLACE VIEW v_session_report_gaps AS
SELECT g.session_id,DATE_FORMAT(CONVERT_TZ(g.gap_started_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS started_display,
       COALESCE(DATE_FORMAT(CONVERT_TZ(g.gap_ended_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i'),'ÅPENT') AS ended_display,
       CASE WHEN g.gap_ended_at IS NULL THEN 'Pågår' ELSE CONCAT(CAST(g.duration_seconds AS CHAR),' s') END COLLATE utf8mb4_unicode_ci AS duration_display,
       COALESCE(g.source,'–') AS source_display,g.gap_started_at,g.gap_ended_at
FROM v_measurement_data_gaps g JOIN v_all_session a ON a.session_id=g.session_id;









CREATE OR REPLACE VIEW v_active_session_report_gaps AS
SELECT r.* FROM v_session_report_gaps r JOIN v_active_session a ON a.session_id=r.session_id;









CREATE OR REPLACE VIEW v_session_report_criterion_corrections AS
SELECT x.session_id,x.created_at,x.created_display,x.area_display,x.owner_id,x.criterion_label,x.action_display,x.parameters_display,x.note_display
FROM (
  SELECT r.session_id,r.created_at,DATE_FORMAT(CONVERT_TZ(r.created_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS created_display,'Biologi' AS area_display,CONVERT(r.phase_id USING utf8mb4) COLLATE utf8mb4_unicode_ci AS owner_id,c.label AS criterion_label,
         CASE r.action WHEN 'override' THEN 'Korrigert' WHEN 'reset' THEN 'Tilbakestilt' ELSE CONVERT(r.action USING utf8mb4) COLLATE utf8mb4_unicode_ci END COLLATE utf8mb4_unicode_ci AS action_display,
         COALESCE(GROUP_CONCAT(CONCAT(CONVERT(p.parameter_id USING utf8mb4),'=',CASE WHEN p.is_unset=1 THEN 'Ikke angitt' ELSE CASE p.data_type WHEN 'real' THEN CONVERT(CAST(p.real_value AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci WHEN 'integer' THEN CONVERT(CAST(p.integer_value AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci WHEN 'boolean' THEN CASE p.boolean_value WHEN 1 THEN 'true' ELSE 'false' END WHEN 'text' THEN p.text_value END END) ORDER BY p.parameter_id SEPARATOR '; '),'–') AS parameters_display,
         COALESCE(r.note,'–') AS note_display
  FROM session_biological_criterion_revisions r
  JOIN v_all_session a ON a.session_id=r.session_id
  JOIN session_biological_criteria c ON c.session_id=r.session_id AND c.phase_id=r.phase_id AND c.criterion_id=r.criterion_id
  LEFT JOIN session_biological_criterion_revision_parameter_values p ON p.criterion_revision_id=r.criterion_revision_id
  GROUP BY r.criterion_revision_id,r.session_id,r.created_at,r.phase_id,c.label,r.action,r.note
  UNION ALL
  SELECT r.session_id,r.created_at,DATE_FORMAT(CONVERT_TZ(r.created_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i'),'Prosesstrinn',CONVERT(r.process_id USING utf8mb4) COLLATE utf8mb4_unicode_ci,c.label,
         CASE r.action WHEN 'override' THEN 'Korrigert' WHEN 'reset' THEN 'Tilbakestilt' ELSE CONVERT(r.action USING utf8mb4) COLLATE utf8mb4_unicode_ci END,
         COALESCE(GROUP_CONCAT(CONCAT(CONVERT(p.parameter_id USING utf8mb4),'=',CASE WHEN p.is_unset=1 THEN 'Ikke angitt' ELSE CASE p.data_type WHEN 'real' THEN CONVERT(CAST(p.real_value AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci WHEN 'integer' THEN CONVERT(CAST(p.integer_value AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci WHEN 'boolean' THEN CASE p.boolean_value WHEN 1 THEN 'true' ELSE 'false' END WHEN 'text' THEN p.text_value END END) ORDER BY p.parameter_id SEPARATOR '; '),'–'),
         COALESCE(r.note,'–')
  FROM session_process_criterion_revisions r
  JOIN v_all_session a ON a.session_id=r.session_id
  JOIN session_process_criteria c ON c.session_id=r.session_id AND c.process_id=r.process_id AND c.criterion_id=r.criterion_id
  LEFT JOIN session_process_criterion_revision_parameter_values p ON p.criterion_revision_id=r.criterion_revision_id
  GROUP BY r.criterion_revision_id,r.session_id,r.created_at,r.process_id,c.label,r.action,r.note
) x;









CREATE OR REPLACE VIEW v_active_session_report_criterion_corrections AS
SELECT r.* FROM v_session_report_criterion_corrections r JOIN v_active_session a ON a.session_id=r.session_id;









CREATE OR REPLACE VIEW v_session_report_process_exceptions AS
SELECT x.session_id,x.created_at,DATE_FORMAT(CONVERT_TZ(x.created_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS created_display,e.candidate_process_id AS owner_id,c.label AS criterion_label,
       CASE x.action WHEN 'register' THEN 'Registrert' WHEN 'withdraw' THEN 'Trukket tilbake' ELSE x.action END COLLATE utf8mb4_unicode_ci AS action_display,
       CASE x.exception_type WHEN 'akseptert_avvik' THEN 'Akseptert avvik' WHEN 'ikke_relevant' THEN 'Ikke relevant' WHEN 'ugyldig_vurderingsgrunnlag' THEN 'Ugyldig vurderingsgrunnlag' ELSE COALESCE(x.exception_type,'–') END COLLATE utf8mb4_unicode_ci AS exception_type_display,
       COALESCE(x.note,'–') AS note_display
FROM process_criterion_exceptions x
JOIN v_all_session a ON a.session_id=x.session_id
JOIN process_evaluations e ON e.evaluation_id=x.evaluation_id
JOIN v_process_evaluation_criterion_read_model c ON c.evaluation_id=x.evaluation_id AND c.criterion_id=x.criterion_id;









CREATE OR REPLACE VIEW v_active_session_report_process_exceptions AS
SELECT r.* FROM v_session_report_process_exceptions r JOIN v_active_session a ON a.session_id=r.session_id;









CREATE OR REPLACE VIEW v_session_report_process_transitions AS
SELECT t.session_id,t.transitioned_at,DATE_FORMAT(CONVERT_TZ(t.transitioned_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS transitioned_display,
       CONCAT(COALESCE(CONVERT(t.from_process_id USING utf8mb4),'–'),' → ',CONVERT(t.to_process_id USING utf8mb4)) AS transition_display,
       CASE t.action WHEN 'next' THEN 'Neste' WHEN 'back' THEN 'Tilbake' WHEN 'backfill' THEN 'Historisk replay' ELSE t.action END COLLATE utf8mb4_unicode_ci AS action_display,
       COALESCE(t.note,'–') AS note_display
FROM process_transitions t JOIN v_all_session a ON a.session_id=t.session_id;









CREATE OR REPLACE VIEW v_active_session_report_process_transitions AS
SELECT r.* FROM v_session_report_process_transitions r JOIN v_active_session a ON a.session_id=r.session_id;









CREATE OR REPLACE VIEW v_session_report_actions AS
SELECT a.session_id,a.completed_at,DATE_FORMAT(CONVERT_TZ(a.completed_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS completed_display,a.label,
       CASE WHEN a.accepted=1 THEN 'Ja' ELSE 'Nei' END COLLATE utf8mb4_unicode_ci AS accepted_display,
       COALESCE(a.outcome,'–') AS outcome_display,
       COALESCE(a.field_error,a.technical_error,a.detail_text,'–') AS detail_display
FROM operator_actions a JOIN v_all_session s ON s.session_id=a.session_id;









CREATE OR REPLACE VIEW v_active_session_report_actions AS
SELECT r.* FROM v_session_report_actions r JOIN v_active_session a ON a.session_id=r.session_id;









CREATE OR REPLACE VIEW v_session_report_timeline AS
SELECT t.session_id,t.happened_at,DATE_FORMAT(CONVERT_TZ(t.happened_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS happened_display,t.type_display,t.event_display,t.note_display
FROM ( SELECT s.session_id,s.pitched_at AS happened_at,CONVERT(('Pitch') USING utf8mb4) COLLATE utf8mb4_unicode_ci AS type_display,CONVERT(('Gjær tilsatt / gjæring startet') USING utf8mb4) COLLATE utf8mb4_unicode_ci AS event_display,CONVERT(('–') USING utf8mb4) COLLATE utf8mb4_unicode_ci AS note_display FROM v_all_session_summary s
 
 UNION ALL
 SELECT b.session_id,r.started_at,CONVERT(('Biologisk fase') USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT((CONCAT(CONVERT(b.phase_id USING utf8mb4) COLLATE utf8mb4_unicode_ci,' · ',p.name)) USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(('–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM biological_visits b JOIN v_biological_visit_timing r ON r.visit_id=b.visit_id JOIN session_biological_phases p ON p.session_id=b.session_id AND p.phase_id=b.phase_id JOIN v_all_session a ON a.session_id=b.session_id
 
 UNION ALL
 SELECT v.session_id,r.started_at,CONVERT(('Prosesstrinn') USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT((CONCAT(CONVERT(v.process_id USING utf8mb4) COLLATE utf8mb4_unicode_ci,' · ',p.name)) USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(('–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM process_visits v JOIN v_process_visit_timing r ON r.visit_id=v.visit_id JOIN session_process_steps p ON p.session_id=v.session_id AND p.process_id=v.process_id JOIN v_all_session a ON a.session_id=v.session_id
 
 UNION ALL
 SELECT g.session_id,g.gap_started_at,CONVERT(('Datagap') USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT((CONCAT('Datagap · ',g.source)) USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT((CASE WHEN g.gap_ended_at IS NULL THEN 'ÅPENT' ELSE CONCAT('Slutt ',DATE_FORMAT(CONVERT_TZ(g.gap_ended_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i')) END) USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM v_measurement_data_gaps g JOIN v_all_session a ON a.session_id=g.session_id
 
 UNION ALL
 SELECT o.session_id,CASE WHEN o.revision_no=1 THEN o.recorded_at ELSE o.created_at END,CONVERT(('Målesett') USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT((CONCAT('Målesett · revisjon ',o.revision_no,' · ',CONVERT(o.status USING utf8mb4),' · SG ',CONVERT(CAST(o.corrected_sg AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci)) USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT((COALESCE(o.note,'–')) USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM observation_round_revisions o JOIN v_all_session a ON a.session_id=o.session_id
 
 UNION ALL
 SELECT n.session_id,n.noted_at,CONVERT(('Notat') USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(('Operatørnotat') USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT((n.note_text) USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM session_notes n JOIN v_all_session a ON a.session_id=n.session_id

 UNION ALL
 SELECT e.session_id,e.occurred_at,CONVERT('Livsløp' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(CASE e.lifecycle WHEN 'active' THEN 'Gjæring startet' WHEN 'completed' THEN 'Gjæring avsluttet' ELSE e.lifecycle END USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(COALESCE(e.note,'–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM session_lifecycle_events e  
 UNION ALL
 SELECT e.session_id,e.transitioned_at,CONVERT('Prosessovergang' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(CONCAT(CONVERT(e.from_process_id USING utf8mb4),' → ',CONVERT(e.to_process_id USING utf8mb4)) USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(COALESCE(e.note,'–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM process_transitions e  
 UNION ALL
 SELECT e.session_id,e.transitioned_at,CONVERT('Biologisk overgang' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(CONCAT(CONVERT(e.from_phase_id USING utf8mb4),' → ',CONVERT(e.to_phase_id USING utf8mb4)) USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(COALESCE(e.reason,'–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM biological_transitions e  
 UNION ALL
 SELECT e.session_id,e.created_at,CONVERT('Tidsregistrering' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(CONCAT(CONVERT(e.timing_field USING utf8mb4),' · revisjon ',e.revision_no) USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(COALESCE(e.reason,'–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM session_timing_revisions e  
 UNION ALL
 SELECT e.session_id,e.created_at,CONVERT('Kriteriekorreksjon' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(CONCAT(CONVERT(e.phase_id USING utf8mb4),' · ',CONVERT(e.criterion_id USING utf8mb4),' · ',CONVERT(e.action USING utf8mb4)) USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(COALESCE(e.note,'–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM session_biological_criterion_revisions e  
 UNION ALL
 SELECT e.session_id,e.created_at,CONVERT('Kriteriekorreksjon' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(CONCAT(CONVERT(e.process_id USING utf8mb4),' · ',CONVERT(e.criterion_id USING utf8mb4),' · ',CONVERT(e.action USING utf8mb4)) USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(COALESCE(e.note,'–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM session_process_criterion_revisions e  
 UNION ALL
 SELECT e.session_id,e.created_at,CONVERT('Kriteriefravik' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(CONCAT(CONVERT(e.criterion_id USING utf8mb4),' · ',CONVERT(e.action USING utf8mb4)) USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(COALESCE(e.note,'–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM process_criterion_exceptions e  
 UNION ALL
 SELECT e.session_id,e.created_at,CONVERT('Kriteriefravik' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(CONCAT(CONVERT(e.criterion_id USING utf8mb4),' · ',CONVERT(e.action USING utf8mb4)) USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(COALESCE(e.note,'–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM biological_criterion_exceptions e  
 UNION ALL
 SELECT e.session_id,e.completed_at,CONVERT('Operatørhandling' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(CONCAT(CONVERT(e.label USING utf8mb4),' · ',COALESCE(CONVERT(e.outcome USING utf8mb4),'')) USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(COALESCE(COALESCE(e.field_error,e.technical_error,e.detail_text),'–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM operator_actions e  WHERE e.session_id IS NOT NULL
 UNION ALL
 SELECT e.session_id,e.occurred_at,CONVERT('Driftsmelding' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(CONCAT(CONVERT(e.code USING utf8mb4),' · ',CONVERT(e.message USING utf8mb4)) USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(COALESCE(e.source_component,'–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM technical_events e  WHERE e.session_id IS NOT NULL
 UNION ALL SELECT p.session_id,e.created_at,CONVERT('Prosessens tidskorrigering' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(CONCAT(CONVERT(p.process_id USING utf8mb4),' · revisjon ',e.revision_no) USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(COALESCE(e.revision_reason,'–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM process_visit_revisions e JOIN process_visits p ON p.visit_id=e.visit_id WHERE e.revision_no>1
 UNION ALL SELECT p.session_id,e.created_at,CONVERT('Biologisk tidsregistrering' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(CONCAT(CONVERT(p.phase_id USING utf8mb4),' · revisjon ',e.revision_no) USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(COALESCE(e.revision_reason,'–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM biological_visit_revisions e JOIN biological_visits p ON p.visit_id=e.visit_id WHERE e.revision_no>1
 UNION ALL SELECT e.session_id,e.released_at,CONVERT('Livsløp' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT('Gjort klar for ny gjæring' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(COALESCE(NULL,'–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM session_release_events e
 UNION ALL SELECT e.session_id,e.requested_at,CONVERT('Arkivering' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(CONCAT('Arkiveringsforsøk ',e.attempt_no) USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(COALESCE(NULL,'–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM session_export_attempts e
 UNION ALL SELECT e.session_id,e.completed_at,CONVERT('Eksport' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(CONCAT(CONVERT(e.export_kind USING utf8mb4),' · ',CONVERT(e.status USING utf8mb4),' · forsøk ',e.attempt_no) USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(COALESCE(e.error_message,'–') USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM session_exports e
) t;









CREATE OR REPLACE VIEW v_active_session_report_timeline AS
SELECT r.* FROM v_session_report_timeline r JOIN v_active_session a ON a.session_id=r.session_id;









CREATE OR REPLACE VIEW v_session_report_series AS
SELECT m.session_id,UNIX_TIMESTAMP(m.bucket_at)*1000 AS at_ms,DATE_FORMAT(CONVERT_TZ(m.bucket_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS at_display,
       m.sg_min,m.sg_mean,m.sg_median,m.sg_value,m.sg_max,m.source_kind,m.source_display,m.interval_seconds,m.segment_id,
       m.temperature_min_c,m.temperature_mean_c,m.temperature_max_c,
       m.pressure_min_bar,m.pressure_mean_bar,m.pressure_max_bar,
       m.rssi_min_dbm,m.rssi_mean_dbm,m.rssi_max_dbm,m.sample_count,m.bucket_at
FROM v_session_measurement_segments m JOIN v_all_session a ON a.session_id=m.session_id;









CREATE OR REPLACE VIEW v_active_session_report_series AS
SELECT r.* FROM v_session_report_series r JOIN v_active_session a ON a.session_id=r.session_id;









CREATE OR REPLACE VIEW v_session_report_biological_criteria AS
SELECT e.session_id,e.evaluated_at,e.candidate_phase_id AS owner_id,DATE_FORMAT(CONVERT_TZ(e.evaluated_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS evaluated_display,
       c.criterion_order,c.label,c.role_id,c.status_display,c.requirement_display,c.actual_display,c.data_window_display,c.explanation
FROM biological_evaluations e
JOIN v_all_session a ON a.session_id=e.session_id
JOIN v_biological_evaluation_criterion_read_model c ON c.evaluation_id=e.evaluation_id;









CREATE OR REPLACE VIEW v_active_session_report_biological_criteria AS
SELECT r.* FROM v_session_report_biological_criteria r JOIN v_active_session a ON a.session_id=r.session_id;









CREATE OR REPLACE VIEW v_session_report_process_criteria AS
SELECT e.session_id,e.evaluated_at,e.candidate_process_id AS owner_id,DATE_FORMAT(CONVERT_TZ(e.evaluated_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS evaluated_display,
       c.criterion_order,c.label,c.role_id,c.status_display,c.requirement_display,c.actual_display,c.data_window_display,c.explanation
FROM process_evaluations e
JOIN v_all_session a ON a.session_id=e.session_id
JOIN v_process_evaluation_criterion_read_model c ON c.evaluation_id=e.evaluation_id;









CREATE OR REPLACE VIEW v_active_session_report_process_criteria AS
SELECT r.* FROM v_session_report_process_criteria r JOIN v_active_session a ON a.session_id=r.session_id;









CREATE OR REPLACE VIEW v_session_report_notes AS
SELECT n.session_id,n.noted_at,DATE_FORMAT(CONVERT_TZ(n.noted_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS noted_display,n.note_text
FROM session_notes n JOIN v_all_session a ON a.session_id=n.session_id;









CREATE OR REPLACE VIEW v_active_session_report_notes AS
SELECT r.* FROM v_session_report_notes r JOIN v_active_session a ON a.session_id=r.session_id;










-- p23r2-revised7: DB-eid dynamisk aksemetadata for Gjæring-grafene ----------
CREATE OR REPLACE VIEW v_session_graph_time_axis AS
SELECT q.session_id,
CASE WHEN c.window_hours IS NULL THEN q.pitched_at ELSE GREATEST(q.pitched_at,TIMESTAMPADD(HOUR,-c.window_hours,q.primary_end)) END AS x_axis_started_at,
CASE WHEN c.window_hours IS NULL THEN IF(q.is_historical=1,q.primary_end,GREATEST(q.primary_end,COALESCE(ref.last_at,q.primary_end))) ELSE q.primary_end END AS x_axis_ended_at,
CONCAT('Dag ',ROUND(TIMESTAMPDIFF(SECOND,q.pitched_at,CASE WHEN c.window_hours IS NULL THEN q.pitched_at ELSE GREATEST(q.pitched_at,TIMESTAMPADD(HOUR,-c.window_hours,q.primary_end)) END)/86400,2),' · ',DATE_FORMAT(CONVERT_TZ(CASE WHEN c.window_hours IS NULL THEN q.pitched_at ELSE GREATEST(q.pitched_at,TIMESTAMPADD(HOUR,-c.window_hours,q.primary_end)) END,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i')) AS x_axis_start_display,
CONCAT('Dag ',ROUND(TIMESTAMPDIFF(SECOND,q.pitched_at,CASE WHEN c.window_hours IS NULL THEN IF(q.is_historical=1,q.primary_end,GREATEST(q.primary_end,COALESCE(ref.last_at,q.primary_end))) ELSE q.primary_end END)/86400,2),' · ',DATE_FORMAT(CONVERT_TZ(CASE WHEN c.window_hours IS NULL THEN IF(q.is_historical=1,q.primary_end,GREATEST(q.primary_end,COALESCE(ref.last_at,q.primary_end))) ELSE q.primary_end END,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i')) AS x_axis_end_display
FROM(SELECT s.session_id,s.pitched_at,s.is_historical,s.domain_now AS primary_end FROM v_all_session s LEFT JOIN(SELECT session_id,MAX(bucket_at) AS last_at FROM v_session_measurement_series GROUP BY session_id) m ON m.session_id=s.session_id) q JOIN v_graph_display_selection c LEFT JOIN(SELECT session_id,MAX(bucket_at) AS last_at FROM v_graph_reference_measurement_series GROUP BY session_id) ref ON ref.session_id=q.session_id;









CREATE OR REPLACE VIEW v_session_overview_graph_extents AS
SELECT q.session_id,q.graph_id,MIN(q.value_num) AS data_min,MAX(q.value_num) AS data_max,MAX(q.include_zero) AS include_zero
FROM (
  SELECT m.session_id,'sg' AS graph_id,CAST(m.sg_min AS DECIMAL(24,9)) AS value_num,0 AS include_zero FROM v_session_measurement_series m WHERE m.sg_min IS NOT NULL
  UNION ALL SELECT m.session_id,'sg',CAST(m.sg_max AS DECIMAL(24,9)),0 FROM v_session_measurement_series m WHERE m.sg_max IS NOT NULL
  UNION ALL SELECT t.session_id,'sg',CAST(t.expected_fg_min AS DECIMAL(24,9)),0 FROM v_current_fermentation_target t WHERE t.expected_fg_min IS NOT NULL
  UNION ALL SELECT t.session_id,'sg',CAST(t.expected_fg_max AS DECIMAL(24,9)),0 FROM v_current_fermentation_target t WHERE t.expected_fg_max IS NOT NULL
  UNION ALL SELECT o.session_id,'sg',CAST(o.corrected_sg AS DECIMAL(24,9)),0 FROM v_current_observation_revision o WHERE o.status='active' AND o.corrected_sg IS NOT NULL
  UNION ALL SELECT m.session_id,'temperature',CAST(m.temperature_min_c AS DECIMAL(24,9)),0 FROM v_session_measurement_series m WHERE m.temperature_min_c IS NOT NULL
  UNION ALL SELECT m.session_id,'temperature',CAST(m.temperature_max_c AS DECIMAL(24,9)),0 FROM v_session_measurement_series m WHERE m.temperature_max_c IS NOT NULL
  UNION ALL SELECT o.session_id,'temperature',CAST(o.manual_temperature_c AS DECIMAL(24,9)),0 FROM v_current_observation_revision o WHERE o.status='active' AND o.manual_temperature_c IS NOT NULL
  UNION ALL SELECT o.session_id,'temperature',CAST(o.cooler_setpoint_c AS DECIMAL(24,9)),0 FROM v_current_observation_revision o WHERE o.status='active' AND o.cooler_setpoint_c IS NOT NULL
  UNION ALL SELECT t.session_id,'temperature',CAST(e.target_value AS DECIMAL(24,9)),0 FROM session_process_targets t JOIN session_process_target_exact e ON e.session_id=t.session_id AND e.process_id=t.process_id AND e.target_id=t.target_id JOIN process_visits pv ON pv.session_id=t.session_id AND pv.process_id=t.process_id WHERE t.metric_id='beer_temperature_c'
  UNION ALL SELECT t.session_id,'temperature',CAST(r.minimum_value AS DECIMAL(24,9)),0 FROM session_process_targets t JOIN session_process_target_range r ON r.session_id=t.session_id AND r.process_id=t.process_id AND r.target_id=t.target_id JOIN process_visits pv ON pv.session_id=t.session_id AND pv.process_id=t.process_id WHERE t.metric_id='beer_temperature_c' AND r.minimum_value IS NOT NULL
  UNION ALL SELECT t.session_id,'temperature',CAST(r.maximum_value AS DECIMAL(24,9)),0 FROM session_process_targets t JOIN session_process_target_range r ON r.session_id=t.session_id AND r.process_id=t.process_id AND r.target_id=t.target_id JOIN process_visits pv ON pv.session_id=t.session_id AND pv.process_id=t.process_id WHERE t.metric_id='beer_temperature_c' AND r.maximum_value IS NOT NULL
  UNION ALL SELECT m.session_id,'pressure',CAST(m.pressure_min_bar AS DECIMAL(24,9)),0 FROM v_session_measurement_series m WHERE m.pressure_min_bar IS NOT NULL
  UNION ALL SELECT m.session_id,'pressure',CAST(m.pressure_max_bar AS DECIMAL(24,9)),0 FROM v_session_measurement_series m WHERE m.pressure_max_bar IS NOT NULL
  UNION ALL SELECT o.session_id,'pressure',CAST(o.pressure_bar AS DECIMAL(24,9)),0 FROM v_current_observation_revision o WHERE o.status='active' AND o.pressure_bar IS NOT NULL
  UNION ALL SELECT t.session_id,'pressure',CAST(e.target_value AS DECIMAL(24,9)),0 FROM session_process_targets t JOIN session_process_target_exact e ON e.session_id=t.session_id AND e.process_id=t.process_id AND e.target_id=t.target_id JOIN process_visits pv ON pv.session_id=t.session_id AND pv.process_id=t.process_id WHERE t.metric_id='pressure_bar'
  UNION ALL SELECT t.session_id,'pressure',CAST(r.minimum_value AS DECIMAL(24,9)),0 FROM session_process_targets t JOIN session_process_target_range r ON r.session_id=t.session_id AND r.process_id=t.process_id AND r.target_id=t.target_id JOIN process_visits pv ON pv.session_id=t.session_id AND pv.process_id=t.process_id WHERE t.metric_id='pressure_bar' AND r.minimum_value IS NOT NULL
  UNION ALL SELECT t.session_id,'pressure',CAST(r.maximum_value AS DECIMAL(24,9)),0 FROM session_process_targets t JOIN session_process_target_range r ON r.session_id=t.session_id AND r.process_id=t.process_id AND r.target_id=t.target_id JOIN process_visits pv ON pv.session_id=t.session_id AND pv.process_id=t.process_id WHERE t.metric_id='pressure_bar' AND r.maximum_value IS NOT NULL

 UNION ALL SELECT session_id,'sg',sg_min,0 FROM v_graph_reference_measurement_series WHERE sg_min IS NOT NULL
 UNION ALL SELECT session_id,'sg',sg_max,0 FROM v_graph_reference_measurement_series WHERE sg_max IS NOT NULL
 UNION ALL SELECT session_id,'temperature',temperature_min_c,0 FROM v_graph_reference_measurement_series WHERE temperature_min_c IS NOT NULL
 UNION ALL SELECT session_id,'temperature',temperature_max_c,0 FROM v_graph_reference_measurement_series WHERE temperature_max_c IS NOT NULL
 UNION ALL SELECT session_id,'pressure',pressure_min_bar,0 FROM v_graph_reference_measurement_series WHERE pressure_min_bar IS NOT NULL
 UNION ALL SELECT session_id,'pressure',pressure_max_bar,0 FROM v_graph_reference_measurement_series WHERE pressure_max_bar IS NOT NULL
) q
WHERE q.value_num IS NOT NULL
GROUP BY q.session_id,q.graph_id;









CREATE OR REPLACE VIEW v_session_overview_graph_axes AS
SELECT z.session_id,z.graph_id,t.x_axis_started_at,t.x_axis_ended_at,t.x_axis_start_display,t.x_axis_end_display,p.band_model,p.band_description,p.band_opacity,
       FLOOR((z.base_min-z.tick_step*0.30)/z.tick_step)*z.tick_step AS y_axis_min,
       CEIL((z.base_max+z.tick_step*0.30)/z.tick_step)*z.tick_step AS y_axis_max,
       z.tick_step AS y_axis_tick_step
FROM (
  SELECT y.*,
         CASE WHEN y.normalized_step<=1 THEN 1*y.magnitude WHEN y.normalized_step<=2 THEN 2*y.magnitude WHEN y.normalized_step<=5 THEN 5*y.magnitude ELSE 10*y.magnitude END AS tick_step
  FROM (
    SELECT x.*,POW(10,FLOOR(LOG10(x.rough_step))) AS magnitude,x.rough_step/POW(10,FLOOR(LOG10(x.rough_step))) AS normalized_step
    FROM (
      SELECT e.session_id,e.graph_id,
             CASE WHEN e.include_zero=1 THEN LEAST(0,e.data_min) ELSE e.data_min END AS base_min,
             CASE WHEN e.include_zero=1 THEN GREATEST(0,e.data_max) ELSE e.data_max END AS base_max,
             GREATEST(
               (CASE WHEN e.include_zero=1 THEN GREATEST(0,e.data_max) ELSE e.data_max END - CASE WHEN e.include_zero=1 THEN LEAST(0,e.data_min) ELSE e.data_min END)/5,
               CASE e.graph_id WHEN 'sg' THEN 0.0002 WHEN 'temperature' THEN 0.2 WHEN 'pressure' THEN 0.02 ELSE 0.01 END
             ) AS rough_step
      FROM v_session_overview_graph_extents e
    ) x
  ) y
) z
JOIN v_session_graph_time_axis t ON t.session_id=z.session_id
JOIN session_overview_graph_policy p ON p.session_id=z.session_id AND p.graph_id=z.graph_id;









CREATE OR REPLACE VIEW v_active_overview_graph_extents AS
SELECT e.* FROM v_session_overview_graph_extents e JOIN v_active_session a ON a.session_id=e.session_id;









CREATE OR REPLACE VIEW v_active_overview_graph_axes AS
SELECT e.* FROM v_session_overview_graph_axes e JOIN v_active_session a ON a.session_id=e.session_id;










-- p22r7 active-session analysis read-models -----------------------------------
CREATE OR REPLACE VIEW v_session_analysis_series AS
SELECT s.session_id,s.graph_id,s.series_id,s.sort_order,s.label,s.source_kind,s.metric_id,s.owner_id,s.criterion_id,
       s.minimum_samples,s.minimum_coverage_fraction,s.warmup_minutes,s.valid_minimum_value,s.valid_maximum_value,
       s.provisional_allowed,s.provisional_minimum_samples,s.provisional_minimum_span_minutes,s.render_mode,
       s.band_model,s.band_description,s.band_opacity,s.standard_color,s.provisional_color,s.standard_dasharray,s.provisional_dasharray,
       CASE WHEN v.actual_value IS NULL THEN NULL ELSE CONCAT(REPLACE(REPLACE(FORMAT(v.actual_value,g.display_decimals) COLLATE utf8mb4_unicode_ci,',',''),'.',','),' ',g.unit) END COLLATE utf8mb4_unicode_ci AS actual_value_display,
       v.sample_at,v.basis_pitched_at,v.source_observation_revision_id,v.basis_revision_key,v.actual_value,v.range_min_value,v.range_max_value,v.measured_at,v.sample_count,v.window_started_at,v.window_ended_at,v.requested_window_seconds,v.coverage_seconds,v.source_kind AS value_source_kind,
       v.value_status,v.standard_basis_met,
       CASE v.value_status WHEN 'provisional' THEN 'Foreløpig' WHEN 'standard' THEN 'Ordinær' ELSE 'Utilgjengelig' END COLLATE utf8mb4_unicode_ci AS value_status_display,
       CASE v.value_status WHEN 'provisional' THEN s.provisional_color WHEN 'standard' THEN s.standard_color ELSE NULL END AS line_color,
       CASE v.value_status WHEN 'provisional' THEN s.provisional_dasharray WHEN 'standard' THEN s.standard_dasharray ELSE NULL END AS line_dasharray,
       CASE WHEN v.sample_at IS NULL THEN NULL ELSE CONCAT(CASE v.value_status WHEN 'provisional' THEN 'Foreløpig' WHEN 'standard' THEN 'Ordinær' END,' · ',v.sample_count,' målepunkter · ',ROUND(v.coverage_seconds/60),' min',CASE WHEN v.requested_window_seconds>0 THEN CONCAT(' av ',ROUND(v.requested_window_seconds/60),' min · ',ROUND(100*v.coverage_seconds/v.requested_window_seconds),' % tidsdekning') ELSE '' END) END COLLATE utf8mb4_unicode_ci AS basis_display,
       CASE WHEN v.requested_window_seconds>0 THEN v.coverage_seconds/v.requested_window_seconds ELSE NULL END AS coverage_fraction
FROM session_analysis_graph_series s
JOIN session_analysis_graphs g ON g.session_id=s.session_id AND g.graph_id=s.graph_id
LEFT JOIN analysis_series_values v ON v.session_id=s.session_id AND v.graph_id=s.graph_id AND v.series_id=s.series_id AND v.basis_pitched_at=(SELECT pitched_at FROM v_all_session WHERE session_id=s.session_id) AND (v.source_observation_revision_id IS NULL OR EXISTS(SELECT 1 FROM v_current_observation_revision o WHERE o.observation_revision_id=v.source_observation_revision_id AND o.session_id=v.session_id AND o.status='active'));









CREATE OR REPLACE VIEW v_session_analysis_latest AS
SELECT s.session_id,s.graph_id,s.series_id,s.sort_order,s.label,s.actual_value,s.measured_at,
       CONCAT(s.label,' · ',COALESCE(s.actual_value_display,'Mangler målegrunnlag'),
              CASE WHEN s.measured_at IS NOT NULL THEN CONCAT(' · målt ',DATE_FORMAT(CONVERT_TZ(s.measured_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i')) ELSE '' END)
              COLLATE utf8mb4_unicode_ci AS latest_value_display
FROM v_session_analysis_series s
WHERE s.sample_at IS NULL OR s.sample_at=(SELECT MAX(v.sample_at) FROM v_session_analysis_series v WHERE v.session_id=s.session_id AND v.graph_id=s.graph_id AND v.series_id=s.series_id);









CREATE OR REPLACE VIEW v_active_analysis_series AS
SELECT s.* FROM v_session_analysis_series s JOIN v_active_session a ON a.session_id=s.session_id;









CREATE OR REPLACE VIEW v_session_analysis_time_markers AS
SELECT g.session_id,g.graph_id,TIMESTAMPADD(DAY,d.seq,a.pitched_at) AS marker_at,d.seq AS relative_day,
CASE WHEN c.source_kind<>'none' THEN CONCAT('Dag ',d.seq,' · ',DATE_FORMAT(CONVERT_TZ(TIMESTAMPADD(DAY,d.seq,a.pitched_at),'+00:00','Europe/Oslo'),'%d.%m')) ELSE DATE_FORMAT(CONVERT_TZ(TIMESTAMPADD(DAY,d.seq,a.pitched_at),'+00:00','Europe/Oslo'),'%d.%m') END AS axis_label
FROM session_analysis_graphs g JOIN v_all_session a ON a.session_id=g.session_id JOIN v_session_graph_time_axis t ON t.session_id=g.session_id JOIN v_graph_display_selection c JOIN seq_0_to_10000 d ON TIMESTAMPADD(DAY,d.seq,a.pitched_at) BETWEEN t.x_axis_started_at AND t.x_axis_ended_at WHERE g.enabled=1;









CREATE OR REPLACE VIEW v_active_analysis_time_markers AS
SELECT m.* FROM v_session_analysis_time_markers m JOIN v_active_session a ON a.session_id=m.session_id;









CREATE OR REPLACE VIEW v_session_analysis_requirements AS
SELECT q.*,
       CONVERT(q.owner_id USING utf8mb4) AS owner_display,
       CASE q.owner_type WHEN 'biology' THEN 'Biologi' WHEN 'process' THEN 'Prosesstrinn' ELSE CONVERT(q.owner_type USING utf8mb4) END COLLATE utf8mb4_unicode_ci AS owner_type_display,
       COALESCE(cr.label,CONVERT(q.role_id USING utf8mb4)) AS role_display,
       CASE
         WHEN q.minimum_value IS NOT NULL AND q.maximum_value IS NOT NULL THEN CONCAT(REPLACE(REPLACE(FORMAT(q.minimum_value,g.display_decimals) COLLATE utf8mb4_unicode_ci,',',''),'.',','),'–',REPLACE(REPLACE(FORMAT(q.maximum_value,g.display_decimals) COLLATE utf8mb4_unicode_ci,',',''),'.',','),' ',g.unit)
         WHEN q.minimum_value IS NOT NULL THEN CONCAT('≥ ',REPLACE(REPLACE(FORMAT(q.minimum_value,g.display_decimals) COLLATE utf8mb4_unicode_ci,',',''),'.',','),' ',g.unit)
         WHEN q.maximum_value IS NOT NULL THEN CONCAT('≤ ',REPLACE(REPLACE(FORMAT(q.maximum_value,g.display_decimals) COLLATE utf8mb4_unicode_ci,',',''),'.',','),' ',g.unit)
         ELSE 'Krav uten numerisk terskel' END COLLATE utf8mb4_unicode_ci AS requirement_display,
       CASE WHEN q.met_at IS NULL THEN NULL ELSE DATE_FORMAT(CONVERT_TZ(q.met_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') END COLLATE utf8mb4_unicode_ci AS met_at_display,
       CASE WHEN q.met_at IS NULL THEN 'Ikke oppfylt' ELSE CONCAT('Oppfylt ',DATE_FORMAT(CONVERT_TZ(q.met_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i')) END COLLATE utf8mb4_unicode_ci AS met_status_display
FROM (
  SELECT gs.session_id,gs.graph_id,'biology' AS owner_type,gs.owner_id,gs.criterion_id,c.label,c.role_id,
         MAX(CASE WHEN p.parameter_id='minimum_value' THEN p.real_value END) AS minimum_value,
         MAX(CASE WHEN p.parameter_id IN ('maximum_value','maximum_range_points') THEN p.real_value END) AS maximum_value,
         (SELECT MIN(e.evaluated_at) FROM biological_evaluations e JOIN biological_evaluation_criteria ec ON ec.evaluation_id=e.evaluation_id
           WHERE e.session_id=gs.session_id AND e.candidate_phase_id=gs.owner_id AND ec.criterion_id=gs.criterion_id AND ec.met=1 AND (ec.criterion_revision_id <=> (SELECT r.criterion_revision_id FROM v_current_biological_criterion_revision r WHERE r.session_id=gs.session_id AND r.phase_id=gs.owner_id AND r.criterion_id=gs.criterion_id))) AS met_at
  FROM session_analysis_graph_series gs
  JOIN session_biological_criteria c ON c.session_id=gs.session_id AND c.phase_id=gs.owner_id AND c.criterion_id=gs.criterion_id
  LEFT JOIN v_effective_biological_criterion_parameters p ON p.session_id=c.session_id AND p.phase_id=c.phase_id AND p.criterion_id=c.criterion_id
  WHERE gs.source_kind='biological_criterion'
  GROUP BY gs.session_id,gs.graph_id,gs.owner_id,gs.criterion_id,c.label,c.role_id
  UNION ALL
  SELECT gs.session_id,gs.graph_id,'process',gs.owner_id,gs.criterion_id,c.label,c.role_id,
         MAX(CASE WHEN p.parameter_id='minimum_value' THEN p.real_value END),
         MAX(CASE WHEN p.parameter_id IN ('maximum_value','maximum_range_points') THEN p.real_value END),
         (SELECT MIN(e.evaluated_at) FROM process_evaluations e JOIN process_evaluation_criteria ec ON ec.evaluation_id=e.evaluation_id
           WHERE e.session_id=gs.session_id AND e.candidate_process_id=gs.owner_id AND ec.criterion_id=gs.criterion_id AND ec.met=1 AND (ec.criterion_revision_id <=> (SELECT r.criterion_revision_id FROM v_current_process_criterion_revision r WHERE r.session_id=gs.session_id AND r.process_id=gs.owner_id AND r.criterion_id=gs.criterion_id)))
  FROM session_analysis_graph_series gs
  JOIN session_process_criteria c ON c.session_id=gs.session_id AND c.process_id=gs.owner_id AND c.criterion_id=gs.criterion_id
  LEFT JOIN v_effective_process_criterion_parameters p ON p.session_id=c.session_id AND p.process_id=c.process_id AND p.criterion_id=c.criterion_id
  WHERE gs.source_kind='process_criterion'
  GROUP BY gs.session_id,gs.graph_id,gs.owner_id,gs.criterion_id,c.label,c.role_id
  UNION ALL
  SELECT g.session_id,g.graph_id,'biology',c.phase_id,c.criterion_id,c.label,c.role_id,
         MAX(CASE WHEN p.parameter_id='minimum_value' THEN p.real_value END),MAX(CASE WHEN p.parameter_id IN ('maximum_value','maximum_range_points') THEN p.real_value END),
         (SELECT MIN(e.evaluated_at) FROM biological_evaluations e JOIN biological_evaluation_criteria ec ON ec.evaluation_id=e.evaluation_id WHERE e.session_id=g.session_id AND e.candidate_phase_id=c.phase_id AND ec.criterion_id=c.criterion_id AND ec.met=1 AND (ec.criterion_revision_id <=> (SELECT r.criterion_revision_id FROM v_current_biological_criterion_revision r WHERE r.session_id=g.session_id AND r.phase_id=c.phase_id AND r.criterion_id=c.criterion_id)))
  FROM session_analysis_graphs g
  JOIN session_analysis_graph_series gs ON gs.session_id=g.session_id AND gs.graph_id=g.graph_id AND gs.source_kind='metric'
  JOIN session_biological_criteria c ON c.session_id=g.session_id AND c.enabled=1 AND (c.metric_id=gs.metric_id OR (c.model_id='stability_window' AND EXISTS(
 SELECT 1 FROM session_metric_runtime_inputs mi JOIN session_metric_runtime_parameter_values mp ON mp.session_id=mi.session_id AND mp.metric_id=mi.metric_id AND mp.parameter_id='window_hours'
 JOIN v_effective_biological_criterion_parameters cp ON cp.session_id=c.session_id AND cp.phase_id=c.phase_id AND cp.criterion_id=c.criterion_id AND cp.parameter_id='window_hours' AND cp.real_value=mp.real_value
 WHERE mi.session_id=gs.session_id AND mi.metric_id=gs.metric_id AND mi.source_kind='series' AND mi.source_id=c.metric_id)))
  LEFT JOIN v_effective_biological_criterion_parameters p ON p.session_id=c.session_id AND p.phase_id=c.phase_id AND p.criterion_id=c.criterion_id
  GROUP BY g.session_id,g.graph_id,c.phase_id,c.criterion_id,c.label,c.role_id
  UNION ALL
  SELECT g.session_id,g.graph_id,'process',c.process_id,c.criterion_id,c.label,c.role_id,
         MAX(CASE WHEN p.parameter_id='minimum_value' THEN p.real_value END),MAX(CASE WHEN p.parameter_id IN ('maximum_value','maximum_range_points') THEN p.real_value END),
         (SELECT MIN(e.evaluated_at) FROM process_evaluations e JOIN process_evaluation_criteria ec ON ec.evaluation_id=e.evaluation_id WHERE e.session_id=g.session_id AND e.candidate_process_id=c.process_id AND ec.criterion_id=c.criterion_id AND ec.met=1 AND (ec.criterion_revision_id <=> (SELECT r.criterion_revision_id FROM v_current_process_criterion_revision r WHERE r.session_id=g.session_id AND r.process_id=c.process_id AND r.criterion_id=c.criterion_id)))
  FROM session_analysis_graphs g
  JOIN session_analysis_graph_series gs ON gs.session_id=g.session_id AND gs.graph_id=g.graph_id AND gs.source_kind='metric'
  JOIN session_process_criteria c ON c.session_id=g.session_id AND c.enabled=1 AND (c.metric_id=gs.metric_id OR (c.model_id='stability_window' AND EXISTS(
 SELECT 1 FROM session_metric_runtime_inputs mi JOIN session_metric_runtime_parameter_values mp ON mp.session_id=mi.session_id AND mp.metric_id=mi.metric_id AND mp.parameter_id='window_hours'
 JOIN v_effective_process_criterion_parameters cp ON cp.session_id=c.session_id AND cp.process_id=c.process_id AND cp.criterion_id=c.criterion_id AND cp.parameter_id='window_hours' AND cp.real_value=mp.real_value
 WHERE mi.session_id=gs.session_id AND mi.metric_id=gs.metric_id AND mi.source_kind='series' AND mi.source_id=c.metric_id)))
  LEFT JOIN v_effective_process_criterion_parameters p ON p.session_id=c.session_id AND p.process_id=c.process_id AND p.criterion_id=c.criterion_id
  GROUP BY g.session_id,g.graph_id,c.process_id,c.criterion_id,c.label,c.role_id
) q
JOIN session_analysis_graphs g ON g.session_id=q.session_id AND g.graph_id=q.graph_id
LEFT JOIN criterion_roles cr ON cr.role_id=q.role_id;









CREATE OR REPLACE VIEW v_active_analysis_requirements AS
SELECT r.session_id,r.graph_id,r.owner_type,r.owner_id,r.criterion_id,r.label,r.role_id,
       r.minimum_value,r.maximum_value,r.met_at,
       r.owner_display,r.owner_type_display,r.role_display,r.requirement_display,r.met_at_display,r.met_status_display
FROM v_session_analysis_requirements r
JOIN v_active_session a ON a.session_id=r.session_id;










CREATE OR REPLACE VIEW v_session_hourly_analysis_policy AS
SELECT d.*,g.display_decimals,g.unit,m.calculation_model_id,
CASE WHEN m.calculation_model_id='metric-rolling-sg-range-v1' THEN (SELECT COALESCE(p.real_value,p.integer_value) FROM session_metric_runtime_parameter_values p WHERE p.session_id=d.session_id AND p.metric_id=d.metric_id AND p.parameter_id='window_hours') ELSE (SELECT COALESCE(p.real_value,p.integer_value) FROM session_biology_calculation_parameter_values p JOIN session_metric_runtime_inputs i ON i.session_id=p.session_id AND i.source_id=p.calculation_id AND i.source_kind='biology_calculation' WHERE i.session_id=d.session_id AND i.metric_id=d.metric_id AND i.input_id='calculation' AND p.parameter_id='window_hours') END AS window_hours,
CASE WHEN m.calculation_model_id='metric-rolling-sg-range-v1' THEN 60*(SELECT COALESCE(p.real_value,p.integer_value) FROM session_metric_runtime_parameter_values p WHERE p.session_id=d.session_id AND p.metric_id=d.metric_id AND p.parameter_id='minimum_span_hours') ELSE (SELECT COALESCE(p.real_value,p.integer_value) FROM session_biology_calculation_parameter_values p JOIN session_metric_runtime_inputs i ON i.session_id=p.session_id AND i.source_id=p.calculation_id AND i.source_kind='biology_calculation' WHERE i.session_id=d.session_id AND i.metric_id=d.metric_id AND i.input_id='calculation' AND p.parameter_id='minimum_span_minutes') END AS minimum_span_minutes
FROM session_analysis_graph_series d JOIN session_analysis_graphs g ON g.session_id=d.session_id AND g.graph_id=d.graph_id JOIN session_metric_runtime_rules m ON m.session_id=d.session_id AND m.metric_id=d.metric_id WHERE d.source_kind='metric' AND m.calculation_model_id IN ('metric-raw-attenuation-v1','metric-calculation-output-v1','metric-rolling-sg-range-v1');








CREATE OR REPLACE VIEW v_session_hourly_analysis_aggregate AS
SELECT d.session_id,d.graph_id,d.series_id,h.bucket_at AS sample_at,MIN(pr.bucket_at) AS window_started_at,MAX(pr.bucket_at) AS window_ended_at,COUNT(*) AS sample_count,TIMESTAMPDIFF(SECOND,MIN(pr.bucket_at),MAX(pr.bucket_at)) AS coverage_seconds,MIN(pr.sg_mean) AS value_min,MAX(pr.sg_mean) AS value_max,
MAX(h.sg_mean) AS current_sg,
(SELECT first.sg_mean FROM v_session_measurement_series first WHERE first.session_id=d.session_id AND first.source_kind='ha_statistics_hourly' AND first.bucket_at=MIN(pr.bucket_at) LIMIT 1) AS first_sg
FROM v_session_hourly_analysis_policy d JOIN v_session_measurement_series h ON h.session_id=d.session_id AND h.source_kind='ha_statistics_hourly' AND h.sg_mean IS NOT NULL JOIN v_session_measurement_series pr ON pr.session_id=d.session_id AND pr.source_kind='ha_statistics_hourly' AND pr.sg_mean IS NOT NULL AND pr.bucket_at BETWEEN TIMESTAMPADD(SECOND,-d.window_hours*3600,h.bucket_at) AND h.bucket_at
WHERE d.calculation_model_id<>'metric-raw-attenuation-v1' GROUP BY d.session_id,d.graph_id,d.series_id,h.bucket_at;








CREATE OR REPLACE VIEW v_session_hourly_analysis_values AS
SELECT d.session_id,d.graph_id,d.series_id,h.bucket_at AS sample_at,100*(s.og-h.sg_mean)/(s.og-1) AS actual_value,1 AS sample_count,0 AS coverage_seconds,0 AS requested_window_seconds,h.bucket_at AS window_started_at,h.bucket_at AS window_ended_at
FROM v_session_hourly_analysis_policy d JOIN v_all_session s ON s.session_id=d.session_id JOIN v_session_measurement_series h ON h.session_id=d.session_id AND h.source_kind='ha_statistics_hourly' WHERE d.calculation_model_id='metric-raw-attenuation-v1' AND h.sg_mean IS NOT NULL AND s.og>1
UNION ALL
SELECT d.session_id,d.graph_id,d.series_id,a.sample_at,CASE d.calculation_model_id WHEN 'metric-calculation-output-v1' THEN 1000*(a.first_sg-a.current_sg)*86400/a.coverage_seconds ELSE 1000*(a.value_max-a.value_min) END,a.sample_count,a.coverage_seconds,d.window_hours*3600,a.window_started_at,a.window_ended_at
FROM v_session_hourly_analysis_policy d JOIN v_session_hourly_analysis_aggregate a ON a.session_id=d.session_id AND a.graph_id=d.graph_id AND a.series_id=d.series_id JOIN v_all_session s ON s.session_id=d.session_id
WHERE a.sample_count>=2 AND a.coverage_seconds>=d.minimum_span_minutes*60 AND a.coverage_seconds>=d.window_hours*3600*d.minimum_coverage_fraction AND TIMESTAMPDIFF(MINUTE,s.pitched_at,a.sample_at)>=d.warmup_minutes AND a.coverage_seconds>0 AND a.sample_count=a.coverage_seconds/3600+1;








CREATE OR REPLACE VIEW v_session_hourly_analysis_series AS
SELECT d.session_id AS session_id,
 d.graph_id AS graph_id,
 CONCAT('ha-hourly-',d.series_id) AS series_id,
 d.sort_order AS sort_order,
 CONCAT('HA timeverdier · ',d.label) AS label,
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
 CONCAT(REPLACE(REPLACE(FORMAT(v.actual_value,d.display_decimals),',',''),'.',','),' ',d.unit) AS actual_value_display,
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
 CONCAT('HA langtidsstatistikk · ',v.sample_count,' timeverdier · ingen MQTT-verifikasjon') AS basis_display,
 CASE WHEN v.requested_window_seconds>0 THEN v.coverage_seconds/v.requested_window_seconds ELSE NULL END AS coverage_fraction FROM v_session_hourly_analysis_policy d JOIN v_session_hourly_analysis_values v ON v.session_id=d.session_id AND v.graph_id=d.graph_id AND v.series_id=d.series_id JOIN v_all_session a ON a.session_id=d.session_id WHERE (d.valid_minimum_value IS NULL OR v.actual_value>=d.valid_minimum_value) AND (d.valid_maximum_value IS NULL OR v.actual_value<=d.valid_maximum_value);








CREATE OR REPLACE VIEW v_primary_analysis_source AS
SELECT s.*,'primary' AS series_role,300 AS interval_seconds FROM v_session_analysis_series s UNION ALL SELECT s.*,'primary',3600 FROM v_session_hourly_analysis_series s;









CREATE OR REPLACE VIEW v_graph_reference_analysis_series AS
SELECT a.session_id AS session_id,
 d.graph_id AS graph_id,
 CONCAT('comparison-',d.series_id) AS series_id,
 d.sort_order AS sort_order,
 CONCAT(p.name,' · ',d.label) AS label,
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
 CONCAT(REPLACE(REPLACE(FORMAT(v.actual_value,g.display_decimals),',',''),'.',','),' ',g.unit) AS actual_value_display,
 TIMESTAMPADD(SECOND,v.offset_seconds,a.pitched_at) AS sample_at,
 a.pitched_at AS basis_pitched_at,
 NULL AS source_observation_revision_id,
 p.profile_id AS basis_revision_key,
 v.actual_value AS actual_value,
 NULL AS range_min_value,
 NULL AS range_max_value,
 TIMESTAMPADD(SECOND,v.offset_seconds,a.pitched_at) AS measured_at,
 v.sample_count AS sample_count,
 TIMESTAMPADD(SECOND,v.offset_seconds-v.coverage_seconds,a.pitched_at) AS window_started_at,
 TIMESTAMPADD(SECOND,v.offset_seconds,a.pitched_at) AS window_ended_at,
 v.window_seconds AS requested_window_seconds,
 v.coverage_seconds AS coverage_seconds,
 'reference' AS value_source_kind,
 'standard' AS value_status,
 1 AS standard_basis_met,
 'Referanse' AS value_status_display,
 '#ef6c00' AS line_color,
 CASE WHEN d.sort_order=1 THEN '6 3' ELSE '2 4' END AS line_dasharray,
 CONCAT(p.name,' · ',v.basis_display) AS basis_display,
 CASE WHEN v.window_seconds>0 THEN v.coverage_seconds/v.window_seconds ELSE NULL END AS coverage_fraction FROM v_active_session a JOIN v_graph_display_selection choice ON choice.source_kind='reference' JOIN demo_reference_profiles p ON p.profile_id=choice.reference_profile_id JOIN demo_reference_analysis_values v ON v.profile_id=p.profile_id JOIN session_analysis_graph_series d ON d.session_id=a.session_id AND d.graph_id=v.graph_id AND d.series_id=v.series_id JOIN session_analysis_graphs g ON g.session_id=d.session_id AND g.graph_id=d.graph_id
UNION ALL
SELECT a.session_id AS session_id,
 v.graph_id AS graph_id,
 CONCAT('comparison-',v.series_id) AS series_id,
 v.sort_order AS sort_order,
 CONCAT(s.batch_name,' · ',v.label) AS label,
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
 TIMESTAMPADD(SECOND,TIMESTAMPDIFF(SECOND,s.pitched_at,v.sample_at),a.pitched_at) AS sample_at,
 a.pitched_at AS basis_pitched_at,
 v.source_observation_revision_id AS source_observation_revision_id,
 v.basis_revision_key AS basis_revision_key,
 v.actual_value AS actual_value,
 v.range_min_value AS range_min_value,
 v.range_max_value AS range_max_value,
 TIMESTAMPADD(SECOND,TIMESTAMPDIFF(SECOND,s.pitched_at,v.measured_at),a.pitched_at) AS measured_at,
 v.sample_count AS sample_count,
 TIMESTAMPADD(SECOND,TIMESTAMPDIFF(SECOND,s.pitched_at,v.window_started_at),a.pitched_at) AS window_started_at,
 TIMESTAMPADD(SECOND,TIMESTAMPDIFF(SECOND,s.pitched_at,v.window_ended_at),a.pitched_at) AS window_ended_at,
 v.requested_window_seconds AS requested_window_seconds,
 v.coverage_seconds AS coverage_seconds,
 v.value_source_kind AS value_source_kind,
 v.value_status AS value_status,
 v.standard_basis_met AS standard_basis_met,
 v.value_status_display AS value_status_display,
 '#ef6c00' AS line_color,
 '6 3' AS line_dasharray,
 CONCAT(s.batch_name,' · ',v.basis_display) AS basis_display,
 v.coverage_fraction AS coverage_fraction FROM v_active_session a JOIN v_graph_display_selection choice ON choice.source_kind='session' JOIN v_all_session s ON s.session_id=choice.reference_session_id JOIN v_session_analysis_series v ON v.session_id=s.session_id;









CREATE OR REPLACE VIEW v_session_analysis_graph_extents AS
SELECT g.session_id,g.graph_id,g.display_decimals,g.y_axis_include_zero,
       MIN(q.value_min) AS data_min,MAX(q.value_max) AS data_max
FROM session_analysis_graphs g
LEFT JOIN (
  SELECT v.session_id,v.graph_id,CASE WHEN gs.band_model='none' THEN v.actual_value ELSE COALESCE(v.range_min_value,v.actual_value) END AS value_min,CASE WHEN gs.band_model='none' THEN v.actual_value ELSE COALESCE(v.range_max_value,v.actual_value) END AS value_max
  FROM analysis_series_values v JOIN v_all_session basis ON basis.session_id=v.session_id AND basis.pitched_at=v.basis_pitched_at JOIN session_analysis_graph_series gs ON gs.session_id=v.session_id AND gs.graph_id=v.graph_id AND gs.series_id=v.series_id
  UNION ALL SELECT session_id,graph_id,actual_value,actual_value FROM v_session_hourly_analysis_series
  UNION ALL SELECT session_id,graph_id,actual_value,actual_value FROM v_graph_reference_analysis_series
  UNION ALL
  SELECT r.session_id,r.graph_id,COALESCE(r.minimum_value,r.maximum_value) AS value_min,COALESCE(r.maximum_value,r.minimum_value) AS value_max
  FROM v_session_analysis_requirements r
  WHERE r.minimum_value IS NOT NULL OR r.maximum_value IS NOT NULL
) q ON q.session_id=g.session_id AND q.graph_id=g.graph_id
WHERE g.enabled=1
GROUP BY g.session_id,g.graph_id,g.display_decimals,g.y_axis_include_zero;









CREATE OR REPLACE VIEW v_session_analysis_graph_axes AS
SELECT z.session_id,z.graph_id,
       CASE WHEN z.fixed_min IS NOT NULL THEN z.fixed_min WHEN z.y_axis_include_zero=1 AND z.base_min=0 THEN 0 ELSE FLOOR((z.base_min-z.tick_step*0.30)/z.tick_step)*z.tick_step END AS y_axis_min,
       CASE WHEN z.fixed_max IS NOT NULL THEN z.fixed_max ELSE CEIL((z.base_max+z.tick_step*0.30)/z.tick_step)*z.tick_step END AS y_axis_max,
       z.tick_step AS y_axis_tick_step
FROM (
 SELECT y.*,CASE WHEN y.normalized_step<=1 THEN y.magnitude WHEN y.normalized_step<=2 THEN 2*y.magnitude WHEN y.normalized_step<=5 THEN 5*y.magnitude ELSE 10*y.magnitude END AS tick_step
 FROM (
  SELECT x.*,POW(10,FLOOR(LOG10(x.rough_step))) AS magnitude,x.rough_step/POW(10,FLOOR(LOG10(x.rough_step))) AS normalized_step
  FROM (
   SELECT b.*,GREATEST((b.base_max-b.base_min)/5,POW(10,-b.display_decimals)) AS rough_step
   FROM (
    SELECT e.*,g.y_axis_min AS fixed_min,g.y_axis_max AS fixed_max,
           COALESCE(g.y_axis_min,CASE WHEN e.y_axis_include_zero=1 THEN LEAST(0,COALESCE(e.data_min,0)) ELSE COALESCE(e.data_min,0) END) AS base_min,
           COALESCE(g.y_axis_max,GREATEST(COALESCE(g.y_axis_min,0),CASE WHEN e.y_axis_include_zero=1 THEN GREATEST(0,COALESCE(e.data_max,0)) ELSE COALESCE(e.data_max,0) END)) AS base_max
    FROM v_session_analysis_graph_extents e JOIN session_analysis_graphs g ON g.session_id=e.session_id AND g.graph_id=e.graph_id
   ) b
  ) x
 ) y
) z;









CREATE OR REPLACE VIEW v_session_analysis_graphs AS
SELECT g.session_id,g.graph_id,g.sort_order,g.label,g.description,g.unit,g.display_decimals,
       ax.y_axis_min,ax.y_axis_max,ax.y_axis_tick_step,t.x_axis_started_at,t.x_axis_ended_at,t.x_axis_start_display,t.x_axis_end_display,g.y_axis_include_zero,g.x_axis_mode,g.enabled,
       g.show_biological_bands,g.show_process_markers,g.show_criterion_markers,g.gap_policy,g.created_at
FROM session_analysis_graphs g
LEFT JOIN v_session_analysis_graph_axes ax ON ax.session_id=g.session_id AND ax.graph_id=g.graph_id
JOIN v_session_graph_time_axis t ON t.session_id=g.session_id
WHERE g.enabled=1;









CREATE OR REPLACE VIEW v_active_analysis_graph_extents AS
SELECT e.* FROM v_session_analysis_graph_extents e JOIN v_active_session a ON a.session_id=e.session_id;









CREATE OR REPLACE VIEW v_active_analysis_graph_axes AS
SELECT e.* FROM v_session_analysis_graph_axes e JOIN v_active_session a ON a.session_id=e.session_id;









CREATE OR REPLACE VIEW v_active_analysis_graphs AS
SELECT e.* FROM v_session_analysis_graphs e JOIN v_active_session a ON a.session_id=e.session_id;









CREATE OR REPLACE VIEW v_active_analysis_biological_markers AS
SELECT g.session_id,g.graph_id,b.phase_id,CONVERT(b.phase_id USING utf8mb4) AS label,r.started_at,r.ended_at
FROM session_analysis_graphs g
JOIN biological_visits b ON b.session_id=g.session_id
JOIN v_biological_visit_timing r ON r.visit_id=b.visit_id
WHERE g.enabled=1 AND g.show_biological_bands=1;









CREATE OR REPLACE VIEW v_active_analysis_process_markers AS
SELECT g.session_id,g.graph_id,p.process_id,CONVERT(p.process_id USING utf8mb4) AS label,r.started_at,r.ended_at
FROM session_analysis_graphs g
JOIN process_visits p ON p.session_id=g.session_id
JOIN v_process_visit_timing r ON r.visit_id=p.visit_id
WHERE g.enabled=1 AND g.show_process_markers=1;









-- p23 structured verification read-models ------------------------------------
CREATE OR REPLACE VIEW v_current_verification_test_result AS
SELECT x.result_id,x.run_id,x.test_id,x.result_status,x.observed_at,x.executor,x.note,x.evidence_ref,x.created_at,
       r.application_version,r.run_type,r.environment,r.source,r.started_at,r.completed_at,r.overall_status
FROM (
  SELECT tr.*,ROW_NUMBER() OVER(PARTITION BY tr.test_id ORDER BY tr.observed_at DESC,tr.created_at DESC,tr.result_id DESC) AS rn
  FROM verification_test_results tr
) x
JOIN verification_test_runs r ON r.run_id=x.run_id
WHERE x.rn=1;









CREATE OR REPLACE VIEW v_verification_definition_status AS
SELECT d.verification_id,d.verification_type,d.title,d.acceptance_criterion,
       SUM(CASE WHEN l.required=1 THEN 1 ELSE 0 END) AS required_test_count,
       SUM(CASE WHEN l.required=1 AND c.result_status='pass' THEN 1 ELSE 0 END) AS pass_count,
       SUM(CASE WHEN l.required=1 AND c.result_status='fail' THEN 1 ELSE 0 END) AS fail_count,
       SUM(CASE WHEN l.required=1 AND c.result_status='blocked' THEN 1 ELSE 0 END) AS blocked_count,
       SUM(CASE WHEN l.required=1 AND (c.test_id IS NULL OR c.result_status='not_run') THEN 1 ELSE 0 END) AS not_run_count,
       CASE
         WHEN SUM(CASE WHEN l.required=1 THEN 1 ELSE 0 END)=0 THEN 'unlinked'
         WHEN SUM(CASE WHEN l.required=1 AND c.result_status='fail' THEN 1 ELSE 0 END)>0 THEN 'fail'
         WHEN SUM(CASE WHEN l.required=1 AND c.result_status='blocked' THEN 1 ELSE 0 END)>0 THEN 'blocked'
         WHEN SUM(CASE WHEN l.required=1 AND c.result_status='pass' THEN 1 ELSE 0 END)=SUM(CASE WHEN l.required=1 THEN 1 ELSE 0 END) THEN 'pass'
         ELSE 'not_run'
       END AS verification_status
FROM verification_definitions d
LEFT JOIN verification_test_links l ON l.verification_id=d.verification_id
LEFT JOIN v_current_verification_test_result c ON c.test_id=l.test_id
WHERE d.status='active'
GROUP BY d.verification_id,d.verification_type,d.title,d.acceptance_criterion;









CREATE OR REPLACE VIEW v_requirement_verification_status AS
SELECT r.requirement_id,r.document_id,r.requirement_class,r.statement,r.source_ref,
       COUNT(l.verification_id) AS verification_count,
       SUM(CASE WHEN v.verification_status='pass' THEN 1 ELSE 0 END) AS pass_count,
       SUM(CASE WHEN v.verification_status='fail' THEN 1 ELSE 0 END) AS fail_count,
       SUM(CASE WHEN v.verification_status='blocked' THEN 1 ELSE 0 END) AS blocked_count,
       SUM(CASE WHEN v.verification_status IN ('not_run','unlinked') THEN 1 ELSE 0 END) AS pending_count,
       CASE
         WHEN COUNT(l.verification_id)=0 THEN 'unlinked'
         WHEN SUM(CASE WHEN v.verification_status='fail' THEN 1 ELSE 0 END)>0 THEN 'fail'
         WHEN SUM(CASE WHEN v.verification_status='blocked' THEN 1 ELSE 0 END)>0 THEN 'blocked'
         WHEN SUM(CASE WHEN v.verification_status='pass' THEN 1 ELSE 0 END)=COUNT(l.verification_id) THEN 'pass'
         ELSE 'not_run'
       END AS verification_status
FROM verification_requirements_catalog r
LEFT JOIN verification_requirement_links l ON l.requirement_id=r.requirement_id AND l.required=1
LEFT JOIN v_verification_definition_status v ON v.verification_id=l.verification_id
WHERE r.status='active'
GROUP BY r.requirement_id,r.document_id,r.requirement_class,r.statement,r.source_ref;









CREATE OR REPLACE VIEW v_verification_summary AS
SELECT t.test_type,
       COUNT(*) AS test_count,
       SUM(CASE WHEN c.result_status='pass' THEN 1 ELSE 0 END) AS pass_count,
       SUM(CASE WHEN c.result_status='fail' THEN 1 ELSE 0 END) AS fail_count,
       SUM(CASE WHEN c.result_status='blocked' THEN 1 ELSE 0 END) AS blocked_count,
       SUM(CASE WHEN c.test_id IS NULL OR c.result_status='not_run' THEN 1 ELSE 0 END) AS not_run_count,
       MAX(c.observed_at) AS latest_observed_at
FROM verification_tests t
LEFT JOIN v_current_verification_test_result c ON c.test_id=t.test_id
WHERE t.status='active'
GROUP BY t.test_type;









CREATE OR REPLACE VIEW v_verification_uat_pending AS
SELECT t.test_id,t.title,t.description,t.method_type,t.implementation_ref,
       COALESCE(c.result_status,'not_run') AS current_status,c.observed_at,c.executor,c.note,c.evidence_ref
FROM verification_tests t
LEFT JOIN v_current_verification_test_result c ON c.test_id=t.test_id
WHERE t.status='active' AND t.test_type='UAT' AND COALESCE(c.result_status,'not_run')<>'pass';









CREATE OR REPLACE VIEW v_verification_unlinked_items AS
SELECT 'requirement' AS item_type,r.requirement_id AS item_id,r.statement AS item_label
FROM verification_requirements_catalog r
LEFT JOIN verification_requirement_links l ON l.requirement_id=r.requirement_id
WHERE r.status='active'
GROUP BY r.requirement_id,r.statement
HAVING COUNT(l.verification_id)=0
UNION ALL
SELECT 'verification',d.verification_id,d.title
FROM verification_definitions d
LEFT JOIN verification_test_links l ON l.verification_id=d.verification_id
WHERE d.status='active'
GROUP BY d.verification_id,d.title
HAVING COUNT(l.test_id)=0;









CREATE OR REPLACE VIEW v_verification_test_history AS
SELECT tr.result_id,tr.run_id,tr.test_id,t.test_type,t.title,tr.result_status,tr.observed_at,tr.executor,tr.note,tr.evidence_ref,
       r.application_version,r.run_type,r.environment,r.source,r.started_at,r.completed_at,r.overall_status
FROM verification_test_results tr
JOIN verification_tests t ON t.test_id=tr.test_id
JOIN verification_test_runs r ON r.run_id=tr.run_id;









CREATE OR REPLACE VIEW v_criterion_default_operator_policy AS
SELECT cm.metric_id,cm.model_id,1 AS exception_allowed,
       CONCAT('[',COALESCE(GROUP_CONCAT(CONCAT('"',p.parameter_id,'"') ORDER BY p.sort_order SEPARATOR ','),''),']') AS correctable_parameters_json
FROM criterion_metric_models cm
LEFT JOIN metric_runtime_rules mr ON mr.metric_id=cm.metric_id
LEFT JOIN criterion_model_parameters p ON p.model_id=cm.model_id AND (p.parameter_id<>'maximum_age_minutes' OR mr.freshness_mode<>'not_applicable')
GROUP BY cm.metric_id,cm.model_id;









CREATE OR REPLACE VIEW v_session_analysis_axis_ticks AS
SELECT a.session_id,a.graph_id,a.y_axis_min+d.seq*a.y_axis_tick_step AS tick_value,
       REPLACE(REPLACE(FORMAT(a.y_axis_min+d.seq*a.y_axis_tick_step,g.display_decimals) COLLATE utf8mb4_unicode_ci,',',''),'.',',') AS axis_label
FROM v_session_analysis_graph_axes a JOIN session_analysis_graphs g ON g.session_id=a.session_id AND g.graph_id=a.graph_id
JOIN seq_0_to_60 d ON a.y_axis_min+d.seq*a.y_axis_tick_step<=a.y_axis_max+a.y_axis_tick_step/1000;








CREATE OR REPLACE VIEW v_session_overview_axis_ticks AS
SELECT a.session_id,a.graph_id,a.y_axis_min+d.seq*a.y_axis_tick_step AS tick_value,
       REPLACE(REPLACE(FORMAT(a.y_axis_min+d.seq*a.y_axis_tick_step,CASE a.graph_id WHEN 'sg' THEN 4 WHEN 'temperature' THEN 1 ELSE 2 END) COLLATE utf8mb4_unicode_ci,',',''),'.',',') AS axis_label
FROM v_session_overview_graph_axes a JOIN seq_0_to_60 d ON a.y_axis_min+d.seq*a.y_axis_tick_step<=a.y_axis_max+a.y_axis_tick_step/1000;









CREATE OR REPLACE VIEW v_session_biological_exception_read_model AS
SELECT x.*,c.label,e.candidate_phase_id AS owner_id,
       DATE_FORMAT(CONVERT_TZ(x.created_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS created_display,
       CASE x.action WHEN 'register' THEN 'Registrert' WHEN 'withdraw' THEN 'Trukket tilbake' END COLLATE utf8mb4_unicode_ci AS action_display,
       CASE x.exception_type WHEN 'akseptert_avvik' THEN 'Akseptert avvik' WHEN 'ikke_relevant' THEN 'Ikke relevant' WHEN 'ugyldig_vurderingsgrunnlag' THEN 'Ugyldig vurderingsgrunnlag' ELSE '–' END COLLATE utf8mb4_unicode_ci AS exception_type_display,
       COALESCE(x.note,'–') AS note_display
FROM biological_criterion_exceptions x JOIN biological_evaluations e ON e.evaluation_id=x.evaluation_id
JOIN session_biological_criteria c ON c.session_id=x.session_id AND c.phase_id=x.phase_id AND c.criterion_id=x.criterion_id;









CREATE OR REPLACE VIEW v_session_history AS
SELECT h.*,
       CASE WHEN h.archive_path IS NOT NULL THEN CONCAT('/local/gjaeringsassistent/exports/',SUBSTRING_INDEX(h.archive_path,'/',-1)) ELSE NULL END AS archive_url,
       CASE WHEN h.template_path IS NOT NULL THEN CONCAT('/local/gjaeringsassistent/exports/',SUBSTRING_INDEX(h.template_path,'/',-1)) ELSE NULL END AS template_url,
       CASE WHEN h.report_path IS NOT NULL THEN CONCAT('/local/gjaeringsassistent/exports/',SUBSTRING_INDEX(h.report_path,'/',-1)) ELSE NULL END AS report_url
FROM (SELECT s.session_id,s.batch_name,COALESCE((SELECT t.value_at FROM v_current_session_timing t WHERE t.session_id=s.session_id AND t.timing_field='pitched_at' LIMIT 1),s.pitched_at) AS pitched_at,s.pitched_at AS original_pitched_at,s.is_demo,sts.template_version_id,tv.name AS template_name,tv.version_label,CASE WHEN EXISTS(SELECT 1 FROM session_release_events rr WHERE rr.session_id=s.session_id) THEN 'released' ELSE (SELECT e.lifecycle FROM session_lifecycle_events e WHERE e.session_id=s.session_id ORDER BY e.occurred_at DESC,e.created_at DESC LIMIT 1) END AS lifecycle,(SELECT e.occurred_at FROM session_lifecycle_events e WHERE e.session_id=s.session_id AND e.lifecycle='completed' ORDER BY e.occurred_at DESC LIMIT 1) AS completed_at,(SELECT r.released_at FROM session_release_events r WHERE r.session_id=s.session_id ORDER BY r.released_at DESC LIMIT 1) AS released_at,(SELECT x.archive_path FROM session_exports x WHERE x.session_id=s.session_id AND x.export_kind='completed_archive' AND x.status='verified' ORDER BY x.attempt_no DESC LIMIT 1) AS archive_path,(SELECT x.archive_sha256 FROM session_exports x WHERE x.session_id=s.session_id AND x.export_kind='completed_archive' AND x.status='verified' ORDER BY x.attempt_no DESC LIMIT 1) AS archive_sha256,(SELECT x.report_path FROM session_exports x WHERE x.session_id=s.session_id AND x.export_kind='completed_archive' AND x.status='verified' ORDER BY x.attempt_no DESC LIMIT 1) AS report_path,(SELECT x.template_path FROM session_exports x WHERE x.session_id=s.session_id AND x.export_kind='completed_archive' AND x.status='verified' ORDER BY x.attempt_no DESC LIMIT 1) AS template_path FROM sessions s LEFT JOIN session_template_snapshots sts ON sts.session_id=s.session_id LEFT JOIN template_versions tv ON tv.version_id=sts.template_version_id) h;










CREATE OR REPLACE VIEW v_dashboard_reference_options AS
SELECT 'none' AS source_kind,'' AS reference_id,'Ingen' AS label
UNION ALL SELECT 'reference',profile_id,name FROM demo_reference_profiles WHERE selectable=1
UNION ALL SELECT 'session',s.session_id,s.batch_name FROM v_all_session s WHERE (s.lifecycle='completed' OR EXISTS(SELECT 1 FROM archive_imports i WHERE i.session_id=s.session_id)) AND COALESCE((SELECT visible FROM archive_visibility_events v WHERE v.session_id=s.session_id ORDER BY event_seq DESC LIMIT 1),1)=1;








CREATE OR REPLACE VIEW v_dashboard_demo_options AS
SELECT profile_id,name,span_seconds,og FROM demo_reference_profiles WHERE selectable=1;








CREATE OR REPLACE VIEW v_dashboard_graph_view_options AS
SELECT 'interval' AS option_kind,300 AS value_number,'5 minutter' AS label UNION ALL SELECT 'interval',900,'15 minutter' UNION ALL SELECT 'interval',1800,'30 minutter' UNION ALL SELECT 'interval',3600,'1 time'
UNION ALL SELECT 'window',NULL,'Hele gjæringen' UNION ALL SELECT 'window',24,'Siste 24 timer' UNION ALL SELECT 'window',48,'Siste 48 timer' UNION ALL SELECT 'window',168,'Siste 7 døgn';








CREATE OR REPLACE VIEW v_session_display_measurement_series AS
SELECT m.session_id,MIN(m.bucket_at) AS bucket_at,MAX(m.interval_ended_at) AS interval_ended_at,SUM(m.sample_count) AS sample_count,MIN(m.sg_min) AS sg_min,SUM(CAST(m.sg_mean AS DECIMAL(24,9))*m.sample_count)/SUM(m.sample_count) AS sg_mean,
CASE WHEN choice.interval_seconds=300 THEN MAX(m.sg_median) ELSE NULL END AS sg_median,
CASE WHEN choice.interval_seconds=300 THEN MAX(m.sg_value) ELSE SUM(CAST(m.sg_mean AS DECIMAL(24,9))*m.sample_count)/SUM(m.sample_count) END AS sg_value,
MAX(m.sg_max) AS sg_max,MIN(m.temperature_min_c) AS temperature_min_c,AVG(m.temperature_mean_c) AS temperature_mean_c,MAX(m.temperature_max_c) AS temperature_max_c,MIN(m.pressure_min_bar) AS pressure_min_bar,AVG(m.pressure_mean_bar) AS pressure_mean_bar,MAX(m.pressure_max_bar) AS pressure_max_bar,m.source_kind,
CASE WHEN choice.interval_seconds=300 THEN MAX(m.source_display) ELSE CONCAT('Samlet detaljdata · ',choice.interval_seconds/60,' minutter · SG middelverdi og min/maks') END AS source_display,choice.interval_seconds AS interval_seconds,m.segment_id
FROM v_session_measurement_segments m JOIN v_all_session s ON s.session_id=m.session_id JOIN v_graph_display_selection choice
WHERE m.source_kind='detail_5m'
GROUP BY m.session_id,m.source_kind,m.segment_id,choice.interval_seconds,FLOOR(TIMESTAMPDIFF(SECOND,s.pitched_at,m.bucket_at)/choice.interval_seconds)
UNION ALL SELECT m.session_id,m.bucket_at,m.interval_ended_at,m.sample_count,m.sg_min,m.sg_mean,m.sg_median,m.sg_value,m.sg_max,m.temperature_min_c,m.temperature_mean_c,m.temperature_max_c,m.pressure_min_bar,m.pressure_mean_bar,m.pressure_max_bar,m.source_kind,m.source_display,m.interval_seconds,m.segment_id FROM v_session_measurement_segments m WHERE m.source_kind='ha_statistics_hourly';









CREATE OR REPLACE VIEW v_dashboard_analysis_source AS
SELECT * FROM v_primary_analysis_source UNION ALL SELECT s.*,'comparison',CASE WHEN s.value_source_kind='ha_statistics_hourly' THEN 3600 ELSE 300 END FROM v_graph_reference_analysis_series s;








CREATE OR REPLACE VIEW v_dashboard_analysis_segments AS
SELECT q.*,SUM(q.new_segment) OVER(PARTITION BY q.session_id,q.graph_id,q.series_id ORDER BY q.sample_at) AS segment_id
FROM(SELECT x.*,CASE WHEN x.previous_at IS NULL OR TIMESTAMPDIFF(SECOND,x.previous_at,x.sample_at)>x.interval_seconds THEN 1 ELSE 0 END AS new_segment
FROM(SELECT s.*,LAG(s.sample_at) OVER(PARTITION BY s.session_id,s.graph_id,s.series_id ORDER BY s.sample_at) AS previous_at FROM v_dashboard_analysis_source s) x) q;








CREATE OR REPLACE VIEW v_dashboard_analysis_series AS
SELECT q.* FROM(SELECT s.*,
ROW_NUMBER() OVER(PARTITION BY s.session_id,s.graph_id,s.series_id,s.segment_id,FLOOR(UNIX_TIMESTAMP(s.sample_at)/c.interval_seconds) ORDER BY s.sample_at) AS first_rank,
ROW_NUMBER() OVER(PARTITION BY s.session_id,s.graph_id,s.series_id,s.segment_id,FLOOR(UNIX_TIMESTAMP(s.sample_at)/c.interval_seconds) ORDER BY s.sample_at DESC) AS last_rank,
ROW_NUMBER() OVER(PARTITION BY s.session_id,s.graph_id,s.series_id,s.segment_id,FLOOR(UNIX_TIMESTAMP(s.sample_at)/c.interval_seconds) ORDER BY s.actual_value,s.sample_at) AS min_rank,
ROW_NUMBER() OVER(PARTITION BY s.session_id,s.graph_id,s.series_id,s.segment_id,FLOOR(UNIX_TIMESTAMP(s.sample_at)/c.interval_seconds) ORDER BY s.actual_value DESC,s.sample_at) AS max_rank
FROM v_dashboard_analysis_segments s JOIN v_graph_display_selection c JOIN v_session_graph_time_axis t ON t.session_id=s.session_id WHERE s.sample_at IS NULL OR s.sample_at BETWEEN t.x_axis_started_at AND t.x_axis_ended_at) q
WHERE q.first_rank=1 OR q.last_rank=1 OR q.min_rank=1 OR q.max_rank=1;








CREATE OR REPLACE VIEW v_dashboard_analysis_latest AS
SELECT q.session_id,q.graph_id,q.series_id,q.sort_order,q.label,q.actual_value,q.measured_at,
CONCAT(q.label,' · ',COALESCE(q.actual_value_display,'Mangler målegrunnlag'),CASE WHEN q.measured_at IS NULL THEN '' ELSE CONCAT(' · målt ',DATE_FORMAT(CONVERT_TZ(q.measured_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i')) END) COLLATE utf8mb4_unicode_ci AS latest_value_display
FROM(SELECT s.*,ROW_NUMBER() OVER(PARTITION BY s.session_id,s.graph_id,s.series_id ORDER BY s.sample_at DESC) AS latest_rank FROM v_dashboard_analysis_source s) q WHERE q.latest_rank=1;








CREATE OR REPLACE VIEW v_dashboard_graph_labels AS
SELECT c.selection_seq,
'Detaljdata lagres hvert 5. minutt. Timesstatistikk fra HA beholder sin oppløsning.' AS graph_basis_display,
COALESCE((SELECT GROUP_CONCAT(DISTINCT source_display ORDER BY source_display SEPARATOR ' · ') FROM v_session_measurement_series m JOIN v_active_session a ON a.session_id=m.session_id),'Ingen måledata') AS measurement_source_labels,
CASE c.source_kind WHEN 'reference' THEN (SELECT name FROM demo_reference_profiles d WHERE d.profile_id=c.reference_profile_id) WHEN 'session' THEN (SELECT batch_name FROM sessions s WHERE s.session_id=c.reference_session_id) ELSE NULL END AS comparison_display
FROM v_graph_display_selection c;









CREATE OR REPLACE VIEW v_report_graph_time_axis AS
SELECT s.session_id,s.pitched_at AS x_axis_started_at,s.domain_now AS x_axis_ended_at,DATE_FORMAT(CONVERT_TZ(s.pitched_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS x_axis_start_display,DATE_FORMAT(CONVERT_TZ(s.domain_now,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i') AS x_axis_end_display FROM v_all_session s LEFT JOIN(SELECT session_id,MAX(bucket_at) AS last_at FROM v_session_measurement_series GROUP BY session_id) m ON m.session_id=s.session_id;









CREATE OR REPLACE VIEW v_report_overview_graph_extents AS
SELECT q.session_id,q.graph_id,MIN(q.value_num) AS data_min,MAX(q.value_num) AS data_max,MAX(q.include_zero) AS include_zero
FROM (
  SELECT m.session_id,'sg' AS graph_id,CAST(m.sg_min AS DECIMAL(24,9)) AS value_num,0 AS include_zero FROM v_session_measurement_series m WHERE m.sg_min IS NOT NULL
  UNION ALL SELECT m.session_id,'sg',CAST(m.sg_max AS DECIMAL(24,9)),0 FROM v_session_measurement_series m WHERE m.sg_max IS NOT NULL
  UNION ALL SELECT t.session_id,'sg',CAST(t.expected_fg_min AS DECIMAL(24,9)),0 FROM v_current_fermentation_target t WHERE t.expected_fg_min IS NOT NULL
  UNION ALL SELECT t.session_id,'sg',CAST(t.expected_fg_max AS DECIMAL(24,9)),0 FROM v_current_fermentation_target t WHERE t.expected_fg_max IS NOT NULL
  UNION ALL SELECT o.session_id,'sg',CAST(o.corrected_sg AS DECIMAL(24,9)),0 FROM v_current_observation_revision o WHERE o.status='active' AND o.corrected_sg IS NOT NULL
  UNION ALL SELECT m.session_id,'temperature',CAST(m.temperature_min_c AS DECIMAL(24,9)),0 FROM v_session_measurement_series m WHERE m.temperature_min_c IS NOT NULL
  UNION ALL SELECT m.session_id,'temperature',CAST(m.temperature_max_c AS DECIMAL(24,9)),0 FROM v_session_measurement_series m WHERE m.temperature_max_c IS NOT NULL
  UNION ALL SELECT o.session_id,'temperature',CAST(o.manual_temperature_c AS DECIMAL(24,9)),0 FROM v_current_observation_revision o WHERE o.status='active' AND o.manual_temperature_c IS NOT NULL
  UNION ALL SELECT o.session_id,'temperature',CAST(o.cooler_setpoint_c AS DECIMAL(24,9)),0 FROM v_current_observation_revision o WHERE o.status='active' AND o.cooler_setpoint_c IS NOT NULL
  UNION ALL SELECT t.session_id,'temperature',CAST(e.target_value AS DECIMAL(24,9)),0 FROM session_process_targets t JOIN session_process_target_exact e ON e.session_id=t.session_id AND e.process_id=t.process_id AND e.target_id=t.target_id JOIN process_visits pv ON pv.session_id=t.session_id AND pv.process_id=t.process_id WHERE t.metric_id='beer_temperature_c'
  UNION ALL SELECT t.session_id,'temperature',CAST(r.minimum_value AS DECIMAL(24,9)),0 FROM session_process_targets t JOIN session_process_target_range r ON r.session_id=t.session_id AND r.process_id=t.process_id AND r.target_id=t.target_id JOIN process_visits pv ON pv.session_id=t.session_id AND pv.process_id=t.process_id WHERE t.metric_id='beer_temperature_c' AND r.minimum_value IS NOT NULL
  UNION ALL SELECT t.session_id,'temperature',CAST(r.maximum_value AS DECIMAL(24,9)),0 FROM session_process_targets t JOIN session_process_target_range r ON r.session_id=t.session_id AND r.process_id=t.process_id AND r.target_id=t.target_id JOIN process_visits pv ON pv.session_id=t.session_id AND pv.process_id=t.process_id WHERE t.metric_id='beer_temperature_c' AND r.maximum_value IS NOT NULL
  UNION ALL SELECT m.session_id,'pressure',CAST(m.pressure_min_bar AS DECIMAL(24,9)),0 FROM v_session_measurement_series m WHERE m.pressure_min_bar IS NOT NULL
  UNION ALL SELECT m.session_id,'pressure',CAST(m.pressure_max_bar AS DECIMAL(24,9)),0 FROM v_session_measurement_series m WHERE m.pressure_max_bar IS NOT NULL
  UNION ALL SELECT o.session_id,'pressure',CAST(o.pressure_bar AS DECIMAL(24,9)),0 FROM v_current_observation_revision o WHERE o.status='active' AND o.pressure_bar IS NOT NULL
  UNION ALL SELECT t.session_id,'pressure',CAST(e.target_value AS DECIMAL(24,9)),0 FROM session_process_targets t JOIN session_process_target_exact e ON e.session_id=t.session_id AND e.process_id=t.process_id AND e.target_id=t.target_id JOIN process_visits pv ON pv.session_id=t.session_id AND pv.process_id=t.process_id WHERE t.metric_id='pressure_bar'
  UNION ALL SELECT t.session_id,'pressure',CAST(r.minimum_value AS DECIMAL(24,9)),0 FROM session_process_targets t JOIN session_process_target_range r ON r.session_id=t.session_id AND r.process_id=t.process_id AND r.target_id=t.target_id JOIN process_visits pv ON pv.session_id=t.session_id AND pv.process_id=t.process_id WHERE t.metric_id='pressure_bar' AND r.minimum_value IS NOT NULL
  UNION ALL SELECT t.session_id,'pressure',CAST(r.maximum_value AS DECIMAL(24,9)),0 FROM session_process_targets t JOIN session_process_target_range r ON r.session_id=t.session_id AND r.process_id=t.process_id AND r.target_id=t.target_id JOIN process_visits pv ON pv.session_id=t.session_id AND pv.process_id=t.process_id WHERE t.metric_id='pressure_bar' AND r.maximum_value IS NOT NULL
) q
WHERE q.value_num IS NOT NULL
GROUP BY q.session_id,q.graph_id;









CREATE OR REPLACE VIEW v_report_overview_graph_axes AS
SELECT z.session_id,z.graph_id,t.x_axis_started_at,t.x_axis_ended_at,t.x_axis_start_display,t.x_axis_end_display,p.band_model,p.band_description,p.band_opacity,
       FLOOR((z.base_min-z.tick_step*0.30)/z.tick_step)*z.tick_step AS y_axis_min,
       CEIL((z.base_max+z.tick_step*0.30)/z.tick_step)*z.tick_step AS y_axis_max,
       z.tick_step AS y_axis_tick_step
FROM (
  SELECT y.*,
         CASE WHEN y.normalized_step<=1 THEN 1*y.magnitude WHEN y.normalized_step<=2 THEN 2*y.magnitude WHEN y.normalized_step<=5 THEN 5*y.magnitude ELSE 10*y.magnitude END AS tick_step
  FROM (
    SELECT x.*,POW(10,FLOOR(LOG10(x.rough_step))) AS magnitude,x.rough_step/POW(10,FLOOR(LOG10(x.rough_step))) AS normalized_step
    FROM (
      SELECT e.session_id,e.graph_id,
             CASE WHEN e.include_zero=1 THEN LEAST(0,e.data_min) ELSE e.data_min END AS base_min,
             CASE WHEN e.include_zero=1 THEN GREATEST(0,e.data_max) ELSE e.data_max END AS base_max,
             GREATEST(
               (CASE WHEN e.include_zero=1 THEN GREATEST(0,e.data_max) ELSE e.data_max END - CASE WHEN e.include_zero=1 THEN LEAST(0,e.data_min) ELSE e.data_min END)/5,
               CASE e.graph_id WHEN 'sg' THEN 0.0002 WHEN 'temperature' THEN 0.2 WHEN 'pressure' THEN 0.02 ELSE 0.01 END
             ) AS rough_step
      FROM v_report_overview_graph_extents e
    ) x
  ) y
) z
JOIN v_report_graph_time_axis t ON t.session_id=z.session_id
JOIN session_overview_graph_policy p ON p.session_id=z.session_id AND p.graph_id=z.graph_id;









CREATE OR REPLACE VIEW v_report_overview_axis_ticks AS
SELECT a.session_id,a.graph_id,a.y_axis_min+d.seq*a.y_axis_tick_step AS tick_value,
       REPLACE(REPLACE(FORMAT(a.y_axis_min+d.seq*a.y_axis_tick_step,CASE a.graph_id WHEN 'sg' THEN 4 WHEN 'temperature' THEN 1 ELSE 2 END) COLLATE utf8mb4_unicode_ci,',',''),'.',',') AS axis_label
FROM v_report_overview_graph_axes a JOIN seq_0_to_60 d ON a.y_axis_min+d.seq*a.y_axis_tick_step<=a.y_axis_max+a.y_axis_tick_step/1000;









CREATE OR REPLACE VIEW v_report_analysis_graph_extents AS
SELECT g.session_id,g.graph_id,g.display_decimals,g.y_axis_include_zero,
       MIN(q.value_min) AS data_min,MAX(q.value_max) AS data_max
FROM session_analysis_graphs g
LEFT JOIN (
  SELECT v.session_id,v.graph_id,CASE WHEN gs.band_model='none' THEN v.actual_value ELSE COALESCE(v.range_min_value,v.actual_value) END AS value_min,CASE WHEN gs.band_model='none' THEN v.actual_value ELSE COALESCE(v.range_max_value,v.actual_value) END AS value_max
  FROM analysis_series_values v JOIN v_all_session basis ON basis.session_id=v.session_id AND basis.pitched_at=v.basis_pitched_at JOIN session_analysis_graph_series gs ON gs.session_id=v.session_id AND gs.graph_id=v.graph_id AND gs.series_id=v.series_id
  UNION ALL SELECT session_id,graph_id,actual_value,actual_value FROM v_session_hourly_analysis_series
  UNION ALL
  SELECT r.session_id,r.graph_id,COALESCE(r.minimum_value,r.maximum_value) AS value_min,COALESCE(r.maximum_value,r.minimum_value) AS value_max
  FROM v_session_analysis_requirements r
  WHERE r.minimum_value IS NOT NULL OR r.maximum_value IS NOT NULL
) q ON q.session_id=g.session_id AND q.graph_id=g.graph_id
WHERE g.enabled=1
GROUP BY g.session_id,g.graph_id,g.display_decimals,g.y_axis_include_zero;









CREATE OR REPLACE VIEW v_report_analysis_graph_axes AS
SELECT z.session_id,z.graph_id,
       CASE WHEN z.fixed_min IS NOT NULL THEN z.fixed_min WHEN z.y_axis_include_zero=1 AND z.base_min=0 THEN 0 ELSE FLOOR((z.base_min-z.tick_step*0.30)/z.tick_step)*z.tick_step END AS y_axis_min,
       CASE WHEN z.fixed_max IS NOT NULL THEN z.fixed_max ELSE CEIL((z.base_max+z.tick_step*0.30)/z.tick_step)*z.tick_step END AS y_axis_max,
       z.tick_step AS y_axis_tick_step
FROM (
 SELECT y.*,CASE WHEN y.normalized_step<=1 THEN y.magnitude WHEN y.normalized_step<=2 THEN 2*y.magnitude WHEN y.normalized_step<=5 THEN 5*y.magnitude ELSE 10*y.magnitude END AS tick_step
 FROM (
  SELECT x.*,POW(10,FLOOR(LOG10(x.rough_step))) AS magnitude,x.rough_step/POW(10,FLOOR(LOG10(x.rough_step))) AS normalized_step
  FROM (
   SELECT b.*,GREATEST((b.base_max-b.base_min)/5,POW(10,-b.display_decimals)) AS rough_step
   FROM (
    SELECT e.*,g.y_axis_min AS fixed_min,g.y_axis_max AS fixed_max,
           COALESCE(g.y_axis_min,CASE WHEN e.y_axis_include_zero=1 THEN LEAST(0,COALESCE(e.data_min,0)) ELSE COALESCE(e.data_min,0) END) AS base_min,
           COALESCE(g.y_axis_max,GREATEST(COALESCE(g.y_axis_min,0),CASE WHEN e.y_axis_include_zero=1 THEN GREATEST(0,COALESCE(e.data_max,0)) ELSE COALESCE(e.data_max,0) END)) AS base_max
    FROM v_report_analysis_graph_extents e JOIN session_analysis_graphs g ON g.session_id=e.session_id AND g.graph_id=e.graph_id
   ) b
  ) x
 ) y
) z;









CREATE OR REPLACE VIEW v_report_analysis_graphs AS
SELECT g.session_id,g.graph_id,g.sort_order,g.label,g.description,g.unit,g.display_decimals,
       ax.y_axis_min,ax.y_axis_max,ax.y_axis_tick_step,t.x_axis_started_at,t.x_axis_ended_at,t.x_axis_start_display,t.x_axis_end_display,g.y_axis_include_zero,g.x_axis_mode,g.enabled,
       g.show_biological_bands,g.show_process_markers,g.show_criterion_markers,g.gap_policy,g.created_at
FROM session_analysis_graphs g
LEFT JOIN v_report_analysis_graph_axes ax ON ax.session_id=g.session_id AND ax.graph_id=g.graph_id
JOIN v_report_graph_time_axis t ON t.session_id=g.session_id
WHERE g.enabled=1;









CREATE OR REPLACE VIEW v_report_analysis_axis_ticks AS
SELECT a.session_id,a.graph_id,a.y_axis_min+d.seq*a.y_axis_tick_step AS tick_value,
       REPLACE(REPLACE(FORMAT(a.y_axis_min+d.seq*a.y_axis_tick_step,g.display_decimals) COLLATE utf8mb4_unicode_ci,',',''),'.',',') AS axis_label
FROM v_report_analysis_graph_axes a JOIN session_analysis_graphs g ON g.session_id=a.session_id AND g.graph_id=a.graph_id
JOIN seq_0_to_60 d ON a.y_axis_min+d.seq*a.y_axis_tick_step<=a.y_axis_max+a.y_axis_tick_step/1000;









CREATE OR REPLACE VIEW v_report_analysis_time_markers AS
SELECT g.session_id,g.graph_id,
       CASE WHEN d.day_no=0 THEN t.x_axis_started_at ELSE CONVERT_TZ(TIMESTAMP(DATE(CONVERT_TZ(t.x_axis_started_at,'+00:00','Europe/Oslo')) + INTERVAL d.day_no DAY),'Europe/Oslo','+00:00') END AS marker_at,
       d.day_no AS relative_day,
       CONCAT('+',d.day_no,' · ',DATE_FORMAT(DATE(CONVERT_TZ(t.x_axis_started_at,'+00:00','Europe/Oslo')) + INTERVAL d.day_no DAY,'%d.%m')) AS axis_label
FROM session_analysis_graphs g
JOIN v_report_graph_time_axis t ON t.session_id=g.session_id
JOIN (SELECT seq AS day_no FROM seq_0_to_10000) d ON d.day_no<=DATEDIFF(DATE(CONVERT_TZ(t.x_axis_ended_at,'+00:00','Europe/Oslo')),DATE(CONVERT_TZ(t.x_axis_started_at,'+00:00','Europe/Oslo')))
WHERE g.enabled=1;









CREATE OR REPLACE VIEW v_report_analysis_series AS
SELECT * FROM v_dashboard_analysis_segments WHERE series_role='primary';








CREATE OR REPLACE VIEW v_report_analysis_latest AS
SELECT q.session_id,q.graph_id,q.series_id,q.sort_order,q.label,q.actual_value,q.measured_at,CONCAT(q.label,' · ',COALESCE(q.actual_value_display,'Mangler målegrunnlag')) AS latest_value_display FROM(SELECT s.*,ROW_NUMBER() OVER(PARTITION BY s.session_id,s.graph_id,s.series_id ORDER BY s.sample_at DESC) AS latest_rank FROM v_primary_analysis_source s) q WHERE q.latest_rank=1;









-- Archive administration reads the same MariaDB authority as the motor.
CREATE OR REPLACE VIEW v_template_library AS
SELECT v.*,COALESCE(o.origin_kind,'own') AS origin_kind,
CASE COALESCE(o.origin_kind,'own') WHEN 'system' THEN 'Systemtemplates' WHEN 'imported' THEN 'Importerte originals' ELSE 'Egne templates' END AS origin_display,
o.original_template_id,o.original_version_id,o.import_operation_id,o.source_sha256,
(SELECT COUNT(*) FROM session_template_snapshots st JOIN template_versions tv ON tv.version_id=st.template_version_id WHERE tv.template_id=v.template_id) AS session_references,
(SELECT COUNT(*) FROM template_versions d JOIN template_versions b ON b.version_id=d.based_on_version_id WHERE b.template_id=v.template_id AND d.template_id<>v.template_id) AS derived_references,
IF(o.origin_kind='imported' AND NOT EXISTS(SELECT 1 FROM session_template_snapshots st JOIN template_versions tv ON tv.version_id=st.template_version_id WHERE tv.template_id=v.template_id) AND NOT EXISTS(SELECT 1 FROM template_versions d JOIN template_versions b ON b.version_id=d.based_on_version_id WHERE b.template_id=v.template_id AND d.template_id<>v.template_id),1,0) AS can_delete
FROM template_versions v LEFT JOIN template_origins o ON o.template_id=v.template_id;








CREATE OR REPLACE VIEW v_archive_library_sessions AS
SELECT s.*,IF(i.import_id IS NULL,'local','imported') AS archive_origin,
IF(i.import_id IS NULL,'Lokal gjæring','Importert gjæring') AS archive_origin_display,
i.original_session_id,i.template_id AS imported_template_id,
IF((s.lifecycle='completed' OR i.import_id IS NOT NULL) AND NOT EXISTS(SELECT 1 FROM v_active_session a WHERE a.session_id=s.session_id),1,0) AS can_delete,
IF(i.import_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM session_template_snapshots st JOIN template_versions tv ON tv.version_id=st.template_version_id WHERE tv.template_id=i.template_id AND st.session_id<>s.session_id) AND NOT EXISTS(SELECT 1 FROM template_versions d JOIN template_versions b ON b.version_id=d.based_on_version_id WHERE b.template_id=i.template_id AND d.template_id<>i.template_id),1,0) AS can_delete_template,
IF(i.import_id IS NOT NULL AND s.lifecycle<>'completed','Importert aktivt øyeblikksbilde','Historisk gjæring') AS snapshot_display,
COALESCE((SELECT visible FROM archive_visibility_events v WHERE v.session_id=s.session_id ORDER BY v.event_seq DESC LIMIT 1),1) AS comparison_visible,
(SELECT CONCAT('/local/gjaeringsassistent/exports/',SUBSTRING_INDEX(e.archive_path,'/',-1)) FROM session_exports e WHERE e.session_id=s.session_id AND e.export_kind='completed_archive' AND e.status='verified' ORDER BY attempt_no DESC LIMIT 1) AS archive_url,
(SELECT CONCAT('/local/gjaeringsassistent/exports/',SUBSTRING_INDEX(e.template_path,'/',-1)) FROM session_exports e WHERE e.session_id=s.session_id AND e.export_kind='completed_archive' AND e.status='verified' ORDER BY attempt_no DESC LIMIT 1) AS template_url
FROM v_all_session s LEFT JOIN archive_imports i ON i.session_id=s.session_id WHERE s.lifecycle='completed' OR i.import_id IS NOT NULL;








CREATE OR REPLACE VIEW v_archive_transfer_latest AS
SELECT e.*,
IF(e.archive_path IS NULL,NULL,CONCAT('/local/gjaeringsassistent/exports/',SUBSTRING_INDEX(e.archive_path,'/',-1))) AS archive_url,
IF(e.template_path IS NULL,NULL,CONCAT('/local/gjaeringsassistent/exports/',SUBSTRING_INDEX(e.template_path,'/',-1))) AS template_url,
IF(e.archive_path IS NULL,NULL,CONCAT('/local/gjaeringsassistent/exports/',SUBSTRING_INDEX(e.archive_path,'/',-1),'.sha')) AS archive_sha_url,
IF(e.template_path IS NULL,NULL,CONCAT('/local/gjaeringsassistent/exports/',SUBSTRING_INDEX(e.template_path,'/',-1),'.sha')) AS template_sha_url,
IF(e.report_path IS NULL,NULL,CONCAT('/local/gjaeringsassistent/exports/',SUBSTRING_INDEX(e.report_path,'/',-1))) AS report_url
FROM archive_transfer_events e WHERE NOT EXISTS(SELECT 1 FROM archive_transfer_events n WHERE n.operation_id=e.operation_id AND n.event_seq>e.event_seq);








CREATE OR REPLACE VIEW v_archive_upload_status AS
SELECT u.upload_id,u.filename,u.expected_bytes,u.expected_chunks,u.sha256,COUNT(c.chunk_no) AS received_chunks,COALESCE(SUM(OCTET_LENGTH(c.payload)),0) AS received_bytes
FROM archive_uploads u LEFT JOIN archive_upload_chunks c ON c.upload_id=u.upload_id GROUP BY u.upload_id,u.filename,u.expected_bytes,u.expected_chunks,u.sha256;









CREATE OR REPLACE VIEW v_archive_import_candidates AS
SELECT c.*,CONCAT(c.template_name,' · ',c.version_label,IF(COALESCE(c.batch_name,'')='','',CONCAT(' · ',c.batch_name)),IF(c.snapshot_kind='active_snapshot',' · Aktivt øyeblikksbilde','')) AS display_name,
IF(c.session_upload_id IS NOT NULL AND EXISTS(SELECT 1 FROM archive_uploads u WHERE u.upload_id=c.session_upload_id),1,0) AS can_import_session,
(SELECT COUNT(*) FROM archive_checksum_warnings w WHERE w.operation_id=c.operation_id AND w.upload_id IN(c.template_upload_id,c.session_upload_id)) AS warning_count
FROM archive_import_candidates c WHERE EXISTS(SELECT 1 FROM archive_uploads u WHERE u.upload_id=c.template_upload_id);









-- Reconstructed at startup and after every lifecycle/measurement transition.
CREATE OR REPLACE VIEW v_session_start_status AS
SELECT x.session_id,x.lifecycle,x.is_demo,x.last_import_cutoff_at,x.initial_target_at,x.source_started_at,
CASE WHEN x.session_id IS NULL THEN 0 WHEN x.lifecycle='completed' OR x.is_demo=1 AND x.demo_points>0 THEN 100
WHEN x.is_demo=1 THEN 0 WHEN x.source_started_at<x.initial_target_at THEN LEAST(100,GREATEST(0,COALESCE(100*TIMESTAMPDIFF(SECOND,x.source_started_at,x.last_import_cutoff_at)/NULLIF(TIMESTAMPDIFF(SECOND,x.source_started_at,x.initial_target_at),0),0))) ELSE 100 END AS progress_percent,
CASE WHEN x.session_id IS NULL THEN 'idle' WHEN x.lifecycle='completed' THEN 'completed'
 WHEN x.is_demo=1 THEN IF(x.demo_points>0,'ready','starting')
 WHEN x.source_profile_id IS NULL THEN 'error' WHEN x.is_historical=1 AND x.last_import_cutoff_at>=x.initial_target_at THEN 'ready' WHEN x.last_error IS NOT NULL THEN 'error'
 WHEN x.source_started_at<x.initial_target_at AND (x.last_import_cutoff_at IS NULL OR x.last_import_cutoff_at<x.initial_target_at) THEN 'importing' ELSE 'ready' END AS state,
CASE WHEN x.session_id IS NULL THEN 'Klar for valg av template og ny gjæring' WHEN x.lifecycle='completed' THEN 'Gjæring avsluttet'
 WHEN x.is_demo=1 THEN IF(x.demo_points>0,'Demo er startet','Laster demo')
 WHEN x.source_profile_id IS NULL THEN 'Obligatorisk målekilde mangler i databasen' WHEN x.is_historical=1 AND x.last_import_cutoff_at>=x.initial_target_at THEN CONCAT('Historisk periode ferdig behandlet · klar for etterregistrering · ',c.summary_display,IF(x.last_error IS NULL,'',CONCAT(' · importadvarsel: ',x.last_error))) WHEN x.last_error IS NOT NULL THEN x.last_error
 WHEN x.source_started_at<x.initial_target_at AND (x.last_import_cutoff_at IS NULL OR x.last_import_cutoff_at<x.initial_target_at) THEN 'Importerer målehistorikk' WHEN x.is_historical=1 THEN 'Historisk import fullført · klar for etterregistrering' ELSE 'Gjæring startet' END AS message,
UTC_TIMESTAMP(3) AS database_now
FROM (SELECT s.session_id,s.lifecycle,s.is_demo,m.source_profile_id,m.source_started_at,m.last_import_cutoff_at,m.last_error,s.is_historical,
COALESCE(s.historical_ended_at,FROM_UNIXTIME(FLOOR(UNIX_TIMESTAMP(s.created_at)/p.poll_interval_seconds)*p.poll_interval_seconds)) AS initial_target_at,
(SELECT COUNT(*) FROM measurements_5m v WHERE v.session_id=s.session_id) AS demo_points
FROM (SELECT 1 AS singleton) a LEFT JOIN v_current_session s ON 1=1 LEFT JOIN session_measurement_sources m ON m.session_id=s.session_id LEFT JOIN measurement_source_profiles p ON p.source_profile_id=m.source_profile_id) x
LEFT JOIN v_session_import_coverage c ON c.session_id=x.session_id;









CREATE OR REPLACE VIEW v_session_pitch_facts AS
SELECT s.session_id,s.pitch_mode_id,d.yeast_amount_g,l.slurry_volume_ml,l.slurry_source_batch,l.slurry_generation,
IF(d.session_id IS NOT NULL OR l.session_id IS NOT NULL,'present','invalid_configuration') AS pitch_facts_status
FROM sessions s LEFT JOIN session_dry_pitches d ON d.session_id=s.session_id LEFT JOIN session_slurry_pitches l ON l.session_id=s.session_id;








CREATE OR REPLACE VIEW v_schema_column_catalog AS
SELECT c.TABLE_NAME AS object_name,t.TABLE_TYPE AS object_type,c.COLUMN_NAME AS column_name,c.ORDINAL_POSITION AS ordinal_position,
c.COLUMN_TYPE AS column_type,c.DATA_TYPE AS data_type,c.IS_NULLABLE AS is_nullable,c.COLUMN_DEFAULT AS column_default,c.EXTRA AS extra,
a.absence_kind,a.explanation AS absence_explanation
FROM INFORMATION_SCHEMA.COLUMNS c JOIN INFORMATION_SCHEMA.TABLES t ON t.TABLE_SCHEMA=c.TABLE_SCHEMA AND t.TABLE_NAME=c.TABLE_NAME
LEFT JOIN schema_absence_semantics a ON a.object_id=CONCAT('table:',c.TABLE_NAME) AND a.column_name=c.COLUMN_NAME
WHERE c.TABLE_SCHEMA=DATABASE();










CREATE OR REPLACE VIEW v_ha_start_status_payload AS
SELECT r.projection_id,r.output_slot,
JSON_OBJECT('state',s.state,'attributes',JSON_MERGE_PATCH(
 JSON_OBJECT('phase',s.state,'message',s.message,'source','MariaDB','updated_at',DATE_FORMAT(s.database_now,'%Y-%m-%dT%H:%i:%s.%fZ'),
 'progress_percent',s.progress_percent,'availability',JSON_OBJECT('session_id',IF(s.session_id IS NULL,'not_started','present'),
 'processed_to',IF(s.last_import_cutoff_at IS NULL,'not_yet','present'),'target_import_end',IF(s.initial_target_at IS NULL,'not_applicable','present'),
 'source_started_at',IF(s.source_started_at IS NULL,'not_applicable','present'))),
 JSON_OBJECT('session_id',s.session_id,'processed_to',DATE_FORMAT(s.last_import_cutoff_at,'%Y-%m-%dT%H:%i:%s.%fZ'),
 'target_import_end',DATE_FORMAT(s.initial_target_at,'%Y-%m-%dT%H:%i:%s.%fZ'),'source_started_at',DATE_FORMAT(s.source_started_at,'%Y-%m-%dT%H:%i:%s.%fZ')))) AS ha_payload
FROM v_session_start_status s JOIN ha_projection_routes r ON r.projection_id='start_status';








CREATE OR REPLACE VIEW v_ha_runtime_context AS
SELECT s.*,sts.template_version_id AS current_template_version_id,tv.name AS current_template_name,tv.version_label AS current_version_label,
d.template_version_id AS draft_template_version_id,dtv.name AS draft_template_name,dtv.version_label AS draft_version_label,
d.expected_attenuation_display AS draft_attenuation_display,d.expected_fg_display AS draft_fg_display,
d.expected_attenuation_min_percent AS draft_attenuation_min,d.expected_attenuation_max_percent AS draft_attenuation_max,
d.expected_fg_min AS draft_fg_min,d.expected_fg_max AS draft_fg_max,
CASE WHEN s.session_id IS NOT NULL THEN s.lifecycle WHEN d.template_version_id IS NOT NULL THEN 'configured' ELSE 'idle' END AS public_lifecycle,
COALESCE(sts.template_version_id,d.template_version_id,(SELECT option_value FROM ha_entity_select_options WHERE entity_id='select.gjaeringsassistent_template' ORDER BY option_order LIMIT 1)) AS selected_template,
CASE WHEN s.session_id IS NOT NULL THEN CONCAT(tv.name,' · ',tv.version_label) WHEN d.template_version_id IS NOT NULL THEN CONCAT(dtv.name,' · ',dtv.version_label) ELSE 'Ingen valgt' END AS template_display
FROM (SELECT 1 AS singleton) a LEFT JOIN v_current_session_summary s ON 1=1
LEFT JOIN session_template_snapshots sts ON sts.session_id=s.session_id LEFT JOIN template_versions tv ON tv.version_id=sts.template_version_id
LEFT JOIN (SELECT d.*,CONCAT(CAST(ROUND(d.expected_attenuation_min_percent,1) AS CHAR),'–',CAST(ROUND(d.expected_attenuation_max_percent,1) AS CHAR),' %') AS expected_attenuation_display,
CONCAT(REPLACE(REPLACE(FORMAT(d.expected_fg_min,4),',',''),'.',','),'–',REPLACE(REPLACE(FORMAT(d.expected_fg_max,4),',',''),'.',',')) AS expected_fg_display FROM session_setup_draft d WHERE draft_key='current') d ON s.session_id IS NULL
LEFT JOIN template_versions dtv ON dtv.version_id=d.template_version_id;








CREATE OR REPLACE VIEW v_ha_status_payloads AS
SELECT r.projection_id,r.output_slot,CASE r.projection_id
WHEN 'system_status' THEN JSON_OBJECT('state',CONCAT('MariaDB · ',c.public_lifecycle),'attributes',JSON_OBJECT('source','MariaDB'))
WHEN 'session_status' THEN JSON_OBJECT('state',IF(c.session_id IS NULL,c.public_lifecycle,CONCAT(c.batch_name,' · ',c.public_lifecycle)),
 'attributes',JSON_MERGE_PATCH(JSON_OBJECT('lifecycle',c.public_lifecycle,'source','MariaDB','note_count',(SELECT COUNT(*) FROM session_notes WHERE session_id=c.session_id),
 'notes',JSON_QUERY(COALESCE((SELECT JSON_ARRAYAGG(JSON_OBJECT('note_id',n.note_id,'session_id',n.session_id,'noted_at',n.noted_at,'note_text',n.note_text,'operation_id',n.operation_id) ORDER BY n.noted_at DESC,n.created_at DESC LIMIT 50) FROM session_notes n WHERE n.session_id=c.session_id),'[]'),'$'),
 'availability',JSON_OBJECT('session_id',IF(c.session_id IS NULL,'not_started','present'))),
 JSON_OBJECT('session_id',c.session_id,'archive_status',c.archive_status,'archive_status_display',c.archive_status_display,
 'archive_error_message',NULLIF(c.archive_error_message,''),'archive_attempt_no',c.archive_attempt_no,'archive_requested_at',c.archive_requested_at,
 'can_prepare_new',c.can_prepare_new,'prepare_action_display',NULLIF(c.prepare_action_display,''),'completed_at',c.completed_at,
 'last_note',JSON_QUERY((SELECT JSON_OBJECT('note_id',n.note_id,'noted_at',n.noted_at,'note_text',n.note_text,'operation_id',n.operation_id) FROM session_notes n WHERE n.session_id=c.session_id ORDER BY n.noted_at DESC,n.created_at DESC LIMIT 1),'$'),
 'note_operation_id',(SELECT NULLIF(n.operation_id,'') FROM session_notes n WHERE n.session_id=c.session_id ORDER BY n.noted_at DESC,n.created_at DESC LIMIT 1),
 'note_status',IF(EXISTS(SELECT 1 FROM session_notes n WHERE n.session_id=c.session_id),'OK · notat lagret',NULL))))
WHEN 'process_status' THEN JSON_OBJECT('state',IF(c.current_process_id IS NULL,'Ikke startet',CONCAT(CONVERT(c.current_process_id USING utf8mb4),' · ',c.current_process_name)),'attributes',JSON_OBJECT('source','MariaDB'))
WHEN 'biology_status' THEN JSON_OBJECT('state',IF(c.current_biological_phase_id IS NULL,'Ikke startet',CONCAT(CONVERT(c.current_biological_phase_id USING utf8mb4),' · ',c.current_biological_phase_name)),'attributes',JSON_OBJECT('source','MariaDB'))
WHEN 'lifecycle' THEN JSON_OBJECT('state',c.public_lifecycle,'attributes',JSON_OBJECT('source','MariaDB'))
WHEN 'template_status' THEN JSON_OBJECT('state',c.template_display,'attributes',JSON_MERGE_PATCH(JSON_OBJECT('source','MariaDB',
 'availability',JSON_OBJECT('template',IF(c.current_template_version_id IS NULL AND c.draft_template_version_id IS NULL,'not_selected','present'))),
 JSON_OBJECT('expected_attenuation_display',COALESCE(c.expected_attenuation_display,c.draft_attenuation_display),'expected_fg_display',COALESCE(c.expected_fg_display,c.draft_fg_display),
 'expected_attenuation_min_percent',COALESCE(c.expected_attenuation_min_percent,c.draft_attenuation_min),'expected_attenuation_max_percent',COALESCE(c.expected_attenuation_max_percent,c.draft_attenuation_max),
 'expected_fg_min',COALESCE(c.expected_fg_min,c.draft_fg_min),'expected_fg_max',COALESCE(c.expected_fg_max,c.draft_fg_max))))
WHEN 'corrected_sg' THEN JSON_OBJECT('state',IF(c.latest_manual_sg IS NULL,'unknown',CAST(c.latest_manual_sg AS CHAR)),'attributes',JSON_OBJECT('source','MariaDB','availability',IF(c.latest_manual_sg IS NULL,'not_measured','present')))
END AS ha_payload FROM v_ha_runtime_context c JOIN ha_projection_routes r ON r.consumer_node_id='p24_ha_status_result';








CREATE OR REPLACE VIEW v_ha_template_selection AS
SELECT c.selected_template,c.public_lifecycle,JSON_OBJECT('name',e.display_name,'icon','mdi:database-outline','entityPicture','',
'options',JSON_MERGE_PRESERVE(JSON_ARRAY((SELECT option_value FROM ha_entity_select_options WHERE entity_id=e.entity_id ORDER BY option_order LIMIT 1)),
COALESCE((SELECT JSON_ARRAYAGG(version_id ORDER BY name,version_label) FROM template_versions WHERE status='published'),'[]'))) AS options_payload
FROM v_ha_runtime_context c JOIN ha_entity_registry e ON e.entity_id='select.gjaeringsassistent_template';










CREATE OR REPLACE VIEW v_process_guidance_counts AS
SELECT e.session_id,e.evaluation_id,
COUNT(CASE WHEN sc.role_id='required' THEN 1 END) AS required_total,
COUNT(CASE WHEN sc.role_id='required' AND (c.criterion_revision_id <=> revision.criterion_revision_id) AND c.met=1 THEN 1 END) AS required_met,
COUNT(CASE WHEN sc.role_id='required' AND (c.criterion_revision_id <=> revision.criterion_revision_id) AND (c.met=1 OR EXISTS(SELECT 1 FROM process_criterion_exceptions x WHERE x.evaluation_id=c.evaluation_id AND x.criterion_id=c.criterion_id AND x.action='register' AND NOT EXISTS(SELECT 1 FROM process_criterion_exceptions n WHERE n.evaluation_id=x.evaluation_id AND n.criterion_id=x.criterion_id AND n.revision_no>x.revision_no))) THEN 1 END) AS required_handled,
(SELECT COUNT(*) FROM process_criterion_exceptions x WHERE x.evaluation_id=e.evaluation_id AND x.action='register' AND NOT EXISTS(SELECT 1 FROM process_criterion_exceptions n WHERE n.evaluation_id=x.evaluation_id AND n.criterion_id=x.criterion_id AND n.revision_no>x.revision_no)) AS exception_count,COUNT(CASE WHEN c.criterion_id IS NOT NULL AND NOT(c.criterion_revision_id <=> revision.criterion_revision_id) THEN 1 END) AS outdated_criteria
FROM process_evaluations e LEFT JOIN session_process_criteria sc ON sc.session_id=e.session_id AND sc.process_id=e.candidate_process_id AND sc.enabled=1 LEFT JOIN process_evaluation_criteria c ON c.evaluation_id=e.evaluation_id AND c.criterion_id=sc.criterion_id LEFT JOIN v_current_process_criterion_revision revision ON revision.session_id=e.session_id AND revision.process_id=e.candidate_process_id AND revision.criterion_id=sc.criterion_id GROUP BY e.session_id,e.evaluation_id;








CREATE OR REPLACE VIEW v_process_guidance_effective AS
SELECT e.*,g.required_total,g.required_met,g.required_handled,g.required_total-g.required_handled AS blocking_required,g.exception_count,g.outdated_criteria,
CASE WHEN g.outdated_criteria>0 THEN 'not_evaluated' WHEN e.readiness='waiting' AND g.required_total>0 AND g.required_total=g.required_handled THEN 'ready_with_exceptions' ELSE e.readiness END AS effective_readiness
FROM v_current_process_candidate_evaluation e JOIN v_process_guidance_counts g ON g.evaluation_id=e.evaluation_id;








CREATE OR REPLACE VIEW v_current_process_guidance AS
SELECT s.session_id,e.evaluation_id,COALESCE(e.readiness,'not_evaluated') AS raw_readiness,COALESCE(e.effective_readiness,'not_evaluated') AS readiness,
COALESCE(e.candidate_process_id,n.process_id) AS next_process_id,COALESCE(e.candidate_process_name,n.name) AS next_process_name,
COALESCE(IF(e.outdated_criteria>0,'Kriteriet er endret. Venter på ny vurdering.',e.summary),IF(n.process_id IS NULL,'Prosessplan fullført','Prosessevaluator er ikke tilbakeført ennå')) AS trigger_summary,
CASE WHEN e.outdated_criteria>0 THEN 'Kriteriet er endret. Venter på ny vurdering.' WHEN e.effective_readiness IN('ready','ready_with_exceptions') THEN CONCAT(CONVERT(e.candidate_process_id USING utf8mb4),' kriterier oppfylt eller håndtert · venter på manuell overgang') ELSE COALESCE(e.operator_status_display,e.summary,IF(n.process_id IS NULL,'Prosessplan fullført','Prosessevaluator er ikke tilbakeført ennå')) END AS reason,
COALESCE(e.required_total,0) AS required_total,COALESCE(e.required_met,0) AS required_met,COALESCE(e.required_handled,0) AS required_handled,
COALESCE(e.blocking_required,0) AS blocking_required,COALESCE(e.exception_count,0) AS exception_count,e.recommended_temperature_c,e.recommended_pressure_bar,
IF(e.evaluation_id IS NULL,'not_yet','present') AS evaluation_status
FROM v_current_session_summary s LEFT JOIN v_process_guidance_effective e ON e.session_id=s.session_id
LEFT JOIN session_process_steps n ON n.session_id=s.session_id AND n.enabled=1 AND n.process_order=(SELECT MIN(p.process_order) FROM session_process_steps p WHERE p.session_id=s.session_id AND p.enabled=1 AND p.process_order>s.current_process_order);








CREATE OR REPLACE VIEW v_session_runtime_presentation AS
SELECT s.session_id,yp.name AS yeast,s.current_process_order AS active_process_order,s.current_process_name AS active_process_name,
(SELECT COUNT(*)>0 FROM v_active_technical_issues) AS attention,pg.next_process_name AS recommended_process_name,
GREATEST(0,TIMESTAMPDIFF(MICROSECOND,s.pitched_at,s.domain_now)/3600000000) AS elapsed_hours,
GREATEST(0,TIMESTAMPDIFF(MICROSECOND,s.current_biological_started_at,s.domain_now)/3600000000) AS active_phase_elapsed_hours,
s.completed_at,CONCAT(FLOOR((GREATEST(0,TIMESTAMPDIFF(SECOND,s.current_biological_started_at,s.domain_now)))/86400),IF(FLOOR((GREATEST(0,TIMESTAMPDIFF(SECOND,s.current_biological_started_at,s.domain_now)))/86400)=1,' dag, ',' dager, '),LPAD(FLOOR(MOD((GREATEST(0,TIMESTAMPDIFF(SECOND,s.current_biological_started_at,s.domain_now))),86400)/3600),2,'0'),':',LPAD(FLOOR(MOD((GREATEST(0,TIMESTAMPDIFF(SECOND,s.current_biological_started_at,s.domain_now))),3600)/60),2,'0')) AS active_phase_duration_display
FROM v_current_session_summary s JOIN sessions se ON se.session_id=s.session_id JOIN yeast_profiles yp ON yp.yeast_profile_id=se.yeast_profile_id LEFT JOIN v_current_process_guidance pg ON pg.session_id=s.session_id;








CREATE OR REPLACE VIEW v_process_recommendation_presentation AS
SELECT e.*,cp.process_name AS current_process_name,REPLACE(UUID(),'-','') AS recommendation_run_id,
CASE WHEN e.effective_readiness IN('ready','ready_with_exceptions') THEN CONCAT('Gå til ',CONVERT(e.candidate_process_id USING utf8mb4),' · ',e.candidate_process_name)
 WHEN e.effective_readiness='waiting' THEN CONCAT('Fortsett ',CONVERT(e.current_process_id USING utf8mb4),' · ',cp.process_name) WHEN e.effective_readiness='completed' THEN 'Prosessplan fullført' ELSE 'Kontroller prosesskriterier' END AS recommendation_title,
CASE WHEN e.effective_readiness IN('ready','ready_with_exceptions') THEN 'process_transition' WHEN e.effective_readiness='waiting' THEN 'hold_process' WHEN e.effective_readiness='completed' THEN 'process_complete' ELSE 'configuration' END AS recommendation_type,
CONCAT(e.summary,IF(e.effective_readiness='ready_with_exceptions',CONCAT(' · Alle ',e.required_total,' obligatoriske kriterier er oppfylt eller eksplisitt håndtert.'),'')) AS recommendation_explanation
FROM v_process_guidance_effective e JOIN v_current_process_visit cp ON cp.session_id=e.session_id;











CREATE OR REPLACE VIEW v_technical_event_presentation AS
SELECT e.*,ROW_NUMBER() OVER(ORDER BY e.occurred_at DESC,e.created_at DESC,e.event_seq DESC) AS event_order,
DATE_FORMAT(CONVERT_TZ(e.occurred_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i:%s') AS occurred_at_local,
IF(CHAR_LENGTH(CONCAT(UPPER(e.severity),' · ',e.code,' · ',e.message))>240,CONCAT(LEFT(CONCAT(UPPER(e.severity),' · ',e.code,' · ',e.message),237),'…'),CONCAT(UPPER(e.severity),' · ',e.code,' · ',e.message)) AS event_state,
JSON_OBJECT('event_id',e.event_id,'event_seq',e.event_seq,'severity',e.severity,'event_type',e.event_type,'code',e.code,'subsystem',e.subsystem,'message',e.message,'occurred_at',e.occurred_at,
'occurred_at_local',DATE_FORMAT(CONVERT_TZ(e.occurred_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i:%s'),'source_component',e.source_component,'source_node_id',e.source_node_id,'issue_key',e.issue_key) AS event_payload
FROM technical_events e;








CREATE OR REPLACE VIEW v_technical_presentation_context AS
SELECT run.check_run_id,run.overall_status,run.checked_at,
DATE_FORMAT(run.checked_at,'%Y-%m-%dT%H:%i:%s.%fZ') AS checked_at_utc,
CONCAT(DATE_FORMAT(CONVERT_TZ(run.checked_at,'+00:00','Europe/Oslo'),'%Y-%m-%dT%H:%i:%s'),
IF(TIMESTAMPDIFF(MINUTE,run.checked_at,CONVERT_TZ(run.checked_at,'+00:00','Europe/Oslo'))>=0,'+','-'),
LPAD(ABS(TIMESTAMPDIFF(MINUTE,run.checked_at,CONVERT_TZ(run.checked_at,'+00:00','Europe/Oslo'))) DIV 60,2,'0'),':',
LPAD(ABS(TIMESTAMPDIFF(MINUTE,run.checked_at,CONVERT_TZ(run.checked_at,'+00:00','Europe/Oslo'))) MOD 60,2,'0')) AS checked_at_local,
(SELECT COUNT(*) FROM v_active_technical_issues) AS active_issue_count,
(SELECT COUNT(*) FROM v_technical_event_presentation WHERE event_order<=50) AS event_count,
JSON_QUERY(COALESCE((SELECT JSON_ARRAYAGG(JSON_OBJECT('issue_key',i.issue_key,'code',i.code,'message',i.message,'severity',i.severity,'occurred_at',i.occurred_at,
'occurred_at_local',DATE_FORMAT(CONVERT_TZ(i.occurred_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i:%s')) ORDER BY i.occurred_at DESC) FROM v_active_technical_issues i),'[]'),'$') AS issues_payload,
JSON_QUERY(COALESCE((SELECT JSON_ARRAYAGG(JSON_QUERY(e.event_payload,'$') ORDER BY e.event_order) FROM v_technical_event_presentation e WHERE event_order<=50),'[]'),'$') AS events_payload,
JSON_QUERY(COALESCE((SELECT JSON_ARRAYAGG(JSON_OBJECT('check_id',x.check_id,'status',x.status,'severity',x.severity,'summary',x.summary,'error_text',x.error_text,'numeric_value',x.numeric_value,'numeric_unit',x.numeric_unit) ORDER BY x.check_order) FROM system_check_results x WHERE x.check_run_id=run.check_run_id),'[]'),'$') AS checks_payload,
m.data_quality_display,m.latest_measurement_state,m.measurement_age_state,m.measurement_age_minutes
FROM (SELECT 1 AS singleton) a LEFT JOIN (SELECT * FROM system_check_runs ORDER BY checked_at DESC,created_at DESC,check_run_id DESC LIMIT 1) run ON 1=1 LEFT JOIN v_measurement_source_status m ON 1=1;








CREATE OR REPLACE VIEW v_ha_technical_payloads AS
SELECT r.projection_id,r.output_slot,
JSON_OBJECT('state',CASE
 WHEN r.projection_id='technical_overall' THEN IF(c.check_run_id IS NULL,'IKKE KJØRT',UPPER(c.overall_status))
 WHEN r.projection_id LIKE 'technical_check_%' THEN IF(x.check_id IS NULL,'IKKE KJØRT',CONCAT(CASE x.status WHEN 'ok' THEN 'OK' WHEN 'warning' THEN 'ADVARSEL' WHEN 'error' THEN 'FEIL' WHEN 'not_applicable' THEN 'IKKE RELEVANT' WHEN 'not_observed' THEN 'IKKE VERIFISERT' WHEN 'not_run' THEN 'IKKE KJØRT' END,' · ',x.summary))
 WHEN r.projection_id='technical_last_check' THEN COALESCE(c.checked_at_local,'Ikke kontrollert ennå')
 WHEN r.projection_id IN('technical_issues','event_issues') THEN CONCAT(c.active_issue_count,' aktive')
 WHEN r.projection_id IN('technical_attention','event_attention') THEN IF(c.active_issue_count>0,'on','off')
 WHEN r.projection_id='technical_data_quality' THEN c.data_quality_display
 WHEN r.projection_id='technical_last_measurement' THEN c.latest_measurement_state
 WHEN r.projection_id='technical_measurement_age' THEN c.measurement_age_state
 ELSE COALESCE(e.event_state,'Ingen hendelse registrert') END,
'attributes',JSON_MERGE_PATCH(JSON_OBJECT('source','MariaDB'),
 CASE
 WHEN r.projection_id='technical_overall' THEN JSON_OBJECT('check_run_id',c.check_run_id,'checked_at',c.checked_at_utc,'checks',JSON_QUERY(c.checks_payload,'$'),'active_issue_count',c.active_issue_count,'event_count',c.event_count,'availability',IF(c.check_run_id IS NULL,'not_yet','present'))
 WHEN r.projection_id LIKE 'technical_check_%' THEN JSON_OBJECT('check_id',SUBSTRING(r.projection_id,17),'status',COALESCE(x.status,'not_run'),'summary',COALESCE(x.summary,'Ingen resultat registrert'),'severity',x.severity,'error_text',NULLIF(x.error_text,''),'numeric_value',x.numeric_value,'numeric_unit',NULLIF(x.numeric_unit,''),'created_at',x.created_at)
 WHEN r.projection_id='technical_last_check' THEN JSON_OBJECT('checked_at',c.checked_at_utc,'checked_at_local',c.checked_at_local,'time_zone','Europe/Oslo','availability',IF(c.checked_at IS NULL,'not_yet','present'))
 WHEN r.projection_id IN('technical_issues','event_issues') THEN JSON_OBJECT('count',c.active_issue_count,'items',JSON_QUERY(c.issues_payload,'$'),'updated_at',DATE_FORMAT(UTC_TIMESTAMP(3),'%Y-%m-%dT%H:%i:%s.%fZ'))
 WHEN r.projection_id IN('technical_attention','event_attention') THEN JSON_OBJECT('count',c.active_issue_count)
 WHEN r.projection_id='technical_data_quality' THEN JSON_OBJECT('last_measurement',c.latest_measurement_state,'measurement_age_minutes',c.measurement_age_minutes)
 WHEN r.projection_id='technical_last_measurement' THEN JSON_OBJECT('recorded_at',NULLIF(c.latest_measurement_state,'Ikke målt ennå'))
 WHEN r.projection_id='technical_measurement_age' THEN JSON_OBJECT('minutes',c.measurement_age_minutes,'availability',IF(c.measurement_age_minutes IS NULL,'not_yet','present'))
 ELSE JSON_OBJECT('event',JSON_QUERY(e.event_payload,'$'),'events',IF(r.projection_id IN('technical_event_1','event_event_1'),JSON_QUERY(c.events_payload,'$'),NULL),'total_events',c.event_count) END)) AS ha_payload
FROM v_technical_presentation_context c JOIN ha_projection_routes r ON r.consumer_node_id IN('p24_ha_technical_result','p24_ha_event_result')
LEFT JOIN system_check_results x ON x.check_run_id=c.check_run_id AND x.check_id=SUBSTRING(r.projection_id,17) AND r.projection_id LIKE 'technical_check_%'
LEFT JOIN v_technical_event_presentation e ON e.event_order=CAST(SUBSTRING_INDEX(r.projection_id,'_',-1) AS UNSIGNED) AND r.projection_id REGEXP '^(technical|event)_event_[1-5]$';









-- p24r13: unified graph read-models, with no graph-ID branches in consumers.
CREATE OR REPLACE VIEW v_graph_process_plan AS
SELECT t.session_id,t.metric_id,p.visit_id,r.started_at,LEAST(COALESCE(r.ended_at,axis.x_axis_ended_at),axis.x_axis_ended_at) AS ended_at,
 e.target_value AS actual_value,e.target_value AS minimum_value,e.target_value AS maximum_value,t.label
FROM session_process_targets t JOIN session_process_target_exact e ON e.session_id=t.session_id AND e.process_id=t.process_id AND e.target_id=t.target_id
JOIN process_visits p ON p.session_id=t.session_id AND p.process_id=t.process_id JOIN v_process_visit_timing r ON r.visit_id=p.visit_id JOIN v_session_graph_time_axis axis ON axis.session_id=t.session_id
UNION ALL
SELECT t.session_id,t.metric_id,p.visit_id,r.started_at,LEAST(COALESCE(r.ended_at,axis.x_axis_ended_at),axis.x_axis_ended_at),
 (e.minimum_value+e.maximum_value)/2,e.minimum_value,e.maximum_value,CONCAT(t.label,' · midtpunkt i planintervall')
FROM session_process_targets t JOIN session_process_target_range e ON e.session_id=t.session_id AND e.process_id=t.process_id AND e.target_id=t.target_id
JOIN process_visits p ON p.session_id=t.session_id AND p.process_id=t.process_id JOIN v_process_visit_timing r ON r.visit_id=p.visit_id JOIN v_session_graph_time_axis axis ON axis.session_id=t.session_id
WHERE e.minimum_value IS NOT NULL AND e.maximum_value IS NOT NULL;









CREATE OR REPLACE VIEW v_graph_comparison_display AS
SELECT m.session_id,MIN(m.bucket_at) AS bucket_at,MIN(m.sg_min) AS sg_min,CASE WHEN COUNT(m.sample_count)=COUNT(*) THEN SUM(m.sg_value*m.sample_count)/SUM(m.sample_count) ELSE AVG(m.sg_value) END AS sg_value,MAX(m.sg_max) AS sg_max,
MIN(m.temperature_min_c) AS temperature_min_c,AVG(m.temperature_mean_c) AS temperature_mean_c,MAX(m.temperature_max_c) AS temperature_max_c,
MIN(m.pressure_min_bar) AS pressure_min_bar,AVG(m.pressure_mean_bar) AS pressure_mean_bar,MAX(m.pressure_max_bar) AS pressure_max_bar,m.segment_id,
CONCAT(MAX(m.source_display),' · ',c.interval_seconds/60,' minutter') AS source_display
FROM v_graph_reference_measurement_series m JOIN v_graph_display_selection c GROUP BY m.session_id,m.segment_id,FLOOR(UNIX_TIMESTAMP(m.bucket_at)/c.interval_seconds),c.interval_seconds;









CREATE OR REPLACE VIEW v_graph_source_values AS
SELECT m.session_id,'measurement' AS source_kind,'tilt_sg' AS metric_id,m.bucket_at AS sample_at,CAST(m.sg_value AS DECIMAL(24,9)) AS actual_value,CAST(m.sg_min AS DECIMAL(24,9)) AS range_min_value,CAST(m.sg_max AS DECIMAL(24,9)) AS range_max_value,CONVERT(m.source_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display,CONVERT(CAST(m.segment_id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci AS segment_id FROM v_session_display_measurement_series m WHERE m.sg_value IS NOT NULL
UNION ALL
SELECT m.session_id,'measurement' AS source_kind,'beer_temperature_c' AS metric_id,m.bucket_at AS sample_at,CAST(m.temperature_mean_c AS DECIMAL(24,9)) AS actual_value,CAST(m.temperature_min_c AS DECIMAL(24,9)) AS range_min_value,CAST(m.temperature_max_c AS DECIMAL(24,9)) AS range_max_value,CONVERT(m.source_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display,CONVERT(CAST(m.segment_id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci AS segment_id FROM v_session_display_measurement_series m WHERE m.temperature_mean_c IS NOT NULL
UNION ALL
SELECT m.session_id,'measurement' AS source_kind,'pressure_bar' AS metric_id,m.bucket_at AS sample_at,CAST(m.pressure_mean_bar AS DECIMAL(24,9)) AS actual_value,CAST(m.pressure_min_bar AS DECIMAL(24,9)) AS range_min_value,CAST(m.pressure_max_bar AS DECIMAL(24,9)) AS range_max_value,CONVERT(m.source_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display,CONVERT(CAST(m.segment_id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci AS segment_id FROM v_session_display_measurement_series m WHERE m.pressure_mean_bar IS NOT NULL
UNION ALL
SELECT m.session_id,'comparison' AS source_kind,'tilt_sg' AS metric_id,m.bucket_at AS sample_at,CAST(m.sg_value AS DECIMAL(24,9)) AS actual_value,CAST(m.sg_min AS DECIMAL(24,9)) AS range_min_value,CAST(m.sg_max AS DECIMAL(24,9)) AS range_max_value,CONVERT(m.source_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display,CONVERT(CAST(m.segment_id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci AS segment_id FROM v_graph_comparison_display m WHERE m.sg_value IS NOT NULL
UNION ALL
SELECT m.session_id,'comparison' AS source_kind,'beer_temperature_c' AS metric_id,m.bucket_at AS sample_at,CAST(m.temperature_mean_c AS DECIMAL(24,9)) AS actual_value,CAST(m.temperature_min_c AS DECIMAL(24,9)) AS range_min_value,CAST(m.temperature_max_c AS DECIMAL(24,9)) AS range_max_value,CONVERT(m.source_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display,CONVERT(CAST(m.segment_id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci AS segment_id FROM v_graph_comparison_display m WHERE m.temperature_mean_c IS NOT NULL
UNION ALL
SELECT m.session_id,'comparison' AS source_kind,'pressure_bar' AS metric_id,m.bucket_at AS sample_at,CAST(m.pressure_mean_bar AS DECIMAL(24,9)) AS actual_value,CAST(m.pressure_min_bar AS DECIMAL(24,9)) AS range_min_value,CAST(m.pressure_max_bar AS DECIMAL(24,9)) AS range_max_value,CONVERT(m.source_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display,CONVERT(CAST(m.segment_id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci AS segment_id FROM v_graph_comparison_display m WHERE m.pressure_mean_bar IS NOT NULL
UNION ALL
SELECT o.session_id,'observation','tilt_sg',o.recorded_at,CAST(o.corrected_sg AS DECIMAL(24,9)),NULL,NULL,CONVERT('Manuell registrering' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT('manual' USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM v_current_observation_revision o WHERE o.status='active' AND o.corrected_sg IS NOT NULL
UNION ALL
SELECT o.session_id,'observation','beer_temperature_c',o.recorded_at,CAST(o.manual_temperature_c AS DECIMAL(24,9)),NULL,NULL,CONVERT('Manuell registrering' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT('manual' USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM v_current_observation_revision o WHERE o.status='active' AND o.manual_temperature_c IS NOT NULL
UNION ALL
SELECT o.session_id,'observation','pressure_bar',o.recorded_at,CAST(o.pressure_bar AS DECIMAL(24,9)),NULL,NULL,CONVERT('Manuell registrering' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT('manual' USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM v_current_observation_revision o WHERE o.status='active' AND o.pressure_bar IS NOT NULL
UNION ALL
SELECT o.session_id,'observation','cooler_setpoint_c',o.recorded_at,CAST(o.cooler_setpoint_c AS DECIMAL(24,9)),NULL,NULL,CONVERT('Manuell registrering' USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT('manual' USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM v_current_observation_revision o WHERE o.status='active' AND o.cooler_setpoint_c IS NOT NULL
UNION ALL
SELECT p.session_id,'process_target',p.metric_id,p.started_at,p.actual_value,p.minimum_value,p.maximum_value,CONVERT(p.label USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(p.visit_id USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM v_graph_process_plan p WHERE p.started_at>=p.started_at
UNION ALL
SELECT p.session_id,'process_target',p.metric_id,p.ended_at,p.actual_value,p.minimum_value,p.maximum_value,CONVERT(p.label USING utf8mb4) COLLATE utf8mb4_unicode_ci,CONVERT(p.visit_id USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM v_graph_process_plan p WHERE p.ended_at>=p.started_at;









CREATE OR REPLACE VIEW v_graph_raw_series AS
SELECT d.session_id,d.graph_id,d.series_id,d.sort_order,CONVERT(d.label USING utf8mb4) COLLATE utf8mb4_unicode_ci AS label,v.sample_at,v.actual_value,v.range_min_value,v.range_max_value,
 CONVERT(CONCAT(REPLACE(REPLACE(FORMAT(v.actual_value,g.display_decimals),',',''),'.',','),' ',g.unit) USING utf8mb4) COLLATE utf8mb4_unicode_ci AS actual_value_display,
 CONVERT(CONCAT(v.basis_display,' · ',DATE_FORMAT(CONVERT_TZ(v.sample_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i')) USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display,
 d.standard_color AS line_color,d.standard_dasharray AS line_dasharray,d.band_model,d.band_description,d.band_opacity,d.render_mode,v.segment_id
FROM session_analysis_graph_series d JOIN session_analysis_graphs g ON g.session_id=d.session_id AND g.graph_id=d.graph_id
JOIN v_graph_source_values v ON v.session_id=d.session_id AND v.source_kind=d.source_kind AND v.metric_id=d.metric_id
WHERE g.enabled=1;









CREATE OR REPLACE VIEW v_graph_series AS
SELECT session_id,graph_id,series_id,sort_order,CONVERT(label USING utf8mb4) COLLATE utf8mb4_unicode_ci AS label,sample_at,actual_value,range_min_value,range_max_value,CONVERT(actual_value_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS actual_value_display,CONVERT(basis_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display,CONVERT(line_color USING utf8mb4) COLLATE utf8mb4_unicode_ci AS line_color,CONVERT(line_dasharray USING utf8mb4) COLLATE utf8mb4_unicode_ci AS line_dasharray,CONVERT(band_model USING utf8mb4) COLLATE utf8mb4_unicode_ci AS band_model,CONVERT(band_description USING utf8mb4) COLLATE utf8mb4_unicode_ci AS band_description,band_opacity,CONVERT(render_mode USING utf8mb4) COLLATE utf8mb4_unicode_ci AS render_mode,CONVERT(segment_id USING utf8mb4) COLLATE utf8mb4_unicode_ci AS segment_id FROM v_dashboard_analysis_series
UNION ALL
SELECT session_id,graph_id,series_id,sort_order,CONVERT(label USING utf8mb4) COLLATE utf8mb4_unicode_ci AS label,sample_at,actual_value,range_min_value,range_max_value,CONVERT(actual_value_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS actual_value_display,CONVERT(basis_display USING utf8mb4) COLLATE utf8mb4_unicode_ci AS basis_display,CONVERT(line_color USING utf8mb4) COLLATE utf8mb4_unicode_ci AS line_color,CONVERT(line_dasharray USING utf8mb4) COLLATE utf8mb4_unicode_ci AS line_dasharray,CONVERT(band_model USING utf8mb4) COLLATE utf8mb4_unicode_ci AS band_model,CONVERT(band_description USING utf8mb4) COLLATE utf8mb4_unicode_ci AS band_description,band_opacity,CONVERT(render_mode USING utf8mb4) COLLATE utf8mb4_unicode_ci AS render_mode,CONVERT(segment_id USING utf8mb4) COLLATE utf8mb4_unicode_ci AS segment_id FROM v_graph_raw_series;









CREATE OR REPLACE VIEW v_graph_reference_bands AS
SELECT d.session_id,d.graph_id,d.series_id,d.label,t.expected_fg_min AS minimum_value,t.expected_fg_max AS maximum_value,d.standard_color AS line_color,d.band_opacity
FROM session_analysis_graph_series d JOIN v_current_fermentation_target t ON t.session_id=d.session_id WHERE d.source_kind='fermentation_target' AND d.metric_id='tilt_sg';









CREATE OR REPLACE VIEW v_graph_extents AS
SELECT g.session_id,g.graph_id,g.display_decimals,g.y_axis_include_zero,MIN(q.value_min) AS data_min,MAX(q.value_max) AS data_max
FROM session_analysis_graphs g LEFT JOIN (
 SELECT session_id,graph_id,CASE WHEN band_model='none' THEN actual_value ELSE COALESCE(range_min_value,actual_value) END AS value_min,CASE WHEN band_model='none' THEN actual_value ELSE COALESCE(range_max_value,actual_value) END AS value_max FROM v_graph_series
 UNION ALL SELECT session_id,graph_id,minimum_value,maximum_value FROM v_graph_reference_bands
 UNION ALL SELECT session_id,graph_id,COALESCE(minimum_value,maximum_value),COALESCE(maximum_value,minimum_value) FROM v_session_analysis_requirements
) q ON q.session_id=g.session_id AND q.graph_id=g.graph_id WHERE g.enabled=1 GROUP BY g.session_id,g.graph_id,g.display_decimals,g.y_axis_include_zero;









CREATE OR REPLACE VIEW v_graph_axes AS
SELECT z.session_id,z.graph_id,
       CASE WHEN z.fixed_min IS NOT NULL THEN z.fixed_min WHEN z.y_axis_include_zero=1 AND z.base_min=0 THEN 0 ELSE FLOOR((z.base_min-z.tick_step*0.30)/z.tick_step)*z.tick_step END AS y_axis_min,
       CASE WHEN z.fixed_max IS NOT NULL THEN z.fixed_max ELSE CEIL((z.base_max+z.tick_step*0.30)/z.tick_step)*z.tick_step END AS y_axis_max,
       z.tick_step AS y_axis_tick_step
FROM (
 SELECT y.*,CASE WHEN y.normalized_step<=1 THEN y.magnitude WHEN y.normalized_step<=2 THEN 2*y.magnitude WHEN y.normalized_step<=5 THEN 5*y.magnitude ELSE 10*y.magnitude END AS tick_step
 FROM (
  SELECT x.*,POW(10,FLOOR(LOG10(x.rough_step))) AS magnitude,x.rough_step/POW(10,FLOOR(LOG10(x.rough_step))) AS normalized_step
  FROM (
   SELECT b.*,GREATEST((b.base_max-b.base_min)/5,POW(10,-b.display_decimals)) AS rough_step
   FROM (
    SELECT e.*,g.y_axis_min AS fixed_min,g.y_axis_max AS fixed_max,
           COALESCE(g.y_axis_min,CASE WHEN e.y_axis_include_zero=1 THEN LEAST(0,COALESCE(e.data_min,0)) ELSE COALESCE(e.data_min,0) END) AS base_min,
           COALESCE(g.y_axis_max,GREATEST(COALESCE(g.y_axis_min,0),CASE WHEN e.y_axis_include_zero=1 THEN GREATEST(0,COALESCE(e.data_max,0)) ELSE COALESCE(e.data_max,0) END)) AS base_max
    FROM v_graph_extents e JOIN session_analysis_graphs g ON g.session_id=e.session_id AND g.graph_id=e.graph_id
   ) b
  ) x
 ) y
) z;










CREATE OR REPLACE VIEW v_graph_definitions AS
SELECT g.session_id,g.graph_id,t.render_scope,g.sort_order,g.label,g.description,g.unit,g.display_decimals,
 a.y_axis_min,a.y_axis_max,a.y_axis_tick_step,t.x_axis_started_at,t.x_axis_ended_at,t.x_axis_start_display,t.x_axis_end_display,
 g.enabled,g.show_biological_bands,g.show_process_markers,g.show_criterion_markers,g.gap_policy,
 EXISTS(SELECT 1 FROM session_analysis_graph_series d WHERE d.session_id=g.session_id AND d.graph_id=g.graph_id AND d.source_kind='measurement') AS show_in_overview,
 p.canvas_width,p.canvas_height,p.compact_height,p.margin_left,p.margin_right,p.margin_top,p.margin_bottom,p.date_font_size,p.axis_font_size,p.marker_font_size,p.font_family,p.line_width,p.point_radius,p.time_marker_spacing
FROM session_analysis_graphs g JOIN v_graph_axes a ON a.session_id=g.session_id AND a.graph_id=g.graph_id JOIN (
 SELECT d.*,'dashboard' AS render_scope FROM v_session_graph_time_axis d
 UNION ALL
 SELECT r.session_id,r.x_axis_started_at,IF((SELECT a.is_historical FROM v_all_session a WHERE a.session_id=r.session_id)=1,r.x_axis_ended_at,GREATEST(r.x_axis_ended_at,COALESCE(ref.last_at,r.x_axis_ended_at))) AS x_axis_ended_at,
 CONCAT('Dag 0.00 · ',DATE_FORMAT(CONVERT_TZ(r.x_axis_started_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i')) AS x_axis_start_display,
 CONCAT('Dag ',ROUND(TIMESTAMPDIFF(SECOND,r.x_axis_started_at,IF((SELECT a.is_historical FROM v_all_session a WHERE a.session_id=r.session_id)=1,r.x_axis_ended_at,GREATEST(r.x_axis_ended_at,COALESCE(ref.last_at,r.x_axis_ended_at))))/86400,2),' · ',DATE_FORMAT(CONVERT_TZ(IF((SELECT a.is_historical FROM v_all_session a WHERE a.session_id=r.session_id)=1,r.x_axis_ended_at,GREATEST(r.x_axis_ended_at,COALESCE(ref.last_at,r.x_axis_ended_at))),'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i')) AS x_axis_end_display,
 'report' FROM v_report_graph_time_axis r LEFT JOIN(SELECT session_id,MAX(bucket_at) AS last_at FROM v_graph_reference_measurement_series GROUP BY session_id) ref ON ref.session_id=r.session_id
) t ON t.session_id=g.session_id CROSS JOIN graph_render_policy p WHERE g.enabled=1;









CREATE OR REPLACE VIEW v_graph_axis_ticks AS
SELECT a.session_id,a.graph_id,a.y_axis_min+d.seq*a.y_axis_tick_step AS tick_value,
REPLACE(REPLACE(FORMAT(a.y_axis_min+d.seq*a.y_axis_tick_step,g.display_decimals) COLLATE utf8mb4_unicode_ci,',',''),'.',',') AS axis_label
FROM v_graph_axes a JOIN session_analysis_graphs g ON g.session_id=a.session_id AND g.graph_id=a.graph_id JOIN seq_0_to_60 d ON a.y_axis_min+d.seq*a.y_axis_tick_step<=a.y_axis_max+a.y_axis_tick_step/1000;









CREATE OR REPLACE VIEW v_graph_latest AS
SELECT v.session_id,v.graph_id,v.series_id,v.sort_order,v.sample_at,v.actual_value,
CONCAT(v.label,' · ',v.actual_value_display,' · ',v.basis_display) AS latest_value_display
FROM (SELECT x.*,ROW_NUMBER() OVER(PARTITION BY session_id,graph_id,series_id ORDER BY sample_at DESC) AS latest_rank FROM v_graph_series x) v WHERE v.latest_rank=1;









CREATE OR REPLACE VIEW v_graph_time_markers AS
SELECT g.session_id,g.graph_id,g.render_scope,TIMESTAMPADD(DAY,d.seq,a.pitched_at) AS marker_at,d.seq AS relative_day,
CASE WHEN c.source_kind<>'none' THEN CONCAT('Dag ',d.seq,' · ',DATE_FORMAT(CONVERT_TZ(TIMESTAMPADD(DAY,d.seq,a.pitched_at),'+00:00','Europe/Oslo'),'%d.%m')) ELSE DATE_FORMAT(CONVERT_TZ(TIMESTAMPADD(DAY,d.seq,a.pitched_at),'+00:00','Europe/Oslo'),'%d.%m') END AS axis_label
FROM v_graph_definitions g JOIN v_all_session a ON a.session_id=g.session_id JOIN v_graph_display_selection c JOIN seq_0_to_10000 d ON TIMESTAMPADD(DAY,d.seq,a.pitched_at) BETWEEN g.x_axis_started_at AND g.x_axis_ended_at
WHERE MOD(d.seq,GREATEST(1,CEIL(TIMESTAMPDIFF(SECOND,g.x_axis_started_at,g.x_axis_ended_at)/86400/GREATEST(1,FLOOR((g.canvas_width-g.margin_left-g.margin_right)/g.time_marker_spacing)))))=0;









CREATE OR REPLACE VIEW v_criterion_correction_receipts AS
SELECT q.*,CASE q.review_state WHEN 'evaluated' THEN 'Korreksjon lagret og vurdert med gjeldende krav.' WHEN 'not_current_candidate' THEN 'Korreksjon lagret. Kravet gjelder når denne fasen eller dette trinnet vurderes på nytt.' ELSE 'Korreksjon lagret. Venter på vurdering med gjeldende krav.' END COLLATE utf8mb4_unicode_ci AS review_message
FROM (SELECT 'biological' AS scope,r.session_id,r.phase_id AS owner_id,r.criterion_id,r.model_id,r.criterion_revision_id,r.revision_no,r.action,r.note,r.operation_id,r.created_at,e.evaluation_id,CASE WHEN e.evaluation_id IS NOT NULL THEN 'evaluated' WHEN NOT (own.phase_order=visit.phase_order+1) THEN 'not_current_candidate' ELSE 'pending' END AS review_state FROM v_current_biological_criterion_revision r JOIN session_biological_phases own ON own.session_id=r.session_id AND own.phase_id=r.phase_id JOIN v_current_biological_visit visit ON visit.session_id=r.session_id LEFT JOIN biological_evaluations e ON e.evaluation_id=(SELECT matching.evaluation_id FROM biological_evaluation_criteria matching JOIN biological_evaluations recorded ON recorded.evaluation_id=matching.evaluation_id WHERE matching.criterion_revision_id=r.criterion_revision_id AND matching.criterion_id=r.criterion_id AND recorded.session_id=r.session_id AND recorded.candidate_phase_id=r.phase_id ORDER BY recorded.evaluated_at DESC,recorded.created_at DESC,recorded.evaluation_id DESC LIMIT 1)
UNION ALL
SELECT 'process' AS scope,r.session_id,r.process_id AS owner_id,r.criterion_id,r.model_id,r.criterion_revision_id,r.revision_no,r.action,r.note,r.operation_id,r.created_at,e.evaluation_id,CASE WHEN e.evaluation_id IS NOT NULL THEN 'evaluated' WHEN NOT (own.process_order=(SELECT MIN(next.process_order) FROM session_process_steps next WHERE next.session_id=r.session_id AND next.enabled=1 AND next.process_order>visit.process_order)) THEN 'not_current_candidate' ELSE 'pending' END AS review_state FROM v_current_process_criterion_revision r JOIN session_process_steps own ON own.session_id=r.session_id AND own.process_id=r.process_id JOIN v_current_process_visit visit ON visit.session_id=r.session_id LEFT JOIN process_evaluations e ON e.evaluation_id=(SELECT matching.evaluation_id FROM process_evaluation_criteria matching JOIN process_evaluations recorded ON recorded.evaluation_id=matching.evaluation_id WHERE matching.criterion_revision_id=r.criterion_revision_id AND matching.criterion_id=r.criterion_id AND recorded.session_id=r.session_id AND recorded.candidate_process_id=r.process_id ORDER BY recorded.evaluated_at DESC,recorded.created_at DESC,recorded.evaluation_id DESC LIMIT 1)) q;






CREATE OR REPLACE VIEW v_historical_phase_options AS
SELECT a.session_id,CONVERT('biological' USING utf8mb4) COLLATE utf8mb4_unicode_ci AS kind,p.phase_id AS owner_id,p.phase_order AS sort_order,CONCAT(CONVERT(p.phase_id USING utf8mb4),' · ',p.name) AS label
FROM v_active_session a JOIN session_biological_phases p ON p.session_id=a.session_id WHERE a.is_historical=1 AND NOT EXISTS(SELECT 1 FROM biological_visits v WHERE v.session_id=p.session_id AND v.phase_id=p.phase_id)
UNION ALL
SELECT a.session_id,CONVERT('process' USING utf8mb4) COLLATE utf8mb4_unicode_ci,p.process_id,p.process_order,CONCAT(CONVERT(p.process_id USING utf8mb4),' · ',p.name)
FROM v_active_session a JOIN session_process_steps p ON p.session_id=a.session_id WHERE a.is_historical=1 AND p.enabled=1 AND NOT EXISTS(SELECT 1 FROM process_visits v WHERE v.session_id=p.session_id AND v.process_id=p.process_id);





CREATE OR REPLACE VIEW v_phase_duration_presentation AS
SELECT q.session_id,q.kind,q.owner_id,q.duration_seconds,CONCAT(FLOOR((q.duration_seconds)/86400),IF(FLOOR((q.duration_seconds)/86400)=1,' dag, ',' dager, '),LPAD(FLOOR(MOD((q.duration_seconds),86400)/3600),2,'0'),':',LPAD(FLOOR(MOD((q.duration_seconds),3600)/60),2,'0')) AS duration_display FROM (
 SELECT session_id,CONVERT('biological' USING utf8mb4) COLLATE utf8mb4_unicode_ci AS kind,phase_id AS owner_id,SUM(duration_seconds) AS duration_seconds FROM v_biological_visit_timing GROUP BY session_id,phase_id
 UNION ALL SELECT session_id,CONVERT('process' USING utf8mb4) COLLATE utf8mb4_unicode_ci,process_id,SUM(duration_seconds) FROM v_process_visit_timing GROUP BY session_id,process_id
) q;



CREATE OR REPLACE VIEW v_measurement_source_system_check AS
SELECT 'measurement_source' AS check_id,
 CASE WHEN p.source_state IS NULL THEN 'error'
 WHEN p.check_status='ok' AND s.lifecycle='active' AND s.state<>'DEMO'
 AND (c.detail_count=0 OR s.last_error IS NOT NULL AND s.last_error<>'') THEN 'warning'
 ELSE p.check_status END AS check_status,
 CASE WHEN p.source_state IS NULL THEN 'error'
 WHEN p.check_status='ok' AND s.lifecycle='active' AND s.state<>'DEMO'
 AND (c.detail_count=0 OR s.last_error IS NOT NULL AND s.last_error<>'') THEN 'warning'
 ELSE p.severity END AS severity,
 CASE WHEN p.source_state IS NULL THEN CONCAT('Målekildestatus mangler registrert kontrollpolicy: ',s.state)
 ELSE CONCAT(s.message,IF(c.session_id IS NULL,'',CONCAT(' · ',c.summary_display)),
 IF(s.last_error IS NULL OR s.last_error='','',CONCAT(' · importadvarsel: ',s.last_error))) END AS summary
FROM v_measurement_source_status s
LEFT JOIN measurement_source_check_policy p ON p.source_state=CONVERT(s.state USING ascii) COLLATE ascii_bin
LEFT JOIN v_session_import_coverage c ON c.session_id=s.session_id;
