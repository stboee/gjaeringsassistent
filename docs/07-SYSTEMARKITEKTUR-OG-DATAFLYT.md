---
doc_id: DOC-07
role: architecture
status: normative
source_format: markdown
---

# 07 – Systemarkitektur og dataflyt

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

**Rolle:** Hovedinngang til gjeldende arkitektur, ansvar og dataflyt.

![Systemarkitektur](figures/FIG-01-SYSTEMARKITEKTUR.svg)

## Ansvarsdeling

```text
MariaDB = data, regler, read-model og ferdig presentasjonsinnhold
Node-RED = generisk motor, orchestrering, integrasjon og transport
Home Assistant/frontend = operatørinteraksjon og visning
```

- MariaDB/InnoDB er eneste persistente authority.
- Det finnes ingen separat applikasjonsbackend mellom Node-RED og MariaDB.
- `flow.*`, skrivbar `global.*`, browser-state, HA-state og runtimefiler skal ikke være nødvendig domenepersistens.
- Node-RED kan implementere generiske algoritmer/modelltyper, men fagregelvalg/terskler/vinduer/policy ligger i registry/template/frozen session.
- Frontend viser ferdige DB/read-model-felt og utfører bare UI-/renderingmekanikk.
- Rene reads kan kjøres parallelt. Faglige mutasjoner er korte atomiske transaksjoner. InnoDB håndterer concurrency; ingen global writer-kø eller normal eksplisitt locking.
- Runtimehistorikk er append-only når ny tilstand kan uttrykkes som nye fakta/revisions. Current-state utledes i views.

## Registry → template → frozen session → motor

![Regel- og sessionflyt](figures/FIG-04-TEMPLATE-START-SNAPSHOT.svg)

```text
MariaDB registry
  ↓ tillatte generiske modeller, inputs og typed parametere
Publisert template
  ↓ konkret regelvalg, B/P, targets, validering og analysemetadata
Start
  ↓ atomisk freeze
Normalisert session-plan
  ↓
Node-RED generisk evaluator/ingest/analyse
  ↓
Persistente facts, evaluations, transitions og analysis_series
  ↓
MariaDB read-models
  ↓
HA/frontend
```

Ugyldig eller manglende frozen regelgrunnlag er konfigurasjons-/datagrunnlagsfeil. Motoren skal ikke reparere dette med skjulte defaults.

## Måleflyt og datakvalitet

![Måleflyt](figures/FIG-05-MAALINGSFLYT.svg)

```text
HA Recorder-history / live history
   ↓
source/session-frozen validation rules
   ↓ forkast ugyldige prøver; ingen clamp
robust 5-min aggregat
   ↓
measurements_5m + measurement_ingest_quality_events
   ↘ measurement_data_gaps
   ↓
B/P evaluator + Analyse
```

Heartbeat avgjør kildekontinuitet. Datagap persisteres eksplisitt og bryter persistens, grafer og andre regler som krever sammenhengende datadekning. `session_measurement_sources.last_import_cutoff_at` er persistent importcursor; omstart leser cursor fra MariaDB og henter manglende periode fra HA Recorder.

Uten aktiv reell session startes ingen periodisk HA-history-import.

## Historisk replay og live

![Evaluering og replay](figures/FIG-06-EVALUERING-REPLAY.svg)

Historisk catch-up sekvenseres:

```text
persistér 5-min chunk
→ evaluer neste B-kandidat
→ evaluer neste P-kandidat
→ persister result/evidence/evt. tillatt transition
→ neste chunk
```

Historisk evalueringshorizon er persistert importcutoff. Live-horizon er MariaDB UTC-klokke.

B-progresjon er sekvensiell. P-kriterier kan vurderes historisk, men overgang persisteres automatisk bare når frozen `historical_replay_auto_transition_allowed` er sann for akkurat neste steg. Ordinære/live P-overganger er operatørbekreftet.

En persistert transition peker på eksakt `evaluation_id`. Historisk overgangsbevis og current candidate-evaluering er derfor separate read-model-fakta.

## Analyse

Om en beregnet verdi skal ha graf, og hvordan den behandles/presenteres, ligger i template/sessionmetadata. Motor og frontend skal ikke ha graph-ID-spesifikke branches.

P24r7 persisterer kun ordinære analysepunkter når frozen minstegrunnlag, gapkrav, inputdomene og outputdomene er gyldige. Gyldige punkter persisteres append-only i `analysis_series_values`; manglende grunnlag skaper ikke syntetiske nullverdier.

## Read-model og frontendgrense

```text
persistente fakta + frozen regler
  ↓
generisk motor persisterer resultat/provenance
  ↓
MariaDB views lager ferdige value/status/display-felt
  ↓
Node-RED transport
  ↓
HA/custom card
```

Frontend kan escape tekst, styre layout, holde ekspandert UI-state og beregne pixelkoordinater for tegning. Frontend skal ikke beregne FG-fremdrift, kriteriestatus, datavindu, alder, targets, gap, anbefaling eller annen domenesemantikk.

## HA- og systemmetadata

HA entity/event-kontrakten ligger i MariaDB-registre og fysisk Node-RED-flow. Bootstrap, HA-avstemming, Systemkontroll og generert kontrakt leser samme metadata. Inputbindinger og select-mappings ligger i DB; manglende mapping er konfigurasjonsfeil, ikke anledning til lokal fallback.

`system_functions`, `information_objects` og `function_information_dependencies` eier maskinlesbar funksjon↔informasjon-lineage. Produsent→objekt→konsument er avledet view, ikke separat sannhet.

## Teknisk observability

Uncaught Gjæringsassistent-feil går gjennom en generell catch/safety-net til `technical_events` når persistensbanen er tilgjengelig. Spesifikke feilbaner kan supplere dette. Systemkontroll og Teknisk-fane leser persistert teknisk grunnlag; de skal ikke opprette en alternativ sensor-/runtimeautoritet.

## Tid og konsistens

Persistent maskintid er UTC. Operative displaytider forberedes i read-model når de er del av domenepresentasjonen. MariaDB-/Node-RED-klokkesammenligning skal ikke avhenge av tvetydig lokal `DATETIME`-parsing.

Konsistens håndheves i denne rekkefølgen: normalisert datamodell → PK/FK/UNIQUE/CHECK → atomisk transaksjon → append-only fakta/revisions → views/read-model → applikasjonsvalidering/presentasjon.

## Verifikasjonsflyt

```text
REQ / DEC / VER / TEST metadata
            +
append-only TECH/FUNC/UAT-resultater
            ↓
MariaDB verification views
            ↓
Node-RED transport/kommando
            ↓
HA Verifikasjon / Teknisk sammendrag
            ↓
JSON + HTML-eksport fra samme DB-grunnlag
```

UAT er en ordinær stateful operasjon: HA-event → validering mot registrert UAT-test → kort DB-transaksjon → append-only run/result → ny read-model. Feil i verifikasjonsmetadata/status rettes i databasen/kilden; frontend eller Node-RED skal ikke fylle inn antatte relasjoner eller status.

## Asynkron oppstart og gjenoppkobling

MariaDB, Node-RED og Home Assistant må behandles som uavhengige moduler som kan starte, stoppe og koble seg til igjen i vilkårlig rekkefølge. MariaDB er fortsatt eneste persistente domenekilde.

Node-RED kjører en idempotent, read-only restore/reconcile mot MariaDB med periodisk retry. Reconcile republiserer gjeldende DB-state, men oppretter ikke nye biologiske evalueringer eller prosesstransisjoner. Home Assistant-historikkimport har egen retry ved utilgjengelig HA og fortsetter fra den persistente MariaDB-cursoren. Identiske infrastruktursvikt dedupliseres i `technical_events` slik at en frakoblet modul ikke genererer en feilstorm i databasen.

Pitchtemperatur er ikke et separat startfelt; første manuelt målte temperatur er temperaturgrunnlaget ved pitch. Pre-start-kladd skal ikke republiseres periodisk til redigerbare HA-felt mens operatøren skriver; restore retries ved faktisk MariaDB-utilgjengelighet i stedet for periodisk overskriving.

## Autoritet ved presentasjon og operasjon

MariaDB utleder effektiv beredskap, kriterietellinger, fasevarighet, valgbare handlinger og status-/anbefalingstekst. Den generiske evalueringsmotoren bruker frozen DB-policy og persisterer evalueringen før presentasjon. Node-RED transporterer den ferdige read-modelen, validerer kontrakt og utfører forespurte DB-operasjoner. Ingen egen tabell med HA-valg/defaults eller alternativ beredskapsberegning skal overstyre DB-projeksjonen.

Fysiske HA-koblinger kontrolleres mot `ha_projection_routes`; felt kontrolleres mot `ha_projection_fields`. Avvik skal bli synlige og rettes ved sin autoritative kilde.

## Felles graftegner

MariaDB projiserer en felles grafkontrakt gjennom `v_graph_definitions`, `v_graph_series`, `v_graph_axes`, `v_graph_axis_ticks`, `v_graph_time_markers`, `v_graph_latest` og `v_graph_reference_bands`. SQL-adaptere kobler de normaliserte måle-, sammenlignings-, observasjons- og planfakta til metadataenes kildetyper. Den eksisterende metrikkevaluatoren utfører kun DB-valgte beregningsmodeller og lagrer resultatene i MariaDB.

`tools/graph_renderer.js` er eneste SVG-tegner. Byggverktøyet inkluderer identisk kilde i dashboard og begge rapportprodusenter; rapportmodulen bruker samme kildefil. Ingen separat tegner for målegrafer eller rapporter beholdes. Node-RED transporterer DB-kontrakten uten egne standarddata. Eldre arkivkontrakter konverteres ved import før commit, uten å påvirke aktiv gjæring.

## Avgrenset lesing, snapshots og publiseringskvittering

`tools/overview_reads.sql`, `tools/report_reads.sql` og `sql/20-views.sql` er de autoritative lesedefinisjonene. `tools/build_read_queries.py` kompilerer disse til DB-prosedyrer i `sql/11-runtime-routines.sql`. `contracts/read-execution-schema.json` inneholder faktiske MariaDB-typer, tegnsett og kollasjoner; `read-execution-plan.json` beskriver avhengighetsrekkefølgen. Ingen domeneformel oversettes til en ny JavaScript-implementasjon.

`ga_init_read_basis` oppretter tomme, forbindelsesprivate tabeller før read-only-transaksjonen. `ga_fill_read_basis` tar bare med valgt sesjon og eventuell valgt sesjonssammenligning via deklarerte eierskaps-FK-er. Globale bibliotekvalg og tekniske problemer beholder sin globale betydning. Kilder leses med vanlige konsistente SELECT-er; JSON_TABLE fyller de private tabellene internt i databasen. Tidsserier deles i dagsgrupper for å begrense intern JSON-størrelse. Ingen stor JSON-pakke sendes frem og tilbake over DB-adapteren. Mellomresultater beregnes én gang i SQL, i avhengighetsrekkefølge. Private Aria-tabeller er avledede engangsresultater; de er ingen permanent autoritet. Permanente tabeller beholder InnoDB og normal transaksjonshåndtering.

`ga_read_overview` og `ga_read_report` eier normalt sitt konsistente read-only-snapshot og rydder etter både suksess og feil. SQLite-arbeideren oppretter tabellene før sitt snapshot og gjenbruker rapportlesingen innen samme snapshot som arkivinnholdet. Den rydder etter commit/rollback. Ingen global kø eller manuell skrivelås innføres.

`ga_poll_overview` sammenligner kildenes antall/siste daterte endring og valgsekvenser med siste vellykkede publiseringskvittering. Dette er en invalidasjonskontroll over fysiske tabeller, ikke en ny kjøring av grafviews. Permanente uforanderlige parameterbarn dekkes av eierens daterte revisjon. Handlinger tvinger full oppdatering; tid, konfigurasjon uten egen endringsdato og ferskhet vurderes minst hvert DB-angitte `overview_clock_refresh_seconds` (60 sekunder). Detaljpunktoppløsning er fortsatt fem minutter. `read_model_publication_receipts` lagrer bare tekniske publiseringsfakta, ikke domene- eller grafverdier. Node-RED kvitterer først etter vellykket atomisk publisering.

Kriterier har separate DB-felt for originalt templatekrav, effektivt krav og vurderingssnapshot. `criterion_basis_current` kommer fra nullsikker sammenligning av vurdert og gjeldende kriterierevisjon. Før ny vurdering viser DB «Venter på ny vurdering», og prosessberedskap er `not_evaluated`. Historiske bevis endres ikke. `v_criterion_correction_receipts` finner en vurdering som bruker den nøyaktige revisjonen også etter automatisk B-overgang. Frontend bruker DB-kvitteringens melding.
