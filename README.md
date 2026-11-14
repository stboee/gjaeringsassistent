# Gjæringsassistent 2026.11.13-1

> Main har en senere, upublisert retting av HTTP 404 for sensorinnstillinger (OPEN-017). Den publiserte pakken er uendret. Se [overleveringen](OVERLEVERING.md) for avgrensning, målrettet test og retting i eksisterende installasjon.

**Målesett, sensorer og kriteriefravik**, med databevarende oppgradering fra p24r16, 2026.11.07-1, 2026.11.09-1 og 2026.11.09-2. Gjæringsassistent gir råd, oversikt og historikk for gjæring i Home Assistant: templates, biologiske faser, prosesstrinn, målinger, sammenlignbare grafer, rapporter og SQLite-arkiver.

MariaDB/InnoDB er eneste autoritative persistente domenekilde. Node-RED er generisk motor/orchestrator; HA er operatør- og presentasjonsflate. Feil eller mangler rettes ved kilden, uten lokale defaults eller frontend-workarounds.

## Installasjon og databevaring

Installeren bevarer eksisterende sesjoner, målinger, korreksjoner, templates, kladder og innstillinger. Støttede kildeversjoner er `0.1.0-prototype24-r16` samt `2026.11.07-1`, `2026.11.09-1` og `2026.11.09-2`. Tom database initialiseres; samme målversjon kan installeres på nytt med samsvarende migreringskvittering. Ukjent versjon eller struktur avvises før database-/flowendringer.

Last ned versjonert ZIP og SHA-256 fra [GitHub Releases](https://github.com/stboee/gjaeringsassistent/releases), kontroller SHA, pakk ut og kjør `./installer/install.sh` som root. Følg [driftsveiledningen](docs/08-DRIFTSVEILEDNING.md) og [compose-referansen](compose/README.md). Før en eksisterende installasjon endres, stoppes Node-RED kort og en komprimert databasebackup med rutiner/triggere samt flow/credentials sikres privat under Node-RED `/data/gjaeringsassistent/backups/`. Databasen resettes ikke.

Eksisterende containeroppsett, Node-RED-konfigurasjonsnoder og sensorbindinger må være konfigurert. Installeren bevarer avtalte config-ID-er og credentials. Installasjonsrapporten erstatter ikke Systemkontroll og operatørtest.

## Avhengigheter

| Komponent | Versjon |
|---|---|
| MariaDB | 12.3.3 |
| Node-RED | 5.0.7 |
| Home Assistant websocket-noder | 0.80.3 |
| node-red-node-mysql | 3.0.4 |
| Node.js | Minst 24 |

## Dokumentasjon og kilder

**Ny chat:** Følg [onboarding-instruksjonen](docs/ONBOARDING-NY-CHAT.md). Den beskriver leserekkefølge, strukturerte kilder og kvitteringen som skal gis før videre arbeid.

Start i [dokumentkartet](docs/00-DOKUMENTKART-OG-STATUS.md), [aktive beslutninger](docs/14-AKTIVE-BESLUTNINGER.md) og [arkitekturen](docs/07-SYSTEMARKITEKTUR-OG-DATAFLYT.md). Eksakte regler, HA-bindinger og schema-/funksjonsmetadata eies også av strukturerte SQL-/registry-kilder. HTML og genererte JSON-kataloger er avledet inspeksjon.

[TEST-RESULTS.md](TEST-RESULTS.md) beskriver faktisk testomfang. [Åpent arbeid](docs/15-AAPENT-ARBEID.md) omfatter blant annet måltest av oppgradering/startflate og faglig kalibrering. Brukeren har bekreftet at p24r16 fungerer fint; dette lukker ikke automatisk alle UAT for datoversjonen.

## Utvikling og release

[AGENTS.md](AGENTS.md) beskriver avklaring i chat, «start», implementering, relevante kontroller og commit direkte på main. Issues/PR inngår ikke i prosjektprosessen.

Versjoner bruker **ÅÅÅÅ.MM.DD-N**, for eksempel 2026.11.13-1. N starter på 1 hver publiseringsdag. Taggen har v som prefiks; release-tittelen har en kort beskrivelse. Eldre testfilnavn og stabile krav-/beslutnings-ID-er beholdes for sporbarhet.

Bygg med python3 tools/build-package.py --zip og kontroller med bash tools/run-tests.sh. ZIP og SHA-256 havner i dist/. Et avgrenset filutvalg brukes både fra Git og utpakket leveranse, slik at Git-metadata og lokale filer ikke følger med.

Releasejobben kjører kontrollene på nytt og knytter leveransen til kildecommitten. Den kjøres ved endring av VERSION på main eller manuelt. Native testbevis må være ferske før publisering; se TEST-RESULTS.md.

## Lisens

[MIT](LICENSE).
