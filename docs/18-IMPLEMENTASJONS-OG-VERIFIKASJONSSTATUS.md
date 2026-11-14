---
doc_id: DOC-18
role: implementation-status
status: current
source_format: markdown
---

# 18 – Implementasjons- og verifikasjonsstatus

**Gjeldende release:** `2026.11.14-1`. Teknisk utgangspunkt er p24r16. Releasehistorikk ligger i RELEASE-NOTES.md.

Implementert, lokalt release-verifisert og målmiljø-verifisert er forskjellige statusnivåer. TEST-RESULTS.md og faktiske verification_test_runs/verification_test_results viser testbevis; dokument 15/09 viser åpne måltester. Ingen grønn releaseport er alene bevis på fungerende operatørflyt i Home Assistant.

| Område | Implementert | Lokal verifikasjon | Målmiljø |
| --- | --- | --- | --- |
| MariaDB/InnoDB, normalisering, append-only revisjoner og eksplisitt sletting | Ja | Native SQL, constraints, rollback, samtidighet og fysisk katalog | Delvis tidligere demonstrert; ny installasjon må kontrolleres |
| DB-eide HA-registre, payloadfelt og inputbindinger | Ja | Faktisk SQL/NR/plugin 0.80.3-validering | Faktisk HA-brukertest åpen |
| Start, frozen templates, livsløp og klargjøring | Ja | Native livsløpsregresjon | Gjeldende brukertest åpen |
| Ordinær HA-history/live, heartbeat-gap og målevalidering | Ja | Native SQL/NR med kontrollerte responser | Reell Recorder/import/kalibrering åpen |
| Historisk fra–til, fast domenehorisont, etterregistrering og B/P-tid | Ja | Native tidsgrenser, klokke, eksport/reimport og kortvisning | Reell HA/nettleser og tidsfelt åpen |
| Kriteriekorreksjon, fravik, vurderingsbevis og seks felles grafer | Ja | Samme SQL, dashboard- og rapporttegner | Visuell kontroll og reelle data åpen |
| Session-avgrenset lesing og billig uendret polling | Ja | Native vekst-/samtidighetstest | CPU/slow-log på gangpc åpen |
| SQLite-par, egen importidentitet, SHA, aktiv eksport og arkivadministrasjon | Ja | Native eksport/import, rollback og samtidige rapporter | TEST-UAT-014 åpen |
| DB-klassifisert Systemkontroll og faktisk importdekning | Ja | TEST-FUNC-023: rapporttilfelle med 215 timepunkter/0 detaljbøtter, policyendring og manglende metadata | Datoversjonens målmiljøtest åpen |
| HA-publisering uten feilsirkel, ferskt DB-retry og utgangskvittering | Ja | TEST-FUNC-023 med faktisk plugin-controller og simulert transport | Reell HA-gjenoppkobling åpen |
| Databevarende oppgradering og backup | Ja | TEST-FUNC-025: faktisk installer/dump/restore, baseline- og filoppgradering samt feiltilfeller; Docker-transport simulert | OPEN-015 åpen |
| DB-eide startfelt/slurry og operativ P/B-kontroll | Ja | TEST-FUNC-024: alle 19 startmålefelt i én observasjon, sen rollback, B/P-fravik ved manglende tidsserie, faktiske feltbindinger og beholdt gammel sesjon | OPEN-016 åpen |
| Sensoriske slidere, temperaturpresisjon, sensorvalg og lesbare kilder | Ja | TEST-FUNC-026/027: faktisk SQL/NR og Chromium med kontrollert HA-skall | Faktisk HA-brukertest åpen |
| Strukturert REQ/DEC/VER/TEST/UAT, registrering og rapport | Ja | Kildemodell, SQL-relasjoner og releaseport | UAT-registrering i målmiljø åpen |

Runtime-schema er 11, template-schema 4. Eksakte tabell-/view-/HA-tall følger genererte fysiske kataloger og releaseforventninger. Katalogdekning alene er ikke et matematisk normalformbevis. Legacy-navn i regresjonsfiler beskriver funksjonens opprinnelse; bevisenes application_version og kildeavtrykk skal være gjeldende release.

S-04/M42 er publiserte normaliserte gjærprofiler. Faktisk gjæring med profilene og faglig kalibrering er ikke utført av programvaretestene. HA-timesstatistikk er grafgrunnlag, ikke oppdiktet ordinært B/P-målegrunnlag.

Prosjekteier bekrefter 14.11.2026 at 2026.11.13-1 er installert i målmiljøet. Siste vedlagte tekniske målrapport er fortsatt fra p24r16 08.11.2026 kl. 22:57. Installasjonsbekreftelsen dokumenterer ikke funksjon, databevaring eller de enkelte UAT-testene; konkrete måltester står fortsatt åpne.

Brukerens nye observasjon av to konfigurasjonsfeil etter templatevalg er reprodusert lokalt i 2026.11.09-1. Årsaken er manglende godkjenning av `startfields` i kortets konfigurasjonskontroll, rettet i 2026.11.09-2. Faktisk HA-/nettleserbekreftelse gjenstår.

## Rettet publisering av sensorinnstillinger

OPEN-017: Brukerens målmiljø viser HTTP 404 for source-settings.json etter installasjon av 2026.11.13-1. Feil parameter source_path er rettet til stage_path i DB-resultatets publiseringsjobb. Publiseringsresultat og stderr er koblet til den eksisterende felles feilrapporteringen. Den utvidede tests/test-p24r8.js prøver produsent/publiserer-grensen og faktisk JSON/gzip-tilbake-lesing og har bestått. Rettelsen inngår i 2026.11.14-1. TEST-RESULTS.md angir faktisk releaseverifikasjon; målmiljøbekreftelse av den nye pakken gjenstår.
