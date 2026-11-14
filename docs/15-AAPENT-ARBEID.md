---
doc_id: DOC-15
role: open-work
status: current
source_format: markdown
---

# 15 – Åpent arbeid og målmiljøstatus

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

**Rolle:** Register over fortsatt åpne forhold og eier av dokumentert målmiljøstatus. Exit-kriteriet avgjør lukking. Implementert kode, lokal regresjon og faktisk måltest skilles.

## Åpne forhold

| ID | Type | Status | Område | Exit-kriterium |
|---|---|---|---|---|
| OPEN-001 | Måltest | Åpen | Reell HA-history/live | Clean install fullfører; Start fra historisk tidspunkt importerer/validerer 5-minuttersdata, registrerer gap, replay-er B/P sekvensielt, går til LIVE og fortsetter etter restart fra persistert cursor. |
| OPEN-002 | Måltest | Åpen | Målekilde/Tilt-projeksjon | Teknisk/Systemkontroll viser fersk DB-eid Tilt-status før Start/under catch-up/i LIVE uten nullable HA-attributtfeil eller konkurrerende produsent. |
| OPEN-003 | Måltest | Åpen | Datakvalitet | Reelt Tilt-grunnlag demonstrerer at åpenbare outliers forkastes før `measurements_5m`, robust median brukes og kvalitetsutfall er sporbare uten clamp. |
| OPEN-004 | Måltest | Åpen | Analyse | Tre aktive analysegrafer viser kun ordinære målebaserte verdier og datagrunnlag etter frozen policy; ingen oppdiktede oppstartsnuller, SG-stabilitetsbånd eller linjer gjennom datagap. |
| OPEN-005 | Måltest | Åpen | Graf/rapport | Gjæring- og rapportgrafer oppdateres med nye committed 5-minuttersdata og bryter linjer ved de samme persisterte `measurement_data_gaps`. |
| OPEN-006 | Måltest | Åpen | Tidskorrigering | Pitch-/B-/P-/observation-korreksjon verifiseres mot reelle data; effektive referanser endres uten å omskrive absolutte måletimestamps. |
| OPEN-007 | Faglig kalibrering | Åpen | W-34/70 kriterier | Hver aktiv terskel/regel er klassifisert som kildebelagt, empirisk kalibrert eller prototypegrense og vurdert mot minst representative reelle gjæringer. |
| OPEN-008 | Avklaring | Åpen | Målevalideringsgrenser | SG/temperatur/RSSI hard range, MAD-multiplikator, max-jump og minimum acceptance er faglig/teknisk begrunnet og justert dersom reell datadistribusjon tilsier det. |
| OPEN-009 | Måltest | Åpen | Historisk sammenligning | Pitch-justert sammenligning er implementert; valg av begge datasett og avsluttet session samt persistens skal måltestes. |
| OPEN-011 | Arkitektur | Åpen | Lineage | Required grensesnitt og aktive systemfunksjoner har komplett registrert lineage; beslutning om eventuell bredere fysisk DB-dekning er dokumentert eksplisitt. |
| OPEN-012 | UX | Åpen | Operatørflate | Gjenstående hensiktsmessige notatplasseringer/handlingskvitteringer fra funksjonelle referanser er enten implementert eller eksplisitt avvist uten å endre domenemodellen. |
| OPEN-013 | Verifikasjon | Åpen | Verifikasjonsmodell | Eksisterende krav/tester kobles gradvis til strukturerte VER/TEST-relasjoner; manglende koblinger er synlige i Verifikasjon-fanen og skal ikke skjules med kunstig coverage-score. |
| OPEN-014 | Måltest/diagnostikk | Åpen | Gjeldende installasjon/arkiv | Installer/schema samsvarer med release-metadata; SQLite-par/sluttrapport, ny start, sammenligning og HA-gjenoppkobling verifiseres i faktisk Docker/HA/Node-RED. TEST-UAT-012/013/014 er åpne. |
| OPEN-015 | Måltest | Åpen | Oppgradering med databevaring | Avtalt og verifisert oppgraderingsløp bevarer eksisterende sesjoner, templates og nødvendig historikk; reset er en særskilt tilsiktet handling. |
| OPEN-016 | Måltest | Åpen | Slurry/startfelt | Den DB-baserte startflaten, komplett første målesett, sensoriske slidere, temperaturpresisjon og P/B-fravik bekreftes i brukerens HA. Rapport 08.11.2026 22:57 viste HA volum=4000/generasjon=2 mens ny DB-kladd hadde NULL. Lokal regresjon dekker dette; funksjonen i installert versjon er ikke bekreftet. |
| OPEN-017 | Feilretting/måltest | Publisert retting; måltest åpen | Sensorinnstillinger gir HTTP 404 | Publisering bruker stage_path, JSON/gzip kan leses tilbake, publiseringsfeil logges og «Les innstillinger» viser faktiske DB-felt i brukerens HA. Den pakkede rettingen bekreftes i brukerens HA. |

## Dokumentert målmiljøstatus

Prosjekteier bekreftet 14.11.2026 installasjon av 2026.11.13-1. Skjermbildet samme dag viste HTTP 404 for source-settings.json samtidig med OK Systemkontroll. Rettelsen er publisert i 2026.11.14-1; installasjon og funksjon av denne utgaven er ikke bekreftet. OPEN-017 forblir åpen til konkret måltest foreligger.

Siste fullstendige vedlagte tekniske målrapport er fra p24r16, 08.11.2026 kl. 22:57. Senere installasjonsbekreftelse/skjermbilder beviser sine egne observasjoner, ikke full databevaring, startflyt eller alle 14 UAT. Konkrete nye bevis registreres her eller som korrelert UAT-resultat; de øvrige dokumentene lenker hit.

## Videre måltest og kalibrering

Bevar rå HA-historikk lenger og hold HA/Raspberry Pi i drift under oppstart. Test støygulv, spranggrenser og biologiske terskler mot rådata. HA-timesstatistikk supplerer eldre grafer uten oppdiktet heartbeat; råd og B/P-overganger krever ordinært grunnlag.

Kontroller CPU/slow-log med aktiv gjæring og sammenligning. Lokal integrasjon gir ingen garantert responstid på gangpc. Faktisk Recorder/time-statistikk, nettverksfeil, nettleser/tidssoner, B/P-korreksjoner, faste akser, arkiv/ny start og HA-gjenoppkobling prøves etter dokument 09. OPEN-015/016/017 knytter databevaring, startfelt og sensorpublisering til konkrete exit-kriterier.

## Sporbarhet

Feilrettingshistorikk finnes i RELEASE-NOTES.md og krav-/beslutningsgrunnlag i dokument 21. Historiske rapportreferanser i et åpent forhold beholdes som bevis for observasjonen. En eldre rapport er ingen automatisk beskrivelse av dagens installasjon.
