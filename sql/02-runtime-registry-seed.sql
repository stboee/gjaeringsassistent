-- Gjæringsassistent – runtime calculation-model registry additions
-- These identifiers are concrete calculation models used by p18r5 measurement_set.js.
-- They are registered relationally so observation_round_revisions can use FKs.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

INSERT IGNORE INTO calculation_models(model_id,label,description,created_at) VALUES
('hydrometer-temperature-correction-sg-v1',
 'Hydrometer temperaturkorreksjon SG v1',
 'Temperaturkorrigerer en hydrometermålt SG med prøvetemperatur og kalibreringstemperatur.',
 UTC_TIMESTAMP(3)),
('refractometer-sg-before-fermentation-v1',
 'Refraktometer SG før gjæring v1',
 'Bruker registrert SG direkte for refraktometermåling før alkohol er dannet.',
 UTC_TIMESTAMP(3)),
('refractometer-alcohol-correction-sg-to-sg-v2',
 'Refraktometer alkoholkorrigering SG til SG v2',
 'Korrigerer refraktometermålt SG under gjæring med faktisk OG.',
 UTC_TIMESTAMP(3)),
('cutaia-apparent-abv-v1',
 'Cutaia apparent ABV v1',
 'Beregner estimert alkoholprosent fra faktisk OG og korrigert SG.',
 UTC_TIMESTAMP(3)),
('expected-attenuation-midpoint-v1',
 'Forventet utgjæring midtpunkt v1',
 'Beregner estimert ferdig alkoholprosent fra faktisk OG og midtpunktet i forventet utgjæringsområde, via avledet FG.',
 UTC_TIMESTAMP(3));
