---
doc_id: DOC-04
role: requirements
status: normative
source_format: markdown
---

# 04 – Krav: installer og release

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

**Rolle:** Normative krav til installer og releasegrense.

## Ansvarsgrense

Installeren skal **installere** releasepakken. Den skal ikke være et alternativt test- eller driftsverktøy for applikasjonen.

1. Installasjon skal bevare eksisterende brukerdata. Tom database initialiseres; kjent eksisterende versjon oppgraderes gjennom et eksplisitt migreringsmanifest. Ingen automatisk database-reset er tillatt.
2. Før mutasjon skal installeren kontrollere kun nødvendige forutsetninger: obligatoriske containere/verktøy, kjørende Node-RED for pakkekontroll og faktisk UID/GID, Node-RED `/data`, eksisterende config/credentials som må bevares, release-SHA og syntaktisk lesbare kontrakt-/flowfiler.
3. Installer skal gjenbruke eksisterende HA- og MariaDB-config-noder/credentials når de avtalte config-ID-ene finnes.
4. Førstegangsinstallasjon bruker baseline/schema/seeds. Oppgradering bruker bare deklarerte migreringer, oppdaterte rutiner/views og relevante systemmetadata; bruker- og template-data reseedes ikke.
5. Node-RED stoppes én gang for konsistent backup og utskifting og startes én gang etter vellykket installasjon. Backup skal være vellykket og komprimeringen kontrolleres før databaseendringer. Ved feil etter stopp forblir Node-RED stoppet med eksplisitt feilsteg og backupsti.
6. Etter DB-installasjon skal installeren bare kontrollere installasjonsmetadata som er nødvendig for å vite at riktig release og schema-metadata ble lagt inn. Detaljerte schema-/modellregresjoner skal ikke gjøre målinstallasjonen til FAIL.
7. Installeren skal **ikke** kjøre syntetisk Start, opprette testsesjoner, trykke HA-knapper, kjøre Systemkontroll, teste restart/restore eller utføre øvrige domene-/runtime-akseptansetester.
8. Statiske tester, kontrakttester, schema-/modellregresjoner, Function-unit-tester og pakketester er **releaseporter** og kjøres før pakking; de skal ikke gjentas som installasjonskritiske tester hos operatøren.
9. Fysisk schema, runtime- og integrasjonsstatus etter installasjon verifiseres mot MariaDB-metadata gjennom applikasjonens egen **Teknisk/Systemkontroll**- og **Verifikasjon**-flate.
10. Installerresultat skal skrives som både `.log` og strukturert `.json`, med minst `last_step`, exitkode, versjon og hvilke config-ID-er som ble bevart.
11. Ved FAIL skal installeren stoppe med presis installasjonsdiagnostikk. Den skal ikke forsøke brede automatiske reparasjoner eller starte nye funksjonstester.
12. Pakken skal inneholde aktiv kilde, SQL, dashboard/frontend, tester, byggverktøy, runtime-avhengigheter, release-metadata og komplett gjeldende dokumentasjon.

**Prinsipp:** *Installeren verifiserer installasjonen. Applikasjonen verifiserer applikasjonen.*

## Frontendgrense

Installeren skal stage dashboard, custom card og loader i `/data/gjaeringsassistent/frontend-source` og publisheren i `/data/gjaeringsassistent/runtime`. Selve publiseringen til `/data/gjaeringsassistent/ha-public` eies av Node-RED ved oppstart. Dette er nødvendig fordi `ha-public` er et separat bind-mount som skygger tilsvarende katalog under hoved-mountet `/data`.

## Verifikasjon og dokumentleveranse

| ID | Status | Krav |
|---|---|---|
| REQ-INST-001 | Fastsatt | Gjeldende dokumentasjon skal bygges som del av samme releasebygg som kode/SQL/kontrakter. Generert HTML er artefakt, ikke separat vedlikeholdt sannhetskilde. |
| REQ-INST-002 | Fastsatt | Ordinær releasepakke skal ikke inneholde komplett historisk p19-dokumentasjon. Historikk beholdes bare når den uttrykkelig dokumenterer forlatte løsninger eller funksjonelle referanser som fortsatt er relevante. |
| REQ-INST-003 | Fastsatt | Releaseporten skal bevare testbarhet og relevante regresjons-/arkitekturkontroller, men skal ikke feile på kunstige minimumstall for dokumenter, REQ, DEC eller OPEN. |
| REQ-INST-004 | Fastsatt | Etter vellykket releaseport skal strukturerte release-testresultater kunne følge pakken og importeres som verifikasjonsfakta ved installasjon. |
| REQ-INST-005 | Fastsatt | Før databaseendring eller endring av Node-RED-flow skal installeren lese faktisk MariaDB-serverversjon og avvise avvik fra den eksakte verifiserte versjonen i BUILD-INFO.json. Avvisning og observert versjon skal fremgå av installasjonsrapporten. |
| REQ-INST-006 | Fastsatt | Eksisterende sesjoner, målinger, korreksjoner, templates, kladder, innstillinger og registrerte testresultater skal bevares ved oppgradering. Ukjent kildeversjon/struktur avvises før mutasjon. |
| REQ-INST-007 | Fastsatt | Oppgraderingsmanifest, kilde-/målversjon, migreringsavtrykk, privat verifisert backup og faktisk installasjonsutfall skal være sporbare. Samme målversjon kan reinstallere filer uten å kjøre migreringen på nytt. |

Lesearkitektur, private snapshot-tabeller og publiseringskvittering er beskrevet i [dokument 07](07-SYSTEMARKITEKTUR-OG-DATAFLYT.md#avgrenset-lesing-snapshots-og-publiseringskvittering). Dette er applikasjonsarkitektur; installeren leverer de deklarerte definisjonene.
