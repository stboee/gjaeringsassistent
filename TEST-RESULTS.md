# Testresultater for 2026.11.09-2

Alle 37 automatiserte TEST har bestått releaseporten. 14 UAT er registrert og beholder sine faktiske målmiljøstatuser. Native regresjonsfiler inneholder faktisk application_version, serverversjon og SHA-256 av testede kilder; eldre bevis er ikke bare ommerket. De 14 UAT er ikke gjennomført i brukerens målmiljø som del av denne leveransen.

## Utført verifikasjon

- Faktisk MariaDB 12.3.3: alle 207 permanente InnoDB-tabeller og 183 views, normaliserte relasjoner/fraværsmetadata, transaksjoner, rollback, read_only-varianter og reelle runtime-spørringer.
- Faktisk install.sh og migreringsplan fra p24r16, 2026.11.07-1 og filoppgradering fra 2026.11.09-1, med simulert Docker-transport. Aktiv og beholdt tidligere gjæring, frozen grunnlag, kladd, notater med full Unicode og øvrige domenetabeller har identiske rader etter oppgradering. Samme versjon kan reinstallere filer med én migreringskvittering.
- Faktisk komprimert backup og gjenoppretting på en separat MariaDB-instans med samme databasenavn; gjenopprettede domenetabeller og aktiv sesjon samsvarer. Ukjent kilde, endret databasestruktur og mislykket backup hindrer migrering. Tom database initialiseres uten syntetisk sesjon.
- DB-eid slurry-start gjennom faktisk NR-feltbinding, samme-verdi-lagring, eksplisitt NULL/fravær, presis avvisning og lagrede forsøksfelt. VM-test laster begge faktiske startkort fra dashboard-YAML gjennom setConfig og kontrollerer visnings-/hendelsesgrensen viser at gamle HA-tall ikke blir reservegrunnlag.
- Operativ P/B-telling med beholdt tidligere sesjon. Ingen globale historiske P/B-rader teller som en ekstra aktiv gjæring.
- Faktisk HA-plugin 0.80.3: validering av SQL-genererte payloads, Start/livsløp, frakobling/gjenoppkobling og utgangskvittering; transporten er simulert.
- B/P-kriterier og tidskorrigeringer, historisk fra–til, fast domenehorisont, seks felles grafer, sammenligning og samme dashboard-/rapporttegner.
- SQLite-par, store arkiver, feil filpar, SHA-advarsler, import/sletting/rollback og samtidige rapporter/måleskriving. Startdiagnostikk blokkerer ikke sletting av ubrukt importert template.
- Ytelse med 6048 femminuttersmålinger over 21 døgn og tre historiske serier; privat lesing, uendret polling og samtidighet. Lokale målinger er ikke responstidsgarantier for gangpc.

## Bevis og begrensninger

Se verification/native-integration.log, verification/start-control-regression.json, verification/install-upgrade-regression.json, øvrige kildebundne regresjonsfiler og verification/release-results.json. verification/native-environment.json beskriver faktisk miljø. Runtime-schema er 10, template-schema 4.

Testene bruker isolerte localhost-databaser. Docker-kommandoenes transport, Node-REDs containerberedskap og HA-nettverket simuleres; dette er ikke faktisk Docker/HA-/nettleser-UAT. Produksjonsinstallasjon, reell Recorder-import, nettleserinteraksjon og faglig kalibrering er ikke utført her. Følg dokument 09/15 for måltester.
