'use strict';
// Actual MariaDB query → shipped Node-RED consumer → shared SVG, in an isolated DB.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto');
const mysql=require('mysql2/promise'),root=path.resolve(__dirname,'..');
const nodes=JSON.parse(fs.readFileSync(path.join(root,'nodered/flows.template.json'))),by=Object.fromEntries(nodes.map(n=>[n.id,n]));
const call=(id,msg={})=>new Function('msg','node','global',by[id].func)(msg,{error:e=>{throw Error(e)},warn:()=>{}},{get:()=>({})});
const checks=[],pass=s=>{checks.push(s);console.log('PASS',s);};
(async()=>{
 const db=await mysql.createConnection({host:'127.0.0.1',port:13310,user:'root',database:'ga_p24_release_test',dateStrings:true,multipleStatements:true});
 try{
  await db.query('SET timestamp=UNIX_TIMESTAMP(UTC_TIMESTAMP(3))');
  const execute=async m=>{const q=Array.isArray(m)?m[0]:m;assert.ok(q,JSON.stringify(m));return {...q,payload:(await db.query(q.topic,q.payload))[0]};};
  const query=async(id,msg={})=>execute(call(id,msg));
  const overview=async()=>JSON.parse(call('p20_overview_result',{_msgid:'r13-test',...(await query('p20_overview_query'))}).payload);
  const selected=call('p20_template_select',{payload:'w3470-standard@3.0'});await execute(selected);
  await db.query("UPDATE session_setup_draft SET pitch_time_mode='specified',pitched_at=UTC_TIMESTAMP(3)-INTERVAL 2 DAY,oxygenation_note='Graph regression fixture',batch_name='R13 grafregresjon' WHERE draft_key='current'");
  const start=call('p20_start_context_result',{...(await query('p20_start_guard'))});await execute(start);const sid=start[0].ga_session_id;
  const [session]=await db.query('SELECT pitched_at FROM sessions WHERE session_id=?',[sid]);
  const pitch=new Date(session[0].pitched_at+'Z').getTime(),stamp=t=>new Date(t).toISOString().replace('T',' ').slice(0,23);
  const rows=[];for(let i=0;i<=288;i++){if(i>110&&i<125)continue;const sg=1.05-i*0.00007;rows.push([sid,stamp(pitch+i*300000),3,sg-.0001,sg,sg,sg+.0001,7.8,8,8.2,.1,.2,.3,stamp(pitch+i*300000),stamp(pitch+i*300000)]);}
  await db.query('INSERT INTO measurements_5m(session_id,bucket_at,sample_count,sg_min,sg_mean,sg_median,sg_max,temperature_min_c,temperature_mean_c,temperature_max_c,pressure_min_bar,pressure_mean_bar,pressure_max_bar,created_at,updated_at) VALUES ?',[rows]);
  await db.query('INSERT INTO measurement_statistics_hourly(statistic_import_id,session_id,start_at,end_at,sg_min,sg_mean,sg_max,temperature_min_c,temperature_mean_c,temperature_max_c,created_at) VALUES(?,?,?,?,1.010,1.011,1.012,9,10,11,UTC_TIMESTAMP(3))',['r13-statistics',sid,stamp(pitch+30*3600000),stamp(pitch+31*3600000)]);
  await db.query("INSERT INTO biological_visits(visit_id,session_id,phase_id,created_at) VALUES('r13-b4',?,'B4',UTC_TIMESTAMP(3)); INSERT INTO biological_visit_revisions(visit_revision_id,visit_id,revision_no,started_at,timing_source,created_at) VALUES('r13-b4-revision','r13-b4',1,?,'regression_fixture',UTC_TIMESTAMP(3))",[sid,stamp(pitch+20*3600000)]);
  await db.query("INSERT INTO process_visits(visit_id,session_id,process_id,created_at) VALUES('r13-p2',?,'P2',UTC_TIMESTAMP(3)); INSERT INTO process_visit_revisions(visit_revision_id,visit_id,revision_no,started_at,timing_source,created_at) VALUES('r13-p2-revision','r13-p2',1,?,'regression_fixture',UTC_TIMESTAMP(3))",[sid,stamp(pitch+20*3600000)]);
  const correct=async(scope,owner,criterion,action,parameters,op)=>{
   const prefix=scope==='biological'?'bio':'process';
   const c=await query('p20_'+prefix+'_criterion_correction_context',{payload:{scope,owner_id:owner,criterion_id:criterion,action,parameters,confirmed:true,operation_id:op}});
   await execute(call('p20_'+prefix+'_criterion_correction_context_result',c));
   const data=await overview(),record=data.criterion_corrections[scope][owner+'/'+criterion];
   assert.equal(record.operation_id,op);assert.equal(record.action,action);assert.ok(['pending','not_current_candidate','evaluated'].includes(record.review_state));assert.ok(record.review_message);
   if(action==='override')for(const [k,v] of Object.entries(parameters))assert.equal(record.parameters[k],v);
   return data;
  };
  await correct('biological','B5','b5-attenuation','override',{minimum_value:99,maximum_value:null,maximum_age_minutes:null},'r13-b-unset');
  await correct('process','P3','p3-biological-phase','override',{minimum_value:3,maximum_value:null},'r13-p-unset');
  // Persist real evaluations and verify that unset never turns into numeric 0.
  for(const prefix of ['bio','process']){
   const context=await query('p20_'+prefix+'_eval_query');const result=call('p20_'+prefix+'_eval_result',{_msgid:'r13-'+prefix,...context});await execute(result);
   const table=prefix==='bio'?'biological_evaluation_criterion_parameter_values':'process_evaluation_criterion_parameter_values';
   const [facts]=await db.query('SELECT p.* FROM '+table+' p JOIN '+(prefix==='bio'?'biological_evaluations':'process_evaluations')+' e ON e.evaluation_id=p.evaluation_id WHERE e.session_id=? AND p.is_unset=1',[sid]);
   assert.ok(facts.length>=(prefix==='bio'?2:1),prefix+' must record unset facts');for(const f of facts)for(const k of ['real_value','integer_value','boolean_value','text_value'])assert.equal(f[k],null);
  }
  const previous=(await db.query('SELECT * FROM biological_evaluation_criterion_parameter_values WHERE is_unset=1'))[0];
  let pending=await correct('biological','B5','b5-attenuation','reset',{},'r13-b-reset');
  let biological=pending.biological.transition_evaluations.find(e=>e.evidence_kind==='current').criteria.find(c=>c.criterion_id==='b5-attenuation');
  assert.equal(biological.required,biological.template_required);assert.notEqual(biological.required,biological.evaluated_required);assert.equal(Number(biological.criterion_basis_current),0);assert.equal(biological.status,'not_evaluated');assert.equal(pending.criterion_corrections.biological['B5/b5-attenuation'].review_state,'pending');
  pending=await correct('process','P3','p3-biological-phase','reset',{},'r13-p-reset');
  const process=pending.process_guidance.condition_evaluations.find(c=>c.criterion_id==='p3-biological-phase');assert.equal(process.required,process.template_required);assert.equal(process.status,'not_evaluated');assert.equal(pending.process_guidance.readiness,'not_evaluated');assert.equal(Number(process.criterion_basis_current),0);assert.equal(pending.criterion_corrections.process['P3/p3-biological-phase'].review_state,'pending');
  assert.deepEqual((await db.query('SELECT * FROM biological_evaluation_criterion_parameter_values WHERE is_unset=1'))[0],previous,'correction cannot rewrite historical assessment parameters');
  for(const prefix of ['bio','process']){const context=await query('p20_'+prefix+'_eval_query');await execute(call('p20_'+prefix+'_eval_result',{_msgid:'r14-reset-'+prefix,...context}));}
  const reviewed=await overview();for(const [scope,key] of [['biological','B5/b5-attenuation'],['process','P3/p3-biological-phase']]){const receipt=reviewed.criterion_corrections[scope][key];assert.equal(receipt.review_state,'evaluated');assert.ok(receipt.evaluation_id);assert.match(receipt.review_message,/vurdert/);}
  pass('effective B/P requirements update immediately after reset; stale assessment blocks Next; old facts remain; receipt waits for exact revised evaluation');
  await correct('biological','B5','b5-attenuation','override',{minimum_value:70,maximum_value:99,maximum_age_minutes:30},'r13-b-numeric');
  pass('B and P: actual correction, explicit unset, actual evaluation history, reset and numeric bounds refresh without contract errors');
  await execute(call('p24r7_selection_write',{payload:{source_kind:'reference',reference_id:'ipl-synthetic-p17r12',interval_seconds:1800,window_hours:null,operation_id:'r13-compare'}}));
  const calculation=await query('p22_analysis_query');await execute(call('p22_analysis_result',calculation));
  const data=await overview();assert.equal(data.analysis.graphs.length,6);for(const key of ['time_markers','biological_markers','process_markers'])assert.ok(data.analysis[key].every(r=>r.session_id===sid),key+' must belong to this session');assert.equal(data.analysis.graphs.filter(g=>Number(g.show_in_overview)===1).length,3);
  const definitions=new Map(data.analysis.series_definitions.map(d=>[d.presentation_id,d]));const expanded=data.analysis.series.map(r=>({...definitions.get(r.presentation_id),...r}));
  for(const id of ['sg','temperature','pressure']){
   assert.ok(expanded.some(r=>r.graph_id===id&&r.series_id==='measured'));
   assert.ok(expanded.some(r=>r.graph_id===id&&r.series_id==='comparison'));
   assert.ok(expanded.some(r=>r.graph_id===id&&r.series_id==='manual'));
   assert.ok(Number(data.analysis.graphs.find(g=>g.graph_id===id).y_axis_max)>Number(data.analysis.graphs.find(g=>g.graph_id===id).y_axis_min));
  }
  assert.ok(expanded.some(r=>r.graph_id==='sg'&&Number(r.actual_value)===1.011&&r.basis_display.includes('HA langtidsstatistikk')));
  assert.ok(expanded.some(r=>r.series_id==='plan'));assert.ok(expanded.some(r=>r.series_id==='cooler'));assert.equal(data.analysis.reference_bands.length,1);
  const fixture={...data,analysis:{...data.analysis,series:expanded}};delete fixture.analysis.series_definitions;fs.writeFileSync(path.join(root,'tests/fixtures/p24r15-overview-regression.json.gz'),require('node:zlib').gzipSync(Buffer.from(JSON.stringify(fixture))));
  const allFonts=new Set(data.analysis.graphs.map(g=>g.date_font_size));assert.equal(allFonts.size,1);
  const classes=new Map(),sandbox={crypto:crypto.webcrypto,Uint32Array,Intl,Date,console,window:{},HTMLElement:class{attachShadow(){this.shadowRoot={innerHTML:'',querySelector:()=>null,querySelectorAll:()=>[]};}},customElements:{get:k=>classes.get(k),define:(k,c)=>classes.set(k,c)},setInterval:()=>1,clearInterval:()=>{},setTimeout};vm.createContext(sandbox);vm.runInContext(fs.readFileSync(path.join(root,'dashboard/gjaeringsassistent-card.js'),'utf8'),sandbox);
  const Card=classes.get('gjaeringsassistent-card'),card=new Card();card._hass={states:{}};card._overviewData=data;
  card._renderAnalysis();const html=card.shadowRoot.innerHTML;assert.equal((html.match(/viewBox="0 0 900 420"/g)||[]).length,6);assert.doesNotMatch(html,/NaN|undefined|mangler gyldig/);
  assert.ok(html.includes(data.analysis.time_markers[0].axis_label));assert.ok(html.includes('font:11px sans-serif'));assert.ok(html.includes('Forventet FG'));
  const graph=data.analysis.graphs.find(g=>g.graph_id==='sg');const svg=card._analysisChart(graph);assert.ok((svg.match(/class="analysis-line"/g)||[]).length>=3,'raw gap and comparison create independent segments');
  card._renderOverview();assert.equal((card.shadowRoot.innerHTML.match(/viewBox="0 0 900 280"/g)||[]).length,3);
  const moduleRender=require(path.join(root,'tools/report_module.js'));await db.query('SET @ga_report_now=UTC_TIMESTAMP(3),@ga_report_session=?',[sid]);const reportRows=[];
  for(const q of fs.readFileSync(path.join(root,'tools/report_queries.sql'),'utf8').split(';').filter(q=>q.trim())){const [sets]=await db.query(q);reportRows.push(...sets.filter(Array.isArray).flat().filter(r=>r._set));}
  const report=moduleRender(reportRows);assert.equal((report.match(/viewBox="0 0 900 420"/g)||[]).length,6);assert.doesNotMatch(report,/NaN|undefined/);assert.ok(report.includes('font:11px sans-serif'));
  const direct=new Function(fs.readFileSync(path.join(root,'tools/graph_renderer.js'),'utf8')+';return gaRenderAnalysisSvg;')();
  const graphSvg=direct({graph,latest:data.analysis.latest,series:data.analysis.series,definitions:data.analysis.series_definitions,timeMarkers:data.analysis.time_markers,axisTicks:data.analysis.axis_ticks,requirements:data.analysis.requirements,biology:data.analysis.biological_markers,process:data.analysis.process_markers,gaps:data.measurement_gaps,referenceBands:data.analysis.reference_bands});assert.ok(html.includes(graphSvg));assert.ok(report.includes(graphSvg));
  const bad={...graph,canvas_width:null};assert.throws(()=>direct({graph:bad,series:[],definitions:[]}),/presentasjonspolicy/);
  pass('all six actual SQL graphs share geometry and typography; manual points, plans, FG band, gaps and real comparison render identically in dashboard/report');
  await execute(call('p24r7_selection_write',{payload:{source_kind:'reference',reference_id:'ipl-synthetic-p17r12',interval_seconds:1800,window_hours:24,operation_id:'r13-short-window'}}));
  const short=await overview();assert.ok(short.analysis.graphs.every(g=>new Date(g.x_axis_started_at+'Z').getTime()>pitch));
  const [fullRange]=await db.query("SELECT * FROM v_graph_definitions WHERE session_id=? AND render_scope='report'",[sid]);
  assert.equal(fullRange.length,6);assert.ok(fullRange.every(g=>new Date(g.x_axis_started_at+'Z').getTime()===pitch));
  const [fullPoints]=await db.query("SELECT COUNT(*) n FROM v_graph_raw_series WHERE session_id=? AND series_id='measured' AND sample_at<?",[sid,short.analysis.graphs[0].x_axis_started_at]);assert.ok(fullPoints[0].n>0);
  const [fullDates]=await db.query("SELECT COUNT(*) n FROM v_graph_time_markers WHERE session_id=? AND render_scope='report' AND marker_at<?",[sid,short.analysis.graphs[0].x_axis_started_at]);assert.ok(fullDates[0].n>0);
  await execute(call('p24r7_selection_write',{payload:{source_kind:'reference',reference_id:'ipl-synthetic-p17r12',interval_seconds:1800,window_hours:null,operation_id:'r13-full-window'}}));
  pass('report retains full measurements and dates while dashboard uses the selected last-24-hour window');
  const bStyles=card._criterionHandlingStyles();assert.ok(bStyles.includes('.criterion-handling'));card._renderBiology();assert.ok(card.shadowRoot.innerHTML.includes(bStyles));card._renderProcess();assert.ok(card.shadowRoot.innerHTML.includes(bStyles));
  pass('B and P use the same correction/exception styles and separate handling cells');
  const core=require('../tools/sqlite_archive'),{DatabaseSync}=require('node:sqlite'),dir=fs.mkdtempSync(path.join(require('node:os').tmpdir(),'ga-r13-facts-'));
  try{
   const pair=await core.exportArchive(db,{session_id:sid,export_id:'r13-unset-snapshot',output_dir:dir});
   const current=await core.importArchive(db,{session:pair.session.path,template:pair.template.path},'r13-current-facts-import');
   for(const prefix of ['biological','process']){
    const table=prefix+'_evaluation_criterion_parameter_values',parent=prefix+'_evaluations';
    assert.ok((await db.query('SELECT COUNT(*) n FROM '+table+' p JOIN '+parent+' e ON e.evaluation_id=p.evaluation_id WHERE e.session_id=? AND p.is_unset=1 AND p.real_value IS NULL AND p.integer_value IS NULL AND p.boolean_value IS NULL AND p.text_value IS NULL',[current.session_id]))[0][0].n>0);
   }
   const legacyFile=path.join(dir,'legacy-facts.sqlite');fs.copyFileSync(pair.session.path,legacyFile);const old=new DatabaseSync(legacyFile);
   for(const prefix of ['biological','process']){
    const table=prefix+'_evaluation_criterion_parameter_values';
    // The old layout actually stored typed zero; format conversion must keep that fact as zero.
    old.exec('UPDATE '+table+" SET real_value=CASE WHEN data_type='real' THEN '0' ELSE NULL END,integer_value=CASE WHEN data_type='integer' THEN 0 ELSE NULL END,boolean_value=CASE WHEN data_type='boolean' THEN 0 ELSE NULL END,text_value=CASE WHEN data_type='text' THEN '' ELSE NULL END WHERE is_unset=1");
    old.exec('ALTER TABLE '+table+' DROP COLUMN is_unset');
   }old.close();
   const legacy=await core.preview(db,{session:legacyFile,template:pair.template.path});
   assert.ok(legacy.session.rows.biological_evaluation_criterion_parameter_values.every(r=>r.is_unset===0));
   assert.ok(legacy.session.rows.biological_evaluation_criterion_parameter_values.some(r=>Number(r.real_value)===0&&r.real_value!==null));
   await core.importArchive(db,{session:legacyFile,template:pair.template.path},'r13-old-facts-import');
   const bad=new DatabaseSync(legacyFile);bad.exec('UPDATE biological_evaluation_criterion_parameter_values SET real_value=NULL,integer_value=NULL,boolean_value=NULL,text_value=NULL');bad.close();
   await assert.rejects(core.preview(db,{session:legacyFile,template:pair.template.path}),/ugyldig verdi/);
   pass('SQLite preserves explicit unset history; old typed-zero history remains zero; missing legacy facts reject');
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
  await db.query("INSERT INTO session_lifecycle_events(lifecycle_event_id,session_id,lifecycle,occurred_at,note,operation_id,created_at) VALUES('r13-graph-end',?,'completed',UTC_TIMESTAMP(3),'Test','r13-graph-end',UTC_TIMESTAMP(3)); INSERT INTO session_release_events(release_event_id,session_id,released_at,operation_id,created_at) VALUES('r13-graph-release',?,UTC_TIMESTAMP(3),'r13-graph-release',UTC_TIMESTAMP(3))",[sid,sid]);
  assert.ok((await db.query("SELECT COUNT(*) n FROM v_graph_time_markers WHERE session_id=? AND render_scope='report'",[sid]))[0][0].n>0,'completed/released reports retain their date labels');
  fs.writeFileSync(path.join(root,'verification/p24r15-graph-regression.json'),JSON.stringify({application_version:fs.readFileSync(path.join(root,'VERSION'),'utf8').trim(),server_version:(await db.query('SELECT VERSION() v'))[0][0].v,status:'pass',checks,target_ha_uat:'not_run'},null,2)+'\n');
 }finally{await db.end();}
})().catch(e=>{console.error(e);process.exitCode=1;});
