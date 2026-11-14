---
doc_id: DOC-02
role: requirements
status: normative
source_format: markdown
---

# 02 – Krav: gjæringsmotor og integrasjon

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

**Rolle:** Normative krav til motor, persistens og integrasjon i gjeldende arkitektur.

## Ansvarsdeling

- **MariaDB/InnoDB** er eneste autoritative persistente sannhetskilde og håndterer normal database-concurrency.
- **Node-RED** er gjæringsmotor/orchestrator og eier validering, regelutførelse, bygging av atomiske domeneoperasjoner og HA-integrasjon.
- **Home Assistant** er operatørflate og presentasjon; HA-state er ikke domenefasit.
- Det finnes ingen separat applikasjonsbackend mellom Node-RED og MariaDB.
- `flow.*` og `global.*` kan ikke brukes som nødvendig persistent domenestate.

## Krav

| ID | Status | Krav |
|---|---|---|
| REQ-MOTOR-001 | Fastsatt | Alle stateful operatørhandlinger valideres mot MariaDB-grunnlag før skriving. |
| REQ-MOTOR-002 | Fastsatt | Én faglig mutasjon skal være én kort atomisk MariaDB-transaksjon; commit eller rollback gjelder hele mutasjonen. |
| REQ-MOTOR-003 | Fastsatt | Node-RED-restart skal kunne rekonstruere nødvendig nåtilstand fra MariaDB alene. |
| REQ-MOTOR-004 | Fastsatt | HA-entity-ID/config-ID-grensen følger dokument 05 og maskinkontrakten. |
| REQ-MOTOR-005 | Fastsatt | Feil i Node-RED/HA-integrasjonen skal inn i normalisert `technical_events` der persistens er mulig. |
| REQ-MOTOR-006 | Fastsatt | Systemkontroll skal skille faktisk teknisk feil fra funksjon som bevisst ikke er portert; `not_applicable` skal ikke gi falsk FAIL. |
| REQ-MOTOR-007 | Fastsatt | Ingen JSON-blobber skal brukes som erstatning for normaliserte domenedata. |
| REQ-MOTOR-008 | Fastsatt | SG-only gjelder alle aktive grensesnitt. |
| REQ-MOTOR-009 | Fastsatt | Runtimehistorikk skal være append-only der ny faglig tilstand kan uttrykkes som ny fakta-/revisjonsrad. Historiske runtime-rader skal ikke toggles til/fra current. |
| REQ-MOTOR-010 | Fastsatt | Systemet skal ikke innføre applikasjonsstyrt DB-serialisering eller eksplisitt locking (`SELECT ... FOR UPDATE`, `GET_LOCK`) som normal concurrency-mekanisme. InnoDB håndterer samtidige readers/writers. |
| REQ-MOTOR-011 | Fastsatt | Datakonsistens skal primært uttrykkes med normalisering, PK/FK/UNIQUE/CHECK og idempotente operation-ID-er. |
| REQ-MOTOR-012 | Fastsatt | Rene reads kan kjøre parallelt og kan kortvarig se siste committed snapshot. Read-model korrigeres ved neste lesing; dette skal ikke kompenseres med global locking. |
| REQ-MOTOR-013 | Fastsatt | Mutable arbeidskladd er tillatt for operatørinput/template-draft, men skal være tydelig skilt fra immutable sessionhistorikk. |
| REQ-MOTOR-014 | Fastsatt | Ordinær `Start gjæring` skal bruke valgt **Start fra** som opprinnelig pitch-/kildestart og hente tilgjengelig SG-, temperatur-, heartbeat- og RSSI-historikk fra DB-konfigurert Home Assistant-kilde. |
| REQ-MOTOR-015 | Fastsatt | HA-historikk skal normaliseres til komplette 5-minuttersbøtter i `measurements_5m`; rå HA-state skal ikke bli alternativ persistent domenestore. |
| REQ-MOTOR-016 | Fastsatt | Heartbeat-kilden avgjør datadekning. Manglende heartbeat skal gi eksplisitt `measurement_data_gaps`; SG/temperatur skal ikke interpoleres over slike gap. |
| REQ-MOTOR-017 | Fastsatt | Etter Start skal samme inkrementelle import fortsette i en aktiv-session-styrt femminuttersløyfe fra persisted `last_import_cutoff_at`. Uten aktiv reell session skal ingen periodisk HA-history-henting initieres; restart skal kunne hente seg inn fra MariaDB-cursor + HA-historikk når aktiv session finnes. |
| REQ-MOTOR-018 | Fastsatt | Målekildens entity-ID-er skal ligge i MariaDB `measurement_source_profiles`, ikke hardkodes i Node-RED-funksjoner. |

| REQ-MOTOR-019 | Fastsatt | Evaluator skal bruke frosne `session_metric_runtime_*`, `session_biology_calculation_*` og kriterieparametere som deklarativt regelgrunnlag. Metrikk-ID skal ikke brukes som skjult domene-switch for å velge fagregel. |
| REQ-MOTOR-020 | Fastsatt | Node-RED implementerer generiske måleberegninger: SG-fall, utgjæringsgrad, signert endepunktrate, maks–min-stabilitet og state-order. Modellvalg, kilder, terskler og vindusparametere kommer fra frozen MariaDB-data. Frontend beregner ingen domenemetrikker. |
| REQ-MOTOR-021 | Fastsatt | En metrikk med `freshness_mode=not_applicable` skal ikke kunne evalueres med `maximum_age_minutes`; dette skal oppdages som ugyldig konfigurasjon ved templatevalidering/publisering. |
| REQ-MOTOR-022 | Fastsatt | Ved HA-history-backfill skal biologimotoren evaluere 5-minuttersgrunnlaget kronologisk, håndheve persistens over faktisk sammenhengende datadekning og opprette hvert sekvensielle biologiske visit/transition ved det historiske kriteriekryssingstidspunktet. |
| REQ-MOTOR-023 | Fastsatt | Persistens skal resettes over registrerte `measurement_data_gaps`; et krav om vedvarende kriterium kan ikke oppfylles ved å akkumulere tid på tvers av et dokumentert datagap. |
| REQ-MOTOR-024 | Fastsatt | `sensor.gjaeringsassistent_malekilde` skal produseres fra én dedikert MariaDB-read-model. Live-ingest og Systemkontroll kan trigge refresh/kontroll, men skal ikke publisere egne konkurrerende målekildetilstander. |
| REQ-MOTOR-025 | Fastsatt | Uten aktiv reell session skal målekildens operative importstatus være `IDLE` og ingen sensorhistorikk hentes for observability. Aktiv reell session uten persistert kildebinding skal være feiltilstand, ikke `IDLE`. |
| REQ-MOTOR-026 | Fastsatt | Ved historisk HA-history/catch-up skal prosesstrinn replayes kronologisk og sekvensielt på samme grunnprinsipp som B-faser. Bare neste aktive P-kandidat kan opprettes, og vurderingen skal bruke målinger, observasjoner og biologisk tilstand som var tilgjengelige ved evalueringstidspunktet. Etter catch-up/live er ordinær P-overgang fortsatt operatørbekreftet. |
| REQ-MOTOR-027 | Fastsatt | `Start gjæring` skal ha sporbar ingress og eksplisitt slutt-/feilkvittering. DB-/bindingfeil i Start-kjeden skal nå normalisert Technical-pipeline og startstatus; taus bortfall av en stateful Start-kommando er ikke tillatt. |
| REQ-MOTOR-028 | Fastsatt | Historisk evaluator skal bruke persistert importcutoff som øvre evalueringshorizon; live evaluator skal bruke MariaDB-klokken. Node-REDs lokale veggklokke skal ikke være fallback for faglig freshness/alder. |
| REQ-MOTOR-029 | Fastsatt | Gjennomført B/P-overgang skal presenteres fra transitionens eksakte `evaluation_id`; current candidate evaluation er et separat read-model-faktum og skal ikke erstatte historisk overgangsbevis. |
| REQ-MOTOR-030 | Fastsatt | Releasebygging skal kjøre maskinell arkitekturkonformitetskontroll for sentrale DB-only-, evalueringshorizon- og read-model-regler. Kontrollen er en utviklings-/releaseport og skal ikke legges inn i installeren. |
| REQ-MOTOR-031 | Fastsatt | Runtime-/rapportverdier som vises til operatøren skal komme ferdig beregnet og ferdig representert fra MariaDB/read-model. Frontend skal ikke beregne, korrigere, tolke, formatere eller supplere domenedata med fallbackverdier. |
| REQ-MOTOR-032 | Fastsatt | En registrert metrikk skal ha én autoritativ beregningsbane. Oversikt, B/P-vurdering og rapport skal lese persistert evaluator-/metric-resultat; samme domeneverdi skal ikke beregnes på nytt i frontend eller parallell Node-RED read-model. |
| REQ-MOTOR-033 | Fastsatt | Kriterieevaluering skal persistere datagrunnlagets provenance, inkludert relevant vindu, sample count, faktisk dekning og siste sample. MariaDB-read-model skal produsere ferdig `data_window_display`; frontend skal bare vise feltet. |
| REQ-MOTOR-034 | Fastsatt | Aktiv gjæring skal kunne generere en HTML snapshotrapport fra MariaDB/read-model uten lifecycle-endring. Rapportverdier skal være de samme ferdige displayverdiene som den operative read-modelen leverer. |
| REQ-MOTOR-035 | Fastsatt | Målekilde/Tilt-status skal leses fra ett MariaDB-view. Node-RED kan normalisere transportformen fra mysql-node, men skal ikke konstruere alternativ målekildestatus, timestamps eller domenedisplay. |
| REQ-MOTOR-036 | Fastsatt | Historisk automatisk prosesstrinnsovergang skal være en eksplisitt egenskap ved hvert template-prosesstrinn og fryses til session. Historisk evaluator kan vurdere alle neste trinn, men kan bare persistere overgang når det frosne trinnet eksplisitt tillater historisk autoovergang. |
| REQ-MOTOR-037 | Fastsatt | W-34/70 standardtemplaten tillater historisk etablering av P1/P2. P3 og senere trinn krever operatørbekreftet overgang selv om kriteriene er oppfylt. |
| REQ-MOTOR-038 | Fastsatt | Historisk HA-import skal sekvensieres som persistér chunk → biologisk evaluering → prosessevaluering → neste chunk. Evaluator-/recommendation-identiteter skal komme fra MariaDB og ikke konstrueres fra Node-RED-klokke. |
| REQ-MOTOR-039 | Fastsatt | Åpent måledatagap skal ha én autoritativ representasjon i `measurement_data_gaps`. `session_measurement_sources` skal ikke cache duplisert gapstatus. |
| REQ-MOTOR-040 | Fastsatt | Validering av rå måleprøver skal være metadata-styrt per målekilde og fryses til session. Motoren kan implementere registrerte generiske valideringsmodeller, men signal-/template-spesifikke grenser skal ikke hardkodes. |
| REQ-MOTOR-041 | Fastsatt | Ugyldige råprøver skal forkastes før autoritativ `measurements_5m`-lagring; systemet skal ikke clamp-e eller erstatte en ugyldig verdi med en oppdiktet plausibel verdi. Kvalitetsutfall skal være sporbare separat. |
| REQ-MOTOR-042 | Fastsatt | Autoritativ SG i en godkjent 5-minuttersbøtte skal være robust aggregert fra godkjente prøver; W-34/70/Tilt bruker median. Min/middel/maks er diagnostikk og skal beregnes fra samme godkjente prøvesett. |
| REQ-MOTOR-043 | Fastsatt | Om en beregnet verdi skal ha analyseserie/graf og dens presentasjons-/behandlingsregler skal ligge i template/sessionmetadata. Motor/frontend skal ikke ha graph-ID-spesifikke regler. |
| REQ-MOTOR-044 | Fastsatt | Analyse publiserer bare verdier som oppfyller frozen minste antall, tidsspenn og dekning. Rate beregnes fra målte endepunkter og faktisk tid; ingen kortvindu-estimat eller foreløpig publisering. |
| REQ-MOTOR-045 | Fastsatt | `analysis_series_values` er append-only. Ugyldige beregnede outputs skal ikke clampes/persisteres som gyldig serie; avvisningen skal registreres som analysevalideringsfaktum. |
| REQ-MOTOR-046 | Fastsatt | HA-projeksjoner skal bare eksponere attributtverdier som er gyldige i HA-kontrakten. Nullable interne råfelt skal erstattes av DB-eide ferdige presentasjonsfelt eller utelates, ikke få Node-RED-fallback. |
| REQ-MOTOR-047 | Fastsatt | Gyldighetsdomene for avledede metrics skal være normalisert metric-metadata og fryses til template/session. Samme frozen grenser skal håndheves før en metric kan brukes av B/P-kriterier og før den kan persisteres i analyseserie. Ugyldig output skal gi manglende/ugyldig datagrunnlag, aldri overgang eller clampet verdi. |

| REQ-MOTOR-048 | Fastsatt | Node-RED skal registrere UAT-resultater gjennom validert MariaDB-operasjon mot aktive `UAT`-tester; frontend-event er bare ingress og er ikke kvittering på lagring. |
| REQ-MOTOR-049 | Fastsatt | Gjeldende test-, verifikasjons- og kravstatus skal utledes i MariaDB read-models. Node-RED og frontend skal ikke beregne egen coverage, samlet kravstatus eller fallback-status. |
| REQ-MOTOR-050 | Fastsatt | Automatisk releaseverifikasjon skal kunne representeres med stabile `TEST-TECH-*`/`TEST-FUNC-*`-identiteter og knyttes til verifikasjonskrav; målmiljøtest skal bruke `TEST-UAT-*`. |
| REQ-MOTOR-051 | Fastsatt | Verifikasjonseksport skal lese ett konsistent DB-grunnlag med metadata, relasjoner, testkjøringer og resultater og produsere JSON og HTML uten domenelogikk i renderer. |
| REQ-MOTOR-052 | Fastsatt | Forventet gjæringsresultat skal uttrykkes normativt som templateens intervall for tilsynelatende utgjæringsgrad. Forventet FG skal beregnes fra faktisk korrigert OG og dette intervallet; operatøren skal ikke registrere et uavhengig FG-mål ved Start. |
| REQ-MOTOR-053 | Fastsatt | Operativ gjæringsprosent skal være tilsynelatende utgjæringsgrad. Egen FG-fremdriftsprosent, rate relativt til historisk maksimum og absolutt SG-rate skal ikke være operative domenemetrikker. |
| REQ-MOTOR-054 | Fastsatt | Målefreshness og generell målekvalitet skal behandles som en felles evalueringsforutsetning. Manglende eller foreldet livegrunnlag skal gi «kan ikke evalueres»/ufullstendig vurdering, ikke falskt biologisk eller prosessuelt kriterium. |
| REQ-MOTOR-055 | Fastsatt | Biologiske kriterier skal bruke et lite forklarbart kjernesett av SG-fall, signert SG-rate, tilsynelatende utgjæringsgrad og SG-stabilitet. Prosesstrinn skal normalt konsumere ferdig biologisk fase og bare legge til operative betingelser; samme biologiske logikk skal ikke dupliseres i P-kriterier. |

| REQ-MOTOR-056 | Fastsatt | MAD-validering bruker deklarert støygulv også ved null MAD. B/P og Analyse bruker identisk endpoint_rate_v1 fra felles kilde: målt SG-forskjell / faktisk tid, ingen regresjon eller følsomhetsbånd. Datagap bryter vinduet. |
| REQ-MOTOR-057 | Fastsatt | Rå Tilt-utgjæringsgrad bruker faktisk OG og godkjent Tilt-SG uten pitch-kalibrering. Manuell utgjæringsgrad bruker faktisk OG og korrigert manuell SG. Kildene er separate og velges eksplisitt av templatekriteriets metric_id; ingen kildebytte/fallback. |
| REQ-MOTOR-058 | Fastsatt | Aktuelle analyseverdier skal hentes fra siste godkjente analyseserie og kontrolleres mot nyere avvisning/freskhet; overgangskriteriers gamle snapshots skal ikke presenteres som aktuell rate. Rå Tilt-AA og manuell AA har hvert sitt faktiske målegrunnlag og måletid; ingen automatisk kildebytte. |
| REQ-MOTOR-059 | Fastsatt | Tomme valgfrie korreksjonsparametere skal lagres eksplisitt som ikke angitt, uten konvertering til nulltallet. Hele konfigurasjonen skal valideres før transaksjonen. Ved ugyldig kriteriekonfigurasjon skal fortsatt beregnbar faktisk verdi og forklarende årsak bevares. |

## Evaluering og operasjonskvittering

Biologisk og prosessuell evaluering kjøres mot frozen sessionplan og persistent målehistorikk i MariaDB. Resultatet persisteres før det publiseres til HA/read-model. Evaluatorene skal ikke bruke HA-state som autoritativt faglig grunnlag. Generiske kriteriemodeller er `threshold`, `observation`, `window_median_range` og `stability_window`.

Overganger, tidskorrigering, kriteriekorreksjon, kriterieavvik og anbefalinger skal opprette nye fakta/revisjoner. Gjeldende revision utledes fra revisjonsrelasjonen; tidligere historikk omskrives ikke.

Operatørhandlinger skal ha observerbar sluttkvittering. En mottatt HA-knapp/event er ikke i seg selv bevis på lagring. Systemkontroll kvitteres med ny `system_check_run`; notat med persisted `operation_id`; målesett med persisted `MEASUREMENT_SAVED`/`MEASUREMENT_REJECTED`/`MEASUREMENT_SAVE_FAILED`. Demo-session følger samme motorbaner som virkelig session.

| REQ-MOTOR-060 | Fastsatt | S-04- og M42-templater skal være egne publiserte normaliserte profiler med kjølig hovedgjæring innen produsentområdet, gradvis opprydding ved 20 °C og eksplisitte sluttkontroller. 21 dager er planleggingsramme, ikke automatisk ferdigregel. |

## Historikk, grafer og import

| ID | Status | Krav |
|---|---|---|
| REQ-MOTOR-061 | Fastsatt | HA-timesstatistikk lagres append-only med reelle min/gjennomsnitt/maks, uten krav om historisk MQTT-heartbeat og uten konstruerte medianer/prøveantall. |
| REQ-MOTOR-062 | Fastsatt | Hver Systemkontroll lagrer alle resultater atomisk med unik kjøringsidentitet og kontrollerer HA mot et ferskt API-svar. |
| REQ-MOTOR-063 | Fastsatt | Aktiv og avsluttet rapport bruker én generator og inkluderer full kronologisk hendelseshistorikk og tilgjengelige timesdata. |
| REQ-MOTOR-064 | Fastsatt | Datasett- og sammenligningsvalg persisteres i MariaDB; den valgte demoidentiteten fryses ved Start. |

| ID | Status | Krav |
|---|---|---|
| REQ-MOTOR-065 | Aktiv | Graftransport skal dele presentasjonsmetadata, bruke kompakt JSON og tilby verifisert gzip. Punktutvalg skjer i DB og bevarer første/siste/min/maks og segmentgrenser. Lagring/analyser beholder femminuttersoppløsning; standard visningsintervall er 30 minutter. |

| ID | Status | Krav |
|---|---|---|
| REQ-MOTOR-066 | Aktiv | HA-timesstatistikk hentes ved første historiske import og ved DB-målt etterslep på minst én time. Vanlig frisk femminuttersimport henter detaljhistorikk. En uløst statistikkfeil gir nytt historisk forsøk; gjenoppretting registreres bare når en slik feil faktisk er aktiv. |

| Krav | Status | Kravtekst |
| --- | --- | --- |
| REQ-MOTOR-073 | Aktiv | En historisk HA-sesjon har fra-tid fra gjeldende pitchrevisjon og en eksplisitt slutt i session_history_windows. Importen stopper ved sluttgrensen, også etter omstart. Sluttgrensen valideres i DB og avgrenser lagring; ingen normal live-import planlegges etter fullføring. |
| REQ-MOTOR-074 | Aktiv | Effektiv P/B-slutt er neste visits gjeldende start innen samme tidslinje. Siste visit avgrenses av DB-eid sesjonsklokke. MariaDB beregner datoer og varighet for dashboard og rapport; korreksjon beholder tidligere revisjoner. |
| REQ-MOTOR-075 | Aktiv | Historiske vurderinger, grafakser og manuelle registreringer bruker den historiske horisonten, ikke dagens klokke. Måle-/hendelsestid og faktisk registreringstid bevares separat. Manglende data og delvis ubrukelig timesstatistikk skal ikke fylles ut med estimater. |

Den historiske sesjonen er den gjeldende operatørens arbeidsøkt mens den etterregistreres. Intern lifecycle=active betyr her at redigering og eksport er tilgjengelig; is_historical og sluttgrensen skiller den fra løpende innhenting. Den bruker samme ene operative arbeidsøkt som eksisterende løsning. «Avslutt gjæring» ferdigstiller ved det historiske sluttidspunktet og bruker ordinær arkiv- og klargjøringsflyt. Ingen fysisk tank eller MQTT-sender stoppes.

## Arkivutveksling

| ID | Status | Krav |
| --- | --- | --- |
| REQ-MOTOR-067 | implemented | Import av gjæring og tilhørende template skjer atomisk med ny lokal identitet og historisk frigivelse. Feil ruller tilbake hele importen; aktiv gjæring og måleskriving påvirkes ikke. |
| REQ-MOTOR-068 | implemented | Importert template får alltid en egen unik ID og kildeproveniens; den sammenlignes, dedupliseres eller flettes ikke med eksisterende templates. Redigering krever egen kopi. |

## Start og arkivadministrasjon

| ID | Status | Krav |
| --- | --- | --- |
| REQ-MOTOR-069 | implemented | Startstatus rekonstrueres fra MariaDB ved demo, import, avslutning, klargjøring og omstart. Systemkontroll skal oppdage vedvarende motstridende HA-status. |
| REQ-MOTOR-070 | implemented | Hele historiske sesjoner kan slettes atomisk med alle tilhørende data. Aktiv sesjon er beskyttet; gjeldende sammenligningsvalg nullstilles ved sletting. Append-only gjelder innenfor beholdte sesjoner. |
| REQ-MOTOR-071 | implemented | Aktiv eksport produserer et merket konsistent øyeblikksbilde av gjæring, template og felles HTML-rapport uten å avslutte sesjonen. Begge SQLite-filer får SHA-256-sidefil. |
| REQ-MOTOR-072 | implemented | Manglende, uleselig eller feil ekstern SHA gir synlig advarsel uten å blokkere import. SQLite-integritet, skjema, eksportpar og transportkontrollsum valideres fortsatt. |

## Systemkontroll og HA-publisering

| Krav | Status | Kravtekst |
| --- | --- | --- |
| REQ-MOTOR-076 | Aktiv | Klassifisering av målekildestatus eies av normalisert MariaDB-policy og read-model. Ukjent statuspolicy eller manglende påkrevd kontrollgrunnlag skal være synlig feil, uten lokal Node-RED-liste eller fallback. |
| REQ-MOTOR-077 | Aktiv | Ferdig behandlet importperiode skal skilles fra faktisk datadekning. Antall og tidsgrenser for ordinære femminuttersmålinger og timesstatistikk samt registrerte rådatagap utledes i DB. Timesstatistikk skal ikke fremstilles som ordinært B/P-grunnlag. |
| REQ-MOTOR-078 | Aktiv | Forbigående HA-publiseringsbrudd journalføres uten rekursiv publisering av feilen. Nytt forsøk leser ferske DB-projeksjoner, aldri en lokal domenekø. Et konkret publiseringsproblem lukkes først etter vellykket utgang fra den berørte HA-noden. Ugyldig payload skal fortsatt være feil. |

## Målekilder og konfigurasjonsrevisjoner

| ID | Status | Krav |
|---|---|---|
| REQ-MOTOR-079 | Aktiv | Sensorbindinger normaliseres per signal, enhet og konfigurasjonsrevisjon i MariaDB, og fryses per reell sesjon. Livebytte trer i kraft ved en DB-bestemt femminuttersgrense; tidligere bindinger og målinger beholdes. Historisk import endres ikke retroaktivt. |
| REQ-MOTOR-080 | Aktiv | Trykk er manuelt til en kompatibel HA-sensor er valgt. Sensortrykk omregnes fra deklarert enhet til bar med DB-eide koeffisienter og grenser. Fravær av valgfritt trykk skal ikke blokkere SG/temperatur. B/P-fravik lagres i en felles kort DB-transaksjon med gjeldende evaluering, kriterierevisjon og eksplisitt bekreftelse. |
