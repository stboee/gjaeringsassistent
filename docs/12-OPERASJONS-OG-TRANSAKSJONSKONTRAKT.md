---
doc_id: DOC-12
role: transaction-contract
status: normative
source_format: markdown
---

# 12 – Node-RED–MariaDB operasjons- og transaksjonskontrakt

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

**Rolle:** Normativ grense for mutasjoner/reads mellom Node-RED-motoren og MariaDB. Det finnes ingen separat applikasjons-API/backend mellom disse lagene.

## Normal operasjon

En stateful operatørhandling følger i prinsippet:

```text
HA button/event
→ Node-RED ingress + operation/correlation ID
→ les autoritativt MariaDB-grunnlag
→ valider fagregel
→ én kort atomisk DB-mutasjon
→ commit/rollback
→ les DB/read-model
→ publiser kvittert resultat
```

Mottatt HA-event er ikke i seg selv kvittering på lagring.

SQL-objekter opprettes med `SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci`. mysql2-forbindelsen bruker `UTF8MB4_UNICODE_CI` og UTC-token `Z`. Skjemaets streng- og tidssemantikk skal være eksplisitt, slik at endrede MariaDB-standardverdier ikke kan endre kontrakten. Lineage-koder som filtreres fra views skal ha eksplisitt kollasjon.

## Intern meldingskontrakt

Mellom noder kan `msg` bære transient data for én operasjon. Informasjon som må overleve operasjonen, en restart eller brukes av en senere kommando skal persisteres i MariaDB og leses derfra igjen.

`flow.*`, `global.*` og runtimefiler skal ikke være nødvendig domenestate. Flyktig debounce/UI-orchestrering er tillatt så lenge det ikke blir autoritativ fagstate.

## Transaksjonsregler

- Én faglig mutasjon skal committe/rollbacke samlet. En DB-feil inne i en fler-statement-mutasjon skal aldri kunne etterlate en senere commitbar deltilstand; transaksjonsgrensen skal derfor ha server-side rollback-handler eller tilsvarende garantert rollback.
- PK/FK/UNIQUE/CHECK og idempotente operation-ID-er brukes som primær integritetsmekanisme.
- InnoDB håndterer normal samtidighet; ingen global writer-kø eller eksplisitt locking som standard.
- Historiske fakta/revisions appendes i stedet for å omskrive journalhistorikk.
- Mutable draft-tabeller er eksplisitte arbeidsflater og kan oppdateres.

## Viktige operasjonsfamilier

- pre-Start draftfelt og templatevalg;
- Start/freeze og målekildebinding;
- HA-history ingest og 5-minutterslagring;
- B/P-evaluering, transitions og recommendations;
- manuelle observation rounds;
- kriteriekorreksjon og process exception;
- tidskorrigering;
- Neste/Tilbake;
- rapport/eksport;
- Avslutt/Gjør klar;
- Systemkontroll/Teknisk eksport;
- UAT-resultat og verifikasjonseksport;
- template draft/save/validate/publish.

Eksakt SQL/flow er implementasjonsfasit for operasjonen; dette dokumentet beskriver ansvarsgrensen.

## Ingest og evaluatorsekvens

Historisk import skal ikke ha konkurrerende evaluatorgrener. Etter committed chunk kjøres biologisk evaluator, deretter prosessevaluator, før neste chunk. Dette er normal prosess-sekvensiering, ikke applikasjonsstyrt writer queue.

## Read-operasjoner

Rene reads kan kjøres parallelt og kan kortvarig se siste committed snapshot. Neste read-model-refresh korrigerer visningen. Systemet skal ikke innføre locking for å skjule normal snapshot-semantikk.

## Feil og kvittering

Valideringsavvisning, DB-/integritetsfeil og teknisk transportfeil er forskjellige utfall og skal kunne skilles. Uncaught Node-RED-feil går til Technical Event-safety-net der persistens er mulig.

Operatørflaten skal bruke observerbar DB/read-model-kvittering for «lagret/utført», ikke optimistisk lokal antakelse.

## Metadata-/bootstrapoperasjon

Node-RED leser HA entity/event-registre, inputbindings og bootstrapmetadata fra MariaDB. Fysiske HA-noder er runtimeimplementasjon; betydningen av entity-ID→domeneinput skal ikke dupliseres i lokale Function-tabeller.

## Verifikasjonsoperasjoner

`record_uat_result` validerer test-ID/status/payload, leser registrert aktiv UAT-test, oppretter nytt `verification_test_run` og `verification_test_result` atomisk og refresher deretter DB-read-modelen. Resultatet overskriver ikke tidligere gjennomføringer.

`export_verification` er read-only og skal lese et konsistent DB-snapshot. JSON og HTML genereres fra samme resultatsett; renderer skal ikke beregne alternativ verifikasjonsstatus.

## Start og normalisert pitch

`ga_select_start_template_tx` og `ga_read_ha_draft_projection` eier templatevalgets kladd og tilbakepublisering. Start leser DB-klokken, eksplisitt pitchmodus/tid, HA-valgkontrakter og grenser. Obligatorisk null/tom input avvises før Number-konvertering. `ga_start_session_tx` skriver felles sesjon, korrekt pitch-subtype og frozen definisjon atomisk. Slurry og tørrgjær kan ikke knyttes til feil pitchmodus.

Prosessovergang leser `v_process_guidance_effective`. Registrert fravik og tilbaketrekking påvirker samme DB-resultat i anbefaling, overgangsbeslutning og oversikt. Manglende påkrevd kriteriebevis skal ikke telles som håndtert.

`ga_prepare_selected_demo_tx` eier også demoens kladdgrunnlag. Node-RED kaller rutinen og sender resultatet gjennom den ordinære Start-banen; demofakta er ikke lokale Node-RED-standardverdier.

## DB-validering av Start

`ga_read_start_context(attempt_id,historical_end)` validerer den aktuelle kladden, lagrer feltvise forsøksfakta og returnerer validering og samme DB-grunnlag fra ett konsistent snapshot. Startfunksjonen transporterer DB-avvisningen og kontrollerer kontraktens tilstedeværelse/samsvar; den har ingen alternativ slurry-/tørrgjærvalidering. `ga_start_session_tx` beholder den atomiske frozen-/pitch-/livsløpsskrivingen. `v_system_check_session` teller åpne P/B-besøk bare innen operativ aktiv sesjon og oppdager både manglende og reelt doble åpne besøk.

## Strukturert grensesnitt og konsumentkontroll

[Grensesnittkatalogen](../contracts/interface-catalog.json) angir autoritative SQL-/kontraktkilder og hvilke read-model-/schemafiler som er avledet eller tatt opp fra MariaDB. [Generert referanse](generated/interface-reference.md) viser parameterdeklarasjoner fra faktisk SQL og direkte CALL-konsumenter i flowen. Rutiner kan også ha SQL-/adapterkonsumenter; fravær av et direkte flowkall betyr ikke automatisk ubrukt rutine.

verify-read-model-contract.py kontrollerer aktive views og kvalifiserte konsumentkolonner. verify-interface-contracts.py kontrollerer direkte rutinenavn, registrerte projeksjonskilder og fullstendige HA-felt/bindinger. Native tester prøver parametere, NULL-/fraværssemantikk, rollback, resultatformer og faktisk plugin-validering. Dekning på ett nivå skal ikke presenteres som full verifikasjon av alle operasjoner eller faktisk HA-transport.
