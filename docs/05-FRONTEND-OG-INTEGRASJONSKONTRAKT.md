---
doc_id: DOC-05
role: contract
status: normative
source_format: markdown
---

# 05 – Frontend- og integrasjonskontrakt

**Rolle:** Normativ semantisk HA ↔ Node-RED-kontrakt. Eksakte maskinmetadata eies av MariaDB-registeret.

## 1. Autoritet og ansvar

- `ha_entity_registry` eier aktive HA-entiteter, entity-/config-ID, type, retning, required-status og bootstrap.
- `ha_entity_select_options` / `ha_entity_number_constraints` eier typeavhengige options/constraints.
- `ha_event_registry` eier parameteriserte HA-eventkanaler og autoritativ listeneridentitet.
- `ha_entity_aliases` eier kjente tidligere entity-ID-er for avstemming.
- `ha_entity_input_bindings` / `ha_entity_input_value_mappings` eier operatørinput→databasefelt/konvertering.
- `contracts/ha-node-red-contract.json` er et **generert releaseuttrekk**, ikke en parallell normativ sannhetskilde.
- Fysiske HA-noder i Node-RED-flowen er runtimeimplementasjon og må være konsistente med registeret.

Som konkret identitetseksempel er templatevalget `select.gjaeringsassistent_template` med config-ID `haec_field_template_v1`. Detaljlisten vedlikeholdes ikke manuelt i dokumentasjonen.

## 2. Grunnregler

1. Entity-ID, config-ID, type og retning er eksplisitte og stabile.
2. Dashboardet skal ikke referere til entiteter uten aktiv metadataregistrering.
3. Fast operatørkommando via HA `button` har nøyaktig én autoritativ `ha-button`-inngang i Node-RED.
4. Parameteriserte operasjoner kan bruke registrerte HA-events; hvert event har én autoritativ listener.
5. Home Assistant er operatør-/presentasjonsflate. Domenevalidering bruker MariaDB-state, ikke reststate i HA/browser.
6. Måltest av operatørgrensen bruker de samme entity/event-banene som operatøren faktisk bruker.

## 3. Bootstrap

Ved Node-RED-start leses HA-register/aliases fra MariaDB før ordinær restore/Systemkontroll. State-bærende entiteter får registrert bootstrapstate; registration-only buttons registreres uten oppdiktet normalverdi.

Bootstrap er teknisk initialisering, ikke domeneautoritet. Persisted draft/runtime fra MariaDB publiseres over bootstrapverdien når read-model er tilgjengelig. Manglende måling uttrykkes som `unknown`/eksplisitt «ingen måling», ikke tallet 0.

## 4. Entity-avstemming

Hvis en required normativ ID mangler kan diagnostikk bruke eksplisitte aliases eller entydig suffiksvariant for å forklare mulig HA-kollisjon. Avstemmingen skal være generisk og basert på registeret, ikke hardkodede Function-lister.

Legacy-ID ved siden av komplett aktiv kontrakt er informativ. Manglende required normativ ID er Systemkontroll-avvik.

## 5. Faste kommandoer

Normal bane:

`dashboard/custom card → HA button.press → registrert HA button → én ha-button-node → Node-RED`

Dette gjelder faste operatørhandlinger som Start, Start demo, Lagre målinger, Kjør systemkontroll, Neste, Tilbake, Avslutt og Gjør klar.

## 6. Parameteriserte events

Kriteriekorreksjon, process exception, tidskorrigering, measurement-status, template-editoroperasjoner og Teknisk eksport/notat kan bruke events med payload. Eksakt eventnavn/retning/listener hentes fra `ha_event_registry`.

## 7. Kvittering

Mottatt HA button/event er ikke bevis på DB-commit. Muterende operasjon kvitteres først når persistert resultat/read-model er observerbart. Eksempler:

- Systemkontroll → ny `system_check_run`;
- notat → persistert operation/faktum;
- Lagre målinger → saved/rejected/failed-resultat;
- kriteriekorreksjon/fravik → ny revision/exception synlig i read-model.

Direkte HA-attributter skal ikke inneholde verdier som bryter HA-nodevalidering, særlig nullable interne råfelt.

## 8. SG og operatørinput

Manuell SG-entitet er `number.gjaeringsassistent_malt_sg`. Operatørinput persisteres i relevant MariaDB-draft før faglig operasjon bruker det. Start/Lagre målinger skal ikke bruke synlig HA-state som fallback dersom persisted grunnlag mangler.

## 9. Ekstern målekilde

Tilt-kildene er eksterne HA-entiteter og inngår ikke i Gjæringsassistentens administrerte HA entity-registry. Deres ID-er eies av `measurement_source_profiles`.

Start bruker **Start fra** som history-start. Node-RED leser kildeprofilen, henter HA History til siste komplette 5-minuttersgrense, validerer/normaliserer og fortsetter deretter inkrementelt mens reell session er aktiv. Heartbeat er datadekningssignal.

## 10. Målekildeprojeksjon

`sensor.gjaeringsassistent_malekilde` produseres bare fra MariaDB-read-modelen `v_measurement_source_ha_projection`. Ingest og Systemkontroll kan trigge refresh, men skal ikke bygge konkurrerende status. Projeksjonen skal bruke HA-sikre ferdige attributter og ikke sende nullable interne råfelt.

## 11. Startstatus

`sensor.gjaeringsassistent_startstatus` er operatør-read-model for Start-fremdrift og sluttstatus. Den er ikke domeneautoritet; session/importcursor i MariaDB er fasit.

## 12. Release-/dokumentasjonskontroll

Bootstrap, HA-avstemming, flow/dashboardkontroll, generert kontrakt og dokumenterte maskinfakta skal alle være avledet fra samme MariaDB-metadata. Releaseporten skal oppdage divergens mellom register, fysisk flow, dashboard og generert kontrakt.
## 13. Verifikasjon og UAT

`Verifikasjon` leser bare MariaDB-eide read-models for krav, VER, TEST og siste resultater. TECH/FUNC/UAT-status skal ikke beregnes på nytt i Node-RED eller frontend.

UAT-resultat sendes som parameterisert HA-event og valideres i Node-RED mot registrert aktiv `TEST-UAT-*` før append-only `verification_test_runs`/`verification_test_results` skrives. Verifikasjonseksport sendes som eget event og produserer JSON og HTML fra samme konsistente DB-grunnlag. HTML er presentasjon av dette grunnlaget og skal ikke innføre alternativ status-/coverage-logikk.


## P24r8 publisering og diagnostikk

Oversikt bruker schema 2.5. `analysis.series_definitions` er en ordbok med DB-eide presentasjonsfelt. Punktets `presentation_id` peker på denne; frontend gjør bare oppslag og tegning. Ingen metrikker beregnes i nettleseren. DB velger første, siste, min og maks per segment/serie/visningsintervall. Det kan derfor være mer enn ett faktisk punkt per 30 minutter. Nå-verdier leses fra full serie og påvirkes ikke av punktutvalget.

Publiseringsverktøyet får kun stier til unik stagingfil og målfil. Det lager kompakt JSON og `.json.gz`, verifiserer gzip tilbake mot JSON-bytes og leser publiserte filer tilbake. Filene er reproducerbare presentasjons-/eksportderivater; MariaDB er fortsatt eneste runtime-authority. HTTP-serveren kan forhandle gzip-sidefilen med Accept-Encoding. Dette endrer ikke JSON-URL-en; faktisk HA-levering skal måltestes. Direkte gzip-nedlasting er også mulig.

Normal Teknisk eksport inneholder antall/tidsrom for importerte 5-minuttersrader og gjeldende timepunkter, DB-lagrede visningsvalg samt SHA, størrelse, genereringstid, akser og punkttall for publisert oversikt. Utvidet diagnostikk inkluderer hele det publiserte slanke GUI-grunnlaget. En manglende/ugyldig oversiktsfil registreres eksplisitt som diagnostikkfeil; den rekonstrueres ikke i eksporten.

Publiseringslåsen gjelder bare de reproduserbare JSON/gzip-filene. Samtidige publiseringer etterlater ett konsistent filpar; en eldre oversikt erstatter ikke en nyere `generated_at`. Dette endrer ingen database-transaksjoner eller domeneautoritet. Midlertidige publiseringsfiler har unik identitet per kjøring.

## P24r12: DB-eid HA-payloadkontrakt

`ha_projection_routes` knytter entity, faktisk output-slot og consumer-node til et registrert DB-view. `ha_projection_fields` definerer feltsti, datatype, obligatorisk/valgfritt, tomverdi og fraværsregel. `ha_draft_output_bindings` definerer 32 outputs og konvertering for Start-/målekladd. Inputbindinger, omvendte valg og numeriske grenser følger eksisterende HA-registre.

Start, syv runtime-statusmeldinger og 29 tekniske meldinger produseres i DB-views. Consumerne validerer de registrerte feltene og sender payloaden videre. De erstatter ikke manglende domenefakta med lokale standardverdier. Oppstartsbanen for Start-status er runtime-projeksjon og fysisk kobling kontrolleres mot metadata.

Manglende session-ID eller tidspunkt utelates bare når kontrakten uttrykkelig tillater det; tilgjengelighetsstatus beskriver årsaken. Påkrevde felter må finnes. Notater, hendelser og kontrollresultater skal være JSON-objekter/arrays, ikke JSON kodet som tekst. Eksakt inputvalidering i plugin 0.80.3 brukes i native test. Full HA-transport krever måltest.

## P24r13: felles grafkontrakt

Alle seks grafer leveres i `analysis.graphs`, med DB-projiserte seriedefinisjoner, punkter, akseticks, tidsmarkører, sisteverdier, kriteriekrav og `reference_bands`. `show_in_overview` velger målegrafene i Gjæring; Analyse og rapport bruker samme grafdefinisjoner. `graph_render_policy` leverer obligatorisk geometri og typografi. Manglende policy avvises, uten lokale reserveverdier. SVG-tegneren utfører kun koordinattransformasjon og presentasjon; ingen domeneverdier estimeres. B/P-korreksjons- og vurderingsrader inkluderer `is_unset`.

Grafdefinisjonenes `render_scope` velger dashboard eller report. Begge bruker samme tegner og aksealgoritme. Dashboard følger valgt tidsvindu; rapport bruker hele gjæringen og eventuell valgt sammenligningsserie. Rapporten leser komplette serier selv når dashboardet viser siste døgn.

## P24r15 parameteriserte hendelser

MariaDB ha_event_registry eier disse kanalene; generert contracts/ha-node-red-contract.json, Node-RED-listenere og dashboard følger samme register.

| Hendelse | Felt | Virkning |
| --- | --- | --- |
| gjaeringsassistent_import_historical | ends_at: ISO-8601, operation_id: identitet | Ordinært DB-startgrunnlag med eksplisitt historisk sluttgrense. Krever angitt historisk start, reell målekilde og ingen annen operativ sesjon. |
| gjaeringsassistent_register_historical_phase | kind: biological/process, owner_id, started_at: ISO-8601, operation_id | Registrerer manglende B/P-start i historisk arbeidsøkt innen DB-validerte nabogrenser. |

Oversiktspayload 2.5 har DB-leverte duration_display, duration_seconds, started_display, ended_display i tidslinjene, phase_durations og historical_phase_options. session inkluderer is_historical, historical_ended_at og domain_now. Frontend viser B/P-varigheten direkte. Teknisk publiseringstid er fortsatt faktisk DB-tid; den flytter ikke historisk domenehorisont.


Målekildeprojeksjonen har obligatoriske displayfelt import_counts_display, import_coverage_display og import_summary_display. Oversiktspayload 2.5 har det valgfrie import_coverage-objektet når en operativ kildeimport finnes. Normal historisk status er ikke en transportfeil. Teknisk HA-publisering kvitteres ved den reelle sensor-/binary-sensor-utgangen; metadataenes target-ID følger den tekniske meldingen og inngår ikke i domeneattributtene.

## DB-eide startfelt

Startflaten bruker `v_start_fields` via `sensor.gjaeringsassistent_startstatus.attributes.start_fields`. Verdi, fravær, label, valg, grenser og valideringsmelding leveres av MariaDB. `gjaeringsassistent_set_start_field` sender entity-ID og eksplisitt brukerinput til den registrerte DB-bindingen, også når samme tall tidligere stod i HA. Node-RED leser ingen HA-verdi som reservegrunnlag. HA number/text/select-entitetene beholdes som kompatible inputkanaler; deres lagrede state er ikke kvittering for innholdet i en ny kladd.

Startflaten viser `start_ready` og `start_readiness_message` uten egen domenetolkning. Kontrollene viser tom input/«Ikke angitt» ved DB-fravær. Fokusert, ennå usendt brukerinput er bare flyktig redigering; lagret status kommer ved neste DB-projeksjon.

## Målekilder og sensorer

`gjaeringsassistent_source_settings` mottar `action` (read/check/save) og unik `operation_id`. Save krever `source_profile_id`, `expected_configuration_id`, `fields` og valgfritt notat. Hvert felt inneholder signal_id, input_mode, entity_id (NULL ved manual) og unit_id. DB avviser utdaterte foreldre, ukjent sensor og feil enhet. Check henter HA get_states og lagrer et kontrollert katalogsnapshot. Resultat publiseres atomisk som source-settings.json; save er først bekreftet når samme operation_id finnes i DB-kvitteringen.

Nettleseren kan holde en ulagret redigeringskladd. Den er ikke domenefakta, og bakgrunnslesing skal bevare den opprinnelige forventede revisjonen. Lagret konfigurasjon og gjeldende sesjonsbinding vises separat. Sist kontrollert er HA-verdien fra siste eksplisitte kontroll, ikke en påstått løpende måleverdi.

## Første komplette målesett

Start lagrer ett komplett første målesett i samme transaksjon som sesjon og frosset grunnlag: metode/SG, prøve- og kalibreringstemperatur, manuell temperatur, trykk, kjølemål/-offset, gjærlås, alle sensoriske felt, utfellingstid, konklusjon og notat. Måletid er pitch; faktisk registreringstid og operation-ID beholdes. En senere kladdendring omskriver ikke startobservasjonen. Et komplett manuelt målesett erstatter ikke kontinuerlig tidsseriedekning for et vinduskriterium.

## Teknisk kontrakt for read-model-publisering

Node-RED skriver først DB-read-modellen til en stagingfil. Den eksisterende felles tools/publish_payload.js mottar én JSON-kodet jobb som kommandolinjeargument. Dette er transport av avledede filer; domenefakta forvaltes fortsatt i MariaDB.

| Felt | Betydning | Krav |
|---|---|---|
| stage_path | Absolutt sti til ferdig skrevet stagingfil i runtime/staged | Påkrevd |
| target_path | Absolutt JSON-mål i ha-public | Påkrevd |
| diagnostics_level | summary eller full for teknisk eksport | Valgfritt |

Samme kontrakt brukes for gjæringsoversikt, teknisk eksport og sensorinnstillinger. source_path er ikke et argument i dette grensesnittet. Produsenten skal levere stage_path; publisereren velger ingen alternativ kildefil ved manglende argument. JSON og gzip publiseres og leses tilbake før suksess. Resultatfeil og stderr skal gå til felles feilrapportering slik at de blir synlige i Teknisk hendelseslogg. Den tekniske kontrakten og dens kobling til produsentene prøves i tests/test-p24r8.js.
