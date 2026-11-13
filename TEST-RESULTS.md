# Testresultater for 2026.11.13-1

Alle 39 automatiserte TEST har bestått den komplette releaseporten. Modellen har i tillegg 14 UAT. Den komplette releaseporten kontrollerer både kildekode/pakke og kildebundne native bevis. De 14 UAT beholder sine faktiske målmiljøstatuser; de er ikke gjennomført i brukerens installasjon som del av denne leveransen.

## Utført native verifikasjon

- Faktisk MariaDB 12.3.3: 216 permanente InnoDB-tabeller og 193 views; constraints, nullable-felt/fraværsmetadata, transaksjoner, rollback, read_only-varianter og runtime-spørringer. Runtime-schema 11, template-schema 4.
- Komplett første målesett: alle 19 operatørfelter, ulike verdier, sensorisk 0 og Unicode-notat i nøyaktig én initial observasjon ved pitch. Sen feil ruller sesjon, frozen grunnlag og observasjon tilbake samlet. Senere kladdendring bevarer startobservasjonen. Slurry, eksplisitt NULL, samtidig kladdendring, feltvise forsøk og operativ P/B-telling prøves også.
- Faktisk B/P-evaluering uten kontinuerlig målegrunnlag: manglende verdi forblir manglende; tillatt fravik kan registreres og trekkes tilbake gjennom faktisk HA-event/NR/DB-bane. Readiness følger samme DB-grunnlag. Biologisk tilbaketrekking virker også etter en nyere evaluering, uten omskriving av opprinnelige fakta.
- Sensoriske slidere og temperaturpresisjon fra DB-register/read-model; HA-katalog, kompatible valg, lagringskvittering og avvisning av gammel revisjon/feil enhet. Valgfritt trykk, kPa til bar, detaljimport uten trykksensor og frosne kildebytter ved riktig bøttegrense. Lesbare tekniske kilder beholder rå identitet.
- Faktisk Chromium 157 kjører det leverte kortet: sliderendepunkt 0/5, ingen skriving ved montering, temperatur med én desimal, HA-kontroll/sensorvalg, bevart ulagret redigering, DB-kvittering, SQL-genererte B/P-kontroller og mobilbredde. HA-skall/transport er kontrollert. Dette er ikke målmiljø-UAT.
- Faktisk HA-plugin 0.80.3: schema-/controller-validering av SQL-genererte payloads, livsløp, frakobling/gjenoppkobling og utgangskvittering med simulert transport.
- Historisk fra–til, fem avgrensede importchunks, 578 målepunkter, fast domenehorisont, etterregistrering, B/P-tidsgrenser og append-only korreksjoner. Seks felles grafer, sammenligning og samme dashboard-/rapporttegner.
- SQLite-par, aktivt snapshot, komplett målehistorikk, store arkiver, feil filpar, SHA-advarsler, import/sletting/rollback, samtidige rapporter og måleskriving. Konstruert fixture med eksakt eldre sensorprofilskjema prøver bevarte arkiverte ID-er ved cursor, manuelt trykk, uregistrerte eldre kildebytter/grenser og rundtur uten å endre aktive sensorvalg. Ukjent skjema og ugyldig binding avvises atomisk. Dette er ikke et innhentet gammelt brukerarkiv.
- Ytelse med 6048 femminuttersmålinger over 21 døgn og tre historiske serier: privat lesing, billig uendret polling og samtidighet. Den gamle p24r13-leseplanens fjernede entity-ID-kolonner leveres av dagens kompatibilitetsview i benchmarken; grafalgoritmer/spørringsform er uendret. Lokale tall er ikke responstidsgarantier for gangpc.

## Installer og databevaring

Faktisk install.sh fra en uendret bygget ZIP-kopi prøves mot native MariaDB fra p24r16, 2026.11.07-1, 2026.11.09-1 og 2026.11.09-2. Docker-transport og Node-RED-beredskap simuleres. Root-kravet kjøres i et upriviligert user namespace med mappet testbruker; host-privilegier er uendret. Aktiv og beholdt tidligere gjæring, frozen grunnlag, kladd, Unicode-notat og øvrige opprinnelige domenetabeller sammenlignes før/etter. Flyttede sensor-ID-er sammenlignes via den deklarerte kompatibilitetsvisningen; begge sesjoner får fem fryste signalbindinger.

Den komprimerte backupen gjenopprettes på en separat MariaDB-instans med samme databasenavn, og alle bevarte domenetabeller/aktiv sesjon sammenlignes. Ukjent kilde, endret struktur, feil gammel kvittering og mislykket backup skal avvise før migrering. Reinstallasjon og tom database uten syntetisk sesjon prøves. Krav-/test-ID-er og sortering sammenlignes med hele den nye katalogen etter oppgradering.

P24r16/2026.11.07-1-fixturen er den komplette Git-taggen v2026.11.07-1 med byte-identisk fysisk p24r16-DDL; versjonsmarkøren varieres eksplisitt. Det opprinnelige p24r16-installasjonsarkivet er ikke kjørt her. 09-1/09-2 bruker eksakte publiserte Git-tagger.

## Bevis, omkjøringer og begrensninger

verification/native-environment.json og native-integration.log beskriver faktisk miljø/kjøringer. Se start-control-regression.json, operator-config-regression.json, operator-ui-regression.json, install-upgrade-regression.json og øvrige native regresjonsfiler. Kildeavtrykk kontrolleres av releaseporten; eldre bevis er ikke bare ommerket. verification/release-results.json registreres først etter komplett grønn releaseport.

Samlet logg beholder også første feil og etterfølgende vellykkede grupper. Utdaterte forventninger om view-antall og fysisk kildeprofil ble tilpasset den nye kontrakten. En fast dato i den samtidige testskriveren kunne kollidere med dens egne tidligere punkter; neste gruppe starter nå etter faktisk siste testpunkt. Upgrade-testen avdekket en reell metadata-sorteringskollisjon; generatoren flytter eksisterende sorteringsverdier før upsert på stabile ID-er og publiserer katalogen atomisk. De berørte kontrollene kjøres på nytt; domenereglene er ikke svekket for å få PASS.

Serverens bufferpool er 128 MiB, adresseplassgrense 4 GiB og MALLOC_ARENA_MAX=2. Den tidligere 2 GiB-adresseplassgrensen var utilstrekkelig under innlasting av views; dette var testmiljøet. Produksjonsinstallasjon, reell Recorder-import, installert HA-nettleserflyt og faglig kalibrering er ikke utført her. Følg dokument 09/15 for måltester.
