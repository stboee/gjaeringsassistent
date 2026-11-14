# Gjæringsassistent – arbeidsregler

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

Ved ny chat: følg [onboarding-instruksjonen](docs/ONBOARDING-NY-CHAT.md) og gi en kildebasert statuskvittering før nytt arbeid avgrenses.

Les `docs/00-DOKUMENTKART-OG-STATUS.md`, aktive beslutninger i dokument 14 og relevante krav/kontrakter før endringer. Undersøk også de strukturerte SQL-/registry-kildene; genererte kataloger erstatter dem ikke.

## Arbeidsmåte

- Diskuter og avgrens først. Brukeren sier «start» før implementering. Gjennomfør deretter avtalt arbeid uten gjentatte avklaringer om ordinære tekniske valg.
- Arbeidet føres direkte på `main`. Issues, PR-er og den tidligere Chat→Work/handoff-prosessen inngår ikke i prosjektets arbeidsflyt.
- Bruk datobasert versjon `ÅÅÅÅ.MM.DD-N`, der N starter på 1 hver publiseringsdag. Git-tag er `v` etterfulgt av versjonen. Release-tittelen har i tillegg en kort beskrivelse.
- Oppdater autoritative kilder, metadata, relevante tester og dokumentasjon samlet. Generer avledede filer med prosjektets byggverktøy.
- Kjør tester som er relevante for endringen. Skill mellom kildeinspeksjon, lokale tester, faktisk MariaDB-/plugin-integrasjon og målmiljø/UAT. Ikke gi eldre bevis ny testdato eller versjon uten ny kjøring.
- Ta ikke med passord, HA-token, credentials, driftsdatabaser eller lokale rapporter i Git. Bevar eksisterende brukerarbeid.
- Produksjonsinstallasjon, restart og datamigrering krever at brukerens bestilling omfatter dette. Installeren bevarer databasen og bruker kun verifiserte versjonsstyrte oppgraderingsbaner; se installer/migrations.json. Ukjent struktur/versjon avvises før mutasjon.

## Arkitektursperrer

- MariaDB/InnoDB er eneste autoritative persistente kilde for domenefakta. Node-RED er generisk motor/orchestrator; HA/frontend formidler handlinger og viser ferdige DB/read-model-felt.
- Manglende eller feil informasjon rettes i datamodellen, registry, frozen session eller read-model. Ingen lokale defaults, oppdiktede verdier, frontend-workarounds eller parallell domenelogikk.
- Reelt fravær skal modelleres og forklares. Påkrevde kontraktfelt kan ikke utelates eller erstattes med 0.
- Normaliserte relasjoner, constraints og korte transaksjoner håndhever integritet. InnoDB håndterer normal samtidighet. Ingen generell writer-kø, normal applikasjonslocking eller retry som skjuler modellfeil.
- Append-only gjelder fakta/revisjoner innenfor hver beholdt sesjon. Hele historiske sesjoner og ubrukte importerte templates kan slettes eksplisitt og atomisk. Drafts er egne mutable arbeidsflater.
- Registry → template → normalisert frozen session → generisk motor. Ingen nødvendige domenedata i flow/global, HA, nettleseren eller lokale runtimefiler.
- SG-only, separate biologiske faser og prosesstrinn, én operativ sesjon og ingen automatisk fysisk utstyrsstyring.
- Én felles graftegner og felles autoritativt seriegrunnlag for dashboard og rapport. Ingen estimering av manglende måleverdier.
- SQLite-par er arkiv-/utvekslingsformat. Operativ sammenligning skjer i MariaDB etter import.
- HA-kontrakt, lineage, schema-/fraværssemantikk og verifikasjonsmodell er strukturerte data og skal vedlikeholdes.

## Dokumentasjon og grensesnitt

- Bevar gode beskrivelser, kravgrunnlag og stabile ID-er. Nye avklaringer og endringer føres sporbar i docs/sources/requirements-history.json; se dokument 21. Ikke oppgi en rekonstruert dialogdato som originalkilde.
- Gjeldende beskrivelser organiseres etter emne. Releasehistorikk eies av RELEASE-NOTES.md; målmiljøstatus av dokument 15. Bevisst gjentakelse av ansvarsdeling og arkitektursperrer skal beholdes.
- Før en produsent eller mottaker endres: les den aktuelle autoritative kontrakten og contracts/interface-catalog.json. Kontroller SQL-registre, obligatoriske felt/fravær og faktiske flowkoblinger. Både positiv bruk og feil argumentnavn/manglende felt skal prøves ved berørt grense.
- Rent dokumentbygg kjøres med tools/build_docs.py og skal ikke endre flow, dashboard eller installer-SQL. Pakkebygget kaller tools/build_runtime.py eksplisitt før dokumentbygg. Genererte kataloger erstatter ikke kildene.

## Bygg og verifikasjon

`python3 tools/build-package.py --zip` bygger versjonert pakke under `dist/`. `bash tools/run-tests.sh` kjører releasekontrollene og kontrollerer også kildebundne native testbevis. Native tester krever isolert MariaDB 12.3.3 og de angitte testavhengighetene; kjør dem aldri mot driftsdatabasen. Se `TEST-RESULTS.md` for faktisk bevis og begrensninger.

P24r16 er opprinnelsen til første GitHub-utgave. Eldre pakkenavn/testfilnavn og stabile krav-/beslutnings-ID-er er referanser, ikke en alternativ arbeidsflyt eller teknisk baseline.
