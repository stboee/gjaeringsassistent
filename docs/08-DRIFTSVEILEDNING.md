---
doc_id: DOC-08
role: operations-guide
status: current
source_format: markdown
---

# 08 – Driftsveiledning

## 1. Installere/reinstallere

Gjeldende release bruker **MariaDB 12.3.3**, fast tag `mariadb:12.3.3`. Oppdater bare eksisterende `gjaeringsassistent-mariadb`-tjeneste i den samlede compose-filen: behold databasevolum, nettverk og credentials, endre image til `mariadb:12.3.3` og sett `MARIADB_AUTO_UPGRADE: "1"` under `environment`. Referansefragmentet finnes i `compose/mariadb-service.yaml`. Ikke opprett en konkurrerende databasecontainer.

Fra katalogen med den eksisterende compose-filen, bruk samme compose-valg som normalt:

```bash
docker compose pull gjaeringsassistent-mariadb
docker compose up -d --no-deps gjaeringsassistent-mariadb
docker exec gjaeringsassistent-mariadb sh -lc 'mariadb -N -B -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" -e "SELECT VERSION()"'
```

Vent til containeren er healthy og versjonsspørringen viser `12.3.3-MariaDB...`. `MARIADB_AUTO_UPGRADE` lar det offisielle imaget oppdatere MariaDBs egne systemtabeller ved behov. Gjæringsassistent oppgraderer deretter applikasjonsskjemaet gjennom sin egen databevarende migrering. MariaDB-systemoppgradering og applikasjonsmigrering er separate operasjoner.

Node-RED-containeren må kjøre for at installeren skal kontrollere installerpakker og lese faktisk UID/GID. Hvis den er stoppet, kjør `docker start gjaeringsassistent-nodered` først. Installeren avviser stoppet/restarting container før database- og flowendringer, med egen diagnose.

Oppgradering fra 2026.11.09-1 er en fil-/metadataoppdatering: kjent fysisk struktur og tidligere migreringskvittering kontrolleres, domenetabeller/rutiner/views beholdes, og privat backup tas før endring.

Kjør `./installer/install.sh` fra den utpakkede releasepakken. Eksisterende data bevares; baseline/seeds brukes bare på tom database. Installeren installerer schema/seeds/views, Node-RED-flow og frontendkilde, men kjører ikke syntetisk Start, Systemkontroll eller andre runtime-akseptansetester.

Før mutasjon leser installeren serverversjonen og sammenligner med `BUILD-INFO.json`. Annen versjon avvises før database- eller flowendringer. Faktisk serverversjon følger `.json`-rapporten som `database_server_version`.

Installerresultat skrives som `.json` og `.log` under `install-reports/`. Ved FAIL brukes `last_step` og tilhørende logg; installerfeil skal løses som installer-/DDL-/flowfeil, ikke maskeres med runtime-workarounds.

## 2. Etter vellykket installasjon

1. Åpne Home Assistant → **Teknisk**.
2. Hard refresh (`Ctrl+F5`) dersom browseren viser gammel frontend.
3. Kontroller at frontendpublisering viser samme releaseversjon som pakken.
4. Kjør **Systemkontroll** dersom den automatiske kontrollen ikke allerede er fersk.
5. Bruk **Aktive problemer**, **Teknisk hendelseslogg**, **Målekilde/Tilt** og **Systemkontroll** til diagnose.

`NOT_APPLICABLE` er ikke feil når kontrollen eksplisitt er utenfor gjeldende operativ kontekst.

## 3. Frontendpublisering

Node-RED publiserer dashboard, custom card og loader ved oppstart fra staging til `/data/gjaeringsassistent/ha-public`. Publisering registreres med releaseversjon og SHA-256 i MariaDB. Installeren skal ikke skrive direkte til en katalog som skjules av bind-mount.

Hvis `custom:gjaeringsassistent-card` mangler, kontroller Lovelace-resource mot `/local/gjaeringsassistent/gjaeringsassistent-card-loader.js` og frontendpubliseringsstatus i Teknisk.

## 4. Eksporter Teknisk

**Eksporter Teknisk** lager et read-only diagnostisk JSON-snapshot under HA-public `exports/` med lokal tid i filnavnet. Snapshotet inneholder relevant HA-projeksjon, MariaDB-runtime/pre-start/sessiongrunnlag, målekildestatus, tekniske hendelser og siste Systemkontroll. I tillegg genererer Node-RED periodisk `gjaeringsassistent-teknisk-status-latest.json` direkte fra MariaDB-read-modellen. Nedlastingsnavnet har timestamp-prefix med millisekunder, også for sistefilen, slik at tidligere nedlastinger bevares. Statusfilen viser DB-/Node-RED-/publisert frontendversjon og DB-/HA-templatealternativer. Kontroller alltid eksporttid og versjoner før filen brukes til å diagnostisere en ny feil. Denne sistefilen gjør diagnostikk tilgjengelig selv om HA-eventbanen for den manuelle eksportknappen er midlertidig utilgjengelig.

Ved feilsøking er disse filene foretrukket fremfor manuell kopiering av enkeltmeldinger. De er kun diagnostikk og er aldri restoreautoritet.

## 5. Template-editor

Før Start velges publisert template i Gjæring-flaten. Template-fanen har et eget MariaDB-persistet administrasjonsvalg og kan brukes til å opprette/redigere draft, validere, publisere, retire og reaktivere templateversjoner både før og under aktiv session. En aktiv session bruker sin frozen session-template uendret; senere templateadministrasjon påvirker ikke sessionens faggrunnlag.

`template-editor.json` er dynamisk read-model. HTTP 404 betyr at genereringskjeden ikke har produsert filen; den skal ikke kopieres manuelt som permanent løsning. Finn årsaken i Teknisk/Technical Events.

## 6. Referansedemo

**Start demo** er en eksplisitt operatørhandling og går gjennom ordinær Start/frozen-session-kjede før deterministisk referansedata legges i de ordinære runtime-tabellene. Demodata har bevarte datagap og skal ikke forveksles med produksjons-Tilt-ingest.

## 7. Ordinær Start med Home Assistant-history

1. Kontroller DB-konfigurert målekilde dersom eksterne entity-ID-er er endret.
2. Velg template og fyll start-/målegrunnlag.
3. Angi **Start fra** i lokal `Europe/Oslo`-tid.
4. Trykk **Start gjæring**.
5. Historikk importeres/valideres kronologisk til komplette 5-minuttersbøtter, B/P replay kjøres sekvensielt og importen fortsetter til LIVE.
6. Deretter kjører inkrementell import bare mens reell session er aktiv. Restart fortsetter fra persistert importcursor.

Heartbeat avgjør datagap. Registrerte gap skal ikke interpoleres.

Systemkontroll trigges etter vellykket Start og ved overgang til LIVE, slik at session-/målekildestatus ikke blir stående som pre-Start-snapshot.

## 8. Datakvalitet

SG, temperatur og RSSI valideres mot frozen sessionregler før `measurements_5m`. Ugyldige samples forkastes; de skal ikke repareres med DB-edit, frontendfilter eller clamp. Kvalitetsutfall finnes i `measurement_ingest_quality_events`.

En tom start på en Analyse-kurve er korrekt inntil minste beregningsgrunnlag finnes. P24r7 viser kun ordinære punkter når faktisk minste tid, antall og dekning er oppfylt. En fysisk/matematisk urimelig verdi skal derimot avvises og være sporbar som valideringshendelse.

## 9. Målekilde/Tilt

Teknisk viser DB-read-modelen for målekilden. Ved aktiv reell session forventes minst profil, sessionbinding, importcursor, sist-OK, siste 5-minuttersmåling, sample count, SG-statistikk, temperatur, RSSI og gapstatus. Tom/`IKKE KJØRT` HA-projeksjon samtidig som DB-status er LIVE er en projeksjons-/integrasjonsfeil og skal fremgå av Technical Events/Systemkontroll.

## 10. Tid

Persistent maskintid er UTC. Operative tidspunkt vises i `Europe/Oslo`. Lokal visning skal ikke brukes som alternativ persistent tidsautoritet.

## 11. Verifikasjon og UAT

Fanen **Verifikasjon** viser DB-avledet TECH/FUNC/UAT-status og REQ→VER→TEST-relasjoner. UAT registreres som nytt append-only resultat med operatør/notat/evidence; tidligere gjennomføringer overskrives ikke. **Eksporter verifikasjon** lager både maskinlesbar JSON og lesbar HTML fra samme konsistente DB-grunnlag under HA-public `exports/`. Teknisk-fanen viser bare et kompakt sammendrag og lenker videre til detaljflaten.

## Historikk, demo og grafvalg

Den ordinære MQTT-automasjonen beholdes; Test MQTT brukes ikke av importen. Femminuttsdata lagres som før. MQTT-tidsstempelsensorens ISO-verdi brukes til å verifisere fersk rådata. Tidsstempelsensoren er ikke en numerisk langtidsstatistikkserie.

Ved oppstart og videre import spør motoren HA om SG, temperatur og RSSI med `recorder/statistics_during_period`, periode `hour`, samtidig med ordinær historikk. HA-brukeren må ha tilgang til Recorder-statistikk. Timesdata brukes som de er, også uten MQTT-verifikasjon. Et feilet statistikkanrop gir en driftsmelding og stopper ikke rådataimporten; meldingen lukkes ved neste vellykkede kall.

Under grafene kan du velge ingen sammenligning, et av de to datasettene eller en avsluttet gjæring. Begge kurvene starter ved dag 0, gjæringsstart. Grafvalget deles mellom Gjæring og Analyse og lagres i MariaDB. Hele gjæringen eller siste 24 timer, 48 timer eller 7 dager kan vises. Visningsintervallene er 5, 15 og 60 minutter, med 15 minutter som første valg. Dette endrer ikke lagrede rådata.

Demo velges før Start demo. `2026-05-29 IPL` er den samme tidligere demoen, kun navnet er endret. `2026-09-25 Gyllen pils` samler 2924 godkjente punkter fra vedlagte rådata/CSV/TSV, fra 25.09.2026 kl. 22:00 norsk tid til 06.10.2026 kl. 20:30. 32 manglende intervaller er bevart som gap; datasettet er ikke et løfte om målinger fram til dagens dato. Duplisert TSV er ikke telt to ganger. Proveniens finnes under `reference/demo`.

Etter Avslutt skal kortet vise Gjæring avsluttet og arkivstatus. Gjør klar vises når DB-gaten tillater frigivelse. Arkiveringsknappen vises når et arkiv mangler eller et forsøk har feilet. Et verifisert arkiv skal ikke utløse en ny arkivering. Arkiv kan fortsatt være større enn 19 MB; bare små filmetadata sendes til MariaDB.

## P24r8 måltest

Etter installasjon: Start reell import, kontroller at Gjæring viser grafene, velg Gyllen pils som sammenligning og vent på DB-kvittering. Valget skal bestå neste periodiske refresh. Analyse skal vise SG/temperatur/trykk før analysegrafene; prøv 5/30/60 minutter og kontroller at gap og nå-verdier er konsistente. Generer aktiv rapport og kontroller høyere grafer. Kjør Systemkontroll med Oslo-tid; skjema og klokke skal være OK. Eksporter både Teknisk og Utvidet diagnostikk. Sistnevnte skal inneholde `frontend_diagnostics.published_payload`; normal eksport skal bare inneholde sammendraget.

I nettleserens Network-fane kan JSON-kallet kontrolleres for Content-Encoding: gzip. Manglende HTTP-komprimering betyr at HA-serverens forhandling må undersøkes; den tapsfrie gzip-sidefilen finnes uansett for direkte nedlasting.

## Historisk timesstatistikk og live-import

Første import henter detaljhistorikk og tilgjengelige HA-timeverdier. Normal femminuttersoppdatering hopper over statistikk-API-et. DB-cursor med minst én times etterslep utløser historisk innhenting. Dette er en teknisk grense for historisk opphenting, ikke en antakelse om Recorder sin retention. Ved en uløst statistikk-API-feil forsøkes historikken fra kildestart på nytt, slik at eldre manglende timer kan repareres. Detaljdata foretrekkes når begge kilder finnes. Tidligere feil lukkes med én gjenopprettingshendelse; vanlige vellykkede API-svar gir ikke nye driftsmeldinger.

Grafkrav bruker originalparametere pluss gjeldende override. Reset gjeninnfører originalparametere. En eksplisitt tom valgfri grense blir ikke nulltallet. Oppfylt-markøren krever evaluering under akkurat den gjeldende revisjonen, også etter reset. Historisk måle-/evalueringsgrunnlag omskrives ikke.

## SQLite-arkiver fra p24r10

Fanen **Template og arkiv** har et eget arkivkort. Velg `-template.sqlite` og, ved gjæringsimport, tilhørende `-gjaering.sqlite`. Kontroller forhåndsvisningen før import. Filenes format, skjema, integritet, transportkontrollsum og sammenhørende manifest kontrolleres. Domene-FK-er og CHECK-er håndheves under selve importtransaksjonen. Feil vises i arkivkortet og ruller tilbake både template og sesjon.

Filene navngis `session-<sessionid>-export-<exportid>-gjaering.sqlite` og `session-<sessionid>-export-<exportid>-template.sqlite`. Template-filen inneholder én original publisert versjon, med nødvendig registergrunnlag. Gjæringsfilen har normaliserte målinger, timedata, frozen grunnlag, vurderinger, korreksjoner, observasjoner, overgangshistorikk og beregnede fakta. Den inneholder ikke mutable UI-valg eller globale systemfeil. Kildeversionens ID bevares som kildeproveniens; andre templates i en versjonskjede importeres ikke.

Importert original er skrivebeskyttet i sin egen kategori. Bruk **Opprett ny template fra eksisterende versjon** med ny ID og navn for å lage en egen redigerbar kopi. Samme importoperasjon gjenbruker sin kvittering; samme gjæringsarkivpar importeres én gang. Separate template-importer får egne unike IDs også når navn og kildeversjon er like.

Import er tillatt mens gjæring pågår. Filkontroll og SQLite kjører i en worker thread; en egen forbindelse til den samme MariaDB-instansen eier hele importtransaksjonen. Den ordinære motorens mysql-node og autoritative dataflyt beholdes. Dette er en avgrenset filoverføringsadapter, ikke en ny beregnings- eller rapportmotor. Ingen manuell kø, fil-lås eller lokal domenestate innføres.

Midlertidig filopplasting går som autentiserte HA-hendelser med 64 KiB deler og DB-kvittering. Disse byte-delene er transport, ikke domenelagring. Maksimal filstørrelse er 512 MiB. Historikk blir tilgjengelig i sammenligningslisten etter import; **Skjul fra sammenligning** legger til en synlighetshendelse og sletter ingen data. Bare eksplisitt støttede eldre SQLite-skjemaer konverteres; ukjente, uvedkommende og fremtidige formater avvises. Tidligere JSON-arkiver konverteres ikke i denne versjonen.

Alle runtime-søk og grafer bruker MariaDB etter import. Filstørrelsen bestemmes av faktisk historikk; SQLite fjerner JSONs gjentatte feltnavn, men gir ingen garanti om en bestemt komprimeringsfaktor. Alle eksisterende målepunkter beholdes i arkivet.

## P24r11 arkivbruk

Gjæringsarkiv og template-arkiv ligger øverst i Template og arkiv. Eksport av en gjæring gir gjæring.sqlite, template.sqlite, én SHA-fil per SQLite-fil og rapport.html med samme prefix. Eksport av bare template gir template.sqlite og SHA. Last ned lenkene for settet. Ved import velges filene samlet; deretter template-navn og ønsket innhold. SHA-advarsler kan aksepteres ved å gjennomføre importen.

Gamle lokale og importerte gjæringer kan slettes fra MariaDB etter bekreftelse. Eksportfiler beholdes, og aktiv gjæring er beskyttet. Importert template kan bare slettes når den ikke lenger brukes; egen kopi basert på originalen teller også som referanse.

## Importer avsluttet gjæring

Bruk ordinært startbilde: template, batchnavn, «Start fra» og første manuelle måleserie. Lagre det angitte starttidspunktet. Angi deretter slutten i feltet ved «Importer avsluttet gjæring». Etter fullført import viser målekilden HISTORISK. Ved feil beholdes cursor og sluttgrense; omstart prøver kun den gjenstående delen. Systemet kan bare hente historikk HA fortsatt har tilgjengelig, og timesstatistikk som krysser slutten kan ikke deles til et presist delintervall.

Under Biologi/Prosesstrinn kan du korrigere eksisterende starter og etterregistrere manglende starter. Databasen avgrenser tidspunktet mellom nabofaser. Manuelle målinger etterregistreres gjennom vanlig målekort; korriger målerundens tidspunkt til faktisk historisk måletid. Rapporter og eksport er tilgjengelige underveis. «Avslutt gjæring» ferdigstiller ved valgt historisk slutt, genererer sluttarkiv og tilbyr ordinær klargjøring.


## Historisk import og HA-gjenoppkobling

Historisk import viser separat at perioden er ferdig behandlet og hvilke måledata som faktisk ble funnet. Kontroller antall femminuttersbøtter, timepunkter og deres tidsgrenser i Teknisk-eksporten. Kun timehistorikk kan gi grafer, men gir ikke ordinær rate-/stabilitets- eller B/P-vurdering. Det er ikke nødvendig å holde importen live for å få etterregistrert en historisk gjæring.

En ventende HA-publisering er synlig som advarsel til den berørte utgangen har bekreftet ny publisering. La forbindelsen/integrasjonen komme opp; systemet leser deretter fersk DB-state på nytt. Ved vedvarende problem hentes Teknisk-eksport og Node-RED-logg. Ugyldige payloads og DB-feil skal undersøkes som reelle feil, ikke avskrives som oppstartsstøy.

Oppgradering støttes fra p24r16 og 2026.11.07-1. Sesjoner, frozen grunnlag, målinger, korreksjoner, templates og kladder bevares. Samme målversjon kan reinstallere filer ved samsvarende migreringskvittering.

## Oppgradering og gjenoppretting

Kjør `./installer/install.sh` som root fra den utpakkede, SHA-kontrollerte pakken. `installer/migrations.json` beskriver kildeversjoner, strukturavtrykk, filrekkefølge og målversjon. Ukjent grunnlag avvises før Node-RED stoppes. Standardløpet har ingen reset-kommando.

Etter stopp lagres `database.sql.gz` (rutiner, triggere, hendelser og alle data), `flows.json`, eventuell `flows_cred.json` og SHA-kontroll i en privat katalog under Node-RED `/data/gjaeringsassistent/backups/`. Konkret hoststi står i installasjonsrapporten. Backupkatalogen har kun root-tilgang og skal ikke legges på GitHub eller i HA-public. Backup beholdes inntil brukeren velger opprydding.

Ved feil etter stopp: les `last_step`, logg og backupsti. Node-RED startes ikke automatisk med en delvis oppgradert database. DDL kan ikke rulles tilbake som én vanlig InnoDB-transaksjon; backupen er tilbakeføringsgrunnlaget. Undersøk feilen før ny installasjon.

Tilbakeføring er en separat, uttrykkelig driftsbeslutning: hold Node-RED stoppet, kontroller SHA og `gzip -t`, gjenopprett dumpen til en tom Gjæringsassistent-database, og legg tilbake flow/credentials med samme UID/GID som før. Eksisterende delvis oppgraderte objekter må ikke blandes med gammelt schema. Denne tømmingen er en valgt gjenoppretting, aldri del av installasjonen. Den lokale integrasjonstesten prøver faktisk dump og gjenoppretting; målmiljøets Docker-transport må fortsatt bekreftes.

Nye startfelt leser databasekladden direkte. Verdier som manglet før oppgradering blir fortsatt eksplisitt manglende og må registreres av brukeren; gamle HA-verdier importeres ikke automatisk.

Den nye startflaten forutsetter oppdatert dashboard-YAML. Når Home Assistant leser den publiserte YAML-filen direkte, lastes dashboardet på nytt etter installasjon. Hvis YAML tidligere er kopiert/importert manuelt til et dashboard i lagringsmodus, oppdater denne kopien fra `dashboard/gjaeringsassistent-dashboard.yaml` i den nye pakken. Filpublisering endrer ikke en separat lagret Lovelace-konfigurasjon.

## Velg målekilder

Åpne Teknisk → Målekilder og sensorer → Kontroller sensorer. Velg SG, temperatur, siste MQTT-oppdatering og RSSI; trykk kan stå Manuell registrering. En trykksensor må levere overtrykk i en støttet enhet (bar, kPa, hPa/mbar, Pa eller psi). Absolutt trykk må ikke velges som overtrykk. Temperaturkilden i denne versjonen må levere °C.

Lagre og vent på databasekvittering. Endringer under en reell livegjæring får virkning ved den oppgitte DB-grensen. Konfigurasjonshistorikken viser tidligere valg; feltverdier er merket sist kontrollert. Arkiverte/historiske sesjoner endres ikke av et nytt globalt valg. Trykk fra HA-timesstatistikk er ikke lagt til; trykkimport gjelder detaljgrunnlag i femminuttersbøtter.
