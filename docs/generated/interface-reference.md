# Grensesnitt – generert referanse

> Avledet inspeksjon av faktiske SQL-registre, rutiner og flow. Se den vedlikeholdte [kildekatalogen](../../contracts/interface-catalog.json). Ingen målmiljøtest hevdes.

## Eierskap og kontroll

| Grense | Autoritative kilder | Kontroller |
|---|---|---|
| MariaDB ↔ Node-RED | [docs/12-OPERASJONS-OG-TRANSAKSJONSKONTRAKT.md](../../docs/12-OPERASJONS-OG-TRANSAKSJONSKONTRAKT.md)<br>[sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql)<br>[sql/12-operator-routines.sql](../../sql/12-operator-routines.sql)<br>[sql/20-views.sql](../../sql/20-views.sql)<br>[tools/overview_reads.sql](../../tools/overview_reads.sql)<br>[tools/report_reads.sql](../../tools/report_reads.sql) | [tests/verify-read-model-contract.py](../../tests/verify-read-model-contract.py)<br>[tests/verify-interface-contracts.py](../../tests/verify-interface-contracts.py)<br>[tests/test-p24r15-live.js](../../tests/test-p24r15-live.js)<br>[tests/test-start-control-live.js](../../tests/test-start-control-live.js) |
| Node-RED ↔ Home Assistant | [docs/05-FRONTEND-OG-INTEGRASJONSKONTRAKT.md](../../docs/05-FRONTEND-OG-INTEGRASJONSKONTRAKT.md)<br>[sql/21-system-metadata-seed.sql](../../sql/21-system-metadata-seed.sql) | [tests/verify-ha-contract.py](../../tests/verify-ha-contract.py)<br>[tests/verify-interface-contracts.py](../../tests/verify-interface-contracts.py)<br>[tests/verify-p24r15.py](../../tests/verify-p24r15.py)<br>[tests/test-operator-ui.js](../../tests/test-operator-ui.js) |
| Node-RED → JSON/gzip-publisering | [docs/05-FRONTEND-OG-INTEGRASJONSKONTRAKT.md](../../docs/05-FRONTEND-OG-INTEGRASJONSKONTRAKT.md)<br>[contracts/publication-job.schema.json](../../contracts/publication-job.schema.json) | [tests/verify-interface-contracts.py](../../tests/verify-interface-contracts.py)<br>[tests/test-interface-contracts.js](../../tests/test-interface-contracts.js)<br>[tests/test-p24r8.js](../../tests/test-p24r8.js) |

## MariaDB-rutiner og faktiske Node-RED-kall

| Rutine | Parameterdeklarasjon fra SQL | Kilde | Kallende noder |
|---|---|---|---|
| `ga_ack_overview` | `IN p_operation CHAR(36), IN p_key CHAR(64), IN p_generated DATETIME(3)` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | p24r8_publication_result |
| `ga_clone_template_tx` | `IN p_source VARCHAR(128),IN p_draft VARCHAR(128),IN p_new_template VARCHAR(128),IN p_new_name VARCHAR(255)` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | p20_template_clone_query |
| `ga_convert_legacy_archive_graphs` | `IN p_version VARCHAR(128),IN p_session VARCHAR(128)` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_correct_visit_time_tx` | `IN p_kind VARCHAR(32),IN p_target VARCHAR(128),IN p_action VARCHAR(16),IN p_requested DATETIME(3),IN p_operation VARCHAR(128)` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | p20_bio_time_correction_query |
| `ga_drop_read_basis` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_fill_read_basis` | `IN p_session VARCHAR(128)` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_fill_read_basis_part_1` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_fill_read_basis_part_2` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_fill_read_basis_part_3` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_fill_read_basis_part_4` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_fill_read_basis_part_5` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_fill_read_basis_part_6` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_fill_read_basis_part_7` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_fill_read_basis_part_8` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_fill_read_basis_part_9` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_freeze_source_configuration` | `IN p_session VARCHAR(128),IN p_profile VARCHAR(128),IN p_effective DATETIME(3)` | [sql/12-operator-routines.sql](../../sql/12-operator-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_init_read_basis` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_init_read_basis_part_1` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_init_read_basis_part_2` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_init_read_basis_part_3` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_init_read_basis_part_4` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_init_read_basis_part_5` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_init_read_basis_part_6` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_init_read_basis_part_7` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_overview_source_key` | `OUT p_key CHAR(64)` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_poll_overview` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | p20_overview_query |
| `ga_prepare_selected_demo_tx` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | p20_demo_prepare_query |
| `ga_read_ha_draft_projection` | `IN p_context VARCHAR(24)` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | p20_sync_draft |
| `ga_read_overview` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | p20_overview_query |
| `ga_read_report` | `IN p_session VARCHAR(128), IN p_now DATETIME(3)` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | p21_session_export_query, p22_active_report_query |
| `ga_read_source_settings` | `IN p_operation VARCHAR(128)` | [sql/12-operator-routines.sql](../../sql/12-operator-routines.sql) | source_settings_command_v1, source_settings_read_query_v1 |
| `ga_read_start_context` | `IN p_attempt_id VARCHAR(128),IN p_historical_end DATETIME(3)` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | p20_start_guard |
| `ga_record_criterion_exception_tx` | `IN p_kind VARCHAR(16),IN p_evaluation VARCHAR(128),IN p_criterion VARCHAR(128),IN p_action VARCHAR(16),IN p_type VARCHAR(32),IN p_confirmed TINYINT,IN p_note TEXT,IN p_operation VARCHAR(128)` | [sql/12-operator-routines.sql](../../sql/12-operator-routines.sql) | p20_process_exception_context_result, p24_bio_exception_context_result |
| `ga_refresh_sensor_catalog` | `IN p_operation VARCHAR(128),IN p_states LONGTEXT` | [sql/12-operator-routines.sql](../../sql/12-operator-routines.sql) | source_settings_catalog_store_v1 |
| `ga_register_active_report_tx` | `IN p_session VARCHAR(128),IN p_operation VARCHAR(128),IN p_path TEXT,IN p_sha CHAR(64)` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | p22_active_report_register_query |
| `ga_register_historical_phase_tx` | `IN p_kind VARCHAR(32),IN p_owner VARCHAR(128),IN p_started DATETIME(3),IN p_operation VARCHAR(128)` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | p24r15_historical_phase_query |
| `ga_request_archive_tx` | `IN p_session VARCHAR(128), IN p_resume BOOLEAN` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | p24_archive_attempt_query |
| `ga_save_source_configuration` | `IN p_profile VARCHAR(128),IN p_expected BIGINT UNSIGNED,IN p_operation VARCHAR(128),IN p_note TEXT,IN p_fields LONGTEXT` | [sql/12-operator-routines.sql](../../sql/12-operator-routines.sql) | source_settings_command_v1 |
| `ga_seed_demo_tx` | `IN p_sid VARCHAR(128)` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | p20_demo_seed_query |
| `ga_select_start_template_tx` | `IN p_selected VARCHAR(128)` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | p20_template_select |
| `ga_start_session_tx` | `ingen` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | Ingen direkte CALL i flow; se SQL-/adapterkonsument |
| `ga_store_ingest_tx` | `IN p_sid VARCHAR(128),IN p_end DATETIME(3),IN p_threshold INTEGER,IN p_error TEXT,IN p_job LONGTEXT` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | p21_live_history_process |
| `ga_store_system_check_tx` | `IN p_overall VARCHAR(32), IN p_checks LONGTEXT` | [sql/11-runtime-routines.sql](../../sql/11-runtime-routines.sql) | p20_systemcheck_result |

## HA-registre

| Register | Rader | Eier |
|---|---:|---|
| `ha_entity_registry` | 75 | SQL/installerte MariaDB-registre |
| `ha_event_registry` | 24 | SQL/installerte MariaDB-registre |
| `ha_entity_input_bindings` | 30 | SQL/installerte MariaDB-registre |
| `ha_entity_input_value_mappings` | 15 | SQL/installerte MariaDB-registre |
| `ha_projection_routes` | 38 | SQL/installerte MariaDB-registre |
| `ha_projection_fields` | 193 | SQL/installerte MariaDB-registre |
| `ha_draft_output_bindings` | 32 | SQL/installerte MariaDB-registre |
| `ha_entity_number_constraints` | 22 | SQL/installerte MariaDB-registre |
| `start_field_rules` | 30 | SQL/installerte MariaDB-registre |
| `start_field_pitch_modes` | 5 | SQL/installerte MariaDB-registre |

Feltstier, datatyper, required/absence-policy, inputbindinger, mapping og fysiske ruter er med i [JSON-uttrekket](interface-reference.json).

## Read-model-publisering

| Produsent | Staging | Argumentnode | Exec | Resultat / stderr |
|---|---|---|---|---|
| `p20_overview_result` | `p20_overview_file` | `p24r8_publication_args` | `p24r8_publication_exec` | `p24r8_publication_result` / `p24r8_publication_stderr` |
| `p20_technical_export_result` | `p20_technical_export_file` | `p24r8_publication_args` | `p24r8_publication_exec` | `p24r8_publication_result` / `p24r8_publication_stderr` |
| `source_settings_result_v1` | `source_settings_staging_file_v1` | `source_settings_publication_args_v1` | `source_settings_publish_v1` | `p24r8_publication_result` / `p24r8_publication_stderr` |

Jobbens obligatoriske felt er stage_path og target_path. diagnostics_level kan være summary/full. source_path er ikke et alternativt feltnavn. Se [maskinskjema](../../contracts/publication-job.schema.json). Kildene og de faktiske koblingene prøves av verify-interface-contracts.py; faktiske argumenter, shell, JSON/gzip og feil prøves av test-interface-contracts.js og test-p24r8.js.
