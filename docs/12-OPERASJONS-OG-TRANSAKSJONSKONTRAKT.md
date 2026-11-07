---
doc_id: DOC-12
role: transaction-contract
status: normative
source_format: markdown
---

# 12 – Node-RED–MariaDB operasjons- og transaksjonskontrakt

**Rolle:** Normativ grense for mutasjoner/reads mellom Node-RED-motoren og MariaDB. Det finnes ingen separat applikasjons-API/backend mellom disse lagene.

## 1. Normal operasjon

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

## 2. Intern meldingskontrakt

Mellom noder kan `msg` bære transient data for én operasjon. Informasjon som må overleve operasjonen, en restart eller brukes av en senere kommando skal persisteres i MariaDB og leses derfra igjen.

`flow.*`, `global.*` og runtimefiler skal ikke være nødvendig domenestate. Flyktig debounce/UI-orchestrering er tillatt så lenge det ikke blir autoritativ fagstate.

## 3. Transaksjonsregler

- Én faglig mutasjon skal committe/rollbacke samlet. En DB-feil inne i en fler-statement-mutasjon skal aldri kunne etterlate en senere commitbar deltilstand; transaksjonsgrensen skal derfor ha server-side rollback-handler eller tilsvarende garantert rollback.
- PK/FK/UNIQUE/CHECK og idempotente operation-ID-er brukes som primær integritetsmekanisme.
- InnoDB håndterer normal samtidighet; ingen global writer-kø eller eksplisitt locking som standard.
- Historiske fakta/revisions appendes i stedet for å omskrive journalhistorikk.
- Mutable draft-tabeller er eksplisitte arbeidsflater og kan oppdateres.

## 4. Viktige operasjonsfamilier

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

## 5. Ingest og evaluatorsekvens

Historisk import skal ikke ha konkurrerende evaluatorgrener. Etter committed chunk kjøres biologisk evaluator, deretter prosessevaluator, før neste chunk. Dette er normal prosess-sekvensiering, ikke applikasjonsstyrt writer queue.

## 6. Read-operasjoner

Rene reads kan kjøres parallelt og kan kortvarig se siste committed snapshot. Neste read-model-refresh korrigerer visningen. Systemet skal ikke innføre locking for å skjule normal snapshot-semantikk.

## 7. Feil og kvittering

Valideringsavvisning, DB-/integritetsfeil og teknisk transportfeil er forskjellige utfall og skal kunne skilles. Uncaught Node-RED-feil går til Technical Event-safety-net der persistens er mulig.

Operatørflaten skal bruke observerbar DB/read-model-kvittering for «lagret/utført», ikke optimistisk lokal antakelse.

## 8. Metadata-/bootstrapoperasjon

Node-RED leser HA entity/event-registre, inputbindings og bootstrapmetadata fra MariaDB. Fysiske HA-noder er runtimeimplementasjon; betydningen av entity-ID→domeneinput skal ikke dupliseres i lokale Function-tabeller.

## 9. Verifikasjonsoperasjoner

`record_uat_result` validerer test-ID/status/payload, leser registrert aktiv UAT-test, oppretter nytt `verification_test_run` og `verification_test_result` atomisk og refresher deretter DB-read-modelen. Resultatet overskriver ikke tidligere gjennomføringer.

`export_verification` er read-only og skal lese et konsistent DB-snapshot. JSON og HTML genereres fra samme resultatsett; renderer skal ikke beregne alternativ verifikasjonsstatus.

## P24r12: Start og normalisert pitch

`ga_select_start_template_tx` og `ga_read_ha_draft_projection` eier templatevalgets kladd og tilbakepublisering. Start leser DB-klokken, eksplisitt pitchmodus/tid, HA-valgkontrakter og grenser. Obligatorisk null/tom input avvises før Number-konvertering. `ga_start_session_tx` skriver felles sesjon, korrekt pitch-subtype og frozen definisjon atomisk. Slurry og tørrgjær kan ikke knyttes til feil pitchmodus.

Prosessovergang leser `v_process_guidance_effective`. Registrert fravik og tilbaketrekking påvirker samme DB-resultat i anbefaling, overgangsbeslutning og oversikt. Manglende påkrevd kriteriebevis skal ikke telles som håndtert.

`ga_prepare_selected_demo_tx` eier også demoens kladdgrunnlag. Node-RED kaller rutinen og sender resultatet gjennom den ordinære Start-banen; demofakta er ikke lokale Node-RED-standardverdier.
