# Gjæringsassistent – videreføring 13.11.2026

Versjon **2026.11.13-1 – Målesett, sensorer og kriteriefravik**. Teknisk utgangspunkt er p24r16 / første GitHub-utgave 2026.11.07-1; forrige publiserte utgave var 2026.11.09-2. VERSION, BUILD-INFO.json, tag og bygget releasepakke fastslår identiteten. Main kan ha nyere dokumentasjon enn siste publiserte pakke.

## Ny chat

Følg [onboarding-instruksjonen](docs/ONBOARDING-NY-CHAT.md), AGENTS.md og dokumentkart 00. Les relevante normative dokumenter og de faktiske SQL-/registry-kildene. Det avklarte arbeidet nedenfor er allerede bestilt og gjennomført; det skal ikke bestilles på nytt fordi en chat skiftes. Arbeid direkte på main uten issues/PR. Nye oppgaver avgrenses før «start».

## Denne leveransen

- Sensoriske 0–5-slidere, eksplisitt forskjell mellom ikke registrert og registrert 0. Manuell temperatur vises med én desimal fra DB.
- «Målekilder og sensorer» øverst i Teknisk og kompakt oppsummering før Start. HA-katalog, kompatible sensorvalg, kvittert lagring, DB-eide enheter og lineær konvertering. Trykk forblir manuelt til en separat overtrykksensor velges.
- Reviderte globale konfigurasjoner og fryst sesjonshistorikk. Live kildebytte gjelder fra en DB-bestemt femminuttersgrense. Detaljimport splitter ved kildegrensen. Trykk fra HA-timesstatistikk er ikke utvidet.
- Lesbare tekniske komponentnavn med beholdt rå node-/rutineidentitet. Historiske logghendelser omskrives ikke.
- «Håndter kriterieavvik» i Prosesstrinn, også ved tillatt fravik når målegrunnlag mangler. Biologi/Prosesstrinn bruker samme DB-transaksjon. Registrering og tilbaketrekking bevarer revisjoner og oppdaterer samme readiness-grunnlag.
- Start lagret allerede alle måleparametere som én initial observasjon atomisk med sesjonen. Ny regresjon prøver alle 19 operatørfelter, sensorisk 0, Unicode, måletid ved pitch, uendret startobservasjon etter senere kladdendring og sen rollback av hele oppstarten. Et manuelt målesett erstatter ikke kontinuerlig tidsseriedekning. Bortfalt prosessfravik skyldtes NULL-håndtering av kriteriets met-status, ikke at startmålesettet manglet.
- SQLite-rundtur tar med fryste sensorbindinger. Det eksakte eldre profilskjemaet konverteres med arkiverte ID-er ved gammel importcursor. Eldre kildebytter/kontrollgrenser oppgis som uregistrerte; dagens sensorvalg endres ikke.

Runtime-schema **11**, template-schema **4**, **216 InnoDB-tabeller og 193 views**. Kildesignaturer og støttede oppgraderingsbaner står i installer/migrations.json. Fra p24r16, 2026.11.07-1, 2026.11.09-1 og 2026.11.09-2 bevares data og eksisterende sensor-ID-er flyttes til normaliserte bindinger. Ukjent struktur/versjon og feil migreringskvittering avvises. Samme målversjon kan reinstallere filer.

## Verifikasjon og målmiljø

Se [TEST-RESULTS.md](TEST-RESULTS.md), verification/release-results.json og kildebundne native regresjonsfiler. Modellen har 39 automatiserte TEST og 14 UAT. MariaDB 12.3.3 og plugin 0.80.3 er faktiske testavhengigheter. Chromium kjører det leverte kortet med kontrollert HA-skall/transport og reelle DB-/NR-kommandoer; dette er ikke brukerens installerte Home Assistant.

Oppgraderingstesten bruker den faktiske installeren fra en uendret bygget pakkekopi, simulert Docker-transport og native MariaDB. Komprimert backup gjenopprettes på en separat isolert server. Ingen installasjon, migrering eller restart er kjørt på brukerens server i denne arbeidsøkten. Produksjonskjøring omfattes ikke av bestillingen om bygg/publisering.

Siste vedlagte målrapport er fortsatt fra p24r16 08.11.2026 kl. 22:57. Brukeren har senere rapportert visningsmangler og bortfalt kriteriefravik; aktuell installert identitet er ikke bekreftet med en nyere rapport. Ingen av de 14 UAT er automatisk lukket av lokale tester eller tidligere generell bekreftelse.

Neste måltest etter tilsiktet installasjon: kontroller Systemkontroll/versjonsidentitet, hele første målesett, slidere 0/5, temperaturpresisjon, sensorvalg/kvittering, kildebytte og B/P-fravik. Dokument 09/15 inneholder øvrige åpne måltester og faglig kalibrering.

## Arkitektursperrer

MariaDB/InnoDB er eneste persistente domeneautoritet. Node-RED er generisk motor/transport; HA viser ferdige DB-felt og sender handlinger. Registry → template → normalisert frozen sesjon → generisk evaluering. Ingen skjulte defaults, alternative frontend-beregninger, generell writer-kø eller normal applikasjonslocking. SG-only, separate B/P-faser og ingen automatisk fysisk utstyrsstyring.

Append-only gjelder fakta/revisjoner i hver beholdt sesjon. Hele historiske sesjoner og ubrukte importerte templates kan slettes eksplisitt og atomisk. Felles grafgrunnlag og tegner brukes i dashboard/rapport. SQLite-par er arkiv-/utvekslingsformat; operativ sammenligning leser MariaDB.

## Publisering

Datoversjon ÅÅÅÅ.MM.DD-N med v-prefiks på tag og kort releasebeskrivelse. Releasejobben ved VERSION-endring bygger og kontrollerer samme kildecommit før ZIP/SHA publiseres. Kontroller Actions, tag og nedlastet pakke; et lokalt forberedelsesbygg har en annen hash enn CI-pakken. Eksisterende tag/artefakt skal ikke omskrives.

## Bekreftet publisering

Publisert 13.11.2026 som [v2026.11.13-1](https://github.com/stboee/gjaeringsassistent/releases/tag/v2026.11.13-1), kildecommit `309625238899dce6a69c7f4b2536ae8f1cb3e9a7`. [Actions 43402451122](https://github.com/stboee/gjaeringsassistent/actions/runs/43402451122) bestod. Den faktisk nedlastede CI-pakken er 1 844 278 byte og har SHA-256 `06cb567d3e155cd0249fd07705e92b6cf17ae104fe820f9e4d8800c02a64a6ec`. Sidefil, ZIP-integritet, alle 239 interne filsjekksummer og pakkens source_commit er kontrollert.

Se verification/published-release-2026.11.13-1.json. Denne publiseringskvitteringen er dokumentert på main etter taggen og endrer ikke den publiserte pakken. Målmiljøinstallasjon og de 14 UAT er fortsatt ikke bekreftet.
