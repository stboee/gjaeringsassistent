---
doc_id: DOC-11
role: template-model
status: normative
source_format: markdown
---

# 11 – Template-livsløp og editormodell

**Rolle:** Normativ domene-/operatørmodell for template-livsløp og editor.

## 1. Hva en template er

En template er **ikke en `.json`-fil**. Den er et versjonert, normalisert domeneaggregat i MariaDB. JSON som `template-editor.json` er kun frontend-read-model/transport.

Den fysiske persistensen beskrives i dokument 06/SQL. Regelsemantikken for metric calculation, kriterier, targets og actions beskrives i dokument 10. Dette dokumentet beskriver livsløpet og operatørarbeidsflyten. En template skal inneholde nok deklarativ informasjon til at motoren ikke trenger å finne opp egne fagregler.

## 2. Livsløp

`templatebibliotek → draft → valider → publiser immutable versjon ↔ retired → Start velger published → Start/freeze`

- `templates` er den stabile templateidentiteten.
- `template_versions` er versjonene og har lifecycle `draft`, `published` eller `retired`.
- Maksimalt én draft per templateidentitet er arbeidsflate.
- Publisert eller retired versjon er immutable som faglig innhold; lifecyclemetadata kan endres mellom `published` og `retired`.
- `retired` betyr at versjonen ikke kan velges for nye gjæringer. Den kan aktiveres igjen uten å opprette ny faglig versjon.
- Templateadministrasjon har et eget, MariaDB-persistet valg i `template_editor_state`. Dette valget er uavhengig av `session_setup_draft` og påvirker ikke Start.
- Ved Start fryses valgt publisert versjon til normaliserte `session_*`-tabeller med snapshotmetadata/SHA-256.
- Templatebibliotek og drafts kan administreres også mens en session er aktiv; frozen sessiondata endres aldri av senere templateadministrasjon.


## 3. Templatebibliotek og administrasjon

Template-fanen skal først vise et samlet **Templatebibliotek** uavhengig av runtime. Biblioteket viser alle templateidentiteter og versjoner med status, kildeversjon og relevante markører for Start-valg eller bruk i aktiv session.

Følgende operasjoner er del av administrasjonen:

- åpne/velge publisert, draft eller retired versjon i Template-fanen uten å endre Start-valget;
- lage eller åpne draft fra en publisert eller retired versjon av samme templateidentitet;
- opprette en ny templateidentitet ved normalisert kopiering fra en eksisterende immutable versjon;
- lagre, validere, publisere eller forkaste draft;
- sette publisert versjon `retired` og senere aktivere den igjen;
- sammenligne draft mot `based_on_version_id` gjennom en generert read-model;
- filtrere biblioteket på status som ren presentasjonsfunksjon.

Publisering av en ny versjon skal **ikke** automatisk endre templatevalget på Start. Operatøren velger eksplisitt hvilken publisert versjon som skal brukes for neste gjæring. Dersom en versjon som er valgt på Start settes `retired`, skal pre-start-valget fjernes fordi retired versjon ikke er startbar.

Ny template opprettes fra en eksisterende publisert/retired kildeversjon. Dette sikrer at registry-eide og templateeide deklarative data kopieres normalisert uten å introdusere en alternativ JSON-sannhetskilde.

## 4. Grafisk editor

Template-fanen er domenespesifikk og grafisk. Registry bestemmer gyldige metrics, modeller, parametere og operasjoner. Operatøren kan arbeide med:

- templateinformasjon og komplette batch-/startdefaults;
- gjærprofil, pitchmodus og målemetode;
- biology calculations med registrert modell, deklarerte input og typed parametere;
- metric-/calculation-semantikk fra registry, inkludert freshness-policy;
- B1–B6 med kriterier;
- P1–P15 med enabled/navn/beskrivelse, kriterier, targets, actions og eksplisitt policy for om historisk replay kan etablere overgang automatisk;
- modelldetaljer, korrigerbare parametere og biological/process exception-policy.
- analysegraph/series-metadata: label, forklaring, enhet, series source, warm-up, coverage, minste ordinære målegrunnlag, punkt-/linjestil uten estimeringsbånd, outputdomene, gap- og markørpolicy;
- valg av kilde-/målevalideringspolicy der dette er templateeiet; kildespesifikke standardregler ligger i source profile og fryses til session.

B1–B6 og P1–P15 er stabile slots; innholdet kan endres gjennom ny templateversjon.

Kriteriematrisene skal være kompakte: bare kriterietyper som faktisk brukes i minst én B-fase/P-slot, eller som operatøren midlertidig har valgt å vise, skal være synlige som rader. Ubrukte registry-metrics samles i en nedtrekksboks **Ubrukte kriterietyper** under henholdsvis B- og P-matrisen. `Vis kriterietype` gjør raden synlig uten å endre templaten; `+` i en celle oppretter kriteriet i akkurat den fasen/trinnet fra registryets defaultmodell/-parametere. Når siste faktiske bruk av kriterietypen slettes, skal raden igjen kunne forsvinne og typen returnere til listen over ubrukte kriterietyper. Deaktivert kriterium er fortsatt en faktisk templateforekomst og skal derfor forbli synlig.

## 5. Read-model og kommandoer

Node-RED genererer `/data/gjaeringsassistent/ha-public/template-editor.json`. Dashboardet leser denne read-modelen, men endringer sendes tilbake som eksplisitte HA-eventkanaler til Node-RED. Node-RED validerer og skriver normaliserte MariaDB-rader.

Inntasting skal registreres i flyktig lokal UI-kladd ved `input`, før feltet mister fokus. Automatisk refresh skal ikke erstatte fokuserte redigeringsfelt eller ulagrede dokumentendringer. Et request-svar som kommer etter at redigering har begynt skal heller ikke overskrive teksten. Ny template-ID/navn/kilde og publiseringsetikett skal bevares ved rerender. **Oppdater** leser read-model og skal ikke forkaste ulagrede endringer.

Frontendvalidering er operatørhjelp. Node-RED/MariaDB er den faktiske validerings- og integritetsgrensen.

## 6. Publiseringsvalidering

Publisering er domenets kompileringstrinn. Før en draft kan bli immutable skal motoren/DB validere minst:

- at alle metrics finnes i registry og har registrert beregningsmodell;
- at calculation model har alle obligatoriske input og typed parametere;
- at kriteriemodellen er tillatt for metrikken;
- at modellparametere er gyldige og komplette;
- at `maximum_age_minutes` bare brukes når metrikkens freshness-semantikk tillater kildealder;
- at operator-policy bare refererer til støttede/korrigerbare parametere;
- at B1–B6/P1–P15 og relasjonene er strukturelt konsistente;
- at historisk autoovergang er eksplisitt deklarert per prosesstrinn og ikke utledes/hardkodes i motoren.
- at analysegraph/series peker på gyldige registrerte metrics/kriterier og har konsistente warm-up/coverage/outputgrenser;
- at målevalideringspolicy som inngår i templaten bare bruker registrerte generiske valideringsmodeller og typed parametere.

Ugyldig eller manglende regelgrunnlag skal stoppe publisering. Motoren skal ikke gjøre en ugyldig template kjørbar med hardkodede terskler eller fallbackverdier.

## 7. Startgrense

1. Operatør velger publisert template.
2. Valget lagres i `session_setup_draft`.
3. Templateadministrasjon/redigering er uavhengig av Start-valget og kan fortsette under aktiv session.
4. Start validerer den eksplisitt valgte `published`-versjonen og oppretter frozen session-kopi.
5. Sessionmotoren bruker frozen `session_*`-data.
6. Senere draft-, publish-, retire- eller reactivate-operasjoner påvirker ikke frozen sessiondata.

## 8. Import/eksport

JSON-templatefiler er ikke persistent autoritativ modell. Eventuell senere import/eksport kan innføres som transportfunksjon, men skal mappe til/fra normalisert template og skal ikke bli alternativ runtime-store.

## forventet utgjæring er templateinput

Template angir `expected_attenuation_min_percent` og `expected_attenuation_max_percent`. Forventet FG er avledet og skal ikke redigeres manuelt. Ved Start kombineres faktisk korrigert OG med templateens forventede utgjæringsområde; sessionen lagrer både det normative utgjæringsområdet og den beregnede FG-projeksjonen som frosne fakta.

For W-34/70-standard er forventet utgjæring 80–84 %. Template-editoren viser beregnet FG for template-OG som read-only informasjon. Startflaten skal ikke be operatøren regne ut eller skrive inn FG-mål.

Pitchtemperatur er ikke et separat startfelt; første manuelt målte temperatur er temperaturgrunnlaget ved pitch. Pre-start-kladd skal ikke republiseres periodisk til redigerbare HA-felt mens operatøren skriver; restore retries ved faktisk MariaDB-utilgjengelighet i stedet for periodisk overskriving.


Kloning kjøres atomisk i `ga_clone_template_tx`, med eksplisitte kolonnelister som utelater genererte kolonner. Forventet utgjæringsgrad, analyse-/båndpolicy og kriterierettigheter følger med. En feil ruller tilbake både ny templateidentitet, draftinnhold og administrasjonsvalg. Eksisterende draft kan gjenåpnes; en opptatt ny template-ID avvises.
