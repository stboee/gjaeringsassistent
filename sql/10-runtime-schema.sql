-- Gjæringsassistent – MariaDB runtime/history schema prototype20-r1-revised1
-- Baseline: p18r5 sql/schema.sql, normalized further to remove all domain JSON blobs.
-- Target: MariaDB 12.3.3 / InnoDB.
-- Requires 00-template-schema.sql + 01-template-registry-seed.sql first.
-- All DATETIME(3) values are UTC by application contract.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
SET SESSION sql_mode = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

CREATE TABLE IF NOT EXISTS database_metadata (
    metadata_id TINYINT PRIMARY KEY CHECK (metadata_id = 1),
    schema_version INTEGER NOT NULL CHECK (schema_version >= 1),
    application_version VARCHAR(96) NOT NULL,
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT IGNORE INTO database_metadata(metadata_id,schema_version,application_version,created_at)
VALUES (1,10,'pending-installer-version',UTC_TIMESTAMP(3));

-- Session identity and immutable/start facts ---------------------------------
CREATE TABLE IF NOT EXISTS sessions (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    batch_name VARCHAR(255) NOT NULL,
    is_demo TINYINT NOT NULL DEFAULT 0 CHECK (is_demo IN (0,1)),
    created_at DATETIME(3) NOT NULL,
    pitched_at DATETIME(3) NOT NULL,
    og DECIMAL(7,5) NOT NULL,
    volume_l DECIMAL(10,3) NOT NULL CHECK (volume_l > 0),
    yeast_profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    pitch_mode_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    pitch_temperature_c DECIMAL(8,3) NOT NULL,
    oxygenation_note TEXT,
    CONSTRAINT fk_sessions__yeast_profile FOREIGN KEY (yeast_profile_id) REFERENCES yeast_profiles(yeast_profile_id),
    CONSTRAINT fk_sessions__pitch_mode FOREIGN KEY (pitch_mode_id) REFERENCES pitch_modes(pitch_mode_id),
    UNIQUE(session_id,pitch_mode_id)
 ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS session_dry_pitches (
 session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 pitch_mode_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'dry' CHECK(pitch_mode_id='dry'),
 yeast_amount_g DECIMAL(10,3) NOT NULL CHECK(yeast_amount_g>0),
 FOREIGN KEY(session_id,pitch_mode_id) REFERENCES sessions(session_id,pitch_mode_id) ON DELETE CASCADE
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS session_slurry_pitches (
 session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 pitch_mode_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'slurry' CHECK(pitch_mode_id='slurry'),
 slurry_volume_ml DECIMAL(12,3) NOT NULL CHECK(slurry_volume_ml>0),
 slurry_source_batch VARCHAR(255) NOT NULL CHECK(CHAR_LENGTH(TRIM(slurry_source_batch))>0),
 slurry_generation INTEGER NOT NULL CHECK(slurry_generation>=0),
 FOREIGN KEY(session_id,pitch_mode_id) REFERENCES sessions(session_id,pitch_mode_id) ON DELETE CASCADE
) ENGINE=InnoDB;


CREATE TABLE IF NOT EXISTS session_lifecycle_events (
    lifecycle_event_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    lifecycle VARCHAR(32) NOT NULL CHECK (lifecycle IN ('active','completed')),
    occurred_at DATETIME(3) NOT NULL,
    note TEXT,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_session_lifecycle_events__state (session_id,lifecycle),
    KEY idx_session_lifecycle_events__session_created (session_id,created_at),
    CONSTRAINT fk_session_lifecycle_events__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Operational release is a separate append-only fact. A released session remains
-- in MariaDB as history, but is no longer the current operator session.
CREATE TABLE IF NOT EXISTS session_release_events (
    release_event_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    released_at DATETIME(3) NOT NULL,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_session_release_events__session (session_id),
    UNIQUE KEY uq_session_release_events__operation (operation_id),
    KEY idx_session_release_events__released (released_at),
    CONSTRAINT fk_session_release_events__session FOREIGN KEY (session_id) REFERENCES sessions(session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_timing_revisions (
    timing_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    timing_field VARCHAR(32) NOT NULL CHECK (timing_field IN ('pitched_at','activity_started_at')),
    revision_no INTEGER NOT NULL CHECK (revision_no >= 1),
    supersedes_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    value_at DATETIME(3) NOT NULL,
    source VARCHAR(64) NOT NULL,
    reason TEXT,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_session_timing_revisions__revision (session_id,timing_field,revision_no),
    UNIQUE KEY uq_session_timing_revisions__timing_ref (session_id,timing_field,timing_revision_id),
    UNIQUE KEY uq_session_timing_revisions__supersedes (supersedes_revision_id),
    KEY idx_session_timing_revisions__session_created (session_id,created_at),
    CONSTRAINT fk_session_timing_revisions__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_timing_revisions__supersedes FOREIGN KEY (session_id,timing_field,supersedes_revision_id) REFERENCES session_timing_revisions(session_id,timing_field,timing_revision_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_fermentation_targets (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    expected_attenuation_min_percent DECIMAL(8,4) NOT NULL,
    expected_attenuation_max_percent DECIMAL(8,4) NOT NULL,
    expected_fg_min DECIMAL(7,5) NOT NULL,
    expected_fg_max DECIMAL(7,5) NOT NULL,
    source VARCHAR(64) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    CONSTRAINT fk_session_fermentation_targets__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CHECK (expected_attenuation_min_percent <= expected_attenuation_max_percent),
    CHECK (expected_fg_min <= expected_fg_max)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_fermentation_target_revisions (
    target_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    revision_no INTEGER NOT NULL CHECK (revision_no >= 1),
    supersedes_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    action VARCHAR(16) NOT NULL CHECK (action IN ('override','reset')),
    expected_fg_min DECIMAL(7,5) NOT NULL,
    expected_fg_max DECIMAL(7,5) NOT NULL,
    confirmed TINYINT NOT NULL CHECK (confirmed=1),
    note TEXT,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_session_fermentation_target_revisions__revision (session_id,revision_no),
    UNIQUE KEY uq_session_fermentation_target_revisions__target_ref (session_id,target_revision_id),
    UNIQUE KEY uq_session_fermentation_target_revisions__supersedes (supersedes_revision_id),
    KEY idx_session_fermentation_target_revisions__session_created (session_id,created_at),
    CONSTRAINT fk_session_fermentation_target_revisions__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_fermentation_target_revisions__supersedes FOREIGN KEY (session_id,supersedes_revision_id) REFERENCES session_fermentation_target_revisions(session_id,target_revision_id),
    CHECK (expected_fg_min <= expected_fg_max)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Frozen template identity and complete normalized session copy ---------------
CREATE TABLE IF NOT EXISTS session_template_snapshots (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    template_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    template_version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    template_version_label VARCHAR(64) NOT NULL,
    template_store_schema_version INTEGER NOT NULL CHECK (template_store_schema_version >= 1),
    snapshot_format_version VARCHAR(32) NOT NULL,
    snapshot_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    source_published_at DATETIME(3),
    created_at DATETIME(3) NOT NULL,
    CONSTRAINT fk_session_template_snapshots__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_template_snapshots__template FOREIGN KEY (template_id) REFERENCES templates(template_id),
    CONSTRAINT fk_session_template_snapshots__version FOREIGN KEY (template_version_id) REFERENCES template_versions(version_id),
    CHECK (CHAR_LENGTH(snapshot_sha256)=64)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_template_validation_warnings (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    warning_order INTEGER NOT NULL CHECK (warning_order >= 1),
    warning_code VARCHAR(128),
    warning_message TEXT NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,warning_order),
    CONSTRAINT fk_session_template_validation_warnings__snapshot FOREIGN KEY (session_id) REFERENCES session_template_snapshots(session_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_template_defaults (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    batch_name_default VARCHAR(255) NOT NULL,
    volume_l_default DECIMAL(10,3) NOT NULL CHECK (volume_l_default > 0),
    og_default DECIMAL(7,5) NOT NULL CHECK (og_default > 1.000 AND og_default <= 1.200),
    expected_attenuation_min_percent DECIMAL(8,4) NOT NULL,
    expected_attenuation_max_percent DECIMAL(8,4) NOT NULL,
    expected_fg_min DECIMAL(7,5) NOT NULL,
    expected_fg_max DECIMAL(7,5) NOT NULL,
    pitch_temperature_c_default DECIMAL(8,3) NOT NULL,
    pitch_mode_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    yeast_profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    yeast_amount_g_default DECIMAL(10,3),
    measurement_method_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    sample_temperature_c_default DECIMAL(8,3) NOT NULL,
    calibration_temperature_c_default DECIMAL(8,3) NOT NULL,
    manual_temperature_c_default DECIMAL(8,3) NOT NULL,
    pressure_bar_default DECIMAL(8,3) NOT NULL,
    cooler_setpoint_c_default DECIMAL(8,3) NOT NULL,
    cooler_calibration_offset_c_default DECIMAL(8,3) NOT NULL,
    airlock_activity_default VARCHAR(32) NOT NULL,
    acetaldehyde_level_default INTEGER NOT NULL,
    diacetyl_level_default INTEGER NOT NULL,
    wort_like_level_default INTEGER NOT NULL,
    sulfur_so2_level_default INTEGER NOT NULL,
    sulfur_h2s_level_default INTEGER NOT NULL,
    clarity_level_default INTEGER NOT NULL,
    settling_yeast_level_default INTEGER NOT NULL,
    settling_minutes_default DECIMAL(10,3) NOT NULL,
    user_conclusion_default VARCHAR(32) NOT NULL,
    measurement_note_default VARCHAR(255) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    CONSTRAINT fk_session_template_defaults__snapshot FOREIGN KEY (session_id) REFERENCES session_template_snapshots(session_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_template_defaults__pitch_mode FOREIGN KEY (pitch_mode_id) REFERENCES pitch_modes(pitch_mode_id),
    CONSTRAINT fk_session_template_defaults__yeast_profile FOREIGN KEY (yeast_profile_id) REFERENCES yeast_profiles(yeast_profile_id),
    CONSTRAINT fk_session_template_defaults__measurement_method FOREIGN KEY (measurement_method_id) REFERENCES measurement_methods(measurement_method_id),
    CHECK (expected_attenuation_min_percent <= expected_attenuation_max_percent),
    CHECK (expected_fg_min <= expected_fg_max)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_biology_calculations (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    calculation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,calculation_id),
    UNIQUE KEY uq_session_biology_calculations__model (session_id,calculation_id,model_id),
    CONSTRAINT fk_session_biology_calculations__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_biology_calculations__type_model FOREIGN KEY (calculation_id,model_id) REFERENCES biology_calculation_type_models(calculation_id,model_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE IF NOT EXISTS session_biology_calculation_inputs (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    calculation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    input_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    source_kind VARCHAR(32) NOT NULL CHECK (source_kind IN ('series','observation','session_field','biology_state','metric')),
    source_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,calculation_id,input_id),
    CONSTRAINT fk_session_biology_calc_inputs__calc FOREIGN KEY (session_id,calculation_id,model_id) REFERENCES session_biology_calculations(session_id,calculation_id,model_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_biology_calc_inputs__model FOREIGN KEY (model_id,input_id) REFERENCES calculation_model_inputs(model_id,input_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_biology_calculation_parameter_values (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    calculation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    data_type VARCHAR(32) NOT NULL CHECK (data_type IN ('real','integer','boolean','text')),
    real_value DECIMAL(18,6),
    integer_value BIGINT,
    boolean_value TINYINT CHECK (boolean_value IS NULL OR boolean_value IN (0,1)),
    text_value VARCHAR(255),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,calculation_id,parameter_id),
    CONSTRAINT fk_session_biology_calc_params__calc FOREIGN KEY (session_id,calculation_id,model_id) REFERENCES session_biology_calculations(session_id,calculation_id,model_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_biology_calc_params__model FOREIGN KEY (model_id,parameter_id,data_type) REFERENCES calculation_model_parameters(model_id,parameter_id,data_type),
    CHECK ((real_value IS NOT NULL) + (integer_value IS NOT NULL) + (boolean_value IS NOT NULL) + (text_value IS NOT NULL) = 1),
    CHECK ((data_type='real' AND real_value IS NOT NULL) OR
           (data_type='integer' AND integer_value IS NOT NULL) OR
           (data_type='boolean' AND boolean_value IS NOT NULL) OR
           (data_type='text' AND text_value IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_biology_calculation_median_first_samples (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    calculation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'median_first_samples' CHECK (model_id IN ('median_first_samples','pitch_baseline_median_v1')),
    sample_count INTEGER NOT NULL CHECK (sample_count > 0),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,calculation_id),
    CONSTRAINT fk_session_biology_calc_median__calc FOREIGN KEY (session_id,calculation_id,model_id) REFERENCES session_biology_calculations(session_id,calculation_id,model_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_biology_calculation_linear_regression (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    calculation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'linear_regression' CHECK (model_id IN ('linear_regression','robust_linear_regression_v1','endpoint_rate_v1')),
    window_hours DECIMAL(12,4) NOT NULL CHECK (window_hours > 0),
    minimum_samples INTEGER NOT NULL CHECK (minimum_samples >= 2),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,calculation_id),
    CONSTRAINT fk_session_biology_calc_regression__calc FOREIGN KEY (session_id,calculation_id,model_id) REFERENCES session_biology_calculations(session_id,calculation_id,model_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Frozen metric runtime rules -------------------------------------------------
-- A session carries the complete declarative metric semantics used by its
-- evaluators, so later registry changes cannot change historical evaluation.
CREATE TABLE IF NOT EXISTS session_metric_runtime_rules (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES metrics(metric_id),
    calculation_model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin REFERENCES calculation_models(model_id),
    freshness_mode VARCHAR(32) NOT NULL CHECK (freshness_mode IN ('source_timestamp','not_applicable')),
    valid_minimum_value DECIMAL(18,6),
    valid_maximum_value DECIMAL(18,6),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,metric_id),
    UNIQUE KEY uq_session_metric_runtime_rules__model (session_id,metric_id,calculation_model_id),
    CHECK (valid_minimum_value IS NULL OR valid_maximum_value IS NULL OR valid_minimum_value <= valid_maximum_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_metric_runtime_inputs (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES calculation_models(model_id),
    input_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    source_kind VARCHAR(32) NOT NULL CHECK (source_kind IN ('series','observation','session_field','biology_calculation','biology_state','metric')),
    source_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,metric_id,input_id),
    CONSTRAINT fk_session_metric_inputs__rule FOREIGN KEY(session_id,metric_id,model_id) REFERENCES session_metric_runtime_rules(session_id,metric_id,calculation_model_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_metric_inputs__model_input FOREIGN KEY(model_id,input_id) REFERENCES calculation_model_inputs(model_id,input_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_metric_runtime_parameter_values (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES calculation_models(model_id),
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    data_type VARCHAR(32) NOT NULL CHECK (data_type IN ('real','integer','boolean','text')),
    real_value DECIMAL(18,6),
    integer_value BIGINT,
    boolean_value TINYINT CHECK (boolean_value IS NULL OR boolean_value IN (0,1)),
    text_value VARCHAR(255),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,metric_id,parameter_id),
    CONSTRAINT fk_session_metric_params__rule FOREIGN KEY(session_id,metric_id,model_id) REFERENCES session_metric_runtime_rules(session_id,metric_id,calculation_model_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_metric_params__model_param FOREIGN KEY(model_id,parameter_id,data_type) REFERENCES calculation_model_parameters(model_id,parameter_id,data_type),
    CHECK ((real_value IS NOT NULL) + (integer_value IS NOT NULL) + (boolean_value IS NOT NULL) + (text_value IS NOT NULL) = 1),
    CHECK ((data_type='real' AND real_value IS NOT NULL) OR
           (data_type='integer' AND integer_value IS NOT NULL) OR
           (data_type='boolean' AND boolean_value IS NOT NULL) OR
           (data_type='text' AND text_value IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Frozen biological plan ------------------------------------------------------
CREATE TABLE IF NOT EXISTS session_biological_phases (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    phase_order INTEGER NOT NULL CHECK (phase_order BETWEEN 1 AND 30),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,phase_id),
    UNIQUE KEY uq_session_biological_phases__order (session_id,phase_order),
    CONSTRAINT fk_session_biological_phases__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_biological_criteria (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_order INTEGER NOT NULL CHECK (criterion_order >= 1),
    enabled TINYINT NOT NULL CHECK (enabled IN (0,1)),
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    role_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    label VARCHAR(255) NOT NULL,
    exception_allowed TINYINT NOT NULL DEFAULT 1 CHECK (exception_allowed IN (0,1)),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,phase_id,criterion_id),
    UNIQUE KEY uq_session_biological_criteria__order (session_id,phase_id,criterion_order),
    UNIQUE KEY uq_session_biological_criteria__model (session_id,phase_id,criterion_id,model_id),
    KEY idx_session_biological_criteria__metric_model (metric_id,model_id),
    CONSTRAINT fk_session_biological_criteria__phase FOREIGN KEY (session_id,phase_id) REFERENCES session_biological_phases(session_id,phase_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_biological_criteria__metric_model FOREIGN KEY (metric_id,model_id) REFERENCES criterion_metric_models(metric_id,model_id),
    CONSTRAINT fk_session_biological_criteria__role FOREIGN KEY (role_id) REFERENCES criterion_roles(role_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Parameter rows are domain-specific and constrained by the criterion model registry.
CREATE TABLE IF NOT EXISTS session_biological_criterion_parameter_values (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    data_type VARCHAR(32) NOT NULL CHECK (data_type IN ('real','integer','boolean','text')),
    real_value DECIMAL(18,6),
    integer_value BIGINT,
    boolean_value TINYINT CHECK (boolean_value IS NULL OR boolean_value IN (0,1)),
    text_value TEXT,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,phase_id,criterion_id,parameter_id),
    CONSTRAINT fk_session_bio_param_values__criterion FOREIGN KEY (session_id,phase_id,criterion_id,model_id) REFERENCES session_biological_criteria(session_id,phase_id,criterion_id,model_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_bio_param_values__parameter FOREIGN KEY (model_id,parameter_id,data_type) REFERENCES criterion_model_parameters(model_id,parameter_id,data_type),
    CHECK ((real_value IS NOT NULL) + (integer_value IS NOT NULL) + (boolean_value IS NOT NULL) + (text_value IS NOT NULL) = 1),
    CHECK ((data_type='real' AND real_value IS NOT NULL) OR
           (data_type='integer' AND integer_value IS NOT NULL) OR
           (data_type='boolean' AND boolean_value IS NOT NULL) OR
           (data_type='text' AND text_value IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_biological_correctable_parameters (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,phase_id,criterion_id,parameter_id),
    CONSTRAINT fk_session_bio_correctable__criterion FOREIGN KEY (session_id,phase_id,criterion_id,model_id) REFERENCES session_biological_criteria(session_id,phase_id,criterion_id,model_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_bio_correctable__parameter FOREIGN KEY (model_id,parameter_id) REFERENCES criterion_model_parameters(model_id,parameter_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_biological_criterion_revisions (
    criterion_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    revision_no INTEGER NOT NULL CHECK (revision_no >= 1),
    supersedes_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    action VARCHAR(16) NOT NULL CHECK (action IN ('override','reset')),
    confirmed TINYINT NOT NULL CHECK (confirmed=1),
    note TEXT,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_session_biological_criterion_revisions__revision (session_id,phase_id,criterion_id,revision_no),
    UNIQUE KEY uq_session_biological_criterion_revisions__criterion_ref (session_id,phase_id,criterion_id,criterion_revision_id),
    UNIQUE KEY uq_session_biological_criterion_revisions__supersedes (supersedes_revision_id),
    UNIQUE KEY uq_session_biological_criterion_revisions__model (criterion_revision_id,model_id),
    KEY idx_session_biological_criterion_revisions__session_created (session_id,created_at),
    CONSTRAINT fk_session_bio_criterion_revisions__criterion FOREIGN KEY (session_id,phase_id,criterion_id,model_id) REFERENCES session_biological_criteria(session_id,phase_id,criterion_id,model_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_bio_criterion_revisions__supersedes FOREIGN KEY (session_id,phase_id,criterion_id,supersedes_revision_id) REFERENCES session_biological_criterion_revisions(session_id,phase_id,criterion_id,criterion_revision_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_biological_criterion_revision_parameter_values (
    criterion_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    data_type VARCHAR(32) NOT NULL CHECK (data_type IN ('real','integer','boolean','text')),
    is_unset TINYINT NOT NULL DEFAULT 0 CHECK(is_unset IN (0,1)),
    real_value DECIMAL(18,6),
    integer_value BIGINT,
    boolean_value TINYINT CHECK (boolean_value IS NULL OR boolean_value IN (0,1)),
    text_value TEXT,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(criterion_revision_id,parameter_id),
    CONSTRAINT fk_session_bio_revision_param__revision FOREIGN KEY (criterion_revision_id,model_id) REFERENCES session_biological_criterion_revisions(criterion_revision_id,model_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_bio_revision_param__parameter FOREIGN KEY (model_id,parameter_id,data_type) REFERENCES criterion_model_parameters(model_id,parameter_id,data_type),
    CHECK ((real_value IS NOT NULL) + (integer_value IS NOT NULL) + (boolean_value IS NOT NULL) + (text_value IS NOT NULL) = 1-is_unset),
    CHECK (is_unset=1 OR (data_type='real' AND real_value IS NOT NULL) OR
           (data_type='integer' AND integer_value IS NOT NULL) OR
           (data_type='boolean' AND boolean_value IS NOT NULL) OR
           (data_type='text' AND text_value IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Frozen process plan ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS session_process_steps (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    slot_no INTEGER NOT NULL CHECK (slot_no BETWEEN 1 AND 15),
    process_order INTEGER NOT NULL CHECK (process_order BETWEEN 1 AND 15),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    enabled TINYINT NOT NULL CHECK (enabled IN (0,1)),
    historical_replay_auto_transition_allowed TINYINT NOT NULL DEFAULT 0 CHECK (historical_replay_auto_transition_allowed IN (0,1)),
    anchor_type VARCHAR(64),
    anchor_biological_phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    anchor_offset_hours DECIMAL(12,4),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,process_id),
    UNIQUE KEY uq_session_process_steps__order (session_id,process_order),
    CONSTRAINT fk_session_process_steps__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_process_steps__bio_anchor FOREIGN KEY (session_id,anchor_biological_phase_id) REFERENCES session_biological_phases(session_id,phase_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_process_targets (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    target_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    target_order INTEGER NOT NULL CHECK (target_order >= 1),
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    label VARCHAR(255) NOT NULL,
    purpose TEXT,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,process_id,target_id),
    UNIQUE KEY uq_session_process_targets__order (session_id,process_id,target_order),
    UNIQUE KEY uq_session_process_targets__model (session_id,process_id,target_id,model_id),
    CONSTRAINT fk_session_process_targets__step FOREIGN KEY (session_id,process_id) REFERENCES session_process_steps(session_id,process_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_process_targets__metric_model FOREIGN KEY (metric_id,model_id) REFERENCES target_metric_models(metric_id,model_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_process_target_exact (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    target_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'exact' CHECK (model_id='exact'),
    target_value DECIMAL(18,6) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,process_id,target_id),
    CONSTRAINT fk_session_process_target_exact__target FOREIGN KEY (session_id,process_id,target_id,model_id) REFERENCES session_process_targets(session_id,process_id,target_id,model_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_process_target_range (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    target_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'range' CHECK (model_id='range'),
    minimum_value DECIMAL(18,6) NOT NULL,
    maximum_value DECIMAL(18,6) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,process_id,target_id),
    CONSTRAINT fk_session_process_target_range__target FOREIGN KEY (session_id,process_id,target_id,model_id) REFERENCES session_process_targets(session_id,process_id,target_id,model_id) ON DELETE CASCADE,
    CHECK (minimum_value <= maximum_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_process_actions (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    action_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    action_order INTEGER NOT NULL CHECK (action_order >= 1),
    action_type_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    label VARCHAR(255) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,process_id,action_id),
    UNIQUE KEY uq_session_process_actions__order (session_id,process_id,action_order),
    UNIQUE KEY uq_session_process_actions__type (session_id,process_id,action_id,action_type_id),
    CONSTRAINT fk_session_process_actions__step FOREIGN KEY (session_id,process_id) REFERENCES session_process_steps(session_id,process_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_process_actions__type FOREIGN KEY (action_type_id) REFERENCES action_types(action_type_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_process_action_set_target (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    action_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    action_type_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'set_target' CHECK (action_type_id='set_target'),
    target_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,process_id,action_id),
    CONSTRAINT fk_session_process_action_set_target__action FOREIGN KEY (session_id,process_id,action_id,action_type_id) REFERENCES session_process_actions(session_id,process_id,action_id,action_type_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_process_action_set_target__target FOREIGN KEY (session_id,process_id,target_id) REFERENCES session_process_targets(session_id,process_id,target_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_process_action_operator (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    action_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    action_type_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'operator_action' CHECK (action_type_id='operator_action'),
    operator_operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,process_id,action_id),
    CONSTRAINT fk_session_process_action_operator__action FOREIGN KEY (session_id,process_id,action_id,action_type_id) REFERENCES session_process_actions(session_id,process_id,action_id,action_type_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_process_action_operator__operation FOREIGN KEY (operator_operation_id) REFERENCES operator_operations(operation_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_process_criteria (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_order INTEGER NOT NULL CHECK (criterion_order >= 1),
    enabled TINYINT NOT NULL CHECK (enabled IN (0,1)),
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    role_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    label VARCHAR(255) NOT NULL,
    exception_allowed TINYINT NOT NULL DEFAULT 0 CHECK (exception_allowed IN (0,1)),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,process_id,criterion_id),
    UNIQUE KEY uq_session_process_criteria__order (session_id,process_id,criterion_order),
    UNIQUE KEY uq_session_process_criteria__model (session_id,process_id,criterion_id,model_id),
    KEY idx_session_process_criteria__metric_model (metric_id,model_id),
    CONSTRAINT fk_session_process_criteria__step FOREIGN KEY (session_id,process_id) REFERENCES session_process_steps(session_id,process_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_process_criteria__metric_model FOREIGN KEY (metric_id,model_id) REFERENCES criterion_metric_models(metric_id,model_id),
    CONSTRAINT fk_session_process_criteria__role FOREIGN KEY (role_id) REFERENCES criterion_roles(role_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_process_criterion_parameter_values (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    data_type VARCHAR(32) NOT NULL CHECK (data_type IN ('real','integer','boolean','text')),
    real_value DECIMAL(18,6),
    integer_value BIGINT,
    boolean_value TINYINT CHECK (boolean_value IS NULL OR boolean_value IN (0,1)),
    text_value TEXT,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,process_id,criterion_id,parameter_id),
    CONSTRAINT fk_session_process_param_values__criterion FOREIGN KEY (session_id,process_id,criterion_id,model_id) REFERENCES session_process_criteria(session_id,process_id,criterion_id,model_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_process_param_values__parameter FOREIGN KEY (model_id,parameter_id,data_type) REFERENCES criterion_model_parameters(model_id,parameter_id,data_type),
    CHECK ((real_value IS NOT NULL) + (integer_value IS NOT NULL) + (boolean_value IS NOT NULL) + (text_value IS NOT NULL) = 1),
    CHECK ((data_type='real' AND real_value IS NOT NULL) OR
           (data_type='integer' AND integer_value IS NOT NULL) OR
           (data_type='boolean' AND boolean_value IS NOT NULL) OR
           (data_type='text' AND text_value IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_process_correctable_parameters (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,process_id,criterion_id,parameter_id),
    CONSTRAINT fk_session_process_correctable__criterion FOREIGN KEY (session_id,process_id,criterion_id,model_id) REFERENCES session_process_criteria(session_id,process_id,criterion_id,model_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_process_correctable__parameter FOREIGN KEY (model_id,parameter_id) REFERENCES criterion_model_parameters(model_id,parameter_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_process_criterion_revisions (
    criterion_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    revision_no INTEGER NOT NULL CHECK (revision_no >= 1),
    supersedes_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    action VARCHAR(16) NOT NULL CHECK (action IN ('override','reset')),
    confirmed TINYINT NOT NULL CHECK (confirmed=1),
    note TEXT,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_session_process_criterion_revisions__revision (session_id,process_id,criterion_id,revision_no),
    UNIQUE KEY uq_session_process_criterion_revisions__criterion_ref (session_id,process_id,criterion_id,criterion_revision_id),
    UNIQUE KEY uq_session_process_criterion_revisions__supersedes (supersedes_revision_id),
    UNIQUE KEY uq_session_process_criterion_revisions__model (criterion_revision_id,model_id),
    KEY idx_session_process_criterion_revisions__session_created (session_id,created_at),
    CONSTRAINT fk_session_process_criterion_revisions__criterion FOREIGN KEY (session_id,process_id,criterion_id,model_id) REFERENCES session_process_criteria(session_id,process_id,criterion_id,model_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_process_criterion_revisions__supersedes FOREIGN KEY (session_id,process_id,criterion_id,supersedes_revision_id) REFERENCES session_process_criterion_revisions(session_id,process_id,criterion_id,criterion_revision_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_process_criterion_revision_parameter_values (
    criterion_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    data_type VARCHAR(32) NOT NULL CHECK (data_type IN ('real','integer','boolean','text')),
    is_unset TINYINT NOT NULL DEFAULT 0 CHECK(is_unset IN (0,1)),
    real_value DECIMAL(18,6),
    integer_value BIGINT,
    boolean_value TINYINT CHECK (boolean_value IS NULL OR boolean_value IN (0,1)),
    text_value TEXT,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(criterion_revision_id,parameter_id),
    CONSTRAINT fk_session_process_revision_param__revision FOREIGN KEY (criterion_revision_id,model_id) REFERENCES session_process_criterion_revisions(criterion_revision_id,model_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_process_revision_param__parameter FOREIGN KEY (model_id,parameter_id,data_type) REFERENCES criterion_model_parameters(model_id,parameter_id,data_type),
    CHECK ((real_value IS NOT NULL) + (integer_value IS NOT NULL) + (boolean_value IS NOT NULL) + (text_value IS NOT NULL) = 1-is_unset),
    CHECK (is_unset=1 OR (data_type='real' AND real_value IS NOT NULL) OR
           (data_type='integer' AND integer_value IS NOT NULL) OR
           (data_type='boolean' AND boolean_value IS NOT NULL) OR
           (data_type='text' AND text_value IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Actual visits and revision history -----------------------------------------
CREATE TABLE IF NOT EXISTS process_visits (
    visit_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    visit_seq BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_process_visits__visit_seq (visit_seq),
    UNIQUE KEY uq_process_visits__session_process_visit (session_id,process_id,visit_id),
    KEY idx_process_visits__session_process (session_id,process_id),
    CONSTRAINT fk_process_visits__step FOREIGN KEY (session_id,process_id) REFERENCES session_process_steps(session_id,process_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS process_visit_revisions (
    visit_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    visit_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    revision_no INTEGER NOT NULL CHECK (revision_no >= 1),
    supersedes_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    started_at DATETIME(3) NOT NULL,
    ended_at DATETIME(3),
    timing_source VARCHAR(64) NOT NULL,
    revision_reason TEXT,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_process_visit_revisions__revision (visit_id,revision_no),
    UNIQUE KEY uq_process_visit_revisions__visit_ref (visit_id,visit_revision_id),
    UNIQUE KEY uq_process_visit_revisions__supersedes (supersedes_revision_id),
    KEY idx_process_visit_revisions__visit_created (visit_id,created_at),
    CONSTRAINT fk_process_visit_revisions__visit FOREIGN KEY (visit_id) REFERENCES process_visits(visit_id) ON DELETE CASCADE,
    CONSTRAINT fk_process_visit_revisions__supersedes FOREIGN KEY (visit_id,supersedes_revision_id) REFERENCES process_visit_revisions(visit_id,visit_revision_id),
    CHECK (ended_at IS NULL OR ended_at >= started_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS biological_visits (
    visit_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    visit_seq BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_biological_visits__visit_seq (visit_seq),
    UNIQUE KEY uq_biological_visits__session_phase_visit (session_id,phase_id,visit_id),
    KEY idx_biological_visits__session_phase (session_id,phase_id),
    CONSTRAINT fk_biological_visits__phase FOREIGN KEY (session_id,phase_id) REFERENCES session_biological_phases(session_id,phase_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Biological evaluations replace p18 criteria_snapshot_json ------------------
CREATE TABLE IF NOT EXISTS biological_evaluations (
    evaluation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    current_phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    candidate_phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    active_visit_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    evaluated_at DATETIME(3) NOT NULL,
    outcome VARCHAR(32) NOT NULL CHECK (outcome IN ('met','not_met','invalid_configuration')),
    confidence VARCHAR(64),
    data_quality VARCHAR(64),
    summary TEXT,
    engine_version VARCHAR(96) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    KEY idx_biological_evaluations__session_evaluated (session_id,evaluated_at),
    CONSTRAINT fk_biological_evaluations__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CONSTRAINT fk_biological_evaluations__current_phase FOREIGN KEY (session_id,current_phase_id) REFERENCES session_biological_phases(session_id,phase_id),
    CONSTRAINT fk_biological_evaluations__candidate_phase FOREIGN KEY (session_id,candidate_phase_id) REFERENCES session_biological_phases(session_id,phase_id),
    CONSTRAINT fk_biological_evaluations__visit FOREIGN KEY (session_id,current_phase_id,active_visit_id) REFERENCES biological_visits(session_id,phase_id,visit_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS biological_evaluation_criteria (
    evaluation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    applied_exception_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    criterion_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    criterion_order INTEGER NOT NULL CHECK (criterion_order >= 1),
    role_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    met TINYINT CHECK (met IS NULL OR met IN (0,1)),
    valid TINYINT NOT NULL CHECK (valid IN (0,1)),
    evaluation_status VARCHAR(32) NOT NULL CHECK (evaluation_status IN ('met','not_met','missing_basis','missing_coverage','stale','invalid_configuration','not_evaluated')),
    actual_value DECIMAL(18,6),
    actual_text TEXT,
    measured_at DATETIME(3),
    source VARCHAR(128),
    data_window_started_at DATETIME(3),
    data_window_ended_at DATETIME(3),
    requested_window_seconds INTEGER CHECK (requested_window_seconds IS NULL OR requested_window_seconds >= 0),
    sample_count INTEGER CHECK (sample_count IS NULL OR sample_count >= 0),
    coverage_seconds INTEGER CHECK (coverage_seconds IS NULL OR coverage_seconds >= 0),
    latest_sample_at DATETIME(3),
    explanation TEXT,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(evaluation_id,criterion_id),
    UNIQUE KEY uq_bio_eval_criteria__session_ref(session_id,evaluation_id,criterion_id),
    UNIQUE KEY uq_biological_evaluation_criteria__model (evaluation_id,criterion_id,model_id),
    CONSTRAINT fk_biological_eval_criteria__evaluation FOREIGN KEY (evaluation_id) REFERENCES biological_evaluations(evaluation_id) ON DELETE CASCADE,
    CONSTRAINT fk_biological_eval_criteria__criterion FOREIGN KEY (session_id,phase_id,criterion_id,model_id) REFERENCES session_biological_criteria(session_id,phase_id,criterion_id,model_id),
    CONSTRAINT fk_biological_eval_criteria__revision FOREIGN KEY (criterion_revision_id) REFERENCES session_biological_criterion_revisions(criterion_revision_id),
    CONSTRAINT fk_biological_eval_criteria__role FOREIGN KEY (role_id) REFERENCES criterion_roles(role_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS biological_evaluation_criterion_parameter_values (
    evaluation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    data_type VARCHAR(32) NOT NULL CHECK (data_type IN ('real','integer','boolean','text')),
    real_value DECIMAL(18,6),
    integer_value BIGINT,
    boolean_value TINYINT CHECK (boolean_value IS NULL OR boolean_value IN (0,1)),
    text_value TEXT,
    is_unset TINYINT NOT NULL DEFAULT 0 CHECK (is_unset IN (0,1)),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(evaluation_id,criterion_id,parameter_id),
    CONSTRAINT fk_bio_eval_param__criterion FOREIGN KEY (evaluation_id,criterion_id,model_id) REFERENCES biological_evaluation_criteria(evaluation_id,criterion_id,model_id) ON DELETE CASCADE,
    CONSTRAINT fk_bio_eval_param__parameter FOREIGN KEY (model_id,parameter_id,data_type) REFERENCES criterion_model_parameters(model_id,parameter_id,data_type),
    CHECK ((real_value IS NOT NULL) + (integer_value IS NOT NULL) + (boolean_value IS NOT NULL) + (text_value IS NOT NULL) = 1-is_unset),
    CHECK (is_unset=1 OR (data_type='real' AND real_value IS NOT NULL) OR
           (data_type='integer' AND integer_value IS NOT NULL) OR
           (data_type='boolean' AND boolean_value IS NOT NULL) OR
           (data_type='text' AND text_value IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS biological_visit_revisions (
    visit_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    visit_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    revision_no INTEGER NOT NULL CHECK (revision_no >= 1),
    supersedes_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    started_at DATETIME(3) NOT NULL,
    ended_at DATETIME(3),
    timing_source VARCHAR(64) NOT NULL,
    confidence VARCHAR(64),
    evaluation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    revision_reason TEXT,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_biological_visit_revisions__revision (visit_id,revision_no),
    UNIQUE KEY uq_biological_visit_revisions__visit_ref (visit_id,visit_revision_id),
    UNIQUE KEY uq_biological_visit_revisions__supersedes (supersedes_revision_id),
    KEY idx_biological_visit_revisions__visit_created (visit_id,created_at),
    CONSTRAINT fk_biological_visit_revisions__visit FOREIGN KEY (visit_id) REFERENCES biological_visits(visit_id) ON DELETE CASCADE,
    CONSTRAINT fk_biological_visit_revisions__supersedes FOREIGN KEY (visit_id,supersedes_revision_id) REFERENCES biological_visit_revisions(visit_id,visit_revision_id),
    CONSTRAINT fk_biological_visit_revisions__evaluation FOREIGN KEY (evaluation_id) REFERENCES biological_evaluations(evaluation_id),
    CHECK (ended_at IS NULL OR ended_at >= started_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Measurements and manual observation history --------------------------------
CREATE TABLE IF NOT EXISTS measurements_raw (
    measurement_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    measured_at DATETIME(3) NOT NULL,
    received_at DATETIME(3) NOT NULL,
    source VARCHAR(64) NOT NULL,
    sg DECIMAL(7,5) NOT NULL,
    temperature_c DECIMAL(8,3) NOT NULL,
    pressure_bar DECIMAL(8,4) NOT NULL,
    rssi_dbm DECIMAL(8,3),
    created_at DATETIME(3) NOT NULL,
    KEY idx_measurements_raw__session_measured (session_id,measured_at),
    CONSTRAINT fk_measurements_raw__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS measurements_5m (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    bucket_at DATETIME(3) NOT NULL,
    sample_count INTEGER NOT NULL CHECK (sample_count >= 1),
    sg_min DECIMAL(7,5) NOT NULL,
    sg_mean DECIMAL(7,5) NOT NULL,
    sg_median DECIMAL(7,5) NOT NULL,
    sg_max DECIMAL(7,5) NOT NULL,
    temperature_min_c DECIMAL(8,3) NOT NULL,
    temperature_mean_c DECIMAL(8,3) NOT NULL,
    temperature_max_c DECIMAL(8,3) NOT NULL,
    pressure_min_bar DECIMAL(8,4),
    pressure_mean_bar DECIMAL(8,4),
    pressure_max_bar DECIMAL(8,4),
    rssi_min_dbm DECIMAL(8,3),
    rssi_mean_dbm DECIMAL(8,3),
    rssi_max_dbm DECIMAL(8,3),
    created_at DATETIME(3) NOT NULL,
    updated_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,bucket_at),
    CONSTRAINT fk_measurements_5m__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CHECK (sg_min <= sg_median AND sg_median <= sg_max),
    CHECK (sg_min <= sg_mean AND sg_mean <= sg_max),
    CHECK (temperature_min_c <= temperature_mean_c AND temperature_mean_c <= temperature_max_c),
    CHECK (pressure_min_bar IS NULL OR pressure_mean_bar IS NULL OR pressure_max_bar IS NULL OR (pressure_min_bar <= pressure_mean_bar AND pressure_mean_bar <= pressure_max_bar)),
    CHECK (rssi_min_dbm IS NULL OR rssi_mean_dbm IS NULL OR rssi_max_dbm IS NULL OR (rssi_min_dbm <= rssi_mean_dbm AND rssi_mean_dbm <= rssi_max_dbm))
,
    KEY idx_measurements_5m__read_change(session_id,updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS measurement_data_gaps (
    gap_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    source VARCHAR(64) NOT NULL,
    gap_started_at DATETIME(3) NOT NULL,
    gap_ended_at DATETIME(3),
    duration_seconds INTEGER,
    threshold_seconds INTEGER NOT NULL DEFAULT 900 CHECK (threshold_seconds > 0),
    detected_at DATETIME(3) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    KEY idx_measurement_data_gaps__session_started (session_id,gap_started_at),
    CONSTRAINT fk_measurement_data_gaps__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CHECK (gap_ended_at IS NULL OR gap_ended_at >= gap_started_at),
    CHECK (duration_seconds IS NULL OR duration_seconds >= threshold_seconds)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Home Assistant measurement source and per-session ingestion state ------------
CREATE TABLE IF NOT EXISTS measurement_source_profiles (
    source_profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    source_type VARCHAR(32) NOT NULL CHECK (source_type IN ('home_assistant')),
    poll_interval_seconds INTEGER NOT NULL DEFAULT 300 CHECK (poll_interval_seconds >= 60),
    gap_threshold_seconds INTEGER NOT NULL DEFAULT 300 CHECK (gap_threshold_seconds >= 60),
    fresh_age_minutes INTEGER NOT NULL CHECK (fresh_age_minutes >= 1),
    stale_age_minutes INTEGER NOT NULL CHECK (stale_age_minutes > fresh_age_minutes),
    status VARCHAR(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
    description TEXT,
    created_at DATETIME(3) NOT NULL,
    updated_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_measurement_source_profiles__active_name (name,status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_measurement_sources (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    source_profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    source_started_at DATETIME(3) NOT NULL,
    last_import_cutoff_at DATETIME(3) NOT NULL,
    last_success_at DATETIME(3),
    last_error TEXT,
    created_at DATETIME(3) NOT NULL,
    updated_at DATETIME(3) NOT NULL,
    CONSTRAINT fk_session_measurement_sources__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_measurement_sources__profile FOREIGN KEY (source_profile_id) REFERENCES measurement_source_profiles(source_profile_id),
    CHECK (last_import_cutoff_at >= source_started_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE IF NOT EXISTS demo_reference_profiles (
    profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    span_seconds INTEGER NOT NULL CHECK (span_seconds > 0),
    og DECIMAL(7,5) NOT NULL,
    source_kind VARCHAR(64) NOT NULL,
    source_note TEXT,
    interval_seconds INTEGER NOT NULL DEFAULT 300 CHECK(interval_seconds IN (300,3600)),
    selectable TINYINT NOT NULL DEFAULT 1 CHECK(selectable IN (0,1)),
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS demo_reference_measurements_5m (
    profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    offset_seconds INTEGER NOT NULL CHECK (offset_seconds >= 0),
    sample_count INTEGER NOT NULL CHECK (sample_count >= 1),
    sg_min DECIMAL(7,5) NOT NULL,
    sg_mean DECIMAL(7,5) NOT NULL,
    sg_median DECIMAL(7,5) NOT NULL,
    sg_max DECIMAL(7,5) NOT NULL,
    temperature_mean_c DECIMAL(8,3) NOT NULL,
    PRIMARY KEY(profile_id,offset_seconds),
    CONSTRAINT fk_demo_reference_measurements__profile FOREIGN KEY (profile_id) REFERENCES demo_reference_profiles(profile_id) ON DELETE CASCADE,
    CHECK (sg_min <= sg_median AND sg_median <= sg_max),
    CHECK (sg_min <= sg_mean AND sg_mean <= sg_max)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS demo_reference_state_markers (
    profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    marker_kind VARCHAR(32) NOT NULL CHECK (marker_kind IN ('biological_phase','process_step')),
    state_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    offset_seconds INTEGER NOT NULL CHECK (offset_seconds >= 0),
    template_version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    derivation TEXT NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(profile_id,marker_kind,state_id),
    CONSTRAINT fk_demo_reference_state_markers__profile FOREIGN KEY (profile_id) REFERENCES demo_reference_profiles(profile_id) ON DELETE CASCADE,
    CONSTRAINT fk_demo_reference_state_markers__template FOREIGN KEY (template_version_id) REFERENCES template_versions(version_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS demo_reference_data_gaps (
    profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    gap_no INTEGER NOT NULL CHECK (gap_no >= 1),
    gap_start_offset_seconds INTEGER NOT NULL CHECK (gap_start_offset_seconds >= 0),
    gap_end_offset_seconds INTEGER NOT NULL CHECK (gap_end_offset_seconds >= gap_start_offset_seconds),
    duration_seconds INTEGER NOT NULL CHECK (duration_seconds >= 0),
    threshold_seconds INTEGER NOT NULL DEFAULT 900 CHECK (threshold_seconds > 0),
    source VARCHAR(64) NOT NULL,
    note TEXT,
    PRIMARY KEY(profile_id,gap_no),
    CONSTRAINT fk_demo_reference_data_gaps__profile FOREIGN KEY (profile_id) REFERENCES demo_reference_profiles(profile_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS observation_rounds (
    observation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_observation_rounds__session_observation (session_id,observation_id),
    KEY idx_observation_rounds__session_created (session_id,created_at),
    CONSTRAINT fk_observation_rounds__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS observation_round_revisions (
    observation_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    observation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    revision_no INTEGER NOT NULL CHECK (revision_no >= 1),
    supersedes_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    status VARCHAR(16) NOT NULL CHECK (status IN ('active','disabled')),
    recorded_at DATETIME(3) NOT NULL,
    measurement_method_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    measured_sg DECIMAL(7,5) NOT NULL,
    sample_temperature_c DECIMAL(8,3) NOT NULL,
    calibration_temperature_c DECIMAL(8,3) NOT NULL,
    corrected_sg DECIMAL(7,5) NOT NULL,
    manual_temperature_c DECIMAL(8,3) NOT NULL,
    pressure_bar DECIMAL(8,4) NOT NULL,
    cooler_setpoint_c DECIMAL(8,3) NOT NULL,
    cooler_calibration_offset_c DECIMAL(8,3) NOT NULL,
    estimated_abv_percent DECIMAL(8,3),
    estimated_finished_abv_percent DECIMAL(8,3),
    airlock_activity VARCHAR(64) NOT NULL,
    acetaldehyde_level INTEGER NOT NULL,
    diacetyl_level INTEGER NOT NULL,
    wort_like_level INTEGER NOT NULL,
    sulfur_so2_level INTEGER NOT NULL,
    sulfur_h2s_level INTEGER NOT NULL,
    clarity_level INTEGER NOT NULL,
    settling_yeast_level INTEGER NOT NULL,
    settling_minutes DECIMAL(12,3) NOT NULL,
    user_conclusion VARCHAR(128) NOT NULL,
    calculated_conclusion VARCHAR(128),
    process_gate_status VARCHAR(64),
    corrected_sg_model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    abv_now_model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    estimated_finished_abv_model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    actual_og_used DECIMAL(7,5) NOT NULL,
    note TEXT,
    revision_reason TEXT,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_observation_round_revisions__revision (observation_id,revision_no),
    UNIQUE KEY uq_observation_round_revisions__observation_ref (observation_id,observation_revision_id),
    UNIQUE KEY uq_observation_round_revisions__supersedes (supersedes_revision_id),
    UNIQUE KEY uq_observation_round_revisions__session_ref (session_id,observation_id,observation_revision_id),
    KEY idx_observation_round_revisions__session_recorded (session_id,recorded_at),
    CONSTRAINT fk_observation_round_revisions__round FOREIGN KEY (session_id,observation_id) REFERENCES observation_rounds(session_id,observation_id) ON DELETE CASCADE,
    CONSTRAINT fk_observation_round_revisions__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CONSTRAINT fk_observation_round_revisions__supersedes FOREIGN KEY (observation_id,supersedes_revision_id) REFERENCES observation_round_revisions(observation_id,observation_revision_id),
    CONSTRAINT fk_observation_round_revisions__method FOREIGN KEY (measurement_method_id) REFERENCES measurement_methods(measurement_method_id),
    CONSTRAINT fk_observation_round_revisions__corrected_sg_model FOREIGN KEY (corrected_sg_model_id) REFERENCES calculation_models(model_id),
    CONSTRAINT fk_observation_round_revisions__abv_model FOREIGN KEY (abv_now_model_id) REFERENCES calculation_models(model_id),
    CONSTRAINT fk_observation_round_revisions__finished_abv_model FOREIGN KEY (estimated_finished_abv_model_id) REFERENCES calculation_models(model_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Process evaluations, criterion results and exceptions ----------------------
CREATE TABLE IF NOT EXISTS process_evaluations (
    evaluation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    current_process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    candidate_process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    active_visit_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    observation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    observation_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    evaluated_at DATETIME(3) NOT NULL,
    readiness VARCHAR(64) NOT NULL,
    data_quality VARCHAR(64),
    summary TEXT,
    recommended_temperature_c DECIMAL(8,3),
    recommended_pressure_bar DECIMAL(8,4),
    engine_version VARCHAR(96) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    KEY idx_process_evaluations__session_evaluated (session_id,evaluated_at),
    CONSTRAINT fk_process_evaluations__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CONSTRAINT fk_process_evaluations__current_process FOREIGN KEY (session_id,current_process_id) REFERENCES session_process_steps(session_id,process_id),
    CONSTRAINT fk_process_evaluations__candidate_process FOREIGN KEY (session_id,candidate_process_id) REFERENCES session_process_steps(session_id,process_id),
    CONSTRAINT fk_process_evaluations__visit FOREIGN KEY (session_id,current_process_id,active_visit_id) REFERENCES process_visits(session_id,process_id,visit_id),
    CONSTRAINT fk_process_evaluations__observation_revision FOREIGN KEY (session_id,observation_id,observation_revision_id) REFERENCES observation_round_revisions(session_id,observation_id,observation_revision_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS process_evaluation_criteria (
    evaluation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    candidate_process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    criterion_order INTEGER NOT NULL CHECK (criterion_order >= 1),
    role_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    met TINYINT CHECK (met IS NULL OR met IN (0,1)),
    valid TINYINT NOT NULL CHECK (valid IN (0,1)),
    evaluation_status VARCHAR(32) NOT NULL CHECK (evaluation_status IN ('met','not_met','missing_basis','missing_coverage','stale','invalid_configuration','not_evaluated')),
    actual_value DECIMAL(18,6),
    actual_text TEXT,
    measured_at DATETIME(3),
    source VARCHAR(128),
    data_window_started_at DATETIME(3),
    data_window_ended_at DATETIME(3),
    requested_window_seconds INTEGER CHECK (requested_window_seconds IS NULL OR requested_window_seconds >= 0),
    sample_count INTEGER CHECK (sample_count IS NULL OR sample_count >= 0),
    coverage_seconds INTEGER CHECK (coverage_seconds IS NULL OR coverage_seconds >= 0),
    latest_sample_at DATETIME(3),
    explanation TEXT,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(evaluation_id,criterion_id),
    UNIQUE KEY uq_process_evaluation_criteria__session_ref (session_id,evaluation_id,criterion_id),
    UNIQUE KEY uq_process_evaluation_criteria__model (evaluation_id,criterion_id,model_id),
    CONSTRAINT fk_process_evaluation_criteria__evaluation FOREIGN KEY (evaluation_id) REFERENCES process_evaluations(evaluation_id) ON DELETE CASCADE,
    CONSTRAINT fk_process_evaluation_criteria__criterion FOREIGN KEY (session_id,candidate_process_id,criterion_id,model_id) REFERENCES session_process_criteria(session_id,process_id,criterion_id,model_id),
    CONSTRAINT fk_process_evaluation_criteria__revision FOREIGN KEY (criterion_revision_id) REFERENCES session_process_criterion_revisions(criterion_revision_id),
    CONSTRAINT fk_process_evaluation_criteria__role FOREIGN KEY (role_id) REFERENCES criterion_roles(role_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS process_evaluation_criterion_parameter_values (
    evaluation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    data_type VARCHAR(32) NOT NULL CHECK (data_type IN ('real','integer','boolean','text')),
    real_value DECIMAL(18,6),
    integer_value BIGINT,
    boolean_value TINYINT CHECK (boolean_value IS NULL OR boolean_value IN (0,1)),
    text_value TEXT,
    is_unset TINYINT NOT NULL DEFAULT 0 CHECK (is_unset IN (0,1)),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(evaluation_id,criterion_id,parameter_id),
    CONSTRAINT fk_process_eval_param__criterion FOREIGN KEY (evaluation_id,criterion_id,model_id) REFERENCES process_evaluation_criteria(evaluation_id,criterion_id,model_id) ON DELETE CASCADE,
    CONSTRAINT fk_process_eval_param__parameter FOREIGN KEY (model_id,parameter_id,data_type) REFERENCES criterion_model_parameters(model_id,parameter_id,data_type),
    CHECK ((real_value IS NOT NULL) + (integer_value IS NOT NULL) + (boolean_value IS NOT NULL) + (text_value IS NOT NULL) = 1-is_unset),
    CHECK (is_unset=1 OR (data_type='real' AND real_value IS NOT NULL) OR
           (data_type='integer' AND integer_value IS NOT NULL) OR
           (data_type='boolean' AND boolean_value IS NOT NULL) OR
           (data_type='text' AND text_value IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS process_criterion_exceptions (
    exception_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    evaluation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    revision_no INTEGER NOT NULL CHECK (revision_no >= 1),
    supersedes_exception_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    action VARCHAR(16) NOT NULL CHECK (action IN ('register','withdraw')),
    exception_type VARCHAR(64) CHECK (exception_type IN ('akseptert_avvik','ikke_relevant','ugyldig_vurderingsgrunnlag')),
    confirmed TINYINT NOT NULL CHECK (confirmed=1),
    note TEXT,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_process_criterion_exceptions__revision (evaluation_id,criterion_id,revision_no),
    UNIQUE KEY uq_process_criterion_exceptions__exception_ref (evaluation_id,criterion_id,exception_id),
    UNIQUE KEY uq_process_criterion_exceptions__supersedes (supersedes_exception_id),
    KEY idx_process_criterion_exceptions__session_created (session_id,created_at),
    CONSTRAINT fk_process_criterion_exceptions__criterion FOREIGN KEY (session_id,evaluation_id,criterion_id) REFERENCES process_evaluation_criteria(session_id,evaluation_id,criterion_id) ON DELETE CASCADE,
    CONSTRAINT fk_process_criterion_exceptions__supersedes FOREIGN KEY (evaluation_id,criterion_id,supersedes_exception_id) REFERENCES process_criterion_exceptions(evaluation_id,criterion_id,exception_id),
    CHECK ((action='register' AND exception_type IS NOT NULL) OR (action='withdraw' AND exception_type IS NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Recommendations and resolution history ------------------------------------
CREATE TABLE IF NOT EXISTS recommendations (
    recommendation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    evaluation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    observation_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    severity VARCHAR(32) NOT NULL,
    rule_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    recommendation_type VARCHAR(96) NOT NULL,
    model_version VARCHAR(96),
    title VARCHAR(255) NOT NULL,
    explanation TEXT,
    source VARCHAR(255),
    uncertainty VARCHAR(64),
    supersedes_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_recommendations__recommendation_ref (session_id,rule_id,recommendation_id),
    UNIQUE KEY uq_recommendations__supersedes (supersedes_id),
    KEY idx_recommendations__session_created (session_id,created_at),
    CONSTRAINT fk_recommendations__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CONSTRAINT fk_recommendations__evaluation FOREIGN KEY (evaluation_id) REFERENCES process_evaluations(evaluation_id),
    CONSTRAINT fk_recommendations__observation_revision FOREIGN KEY (observation_revision_id) REFERENCES observation_round_revisions(observation_revision_id),
    CONSTRAINT fk_recommendations__supersedes FOREIGN KEY (session_id,rule_id,supersedes_id) REFERENCES recommendations(session_id,rule_id,recommendation_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS recommendation_resolutions (
    resolution_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    recommendation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    outcome VARCHAR(16) NOT NULL CHECK (outcome IN ('executed','dismissed')),
    actual_action TEXT,
    note TEXT,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_recommendation_resolutions__recommendation (recommendation_id),
    UNIQUE KEY uq_recommendation_resolutions__operation (operation_id),
    KEY idx_recommendation_resolutions__recommendation_created (recommendation_id,created_at),
    CONSTRAINT fk_recommendation_resolutions__recommendation FOREIGN KEY (recommendation_id) REFERENCES recommendations(recommendation_id) ON DELETE CASCADE,
    CONSTRAINT fk_recommendation_resolutions__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Transitions: typed facts + links to immutable evaluations ------------------
CREATE TABLE IF NOT EXISTS process_transitions (
    transition_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    transitioned_at DATETIME(3) NOT NULL,
    from_visit_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    to_visit_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    from_process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    to_process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    action VARCHAR(32) NOT NULL,
    evaluation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    recommendation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    recommended_temperature_c DECIMAL(8,3),
    recommended_pressure_bar DECIMAL(8,4),
    operator_temperature_setting_c DECIMAL(8,3),
    operator_pressure_setting_bar DECIMAL(8,4),
    note TEXT,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_process_transitions__operation (operation_id),
    KEY idx_process_transitions__session_transitioned (session_id,transitioned_at),
    CONSTRAINT fk_process_transitions__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CONSTRAINT fk_process_transitions__from_visit FOREIGN KEY (session_id,from_process_id,from_visit_id) REFERENCES process_visits(session_id,process_id,visit_id),
    CONSTRAINT fk_process_transitions__to_visit FOREIGN KEY (session_id,to_process_id,to_visit_id) REFERENCES process_visits(session_id,process_id,visit_id),
    CONSTRAINT fk_process_transitions__from_process FOREIGN KEY (session_id,from_process_id) REFERENCES session_process_steps(session_id,process_id),
    CONSTRAINT fk_process_transitions__to_process FOREIGN KEY (session_id,to_process_id) REFERENCES session_process_steps(session_id,process_id),
    CONSTRAINT fk_process_transitions__evaluation FOREIGN KEY (evaluation_id) REFERENCES process_evaluations(evaluation_id),
    CONSTRAINT fk_process_transitions__recommendation FOREIGN KEY (recommendation_id) REFERENCES recommendations(recommendation_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS process_transition_warnings (
    transition_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    warning_order INTEGER NOT NULL CHECK (warning_order >= 1),
    warning_code VARCHAR(128),
    warning_message TEXT NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(transition_id,warning_order),
    CONSTRAINT fk_process_transition_warnings__transition FOREIGN KEY (transition_id) REFERENCES process_transitions(transition_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS biological_transitions (
    transition_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    transitioned_at DATETIME(3) NOT NULL,
    from_visit_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    to_visit_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    from_phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    to_phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    transition_source VARCHAR(32) NOT NULL CHECK (transition_source IN ('automatic','manual_correction')),
    confidence VARCHAR(64),
    evaluation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    reason TEXT,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_biological_transitions__operation (operation_id),
    KEY idx_biological_transitions__session_transitioned (session_id,transitioned_at),
    CONSTRAINT fk_biological_transitions__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CONSTRAINT fk_biological_transitions__from_visit FOREIGN KEY (session_id,from_phase_id,from_visit_id) REFERENCES biological_visits(session_id,phase_id,visit_id),
    CONSTRAINT fk_biological_transitions__to_visit FOREIGN KEY (session_id,to_phase_id,to_visit_id) REFERENCES biological_visits(session_id,phase_id,visit_id),
    CONSTRAINT fk_biological_transitions__from_phase FOREIGN KEY (session_id,from_phase_id) REFERENCES session_biological_phases(session_id,phase_id),
    CONSTRAINT fk_biological_transitions__to_phase FOREIGN KEY (session_id,to_phase_id) REFERENCES session_biological_phases(session_id,phase_id),
    CONSTRAINT fk_biological_transitions__evaluation FOREIGN KEY (evaluation_id) REFERENCES biological_evaluations(evaluation_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Archive/export attempts preserve failures as well as verified success -------
CREATE TABLE IF NOT EXISTS session_export_attempts (
    attempt_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    export_kind VARCHAR(32) NOT NULL CHECK (export_kind='completed_archive'),
    attempt_no BIGINT UNSIGNED NOT NULL AUTO_INCREMENT UNIQUE,
    requested_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_session_export_attempts__number (session_id,export_kind,attempt_no),
    CONSTRAINT fk_session_export_attempts__session FOREIGN KEY(session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_exports (
    export_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    export_kind VARCHAR(32) NOT NULL CHECK (export_kind IN ('completed_archive','active_report')),
    attempt_no INTEGER NOT NULL CHECK (attempt_no >= 1),
    status VARCHAR(16) NOT NULL CHECK (status IN ('verified','failed')),
    archive_path TEXT,
    archive_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin,
    archive_bytes BIGINT UNSIGNED,
    report_path TEXT,
    report_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin,
    report_bytes BIGINT UNSIGNED,
    template_path TEXT,
    template_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin,
    template_bytes BIGINT UNSIGNED,
    error_message TEXT,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    completed_at DATETIME(3) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_session_exports__attempt (session_id,export_kind,attempt_no),
    KEY idx_session_exports__session_completed (session_id,completed_at),
    CONSTRAINT fk_session_exports__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CHECK ((status='verified' AND archive_path IS NOT NULL AND archive_sha256 IS NOT NULL AND error_message IS NULL) OR
           (status='failed' AND error_message IS NOT NULL)),
    CHECK (archive_sha256 IS NULL OR CHAR_LENGTH(archive_sha256)=64),
    CHECK (export_kind<>'completed_archive' OR status<>'verified' OR (archive_bytes>0 AND report_path IS NOT NULL AND report_sha256 REGEXP '^[0-9a-f]{64}$' AND archive_sha256 REGEXP '^[0-9a-f]{64}$' AND report_bytes>0 AND archive_bytes IS NOT NULL AND report_bytes IS NOT NULL AND template_path IS NOT NULL AND template_sha256 REGEXP '^[0-9a-f]{64}$' AND template_bytes IS NOT NULL AND template_bytes>0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Transfer metadata is operational bookkeeping. Archive contents are normalized
-- domain tables; upload chunks are temporary binary transport, never authority.
CREATE TABLE IF NOT EXISTS active_report_requests (
 report_seq BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
 session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 requested_at DATETIME(3) NOT NULL,
 FOREIGN KEY(session_id) REFERENCES sessions(session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_origins (
 template_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 origin_kind VARCHAR(16) NOT NULL CHECK(origin_kind IN ('system','own','imported')),
 original_template_id VARCHAR(128),original_version_id VARCHAR(128),
 import_operation_id VARCHAR(128) UNIQUE,source_sha256 CHAR(64),created_at DATETIME(3) NOT NULL,
 FOREIGN KEY(template_id) REFERENCES templates(template_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS archive_imports (
 import_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
 session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
 template_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 original_session_id VARCHAR(128) NOT NULL,source_export_id VARCHAR(128) NOT NULL,
 archive_sha256 CHAR(64) NOT NULL,template_sha256 CHAR(64) NOT NULL,
 imported_at DATETIME(3) NOT NULL,
 UNIQUE(original_session_id,archive_sha256,template_sha256),
 FOREIGN KEY(session_id) REFERENCES sessions(session_id),
 FOREIGN KEY(template_id) REFERENCES templates(template_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS archive_visibility_events (
 event_seq BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 visible TINYINT NOT NULL CHECK(visible IN (0,1)),
 operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
 occurred_at DATETIME(3) NOT NULL,
 FOREIGN KEY(session_id) REFERENCES sessions(session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS archive_uploads (
 upload_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 filename VARCHAR(255) NOT NULL,expected_bytes BIGINT UNSIGNED NOT NULL,
 expected_chunks INTEGER NOT NULL CHECK(expected_chunks>0),
 sha256 CHAR(64) NOT NULL,created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS archive_upload_chunks (
 upload_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 chunk_no INTEGER NOT NULL CHECK(chunk_no>=0),payload MEDIUMBLOB NOT NULL,
 created_at DATETIME(3) NOT NULL,PRIMARY KEY(upload_id,chunk_no),
 FOREIGN KEY(upload_id) REFERENCES archive_uploads(upload_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS archive_transfer_events (
 event_seq BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 action VARCHAR(32) NOT NULL,status VARCHAR(16) NOT NULL,
 message TEXT NOT NULL,session_id VARCHAR(128),template_id VARCHAR(128),
 source_session_id VARCHAR(128),source_template_id VARCHAR(128),
 batch_name VARCHAR(255),template_name VARCHAR(255),pitched_display VARCHAR(64),
 measurement_count BIGINT UNSIGNED,archive_path TEXT,template_path TEXT,report_path TEXT,
 occurred_at DATETIME(3) NOT NULL,
 KEY idx_archive_transfer_operation(operation_id,event_seq)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS demo_reference_synthetic_details (
 profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 offset_seconds INTEGER NOT NULL,pressure_bar DECIMAL(8,3),
 PRIMARY KEY(profile_id,offset_seconds),
 FOREIGN KEY(profile_id,offset_seconds) REFERENCES demo_reference_measurements_5m(profile_id,offset_seconds)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_notes (
    note_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    noted_at DATETIME(3) NOT NULL,
    note_text TEXT NOT NULL,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_session_notes__operation (operation_id),
    KEY idx_session_notes__session_noted (session_id,noted_at),
    CONSTRAINT fk_session_notes__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Operator action audit -------------------------------------------------------
CREATE TABLE IF NOT EXISTS operator_actions (
    action_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    action_name VARCHAR(128) NOT NULL,
    entity_id VARCHAR(255),
    label VARCHAR(255) NOT NULL,
    pressed_at DATETIME(3) NOT NULL,
    completed_at DATETIME(3) NOT NULL,
    outcome VARCHAR(32) NOT NULL,
    accepted TINYINT NOT NULL CHECK (accepted IN (0,1)),
    state_before VARCHAR(64),
    state_after VARCHAR(64),
    technical_error TEXT,
    field_error TEXT,
    detail_text TEXT,
    created_at DATETIME(3) NOT NULL,
    KEY idx_operator_actions__session_completed (session_id,completed_at),
    KEY idx_operator_actions__operation (operation_id),
    CONSTRAINT fk_operator_actions__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS operator_action_warnings (
    action_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    warning_order INTEGER NOT NULL CHECK (warning_order >= 1),
    warning_message TEXT NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(action_id,warning_order),
    CONSTRAINT fk_operator_action_warnings__action FOREIGN KEY (action_id) REFERENCES operator_actions(action_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Technical event history: no generic details payload ------------------------
CREATE TABLE IF NOT EXISTS technical_events (
    event_seq BIGINT UNSIGNED NOT NULL AUTO_INCREMENT UNIQUE,
    event_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    schema_version VARCHAR(32) NOT NULL DEFAULT '1.0',
    occurred_at DATETIME(3) NOT NULL,
    severity VARCHAR(16) NOT NULL CHECK (severity IN ('info','warning','error','critical')),
    event_type VARCHAR(32) NOT NULL CHECK (event_type IN ('event','issue_raised','issue_cleared')),
    code VARCHAR(128) NOT NULL,
    issue_key VARCHAR(255),
    subsystem VARCHAR(128) NOT NULL,
    source_component VARCHAR(128),
    source_node_id VARCHAR(128),
    source_node_name VARCHAR(255),
    source_type VARCHAR(128),
    operation VARCHAR(128),
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    process_step VARCHAR(128),
    correlation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    message TEXT NOT NULL,
    recoverable TINYINT NOT NULL CHECK (recoverable IN (0,1)),
    blocks_operation TINYINT NOT NULL CHECK (blocks_operation IN (0,1)),
    related_event_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    created_at DATETIME(3) NOT NULL,
    KEY idx_technical_events__occurred (occurred_at),
    KEY idx_technical_events__issue_occurred (issue_key,occurred_at),
    KEY idx_technical_events__correlation (correlation_id),
    KEY idx_technical_events__session_occurred (session_id,occurred_at),
    CONSTRAINT fk_technical_events__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CONSTRAINT fk_technical_events__related FOREIGN KEY (related_event_id) REFERENCES technical_events(event_id),
    CHECK ((event_type='event') OR issue_key IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- System check is history, not mutable JSON state -----------------------------
-- System-check catalog: semantics/expectations live in MariaDB; execution stays in Node-RED ----
CREATE TABLE IF NOT EXISTS system_check_definitions (
    check_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    label VARCHAR(255) NOT NULL,
    category VARCHAR(64) NOT NULL,
    enabled TINYINT NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
    sort_order INTEGER NOT NULL CHECK (sort_order >= 1),
    failure_severity VARCHAR(16) NOT NULL CHECK (failure_severity IN ('warning','error','critical')),
    expected_source VARCHAR(255),
    description TEXT,
    created_at DATETIME(3) NOT NULL,
    updated_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_system_check_definitions__sort (sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS system_check_expectations (
    check_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    expectation_key VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    expected_text VARCHAR(255),
    expected_number DECIMAL(18,6),
    created_at DATETIME(3) NOT NULL,
    updated_at DATETIME(3) NOT NULL,
    PRIMARY KEY(check_id,expectation_key),
    CONSTRAINT fk_system_check_expectations__definition FOREIGN KEY (check_id) REFERENCES system_check_definitions(check_id) ON DELETE CASCADE,
    CHECK ((expected_text IS NULL) <> (expected_number IS NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS frontend_publication_runs (
    publication_run_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    application_version VARCHAR(128) NOT NULL,
    status VARCHAR(16) NOT NULL CHECK (status IN ('ok','error')),
    published_at DATETIME(3),
    checked_at DATETIME(3) NOT NULL,
    manifest_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin,
    mount_verified TINYINT NOT NULL DEFAULT 0 CHECK (mount_verified IN (0,1)),
    error_message TEXT,
    created_at DATETIME(3) NOT NULL,
    CHECK ((status='ok' AND error_message IS NULL) OR status='error')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS frontend_publication_artifacts (
    publication_run_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    artifact_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    public_name VARCHAR(255) NOT NULL,
    source_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    published_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    bytes BIGINT NOT NULL CHECK (bytes >= 0),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(publication_run_id,artifact_id),
    CONSTRAINT fk_frontend_publication_artifacts__run FOREIGN KEY (publication_run_id) REFERENCES frontend_publication_runs(publication_run_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS system_check_runs (
    check_run_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    overall_status VARCHAR(32) NOT NULL,
    checked_at DATETIME(3) NOT NULL,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    created_at DATETIME(3) NOT NULL,
    KEY idx_system_check_runs__checked (checked_at),
    CONSTRAINT fk_system_check_runs__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS system_check_results (
    check_run_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    check_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    check_order INTEGER NOT NULL CHECK (check_order >= 1),
    status VARCHAR(32) NOT NULL,
    severity VARCHAR(16) NOT NULL CHECK (severity IN ('info','warning','error','critical')),
    summary TEXT NOT NULL,
    error_text TEXT,
    numeric_value DECIMAL(18,6),
    numeric_unit VARCHAR(64),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(check_run_id,check_id),
    UNIQUE KEY uq_system_check_results__order (check_run_id,check_order),
    CONSTRAINT fk_system_check_results__run FOREIGN KEY (check_run_id) REFERENCES system_check_runs(check_run_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Verification executions/results --------------------------------------------
-- Metadata is defined in the template schema. Executions/results are facts and
-- therefore append-only. A new execution never overwrites an earlier result.
CREATE TABLE IF NOT EXISTS verification_test_runs (
    run_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    application_version VARCHAR(96) NOT NULL,
    run_type VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL CHECK (run_type IN ('release','technical','functional','uat','mixed')),
    environment VARCHAR(128) NOT NULL,
    source VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL CHECK (source IN ('release_build','target_environment','operator','import')),
    started_at DATETIME(3) NOT NULL,
    completed_at DATETIME(3),
    overall_status VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL CHECK (overall_status IN ('running','pass','fail','blocked','partial')),
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    note TEXT,
    created_at DATETIME(3) NOT NULL,
    KEY idx_verification_test_runs__completed (completed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS verification_test_results (
    result_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    run_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    test_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    result_status VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL CHECK (result_status IN ('pass','fail','blocked','not_run')),
    observed_at DATETIME(3) NOT NULL,
    executor VARCHAR(255),
    note TEXT,
    evidence_ref VARCHAR(1024),
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_verification_test_results__run_test (run_id,test_id),
    KEY idx_verification_test_results__test_time (test_id,observed_at),
    CONSTRAINT fk_verification_test_results__run FOREIGN KEY(run_id) REFERENCES verification_test_runs(run_id) ON DELETE CASCADE,
    CONSTRAINT fk_verification_test_results__test FOREIGN KEY(test_id) REFERENCES verification_tests(test_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Pre-start operator draft: DB is still sole persistent source ----------------
CREATE TABLE IF NOT EXISTS session_setup_draft (
    draft_key VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY CHECK (draft_key='current'),
    template_version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    is_demo TINYINT NOT NULL DEFAULT 0 CHECK (is_demo IN (0,1)),
    demo_reference_profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    pitched_at DATETIME(3),
    pitch_time_mode VARCHAR(16) NOT NULL DEFAULT 'now' CHECK (pitch_time_mode IN ('now','specified')),
    batch_name VARCHAR(255),
    og DECIMAL(7,5),
    expected_attenuation_min_percent DECIMAL(8,4),
    expected_attenuation_max_percent DECIMAL(8,4),
    expected_fg_min DECIMAL(7,5) AS (CASE WHEN og IS NULL OR expected_attenuation_max_percent IS NULL THEN NULL ELSE ROUND(1 + (og - 1) * (1 - expected_attenuation_max_percent / 100), 5) END) STORED,
    expected_fg_max DECIMAL(7,5) AS (CASE WHEN og IS NULL OR expected_attenuation_min_percent IS NULL THEN NULL ELSE ROUND(1 + (og - 1) * (1 - expected_attenuation_min_percent / 100), 5) END) STORED,
    volume_l DECIMAL(10,3),
    pitch_mode_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    pitch_temperature_c DECIMAL(8,3),
    yeast_amount_g DECIMAL(10,3),
    slurry_volume_ml DECIMAL(12,3),
    slurry_source_batch VARCHAR(255),
    slurry_generation INTEGER,
    oxygenation_note TEXT,
    measurement_method_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    measured_sg DECIMAL(7,5),
    sample_temperature_c DECIMAL(8,3) NOT NULL,
    calibration_temperature_c DECIMAL(8,3) NOT NULL,
    manual_temperature_c DECIMAL(8,3) NOT NULL,
    pressure_bar DECIMAL(8,4) NOT NULL,
    cooler_setpoint_c DECIMAL(8,3) NOT NULL,
    cooler_calibration_offset_c DECIMAL(8,3) NOT NULL,
    airlock_activity VARCHAR(64) NOT NULL,
    acetaldehyde_level INTEGER NOT NULL,
    diacetyl_level INTEGER NOT NULL,
    wort_like_level INTEGER NOT NULL,
    sulfur_so2_level INTEGER NOT NULL,
    sulfur_h2s_level INTEGER NOT NULL,
    clarity_level INTEGER NOT NULL,
    settling_yeast_level INTEGER NOT NULL,
    settling_minutes DECIMAL(12,3) NOT NULL,
    user_conclusion VARCHAR(128) NOT NULL,
    measurement_note TEXT,
    note TEXT,
    saved_at DATETIME(3),
    created_at DATETIME(3) NOT NULL,
    updated_at DATETIME(3) NOT NULL,
    CONSTRAINT fk_session_setup_draft__demo_profile FOREIGN KEY (demo_reference_profile_id) REFERENCES demo_reference_profiles(profile_id),
    CONSTRAINT fk_session_setup_draft__template_version FOREIGN KEY (template_version_id) REFERENCES template_versions(version_id),
    CONSTRAINT fk_session_setup_draft__pitch_mode FOREIGN KEY (pitch_mode_id) REFERENCES pitch_modes(pitch_mode_id),
    CONSTRAINT fk_session_setup_draft__measurement_method FOREIGN KEY (measurement_method_id) REFERENCES measurement_methods(measurement_method_id),
    CHECK (expected_attenuation_min_percent IS NULL OR expected_attenuation_max_percent IS NULL OR expected_attenuation_min_percent <= expected_attenuation_max_percent),
    CHECK (expected_fg_min IS NULL OR expected_fg_max IS NULL OR expected_fg_min <= expected_fg_max),
    CHECK (measured_sg IS NULL OR (measured_sg >= 0.98 AND measured_sg <= 1.2)),
    CHECK (airlock_activity IS NULL OR airlock_activity IN ('none','sporadic','low','moderate','high','very_high')),
    CHECK (user_conclusion IS NULL OR user_conclusion IN ('ready','not_ready','uncertain'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Active-session operator measurement draft: MariaDB is sole input source ----
CREATE TABLE IF NOT EXISTS measurement_input_draft (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    measurement_method_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    measured_sg DECIMAL(7,5) NOT NULL,
    sample_temperature_c DECIMAL(8,3) NOT NULL,
    calibration_temperature_c DECIMAL(8,3) NOT NULL,
    manual_temperature_c DECIMAL(8,3) NOT NULL,
    pressure_bar DECIMAL(8,4) NOT NULL,
    cooler_setpoint_c DECIMAL(8,3) NOT NULL,
    cooler_calibration_offset_c DECIMAL(8,3) NOT NULL,
    airlock_activity VARCHAR(64) NOT NULL,
    acetaldehyde_level INTEGER NOT NULL,
    diacetyl_level INTEGER NOT NULL,
    wort_like_level INTEGER NOT NULL,
    sulfur_so2_level INTEGER NOT NULL,
    sulfur_h2s_level INTEGER NOT NULL,
    clarity_level INTEGER NOT NULL,
    settling_yeast_level INTEGER NOT NULL,
    settling_minutes DECIMAL(12,3) NOT NULL,
    user_conclusion VARCHAR(128) NOT NULL,
    measurement_note TEXT,
    created_at DATETIME(3) NOT NULL,
    updated_at DATETIME(3) NOT NULL,
    CONSTRAINT fk_measurement_input_draft__session FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CONSTRAINT fk_measurement_input_draft__method FOREIGN KEY (measurement_method_id) REFERENCES measurement_methods(measurement_method_id),
    CHECK (measured_sg >= 0.98 AND measured_sg <= 1.2),
    CHECK (airlock_activity IN ('none','sporadic','low','moderate','high','very_high')),
    CHECK (user_conclusion IN ('ready','not_ready','uncertain'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- p22r7 measurement validation policy and frozen session rules -----------------
CREATE TABLE IF NOT EXISTS measurement_source_validation_rules (
    source_profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    rule_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    signal_id VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL CHECK (signal_id IN ('sg','temperature','rssi')),
    rule_order INTEGER NOT NULL CHECK (rule_order >= 1),
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    enabled TINYINT NOT NULL CHECK (enabled IN (0,1)),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(source_profile_id,rule_id),
    UNIQUE KEY uq_measurement_source_validation_rules__order(source_profile_id,signal_id,rule_order),
    CONSTRAINT fk_measurement_source_validation_rules__profile FOREIGN KEY(source_profile_id) REFERENCES measurement_source_profiles(source_profile_id) ON DELETE CASCADE,
    CONSTRAINT fk_measurement_source_validation_rules__model FOREIGN KEY(model_id) REFERENCES measurement_validation_models(model_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS measurement_source_validation_rule_parameter_values (
    source_profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    rule_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    data_type VARCHAR(16) NOT NULL CHECK (data_type IN ('real','integer','boolean','text')),
    real_value DECIMAL(18,6), integer_value BIGINT, boolean_value TINYINT, text_value TEXT,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(source_profile_id,rule_id,parameter_id),
    CONSTRAINT fk_measurement_source_validation_rule_parameter_values__rule FOREIGN KEY(source_profile_id,rule_id) REFERENCES measurement_source_validation_rules(source_profile_id,rule_id) ON DELETE CASCADE,
 CHECK((real_value IS NOT NULL)+(integer_value IS NOT NULL)+(boolean_value IS NOT NULL)+(text_value IS NOT NULL)=1),
 CHECK((data_type='real' AND real_value IS NOT NULL) OR (data_type='integer' AND integer_value IS NOT NULL) OR (data_type='boolean' AND boolean_value IN(0,1)) OR (data_type='text' AND text_value IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_measurement_validation_rules (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    rule_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    signal_id VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL CHECK (signal_id IN ('sg','temperature','rssi')),
    rule_order INTEGER NOT NULL CHECK (rule_order >= 1),
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    enabled TINYINT NOT NULL CHECK (enabled IN (0,1)),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,rule_id),
    UNIQUE KEY uq_session_measurement_validation_rules__order(session_id,signal_id,rule_order),
    CONSTRAINT fk_session_measurement_validation_rules__session FOREIGN KEY(session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_measurement_validation_rules__model FOREIGN KEY(model_id) REFERENCES measurement_validation_models(model_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_measurement_validation_rule_parameter_values (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    rule_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    data_type VARCHAR(16) NOT NULL CHECK (data_type IN ('real','integer','boolean','text')),
    real_value DECIMAL(18,6), integer_value BIGINT, boolean_value TINYINT, text_value TEXT,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,rule_id,parameter_id),
    CONSTRAINT fk_session_measurement_validation_rule_parameter_values__rule FOREIGN KEY(session_id,rule_id) REFERENCES session_measurement_validation_rules(session_id,rule_id) ON DELETE CASCADE,
 CHECK((real_value IS NOT NULL)+(integer_value IS NOT NULL)+(boolean_value IS NOT NULL)+(text_value IS NOT NULL)=1),
 CHECK((data_type='real' AND real_value IS NOT NULL) OR (data_type='integer' AND integer_value IS NOT NULL) OR (data_type='boolean' AND boolean_value IN(0,1)) OR (data_type='text' AND text_value IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS measurement_ingest_quality_events (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    bucket_at DATETIME(3) NOT NULL,
    signal_id VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    received_count INTEGER NOT NULL CHECK (received_count >= 0),
    accepted_count INTEGER NOT NULL CHECK (accepted_count >= 0),
    rejected_count INTEGER NOT NULL CHECK (rejected_count >= 0),
    status VARCHAR(24) NOT NULL CHECK (status IN ('accepted','rejected','no_samples')),
    reason_code VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,bucket_at,signal_id),
    CONSTRAINT fk_measurement_ingest_quality_events__session FOREIGN KEY(session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CHECK (accepted_count + rejected_count <= received_count)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- p22r7 frozen, metadata-driven analysis and append-only values ----------------
CREATE TABLE IF NOT EXISTS session_analysis_graphs (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    graph_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    sort_order INTEGER NOT NULL CHECK (sort_order >= 1),
    label VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    unit VARCHAR(64) NOT NULL,
    display_decimals INTEGER NOT NULL CHECK (display_decimals BETWEEN 0 AND 6),
    y_axis_min DECIMAL(18,6),
    y_axis_max DECIMAL(18,6),
    y_axis_tick_step DECIMAL(18,6) CHECK (y_axis_tick_step IS NULL OR y_axis_tick_step > 0),
    y_axis_include_zero TINYINT NOT NULL DEFAULT 1 CHECK (y_axis_include_zero IN (0,1)),
    x_axis_mode VARCHAR(32) NOT NULL DEFAULT 'relative_day_date' CHECK (x_axis_mode IN ('relative_day_date')),
    enabled TINYINT NOT NULL CHECK (enabled IN (0,1)),
    show_biological_bands TINYINT NOT NULL CHECK (show_biological_bands IN (0,1)),
    show_process_markers TINYINT NOT NULL CHECK (show_process_markers IN (0,1)),
    show_criterion_markers TINYINT NOT NULL CHECK (show_criterion_markers IN (0,1)),
    gap_policy VARCHAR(32) NOT NULL CHECK (gap_policy IN ('measurement_gaps','none')),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,graph_id),
    UNIQUE KEY uq_session_analysis_graphs__order(session_id,sort_order),
    CONSTRAINT fk_session_analysis_graphs__session FOREIGN KEY(session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
    CHECK (y_axis_min IS NULL OR y_axis_max IS NULL OR y_axis_min < y_axis_max)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_analysis_graph_series (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    graph_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    series_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    sort_order INTEGER NOT NULL CHECK (sort_order >= 1),
    label VARCHAR(255) NOT NULL,
    source_kind VARCHAR(32) NOT NULL CHECK (source_kind IN ('metric','biological_criterion','process_criterion','measurement','comparison','observation','process_target','fermentation_target')),
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    owner_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    minimum_samples INTEGER CHECK (minimum_samples IS NULL OR minimum_samples > 0),
    minimum_coverage_fraction DECIMAL(8,6) CHECK (minimum_coverage_fraction IS NULL OR (minimum_coverage_fraction >= 0 AND minimum_coverage_fraction <= 1)),
    warmup_minutes INTEGER CHECK (warmup_minutes IS NULL OR warmup_minutes >= 0),
    valid_minimum_value DECIMAL(18,6),
    valid_maximum_value DECIMAL(18,6),
    provisional_allowed TINYINT NOT NULL CHECK (provisional_allowed IN (0,1)),
    provisional_minimum_samples INTEGER NOT NULL CHECK (provisional_minimum_samples >= 2),
    provisional_minimum_span_minutes DECIMAL(18,6) NOT NULL CHECK (provisional_minimum_span_minutes > 0),
    render_mode VARCHAR(16) NOT NULL DEFAULT 'line' CHECK (render_mode IN ('line','points','step')),
    band_model VARCHAR(32) NOT NULL CHECK (band_model IN ('none','sample_range','derived_input_range','regression_input_range','regression_sensitivity')),
    band_description TEXT NOT NULL,
    standard_color CHAR(7) NOT NULL CHECK (standard_color REGEXP '^#[0-9A-Fa-f]{6}$'),
    provisional_color CHAR(7) NOT NULL CHECK (provisional_color REGEXP '^#[0-9A-Fa-f]{6}$'),
    standard_dasharray VARCHAR(32) NOT NULL,
    provisional_dasharray VARCHAR(32) NOT NULL,
    band_opacity DECIMAL(4,3) NOT NULL CHECK (band_opacity > 0 AND band_opacity <= 1),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,graph_id,series_id),
    UNIQUE KEY uq_session_analysis_graph_series__order(session_id,graph_id,sort_order),
    CONSTRAINT fk_session_analysis_graph_series__graph FOREIGN KEY(session_id,graph_id) REFERENCES session_analysis_graphs(session_id,graph_id) ON DELETE CASCADE,
    CONSTRAINT fk_session_analysis_graph_series__metric FOREIGN KEY(metric_id) REFERENCES metrics(metric_id),
    CHECK ((source_kind NOT IN ('biological_criterion','process_criterion') AND metric_id IS NOT NULL AND owner_id IS NULL AND criterion_id IS NULL)
        OR (source_kind IN ('biological_criterion','process_criterion') AND metric_id IS NULL AND owner_id IS NOT NULL AND criterion_id IS NOT NULL)),
    CHECK (valid_minimum_value IS NULL OR valid_maximum_value IS NULL OR valid_minimum_value <= valid_maximum_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS analysis_series_values (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    graph_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    series_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    sample_at DATETIME(3) NOT NULL,
    basis_pitched_at DATETIME(3) NOT NULL,
    actual_value DECIMAL(24,9) NOT NULL,
    value_status VARCHAR(16) NOT NULL CHECK (value_status IN ('provisional','standard')),
    standard_basis_met TINYINT NOT NULL CHECK (standard_basis_met IN (0,1)),
    range_min_value DECIMAL(24,9),
    range_max_value DECIMAL(24,9),
    measured_at DATETIME(3), sample_count INTEGER, window_started_at DATETIME(3), window_ended_at DATETIME(3), requested_window_seconds INTEGER, coverage_seconds INTEGER,
    source_kind VARCHAR(32) NOT NULL, created_at DATETIME(3) NOT NULL,
    source_observation_revision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    basis_revision_key VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'base',
    PRIMARY KEY(session_id,graph_id,series_id,sample_at,basis_pitched_at,basis_revision_key),
    CONSTRAINT fk_analysis_values__observation_revision FOREIGN KEY(source_observation_revision_id) REFERENCES observation_round_revisions(observation_revision_id),
    CHECK (basis_revision_key=COALESCE(source_observation_revision_id,'base')),
    CONSTRAINT fk_analysis_series_values__series FOREIGN KEY(session_id,graph_id,series_id) REFERENCES session_analysis_graph_series(session_id,graph_id,series_id) ON DELETE CASCADE,
    CHECK ((value_status='standard' AND standard_basis_met=1) OR (value_status='provisional' AND standard_basis_met=0)),
    KEY idx_analysis_series_values__time(session_id,sample_at),
    KEY idx_analysis_series_values__latest(session_id,graph_id,series_id,basis_pitched_at,sample_at),
    KEY idx_analysis_series_values__created(session_id,created_at),
    CHECK (range_min_value IS NULL OR range_max_value IS NULL OR range_min_value <= actual_value),
    CHECK (range_min_value IS NULL OR range_max_value IS NULL OR actual_value <= range_max_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS analysis_validation_events (
    validation_event_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    graph_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    series_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    sample_at DATETIME(3) NOT NULL,
    basis_pitched_at DATETIME(3) NOT NULL,
    reason_code VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    CONSTRAINT fk_analysis_validation_events__series FOREIGN KEY(session_id,graph_id,series_id) REFERENCES session_analysis_graph_series(session_id,graph_id,series_id) ON DELETE CASCADE,
    UNIQUE KEY uq_analysis_validation_events__reason(session_id,graph_id,series_id,sample_at,basis_pitched_at,reason_code),
    KEY idx_analysis_validation_events__sample(session_id,sample_at)
,
    KEY idx_analysis_validation_events__read_change(session_id,created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS session_overview_graph_policy (
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    graph_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    band_model VARCHAR(32) NOT NULL CHECK (band_model IN ('none','sample_range')),
    band_description TEXT NOT NULL,
    band_opacity DECIMAL(4,3) NOT NULL CHECK (band_opacity > 0 AND band_opacity <= 1),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(session_id,graph_id),
    FOREIGN KEY(session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS biological_criterion_exceptions (
    exception_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    evaluation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    revision_no INTEGER NOT NULL CHECK (revision_no >= 1),
    supersedes_exception_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    action VARCHAR(16) NOT NULL CHECK (action IN ('register','withdraw')),
    exception_type VARCHAR(64) CHECK (exception_type IN ('akseptert_avvik','ikke_relevant','ugyldig_vurderingsgrunnlag')),
    confirmed TINYINT NOT NULL CHECK (confirmed=1),
    note TEXT,
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_biological_criterion_exceptions__revision (session_id,phase_id,criterion_id,revision_no),
    UNIQUE KEY uq_biological_criterion_exceptions__exception_ref (session_id,phase_id,criterion_id,exception_id),
    UNIQUE KEY uq_biological_criterion_exceptions__supersedes (supersedes_exception_id),
    KEY idx_biological_criterion_exceptions__session_created (session_id,created_at),
    CONSTRAINT fk_biological_criterion_exceptions__criterion FOREIGN KEY (session_id,evaluation_id,criterion_id) REFERENCES biological_evaluation_criteria(session_id,evaluation_id,criterion_id) ON DELETE CASCADE,
    CONSTRAINT fk_biological_criterion_exceptions__supersedes FOREIGN KEY (session_id,phase_id,criterion_id,supersedes_exception_id) REFERENCES biological_criterion_exceptions(session_id,phase_id,criterion_id,exception_id),
    FOREIGN KEY(session_id,phase_id) REFERENCES session_biological_phases(session_id,phase_id),
    CHECK ((action='register' AND exception_type IS NOT NULL) OR (action='withdraw' AND exception_type IS NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE biological_evaluation_criteria ADD CONSTRAINT fk_bio_eval_criteria__applied_exception
FOREIGN KEY(session_id,phase_id,criterion_id,applied_exception_id) REFERENCES biological_criterion_exceptions(session_id,phase_id,criterion_id,exception_id);

-- Qualified baseline is an immutable calculation fact, scoped to effective pitch.
CREATE TABLE IF NOT EXISTS session_calculation_baselines (
 session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 calculation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 pitched_at DATETIME(3) NOT NULL, baseline_value DECIMAL(18,6) NOT NULL,
 measured_at DATETIME(3) NOT NULL, window_started_at DATETIME(3) NOT NULL,
 window_ended_at DATETIME(3) NOT NULL, sample_count INTEGER NOT NULL CHECK(sample_count>=2),
 source VARCHAR(64) NOT NULL, created_at DATETIME(3) NOT NULL,
 PRIMARY KEY(session_id,calculation_id,pitched_at),
 FOREIGN KEY(session_id,calculation_id) REFERENCES session_biology_calculations(session_id,calculation_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- p24r7 explicit source resolution, shared selections and reference evidence.
CREATE TABLE IF NOT EXISTS measurement_statistics_hourly (
 statistic_seq BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 statistic_import_id CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
 session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 start_at DATETIME(3) NOT NULL,end_at DATETIME(3) NOT NULL,
 sg_min DOUBLE,sg_mean DOUBLE,sg_max DOUBLE,
 temperature_min_c DOUBLE,temperature_mean_c DOUBLE,temperature_max_c DOUBLE,
 rssi_min_dbm DOUBLE,rssi_mean_dbm DOUBLE,rssi_max_dbm DOUBLE,
 created_at DATETIME(3) NOT NULL,
 KEY idx_statistics_session_start(session_id,start_at,statistic_seq),
 CONSTRAINT fk_statistics_session FOREIGN KEY(session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
 CHECK(end_at=start_at+INTERVAL 1 HOUR)
,
    KEY idx_measurement_statistics_hourly__read_change(session_id,created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS measurement_gap_closures (
 gap_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 gap_ended_at DATETIME(3) NOT NULL,duration_seconds INTEGER NOT NULL CHECK(duration_seconds>=0),created_at DATETIME(3) NOT NULL,
 CONSTRAINT fk_gap_closure_gap FOREIGN KEY(gap_id) REFERENCES measurement_data_gaps(gap_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS demo_reference_measurement_details (
 profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,offset_seconds INTEGER NOT NULL,
 temperature_min_c DECIMAL(8,3),temperature_max_c DECIMAL(8,3),rssi_min_dbm DECIMAL(8,3),rssi_mean_dbm DECIMAL(8,3),rssi_max_dbm DECIMAL(8,3),source_kind VARCHAR(64) NOT NULL,
 PRIMARY KEY(profile_id,offset_seconds),
 CONSTRAINT fk_reference_detail_measurement FOREIGN KEY(profile_id,offset_seconds) REFERENCES demo_reference_measurements_5m(profile_id,offset_seconds) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS session_demo_sources (
 session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,interval_seconds INTEGER NOT NULL DEFAULT 300 CHECK(interval_seconds IN (300,3600)),created_at DATETIME(3) NOT NULL,
 CONSTRAINT fk_session_demo_session FOREIGN KEY(session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
 CONSTRAINT fk_session_demo_profile FOREIGN KEY(profile_id) REFERENCES demo_reference_profiles(profile_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS demo_profile_selection_events (
 selection_seq BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,selected_at DATETIME(3) NOT NULL,
 CONSTRAINT fk_demo_selection_profile FOREIGN KEY(profile_id) REFERENCES demo_reference_profiles(profile_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS graph_display_selection_events (
 selection_seq BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 source_kind VARCHAR(16) NOT NULL CHECK(source_kind IN ('none','reference','session')),
 reference_profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
 reference_session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
 interval_seconds INTEGER NOT NULL CHECK(interval_seconds IN (300,900,1800,3600)),
 window_hours INTEGER CHECK(window_hours IN (24,48,168)),
 operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,selected_at DATETIME(3) NOT NULL,
 CONSTRAINT fk_graph_selection_profile FOREIGN KEY(reference_profile_id) REFERENCES demo_reference_profiles(profile_id),
 CONSTRAINT fk_graph_selection_session FOREIGN KEY(reference_session_id) REFERENCES sessions(session_id),
 CHECK((source_kind='none' AND reference_profile_id IS NULL AND reference_session_id IS NULL) OR (source_kind='reference' AND reference_profile_id IS NOT NULL AND reference_session_id IS NULL) OR(source_kind='session' AND reference_session_id IS NOT NULL AND reference_profile_id IS NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS demo_reference_analysis_values (
 profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,graph_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,series_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,offset_seconds INTEGER NOT NULL,
 actual_value DECIMAL(18,9) NOT NULL,sample_count INTEGER NOT NULL,coverage_seconds INTEGER NOT NULL,window_seconds INTEGER NOT NULL,basis_display TEXT NOT NULL,
 PRIMARY KEY(profile_id,graph_id,series_id,offset_seconds),
 CONSTRAINT fk_reference_analysis_profile FOREIGN KEY(profile_id) REFERENCES demo_reference_profiles(profile_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Temporary archive catalogue and external checksum notices are transport metadata.
CREATE TABLE IF NOT EXISTS archive_import_candidates (
 candidate_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 template_upload_id VARCHAR(128) NOT NULL,session_upload_id VARCHAR(128),
 source_export_id VARCHAR(128) NOT NULL,source_session_id VARCHAR(128),
 template_name VARCHAR(255) NOT NULL,version_label VARCHAR(128) NOT NULL,
 batch_name VARCHAR(255),pitched_at VARCHAR(64),snapshot_kind VARCHAR(32),
 measurement_count BIGINT UNSIGNED NOT NULL,created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS archive_checksum_warnings (
 warning_seq BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 upload_id VARCHAR(128) NOT NULL,filename VARCHAR(255) NOT NULL,
 warning_kind VARCHAR(16) NOT NULL CHECK(warning_kind IN ('missing','unreadable','mismatch')),
 message TEXT NOT NULL,created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Operational publication receipts: no domain state or measurement cache.
CREATE TABLE IF NOT EXISTS read_model_publication_receipts (
 publication_seq BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 operation_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
 source_key CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 generated_at DATETIME(3) NOT NULL,
 published_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A historical session is an editing workspace with a finite domain clock.
-- The beginning is the session's authoritative pitched_at revision, not a copy.
CREATE TABLE IF NOT EXISTS session_history_windows (
 session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 ended_at DATETIME(3) NOT NULL,
 operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
 created_at DATETIME(3) NOT NULL,
 CONSTRAINT fk_session_history_windows__session FOREIGN KEY(session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Source-state classification is authoritative metadata, never a Function whitelist.
CREATE TABLE IF NOT EXISTS measurement_source_check_policy (
 source_state VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 check_status VARCHAR(32) NOT NULL CHECK(check_status IN ('ok','warning','error')),
 severity VARCHAR(16) NOT NULL CHECK(severity IN ('info','warning','error'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Production upgrade and DB-owned start input/diagnostics ---------------------
CREATE TABLE IF NOT EXISTS start_field_rules (
 entity_id VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 section_id VARCHAR(32) NOT NULL CHECK(section_id IN('pitch','measurement')),
 required_value TINYINT NOT NULL CHECK(required_value IN(0,1)),
 positive_required TINYINT NOT NULL CHECK(positive_required IN(0,1)),
 sort_order INTEGER NOT NULL UNIQUE,
 FOREIGN KEY(entity_id) REFERENCES ha_entity_input_bindings(entity_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS start_field_pitch_modes (
 entity_id VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 pitch_mode_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 PRIMARY KEY(entity_id,pitch_mode_id),
 FOREIGN KEY(entity_id) REFERENCES start_field_rules(entity_id),
 FOREIGN KEY(pitch_mode_id) REFERENCES pitch_modes(pitch_mode_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS session_start_attempts (
 attempt_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 requested_at DATETIME(3) NOT NULL,
 ready_to_start TINYINT NOT NULL CHECK(ready_to_start IN(0,1)),
 validation_message TEXT NOT NULL,
 template_version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
 pitch_mode_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
 FOREIGN KEY(template_version_id) REFERENCES template_versions(version_id) ON DELETE CASCADE,
 FOREIGN KEY(pitch_mode_id) REFERENCES pitch_modes(pitch_mode_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS session_start_attempt_fields (
 attempt_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 entity_id VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 observed_value TEXT,
 validation_status VARCHAR(24) NOT NULL CHECK(validation_status IN('ok','missing','invalid','not_applicable')),
 validation_message TEXT NOT NULL,
 PRIMARY KEY(attempt_id,entity_id),
 FOREIGN KEY(attempt_id) REFERENCES session_start_attempts(attempt_id) ON DELETE CASCADE,
 FOREIGN KEY(entity_id) REFERENCES ha_entity_input_bindings(entity_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS database_migrations (
 migration_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 checksum_sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 source_version VARCHAR(128) NOT NULL,
 target_version VARCHAR(128) NOT NULL,
 applied_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
