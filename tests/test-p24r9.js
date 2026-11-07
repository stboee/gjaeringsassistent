'use strict';
// TEST-FUNC-016: regressions from the r8 user report, plus DB-backed renderer inputs.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),zlib=require('node:zlib'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..'),flow=JSON.parse(fs.readFileSync(path.join(root,'nodered/flows.template.json'))),by=Object.fromEntries(flow.map(n=>[n.id,n]));
const call=(id,msg)=>new Function('msg','node',by[id].func)(msg,{error:e=>{throw Error(e)},warn:()=>{}});
const command={source_kind:'reference',reference_id:'gyllen-pils-20260925',interval_seconds:1800,window_hours:null,operation_id:'r9-selected'};
const wrappers=[c=>c,c=>({data:c}),c=>({event:c}),c=>({event:{data:c}})];
for(const wrap of wrappers){
  assert.deepEqual(call('p24r7_selection_write',{payload:wrap(command)}).payload,['reference',command.reference_id,null,1800,null,command.operation_id]);
  assert.deepEqual(call('p24r7_selection_write',{payload:wrap({profile_id:command.reference_id,operation_id:'r9-demo'})}).payload,[command.reference_id,'r9-demo']);
}
const g={initial_import:false,statistics_required:false,statistics_start:'2026-10-01T00:00:00Z',import_start:'2026-10-01T01:00:00Z',import_end:'2026-10-01T02:00:00Z',sg_entity_id:'sensor.sg',temperature_entity_id:'sensor.temp',rssi_entity_id:'sensor.rssi'};
const history={entityId:'sensor.sg',startDate:g.import_start,endDate:g.import_end};
let out=call('p24r7_statistics_request',{ga_ingest:g,payload:history,ga_hourly_statistics:{old:'snapshot'}});
assert.equal(out[0],null);assert.equal(out[1].payload,history);assert.ok(!('ga_hourly_statistics' in out[1]));
for(const flags of [{initial_import:true,statistics_required:false},{initial_import:false,statistics_required:true}]){
  out=call('p24r7_statistics_request',{ga_ingest:{...g,...flags},payload:history});assert.equal(out[1],null);assert.equal(out[0].payload.data.start_time,g.statistics_start);
  const restored=call('p24r7_statistics_result',{...out[0],ga_hourly_statistics:{'sensor.sg':[]}});assert.equal(restored[0].payload,history);assert.equal(restored[1].ga_event.event_type,'issue_cleared');
}
assert.deepEqual(by.p24r7_statistics_request.wires,[['p24r7_statistics_api'],['p21_live_get_history']]);
const evidence=JSON.parse(fs.readFileSync(path.join(root,'verification/p24r9-runtime-regression.json')));assert.equal(evidence.status,'pass');assert.ok(evidence.comparison_points>0);
const rows=evidence.corrected_requirements;assert.ok(rows.some(r=>r.owner_type==='biology')&&rows.some(r=>r.owner_type==='process'));assert.ok(rows.every(r=>r.minimum_value!==null&&r.maximum_value!==null&&r.met_at));
const fixture=JSON.parse(zlib.gunzipSync(fs.readFileSync(path.join(__dirname,'fixtures/p24r15-overview-regression.json.gz'))));
const graph=fixture.analysis.graphs.find(g=>g.graph_id===rows[0].graph_id);assert.ok(graph);
const sets=[['clock',[{database_now:'2026-10-10T01:00:04Z'}]],['summary',[{...fixture.session,session_id:'r9-criteria',lifecycle:'active'}]],['graph_selection',[evidence.graph_selection]],['comparison_series',evidence.comparison_example.map(r=>({...r,at:r.bucket_at,sg:r.sg_median,temperature_c:r.temperature_mean_c}))],['analysis_graphs',fixture.analysis.graphs],['analysis_series',fixture.analysis.series],['analysis_reference_bands',fixture.analysis.reference_bands],['analysis_axis_ticks',fixture.analysis.axis_ticks],['analysis_time_markers',fixture.analysis.time_markers],['analysis_requirements',rows]];
sets.push(['process_guidance',[{readiness:'not_evaluated',trigger_summary:'Venter'}]],['runtime_presentation',[{elapsed_hours:0,active_phase_elapsed_hours:0,yeast:'W3470',attention:0}]]);
const overview=JSON.parse(call('p20_overview_result',{_msgid:'r9',payload:sets.map(([k,rs])=>rs.map(r=>({_set:k,...r})))}).payload);
assert.equal(overview.graph_selection.operation_id,evidence.graph_selection.operation_id);assert.equal(overview.comparison_series.length,3);assert.deepEqual(overview.analysis.requirements,rows);
class Shadow{constructor(){this.innerHTML='';this.one=new Map();}querySelector(k){return this.one.get(k)||null;}querySelectorAll(){return [];}}
const classes=new Map(),ctx={crypto:crypto.webcrypto,Uint32Array,Intl,Date,console,window:{},HTMLElement:class{attachShadow(){this.shadowRoot=new Shadow();}},customElements:{get:k=>classes.get(k),define:(k,c)=>classes.set(k,c)},setInterval:()=>1,clearInterval:()=>{},setTimeout};vm.createContext(ctx);vm.runInContext(fs.readFileSync(path.join(root,'dashboard/gjaeringsassistent-card.js'),'utf8'),ctx);
const c=new (classes.get('gjaeringsassistent-card'))();c._config.view='analysis';c._overviewData=overview;c._hass={states:{}};c._renderAnalysis();for(const r of rows)assert.ok(c.shadowRoot.innerHTML.includes(r.requirement_display),'card displays current DB requirement label');
const report=call('p22_active_report_result',{_msgid:'test-report',payload:[[{_set:'clock',database_now:'2026-10-10T01:00:04Z',generated_display:'10.10.2026'}],[{_set:'summary',session_id:'r9-criteria'}],[{_set:'session',session_id:'r9-criteria',batch_name:'R9 DB-backed regression'}],...sets.filter(([k])=>k.startsWith('analysis_')).map(([k,rs])=>rs.map(r=>({_set:k,...r})))]});
for(const r of rows)assert.ok(report.payload.includes(r.requirement_display),'shared report displays current DB requirement label');
assert.doesNotMatch(c.shadowRoot.innerHTML,/NaN|undefined/);assert.doesNotMatch(report.payload,/NaN|undefined/);
console.log('RESULT: PASS – r9 four event envelopes, live/statistics routing, real DB selection/comparison, corrected card/shared-report requirements');

(async()=>{
  // Optional process fields must reach the runtime as unset, just like biology.
  for(const [method,scope,group] of [['_sendBioCorrection','biological','biological'],['_sendProcessCorrection','process','process']]){
    let sent;const box={dataset:{ownerId:'owner',criterionId:'criterion'},querySelector:k=>k==='.criterion-correction-confirm'?{checked:true}:null,querySelectorAll:()=>[{dataset:{kind:'real',param:'minimum_value'},value:'1.25'},{dataset:{kind:'real',param:'maximum_value'},value:''}]};
    c._commandAcquire=()=>true;c._renderBiology=()=>{};c._renderProcess=()=>{};
    c._hass.callApi=async(method,url,data)=>{sent=data;};
    c._refreshOverviewUntil=async pred=>{assert.equal(pred({criterion_corrections:{[group]:{'owner/criterion':{operation_id:'other-command'}}}}),false);return pred({criterion_corrections:{[group]:{'owner/criterion':{operation_id:sent.operation_id}}}});};
    await c[method](box,'override');assert.equal(sent.scope,scope);assert.equal(sent.parameters.maximum_value,null);assert.equal(sent.parameters.minimum_value,1.25);assert.ok(sent.operation_id);
  }
  const demo=new (classes.get('gjaeringsassistent-card'))();demo._config.view='demo';demo._hass={states:{}};demo._overviewData={demo_options:[{profile_id:'gyllen-pils-20260925',name:'2026-09-25 Gyllen pils'}],demo_selection:{profile_id:'gyllen-pils-20260925',selection_seq:1}};
  let onChange,sent;demo.shadowRoot.one.set('.demo-profile',{addEventListener:(event,cb)=>{onChange=cb;}});demo.shadowRoot.one.set('.demo-start',{disabled:false,addEventListener:()=>{}});
  demo._hass.callApi=async(method,url,data)=>{sent=data;assert.equal(demo._selectionPending,true);await demo._loadOverview();};
  demo._refreshOverviewUntil=async pred=>{assert.equal(pred({demo_selection:{selection_seq:100,operation_id:'other-user'}}),false);return pred({demo_selection:{operation_id:sent.operation_id}});};
  demo._renderDemo();await onChange({target:{value:'gyllen-pils-20260925'}});assert.equal(demo._selectionPending,false);assert.ok(!demo._selectionStatus);
  console.log('RESULT: PASS – r9 optional B/P inputs, exact criterion/demo command acknowledgements and pending refresh');
})().catch(error=>{console.error(error);process.exitCode=1;});
