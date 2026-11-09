SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

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
