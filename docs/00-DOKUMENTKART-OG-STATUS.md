---
doc_id: DOC-00
role: governance
status: normative
source_format: markdown
---

# 00 – Dokumentkart og status

**Gjeldende release:** `2026.11.09-1`

Prosjektets utviklings-/publiseringsregler står i [AGENTS.md](../AGENTS.md). Datoversjon er ÅÅÅÅ.MM.DD-N med kort releasebeskrivelse. Utvikling skjer direkte på main etter avklaring og «start»; issues/PR inngår ikke i arbeidsflyten.

## Dokumentprinsipper

Dokumentsettet beskriver **gjeldende** krav, arkitektur, semantikk og operativ bruk. Releasehistorikk skal ligge i `RELEASE-NOTES.md` eller historisk referansemateriale, ikke som løpende «revisedX»-seksjoner i normative dokumenter.

Tre nivåer skal holdes adskilt:

1. **Normativt krav / beslutning** – hva systemet skal gjøre og hvorfor.
2. **Implementert og release-verifisert** – hva som finnes i den aktuelle pakken og har bestått releaseporten.
3. **Målmiljø-verifisert** – hva som faktisk er demonstrert mot installert Home Assistant/Node-RED/MariaDB og reelle data.

`docs/*.md`, SQL/registry og de strukturerte verifikasjonskildene er vedlikeholdte kilder etter hvilket informasjonselement de eier. HTML og genererte JSON-/SQL-uttrekk er avledede artefakter og skal ikke redigeres som parallelle sannhetskilder. Feil eller mangler skal rettes ved den autoritative kilden; Node-RED, Home Assistant eller frontend skal aldri kompensere med skjulte defaults, fallback eller parallell domenelogikk.

## Dokumenthierarki

| Nr | Dokument | Rolle | Autoritet |
|---:|---|---|---|
| 01 | Krav – felles | Produkt- og domenekrav | Normativ |
| 02 | Krav – motor og integrasjon | Node-RED/MariaDB/HA-ansvar og motorgrenser | Normativ |
| 03 | Krav – dashboard | Operatørflate og visualisering | Normativ |
| 04 | Krav – installer og release | Installasjons-/releasegrense | Normativ |
| 05 | Frontend- og integrasjonskontrakt | HA ↔ Node-RED-kontrakt | Normativ |
| 06 | Datamodell og persistens | Logisk datamodell og persistensprinsipper | Normativ |
| 07 | Systemarkitektur og dataflyt | Systemgrenser og hovedflyter | Normativ |
| 08 | Driftsveiledning | Installasjon, drift og feilsøking | Normativ operativ |
| 09 | Akseptansetest | Målmiljø-verifikasjon | Normativ verifikasjon |
| 10 | Regel- og evalueringsmodell | Generisk regel-/kriterie-/datakvalitetssemantikk | Normativ |
| 11 | Template- og editormodell | Draft → publisering → frozen session | Normativ |
| 12 | Operasjons- og transaksjonskontrakt | Node-RED ↔ MariaDB-operasjonsgrense | Normativ |
| 13 | Livsløp, observasjoner, rapport og historikk | Session-livsløp og historikk | Normativ |
| 14 | Aktive beslutninger | ADR/DEC-register | Normativ |
| 15 | Åpent arbeid | Reelle gjenstående måltester/avklaringer | Gjeldende status |
| 16 | W-34/70 faggrunnlag og prosessmodell | Profilspesifikk forklaring; eksakte verdier genereres fra SQL | Normativ forklaring + generert detaljfasit |
| 18 | Implementasjons- og verifikasjonsstatus | Gjeldende capability/status uten releasehistorikk | Gjeldende status |
| 19 | Teknisk diagnostikk og Systemkontroll | Observability-/diagnostikkmodell | Normativ |

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

## Historiske referanser

Ordinær p24-release inneholder ikke komplette historiske dokumentsett. `../reference/BASELINES.json` beholder bare eksplisitte funksjonelle/designmessige referanser. `p18-r5` og `p17r12` kan brukes når gjeldende dokumentasjon uttrykkelig peker på dem; deres tekniske implementasjon er ikke baseline. Forlatte tekniske løsninger som ikke skal gjeninnføres beskrives som aktive DEC/arkitektursperrer, ikke ved å distribuere gamle normative dokumenter.

## Videreføring til ny chat

Følg [Onboarding av en ny chat](ONBOARDING-NY-CHAT.md) for konkret leserekkefølge, undersøkelse av strukturerte kilder og statuskvittering.

`../OVERLEVERING.md` er leveransens daterte overleveringssnapshot med leserekkefølge, prinsipper og installasjons-/teststatus. Det er et inngangspunkt, ikke en parallell normativ kilde. Nye observasjoner kontrolleres mot aktuell versjon.
