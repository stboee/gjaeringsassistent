---
doc_id: DOC-17
role: domain_reference
status: normative
source_format: markdown
---

# 17 – Aletemplater og faggrunnlag

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

Det finnes egne publiserte profiler `s04-cool@1.0` og `m42-cool@1.0`. Temperatur, gjærmengde, forventet utgjæring og sluttkriterier er template-/sessiondata; motoren har ingen gjærsort-spesialkode.

| Profil | Produsentområde | Hovedgjæring | Ramp P3/P4/P5 | Forventet utgjæring | Startgrunnlag ved 150 L, OG 1,050 |
|---|---|---|---|---|---|
| SafAle S-04 | 18–26 °C | 18 °C | 19 → 20 → 20 °C | 74–82 % | 120 g fersk tørrgjær |
| M42 New World Strong Ale | 16–22 °C | 17 °C | 18 → 19 → 20 °C | 77–82 % | 70 g fersk tørrgjær |

**Produsentfakta:** Fermentis oppgir ideelt 18–26 °C og 50–80 g/hL. Ved 150 L = 1,5 hL blir dette 75–120 g. Fermentis' egen Tips and Tricks-brosjyre oppgir S-04-utgjæring 74–82 %. M42-produktsiden oppgir 16–22 °C, 77–82 % og én 10 g-pose per opptil 23 L; 150/23 = 6,52 poser, avrundet til 7 poser = 70 g. Produsentens håndbok angir minst to 10 g-poser/23 L ved ale-OG over 1,050: 150/23 × 2 = 13,04 poser, avrundet til 14 poser = 140 g. For 250 g-pakninger følges etikettens dose, slik håndboken uttrykkelig presiserer. Mengden må justeres manuelt mot faktisk volum/OG/pakning; dette er ikke en automatisk doseberegner.

**Prosjektets prosessvalg:** Hold hovedgjæringen stabil på den kjølige siden og øk gradvis til 20 °C når B-fase og temperaturgrunnlag tillater det. Rampene, B-grensene, 75 % vindusdekning og 21-dagers planramme er prosjektvalg, ikke produsentgarantier. Forventet utgjæringsområde påvirkes også av vørterens gjærbarhet. Det er ikke en garanti om oppnådd FG eller et ferdigsignal.

P1/P2 kan replayes ved historisk import; P3 og videre krever manuell bekreftelse. Trykkmål er 0 bar gjennom aktiv hoved-/sluttgjæring. Positivt trykk ved kaldkrasj er et eksplisitt operatørmål; programmet regulerer ingen ventil. Tørrhumling (P7) er deaktivert som standard og aktiveres i en draft når oppskriften krever det.

Før kaldkrasj kreves B6, SG-stabilitet i et 48-timersvindu med minst 36 timers sammenhengende data, fersk manuell utgjæringskontroll samt diacetyl og acetaldehyd på nivå 0. Høy flokkulering, synlig klaring eller 21 forløpte dager erstatter ingen av disse kontrollene. Ved avvik brukes den ordinære eksplisitte kriteriefraviksbanen, med bevart evidens. Ved tørrhumling tas ny stabilitets-/smakskontroll for mulig hop creep. M42-håndboken anbefaler fersk tørrgjær fremfor høsting/repitch.

Kilder lest 08.10.2026:

- [Fermentis S-04 produsentside](https://fermentis.com/en/product/safale-s%E2%80%9104/).
- [Fermentis Tips and Tricks, produsentens brosjyre hos Castle Malting, trykt s. 32/38](https://www.castlemalting.com/Presentations/Brochure_Fermentis_Tips_and_Tricks_EN.pdf).
- [Mangrove Jack’s M42 produsentside](https://mangrovejacks.com/products/new-world-strong-ale-m42-yeast-10g).
- [Mangrove Jack’s offisielle håndbok, s. 4–5 og M42-profil](https://help.mangrovejacks.com/hc/en-us/article_attachments/13551379984785).
