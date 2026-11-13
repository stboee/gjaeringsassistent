---
doc_id: DOC-09
role: verification
status: normative
source_format: markdown
---

# 09 – Akseptansetest

**Rolle:** Gjeldende normativ måltest for installert release og reelle integrasjoner.

## 1. Installasjon og oppstart

1. Installer på tom database eller oppgrader en støttet kilde med databevaring. Schema, seed, flow og frontend skal fullføre uten FK-/SQL-feil.
2. Node-RED skal starte uten vedvarende Technical-feil.
3. Automatisk Systemkontroll skal fullføre etter oppstart og vise eksplisitt resultat for database, schema, HA-kontrakt, konfigurasjon, lineage og frontendpublisering.

## 2. Template og Start-grunnlag

1. Velg publisert W-34/70-template.
2. Endre minst ett pre-Start-felt og verifiser at restart/refresh gjenskaper verdien fra MariaDB-draft, ikke fra lokal Node-RED-state.
3. `Start fra` skal være eksplisitt dato/tid og persisteres i MariaDB.
4. DB-konfigurert målekilde skal være synlig i Teknisk.

## 3. Start gjæring

1. Trykk `Start gjæring` én gang. `sensor.gjaeringsassistent_startstatus` skal umiddelbart vise `starting` / fase `Mottatt`.
2. Technical Event-historikken skal inneholde `START_REQUESTED` med korrelert `operation_id`.
3. Hvis startgrunnlaget er ugyldig, skal Start vise konkret avvisningsårsak og `START_REJECTED` skal være sporbar.
4. Hvis MariaDB-feil oppstår i startgrunnlag eller starttransaksjon, skal samme feil være synlig i startstatus og Technical; kommandoen skal ikke forsvinne taus.
5. Vellykket Start skal opprette én aktiv session, frozen template/sessionplan og `session_measurement_sources` for reell session.

## 4. HA-history, datagap og live

1. Start reell session med `Start fra` i fortiden. SG, temperatur, heartbeat og RSSI skal hentes fra entity-ID-er i `measurement_source_profiles`.
2. Komplette data skal normaliseres til 5-minuttersbøtter i `measurements_5m`.
3. Heartbeat-fravær skal registreres i `measurement_data_gaps`; systemet skal ikke interpolere SG/temperatur over gapet.
4. `last_import_cutoff_at` skal flyttes frem for hver vellykket chunk.
5. Etter historisk catch-up skal aktiv-session-styrt 5-minuttersimport fortsette fra samme persisterte cursor.
6. Restart Node-RED under aktiv session og verifiser at importen fortsetter fra MariaDB-cursor uten duplisert domenestate.

## 5. Sekvensiell B/P-replay

1. Bruk en historisk serie som dekker flere biologiske/prosessuelle overganger.
2. B-replay skal bare vurdere neste B-fase av gangen og persistere hver visit/transition ved første historiske kriteriekryssing.
3. P-replay skal bare vurdere neste aktive P-trinn av gangen. Når required-kriteriene første gang er oppfylt, kan append-only `process_transitions` med `action='backfill'` bare opprettes dersom det aktuelle frosne session-trinnet har `historical_replay_auto_transition_allowed=1`.
4. For W-34/70 skal historisk replay kunne etablere P1/P2, men ikke P3 eller senere. P3 kan bli vurdert som klar, men aktivt prosesstrinn skal forbli P2 til operatøren trykker `Neste`.
5. En historisk P-vurdering skal ikke bruke observasjon eller biologisk tilstand fra et senere tidspunkt.
6. Dokumenterte datagap skal bryte stabilitets-/persistensvinduer slik frozen kriterier angir.
7. Etter catch-up skal neste ordinære P-overgang fortsatt kreve operatørens `Neste`; live-motoren skal ikke automatisk hoppe videre.

## 6. Målinger og operatørhandlinger

1. `Lagre målinger` skal lese `measurement_input_draft`, persistere ett komplett observation/revision-sett og gi eksplisitt saved/rejected/failed-kvittering.
2. Korrigering av måletid, pitchtid, B-start og P-start skal opprette nye revisions uten å omskrive historiske timestamps.
3. Kriteriekorreksjon og process-exception skal bevare frozen templateverdier og opprette session-eid revision/fakta.
4. `Neste` og `Tilbake` etter live/catch-up skal opprette append-only visit/transitions; Tilbake krever advarsel, ikke obligatorisk begrunnelse.

## 7. Session-livsløp og historikk

1. `Avslutt gjæring` skal appendere completed lifecycle og lukke åpne visits via nye revisions.
2. Completed session skal generere verifisert SQLite-par og lesbar HTML-rapport.
3. `Gjør klar` for reell session skal kreve verifisert completed-arkiv og appendere release-faktum uten å slette sessionhistorikken.
4. Under aktiv gjæring skal `Generer rapport` lage et HTML-snapshot fra MariaDB/read-model uten lifecycle-endring. Rapporten skal minst dekke sammendrag, SG-/temperaturforløp, B/P-forløp, målinger/sensorikk, kriterievurderinger, kriteriekorreksjoner/-avvik, prosesstransisjoner, datagap, kronologi, notater og operatørhandlinger.
5. Historisk rapport skal være read-only.

## 8. Arkitekturkontroller

1. MariaDB skal være eneste persistent authority; måltesten skal ikke avhenge av `flow.*`, `global.*`, HA-state eller frontend-fallback som domenefasit.
2. Manglende nødvendig frozen regel/input/parameter skal gi `invalid_configuration`, ikke oppdiktet verdi.
3. `v_metadata_lineage_gaps` skal ikke rapportere required producer/consumer-brudd.
4. `v_function_producer_consumer` skal være avledet fra `function_information_dependencies`; ingen separat producer/consumer-sannhet skal finnes.


## 9. Evalueringshorizon og overgangsbevis

1. Under delvis HA-history-import skal B/P-current evaluation bruke persistert `last_import_cutoff_at`, ikke faktisk veggklokke.
2. En passert B/P-fase skal i GUI vise kriteriene fra akkurat `transition.evaluation_id`, selv om en annen vurdering av samme kandidat ble opprettet senere eller har et nyere `evaluated_at`.
3. Når ingen evaluatorrad ennå finnes, kan neste ordnede kandidat utledes fra frozen sessionplan, men status skal være `not_evaluated`; ingen kriterieverdi kan diktes opp.
4. Historisk P-replay skal hoppe over disabled/reserve-slots.
5. Etter catch-up skal `live_ingest` ikke automatisk gjennomføre P-overgang.
6. Målekildekortets `last_import_cutoff_at`, `last_success_at` og `updated_at` skal være DB-verdier, og samme DB-read-model skal brukes ved ingest-refresh og Systemkontroll-refresh.


## 10. Datakvalitet og Analyse

- Målekilde/Tilt-panelet skal endre siste bøtte/import/sist OK etter nye 5-minuttersimports selv om sensorens state fortsatt er `LIVE`; displaytid skal være `Europe/Oslo`.
- Hver Analyse-graf skal vise B/P-kriterier, krav/rolle og første oppfyllelsestid fra samme requirements-read-model som terskellinjer/markører.
- I redigerbar template-draft skal ubrukte registry-kriterietyper ligge i dropdown og ikke som permanente tomme matriserader; `Vis kriterietype` + `+` skal opprette kriterium i valgt celle, og sletting av siste forekomst skal gjøre typen ubrukt igjen.

Akseptanse omfatter også at en avledet metric utenfor sitt frozen `valid_minimum_value`/`valid_maximum_value` avvises før både B/P-kriterievurdering og `analysis_series_values`. Testen skal dokumentere at ingen overgang kan utløses av den ugyldige verdien og at verdien ikke clampes.


- Injiser/observer en åpenbart ugyldig Tilt-prøve i testgrunnlaget: prøven skal ikke påvirke `measurements_5m`; kvalitetsutfallet skal være sporbart.
- Kontroller at et langt/registrert datagap ikke utløser max-jump-avvisning av første ellers gyldige bøtte etter gapet.
- Kontroller at analysekurver er tomme frem til deklarert warm-up/sample/coverage er oppfylt, fremfor å starte med `0`.
- Kontroller at derived output utenfor frozen gyldighetsdomene ikke persisteres i `analysis_series_values`.
- Kontroller at de tre W-34/70-grafene for tilsynelatende utgjæringsgrad, signert SG-rate og SG-stabilitet kommer fra frozen sessionmetadata, at y-akse/ticks og `+dag · dato` kommer fra DB-read-model, og at headerforklaring/krav/markører følger samme grunnlag.
- Kontroller at HA-målekildesensoren kan publiseres både før Start, under catch-up og i LIVE uten nullable-attributtfeil.
- Kontroller at Systemkontroll kjøres på nytt etter Start og overgang til LIVE, og at uncaught runtimefeil blir synlige som `runtime_issues`.

## 11. Strukturert verifikasjon og UAT

Akseptansetestene representeres i p23 som stabile `TEST-UAT-*`-objekter koblet til relevante VER/REQ. UAT-resultater er append-only fakta med test, releaseversjon, tidspunkt, resultat (`pass/fail/blocked/not_run`), operatør og eventuelt notat/evidence.

Minstekontroll for p23r2:

1. `TEST-UAT-009`: Verifikasjon-fanen skal vise DB-eide REQ→VER→TEST-relasjoner og kunne registrere et UAT-resultat som et nytt run/result uten å overskrive tidligere historikk.
2. `TEST-UAT-010`: verifikasjonseksport skal produsere både JSON og selvstendig HTML fra samme DB-grunnlag; status skal samsvare med dashboardets DB-read-model.
3. `TEST-UAT-011`: med aktiv reell session skal full vertsmaskin-/containeroppstart i vilkårlig MariaDB/Node-RED/HA-rekkefølge rekonstruere samme session, B-fase, P-trinn og målekilde fra MariaDB uten ny Start. Etter HA-reconnect skal HA-projeksjoner repopuleres, og live-import skal fortsette fra persistert cursor uten duplisert domenhistorikk.
4. Teknisk-fanen skal vise kompakt verifikasjonsstatus uten å beregne egen status/coverage.
5. Manglende relasjon eller autoritativ status skal vises som manglende/ikke verifisert grunnlag, ikke fylles med frontend-/Node-RED-default.


## 12. P24-kriterier, oppstartsanalyse og grafsemantikk

1. Klon W-34/70 til draft og ny template. Verifiser utgjæringsintervall, alle kriterier og analysemetadata. Endre rettigheter for ett B- og ett P-kriterium, publiser og Start; sessionen skal bruke det frosne valget.
2. Korriger et tillatt biologisk kriterium. Registrer et bekreftet fravik med tomt notat. Direkte fasesetting skal være borte; original vurdering, faktisk `met/not_met` og håndteringen skal kunne spores hver for seg. Prøv tilbaketrekking før overgang og kontroller ny vurdering.
3. Ved tidlig import skal rate/stabilitet mangle til frozen minste tid/dekning er oppfylt. Ingen foreløpig kurve eller estimert bånd skal tegnes.
4. Kontroller at SG-stabilitet har to generelle 24/48-timerskurver og relevante kriterieterskler, ingen min–maks-envelope, og dynamisk Y-akse. SG-/temperatur-/utgjæringsbånd og rate-spenn skal følge datamodellens beskrivelse.
5. Sammenlign alle grafer i dashboard, aktiv rapport og sluttrapport: X starter ved effektiv pitch, tom oppstart er synlig og persisterte gap bryter både linje og bånd. Korriger pitchtid og kontroller alle tre flater igjen.


## 13. Inntasting, Systemkontroll og teknisk nedlasting

1. Etter installasjon på MariaDB 12.3.3: kjør Systemkontroll og kontroller schema, templateantall og metadata/lineage. Kontroller at Gjæring har de publiserte templatealternativene før Start.
2. Skriv i template-draft, ny template-ID/navn og publiseringsetikett over minst én refresh-periode. Tekst, fokus og markør skal beholdes. Prøv Oppdater med ulagrede draftendringer; teksten skal ikke forkastes.
3. Last ned både manuell Teknisk-eksport og siste automatiske status to ganger. Alle nedlastingsnavn skal starte med lokalt timestamp og eldre nedlastinger skal bevares.
4. Kontroller at den nye JSON-filen har aktuell eksporttid og viser samsvarende DB-/Node-RED-/frontend-release, faktisk MariaDB 12.3.3, `utf8mb4_unicode_ci`, publiserte templateversjoner og HA-valgets options. Aktive problemer og historiske oppklarte hendelser skal kunne skilles fra hverandre.

## 14. Kalibrering, løpende status og korreksjon

1. Start med faktisk OG og senere Tilt-data uten målinger nær pitch. Rå Tilt-utgjæring skal være tilgjengelig, med eksplisitt ukalibrert kilde.
2. Registrer korrigert manuell SG. Kontroller separat punkt og siste-verdi-tekst, med manuell måletid; ingen mellomliggende manuelle verdier.
3. Ved flat SG skal dagens rate være nær 0 med fersk måletid; gamle B-overgangsvurderinger skal fortsatt ha sitt historiske tall. Foreldet import skal vise utilgjengelig aktuell rate.
4. Kontroller én AA og estimert ABV nå, raw Tilt-SG, gjær/volum/OG, varigheter og neste prosesstrinns årsak/tid i Aktiv gjæring. Rapport og genereringsknapp skal ligge nederst. Pitch- og observasjonstidskorreksjon skal være to separate funksjoner under Måleresultater.
5. Tøm valgfri maksimalgrense/alder: den skal lagres som ikke angitt. Ugyldig intervall, nulltall i positiv alder og manglende obligatorisk felt skal avvises før lagring; beregnbar faktisk verdi skal fortsatt kunne leses ved ugyldig kriteriekonfigurasjon.
6. Korriger pitch og kontroller at aktuelt analysegrunnlag endres uten at de tidligere faktaene slettes. Kontroller Systemkontroll mot installert schema, templatevalg, inntasting under automatisk refresh og tidsstemplede tekniske nedlastingsnavn.

## P24r7 målmiljøkontroll

1. Velg hver av de tre publiserte templatene før Start. Kontroller temperaturmål, utgjæringsområde, gjærmengde og P7 enabled-policy i templateeditoren.
2. Start uten tilgjengelig femminuttersmåling. Startstatus skal ikke gi HA-valideringsfeil for null `latest_measurement_5m`.
3. Kontroller begge AA-kilder og siste-verdi-feltet over alle tre Analyse-grafene. SG-rate har Y-min 0; negativ rate skal fortsatt stå som negativ i siste-verdi-feltet. Manuelle punkter forbindes ikke.
4. Avslutt en reell session med stort arkiv. Begge SQLite-filer og HTML skal få verified-resultat med byteantall og SHA-256, og historikklenkene skal åpne de registrerte filene. DB-grensen skal ikke økes.
5. Ved fil-/verktøyfeil skal gjæringen fortsatt være completed, med vedvarende arkivfeil i Systemkontroll. Forsøk arkivering på nytt skal gi nytt attempt/resultat og ikke en ny Avslutt-hendelse. Gjør klar skal lykkes etter verified. Registrer TEST-UAT-012/013.

## P24r7 målmiljøkontroll

1. Installer rent, kjør Systemkontroll to ganger raskt og bekreft tabell-/view-/InnoDB-antall fra gjeldende migreringsmanifest og 15 resultater per kjøring. Fersk HA-entitetskontroll skal finne arkiveringsknappen.
2. Start fra 25.09.2026 kl. 22:00. Bekreft at eldre timer fra HA-statistikk vises også uten tidsstempelsensorens gamle historie. Ingen kunstige femminuttspunkter skal oppstå. Fjern tilgang til statistikk midlertidig: rådata skal fortsette, og feilmeldingen skal lukkes når tilgangen kommer tilbake.
3. Velg hver demo, kontroller navn og start. Sammenlign med det andre datasettet og en avsluttet gjæring. Bekreft dag-0-justering, kildemerking, egne analysetall, delte/persistente valg og 24/48 timer/7 dager/hele gjæringen.
4. Avslutt: visningen skal umiddelbart gå til Gjæring avsluttet. Ved verifisert eksport skal retry-knappen være skjult. Ved eksportfeil skal nytt forsøk være tilgjengelig og Gjør klar sperret. Etter verifisering skal Gjør klar fungere.
5. Generer aktiv rapport og sluttrapport. Begge skal ha kronologisk oversikt og eldre timesdata; et kort dashboardvindu eller sammenligningsvalg skal ikke kutte rapporten.

## P24r9 målmiljøprøver

- Velg Gyllen pils under Sammenlign med. Kontroller at oransje sammenligningskurve vises og valget består etter flere automatiske oppdateringer. Prøv også demovalg og Ingen sammenligning.
- Etter første import: la normal live-innhenting gå minst tre femminuttersrunder. Det skal ikke komme nye «HA langtidsstatistikk er hentet»/RECOVERED-meldinger. Ved reell API-feil skal årsaken være synlig og én senere gjenoppretting lukke den.
- Korriger en terskel på Biologi og Prosess. Sjekk kravtekst/linje i Analyse og aktiv rapport. Fjern en valgfri grense og tilbakestill. Originalkravet skal da vises igjen; eldre oppfylt-markering fra annen revisjon skal ikke overføres.
- Korriger et stabilitetsvindu og kontroller at kravet vises ved riktig vindusserie. Historiske målinger/evalueringer skal være bevart.

## P24r10 måltest

1. Åpne Template og arkiv. Kontroller system/egen/importert-kategorier og filvalg på den faktiske HA-adressen (også ved HTTP).
2. Eksporter en avsluttet gjæring; last ned begge SQLite-filer og åpne den registrerte HTML-rapporten i Historikk. Importer paret mens en annen gjæring pågår; kontroller at målekilden og grafene fortsetter å oppdateres.
3. Velg importert gjæring i sammenligningslisten; kontroller begge dataseriene. Skjul og vis den igjen.
4. Importer en template og kopier den med ny egen ID. Kontroller at originalen forblir skrivebeskyttet og systemtemplates er uendret.
5. Avslutt gjæringen. Kontroller at Gjør klar vises først når arkivet er verifisert, og at arkivering under behandling ikke fremstår som en systemfeil.
6. Se IPL og Gyllen i sammenligning: ulike måleserier, datoer under grafene og datomarkører i HTML-rapport.

## P24r11 tillegg til TEST-UAT-014

1. Start original IPL-demo, avslutt, gjør klar, velg template og kontroller at ordinær Start er tilgjengelig. Start en ordinær gjæring og kontroller startstatus etter omstart av Node-RED.
2. Under aktiv gjæring: eksporter øyeblikksbilde fra øverste arkivkort. Last ned to SQLite-filer, to SHA-filer og HTML. Bekreft at aktiv gjæring og måleinnhenting fortsetter.
3. Velg arkivfilene samlet. Kontroller liste etter template-navn, bytt mellom bare template og template med data, og vent flere automatiske oppdateringer. Valgene skal beholdes.
4. Prøv manglende SHA, feil SHA og uleselig SHA. Advarsel skal vises før import, og import skal fungere. En skadet SQLite eller feil gjærings/template-par skal avvises.
5. Importer for sammenligning. Velg den importerte sesjonen i Analyse. Slett sesjonen og kontroller at valget går tilbake til Ingen og at sesjonen forsvinner fra databasen. Slett ubrukt originaltemplate separat eller sammen med sesjonen. Kontrollér at en brukt template ikke kan slettes og at eksportfiler beholdes.

Disse stegene krever målmiljøet Home Assistant/Node-RED. Lokale MariaDB- og VM-tester erstatter ikke denne UAT-en.

## P24r12 måltest etter installasjon

Lokal SQL/plugin-test erstatter ikke denne måltesten. Åpne Gjæring uten aktiv sesjon: velg en vanlig template og kontroller at normal Start vises. Start, vent på import, kontroller status og målegrafer. Prøv et notat og Systemkontroll uten valideringsfeil i Node-RED-loggen.

Kjør demo, avslutt, vent på verifisert arkiv og velg Gjør klar. Velg vanlig template igjen: normal Start skal vises, og kortet skal ikke bli stående som «Starter gjæring». Gjenta etter Node-RED-omstart/reconnect. Kontroller tekniske hendelser og dato/tid i HA. Importer et tidligere SQLite v1-filpar og kontroller separat historisk sesjon, template og sammenligning. Registrer først UAT som bestått når disse prøvene er gjennomført i målmiljøet.

## P24r13 måltest etter installasjon

1. Korriger B5-grense, la en valgfri grense stå «ikke angitt», lagre og kontroller ny vurdering og grafgrense. Gjenta for P og tilbakestill begge. Ingen DB-kontraktfeil skal oppstå.
2. Kontroller at B og P har samme utseende for korreksjon og fravik.
3. Åpne Analyse og sammenlign med begge demosett eller en tidligere sesjon. Alle seks grafer skal beholde valget og bruke samme datoformat og skriftstørrelse. Gjæring viser tre kompakte målegrafer.
4. Generer rapport og sammenlign grafene med Analyse. Målinger, manuelle punkter, plan, markører, gap og kriteriegrenser skal samsvare ved samme DB-tid.
5. Importer et eldre SQLite-par og en eldre template alene. Begge skal gi de seks grafdefinisjonene uten å påvirke aktiv gjæring.

Denne måltesten er åpen til den er gjennomført i faktisk HA/Node-RED-miljø.


P24r14 kontrollerer i tillegg avgrenset lesing, uendret poll, historisk datavekst og samtidige lesere/skrivere i `test-p24r15-performance-live.js`. Hele baseline-oversikten sammenlignes separat; se TEST-RESULTS.md. CPU og visuell HA-test på gangpc står åpne.

## P24r15 – historisk forløp og B/P-tid

TEST-FUNC-022 kjøres med tests/test-p24r15-historical-live.js mot isolert MariaDB 12.3.3. Den prøver ekte leverte NR-funksjoner, fem importbolker, minuttpresis slutt, manglende videre poll etter omstart, avvisning av overskridelse, manglende/fulle timer, B/P-etterregistrering og korrigering av begge tilstøtende varigheter. Senere målinger, fast vurderingsklokke, faktisk dashboard og SQLite-par med SHA/rapport/reimport prøves.

Målmiljøet må i TEST-UAT-014 i tillegg prøves med faktiske HA Recorder-data: historisk fra–til med siste deltime, korrigert B/P-start, manuell målerunde med korrigert måletid, kriterieavvik og eksport. Kontroller at ingen tidsakse vokser neste dag og at Node-RED-omstart ikke starter ny HA-import. Disse måltestene registreres som not_run frem til faktisk utførelse.


## Måltest av diagnostikk og gjenoppkobling

TEST-UAT-014 omfatter også: importer en eldre periode med bare timesstatistikk; forvent ferdig behandlet periode med synlig datagrunnlagsadvarsel og ingen falsk feil for HISTORISK. Kontroller at counts/tidsgrenser stemmer med DB-eksporten. Koble HA fra og til mens Node-RED kjører; forvent dedupliserte ventende publiseringer, gjenlesing fra DB og lukking først etter faktisk vellykket HA-utgang. Kontroller at redigerbare input ikke resettes av denne retry-banen. Dette krever faktisk Docker/HA og er ikke utført av native testen.

## Måltest av databevaring og slurry-start

Oppgrader en kjent kilde med aktiv gjæring, beholdt tidligere sesjon og egne/importerte templates. Kontroller uendret sesjons-ID, målinger, korreksjoner, templateinnhold og kladd etter oppgradering. Kontroller installasjonsrapportens backupsti og migreringskvittering. Ved neste ordinære start: velg Slurry, bekreft at manglende DB-felt vises som manglende, lagre volum/generasjon/kildebatch/oksygenering og start. Samme verdi skal kunne lagres på nytt. Teknisk eksport skal vise startforsøkets faktiske verdier; Systemkontroll skal vise én operativ P-/B-fase selv om gamle sesjoner beholdes. Lokal simulert HA-transport er ikke målmiljø-UAT.

## Operatørflate og kildebytte

Kontroller i mål-HA: manglende slider blir ikke automatisk 0; velg og lagre 0 og 5, og prøv temperatur med én desimal. Kontroller sensorlisten, bevarte ulagrede valg ved refresh, DB-kvittering, trykk manuelt/sensor og historikk ved kildebytte. Prøv registrering og tilbaketrekking av tillatt kriterieavvik i både Biologi og Prosesstrinn og kontroller readiness/rapport. Lokal Chromium-test erstatter ikke denne måltesten.

Ved ordinær Start kontrolleres at hele første målesettet vises i historikken, inkludert sensorisk 0 og notat. Senere kladdendringer skal ikke omskrive det. Manglende kontinuerlig grunnlag skal fortsatt være synlig, og tillatt B/P-fravik skal kunne registreres og trekkes tilbake. Dette er målmiljø-UAT, separat fra native test og kontrollert Chromium-skall.
