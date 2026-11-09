-- File-only release: domain tables, routines, views and session data are unchanged.
UPDATE system_check_expectations SET expected_text='2026.11.09-2',updated_at=UTC_TIMESTAMP(3) WHERE expectation_key='application_version' AND check_id IN ('configuration','frontend_publishing');
