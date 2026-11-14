---
doc_id: DOC-20
role: operator-guide
status: current
source_format: markdown
---

# 20 – Operatørveiledning

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

**Rolle:** Praktisk veiledning for operatøren. Krav og regler eies av fag- og kontraktdokumentene; her forklares handlingene og hvordan faktisk lagring bekreftes.

## Før du begynner

Kontroller at riktig template er valgt, og at Teknisk viser tilgjengelig datagrunnlag. En synlig HA-verdi er ingen garanti for at den finnes i den aktuelle databasekladden. Vent på DB-kvittering etter lagring. Manglende data vises som manglende og skal ikke fylles automatisk.

## Templatebibliotek og redigering

Før Start velges publisert template i Gjæring-flaten. Template-fanen har et eget MariaDB-persistet administrasjonsvalg og kan brukes til å opprette/redigere draft, validere, publisere, retire og reaktivere templateversjoner både før og under aktiv session. En aktiv session bruker sin frozen session-template uendret; senere templateadministrasjon påvirker ikke sessionens faggrunnlag.

`template-editor.json` er dynamisk read-model. HTTP 404 betyr at genereringskjeden ikke har produsert filen; den skal ikke kopieres manuelt som permanent løsning. Finn årsaken i Teknisk/Technical Events.

## Referansedata og demo

**Start demo** er en eksplisitt operatørhandling og går gjennom ordinær Start/frozen-session-kjede før deterministisk referansedata legges i de ordinære runtime-tabellene. Demodata har bevarte datagap og skal ikke forveksles med produksjons-Tilt-ingest.

## Start og første komplette målesett

Velg publisert template og fyll batch, volum, faktisk OG, starttid og gjærgrunnlag. Kontroller gjærmodus og tilhørende obligatoriske felt. Registrer hele første målesettet, inkludert relevante manuelle/sensoriske verdier og notat, og vent på DB-kvittering. Trykk Start gjæring og følg startstatus til sesjonen er opprettet eller en konkret avvisning vises. Første målesett lagres atomisk med sesjonen ved pitch; senere kladdendringer skal ikke omskrive observasjonen.

1. Kontroller DB-konfigurert målekilde dersom eksterne entity-ID-er er endret.
2. Velg template og fyll start-/målegrunnlag.
3. Angi **Start fra** i lokal `Europe/Oslo`-tid.
4. Trykk **Start gjæring**.
5. Historikk importeres/valideres kronologisk til komplette 5-minuttersbøtter, B/P replay kjøres sekvensielt og importen fortsetter til LIVE.
6. Deretter kjører inkrementell import bare mens reell session er aktiv. Restart fortsetter fra persistert importcursor.

Heartbeat avgjør datagap. Registrerte gap skal ikke interpoleres.

Systemkontroll trigges etter vellykket Start og ved overgang til LIVE, slik at session-/målekildestatus ikke blir stående som pre-Start-snapshot.

## Grafer og datasettvalg

Den ordinære MQTT-automasjonen beholdes; Test MQTT brukes ikke av importen. Femminuttsdata lagres som før. MQTT-tidsstempelsensorens ISO-verdi brukes til å verifisere fersk rådata. Tidsstempelsensoren er ikke en numerisk langtidsstatistikkserie.

Ved oppstart og videre import spør motoren HA om SG, temperatur og RSSI med `recorder/statistics_during_period`, periode `hour`, samtidig med ordinær historikk. HA-brukeren må ha tilgang til Recorder-statistikk. Timesdata brukes som de er, også uten MQTT-verifikasjon. Et feilet statistikkanrop gir en driftsmelding og stopper ikke rådataimporten; meldingen lukkes ved neste vellykkede kall.

Under grafene kan du velge ingen sammenligning, et av de to datasettene eller en avsluttet gjæring. Begge kurvene starter ved dag 0, gjæringsstart. Grafvalget deles mellom Gjæring og Analyse og lagres i MariaDB. Hele gjæringen eller siste 24 timer, 48 timer eller 7 dager kan vises. Visningsintervallene er 5, 15 og 60 minutter, med 15 minutter som første valg. Dette endrer ikke lagrede rådata.

Demo velges før Start demo. `2026-05-29 IPL` er den samme tidligere demoen, kun navnet er endret. `2026-09-25 Gyllen pils` samler 2924 godkjente punkter fra vedlagte rådata/CSV/TSV, fra 25.09.2026 kl. 22:00 norsk tid til 06.10.2026 kl. 20:30. 32 manglende intervaller er bevart som gap; datasettet er ikke et løfte om målinger fram til dagens dato. Duplisert TSV er ikke telt to ganger. Proveniens finnes under `reference/demo`.

Etter Avslutt skal kortet vise Gjæring avsluttet og arkivstatus. Gjør klar vises når DB-gaten tillater frigivelse. Arkiveringsknappen vises når et arkiv mangler eller et forsøk har feilet. Et verifisert arkiv skal ikke utløse en ny arkivering. Arkiv kan fortsatt være større enn 19 MB; bare små filmetadata sendes til MariaDB.

## Arkiver, import og sammenligning

1. Velg template.sqlite og, ved gjæringsimport, tilhørende gjaering.sqlite fra samme eksportsett.
2. Les forhåndsvisningen og velg navn og innhold før import. Kontroller SHA-advarsler; transport og intern integritet kontrolleres uansett.
3. Vent på DB-kvittering. Ved feil skal importen rulle tilbake samlet.
4. Velg den importerte gjæringen i sammenligning. Skjul fra sammenligning endrer synlighet uten å slette data.
5. En importert original er skrivebeskyttet. Bruk Opprett ny template fra eksisterende versjon med egen ID/navn for en redigerbar kopi.

Gjæringsarkiv og template-arkiv ligger øverst i Template og arkiv. Eksport av en gjæring gir gjæring.sqlite, template.sqlite, én SHA-fil per SQLite-fil og rapport.html med samme prefix. Eksport av bare template gir template.sqlite og SHA. Last ned lenkene for settet. Ved import velges filene samlet; deretter template-navn og ønsket innhold. SHA-advarsler kan aksepteres ved å gjennomføre importen.

Gamle lokale og importerte gjæringer kan slettes fra MariaDB etter bekreftelse. Eksportfiler beholdes, og aktiv gjæring er beskyttet. Importert template kan bare slettes når den ikke lenger brukes; egen kopi basert på originalen teller også som referanse.

## Etterregistrere avsluttet gjæring

Bruk ordinært startbilde: template, batchnavn, «Start fra» og første manuelle måleserie. Lagre det angitte starttidspunktet. Angi deretter slutten i feltet ved «Importer avsluttet gjæring». Etter fullført import viser målekilden HISTORISK. Ved feil beholdes cursor og sluttgrense; omstart prøver kun den gjenstående delen. Systemet kan bare hente historikk HA fortsatt har tilgjengelig, og timesstatistikk som krysser slutten kan ikke deles til et presist delintervall.

Under Biologi/Prosesstrinn kan du korrigere eksisterende starter og etterregistrere manglende starter. Databasen avgrenser tidspunktet mellom nabofaser. Manuelle målinger etterregistreres gjennom vanlig målekort; korriger målerundens tidspunkt til faktisk historisk måletid. Rapporter og eksport er tilgjengelige underveis. «Avslutt gjæring» ferdigstiller ved valgt historisk slutt, genererer sluttarkiv og tilbyr ordinær klargjøring.

## Målekilder og kildebytte

Åpne Teknisk → Målekilder og sensorer → Kontroller sensorer. Velg SG, temperatur, siste MQTT-oppdatering og RSSI; trykk kan stå Manuell registrering. En trykksensor må levere overtrykk i en støttet enhet (bar, kPa, hPa/mbar, Pa eller psi). Absolutt trykk må ikke velges som overtrykk. Temperaturkilden i denne versjonen må levere °C.

Lagre og vent på databasekvittering. Endringer under en reell livegjæring får virkning ved den oppgitte DB-grensen. Konfigurasjonshistorikken viser tidligere valg; feltverdier er merket sist kontrollert. Arkiverte/historiske sesjoner endres ikke av et nytt globalt valg. Trykk fra HA-timesstatistikk er ikke lagt til; trykkimport gjelder detaljgrunnlag i femminuttersbøtter.

## Målinger og korrigering

Registrer hele målesettet i Måleresultater. SG er eneste tetthetsskala. Sensoriske felt har 0 = ønsket/ingen avvik og 5 = størst avvik; «ikke registrert» er forskjellig fra 0. Temperatur registreres med én desimal. Lagret målerunde og måletid kan kontrolleres i historikken. En korreksjon oppretter en ny revisjon; opprinnelige fakta beholdes.

## Biologi og prosesstrinn

Les vurdering, faktisk verdi og datavindu før overgang. B-faser og P-trinn er separate. Bruk Neste/Tilbake for operative prosesstrinn; Tilbake gir advarsel og krever ikke et obligatorisk begrunnelsesfelt. Kriteriekorreksjon og kriterieavvik finnes bare der frozen policy tillater dem. Registrer eller trekk tilbake avvik i samme kriterieflate og kontroller ny DB-vurdering; et avvik skaper ingen manglende målinger.

## Rapport, avslutning og ny gjæring

Generer rapport fra aktiv gjæring. Avslutt gjæring ferdigstiller sesjonen og starter arkivering. Kontroller verifiserte SQLite-filer, SHA og sluttrapport. Ved arkivfeil brukes Forsøk arkivering på nytt; en ny Avslutt-hendelse er ikke nødvendig. Gjør klar for ny gjæring krever den avtalte arkivkvitteringen. Se [livsløpskontrakten](13-LIVSLOP-OBSERVASJONER-RAPPORT-OG-HISTORIKK.md).

## Ved feil

Les den konkrete meldingen og hent Eksporter Teknisk. Kontroller sist kjørt Systemkontroll, aktive problemer og hendelsesloggen. Filpublisering og lagring i MariaDB har separate kvitteringer. Se [driftsveiledningen](08-DRIFTSVEILEDNING.md) og [diagnostikkmodellen](19-TEKNISK-FANE-OG-DRIFTSMELDINGER.md). Akseptanseprøver utføres etter [dokument 09](09-AKSEPTANSETEST.md); generell vellykket bruk lukker ikke automatisk alle UAT.
