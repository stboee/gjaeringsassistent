-- Gjæringsassistent – MariaDB template registry seed draft 1
-- Idempotent registry seed converted from p18r5.
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

START TRANSACTION;
INSERT IGNORE INTO criterion_roles(role_id,label,description,created_at) VALUES ('required','Obligatorisk','Inngår i beslutningen og må være oppfylt.',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_roles(role_id,label,description,created_at) VALUES ('supporting','Støttende','Støtter vurderingen, men blokkerer ikke alene.',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_roles(role_id,label,description,created_at) VALUES ('information','Informasjon','Relevant kontekst som ikke påvirker beslutningen direkte.',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_models(model_id,label,description,created_at) VALUES ('threshold','Terskel','Sammenligner en verdi mot operator/grense.',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_models(model_id,label,description,created_at) VALUES ('observation','Observasjon','Krever at en fersk verdi finnes.',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_models(model_id,label,description,created_at) VALUES ('window_median_range','Median i vindu','Median i tidsvindu må ligge innen mål ± toleranse.',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_models(model_id,label,description,created_at) VALUES ('stability_window','Stabilitet i vindu','Variasjon i tidsvindu må være under grense.',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_model_parameters(model_id,parameter_id,sort_order,label,data_type,unit_source,fixed_unit,created_at) VALUES ('threshold','minimum_value',1,'Minimum','real','metric',NULL,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_model_parameters(model_id,parameter_id,sort_order,label,data_type,unit_source,fixed_unit,created_at) VALUES ('threshold','maximum_value',2,'Maksimum','real','metric',NULL,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_model_parameters(model_id,parameter_id,sort_order,label,data_type,unit_source,fixed_unit,created_at) VALUES ('threshold','maximum_age_minutes',3,'Maks alder','integer','fixed','min',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_model_parameters(model_id,parameter_id,sort_order,label,data_type,unit_source,fixed_unit,created_at) VALUES ('observation','maximum_age_minutes',1,'Maks alder','integer','fixed','min',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_model_parameters(model_id,parameter_id,sort_order,label,data_type,unit_source,fixed_unit,created_at) VALUES ('window_median_range','window_minutes',1,'Tidsvindu','integer','fixed','min',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_model_parameters(model_id,parameter_id,sort_order,label,data_type,unit_source,fixed_unit,created_at) VALUES ('window_median_range','minimum_samples',2,'Minimum antall målinger','integer','none',NULL,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_model_parameters(model_id,parameter_id,sort_order,label,data_type,unit_source,fixed_unit,created_at) VALUES ('window_median_range','maximum_age_minutes',3,'Maks alder','integer','fixed','min',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_model_parameters(model_id,parameter_id,sort_order,label,data_type,unit_source,fixed_unit,created_at) VALUES ('window_median_range','minimum_value',4,'Minimum','real','metric',NULL,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_model_parameters(model_id,parameter_id,sort_order,label,data_type,unit_source,fixed_unit,created_at) VALUES ('window_median_range','maximum_value',5,'Maksimum','real','metric',NULL,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_model_parameters(model_id,parameter_id,sort_order,label,data_type,unit_source,fixed_unit,created_at) VALUES ('stability_window','window_hours',1,'Tidsvindu','real','fixed','t',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_model_parameters(model_id,parameter_id,sort_order,label,data_type,unit_source,fixed_unit,created_at) VALUES ('stability_window','maximum_range_points',2,'Maks variasjon','real','metric',NULL,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_model_parameters(model_id,parameter_id,sort_order,label,data_type,unit_source,fixed_unit,created_at) VALUES ('stability_window','minimum_samples',3,'Minimum antall målinger','integer','none',NULL,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_model_parameters(model_id,parameter_id,sort_order,label,data_type,unit_source,fixed_unit,created_at) VALUES ('stability_window','minimum_span_hours',4,'Minimum tidsspenn','real','fixed','t',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_model_parameters(model_id,parameter_id,sort_order,label,data_type,unit_source,fixed_unit,created_at) VALUES ('stability_window','maximum_age_minutes',5,'Maks alder','integer','fixed','min',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_model_parameters(model_id,parameter_id,sort_order,label,data_type,unit_source,fixed_unit,created_at) VALUES ('stability_window','since_current_process_start',6,'Kun siden prosesstrinnets start','boolean','none',NULL,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('relative_sg_drop_points',1,'Relativt SG-fall','SG-poeng','derived',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('relative_sg_drop_points','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('relative_sg_drop_points','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('relative_sg_drop_points',0,NULL,NULL,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('relative_sg_drop_points',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('sg_rate_points_per_day',2,'SG-rate','SG-poeng/d','derived',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('sg_rate_points_per_day','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('sg_rate_points_per_day','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('sg_rate_points_per_day',0,NULL,NULL,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('sg_rate_points_per_day',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('apparent_attenuation_percent',4,'Tilsynelatende utgjæringsgrad','%','derived',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('apparent_attenuation_percent','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('apparent_attenuation_percent','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('apparent_attenuation_percent',0,NULL,NULL,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('apparent_attenuation_percent',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('tilt_sg',7,'Tilt SG / stabilitet','SG','continuous_sensor',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('tilt_sg','stability_window',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('tilt_sg','threshold',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('tilt_sg','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('tilt_sg',0,NULL,30,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('tilt_sg',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_stability_window_defaults(metric_id,window_hours,maximum_range_points,minimum_samples,minimum_span_hours,maximum_age_minutes,since_current_process_start,created_at) VALUES ('tilt_sg',24.0,1.0,3,18.0,NULL,0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('beer_temperature_c',8,'Øltemperatur','°C','continuous_sensor',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('beer_temperature_c','window_median_range',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('beer_temperature_c','threshold',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('beer_temperature_c','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('beer_temperature_c',0,NULL,30,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('beer_temperature_c',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_window_median_range_defaults(metric_id,window_minutes,minimum_samples,maximum_age_minutes,minimum_value,maximum_value,created_at) VALUES ('beer_temperature_c',30,5,30,9.2,10.8,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('manual_temperature_c',9,'Manuell temperatur','°C','manual_measurement',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('manual_temperature_c','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('manual_temperature_c','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('manual_temperature_c',0,NULL,30,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('manual_temperature_c',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('pressure_bar',10,'Tanktrykk','bar','manual_measurement',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('pressure_bar','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('pressure_bar','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('pressure_bar',0,NULL,30,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('pressure_bar',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('cooler_setpoint_c',11,'Kjølemaskinens settpunkt','°C','manual_measurement',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('cooler_setpoint_c','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('cooler_setpoint_c','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('cooler_setpoint_c',0,NULL,30,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('cooler_setpoint_c',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('airlock_activity',12,'Gjærlåsaktivitet','','manual_measurement',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('airlock_activity','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('airlock_activity','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('airlock_activity',0,NULL,30,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('airlock_activity',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('corrected_sg',13,'Manuell korrigert SG','SG','manual_measurement',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('corrected_sg','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('corrected_sg','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('corrected_sg',0,NULL,30,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('corrected_sg',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('cooler_calibration_offset_c',14,'Icemaster kalibrerings-offset','°C','manual_measurement',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('cooler_calibration_offset_c','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('cooler_calibration_offset_c','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('cooler_calibration_offset_c',0,NULL,30,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('cooler_calibration_offset_c',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('acetaldehyde_level',15,'Acetaldehyd','nivå','manual_measurement',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('acetaldehyde_level','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('acetaldehyde_level','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('acetaldehyde_level',0,NULL,30,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('acetaldehyde_level',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('diacetyl_level',16,'Diacetyl','nivå','manual_measurement',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('diacetyl_level','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('diacetyl_level','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('diacetyl_level',0,NULL,30,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('diacetyl_level',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('wort_like_level',17,'Vørterpreg','nivå','manual_measurement',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('wort_like_level','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('wort_like_level','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('wort_like_level',0,NULL,30,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('wort_like_level',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('sulfur_so2_level',18,'SO₂','nivå','manual_measurement',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('sulfur_so2_level','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('sulfur_so2_level','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('sulfur_so2_level',0,NULL,30,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('sulfur_so2_level',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('sulfur_h2s_level',19,'H₂S','nivå','manual_measurement',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('sulfur_h2s_level','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('sulfur_h2s_level','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('sulfur_h2s_level',0,NULL,30,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('sulfur_h2s_level',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('clarity_level',20,'Klarhet','nivå','manual_measurement',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('clarity_level','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('clarity_level','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('clarity_level',0,NULL,30,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('clarity_level',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('settling_yeast_level',21,'Utfelling i prøve','nivå','manual_measurement',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('settling_yeast_level','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('settling_yeast_level','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('settling_yeast_level',0,NULL,30,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('settling_yeast_level',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('settling_minutes',22,'Utfellingstid','min','manual_measurement',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('settling_minutes','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('settling_minutes','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('settling_minutes',0,NULL,30,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('settling_minutes',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO metrics(metric_id,sort_order,label,unit,source_class,created_at) VALUES ('biological_phase_order',23,'Biologisk fase','','derived',UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('biological_phase_order','threshold',1,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('biological_phase_order','observation',0,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('biological_phase_order',0,NULL,NULL,UTC_TIMESTAMP(3));
INSERT IGNORE INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('biological_phase_order',720,UTC_TIMESTAMP(3));
INSERT IGNORE INTO target_models(model_id,label,description,created_at) VALUES ('exact','Eksakt','Ett måltall.',UTC_TIMESTAMP(3));
INSERT IGNORE INTO target_models(model_id,label,description,created_at) VALUES ('range','Område','Minimum og maksimum.',UTC_TIMESTAMP(3));
INSERT IGNORE INTO target_metric_models(metric_id,model_id,created_at) VALUES ('beer_temperature_c','exact',UTC_TIMESTAMP(3));
INSERT IGNORE INTO target_metric_models(metric_id,model_id,created_at) VALUES ('beer_temperature_c','range',UTC_TIMESTAMP(3));
INSERT IGNORE INTO target_metric_models(metric_id,model_id,created_at) VALUES ('pressure_bar','exact',UTC_TIMESTAMP(3));
INSERT IGNORE INTO target_metric_models(metric_id,model_id,created_at) VALUES ('pressure_bar','range',UTC_TIMESTAMP(3));
INSERT IGNORE INTO action_types(action_type_id,label,created_at) VALUES ('set_target','Sett mål',UTC_TIMESTAMP(3));
INSERT IGNORE INTO action_types(action_type_id,label,created_at) VALUES ('operator_action','Operatørhandling',UTC_TIMESTAMP(3));
INSERT IGNORE INTO operator_operations(operation_id,label,created_at) VALUES ('pitch','Pitch gjær',UTC_TIMESTAMP(3));
INSERT IGNORE INTO operator_operations(operation_id,label,created_at) VALUES ('dry_hop','Tilsett tørrhumle',UTC_TIMESTAMP(3));
INSERT IGNORE INTO operator_operations(operation_id,label,created_at) VALUES ('sediment_dump','Dump bunnfall',UTC_TIMESTAMP(3));
INSERT IGNORE INTO pitch_modes(pitch_mode_id,label,created_at) VALUES ('dry','Tørrgjær',UTC_TIMESTAMP(3));
INSERT IGNORE INTO pitch_modes(pitch_mode_id,label,created_at) VALUES ('slurry','Slurry',UTC_TIMESTAMP(3));
INSERT IGNORE INTO measurement_methods(measurement_method_id,label,created_at) VALUES ('refractometer','Refraktometer',UTC_TIMESTAMP(3));
INSERT IGNORE INTO measurement_methods(measurement_method_id,label,created_at) VALUES ('hydrometer','Hydrometer',UTC_TIMESTAMP(3));
INSERT IGNORE INTO yeast_profiles(yeast_profile_id,name,created_at) VALUES ('fermentis-w3470','Fermentis SafLager W-34/70',UTC_TIMESTAMP(3));
INSERT IGNORE INTO calculation_models(model_id,label,description,created_at) VALUES ('median_first_samples','Median av første målinger','Median av de første N gyldige målingene.',UTC_TIMESTAMP(3));
INSERT IGNORE INTO calculation_models(model_id,label,description,created_at) VALUES ('linear_regression','Lineær regresjon','Lineær regresjon over et tidsvindu.',UTC_TIMESTAMP(3));

-- Generic metric calculation vocabulary. The model IDs are the only calculation
-- branches Node-RED may implement; metric IDs select models declaratively here.
INSERT IGNORE INTO calculation_models(model_id,label,description,created_at) VALUES
('metric-relative-sg-drop-v1','Relativt SG-fall v1','Beregner SG-fall fra etablert Tilt-baseline til aktuell Tilt-median.',UTC_TIMESTAMP(3)),
('metric-calculation-output-v1','Templateberegning som metrikk v1','Eksponerer resultatet fra en frozen biology calculation som metric.',UTC_TIMESTAMP(3)),
('metric-current-biology-order-v1','Gjeldende biologisk rekkefølge v1','Leser gjeldende biologisk faseorden som current-state metric uten freshness.',UTC_TIMESTAMP(3)),
('metric-direct-source-v1','Direkte registrert verdi v1','Eksponerer siste verdi fra en deklarert series- eller observasjonskilde uten metrikkspesifikk motorlogikk.',UTC_TIMESTAMP(3));

INSERT IGNORE INTO calculation_model_inputs(model_id,input_id,sort_order,label,created_at) VALUES
('median_first_samples','series_sg',1,'SG-serie',UTC_TIMESTAMP(3)),
('linear_regression','series_sg',1,'SG-serie',UTC_TIMESTAMP(3)),
('metric-relative-sg-drop-v1','series_sg',1,'SG-serie',UTC_TIMESTAMP(3)),
('metric-relative-sg-drop-v1','tilt_baseline',2,'Tilt-baseline',UTC_TIMESTAMP(3)),
('metric-calculation-output-v1','calculation',1,'Frozen biology calculation',UTC_TIMESTAMP(3)),
('metric-current-biology-order-v1','phase_order',1,'Gjeldende biologisk faseorden',UTC_TIMESTAMP(3)),
('metric-direct-source-v1','value',1,'Deklarert kildeverdi',UTC_TIMESTAMP(3));

INSERT IGNORE INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES
('median_first_samples','sample_count',1,'Antall første prøver','integer',UTC_TIMESTAMP(3)),
('linear_regression','window_hours',1,'Regresjonsvindu','real',UTC_TIMESTAMP(3)),
('linear_regression','minimum_samples',2,'Minimum datapunkter','integer',UTC_TIMESTAMP(3)),
('metric-relative-sg-drop-v1','current_sample_count',1,'Antall siste SG-punkter i aktuell median','integer',UTC_TIMESTAMP(3));

INSERT IGNORE INTO calculation_models(model_id,label,description,created_at) VALUES
('metric-apparent-attenuation-v1','Tilsynelatende utgjæringsgrad v1','Korrigerer aktuell Tilt-SG mot manuell OG via etablert Tilt-baseline og beregner apparent attenuation.',UTC_TIMESTAMP(3));
INSERT IGNORE INTO calculation_model_inputs(model_id,input_id,sort_order,label,created_at) VALUES
('metric-apparent-attenuation-v1','series_sg',1,'SG-serie',UTC_TIMESTAMP(3)),
('metric-apparent-attenuation-v1','og',2,'Faktisk OG',UTC_TIMESTAMP(3)),
('metric-apparent-attenuation-v1','tilt_baseline',3,'Tilt-baseline',UTC_TIMESTAMP(3));
INSERT IGNORE INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES
('metric-apparent-attenuation-v1','current_sample_count',1,'Antall siste SG-punkter i aktuell median','integer',UTC_TIMESTAMP(3));

-- Every metric gets explicit runtime semantics, including whether timestamp age
-- can be applied. No evaluator may infer this from the metric name.
INSERT IGNORE INTO metric_runtime_rules(metric_id,calculation_model_id,freshness_mode,created_at) VALUES
('relative_sg_drop_points','metric-relative-sg-drop-v1','source_timestamp',UTC_TIMESTAMP(3)),
('apparent_attenuation_percent','metric-apparent-attenuation-v1','source_timestamp',UTC_TIMESTAMP(3)),
('sg_rate_points_per_day','metric-calculation-output-v1','source_timestamp',UTC_TIMESTAMP(3)),
('tilt_sg','metric-direct-source-v1','source_timestamp',UTC_TIMESTAMP(3)),
('beer_temperature_c','metric-direct-source-v1','source_timestamp',UTC_TIMESTAMP(3)),
('manual_temperature_c','metric-direct-source-v1','source_timestamp',UTC_TIMESTAMP(3)),
('pressure_bar','metric-direct-source-v1','source_timestamp',UTC_TIMESTAMP(3)),
('cooler_setpoint_c','metric-direct-source-v1','source_timestamp',UTC_TIMESTAMP(3)),
('airlock_activity','metric-direct-source-v1','source_timestamp',UTC_TIMESTAMP(3)),
('corrected_sg','metric-direct-source-v1','source_timestamp',UTC_TIMESTAMP(3)),
('cooler_calibration_offset_c','metric-direct-source-v1','source_timestamp',UTC_TIMESTAMP(3)),
('acetaldehyde_level','metric-direct-source-v1','source_timestamp',UTC_TIMESTAMP(3)),
('diacetyl_level','metric-direct-source-v1','source_timestamp',UTC_TIMESTAMP(3)),
('wort_like_level','metric-direct-source-v1','source_timestamp',UTC_TIMESTAMP(3)),
('sulfur_so2_level','metric-direct-source-v1','source_timestamp',UTC_TIMESTAMP(3)),
('sulfur_h2s_level','metric-direct-source-v1','source_timestamp',UTC_TIMESTAMP(3)),
('clarity_level','metric-direct-source-v1','source_timestamp',UTC_TIMESTAMP(3)),
('settling_yeast_level','metric-direct-source-v1','source_timestamp',UTC_TIMESTAMP(3)),
('settling_minutes','metric-direct-source-v1','source_timestamp',UTC_TIMESTAMP(3)),
('biological_phase_order','metric-current-biology-order-v1','not_applicable',UTC_TIMESTAMP(3));

-- Generic metric-output validity is domain metadata. Evaluators and analysis
-- producers must reject values outside these ranges; they must never clamp them.
UPDATE metric_runtime_rules SET valid_minimum_value=-100.0, valid_maximum_value=100.0 WHERE metric_id='relative_sg_drop_points';
UPDATE metric_runtime_rules SET valid_minimum_value=-10.0, valid_maximum_value=120.0 WHERE metric_id='apparent_attenuation_percent';
UPDATE metric_runtime_rules SET valid_minimum_value=-20.0, valid_maximum_value=50.0 WHERE metric_id='sg_rate_points_per_day';

INSERT IGNORE INTO metric_runtime_inputs(metric_id,model_id,input_id,source_kind,source_id,created_at) VALUES
('relative_sg_drop_points','metric-relative-sg-drop-v1','series_sg','series','tilt_sg',UTC_TIMESTAMP(3)),
('relative_sg_drop_points','metric-relative-sg-drop-v1','tilt_baseline','biology_calculation','tilt_baseline',UTC_TIMESTAMP(3)),
('apparent_attenuation_percent','metric-apparent-attenuation-v1','series_sg','series','tilt_sg',UTC_TIMESTAMP(3)),
('apparent_attenuation_percent','metric-apparent-attenuation-v1','og','session_field','og',UTC_TIMESTAMP(3)),
('apparent_attenuation_percent','metric-apparent-attenuation-v1','tilt_baseline','biology_calculation','tilt_baseline',UTC_TIMESTAMP(3)),
('sg_rate_points_per_day','metric-calculation-output-v1','calculation','biology_calculation','sg_rate',UTC_TIMESTAMP(3)),
('biological_phase_order','metric-current-biology-order-v1','phase_order','biology_state','current_phase_order',UTC_TIMESTAMP(3)),
('tilt_sg','metric-direct-source-v1','value','series','tilt_sg',UTC_TIMESTAMP(3)),
('beer_temperature_c','metric-direct-source-v1','value','series','beer_temperature_c',UTC_TIMESTAMP(3)),
('manual_temperature_c','metric-direct-source-v1','value','observation','manual_temperature_c',UTC_TIMESTAMP(3)),
('pressure_bar','metric-direct-source-v1','value','observation','pressure_bar',UTC_TIMESTAMP(3)),
('cooler_setpoint_c','metric-direct-source-v1','value','observation','cooler_setpoint_c',UTC_TIMESTAMP(3)),
('airlock_activity','metric-direct-source-v1','value','observation','airlock_activity',UTC_TIMESTAMP(3)),
('corrected_sg','metric-direct-source-v1','value','observation','corrected_sg',UTC_TIMESTAMP(3)),
('cooler_calibration_offset_c','metric-direct-source-v1','value','observation','cooler_calibration_offset_c',UTC_TIMESTAMP(3)),
('acetaldehyde_level','metric-direct-source-v1','value','observation','acetaldehyde_level',UTC_TIMESTAMP(3)),
('diacetyl_level','metric-direct-source-v1','value','observation','diacetyl_level',UTC_TIMESTAMP(3)),
('wort_like_level','metric-direct-source-v1','value','observation','wort_like_level',UTC_TIMESTAMP(3)),
('sulfur_so2_level','metric-direct-source-v1','value','observation','sulfur_so2_level',UTC_TIMESTAMP(3)),
('sulfur_h2s_level','metric-direct-source-v1','value','observation','sulfur_h2s_level',UTC_TIMESTAMP(3)),
('clarity_level','metric-direct-source-v1','value','observation','clarity_level',UTC_TIMESTAMP(3)),
('settling_yeast_level','metric-direct-source-v1','value','observation','settling_yeast_level',UTC_TIMESTAMP(3)),
('settling_minutes','metric-direct-source-v1','value','observation','settling_minutes',UTC_TIMESTAMP(3));

INSERT IGNORE INTO metric_runtime_parameter_values(metric_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) VALUES
('relative_sg_drop_points','metric-relative-sg-drop-v1','current_sample_count','integer',NULL,3,NULL,NULL,UTC_TIMESTAMP(3)),
('apparent_attenuation_percent','metric-apparent-attenuation-v1','current_sample_count','integer',NULL,3,NULL,NULL,UTC_TIMESTAMP(3));

INSERT IGNORE INTO biology_calculation_types(calculation_id,label,created_at) VALUES ('tilt_baseline','Tilt baseline',UTC_TIMESTAMP(3));
INSERT IGNORE INTO biology_calculation_types(calculation_id,label,created_at) VALUES ('sg_rate','SG-rate',UTC_TIMESTAMP(3));
INSERT IGNORE INTO biology_calculation_type_models(calculation_id,model_id,created_at) VALUES ('tilt_baseline','median_first_samples',UTC_TIMESTAMP(3));
-- Legacy regression remains registry vocabulary, not an allowed p24r6 SG-rate choice.
COMMIT;

-- p23r2 display precision is registry data; frontend must not choose precision.
UPDATE metrics SET display_decimals=1 WHERE metric_id='apparent_attenuation_percent';
UPDATE metrics SET display_decimals=2 WHERE metric_id IN ('relative_sg_drop_points','sg_rate_points_per_day','beer_temperature_c','manual_temperature_c','pressure_bar','cooler_setpoint_c','cooler_calibration_offset_c');
UPDATE metrics SET display_decimals=4 WHERE metric_id='tilt_sg';
UPDATE metrics SET display_decimals=0 WHERE metric_id IN ('acetaldehyde_level','diacetyl_level','wort_like_level','sulfur_so2_level','sulfur_h2s_level','clarity_level','settling_yeast_level','settling_minutes','biological_phase_order');


-- Measurement validation vocabulary -------------------------------------------
INSERT IGNORE INTO measurement_validation_models(model_id,label,description,created_at) VALUES
('hard_range_v1','Hardt gyldighetsområde','Forkaster numeriske samples utenfor deklarert minimum/maksimum.',UTC_TIMESTAMP(3)),
('robust_mad_v1','Robust MAD-filter','Forkaster uteliggere i en bøtte ved median absolute deviation uten å endre godkjente samples.',UTC_TIMESTAMP(3)),
('max_jump_v1','Maks hopp fra forrige bøtte','Forkaster bøtte dersom robust verdi avviker mer enn deklarert absolutt grense fra forrige godkjente bøtte.',UTC_TIMESTAMP(3)),
('minimum_acceptance_v1','Minstekrav til godkjent datagrunnlag','Krever minimum antall og andel godkjente samples.',UTC_TIMESTAMP(3));
INSERT IGNORE INTO measurement_validation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES
('hard_range_v1','minimum_value',1,'Minimum','real',UTC_TIMESTAMP(3)),('hard_range_v1','maximum_value',2,'Maksimum','real',UTC_TIMESTAMP(3)),
('robust_mad_v1','mad_multiplier',1,'MAD-multiplikator','real',UTC_TIMESTAMP(3)),
('max_jump_v1','maximum_delta',1,'Maksimalt hopp','real',UTC_TIMESTAMP(3)),
('minimum_acceptance_v1','minimum_samples',1,'Minimum samples','integer',UTC_TIMESTAMP(3)),('minimum_acceptance_v1','minimum_fraction',2,'Minimum godkjent andel','real',UTC_TIMESTAMP(3));

-- p24r3 generic, metadata-controlled methodology.
INSERT INTO calculation_models(model_id,label,description,created_at) VALUES
('pitch_baseline_median_v1','Kvalifisert pitch-baseline','Første sammenhengende, stabile SG-serie nær effektiv pitch; beholdes som DB-faktum.',UTC_TIMESTAMP(3)),
('robust_linear_regression_v1','Robust lineær SG-regresjon','Huber-vektet trend med konservativt følsomhetsbånd og eksplisitte kvalitetsgrenser.',UTC_TIMESTAMP(3)),
('metric-rolling-sg-range-v1','Rullerende SG-stabilitet','Maks–min av godkjente SG-medianer i et deklarert tidsvindu.',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_inputs(model_id,input_id,sort_order,label,created_at) VALUES
('pitch_baseline_median_v1','series_sg',1,'SG-serie',UTC_TIMESTAMP(3)),
('robust_linear_regression_v1','series_sg',1,'SG-serie',UTC_TIMESTAMP(3)),
('metric-rolling-sg-range-v1','series_sg',1,'SG-serie',UTC_TIMESTAMP(3));
INSERT INTO calculation_models(model_id,label,description,created_at) VALUES ('endpoint_rate_v1','SG-fall mellom målte endepunkter','Faktisk SG-forskjell delt på faktisk tid; ingen regresjon.',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_inputs(model_id,input_id,sort_order,label,created_at) VALUES ('endpoint_rate_v1','series_sg',1,'Godkjent SG-serie',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('endpoint_rate_v1','window_hours',1,'Analyseperiode · timer','real',UTC_TIMESTAMP(3)),('endpoint_rate_v1','minimum_samples',2,'Minste antall målepunkter','integer',UTC_TIMESTAMP(3)),('endpoint_rate_v1','minimum_span_minutes',3,'Minste sammenhengende tidsspenn · min','real',UTC_TIMESTAMP(3));
INSERT INTO biology_calculation_type_models(calculation_id,model_id,created_at) VALUES
('tilt_baseline','pitch_baseline_median_v1',UTC_TIMESTAMP(3)),('sg_rate','endpoint_rate_v1',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('pitch_baseline_median_v1','sample_count',1,'Minste antall målepunkter','integer',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('pitch_baseline_median_v1','window_minutes',2,'Pitchvindu · min','real',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('pitch_baseline_median_v1','maximum_start_delay_minutes',3,'Maks forsinkelse fra pitch · min','real',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('pitch_baseline_median_v1','minimum_span_minutes',4,'Minste sammenhengende tidsspenn · min','real',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('pitch_baseline_median_v1','maximum_range_points',5,'Maks SG-spenn · SG-poeng','real',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('pitch_baseline_median_v1','maximum_gap_minutes',6,'Maks intervall mellom målepunkter · min','real',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('robust_linear_regression_v1','window_hours',1,'Analyseperiode · timer','real',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('robust_linear_regression_v1','minimum_samples',2,'Minste antall målepunkter','integer',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('robust_linear_regression_v1','minimum_span_minutes',3,'Minste sammenhengende tidsspenn · min','real',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('robust_linear_regression_v1','noise_floor_sg',4,'Minste residualspredning · SG','real',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('robust_linear_regression_v1','huber_multiplier',5,'Huber-faktor','real',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('robust_linear_regression_v1','iterations',6,'Antall robuste tilpasninger','integer',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('robust_linear_regression_v1','maximum_outlier_fraction',7,'Maks andel avvikende målepunkter','real',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('robust_linear_regression_v1','outlier_multiplier',8,'Residualgrense · spredningsfaktor','real',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('robust_linear_regression_v1','uncertainty_multiplier',9,'Følsomhetsfaktor','real',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('robust_linear_regression_v1','maximum_uncertainty_rate',10,'Maks halv båndbredde · SG-poeng/døgn','real',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('metric-rolling-sg-range-v1','window_hours',1,'window_hours','real',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('metric-rolling-sg-range-v1','minimum_samples',2,'minimum_samples','integer',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('metric-rolling-sg-range-v1','minimum_span_hours',3,'minimum_span_hours','real',UTC_TIMESTAMP(3));
INSERT INTO metrics(metric_id,sort_order,label,unit,source_class,display_decimals,created_at) VALUES ('sg_stability_24h_points',124,'SG-stabilitet 24 t','SG-poeng','derived',2,UTC_TIMESTAMP(3));
INSERT INTO metric_runtime_rules(metric_id,calculation_model_id,freshness_mode,valid_minimum_value,valid_maximum_value,created_at) VALUES ('sg_stability_24h_points','metric-rolling-sg-range-v1','source_timestamp',0,100,UTC_TIMESTAMP(3));
INSERT INTO metric_runtime_inputs(metric_id,model_id,input_id,source_kind,source_id,created_at) VALUES ('sg_stability_24h_points','metric-rolling-sg-range-v1','series_sg','series','tilt_sg',UTC_TIMESTAMP(3));
INSERT INTO metric_runtime_parameter_values(metric_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) VALUES ('sg_stability_24h_points','metric-rolling-sg-range-v1','window_hours','real',24.0,NULL,NULL,NULL,UTC_TIMESTAMP(3));
INSERT INTO metric_runtime_parameter_values(metric_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) VALUES ('sg_stability_24h_points','metric-rolling-sg-range-v1','minimum_samples','integer',NULL,3,NULL,NULL,UTC_TIMESTAMP(3));
INSERT INTO metric_runtime_parameter_values(metric_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) VALUES ('sg_stability_24h_points','metric-rolling-sg-range-v1','minimum_span_hours','real',18.0,NULL,NULL,NULL,UTC_TIMESTAMP(3));
INSERT INTO metrics(metric_id,sort_order,label,unit,source_class,display_decimals,created_at) VALUES ('sg_stability_48h_points',148,'SG-stabilitet 48 t','SG-poeng','derived',2,UTC_TIMESTAMP(3));
INSERT INTO metric_runtime_rules(metric_id,calculation_model_id,freshness_mode,valid_minimum_value,valid_maximum_value,created_at) VALUES ('sg_stability_48h_points','metric-rolling-sg-range-v1','source_timestamp',0,100,UTC_TIMESTAMP(3));
INSERT INTO metric_runtime_inputs(metric_id,model_id,input_id,source_kind,source_id,created_at) VALUES ('sg_stability_48h_points','metric-rolling-sg-range-v1','series_sg','series','tilt_sg',UTC_TIMESTAMP(3));
INSERT INTO metric_runtime_parameter_values(metric_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) VALUES ('sg_stability_48h_points','metric-rolling-sg-range-v1','window_hours','real',48.0,NULL,NULL,NULL,UTC_TIMESTAMP(3));
INSERT INTO metric_runtime_parameter_values(metric_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) VALUES ('sg_stability_48h_points','metric-rolling-sg-range-v1','minimum_samples','integer',NULL,3,NULL,NULL,UTC_TIMESTAMP(3));
INSERT INTO metric_runtime_parameter_values(metric_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) VALUES ('sg_stability_48h_points','metric-rolling-sg-range-v1','minimum_span_hours','real',36.0,NULL,NULL,NULL,UTC_TIMESTAMP(3));
INSERT INTO measurement_validation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('robust_mad_v1','noise_floor',2,'Minste støyskala','real',UTC_TIMESTAMP(3));

-- p24r6: measured endpoint rate and explicitly separate raw/manual attenuation.
INSERT INTO calculation_models(model_id,label,description,created_at) VALUES
('metric-raw-attenuation-v1','Utgjæringsgrad · rå Tilt','Faktisk OG og siste godkjente Tilt-SG, uten pitchoffset eller kalibreringsestimat.',UTC_TIMESTAMP(3)),
('metric-manual-attenuation-v1','Utgjæringsgrad · manuell kontroll','Faktisk OG og instrument-/temperaturkorrigert manuell SG. Ingen kildebytte.',UTC_TIMESTAMP(3)),
('metric-raw-sg-drop-v1','SG-fall · OG mot rå Tilt','Faktisk OG minus siste godkjente Tilt-SG i SG-poeng. Tilt-offset er ikke korrigert.',UTC_TIMESTAMP(3));
INSERT INTO calculation_model_inputs(model_id,input_id,sort_order,label,created_at) VALUES
('metric-raw-attenuation-v1','series_sg',1,'Rå Tilt-SG',UTC_TIMESTAMP(3)),('metric-raw-attenuation-v1','og',2,'Faktisk OG',UTC_TIMESTAMP(3)),
('metric-manual-attenuation-v1','value',1,'Korrigert manuell SG',UTC_TIMESTAMP(3)),('metric-manual-attenuation-v1','og',2,'Faktisk OG',UTC_TIMESTAMP(3)),
('metric-raw-sg-drop-v1','series_sg',1,'Rå Tilt-SG',UTC_TIMESTAMP(3)),('metric-raw-sg-drop-v1','og',2,'Faktisk OG',UTC_TIMESTAMP(3));
INSERT INTO metrics(metric_id,sort_order,label,unit,source_class,display_decimals,created_at) VALUES
('manual_apparent_attenuation_percent',5,'Tilsynelatende utgjæringsgrad · manuell kontroll','%','derived',1,UTC_TIMESTAMP(3));
INSERT INTO criterion_metric_models(metric_id,model_id,is_default,created_at) VALUES ('manual_apparent_attenuation_percent','threshold',1,UTC_TIMESTAMP(3)),('manual_apparent_attenuation_percent','observation',0,UTC_TIMESTAMP(3));
INSERT INTO criterion_metric_threshold_defaults(metric_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES ('manual_apparent_attenuation_percent',0,NULL,720,UTC_TIMESTAMP(3));
INSERT INTO criterion_metric_observation_defaults(metric_id,maximum_age_minutes,created_at) VALUES ('manual_apparent_attenuation_percent',720,UTC_TIMESTAMP(3));
INSERT INTO metric_runtime_rules(metric_id,calculation_model_id,freshness_mode,valid_minimum_value,valid_maximum_value,created_at) VALUES ('manual_apparent_attenuation_percent','metric-manual-attenuation-v1','source_timestamp',-10,120,UTC_TIMESTAMP(3));
DELETE FROM metric_runtime_inputs WHERE metric_id IN ('apparent_attenuation_percent','relative_sg_drop_points');
DELETE FROM metric_runtime_parameter_values WHERE metric_id IN ('apparent_attenuation_percent','relative_sg_drop_points');
UPDATE metric_runtime_rules SET calculation_model_id='metric-raw-attenuation-v1' WHERE metric_id='apparent_attenuation_percent';
UPDATE metric_runtime_rules SET calculation_model_id='metric-raw-sg-drop-v1' WHERE metric_id='relative_sg_drop_points';
INSERT INTO metric_runtime_inputs(metric_id,model_id,input_id,source_kind,source_id,created_at) VALUES
('apparent_attenuation_percent','metric-raw-attenuation-v1','series_sg','series','tilt_sg',UTC_TIMESTAMP(3)),('apparent_attenuation_percent','metric-raw-attenuation-v1','og','session_field','og',UTC_TIMESTAMP(3)),
('relative_sg_drop_points','metric-raw-sg-drop-v1','series_sg','series','tilt_sg',UTC_TIMESTAMP(3)),('relative_sg_drop_points','metric-raw-sg-drop-v1','og','session_field','og',UTC_TIMESTAMP(3)),
('manual_apparent_attenuation_percent','metric-manual-attenuation-v1','value','observation','corrected_sg',UTC_TIMESTAMP(3)),('manual_apparent_attenuation_percent','metric-manual-attenuation-v1','og','session_field','og',UTC_TIMESTAMP(3));
UPDATE metrics SET label='Tilsynelatende utgjæringsgrad · rå Tilt' WHERE metric_id='apparent_attenuation_percent';


INSERT INTO calculation_model_parameters(model_id,parameter_id,sort_order,label,data_type,created_at) VALUES ('metric-manual-attenuation-v1','maximum_age_minutes',1,'Maksimal alder på manuell kontroll','integer',UTC_TIMESTAMP(3));
INSERT INTO metric_runtime_parameter_values(metric_id,model_id,parameter_id,data_type,integer_value,created_at) VALUES ('manual_apparent_attenuation_percent','metric-manual-attenuation-v1','maximum_age_minutes','integer',720,UTC_TIMESTAMP(3));

INSERT INTO graph_render_policy VALUES (1,900,420,280,68,20,46,48,11,11,10,'sans-serif',2.4,100,2,UTC_TIMESTAMP(3));

INSERT INTO read_model_execution_policy(policy_id,json_staging_bytes,overview_clock_refresh_seconds) VALUES(1,33554432,60);
