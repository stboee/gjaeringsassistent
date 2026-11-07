---
doc_id: DOC-16
role: profile-model
status: normative
source_format: markdown
---

# 16 – W-34/70 faggrunnlag og prosessmodell

**Rolle:** Profilspesifikk forklaring av intensjon og faglig klassifikasjon for den publiserte W-34/70-templaten. Eksakte aktive kriterier, parametere, replay-flagg, analysemetadata og målekildevalidering skal ikke vedlikeholdes manuelt her; de genereres fra SQL til `generated/w3470-rule-reference.json`.

## 1. Avgrensning

Modellen gjelder ren tankgjæring med `Saccharomyces`/W-34/70-lignende lagerforløp. Brettanomyces, surøl, blandingskultur og flaskekarbonering ligger utenfor denne profilen.

Templateverdier er ikke automatisk universelle bryggefaglige sannheter. Hver regel skal kunne klassifiseres som:

- **kildebelagt** – direkte støttet av dokumentert ekstern kilde;
- **empirisk kalibrert** – valgt på grunnlag av egne batchdata/operativ erfaring;
- **prototypegrense** – teknisk/faglig startverdi som fortsatt krever målmiljøkalibrering.

Status for faglig kalibrering føres i dokument 15.

## 2. Biologisk referanseforløp

B1–B6 beskriver et ordnet biologisk referanseforløp:

| Fase | Hensikt |
|---|---|
| B1 – Inokulert og tilpasning | Etter pitch; målbar aktivitet er ennå ikke sikkert etablert. |
| B2 – Aktivitetsstart og tidlig vekst | Målbar gjæringsaktivitet er etablert. |
| B3 – Aktiv hovedgjæring | Høy, tydelig hovedaktivitet. |
| B4 – Sen gjæring | Utgjæringen er langt kommet og rate avtar fra batchens topp. |
| B5 – Modning og metabolsk opprydding | Nær slutt; gjæren er fortsatt metabolsk aktiv. |
| B6 – Stabil utgjæring | Forventet utgjæring er nådd og SG er stabil innen definert vindu. |

Fasene har ikke skjult kalenderlogikk. Den publiserte templaten eier kriteriene.

## 3. Prosesstrinn

Gjeldende template bruker P1–P10 og reserverer P11–P15:

| P | Prosesstrinn | Hovedhensikt | Historisk autoetablering |
|---|---|---|---|
| P1 | Klargjøring, pitch og temperaturstabilisering | Registrere pitch og kjøle kontrollert mot første mål. | Tillatt |
| P2 | Kald hovedgjæring | La aktivitet etableres og hovedgjæring gå kaldt. | Tillatt |
| P3 | Første temperaturøkning mot 10 °C | Temperaturøkning først når hovedgjæringen er solid etablert. | Ikke tillatt |
| P4 | Videre temperaturøkning mot 12 °C | Videre ramp styres av biologisk fremdrift. | Ikke tillatt |
| P5 | Varm sluttfase mot 14 °C | Holde gjæren aktiv mot slutten av hovedutgjæringen. | Ikke tillatt |
| P6 | Modning og metabolsk opprydding | Holde varm sluttfase til SG/sensorikk tilsier videre steg. | Ikke tillatt |
| P7 | Tørrhumling | Sen varm tørrhumling etter tilstrekkelig utgjæring/opprydding. | Ikke tillatt |
| P8 | Kaldkrasj mot 4 °C | Ny stabilitets-/sensorikkvurdering før nedkjøling. | Ikke tillatt |
| P9 | Bunnfallsdump | Fjerne utfelt bunnfall etter kaldkrasj. | Ikke tillatt |
| P10 | Kaldkondisjonering ved 2–3 °C | Kondisjonere kaldt og følge klarhet/utfelling. | Ikke tillatt |
| P11–P15 | Reservert | Ledige generiske templateplasser. | Ikke tillatt |

P3 og senere kan være **kriteriemessig klare** uten å være implementert/aktivert. Operatørens `Neste` er nødvendig.

## 4. Tilt som trendgrunnlag

Manuell OG/SG er absolutt observasjonsgrunnlag der den brukes. P24r7 viser rå Tilt-AA fra faktisk OG og godkjent Tilt-median, og separat manuell AA fra faktisk OG og korrigert manuell SG. Det er ingen kalibrering, offsetestimat eller automatisk kildebytte. Tiltens absolutte måleavvik kan derfor gi ulikt tall fra manuell kontroll; målegrunnlaget vises uttrykkelig.

`relative_sg_drop_points` beholder den etablerte tekniske identiteten, men bruker nå faktisk OG minus rå Tilt-median i SG-poeng. Videre biologisk fremdrift bruker tilsynelatende utgjæringsgrad fra templatekriteriets valgte kilde. SG-rate er faktisk SG-forskjell mellom vinduets endepunkter / faktisk tid: positiv betyr fallende SG, null ingen endepunktendring og negativ stigende SG. Rategrafen starter ved 0; en negativ faktisk rate bevares og vises i siste-verdi-feltet.

## 5. Analyse

W-34/70-templaten deklarerer tre operatørgrafer:

1. **Tilsynelatende utgjæringsgrad** – hvor stor del av den opprinnelige gravityen som er gjæret ut. Forventet templateområde er 80–84 %, og forventet FG beregnes fra faktisk OG og dette intervallet.
2. **SG-rate** – signert trend i SG-poeng per døgn. Den viser både aktivitetsnivå og retning uten egen graf for absoluttverdi eller rate relativt til historisk maksimum.
3. **SG-stabilitet** – spenn mellom høyeste og laveste godkjente SG i deklarert stabilitetsvindu; lav verdi betyr stabil SG.

Vertikal minimum, maksimum, tick-intervall, null-policy, warm-up, coverage, outputdomene, serieopphav, B/P-markører og kriterieterskler er template/sessionmetadata. Horisontal akse bruker DB-eide `+dag · dato`-markører. Frontend tegner verdiene og aksene den får fra read-model og skal ikke utlede egne domenebetingede grenser.

## 6. Målevalidering

Tilt-kilden bruker deklarative validatorer for SG, temperatur og RSSI. Gjeldende parametere er **prototype-/tekniske grenser** inntil de er kalibrert mot reell datadistribusjon. De skal ikke presenteres som bryggefaglige universallover.

Valideringsprinsippet er likevel normativt:

- hard plausibilitetsrange før domenelagring;
- robust outlierdeteksjon (MAD) når datagrunnlaget er stort nok;
- max-jump bare mot tidsmessig sammenhengende forrige godkjente bøtte;
- minimum sample count/accepted fraction;
- forkast ugyldig sample/bøtte fremfor clamp;
- kvalitetsutfall lagres separat.

Eksakte aktive tall genereres fra `../sql/23-measurement-source-seed.sql`.

## 7. Empirisk grunnlag

P2–P8 er delvis videreført/kalibrert mot en vellykket IPL-batch. Dokumentert historikk beskriver blant annet pitch rundt 12 °C med videre nedkjøling mot 8 °C og senere controller-offsetjusteringer. Tidlige controller-settpunkter som ikke ble eksplisitt registrert skal ikke rekonstrueres som fakta.

Denne empirien er kalibreringsgrunnlag, ikke i seg selv bevis for at alle terskler er optimale.

## 8. Eksternt startgrunnlag

Følgende kilder er tidligere identifisert som startgrunnlag og skal vurderes konkret før en regel klassifiseres som kildebelagt:

- Fermentis – *SafLager W-34/70* produkt-/teknisk informasjon;
- Fermentis – materiale om pitching, oksygen og temperatur;
- Fermentis – karakterisering av W-34/70;
- White Labs – *The Life of Brewers Yeast*;
- Powell mfl. 2003 – *Impact of brewing yeast cell age on fermentation performance*;
- Zamudio Lara mfl. 2022 – *Parameter Estimation of Dynamic Beer Fermentation Models*;
- Gibson mfl. 2018 – diacetylkontroll under brewery fermentation;
- Krogerus & Gibson 2013 – valin/diacetyl;
- Brewers Association – hop creep-materiale;
- Murphy & Son – Protafloc/kjelfining der dette er relevant for bryggeprosessen, ikke som direkte gjæringskriterium.

Listen er kildekandidater, ikke automatisk regelbelegg. Dokument 15 krever eksplisitt regel-for-regel-kalibrering.

### Konkrete bevarte kildehenvisninger

- Fermentis: [SafLager W-34/70](https://fermentis.com/en/product/saflager-w-34-70/)
- Fermentis: [Pitching, oksygen og temperatur](https://fermentis.com/en/news/fermentation/what-are-the-best-5-ways-to-improve-fermentation/)
- Fermentis: [Karakterisering av W-34/70](https://fermentis.com/en/news/fermentation/rediscover-saflager-w-34-70/)
- White Labs: [The Life of Brewers Yeast](https://blog.whitelabs.com/the-life-of-brewers-yeast)
- Powell mfl. 2003: [Impact of brewing yeast cell age on fermentation performance](https://academic.oup.com/femsyr/article/3/2/149/590373)
- Zamudio Lara mfl. 2022: [Parameter Estimation of Dynamic Beer Fermentation Models](https://www.mdpi.com/2304-8158/11/22/3602)
- Gibson mfl. 2018: [Diacetyl control during brewery fermentation](https://pmc.ncbi.nlm.nih.gov/articles/PMC6267509/)
- Krogerus og Gibson 2013: [Influence of valine on diacetyl](https://pmc.ncbi.nlm.nih.gov/articles/PMC3708283/)
- Murphy & Son: [Protafloc som kjelfining](https://www.murphyandson.co.uk/our-carrageenan-kettle-finings-product-range/)


Lenkene er videreført fra tidligere prosjektgrunnlag og er ikke revalidert ved GitHub-etableringen. Regel-for-regel-vurdering og kildeklassifikasjon må fortsatt utføres. Protafloc er bryggeprosessbakgrunn, ikke automatisk et gjæringskriterium.

## 9. Maskinlesbar detaljfasit

`tools/build_docs.py` genererer `generated/w3470-rule-reference.json` direkte fra:

- `../sql/03-w3470-template-seed.sql`;
- `../sql/23-measurement-source-seed.sql`.

Der finnes de eksakte publiserte B/P-kriteriene, parametrene, replay-flaggene, analysegraph/series-reglene og valideringsparametrene. Ved avvik mellom denne forklaringen og generert SQL-uttrekk er SQL/installert MariaDB detaljfasit, og dokumentforklaringen skal revideres.

## operativ prosent- og kriteriemodell

W-34/70-standard bruker 80–84 % forventet tilsynelatende utgjæring som normativt templateområde. Forventet FG beregnes fra faktisk OG for den enkelte batch. Dette erstatter den tidligere uavhengige FG-fremdriftsprosenten og hindrer at et legitimt sluttpunkt innenfor gjærens forventede utgjæringsområde blokkeres av en separat prosentmodell.

Biologisk standardmodell i gjeldende modell:

- B2: SG-fall siden etablert startnivå ≥ 1,5 SG-poeng.
- B3: SG-rate ≥ 1,5 SG-poeng/døgn.
- B4: utgjæringsgrad ≥ 60 % og SG-rate ≤ 1,5 SG-poeng/døgn.
- B5: utgjæringsgrad ≥ 75 %.
- B6: utgjæringsgrad ≥ 80 % og SG-spenn ≤ 1,0 SG-poeng i 24-timersvinduet med minimumskrav til prøver og dekning.

Prosessmodellen bruker biologisk fase som ferdig vurdering og kombinerer den med operative temperaturkrav. P3 og senere krever fortsatt operatørbekreftelse; historisk import kan ikke automatisk passere P3. P8 vurderer SG-stabilitet på nytt etter tørrhumling for å fange mulig hop creep.
