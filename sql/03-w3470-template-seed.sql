-- W-34/70 published p18 template seed for p20r1
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

INSERT IGNORE INTO templates(template_id,created_at) VALUES ('w3470-standard','2026-09-27 01:04:57.142');

INSERT IGNORE INTO template_versions(version_id,template_id,status,version_label,based_on_version_id,name,created_at,published_at) VALUES ('w3470-standard@3.0','w3470-standard','published','3.0',NULL,'W-34/70 standardprosess – biologisk styrt','2026-09-27 01:04:57.142','2026-09-27 01:04:57.142');

INSERT IGNORE INTO template_defaults(version_id,batch_name_default,volume_l_default,og_default,expected_attenuation_min_percent,expected_attenuation_max_percent,pitch_temperature_c_default,pitch_mode_id,yeast_profile_id,yeast_amount_g_default,measurement_method_id,sample_temperature_c_default,calibration_temperature_c_default,manual_temperature_c_default,pressure_bar_default,cooler_setpoint_c_default,cooler_calibration_offset_c_default,airlock_activity_default,acetaldehyde_level_default,diacetyl_level_default,wort_like_level_default,sulfur_so2_level_default,sulfur_h2s_level_default,clarity_level_default,settling_yeast_level_default,settling_minutes_default,user_conclusion_default,measurement_note_default,created_at) VALUES ('w3470-standard@3.0','W-34/70 batch',150.0,1.050,80.0,84.0,12.0,'dry','fermentis-w3470',200.0,'refractometer',20.0,20.0,12.0,0.0,12.0,0.0,'none',0,0,0,0,0,0,0,0,'uncertain','','2026-09-27 01:04:57.142');

-- Materialize the generic metric vocabulary into this concrete published
-- template. These rows are now part of the template contract; runtime freezes
-- them from the template and never reaches back to registry defaults.
INSERT IGNORE INTO template_metric_runtime_rules(version_id,metric_id,calculation_model_id,freshness_mode,valid_minimum_value,valid_maximum_value,created_at)
SELECT 'w3470-standard@3.0',metric_id,calculation_model_id,freshness_mode,valid_minimum_value,valid_maximum_value,'2026-09-27 01:04:57.142'
FROM metric_runtime_rules;

INSERT IGNORE INTO template_metric_runtime_inputs(version_id,metric_id,model_id,input_id,source_kind,source_id,created_at)
SELECT 'w3470-standard@3.0',metric_id,model_id,input_id,source_kind,source_id,'2026-09-27 01:04:57.142'
FROM metric_runtime_inputs;

INSERT IGNORE INTO template_metric_runtime_parameter_values(version_id,metric_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at)
SELECT 'w3470-standard@3.0',metric_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,'2026-09-27 01:04:57.142'
FROM metric_runtime_parameter_values;


INSERT IGNORE INTO template_biology_calculations(version_id,calculation_id,model_id,created_at) VALUES ('w3470-standard@3.0','sg_rate','endpoint_rate_v1','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_biology_calculations(version_id,calculation_id,model_id,created_at) VALUES ('w3470-standard@3.0','tilt_baseline','pitch_baseline_median_v1','2026-09-27 01:04:57.142');

INSERT IGNORE INTO template_biology_calculation_median_first_samples(version_id,calculation_id,model_id,sample_count,created_at) VALUES ('w3470-standard@3.0','tilt_baseline','pitch_baseline_median_v1',3,'2026-09-27 01:04:57.142');

INSERT IGNORE INTO template_biology_calculation_linear_regression(version_id,calculation_id,model_id,window_hours,minimum_samples,created_at) VALUES ('w3470-standard@3.0','sg_rate','endpoint_rate_v1',24.0,12,'2026-09-27 01:04:57.142');

INSERT IGNORE INTO template_biology_calculation_inputs(version_id,calculation_id,model_id,input_id,source_kind,source_id,created_at) VALUES
('w3470-standard@3.0','tilt_baseline','pitch_baseline_median_v1','series_sg','series','tilt_sg','2026-09-27 01:04:57.142'),
('w3470-standard@3.0','sg_rate','endpoint_rate_v1','series_sg','series','tilt_sg','2026-09-27 01:04:57.142');

INSERT IGNORE INTO template_biology_calculation_parameter_values(version_id,calculation_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) VALUES
('w3470-standard@3.0','tilt_baseline','pitch_baseline_median_v1','sample_count','integer',NULL,3,NULL,NULL,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','sg_rate','endpoint_rate_v1','window_hours','real',24.0,NULL,NULL,NULL,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','sg_rate','endpoint_rate_v1','minimum_samples','integer',NULL,12,NULL,NULL,'2026-09-27 01:04:57.142');


INSERT IGNORE INTO template_biological_phases(version_id,phase_id,phase_order,name,description,created_at) VALUES ('w3470-standard@3.0','B1',1,'Inokulert og tilpasning','Etter pitch; gjæren tilpasser seg før målbar aktivitet.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_biological_phases(version_id,phase_id,phase_order,name,description,created_at) VALUES ('w3470-standard@3.0','B2',2,'Aktivitetsstart og tidlig vekst','Målbar gjæringsaktivitet er etablert.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_biological_phases(version_id,phase_id,phase_order,name,description,created_at) VALUES ('w3470-standard@3.0','B3',3,'Aktiv hovedgjæring','Hovedgjæringen er tydelig etablert og har høy aktivitet.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_biological_phases(version_id,phase_id,phase_order,name,description,created_at) VALUES ('w3470-standard@3.0','B4',4,'Sen gjæring','Utgjæringen er langt kommet og gjæringshastigheten har avtatt.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_biological_phases(version_id,phase_id,phase_order,name,description,created_at) VALUES ('w3470-standard@3.0','B5',5,'Modning og metabolsk opprydding','Nær slutt på utgjæring; gjæren er fortsatt metabolsk aktiv.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_biological_phases(version_id,phase_id,phase_order,name,description,created_at) VALUES ('w3470-standard@3.0','B6',6,'Stabil utgjæring','Forventet utgjæring er nådd og SG er stabil innen definert målevindu.','2026-09-27 01:04:57.142');






-- p23r2: understandable biological criteria. Data freshness/coverage is an evaluation-readiness concern, not a phase criterion.
INSERT IGNORE INTO template_biological_criteria(version_id,phase_id,criterion_id,criterion_order,enabled,metric_id,model_id,role_id,label,created_at) VALUES
('w3470-standard@3.0','B2','b2-relative-drop',1,1,'relative_sg_drop_points','threshold','required','SG-fall siden start','2026-09-27 01:04:57.142'),
('w3470-standard@3.0','B3','b3-sg-rate',1,1,'sg_rate_points_per_day','threshold','required','SG-rate','2026-09-27 01:04:57.142'),
('w3470-standard@3.0','B4','b4-attenuation',1,1,'apparent_attenuation_percent','threshold','required','Utgjæringsgrad','2026-09-27 01:04:57.142'),
('w3470-standard@3.0','B4','b4-sg-rate',2,1,'sg_rate_points_per_day','threshold','required','Avtagende SG-rate','2026-09-27 01:04:57.142'),
('w3470-standard@3.0','B5','b5-attenuation',1,1,'apparent_attenuation_percent','threshold','required','Utgjæringsgrad','2026-09-27 01:04:57.142'),
('w3470-standard@3.0','B6','b6-attenuation',1,1,'apparent_attenuation_percent','threshold','required','Forventet utgjæring nådd','2026-09-27 01:04:57.142'),
('w3470-standard@3.0','B6','b6-sg-stability',2,1,'tilt_sg','stability_window','required','SG-stabilitet','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_biological_criterion_threshold(version_id,phase_id,criterion_id,model_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES
('w3470-standard@3.0','B2','b2-relative-drop','threshold',1.5,NULL,NULL,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','B3','b3-sg-rate','threshold',1.5,NULL,NULL,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','B4','b4-attenuation','threshold',60.0,NULL,NULL,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','B4','b4-sg-rate','threshold',NULL,1.5,NULL,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','B5','b5-attenuation','threshold',75.0,NULL,NULL,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','B6','b6-attenuation','threshold',80.0,NULL,NULL,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_biological_criterion_stability_window(version_id,phase_id,criterion_id,model_id,window_hours,maximum_range_points,minimum_samples,minimum_span_hours,maximum_age_minutes,since_current_process_start,created_at) VALUES
('w3470-standard@3.0','B6','b6-sg-stability','stability_window',24.0,1.0,12,18.0,NULL,0,'2026-09-27 01:04:57.142');

INSERT IGNORE INTO template_process_steps(version_id,process_id,process_order,enabled,historical_replay_auto_transition_allowed,name,description,created_at) VALUES ('w3470-standard@3.0','P1',1,1,1,'Klargjøring, pitch og temperaturstabilisering','Registrer pitch ved faktisk temperatur og kjøl kontrollert mot første gjæringsmål. Pitchtemperatur og gjæringstemperatur er separate størrelser.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_steps(version_id,process_id,process_order,enabled,historical_replay_auto_transition_allowed,name,description,created_at) VALUES ('w3470-standard@3.0','P2',2,1,1,'Kald hovedgjæring','Hold kaldt mens gjæringen etableres og går inn i aktiv hovedgjæring.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_steps(version_id,process_id,process_order,enabled,historical_replay_auto_transition_allowed,name,description,created_at) VALUES ('w3470-standard@3.0','P3',3,1,0,'Første temperaturøkning mot 10 °C','Øk først når hovedgjæringen er solid etablert. Terskelen er kalibrert konservativt mot den vellykkede IPL-batchen.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_steps(version_id,process_id,process_order,enabled,historical_replay_auto_transition_allowed,name,description,created_at) VALUES ('w3470-standard@3.0','P4',4,1,0,'Videre temperaturøkning mot 12 °C','Videre ramp styres av biologisk fremdrift, ikke av timer siden forrige endring.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_steps(version_id,process_id,process_order,enabled,historical_replay_auto_transition_allowed,name,description,created_at) VALUES ('w3470-standard@3.0','P5',5,1,0,'Varm sluttfase mot 14 °C','Øk når biologien er i B5 og forrige temperaturmål er nådd.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_steps(version_id,process_id,process_order,enabled,historical_replay_auto_transition_allowed,name,description,created_at) VALUES ('w3470-standard@3.0','P6',6,1,0,'Modning og metabolsk opprydding','Hold varm sluttfase mens biologien nærmer seg stabil forventet utgjæring.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_steps(version_id,process_id,process_order,enabled,historical_replay_auto_transition_allowed,name,description,created_at) VALUES ('w3470-standard@3.0','P7',7,1,0,'Tørrhumling','Sen varm tørrhumling etter at B6 har bekreftet forventet og stabil utgjæring. Kan deaktiveres i templates uten tørrhumling.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_steps(version_id,process_id,process_order,enabled,historical_replay_auto_transition_allowed,name,description,created_at) VALUES ('w3470-standard@3.0','P8',8,1,0,'Kaldkrasj mot 4 °C','Kaldkrasj først etter ny SG-stabilitet etter tørrhumling; dette fanger mulig hop creep.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_steps(version_id,process_id,process_order,enabled,historical_replay_auto_transition_allowed,name,description,created_at) VALUES ('w3470-standard@3.0','P9',9,1,0,'Bunnfallsdump','Dump bunnfall når kaldkrasjtemperaturen er oppnådd og utfelling er etablert.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_steps(version_id,process_id,process_order,enabled,historical_replay_auto_transition_allowed,name,description,created_at) VALUES ('w3470-standard@3.0','P10',10,1,0,'Kaldkondisjonering ved 2–3 °C','Kondisjoner kaldt etter bunnfallsdump.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_steps(version_id,process_id,process_order,enabled,historical_replay_auto_transition_allowed,name,description,created_at) VALUES ('w3470-standard@3.0','P11',11,0,0,'Reservert prosesstrinn P11','Ledig templateplass.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_steps(version_id,process_id,process_order,enabled,historical_replay_auto_transition_allowed,name,description,created_at) VALUES ('w3470-standard@3.0','P12',12,0,0,'Reservert prosesstrinn P12','Ledig templateplass.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_steps(version_id,process_id,process_order,enabled,historical_replay_auto_transition_allowed,name,description,created_at) VALUES ('w3470-standard@3.0','P13',13,0,0,'Reservert prosesstrinn P13','Ledig templateplass.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_steps(version_id,process_id,process_order,enabled,historical_replay_auto_transition_allowed,name,description,created_at) VALUES ('w3470-standard@3.0','P14',14,0,0,'Reservert prosesstrinn P14','Ledig templateplass.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_steps(version_id,process_id,process_order,enabled,historical_replay_auto_transition_allowed,name,description,created_at) VALUES ('w3470-standard@3.0','P15',15,0,0,'Reservert prosesstrinn P15','Ledig templateplass.','2026-09-27 01:04:57.142');


-- p23r2: process readiness consumes biological phase plus only genuinely operative conditions.
INSERT IGNORE INTO template_process_criteria(version_id,process_id,criterion_id,criterion_order,enabled,metric_id,model_id,role_id,label,exception_allowed,created_at) VALUES
('w3470-standard@3.0','P2','p2-temperature',1,1,'beer_temperature_c','window_median_range','required','Øltemperatur',1,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P3','p3-biological-phase',1,1,'biological_phase_order','threshold','required','Biologisk fase',1,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P3','p3-current-temperature',2,1,'beer_temperature_c','window_median_range','required','Øltemperatur',1,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P4','p4-biological-phase',1,1,'biological_phase_order','threshold','required','Biologisk fase',1,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P4','p4-current-temperature',2,1,'beer_temperature_c','window_median_range','required','Øltemperatur',1,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P5','p5-biological-phase',1,1,'biological_phase_order','threshold','required','Biologisk fase',1,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P5','p5-current-temperature',2,1,'beer_temperature_c','window_median_range','required','Øltemperatur',1,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P6','p6-biological-phase',1,1,'biological_phase_order','threshold','required','Biologisk fase',1,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P6','p6-current-temperature',2,1,'beer_temperature_c','window_median_range','required','Øltemperatur',1,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P7','p7-biological-phase',1,1,'biological_phase_order','threshold','required','Biologisk fase',1,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P7','p7-current-temperature',2,1,'beer_temperature_c','window_median_range','required','Øltemperatur',1,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P8','p8-biological-phase',1,1,'biological_phase_order','threshold','required','Biologisk fase',1,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P8','p8-sg-stability-after-dry-hop',2,1,'tilt_sg','stability_window','required','SG-stabilitet etter tørrhumling',1,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P9','p9-temperature',1,1,'beer_temperature_c','window_median_range','required','Øltemperatur',1,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P10','p10-temperature-range',1,1,'beer_temperature_c','window_median_range','required','Øltemperatur',1,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_criterion_threshold(version_id,process_id,criterion_id,model_id,minimum_value,maximum_value,maximum_age_minutes,created_at) VALUES
('w3470-standard@3.0','P3','p3-biological-phase','threshold',3.0,NULL,NULL,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P4','p4-biological-phase','threshold',4.0,NULL,NULL,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P5','p5-biological-phase','threshold',5.0,NULL,NULL,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P6','p6-biological-phase','threshold',5.0,NULL,NULL,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P7','p7-biological-phase','threshold',6.0,NULL,NULL,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P8','p8-biological-phase','threshold',6.0,NULL,NULL,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_criterion_window_median_range(version_id,process_id,criterion_id,model_id,window_minutes,minimum_samples,maximum_age_minutes,minimum_value,maximum_value,created_at) VALUES
('w3470-standard@3.0','P2','p2-temperature','window_median_range',30,5,NULL,7.4,8.6,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P3','p3-current-temperature','window_median_range',30,5,NULL,7.2,8.8,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P4','p4-current-temperature','window_median_range',30,5,NULL,9.2,10.8,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P5','p5-current-temperature','window_median_range',30,5,NULL,11.2,12.8,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P6','p6-current-temperature','window_median_range',30,5,NULL,13.0,15.0,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P7','p7-current-temperature','window_median_range',30,5,NULL,14.0,16.0,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P9','p9-temperature','window_median_range',30,5,NULL,3.4,4.6,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','P10','p10-temperature-range','window_median_range',30,5,NULL,2.0,3.0,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_criterion_stability_window(version_id,process_id,criterion_id,model_id,window_hours,maximum_range_points,minimum_samples,minimum_span_hours,maximum_age_minutes,since_current_process_start,created_at) VALUES
('w3470-standard@3.0','P8','p8-sg-stability-after-dry-hop','stability_window',48.0,1.5,12,24.0,NULL,1,'2026-09-27 01:04:57.142');

INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P1','beer_temperature',1,'beer_temperature_c','exact','Øltemperatur','Etablere gjæringen og bringe ølet kontrollert mot første gjæringsmål.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P1','pressure',2,'pressure_bar','exact','Tanktrykk','Etablere gjæringen og bringe ølet kontrollert mot første gjæringsmål.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P10','beer_temperature',1,'beer_temperature_c','range','Øltemperatur','Kald kondisjonering og videre klaring.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P10','pressure',2,'pressure_bar','exact','Tanktrykk','Kald kondisjonering og videre klaring.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P2','beer_temperature',1,'beer_temperature_c','exact','Øltemperatur','Beholde lav gjæringstemperatur mens aktiviteten etableres.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P2','pressure',2,'pressure_bar','exact','Tanktrykk','Beholde lav gjæringstemperatur mens aktiviteten etableres.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P3','beer_temperature',1,'beer_temperature_c','exact','Øltemperatur','Støtte videre utgjæring uten å forlate den kalde hovedgjæringen for tidlig.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P3','pressure',2,'pressure_bar','exact','Tanktrykk','Støtte videre utgjæring uten å forlate den kalde hovedgjæringen for tidlig.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P4','beer_temperature',1,'beer_temperature_c','exact','Øltemperatur','Støtte sen hovedgjæring mens gjæren fortsatt har tydelig aktivitet.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P4','pressure',2,'pressure_bar','exact','Tanktrykk','Støtte sen hovedgjæring mens gjæren fortsatt har tydelig aktivitet.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P5','beer_temperature',1,'beer_temperature_c','exact','Øltemperatur','Holde gjæren aktiv gjennom sen utgjæring og forberede metabolsk opprydding.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P5','pressure',2,'pressure_bar','exact','Tanktrykk','Holde gjæren aktiv gjennom sen utgjæring og forberede metabolsk opprydding.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P6','beer_temperature',1,'beer_temperature_c','exact','Øltemperatur','Gi gjæren arbeidsbetingelser for siste utgjæring og metabolsk opprydding.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P6','pressure',2,'pressure_bar','exact','Tanktrykk','Gi gjæren arbeidsbetingelser for siste utgjæring og metabolsk opprydding.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P7','beer_temperature',1,'beer_temperature_c','exact','Øltemperatur','Tilsette tørrhumle mens ølet er nær FG og gjær fortsatt er tilgjengelig for å håndtere eventuell ny fermenterbarhet.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P7','pressure',2,'pressure_bar','exact','Tanktrykk','Tilsette tørrhumle mens ølet er nær FG og gjær fortsatt er tilgjengelig for å håndtere eventuell ny fermenterbarhet.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P8','beer_temperature',1,'beer_temperature_c','exact','Øltemperatur','Stoppe varm prosess og starte kontrollert utfelling, med positivt tanktrykk.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P8','pressure',2,'pressure_bar','exact','Tanktrykk','Stoppe varm prosess og starte kontrollert utfelling, med positivt tanktrykk.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P9','beer_temperature',1,'beer_temperature_c','exact','Øltemperatur','Fjerne sediment etter kaldkrasj.','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_targets(version_id,process_id,target_id,target_order,metric_id,model_id,label,purpose,created_at) VALUES ('w3470-standard@3.0','P9','pressure',2,'pressure_bar','exact','Tanktrykk','Fjerne sediment etter kaldkrasj.','2026-09-27 01:04:57.142');

INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P1','beer_temperature','exact',8.0,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P1','pressure','exact',0.0,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P10','pressure','exact',0.4,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P2','beer_temperature','exact',8.0,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P2','pressure','exact',0.3,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P3','beer_temperature','exact',10.0,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P3','pressure','exact',0.3,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P4','beer_temperature','exact',12.0,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P4','pressure','exact',0.4,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P5','beer_temperature','exact',14.0,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P5','pressure','exact',0.4,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P6','beer_temperature','exact',15.0,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P6','pressure','exact',0.4,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P7','beer_temperature','exact',15.0,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P7','pressure','exact',0.4,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P8','beer_temperature','exact',4.0,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P8','pressure','exact',0.4,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P9','beer_temperature','exact',4.0,'2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_target_exact(version_id,process_id,target_id,model_id,target_value,created_at) VALUES ('w3470-standard@3.0','P9','pressure','exact',0.4,'2026-09-27 01:04:57.142');

INSERT IGNORE INTO template_process_target_range(version_id,process_id,target_id,model_id,minimum_value,maximum_value,created_at) VALUES ('w3470-standard@3.0','P10','beer_temperature','range',2.0,3.0,'2026-09-27 01:04:57.142');

INSERT IGNORE INTO template_process_actions(version_id,process_id,action_id,action_order,action_type_id,label,created_at) VALUES ('w3470-standard@3.0','P1','p1-pitch',1,'operator_action','Pitch gjær','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_actions(version_id,process_id,action_id,action_order,action_type_id,label,created_at) VALUES ('w3470-standard@3.0','P10','p10-temperature',1,'set_target','Sett temperaturområde','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_actions(version_id,process_id,action_id,action_order,action_type_id,label,created_at) VALUES ('w3470-standard@3.0','P3','p3-pressure',2,'set_target','Sett trykkmål','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_actions(version_id,process_id,action_id,action_order,action_type_id,label,created_at) VALUES ('w3470-standard@3.0','P3','p3-temperature',1,'set_target','Sett temperaturmål','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_actions(version_id,process_id,action_id,action_order,action_type_id,label,created_at) VALUES ('w3470-standard@3.0','P4','p4-pressure',2,'set_target','Sett trykkmål','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_actions(version_id,process_id,action_id,action_order,action_type_id,label,created_at) VALUES ('w3470-standard@3.0','P4','p4-temperature',1,'set_target','Sett temperaturmål','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_actions(version_id,process_id,action_id,action_order,action_type_id,label,created_at) VALUES ('w3470-standard@3.0','P5','p5-pressure',2,'set_target','Sett trykkmål','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_actions(version_id,process_id,action_id,action_order,action_type_id,label,created_at) VALUES ('w3470-standard@3.0','P5','p5-temperature',1,'set_target','Sett temperaturmål','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_actions(version_id,process_id,action_id,action_order,action_type_id,label,created_at) VALUES ('w3470-standard@3.0','P6','p6-pressure',2,'set_target','Sett trykkmål','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_actions(version_id,process_id,action_id,action_order,action_type_id,label,created_at) VALUES ('w3470-standard@3.0','P6','p6-temperature',1,'set_target','Sett temperaturmål','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_actions(version_id,process_id,action_id,action_order,action_type_id,label,created_at) VALUES ('w3470-standard@3.0','P7','p7-dry-hop',1,'operator_action','Tilsett tørrhumle','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_actions(version_id,process_id,action_id,action_order,action_type_id,label,created_at) VALUES ('w3470-standard@3.0','P7','p7-pressure',3,'set_target','Sett trykkmål','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_actions(version_id,process_id,action_id,action_order,action_type_id,label,created_at) VALUES ('w3470-standard@3.0','P7','p7-temperature',2,'set_target','Sett temperaturmål','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_actions(version_id,process_id,action_id,action_order,action_type_id,label,created_at) VALUES ('w3470-standard@3.0','P8','p8-pressure',2,'set_target','Sett trykkmål','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_actions(version_id,process_id,action_id,action_order,action_type_id,label,created_at) VALUES ('w3470-standard@3.0','P8','p8-temperature',1,'set_target','Sett temperaturmål','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_actions(version_id,process_id,action_id,action_order,action_type_id,label,created_at) VALUES ('w3470-standard@3.0','P9','p9-sediment-dump',1,'operator_action','Dump bunnfall','2026-09-27 01:04:57.142');

INSERT IGNORE INTO template_process_action_set_target(version_id,process_id,action_id,action_type_id,target_id,created_at) VALUES ('w3470-standard@3.0','P10','p10-temperature','set_target','beer_temperature','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_action_set_target(version_id,process_id,action_id,action_type_id,target_id,created_at) VALUES ('w3470-standard@3.0','P3','p3-pressure','set_target','pressure','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_action_set_target(version_id,process_id,action_id,action_type_id,target_id,created_at) VALUES ('w3470-standard@3.0','P3','p3-temperature','set_target','beer_temperature','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_action_set_target(version_id,process_id,action_id,action_type_id,target_id,created_at) VALUES ('w3470-standard@3.0','P4','p4-pressure','set_target','pressure','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_action_set_target(version_id,process_id,action_id,action_type_id,target_id,created_at) VALUES ('w3470-standard@3.0','P4','p4-temperature','set_target','beer_temperature','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_action_set_target(version_id,process_id,action_id,action_type_id,target_id,created_at) VALUES ('w3470-standard@3.0','P5','p5-pressure','set_target','pressure','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_action_set_target(version_id,process_id,action_id,action_type_id,target_id,created_at) VALUES ('w3470-standard@3.0','P5','p5-temperature','set_target','beer_temperature','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_action_set_target(version_id,process_id,action_id,action_type_id,target_id,created_at) VALUES ('w3470-standard@3.0','P6','p6-pressure','set_target','pressure','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_action_set_target(version_id,process_id,action_id,action_type_id,target_id,created_at) VALUES ('w3470-standard@3.0','P6','p6-temperature','set_target','beer_temperature','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_action_set_target(version_id,process_id,action_id,action_type_id,target_id,created_at) VALUES ('w3470-standard@3.0','P7','p7-pressure','set_target','pressure','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_action_set_target(version_id,process_id,action_id,action_type_id,target_id,created_at) VALUES ('w3470-standard@3.0','P7','p7-temperature','set_target','beer_temperature','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_action_set_target(version_id,process_id,action_id,action_type_id,target_id,created_at) VALUES ('w3470-standard@3.0','P8','p8-pressure','set_target','pressure','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_action_set_target(version_id,process_id,action_id,action_type_id,target_id,created_at) VALUES ('w3470-standard@3.0','P8','p8-temperature','set_target','beer_temperature','2026-09-27 01:04:57.142');

INSERT IGNORE INTO template_process_action_operator(version_id,process_id,action_id,action_type_id,operation_id,created_at) VALUES ('w3470-standard@3.0','P1','p1-pitch','operator_action','pitch','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_action_operator(version_id,process_id,action_id,action_type_id,operation_id,created_at) VALUES ('w3470-standard@3.0','P7','p7-dry-hop','operator_action','dry_hop','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_process_action_operator(version_id,process_id,action_id,action_type_id,operation_id,created_at) VALUES ('w3470-standard@3.0','P9','p9-sediment-dump','operator_action','sediment_dump','2026-09-27 01:04:57.142');







-- p21r13: explicit source-freshness criteria; freshness is not hidden inside other metrics.




-- p23r2 operator analysis: one established fermentation percentage plus rate and stability.
INSERT IGNORE INTO template_analysis_graphs(version_id,graph_id,sort_order,label,description,unit,display_decimals,y_axis_min,y_axis_max,y_axis_tick_step,y_axis_include_zero,x_axis_mode,enabled,show_biological_bands,show_process_markers,show_criterion_markers,gap_policy,created_at) VALUES
('w3470-standard@3.0','attenuation',1,'Tilsynelatende utgjæringsgrad','Viser tilsynelatende utgjæringsgrad fra faktisk OG og godkjent rå Tilt-SG, samt egne kontrollpunkter fra korrigert manuell SG. Kildene har hver sin faktiske måletid; ingen offsetestimat eller automatisk kildebytte.','%',1,NULL,NULL,NULL,0,'relative_day_date',1,1,1,1,'measurement_gaps','2026-09-27 01:04:57.142'),
('w3470-standard@3.0','sg-rate',2,'SG-rate','Viser målt SG-forskjell mellom vinduets endepunkter delt på faktisk tid, i SG-poeng per døgn. Høy positiv verdi betyr raskt SG-fall; verdier nær null betyr liten endring, mens negativ verdi betyr stigende SG-trend og bør vurderes mot målekvalitet og prosesshendelser.','SG-poeng/d',2,NULL,NULL,NULL,1,'relative_day_date',1,1,1,1,'measurement_gaps','2026-09-27 01:04:57.142'),
('w3470-standard@3.0','sg-stability',3,'SG-stabilitet','Viser spennet mellom høyeste og laveste godkjente SG i stabilitetsvinduet. Lav verdi betyr at SG er stabil; B6 bruker samme type stabilitetsregel for å avgjøre om forventet utgjæring er nådd og stabil.','SG-poeng',2,NULL,NULL,NULL,1,'relative_day_date',1,1,1,1,'measurement_gaps','2026-09-27 01:04:57.142');
INSERT IGNORE INTO template_analysis_graph_series(version_id,graph_id,series_id,sort_order,label,source_kind,metric_id,owner_id,criterion_id,minimum_samples,minimum_coverage_fraction,warmup_minutes,valid_minimum_value,valid_maximum_value,provisional_allowed,provisional_minimum_samples,provisional_minimum_span_minutes,band_model,band_description,standard_color,provisional_color,standard_dasharray,provisional_dasharray,band_opacity,created_at) VALUES
('w3470-standard@3.0','attenuation','attenuation',1,'Utgjæringsgrad · rå Tilt','metric','apparent_attenuation_percent',NULL,NULL,1,0,0,-10,120,0,3,10,'none','Faktisk OG og rå Tilt-SG, uten kalibreringsestimat eller bånd.','#039be5','#ff8f00','','6 4',0.24,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','sg-rate','sg-rate',1,'SG-rate','metric','sg_rate_points_per_day',NULL,NULL,12,0.75,1080,-20,50,0,3,20,'none','Målte endepunkter og faktisk tid; ingen regresjon, foreløpige verdier eller bånd.','#039be5','#ff8f00','','6 4',0.24,'2026-09-27 01:04:57.142'),
('w3470-standard@3.0','sg-stability','stability-24h',1,'24 timer','metric','sg_stability_24h_points',NULL,NULL,12,0.75,1080,0,100,0,3,10,'none','Ingen bånd: verdien er selv maks–min-spennet.','#039be5','#ff8f00','','6 4',0.24,UTC_TIMESTAMP(3)),
('w3470-standard@3.0','sg-stability','stability-48h',2,'48 timer','metric','sg_stability_48h_points',NULL,NULL,12,0.75,2160,0,100,0,3,10,'none','Ingen bånd: verdien er selv maks–min-spennet.','#6a1b9a','#ff8f00','','6 4',0.24,UTC_TIMESTAMP(3));


-- p24r1 explicit operator defaults: every model-permitted criterion parameter
-- is correctable; templates may subsequently remove individual permissions.
INSERT IGNORE INTO template_biological_correctable_parameters(version_id,phase_id,criterion_id,model_id,parameter_id,created_at)
SELECT c.version_id,c.phase_id,c.criterion_id,c.model_id,p.parameter_id,UTC_TIMESTAMP(3)
FROM template_biological_criteria c JOIN criterion_model_parameters p ON p.model_id=c.model_id
WHERE c.version_id='w3470-standard@3.0' AND (p.parameter_id<>'maximum_age_minutes' OR EXISTS(SELECT 1 FROM template_metric_runtime_rules r WHERE r.version_id=c.version_id AND r.metric_id=c.metric_id AND r.freshness_mode<>'not_applicable'));
INSERT IGNORE INTO template_process_correctable_parameters(version_id,process_id,criterion_id,model_id,parameter_id,created_at)
SELECT c.version_id,c.process_id,c.criterion_id,c.model_id,p.parameter_id,UTC_TIMESTAMP(3)
FROM template_process_criteria c JOIN criterion_model_parameters p ON p.model_id=c.model_id
WHERE c.version_id='w3470-standard@3.0' AND (p.parameter_id<>'maximum_age_minutes' OR EXISTS(SELECT 1 FROM template_metric_runtime_rules r WHERE r.version_id=c.version_id AND r.metric_id=c.metric_id AND r.freshness_mode<>'not_applicable'));
UPDATE template_process_criteria SET exception_allowed=1 WHERE version_id='w3470-standard@3.0';

INSERT INTO template_overview_graph_policy(version_id,graph_id,band_model,band_description,band_opacity,created_at) VALUES
('w3470-standard@3.0','sg','sample_range','Bånd viser SG-min–maks i hvert godkjente femminuttersaggregat.',0.24,UTC_TIMESTAMP(3)),
('w3470-standard@3.0','temperature','sample_range','Bånd viser temperatur-min–maks i hvert godkjente femminuttersaggregat.',0.24,UTC_TIMESTAMP(3)),
('w3470-standard@3.0','pressure','sample_range','Bånd viser trykk-min–maks der målekilden faktisk leverer spredning.',0.24,UTC_TIMESTAMP(3));

INSERT INTO template_biology_calculation_parameter_values(version_id,calculation_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) VALUES ('w3470-standard@3.0','tilt_baseline','pitch_baseline_median_v1','window_minutes','real',30.0,NULL,NULL,NULL,UTC_TIMESTAMP(3));
INSERT INTO template_biology_calculation_parameter_values(version_id,calculation_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) VALUES ('w3470-standard@3.0','tilt_baseline','pitch_baseline_median_v1','maximum_start_delay_minutes','real',10.0,NULL,NULL,NULL,UTC_TIMESTAMP(3));
INSERT INTO template_biology_calculation_parameter_values(version_id,calculation_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) VALUES ('w3470-standard@3.0','tilt_baseline','pitch_baseline_median_v1','minimum_span_minutes','real',10.0,NULL,NULL,NULL,UTC_TIMESTAMP(3));
INSERT INTO template_biology_calculation_parameter_values(version_id,calculation_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) VALUES ('w3470-standard@3.0','tilt_baseline','pitch_baseline_median_v1','maximum_range_points','real',1.0,NULL,NULL,NULL,UTC_TIMESTAMP(3));
INSERT INTO template_biology_calculation_parameter_values(version_id,calculation_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) VALUES ('w3470-standard@3.0','tilt_baseline','pitch_baseline_median_v1','maximum_gap_minutes','real',10.0,NULL,NULL,NULL,UTC_TIMESTAMP(3));
INSERT INTO template_biology_calculation_parameter_values(version_id,calculation_id,model_id,parameter_id,data_type,real_value,integer_value,boolean_value,text_value,created_at) VALUES ('w3470-standard@3.0','sg_rate','endpoint_rate_v1','minimum_span_minutes','real',1080.0,NULL,NULL,NULL,UTC_TIMESTAMP(3));

-- p24r6 frozen graph/source policy. No provisional values or estimation bands.
UPDATE template_analysis_graphs SET description='Faktisk OG sammenholdes med rå Tilt-SG og korrigerte manuelle SG-kontroller. Seriene vises separat uten pitchoffset eller utfylling av manglende data.' WHERE version_id='w3470-standard@3.0' AND graph_id='attenuation';
UPDATE template_analysis_graphs SET y_axis_min=0,y_axis_include_zero=1,description='SG-fall mellom første og siste godkjente måling i et sammenhengende 24-timersvindu, delt på faktisk tid. Minst 18 timer. Negativ rate betyr SG-økning og beholdes numerisk.' WHERE version_id='w3470-standard@3.0' AND graph_id='sg-rate';
UPDATE template_analysis_graph_series SET provisional_allowed=0,band_model='none',band_description='Beregnet fra faktiske målinger. Ingen estimering eller følsomhetsbånd.',minimum_samples=12,minimum_coverage_fraction=0.75 WHERE version_id='w3470-standard@3.0';
UPDATE template_analysis_graph_series SET label='Rå Tilt',minimum_samples=1,minimum_coverage_fraction=0,warmup_minutes=0 WHERE version_id='w3470-standard@3.0' AND graph_id='attenuation';
UPDATE template_analysis_graph_series SET warmup_minutes=1080 WHERE version_id='w3470-standard@3.0' AND graph_id='sg-rate';
INSERT INTO template_analysis_graph_series(version_id,graph_id,series_id,sort_order,label,source_kind,metric_id,minimum_samples,minimum_coverage_fraction,warmup_minutes,valid_minimum_value,valid_maximum_value,provisional_allowed,provisional_minimum_samples,provisional_minimum_span_minutes,band_model,band_description,standard_color,provisional_color,standard_dasharray,provisional_dasharray,band_opacity,render_mode,created_at)
VALUES ('w3470-standard@3.0','attenuation','manual-attenuation',2,'Manuell kontroll','metric','manual_apparent_attenuation_percent',1,0,0,-10,120,0,2,1,'none','Punkter fra korrigert manuell SG og faktisk OG. Ingen mellomliggende verdier.','#ef6c00','#ef6c00','','',0.24,'points',UTC_TIMESTAMP(3));
UPDATE template_biological_criteria SET label='Utgjæringsgrad · rå Tilt' WHERE version_id='w3470-standard@3.0' AND metric_id='apparent_attenuation_percent';
