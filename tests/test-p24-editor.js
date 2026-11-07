'use strict';
// Regression for input loss during HA/read-model refresh. A small DOM adapter
// supplies focus and events; the shipped card methods and HTML run unchanged.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const root=path.resolve(__dirname,'..');
class Field extends EventTarget {
  constructor(value='',dataset={},tag='input'){super();this.value=value;this.dataset=dataset;this.tag=tag;}
  matches(){return ['input','textarea','select'].includes(this.tag);}
  input(value){this.value=value;this.dispatchEvent(new Event('input'));}
}
class Shadow {
  constructor(){this.html='';this.writes=0;this.activeElement=null;this.one=new Map();this.all=new Map();}
  set innerHTML(value){this.html=value;this.writes++;}
  get innerHTML(){return this.html;}
  querySelector(selector){return this.one.get(selector)||null;}
  querySelectorAll(selector){return this.all.get(selector)||[];}
}
const timers=[],registered=new Map(),sandbox={Intl,Date,structuredClone,console,window:{},
  HTMLElement:class{attachShadow(){this.shadowRoot=new Shadow();}},
  customElements:{get:id=>registered.get(id),define:(id,c)=>registered.set(id,c)},
  setInterval:()=>1,clearInterval:()=>{},setTimeout:(fn)=>{timers.push(fn);return timers.length;}};
vm.createContext(sandbox);vm.runInContext(fs.readFileSync(path.join(root,'dashboard/gjaeringsassistent-card.js'),'utf8'),sandbox);
const Card=registered.get('gjaeringsassistent-card');
const snapshot={mode:'draft',generated_at:'2026-10-06T17:00:00Z',document:{template_id:'unit',version_id:'unit@draft',status:'draft',name:'Fra DB',defaults:{},yeast:{},biology:{phases:[]},process:{slots:[]}}};
const copy=x=>structuredClone(x);
function card(){const c=new Card();c._config.view='template';c._hass={states:{},callApi:async()=>{}};c._templateData=copy(snapshot);c._templateDraft=copy(snapshot.document);return c;}
function deferred(){let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve};}
const response=data=>({ok:true,json:async()=>copy(data)});

(async()=>{
  let c=card(),name=new Field('Fra DB',{path:'name',kind:'string'});
  c.shadowRoot.all.set('.template-input,.criterion-role-edit,.criterion-label-edit,.criterion-param',[name]);
  c._renderTemplate();
  name.input('Nytt navn mens jeg skriver');
  assert.equal(c._templateDraft.name,name.value);assert.equal(c._templateDirty,true);
  // A request begun before input must not overwrite even after focus has left.
  c=card();name=new Field('Fra DB',{path:'name',kind:'string'});
  c.shadowRoot.all.set('.template-input,.criterion-role-edit,.criterion-label-edit,.criterion-param',[name]);c._renderTemplate();
  const original=c._templateDraft,pending=deferred();let reads=0;
  sandbox.fetch=async()=>{reads++;return pending.promise;};
  const load=c._loadTemplate();const writes=c.shadowRoot.writes;
  c.shadowRoot.activeElement=name;name.input('Behold min tekst');c.shadowRoot.activeElement=null;
  pending.resolve(response({...snapshot,mode:'none',document:null}));await load;
  assert.equal(c._templateDraft,original);assert.equal(c._templateDraft.name,'Behold min tekst');
  assert.equal(c._templateData.mode,'draft');assert.equal(c.shadowRoot.writes,writes);
  await c._loadTemplate();assert.equal(reads,1,'Dirty draft stops periodic refresh');
  // A delayed command refresh cannot erase edits made after that command.
  const before=c._templateEditRevision;name.input('Skrevet etter Lagre');await c._loadTemplate(true,before);assert.equal(reads,1);
  // Merely focusing a field, before its first character, also keeps the DOM.
  c=card();c.shadowRoot.activeElement=new Field();await c._loadTemplate();assert.equal(reads,1);
  c.shadowRoot.activeElement=null;const focusPending=deferred();sandbox.fetch=()=>focusPending.promise;
  const focusLoad=c._loadTemplate();const focusedWrites=c.shadowRoot.writes;c.shadowRoot.activeElement=new Field();
  focusPending.resolve(response(snapshot));await focusLoad;assert.equal(c.shadowRoot.writes,focusedWrites);
  c.shadowRoot.activeElement=null;sandbox.fetch=async()=>response({...snapshot,document:{...snapshot.document,name:'Ny fra DB'}});
  await c._loadTemplate();assert.equal(c._templateDraft.name,'Ny fra DB');
  // Auxiliary creation/publication fields remain UI drafts across refresh.
  c=card();const id=new Field(),title=new Field(),label=new Field();
  c.shadowRoot.one.set('.new-template-id',id);c.shadowRoot.one.set('.new-template-name',title);c.shadowRoot.one.set('.publish-label',label);c._renderTemplate();
  id.input('my-lager');title.input('Min lager');label.input('4.1');c._renderTemplate();
  assert.match(c.shadowRoot.innerHTML,/value="my-lager"/);assert.match(c.shadowRoot.innerHTML,/value="Min lager"/);assert.match(c.shadowRoot.innerHTML,/value="4.1"/);
  // Explicit read-only refresh must preserve an unsaved document.
  c=card();c._templateDirty=true;c._templateDraft.name='Ulagret';await c._refreshTemplateBackend();
  assert.match(c._templateStatus,/Ulagrede endringer beholdes/);await timers.pop()();assert.equal(c._templateDraft.name,'Ulagret');
  // The manual and fallback download names both have a timestamp prefix.
  c=card();c._config.view='system';c._hass.callApi=async()=>{throw Error('Test event unavailable');};
  await c._exportTechnical({disabled:false});assert.match(c._technicalExportFilename,/^\d{8}T\d{9}-gjaeringsassistent-teknisk-status\.json$/);
  assert.match(c._technicalExportUrl,/teknisk-status-latest\.json/);
  assert.ok(c.shadowRoot.innerHTML.includes('download="'+c._technicalExportFilename+'"'));
  assert.match(c.shadowRoot.innerHTML,/class="latest-technical"[^>]+download="\d{8}T\d{9}-/);
  c=card();c._config.view='overview';c._config.title='Aktiv gjæring';
  c._overviewData={session:{session_id:'live'},report_summary:{batch_display:'Brygg 42',yeast_display:'W-34/70',pitched_display:'01.10.2026 22:00',elapsed_display:'144 timer siden pitch',og_volume_display:'1,0480 · 150 L',biology_display:'B6 · Stabil',phase_duration_display:'48 timer i fasen',process_display:'P8 · Modning',process_duration_display:'72 timer i prosesstrinnet',latest_tilt_sg_display:'1,0135',attenuation_display:'68,33 %',attenuation_basis_display:'Ordinær · fersk måletid',expected_attenuation_display:'80–84 %',expected_fg_display:'1,0077–1,0096',abv_now_display:'4,41 % · estimert',abv_basis_display:'Ordinær · fersk måletid',sg_rate_display:'0,00 SG-poeng/d',sg_rate_basis_display:'Ordinær · 289 målepunkter / 1440 min',stability_24h_display:'0,10 SG-poeng',stability_48h_display:'0,20 SG-poeng',next_process_display:'P9 · Venter',process_evaluated_display:'Vurdert 07.10.2026 10:05'},process_guidance:{reason:'Venter på bekreftelse'},series:[],biological_phases:[]};
  c._renderOverview();const overview=c.shadowRoot.innerHTML;
  for(const text of ['Brygg 42','W-34/70','ABV nå','4,41 % · estimert','SG-stabilitet · 24 t','SG-stabilitet · 48 t','0,00 SG-poeng/d','Vurdert 07.10.2026 10:05'])assert.ok(overview.includes(text));
  assert.equal((overview.match(/>Utgjæringsgrad</g)||[]).length,1);assert.doesNotMatch(overview,/undefined|NaN/);
  const dashboard=fs.readFileSync(path.join(root,'dashboard/gjaeringsassistent-dashboard.yaml'),'utf8'),fermentation=dashboard.split('  - title: Biologi')[0];
  assert.ok(fermentation.indexOf('view: report')>fermentation.indexOf('view: overview'));
  assert.ok(dashboard.indexOf('title: Korriger pitchtid')>dashboard.indexOf('  - title: Måleresultater'));assert.ok(dashboard.indexOf('title: Korriger pitchtid')<dashboard.indexOf('  - title: Template'));
  console.log('RESULT: PASS – input before blur, refresh races, focus, auxiliary forms and timestamp download names');
})().catch(e=>{console.error(e);process.exitCode=1;});
