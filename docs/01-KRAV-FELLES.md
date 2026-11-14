---
doc_id: DOC-01
role: requirements
status: normative
source_format: markdown
---

# 01 – Krav: felles system

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

**Rolle:** Normative produkt- og domenekrav. Implementasjonsstatus ligger i dokument 18; målmiljøverifikasjon og åpne forhold ligger i dokument 15.

## Grunnprinsipper

- Gjæringsassistenten gir råd, vurderinger og status, men styrer ikke utstyr automatisk.
- MariaDB er eneste autoritative persistente sannhetskilde. Node-RED er gjæringsmotor/orchestrator; Home Assistant/dashboard er operatør- og presentasjonslag.
- Bare én unreleased session kan være operativ om gangen.
- Template, biologimodell, prosesstrinn, kriterier, mål, actions, målevalidering og analysemetadata fryses ved Start.
- Biologisk fase og prosesstrinn er separate modeller. Biologisk progresjon kan være automatisk; ordinære P-overganger er operatørbekreftet.
- Historisk replay kan bare autoetablere P-trinn som eksplisitt er tillatt av den frosne templatepolicyen.
- Manuelle målinger lagres som komplette atomiske målesett. Kontinuerlige sensormålinger lagres som validerte, normaliserte tidsserier.
- Historisk betydningsfulle korrigeringer skal bevare tidligere verdi/revisjon.
- Restart skal rekonstruere nødvendig nåtilstand fra committede MariaDB-data.
- Sensoriske 0–5-skalaer bruker samme retning: **0 = ønsket/ingen avvik, 5 = størst avvik**.
- SG-only gjelder tetthet i GUI, template, runtime, rapport, dokumentasjon og tester.

## Gjeldende krav

| ID | Status | Krav |
|---|---|---|
| REQ-COM-001 | Fastsatt | Løsningen skal gi råd og status, men aldri styre utstyr automatisk. |
| REQ-COM-002 | Fastsatt | MariaDB er eneste autoritative persistente sannhetskilde. Node-RED er gjæringsmotor/orchestrator og utfører all domeneskriving gjennom den sentraliserte MariaDB-grensen. `flow.*`, skrivbar `global.*`, HA-state og frontendprojeksjoner skal ikke være autoritativ applikasjonsstate. |
| REQ-COM-003 | Fastsatt | Første produksjonsversjon skal bruke dokumenterte grenser og tydelig merkede faglige tommelfingerregler. |
| REQ-COM-004 | Fastsatt | Historiske batcher skal ikke påvirke anbefalingsmotoren i v1. |
| REQ-COM-005 | Fastsatt | Hver anbefaling skal vise regeltype, kilde, begrunnelse og usikkerhet. |
| REQ-COM-006 | Fastsatt | En anbefaling har status `pending`, `executed`, `rejected` eller `superseded`. |
| REQ-COM-007 | Fastsatt | En ny anbefaling skal kunne erstatte en utdatert anbefaling uten å slette historikken. |
| REQ-COM-008 | Fastsatt | Bare én aktiv sesjon tillates. `draft` er ikke en egen persistent livsløpstilstand. |
| REQ-COM-009 | Fastsatt | Session opprettes som del av den samlede Start-operasjonen; det finnes ikke en separat før-pitch-opprettelsesflyt. |
| REQ-COM-010 | Fastsatt | Pitchtid registreres ved Start og holdes separat fra tidspunktet startdata og målesett registreres. |
| REQ-COM-011 | Fastsatt | `activity_started_at` registreres automatisk og kan korrigeres manuelt uten å slette originalen. |
| REQ-COM-012 | Fastsatt | Sesjonen avsluttes bare manuelt. Eget obligatorisk sluttnotat kreves ikke; notater registreres separat mens sesjonen er aktiv. |
| REQ-COM-013 | Fastsatt | Templateidentitet, biologimodell, prosessplan, kriterier, mål og actions fryses ved Start som en komplett normalisert session-kopi med snapshot-metadata/SHA-256. Ingen JSON-blob er autoritativt regelgrunnlag. |
| REQ-COM-014 | Fastsatt | Frosset plan redigeres ikke under aktiv gjæring; faktiske tiltak, avvik og timing registreres mot den uendrede planen. |
| REQ-COM-015 | Fastsatt | Prosessmodellen har 15 generiske plasser. Gjeldende W-34/70/IPL-grunnlag bruker P1–P10 aktivt og P11–P15 som reserve. |
| REQ-COM-016 | Fastsatt | Ordinære/live prosesstrinnoverganger krever manuell operatørbekreftelse. Historisk replay kan bare autoetablere et prosesstrinn når dette eksplisitt er tillatt i den frosne step-policyen; W-34/70 tillater dette bare for P1/P2. |
| REQ-COM-017 | Fastsatt | Aktivt og anbefalt prosesstrinn skal vises separat fra biologisk fase. |
| REQ-COM-018 | Fastsatt | Normal framdrift skjer ett trinn om gangen med `Neste`; `Hopp over` er ikke del av gjeldende operatørkontrakt. |
| REQ-COM-019 | Fastsatt | Prosess-tilbakeføring går ett trinn tilbake og krever advarsel/bekreftelse, men ingen obligatorisk begrunnelse. Hendelsen og resultatet skal logges; eventuell kommentar registreres i generelt notatfelt. |
| REQ-COM-020 | Fastsatt | Templatebestemte prosesskrav skal advare, men aldri blokkere en manuelt bekreftet overgang. |
| REQ-COM-021 | Fastsatt | Automatisk målbare sjekkpunkter og manuelle sensoriske/praktiske punkter skal kunne blandes. |
| REQ-COM-022 | Fastsatt | Manuell SG før kaldkrasj er standardpunkt; manglende verdi gir bare advarsel. |
| REQ-COM-023 | Fastsatt | Manuell SG kan komme fra hydrometer eller alkohol-korrigert refraktometer. |
| REQ-COM-024 | Fastsatt | Avvik fra Tilt vises og logges, men Tilt-serien kalibreres ikke automatisk. |
| REQ-COM-025 | Fastsatt | Maksimal lengde for hvert notatfelt er 255 tegn. |
| REQ-COM-026 | Fastsatt | Startgrunnlaget valideres samlet og fryses atomisk ved Start. Korrigering etter Start skal bare skje gjennom eksplisitt støttet revisjons-/korrigeringsmekanisme. |
| REQ-COM-027 | Utsatt | Endelig W-34/70-regelsett og terskelverdier fastsettes etter kilde- og prototyperevisjon. |
| REQ-COM-028 | Fastsatt | Seks biologiske faser brukes som fast referanseforløp for ren tankgjæring med `Saccharomyces`. |
| REQ-COM-029 | Fastsatt | Biologisk fase oppdateres automatisk etter vedvarende kriterier. Registrerte tidsstempler kan korrigeres manuelt uten begrunnelseskrav; originalt, manuelt og effektivt tidspunkt bevares sporbar og overstyringen kan fjernes. |
| REQ-COM-030 | Fastsatt | Brettanomyces, surøl, blandingskultur og flaskekarbonering er utenfor omfanget. |
| REQ-COM-031 | Fastsatt | Bare ett prosesstrinn kan være aktivt; parallelle mål og aktiviteter ligger i dette trinnet. |
| REQ-COM-032 | Fastsatt | Forventet FG-grunnlag hentes fra valgt template og fastsettes før Start; det er del av den frosne session-planen. |
| REQ-COM-033 | Prototype | Biologisk tid måles fra autoritativ pitch til første bekreftede inngang i B6, mens tid i B6 vises separat. |
| REQ-COM-034 | Prototype | B6 heter `Stabil utgjæring`; betegnelsen påstår ikke sensorisk ferdig øl eller utført klarning. |
| REQ-COM-036 | Fastsatt | Bare aktiv sesjon kan registrere prosessdata. `idle`, `configured`, `active`, `completed` er gjeldende tekniske livsløpsnavn. |
| REQ-COM-037 | Fastsatt | Grunnmodellen lagrer manuell SG/temperatur, trykk, kjøleverdier, gjærlås, notat og templatevalgte sensoriske 0–5-felt uavhengig av B/P. |
| REQ-COM-038 | Fastsatt | Diacetyl er én ordinær sensorisk 0–5-verdi; prosesstemplaten avgjør eventuell terskel. |
| REQ-COM-039 | Fastsatt | Avslutning skal kunne eksportere den aktuelle sessionens frosne templategrunnlag, normaliserte domenedata, relevante logger og manifest. Normalisert sessionhistorikk beholdes i MariaDB; eksport er arkiv/transport og gate før operativ release av reell session. |
| REQ-COM-040 | Fastsatt | Template kan bare byttes før sesjonsstart og fryses som en fullstendig kopi i sesjonen. |
| REQ-COM-041 | Fastsatt | Session-ID skal være stabil og filsystemsikker og bygge på tidsstempel og sikkert templategrunnlag uten kollisjonsfare. |
| REQ-COM-042 | Fastsatt | Data fra Tilt, manuelle målinger, sensorikk og prosesshandlinger skal bare registreres i en aktiv sesjon. |
| REQ-COM-043 | Fastsatt | En uplanlagt Node-RED-/serveromstart skal gjenopprette konfigurert eller aktiv session uten ny Start, rekonstruert fra normaliserte MariaDB-data. HA-entiteter og frontendprojeksjoner er ikke restoreautoritet. |
| REQ-COM-044 | Fastsatt | Historikk skal kunne bevares som selvstendige, integritetsverifiserte session-eksporter utenfor den operative MariaDB-instansen. |
| REQ-COM-045 | Fastsatt | Rapport skal kunne genereres underveis og etter avslutning; historisk rapport skal kunne bygges fra valgt eksportfil. |
| REQ-COM-046 | Fastsatt | `Gjør klar for ny gjæring` er en egen handling etter kvittert avslutning og, for reell gjæring, komplett SQLite-par for gjæring/template og HTML-rapport for samme sesjon, filverifisert med størrelse og SHA-256. Filfeil vises og logges; manglende, pågående eller mislykket eksport blokkerer. Demo er eksplisitt unntatt eksportkravet. |
| REQ-COM-047 | Fastsatt | Ved `Gjør klar` skal avsluttet session frigjøres operativt med append-only release-faktum. Historiske sessiondata beholdes; mutable inputdraft kan nullstilles. Eksportfiler, rapporter og teknisk historikk som skal bevares slettes ikke. |
| REQ-COM-048 | Fastsatt | Manuelle grunnobservasjoner lagres atomisk via `record_observation`; Start lagrer første SG/temperatur/metode, og ordinære målesett kan inneholde den komplette templatevalgte sensoriske målkontrakten. |
| REQ-COM-049 | Fastsatt | Hvert nytt manuelt målesett bekreftes komplett. Manglende eller avvikende kriteriegrunnlag kan advare, men operatøren kan fortsatt bekrefte en prosessovergang. |
| REQ-COM-050 | Fastsatt | Readiness bestemmes av den generiske templatebestemte kriteriemodellen; ingen fast hardkodet AND-/brukerkonklusjonsmodell gjelder på tvers av alle trinn. |
| REQ-COM-051 | Fastsatt | Kontrolltypers maksimale alder og ugyldiggjørende endringer skal forvaltes per template og kontrolltype. |
| REQ-COM-052 | Fastsatt | Template bestemmer hvilke målinger/sensoriske observasjoner og grenser som er relevante. Maltsødme er ikke del av gjeldende målemodell, og konkrete terskler skal ikke hardkodes som universelle krav. |
| REQ-COM-053 | Fastsatt | Manglende eller ikke-bestått kontroll gir rød/advarende informasjon, men kan overstyres med ett trykk; alle aktive advarsler logges. |
| REQ-COM-054 | Fastsatt | Pakking/tappeklar er ikke eget prosesstrinn i gjeldende modell; avslutning er en separat manuell livsløpshandling. |
| REQ-COM-055 | Fastsatt | Standardforløpet bruker P8 som kaldkrasj, P9 som bunnfallsdump og P10 som kaldkondisjonering; konkrete inngangskriterier bestemmes av templaten. |
| REQ-COM-056 | Fastsatt | Det finnes ingen hardkodet trykk-/vakuumsikringsport; relevante trykkkrav må uttrykkes gjennom template/kriterier dersom de innføres. |
| REQ-COM-057 | Fastsatt | Kaldkondisjonering inngår i alle støttede gjæringsforløp; måltemperatur og varighet bestemmes av templaten. |
| REQ-COM-058 | Fastsatt | Temperaturøkninger kan modelleres som egne prosesstrinn, mens biologiske faser fortsatt holdes som separat modell. |
| REQ-COM-059 | Prototype | Før livebruk skal Systemkontroll, omstart, sensor-/integrasjonsavbrudd, HA-reconnect, rapport/eksport og minst én komplett testgjæring verifiseres i målmiljøet. |
| REQ-COM-060 | Fastsatt | Bunnfallsdump inngår som P9 i standardforløpet. Gjærhøsting, gjærsortering, overføring og pakking ligger utenfor prosessmodellen. |
| REQ-COM-061 | Fastsatt | Manuelt målt temperatur og kjølemaskinens settpunkt lagres som separate observasjonsverdier. |
| REQ-COM-062 | Fastsatt | Hver brukerinitierte stateful handling skal få en unik operasjons-ID og kunne spores til eksplisitt sluttresultat fra samme operasjon, med tidspunkt, handling, tilstand før/etter, godtatt/avvist, feltfeil, aktive advarsler og teknisk feil. Valideringsavvisning og persistens-/integrasjonsfeil skal skilles. |
| REQ-COM-063 | Fastsatt | Systemkontrollen skal, når HA-integrasjonen er migrert, sammenligne forventede og faktisk registrerte HA-entity-ID-er og vise mangler og mulige suffikskollisjoner. |
| REQ-COM-064 | Fastsatt | Stateful operatørhandlinger skal ha korrelasjons-/operasjons-ID der nødvendig for idempotens/sporbarhet og en enkel global 8 s dobbelttrykksguard som dekker normal GUI-/read-model-oppdateringstid. Sensoringest og tekniske systemkommandoer behandles ikke som operatørknappetrykk. |

| REQ-COM-065 | Fastsatt | Faglige regler som kan variere mellom templateversjoner skal eies deklarativt av registry/template i MariaDB. Node-RED skal ikke hardkode fase-, prosesstrinn-, gjærprofil- eller template-spesifikke terskler, vinduer, persistenskrav eller freshnessgrenser. |
| REQ-COM-066 | Fastsatt | Hver beregnet metrikk skal ha registrert generisk beregningsmodell, deklarerte input og typed parametere. Motoren implementerer beregningsmodellene generisk, mens MariaDB bestemmer hvilken modell og hvilke verdier som brukes. |
| REQ-COM-067 | Fastsatt | Freshness og persistens er separate begreper. `maximum_age_minutes` gjelder alder på datagrunnlaget; krav om vedvarende kriterium uttrykkes eksplisitt med persistens-/vindusparametere og skal ikke simuleres som maksimal alder på en fase/state. |
| REQ-COM-068 | Fastsatt | Automatisk biologisk framdrift er sekvensiell. Motoren vurderer bare neste biologiske fase som overgangskandidat; historisk backfill skal replayes kronologisk og kan ikke hoppe over en mellomliggende B-fase. |
| REQ-COM-069 | Fastsatt | En aktiv sessions regelvurdering skal kunne reproduceres fra persisterte domenedata og den frosne normaliserte session-planen. Dersom Function-nodekode må tilføre en fagregel som ikke finnes i session-planen, er regelen ikke gyldig implementert. |
| REQ-COM-070 | Fastsatt | Publisering av template skal avvise kombinasjoner av metrikk, beregningsmodell, kriteriemodell, input, typed parametere og freshness som registry ikke tillater. Motoren skal ikke reparere manglende eller ugyldig regelgrunnlag med skjulte defaults. |
| REQ-COM-071 | Fastsatt | Operativ observability skal lese det persisterte produksjonsgrunnlaget. Teknisk/Systemkontroll skal ikke opprette en alternativ live-sensorbane eller være konkurrerende produsent av målekildens runtime-status. |

| REQ-COM-072 | Fastsatt | Måledata med åpenbart ugyldig eller utilstrekkelig grunnlag skal ikke gjøres autoritative ved normalisering/clamping. Valideringsutfall skal være sporbare, mens autoritative tidsserier bare skal inneholde godkjent grunnlag. |
| REQ-COM-073 | Fastsatt | Utilstrekkelig målegrunnlag vises som manglende. P24r7 publiserer bare ordinære analyseverdier fra faktiske målinger; ingen foreløpige verdier, regresjonsestimater, utfylling eller følsomhetsbånd. |

| REQ-COM-074 | Fastsatt | Feil eller mangler skal rettes ved den autoritative kilden. Feil/mangler i MariaDB, registry, frozen session, runtimefakta eller read-model skal ikke maskeres med fallback, defaultverdi, korreksjon eller parallell domenelogikk i Node-RED, Home Assistant eller frontend. |
| REQ-COM-075 | Fastsatt | Krav, beslutninger, verifikasjonskrav, tester og deres relasjoner skal være strukturerte metadata i MariaDB. Faktiske testkjøringer og testresultater skal lagres som egne historiske fakta. |
| REQ-COM-076 | Fastsatt | Verifikasjonsresultater er append-only. En ny TECH/FUNC/UAT-kjøring skal opprette nye run/result-fakta og skal ikke overskrive tidligere verifikasjonshistorikk. |
| REQ-COM-077 | Fastsatt | Verifikasjon skal skille eksplisitt mellom tekniske tester, funksjonelle regresjonstester og UAT/målmiljøtest. Testbarhet skal bygges inn i løsningen selv om omfanget av faktisk testkjøring tilpasses endringens risiko og prototypefasen. |
| REQ-COM-078 | Fastsatt | Verifikasjonsdata skal kunne eksporteres som maskinlesbart datasett og lesbar HTML-rapport fra samme DB-eide snapshot/read-model uten at eksportlaget introduserer alternativ tolkning eller statusberegning. |
| REQ-COM-079 | Fastsatt | MariaDB, Node-RED og Home Assistant skal behandles som asynkrone moduler som kan være utilgjengelige og komme tilbake i vilkårlig rekkefølge. Når avhengigheter blir tilgjengelige skal Node-RED idempotent rekonstruere og republisere gjeldende tilstand fra MariaDB uten manuell Start, lokal persistent fallback eller duplisert domenhistorikk. |

**ID-forvaltning:** `REQ-COM-035` er reservert/utgått og skal ikke gjenbrukes til et annet krav. Nummerhullet er dermed eksplisitt og stabilt.

## Modellgrense

Første produksjonsomfang gjelder ren tankgjæring med `Saccharomyces`. Brettanomyces, surøl, blandingskultur og flaskekarbonering ligger utenfor omfanget. Endelige W-34/70-terskler er et eget faglig valideringsarbeid; prototypeverdier skal ikke presenteres som universelle faggrenser.

Pitchtemperatur er ikke et separat startfelt; første manuelt målte temperatur er temperaturgrunnlaget ved pitch. Pre-start-kladd skal ikke republiseres periodisk til redigerbare HA-felt mens operatøren skriver; restore retries ved faktisk MariaDB-utilgjengelighet i stedet for periodisk overskriving.

| REQ-COM-080 | Fastsatt | Sluttarkiv/rapport skal filverifiseres med størrelse og SHA-256 før verified registreres. Bare metadata sendes tilbake til DB; eksportstørrelsen skal ikke være avhengig av max_allowed_packet. Arkiveringsforsøk og terminalt resultat er append-only fakta. |
| REQ-COM-081 | Fastsatt | Ingen analyseverdi skal anslås mellom manglende målinger. En beregning fra faktiske målinger er tillatt og skal vise kilde og faktisk måletid; manuell og rå Tilt-basis skal være atskilt. |

## Arkivutveksling

| ID | Status | Krav |
| --- | --- | --- |
| REQ-COM-082 | implemented | SQLite er filutveksling; importert historikk normaliseres i MariaDB. Motoren bruker ikke et eksternt SQLite-arkiv direkte. |
| REQ-COM-083 | implemented | Gjærings- og template-arkiv har samme session-/eksportprefix og valideres som et sett. Begge er SQLite; HTML-rapport beholdes. |
