'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),zlib=require('node:zlib'),crypto=require('node:crypto'),os=require('node:os'),child=require('node:child_process');
const root=path.resolve(__dirname,'..'),flow=JSON.parse(fs.readFileSync(path.join(root,'nodered/flows.template.json'))),by=Object.fromEntries(flow.map(n=>[n.id,n]));
const invoke=(id,msg)=>new Function('msg','node',by[id].func)(msg,{error:e=>{throw Error(e)},warn:()=>{}});
const pack=new Function(fs.readFileSync(path.join(root,'tools/presentation_payload.js'),'utf8')+';return gaPackAnalysisPresentation;')();
const original=JSON.parse(zlib.gunzipSync(fs.readFileSync(path.join(__dirname,'fixtures/p24r15-overview-regression.json.gz'))));
const packed={...original,schema_version:'2.3',application_version:fs.readFileSync(path.join(root,'VERSION'),'utf8').trim(),analysis:pack(original.analysis)};
const decoded=new Map(packed.analysis.series_definitions.map(x=>[x.presentation_id,x]));
assert.equal(packed.analysis.series.length,original.analysis.series.length);
for(let i=0;i<original.analysis.series.length;i++){
  const before=original.analysis.series[i],after={...decoded.get(packed.analysis.series[i].presentation_id),...packed.analysis.series[i]};
  for(const key of ['graph_id','series_id','sample_at','actual_value','range_min_value','range_max_value','segment_id','line_color','line_dasharray','actual_value_display','basis_display','label','band_model','band_description','band_opacity','render_mode'])assert.deepEqual(after[key],before[key],key);
}
const bytes=Buffer.from(JSON.stringify(packed)+'\n'),gzip=zlib.gzipSync(bytes);
assert.ok(bytes.length<4_000_000,'full attached dashboard must be under 4 MB without dropping points');
assert.ok(gzip.length<300_000);assert.deepEqual(zlib.gunzipSync(gzip),bytes);
const selection={source_kind:'reference',reference_id:'gyllen-pils-20260925',interval_seconds:1800,window_hours:null,operation_id:'r8-select'};
for(const payload of [selection,{data:selection},{event:{data:selection}}]){
  const msg=invoke('p24r7_selection_write',{payload});assert.equal(msg.ga_route,'dashboard_selection');assert.deepEqual(msg.payload,['reference',selection.reference_id,null,1800,null,'r8-select']);
}
const demo=invoke('p24r7_selection_write',{payload:{profile_id:'gyllen-pils-20260925',operation_id:'r8-demo'}});assert.deepEqual(demo.payload,['gyllen-pils-20260925','r8-demo']);
assert.throws(()=>invoke('p24r7_selection_write',{payload:{...selection,interval_seconds:17}}),/Ugyldig visningsintervall/);
assert.throws(()=>invoke('p24r7_selection_write',{payload:{...selection,operation_id:null}}),/operation_id/);
// A real shell round trip verifies quoting, rather than assuming JSON is shell escaping.
const request=JSON.stringify({stage_path:"/tmp/quote-'-$-`-test.json",target_path:'/tmp/out.json'});
const args=invoke('p24r8_publication_args',{ga_publication_args:request}).payload;
const received=child.execSync('node -e '+"'process.stdout.write(process.argv[1])' "+args,{encoding:'utf8'});assert.equal(received,request);
class Shadow{constructor(){this.html='';this.writes=0;this.one=new Map();this.all=new Map();}set innerHTML(v){this.html=v;this.writes++;}get innerHTML(){return this.html;}querySelector(q){return this.one.get(q)||null;}querySelectorAll(q){return this.all.get(q)||[];}}
const registered=new Map(),sandbox={crypto:crypto.webcrypto,Uint32Array,Intl,Date,console,window:{},HTMLElement:class{attachShadow(){this.shadowRoot=new Shadow();}},customElements:{get:k=>registered.get(k),define:(k,c)=>registered.set(k,c)},setInterval:()=>1,clearInterval:()=>{},setTimeout};
vm.createContext(sandbox);vm.runInContext(fs.readFileSync(path.join(root,'dashboard/gjaeringsassistent-card.js'),'utf8'),sandbox);
const Card=registered.get('gjaeringsassistent-card');
function card(view,data=packed){const c=new Card();c._config.view=view;c._hass={states:{}};c._overviewData=data;return c;}
let c=card('overview',packed);c._renderOverview();assert.match(c.shadowRoot.innerHTML,/Specific gravity/);assert.doesNotMatch(c.shadowRoot.innerHTML,/Henter status/);assert.match(c.shadowRoot.innerHTML,/HA langtidsstatistikk/);
c=card('analysis');c._renderAnalysis();for(const title of ['Specific gravity','Temperatur','Trykk'])assert.ok(c.shadowRoot.innerHTML.includes(title));assert.match(c.shadowRoot.innerHTML,/0 0 900 420/);assert.doesNotMatch(c.shadowRoot.innerHTML,/NaN|undefined/);
c=card('overview',{...packed,measurement_source_labels:[]});c._analysisChart=()=>{throw Error('Injected render failure');};const priorConsole=sandbox.console;sandbox.console={...console,error:()=>{}};c._render();assert.match(c.shadowRoot.innerHTML,/Kan ikke vise kortet: Injected render failure/);sandbox.console=priorConsole;
const {publishPayload}=require(path.join(root,'tools/publish_payload.js')),temp=fs.mkdtempSync(path.join(os.tmpdir(),'r8-publish-')),publicRoot=path.join(temp,'public'),stageRoot=path.join(temp,'staged');fs.mkdirSync(publicRoot);fs.mkdirSync(stageRoot);
function publish(data,name,extra={}){const stage_path=path.join(stageRoot,name+'.json');fs.writeFileSync(stage_path,JSON.stringify(data));return publishPayload({stage_path,target_path:path.join(publicRoot,name+'.json'),...extra},{publicRoot,stageRoot});}
const published=publish(packed,'fermentation-overview');assert.equal(published.status,'ok');assert.deepEqual(zlib.gunzipSync(fs.readFileSync(path.join(publicRoot,'fermentation-overview.json.gz'))),fs.readFileSync(path.join(publicRoot,'fermentation-overview.json')));
// Transport-only fixture: exercise the actual source-settings result node all
// the way into the shared publisher. UI/SQL tests alone missed this boundary.
const sourceData={schema_version:'1.0',source_profile_id:'transport-fixture',fields:[],transport_note:"Bevar øæå og ' i transporten"};
const sourceResult=invoke('source_settings_result_v1',{_msgid:'source-publication-test',ga_source_action:'read',payload:[[{payload:JSON.stringify(sourceData)}]]})[0];
const sourceJob=JSON.parse(sourceResult.ga_publication_args);
assert.deepEqual(Object.keys(sourceJob).sort(),['stage_path','target_path']);
assert.equal(sourceJob.stage_path,sourceResult.filename);assert.equal(sourceJob.target_path,'/data/gjaeringsassistent/ha-public/source-settings.json');
assert.ok(by.source_settings_result_v1.wires[0].includes('source_settings_staging_file_v1'));
assert.ok(by.source_settings_staging_file_v1.wires[0].includes('source_settings_publication_args_v1'));
assert.ok(by.source_settings_publication_args_v1.wires[0].includes('source_settings_publish_v1'));
assert.ok(by.source_settings_publish_v1.wires[0].includes('p24r8_publication_result'));
assert.ok(by.source_settings_publish_v1.wires[1].includes('p24r8_publication_stderr'));
const sourceQuoted=invoke('source_settings_publication_args_v1',{ga_publication_args:request}).payload;
assert.equal(sourceQuoted,args,'source settings must use the shared, tested shell-argument contract');
assert.equal(child.execSync('node -e '+"'process.stdout.write(process.argv[1])' "+sourceQuoted,{encoding:'utf8'}),request);
// Redirect only filesystem roots for the isolated test, after validating the
// production argument names and exact filename. No domain data are rewritten.
sourceJob.stage_path=path.join(stageRoot,path.basename(sourceJob.stage_path));sourceJob.target_path=path.join(publicRoot,path.basename(sourceJob.target_path));
fs.writeFileSync(sourceJob.stage_path,sourceResult.payload);
const sourcePublished=publishPayload(sourceJob,{publicRoot,stageRoot});assert.equal(sourcePublished.status,'ok');
const sourceBytes=fs.readFileSync(sourceJob.target_path);assert.deepEqual(JSON.parse(sourceBytes),sourceData);
assert.deepEqual(zlib.gunzipSync(fs.readFileSync(sourceJob.target_path+'.gz')),sourceBytes);assert.equal(fs.existsSync(sourceJob.stage_path),false);
assert.throws(()=>invoke('p24r8_publication_result',{payload:JSON.stringify({status:'error',error_message:'Injected source publication failure'})}),/Datapublisering feilet/);
assert.throws(()=>invoke('p24r8_publication_stderr',{payload:'Injected source stderr'}),/Datapublisering/);
assert.equal(invoke('p24r8_publication_result',{payload:JSON.stringify(sourcePublished)}),null);
publish({application_version:packed.application_version},'summary',{diagnostics_level:'summary'});let report=JSON.parse(fs.readFileSync(path.join(publicRoot,'summary.json')));assert.equal(report.frontend_diagnostics.collections.analysis_points,packed.analysis.series.length);assert.ok(!('published_payload' in report.frontend_diagnostics));
publish({application_version:packed.application_version},'full',{diagnostics_level:'full'});report=JSON.parse(fs.readFileSync(path.join(publicRoot,'full.json')));assert.deepEqual(report.frontend_diagnostics.published_payload,packed);
assert.throws(()=>publishPayload({stage_path:'/outside/stage.json',target_path:path.join(publicRoot,'outside.json')},{publicRoot,stageRoot}),/publiseringssti/);
(async()=>{
  // Another user's newer sequence must not count as acknowledgement of this command.
  c=card('analysis');const reference={addEventListener:()=>{},value:'gyllen-pils-20260925',selectedOptions:[{dataset:{kind:'reference'}}]},window={addEventListener:()=>{},value:''},interval={addEventListener:()=>{},value:'1800'};c.shadowRoot.one.set('.graph-reference',reference);c.shadowRoot.one.set('.graph-window',window);c.shadowRoot.one.set('.graph-interval',interval);c.shadowRoot.all.set('.graph-controls select',[reference,window,interval]);
  let sent,reads=0;c._hass.callApi=async(method,url,data)=>{sent=data;invoke('p24r7_selection_write',{payload:data});await c._loadOverview();assert.equal(c.shadowRoot.writes,0,'periodic refresh does not reset a pending selection');};
  sandbox.fetch=async()=>({ok:true,json:async()=>({...packed,graph_selection:{...packed.graph_selection,selection_seq:2,operation_id:reads++>0?sent.operation_id:'other-user'}})});
  await c._sendGraphSelection();assert.equal(c._overviewData.graph_selection.operation_id,sent.operation_id);assert.equal(c._selectionPending,false);assert.ok(c.shadowRoot.writes>0);assert.ok(!c._selectionStatus);assert.doesNotMatch(c.shadowRoot.innerHTML,/Kan ikke vise kortet/);
  // An older HTTP request resolving after the command acknowledgement cannot undo it.
  c=card('analysis');let resolveOld,oldRequested=false;
  sandbox.fetch=async()=>{if(!oldRequested){oldRequested=true;return new Promise(resolve=>{resolveOld=resolve;});}return {ok:true,json:async()=>({...packed,graph_selection:{operation_id:'confirmed-new'}})};};
  const oldRequest=c._loadOverview();
  assert.equal(await c._refreshOverviewUntil(d=>d.graph_selection?.operation_id==='confirmed-new',500,1),true);
  resolveOld({ok:true,json:async()=>({...packed,graph_selection:{operation_id:'stale-old'}})});await oldRequest;
  assert.equal(c._overviewData.graph_selection.operation_id,'confirmed-new');
  // Independent publisher processes must leave one consistent pair and retain the newest snapshot.
  const script="const {publishPayload}=require(process.argv[1]);console.log(JSON.stringify(publishPayload(JSON.parse(process.argv[2]),JSON.parse(process.argv[3]))));";
  const jobs=Array.from({length:4},(_,i)=>{const stage_path=path.join(stageRoot,'parallel-'+i+'.json');fs.writeFileSync(stage_path,JSON.stringify({...packed,generated_at:'2026-10-09T20:00:0'+i+'Z',publication_test:i}));return {stage_path,target_path:path.join(publicRoot,'parallel.json')};});
  await Promise.all(jobs.map(job=>new Promise((resolve,reject)=>{const worker=child.spawn(process.execPath,['-e',script,path.join(root,'tools/publish_payload.js'),JSON.stringify(job),JSON.stringify({publicRoot,stageRoot})]);let output='',error='';worker.stdout.on('data',b=>output+=b);worker.stderr.on('data',b=>error+=b);worker.on('error',reject);worker.on('close',code=>{try{assert.equal(code,0,error);assert.equal(JSON.parse(output).status,'ok');resolve();}catch(e){reject(e);}});}))); 
  const parallelBytes=fs.readFileSync(path.join(publicRoot,'parallel.json'));assert.equal(JSON.parse(parallelBytes).publication_test,3);assert.deepEqual(zlib.gunzipSync(fs.readFileSync(path.join(publicRoot,'parallel.json.gz'))),parallelBytes);
  const stale=publish({...packed,generated_at:'2026-10-09T19:00:00Z'},'parallel');assert.equal(stale.skipped_older_snapshot,true);assert.deepEqual(fs.readFileSync(path.join(publicRoot,'parallel.json')),parallelBytes);
  // Full diagnostics is an explicit event field in the shipped card.
  c=card('system');c._hass.callApi=async(method,url,data)=>{assert.equal(data.diagnostics_level,'full');};await c._exportTechnical({disabled:false},'full');
  fs.rmSync(temp,{recursive:true,force:true});
  fs.writeFileSync(path.join(root,'verification/p24r8-presentation-regression.json'),JSON.stringify({application_version:packed.application_version,status:'pass',source_publication:{argument_contract:['stage_path','target_path'],json_and_gzip_readback:true,publication_errors_visible:true},source_fingerprints:Object.fromEntries(['nodered/flows.template.json','tools/publish_payload.js','tests/test-p24r8.js'].map(f=>[f,crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex')])),source_fixture:'tests/fixtures/p24r15-overview-regression.json.gz',original_bytes:19898199,compact_bytes:bytes.length,gzip_bytes:gzip.length,original_points:original.analysis.series.length,preserved_points:packed.analysis.series.length,presentation_definitions:packed.analysis.series_definitions.length,tests:['original overview rendering','dictionary field round-trip','larger shared graphs and measurement charts','direct/wrapped HA event inputs','exact operation acknowledgement, pending refresh and late HTTP reply','shell argument round-trip','actual source-settings producer/publisher arguments, JSON/gzip readback and visible errors','concurrent JSON/gzip publication and obsolete snapshot rejection','summary and full diagnostics','visible rendering failure']},null,2)+'\n');
  console.log('RESULT: PASS – r8 actual overview, lossless presentation projection, graph selection/refresh, larger graphs, gzip and diagnostics');
})().catch(e=>{console.error(e);process.exitCode=1;});
