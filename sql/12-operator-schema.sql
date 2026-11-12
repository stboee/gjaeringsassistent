-- DB-owned operator controls, source revisions and immutable session bindings.
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS measurement_source_signals (
 signal_id VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 label VARCHAR(128) NOT NULL,
 observation_kind VARCHAR(16) NOT NULL CHECK(observation_kind IN('number','timestamp')),
 sensor_required TINYINT NOT NULL CHECK(sensor_required IN(0,1)),
 operator_entity_id VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin,
 display_order INTEGER NOT NULL,
 show_on_start TINYINT NOT NULL CHECK(show_on_start IN(0,1)),
 description TEXT NOT NULL,
 CONSTRAINT fk_source_signals__operator_entity FOREIGN KEY(operator_entity_id) REFERENCES ha_entity_registry(entity_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS measurement_source_units (
 signal_id VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 unit_id VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 ha_unit VARCHAR(32) NOT NULL,
 label VARCHAR(128) NOT NULL,
 multiplier DECIMAL(24,12) NOT NULL CHECK(multiplier>0),
 additive_offset DECIMAL(24,12) NOT NULL,
 is_canonical TINYINT NOT NULL CHECK(is_canonical IN(0,1)),
 canonical_signal VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin GENERATED ALWAYS AS(IF(is_canonical=1,signal_id,NULL)) PERSISTENT UNIQUE,
 PRIMARY KEY(signal_id,unit_id), UNIQUE KEY uq_source_units__ha(signal_id,ha_unit),
 CONSTRAINT fk_source_units__signal FOREIGN KEY(signal_id) REFERENCES measurement_source_signals(signal_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS measurement_source_configurations (
 configuration_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 source_profile_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 parent_configuration_id BIGINT UNSIGNED,
 parent_key BIGINT UNSIGNED GENERATED ALWAYS AS(COALESCE(parent_configuration_id,0)) PERSISTENT,
 operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
 note TEXT, created_at DATETIME(3) NOT NULL,
 UNIQUE KEY uq_source_configurations__parent(source_profile_id,parent_key),
 UNIQUE KEY uq_source_configurations__identity(source_profile_id,configuration_id),
 CONSTRAINT fk_source_configurations__profile FOREIGN KEY(source_profile_id) REFERENCES measurement_source_profiles(source_profile_id),
 CONSTRAINT fk_source_configurations__parent FOREIGN KEY(source_profile_id,parent_configuration_id) REFERENCES measurement_source_configurations(source_profile_id,configuration_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS measurement_source_signal_bindings (
 configuration_id BIGINT UNSIGNED NOT NULL,
 signal_id VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 input_mode VARCHAR(16) NOT NULL CHECK(input_mode IN('sensor','manual')),
 entity_id VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin,
 unit_id VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 PRIMARY KEY(configuration_id,signal_id),
 CONSTRAINT fk_source_bindings__configuration FOREIGN KEY(configuration_id) REFERENCES measurement_source_configurations(configuration_id),
 CONSTRAINT fk_source_bindings__unit FOREIGN KEY(signal_id,unit_id) REFERENCES measurement_source_units(signal_id,unit_id),
 CHECK((input_mode='sensor' AND entity_id IS NOT NULL AND entity_id LIKE 'sensor.%') OR(input_mode='manual' AND entity_id IS NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS session_measurement_source_configurations (
 session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 configuration_id BIGINT UNSIGNED NOT NULL,
 effective_from DATETIME(3) NOT NULL,
 profile_name VARCHAR(255) NOT NULL, note TEXT, created_at DATETIME(3) NOT NULL,
 PRIMARY KEY(session_id,configuration_id),
 KEY idx_session_sources__time(session_id,effective_from,configuration_id),
 CONSTRAINT fk_session_sources__session FOREIGN KEY(session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS session_measurement_signal_bindings (
 session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 configuration_id BIGINT UNSIGNED NOT NULL,
 signal_id VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 input_mode VARCHAR(16) NOT NULL CHECK(input_mode IN('sensor','manual')),
 entity_id VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin,
 unit_id VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 minimum_value DECIMAL(24,8), maximum_value DECIMAL(24,8),
 PRIMARY KEY(session_id,configuration_id,signal_id),
 CONSTRAINT fk_session_bindings__configuration FOREIGN KEY(session_id,configuration_id) REFERENCES session_measurement_source_configurations(session_id,configuration_id) ON DELETE CASCADE,
 CONSTRAINT fk_session_bindings__unit FOREIGN KEY(signal_id,unit_id) REFERENCES measurement_source_units(signal_id,unit_id),
 CHECK((input_mode='sensor' AND entity_id IS NOT NULL AND entity_id LIKE 'sensor.%') OR(input_mode='manual' AND entity_id IS NULL)),
 CHECK(minimum_value IS NULL OR maximum_value IS NULL OR minimum_value<=maximum_value)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS ha_sensor_catalog_checks (
 check_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 operation_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
 checked_at DATETIME(3) NOT NULL,
 sensor_count INTEGER NOT NULL CHECK(sensor_count>=0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS ha_sensor_catalog (
 entity_id VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 check_id BIGINT UNSIGNED NOT NULL,
 friendly_name VARCHAR(255) NOT NULL, device_class VARCHAR(32) NOT NULL,
 ha_unit VARCHAR(32) NOT NULL, state_text VARCHAR(255) NOT NULL, last_updated DATETIME(3) NOT NULL,
 CONSTRAINT fk_sensor_catalog__check FOREIGN KEY(check_id) REFERENCES ha_sensor_catalog_checks(check_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS technical_components (
 component_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 display_name VARCHAR(255) NOT NULL,
 component_layer VARCHAR(32) NOT NULL CHECK(component_layer IN('node_red','mariadb','tool')),
 description TEXT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
