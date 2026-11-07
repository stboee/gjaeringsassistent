-- Expected to FAIL with a foreign-key error. Installer interprets failure as PASS.
INSERT INTO process_visits(visit_id,session_id,process_id,created_at)
VALUES ('__expected_fk_failure__','__missing_session__','__missing_process__',UTC_TIMESTAMP(3));
