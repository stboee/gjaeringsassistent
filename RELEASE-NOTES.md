# 2026.11.14-1 – Rettet publisering av sensorinnstillinger

- Retter HTTP 404 i «Målekilder og sensorer»: publiseringsjobben bruker eksisterende `stage_path`-kontrakt. `source_path` var et feil argumentnavn i den nye produsenten.
- Publiseringsresultat og stderr følger den felles feilrapporteringen til Teknisk hendelseslogg.
- Regresjonstesten prøver produsent, argumenter, fysiske koblinger, shell-rundtur, faktisk JSON/gzip-publisering, tilbake-lesing og feilrapportering.
- Dokumenterer den tekniske publiseringskontrakten eksplisitt. Domenedata og faglige beregninger er uendret.
- Installer støtter databevarende filoppgradering fra 2026.11.13-1 med kjent fysisk struktur og verifisert tidligere migreringskvittering. Denne banen endrer versjonsmetadata og leverte filer; domenetabeller, rutiner og views beholdes. Eldre støttede oppgraderingsbaner videreføres.

Leveres som samlet ZIP/SHA med ordinær installer. Kjør `./installer/install.sh` fra den utpakkede pakken. Målmiljøbekreftelse gjenstår; se TEST-RESULTS.md og dokument 09/15.

## Tidligere utgaver

# 2026.11.13-1 – Målesett, sensorer og kriteriefravik

- Start lagrer ett komplett første målesett atomisk med sesjonen. Utvidet regresjon prøver alle inputfelter, registrert 0, Unicode, sen rollback og B/P-fravik ved manglende kontinuerlig grunnlag.
- Sensoriske 0–5-slidere viser eksplisitt manglende verdi og registrert 0. Temperaturfelt bruker én desimal fra DB.
- Målekilder og sensorer øverst i Teknisk, med HA-kontroll, sensorvalg, lagring, DB-kvittering og fryst kildehistorikk. Valgfritt overtrykk støtter flere enheter i detaljimporten.
- SQLite-import gjenkjenner det eksakte eldre sensorprofilskjemaet og bevarer arkiverte bindinger ved importcursor, uten å endre dagens sensorvalg.
- Lesbare tekniske kildenavn; rå node-/rutineidentitet beholdes i detaljer/eksport.
- Kriterieavvik i Prosesstrinn er tilbake, også ved manglende målegrunnlag. Biologi/Prosesstrinn bruker samme DB-transaksjon og beholder revisjoner.
- Verifikasjonskatalogen oppdateres atomisk uten sorteringskollisjon når nye krav legges til.
- Databevarende oppgradering fra p24r16, 2026.11.07-1, 2026.11.09-1 og 2026.11.09-2. Runtime-schema 11, template-schema 4, 216 tabeller og 193 views.

Se TEST-RESULTS.md for faktisk testbevis og åpne måltester. Installer med ./installer/install.sh og last dashboardet på nytt med Ctrl+F5.

## Tidligere utgaver

# 2026.11.09-2 – Rettede startkort

- Retter konfigurasjonsfeil på kortene «Startgrunnlag · lagret i MariaDB» og «Første komplette målesett» etter templatevalg.
- Regresjonstesten bruker de faktiske kortkonfigurasjonene fra dashboardet gjennom samme setConfig-grense som Home Assistant.
- Databevarende filoppgradering fra 2026.11.09-1 kontrollerer struktur og tidligere migreringskvittering. Domenetabeller, rutiner og views endres ikke i denne oppgraderingsbanen. Oppgradering fra p24r16 / 2026.11.07-1 er fortsatt støttet.

Installeren er kjørbar direkte fra den utpakkede pakken. Installer med `./installer/install.sh` og last Home Assistant-dashboardet på nytt med Ctrl+F5. Se TEST-RESULTS.md for faktisk testomfang; nettleser-UAT i målmiljøet er fortsatt åpen.

## Tidligere utgaver

# 2026.11.09-1 – Databevaring og trygg oppstart

- Installer oppgraderer fra p24r16 eller 2026.11.07-1 uten å nullstille databasen. Verifisert privat database-/flowbackup før mutasjon, strukturkontroll og migreringskvittering. Samme målversjon kan reinstallere filer.
- Startfelt viser aktuell databasekladd direkte. Slurryvolum/generasjon som mangler vises som manglende; gamle HA-tall er ikke grunnlag. Eksplisitt samme-verdi-lagring støttes.
- DB eier startklarstatus, feltvise avvisninger og lagrede startforsøk. Teknisk eksport inkluderer de ti siste forsøkenes snapshots.
- Systemkontroll avgrenser P/B-telling til aktiv operativ sesjon og oppdager reelle doble åpne besøk.
- Normaliserte metadata, HA-kontrakt, dokumentasjon og regresjonstester oppdateres samlet. Ingen endringer i grafmotor eller gjæringsprofiler.

Se TEST-RESULTS.md for faktisk bevis og begrensninger. Lokal HA-/Docker-transport er simulert; installasjon og brukerflate på gangpc er ikke målbekreftet.

## Tidligere utgave

# 2026.11.07-1 – Første GitHub-utgave

Første utgave i nytt repository, med siste fungerende p24r16 som teknisk grunnlag.

- Datoversjon ÅÅÅÅ.MM.DD-N samordnes i applikasjon, databaseforventninger, HA-kontrakt, frontendpublisering og leveransemetadata.
- README, overlevering og AGENTS.md beskriver gjeldende arkitektur og arbeidsmåte. Direkte arbeid på main etter avklaring og «start»; issues/PR inngår ikke i prosessen.
- Konkrete faglige nettlenker videreføres i W-34/70-faggrunnlaget. De er kildekandidater, ikke automatisk belegg for aktive terskler.
- Pakkebyggingen fungerer fra Git-checkout og lager versjonert ZIP/SHA uten Git-metadata, lokale driftsfiler eller tidligere bygg.
- Ytelsestestens klokkefremrykk bruker Unix-tid og DB-policy uavhengig av sesjonstidssone; runtime-logikken er uendret.
- MIT-lisensen fra det nye repositoryet er bevart. Releasejobben kontrollerer og publiserer ZIP og SHA for kildecommitten.

MariaDB 12.3.3, Node-RED 5.0.7, HA-plugin 0.80.3 og mysql-palett 3.0.4 videreføres. Runtime-schema er 9 og template-schema 4. Se TEST-RESULTS.md for faktisk testomfang og åpne måltester.

**Installeren resetter fortsatt databasen. Utgaven er ikke en databevarende produksjonsoppgradering.** Eksporter sesjoner/templates som skal beholdes før tilsiktet installasjon. Neste avgrensede arbeid er et oppgraderingsløp med bevaring av data.
