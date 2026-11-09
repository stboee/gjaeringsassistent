---
doc_id: DOC-ONBOARDING
role: governance
status: current
source_format: markdown
---

# Onboarding av en ny chat

Dette er den faste inngangen for en ny chat som skal videreføre Gjæringsassistent. Instruksjonen beskriver hvordan prosjektforståelsen etableres og kontrolleres. Krav, beslutninger og strukturerte registre beholder sine egne autoritative kilder; denne siden er et lesekart.

Repository: https://github.com/stboee/gjaeringsassistent.
Bruk gjeldende main og siste relevante release, ikke en gammel kopi av dette dokumentet som udatert statusfasit.

Råtekst ved behov: https://raw.githubusercontent.com/stboee/gjaeringsassistent/main/docs/ONBOARDING-NY-CHAT.md.

## 1. Tekst prosjekteier kan gi en ny chat

> Vi viderefører Gjæringsassistent. Les https://github.com/stboee/gjaeringsassistent/blob/main/docs/ONBOARDING-NY-CHAT.md og gjennomfør onboardingen som beskrives der. Etabler først forståelse av gjeldende kilder, leveranse, installasjonsstatus, arkitektur og åpent arbeid. Oppsummer hva du faktisk har lest, hvilke bindende prinsipper som gjelder og hva som gjenstår. Vi diskuterer videre arbeid før jeg sier «start». Ikke endre kode, bygg en ny utgave eller kjør installasjon som del av onboardingen.

Oppgi gjerne faktisk installert versjon og en fersk Teknisk-/Systemkontrollrapport hvis den finnes. Manglende rapport hindrer ikke lesing og prosjektforståelse; det betyr at målmiljøstatus må stå som ukjent der bevis mangler.

## 2. Fastslå hvilket grunnlag du har

1. Bekreft hvilke repositoryfiler, releases, vedlegg og tidligere samtaler du faktisk har tilgang til. Ikke påstå at en gammel chat eller rapport er lest uten å ha åpnet den.
2. Registrer full commit-SHA for main, VERSION, nyeste relevante release/tag og taggens kildecommit. Les releasebeskrivelsen og identiteten i BUILD-INFO.json.
3. Skill main fra publisert release. Dokumentasjon kan være nyere på main uten at en ny installasjonspakke er gitt ut. En GitHub-generert kilde-ZIP og prosjektets bygde installasjonspakke er forskjellige artefakter.
4. Hvis en leveransepakke brukes som teknisk grunnlag: kontroller den mot medfølgende SHA-256 og kontroller versjon/kildecommit. Ikke bruk den lokale forberedelsespakkens hash som hash for en senere CI-bygget release.
5. Fastslå faktisk installert versjon fra nyere brukerbekreftelse eller rapport. Siste release er ikke automatisk installert. Ikke anta at det finnes en aktiv gjæring, eller at historiske logger viser en aktuell feil.

Onboarding er lesing og inspeksjon. Den starter ikke containere, database-reset, tester som skriver data, migrering eller installasjon.

## 3. Les i denne rekkefølgen

Les først kjernen. Bruk deretter fagområdene nedenfor til målrettet fordypning. Ikke fyll konteksten med komplette SQL-dumper, millioner av katalogtegn eller gjentatte kopier av de samme dataene.

| Trinn | Kilder | Hva du skal forstå |
|---|---|---|
| Arbeidsregler og orientering | [AGENTS.md](../AGENTS.md), [README.md](../README.md), [OVERLEVERING.md](../OVERLEVERING.md) | Arbeidsmåte, aktuell leveranse, siste bekreftelser og avgrensninger. |
| Identitet og bevis | VERSION, BUILD-INFO.json, RELEASE-MANIFEST.json, RELEASE-NOTES.md, TEST-RESULTS.md i repo-roten; GitHub Release og relevant Actions-kjøring | Hvilken kode/pakke bevisene gjelder, og hva som faktisk er levert og testet. |
| Dokumenthierarki og beslutninger | [Dokumentkart 00](00-DOKUMENTKART-OG-STATUS.md), [aktive beslutninger 14](14-AKTIVE-BESLUTNINGER.md) | Hvem som eier ulike informasjonstyper, gjeldende beslutninger og forlatte løsninger. |
| Produkt og arkitektur | [Felles krav 01](01-KRAV-FELLES.md), [arkitektur 07](07-SYSTEMARKITEKTUR-OG-DATAFLYT.md) | Produktgrenser, ansvar, livsløp og dataflyt. |
| Kontrakter og datamodell | [Integrasjon 05](05-FRONTEND-OG-INTEGRASJONSKONTRAKT.md), [persistens 06](06-DATAMODELL-OG-PERSISTENS.md), [operasjoner 12](12-OPERASJONS-OG-TRANSAKSJONSKONTRAKT.md) | HA ↔ Node-RED ↔ MariaDB, normalisering, transaksjoner, revisjoner og fravær. |
| Gjeldende status | [Åpent arbeid 15](15-AAPENT-ARBEID.md), [implementasjonsstatus 18](18-IMPLEMENTASJONS-OG-VERIFIKASJONSSTATUS.md), [akseptanse 09](09-AKSEPTANSETEST.md) | Reelt gjenstående arbeid og skillet mellom implementert, lokalt verifisert og målmiljøbekreftet. |
| Strukturerte kilder | Avsnitt 4 nedenfor | Faktiske registrerte kontrakter, regler, schema- og verifikasjonsmetadata. |

Før arbeid på et område leses også de relevante detaljene:

| Område | Fordypning |
|---|---|
| Motor og frontend | [Krav 02](02-KRAV-MOTOR-OG-INTEGRASJON.md), [krav 03](03-KRAV-DASHBOARD.md), berørte Node-RED-noder og dashboardkode. |
| Installer og produksjonsoppgradering | [Krav 04](04-KRAV-INSTALLER.md), [drift 08](08-DRIFTSVEILEDNING.md), installer/install.sh og compose-referansen. |
| Kriterier, templates og gjærprofiler | [Regelmodell 10](10-REGEL-OG-EVALUERINGSMODELL.md), [template/editor 11](11-TEMPLATE-OG-EDITOR-MODELL.md), [W-34/70 16](16-W3470-FAGGRUNNLAG-OG-PROSESSMODELL.md), [ale-profiler 17](17-ALE-TEMPLATER-OG-FAKTA.md) og relevante SQL-seeder. |
| Livsløp, etterregistrering og arkiver | [Dokument 13](13-LIVSLOP-OBSERVASJONER-RAPPORT-OG-HISTORIKK.md), berørte rutiner/views og arkivkontrakten. |
| Systemkontroll og feil | [Teknisk diagnostikk 19](19-TEKNISK-FANE-OG-DRIFTSMELDINGER.md), fersk Teknisk-/Systemkontrollrapport og de konkrete DB-/transportbanene. |
| Grafer og ytelse | Dokument 03/07/10/13, SQL-read-models og leseplan, tools/graph_renderer.js og relevante testbevis. |

## 4. Undersøk strukturerte data, ikke bare forklaringene

Å ha lest README eller et generert JSON-uttrekk er ikke tilstrekkelig. Finn de faktiske definisjonene og bindingene i SQL-/registry-kildene. Bruk målrettede søk, tabell-/kolonnedefinisjoner og konkrete relasjoner; ikke anta at et navn alene beskriver regelen.

| Informasjon | Kilder som skal undersøkes |
|---|---|
| Fysisk datamodell og integritet | sql/00-template-schema.sql, sql/10-runtime-schema.sql, relevante rutiner i sql/11-runtime-routines.sql og views i sql/20-views.sql. Installerrekkefølgen er også del av kontrakten. |
| HA-identitet, input og valg | ha_entity_registry, ha_event_registry, ha_entity_input_bindings, ha_entity_input_value_mappings og constraint-/valgregistre; særlig sql/21-system-metadata-seed.sql. |
| Ferdig HA-output | ha_projection_routes, ha_projection_fields, ha_draft_output_bindings, tilhørende DB-projeksjoner og faktiske fysiske flowkoblinger. |
| Funksjon–informasjon-avhengigheter | system_functions, information_objects og function_information_dependencies. |
| Schema- og fraværssemantikk | schema_relation_semantics og schema_absence_semantics; fysisk DDL og, hvis autorisert tilgjengelig, MariaDB INFORMATION_SCHEMA. |
| Regler og frosset sesjonsgrunnlag | sql/01-template-registry-seed.sql, sql/02-runtime-registry-seed.sql, sql/03-w3470-template-seed.sql, sql/04-ale-templates-seed.sql, sql/23-measurement-source-seed.sql og berørte session-relasjoner. |
| Verifikasjon og faktiske resultater | verification/test-catalog.json, verification/verification-model.json, sql/24-verification-metadata-seed.sql, sql/25-release-verification-results-seed.sql og verification_test_runs/verification_test_results. Les relevante resultatfiler og kildeavtrykk. |

contracts/ha-node-red-contract.json, den fysiske schemakatalogen og docs/generated er avledet inspeksjon. De erstatter ikke eierregistrene. HTML genereres fra Markdown. Katalogdekning er ikke alene et bevis på full normalisering eller korrekt domenesemantikk.

Du trenger ikke et kjørende målmiljø for å gjennomføre kildeonboarding. Skill kildeinspeksjon fra faktisk kontroll av installert MariaDB/HA/Node-RED.

## 5. Vis at arkitektursperrene er forstått

Kontroller prinsippene mot gjeldende beslutninger og relevante kilder:

- MariaDB/InnoDB er eneste autoritative persistente domenekilde. Node-RED utfører generiske, DB-valgte modeller og transport; HA/frontend viser ferdige domenefelt og formidler handlinger.
- Feil eller mangler rettes i datamodell, registry, frozen session eller read-model. Ingen lokale defaults, oppdiktede verdier, reserveberegninger eller frontend-workarounds.
- Registry definerer vokabular/modeller; template velger; Start fryser en normalisert sesjonskopi. Senere korreksjoner bruker eksplisitte, sporbare mekanismer.
- Påkrevde kontraktfelt skal leveres. Reelt fravær må modelleres og forklares og skal ikke erstattes med 0.
- Normaliserte relasjoner, constraints og korte transaksjoner håndhever integritet. InnoDB håndterer normal samtidighet; ingen generell writer-kø eller applikasjonslocking som standard.
- Append-only gjelder fakta/revisjoner innenfor hver beholdt sesjon. Hele historiske sesjoner og ubrukte importerte templates kan slettes eksplisitt og atomisk. Drafts er egne mutable arbeidsflater.
- SG-only, separate biologiske faser og prosesstrinn, én operativ sesjon og ingen automatisk fysisk utstyrsstyring.
- B/P-start, slutt og varighet følger DB-eide tidsrevisjoner og nabogrenser. Frontend skal ikke korrigere varigheten ved visning.
- Felles graftegner og autoritativt seriegrunnlag i dashboard og rapport. Manglende måleverdier estimeres ikke. HA-timesstatistikk er separat historisk grafgrunnlag uten oppdiktet heartbeat eller ordinært B/P-grunnlag.
- SQLite-par er arkiv-/utvekslingsformat. Operativ sammenligning skjer i MariaDB etter import. Importert template har egen unik identitet og opprinnelse.

Forklar kort hvordan en manglende påkrevd visningsverdi skal spores fra HA/Node-RED til den autoritative kilden. Forklar også forskjellen mellom en append-only sesjonskorreksjon og eksplisitt sletting av en hel gammel sesjon. Dette gjør forståelsen kontrollerbar.

Flyktig transport-/UI-state og pixelkoordinater for tegning er tekniske mekanismer. De skal ikke forveksles med nødvendig domenepersistens eller brukes til alternative fagberegninger.

## 6. Første svar etter onboardingen

Gi en kort, kildebasert kvittering med:

1. Kilder du faktisk har åpnet, samt vesentlige mangler i tilgangen.
2. Main-SHA, relevant release/tag, teknisk utgangspunkt og faktisk installasjonsstatus. Merk det som er ukjent.
3. De bindende prinsippene, med filreferanser og gjerne relevante beslutnings-ID-er.
4. Siste endringer, utførte tester og hva bevisene ikke dekker. Skill syntaks/statisk kontroll, native DB/plugin-integrasjon og faktisk HA-/nettleser-UAT.
5. Reelle åpne feil/måltester, dokumentasjonsmotstrid og pågående, allerede avklart arbeid.
6. Foreslått neste avgrensede arbeid og eventuelle spørsmål som faktisk blokkerer det.

Ikke erklær et krav oppfylt bare fordi kode finnes eller en test sier PASS. Ikke merk alle UAT bestått på grunnlag av en generell positiv brukermelding. Nye observasjoner må knyttes til riktig versjon og tidspunkt.

Onboarding alene er ikke bestilling av en ny programvareversjon. Nye arbeidsomfang avklares før «start». Ved uttrykkelig videreføring av allerede godkjent arbeid skal eksisterende autorisasjon og siste styring bevares; ikke krev gjentatte godkjenninger av samme oppgave.

## 7. Arbeidsmåte og produksjonsgrense

Arbeid direkte på main etter avtalt bestilling. Issues, PR og den tidligere Chat→Work/handoff-prosessen inngår ikke i prosjektprosessen. Versjoner bruker ÅÅÅÅ.MM.DD-N med v-prefiks på tag og kort beskrivelse i release-tittelen. Eldre testfilnavn er referanser, ikke gjeldende versjonsnummerering.

Rene dokumentoppdateringer kan ligge på main etter siste tag. Ikke påstå at de dermed inngår i en allerede publisert ZIP. En eksisterende release/tag skal ikke omskrives for å få dokumenthistorikken til å stemme.

**Installeren bevarer databasen gjennom deklarerte migreringer.** Støttede kilder og strukturavtrykk står i installer/migrations.json; målmiljøbekreftelse er fortsatt åpen. Kontroller alltid siste status før installasjons-/oppgraderingsforslag; ikke bruk en prototypebestilling om reset som varig produksjonsautorisasjon. Onboarding gir ikke adgang til å kjøre installasjon, restart eller datamigrering.

Historiske pakker brukes bare når dagens dokumentasjon uttrykkelig gir dem en rolle. P17r12/p18r5 er funksjonelle/designmessige referanser, ikke teknisk baseline. Forlatt SQLite-runtime, separat backend eller writer-kø skal ikke gjeninnføres som løsning på et nytt problem.

## 8. Hold videreføringen oppdatert

Etter en leveranse eller vesentlig statusendring oppdateres OVERLEVERING.md, relevante statusdokumenter og faktisk verifikasjonsgrunnlag. Bevar skillet mellom foreslått, besluttet, implementert, testet, publisert og installert.

Noter kort: gjeldende kode/pakke, siste brukerbekreftelse, åpne konkrete feil, avtalt neste omfang og om arbeidet er startet. Ikke dupliser hele historikken i normative dokumenter.

Prosjekteier skal kunne gi en ny chat lenken til denne siden og eventuell fersk målmiljøstatus. Prosjektet skal kunne gjenopptas fra repositoryets kilder uten at den gamle chatten er tilgjengelig.
