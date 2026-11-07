---
doc_id: DOC-15
role: open-work
status: current
source_format: markdown
---

# 15 – Åpent arbeid

**Rolle:** Register over reelle, fortsatt åpne forhold. Historiske lukkede prototypefeil føres i releasehistorikk, ikke her.

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

Nye forhold legges inn når de er observerte eller eksplisitt besluttede arbeidsoppgaver. Spekulasjoner uten konkret exit-kriterium hører ikke hjemme i registeret.

## Neste brygg

Bevar rå HA-historikk lenger og hold HA/Raspberry Pi i drift under oppstart. Test støygulv, spranggrenser og biologiske terskler mot rådata. HA-timesstatistikk supplerer eldre grafer uten MQTT-verifikasjon; råd og B/P-overganger krever fortsatt ordinært målegrunnlag. Faglig tuning av terskler er åpen.

## Gjeldende målmiljøstatus

Brukeren har bekreftet at p24r16 er installert og fungerer fint. Første GitHub-utgave 2026.11.07-1 bygger på dette grunnlaget. Bekreftelsen lukker ikke automatisk hver enkelt av de 14 UAT-testene; faktisk installasjon av datoversjonen og konkrete målresultater må registreres separat.

Kontroller CPU/slow-log på gangpc med aktiv gjæring og sammenligning. Lokal native integrasjon dokumenterer leseavgrensning og samtidighet, ikke garantert responstid på gangpc. Reell HA Recorder/time-statistikk, nettverksfeil, nettleser/tidssoner, B/P-korreksjoner, faste akser, arkiv/ny start og HA-gjenoppkobling er fortsatt måltester der konkrete bevis mangler.

## Produksjonsoppgraderinger

| ID | Type | Status | Område | Exit-kriterium |
|---|---|---|---|---|
| OPEN-015 | Avklaring/implementering | Åpen | Oppgradering med databevaring | Avtalt og verifisert oppgraderingsløp bevarer eksisterende sesjoner, templates og nødvendig historikk; reset er en særskilt tilsiktet handling. |

Dagens installer resetter fortsatt databasen. GitHub-publisering er ikke en databevarende migrering. Issues/PR inngår ikke i prosjektarbeidsflyten; avtalt arbeid dokumenteres i gjeldende kilder og føres direkte på main.
