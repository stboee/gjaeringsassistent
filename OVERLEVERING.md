> Arbeidspunkt 12.11.2026: Kildeendringene er nå rekonstruert og sikret på main, men ikke releasetestet. VERSION beholdes på siste publiserte utgave til alle kontroller er ferdige. Ikke installer main som en ferdig leveranse. Native testmiljø undersøkes for minnegrense under view-innlasting. Rekonstruert mål har 216 tabeller og 193 views.

# Gjæringsassistent – videreføring

Leveranse **2026.11.09-2 – Rettede startkort**. Teknisk utgangspunkt er p24r16 og første GitHub-utgave 2026.11.07-1. Se VERSION, BUILD-INFO.json, Git-tag og release-artefakt for faktisk identitet; dokumentasjon på main kan være nyere enn en publisert pakke.

## Ny chat

Følg [onboarding-instruksjonen](docs/ONBOARDING-NY-CHAT.md). Les AGENTS.md, dokumentkart 00, aktive beslutninger 14, relevante kontrakter og de strukturerte SQL-/registry-kildene. Skill kode, lokal test, publisert pakke og faktisk installasjon. Diskuter neste arbeid før «start»; allerede autorisert arbeid videreføres uten gjentatte godkjenninger.

## Denne leveransen

- Retter avvisning av de to startkortene: `startfields` er en tillatt kortvisning. Testen leser begge konfigurasjonene fra dashboard-YAML og bruker offentlig `setConfig`, i tillegg til DB-felt- og hendelsesgrensen.
- Filoppgradering fra 2026.11.09-1 beholder alle domenedata og kontrollerer schema og den tidligere migreringskvitteringen.

- Databevarende installasjon fra `0.1.0-prototype24-r16` eller `2026.11.07-1`, samt filoppgradering fra `2026.11.09-1`; tom database initialiseres. Samme målversjon kan reinstallere filer med samsvarende migreringskvittering. Manifestet står i installer/migrations.json.
- Privat, komprimert SQL-backup og flow/credentials før endring. Backup tar med tabeller, rutiner, triggere, hendelser og view-definisjonenes tegnsett/sikkerhet uten å evaluere grafuttrykk. Feil i backup eller ukjent grunnlag hindrer migrering.
- DB-eide startfelt og startklarstatus. HA kan ikke skjule et NULL-felt i en ny kladd med en gammel tallverdi. Samme verdi kan registreres eksplisitt. Slurry og tørrgjær valideres fra samme aktuelle DB-grunnlag.
- Startforsøk med feltvise snapshots i MariaDB og de ti siste i teknisk eksport. Normaliserte regler og HA-bindinger eier labels, valg, grenser og krav.
- Systemkontroll teller åpne P/B-besøk bare innen aktiv operativ sesjon og avdekker reelle doble/manglende besøk. Beholdte gamle sesjoner utløser ikke denne feilen.

Runtime-schema er 10, template-schema 4, med 207 permanente InnoDB-tabeller og 183 views. Historiske testnavn beholder sine navn; application_version og kildeavtrykk angir hva som faktisk er testet. Grafmotor, gjæringsprofiler og arkivformat er videreført.

## Arkitektursperrer

MariaDB/InnoDB er eneste persistente domeneautoritet. Node-RED er generisk motor/transport; HA/frontend viser ferdige DB-felt og sender eksplisitte kommandoer. Ingen HA-reserveverdier, skjulte defaults, frontend-beregninger eller generell writer-kø. Registry → template → normalisert frozen sesjon → generisk evaluering. SG-only, egne B/P-faser og ingen automatisk fysisk utstyrsstyring. Korte transaksjoner og DB-constraints håndterer integritet/samtidighet.

Append-only gjelder fakta/revisjoner i hver beholdt sesjon. Hele gamle sesjoner og ubrukte importerte templates kan slettes eksplisitt og atomisk. Startdiagnostikk følger en eksplisitt slettet template gjennom deklarert FK-kaskade. Én felles graftegner brukes i dashboard og rapport. SQLite-par er utvekslingsformat; operativ sammenligning skjer i MariaDB.

## Test og målmiljø

Se [TEST-RESULTS.md](TEST-RESULTS.md), verification/release-results.json og de kildebundne native regresjonsfilene. 37 automatiserte tester og 14 UAT er registrert. Native testmiljø bruker faktisk MariaDB 12.3.3 og plugin 0.80.3; Docker-/HA-transport er simulert. Databevaring sammenlignes over alle eksisterende domenetabeller, og backup gjenopprettes på separat isolert MariaDB-instans. Ingen produksjonsinstallasjon er utført av denne arbeidsøkten.

Siste vedlagte målrapport er fra **p24r16 den 08.11.2026 kl. 22:57**. HA viste slurryvolum 4000/generasjon 2 mens databasekladden hadde NULL. Tidligere rapport viste feil P/B-telling. Brukeren hadde tidligere bekreftet generell funksjon i p24r16; nyere konkrete avvik og manglende måltest av denne leveransen er ikke overstyrt av den bekreftelsen.

Åpent mål-/fagarbeid står i dokument 15 og akseptanse 09: reell oppgradering og startflate, Recorder-/timesimport, HA-gjenoppkobling, nettverksbrudd, nettleser/tidssoner, arkiv/ny start, B/P-korreksjoner, CPU/slow-log og faglig kalibrering. Ingen UAT er automatisk merket bestått.

## Videre arbeid og publisering

Arbeid direkte på main; issues og PR inngår ikke i prosjektprosessen. Versjon er ÅÅÅÅ.MM.DD-N, tag v-prefiks, med kort releasebeskrivelse. Publisert release inneholder ZIP og SHA-256 knyttet til samme kildecommit. Eksisterende tag/artefakt skal ikke omskrives.

Nåværende oppgraderingsbestilling omfatter bygg/publisering, ikke kjøring på brukerens server. Den autoriserte rettelsen av startkortenes konfigurasjonsfeil inngår i denne leveransen. Ved videre feil: les fersk teknisk rapport, skill aktive feil fra historiske hendelser og følg HA/NR/read-model til autoritativ DB-kilde.

Brukeren rapporterte to konfigurasjonsfeil etter templatevalg i den nye startflaten. Begge er reprodusert lokalt i 2026.11.09-1 og rettet her. Dette er ikke en bekreftelse på at den øvrige startflyten eller databevaring er målmiljøtestet.


## Pågående arbeid – 12.11.2026

**Bestilt og startet, ikke ferdigstilt eller publisert:** Sensoriske slidere, temperaturpresisjon, sensorinnstillinger, lesbare hendelseskilder og kriteriefravik i Prosesstrinn. Brukeren har godkjent hele omfanget og sagt «start»; videreføring krever ikke en ny godkjenning. Planlagt versjon er `2026.11.12-1`, men VERSION på main viser fremdeles den publiserte `2026.11.09-2`.

Arbeidsmiljøet ble utilgjengelig under en testkjøring. GitHub var fortsatt tilgjengelig. Dette avsnittet er et statuspunkt, **ikke en sikkerhetskopi av kildeendringene**. Arbeidsendringene er skrevet i det lokale arbeidstreet, men er ennå ikke lagt på main. Ikke betrakt dem som tapt uten å forsøke å gjenopprette miljøet.

### Avklart omfang

1. Sensoriske felt vises som 0–5-slidere med heltall, DB-eid forklaring og tydelig skille mellom «ikke registrert» og registrert 0. Startkortet skal følge eksisterende `input_mode='slider'` i HA-/DB-registeret.
2. Manuelle temperaturfelt bruker én desimal fra DB/read-model. Lagret rå-/målepresisjon beholdes.
3. «Målekilder og sensorer» øverst i Teknisk: HA-valg for SG, temperatur, heartbeat, RSSI og valgfritt trykk. Trykk er manuelt inntil en separat sensor velges. DB eier enheter, lineær enhetskonvertering, kontrollert HA-katalog, konfigurasjonsrevisjoner og sesjonens kildehistorikk. Kildebytte i livegjæring gjelder fra en DB-bestemt femminuttersgrense. Startbildet får et kompakt sammendrag.
4. Teknisk hendelseslogg får lesbare DB-eide komponentnavn. Opprinnelige node-/rutine-ID-er beholdes i detaljer og eksport. Historiske hendelser omskrives ikke.
5. Prosesstrinn skal ha kriteriekorreksjon og «Håndter kriterieavvik», som Biologi. Tillatelser kommer fra DB og frozen template; registrering/tilbaketrekking bevarer historikken og påvirker samme readiness/read-model som resten av motoren.

### Lokalt implementert grunnlag som må kontrolleres

Utgangspunkt før endringene: main/tag v2026.11.09-2 på `8ffcc1d099d9de1f028d1048ba5c5f36fa5d621e`, tree `e53420eafaad8f13cd33bf3fd18d1184050c9166`. Ingen produksjonsinstallasjon eller restart på brukerens server er gjort.

- `sql/12-operator-schema.sql`: ni normaliserte tabeller: measurement_source_signals, measurement_source_units, measurement_source_configurations, measurement_source_signal_bindings, session_measurement_source_configurations, session_measurement_signal_bindings, ha_sensor_catalog_checks, ha_sensor_catalog og technical_components.
- De fire entity-ID-kolonnene er fjernet fra den lokale definisjonen av measurement_source_profiles. De erstattes av reviderte bindinger per signal. Viskopien v_measurement_source_profiles leverer kompatible lesefelt; liveimport leser sesjonens fryste binding ved cursor.
- `sql/12-operator-routines.sql`: les/kontroller/lagre sensorkonfigurasjon, frys sesjonsbindinger og en felles ga_record_criterion_exception_tx for B/P med rollback-handler. Sistnevnte er nylig lagt til og må testes ferdig.
- `sql/26-operator-config-seed.sql`: signaler, enheter, komponentnavn og nye rutine-/nodenavn. Trykk i kPa er faktisk prøvd mot DB-deklarert konvertering til bar. Aktuell trykkbane er femminuttersdata; trykk i HA-timesstatistikk er ikke utvidet.
- `sql/migrations/2026.11.12-1-upgrade.sql` flytter eksisterende entity-ID-er til bindinger, oppretter sesjonskopier og legger til display_decimals. Migrert binding får virkning ved gammel importcursor; eldre kildebytter skal ikke diktes opp.
- `sql/migrations/2026.11.12-1-metadata.sql` og tillegg i 21-seeden beskriver nye tabeller, reelt fravær, lineage, ett nytt HA-event og visningshjelp.
- `sql/20-views.sql`: formattering/kontrolltype, normaliserte kildevisninger, katalogalternativer, kildehistorikk, tekniske kildenavn og rapporttidslinje.
- Årsaken til bortfalt prosessfravik er funnet: `c.met<>1` blir NULL ved manglende målegrunnlag. Lesebanen er endret til DB-eid exception_register_allowed med eksplisitt håndtering av NULL, konfigurasjonsfeil og kriterierevisjon.
- `nodered/flows.template.json`: nye source_settings-noder og én rute i felles DB-adapter; HA get_states er transport, katalog/valg lagres i DB. Importen bruker DB-enhetsmodeller og avslutter chunk ved kildegrensen. Manglende valgfritt trykk stopper ikke SG/temperatur. B/P-fraviksresultater er endret til den felles DB-rutinen.
- `dashboard/gjaeringsassistent-card.js` og dashboard-YAML: ny source-settings-visning, reelle range-kontroller, temperaturformat, lagrede kildevalg, vern av pågående redigering og lesbare hendelseskilder.
- `tools/archive_contract.json`: sesjonseide kildekonfigurasjoner/bindinger og nødvendige signal-/enhetsregistre er tatt med for å bevare kildeopphav ved SQLite-rundtur.
- Lokal manifestplan: runtime-schema 11, template-schema 4, 216 basetabeller og 191 views. Første native katalogopptak bekreftet dette. Fysisk kolonneavtrykk etter normaliseringen: `4373e5ae8c5603829db193d9b769b3270ab2f9371a43d56334eea0620d99647f`; bekreft på nytt før publisering.
- Forrige migreringskvittering for v2026.11.09-2: migration_id `2026.11.09-2-start-cards`, SHA-256 `91159b54d5fe274c041a6d4c947939252adce6c5fe1abfeccebe807266a7b154`. V2026.11.09-1 beholdes også som kjent oppgraderingskilde.

### Faktiske foreløpige kontroller

En første native gruppe på MariaDB 12.3.3 bestod: slider-/temperaturfelt, HA-katalogtransport, DB-kvittering, avvisning av utdaterte valg/feil enhet, kPa→bar, fortsatt SG-/temperaturimport uten trykk, kildebytte ved korrekt bøttegrense og lesbare kildenavn med beholdt rå identitet. Koden er endret videre etter den kjøringen. Den er **ikke** et endelig releasebevis for siste lokale kilde.

Eksisterende startformtest har passert etter de første formendringene. Nye `tests/test-operator-config-live.js` og `tests/test-operator-ui.js` er lagt til lokalt. Sistnevnte bruker faktisk Chromium/Playwright med kontrollert HA-skall/transport og faktiske DB-/Node-RED-felt- og kildekommandoer; den er ikke ferdig kjørt. B/P-fixtures skal genereres fra faktisk SQL/Node-RED, ikke håndlagde domeneverdier. `tests/test-p24r15-live.js` er endret til å prøve manglende prosessgrunnlag og faktisk registrering/tilbaketrekking.

### Gjenopptaking

Arbeidstreet lå i `/workspace/scratch/1ddb593c676d/gjaeringsassistent`. Hjelpere/status lå i `/workspace/scratch/1ddb593c676d/release-test-env`, særlig operator-release-state.json, operator_work.py, operator-core.log og operator-native.log. Siste kjøring var operator_work.py med reset-isolated-db → test-operator-config-live → reset-isolated-db → test-p24r15-live. Resultatet er ukjent fordi miljøforbindelsen falt ut.

1. Gjenopprett miljøtilgang og kontroller faktisk arbeidstre/diff før noe rekonstrueres. Bevar de lokale endringene. Main har nå dette nyere statuspunktet; flett dokumentasjonen med lokalt arbeid.
2. Kontroller siste native feil/resultat og kjør de nye fraviks- og nettlesertestene ferdig. Nytt testmiljø må initialiseres med aktuell OS-bruker, ikke chown til root; last Europe/Oslo i den isolerte MariaDB-instansen.
3. Fullfør sensorstatus ved sesjonscursor, kilde-/rapporthistorikk, SQLite-rundtur og sletting. Kontroller alle nullable-felt og normaliserings-/lineagemetadata.
4. Oppdater eldre testfixtures for den nye signalbindingskontrakten, kilde-/målstrukturer i migreringstestene, antall tabeller/views/events og faktisk schema-versjon. Oppdater testkatalog/verifikasjonsmodell, aktuelle dokumenter, versjonsmarkører og overlevering samlet.
5. Gjør et nytt faktisk katalogopptak og regenerer SQL-leseplanen med build_read_queries.py. Kjør relevante native tester og full releaseport. Ikke gi gamle bevis ny versjon/dato.
6. Prøv reelle install.sh-oppgraderinger fra støttede kilder på en uendret pakkekopi. Bevis at domenedata beholdes og at flyttede sensorbindinger er identiske med de gamle. Kontroller backup/gjenoppretting, ukjent grunnlag, feil kvittering og reinstallasjon.
7. Publiser først deretter direkte til main med datotag og ZIP/SHA. Kontroller Actions, taggens commit og den nedlastede pakkens indre sjekksummer. Ingen ny release eller fullført installasjon skal påstås før dette er gjort.
