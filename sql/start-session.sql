SET @ga_session_id=?;
SET @ga_is_demo=?;
SET @ga_template_version=?;
SET @ga_source_profile=?;
SET @ga_batch_name=?;
SET @ga_pitched_at=?;
SET @ga_created_at=?;
SET @ga_og=?;
SET @ga_volume_l=?;
SET @ga_pitch_mode=?;
SET @ga_pitch_temperature_c=?;
SET @ga_yeast_amount_g=?;
SET @ga_slurry_volume_ml=?;
SET @ga_slurry_source_batch=?;
SET @ga_slurry_generation=?;
SET @ga_oxygenation_note=?;
SET @ga_expected_attenuation_min=?;
SET @ga_expected_attenuation_max=?;
SET @ga_expected_fg_min=ROUND(1 + (@ga_og - 1) * (1 - @ga_expected_attenuation_max / 100),5);
SET @ga_expected_fg_max=ROUND(1 + (@ga_og - 1) * (1 - @ga_expected_attenuation_min / 100),5);
SET @ga_operation_id=?;
SET @ga_measurement_method=?;
SET @ga_measured_sg=?;
SET @ga_sample_temperature_c=?;
SET @ga_calibration_temperature_c=?;
SET @ga_corrected_sg=?;
SET @ga_manual_temperature_c=?;
SET @ga_pressure_bar=?;
SET @ga_cooler_setpoint_c=?;
SET @ga_cooler_calibration_offset_c=?;
SET @ga_airlock_activity=?;
SET @ga_acetaldehyde_level=?;
SET @ga_diacetyl_level=?;
SET @ga_wort_like_level=?;
SET @ga_sulfur_so2_level=?;
SET @ga_sulfur_h2s_level=?;
SET @ga_clarity_level=?;
SET @ga_settling_yeast_level=?;
SET @ga_settling_minutes=?;
SET @ga_user_conclusion=?;
SET @ga_measurement_note=?;
SET @ga_corrected_sg_model=?;
SET @ga_abv_now=?;
SET @ga_finished_abv=?;
SET @ga_finished_abv_model=?;

SET @ga_history_end=?;
CALL ga_start_session_tx();

SELECT s.*,sts.template_version_id,tv.template_id,tv.name AS template_name,tv.version_label
FROM v_active_session_summary s
JOIN session_template_snapshots sts ON sts.session_id=s.session_id
LEFT JOIN template_versions tv ON tv.version_id=sts.template_version_id
WHERE s.session_id=@ga_session_id;
