# Gjæringsassistent – pågående arbeid

<!-- BEGIN ARCHITECTURE GUARDRAILS -->
**Gjennomgående ansvarsdeling og arkitektursperrer**

- MariaDB/InnoDB er eneste autoritative persistente sannhetskilde for domenedata, konfigurasjon, regler, parametere og nødvendig vedvarende tilstand. Informasjon lagres der og hentes derfra.
- HA/frontend viser ferdige DB/read-model-felt og formidler handlinger. Node-RED er generisk motor, orkestrering og transport; HA-state er ikke domenefasit.
- Ingen oppdiktede verdier, lokale defaults, fallback, reserveberegninger, hardkodede fagregler eller workarounds for manglende/feil grunnlag. Feilen rettes ved den autoritative kilden og skal være synlig.
- Påkrevde felt kan ikke utelates; reelt fravær modelleres og forklares, aldri som 0. Ingen nødvendig domenestate i flow/global/context, nettleser, HA eller lokale runtimefiler.
- Registry → template → normalisert frozen session → generisk motor. Sessionens grunnlag, rettigheter og policy er eksplisitte og sporbare.
- Normaliserte relasjoner, PK/FK/UNIQUE/CHECK og korte transaksjoner håndhever integritet. InnoDB håndterer normal samtidighet; ingen global writer-kø, normal applikasjonslocking eller retry som skjuler modellfeil.
- Fakta og korreksjoner innen beholdte sesjoner er append-only. Mutable kladder og eksplisitt atomisk sletting av hele gamle sesjoner er særskilt modellerte operasjoner.
- SG-only; separate B/P-modeller; én operativ sesjon; ingen automatisk fysisk styring. Dashboard og rapport bruker felles autoritativt seriegrunnlag og graftegner uten estimerte målinger.

Flyktig transport, ulagret operatørinput og tegnekoordinater gir ingen adgang til alternativ faglig tilstand. Grunnreglene gjentas bevisst og kontrolleres mot samme kilde; se dokument 14 for begrunnelser.
<!-- END ARCHITECTURE GUARDRAILS -->

## Avtalt omfang

Prosjekteier har sagt «start» til en samlet dokumentrevisjon: bevare god dokumentasjon, supplere mangler, bevare dialogbasert kravhistorikk og stabile ID-er, samle releasehistorikk og kontrollere strukturerte kontrakter mot faktiske produsenter/mottakere. Ansvarsdeling og sperrene mot oppdiktede verdier/defaults/workarounds skal gjentas bevisst.

## Arbeidsgrunnlag og kilder

Revisjonen startet fra a69a78394a3997705152d1253f68ceef3be85a6f. Publisert programvare identifiseres av [releasekvitteringen](verification/published-release-2026.11.14-1.json); dette dokumentet er ingen ny releasekvittering. Krav og beslutninger eies av dokument 01–04/14, historikk av dokument 21, målmiljøstatus av dokument 15 og grensesnitt av dokument 05/12 samt contracts/interface-catalog.json.

## Gjennomført dokumentrevisjon

Dokumentene er omorganisert etter emne, operatørveiledning og samlet kravhistorikk er opprettet, og grensesnittkatalogen knytter kontrakter til faktiske SQL-/flow-/mottakergrenser. 264 krav og 68 beslutninger har uendret ID og innhold. De fem opprinnelige strukturerte schema-/HA-kontraktene og runtime flow/kort er bevart byte-identisk. Dokumentbygget er skilt fra runtimegenerering.

Filoppgradering oppdaterer nå også den tekniske krav-/beslutningskatalogen, slik at kildehenvisninger følger dokumentene. Alle fem oppgraderingsbaner og ny native integrasjonskjøring har bestått; se revisjonsbeviset for presis kilde/omfang. Publisert programvare er fortsatt den uendrede 2026.11.14-1. Ved en senere programvareutgivelse må ny versjon og migreringskvittering fra faktisk publisert kilde brukes; denne dokumentrevisjonen er ikke bekreftet installert.

## Videreføring

Les [onboarding](docs/ONBOARDING-NY-CHAT.md) og [dokumentkartet](docs/00-DOKUMENTKART-OG-STATUS.md). Se docs/sources/document-revision.json og verification/documentation-review.json for faktisk revisjonsregnskap og kontroller. Oppdagede kilde-/kontraktavvik skal være eksplisitte; eldre native bevis skal ikke gis ny testdato eller versjon uten ny kjøring. Dokumentrevisjon på main er forskjellig fra innholdet i en allerede publisert ZIP.
