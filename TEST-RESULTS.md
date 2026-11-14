# Testresultater for 2026.11.14-1

Komplett releaseport er grønn: 39 automatiserte TEST er registrert PASS etter kjøring mot gjeldende kilde og kontroll av kildebundne native bevis. Modellen har i tillegg 14 UAT; målmiljøtestene er ikke automatisk lukket.

## Endringsrettet kontroll

Den publiserte 2026.11.13-1 hadde en konkret produsent-/publisererfeil: source_path ble sendt der den eksisterende publisereren krever stage_path. Den utvidede tests/test-p24r8.js reproduserte feilen før rettingen og bestod etterpå. Den prøver faktiske flowargumenter/koblinger, shell-rundtur, fysisk JSON/gzip-publisering og tilbake-lesing og synlig feilrapportering. Dette er en transporttest med eksplisitt fixture, ikke en faglig DB- eller målmiljøtest.

## Native regresjon

Gjeldende kilde har bestått kontroll mot faktisk MariaDB 12.3.3 med 216 permanente InnoDB-tabeller og 193 views, runtime-schema 11 og template-schema 4. Gruppene omfatter komplett første målesett/rollback, B/P-fravik, sensorvalg og frosne bindinger, Systemkontroll, faktisk plugin 0.80.3, seks felles grafer/rapporter, SQLite-par og eldre skjema, historisk import/tid, kontrakter og samtidighet.

Chromium 157 har prøvd levert kortkode med kontrollert HA-skall og reelle DB-/Node-RED-funksjoner. Ytelsesfixturen har 6048 femminuttersmålinger over 21 døgn og tre historiske serier. Den gamle p24r13-leseplanens fjernede entity-ID-kolonner leveres av kompatibilitetsviewet i benchmarken; grafalgoritmer/spørringsform er uendret. Lokale tall er ikke responstidsgarantier for gangpc.

## Installer og databevaring

Faktisk install.sh har bestått fra en uendret bygget ZIP-kopi mot p24r16, 2026.11.07-1, 2026.11.09-1, 2026.11.09-2 og 2026.11.13-1. Docker-transport og Node-RED-beredskap simuleres. Root-kravet kjøres i et upriviligert user namespace med mappet testbruker; host-privilegier er uendret.

Den nye 13-1-banen bruker files-planen uten å kjøre domene-DDL, rutiner eller views. Aktiv og beholdt tidligere gjæring, frozen grunnlag, kladd, Unicode-notat og opprinnelige domenetabeller sammenlignes før/etter. Den faktiske komprimerte backupen gjenopprettes på en separat MariaDB-instans med samme databasenavn og sammenlignes. Ukjent kilde, endret struktur, feil gammel kvittering og mislykket backup skal avvise før migrering; reinstallasjon og tom database prøves også.

P24r16/2026.11.07-1-fixturen er komplett Git-tag v2026.11.07-1 med byte-identisk fysisk p24r16-DDL; versjonsmarkøren varieres eksplisitt. Det opprinnelige p24r16-installasjonsarkivet er ikke kjørt her. Senere kilder bruker eksakte publiserte Git-tagger.

## Bevis og begrensninger

verification/native-environment.json og native-integration.log beskriver faktisk miljø. Se start-control-regression.json, operator-config-regression.json, operator-ui-regression.json, install-upgrade-regression.json, p24r8-presentation-regression.json og øvrige native resultater. Kildeavtrykk kontrolleres av releaseporten. Eldre bevis gis ikke ny versjon eller dato uten ny kjøring. verification/release-results.json registrerer 39 PASS etter komplett grønn releaseport.

Testserveren bruker 128 MiB bufferpool, 4 GiB adresseplassgrense og MALLOC_ARENA_MAX=2. Ingen produksjonsinstallasjon eller faktisk Recorder-/HA-nettleser-UAT er utført. Målmiljøbekreftelse av rettingen og øvrig faglig kalibrering følger dokument 09/15.
