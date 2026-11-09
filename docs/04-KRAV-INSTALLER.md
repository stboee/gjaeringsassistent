---
doc_id: DOC-04
role: requirements
status: normative
source_format: markdown
---

# 04 – Krav: installer og release

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

## P23 verifikasjons-/dokumentasjonskrav

| ID | Status | Krav |
|---|---|---|
| REQ-INST-001 | Fastsatt | Gjeldende dokumentasjon skal bygges som del av samme releasebygg som kode/SQL/kontrakter. Generert HTML er artefakt, ikke separat vedlikeholdt sannhetskilde. |
| REQ-INST-002 | Fastsatt | Ordinær releasepakke skal ikke inneholde komplett historisk p19-dokumentasjon. Historikk beholdes bare når den uttrykkelig dokumenterer forlatte løsninger eller funksjonelle referanser som fortsatt er relevante. |
| REQ-INST-003 | Fastsatt | Releaseporten skal bevare testbarhet og relevante regresjons-/arkitekturkontroller, men skal ikke feile på kunstige minimumstall for dokumenter, REQ, DEC eller OPEN. |
| REQ-INST-004 | Fastsatt | Etter vellykket releaseport skal strukturerte release-testresultater kunne følge pakken og importeres som verifikasjonsfakta ved installasjon. |
| REQ-INST-005 | Fastsatt | Før databaseendring eller endring av Node-RED-flow skal installeren lese faktisk MariaDB-serverversjon og avvise avvik fra den eksakte verifiserte versjonen i BUILD-INFO.json. Avvisning og observert versjon skal fremgå av installasjonsrapporten. |
| REQ-INST-006 | Fastsatt | Eksisterende sesjoner, målinger, korreksjoner, templates, kladder, innstillinger og registrerte testresultater skal bevares ved oppgradering. Ukjent kildeversjon/struktur avvises før mutasjon. |
| REQ-INST-007 | Fastsatt | Oppgraderingsmanifest, kilde-/målversjon, migreringsavtrykk, privat verifisert backup og faktisk installasjonsutfall skal være sporbare. Samme målversjon kan reinstallere filer uten å kjøre migreringen på nytt. |

## p24r14: avgrenset lesing og publisering

`tools/overview_reads.sql`, `tools/report_reads.sql` og `sql/20-views.sql` er de autoritative lesedefinisjonene. `tools/build_read_queries.py` kompilerer disse til DB-prosedyrer i `sql/11-runtime-routines.sql`. `contracts/read-execution-schema.json` inneholder faktiske MariaDB-typer, tegnsett og kollasjoner; `read-execution-plan.json` beskriver avhengighetsrekkefølgen. Ingen domeneformel oversettes til en ny JavaScript-implementasjon.

`ga_init_read_basis` oppretter tomme, forbindelsesprivate tabeller før read-only-transaksjonen. `ga_fill_read_basis` tar bare med valgt sesjon og eventuell valgt sesjonssammenligning via deklarerte eierskaps-FK-er. Globale bibliotekvalg og tekniske problemer beholder sin globale betydning. Kilder leses med vanlige konsistente SELECT-er; JSON_TABLE fyller de private tabellene internt i databasen. Tidsserier deles i dagsgrupper for å begrense intern JSON-størrelse. Ingen stor JSON-pakke sendes frem og tilbake over DB-adapteren. Mellomresultater beregnes én gang i SQL, i avhengighetsrekkefølge. Private Aria-tabeller er avledede engangsresultater; de er ingen permanent autoritet. Permanente tabeller beholder InnoDB og normal transaksjonshåndtering.

`ga_read_overview` og `ga_read_report` eier normalt sitt konsistente read-only-snapshot og rydder etter både suksess og feil. SQLite-arbeideren oppretter tabellene før sitt snapshot og gjenbruker rapportlesingen innen samme snapshot som arkivinnholdet. Den rydder etter commit/rollback. Ingen global kø eller manuell skrivelås innføres.

`ga_poll_overview` sammenligner kildenes antall/siste daterte endring og valgsekvenser med siste vellykkede publiseringskvittering. Dette er en invalidasjonskontroll over fysiske tabeller, ikke en ny kjøring av grafviews. Permanente uforanderlige parameterbarn dekkes av eierens daterte revisjon. Handlinger tvinger full oppdatering; tid, konfigurasjon uten egen endringsdato og ferskhet vurderes minst hvert DB-angitte `overview_clock_refresh_seconds` (60 sekunder). Detaljpunktoppløsning er fortsatt fem minutter. `read_model_publication_receipts` lagrer bare tekniske publiseringsfakta, ikke domene- eller grafverdier. Node-RED kvitterer først etter vellykket atomisk publisering.

Kriterier har separate DB-felt for originalt templatekrav, effektivt krav og vurderingssnapshot. `criterion_basis_current` kommer fra nullsikker sammenligning av vurdert og gjeldende kriterierevisjon. Før ny vurdering viser DB «Venter på ny vurdering», og prosessberedskap er `not_evaluated`. Historiske bevis endres ikke. `v_criterion_correction_receipts` finner en vurdering som bruker den nøyaktige revisjonen også etter automatisk B-overgang. Frontend bruker DB-kvitteringens melding.
