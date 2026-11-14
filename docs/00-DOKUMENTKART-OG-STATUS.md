---
doc_id: DOC-00
role: governance
status: current
source_format: markdown
---

# 00 – Dokumentkart og kildeeierskap

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

**Rolle:** Navigasjon og eierskap for hele dokumentasjonsmodellen: Markdown, SQL-registre, strukturerte kontrakter, verifikasjonskilder og genererte leseutgaver.

## Dokumentprinsipper

Gjeldende fag- og kontraktdokumenter beskriver systemet etter emne. [Releasehistorikken](../RELEASE-NOTES.md) beskriver leveranser; [kravhistorikken](21-KRAVHISTORIKK-OG-DOKUMENTFORVALTNING.md) bevarer behov, begrunnelser og endringer. God dokumentasjon bevares og mangler suppleres. Arkitektursperrene gjentas bevisst.

Normativt krav/beslutning, implementert/release-verifisert funksjon og målmiljø-verifisert funksjon er separate nivåer. En grønn lokal test eller installasjonsbekreftelse lukker ikke automatisk UAT. Eksakte verdier og ID-er vedlikeholdes hos sin eier; oversikter genereres eller lenker dit.

Arbeidsregler står i [AGENTS.md](../AGENTS.md). Datoversjon og publiseringsidentitet eies av VERSION/BUILD-INFO og de kontrollerte releasekvitteringene. Ingen manuelt kopiert «gjeldende release» på hver side.

## Dokumenthierarki

<!-- BEGIN DOCUMENT MAP -->
| Gruppe | Dokument | Rolle |
|---|---|---|
| Inngang og styring | [00 – Dokumentkart og kildeeierskap](00-DOKUMENTKART-OG-STATUS.md) | governance |
| Inngang og styring | [Onboarding av en ny chat](ONBOARDING-NY-CHAT.md) | governance |
| Inngang og styring | [21 – Kravhistorikk og dokumentforvaltning](21-KRAVHISTORIKK-OG-DOKUMENTFORVALTNING.md) | history |
| Krav og beslutninger | [01 – Krav: felles system](01-KRAV-FELLES.md) | requirements |
| Krav og beslutninger | [02 – Krav: gjæringsmotor og integrasjon](02-KRAV-MOTOR-OG-INTEGRASJON.md) | requirements |
| Krav og beslutninger | [03 – Krav: Home Assistant-dashboard](03-KRAV-DASHBOARD.md) | requirements |
| Krav og beslutninger | [04 – Krav: installer og release](04-KRAV-INSTALLER.md) | requirements |
| Krav og beslutninger | [14 – Aktive beslutninger](14-AKTIVE-BESLUTNINGER.md) | decisions |
| Arkitektur og modeller | [07 – Systemarkitektur og dataflyt](07-SYSTEMARKITEKTUR-OG-DATAFLYT.md) | architecture |
| Arkitektur og modeller | [06 – Datamodell og persistens](06-DATAMODELL-OG-PERSISTENS.md) | architecture |
| Arkitektur og modeller | [10 – Regel- og evalueringsmodell](10-REGEL-OG-EVALUERINGSMODELL.md) | rule-model |
| Arkitektur og modeller | [11 – Template-livsløp og editormodell](11-TEMPLATE-OG-EDITOR-MODELL.md) | template-model |
| Arkitektur og modeller | [13 – Livsløp, observasjoner, rapport og historikk](13-LIVSLOP-OBSERVASJONER-RAPPORT-OG-HISTORIKK.md) | lifecycle |
| Arkitektur og modeller | [16 – W-34/70 faggrunnlag og prosessmodell](16-W3470-FAGGRUNNLAG-OG-PROSESSMODELL.md) | profile-model |
| Arkitektur og modeller | [17 – Aletemplater og faggrunnlag](17-ALE-TEMPLATER-OG-FAKTA.md) | domain_reference |
| Grensesnitt og diagnostikk | [05 – Frontend- og integrasjonskontrakt](05-FRONTEND-OG-INTEGRASJONSKONTRAKT.md) | contract |
| Grensesnitt og diagnostikk | [12 – Node-RED–MariaDB operasjons- og transaksjonskontrakt](12-OPERASJONS-OG-TRANSAKSJONSKONTRAKT.md) | transaction-contract |
| Grensesnitt og diagnostikk | [19 – Teknisk diagnostikk og Systemkontroll](19-TEKNISK-FANE-OG-DRIFTSMELDINGER.md) | diagnostics |
| Bruk og drift | [20 – Operatørveiledning](20-OPERATOERVEILEDNING.md) | operator-guide |
| Bruk og drift | [08 – Driftsveiledning](08-DRIFTSVEILEDNING.md) | operations-guide |
| Verifikasjon og status | [09 – Akseptansetest](09-AKSEPTANSETEST.md) | verification |
| Verifikasjon og status | [15 – Åpent arbeid og målmiljøstatus](15-AAPENT-ARBEID.md) | open-work |
| Verifikasjon og status | [18 – Implementasjons- og verifikasjonsstatus](18-IMPLEMENTASJONS-OG-VERIFIKASJONSSTATUS.md) | implementation-status |
<!-- END DOCUMENT MAP -->

## Autoritative kilder

| Informasjon | Autoritativ kilde |
|---|---|
| Produkt-/domenekrav | dokument 01–04 |
| Arkitektur-/produktbeslutninger | dokument 14 |
| HA entity/config-ID-er, eventkanaler, bootstrapmetadata | MariaDB `ha_entity_registry` / `ha_event_registry` + underregistre; seed i `../sql/21-system-metadata-seed.sql` |
| HA↔Node-RED-semantikk | dokument 05 |
| Fysiske tabeller/views/kolonner/constraints | SQL DDL + MariaDB `INFORMATION_SCHEMA` |
| Template-/registry-regler | SQL registry/template-seed + installert MariaDB |
| W-34/70 eksakte aktive kriterier/parametere | `../sql/03-w3470-template-seed.sql`; generert inspeksjonsuttrekk `generated/w3470-rule-reference.json` |
| Målekilde-/valideringsprofil | `../sql/23-measurement-source-seed.sql`; generert inspeksjonsuttrekk `generated/w3470-rule-reference.json` |
| Systemfunksjoner og informasjonsavhengigheter | `system_functions`, `information_objects`, `function_information_dependencies` |
| Implementert/release-verifisert funksjon | dokument 18 + releaseport/tester |
| Målmiljø-verifisering og åpne forhold | dokument 15 og dokument 09 |
| Krav-/beslutningsmetadata | dokument 01–04 og 14, generert til MariaDB-katalog |
| VER-/TEST-relasjoner | `../verification/verification-model.json` og `../verification/test-catalog.json`, validert/generert ved build |
| Faktiske TECH/FUNC/UAT-resultater | MariaDB `verification_test_runs` / `verification_test_results` |

Genererte artefakter er **ikke** nye sannhetskilder. De gjør normative kilder søkbare og maskinlesbare.

## Maskinlesbar dokumentasjon

`tools/build_docs.py` genererer minst:

- `generated/document-index.json` – dokument-ID, rolle og status;
- `generated/requirements.json` – krav-ID, status, tekst og kildeposisjon;
- `generated/traceability.json` – eldre tekstbasert referanseuttrekk; den strukturerte VER/TEST-modellen er fasit for gjeldende verifikasjon;
- `generated/verification-model.json` – generert krav/DEC/VER/TEST-relasjonsmodell fra gjeldende kilder;
- `generated/decisions.json` – ADR/DEC-uttrekk;
- `generated/open-work.json` – OPEN-register;
- `generated/w3470-rule-reference.json` – avledet inspeksjonsuttrekk fra W-34/70-/målekilde-SQL.

HTML-leseutgaver genereres fra Markdown med samme byggesteg. Releaseporten skal regenerere dokumentartefaktene og kreve null diff.


## Hele grensesnittkjeden

[Grensesnittkatalogen](../contracts/interface-catalog.json) er det vedlikeholdte kartet over DB ↔ NR, NR ↔ HA og teknisk filpublisering. [Generert grensesnittreferanse](generated/interface-reference.md) viser registrerte rutiner, ruter, felt og faktiske flowkoblinger. Autoritet, fraværsregler og kontrollmetode skal fremgå; genererte kataloger er ikke parallelle autoriteter.

## Status og bevis

Dokument 15 eier åpne forhold og dokumenterte målmiljøobservasjoner. Dokument 18 er en kort funksjonsoversikt som lenker til bevis og OPEN-ID-er. TEST-RESULTS.md beskriver den navngitte releasens testomfang. verification/-filer har egne versjoner, datoer og kildeavtrykk; historiske bevis får ikke ny dato uten ny kjøring.

## Historiske referanser

Gamle dokumentutgaver finnes på sine Git-committer/tagger. Ordinær release distribuerer gjeldende dokumentasjon. [BASELINES](../reference/BASELINES.json) beskriver eksplisitte funksjonelle/designreferanser; deres tekniske implementasjon er ikke gjeldende arkitektur. Aktive sperrer mot forlatte løsninger står i dokument 14 og gjentas i dokumentene.

## Ny chat og vedlikehold

[Onboarding](ONBOARDING-NY-CHAT.md) angir lesekjerne og oppgaveavhengig fordypning. OVERLEVERING.md inneholder pågående avtale og neste steg og viser til eierne av krav, kontrakter og målstatus. [Dokumentforvaltning](21-KRAVHISTORIKK-OG-DOKUMENTFORVALTNING.md) beskriver bevaring og kontroll.
