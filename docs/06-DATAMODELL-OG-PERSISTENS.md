---
doc_id: DOC-06
role: architecture
status: normative
source_format: markdown
---

# 06 – Datamodell og persistens

**Rolle:** Normativ logisk modell. Fysisk detaljfasit er SQL-filene under `../sql/` og installert MariaDB `INFORMATION_SCHEMA`.

## 1. Autoritet

MariaDB/InnoDB er eneste autoritative persistente sannhetskilde. Fysiske tabell-/viewtall er release-/schemafakta og verifiseres fra SQL/`INFORMATION_SCHEMA`, ikke vedlikeholdes som parallell tekstfasit. Node-RED utfører generiske motor-/integrasjonsoperasjoner mot disse dataene; Home Assistant og frontend er operatør-/presentasjonslag.

Domenefakta skal være eksplisitt normalisert med definert nøkkel, relasjoner og gyldighetskrav. Fravær og frozen faktumomfang skal dokumenteres i strukturerte metadata. JSON/read-model-filer er transport/presentasjon og skal ikke være alternativ runtime-store.

## 2. Registry, template og frozen session

Registry beskriver motorens vokabular: metrics, calculation models, inputs, typed parametere, kriteriemodeller/-roller, targets, actions, målemetoder, gjærprofiler og valideringsmodeller.

En template er et versjonert normalisert aggregat. Publisert versjon er immutable; redigering skjer i draft. Ved Start fryses valgt publisert versjon til normaliserte `session_*`-tabeller med snapshotmetadata/SHA-256. Frozen session omfatter blant annet:

- biologiske faser og prosesstrinn;
- kriterier, typed kriterieparametere, targets og actions;
- metric-runtime-regler, inputs, parametere og outputdomene;
- biological calculations;
- historical replay-policy per prosesstrinn;
- analysegraph/series-metadata;
- målekilde-/valideringsregler som gjelder sessionen.

Aktiv session skal ikke lese senere registry/templateendringer som domenegrunnlag.

## 3. Session, livsløp og revisions

`sessions` inneholder immutable identitets-/startfakta. Livsløp uttrykkes append-only i `session_lifecycle_events`; `session_release_events` frigjør completed session operativt uten å slette historikken. Views utleder current/active state.

Biologiske og prosessuelle forløp modelleres som visits + append-only revisions. Timingkorrigering lager ny revision; tidligere revision overskrives ikke. Current revision er leaf-revision uten etterfølger.

## 4. Manuelle observasjoner

`measurement_input_draft` er mutable arbeidskladd. `record_observation` oppretter et atomisk `observation_round` med revision. Korrigering/deaktivering uttrykkes med ny revision.

Tetthet er SG-only. Manuelle målesett kan inneholde SG/metode/prøvetemperatur/kalibreringstemperatur, manuell temperatur, trykk, kjølemål/-offset, gjærlås, notat og templatevalgte sensoriske 0–5-felt.

## 5. Kontinuerlige målinger og datakvalitet

Ekstern Home Assistant Recorder-history er kildebuffer, ikke domenestore. `measurement_source_profiles` beskriver kilden. Ved Start fryses kilde-/valideringspolicy til session.

Råprøver valideres før autoritativ 5-minutterslagring. Ugyldige prøver forkastes; de clampes ikke til plausible verdier. Kvalitetsutfall lagres separat i `measurement_ingest_quality_events`.

`measurements_5m` inneholder godkjent 5-minuttersgrunnlag. For Tilt-SG er autoritativ verdi robust median av godkjente samples; min/middel/maks er diagnostiske aggregater fra samme godkjente prøvesett. `measurement_data_gaps` er eneste autoritative gaprepresentasjon. `session_measurement_sources` eier binding/importcursor/sist-OK, men cacher ikke åpent gap.

## 6. Evaluering og analyse

Biologiske/prosessuelle evalueringer og kriteriebevis persisteres med `evaluation_status`, actual value, effektivt parametergrunnlag og provenance for datavindu/sample count/dekning/siste sample der relevant. Historisk overgang peker på eksakt `evaluation_id`; current candidate er et separat faktum.

Avledede Analyse-serier persisteres append-only i `analysis_series_values`. Ordinær status krever frozen minste tid, antall, dekning og modellgrunnlag samt gyldig input/outputdomene og gapregler. P24r7 publiserer ikke foreløpige verdier. Ugyldig/manglende grunnlag er fravær av autoritativ verdi, aldri syntetisk `0`. Avviste beregnede outputs registreres separat i `analysis_validation_events`.

## 7. Recommendations, korreksjoner og fravik

Recommendations, operator resolutions, kriteriekorreksjoner og prosesskriteriefravik er egne historiske fakta. Superseded/current status utledes fra nyere fakta; eldre rader omskrives ikke.

## 8. Teknisk historikk og systemmetadata

`technical_events` lagrer tekniske hendelser og issue raise/clear. `v_active_technical_issues` utleder åpne problemer. `system_check_definitions`, `system_check_expectations`, `system_check_runs` og `system_check_results` eier Systemkontrollkatalog/forventning/historikk.

HA-kontrakten og funksjon↔informasjon-lineage eies av normaliserte registre som `ha_entity_registry`, `ha_event_registry`, `system_functions`, `information_objects` og `function_information_dependencies`. Fysiske tabeller/views katalogiseres fra `INFORMATION_SCHEMA`; det skal ikke finnes en separat manuelt vedlikeholdt liste over alle DB-objekter.

P23-verifikasjon skiller mellom metadata og faktiske resultater. Krav, beslutninger, VER-definisjoner, TEST-katalog og mange-til-mange-relasjoner ligger i normaliserte `verification_*`-metadataobjekter. `verification_test_runs` og `verification_test_results` er append-only historiske fakta for faktiske TECH/FUNC/UAT-gjennomføringer. DB-views utleder gjeldende status og ufullstendige koblinger; dashboard/Node-RED skal ikke rekonstruere statusen.

## 9. Current-state og read-models

Current state er avledet fra persistente fakta. Viktige grupper er:

- session/lifecycle/current visits og revisions;
- overgangsbevis og current candidate-evaluering;
- criterion read-models med ferdige `actual_display`, `requirement_display`, `status_display`, `data_window_display`;
- measurement-source status/HA-projection;
- active report read-models;
- Analyse graph/series/requirement/marker read-models;
- metadata-lineage og systemkontroll-read-models.

Frontend skal vise disse uten å etablere alternative domeneregler eller fallback.

## 10. Concurrency

InnoDB håndterer normal samtidighet med MVCC, constraints og korte transaksjoner. Systemet skal ikke bruke global writer-kø, applikasjonsstyrt serialisering eller `SELECT ... FOR UPDATE`/`GET_LOCK` som normalmekanisme.

## 11. Mutable unntak

Mutable arbeidsflater er eksplisitte: `session_setup_draft`, `measurement_input_draft` og upublisert template-draft. De er editor-/inputflater, ikke journal/historikk.

## Templateadministrasjon

`template_editor_state` er den delte, persistente UI-/arbeidsflytpekeren for hvilken templateversjon Template-fanen administrerer. Den er eksplisitt adskilt fra `session_setup_draft`, som eier Start-valget. `template_versions.status` bruker `draft`, `published` og `retired`; retired versjoner beholdes og kan reaktiveres.


## Analyse- og operatørmetadata

`template_analysis_graph_series` og frozen `session_analysis_graph_series` eier `provisional_allowed`, minste antall/tidsutstrekning, `band_model`, båndbeskrivelse/opasitet, standard-/foreløpig farge og linjestil. `analysis_series_values` lagrer `value_status=provisional|standard`, modenhetsflagget, antall punkter, forespurt vindu og faktisk dekning sammen med hovedverdi og eventuelt meningsfullt spenn. Disse radene er append-only. Legacy-felter for foreløpig stil og bånd er beholdt i skjemaet; alle operative p24r7-analyser har provisional_allowed=0 og band_model=none.

`template_overview_graph_policy` fryses til `session_overview_graph_policy` og bestemmer om SG-/temperatur-/trykkspenn tegnes. `v_session_analysis_series` leverer statuslabel, basislabel og faktisk stil, mens felles tidsakse og akseticks leveres som read-model-felt.

`biological_criterion_exceptions` journalfører bekreftede biologiske kriteriefravik; evalueringen peker med `applied_exception_id` på håndteringen og beholder det opprinnelige råresultatet. Biologiske og prosesskriterier har frozen `exception_allowed` og eksplisitte korrektable parameterrelasjoner.

## Kvalifisert kalibrering og analysegrunnlag

`session_calculation_baselines` lagrer baselineverdi, kvalifiserende målevindu, antall punkter, måletid og kilde. Nøkkelen er session, beregning og effektiv pitch. Dette er kompatibilitets-/diagnostikkfakta. Operativ p24r7-AA og SG-fall bruker faktisk OG og faktisk SG uten baselinekalibrering; rate bruker målte endepunkter. Korrigert pitch lager eget append-only analysegrunnlag.

Analyseverdier og avvisningsfakta har `basis_pitched_at` i sin identitet. Gjeldende read-model filtrerer på effektiv pitch, mens tidligere beregninger beholdes. Gjentatt evaluering av samme grunnlag er idempotent. `v_current_metric_value` leser analyseserier og viser manglende grunnlag når verdien er foreldet eller en nyere hovedverdi er avvist.

Kriterierevisjonenes parameterverdier har `is_unset`. Ved `is_unset=1` er alle typed value-kolonner NULL; ellers kreves akkurat én typed verdi. Dette lar en valgfri grense fjernes uttrykkelig uten å tolkes som 0. Evaluerings- og rapportmodellene bevarer denne forskjellen.

Manuelle analysepunkter peker med FK på source_observation_revision_id; basis_revision_key inngår i den append-only identiteten. Read-modelen viser bare aktive gjeldende observasjonsrevisjoner. Ny SG/tidsrevisjon endrer aktuell graf og sisteverdi uten å omskrive tidligere beregninger.

## HA-statistikk og datasettvalg

`measurement_statistics_hourly` beholder start/slutt og HA sine faktiske min/gjennomsnitt/maks-verdier. Identiske importer dedupliseres; endrede HA-verdier blir en ny append-only revisjon. Ingen prøveantall eller median konstrueres. `measurement_gap_closures` lukker rådata-gap append-only. `graph_display_selection_events` og `demo_profile_selection_events` lagrer valg i MariaDB; demoens kilde fryses i `session_demo_sources` ved Start.

Tekniske hendelser har en DB-sekvens som avgjør rekkefølgen når to meldinger har likt millisekundstempel. Hver Systemkontroll får en UUID og alle 15 resultater lagres i én transaksjon med rollback-handler. HA-entiteter kontrolleres med en fersk `get_states`-forespørsel.

## SQLite-arkiver fra p24r10

Fanen **Template og arkiv** har et eget arkivkort. Velg `-template.sqlite` og, ved gjæringsimport, tilhørende `-gjaering.sqlite`. Kontroller forhåndsvisningen før import. Filenes format, skjema, integritet, transportkontrollsum og sammenhørende manifest kontrolleres. Domene-FK-er og CHECK-er håndheves under selve importtransaksjonen. Feil vises i arkivkortet og ruller tilbake både template og sesjon.

Filene navngis `session-<sessionid>-export-<exportid>-gjaering.sqlite` og `session-<sessionid>-export-<exportid>-template.sqlite`. Template-filen inneholder én original publisert versjon, med nødvendig registergrunnlag. Gjæringsfilen har normaliserte målinger, timedata, frozen grunnlag, vurderinger, korreksjoner, observasjoner, overgangshistorikk og beregnede fakta. Den inneholder ikke mutable UI-valg eller globale systemfeil. Kildeversionens ID bevares som kildeproveniens; andre templates i en versjonskjede importeres ikke.

Importert original er skrivebeskyttet i sin egen kategori. Bruk **Opprett ny template fra eksisterende versjon** med ny ID og navn for å lage en egen redigerbar kopi. Samme importoperasjon gjenbruker sin kvittering; samme gjæringsarkivpar importeres én gang. Separate template-importer får egne unike IDs også når navn og kildeversjon er like.

Import er tillatt mens gjæring pågår. Filkontroll og SQLite kjører i en worker thread; en egen forbindelse til den samme MariaDB-instansen eier hele importtransaksjonen. Den ordinære motorens mysql-node og autoritative dataflyt beholdes. Dette er en avgrenset filoverføringsadapter, ikke en ny beregnings- eller rapportmotor. Ingen manuell kø, fil-lås eller lokal domenestate innføres.

Midlertidig filopplasting går som autentiserte HA-hendelser med 64 KiB deler og DB-kvittering. Disse byte-delene er transport, ikke domenelagring. Maksimal filstørrelse er 512 MiB. Historikk blir tilgjengelig i sammenligningslisten etter import; **Skjul fra sammenligning** legger til en synlighetshendelse og sletter ingen data. Bare eksplisitt støttede eldre SQLite-skjemaer konverteres; ukjente, uvedkommende og fremtidige formater avvises. Tidligere JSON-arkiver konverteres ikke i denne versjonen.

Alle runtime-søk og grafer bruker MariaDB etter import. Filstørrelsen bestemmes av faktisk historikk; SQLite fjerner JSONs gjentatte feltnavn, men gir ingen garanti om en bestemt komprimeringsfaktor. Alle eksisterende målepunkter beholdes i arkivet.

## P24r11 sletting og startstatus

Append-only gjelder faglige fakta og revisjoner **innenfor en sesjon som beholdes**. Hele historiske lokale eller importerte sesjoner kan fjernes fra MariaDB i én transaksjon. Tilhørende målinger, forløp, korreksjoner, notater og operasjonsspor slettes samlet. Gjeldende sammenligningsvalg byttes til Ingen. Aktive sesjoner kan ikke slettes. Importert template kan slettes separat når den er ubrukt, eller sammen med sesjonen dersom andre sesjoner/egne templates ikke refererer til den. Eksportfiler utenfor databasen beholdes.

`v_session_start_status` utleder startstatus fra gjeldende sesjon, demomålinger og historikkimportens DB-markører. Home Assistant får denne projeksjonen etter livsløpsendringer og hvert tiende sekund. En gammel HA-status som starting etter klargjøring oppdages også av Systemkontroll. Ingen domenestatus lagres i Node-RED-minne.

`archive_import_candidates` er midlertidige fil-/manifestvalg; `archive_checksum_warnings` er synlige transportadvarsler. De er ikke runtime authority for gjæringen.

## P24r12: fravær, normalisering og fysisk katalog

`sessions` lagrer felles pitchfakta. `session_dry_pitches` lagrer påkrevd tørrgjærmengde; `session_slurry_pitches` lagrer påkrevd slurryvolum, kilde og generasjon. Sammensatt FK til sesjon/pitchmodus og livsløpstrigger sikrer korrekt subtype før aktiv gjæring.

SQL-NULL er tillatt når et faktum faktisk ikke finnes: arbeidskladd ikke fullført, måling ikke tilgjengelig, hendelse ikke inntruffet, første revisjon uten forgjenger, valgfri opplysning eller irrelevant alternativ i en typevelger. Det betyr aldri tallet 0. Påkrevde input avvises før bruk. HA får obligatoriske status-/tilgjengelighetsfelter og utelater valgfrie utilgjengelige råfelt etter den registrerte kontrakten.

`schema_relation_semantics` beskriver faktumets nøkkel, omfang og normaliseringsbegrunnelse. `schema_absence_semantics` beskriver hvert nullable tabellfelt. `v_schema_column_catalog` leser faktisk type, nullbarhet og default fra INFORMATION_SCHEMA. Den fysiske katalogen og viewkolonnene eksporteres ved native releasekontroll; de er genererte inspeksjonsartefakter, ikke en ny runtime-authority.

Frozen template-/sesjonsfakta beskriver en historisk definisjon med eget nøkkelomfang. De skal bevares selv om dagens register endres. Typed parameterrelasjoner bruker en eksplisitt typevelger og én relevant verdikolonne, kontrollert med CHECK/FK. Dette er dokumenterte representasjonsvalg. En komplett katalog er ikke i seg selv et formelt normalformbevis.

Begge application_version-markører oppdateres fra VERSION av installeren. Nye arkiver bruker SQLite format 2; v1-pitchkolonner konverteres til subtypefakta ved import uten å fylle inn ukjente verdier.

## P24r13: seks grafer og eksplisitt vurderingsfravær

`template_analysis_graphs`/`template_analysis_graph_series` og de frosne `session_`-relasjonene beskriver nå også SG, temperatur og trykk. Kildetype angir metric, kriterium, measurement, comparison, observation, process_target eller fermentation_target; renderer trenger ingen graf-ID-regler. Planpunkter kommer fra DB-planfakta, mens measurement/observation bare bruker faktisk lagrede målinger. `graph_render_policy` er ett globalt register for presentasjon, med obligatoriske dimensjoner og skriftstørrelser.

B/P-vurderingenes parameterrelasjoner har eksplisitt `is_unset`. En angitt verdi har nøyaktig én typet verdi; en ikke angitt verdi har ingen. Fravær lagres aldri som numerisk 0. `legacy_measurement_graph_models` og `legacy_measurement_graph_series_models` er et formatkonverteringsregister for eldre arkiver, brukt av `ga_convert_legacy_archive_graphs` i importtransaksjonen, ikke en runtime-fallback. Eksisterende arkivpolicy bevares ved konvertering. 


Lesepolicy og publiseringskvitteringer er tekniske fakta: policyverdier tilhører policy-ID, og kildehash/genereringstid/publiseringstid tilhører den unike publiseringsoperasjonen. Kvitteringene inneholder ingen domeneverdier eller kopier av grafer. 

## P24r15: historisk vindu og fasetid

Runtime-schema er 11, template-schema er 4. session_history_windows er et valgfritt sesjonssubtypefaktum med obligatorisk ended_at, operation_id og created_at. Start finnes bare som sessionens pitchfaktum/revisjon. En ordinær sesjon har ingen historisk subtype, ikke en oppdiktet sluttdato. Gjeldende tabell-/viewantall følger migreringsmanifestet og faktisk native katalogopptak.

v_all_session.domain_now er historisk slutt, faktisk ferdigstilling for avsluttet ordinær sesjon, ellers DB-klokken. Importcursor bestemmer hvor langt en uferdig historisk import kan vurderes. v_process_visit_timing og v_biological_visit_timing bruker gjeldende startrevisjoner og neste start som slutt. ended_at i rå visitrevisjoner er det registrerte lukkefaktumet på revisjonstidspunktet; effektiv tidslinje leses fra timing-views og kan derfor endres uten omskriving av gamle lukkefakta. DB-korreksjonen avviser kryssing av naboer og sesjonsgrenser. v_phase_duration_presentation summerer visits per B/P-eier, også gjentatte prosesstrinn.

Historisk etterregistrering er et datert operatørfaktum. Det hevder ikke at kriterier var oppfylt eller at automatisk overgang fant sted. Opprinnelige evalueringer og overgangsbevis beholdes. Forbindelsens midlertidige lesetabeller og publiseringskontroll fra r14 videreføres; ingen domenecache legges i Node-RED.


`measurement_source_check_policy` er normalisert klassifiseringsmetadata med nøkkel source_state og obligatorisk kontrollstatus/alvorlighet. `v_session_import_coverage` er en avledet opptelling, ikke en ny persistent målekopi. `v_measurement_source_system_check` kobler registrert policy med faktiske datagrunnlag. HA-publiseringsfeil/-kvitteringer er ordinære append-only Technical Events, ikke et alternativt session-state-lager.

## Startkontrakt og migreringsjournal

`start_field_rules` og `start_field_pitch_modes` utvider HA-inputregistrene med normalisert krav/tilhørighet. `v_start_fields`, `v_start_issues` og `v_start_readiness` leser aktuelle kladdverdier og registrerte grenser. `ga_read_start_context` lagrer ett startforsøk og feltvise snapshots i `session_start_attempts` / `session_start_attempt_fields` før det samme konsistente grunnlaget returneres til motoren. NULL betyr at input faktisk manglet; det blir ikke 0. `database_migrations` journalfører utført migrering og kildeavtrykk. `installer/migrations.json` eier støttede oppgraderingsbaner; DB-ledgeren eier installasjonens faktiske utførelseshistorikk.

Startforsøk som tilhører en eksplisitt slettet ubrukt template følger denne slettingen gjennom FK-kaskade, inkludert feltvise snapshots. De blokkerer derfor ikke den avtalte oppryddingen av importerte templates. Beholdte sesjoner og deres frozen grunnlag endres ikke.

## Normaliserte målekilder

Signaler/enheter ligger i measurement_source_signals / measurement_source_units. Konfigurasjoner er en ubeskåret revisjonskjede per profil med én forelder og unik etterfølger; bindinger ligger i measurement_source_signal_bindings. Sesjonskopier i session_measurement_source_configurations / session_measurement_signal_bindings er uavhengige av den globale revisjons-ID-en og følger SQLite-arkivet. En konfigurert sensor er et eksplisitt entity-ID/enhet-par. Trykk kan være manual med NULL entity-ID. Ikke konfigurert sensor er reelt fravær, ikke 0 bar.

HA-katalogen er en muterbar teknisk cache med egen kontrollhistorikk. technical_components eier presentasjonsnavn uten å endre technical_events. ha_entity_number_constraints.display_decimals eier inputformat; selve måleverdien beholder sin kolonnetype/presisjon. Migrering av gamle sesjoner starter kildehistorikken ved deres lagrede importcursor; eldre bytter kan ikke rekonstrueres.
