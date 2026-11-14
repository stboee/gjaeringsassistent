---
doc_id: DOC-08
role: operations-guide
status: current
source_format: markdown
---

# 08 – Driftsveiledning

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

## Installere/reinstallere

Gjeldende release bruker **MariaDB 12.3.3**, fast tag `mariadb:12.3.3`. Oppdater bare eksisterende `gjaeringsassistent-mariadb`-tjeneste i den samlede compose-filen: behold databasevolum, nettverk og credentials, endre image til `mariadb:12.3.3` og sett `MARIADB_AUTO_UPGRADE: "1"` under `environment`. Referansefragmentet finnes i `compose/mariadb-service.yaml`. Ikke opprett en konkurrerende databasecontainer.

Fra katalogen med den eksisterende compose-filen, bruk samme compose-valg som normalt:

```bash
docker compose pull gjaeringsassistent-mariadb
docker compose up -d --no-deps gjaeringsassistent-mariadb
docker exec gjaeringsassistent-mariadb sh -lc 'mariadb -N -B -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" -e "SELECT VERSION()"'
```

Vent til containeren er healthy og versjonsspørringen viser `12.3.3-MariaDB...`. `MARIADB_AUTO_UPGRADE` lar det offisielle imaget oppdatere MariaDBs egne systemtabeller ved behov. Gjæringsassistent oppgraderer deretter applikasjonsskjemaet gjennom sin egen databevarende migrering. MariaDB-systemoppgradering og applikasjonsmigrering er separate operasjoner.

Node-RED-containeren må kjøre for at installeren skal kontrollere installerpakker og lese faktisk UID/GID. Hvis den er stoppet, kjør `docker start gjaeringsassistent-nodered` først. Installeren avviser stoppet/restarting container før database- og flowendringer, med egen diagnose.

Oppgradering fra 2026.11.13-1 til 2026.11.14-1 er en fil-/versjonsoppdatering: kjent fysisk struktur og tidligere migreringskvittering kontrolleres, domenetabeller/rutiner/views beholdes, og privat backup tas før endring. Eldre støttede kildeversjoner følger sine deklarerte migreringer i installer/migrations.json.

Kjør `./installer/install.sh` fra den utpakkede releasepakken. Eksisterende data bevares; baseline/seeds brukes bare på tom database. Installeren installerer schema/seeds/views, Node-RED-flow og frontendkilde, men kjører ikke syntetisk Start, Systemkontroll eller andre runtime-akseptansetester.

Før mutasjon leser installeren serverversjonen og sammenligner med `BUILD-INFO.json`. Annen versjon avvises før database- eller flowendringer. Faktisk serverversjon følger `.json`-rapporten som `database_server_version`.

Installerresultat skrives som `.json` og `.log` under `install-reports/`. Ved FAIL brukes `last_step` og tilhørende logg; installerfeil skal løses som installer-/DDL-/flowfeil, ikke maskeres med runtime-workarounds.

## Etter vellykket installasjon

1. Åpne Home Assistant → **Teknisk**.
2. Hard refresh (`Ctrl+F5`) dersom browseren viser gammel frontend.
3. Kontroller at frontendpublisering viser samme releaseversjon som pakken.
4. Kjør **Systemkontroll** dersom den automatiske kontrollen ikke allerede er fersk.
5. Bruk **Aktive problemer**, **Teknisk hendelseslogg**, **Målekilde/Tilt** og **Systemkontroll** til diagnose.

`NOT_APPLICABLE` er ikke feil når kontrollen eksplisitt er utenfor gjeldende operativ kontekst.

## Frontendpublisering

Node-RED publiserer dashboard, custom card og loader ved oppstart fra staging til `/data/gjaeringsassistent/ha-public`. Publisering registreres med releaseversjon og SHA-256 i MariaDB. Installeren skal ikke skrive direkte til en katalog som skjules av bind-mount.

Hvis `custom:gjaeringsassistent-card` mangler, kontroller Lovelace-resource mot `/local/gjaeringsassistent/gjaeringsassistent-card-loader.js` og frontendpubliseringsstatus i Teknisk.

## Eksporter Teknisk

**Eksporter Teknisk** lager et read-only diagnostisk JSON-snapshot under HA-public `exports/` med lokal tid i filnavnet. Snapshotet inneholder relevant HA-projeksjon, MariaDB-runtime/pre-start/sessiongrunnlag, målekildestatus, tekniske hendelser og siste Systemkontroll. I tillegg genererer Node-RED periodisk `gjaeringsassistent-teknisk-status-latest.json` direkte fra MariaDB-read-modellen. Nedlastingsnavnet har timestamp-prefix med millisekunder, også for sistefilen, slik at tidligere nedlastinger bevares. Statusfilen viser DB-/Node-RED-/publisert frontendversjon og DB-/HA-templatealternativer. Kontroller alltid eksporttid og versjoner før filen brukes til å diagnostisere en ny feil. Denne sistefilen gjør diagnostikk tilgjengelig selv om HA-eventbanen for den manuelle eksportknappen er midlertidig utilgjengelig.

Ved feilsøking er disse filene foretrukket fremfor manuell kopiering av enkeltmeldinger. De er kun diagnostikk og er aldri restoreautoritet.

## Template-editor

Praktisk bruk er samlet i [operatørveiledningen](20-OPERATOERVEILEDNING.md). DB-kvitteringen er grunnlag for lagret/utført status.

## Referansedemo

Praktisk bruk er samlet i [operatørveiledningen](20-OPERATOERVEILEDNING.md). DB-kvitteringen er grunnlag for lagret/utført status.

## Ordinær Start med Home Assistant-history

Praktisk bruk er samlet i [operatørveiledningen](20-OPERATOERVEILEDNING.md). DB-kvitteringen er grunnlag for lagret/utført status.

## Datakvalitet

SG, temperatur og RSSI valideres mot frozen sessionregler før `measurements_5m`. Ugyldige samples forkastes; de skal ikke repareres med DB-edit, frontendfilter eller clamp. Kvalitetsutfall finnes i `measurement_ingest_quality_events`.

En tom start på en Analyse-kurve er korrekt inntil minste beregningsgrunnlag finnes. P24r7 viser kun ordinære punkter når faktisk minste tid, antall og dekning er oppfylt. En fysisk/matematisk urimelig verdi skal derimot avvises og være sporbar som valideringshendelse.

## Målekilde/Tilt

Teknisk viser DB-read-modelen for målekilden. Ved aktiv reell session forventes minst profil, sessionbinding, importcursor, sist-OK, siste 5-minuttersmåling, sample count, SG-statistikk, temperatur, RSSI og gapstatus. Tom/`IKKE KJØRT` HA-projeksjon samtidig som DB-status er LIVE er en projeksjons-/integrasjonsfeil og skal fremgå av Technical Events/Systemkontroll.

## Tid

Persistent maskintid er UTC. Operative tidspunkt vises i `Europe/Oslo`. Lokal visning skal ikke brukes som alternativ persistent tidsautoritet.

## Verifikasjon og UAT

Fanen **Verifikasjon** viser DB-avledet TECH/FUNC/UAT-status og REQ→VER→TEST-relasjoner. UAT registreres som nytt append-only resultat med operatør/notat/evidence; tidligere gjennomføringer overskrives ikke. **Eksporter verifikasjon** lager både maskinlesbar JSON og lesbar HTML fra samme konsistente DB-grunnlag under HA-public `exports/`. Teknisk-fanen viser bare et kompakt sammendrag og lenker videre til detaljflaten.

## Historikk, demo og grafvalg

Praktisk bruk er samlet i [operatørveiledningen](20-OPERATOERVEILEDNING.md). DB-kvitteringen er grunnlag for lagret/utført status.

## Kontroll av publisering og diagnostikk

Etter installasjon: Start reell import, kontroller at Gjæring viser grafene, velg Gyllen pils som sammenligning og vent på DB-kvittering. Valget skal bestå neste periodiske refresh. Analyse skal vise SG/temperatur/trykk før analysegrafene; prøv 5/30/60 minutter og kontroller at gap og nå-verdier er konsistente. Generer aktiv rapport og kontroller høyere grafer. Kjør Systemkontroll med Oslo-tid; skjema og klokke skal være OK. Eksporter både Teknisk og Utvidet diagnostikk. Sistnevnte skal inneholde `frontend_diagnostics.published_payload`; normal eksport skal bare inneholde sammendraget.

I nettleserens Network-fane kan JSON-kallet kontrolleres for Content-Encoding: gzip. Manglende HTTP-komprimering betyr at HA-serverens forhandling må undersøkes; den tapsfrie gzip-sidefilen finnes uansett for direkte nedlasting.

## Historisk timesstatistikk og live-import

Første import henter detaljhistorikk og tilgjengelige HA-timeverdier. Normal femminuttersoppdatering hopper over statistikk-API-et. DB-cursor med minst én times etterslep utløser historisk innhenting. Dette er en teknisk grense for historisk opphenting, ikke en antakelse om Recorder sin retention. Ved en uløst statistikk-API-feil forsøkes historikken fra kildestart på nytt, slik at eldre manglende timer kan repareres. Detaljdata foretrekkes når begge kilder finnes. Tidligere feil lukkes med én gjenopprettingshendelse; vanlige vellykkede API-svar gir ikke nye driftsmeldinger.

Grafkrav bruker originalparametere pluss gjeldende override. Reset gjeninnfører originalparametere. En eksplisitt tom valgfri grense blir ikke nulltallet. Oppfylt-markøren krever evaluering under akkurat den gjeldende revisjonen, også etter reset. Historisk måle-/evalueringsgrunnlag omskrives ikke.

## Arkivkontroll

Arkivenes format, innhold, integritet og transaksjonsgrenser eies av [dokument 13](13-LIVSLOP-OBSERVASJONER-RAPPORT-OG-HISTORIKK.md#sqlite-arkivenes-innhold-og-integritet). Praktisk filvalg og import beskrives i [operatørveiledningen](20-OPERATOERVEILEDNING.md#arkiver-import-og-sammenligning). Ved feil hentes teknisk eksport; en filkvittering skal kontrolleres før videre handling.

## Arkivadministrasjon

Gjæringsarkiv og template-arkiv ligger øverst i Template og arkiv. Eksport av en gjæring gir gjæring.sqlite, template.sqlite, én SHA-fil per SQLite-fil og rapport.html med samme prefix. Eksport av bare template gir template.sqlite og SHA. Last ned lenkene for settet. Ved import velges filene samlet; deretter template-navn og ønsket innhold. SHA-advarsler kan aksepteres ved å gjennomføre importen.

Gamle lokale og importerte gjæringer kan slettes fra MariaDB etter bekreftelse. Eksportfiler beholdes, og aktiv gjæring er beskyttet. Importert template kan bare slettes når den ikke lenger brukes; egen kopi basert på originalen teller også som referanse.

## Importer avsluttet gjæring

Praktisk bruk er samlet i [operatørveiledningen](20-OPERATOERVEILEDNING.md). DB-kvitteringen er grunnlag for lagret/utført status.

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

Praktisk bruk er samlet i [operatørveiledningen](20-OPERATOERVEILEDNING.md). Ved HTTP 404 for source-settings.json kontrolleres publiseringsresultat og Teknisk hendelseslogg. Feilen med source_path er beskrevet i releasehistorikken; gjeldende kontrakt krever stage_path.

Krav-/beslutningskatalogen er tekniske dokumentasjonsmetadata. Ved filoppgradering oppdateres denne katalogen fra den deklarerte sql/24-verification-metadata-seed.sql slik at kildeposisjoner og visningsrekkefølge følger dokumentene. Krav-/beslutnings-ID-er og tekst bevares; historiske testresultater beholdes.
