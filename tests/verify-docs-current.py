#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,re,subprocess,sys
from html.parser import HTMLParser
from urllib.parse import urlsplit,unquote
ROOT=Path(__file__).resolve().parents[1]; DOCS=ROOT/'docs'; GEN=DOCS/'generated'
errors=[]
active=sorted(DOCS.glob('*.md'))
required_docs={
 '00-DOKUMENTKART-OG-STATUS.md','01-KRAV-FELLES.md','02-KRAV-MOTOR-OG-INTEGRASJON.md',
 '03-KRAV-DASHBOARD.md','04-KRAV-INSTALLER.md','05-FRONTEND-OG-INTEGRASJONSKONTRAKT.md',
 '06-DATAMODELL-OG-PERSISTENS.md','07-SYSTEMARKITEKTUR-OG-DATAFLYT.md','08-DRIFTSVEILEDNING.md',
 '09-AKSEPTANSETEST.md','10-REGEL-OG-EVALUERINGSMODELL.md','11-TEMPLATE-OG-EDITOR-MODELL.md',
 '12-OPERASJONS-OG-TRANSAKSJONSKONTRAKT.md','13-LIVSLOP-OBSERVASJONER-RAPPORT-OG-HISTORIKK.md',
 '14-AKTIVE-BESLUTNINGER.md','15-AAPENT-ARBEID.md','16-W3470-FAGGRUNNLAG-OG-PROSESSMODELL.md',
 '17-ALE-TEMPLATER-OG-FAKTA.md','20-OPERATOERVEILEDNING.md','21-KRAVHISTORIKK-OG-DOKUMENTFORVALTNING.md','ONBOARDING-NY-CHAT.md','18-IMPLEMENTASJONS-OG-VERIFIKASJONSSTATUS.md','19-TEKNISK-FANE-OG-DRIFTSMELDINGER.md','index.md'}
missing=sorted(required_docs-{p.name for p in active})
if missing: errors.append('mangler gjeldende dokumenter: '+', '.join(missing))
if (DOCS/'12-API-KONTRAKT.md').exists(): errors.append('utgått separat API-kontrakt finnes fortsatt')
if (ROOT/'reference/docs').exists() and any((ROOT/'reference/docs').rglob('*.md')): errors.append('komplette historiske dokumentsett skal ikke distribueres i p23-release')

# Frontmatter, local links and unique IDs.
doc_ids=[]; req_ids=[]
for p in active:
    txt=p.read_text(encoding='utf-8')
    m=re.match(r'^---\n(.*?)\n---\n',txt,re.S)
    if not m: errors.append(f'{p.name}: mangler YAML-frontmatter'); continue
    meta={}
    for line in m.group(1).splitlines():
        if ':' in line:
            k,v=line.split(':',1); meta[k.strip()]=v.strip()
    for k in ('doc_id','role','status','source_format'):
        if not meta.get(k): errors.append(f'{p.name}: frontmatter mangler {k}')
    if meta.get('source_format')!='markdown': errors.append(f'{p.name}: source_format skal være markdown')
    if meta.get('doc_id'): doc_ids.append(meta['doc_id'])
    for lm in re.finditer(r'!?\[[^\]]*\]\(([^)]+)\)',txt):
        target=lm.group(1).split('#')[0].strip()
        if target and '://' not in target and not target.startswith('mailto:') and not (p.parent/target).exists():
            errors.append(f'{p.name}: manglende lokal lenke/figur {target}')
    for line in txt.splitlines():
        if line.startswith('#') and re.search(r'\b(?:p\d{2}(?:r\d+)?|prototype\d+|revised\d+)\b',line,re.I):
            errors.append(f'{p.name}: historisk releaseoverskrift i aktiv dokumentasjon: {line}')
    h2=re.findall(r'^## (.+)$',txt,re.M)
    if len(h2)!=len(set(h2)): errors.append(f'{p.name}: dupliserte emneoverskrifter')
    req_ids += re.findall(r'^\|\s*(REQ-[A-Z]+-\d+)\s*\|',txt,re.M)
if len(doc_ids)!=len(set(doc_ids)): errors.append('dupliserte doc_id i aktiv dokumentasjon')
if len(req_ids)!=len(set(req_ids)): errors.append('dupliserte REQ-ID-er i aktive dokumenter')

# Stable IDs are checked for uniqueness, not artificial minimum counts.
dec=(DOCS/'14-AKTIVE-BESLUTNINGER.md').read_text(encoding='utf-8')
dec_ids=re.findall(r'^\|\s*((?:DEC|ADR)-[A-Z0-9-]+)\s*\|',dec,re.M)
if len(dec_ids)!=len(set(dec_ids)): errors.append('dupliserte DEC/ADR-ID-er')
openw=(DOCS/'15-AAPENT-ARBEID.md').read_text(encoding='utf-8')
open_ids=re.findall(r'^\|\s*(OPEN-\d+)\s*\|',openw,re.M)
if len(open_ids)!=len(set(open_ids)): errors.append('dupliserte OPEN-ID-er')
if 'Exit-kriterium' not in openw: errors.append('OPEN-register mangler exit-kriterium')

# Guardrails that must remain explicit because they protect against recurring workarounds.
alltxt='\n'.join(p.read_text(encoding='utf-8') for p in active)
for phrase in [
 'MariaDB/InnoDB er eneste autoritative persistente sannhetskilde',
 'Feil eller mangler skal rettes ved den autoritative kilden',
 'append-only',
 'ingen global writer-kø',
 'frozen session',
 'Verifikasjon',
 'TEST-UAT-009',
 'JSON',
 'HTML']:
    if phrase.lower() not in alltxt.lower(): errors.append('mangler sentral dokumentert regel/begrep: '+phrase)

for fig in ['FIG-01-SYSTEMARKITEKTUR.svg','FIG-02-DASHBOARD-MAALBILDE.svg','FIG-03-GRAFKONTRAKT.svg','FIG-04-TEMPLATE-START-SNAPSHOT.svg','FIG-05-MAALINGSFLYT.svg','FIG-06-EVALUERING-REPLAY.svg']:
    if not (DOCS/'figures'/fig).exists(): errors.append('mangler aktiv figur '+fig)

required_generated=['requirements-history.md','requirements-history.html','interface-reference.json','interface-reference.md','document-index.json','requirements.json','traceability.json','decisions.json','open-work.json','w3470-rule-reference.json','w3470-rule-reference.md','verification-model.json']
for name in required_generated:
    if not (GEN/name).exists(): errors.append('mangler generert dokumentmetadata '+name)

# Generated artefacts must be reproducible from authoritative sources.
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
generated_paths=sorted(list(DOCS.glob('*.html'))+list(GEN.glob('*'))+[ROOT/'sql/24-verification-metadata-seed.sql'])
runtime_paths=[ROOT/p for p in ['nodered/flows.template.json','dashboard/gjaeringsassistent-card.js','sql/24-verification-metadata-seed.sql','contracts/ha-node-red-contract.json']]
runtime_before={str(p):digest(p) for p in runtime_paths}
source_paths=list(active)+[ROOT/p for p in ['AGENTS.md','README.md','OVERLEVERING.md']]
source_before={str(p):digest(p) for p in source_paths}
before={p.relative_to(ROOT).as_posix():digest(p) for p in generated_paths if p.is_file()}
try:
    subprocess.run([sys.executable,str(ROOT/'tools/build_docs.py')],cwd=ROOT,check=True,stdout=subprocess.DEVNULL)
except Exception as e:
    errors.append(f'dokumentbygg feilet: {e}')
after_paths=sorted(list(DOCS.glob('*.html'))+list(GEN.glob('*'))+[ROOT/'sql/24-verification-metadata-seed.sql'])
after={p.relative_to(ROOT).as_posix():digest(p) for p in after_paths if p.is_file()}
if source_before!={str(p):digest(p) for p in source_paths}: errors.append('Genererte grunnregel-/kartblokker var stale før dokumentkontrollen')
if runtime_before!={str(p):digest(p) for p in runtime_paths}: errors.append('Rent dokumentbygg endret runtime/installerte metadata')
if before!=after:
    changed=sorted(x for x in set(before)|set(after) if before.get(x)!=after.get(x))
    errors.append('genererte dokumentartefakter var stale/ikke deterministiske: '+', '.join(changed[:16]))

# Check links and anchors in the actual rendered pages, including generated references.
class PageLinks(HTMLParser):
    def __init__(self,text):
        super().__init__(); self.ids=set(); self.refs=[]; self.feed(text)
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if 'id' in attrs:self.ids.add(attrs['id'])
        for key in (['href'] if tag in ['a','link'] else ['src'] if tag=='img' else []):
            if attrs.get(key):self.refs.append(attrs[key])
pages={p.resolve():PageLinks(p.read_text()) for p in list(DOCS.glob('*.html'))+list(GEN.glob('*.html'))}
for p,page in pages.items():
    for href in page.refs:
        url=urlsplit(href)
        if url.scheme or url.netloc:continue
        target=(p.parent/unquote(url.path)).resolve() if url.path else p
        if not target.is_file():errors.append(f'{p.name}: manglende HTML-lenke {href}')
        elif url.fragment and target in pages and unquote(url.fragment) not in pages[target].ids:
            errors.append(f'{p.name}: manglende HTML-anker {href}')

# Generated registries must agree with source IDs after rebuild.
try:
    rq=json.loads((GEN/'requirements.json').read_text(encoding='utf-8'))
    if rq.get('count')!=len(req_ids): errors.append('requirements.json samsvarer ikke med REQ-kildene')
    dj=json.loads((GEN/'decisions.json').read_text(encoding='utf-8'))
    if dj.get('count')!=len(dec_ids): errors.append('decisions.json samsvarer ikke med DEC-kilden')
    vj=json.loads((GEN/'verification-model.json').read_text(encoding='utf-8'))
    if vj.get('requirements_count')!=len(req_ids): errors.append('verification-model requirements_count samsvarer ikke med kildene')
    if vj.get('decisions_count')!=len(dec_ids): errors.append('verification-model decisions_count samsvarer ikke med kildene')
except Exception as e: errors.append('kunne ikke lese genererte registre: '+str(e))

subprocess.run([sys.executable,str(ROOT/'tests/verify-document-preservation.py')],cwd=ROOT,check=True)

if errors:
    print('RESULT: FAIL – aktiv dokumentasjon')
    for e in errors: print('FAIL',e)
    raise SystemExit(1)
print(f'RESULT: PASS – dokumentasjon: {len(active)} aktive kilder, {len(req_ids)} REQ, {len(dec_ids)} DEC/ADR, {len(open_ids)} OPEN; HTML/maskinmetadata reproduserbare')
