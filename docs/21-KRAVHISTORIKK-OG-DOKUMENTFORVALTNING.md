---
doc_id: DOC-21
role: history
status: current
source_format: markdown
---

# 21 – Kravhistorikk og dokumentforvaltning

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

**Rolle:** Samlet krav-/beslutningsproveniens og regler for å bevare dokumentasjon. Gjeldende krav eies av dokument 01–04; aktive beslutninger av dokument 14. Releaseendringer eies av RELEASE-NOTES.md.

## Bevaring og kravhistorikk

[requirements-history.json](sources/requirements-history.json) bevarer første dokumenterte baseline med alle 264 krav og 68 beslutninger, opprinnelig tekst og kildeposisjon ved den eksplisitte basecommitten. Det er historiske snapshots; dagens krav oppdateres hos sin eier. Opprinnelig dialogdato skal ikke utledes fra en senere dokument- eller commitdato.

Nye avklaringer føres som en ny historikkhendelse med kilde, begrunnelse og berørte ID-er. Ved kravendring registreres tidligere og ny betydning samt eventuell erstatter; ID-er gjenbrukes ikke. Tidligere utgåtte ID-er og eksisterende historikk i Git beholdes. Historikken er ikke en påstand om at alle krav er implementert eller verifisert.

En [generert leseutgave](generated/requirements-history.md) viser alle baselinekrav, beslutninger og senere kildeavklaringer med lenker til de opprinnelige dokumentposisjonene. Den redigeres ikke separat.

## Kildekvalitet

HIST-001 er et kontrollert Git-snapshot. HIST-002 registrerer prosjekteierens avklaringer i denne revisjonen. HIST-003 er gjenfunnet samtalesammendrag med rapportert dato, ikke åpnet originaldialog eller ordrett sitat. Manglende opprinnelsesreferanse er eksplisitt ukjent. Nye funn kan supplere historikken uten å erstatte det eksisterende beviset.

## Bevisst gjentakelse

Ansvarsdeling, databaseautoritet og reglene mot «juks» gjentas i alle aktive dokumenter og inngangspunkter. [Grunnteksten](sources/architecture-guardrails.md) er vedlikeholdt kilde; like blokker innarbeides ved dokumentbygg og kontrolleres for samsvar. Dette er et synlig vern mot tilbakevendende kodefeil, ikke uønsket dobbeltføring.

## Endringsregler

God forklaring, begrunnelse, konkrete eksempler, kontrakter og kildehenvisninger bevares. Ved flytting skal destinasjonen finnes og lenkene oppdateres. Mangler suppleres; motstrid mellom krav og kode registreres som avvik før betydningen endres. Gjeldende regler organiseres etter emne uten nye releaseavsnitt. Stabile DEC/REQ/TEST-ID-er og faktiske kompatibilitetsversjoner beholdes.

## Strukturerte kilder og avledninger

[Grensesnittkatalogen](../contracts/interface-catalog.json) skiller autoritative kilder, genererte kataloger, implementasjon og kontroll. SQL-registre og rutiner, kontraktskjema, verifikasjonsmodell og kravhistorikk inngår i samme dokumentforvaltning. HTML/JSON/SQL-uttrekk genereres fra sine eiere og redigeres ikke som parallelle sannheter.

## Kontroll av revisjonen

[Revisjonsregnskapet](sources/document-revision.json) knytter kildeavsnitt før revisjonen til bevart innhold eller begrunnet behandling. Krav- og beslutningstekst kontrolleres eksakt mot historikksnapshotet. Dokumentkontroll prøver gjentatte grunnregler, overskrifter, lenker, dokumentkart og reproduksjon. Grensesnittkontroll prøver faktiske register-/flow-/mottakergrenser og negative kontrakttilfeller. Dette lukker ingen målmiljø-UAT.

Releasejobben bruker tools/release_notes.py til å hente bare den aktuelle utgavens avsnitt fra RELEASE-NOTES.md. Tidligere releasebeskrivelser og publiserte pakker omskrives ikke av denne revisjonen.

Dokumentbygg krever Pandoc-versjonen i tools/doc-builder.json. Begge GitHub-jobber installerer samme offisielle pakke med kontrollert SHA-256; formatteringsforskjeller mellom verktøyversjoner skal ikke skjules ved å svekke reproduksjonskontrollen.
