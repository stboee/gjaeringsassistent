---
doc_id: DOC-13
role: lifecycle
status: normative
source_format: markdown
---

# 13 – Livsløp, observasjoner, rapport og historikk

**Rolle:** Normativ funksjonell modell for session-livsløp, observasjoner, rapport/eksport og historikk.

## 1. Operativt livsløp

Operatørflaten skiller mellom:

- `idle` – ingen unreleased session;
- `configured` – pre-Start draft er lagret, men ingen session er opprettet;
- `active` – gjæring pågår;
- `completed` – gjæringen er manuelt avsluttet, men session er ennå ikke operativt frigitt.

`draft` er ikke en persistent session-lifecycle. `Gjør klar for ny gjæring` append-er et release-faktum slik at historisk session beholdes samtidig som operativ current session forsvinner.

## 2. Start og frozen grunnlag

Start validerer valgt publisert template og persisted startdraft og oppretter session atomisk. Pitchtid og første observation er eksplisitte fakta. Template/regler, replay-policy, metric/outputdomener, analysemetadata og målekilde-/valideringsgrunnlag fryses til session.

For reell session opprettes målekildebinding og historikkimport fra valgt `Start fra`. Startstatus skal vise mottatt/validering/import/fremdrift/sluttstatus som read-model, men MariaDB-session/importcursor er autoritet.

## 3. Observasjoner

Manuelle observation rounds er atomiske komplette målesett. Start lagrer første relevante observasjon. Senere målesett lagres med eksplisitt operatørhandling.

Tidskorrigering/deaktivering oppretter ny revision og omskriver ikke historisk verdi. SG-only gjelder tetthet. Sensoriske 0–5-felt følger 0=ønsket/ingen avvik, 5=størst avvik.

## 4. Biologi og prosesstrinn

Biologiske visits/transitions kan etableres automatisk fra sekvensielle kriterier. Operatøren kan korrigere tillatte kriterieparametere og registrere bekreftet kriteriefravik med valgfritt notat. Evaluatoren utleder faseovergang fra dette grunnlaget; tidligere rå vurdering beholdes. Prosesstrinn har separat visit-/transitionhistorikk. Ordinære P-overganger skjer ved operatørens `Neste`/`Tilbake`; historisk replay kan bare autoetablere steg som frozen policy eksplisitt tillater.

Kriterium oppfylt/readiness og faktisk P-transition er separate fakta. P3 kan derfor være `ready` samtidig som P2 fortsatt er aktivt.

## 5. Avslutt gjæring

**Avslutt gjæring** er en eksplisitt manuell handling. Åpne visits lukkes historikkbevarende, lifecycle går til `completed`, og nye aktive-session-målinger skal ikke aksepteres.

Sluttnotat er ikke obligatorisk; notater er egne fakta.

## 6. Aktiv rapport

Under aktiv session kan operatøren generere et HTML-snapshot uten lifecycle-endring. Rapporten registreres som `active_report` og bygges fra MariaDB/read-models.

Rapporten skal dekke relevante sammendrag, hele operative grafsettet (SG, temperatur, trykk og deklarerte analysegrafer), B/P-forløp, manuelle målinger/sensorikk, kriteriebevis, korreksjoner/fravik, transitions, datagap, kronologi, notater og operatørhandlinger. Grafene bruker samme DB-eide serier, metadata-bestemte bånd der meningsfullt, dynamiske aksemetadata og relevante mål-/kriteriegrenser som dashboardet. Renderer kan tegne HTML/SVG-layout, men skal ikke beregne domenedata, etablere egne aksegrenser eller skjule gap med interpolasjon.

`p18-r5` er funksjonell referanse for rapportdekning, ikke teknisk implementasjonskilde.

## 7. Completed eksport og sluttrapport

Completed session kan eksporteres til integritetsverifisert arkiv med frozen template/sessiongrunnlag, normaliserte data, relevante logger og manifest. HTML-sluttrapport er lesbar presentasjon; SQLite-paret er filutveksling og arkiv; importert historikk ligger i MariaDB.

For reell session krever **Gjør klar** verifisert completed-arkiv for samme session. Demo kan være eksplisitt unntatt denne sikkerhetsgaten.

## 8. Gjør klar for ny gjæring

Handlingen append-er release-faktum. Historiske sessiondata, rapporter, eksport og teknisk historikk beholdes. Mutable inputdraft kan klargjøres/nullstilles for neste session.

## 9. Historisk rapport og sammenligning

Historiske rapporter er read-only og skal aldri aktivere/mutere historisk session. Analyse kan sammenligne gjæringer justert etter tid siden pitch. Importerte gjæringer er tilgjengelige etter innlesing til MariaDB; arkivfanen styrer synlighet i sammenligningslisten.

## 10. Restart

Node-RED-/serverrestart rekonstruerer nødvendig nåtilstand fra MariaDB. Aktiv reell session gjenopptar import fra persisted `last_import_cutoff_at`; browser/HA-state/runtimefiler skal ikke være restoreautoritet.

## 11. Historisk catch-up → LIVE

Catch-up bruker samme 5-minutters-, evaluator- og analysegrunnlag som live, men kjøres kronologisk mot persisted importhorizon. Når importen når LIVE, fortsetter inkrementell femminuttersimport og Systemkontroll refreshes slik at målekilde/sessionstatus viser gjeldende DB-fakta.

## 12. Filverifisert sluttarkiv og gjenopptak

Runtime registrerer først `session_export_attempts` med DB-generert identitet, sekvens og tidspunkt. Et konsistent MariaDB-snapshot skrives som to normaliserte SQLite-filer med samme eksportprefix. Begge kontrolleres og leses tilbake; HTML bygges fra den felles rapportgeneratoren. Bare kontrollerte filer kan gi append-only `session_exports` med status `verified`. Registreringen inneholder filstier, byteantall og SHA-256; arkivinnhold sendes ikke som SQL-parameter.

Hvert forsøk har egne filnavn, slik at tidligere arkiv ikke overskrives. Historikklenker kommer fra de registrerte faktiske filstiene. Fil-/byggfeil gir `failed` og konkret feiltekst. Et forsøk som avbrytes ved runtime-/DB-bortfall beholdes med manglende fullføringskvittering. `v_session_archive_status` er autoritet for status, og Systemkontroll skiller manglende/mislykket sluttarkiv fra normal pågående arkivering.

**Forsøk arkivering på nytt** lager et nytt forsøk for avsluttet gjæring som mangler verifisert arkiv. Det endrer ingen B/P-visits, målinger eller lifecycle-fakta. **Gjør klar** krever fortsatt verifisert arkiv for reell gjæring. Ved databasebortfall kan resultatet ikke registreres mens DB er utilgjengelig; startfaktumet gjør dette synlig etter gjenoppkobling.

## Felles rapport og korrekt avslutningsvisning

Aktiv rapport og sluttrapport bruker samme `tools/report_renderer.js` og samme sessionavgrensede SQL-read-model i `tools/report_queries.sql`. Rapporten følger hele sessionen; dashboardets tidsvindu eller sammenligningsvalg endrer ikke rapportens akser eller innhold. Begge inkluderer HA-timesdata, kildemerking og kronologisk oversikt over livsløp, B/P-overganger, målesett/revisjoner, tidskorrigeringer, kriterieendringer/fravik, notater, operatørhandlinger, eksporthendelser og driftsmeldinger. Avslutning starter eksporten, så bekreftelsen på akkurat denne eksporten registreres etter at rapporten er generert.

Resultatdekoding godtar både vanlige SELECT-rader og CALL-resultatsett. Avsluttet session publiseres fortsatt som `completed` mens arkivering pågår; den skal ikke vises som nytt templatevalg. Arkiveringsstart svarer med allerede verifisert, pågår, startet eller ingen avsluttet session, ut fra MariaDB. Et pending forsøk kan gjenopptas etter restart uten at livsløpet avsluttes en gang til.

## SQLite-arkiver fra p24r10

Fanen **Template og arkiv** har et eget arkivkort. Velg `-template.sqlite` og, ved gjæringsimport, tilhørende `-gjaering.sqlite`. Kontroller forhåndsvisningen før import. Filenes format, skjema, integritet, transportkontrollsum og sammenhørende manifest kontrolleres. Domene-FK-er og CHECK-er håndheves under selve importtransaksjonen. Feil vises i arkivkortet og ruller tilbake både template og sesjon.

Filene navngis `session-<sessionid>-export-<exportid>-gjaering.sqlite` og `session-<sessionid>-export-<exportid>-template.sqlite`. Template-filen inneholder én original publisert versjon, med nødvendig registergrunnlag. Gjæringsfilen har normaliserte målinger, timedata, frozen grunnlag, vurderinger, korreksjoner, observasjoner, overgangshistorikk og beregnede fakta. Den inneholder ikke mutable UI-valg eller globale systemfeil. Kildeversionens ID bevares som kildeproveniens; andre templates i en versjonskjede importeres ikke.

Importert original er skrivebeskyttet i sin egen kategori. Bruk **Opprett ny template fra eksisterende versjon** med ny ID og navn for å lage en egen redigerbar kopi. Samme importoperasjon gjenbruker sin kvittering; samme gjæringsarkivpar importeres én gang. Separate template-importer får egne unike IDs også når navn og kildeversjon er like.

Import er tillatt mens gjæring pågår. Filkontroll og SQLite kjører i en worker thread; en egen forbindelse til den samme MariaDB-instansen eier hele importtransaksjonen. Den ordinære motorens mysql-node og autoritative dataflyt beholdes. Dette er en avgrenset filoverføringsadapter, ikke en ny beregnings- eller rapportmotor. Ingen manuell kø, fil-lås eller lokal domenestate innføres.

Midlertidig filopplasting går som autentiserte HA-hendelser med 64 KiB deler og DB-kvittering. Disse byte-delene er transport, ikke domenelagring. Maksimal filstørrelse er 512 MiB. Historikk blir tilgjengelig i sammenligningslisten etter import; **Skjul fra sammenligning** legger til en synlighetshendelse og sletter ingen data. SQLite-filer fra eldre, uvedkommende eller fremtidige formater avvises. Tidligere JSON-arkiver konverteres ikke i denne versjonen.

Alle runtime-søk og grafer bruker MariaDB etter import. Filstørrelsen bestemmes av faktisk historikk; SQLite fjerner JSONs gjentatte feltnavn, men gir ingen garanti om en bestemt komprimeringsfaktor. Alle eksisterende målepunkter beholdes i arkivet.

## P24r11 samlet import og aktiv eksport

Øverst i Template og arkiv velges SQLite-filene og deres SHA-filer i ett filfelt. Backend leser template-navn og versjon fra filinnhold og parer etter eksport-ID/session-ID/version-ID. Velg arkivnavn, deretter **kun template** eller **template og gjæringsdata**. En manglende gjæringsfil gjør bare template tilgjengelig. Begge importtypene oppretter en unik importert original.

Eksport av aktiv gjæring er tilgjengelig i samme kort. SQLite-par og HTML bygges fra samme konsistente database-snapshot, med tidspunkt og merking aktivt øyeblikksbilde. Gjæringen fortsetter. Import av et slikt sett blir separat frigitt historikk for sammenligning og overtar aldri aktiv drift.

Hver SQLite-fil får en sidefil med navnet `<fil>.sqlite.sha`, SHA-256 og filnavn. Manglende, uleselig eller avvikende sidefil vises som advarsel i forhåndsvisning og arkivloggen, men import er tillatt. Skadde eller uvedkommende SQLite-filer, feil skjema og feil eksportpar avvises. Intern transportkontrollsum valideres uavhengig av sidefilen.

**Slett gjæring fra MariaDB** fjerner hele den historiske sesjonen etter bekreftelse. En ubrukt importert originaltemplate kan tas med via avkrysning. Importerte templates vises separat med bruksreferanser og egen sletteknapp når de er ubrukte.
