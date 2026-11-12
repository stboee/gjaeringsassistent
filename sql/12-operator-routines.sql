SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
DROP PROCEDURE IF EXISTS ga_read_source_settings;
DROP PROCEDURE IF EXISTS ga_refresh_sensor_catalog;
DROP PROCEDURE IF EXISTS ga_freeze_source_configuration;
DROP PROCEDURE IF EXISTS ga_save_source_configuration;
DROP PROCEDURE IF EXISTS ga_record_criterion_exception_tx;
DELIMITER //
CREATE PROCEDURE ga_read_source_settings(IN p_operation VARCHAR(128))
BEGIN
 SELECT JSON_OBJECT('schema_version','1.0','application_version',(SELECT application_version FROM database_metadata WHERE metadata_id=1),'source_profile_id',p.source_profile_id,'profile_name',p.name,'configuration_id',c.configuration_id,'operation_id',c.operation_id,
 'receipt_operation_id',(SELECT operation_id FROM measurement_source_configurations WHERE operation_id=p_operation),
 'catalog_operation_id',(SELECT operation_id FROM ha_sensor_catalog_checks ORDER BY check_id DESC LIMIT 1),
 'catalog_checked_display',COALESCE((SELECT DATE_FORMAT(CONVERT_TZ(checked_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i:%s') FROM ha_sensor_catalog_checks ORDER BY check_id DESC LIMIT 1),'Ikke kontrollert'),
 'fields',(SELECT JSON_ARRAYAGG(JSON_OBJECT('signal_id',f.signal_id,'label',f.label,'description',f.description,'sensor_required',f.sensor_required,'show_on_start',f.show_on_start,'manual_unit_id',f.manual_unit_id,'modes',JSON_QUERY(f.modes,'$'),'input_mode',f.input_mode,'entity_id',f.entity_id,'entity_display',f.entity_display,'unit_id',f.unit_id,'unit_display',f.unit_display,'status_display',f.status_display,'latest_value_display',f.latest_value_display,'last_updated_display',f.last_updated_display,'options',JSON_QUERY(f.options,'$')) ORDER BY f.display_order) FROM v_source_configuration_fields f WHERE f.source_profile_id=p.source_profile_id),
 'active_bindings',(SELECT JSON_ARRAYAGG(JSON_OBJECT('session_id',sc.session_id,'configuration_id',sc.configuration_id,'effective_display',DATE_FORMAT(CONVERT_TZ(sc.effective_from,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i:%s'),'note',sc.note) ORDER BY sc.effective_from DESC,sc.configuration_id DESC) FROM session_measurement_source_configurations sc JOIN v_active_session a ON a.session_id=sc.session_id),
 'history',(SELECT JSON_ARRAYAGG(JSON_OBJECT('configuration_id',h.configuration_id,'created_display',DATE_FORMAT(CONVERT_TZ(h.created_at,'+00:00','Europe/Oslo'),'%d.%m.%Y %H:%i:%s'),'note',h.note,'bindings',JSON_QUERY(h.bindings,'$')) ORDER BY h.configuration_id DESC LIMIT 20) FROM v_source_configuration_history h WHERE h.source_profile_id=p.source_profile_id)) AS payload
 FROM measurement_source_profiles p JOIN v_current_measurement_source_configuration c ON c.source_profile_id=p.source_profile_id WHERE p.status='active' ORDER BY p.source_profile_id LIMIT 1;
END//
CREATE PROCEDURE ga_refresh_sensor_catalog(IN p_operation VARCHAR(128),IN p_states LONGTEXT)
BEGIN
 DECLARE v_check BIGINT UNSIGNED;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 IF p_operation IS NULL OR p_operation='' OR NOT JSON_VALID(p_states) OR JSON_TYPE(p_states)<>'ARRAY' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Ugyldig sensorkontroll'; END IF;
 IF NOT EXISTS(SELECT 1 FROM ha_sensor_catalog_checks WHERE operation_id=p_operation) THEN
  START TRANSACTION;
  INSERT INTO ha_sensor_catalog_checks(operation_id,checked_at,sensor_count) VALUES(p_operation,UTC_TIMESTAMP(3),0);SET v_check=LAST_INSERT_ID();
  DELETE FROM ha_sensor_catalog;
  INSERT INTO ha_sensor_catalog(entity_id,check_id,friendly_name,device_class,ha_unit,state_text,last_updated)
  SELECT j.entity_id,v_check,COALESCE(NULLIF(j.friendly_name,''),j.entity_id),COALESCE(j.device_class,''),COALESCE(j.ha_unit,''),j.state_text,CAST(REPLACE(LEFT(j.last_updated,23),'T',' ') AS DATETIME(3))
  FROM JSON_TABLE(p_states,'$[*]' COLUMNS(entity_id VARCHAR(255) PATH '$.entity_id',state_text VARCHAR(255) PATH '$.state',last_updated VARCHAR(64) PATH '$.last_updated',friendly_name VARCHAR(255) PATH '$.attributes.friendly_name' NULL ON EMPTY,ha_unit VARCHAR(32) PATH '$.attributes.unit_of_measurement' NULL ON EMPTY,device_class VARCHAR(32) PATH '$.attributes.device_class' NULL ON EMPTY)) j
  WHERE j.entity_id LIKE 'sensor.%' AND j.last_updated REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' AND j.state_text IS NOT NULL AND NOT EXISTS(SELECT 1 FROM ha_entity_registry r WHERE r.entity_id=j.entity_id)
   AND(EXISTS(SELECT 1 FROM measurement_source_units u WHERE u.ha_unit=COALESCE(j.ha_unit,'')) OR EXISTS(SELECT 1 FROM measurement_source_signal_bindings b WHERE b.entity_id=j.entity_id));
  UPDATE ha_sensor_catalog_checks SET sensor_count=(SELECT COUNT(*) FROM ha_sensor_catalog WHERE check_id=v_check) WHERE check_id=v_check;COMMIT;
 END IF;
 CALL ga_read_source_settings(p_operation);
END//
CREATE PROCEDURE ga_freeze_source_configuration(IN p_session VARCHAR(128),IN p_profile VARCHAR(128),IN p_effective DATETIME(3))
BEGIN
 INSERT INTO session_measurement_source_configurations(session_id,configuration_id,effective_from,profile_name,note,created_at)
 SELECT p_session,c.configuration_id,p_effective,p.name,c.note,UTC_TIMESTAMP(3) FROM v_current_measurement_source_configuration c JOIN measurement_source_profiles p ON p.source_profile_id=c.source_profile_id WHERE c.source_profile_id=p_profile;
 IF ROW_COUNT()<>1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Målekildens konfigurasjon mangler'; END IF;
 INSERT INTO session_measurement_signal_bindings(session_id,configuration_id,signal_id,input_mode,entity_id,unit_id,minimum_value,maximum_value)
 SELECT p_session,b.configuration_id,b.signal_id,b.input_mode,b.entity_id,b.unit_id,n.minimum_value,n.maximum_value FROM measurement_source_signal_bindings b JOIN session_measurement_source_configurations c ON c.session_id=p_session AND c.configuration_id=b.configuration_id JOIN measurement_source_signals s ON s.signal_id=b.signal_id LEFT JOIN ha_entity_number_constraints n ON n.entity_id=s.operator_entity_id;
END//
CREATE PROCEDURE ga_save_source_configuration(IN p_profile VARCHAR(128),IN p_expected BIGINT UNSIGNED,IN p_operation VARCHAR(128),IN p_note TEXT,IN p_fields LONGTEXT)
BEGIN
 DECLARE v_configuration BIGINT UNSIGNED;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 IF p_operation IS NULL OR p_operation='' OR p_profile IS NULL OR NOT JSON_VALID(p_fields) OR JSON_TYPE(p_fields)<>'ARRAY' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Ugyldig sensorkonfigurasjon'; END IF;
 IF NOT EXISTS(SELECT 1 FROM measurement_source_configurations WHERE operation_id=p_operation) THEN
  START TRANSACTION;
  IF NOT EXISTS(SELECT 1 FROM v_current_measurement_source_configuration c JOIN measurement_source_profiles p ON p.source_profile_id=c.source_profile_id WHERE c.source_profile_id=p_profile AND c.configuration_id=p_expected AND p.status='active') THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Sensorkonfigurasjonen er endret. Les inn gjeldende konfigurasjon først'; END IF;
  IF JSON_LENGTH(p_fields)<>(SELECT COUNT(*) FROM measurement_source_signals) OR EXISTS(SELECT 1 FROM JSON_TABLE(p_fields,'$[*]' COLUMNS(signal_id VARCHAR(32) PATH '$.signal_id')) j GROUP BY j.signal_id HAVING COUNT(*)<>1)
  OR EXISTS(SELECT 1 FROM JSON_TABLE(p_fields,'$[*]' COLUMNS(signal_id VARCHAR(32) PATH '$.signal_id',input_mode VARCHAR(16) PATH '$.input_mode',entity_id VARCHAR(255) PATH '$.entity_id' NULL ON EMPTY,unit_id VARCHAR(32) PATH '$.unit_id')) j LEFT JOIN measurement_source_signals s ON s.signal_id=j.signal_id LEFT JOIN measurement_source_units u ON u.signal_id=j.signal_id AND u.unit_id=j.unit_id
   WHERE s.signal_id IS NULL OR u.unit_id IS NULL OR j.input_mode IS NULL OR j.input_mode NOT IN('sensor','manual') OR(s.sensor_required=1 AND j.input_mode<>'sensor') OR(j.input_mode='manual' AND(j.entity_id IS NOT NULL OR u.is_canonical<>1))
    OR(j.input_mode='sensor' AND(j.entity_id IS NULL OR NOT EXISTS(SELECT 1 FROM v_source_binding_options o WHERE o.signal_id=j.signal_id AND o.entity_id=j.entity_id AND o.unit_id=j.unit_id) AND NOT EXISTS(SELECT 1 FROM measurement_source_signal_bindings b WHERE b.configuration_id=p_expected AND b.signal_id=j.signal_id AND b.entity_id=j.entity_id AND b.unit_id=j.unit_id AND b.input_mode='sensor'))))
  THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Sensorvalg er ufullstendig, ukjent eller har feil enhet. Kjør Kontroller sensorer'; END IF;
  INSERT INTO measurement_source_configurations(source_profile_id,parent_configuration_id,operation_id,note,created_at) VALUES(p_profile,p_expected,p_operation,NULLIF(TRIM(p_note),''),UTC_TIMESTAMP(3));SET v_configuration=LAST_INSERT_ID();
  INSERT INTO measurement_source_signal_bindings(configuration_id,signal_id,input_mode,entity_id,unit_id)
  SELECT v_configuration,j.signal_id,j.input_mode,j.entity_id,j.unit_id FROM JSON_TABLE(p_fields,'$[*]' COLUMNS(signal_id VARCHAR(32) PATH '$.signal_id',input_mode VARCHAR(16) PATH '$.input_mode',entity_id VARCHAR(255) PATH '$.entity_id' NULL ON EMPTY,unit_id VARCHAR(32) PATH '$.unit_id')) j;
  INSERT INTO session_measurement_source_configurations(session_id,configuration_id,effective_from,profile_name,note,created_at)
  SELECT a.session_id,v_configuration,GREATEST(m.last_import_cutoff_at,TIMESTAMPADD(MICROSECOND,CEIL(GREATEST(0,TIMESTAMPDIFF(MICROSECOND,m.source_started_at,UTC_TIMESTAMP(3)))/(p.poll_interval_seconds*1000000))*p.poll_interval_seconds*1000000,m.source_started_at)),p.name,NULLIF(TRIM(p_note),''),UTC_TIMESTAMP(3)
  FROM v_active_session a JOIN session_measurement_sources m ON m.session_id=a.session_id JOIN measurement_source_profiles p ON p.source_profile_id=m.source_profile_id WHERE m.source_profile_id=p_profile AND a.is_demo=0 AND a.is_historical=0;
  INSERT INTO session_measurement_signal_bindings(session_id,configuration_id,signal_id,input_mode,entity_id,unit_id,minimum_value,maximum_value)
  SELECT c.session_id,b.configuration_id,b.signal_id,b.input_mode,b.entity_id,b.unit_id,n.minimum_value,n.maximum_value FROM session_measurement_source_configurations c JOIN measurement_source_signal_bindings b ON b.configuration_id=c.configuration_id JOIN measurement_source_signals s ON s.signal_id=b.signal_id LEFT JOIN ha_entity_number_constraints n ON n.entity_id=s.operator_entity_id WHERE c.configuration_id=v_configuration;
  COMMIT;
 END IF;
 CALL ga_read_source_settings(p_operation);
END//
CREATE PROCEDURE ga_record_criterion_exception_tx(IN p_kind VARCHAR(16),IN p_evaluation VARCHAR(128),IN p_criterion VARCHAR(128),IN p_action VARCHAR(16),IN p_type VARCHAR(32),IN p_confirmed TINYINT,IN p_note TEXT,IN p_operation VARCHAR(128))
BEGIN
 DECLARE v_session VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin;
 DECLARE v_owner VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin;
 DECLARE v_allowed TINYINT;
 DECLARE v_previous VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin;
 DECLARE v_previous_action VARCHAR(16); DECLARE v_revision INTEGER;
 DECLARE v_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 IF p_kind NOT IN('process','biological') OR p_action NOT IN('register','withdraw') OR p_kind IS NULL OR p_action IS NULL OR p_confirmed IS NULL OR p_confirmed<>1 OR p_operation IS NULL OR p_operation='' OR(p_action='register' AND(p_type IS NULL OR p_type NOT IN('akseptert_avvik','ikke_relevant','ugyldig_vurderingsgrunnlag'))) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Kriteriefravik avvist: ugyldig eller ubekreftet forespørsel'; END IF;
 START TRANSACTION WITH CONSISTENT SNAPSHOT;
 IF p_kind='process' THEN
  SELECT c.session_id,c.candidate_process_id,c.exception_register_allowed INTO v_session,v_owner,v_allowed FROM v_process_evaluation_criterion_read_model c JOIN v_current_process_candidate_evaluation e ON e.evaluation_id=c.evaluation_id JOIN v_active_session a ON a.session_id=c.session_id WHERE c.evaluation_id=p_evaluation AND c.criterion_id=p_criterion;
  SELECT MAX(revision_no) INTO v_revision FROM process_criterion_exceptions WHERE evaluation_id=p_evaluation AND criterion_id=p_criterion;
  SELECT exception_id,action INTO v_previous,v_previous_action FROM process_criterion_exceptions WHERE evaluation_id=p_evaluation AND criterion_id=p_criterion AND revision_no=v_revision;
 ELSE
  SELECT c.session_id,c.phase_id,c.exception_register_allowed INTO v_session,v_owner,v_allowed FROM v_biological_evaluation_criterion_read_model c JOIN v_current_biological_candidate_evaluation e ON e.evaluation_id=c.evaluation_id JOIN v_active_session a ON a.session_id=c.session_id WHERE c.evaluation_id=p_evaluation AND c.criterion_id=p_criterion;
  SELECT MAX(revision_no) INTO v_revision FROM biological_criterion_exceptions WHERE session_id=v_session AND phase_id=v_owner AND criterion_id=p_criterion;
  SELECT exception_id,action INTO v_previous,v_previous_action FROM biological_criterion_exceptions WHERE session_id=v_session AND phase_id=v_owner AND criterion_id=p_criterion AND revision_no=v_revision;
 END IF;
 IF v_session IS NULL OR(p_action='register' AND(v_allowed IS NULL OR v_allowed<>1)) OR(p_action='withdraw' AND(v_previous_action IS NULL OR v_previous_action<>'register')) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Kriteriefravik avvist: ikke gjeldende, ikke tillatt, oppfylt kriterium eller ingen aktiv registrering'; END IF;
 SET v_id=CONCAT('criterion-exception-',REPLACE(UUID(),'-',''));
 IF p_kind='process' THEN
  INSERT INTO process_criterion_exceptions(exception_id,session_id,evaluation_id,criterion_id,revision_no,supersedes_exception_id,action,exception_type,confirmed,note,operation_id,created_at) VALUES(v_id,v_session,p_evaluation,p_criterion,COALESCE(v_revision,0)+1,v_previous,p_action,IF(p_action='register',p_type,NULL),1,NULLIF(TRIM(p_note),''),p_operation,UTC_TIMESTAMP(3));
 ELSE
  INSERT INTO biological_criterion_exceptions(exception_id,session_id,phase_id,evaluation_id,criterion_id,revision_no,supersedes_exception_id,action,exception_type,confirmed,note,operation_id,created_at) VALUES(v_id,v_session,v_owner,p_evaluation,p_criterion,COALESCE(v_revision,0)+1,v_previous,p_action,IF(p_action='register',p_type,NULL),1,NULLIF(TRIM(p_note),''),p_operation,UTC_TIMESTAMP(3));
 END IF;
 COMMIT;
 IF p_kind='process' THEN SELECT 'saved' AS _set,e.* FROM process_criterion_exceptions e WHERE exception_id=v_id; ELSE SELECT 'saved' AS _set,e.* FROM biological_criterion_exceptions e WHERE exception_id=v_id; END IF;
END//
DELIMITER ;
