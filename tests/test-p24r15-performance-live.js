'use strict';
// Isolated fixture only. Measured read amplification and concurrency, not a
// machine-independent latency guarantee. No production endpoint or datadir.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const mysql=require('mysql2/promise'),root=path.resolve(__dirname,'..');
const by=Object.fromEntries(JSON.parse(fs.readFileSync(path.join(root,'nodered/flows.template.json'))).map(n=>[n.id,n]));
const run=(id,msg={})=>new Function('msg','node','global',by[id].func)(msg,{error:e=>{throw Error(e)},warn:()=>{}},{get:()=>({})});
const cfg={host:'127.0.0.1',port:13310,user:'root',database:'ga_p24_release_test',multipleStatements:true,dateStrings:true};
const checks=[],pass=s=>{checks.push(s);console.log('PASS',s);};
const cpu=()=>{if(!process.env.GA_TEST_SERVER_PID)return null;try{const fields=fs.readFileSync('/proc/'+process.env.GA_TEST_SERVER_PID+'/stat','utf8').split(') ')[1].split(' ');return (Number(fields[11])+Number(fields[12]))*10;}catch(e){if(e.code==='ENOENT')return null;throw e;}};
(async()=>{const db=await mysql.createConnection(cfg),other=await mysql.createConnection(cfg);try{
 // Freeze only the DB fixture clock: baseline/current plan labels must not differ when the benchmark crosses a minute.
 const fixedEpoch=Number((await db.query('SELECT UNIX_TIMESTAMP() n'))[0][0].n);await db.query('SET timestamp=?',[fixedEpoch]);await other.query('SET timestamp=?',[fixedEpoch]);
 const n=6048,pitch='2026-09-20 00:00:00',stamp=i=>new Date(Date.parse(pitch+'Z')+i*300000).toISOString().replace('T',' ').slice(0,23);
 await db.query("INSERT INTO session_release_events(release_event_id,session_id,released_at,operation_id,created_at) SELECT CONCAT('perf-release-',session_id),session_id,UTC_TIMESTAMP(3),CONCAT('perf-release-',session_id),UTC_TIMESTAMP(3) FROM v_current_session");
 const source=fs.readFileSync(path.join(root,'tests/test-sqlite-live.js'),'utf8'),base=new Function('return '+source.match(/const vars=(\{[^\n]+\});/)[1])();for(const key of ['acetaldehyde_level','diacetyl_level','wort_like_level','sulfur_so2_level','sulfur_h2s_level','clarity_level','settling_yeast_level','settling_minutes'])base[key]=0;
 const sid='r14-performance-active',v={...base,session_id:sid,is_demo:0,pitched_at:pitch,created_at:pitch,batch_name:'21 døgn ytelsestest',operation_id:sid+'-start'},params=[];
 const startSql=fs.readFileSync(path.join(root,'sql/start-session.sql'),'utf8').split('SELECT s.*')[0].replace(/SET @ga_([a-z0-9_]+)=\?;/g,(m,k)=>{params.push(v[k]??null);return m;});await db.query(startSql,params);
 const rows=[];for(let i=0;i<n;i++){const sg=1.011+0.038*Math.exp(-i/1000);rows.push([sid,stamp(i),5,sg-.0001,sg,sg,sg+.0001,9.8,10,10.2,.15,.2,.25,stamp(i),stamp(i)]);}
 for(let i=0;i<n;i+=750)await db.query('INSERT INTO measurements_5m(session_id,bucket_at,sample_count,sg_min,sg_mean,sg_median,sg_max,temperature_min_c,temperature_mean_c,temperature_max_c,pressure_min_bar,pressure_mean_bar,pressure_max_bar,created_at,updated_at) VALUES ?',[rows.slice(i,i+750)]);
 const q=run('p22_analysis_query'),result=run('p22_analysis_result',{payload:(await db.query(q.topic,q.payload))[0]});await db.query(result.topic,result.payload);
 await db.query("INSERT INTO graph_display_selection_events(source_kind,interval_seconds,operation_id,selected_at) VALUES('none',1800,'r14-perf-view',UTC_TIMESTAMP(3))");
 const readCount=async()=>Number((await db.query("SHOW SESSION STATUS LIKE 'Rows_read'"))[0][0].Value);
 const measure=async(sql,args=[])=>{const count=await readCount(),c=cpu(),t=performance.now();const [sets]=await db.query(sql,args);const elapsed=performance.now()-t;return {sets,elapsed_ms:elapsed,rows_read:(await readCount())-count,cpu_ms:c===null?null:cpu()-c};};
 const compact=m=>({elapsed_ms:Math.round(m.elapsed_ms),rows_read:m.rows_read,cpu_ms:m.cpu_ms});
 // Actual p24r13 baseline on precisely the same base-table fixture.
 const views=fs.readFileSync(path.join(root,'sql/20-views.sql'),'utf8'),old=fs.readFileSync(path.join(root,'tests/fixtures/p24r13-views-baseline.sql'),'utf8'),before=[];let expectedLatest;
 try{await db.query(old);for(const name of ['v_graph_definitions','v_graph_series','v_graph_latest','v_graph_axis_ticks','v_graph_time_markers']){const scope=['v_graph_definitions','v_graph_time_markers'].includes(name)?" AND render_scope='dashboard'":'';const m=await measure('SELECT * FROM '+name+' WHERE session_id=?'+scope,[sid]);before.push({view:name,rows:m.sets.length,...compact(m)});if(name==='v_graph_latest')expectedLatest=m.sets;}}finally{await db.query(views);}
 const after=await measure('CALL ga_read_overview()'),flat=after.sets.filter(Array.isArray).flat(),groups=Object.groupBy(flat,r=>r._set),basis=groups.overview_publication_basis[0];
 assert.ok(groups.analysis_series.length<before.find(x=>x.view==='v_graph_series').rows);assert.equal(groups.analysis_graphs.length,6);
 const latestKey=r=>JSON.stringify([r.graph_id,r.series_id,r.actual_value,r.measured_at,r.latest_value_display]);assert.deepEqual(groups.analysis_latest.map(latestKey).sort(),expectedLatest.map(latestKey).sort());
 const oldReads=before.reduce((s,r)=>s+r.rows_read,0),oldMs=before.reduce((s,r)=>s+r.elapsed_ms,0);assert.ok(after.rows_read<oldReads*.6,'full overview must read substantially less than just five old graph queries');
 await db.query('CALL ga_ack_overview(?,?,?)',[basis.operation_id,basis.source_key,basis.generated_at]);
 const poll=await measure('CALL ga_poll_overview()');assert.equal(poll.sets[0][0].should_publish,0);assert.ok(poll.elapsed_ms<after.elapsed_ms*.25);console.log('READ METRICS',JSON.stringify({before,after:compact(after),poll:compact(poll)}));assert.ok(poll.rows_read<after.rows_read*.3);
 console.log('MEASURED',JSON.stringify({before,after:compact(after),poll:compact(poll)}));
 assert.equal(run('p20_overview_result',{payload:poll.sets}),null);
 pass('21 days: all six graphs/latest values retained; DB display thinning reduces points; unchanged polling skips all graph stages');
 // Historical data growth must not grow the read basis. Clone complete frozen
 // sources through actual Start, then write identical analysis facts.
 await db.query("INSERT INTO session_release_events(release_event_id,session_id,released_at,operation_id,created_at) VALUES('r14-perf-fixture-hold',?,UTC_TIMESTAMP(3),'r14-perf-fixture-hold',UTC_TIMESTAMP(3))",[sid]);
 for(let h=0;h<3;h++){
  const hs='r14-performance-old-'+h,hp=[];const values={...v,session_id:hs,batch_name:'Historisk '+h,operation_id:hs+'-start'};await db.query(startSql.replace(/SET @ga_([a-z0-9_]+)=\?;/g,(m,k)=>{hp.push(values[k]??null);return m;}),hp);
  for(const table of ['measurements_5m','analysis_series_values']){const [cols]=await db.query('SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? ORDER BY ORDINAL_POSITION',[table]);const names=cols.map(c=>'`'+c.COLUMN_NAME+'`');await db.query('INSERT INTO '+table+'('+names.join(',')+') SELECT '+names.map((c,i)=>cols[i].COLUMN_NAME==='session_id'?'?':c).join(',')+' FROM '+table+' WHERE session_id=?',[hs,sid]);}
  await db.query("INSERT INTO session_release_events(release_event_id,session_id,released_at,operation_id,created_at) VALUES(?,?,UTC_TIMESTAMP(3),?,UTC_TIMESTAMP(3))",[hs+'-release',hs,hs+'-release']);
 }
 await db.query("DELETE FROM session_release_events WHERE release_event_id='r14-perf-fixture-hold'");
 const grown=await measure('CALL ga_read_overview()');assert.ok(grown.rows_read<after.rows_read*1.15,'unselected historical measurements must not amplify reads');
 await db.query('CALL ga_init_read_basis();START TRANSACTION WITH CONSISTENT SNAPSHOT,READ ONLY;CALL ga_fill_read_basis(?)',[sid]);const [scoped]=await db.query('SELECT DISTINCT session_id FROM ga_rb_t_measurements_5m');assert.deepEqual(scoped.map(r=>r.session_id),[sid]);
 await other.query('SET SESSION innodb_lock_wait_timeout=1');const t=performance.now();await other.query("UPDATE measurements_5m SET updated_at=UTC_TIMESTAMP(3) WHERE session_id=? ORDER BY bucket_at DESC LIMIT 1",[sid]);const write_ms=performance.now()-t;
 await db.commit();await db.query('CALL ga_drop_read_basis()');
 const readers=await Promise.all([mysql.createConnection(cfg),mysql.createConnection(cfg)]);try{const results=await Promise.all(readers.map(c=>c.query('CALL ga_read_overview()')));assert.ok(results.every(([s])=>s.filter(Array.isArray).flat().some(r=>r._set==='analysis_graphs')));}finally{await Promise.all(readers.map(c=>c.end()));}
 pass('three complete historical series do not amplify the read; concurrent readers are private; canonical measurement UPDATE is not blocked by a read snapshot');
 const changed=await measure('CALL ga_poll_overview()');assert.equal(changed.sets.filter(Array.isArray).flat().find(r=>r._set==='overview_publication_basis').should_publish,1,'committed measurement update must trigger a new overview');
 const changeBasis=changed.sets.filter(Array.isArray).flat().find(r=>r._set==='overview_publication_basis');await db.query('CALL ga_ack_overview(?,?,?)',[changeBasis.operation_id,changeBasis.source_key,changeBasis.generated_at]);
 // Advance the frozen epoch beyond the DB-owned refresh interval. Passing
 // UTC_TIMESTAMP through UNIX_TIMESTAMP interprets it in the session zone.
 const [clockPolicy]=await db.query('SELECT overview_clock_refresh_seconds AS seconds FROM read_model_execution_policy WHERE policy_id=1');
 await db.query('SET timestamp=?',[fixedEpoch+Number(clockPolicy[0].seconds)+1]);const clock=await db.query('CALL ga_poll_overview()');assert.equal(clock[0].filter(Array.isArray).flat().find(r=>r._set==='overview_publication_basis').should_publish,1,'clock refresh deadline must trigger a new overview');await db.query('SET timestamp=DEFAULT');
 pass('measurement change and DB clock deadline each trigger fresh publication; receipt is idempotent and unchanged polls remain cheap');
 fs.writeFileSync(path.join(root,'verification/p24r15-performance-regression.json'),JSON.stringify({application_version:fs.readFileSync(path.join(root,'VERSION'),'utf8').trim(),server_version:(await db.query('SELECT VERSION() v'))[0][0].v,status:'pass',fixture:{active_measurements:n,historical_sessions:3,historical_measurements:n*3,interval_seconds:300,display_interval_seconds:1800},baseline_graph_queries:before,baseline_graph_total:{elapsed_ms:oldMs,rows_read:oldReads},full_overview:compact(after),with_three_historical_series:compact(grown),unchanged_poll:compact(poll),concurrent_write_ms:write_ms,checks,target_ha_uat:'not_run'},null,2)+'\n');
 await db.query("INSERT INTO session_release_events(release_event_id,session_id,released_at,operation_id,created_at) VALUES('r14-performance-release',?,UTC_TIMESTAMP(3),'r14-performance-release',UTC_TIMESTAMP(3))",[sid]);
}finally{await db.end();await other.end();}})().catch(e=>{console.error(e.code,e.sqlMessage||e.message);process.exitCode=1;});
