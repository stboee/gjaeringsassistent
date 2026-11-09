---
doc_id: DOC-18
role: implementation-status
status: current
source_format: markdown
---

# 18 – Implementasjons- og verifikasjonsstatus

**Gjeldende release:** `2026.11.09-1`. Teknisk utgangspunkt er p24r16. Releasehistorikk ligger i RELEASE-NOTES.md.

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
| Databevarende oppgradering og backup | Ja | TEST-FUNC-025: faktisk installer/dump/restore, begge kildeversjoner og feiltilfeller; Docker-transport simulert | OPEN-015 åpen |
| DB-eide startfelt/slurry og operativ P/B-kontroll | Ja | TEST-FUNC-024: faktiske DB-feltbindinger/snapshots og ny sesjon ved siden av beholdt gammel | OPEN-016 åpen |
| Strukturert REQ/DEC/VER/TEST/UAT, registrering og rapport | Ja | Kildemodell, SQL-relasjoner og releaseport | UAT-registrering i målmiljø åpen |

Runtime-schema er 10, template-schema 4. Eksakte tabell-/view-/HA-tall følger genererte fysiske kataloger og releaseforventninger. Katalogdekning alene er ikke et matematisk normalformbevis. Legacy-navn i regresjonsfiler beskriver funksjonens opprinnelse; bevisenes application_version og kildeavtrykk skal være gjeldende release.

S-04/M42 er publiserte normaliserte gjærprofiler. Faktisk gjæring med profilene og faglig kalibrering er ikke utført av programvaretestene. HA-timesstatistikk er grafgrunnlag, ikke oppdiktet ordinært B/P-målegrunnlag.

Siste vedlagte målrapport er fra p24r16 08.11.2026 kl. 22:57. Den nye leveransen er ikke bekreftet installert i målmiljøet. Tidligere generell bekreftelse av p24r16 lukker ikke de ferske konkrete avvikene eller de enkelte UAT-testene.
