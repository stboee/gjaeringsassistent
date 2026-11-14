# Gjæringsassistent – videreføring 14.11.2026

Versjon **2026.11.14-1 – Rettet publisering av sensorinnstillinger**. Forrige publiserte utgave er 2026.11.13-1, kildecommit 309625238899dce6a69c7f4b2536ae8f1cb3e9a7. VERSION, BUILD-INFO.json, tag og bygget releasepakke fastslår leveranseidentiteten. Main kan ha nyere dokumentasjon enn publisert pakke.

## Ny chat og arbeidsmåte

Følg [onboarding-instruksjonen](docs/ONBOARDING-NY-CHAT.md), AGENTS.md og dokumentkart 00. Les relevante normative dokumenter og de faktiske SQL-/registry-kildene. Arbeid direkte på main uten issues/PR. Allerede godkjent arbeid videreføres uten en ny «start»-runde.

Brukeren har bedt om ny samlet ZIP, tag og GitHub Release for denne rettingen. Bestillingen er startet og omfatter bygg/publisering, ikke installasjon eller restart på brukerens server.

## Rettelsen og den eksisterende kontrakten

Brukeren har installert 2026.11.13-1 og viser 14.11.2026 «Sensorinnstillinger: HTTP 404» for /local/gjaeringsassistent/source-settings.json, samtidig som Systemkontroll viser OK. Den nye kortkoden lastes.

Årsaken er reprodusert: source_settings_result_v1 sendte source_path, mens tools/publish_payload.js leser stage_path. Samme stage_path-kontrakt fantes allerede for gjæringsoversikt og teknisk eksport. source_path var et feil argumentnavn i den nye sensornoden; rettingen endrer ikke publiseringsgrensesnittet. Dokument 05 beskriver nå kontrakten eksplisitt.

Produsenten sender stage_path. Exec-resultat og stderr er koblet til den eksisterende felles resultat-/feilrapporteringen slik at nye publiseringsfeil blir synlige i Teknisk hendelseslogg. Ingen faglige beregninger eller domenemodell endres.

Den utvidede tests/test-p24r8.js prøver faktiske produsentargumenter, fysiske flowkoblinger, shell-rundtur, JSON/gzip-publisering og tilbake-lesing samt feilrapportering. Testen reproduserte feilen før rettingen og bestod etterpå. Transportfixturet er ikke konstruert faglig målegrunnlag. Beviset har kildeavtrykk og kontrolleres i releaseporten.

## Levering og databevaring

Rettelsen leveres samlet med ordinær installer. Manuell redigering av source_path er ikke en forutsetning for denne pakken.

Fra 2026.11.13-1 brukes en egen files-plan: den krever samme fysiske målstruktur og samsvarende tidligere migreringskvittering, oppdaterer leverte filer og versjonsmetadata og beholder domenetabeller, rutiner og views. Privat backup tas før endring. Eldre støttede kilder p24r16, 2026.11.07-1, 2026.11.09-1 og 2026.11.09-2 følger deklarerte migreringer. Ukjent struktur/versjon eller feil kvittering avvises.

Runtime-schema **11**, template-schema **4**, **216 InnoDB-tabeller og 193 views**. Se installer/migrations.json for strukturavtrykk og rekkefølge. Eksisterende sensorvalg, aktiv gjæring, frozen grunnlag, historikk og kladder skal bevares.

## Verifikasjon og målmiljø

Se TEST-RESULTS.md, verification/release-results.json og kildebundne regresjonsfiler for faktisk gjennomført verifikasjon. Modellen har 39 automatiserte TEST og 14 UAT. MariaDB 12.3.3 og plugin 0.80.3 er faktiske testavhengigheter. Chromium kjører kortet med kontrollert HA-skall/transport; dette er ikke brukerens installerte Home Assistant.

Oppgraderingstesten bruker faktisk installer fra en uendret bygget pakkekopi, simulert Docker-transport og native MariaDB. Komprimert backup gjenopprettes på en separat isolert server. Root-kravet prøves i et upriviligert user namespace. Ingen produksjonsinstallasjon, migrering eller restart er kjørt av denne arbeidsøkten.

Prosjekteier bekrefter installasjon av 2026.11.13-1 den 14.11.2026. Installasjon og funksjon av 2026.11.14-1 er ikke bekreftet. OPEN-017 står åpen for måltest: «Les innstillinger» skal vise DB-feltene og JSON-filen skal være tilgjengelig. De øvrige UAT beholder sine faktiske statuser. Ferske fullstendige tekniske målrapporter er ikke mottatt.

## Arkitektursperrer

MariaDB/InnoDB er eneste persistente domeneautoritet. Node-RED er generisk motor/transport; HA viser ferdige DB-felt og sender handlinger. Registry → template → normalisert frozen sesjon → generisk evaluering. Ingen skjulte defaults, alternative frontend-beregninger, generell writer-kø eller normal applikasjonslocking. SG-only, separate B/P-faser og ingen automatisk fysisk utstyrsstyring.

Append-only gjelder fakta/revisjoner i hver beholdt sesjon. Hele historiske sesjoner og ubrukte importerte templates kan slettes eksplisitt og atomisk. Felles grafgrunnlag og tegner brukes i dashboard/rapport. SQLite-par er arkiv-/utvekslingsformat; operativ sammenligning leser MariaDB.

## Publisering

Datoversjon ÅÅÅÅ.MM.DD-N med v-prefiks på tag og kort releasebeskrivelse. Releasejobben bygger og kontrollerer samme kildecommit før ZIP/SHA publiseres. Kontroller Actions, tag og nedlastet pakke; et lokalt forberedelsesbygg har en annen hash enn CI-pakken. Eksisterende tag/artefakt skal ikke omskrives. Publiseringskvitteringer i verification/published-release-*.json føres etter faktisk nedlasting og kontroll.
