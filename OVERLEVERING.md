# Gjæringsassistent – videreføring

Oppdatert 7. november 2026 for **2026.11.07-1 – Første GitHub-utgave**. Teknisk utgangspunkt er p24r16, original ZIP-SHA-256 884b2dea0e42cfbf5efabc8a32ff3c0ab464c18c4ab206ec0d38a6c8ba6c26d4.

## Ny chat

Start med [den faste onboarding-instruksjonen](docs/ONBOARDING-NY-CHAT.md). Den bruker dette notatet som datert status og peker videre til autoritative krav og strukturerte kilder. Les aktuell main og release; ikke anta at siste release er installert.

## Status

Brukeren har bekreftet at p24r16 er installert og fungerer fint og ønsker å forsøke løsningen i produksjon. Datoversjonen er første publisering i nytt repository. [Release v2026.11.07-1](https://github.com/stboee/gjaeringsassistent/releases/tag/v2026.11.07-1) er publisert fra commit a1919e64d6a9db5aec9ae3cc2fd0b18314d9caca med ZIP og SHA-256. Dokumentoppdateringer på main etter taggen er ikke en ny programvareleveranse. Tidligere brukerbekreftelse er ikke en samlet UAT-kvittering for datoversjonen.

Gjeldende repository er https://github.com/stboee/gjaeringsassistent. Det gamle er omdøpt til gjaeringsassistent-old. En separat videreføringspakke er sikret med 200 gamle filer, p24r16 og kontrollsummer. Gamle styringsfiler og historiske løsninger skal ikke overstyre dagens dokumentasjon.

Denne utgaven samordner datoversjon, dokumentasjon, faglige kildelenker og Git-basert pakking. Nåværende MariaDB/InnoDB-arkitektur, generisk Node-RED-motor, HA-presentasjon, frosne sesjoner, historisk fra–til, seks felles grafer og SQLite-par er teknisk grunnlag.

Se TEST-RESULTS.md og verification/ for faktisk ny kjøring, kildeavtrykk og begrensninger. Eldre filnavn er testenes opprinnelse; application_version må stemme med utgaven. Native HA-plugin-tester bruker faktisk plugin med simulert transport. Det er ikke faktisk HA-/nettleser-UAT.

## Leserekkefølge

1. AGENTS.md, README, VERSION, BUILD-INFO.json, RELEASE-MANIFEST.json, RELEASE-NOTES.md og TEST-RESULTS.md.
2. docs/00-DOKUMENTKART-OG-STATUS.md og dokument 14 med aktive beslutninger.
3. Relevante krav 01–04, arkitektur 07, integrasjonskontrakt 05, datamodell 06 og operasjonskontrakt 12.
4. Regelmodell 10, template/editor 11, livsløp/rapport 13 og relevante fagprofiler 16/17.
5. Åpent arbeid 15, akseptanse 09, implementasjonsstatus 18 og teknisk diagnostikk 19.
6. SQL DDL, views/rutiner, registry-/template-seeder samt verification/test-catalog.json og verification/verification-model.json.

## Prinsipper som skal videreføres

- MariaDB/InnoDB er eneste autoritative persistente domenekilde. Node-RED er generisk motor/orchestrator; HA/frontend viser ferdige read-model-felt og formidler handlinger.
- Feil rettes i modellen, registry, frozen session eller read-model. Ingen lokale defaults, oppdiktede verdier, reserveberegninger eller frontend-workarounds.
- Normaliserte relasjoner, PK/FK/UNIQUE/CHECK og korte transaksjoner. InnoDB håndterer samtidighet; ingen generell writer-kø eller eksplisitt locking som normalmekanisme.
- Append-only gjelder fakta/revisjoner innenfor hver beholdt sesjon. Hele historiske sesjoner og ubrukte importerte templates kan slettes eksplisitt og atomisk. Drafts er egne mutable arbeidsflater.
- Registry → template → normalisert frozen session → generisk motor. Ingen nødvendig domenepersistens i flow/global, HA, nettleser eller lokale runtimefiler.
- Reelt fravær dokumenteres og erstattes ikke med 0. Påkrevde kontraktfelt kan ikke utelates.
- SG-only, separate B/P-modeller, én operativ sesjon og ingen automatisk fysisk utstyrsstyring.
- Én felles graftegner og samme autoritative seriegrunnlag i dashboard/rapport. Manglende måleverdier estimeres ikke. HA-timesstatistikk supplerer historiske grafer uten oppdiktet heartbeat eller ordinært B/P-grunnlag.
- SQLite er arkiv-/utvekslingsformat for sammenhørende sesjons- og templatefiler. Sammenligning skjer i MariaDB etter import. Importert template får unik identitet og opprinnelse.

## Strukturerte kilder må faktisk undersøkes

HA-identitet, inputbindinger, mappings og constraints eies av ha_entity_registry/ha_event_registry med underregistre. Output følger ha_projection_routes/ha_projection_fields/ha_draft_output_bindings. Funksjon–informasjon-lineage finnes i system_functions, information_objects og function_information_dependencies. Schema-/fraværssemantikk finnes i schema_relation_semantics/schema_absence_semantics; fysisk fasit er DDL og INFORMATION_SCHEMA.

SQL 01–04, 21, 23 og 24 beskriver registry, templates, system-/målekildemetadata og verifikasjon. Faktiske resultater er verification_test_runs/verification_test_results, med seed 25 for utførte releasekontroller. HTML, genererte JSON-kataloger og fysisk katalog er avledet inspeksjon.

## Arbeidsmåte og neste steg

Diskuter omfang først og vent på «start» før implementering. Gjennomfør deretter avtalt arbeid uten unødvendige nye avklaringer. Arbeidet føres direkte på main; issues/PR og den gamle Chat→Work/handoff-prosessen inngår ikke i arbeidsflyten. Datoversjon er ÅÅÅÅ.MM.DD-N, tag med v-prefiks og kort beskrivelse i release-tittelen.

Skill besluttet, implementert, lokalt testet, levert, installert og målmiljøbekreftet. Nye observasjoner må knyttes til riktig tid og versjon. Ikke påstå at tidligere chat eller vedlegg er lest uten faktisk tilgang. Ikke viderefør gammel backlog uten kontroll mot dagens grunnlag.

**Prototypeinstalleren resetter databasen.** Et oppgraderingsløp med databevaring er neste avgrensede arbeid før ordinære produksjonsoppgraderinger. Reell Recorder-/timesimport, HA-gjenoppkobling, nettverksbrudd, nettleser/tidssoner, arkiv-/ny-start-flyt og CPU/slow-log må fortsatt målverifiseres der konkret bevis mangler. Faglig kalibrering er åpen.

En ny chat bør først oppsummere kilder den faktisk har lest, versjon/installasjonsstatus, bindende prinsipper, siste endringer, åpne forhold og foreslått omfang. Ingen ny funksjonalitet eller produksjonsinstallasjon følger automatisk av denne overleveringen.
