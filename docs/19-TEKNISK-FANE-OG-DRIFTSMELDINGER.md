---
doc_id: DOC-19
role: diagnostics
status: normative
source_format: markdown
---

# 19 – Teknisk diagnostikk og Systemkontroll

**Rolle:** Normativ teknisk/operativ kontrakt for observability. Visuell plassering i dashboardet ligger i dokument 03.

## 1. Formål

Teknisk gir én lesbar flate for runtime/datagrunnlag, målekilde, aktive problemer, teknisk hendelseslogg, Systemkontroll, strukturert diagnostisk eksport og eksplisitt måledataeksport. MariaDB er autoritativ; HA-attributter/custom card er projeksjon.

## 2. Technical Events og aktive issues

- `technical_events` lagrer tekniske hendelser.
- `issue_raised` / `issue_cleared` med `issue_key` uttrykker problemhistorikk.
- `v_active_technical_issues` utleder åpne problemer.
- Identisk aktiv issue skal ikke få ny `issue_raised` ved hvert kontrollkjør når nøkkel/melding er uendret.

Den generelle Node-RED Catch-en er et tab-wide uncaught safety-net for Gjæringsassistent-flowen, ikke en manuelt vedlikeholdt liste over enkelt-noder. Technical Event-writer/MySQL og egen feilresultatkjede må skjermes mot rekursiv catch.

## 3. Systemkontroll

`system_check_definitions` eier kontrollkatalog/label/kategori/alvorlighet. `system_check_expectations` eier eksplisitte releaseforventninger som ikke kan utledes fra andre registre. Hvert kjør persisteres i `system_check_runs` og resultat per kontroll i `system_check_results`.

Kontrollene dekker minst database, schema, writable, HA-kontrakt, session/livsløp, frontendpublisering, Node-RED, målekilde, runtimeautoritet, konfigurasjon, metadata-lineage, tid og aktive runtimefeil.

Systemkontroll trigges ved Node-RED-start, etter vellykket Start, ved overgang fra history catch-up til LIVE og på operatørens **Kjør systemkontroll**. `checked_at` skal komme fra persisted run.

## 4. Runtime issues

Kontrollpunktet `runtime_issues` gjør nye ikke-Systemkontroll-runtimefeil synlige i samlet status. Systemkontroll skal ikke bli grønn samtidig som uncaught feil bare finnes i Node-RED-loggen.

## 5. Målekilde / Tilt

Systemkontroll leser `v_measurement_source_status`. HA-sensoren leser en dedikert `v_measurement_source_ha_projection`. Begge bygger på samme MariaDB-fakta:

- `measurement_source_profiles`;
- `session_measurement_sources`;
- `measurement_data_gaps`;
- siste `measurements_5m`;
- relevante ingest quality-fakta.

Teknisk skal ved aktiv reell session kunne vise profil, source entity-ID-er, importcursor, sist-OK, siste bøtte/sample count, SG min/middel/median/maks, temperaturmiddel, RSSI, målingsalder, gap og siste feil/status. Den skal ikke lese eksterne Tilt-entiteter direkte for å lage en parallell sannhet.

HA-projeksjonen skal bare inneholde HA-gyldige scalar/string/object/array-attributter. Nullable interne råfelt skal ikke sendes som `null` hvis HA-nodekontrakten avviser dem; DB-read-model skal levere displayverdi eller utelate feltet.

Teknisk-panelet skal følge målekildeprojeksjonen ved hver vellykket live-import, også når HA-state forblir `LIVE` og bare attributtene endres. Persistente timestamps forblir UTC; `*_display`-feltene som vises i Målekilde/Tilt skal formateres i `Europe/Oslo` av MariaDB-read-modelen. Panelet skal kunne vise når projeksjonen sist ble lest/oppdatert slik at ferskheten kan kontrolleres uten å tolke UTC manuelt.

## 6. Metadata/informasjonskjede

HA-kontrollen leser active/required entities og aliases fra `ha_entity_registry`/`ha_entity_aliases`; ingen parallell hardkodet entity-liste i Systemkontroll.

`metadata_lineage` leser `v_metadata_lineage_gaps`, `v_information_object_usage` og `v_function_producer_consumer`. Required grensesnitt/aktive funksjoner uten nødvendige avhengigheter skal feile; alle fysiske DB-objekter trenger ikke automatisk både direkte produsent og konsument fordi seed/config/audit/read-model-kjeder kan være indirekte.

## 7. Frontendpublisering

Node-RED publiserer dashboard/custom card/loader atomisk og journalfører `frontend_publication_runs` / `frontend_publication_artifacts` med releaseversjon, mount-verifikasjon og SHA-256. Systemkontroll sammenligner siste vellykkede publisering med forventet releaseidentitet og artefakt-SHA.

## 8. Strukturert Teknisk-eksport

**Eksporter Teknisk** skriver et read-only JSON-snapshot under HA-public `exports/`. Snapshotet skal inneholde applikasjonsversjon, pre-start/current-session-grunnlag, relevante HA-projeksjoner, målekildestatus/binding/siste 5-minuttersdata/datagap, aktive problemer, nyere Technical Events, frontendpublisering og siste Systemkontroll inkl. definisjoner/resultater. Node-RED skal også holde `gjaeringsassistent-teknisk-status-latest.json` oppdatert periodisk gjennom den samme DB-spørringen, uten å være avhengig av et HA-event. Ved manuell eksportfeil kan frontend derfor lenke til siste DB-genererte snapshot.

Alle operatørnedlastinger skal få lokalt timestamp-prefix med millisekunder, også når nedlastingen peker til den automatiske sistefilen. `latest` er en periodisk serverprojeksjon; det lagrede nedlastingsnavnet skal bevare tidligere rapporter. Eksporten skal også inneholde faktisk MariaDB-versjon, SQL-modus, forbindelsens tegnsett/kollasjon, Node-RED-kodens releaseversjon, publiserte templateversjoner og HA-templatevalgets faktiske alternativer. DB-release og Node-RED-/frontend-release skal kunne sammenlignes ved feilsøking.

Filen er diagnostikk og skal aldri importeres som runtime-state.

## 9. Måledataeksport

**Eksporter måledata** er en separat operatørhandling i Teknisk, ikke et Systemkontroll-resultat. Den skriver CSV direkte fra MariaDB for aktiv session og omfatter session-ID/batch, pitch, OG, forventet utgjæring/avledet FG, kronologiske 5-minuttersmålinger med sample count og tilgjengelige min/middel/median/maks-verdier for SG, temperatur, trykk og RSSI, samt persisterte `measurement_data_gaps`. Frontend bestiller bare eksporten og viser lenken; den beregner eller reparerer ikke måledata.

Eksporten er analyse-/diagnostikkgrunnlag og er ikke runtime-state eller restorekilde.

## 10. Tid

Persistent maskintid er UTC. Operative tidspunkt i Teknisk formateres i `Europe/Oslo`. Klokkesammenligning Node-RED↔MariaDB skal bruke entydig tid/epoch der det er hensiktsmessig.

## 11. Legacy HA-identiteter

Kjente legacy entity-ID-er kan eksistere i HA-registry etter tidligere prototyper. Når alle aktive normative ID-er finnes, er legacy-ID alene informativ og skal ikke sette samlet status til warning/error. Manglende required normativ ID er derimot avvik.

## 12. Verifikasjonsstatus

Teknisk viser et kompakt DB-avledet sammendrag for TECH/FUNC/UAT og siste relevante testkjøring. Detaljert REQ→VER→TEST/resultathistorikk, UAT-registrering og verifikasjonseksport ligger i egen **Verifikasjon**-fane. Teknisk/frontend skal ikke beregne coverage eller reparere manglende verifikasjonsrelasjoner.

## Analyse- og rådatakvalitet i teknisk eksport

Teknisk JSON-format 1.1 inkluderer `analysis_quality`: kvalifiserte baselines, aktuelle metrics/status, frozen beregningsparametere, siste 100 analyseavvisninger, DB-grupperte avvisningstall og siste 100 råkvalitetsutfall med avviste/manglende prøver. Dette følger både manuell eksport og den periodiske sistefilen. Avviste bånd har egen reason_code og skal ikke i seg selv gjøre en gyldig hovedverdi utilgjengelig. Neste bryggs tuning kan dermed undersøke både datagrunnlag og hvorfor en verdi ble holdt tilbake.

## Skrivbarhetskontroll

MariaDB 12.3.3 returnerer `read_only` som enum. Systemkontrollqueryen leverer `database_writable=1` bare ved `@@global.read_only=OFF`, ellers 0, sammen med den rå serververdien. Kontrollmotoren bruker denne eksplisitte DB-verdien; manglende eller ugyldig kontrollgrunnlag gir synlig feil. En senere OK-kontroll lukker tidligere writable-feil med et nytt `issue_cleared`-event; eksisterende kontroll- og hendelseshistorikk omskrives ikke.

## P24r8 publisering og diagnostikk

Oversikt bruker schema 2.3. `analysis.series_definitions` er en ordbok med DB-eide presentasjonsfelt. Punktets `presentation_id` peker på denne; frontend gjør bare oppslag og tegning. Ingen metrikker beregnes i nettleseren. DB velger første, siste, min og maks per segment/serie/visningsintervall. Det kan derfor være mer enn ett faktisk punkt per 30 minutter. Nå-verdier leses fra full serie og påvirkes ikke av punktutvalget.

Publiseringsverktøyet får kun stier til unik stagingfil og målfil. Det lager kompakt JSON og `.json.gz`, verifiserer gzip tilbake mot JSON-bytes og leser publiserte filer tilbake. Filene er reproducerbare presentasjons-/eksportderivater; MariaDB er fortsatt eneste runtime-authority. HTTP-serveren kan forhandle gzip-sidefilen med Accept-Encoding. Dette endrer ikke JSON-URL-en; faktisk HA-levering skal måltestes. Direkte gzip-nedlasting er også mulig.

Normal Teknisk eksport inneholder antall/tidsrom for importerte 5-minuttersrader og gjeldende timepunkter, DB-lagrede visningsvalg samt SHA, størrelse, genereringstid, akser og punkttall for publisert oversikt. Utvidet diagnostikk inkluderer hele det publiserte slanke GUI-grunnlaget. En manglende/ugyldig oversiktsfil registreres eksplisitt som diagnostikkfeil; den rekonstrueres ikke i eksporten.

## P24r12: teknisk projeksjon

`v_technical_event_presentation`, `v_technical_presentation_context` og `v_ha_technical_payloads` eier tekniske statuslinjer, tom historikk, hendelsesarrays og kontrolltid i Europe/Oslo. Teknisk writer krever eksplisitt severity, event_type, code, subsystem, recoverable og blocks_operation fra produsenten. Systemkontroll leser runtime_node_id i HA-registeret for å kontrollere foreldet Start-status.

Releasekontroll leser fysisk schema og strukturerte fraværs-/relasjonsmetadata. Maskinresultater skiller fortsatt lokal TECH/FUNC-verifikasjon fra utestet målmiljø-UAT.

Systemkontroll sjekker også manglende nullable-kolonneforklaringer, manglende relasjonsmetadata og uenighet mellom de to application_version-markørene. Ingen av disse feilene godtas som et komplett schema.

Tekniske event-ID-er, schema_version og lagringstid genereres av MariaDB. Node-RED legger ikke til en lokal klokke eller tilfeldig identitet ved lagring.

## Målekildeklassifisering, datadekning og ventende HA-publisering

`measurement_source_check_policy` eier status/alvorlighet per målekildestatus. `v_measurement_source_system_check` leverer ferdig kontrollresultat. `HISTORISK` er en normal tilstand etter fullført avgrenset import. Manglende ordinært målegrunnlag eller registrert importadvarsel gir datagrunnlagsadvarsel; ukjent policy gir feil. Node-RED validerer kontrakten og persisterer resultatet uten egen statusliste.

`v_session_import_coverage` viser faktisk antall og første/siste tidspunkt for femminuttersbøtter og gjeldende timepunkter samt antall registrerte rådatagap. Bøtter/punkter er ikke råprøver eller en beregnet dekningsprosent. En ferdig behandlet periode betyr ikke at hele perioden har data. «Ingen registrerte gap» alene beviser heller ikke full dekning. Den samme DB-teksten inngår i startstatus, målekilde, oversikt, rapport og teknisk eksport.

`HA_PUBLICATION_DEFERRED` er en åpen, deduplisert advarsel per berørt HA-utgangsnode ved `NoConnectionError`/«Integration not loaded». Hendelsen lagres uten straks å publisere driftsmeldingen tilbake gjennom feilbanen. En ti-sekunders teknisk kontroll leser ventende DB-problemer. Når pluginens egen forbindelsestelemetri er connected/running, leses ferske DB-projeksjoner for status, teknisk, målekilde og startstatus. Ingen gamle domenepayloads eller redigerbare arbeidskladder blir lagt i en lokal retry-kø.

Den faktiske HA-nodens vellykkede utgang kvitterer `HA_PUBLICATION_RECOVERED` for samme node. Verken en mottatt kommando, en eksisterende entitet, neste Systemkontroll eller forbindelsesflagget alene lukker problemet. Normale publiseringer uten gjenoppretting lager ingen ekstra kvitteringsspørring. Payload-/kontraktfeil forblir reelle feil. Feil i den tekniske DB-writeren skal ikke utløse ny HA-publisering som rekursivt lager samme feil.
