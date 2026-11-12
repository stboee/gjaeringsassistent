-- Gjæringsassistent p21r13 – Home Assistant measurement source
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
INSERT INTO measurement_source_profiles(source_profile_id,name,source_type,poll_interval_seconds,gap_threshold_seconds,fresh_age_minutes,stale_age_minutes,status,description,created_at,updated_at) VALUES('tilt-pro-blue-ha','Tilt Pro Blue · Home Assistant','home_assistant',300,300,15,60,'active','Normaliserte, reviderte bindinger per signal.',UTC_TIMESTAMP(3),UTC_TIMESTAMP(3));
INSERT INTO measurement_source_configurations(source_profile_id,parent_configuration_id,operation_id,note,created_at) VALUES('tilt-pro-blue-ha',NULL,'source-initial-tilt-pro-blue-ha','Opprinnelig sensorkonfigurasjon',UTC_TIMESTAMP(3));
INSERT INTO measurement_source_signal_bindings(configuration_id,signal_id,input_mode,entity_id,unit_id) SELECT configuration_id,'sg','sensor','sensor.bryggeri_tilt_pro_blue_bryggeri_tilt_pro_blue_sg','sg' FROM measurement_source_configurations WHERE operation_id='source-initial-tilt-pro-blue-ha';
INSERT INTO measurement_source_signal_bindings(configuration_id,signal_id,input_mode,entity_id,unit_id) SELECT configuration_id,'temperature','sensor','sensor.bryggeri_tilt_pro_blue_bryggeri_tilt_pro_blue_temperatur','celsius' FROM measurement_source_configurations WHERE operation_id='source-initial-tilt-pro-blue-ha';
INSERT INTO measurement_source_signal_bindings(configuration_id,signal_id,input_mode,entity_id,unit_id) SELECT configuration_id,'heartbeat','sensor','sensor.bryggeri_tilt_pro_blue_bryggeri_tilt_pro_blue_sist_oppdatert','timestamp' FROM measurement_source_configurations WHERE operation_id='source-initial-tilt-pro-blue-ha';
INSERT INTO measurement_source_signal_bindings(configuration_id,signal_id,input_mode,entity_id,unit_id) SELECT configuration_id,'rssi','sensor','sensor.bryggeri_tilt_pro_blue_bryggeri_tilt_pro_blue_rssi','dbm' FROM measurement_source_configurations WHERE operation_id='source-initial-tilt-pro-blue-ha';
INSERT INTO measurement_source_signal_bindings(configuration_id,signal_id,input_mode,entity_id,unit_id) SELECT configuration_id,'pressure','manual',NULL,'bar' FROM measurement_source_configurations WHERE operation_id='source-initial-tilt-pro-blue-ha';

-- p22r7 source-owned validation policy. Invalid samples are rejected, never clamped.
INSERT INTO measurement_source_validation_rules(source_profile_id,rule_id,signal_id,rule_order,model_id,enabled,created_at) VALUES
('tilt-pro-blue-ha','sg-range','sg',1,'hard_range_v1',1,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','sg-mad','sg',2,'robust_mad_v1',1,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','sg-jump','sg',3,'max_jump_v1',1,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','sg-minimum','sg',4,'minimum_acceptance_v1',1,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','temperature-range','temperature',1,'hard_range_v1',1,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','temperature-mad','temperature',2,'robust_mad_v1',1,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','temperature-jump','temperature',3,'max_jump_v1',1,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','temperature-minimum','temperature',4,'minimum_acceptance_v1',1,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','rssi-range','rssi',1,'hard_range_v1',1,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','rssi-mad','rssi',2,'robust_mad_v1',1,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','rssi-minimum','rssi',3,'minimum_acceptance_v1',1,UTC_TIMESTAMP(3))
ON DUPLICATE KEY UPDATE signal_id=VALUES(signal_id),rule_order=VALUES(rule_order),model_id=VALUES(model_id),enabled=VALUES(enabled);
INSERT INTO measurement_source_validation_rule_parameter_values(source_profile_id,rule_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) VALUES
('tilt-pro-blue-ha','sg-range','minimum_value','real',0.980,NULL,NULL,NULL,UTC_TIMESTAMP(3)),('tilt-pro-blue-ha','sg-range','maximum_value','real',1.200,NULL,NULL,NULL,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','sg-mad','mad_multiplier','real',6.0,NULL,NULL,NULL,UTC_TIMESTAMP(3)),('tilt-pro-blue-ha','sg-jump','maximum_delta','real',0.0008,NULL,NULL,NULL,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','sg-minimum','minimum_samples','integer',NULL,3,NULL,NULL,UTC_TIMESTAMP(3)),('tilt-pro-blue-ha','sg-minimum','minimum_fraction','real',0.50,NULL,NULL,NULL,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','temperature-range','minimum_value','real',-5,NULL,NULL,NULL,UTC_TIMESTAMP(3)),('tilt-pro-blue-ha','temperature-range','maximum_value','real',40,NULL,NULL,NULL,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','temperature-mad','mad_multiplier','real',6.0,NULL,NULL,NULL,UTC_TIMESTAMP(3)),('tilt-pro-blue-ha','temperature-jump','maximum_delta','real',5.0,NULL,NULL,NULL,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','temperature-minimum','minimum_samples','integer',NULL,3,NULL,NULL,UTC_TIMESTAMP(3)),('tilt-pro-blue-ha','temperature-minimum','minimum_fraction','real',0.50,NULL,NULL,NULL,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','rssi-range','minimum_value','real',-130,NULL,NULL,NULL,UTC_TIMESTAMP(3)),('tilt-pro-blue-ha','rssi-range','maximum_value','real',-1,NULL,NULL,NULL,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','rssi-mad','mad_multiplier','real',8.0,NULL,NULL,NULL,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','rssi-minimum','minimum_samples','integer',NULL,1,NULL,NULL,UTC_TIMESTAMP(3)),('tilt-pro-blue-ha','rssi-minimum','minimum_fraction','real',0.20,NULL,NULL,NULL,UTC_TIMESTAMP(3))
ON DUPLICATE KEY UPDATE data_type=VALUES(data_type),real_value=VALUES(real_value),integer_value=VALUES(integer_value),boolean_value=VALUES(boolean_value),text_value=VALUES(text_value);

INSERT INTO measurement_source_validation_rule_parameter_values(source_profile_id,rule_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) VALUES
('tilt-pro-blue-ha','sg-mad','noise_floor','real',0.0001,NULL,NULL,NULL,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','temperature-mad','noise_floor','real',0.05,NULL,NULL,NULL,UTC_TIMESTAMP(3)),
('tilt-pro-blue-ha','rssi-mad','noise_floor','real',1,NULL,NULL,NULL,UTC_TIMESTAMP(3));
