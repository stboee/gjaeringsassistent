---
doc_id: DOC-18
role: implementation-status
status: current
source_format: markdown
---

# 18 – Implementasjons- og verifikasjonsstatus

**Gjeldende release:** `2026.11.07-1`. Teknisk utgangspunkt er p24r16. Releasehistorikk ligger i RELEASE-NOTES.md.

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
| Strukturert REQ/DEC/VER/TEST/UAT, registrering og rapport | Ja | Kildemodell, SQL-relasjoner og releaseport | UAT-registrering i målmiljø åpen |

Runtime-schema er 9, template-schema 4. Eksakte tabell-/view-/HA-tall følger genererte fysiske kataloger og releaseforventninger. Katalogdekning alene er ikke et matematisk normalformbevis. Legacy-navn i regresjonsfiler beskriver funksjonens opprinnelse; bevisenes application_version og kildeavtrykk skal være gjeldende release.

S-04/M42 er publiserte normaliserte gjærprofiler. Faktisk gjæring med profilene og faglig kalibrering er ikke utført av programvaretestene. HA-timesstatistikk er grafgrunnlag, ikke oppdiktet ordinært B/P-målegrunnlag.

p24r15 er bekreftet installert ved brukerens rapport fra 17.10.2026. Brukeren har senere bekreftet at p24r16 er installert og fungerer fint. Datoversjonen er første GitHub-utgave; installasjon av selve datoversjonen og de enkelte UAT-resultatene må dokumenteres separat.
