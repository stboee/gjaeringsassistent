---
doc_id: DOC-18
role: implementation-status
status: current
source_format: markdown
---

# 18 – Implementasjons- og verifikasjonsstatus

<!-- BEGIN ARCHITECTURE GUARDRAILS -->
**Gjennomgående ansvarsdeling og arkitektursperrer**

- MariaDB/InnoDB er eneste autoritative persistente sannhetskilde for domenedata, konfigurasjon, regler, parametere og nødvendig vedvarende tilstand. Informasjon lagres der og hentes derfra.
- HA/frontend viser ferdige DB/read-model-felt og formidler handlinger. Node-RED er generisk motor, orkestrering og transport; HA-state er ikke domenefasit.
- Ingen oppdiktede verdier, lokale defaults, fallback, reserveberegninger, hardkodede fagregler eller workarounds for manglende/feil grunnlag. Feilen rettes ved den autoritative kilden og skal være synlig.
- Påkrevde felt kan ikke utelates; reelt fravær modelleres og forklares, aldri som 0. Ingen nødvendig domenestate i flow/global/context, nettleser, HA eller lokale runtimefiler.
- Registry → template → normalisert frozen session → generisk motor. Sessionens grunnlag, rettigheter og policy er eksplisitte og sporbare.
- Normaliserte relasjoner, PK/FK/UNIQUE/CHECK og korte transaksjoner håndhever integritet. InnoDB håndterer normal samtidighet; ingen global writer-kø, normal applikasjonslocking eller retry som skjuler modellfeil.
- Fakta og korreksjoner innen beholdte sesjoner er append-only. Mutable kladder og eksplisitt atomisk sletting av hele gamle sesjoner er særskilt modellerte operasjoner.
- SG-only; separate B/P-modeller; én operativ sesjon; ingen automatisk fysisk styring. Dashboard og rapport bruker felles autoritativt seriegrunnlag og graftegner uten estimerte målinger.

Flyktig transport, ulagret operatørinput og tegnekoordinater gir ingen adgang til alternativ faglig tilstand. Grunnreglene gjentas bevisst og kontrolleres mot samme kilde; se dokument 14 for begrunnelser.
<!-- END ARCHITECTURE GUARDRAILS -->

Denne oversikten beskriver tilgjengelige funksjoner i kildegrunnlaget. Eksakt leveranse og testkjøring identifiseres av VERSION/BUILD-INFO og bevisenes kildeavtrykk.

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


Sensorinnstillingenes publiseringskontrakt er implementert og har lokal transportregresjon. Målbekreftelse følger OPEN-017. Se [dokument 15](15-AAPENT-ARBEID.md) for all dokumentert installasjons-/målmiljøstatus og [TEST-RESULTS](../TEST-RESULTS.md) for releasens bevis. Historiske feil og rettinger beskrives i releasehistorikken.
