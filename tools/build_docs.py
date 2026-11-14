#!/usr/bin/env python3
from pathlib import Path
import json,re,subprocess,sys,html,hashlib,shutil,platform
ROOT=Path(__file__).resolve().parents[1]
builder_pin=json.loads((ROOT/'tools/doc-builder.json').read_text())
if subprocess.check_output(['pandoc','--version'],text=True).splitlines()[0]!='pandoc '+builder_pin['pandoc_version']:
    raise SystemExit('Dokumentbygget krever Pandoc '+builder_pin['pandoc_version']+' fra tools/doc-builder.json')
if platform.system()=='Linux' and platform.machine()=='x86_64':
    binary=Path(shutil.which('pandoc'))
    if hashlib.sha256(binary.read_bytes()).hexdigest()!=builder_pin['ubuntu_amd64_binary_sha256']:
        raise SystemExit('Dokumentbygget krever den SHA-låste offisielle Pandoc-binæren; se tools/doc-builder.json')
DOCS=ROOT/'docs'
GEN=DOCS/'generated'
GEN.mkdir(exist_ok=True)

from documentation_metadata import sync_document_sources, build_interface_reference, build_requirement_history
sync_document_sources(ROOT)
build_interface_reference(ROOT)
build_requirement_history(ROOT)

# Minimal YAML-front-matter parser for scalar metadata used by active docs.
def frontmatter(path):
    text=path.read_text(encoding='utf-8')
    meta={}
    if text.startswith('---\n'):
        end=text.find('\n---\n',4)
        if end!=-1:
            for line in text[4:end].splitlines():
                if ':' in line:
                    k,v=line.split(':',1)
                    meta[k.strip()]=v.strip().strip('"\'')
    h=re.search(r'^#\s+(.+)$',text,re.M)
    meta.setdefault('title',h.group(1).strip() if h else path.stem)
    return meta,text

active=sorted(p for p in DOCS.glob('*.md'))
index=[]
for p in active:
    m,_=frontmatter(p)
    index.append({'file':p.name,**m})
(GEN/'document-index.json').write_text(json.dumps({'generated_from':'docs/*.md','documents':index},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

# Requirements are normative Markdown; this is a generated query/traceability surface.
reqs=[]
for p in active:
    _,text=frontmatter(p)
    for lineno,line in enumerate(text.splitlines(),1):
        if not re.match(r'^\|\s*REQ-[A-Z]+-\d+\s*\|',line):
            continue
        cells=[c.strip() for c in line.strip().strip('|').split('|')]
        if len(cells)>=3:
            rid,status=cells[0],cells[1]
            requirement=cells[-1]
            reqs.append({'id':rid,'status':status,'requirement':requirement,'source':p.name,'line':lineno})
all_tests='\n'.join(p.read_text(encoding='utf-8',errors='ignore') for p in (ROOT/'tests').rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix in {'.py','.js','.sh','.json','.md','.sql'})
for r in reqs:
    r['test_references']=len(re.findall(rf'(?<![A-Z0-9-]){re.escape(r["id"])}(?![A-Z0-9-])',all_tests))
(GEN/'requirements.json').write_text(json.dumps({'generated_from':['docs/01-*.md','docs/02-*.md','docs/03-*.md','docs/04-*.md'],'count':len(reqs),'requirements':reqs},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(GEN/'traceability.json').write_text(json.dumps({
    'generated_from':'requirements.json + tests/* textual REQ references',
    'note':'A textual test reference is evidence of explicit traceability, not proof that the requirement is fully verified.',
    'requirements_total':len(reqs),
    'with_explicit_test_reference':sum(1 for r in reqs if r['test_references']>0),
    'without_explicit_test_reference':[r['id'] for r in reqs if r['test_references']==0]
},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

# Stable decisions are generated from the normative decision table.
_,dtext=frontmatter(DOCS/'14-AKTIVE-BESLUTNINGER.md')
decs=[]
for lineno,line in enumerate(dtext.splitlines(),1):
    if not re.match(r'^\|\s*(?:ADR|DEC)-[A-Z0-9-]+\s*\|',line):
        continue
    c=[x.strip() for x in line.strip().strip('|').split('|')]
    if len(c)>=4:
        decs.append({'id':c[0],'decision':c[1],'rationale':c[2],'consequence':c[3],'source':'14-AKTIVE-BESLUTNINGER.md','line':lineno})
(GEN/'decisions.json').write_text(json.dumps({'generated_from':'docs/14-AKTIVE-BESLUTNINGER.md','count':len(decs),'decisions':decs},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

_,owtext=frontmatter(DOCS/'15-AAPENT-ARBEID.md')
ows=[]
for lineno,line in enumerate(owtext.splitlines(),1):
    if re.match(r'^\|\s*OPEN-\d+',line):
        c=[x.strip() for x in line.strip().strip('|').split('|')]
        if len(c)>=5: ows.append({'id':c[0],'type':c[1],'status':c[2],'subject':c[3],'exit_criterion':c[4],'source':'15-AAPENT-ARBEID.md','line':lineno})
(GEN/'open-work.json').write_text(json.dumps({'generated_from':'docs/15-AAPENT-ARBEID.md','items':ows},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

# Compact SQL INSERT parser used only to generate an inspection reference; SQL remains authority.
def split_sql_values(s):
    vals=[]; cur=''; inq=False; i=0
    while i<len(s):
        ch=s[i]
        if ch=="'":
            cur+=ch
            if inq and i+1<len(s) and s[i+1]=="'": cur+="'"; i+=2; continue
            inq=not inq; i+=1; continue
        if ch==',' and not inq:
            vals.append(cur.strip()); cur=''
        else: cur+=ch
        i+=1
    vals.append(cur.strip()); return vals

def scalar(v):
    v=v.strip()
    if v.upper()=='NULL': return None
    if v.startswith("'") and v.endswith("'"): return v[1:-1].replace("''", "'")
    if re.fullmatch(r'-?\d+',v): return int(v)
    if re.fullmatch(r'-?(?:\d+\.\d*|\d*\.\d+)',v): return float(v)
    return v

def parse_inserts(path):
    t=path.read_text(encoding='utf-8'); out={}
    pat=re.compile(r'INSERT\s+(?:IGNORE\s+)?INTO\s+([A-Za-z0-9_]+)\s*\(([^)]*)\)\s*VALUES\s*',re.I)
    for m in pat.finditer(t):
        table=m.group(1); cols=[x.strip() for x in m.group(2).split(',')]
        i=m.end(); depth=0; inq=False; stmt=''
        while i<len(t):
            ch=t[i]
            if ch=="'":
                stmt+=ch
                if inq and i+1<len(t) and t[i+1]=="'": stmt+="'"; i+=2; continue
                inq=not inq; i+=1; continue
            if not inq:
                if ch=='(': depth+=1
                elif ch==')': depth-=1
                elif ch==';' and depth==0: break
            stmt+=ch; i+=1
        # Cut optional ON DUPLICATE... outside tuple list.
        stmt=re.split(r'\bON\s+DUPLICATE\s+KEY\b',stmt,flags=re.I)[0]
        tuples=[]; j=0
        while j<len(stmt):
            if stmt[j]!='(': j+=1; continue
            start=j+1; d=1; q=False; j+=1
            while j<len(stmt) and d:
                if stmt[j]=="'":
                    if q and j+1<len(stmt) and stmt[j+1]=="'": j+=2; continue
                    q=not q
                elif not q:
                    if stmt[j]=='(': d+=1
                    elif stmt[j]==')': d-=1
                j+=1
            raw=stmt[start:j-1]
            parts=split_sql_values(raw)
            if len(parts)==len(cols): tuples.append(dict(zip(cols,map(scalar,parts))))
        out.setdefault(table,[]).extend(tuples)
    return out
seed=parse_inserts(ROOT/'sql/03-w3470-template-seed.sql')
source=parse_inserts(ROOT/'sql/23-measurement-source-seed.sql')
keep=['template_versions','template_defaults','template_biological_phases','template_biological_criteria','template_biological_criterion_threshold','template_biological_criterion_stability_window','template_process_steps','template_process_criteria','template_process_criterion_threshold','template_process_criterion_observation','template_process_criterion_stability_window','template_process_criterion_window_median_range','template_analysis_graphs','template_analysis_graph_series']
ref={'generated_from':['sql/03-w3470-template-seed.sql','sql/23-measurement-source-seed.sql'],'authority':'SQL/installed MariaDB; this file is generated inspection material','template':{k:seed.get(k,[]) for k in keep},'measurement_source_validation':{k:source.get(k,[]) for k in ['measurement_source_profiles','measurement_source_validation_rules','measurement_source_validation_rule_parameter_values']}}
(GEN/'w3470-rule-reference.json').write_text(json.dumps(ref,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

# Human-readable derivative of the same SQL extraction. It is generated, never edited manually.
def mdv(v):
    if v is None: return '—'
    return str(v).replace('|','\\|').replace('\n',' ')
def detail_map(rows,key):
    out={}
    for r in rows:
        out.setdefault(r.get(key),[]).append(r)
    return out
lines=['# W-34/70 – generert regelreferanse','',
       '> Generert av `tools/build_docs.py` fra SQL-seedene. SQL/installert MariaDB er autoritet; denne filen er inspeksjonsmateriale.','']
steps=seed.get('template_process_steps',[])
lines += ['## Prosesstrinn og historisk replay','', '| P | Aktiv | Historisk auto | Navn |', '|---|---:|---:|---|']
for r in steps:
    lines.append(f"| {mdv(r.get('process_id'))} | {mdv(r.get('enabled'))} | {mdv(r.get('historical_replay_auto_transition_allowed'))} | {mdv(r.get('name'))} |")
lines += ['','## Biologiske kriterier','', '| B | Kriterium | Metric | Modell | Rolle | Detalj |', '|---|---|---|---|---|---|']
bth=detail_map(seed.get('template_biological_criterion_threshold',[]),'criterion_id')
bst=detail_map(seed.get('template_biological_criterion_stability_window',[]),'criterion_id')
for r in seed.get('template_biological_criteria',[]):
    det=(bth.get(r.get('criterion_id'),[])+bst.get(r.get('criterion_id'),[]))
    lines.append(f"| {mdv(r.get('phase_id'))} | {mdv(r.get('label'))} | `{mdv(r.get('metric_id'))}` | `{mdv(r.get('model_id'))}` | {mdv(r.get('role_id'))} | `{mdv(det)}` |")
lines += ['','## Prosesskriterier','', '| P | Kriterium | Metric | Modell | Rolle | Detalj |', '|---|---|---|---|---|---|']
ptables=['template_process_criterion_threshold','template_process_criterion_observation','template_process_criterion_stability_window','template_process_criterion_window_median_range']
pdetails={}
for tn in ptables:
    for r in seed.get(tn,[]): pdetails.setdefault(r.get('criterion_id'),[]).append({'table':tn,**r})
for r in seed.get('template_process_criteria',[]):
    lines.append(f"| {mdv(r.get('process_id'))} | {mdv(r.get('label'))} | `{mdv(r.get('metric_id'))}` | `{mdv(r.get('model_id'))}` | {mdv(r.get('role_id'))} | `{mdv(pdetails.get(r.get('criterion_id'),[]))}` |")
lines += ['','## Analysegrafer','', '| Graf | Label | Forklaring | Enhet | Aktiv |', '|---|---|---|---|---:|']
for r in seed.get('template_analysis_graphs',[]):
    lines.append(f"| `{mdv(r.get('graph_id'))}` | {mdv(r.get('label'))} | {mdv(r.get('description'))} | {mdv(r.get('unit'))} | {mdv(r.get('enabled'))} |")
lines += ['','## Målekildevalidering','', '```json', json.dumps(ref['measurement_source_validation'],ensure_ascii=False,indent=2), '```','']
(GEN/'w3470-rule-reference.md').write_text('\n'.join(lines),encoding='utf-8')

# Structured p23 verification metadata is built from the same authoritative document/test sources.
subprocess.run([sys.executable, str(ROOT/'tools/build_verification_registry.py'),'--no-sql'], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)

# Render active Markdown to HTML. Rewrite links to active Markdown into generated HTML links.
render_sources=active+[GEN/'interface-reference.md',GEN/'w3470-rule-reference.md',GEN/'requirements-history.md']
for p in render_sources:
    out=p.with_suffix('.html')
    meta,_=frontmatter(p)
    subprocess.run(['pandoc',str(p),'-s','--from','gfm+yaml_metadata_block','--metadata','lang=nb-NO','--metadata',f'title={meta.get("title",p.stem)}','--css',('../assets/style.css' if p.parent==GEN else 'assets/style.css'),'-o',str(out)],cwd=DOCS,check=True)
    s=out.read_text(encoding='utf-8')
    s=re.sub(r'href="([^"#]+)\.md(#[^"]*)?"',lambda m:(f'href="{m.group(1)}.html{m.group(2) or ""}"' if (p.parent/(m.group(1)+'.md')).resolve() in [q.resolve() for q in render_sources] else m.group(0)),s)
    out.write_text(s,encoding='utf-8')
print(f'Generated {len(render_sources)} HTML documents from {len(active)} active sources and machine-readable documentation metadata in {GEN.relative_to(ROOT)}')
