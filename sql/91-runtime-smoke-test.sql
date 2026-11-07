-- Gjæringsassistent – runtime/history smoke test
-- Inserts a minimal coherent session inside a transaction and rolls everything back.

START TRANSACTION;

INSERT INTO sessions(
  session_id,batch_name,created_at,pitched_at,og,volume_l,
  yeast_profile_id,pitch_mode_id,pitch_temperature_c
) VALUES (
  '__schema_smoke__','Schema smoke',UTC_TIMESTAMP(3),UTC_TIMESTAMP(3),
  1.05000,150.000,'fermentis-w3470','dry',10.000
);
INSERT INTO session_dry_pitches(session_id,yeast_amount_g) VALUES('__schema_smoke__',200.000);

INSERT INTO session_lifecycle_events(lifecycle_event_id,session_id,lifecycle,occurred_at,created_at)
VALUES ('__schema_smoke_lifecycle__','__schema_smoke__','active',UTC_TIMESTAMP(3),UTC_TIMESTAMP(3));

INSERT INTO session_process_steps(
  session_id,process_id,slot_no,process_order,enabled,name,description,created_at
) VALUES ('__schema_smoke__','p1',1,1,1,'P1 smoke',NULL,UTC_TIMESTAMP(3));

INSERT INTO process_visits(visit_id,session_id,process_id,created_at)
VALUES ('__schema_smoke_pv1__','__schema_smoke__','p1',UTC_TIMESTAMP(3));

INSERT INTO process_visit_revisions(
  visit_revision_id,visit_id,revision_no,started_at,timing_source,revision_reason,created_at
) VALUES (
  '__schema_smoke_pvr1__','__schema_smoke_pv1__',1,UTC_TIMESTAMP(3),'smoke_test','initial',UTC_TIMESTAMP(3)
);

INSERT INTO session_biological_phases(
  session_id,phase_id,phase_order,name,description,created_at
) VALUES ('__schema_smoke__','b1',1,'B1 smoke',NULL,UTC_TIMESTAMP(3));

INSERT INTO biological_visits(visit_id,session_id,phase_id,created_at)
VALUES ('__schema_smoke_bv1__','__schema_smoke__','b1',UTC_TIMESTAMP(3));

INSERT INTO biological_visit_revisions(
  visit_revision_id,visit_id,revision_no,started_at,timing_source,confidence,revision_reason,created_at
) VALUES (
  '__schema_smoke_bvr1__','__schema_smoke_bv1__',1,UTC_TIMESTAMP(3),'smoke_test','test','initial',UTC_TIMESTAMP(3)
);

INSERT INTO observation_rounds(observation_id,session_id,created_at)
VALUES ('__schema_smoke_obs__','__schema_smoke__',UTC_TIMESTAMP(3));

INSERT INTO observation_round_revisions(
  observation_revision_id,observation_id,session_id,revision_no,status,recorded_at,
  measurement_method_id,measured_sg,sample_temperature_c,calibration_temperature_c,corrected_sg,
  manual_temperature_c,pressure_bar,cooler_setpoint_c,cooler_calibration_offset_c,estimated_abv_percent,
  airlock_activity,acetaldehyde_level,diacetyl_level,wort_like_level,sulfur_so2_level,sulfur_h2s_level,
  clarity_level,settling_yeast_level,settling_minutes,user_conclusion,
  corrected_sg_model_id,abv_now_model_id,actual_og_used,revision_reason,created_at
) VALUES (
  '__schema_smoke_obsr1__','__schema_smoke_obs__','__schema_smoke__',1,'active',UTC_TIMESTAMP(3),
  'hydrometer',1.04000,20.000,20.000,1.04000,
  10.000,0.0000,10.000,0.000,1.30,
  'none',0,0,0,0,0,0,0,0.000,'uncertain',
  'hydrometer-temperature-correction-sg-v1','cutaia-apparent-abv-v1',1.05000,'initial',UTC_TIMESTAMP(3)
);

SELECT 'smoke_active_session_view' AS test,
       IF(COUNT(*)=1,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result
FROM v_active_session WHERE session_id='__schema_smoke__';

SELECT 'smoke_current_process_view' AS test,
       IF(COUNT(*)=1,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result
FROM v_current_process_visit WHERE session_id='__schema_smoke__' AND process_id='p1';

SELECT 'smoke_current_biology_view' AS test,
       IF(COUNT(*)=1,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result
FROM v_current_biological_visit WHERE session_id='__schema_smoke__' AND phase_id='b1';

SELECT 'smoke_latest_observation_view' AS test,
       IF(COUNT(*)=1 AND MAX(corrected_sg)=1.04000,'PASS','FAIL') AS result
FROM v_latest_observation WHERE session_id='__schema_smoke__';

SELECT 'smoke_current_session_view_active' AS test,
       IF(COUNT(*)=1 AND MAX(lifecycle)='active','PASS','FAIL') AS result
FROM v_current_session WHERE session_id='__schema_smoke__';

INSERT INTO session_lifecycle_events(lifecycle_event_id,session_id,lifecycle,occurred_at,operation_id,created_at)
VALUES ('__schema_smoke_completed__','__schema_smoke__','completed',DATE_ADD(UTC_TIMESTAMP(3),INTERVAL 1 SECOND),'__schema_smoke_complete_op__',UTC_TIMESTAMP(3));

SELECT 'smoke_completed_session_is_current_not_active' AS test,
       IF((SELECT COUNT(*) FROM v_current_session WHERE session_id='__schema_smoke__' AND lifecycle='completed')=1
          AND (SELECT COUNT(*) FROM v_active_session WHERE session_id='__schema_smoke__')=0,'PASS','FAIL') AS result;

INSERT INTO session_release_events(release_event_id,session_id,released_at,operation_id,created_at)
VALUES ('__schema_smoke_release__','__schema_smoke__',DATE_ADD(UTC_TIMESTAMP(3),INTERVAL 2 SECOND),'__schema_smoke_release_op__',UTC_TIMESTAMP(3));

SELECT 'smoke_released_session_not_operational' AS test,
       IF(COUNT(*)=0,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result
FROM v_current_session WHERE session_id='__schema_smoke__';

ROLLBACK;

SELECT 'smoke_rollback_clean' AS test,
       IF(COUNT(*)=0,'PASS',CONCAT('FAIL: ',COUNT(*))) AS result
FROM sessions WHERE session_id='__schema_smoke__';
