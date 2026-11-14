---
doc_id: DOC-INDEX
role: entrypoint
status: current
source_format: markdown
---

# Gjæringsassistent – dokumentasjon

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

Dette er dokumentasjonen på den aktuelle kildecommitten. Publisert programvare og kildekoden på main kan ha ulik dokumentrevisjon. Leveranseidentiteten finnes i [VERSION](../VERSION), [BUILD-INFO](../BUILD-INFO.json) og [GitHub Releases](https://github.com/stboee/gjaeringsassistent/releases).

- Operatør: [brukerveiledning](20-OPERATOERVEILEDNING.md).
- Installasjon og drift: [driftsveiledning](08-DRIFTSVEILEDNING.md).
- Utvikling og feilretting: [arkitektur](07-SYSTEMARKITEKTUR-OG-DATAFLYT.md), [HA-kontrakt](05-FRONTEND-OG-INTEGRASJONSKONTRAKT.md), [DB-kontrakt](12-OPERASJONS-OG-TRANSAKSJONSKONTRAKT.md) og [strukturerte grensesnitt](generated/interface-reference.md).
- Krav og begrunnelser: [dokumentkart](00-DOKUMENTKART-OG-STATUS.md), [beslutninger](14-AKTIVE-BESLUTNINGER.md) og [kravhistorikk](21-KRAVHISTORIKK-OG-DOKUMENTFORVALTNING.md).
- Status: [åpne forhold og målmiljø](15-AAPENT-ARBEID.md), [funksjonsoversikt](18-IMPLEMENTASJONS-OG-VERIFIKASJONSSTATUS.md).
- Ny chat: [onboarding](ONBOARDING-NY-CHAT.md) og [pågående arbeid](../OVERLEVERING.md).

HTML og generated/-kataloger er avledede leseutgaver. Autoritative kilder og eiere fremgår av dokumentkartet.
