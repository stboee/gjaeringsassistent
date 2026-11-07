-- Gjæringsassistent – MariaDB template schema draft 1
-- Source model: p18r5 template-schema.sql; confirmed structurally identical in p19r10 migration 0002.
-- Target: MariaDB 12.3.3 / InnoDB
-- Domain JSON blobs: none.
-- Timestamps are DATETIME(3) and callers should supply UTC timestamps (seed uses UTC_TIMESTAMP(3)).

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
SET SESSION sql_mode = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';


CREATE TABLE IF NOT EXISTS template_database_metadata (
    metadata_id INTEGER PRIMARY KEY CHECK (metadata_id = 1),
    schema_version INTEGER NOT NULL CHECK (schema_version >= 1),
    application_version VARCHAR(96) NOT NULL,
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT IGNORE INTO template_database_metadata(metadata_id,schema_version,application_version,created_at)
VALUES (1,4,'pending-install-version',UTC_TIMESTAMP(3));

-- System metadata / machine-readable documentation --------------------------
-- These tables are the normative metadata source for HA integration, system
-- functions and information lineage. Node-RED contains the physical nodes, but
-- documentation and validation must read the metadata registry instead of
-- maintaining parallel hard-coded entity lists.
CREATE TABLE IF NOT EXISTS ha_entity_registry (
    entity_id VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    config_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    entity_type VARCHAR(32) NOT NULL CHECK (entity_type IN ('sensor','binary_sensor','number','select','text','button')),
    display_name VARCHAR(255) NOT NULL,
    direction VARCHAR(40) NOT NULL CHECK (direction IN ('nodered_to_home_assistant','home_assistant_to_nodered','bidirectional')),
    status VARCHAR(24) NOT NULL DEFAULT 'active' CHECK (status IN ('active','planned','deprecated')),
    required TINYINT NOT NULL DEFAULT 1 CHECK (required IN (0,1)),
    bootstrap_mode VARCHAR(32) NOT NULL CHECK (bootstrap_mode IN ('literal_then_runtime','runtime','registration_only')),
    bootstrap_value VARCHAR(512),
    bootstrap_slot INTEGER,
    runtime_node_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    bootstrap_node_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    sort_order INTEGER NOT NULL CHECK (sort_order >= 1),
    description TEXT,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_ha_entity_registry__config (config_id),
    UNIQUE KEY uq_ha_entity_registry__sort (sort_order),
    UNIQUE KEY uq_ha_entity_registry__bootstrap_slot (bootstrap_slot),
    CHECK ((entity_type='button' AND bootstrap_mode='registration_only' AND bootstrap_slot IS NULL AND bootstrap_node_id IS NULL)
        OR (entity_type<>'button' AND bootstrap_mode<>'registration_only' AND bootstrap_slot IS NOT NULL AND bootstrap_node_id IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS ha_entity_select_options (
    entity_id VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    option_order INTEGER NOT NULL CHECK (option_order >= 1),
    option_value VARCHAR(255) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(entity_id,option_order),
    UNIQUE KEY uq_ha_entity_select_options__value (entity_id,option_value),
    CONSTRAINT fk_ha_entity_select_options__entity FOREIGN KEY(entity_id) REFERENCES ha_entity_registry(entity_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS ha_entity_input_bindings (
    entity_id VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    converter_id VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL CHECK (converter_id IN ('text','number','integer','datetime','select')),
    session_field VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    measurement_field VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    mirror_session_field VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    fixed_session_field VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    fixed_session_value VARCHAR(255),
    created_at DATETIME(3) NOT NULL,
    CONSTRAINT fk_ha_entity_input_bindings__entity FOREIGN KEY(entity_id) REFERENCES ha_entity_registry(entity_id) ON DELETE CASCADE,
    CHECK (session_field IS NOT NULL OR measurement_field IS NOT NULL),
    CHECK ((fixed_session_field IS NULL AND fixed_session_value IS NULL) OR (fixed_session_field IS NOT NULL AND fixed_session_value IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS ha_entity_input_value_mappings (
    entity_id VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    ha_value VARCHAR(255) NOT NULL,
    database_value VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(entity_id,ha_value),
    UNIQUE(entity_id,database_value),
    CONSTRAINT fk_ha_entity_input_value_mappings__binding FOREIGN KEY(entity_id) REFERENCES ha_entity_input_bindings(entity_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS ha_entity_number_constraints (
    entity_id VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    minimum_value DECIMAL(18,6) NOT NULL,
    maximum_value DECIMAL(18,6) NOT NULL,
    step_value DECIMAL(18,6) NOT NULL CHECK (step_value > 0),
    input_mode VARCHAR(16) NOT NULL CHECK (input_mode IN ('box','slider')),
    created_at DATETIME(3) NOT NULL,
    CONSTRAINT fk_ha_entity_number_constraints__entity FOREIGN KEY(entity_id) REFERENCES ha_entity_registry(entity_id) ON DELETE CASCADE,
    CHECK (minimum_value <= maximum_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS ha_event_registry (
    event_type VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    direction VARCHAR(40) NOT NULL CHECK (direction IN ('nodered_to_home_assistant','home_assistant_to_nodered','bidirectional')),
    event_mode VARCHAR(32) NOT NULL CHECK (event_mode IN ('parameterized','fixed')),
    listener_node_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'active' CHECK (status IN ('active','planned','deprecated')),
    required TINYINT NOT NULL DEFAULT 1 CHECK (required IN (0,1)),
    description TEXT,
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS ha_entity_aliases (
    alias_entity_id VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    entity_id VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    alias_kind VARCHAR(24) NOT NULL CHECK (alias_kind IN ('legacy','known_collision')),
    enabled TINYINT NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
    created_at DATETIME(3) NOT NULL,
    CONSTRAINT fk_ha_entity_aliases__entity FOREIGN KEY(entity_id) REFERENCES ha_entity_registry(entity_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS system_functions (
    function_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    label VARCHAR(255) NOT NULL,
    subsystem VARCHAR(64) NOT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'active' CHECK (status IN ('active','planned','deprecated')),
    description TEXT NOT NULL,
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS information_objects (
    object_id VARCHAR(384) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    object_type VARCHAR(32) NOT NULL CHECK (object_type IN ('table','view','ha_entity','event','frontend_projection','registry')),
    object_name VARCHAR(320) NOT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'active' CHECK (status IN ('active','planned','deprecated')),
    requires_producer TINYINT NOT NULL DEFAULT 0 CHECK (requires_producer IN (0,1)),
    requires_consumer TINYINT NOT NULL DEFAULT 0 CHECK (requires_consumer IN (0,1)),
    description TEXT,
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_information_objects__type_name (object_type,object_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS function_information_dependencies (
    function_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    object_id VARCHAR(384) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    relation_type VARCHAR(24) NOT NULL CHECK (relation_type IN ('consumes','reads','writes','publishes','validates')),
    required TINYINT NOT NULL DEFAULT 1 CHECK (required IN (0,1)),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(function_id,object_id,relation_type),
    CONSTRAINT fk_function_information_dependencies__function FOREIGN KEY(function_id) REFERENCES system_functions(function_id) ON DELETE CASCADE,
    CONSTRAINT fk_function_information_dependencies__object FOREIGN KEY(object_id) REFERENCES information_objects(object_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Verification metadata -------------------------------------------------------
-- p23: requirements, verification requirements and tests are structured
-- metadata. They describe what shall be true and how it is verified; runtime
-- executions/results live in the runtime schema and are append-only.
CREATE TABLE IF NOT EXISTS verification_requirements_catalog (
    requirement_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    document_id VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    requirement_class VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'active' CHECK (status IN ('active','deprecated')),
    statement TEXT NOT NULL,
    source_ref VARCHAR(255) NOT NULL,
    sort_order INTEGER NOT NULL CHECK (sort_order >= 1),
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_verification_requirements_catalog__sort (sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS verification_decisions_catalog (
    decision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    decision TEXT NOT NULL,
    rationale TEXT NOT NULL,
    consequence TEXT NOT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'active' CHECK (status IN ('active','deprecated')),
    source_ref VARCHAR(255) NOT NULL,
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS verification_definitions (
    verification_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    verification_type VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL CHECK (verification_type IN ('technical','functional','uat','integration','inspection')),
    title VARCHAR(255) NOT NULL,
    acceptance_criterion TEXT NOT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'active' CHECK (status IN ('active','deprecated')),
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS verification_requirement_links (
    requirement_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    verification_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    required TINYINT NOT NULL DEFAULT 1 CHECK (required IN (0,1)),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(requirement_id,verification_id),
    CONSTRAINT fk_verification_requirement_links__requirement FOREIGN KEY(requirement_id) REFERENCES verification_requirements_catalog(requirement_id) ON DELETE CASCADE,
    CONSTRAINT fk_verification_requirement_links__verification FOREIGN KEY(verification_id) REFERENCES verification_definitions(verification_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS verification_decision_requirement_links (
    decision_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    requirement_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(decision_id,requirement_id),
    CONSTRAINT fk_verification_decision_requirement_links__decision FOREIGN KEY(decision_id) REFERENCES verification_decisions_catalog(decision_id) ON DELETE CASCADE,
    CONSTRAINT fk_verification_decision_requirement_links__requirement FOREIGN KEY(requirement_id) REFERENCES verification_requirements_catalog(requirement_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS verification_tests (
    test_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    test_type VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL CHECK (test_type IN ('TECH','FUNC','UAT')),
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    method_type VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    implementation_ref VARCHAR(512),
    automated TINYINT NOT NULL CHECK (automated IN (0,1)),
    status VARCHAR(24) NOT NULL DEFAULT 'active' CHECK (status IN ('active','deprecated')),
    sort_order INTEGER NOT NULL CHECK (sort_order >= 1),
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_verification_tests__sort (sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS verification_test_links (
    verification_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    test_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    required TINYINT NOT NULL DEFAULT 1 CHECK (required IN (0,1)),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(verification_id,test_id),
    CONSTRAINT fk_verification_test_links__verification FOREIGN KEY(verification_id) REFERENCES verification_definitions(verification_id) ON DELETE CASCADE,
    CONSTRAINT fk_verification_test_links__test FOREIGN KEY(test_id) REFERENCES verification_tests(test_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS verification_uat_steps (
    test_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    step_order INTEGER NOT NULL CHECK (step_order >= 1),
    instruction TEXT NOT NULL,
    expected_result TEXT NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(test_id,step_order),
    CONSTRAINT fk_verification_uat_steps__test FOREIGN KEY(test_id) REFERENCES verification_tests(test_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Engine-owned reference data -------------------------------------------------
CREATE TABLE IF NOT EXISTS metrics (
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    sort_order INTEGER NOT NULL CHECK (sort_order >= 1),
    label VARCHAR(255) NOT NULL,
    unit VARCHAR(64) NOT NULL,
    display_decimals INTEGER NOT NULL DEFAULT 2 CHECK (display_decimals BETWEEN 0 AND 6),
    source_class VARCHAR(32) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    UNIQUE(sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS criterion_roles (
    role_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    label VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS criterion_models (
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    label VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS criterion_model_parameters (
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES criterion_models(model_id) ON DELETE CASCADE,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    sort_order INTEGER NOT NULL CHECK (sort_order >= 1),
    label VARCHAR(255) NOT NULL,
    data_type VARCHAR(32) NOT NULL CHECK (data_type IN ('real','integer','boolean','text')),
    unit_source VARCHAR(32) NOT NULL CHECK (unit_source IN ('metric','fixed','none')),
    fixed_unit VARCHAR(64),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(model_id,parameter_id),
    UNIQUE KEY uq_criterion_model_parameters__typed (model_id,parameter_id,data_type),
    UNIQUE KEY uq_criterion_model_parameters__order (model_id,sort_order),
    CHECK ((unit_source='fixed' AND fixed_unit IS NOT NULL) OR unit_source!='fixed')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS criterion_metric_models (
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES metrics(metric_id) ON DELETE CASCADE,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES criterion_models(model_id) ON DELETE CASCADE,
    is_default TINYINT NOT NULL CHECK (is_default IN (0,1)),
    default_guard TINYINT AS (IF(is_default = 1, 1, NULL)) PERSISTENT,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(metric_id,model_id),
    UNIQUE KEY uq_criterion_metric_models__default (metric_id, default_guard)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS criterion_metric_threshold_defaults (
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY REFERENCES metrics(metric_id) ON DELETE CASCADE,
    minimum_value DECIMAL(18,6),
    maximum_value DECIMAL(18,6),
    maximum_age_minutes INTEGER CHECK (maximum_age_minutes IS NULL OR maximum_age_minutes > 0),
    created_at DATETIME(3) NOT NULL,
    CHECK (minimum_value IS NOT NULL OR maximum_value IS NOT NULL),
    CHECK (minimum_value IS NULL OR maximum_value IS NULL OR minimum_value <= maximum_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS criterion_metric_observation_defaults (
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY REFERENCES metrics(metric_id) ON DELETE CASCADE,
    maximum_age_minutes INTEGER CHECK (maximum_age_minutes IS NULL OR maximum_age_minutes > 0),
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS criterion_metric_window_median_range_defaults (
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY REFERENCES metrics(metric_id) ON DELETE CASCADE,
    window_minutes INTEGER NOT NULL CHECK (window_minutes > 0),
    minimum_samples INTEGER NOT NULL CHECK (minimum_samples > 0),
    maximum_age_minutes INTEGER CHECK (maximum_age_minutes IS NULL OR maximum_age_minutes > 0),
    minimum_value DECIMAL(18,6) NOT NULL,
    maximum_value DECIMAL(18,6) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    CHECK (minimum_value <= maximum_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS criterion_metric_stability_window_defaults (
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY REFERENCES metrics(metric_id) ON DELETE CASCADE,
    window_hours DECIMAL(18,6) NOT NULL CHECK (window_hours > 0),
    maximum_range_points DECIMAL(18,6) NOT NULL CHECK (maximum_range_points >= 0),
    minimum_samples INTEGER NOT NULL CHECK (minimum_samples > 0),
    minimum_span_hours DECIMAL(18,6) NOT NULL CHECK (minimum_span_hours >= 0),
    maximum_age_minutes INTEGER CHECK (maximum_age_minutes IS NULL OR maximum_age_minutes > 0),
    since_current_process_start TINYINT NOT NULL CHECK (since_current_process_start IN (0,1)),
    created_at DATETIME(3) NOT NULL,
    CHECK (minimum_span_hours <= window_hours)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS target_models (
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    label VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS target_metric_models (
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES metrics(metric_id) ON DELETE CASCADE,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES target_models(model_id) ON DELETE CASCADE,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(metric_id,model_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS action_types (
    action_type_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    label VARCHAR(255) NOT NULL,
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS operator_operations (
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    label VARCHAR(255) NOT NULL,
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS pitch_modes (
    pitch_mode_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    label VARCHAR(255) NOT NULL,
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS measurement_methods (
    measurement_method_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    label VARCHAR(255) NOT NULL,
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS yeast_profiles (
    yeast_profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS calculation_models (
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    label VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Declarative metric runtime rules -------------------------------------------
-- The database owns which generic calculation model a metric uses, its inputs,
-- parameters and freshness semantics. Node-RED implements the generic models;
-- it must not infer metric-specific domain rules from metric_id.
CREATE TABLE IF NOT EXISTS calculation_model_inputs (
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES calculation_models(model_id) ON DELETE CASCADE,
    input_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    sort_order INTEGER NOT NULL CHECK (sort_order >= 1),
    label VARCHAR(255) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(model_id,input_id),
    UNIQUE KEY uq_calculation_model_inputs__order (model_id,sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS calculation_model_parameters (
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES calculation_models(model_id) ON DELETE CASCADE,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    sort_order INTEGER NOT NULL CHECK (sort_order >= 1),
    label VARCHAR(255) NOT NULL,
    data_type VARCHAR(32) NOT NULL CHECK (data_type IN ('real','integer','boolean','text')),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(model_id,parameter_id),
    UNIQUE KEY uq_calculation_model_parameters__typed (model_id,parameter_id,data_type),
    UNIQUE KEY uq_calculation_model_parameters__order (model_id,sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS metric_runtime_rules (
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY REFERENCES metrics(metric_id) ON DELETE CASCADE,
    calculation_model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES calculation_models(model_id),
    freshness_mode VARCHAR(32) NOT NULL CHECK (freshness_mode IN ('source_timestamp','not_applicable')),
    valid_minimum_value DECIMAL(18,6),
    valid_maximum_value DECIMAL(18,6),
    created_at DATETIME(3) NOT NULL,
    UNIQUE KEY uq_metric_runtime_rules__model (metric_id,calculation_model_id),
    CHECK (valid_minimum_value IS NULL OR valid_maximum_value IS NULL OR valid_minimum_value <= valid_maximum_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS metric_runtime_inputs (
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES metric_runtime_rules(metric_id) ON DELETE CASCADE,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES calculation_models(model_id),
    input_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    source_kind VARCHAR(32) NOT NULL CHECK (source_kind IN ('series','observation','session_field','biology_calculation','biology_state','metric')),
    source_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(metric_id,input_id),
    FOREIGN KEY(metric_id,model_id) REFERENCES metric_runtime_rules(metric_id,calculation_model_id) ON DELETE CASCADE,
    FOREIGN KEY(model_id,input_id) REFERENCES calculation_model_inputs(model_id,input_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS metric_runtime_parameter_values (
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES metric_runtime_rules(metric_id) ON DELETE CASCADE,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES calculation_models(model_id),
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    data_type VARCHAR(32) NOT NULL CHECK (data_type IN ('real','integer','boolean','text')),
    real_value DECIMAL(18,6),
    integer_value BIGINT,
    boolean_value TINYINT CHECK (boolean_value IS NULL OR boolean_value IN (0,1)),
    text_value VARCHAR(255),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(metric_id,parameter_id),
    FOREIGN KEY(metric_id,model_id) REFERENCES metric_runtime_rules(metric_id,calculation_model_id) ON DELETE CASCADE,
    FOREIGN KEY(model_id,parameter_id,data_type) REFERENCES calculation_model_parameters(model_id,parameter_id,data_type),
    CHECK ((real_value IS NOT NULL) + (integer_value IS NOT NULL) + (boolean_value IS NOT NULL) + (text_value IS NOT NULL) = 1),
    CHECK ((data_type='real' AND real_value IS NOT NULL) OR
           (data_type='integer' AND integer_value IS NOT NULL) OR
           (data_type='boolean' AND boolean_value IS NOT NULL) OR
           (data_type='text' AND text_value IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS biology_calculation_types (
    calculation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    label VARCHAR(255) NOT NULL,
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS biology_calculation_type_models (
    calculation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES biology_calculation_types(calculation_id) ON DELETE CASCADE,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES calculation_models(model_id) ON DELETE CASCADE,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(calculation_id,model_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Template identity and lifecycle --------------------------------------------
CREATE TABLE IF NOT EXISTS templates (
    template_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_versions (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    template_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES templates(template_id) ON DELETE CASCADE,
    status VARCHAR(32) NOT NULL CHECK (status IN ('draft','published','retired')),
    version_label VARCHAR(64),
    based_on_version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin REFERENCES template_versions(version_id),
    name VARCHAR(255) NOT NULL,
    revision_note VARCHAR(1000),
    created_at DATETIME(3) NOT NULL,
    published_at DATETIME(3),
    retired_at DATETIME(3),
    draft_guard TINYINT AS (IF(status = 'draft', 1, NULL)) PERSISTENT,
    CHECK ((status='draft' AND version_label IS NULL AND published_at IS NULL AND retired_at IS NULL) OR
           (status='published' AND version_label IS NOT NULL AND published_at IS NOT NULL AND retired_at IS NULL) OR
           (status='retired' AND version_label IS NOT NULL AND published_at IS NOT NULL AND retired_at IS NOT NULL)),
    UNIQUE(template_id,version_label),
    UNIQUE KEY uq_template_versions__one_draft (template_id, draft_guard)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE INDEX IF NOT EXISTS idx_template_versions__template_id__status
ON template_versions(template_id,status);

-- Shared operator selection for the Template administration surface.
-- This is presentation/workflow state only; it never changes Start selection
-- and is persisted because multiple dashboards must observe the same editor target.
CREATE TABLE IF NOT EXISTS template_editor_state (
    state_key VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY CHECK (state_key='current'),
    selected_version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    updated_at DATETIME(3) NOT NULL,
    CONSTRAINT fk_template_editor_state__version FOREIGN KEY(selected_version_id) REFERENCES template_versions(version_id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Template-owned metric calculation semantics ---------------------------------
-- Registry rows above define the supported vocabulary/defaults. A concrete
-- template version materializes the calculation model, inputs, parameters and
-- freshness semantics that apply to that template. Start freezes these rows
-- into the session; runtime must never fall back to registry defaults.
CREATE TABLE IF NOT EXISTS template_metric_runtime_rules (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES template_versions(version_id) ON DELETE CASCADE,
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    calculation_model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    freshness_mode VARCHAR(32) NOT NULL CHECK (freshness_mode IN ('source_timestamp','not_applicable')),
    valid_minimum_value DECIMAL(18,6),
    valid_maximum_value DECIMAL(18,6),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,metric_id),
    UNIQUE KEY uq_template_metric_runtime_rules__model (version_id,metric_id,calculation_model_id),
    FOREIGN KEY(metric_id,calculation_model_id) REFERENCES metric_runtime_rules(metric_id,calculation_model_id),
    CHECK (valid_minimum_value IS NULL OR valid_maximum_value IS NULL OR valid_minimum_value <= valid_maximum_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_metric_runtime_inputs (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    input_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    source_kind VARCHAR(32) NOT NULL CHECK (source_kind IN ('series','observation','session_field','biology_calculation','biology_state','metric')),
    source_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,metric_id,input_id),
    FOREIGN KEY(version_id,metric_id,model_id) REFERENCES template_metric_runtime_rules(version_id,metric_id,calculation_model_id) ON DELETE CASCADE,
    FOREIGN KEY(model_id,input_id) REFERENCES calculation_model_inputs(model_id,input_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_metric_runtime_parameter_values (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    data_type VARCHAR(32) NOT NULL CHECK (data_type IN ('real','integer','boolean','text')),
    real_value DECIMAL(18,6),
    integer_value BIGINT,
    boolean_value TINYINT CHECK (boolean_value IS NULL OR boolean_value IN (0,1)),
    text_value VARCHAR(255),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,metric_id,parameter_id),
    FOREIGN KEY(version_id,metric_id,model_id) REFERENCES template_metric_runtime_rules(version_id,metric_id,calculation_model_id) ON DELETE CASCADE,
    FOREIGN KEY(model_id,parameter_id,data_type) REFERENCES calculation_model_parameters(model_id,parameter_id,data_type),
    CHECK ((real_value IS NOT NULL) + (integer_value IS NOT NULL) + (boolean_value IS NOT NULL) + (text_value IS NOT NULL) = 1),
    CHECK ((data_type='real' AND real_value IS NOT NULL) OR
           (data_type='integer' AND integer_value IS NOT NULL) OR
           (data_type='boolean' AND boolean_value IS NOT NULL) OR
           (data_type='text' AND text_value IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_defaults (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY REFERENCES template_versions(version_id) ON DELETE CASCADE,
    batch_name_default VARCHAR(255) NOT NULL CHECK (CHAR_LENGTH(TRIM(batch_name_default)) > 0),
    volume_l_default DECIMAL(18,6) NOT NULL CHECK (volume_l_default > 0),
    og_default DECIMAL(18,6) NOT NULL CHECK (og_default > 1.000 AND og_default <= 1.200),
    expected_attenuation_min_percent DECIMAL(8,4) NOT NULL CHECK (expected_attenuation_min_percent > 0 AND expected_attenuation_min_percent < 100),
    expected_attenuation_max_percent DECIMAL(8,4) NOT NULL CHECK (expected_attenuation_max_percent > 0 AND expected_attenuation_max_percent < 100),
    expected_fg_min DECIMAL(18,6) AS (ROUND(1 + (og_default - 1) * (1 - expected_attenuation_max_percent / 100), 6)) STORED,
    expected_fg_max DECIMAL(18,6) AS (ROUND(1 + (og_default - 1) * (1 - expected_attenuation_min_percent / 100), 6)) STORED,
    pitch_temperature_c_default DECIMAL(18,6) NOT NULL,
    pitch_mode_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES pitch_modes(pitch_mode_id),
    yeast_profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES yeast_profiles(yeast_profile_id),
    yeast_amount_g_default DECIMAL(18,6) CHECK (yeast_amount_g_default IS NULL OR yeast_amount_g_default > 0),
    measurement_method_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES measurement_methods(measurement_method_id),
    sample_temperature_c_default DECIMAL(18,6) NOT NULL,
    calibration_temperature_c_default DECIMAL(18,6) NOT NULL,
    manual_temperature_c_default DECIMAL(18,6) NOT NULL,
    pressure_bar_default DECIMAL(18,6) NOT NULL,
    cooler_setpoint_c_default DECIMAL(18,6) NOT NULL,
    cooler_calibration_offset_c_default DECIMAL(18,6) NOT NULL,
    airlock_activity_default VARCHAR(32) NOT NULL CHECK (airlock_activity_default IN ('none','sporadic','low','moderate','high','very_high')),
    acetaldehyde_level_default INTEGER NOT NULL CHECK (acetaldehyde_level_default BETWEEN 0 AND 5),
    diacetyl_level_default INTEGER NOT NULL CHECK (diacetyl_level_default BETWEEN 0 AND 5),
    wort_like_level_default INTEGER NOT NULL CHECK (wort_like_level_default BETWEEN 0 AND 5),
    sulfur_so2_level_default INTEGER NOT NULL CHECK (sulfur_so2_level_default BETWEEN 0 AND 5),
    sulfur_h2s_level_default INTEGER NOT NULL CHECK (sulfur_h2s_level_default BETWEEN 0 AND 5),
    clarity_level_default INTEGER NOT NULL CHECK (clarity_level_default BETWEEN 0 AND 5),
    settling_yeast_level_default INTEGER NOT NULL CHECK (settling_yeast_level_default BETWEEN 0 AND 5),
    settling_minutes_default DECIMAL(18,6) NOT NULL CHECK (settling_minutes_default BETWEEN 0 AND 1440),
    user_conclusion_default VARCHAR(32) NOT NULL CHECK (user_conclusion_default IN ('ready','not_ready','uncertain')),
    measurement_note_default VARCHAR(255) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    CHECK (expected_attenuation_min_percent <= expected_attenuation_max_percent),
    CHECK (expected_fg_min <= expected_fg_max)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Biology model --------------------------------------------------------------
CREATE TABLE IF NOT EXISTS template_biology_calculations (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES template_versions(version_id) ON DELETE CASCADE,
    calculation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES biology_calculation_types(calculation_id),
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES calculation_models(model_id),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,calculation_id),
    UNIQUE KEY uq_template_biology_calculations__model (version_id,calculation_id,model_id),
    FOREIGN KEY(calculation_id,model_id) REFERENCES biology_calculation_type_models(calculation_id,model_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Template-owned generic calculation semantics. Specialized tables below remain
-- compatibility projections for the editor; the motor reads these normalized
-- input/parameter rows after they are frozen into the session.
CREATE TABLE IF NOT EXISTS template_biology_calculation_inputs (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    calculation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    input_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    source_kind VARCHAR(32) NOT NULL CHECK (source_kind IN ('series','observation','session_field','biology_state','metric')),
    source_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,calculation_id,input_id),
    FOREIGN KEY(version_id,calculation_id,model_id) REFERENCES template_biology_calculations(version_id,calculation_id,model_id) ON DELETE CASCADE,
    FOREIGN KEY(model_id,input_id) REFERENCES calculation_model_inputs(model_id,input_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_biology_calculation_parameter_values (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    calculation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    data_type VARCHAR(32) NOT NULL CHECK (data_type IN ('real','integer','boolean','text')),
    real_value DECIMAL(18,6),
    integer_value BIGINT,
    boolean_value TINYINT CHECK (boolean_value IS NULL OR boolean_value IN (0,1)),
    text_value VARCHAR(255),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,calculation_id,parameter_id),
    FOREIGN KEY(version_id,calculation_id,model_id) REFERENCES template_biology_calculations(version_id,calculation_id,model_id) ON DELETE CASCADE,
    FOREIGN KEY(model_id,parameter_id,data_type) REFERENCES calculation_model_parameters(model_id,parameter_id,data_type),
    CHECK ((real_value IS NOT NULL) + (integer_value IS NOT NULL) + (boolean_value IS NOT NULL) + (text_value IS NOT NULL) = 1),
    CHECK ((data_type='real' AND real_value IS NOT NULL) OR
           (data_type='integer' AND integer_value IS NOT NULL) OR
           (data_type='boolean' AND boolean_value IS NOT NULL) OR
           (data_type='text' AND text_value IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_biology_calculation_median_first_samples (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    calculation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'median_first_samples' CHECK (model_id IN ('median_first_samples','pitch_baseline_median_v1')),
    sample_count INTEGER NOT NULL CHECK (sample_count > 0),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,calculation_id),
    FOREIGN KEY(version_id,calculation_id) REFERENCES template_biology_calculations(version_id,calculation_id) ON DELETE CASCADE,
    FOREIGN KEY(calculation_id,model_id) REFERENCES biology_calculation_type_models(calculation_id,model_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_biology_calculation_linear_regression (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    calculation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'linear_regression' CHECK (model_id IN ('linear_regression','robust_linear_regression_v1','endpoint_rate_v1')),
    window_hours DECIMAL(18,6) NOT NULL CHECK (window_hours > 0),
    minimum_samples INTEGER NOT NULL CHECK (minimum_samples >= 2),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,calculation_id),
    FOREIGN KEY(version_id,calculation_id) REFERENCES template_biology_calculations(version_id,calculation_id) ON DELETE CASCADE,
    FOREIGN KEY(calculation_id,model_id) REFERENCES biology_calculation_type_models(calculation_id,model_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_biological_phases (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES template_versions(version_id) ON DELETE CASCADE,
    phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    phase_order INTEGER NOT NULL CHECK (phase_order >= 1),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,phase_id),
    UNIQUE(version_id,phase_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_biological_criteria (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_order INTEGER NOT NULL CHECK (criterion_order >= 1),
    enabled TINYINT NOT NULL CHECK (enabled IN (0,1)),
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES metrics(metric_id),
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES criterion_models(model_id),
    role_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES criterion_roles(role_id),
    label VARCHAR(255) NOT NULL,
    exception_allowed TINYINT NOT NULL DEFAULT 1 CHECK (exception_allowed IN (0,1)),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,phase_id,criterion_id),
    UNIQUE(version_id,phase_id,criterion_order),
    UNIQUE(version_id,phase_id,criterion_id,model_id),
    FOREIGN KEY(version_id,phase_id) REFERENCES template_biological_phases(version_id,phase_id) ON DELETE CASCADE,
    FOREIGN KEY(metric_id,model_id) REFERENCES criterion_metric_models(metric_id,model_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE INDEX IF NOT EXISTS idx_tpl_bio_criteria_order
ON template_biological_criteria(version_id,phase_id,criterion_order);

CREATE TABLE IF NOT EXISTS template_biological_criterion_threshold (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'threshold' CHECK (model_id='threshold'),
    minimum_value DECIMAL(18,6),
    maximum_value DECIMAL(18,6),
    maximum_age_minutes INTEGER CHECK (maximum_age_minutes IS NULL OR maximum_age_minutes > 0),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,phase_id,criterion_id),
    FOREIGN KEY(version_id,phase_id,criterion_id,model_id) REFERENCES template_biological_criteria(version_id,phase_id,criterion_id,model_id) ON DELETE CASCADE,
    CHECK (minimum_value IS NOT NULL OR maximum_value IS NOT NULL),
    CHECK (minimum_value IS NULL OR maximum_value IS NULL OR minimum_value <= maximum_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_biological_criterion_observation (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'observation' CHECK (model_id='observation'),
    maximum_age_minutes INTEGER CHECK (maximum_age_minutes IS NULL OR maximum_age_minutes > 0),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,phase_id,criterion_id),
    FOREIGN KEY(version_id,phase_id,criterion_id,model_id) REFERENCES template_biological_criteria(version_id,phase_id,criterion_id,model_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_biological_criterion_window_median_range (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'window_median_range' CHECK (model_id='window_median_range'),
    window_minutes INTEGER NOT NULL CHECK (window_minutes > 0),
    minimum_samples INTEGER NOT NULL CHECK (minimum_samples > 0),
    maximum_age_minutes INTEGER CHECK (maximum_age_minutes IS NULL OR maximum_age_minutes > 0),
    minimum_value DECIMAL(18,6) NOT NULL,
    maximum_value DECIMAL(18,6) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,phase_id,criterion_id),
    FOREIGN KEY(version_id,phase_id,criterion_id,model_id) REFERENCES template_biological_criteria(version_id,phase_id,criterion_id,model_id) ON DELETE CASCADE,
    CHECK (minimum_value <= maximum_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_biological_criterion_stability_window (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'stability_window' CHECK (model_id='stability_window'),
    window_hours DECIMAL(18,6) NOT NULL CHECK (window_hours > 0),
    maximum_range_points DECIMAL(18,6) NOT NULL CHECK (maximum_range_points >= 0),
    minimum_samples INTEGER NOT NULL CHECK (minimum_samples > 0),
    minimum_span_hours DECIMAL(18,6) NOT NULL CHECK (minimum_span_hours >= 0),
    maximum_age_minutes INTEGER CHECK (maximum_age_minutes IS NULL OR maximum_age_minutes > 0),
    since_current_process_start TINYINT NOT NULL CHECK (since_current_process_start IN (0,1)),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,phase_id,criterion_id),
    FOREIGN KEY(version_id,phase_id,criterion_id,model_id) REFERENCES template_biological_criteria(version_id,phase_id,criterion_id,model_id) ON DELETE CASCADE,
    CHECK (minimum_span_hours <= window_hours)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_biological_correctable_parameters (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    phase_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,phase_id,criterion_id,parameter_id),
    FOREIGN KEY(version_id,phase_id,criterion_id,model_id) REFERENCES template_biological_criteria(version_id,phase_id,criterion_id,model_id) ON DELETE CASCADE,
    FOREIGN KEY(model_id,parameter_id) REFERENCES criterion_model_parameters(model_id,parameter_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Process model --------------------------------------------------------------
CREATE TABLE IF NOT EXISTS template_process_steps (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES template_versions(version_id) ON DELETE CASCADE,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_order INTEGER NOT NULL CHECK (process_order BETWEEN 1 AND 15),
    enabled TINYINT NOT NULL CHECK (enabled IN (0,1)),
    historical_replay_auto_transition_allowed TINYINT NOT NULL DEFAULT 0 CHECK (historical_replay_auto_transition_allowed IN (0,1)),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,process_id),
    UNIQUE(version_id,process_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_process_targets (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    target_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    target_order INTEGER NOT NULL CHECK (target_order >= 1),
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES metrics(metric_id),
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES target_models(model_id),
    label VARCHAR(255) NOT NULL,
    purpose TEXT,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,process_id,target_id),
    UNIQUE(version_id,process_id,target_order),
    UNIQUE(version_id,process_id,target_id,model_id),
    FOREIGN KEY(version_id,process_id) REFERENCES template_process_steps(version_id,process_id) ON DELETE CASCADE,
    FOREIGN KEY(metric_id,model_id) REFERENCES target_metric_models(metric_id,model_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_process_target_exact (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    target_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'exact' CHECK (model_id='exact'),
    target_value DECIMAL(18,6) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,process_id,target_id),
    FOREIGN KEY(version_id,process_id,target_id,model_id) REFERENCES template_process_targets(version_id,process_id,target_id,model_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_process_target_range (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    target_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'range' CHECK (model_id='range'),
    minimum_value DECIMAL(18,6) NOT NULL,
    maximum_value DECIMAL(18,6) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,process_id,target_id),
    FOREIGN KEY(version_id,process_id,target_id,model_id) REFERENCES template_process_targets(version_id,process_id,target_id,model_id) ON DELETE CASCADE,
    CHECK (minimum_value <= maximum_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_process_actions (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    action_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    action_order INTEGER NOT NULL CHECK (action_order >= 1),
    action_type_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES action_types(action_type_id),
    label VARCHAR(255) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,process_id,action_id),
    UNIQUE(version_id,process_id,action_order),
    UNIQUE(version_id,process_id,action_id,action_type_id),
    FOREIGN KEY(version_id,process_id) REFERENCES template_process_steps(version_id,process_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_process_action_set_target (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    action_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    action_type_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'set_target' CHECK (action_type_id='set_target'),
    target_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,process_id,action_id),
    FOREIGN KEY(version_id,process_id,action_id,action_type_id) REFERENCES template_process_actions(version_id,process_id,action_id,action_type_id) ON DELETE CASCADE,
    FOREIGN KEY(version_id,process_id,target_id) REFERENCES template_process_targets(version_id,process_id,target_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_process_action_operator (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    action_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    action_type_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'operator_action' CHECK (action_type_id='operator_action'),
    operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES operator_operations(operation_id),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,process_id,action_id),
    FOREIGN KEY(version_id,process_id,action_id,action_type_id) REFERENCES template_process_actions(version_id,process_id,action_id,action_type_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_process_criteria (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_order INTEGER NOT NULL CHECK (criterion_order >= 1),
    enabled TINYINT NOT NULL CHECK (enabled IN (0,1)),
    metric_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES metrics(metric_id),
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES criterion_models(model_id),
    role_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL REFERENCES criterion_roles(role_id),
    label VARCHAR(255) NOT NULL,
    exception_allowed TINYINT NOT NULL CHECK (exception_allowed IN (0,1)),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,process_id,criterion_id),
    UNIQUE(version_id,process_id,criterion_order),
    UNIQUE(version_id,process_id,criterion_id,model_id),
    FOREIGN KEY(version_id,process_id) REFERENCES template_process_steps(version_id,process_id) ON DELETE CASCADE,
    FOREIGN KEY(metric_id,model_id) REFERENCES criterion_metric_models(metric_id,model_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE INDEX IF NOT EXISTS idx_tpl_process_criteria_order
ON template_process_criteria(version_id,process_id,criterion_order);

CREATE TABLE IF NOT EXISTS template_process_criterion_threshold (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'threshold' CHECK (model_id='threshold'),
    minimum_value DECIMAL(18,6),
    maximum_value DECIMAL(18,6),
    maximum_age_minutes INTEGER CHECK (maximum_age_minutes IS NULL OR maximum_age_minutes > 0),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,process_id,criterion_id),
    FOREIGN KEY(version_id,process_id,criterion_id,model_id) REFERENCES template_process_criteria(version_id,process_id,criterion_id,model_id) ON DELETE CASCADE,
    CHECK (minimum_value IS NOT NULL OR maximum_value IS NOT NULL),
    CHECK (minimum_value IS NULL OR maximum_value IS NULL OR minimum_value <= maximum_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_process_criterion_observation (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'observation' CHECK (model_id='observation'),
    maximum_age_minutes INTEGER CHECK (maximum_age_minutes IS NULL OR maximum_age_minutes > 0),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,process_id,criterion_id),
    FOREIGN KEY(version_id,process_id,criterion_id,model_id) REFERENCES template_process_criteria(version_id,process_id,criterion_id,model_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_process_criterion_window_median_range (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'window_median_range' CHECK (model_id='window_median_range'),
    window_minutes INTEGER NOT NULL CHECK (window_minutes > 0),
    minimum_samples INTEGER NOT NULL CHECK (minimum_samples > 0),
    maximum_age_minutes INTEGER CHECK (maximum_age_minutes IS NULL OR maximum_age_minutes > 0),
    minimum_value DECIMAL(18,6) NOT NULL,
    maximum_value DECIMAL(18,6) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,process_id,criterion_id),
    FOREIGN KEY(version_id,process_id,criterion_id,model_id) REFERENCES template_process_criteria(version_id,process_id,criterion_id,model_id) ON DELETE CASCADE,
    CHECK (minimum_value <= maximum_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_process_criterion_stability_window (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'stability_window' CHECK (model_id='stability_window'),
    window_hours DECIMAL(18,6) NOT NULL CHECK (window_hours > 0),
    maximum_range_points DECIMAL(18,6) NOT NULL CHECK (maximum_range_points >= 0),
    minimum_samples INTEGER NOT NULL CHECK (minimum_samples > 0),
    minimum_span_hours DECIMAL(18,6) NOT NULL CHECK (minimum_span_hours >= 0),
    maximum_age_minutes INTEGER CHECK (maximum_age_minutes IS NULL OR maximum_age_minutes > 0),
    since_current_process_start TINYINT NOT NULL CHECK (since_current_process_start IN (0,1)),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,process_id,criterion_id),
    FOREIGN KEY(version_id,process_id,criterion_id,model_id) REFERENCES template_process_criteria(version_id,process_id,criterion_id,model_id) ON DELETE CASCADE,
    CHECK (minimum_span_hours <= window_hours)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_process_correctable_parameters (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    process_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    criterion_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,process_id,criterion_id,parameter_id),
    FOREIGN KEY(version_id,process_id,criterion_id,model_id) REFERENCES template_process_criteria(version_id,process_id,criterion_id,model_id) ON DELETE CASCADE,
    FOREIGN KEY(model_id,parameter_id) REFERENCES criterion_model_parameters(model_id,parameter_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- p22r7 generic measurement validation registry -------------------------------
CREATE TABLE IF NOT EXISTS measurement_validation_models (
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    label VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS measurement_validation_model_parameters (
    model_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    parameter_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    sort_order INTEGER NOT NULL CHECK (sort_order >= 1),
    label VARCHAR(255) NOT NULL,
    data_type VARCHAR(16) NOT NULL CHECK (data_type IN ('real','integer','boolean','text')),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(model_id,parameter_id),
    CONSTRAINT fk_measurement_validation_model_parameters__model FOREIGN KEY(model_id) REFERENCES measurement_validation_models(model_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Analysis presentation/series are declared by template, then frozen at Start.
CREATE TABLE IF NOT EXISTS template_analysis_graphs (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
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
    PRIMARY KEY(version_id,graph_id),
    UNIQUE KEY uq_template_analysis_graphs__order(version_id,sort_order),
    CONSTRAINT fk_template_analysis_graphs__version FOREIGN KEY(version_id) REFERENCES template_versions(version_id) ON DELETE CASCADE,
    CHECK (y_axis_min IS NULL OR y_axis_max IS NULL OR y_axis_min < y_axis_max)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_analysis_graph_series (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
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
    PRIMARY KEY(version_id,graph_id,series_id),
    UNIQUE KEY uq_template_analysis_graph_series__order(version_id,graph_id,sort_order),
    CONSTRAINT fk_template_analysis_graph_series__graph FOREIGN KEY(version_id,graph_id) REFERENCES template_analysis_graphs(version_id,graph_id) ON DELETE CASCADE,
    CONSTRAINT fk_template_analysis_graph_series__metric FOREIGN KEY(metric_id) REFERENCES metrics(metric_id),
    CHECK ((source_kind NOT IN ('biological_criterion','process_criterion') AND metric_id IS NOT NULL AND owner_id IS NULL AND criterion_id IS NULL)
        OR (source_kind IN ('biological_criterion','process_criterion') AND metric_id IS NULL AND owner_id IS NOT NULL AND criterion_id IS NOT NULL)),
    CHECK (valid_minimum_value IS NULL OR valid_maximum_value IS NULL OR valid_minimum_value <= valid_maximum_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS template_overview_graph_policy (
    version_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    graph_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    band_model VARCHAR(32) NOT NULL CHECK (band_model IN ('none','sample_range')),
    band_description TEXT NOT NULL,
    band_opacity DECIMAL(4,3) NOT NULL CHECK (band_opacity > 0 AND band_opacity <= 1),
    created_at DATETIME(3) NOT NULL,
    PRIMARY KEY(version_id,graph_id),
    FOREIGN KEY(version_id) REFERENCES template_versions(version_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- p24r12: typed field contracts and projection routes are normative DB data.
CREATE TABLE IF NOT EXISTS ha_projection_routes (
 projection_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 entity_id VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 output_slot INTEGER NOT NULL CHECK(output_slot>0),
 source_object_id VARCHAR(384) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 consumer_node_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 UNIQUE(consumer_node_id,entity_id), UNIQUE(consumer_node_id,output_slot),
 FOREIGN KEY(entity_id) REFERENCES ha_entity_registry(entity_id),
 FOREIGN KEY(source_object_id) REFERENCES information_objects(object_id)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS ha_projection_fields (
 projection_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 field_path VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 value_type VARCHAR(24) NOT NULL CHECK(value_type IN('string','number','boolean','object','array','scalar')),
 required TINYINT NOT NULL CHECK(required IN(0,1)),
 absence_policy VARCHAR(24) NOT NULL CHECK(absence_policy IN('error','omit','explicit_status')),
 empty_allowed TINYINT NOT NULL CHECK(empty_allowed IN(0,1)),
 PRIMARY KEY(projection_id,field_path),
 FOREIGN KEY(projection_id) REFERENCES ha_projection_routes(projection_id),
 CHECK(required=0 OR absence_policy<>'omit')
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS ha_draft_output_bindings (
 output_slot INTEGER PRIMARY KEY CHECK(output_slot BETWEEN 1 AND 32),
 entity_id VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 field_name VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 converter_id VARCHAR(24) NOT NULL CHECK(converter_id IN('text','number','integer','datetime','select')),
 start_enabled TINYINT NOT NULL CHECK(start_enabled IN(0,1)),
 measurement_enabled TINYINT NOT NULL CHECK(measurement_enabled IN(0,1)),
 absence_policy VARCHAR(24) NOT NULL CHECK(absence_policy IN('omit','clear','error')),
 FOREIGN KEY(entity_id) REFERENCES ha_entity_registry(entity_id)
) ENGINE=InnoDB;
-- Every nullable physical column has a reviewed meaning. The catalog itself
-- is read directly from INFORMATION_SCHEMA; these are semantic annotations.
CREATE TABLE IF NOT EXISTS schema_absence_semantics (
 object_id VARCHAR(384) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 column_name VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 absence_kind VARCHAR(32) NOT NULL CHECK(absence_kind IN('not_yet','not_applicable','optional','not_available','initial_revision','typed_alternative')),
 explanation VARCHAR(512) NOT NULL,
 PRIMARY KEY(object_id,column_name),
 FOREIGN KEY(object_id) REFERENCES information_objects(object_id)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS schema_relation_semantics (
 object_id VARCHAR(384) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 relation_kind VARCHAR(32) NOT NULL CHECK(relation_kind IN('registry','relation','snapshot','event','measurement','draft','metadata','subtype')),
 fact_scope VARCHAR(512) NOT NULL,
 normalization_note VARCHAR(1024) NOT NULL,
 FOREIGN KEY(object_id) REFERENCES information_objects(object_id)
) ENGINE=InnoDB;


-- p24r13: one DB-owned layout for every delivery surface; no UI defaults.
CREATE TABLE IF NOT EXISTS graph_render_policy (
 policy_id INTEGER PRIMARY KEY CHECK (policy_id=1),
 canvas_width INTEGER NOT NULL CHECK (canvas_width>=600),
 canvas_height INTEGER NOT NULL CHECK (canvas_height>=300),
 compact_height INTEGER NOT NULL CHECK (compact_height>=200),
 margin_left INTEGER NOT NULL CHECK (margin_left>0),
 margin_right INTEGER NOT NULL CHECK (margin_right>0),
 margin_top INTEGER NOT NULL CHECK (margin_top>0),
 margin_bottom INTEGER NOT NULL CHECK (margin_bottom>0),
 date_font_size INTEGER NOT NULL CHECK (date_font_size>=8),
 axis_font_size INTEGER NOT NULL CHECK (axis_font_size>=8),
 marker_font_size INTEGER NOT NULL CHECK (marker_font_size>=8),
 font_family VARCHAR(64) NOT NULL,
 line_width DECIMAL(6,3) NOT NULL CHECK (line_width>0),
 time_marker_spacing INTEGER NOT NULL CHECK (time_marker_spacing>=30),
 point_radius DECIMAL(6,3) NOT NULL CHECK (point_radius>0),
 CHECK (margin_left+margin_right<canvas_width),
 CHECK (margin_top+margin_bottom<compact_height),
 created_at DATETIME(3) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Explicit legacy import conversion catalog; never a runtime fallback.
CREATE TABLE IF NOT EXISTS legacy_measurement_graph_models (
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
    PRIMARY KEY(graph_id),
    UNIQUE KEY r13_uq_legacy_measurement_graph_models__order(sort_order),
    CHECK (y_axis_min IS NULL OR y_axis_max IS NULL OR y_axis_min < y_axis_max)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS legacy_measurement_graph_series_models (
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
    PRIMARY KEY(graph_id,series_id),
    UNIQUE KEY r13_uq_legacy_measurement_graph_series_models__order(graph_id,sort_order),
    CONSTRAINT r13_fk_legacy_measurement_graph_series_models__graph FOREIGN KEY(graph_id) REFERENCES legacy_measurement_graph_models(graph_id) ON DELETE CASCADE,
    CONSTRAINT r13_fk_legacy_measurement_graph_series_models__metric FOREIGN KEY(metric_id) REFERENCES metrics(metric_id),
    CHECK ((source_kind NOT IN ('biological_criterion','process_criterion') AND metric_id IS NOT NULL AND owner_id IS NULL AND criterion_id IS NULL)
        OR (source_kind IN ('biological_criterion','process_criterion') AND metric_id IS NULL AND owner_id IS NOT NULL AND criterion_id IS NOT NULL)),
    CHECK (valid_minimum_value IS NULL OR valid_maximum_value IS NULL OR valid_minimum_value <= valid_maximum_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS read_model_execution_policy (
 policy_id TINYINT NOT NULL PRIMARY KEY CHECK(policy_id=1),
 json_staging_bytes BIGINT NOT NULL CHECK(json_staging_bytes>=1048576),
 overview_clock_refresh_seconds INTEGER NOT NULL CHECK(overview_clock_refresh_seconds>=30)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
