---
doc_id: DOC-14
role: decisions
status: normative
source_format: markdown
---

# 14 – Aktive beslutninger

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

**Rolle:** Stabilt ADR/DEC-register. ID-er gjenbrukes ikke. En beslutning som erstattes beholdes i historisk referanse/releasehistorikk; gjeldende dokument inneholder bare aktive beslutninger.

| ID | Beslutning | Begrunnelse | Konsekvens |
|---|---|---|---|
| DEC-GA-001 | MariaDB/InnoDB er eneste persistente authority. | Én sannhetskilde reduserer divergens og restartproblemer. | Domenestate i flow/global/HA/frontend/runtimefiler er ikke tillatt. |
| DEC-GA-002 | Node-RED er generisk gjæringsmotor/orchestrator; HA er operatørflate. | Tydelig ansvarsdeling. | HA skal ikke være domenemotor. |
| DEC-GA-003 | `p18-r5` er funksjonell/designmessig referanse, ikke teknisk baseline. | Verdifull funksjon/UX skal kunne sammenlignes uten å gjeninnføre svak implementasjon. | SQLite/writer-kø/lokal runtime-state fra referansen kopieres ikke. |
| DEC-GA-004 | Normaliserte domenedata foretrekkes fremfor generiske JSON-event/state-blobs. | Integritet, sporing og DB-validering. | JSON brukes som transport/eksport/read-model, ikke autoritativ runtime. |
| DEC-GA-005 | Tetthet er SG-only. | Én entydig domenekontrakt. | Ingen Brix i GUI, template, runtime, rapport, docs eller tester. |
| DEC-GA-007 | E2E-/måltest går gjennom den reelle operatør-/integrasjonsgrensen. | Direkte DB/inject kan gi falsk trygghet. | Direkte tester kan være unit/integration, men ikke kalles operatør-E2E. |
| DEC-GA-008 | HA-semantikk dokumenteres i 05; eksakte maskinmetadata eies av MariaDB-registre. | Unngå parallelle entity/event-lister. | Generert kontrakt er avledet inspeksjon. |
| DEC-GA-009 | Teknisk er operativ observability, ikke bare PASS/FAIL. | Sporadiske runtimefeil må finnes igjen. | Technical Events, aktive issues, målekilde og Systemkontroll vises samlet. |
| DEC-GA-010 | `Tilbake` krever advarsel/bekreftelse, ikke obligatorisk begrunnelse. | Operatørflyten skal ikke blokkeres unødig. | Kommentar kan registreres som generelt notat. |
| DEC-GA-011 | Publiserte defaults/regler skal være eksplisitte; motor/frontend skal ikke gjette fallback. | Skjulte defaults gjør vurderinger irreproduserbare. | Manglende grunnlag er synlig feil/status. |
| DEC-GA-012 | Runtimehistorikk innenfor hver beholdt sesjon er append-only der ny tilstand kan uttrykkes som nytt faktum/revision. Hele historiske sesjoner kan slettes eksplisitt. | Audit og reproduksjon. | Current state utledes i views. |
| DEC-GA-013 | Draft-tabeller er eksplisitte mutable arbeidsflater. | Redigering trenger mutabilitet uten å omskrive historikk. | `session_setup_draft`, `measurement_input_draft`, template-draft skilles fra journal. |
| DEC-GA-014 | Ingen generell writer-kø eller eksplisitt DB-locking som normalmekanisme. | InnoDB håndterer concurrency; applikasjonslocking øker kompleksitet. | Modell/constraints/transaksjon revurderes før locking innføres. |
| DEC-GA-015 | PK/FK/UNIQUE/CHECK, operation-ID og korte transaksjoner er primær konsistensmekanisme. | Konsistens bør ligge nær data. | Applikasjonen bygger på DB-integritet. |
| DEC-GA-016 | Kortvarig stale read er akseptabelt. | Normal MVCC/snapshot-adferd trenger ikke global serialisering. | Neste read-model-refresh viser siste commit. |
| DEC-GA-017 | Deadlock analyseres som modell/SQL-symptom, ikke maskeres med generell retry. | Retry kan skjule strukturelle feil. | Konkret årsak må forstås før tiltak. |
| DEC-GA-018 | Funksjonell verdi prioriteres; teknisk arbeid gjøres når robust funksjon krever det. | Prototypearbeidet skal ikke bli infrastrukturprosjekt. | Teknisk kompleksitet må begrunnes av konkret behov. |
| DEC-GA-019 | Runtime-/valideringsmetadata har én autoritativ kilde. | Metadata-duplisering gir drift. | HA-metadata og funksjon↔informasjon-lineage modelleres i MariaDB. |
| DEC-GA-020 | Ordinær Start omfatter history catch-up og overgang til kontinuerlig 5-minuttersimport. | Én sammenhengende måleprosess. | Ingen separat «live-start»-modus. |
| DEC-GA-021 | `Start fra` er opprinnelig pitch-/importstart; senere pitchkorreksjon omskriver ikke måletimestamps. | Historiske målepunkter må beholde faktisk tid. | Effektiv pitchreferanse kan revideres separat. |
| DEC-GA-022 | Eksterne Tilt entity-ID-er eies av `measurement_source_profiles`. | Sensorbinding er konfigurasjon. | Node-RED Function-kode hardkoder ikke entity-ID-er. |
| DEC-GA-023 | Heartbeat er autoritativt datadekningssignal. | Uendret SG/temperatur betyr ikke kommunikasjonsbrudd. | Gap bygges fra heartbeat og persisteres i `measurement_data_gaps`. |
| ADR-GA-024 | Registry, template, frozen session og motor har separate ansvar. | Fagregler må være deklarative/reproduserbare. | Registry definerer vokabular; template velger; Start fryser; motor utfører generiske modeller. |
| DEC-GA-025 | Metric-ID alene skal ikke gi skjult beregningssemantikk. | Navn er ikke fagregel. | Beregningsmodell/input/parametere er eksplisitte metadata. |
| DEC-GA-026 | Freshness og persistens/stabilitet er separate begreper. | De beskriver ulike egenskaper. | Maks alder skal ikke brukes som skjult persistensregel. |
| DEC-GA-027 | Biologisk progresjon er sekvensiell; datagap bryter nødvendig kontinuitet. | Hindrer historiske hopp og falsk persistens. | Bare neste B-kandidat vurderes. |
| DEC-GA-028 | Målekildestatus har én MariaDB-read-model/produsent. | Konkurrerende produsenter ga stale/motstridende status. | Ingest/Systemkontroll trigger refresh, men lager ikke alternativ status. |
| DEC-GA-029 | HA-inputbinding/verdimapping eies av MariaDB. | Entity→domene-felt skal ikke ligge som lokal Function-tabell. | Manglende binding/mapping er konfigurasjonsfeil. |
| DEC-GA-030 | Frontend er ren visning/interaksjon av ferdige domenefelt. | GUI-workarounds skjuler kildedefekter. | Ingen domeneberegning/fallback/formatregler i frontend. |
| DEC-GA-031 | En metric har én autoritativ beregningsbane. | Parallelle formler gir mismatch. | Overview/B/P/report/Analyse leser persistert resultat/read-model. |
| DEC-GA-032 | DB/read-model-feil skal være synlig og rettes ved kilden. | Fail-visible gir bedre arkitektur enn skjult fallback. | GUI/Node-RED skal ikke maskere feil med lokal workaround. |
| DEC-GA-033 | Ugyldige råmålinger forkastes før autoritativ domenelagring; de clampes ikke. | Korrigerte oppdiktede data forurenser analysegrunnlaget. | Kvalitetsutfall logges separat. |
| DEC-GA-034 | Analysevisualisering og behandlingsregler er datamodell/template-metadata. | Nye grafer skal ikke kreve spesialmotor/frontend. | Graph/series/warm-up/gap/markerpolicy fryses til session. |
| DEC-GA-035 | Utilstrekkelig minste beregningsgrunnlag gir ingen verdi; p24r7 krever ordinært faktisk grunnlag. | Unngå oppdiktede tall. | Status, datagrunnlag og stil leveres fra read-model; ordinære krav beholdes. |
| DEC-GA-036 | Uncaught teknisk feilfangst er et generelt flow-safety-net. | Nye noder skal ikke falle utenfor «søppelbøtta». | Technical Event-writer/fangstsløyfe skjermes mot rekursjon. |
| DEC-GA-037 | Gyldighetsdomene for avledede metrics er domenemetadata og håndheves før B/P og Analyse. | Urimelige derived values skal ikke drive overganger eller grafer. | Output utenfor frozen domene avvises, ikke clampes. |
| DEC-GA-038 | Historisk P-autoovergang er per-step frozen policy. | Historikk kan rekonstrueres uten å late som fysisk operatørhandling er utført. | W-34/70 kan autoetablere P1/P2; P3+ krever operatørtransition. |
| DEC-GA-039 | Rapport/Gjæring/Analyse bruker autoritative datagap og samme domeneseriegrunnlag. | Linje gjennom manglende data skaper oppdiktet visuell informasjon. | Renderer bryter kurver ved persisterte gap. |
| DEC-GA-040 | Normativ dokumentasjon skal beskrive gjeldende sannhet; releasehistorikk holdes separat og maskinmetadata genereres fra kilder. | Historikk i kravdokumenter gjorde dem stale og vanskelige å validere. | Markdown er kilde; HTML/JSON/traceability genereres og releasekontrolleres. |
| DEC-GA-041 | Templateadministrasjon er uavhengig av runtime/session. | Frozen sessionplan gjør senere templatearbeid trygt. | Aktiv eller completed session blokkerer ikke templatebibliotek, draft eller publisering. |
| DEC-GA-042 | Template lifecycle er `draft/published/retired`, og `retired` er reversibel. | En versjon kan tas ut av Start-utvalget uten å slette historikk eller tvinge ny versjon. | Retired versjon kan reaktiveres; publisert/retired faginnhold er immutable. |
| DEC-GA-043 | Template-fanens administrasjonsvalg og Start-fanens templatevalg er separate MariaDB-fakta. | Inspeksjon/redigering skal ikke utilsiktet endre hvilken prosess neste gjæring starter med. | Publisering/åpning i Template-fanen endrer ikke `session_setup_draft`; Start kan kun velge `published`. |
| DEC-GA-044 | Verifikasjon modelleres som strukturerte relasjoner i MariaDB. | Krav, verifikasjon og resultater må kunne inspiseres og analyseres uten tekstsøk. | Metadata og faktiske resultater skilles; read-models utleder status. |
| DEC-GA-045 | TECH, FUNC og UAT er separate verifikasjonsklasser. | Teknisk integritet, domeneregresjon og målmiljøbruk har ulike testegenskaper. | Testtype og metode er eksplisitt metadata; én type erstatter ikke de andre. |
| DEC-GA-046 | Høy testbarhet beholdes selv når hele testpakken ikke kjøres ved hver prototypeendring. | Testarkitektur har verdi, men prototypearbeidet skal ikke styres av testprosess. | Testomfang tilpasses risiko; etablerte regresjonstester bevares. |
| DEC-GA-047 | UAT-resultater er append-only verifikasjonsfakta og kan registreres fra dashboardet. | Målmiljøerfaring skal være synlig og analyserbar sammen med krav/testmetadata. | Ny UAT gir ny run/result; tidligere observasjoner overskrives ikke. |
| DEC-GA-048 | JSON-eksport og HTML-verifikasjonsrapport produseres fra samme DB-grunnlag. | Maskinanalyse og menneskelesing skal beskrive samme snapshot. | Rapportgeneratoren presenterer; den beregner ikke alternativ verifikasjonsstatus. |
| DEC-GA-049 | Komplett p19-dokumentasjon distribueres ikke i p23-release. | Historisk teknisk arkitektur kan forveksles med gjeldende løsning. | Bare eksplisitte baseline-/forlatt-løsning-referanser beholdes. |
| DEC-GA-050 | Separat FastAPI/backend-lag og tidligere SQLite-/writer-kø-arkitektur er forlatte løsninger og skal ikke gjeninnføres som workaround. | De økte kompleksitet og ga flere sannhetskilder/concurrencyproblemer uten funksjonell gevinst. | Gjeldende p24 er Node-RED ↔ MariaDB direkte med InnoDB/constraints/transaksjoner og DB-eide read-models. |

| DEC-GA-051 | B/P og detaljbasert Analyse bruker samme målebaserte modell; historiske timeverdier er separat grafgrunnlag. | Samme beregningsgrunnlag og terskler. | Ordinære verdier og datagrunnlag persisteres append-only; utilstrekkelig grunnlag gir fravær. |
| DEC-GA-052 | Bånd er størrelsens metadata, ikke en universell grafregel. | Et bånd må ha konkret fysisk/statistisk betydning. | P24r7-AA/rate/stabilitet har ingen estimert bånd. Oversiktsgrafer kan vise faktisk min/maks-spredning fra samme godkjente prøvesett. |
| DEC-GA-053 | Biologisk fase endres gjennom kriterievurdering. | En fase skal kunne forklares fra sitt grunnlag. | Direkte fasesetter fjernes; korreksjon/fravik er egne append-only fakta. |
| DEC-GA-054 | Modellens tillatte kriterieparametere er korrigerbare og fravik tillatt som standard. | Operatøren trenger konsistent håndtering på B og P. | Editor kan deaktivere rettigheter; Start fryser policyen. |
| DEC-GA-055 | Alle gjæringsgrafer starter ved effektiv pitch. | Sammenlignbar oppstart og synlig ventetid. | DB/read-model leverer felles X-akse til dashboard og rapporter. |

| DEC-P24R6-001 | Målebasert Analyse og filverifisert eksport | Manglende pitchhistorikk og store SQL-pakker blokkerte bruk | Separate rå/manuelle AA-kilder, målt endepunktrate, ordinære vinduer, metadata-only eksportregistrering og append-only retry. |

| DEC-P24R8-TRANSPORT | Felles presentasjonsordbok og komprimert publisering | Gjentatt metadata var hovedårsaken til store filer. | Ingen råmålinger slettes ved transportkomprimering; DB styrer utvalg og verdier. |

| DEC-P24R9-CURRENT | Importbehov og gjeldende grafkrav utledes i MariaDB. | Gjentatt statistikkhenting og gamle kravlinjer ga misvisende visning. | Normal live-import henter detaljdata; parameterkorreksjon/reset og oppfylt-markører følger DB-revisjonen. Tidligere målinger og evalueringer beholdes. |

## Arkivformat og import

| ID | Beslutning | Begrunnelse | Konsekvens |
| --- | --- | --- | --- |
| DEC-P24R10-ARCHIVES | Gjærings- og originaltemplate-arkiv er et sammenhørende SQLite-par. | Filer skal være søkbare og kunne importeres uten å sende store JSON-pakker til DB. | All runtime authority og all sammenligning ligger fortsatt i MariaDB. |
| DEC-P24R10-IMPORT | Importert original får ny identitet og egen kategori; historisk import frigir sesjonen atomisk. | Kilden skal ikke blandes med eksisterende templates eller aktiv gjæring. | Import er tillatt under gjæring; feil ruller tilbake hele settet og redigering krever egen kopi. |

## Sesjonssletting og konsistent utveksling

| ID | Beslutning | Begrunnelse | Konsekvens |
| --- | --- | --- | --- |
| DEC-P24R11-DELETE | Append-only gjelder innholdet i hver beholdt sesjon, ikke hele databasen. | Gamle sesjoner skal kunne ryddes etter eksport eller sammenligning. | Eksplisitt sletting av hele sesjonen i én transaksjon, med aktivbeskyttelse og referansekontroll for templates. |
| DEC-P24R11-SNAPSHOT | Alle eksportfiler for en sesjon bygger på ett konsistent MariaDB-snapshot. | Aktiv drift skal kunne fortsette mens arkivet lages. | SQLite-par, HTML og SHA-filer deler prefix; aktivt øyeblikksbilde merkes med tidspunkt. |
| DEC-P24R11-SHA | Eksterne SHA-filer er en valgfri kontroll med advarsel. | Gamle eller flyttede arkiver skal fortsatt kunne importeres. | Manglende/feil SHA blokkerer ikke import; intern integritet og faktisk overføring valideres obligatorisk. |

## Versjonering og videreføring

| ID | Beslutning | Begrunnelse | Konsekvens |
|---|---|---|---|
| DEC-RELEASE-001 | Datoversjon ÅÅÅÅ.MM.DD-N, v-prefiks på tag og kort releasebeskrivelse. | Entydig publiseringsdag og identitet uten prototype-serier. | Løpenummer starter på 1 hver publiseringsdag; prosjektversjon samordnes i leveranse- og runtime-metadata. |
| DEC-WORK-001 | Avklaring i chat, «start», implementering og relevante kontroller; direkte commit på main. | Dagens avtalte prosjektarbeidsmåte. | Issues/PR og den gamle Chat→Work-handoff-prosessen videreføres ikke. |

## Databevaring og oppstart

| ID | Beslutning | Begrunnelse | Konsekvens |
|---|---|---|---|
| DEC-PROD-001 | Installasjon bevarer eksisterende data; verifiserte migreringer erstatter prototype-reset. | Brukeren tar løsningen i ordinær drift. | Førstegangsseeding kjøres bare på tom database. Privat backup før oppgradering; ukjent kilde avvises. Erstatter tidligere DEC-GA-006. |
| DEC-START-001 | Startfelt, mangler og startklarstatus eies av databasekladden og DB-registre. | Gamle HA-tall kunne skjule NULL etter nytt templatevalg. | Generisk DB-basert skjema sender eksplisitte feltkommandoer; ingen HA-fallback eller null-til-nulltall. Startforsøk lagrer observerte felt og DB-avvisning. |

## Sensorbindinger og operatørfelt

| ID | Beslutning | Begrunnelse | Konsekvens |
|---|---|---|---|
| DEC-SOURCES-001 | DB-eide reviderte signalbindinger, fryst per sesjon og virkning fra neste DB-bøttegrense ved livebytte. | Kildebytter må være sporbare uten å omskrive tidligere data. | HA-katalog er kontrollert teknisk snapshot; NR transporterer. Valgfritt overtrykk bruker DB-deklarert enhet/konvertering og er manuelt før valg. |
| DEC-OPERATOR-001 | Feltkontroll og desimaler følger DB-registeret; B/P-avvik bruker samme autoritative transaksjon. | Synlig verdi, mangler og tillatte handlinger må stemme med DB. | Slider har eksplisitt ikke registrert og registrert 0. Kildenavn er lesbare mens rå identitet bevares. |
