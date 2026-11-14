SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
-- Same-schema upgrade: release identity only; domain tables/routines/views remain intact.
UPDATE system_check_expectations SET expected_text='2026.11.14-1' WHERE expectation_key='application_version';
