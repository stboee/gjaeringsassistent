# Gjæringsassistent – videreføring

Leveranse **2026.11.09-1 – Databevaring og trygg oppstart**. Teknisk utgangspunkt er p24r16 og første GitHub-utgave 2026.11.07-1. Se VERSION, BUILD-INFO.json, Git-tag og release-artefakt for faktisk identitet; dokumentasjon på main kan være nyere enn en publisert pakke.

## Ny chat

Følg [onboarding-instruksjonen](docs/ONBOARDING-NY-CHAT.md). Les AGENTS.md, dokumentkart 00, aktive beslutninger 14, relevante kontrakter og de strukturerte SQL-/registry-kildene. Skill kode, lokal test, publisert pakke og faktisk installasjon. Diskuter neste arbeid før «start»; allerede autorisert arbeid videreføres uten gjentatte godkjenninger.

## Denne leveransen

- Databevarende installasjon fra `0.1.0-prototype24-r16` eller `2026.11.07-1`; tom database initialiseres. Samme målversjon kan reinstallere filer med samsvarende migreringskvittering. Manifestet står i installer/migrations.json.
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

Nåværende oppgraderingsbestilling omfatter bygg/publisering, ikke kjøring på brukerens server. Ingen ny implementeringsoppgave er avtalt utover denne leveransen. Ved videre feil: les fersk teknisk rapport, skill aktive feil fra historiske hendelser og følg HA/NR/read-model til autoritativ DB-kilde.
