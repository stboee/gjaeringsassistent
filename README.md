# Gjæringsassistent 2026.11.07-1

**Første GitHub-utgave**, med p24r16 som teknisk utgangspunkt. Gjæringsassistent gir råd, oversikt og historikk for gjæring i Home Assistant: templates, biologiske faser, prosesstrinn, målinger, sammenlignbare grafer, rapporter og SQLite-arkiver.

MariaDB/InnoDB er eneste autoritative persistente domenekilde. Node-RED er generisk motor/orchestrator; HA er operatør- og presentasjonsflate. Feil eller mangler rettes ved kilden, uten lokale defaults eller frontend-workarounds.

## Installasjon og databevaring

**Installeren resetter Gjæringsassistent-databasen. Denne utgaven har ikke et oppgraderingsløp som bevarer eksisterende sesjoner.** Eksporter sesjoner og templates som skal beholdes før tilsiktet installasjon. Ikke kjør installeren som en vanlig produksjonsoppgradering.

Last ned versjonert ZIP og SHA-256 fra [GitHub Releases](https://github.com/stboee/gjaeringsassistent/releases), kontroller SHA og pakk ut. Følg [driftsveiledningen](docs/08-DRIFTSVEILEDNING.md) og [compose-referansen](compose/README.md). Når installasjon med reset er tilsiktet, kjøres ./installer/install.sh fra den utpakkede pakken.

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

Start i [dokumentkartet](docs/00-DOKUMENTKART-OG-STATUS.md), [aktive beslutninger](docs/14-AKTIVE-BESLUTNINGER.md) og [arkitekturen](docs/07-SYSTEMARKITEKTUR-OG-DATAFLYT.md). Eksakte regler, HA-bindinger og schema-/funksjonsmetadata eies også av strukturerte SQL-/registry-kilder. HTML og genererte JSON-kataloger er avledet inspeksjon.

[TEST-RESULTS.md](TEST-RESULTS.md) beskriver faktisk testomfang. [Åpent arbeid](docs/15-AAPENT-ARBEID.md) omfatter blant annet produksjonsoppgradering og faglig kalibrering. Brukeren har bekreftet at p24r16 fungerer fint; dette lukker ikke automatisk alle UAT for datoversjonen.

## Utvikling og release

[AGENTS.md](AGENTS.md) beskriver avklaring i chat, «start», implementering, relevante kontroller og commit direkte på main. Issues/PR inngår ikke i prosjektprosessen.

Versjoner bruker **ÅÅÅÅ.MM.DD-N**, for eksempel 2026.11.07-1. N starter på 1 hver publiseringsdag. Taggen har v som prefiks; release-tittelen har en kort beskrivelse. Eldre testfilnavn og stabile krav-/beslutnings-ID-er beholdes for sporbarhet.

Bygg med python3 tools/build-package.py --zip og kontroller med bash tools/run-tests.sh. ZIP og SHA-256 havner i dist/. Et avgrenset filutvalg brukes både fra Git og utpakket leveranse, slik at Git-metadata og lokale filer ikke følger med.

Releasejobben kjører kontrollene på nytt og knytter leveransen til kildecommitten. Den kjøres ved endring av VERSION på main eller manuelt. Native testbevis må være ferske før publisering; se TEST-RESULTS.md.

## Lisens

[MIT](LICENSE).
