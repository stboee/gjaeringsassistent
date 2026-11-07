# Testresultater for 2026.11.07-1

Første GitHub-utgave er kontrollert med ny kjøring av native MariaDB-integrasjon og den komplette automatiserte releaseporten. P24r16-resultater er ikke bare ommerket. Alle 35 automatiserte TEST registreres med PASS etter bestått kjøring; de 14 UAT har ikke en registrert målmiljøkjøring for datoversjonen.

## Utført

- Faktisk MariaDB 12.3.3 med ren installerrekkefølge, constraints, rollback, read_only-moduser, alle 178 views og reelle runtime-spørringer.
- Faktisk HA-plugin 0.80.3: validering av SQL-genererte payloads, Start/livsløp, publisering, frakobling/gjenoppretting og utgangskvittering. HA-transporten er simulert.
- Kriteriekorreksjoner, B/P-tid og historisk fra–til, fast horisont, 578 målepunkter i fem bolker og SQLite-rundtur.
- Seks felles grafer i dashboard/rapport, sammenligning, egne målemarkører, datoer, typed schema-/fraværsmetadata og generering av kontrakter.
- SQLite-par, store arkiver, feil filpar, SHA-advarsler, import/sletting, rollback, måleskriving under overføring og tolv samtidige rapporter.
- Ytelse med 6048 femminuttersmålinger over 21 døgn og tre komplette historiske serier, private lesinger og billig uendret polling.
- Full releaseport: dokument-/kontrakt-/metadata-/arkitekturkontroller, flowbygging, installerens preflight og JavaScript-regresjonene.
- Ny pakkegrense er prøvd med lokale credential-/nøkkel-/Git-/byggfiler og bevarte kilde-/database-/komprimerte testfiksturer. Versjonsformat, gyldig npm-representasjon, workflow-YAML og shellsyntaks er kontrollert.

## Testmiljø og justering

Isolert native server med 64 MiB bufferpool, Node.js 24.22.1 og pakket HA-plugin 0.80.3. Native tester som bruker dateStrings følger UTC-kontrakten og kjøres med TZ=UTC. Ytelsestesten er også bestått med Europe/Oslo.

Kontrollen av klokkefremrykking i ytelsestesten avdekket en tidssoneavhengig testforutsetning. Den er rettet til å bruke det frosne Unix-tidspunktet og DB-policyens refreshintervall direkte. Den eksisterende runtime-pollingen er uendret. Tidlige mislykkede testforsøk er beholdt i native-loggen; endelig bestått kjøring og de ferske kildeavtrykkene er grunnlaget for PASS.

Ny full oversikt: 8850 ms / 54523 Rows_read. Uendret poll: 8 ms / 371 Rows_read. Dette er lokale målinger, ikke en responstidsgaranti for gangpc. Rows_read er ikke Rows_examined.

## Bevis og begrensninger

Se verification/native-integration.log, verification/release-gate.log og verification/release-results.json. De native regresjonsfilene har fortsatt sine etablerte testnavn, men application_version er 2026.11.07-1 og kildeavtrykk er kontrollert. Fysisk katalog kommer fra den nye MariaDB-kjøringen: 202 permanente InnoDB-tabeller og 178 views.

Brukeren har bekreftet at p24r16 fungerer fint. Ingen faktisk HA-/nettleser-UAT er utført som del av denne publiseringen. Målmiljøets nettverk, tidssoner, Recorder, reconnect og operatørflyt må vurderes med konkrete målresultater. Faglig kalibrering av gjærprofiler/valideringsgrenser er fortsatt åpen.

**Prototypeinstalleren resetter databasen.** Denne releasekontrollen er ikke en databevarende produksjonsoppgradering.
