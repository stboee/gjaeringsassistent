---
doc_id: DOC-10
role: rule-model
status: normative
source_format: markdown
---

# 10 – Regel- og evalueringsmodell

**Rolle:** Normativ, generisk regel-/kriterie-/datakvalitetsmodell. Profilspesifikke W-34/70-valg beskrives i dokument 16 og eksakte aktive verdier genereres fra SQL.

## 1. Fire lag

Regelmodellen har fire eksplisitte lag:

1. **Registry** – tillatt vokabular: metrics, generiske calculation models, inputs, typed parametere, kriteriemodeller/-roller, valideringsmodeller og operatoroperasjoner.
2. **Template** – velger konkrete modeller, inputs, parametere, kriterier, targets, actions, replay-policy, analysemetadata og eventuelle kildevalg.
3. **Frozen session** – Start kopierer hele publiserte regelgrunnlaget til normaliserte `session_*`-tabeller.
4. **Generisk motor** – Node-RED utfører registrert modelltype mot frozen data og persisterer resultat/provenance.

Motoren skal ikke velge fagregel fordi en metric heter X, fasen heter B3 eller prosesstrinnet heter P4. Manglende/inkonsistent frozen grunnlag gir `invalid_configuration` eller annet eksplisitt manglende datagrunnlag; ingen skjulte defaults.

## 2. Felles kriteriespråk

B- og P-kriterier bruker samme ytre modell: identitet, metric, criterion model, role, label og typed parameters. Aktive generiske kriteriemodeller omfatter:

- `threshold`;
- `observation`;
- `window_median_range`;
- `stability_window`.

Roller:

- `required` – inngår i rå fase/readiness-port;
- `supporting` – vises/støtter, men blokkerer ikke alene;
- `information` – kontekst uten porteffekt.

Nye kriteriemodeller implementeres ett sted og kan brukes av både B og P.

## 3. Eksplisitt kriteriestatus

Persistert kriterieresultat har eksplisitt `evaluation_status`:

| Status | Betydning |
|---|---|
| `met` | Gyldig grunnlag og kriteriet er oppfylt. |
| `not_met` | Gyldig grunnlag, men kriteriet er ikke oppfylt. |
| `missing_basis` | Nødvendig måling/observasjon mangler. |
| `missing_coverage` | For få datapunkter eller for kort faktisk dekning. |
| `stale` | Grunnlaget er eldre enn tillatt. |
| `invalid_configuration` | Modell/parameter/input er ugyldig eller ufullstendig. |
| `not_evaluated` | Kriteriet er ennå ikke vurdert. |

`valid=0` er ikke synonym for konfigurasjonsfeil. Frontend skal bruke persistert status/read-modeltekst.

## 4. Freshness, vindu, persistens og warm-up

Begrepene skal holdes adskilt:

- `maximum_age_minutes` = freshness for datagrunnlag;
- `window_*`, `minimum_samples`, `minimum_span_hours` = hvilket tidsgrunnlag kriteriet analyserer;
- persistens = hvor lenge kriteriet må være sammenhengende oppfylt før overgang;
- analyse-`warmup_minutes`/coverage = når en avledet tidsserie i det hele tatt kan produsere autoritativt punkt;
- tid i B/P = historisk state, ikke automatisk freshnessregel.

Registrert `measurement_data_gaps` bryter kontinuitet der modellen krever sammenhengende datagrunnlag.

## 5. Metricberegning og gyldighetsdomene

Hver avledet metric peker på generisk beregningsmodell med deklarerte inputs og typed parametere. Metric-registry har i tillegg et gyldighetsdomene som fryses til template/session.

Hvis beregningsoutput ligger utenfor frozen domene, er metricen ugyldig grunnlag. Den kan ikke tilfredsstille B/P-kriterium og skal ikke persisteres som gyldig Analyse-punkt. Verdien skal ikke clampes.

## 6. Målevalidering

Målekildevalidering følger samme deklarative mønster:

```text
source profile validation registry
→ freeze til session
→ generiske validatorer
→ godkjente samples
→ robust 5-min aggregat
```

Aktive generiske modelltyper kan omfatte hard range, robust MAD, max-jump og minimum acceptance. Signalspesifikke grenseverdier ligger i metadata, ikke i motoren.

Forkastede samples skal ikke bli autoritative data. Kvalitetsutfall persisteres separat slik at datarensing er sporbar uten å lagre en korrigert/opdiktet måleverdi som sannhet.

## 7. Analysemetadata

Om en verdi skal ha graf er template-/sessionmetadata. Graph/series-metadata kan blant annet angi:

- label og forklaring;
- enhet og desimaler;
- source kind / metric / criterion series;
- minimum samples, coverage og warm-up;
- gyldig serie-outputdomene;
- gap-policy;
- B-bånd, P-markører og kriteriemarkører;
- DB-eid dynamisk `y_axis_min`, `y_axis_max` og `y_axis_tick_step` fra aktuell serie/range og relevante krav;
- `range_min`/`range_max` slik at faktisk spredning kan tegnes som envelope der datagrunnlaget støtter det.

Motoren produserer generiske analyseserier etter frozen metadata. Runtimeaksen er read-model-avledet fra den faktiske sessionen; templaten skal ikke tvinge et unødvendig stort fast Y-spenn. Frontend itererer read-modelen og kjenner ikke graf-ID-ene som domenegren eller beregner eget akseområde.

## 8. Biologisk progresjon

B1–B6 er generiske ordnede faseplasser. Biologisk overgang er sekvensiell: bare neste aktiverte B-fase vurderes som overgangskandidat. Historisk replay går kronologisk; en senere fase kan ikke hoppes til bare fordi kriteriene ved siste tidspunkt også ville vært oppfylt.

## 9. Prosesstrinn og replay-policy

P1–P15 er generiske ordnede plasser. Ordinære/live overganger er operatørbekreftet. Historisk replay kan vurdere neste P-kandidat, men kan bare persistere automatisk overgang dersom frozen stegmetadata eksplisitt tillater `historical_replay_auto_transition_allowed`.

Kriterium **oppfylt** og prosesstrinn **aktivert** er separate fakta og skal presenteres separat.

## 10. Kriteriekorreksjon og fravik

Registry eier hva motoren teknisk støtter; templaten eier tillatelsen per kriterium.

- session-kriteriekorreksjon kan bare endre parametere som frozen template har merket korrigerbare;
- biologiske og prosesskriteriefravik kan bare brukes når frozen `exception_allowed` er sann;
- korreksjon/fravik omskriver ikke original template eller rå evaluering;
- prosessfravik kan påvirke effektiv readiness uten å endre kriteriets `met`-faktum;
- operatørnotat ved kriteriekorreksjon og prosessfravik er valgfritt; tomt notat er ikke en valideringsfeil;
- biologisk fase utledes av kriterier; korreksjon/fravik er separate historikkbevarende fakta og endrer ikke opprinnelig rå vurdering eller frozen template.

## 11. Evalueringshorizon og provenance

Historisk evaluator bruker persistert importcutoff som øvre horizon; live bruker MariaDB-klokken. Freshness, vinduer og observasjonsalder beregnes mot eksplisitt evalueringshorizon, aldri lokal `Date.now()`-fallback.

Evaluator persisterer provenance som relevant vindu, sample count, faktisk dekning, siste sample og effektive parametere. MariaDB-read-model lager ferdig `data_window_display`, `actual_display`, `requirement_display` og `status_display`.

## 12. Overgangsbevis

En transition peker på eksakt `evaluation_id`. Historisk presentasjon følger derfor:

`transition → evaluation → criteria`

Current candidate-evaluering er et separat faktum. «Siste evaluated_at» skal ikke brukes som erstatning for overgangens faktiske bevis.

## 13. Recommendation-livsløp

Recommendation-status er `pending`, `executed`, `rejected` eller `superseded`. Original anbefaling, datagrunnlag og begrunnelse beholdes; operatørens faktiske handling er et separat faktum.

## 14. Publiseringsvalidering

Templatepublisering skal avvise registry-inkompatible metric/model/input/parameter/freshness-/criterion-kombinasjoner og ugyldig operatorpolicy. Publisering skal også validere analyse- og replaymetadata. Motoren skal ikke være reparasjonslag for en ugyldig publisert template.

## forenklet biologisk kriteriemodell

Gjæringsprosenten i runtime er **tilsynelatende utgjæringsgrad (apparent attenuation)**. Egen «FG-fremdrift», rate relativt til historisk maksimum og absolutt SG-rate er ikke operative domenemetrikker i gjeldende modell.

W-34/70-standardtemplaten uttrykker biologien med et lite, forklarbart kjernesett: SG-fall siden start, signert SG-rate, tilsynelatende utgjæringsgrad og SG-stabilitet. B2 registrerer etablert SG-fall, B3 aktiv hovedgjæring, B4 langt kommet utgjæring med avtagende rate, B5 nær forventet utgjæring og B6 forventet utgjæring kombinert med stabil SG.

Målefreshness og generell målekvalitet er **evalueringsforutsetninger**, ikke biologiske egenskaper. Prosesskriterier skal normalt konsumere ferdig biologisk fase og bare legge til operative forhold som temperatur, manuell bekreftelse eller stabilitet etter en konkret prosesshendelse. Dermed skal P-trinn ikke duplisere SG-logikken som allerede ligger i B-modellen.


## Operatørpolicy og målegrunnlag

Registry definerer modellens tillatte parameter-ID-er. Ved opprettelse/modellbytte får kriteriet disse korrigeringsrettighetene og `exception_allowed=true` fra DB-registry; parametere som er uforenlige med metricens freshness-semantikk utelates. Templateeditor kan slå rettighetene av. Publisert template og Start fryser det konkrete valget til sessionen.

Biologisk fravik knyttes til en eksplisitt kandidatvurdering/kriterium og bekreftes før innsending. Registrering og tilbaketrekking er append-only. Ved ny evaluering beholdes faktisk verdi, `met`, `valid` og datagrunnlag, mens `applied_exception_id` peker på eventuell håndtering. Et fravik kan ikke omgå `invalid_configuration` eller hoppe over en fase. Overgangstid kan ikke settes tidligere enn fravikets registrering. Det ruller ikke tilbake allerede registrerte overganger.



## Målebasert analyse i p24r7

Alle operative analyser bygger på godkjente faktiske målinger. Det er ingen regresjonsestimater, foreløpige verdier, følsomhetsbånd eller oppskalering av et kort stabilitetsvindu. Manglende data forblir manglende. Råvalidering med median/MAD og deklarert støygulv beholdes; den prøver ikke å rekonstruere råprøver fra gamle min/maks-aggregater.

`endpoint_rate_v1` beregner **1000 × (første SG − siste SG) / faktisk tidsavstand i døgn** innen et sammenhengende 24-timersvindu. Publisering krever 12 godkjente punkter og minst 18 timers faktisk tidsspenn. Eksakt første/siste måletid brukes; ingen interpolasjon til vindusgrensene. Økende SG gir negativ rate, flat SG gir ekte null. Grafens frozen nedre grense er 0; negative verdier beholdes numerisk i siste-verdi-feltet. Høy faktisk positiv rate beholdes og øker aksen.

Rå Tilt-utgjæringsgrad er **100 × (faktisk OG − godkjent Tilt-SG) / (faktisk OG − 1)**. Ingen pitchoffset beregnes, og manglende tidlig Tilt-historikk blokkerer ikke råserien. Manuell utgjæringsgrad bruker samme formel med instrument-/temperaturkorrigert manuell SG og vises som punkter ved de faktiske registreringstidene. Manuell kontroll er ingen automatisk fallback for Tilt. Templatekriterier velger basis med `metric_id`: `apparent_attenuation_percent` = rå Tilt, `manual_apparent_attenuation_percent` = manuell kontroll. Rå Tilt kan avvike fra manuell kontroll; dette skal synes.

SG-fall til B2 er nå faktisk OG minus rå Tilt i SG-poeng, uten pitchkalibrering. B3/B4 beholder prototypegrensene 1,5 SG-poeng/døgn, nå anvendt på målt endepunktrate; grensene er prosessvalg og må vurderes mot neste brygg. De er ikke dokumenterte produsentgrenser.

`metric-rolling-sg-range-v1` viser **1000 × (maks SG − min SG)** fra sammenhengende godkjente målinger i 24-/48-timersvindu. Frozen minste tidsdekning er 18/36 timer (75 %) og minst 12 punkter. Vinduets faktiske omfang vises; verdien ekstrapoleres ikke til full tid. Datagap nullstiller vindusgrunnlaget. B/P-stabilitetskriterier bruker samme maks–min-metode med egne eksplisitte templatevinduer/ankere.

Siste-verdi-tekst og måletid produseres av `v_session_analysis_latest`; frontend og begge rapportprodusenter viser disse feltene direkte. Låst `render_mode=points` betyr manuelle punkter; `line` betyr målte Tilt-/vindusserier med avbrudd ved datagap.

Legacy-registrydata for pitch-baseline/regresjon beholdes som kompatibilitetsdata. De operative p24r7-metrikkene og de nye templatene bruker dem ikke som utgjæringskalibrering eller rateestimat.

## Historiske timesverdier

Detaljerte femminuttsdata foretrekkes. HA-timesverdier vises for hele timer uten detaljerte punkter og tidligst fra gjæringsstart. Timesdata opprettes aldri som tolv kunstige femminuttspunkter, og en manglende time bryter kurven. SG-verdien er HA sitt gjennomsnitt; min/maks er de faktiske lagrede grensene.

Historiske analysekurver beregnes i MariaDB fra timesgjennomsnitt: AA fra sessionens faktiske OG, SG-rate fra første/siste timeverdi i datavinduet og stabilitet fra maks–min av timeverdiene. Rate/stabilitet krever minst to reelle timeverdier, sammenhengende timer og frozen krav til tid/dekning/oppvarmingsperiode og outputdomene. Antall råprøver kan ikke rekonstrueres og brukes ikke som et oppdiktet antall. Kilden merkes uttrykkelig; timesanalyse er grafgrunnlag og brukes ikke til å erklære B/P-kriterier oppfylt.

Sammenligningsserien beholder sin egen OG, sine frozen regler og sitt målegrunnlag. Den påvirker ingen anbefaling eller overgang. Visningen av detaljerte analyser beholder første, siste, minste og største reelle punkt i valgt visningsintervall. Ingen nye analyseverdier beregnes i nettleseren.
