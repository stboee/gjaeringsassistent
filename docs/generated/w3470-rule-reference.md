# W-34/70 – generert regelreferanse

> Generert av `tools/build_docs.py` fra SQL-seedene. SQL/installert MariaDB er autoritet; denne filen er inspeksjonsmateriale.

## Prosesstrinn og historisk replay

| P | Aktiv | Historisk auto | Navn |
|---|---:|---:|---|
| P1 | 1 | 1 | Klargjøring, pitch og temperaturstabilisering |
| P2 | 1 | 1 | Kald hovedgjæring |
| P3 | 1 | 0 | Første temperaturøkning mot 10 °C |
| P4 | 1 | 0 | Videre temperaturøkning mot 12 °C |
| P5 | 1 | 0 | Varm sluttfase mot 14 °C |
| P6 | 1 | 0 | Modning og metabolsk opprydding |
| P7 | 1 | 0 | Tørrhumling |
| P8 | 1 | 0 | Kaldkrasj mot 4 °C |
| P9 | 1 | 0 | Bunnfallsdump |
| P10 | 1 | 0 | Kaldkondisjonering ved 2–3 °C |
| P11 | 0 | 0 | Reservert prosesstrinn P11 |
| P12 | 0 | 0 | Reservert prosesstrinn P12 |
| P13 | 0 | 0 | Reservert prosesstrinn P13 |
| P14 | 0 | 0 | Reservert prosesstrinn P14 |
| P15 | 0 | 0 | Reservert prosesstrinn P15 |

## Biologiske kriterier

| B | Kriterium | Metric | Modell | Rolle | Detalj |
|---|---|---|---|---|---|
| B2 | SG-fall siden start | `relative_sg_drop_points` | `threshold` | required | `[{'version_id': 'w3470-standard@3.0', 'phase_id': 'B2', 'criterion_id': 'b2-relative-drop', 'model_id': 'threshold', 'minimum_value': 1.5, 'maximum_value': None, 'maximum_age_minutes': None, 'created_at': '2026-09-27 01:04:57.142'}]` |
| B3 | SG-rate | `sg_rate_points_per_day` | `threshold` | required | `[{'version_id': 'w3470-standard@3.0', 'phase_id': 'B3', 'criterion_id': 'b3-sg-rate', 'model_id': 'threshold', 'minimum_value': 1.5, 'maximum_value': None, 'maximum_age_minutes': None, 'created_at': '2026-09-27 01:04:57.142'}]` |
| B4 | Utgjæringsgrad | `apparent_attenuation_percent` | `threshold` | required | `[{'version_id': 'w3470-standard@3.0', 'phase_id': 'B4', 'criterion_id': 'b4-attenuation', 'model_id': 'threshold', 'minimum_value': 60.0, 'maximum_value': None, 'maximum_age_minutes': None, 'created_at': '2026-09-27 01:04:57.142'}]` |
| B4 | Avtagende SG-rate | `sg_rate_points_per_day` | `threshold` | required | `[{'version_id': 'w3470-standard@3.0', 'phase_id': 'B4', 'criterion_id': 'b4-sg-rate', 'model_id': 'threshold', 'minimum_value': None, 'maximum_value': 1.5, 'maximum_age_minutes': None, 'created_at': '2026-09-27 01:04:57.142'}]` |
| B5 | Utgjæringsgrad | `apparent_attenuation_percent` | `threshold` | required | `[{'version_id': 'w3470-standard@3.0', 'phase_id': 'B5', 'criterion_id': 'b5-attenuation', 'model_id': 'threshold', 'minimum_value': 75.0, 'maximum_value': None, 'maximum_age_minutes': None, 'created_at': '2026-09-27 01:04:57.142'}]` |
| B6 | Forventet utgjæring nådd | `apparent_attenuation_percent` | `threshold` | required | `[{'version_id': 'w3470-standard@3.0', 'phase_id': 'B6', 'criterion_id': 'b6-attenuation', 'model_id': 'threshold', 'minimum_value': 80.0, 'maximum_value': None, 'maximum_age_minutes': None, 'created_at': '2026-09-27 01:04:57.142'}]` |
| B6 | SG-stabilitet | `tilt_sg` | `stability_window` | required | `[{'version_id': 'w3470-standard@3.0', 'phase_id': 'B6', 'criterion_id': 'b6-sg-stability', 'model_id': 'stability_window', 'window_hours': 24.0, 'maximum_range_points': 1.0, 'minimum_samples': 12, 'minimum_span_hours': 18.0, 'maximum_age_minutes': None, 'since_current_process_start': 0, 'created_at': '2026-09-27 01:04:57.142'}]` |

## Prosesskriterier

| P | Kriterium | Metric | Modell | Rolle | Detalj |
|---|---|---|---|---|---|
| P2 | Øltemperatur | `beer_temperature_c` | `window_median_range` | required | `[{'table': 'template_process_criterion_window_median_range', 'version_id': 'w3470-standard@3.0', 'process_id': 'P2', 'criterion_id': 'p2-temperature', 'model_id': 'window_median_range', 'window_minutes': 30, 'minimum_samples': 5, 'maximum_age_minutes': None, 'minimum_value': 7.4, 'maximum_value': 8.6, 'created_at': '2026-09-27 01:04:57.142'}]` |
| P3 | Biologisk fase | `biological_phase_order` | `threshold` | required | `[{'table': 'template_process_criterion_threshold', 'version_id': 'w3470-standard@3.0', 'process_id': 'P3', 'criterion_id': 'p3-biological-phase', 'model_id': 'threshold', 'minimum_value': 3.0, 'maximum_value': None, 'maximum_age_minutes': None, 'created_at': '2026-09-27 01:04:57.142'}]` |
| P3 | Øltemperatur | `beer_temperature_c` | `window_median_range` | required | `[{'table': 'template_process_criterion_window_median_range', 'version_id': 'w3470-standard@3.0', 'process_id': 'P3', 'criterion_id': 'p3-current-temperature', 'model_id': 'window_median_range', 'window_minutes': 30, 'minimum_samples': 5, 'maximum_age_minutes': None, 'minimum_value': 7.2, 'maximum_value': 8.8, 'created_at': '2026-09-27 01:04:57.142'}]` |
| P4 | Biologisk fase | `biological_phase_order` | `threshold` | required | `[{'table': 'template_process_criterion_threshold', 'version_id': 'w3470-standard@3.0', 'process_id': 'P4', 'criterion_id': 'p4-biological-phase', 'model_id': 'threshold', 'minimum_value': 4.0, 'maximum_value': None, 'maximum_age_minutes': None, 'created_at': '2026-09-27 01:04:57.142'}]` |
| P4 | Øltemperatur | `beer_temperature_c` | `window_median_range` | required | `[{'table': 'template_process_criterion_window_median_range', 'version_id': 'w3470-standard@3.0', 'process_id': 'P4', 'criterion_id': 'p4-current-temperature', 'model_id': 'window_median_range', 'window_minutes': 30, 'minimum_samples': 5, 'maximum_age_minutes': None, 'minimum_value': 9.2, 'maximum_value': 10.8, 'created_at': '2026-09-27 01:04:57.142'}]` |
| P5 | Biologisk fase | `biological_phase_order` | `threshold` | required | `[{'table': 'template_process_criterion_threshold', 'version_id': 'w3470-standard@3.0', 'process_id': 'P5', 'criterion_id': 'p5-biological-phase', 'model_id': 'threshold', 'minimum_value': 5.0, 'maximum_value': None, 'maximum_age_minutes': None, 'created_at': '2026-09-27 01:04:57.142'}]` |
| P5 | Øltemperatur | `beer_temperature_c` | `window_median_range` | required | `[{'table': 'template_process_criterion_window_median_range', 'version_id': 'w3470-standard@3.0', 'process_id': 'P5', 'criterion_id': 'p5-current-temperature', 'model_id': 'window_median_range', 'window_minutes': 30, 'minimum_samples': 5, 'maximum_age_minutes': None, 'minimum_value': 11.2, 'maximum_value': 12.8, 'created_at': '2026-09-27 01:04:57.142'}]` |
| P6 | Biologisk fase | `biological_phase_order` | `threshold` | required | `[{'table': 'template_process_criterion_threshold', 'version_id': 'w3470-standard@3.0', 'process_id': 'P6', 'criterion_id': 'p6-biological-phase', 'model_id': 'threshold', 'minimum_value': 5.0, 'maximum_value': None, 'maximum_age_minutes': None, 'created_at': '2026-09-27 01:04:57.142'}]` |
| P6 | Øltemperatur | `beer_temperature_c` | `window_median_range` | required | `[{'table': 'template_process_criterion_window_median_range', 'version_id': 'w3470-standard@3.0', 'process_id': 'P6', 'criterion_id': 'p6-current-temperature', 'model_id': 'window_median_range', 'window_minutes': 30, 'minimum_samples': 5, 'maximum_age_minutes': None, 'minimum_value': 13.0, 'maximum_value': 15.0, 'created_at': '2026-09-27 01:04:57.142'}]` |
| P7 | Biologisk fase | `biological_phase_order` | `threshold` | required | `[{'table': 'template_process_criterion_threshold', 'version_id': 'w3470-standard@3.0', 'process_id': 'P7', 'criterion_id': 'p7-biological-phase', 'model_id': 'threshold', 'minimum_value': 6.0, 'maximum_value': None, 'maximum_age_minutes': None, 'created_at': '2026-09-27 01:04:57.142'}]` |
| P7 | Øltemperatur | `beer_temperature_c` | `window_median_range` | required | `[{'table': 'template_process_criterion_window_median_range', 'version_id': 'w3470-standard@3.0', 'process_id': 'P7', 'criterion_id': 'p7-current-temperature', 'model_id': 'window_median_range', 'window_minutes': 30, 'minimum_samples': 5, 'maximum_age_minutes': None, 'minimum_value': 14.0, 'maximum_value': 16.0, 'created_at': '2026-09-27 01:04:57.142'}]` |
| P8 | Biologisk fase | `biological_phase_order` | `threshold` | required | `[{'table': 'template_process_criterion_threshold', 'version_id': 'w3470-standard@3.0', 'process_id': 'P8', 'criterion_id': 'p8-biological-phase', 'model_id': 'threshold', 'minimum_value': 6.0, 'maximum_value': None, 'maximum_age_minutes': None, 'created_at': '2026-09-27 01:04:57.142'}]` |
| P8 | SG-stabilitet etter tørrhumling | `tilt_sg` | `stability_window` | required | `[{'table': 'template_process_criterion_stability_window', 'version_id': 'w3470-standard@3.0', 'process_id': 'P8', 'criterion_id': 'p8-sg-stability-after-dry-hop', 'model_id': 'stability_window', 'window_hours': 48.0, 'maximum_range_points': 1.5, 'minimum_samples': 12, 'minimum_span_hours': 24.0, 'maximum_age_minutes': None, 'since_current_process_start': 1, 'created_at': '2026-09-27 01:04:57.142'}]` |
| P9 | Øltemperatur | `beer_temperature_c` | `window_median_range` | required | `[{'table': 'template_process_criterion_window_median_range', 'version_id': 'w3470-standard@3.0', 'process_id': 'P9', 'criterion_id': 'p9-temperature', 'model_id': 'window_median_range', 'window_minutes': 30, 'minimum_samples': 5, 'maximum_age_minutes': None, 'minimum_value': 3.4, 'maximum_value': 4.6, 'created_at': '2026-09-27 01:04:57.142'}]` |
| P10 | Øltemperatur | `beer_temperature_c` | `window_median_range` | required | `[{'table': 'template_process_criterion_window_median_range', 'version_id': 'w3470-standard@3.0', 'process_id': 'P10', 'criterion_id': 'p10-temperature-range', 'model_id': 'window_median_range', 'window_minutes': 30, 'minimum_samples': 5, 'maximum_age_minutes': None, 'minimum_value': 2.0, 'maximum_value': 3.0, 'created_at': '2026-09-27 01:04:57.142'}]` |

## Analysegrafer

| Graf | Label | Forklaring | Enhet | Aktiv |
|---|---|---|---|---:|
| `attenuation` | Tilsynelatende utgjæringsgrad | Viser tilsynelatende utgjæringsgrad fra faktisk OG og godkjent rå Tilt-SG, samt egne kontrollpunkter fra korrigert manuell SG. Kildene har hver sin faktiske måletid; ingen offsetestimat eller automatisk kildebytte. | % | 1 |
| `sg-rate` | SG-rate | Viser målt SG-forskjell mellom vinduets endepunkter delt på faktisk tid, i SG-poeng per døgn. Høy positiv verdi betyr raskt SG-fall; verdier nær null betyr liten endring, mens negativ verdi betyr stigende SG-trend og bør vurderes mot målekvalitet og prosesshendelser. | SG-poeng/d | 1 |
| `sg-stability` | SG-stabilitet | Viser spennet mellom høyeste og laveste godkjente SG i stabilitetsvinduet. Lav verdi betyr at SG er stabil; B6 bruker samme type stabilitetsregel for å avgjøre om forventet utgjæring er nådd og stabil. | SG-poeng | 1 |

## Målekildevalidering

```json
{
  "measurement_source_profiles": [
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "name": "Tilt Pro Blue · Home Assistant",
      "source_type": "home_assistant",
      "sg_entity_id": "sensor.bryggeri_tilt_pro_blue_bryggeri_tilt_pro_blue_sg",
      "temperature_entity_id": "sensor.bryggeri_tilt_pro_blue_bryggeri_tilt_pro_blue_temperatur",
      "heartbeat_entity_id": "sensor.bryggeri_tilt_pro_blue_bryggeri_tilt_pro_blue_sist_oppdatert",
      "rssi_entity_id": "sensor.bryggeri_tilt_pro_blue_bryggeri_tilt_pro_blue_rssi",
      "poll_interval_seconds": 300,
      "gap_threshold_seconds": 300,
      "fresh_age_minutes": 15,
      "stale_age_minutes": 60,
      "status": "active",
      "description": "Primær livekilde. Entity-ID-er er DB-konfigurasjon og skal ikke hardkodes i Node-RED-funksjoner.",
      "created_at": "UTC_TIMESTAMP(3)",
      "updated_at": "UTC_TIMESTAMP(3)"
    }
  ],
  "measurement_source_validation_rules": [
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "sg-range",
      "signal_id": "sg",
      "rule_order": 1,
      "model_id": "hard_range_v1",
      "enabled": 1,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "sg-mad",
      "signal_id": "sg",
      "rule_order": 2,
      "model_id": "robust_mad_v1",
      "enabled": 1,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "sg-jump",
      "signal_id": "sg",
      "rule_order": 3,
      "model_id": "max_jump_v1",
      "enabled": 1,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "sg-minimum",
      "signal_id": "sg",
      "rule_order": 4,
      "model_id": "minimum_acceptance_v1",
      "enabled": 1,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "temperature-range",
      "signal_id": "temperature",
      "rule_order": 1,
      "model_id": "hard_range_v1",
      "enabled": 1,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "temperature-mad",
      "signal_id": "temperature",
      "rule_order": 2,
      "model_id": "robust_mad_v1",
      "enabled": 1,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "temperature-jump",
      "signal_id": "temperature",
      "rule_order": 3,
      "model_id": "max_jump_v1",
      "enabled": 1,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "temperature-minimum",
      "signal_id": "temperature",
      "rule_order": 4,
      "model_id": "minimum_acceptance_v1",
      "enabled": 1,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "rssi-range",
      "signal_id": "rssi",
      "rule_order": 1,
      "model_id": "hard_range_v1",
      "enabled": 1,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "rssi-mad",
      "signal_id": "rssi",
      "rule_order": 2,
      "model_id": "robust_mad_v1",
      "enabled": 1,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "rssi-minimum",
      "signal_id": "rssi",
      "rule_order": 3,
      "model_id": "minimum_acceptance_v1",
      "enabled": 1,
      "created_at": "UTC_TIMESTAMP(3)"
    }
  ],
  "measurement_source_validation_rule_parameter_values": [
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "sg-range",
      "parameter_id": "minimum_value",
      "data_type": "real",
      "real_value": 0.98,
      "integer_value": null,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "sg-range",
      "parameter_id": "maximum_value",
      "data_type": "real",
      "real_value": 1.2,
      "integer_value": null,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "sg-mad",
      "parameter_id": "mad_multiplier",
      "data_type": "real",
      "real_value": 6.0,
      "integer_value": null,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "sg-jump",
      "parameter_id": "maximum_delta",
      "data_type": "real",
      "real_value": 0.0008,
      "integer_value": null,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "sg-minimum",
      "parameter_id": "minimum_samples",
      "data_type": "integer",
      "real_value": null,
      "integer_value": 3,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "sg-minimum",
      "parameter_id": "minimum_fraction",
      "data_type": "real",
      "real_value": 0.5,
      "integer_value": null,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "temperature-range",
      "parameter_id": "minimum_value",
      "data_type": "real",
      "real_value": -5,
      "integer_value": null,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "temperature-range",
      "parameter_id": "maximum_value",
      "data_type": "real",
      "real_value": 40,
      "integer_value": null,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "temperature-mad",
      "parameter_id": "mad_multiplier",
      "data_type": "real",
      "real_value": 6.0,
      "integer_value": null,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "temperature-jump",
      "parameter_id": "maximum_delta",
      "data_type": "real",
      "real_value": 5.0,
      "integer_value": null,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "temperature-minimum",
      "parameter_id": "minimum_samples",
      "data_type": "integer",
      "real_value": null,
      "integer_value": 3,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "temperature-minimum",
      "parameter_id": "minimum_fraction",
      "data_type": "real",
      "real_value": 0.5,
      "integer_value": null,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "rssi-range",
      "parameter_id": "minimum_value",
      "data_type": "real",
      "real_value": -130,
      "integer_value": null,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "rssi-range",
      "parameter_id": "maximum_value",
      "data_type": "real",
      "real_value": -1,
      "integer_value": null,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "rssi-mad",
      "parameter_id": "mad_multiplier",
      "data_type": "real",
      "real_value": 8.0,
      "integer_value": null,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "rssi-minimum",
      "parameter_id": "minimum_samples",
      "data_type": "integer",
      "real_value": null,
      "integer_value": 1,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "rssi-minimum",
      "parameter_id": "minimum_fraction",
      "data_type": "real",
      "real_value": 0.2,
      "integer_value": null,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "sg-mad",
      "parameter_id": "noise_floor",
      "data_type": "real",
      "real_value": 0.0001,
      "integer_value": null,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "temperature-mad",
      "parameter_id": "noise_floor",
      "data_type": "real",
      "real_value": 0.05,
      "integer_value": null,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    },
    {
      "source_profile_id": "tilt-pro-blue-ha",
      "rule_id": "rssi-mad",
      "parameter_id": "noise_floor",
      "data_type": "real",
      "real_value": 1,
      "integer_value": null,
      "boolean_value": null,
      "text_value": null,
      "created_at": "UTC_TIMESTAMP(3)"
    }
  ]
}
```
