'use strict';
// Real isolated MariaDB, shipped NR functions and shared dashboard/report paths.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto'),os=require('node:os');
const mysql=require('mysql2/promise'),root=path.resolve(__dirname,'..'),archive=require('../tools/sqlite_archive.js');
const by=Object.fromEntries(JSON.parse(fs.readFileSync(path.join(root,'nodered/flows.template.json'))).map(n=>[n.id,n]));
const call=(id,msg={})=>new Function('msg','node','global',by[id].func)(msg,{error:e=>{throw Error(e)},warn:()=>{}},{get:()=>({})});
const checks=[],pass=s=>{checks.push(s);console.log('PASS',s);},iso=t=>new Date(t).toISOString(),sqlTime=t=>iso(t).replace('T',' ').replace('Z','');
const config={host:'127.0.0.1',port:13310,user:'root',database:'ga_p24_release_test',dateStrings:true,supportBigNumbers:true,bigNumberStrings:true,multipleStatements:true};
(async()=>{const db=await mysql.createConnection(config);const dir=fs.mkdtempSync(path.join(os.tmpdir(),'ga-r15-history-'));try{
 const version=(await db.query('SELECT VERSION() version'))[0][0].version;assert.match(version,/^12\.3\.3-/);
 const execute=async m=>{const q=Array.isArray(m)?m[0]:m;assert.ok(q);return {...q,payload:(await db.query(q.topic,q.payload))[0]};};
 const query=async(id,msg={})=>execute(call(id,msg));
 const from=Date.parse('2026-09-25T20:00:00Z'),until=Date.parse('2026-09-27T20:07:00Z');
 const select=call('p20_template_select',{payload:'w3470-standard@3.0'});await execute(select);
 await db.query("UPDATE session_setup_draft SET is_demo=0,pitch_time_mode='specified',pitched_at=?,batch_name='R15 historisk fra–til' WHERE draft_key='current'",[sqlTime(from)]);
 assert.throws(()=>call('p24r15_historical_start_request',{payload:{}}),/eksplisitt sluttid/);
 const start=await query('p20_start_guard',{payload:{event:{data:{ends_at:iso(until)}}}});
 const write=call('p20_start_context_result',start);assert.ok(write[0]);await execute(write);
 const sid=write[0].ga_session_id;assert.ok(sid);
 assert.equal((await db.query('SELECT ended_at FROM session_history_windows WHERE session_id=?',[sid]))[0][0].ended_at,sqlTime(until));
 assert.equal((await db.query('SELECT domain_now FROM v_all_session WHERE session_id=?',[sid]))[0][0].domain_now,sqlTime(until));
 pass('ordinary start fields and first observation create a finite historical DB window');
 let chunks=0,last=null;
 while(true){
  const ctx=await query('p21_live_ingest_context_query',{ga_ingest_reason:chunks?'start_continue':'start'}),planned=call('p21_live_ingest_context_result',ctx);
  if(!planned[0]){assert.deepEqual(planned,[null,null,null]);break;}
  const req=planned[0],g=req.ga_ingest;assert.equal(g.is_historical,true);assert.equal(g.target_import_end,iso(until));
  const a=Date.parse(g.import_start),z=Date.parse(g.import_end);assert.ok(z<=until);assert.equal(req.payload.endDate,iso(z));
  const raw=[];
  for(let t=a+20000;t<z;t+=30000){const when=iso(t);raw.push({entity_id:g.sg_entity_id,state:String(1.05-(t-from)/86400000*.005),last_updated:when},{entity_id:g.temperature_entity_id,state:'12.0',last_updated:when},{entity_id:g.rssi_entity_id,state:'-75',last_updated:when},{entity_id:g.heartbeat_entity_id,state:when,last_updated:when});}
  // HA can include a state after the requested range. It must never enter the dataset.
  raw.push({entity_id:g.sg_entity_id,state:'1.199',last_updated:iso(until+60000)});
  req.payload=raw;req.ga_hourly_statistics={[g.sg_entity_id]:[{start:iso(from),end:iso(from+3600000),min:1.048,mean:1.049,max:1.05},{start:iso(until-60000),end:iso(until+3540000),mean:1.199}]};
  const prepared=call('p21_live_history_process',req);
  if(!chunks){
   await assert.rejects(()=>db.query('CALL ga_store_ingest_tx(?,?,?,?,?)',[sid,sqlTime(until+300000),g.gap_threshold_seconds,null,JSON.stringify({rows:[],hourly:[]})]),/DB-tidsrom/);
   assert.equal((await db.query('SELECT last_import_cutoff_at FROM session_measurement_sources WHERE session_id=?',[sid]))[0][0].last_import_cutoff_at,sqlTime(from));
  }
  const saved=await execute(prepared),result=call('p21_live_ingest_write_result',saved);
  if(z===until)assert.equal(result[5],null,'no new scheduled poll at the historical end');
  chunks++;last=req;assert.ok(chunks<10);
 }
 assert.equal(chunks,5);const [points]=await db.query('SELECT COUNT(*) n,MAX(bucket_at) last_at,MAX(sg_mean) max_sg FROM measurements_5m WHERE session_id=?',[sid]);assert.equal(Number(points[0].n),578);assert.equal(points[0].last_at,'2026-09-27 20:05:00.000');assert.ok(Number(points[0].max_sg)<1.1);
 assert.equal((await db.query('SELECT COUNT(*) n FROM measurement_statistics_hourly WHERE session_id=?',[sid]))[0][0].n,'1');
 const reboot=call('p21_live_ingest_context_result',await query('p21_live_ingest_context_query',{ga_ingest_reason:'startup'}));assert.deepEqual(reboot,[null,null,null]);
 assert.equal((await db.query('SELECT state FROM v_measurement_source_status'))[0][0].state,'HISTORISK');
 await db.query('UPDATE session_measurement_sources SET last_error=? WHERE session_id=?',['Kvalitetsavvisning i siste delbøtte',sid]);assert.equal((await db.query('SELECT state FROM v_session_start_status'))[0][0].state,'ready');await db.query('UPDATE session_measurement_sources SET last_error=NULL WHERE session_id=?',[sid]);
 pass('five bounded chunks, exact partial final bucket, hour boundary, late HA record rejection, failed-write retry basis and restart without live polling');
 const register=async(kind,owner,t)=>{const cmd=call('p24r15_historical_phase_query',{payload:{event:{data:{kind,owner_id:owner,started_at:iso(t),operation_id:`register-${kind}-${owner}`}}}});const r=(await execute(cmd)).payload;assert.equal(Number(r[0][0].correction_applied),1);};
 await register('biological','B2',from+6*3600000);await register('biological','B3',from+24*3600000);
 await register('process','P2',from+12*3600000);await register('process','P3',from+30*3600000);
 const [before]=await db.query("SELECT phase_id,visit_id,started_at,ended_at,duration_seconds,duration_display FROM v_biological_visit_timing WHERE session_id=? ORDER BY started_at",[sid]);
 assert.equal(before[0].ended_at,before[1].started_at);assert.equal(before[1].ended_at,before[2].started_at);assert.equal(before[2].ended_at,sqlTime(until));
 const b2=before[1].visit_id;
 const correct=async(kind,id,t,action='set')=>(await query('p20_bio_time_correction_query',{payload:{event:{data:{kind,target_id:id,action,timestamp:iso(t),operation_id:`correct-${crypto.randomUUID()}`}}}})).payload[0][0];
 assert.equal(Number((await correct('biological',b2,from+8*3600000)).correction_applied),1);
 const [after]=await db.query('SELECT phase_id,started_at,ended_at,duration_seconds FROM v_biological_visit_timing WHERE session_id=? ORDER BY started_at',[sid]);
 assert.equal(after[0].ended_at,sqlTime(from+8*3600000));assert.equal(Number(after[0].duration_seconds),8*3600);assert.equal(Number(after[1].duration_seconds),16*3600);
 assert.equal(Number((await correct('biological',b2,from+26*3600000)).correction_applied),0,'cannot cross next phase boundary');
 assert.equal(Number((await correct('biological',b2,from,'clear')).correction_applied),1);
 const p2=(await db.query("SELECT visit_id FROM process_visits WHERE session_id=? AND process_id='P2'",[sid]))[0][0].visit_id;
 assert.equal(Number((await correct('process',p2,from+14*3600000)).correction_applied),1);
 const [pt]=await db.query('SELECT process_id,started_at,ended_at,duration_seconds FROM v_process_visit_timing WHERE session_id=? ORDER BY started_at',[sid]);assert.equal(pt[0].ended_at,pt[1].started_at);assert.equal(Number(pt[0].duration_seconds),14*3600);assert.equal(Number(pt[1].duration_seconds),16*3600);
 assert.equal((await db.query('SELECT COUNT(*) n FROM biological_visit_revisions WHERE visit_id=?',[b2]))[0][0].n,'3');
 pass('manual missing B/P phases, shared neighboring boundary, both duration changes, chronological rejection, reset and append-only revisions');
 // Later actions continue to evaluate at the historical horizon.
 const bioCtx=await query('p20_bio_eval_query'),processCtx=await query('p20_process_eval_query');
 assert.equal(bioCtx.payload[0][0].database_now,sqlTime(until));assert.equal(processCtx.payload[0][0].database_now,sqlTime(until));
 const measurement1=call('p20_measurement_context_result',await query('p20_measurement_context_query'));await execute(measurement1);
 const measurement2=call('p20_measurement_context_result',await query('p20_measurement_context_query'));await execute(measurement2);
 assert.notEqual(measurement1[0].ga_measurement_saved.observation_id,measurement2[0].ga_measurement_saved.observation_id);
 assert.equal(measurement1[0].ga_measurement_saved.recorded_at,sqlTime(until));
 const firstObs=(await db.query("SELECT observation_id FROM observation_round_revisions WHERE session_id=? AND revision_reason='manual_measurement' ORDER BY created_at LIMIT 1",[sid]))[0][0].observation_id;
 await correct('observation',firstObs,from+17*3600000);
 assert.equal((await db.query('SELECT recorded_at FROM v_current_observation_revision WHERE observation_id=?',[firstObs]))[0][0].recorded_at,sqlTime(from+17*3600000));
 pass('frozen evaluation clock, distinct after-registered observations with historical measured_at and current audit time');
 const overview=()=>query('p20_overview_query').then(x=>JSON.parse(call('p20_overview_result',x).payload));
 let data=await overview();assert.equal(Number(data.session.is_historical),1);assert.equal(data.session.historical_ended_at,sqlTime(until));
 for(const g of data.analysis.graphs)assert.equal(Date.parse(g.x_axis_ended_at.replace(' ','T')+'Z'),until);
 const classes=new Map(),sandbox={crypto:crypto.webcrypto,Uint32Array,Intl,Date,console,window:{},HTMLElement:class{attachShadow(){this.shadowRoot={innerHTML:'',querySelector:()=>null,querySelectorAll:()=>[]};}},customElements:{get:k=>classes.get(k),define:(k,c)=>classes.set(k,c)},setInterval:()=>1,clearInterval:()=>{},setTimeout};vm.createContext(sandbox);vm.runInContext(fs.readFileSync(path.join(root,'dashboard/gjaeringsassistent-card.js'),'utf8'),sandbox);
 const Card=classes.get('gjaeringsassistent-card'),card=new Card();card._hass={states:{}};card._overviewData=data;card._config={};card._overviewHours=()=>{throw Error('Frontend must not calculate phase duration');};
 assert.doesNotThrow(()=>card._overviewBioStrip());card._renderBiology();for(const r of data.phase_durations.filter(x=>x.kind==='biological'))assert.ok(card.shadowRoot.innerHTML.includes(r.duration_display));
 card._renderProcess();for(const r of data.phase_durations.filter(x=>x.kind==='process'))assert.ok(card.shadowRoot.innerHTML.includes(r.duration_display));
 const summaryBefore=(await db.query('SELECT elapsed_display,phase_duration_display,process_duration_display FROM v_session_report_summary WHERE session_id=?',[sid]))[0];card._config={view:'startaction'};card._hass={states:{'sensor.gjaeringsassistent_livslop':{state:'configured'}}};card.shadowRoot.activeElement={matches:selector=>selector==='.historical-end'};let redraws=0;card._render=()=>redraws++;card.hass={states:{'sensor.gjaeringsassistent_livslop':{state:'configured'},'sensor.gjaeringsassistent_startstatus':{state:'idle'}}};assert.equal(redraws,0,'HA refresh preserves an unfinished end-time edit');
 const ends=data.analysis.graphs.map(x=>x.x_axis_ended_at);await db.query('SET timestamp=UNIX_TIMESTAMP(UTC_TIMESTAMP(3))+86400');data=await overview();assert.deepEqual(data.analysis.graphs.map(x=>x.x_axis_ended_at),ends);assert.deepEqual((await db.query('SELECT elapsed_display,phase_duration_display,process_duration_display FROM v_session_report_summary WHERE session_id=?',[sid]))[0],summaryBefore);await db.query('SET timestamp=0');
 pass('real overview and both cards render DB durations; all graph ends stay fixed when the DB wall clock advances');
 // Post-import assessment and exceptions must use the historical clock even though
 // the operator records them weeks later.
 await execute(call('p22_analysis_result',await query('p22_analysis_query')));
 await execute(call('p20_bio_eval_result',await query('p20_bio_eval_query')));
 await execute(call('p20_process_eval_result',await query('p20_process_eval_query')));
 const [evalTimes]=await db.query('SELECT MAX(evaluated_at) t FROM biological_evaluations WHERE session_id=? UNION ALL SELECT MAX(evaluated_at) t FROM process_evaluations WHERE session_id=?',[sid,sid]);assert.ok(evalTimes.every(x=>x.t===sqlTime(until)));
 const [eligible]=await db.query("SELECT e.evaluation_id,c.criterion_id FROM v_current_biological_candidate_evaluation e JOIN biological_evaluation_criteria c ON c.evaluation_id=e.evaluation_id JOIN session_biological_criteria sc ON sc.session_id=e.session_id AND sc.phase_id=e.candidate_phase_id AND sc.criterion_id=c.criterion_id WHERE e.session_id=? AND sc.exception_allowed=1 AND (c.met=0 OR c.valid=0) LIMIT 1",[sid]);
 assert.equal(eligible.length,1,'historical fixture has a blocked, operator-correctable criterion');
 const exReq=await query('p24_bio_exception_context',{payload:{event:{data:{...eligible[0],action:'register',exception_type:'akseptert_avvik',confirmed:true,note:'Historisk etterregistrert avvik',operation_id:'r15-historical-exception'}}}});
 const exWrite=call('p24_bio_exception_context_result',exReq);assert.ok(exWrite[0]);await execute(exWrite);
 await execute(call('p20_bio_eval_result',await query('p20_bio_eval_query')));
 assert.ok(Number((await db.query('SELECT COUNT(*) n FROM biological_evaluation_criteria c JOIN biological_criterion_exceptions x ON x.exception_id=c.applied_exception_id WHERE x.operation_id=?',['r15-historical-exception']))[0][0].n)>0);
 pass('actual post-import analyses and B/P assessments use the frozen horizon; a later recorded biological exception is applied');

 const end=call('p21_session_end_context_result',await query('p21_session_end_guard'));await execute(end);
 assert.equal((await db.query('SELECT lifecycle,completed_at FROM v_current_session WHERE session_id=?',[sid]))[0][0].completed_at,sqlTime(until));
 const pair=await archive.exportArchive(db,{session_id:sid,export_id:'r15-history-final',output_dir:dir});
 const preview=await archive.preview(db,{session:pair.session.path,template:pair.template.path});assert.equal(preview.session.rows.session_history_windows[0].ended_at,sqlTime(until));
 const report=fs.readFileSync(pair.report.path,'utf8');assert.ok(report.includes('Historisk gjæringsrapport'));assert.ok(fs.existsSync(pair.session.sha_path)&&fs.existsSync(pair.template.sha_path));
 const imported=await archive.importArchive(db,{session:pair.session.path,template:pair.template.path},'r15-history-reimport');assert.equal((await db.query('SELECT ended_at FROM session_history_windows WHERE session_id=?',[imported.session_id]))[0][0].ended_at,sqlTime(until));
 const [axes]=await db.query('SELECT x_axis_ended_at FROM v_report_graph_time_axis WHERE session_id=?',[imported.session_id]);assert.equal(axes[0].x_axis_ended_at,sqlTime(until));
 pass('completion uses historical end; SQLite pair, both SHA files, common report and reimport preserve the fixed window');
 fs.writeFileSync(path.join(root,'verification/p24r15-historical-regression.json'),JSON.stringify({application_version:fs.readFileSync(path.join(root,'VERSION'),'utf8').trim(),server_version:version,status:'pass',checks,chunks,measurement_count:Number(points[0].n),from:iso(from),until:iso(until),target_ha_uat:'not_run',test_sha256:crypto.createHash('sha256').update(fs.readFileSync(__filename)).digest('hex')},null,2)+'\n');
 console.log('RESULT: PASS – p24r15 historical import, phase boundaries, after-registration and SQLite export');
}finally{await db.end();fs.rmSync(dir,{recursive:true,force:true});}})().catch(e=>{console.error(e.code||'ASSERT',e.sqlMessage||e.stack);process.exitCode=1;});
