'use strict';
// Actual SQL + Node-RED input path. HA event delivery is simulated, not target UAT.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const mysql=require('mysql2/promise'),root=path.resolve(__dirname,'..');
const by=Object.fromEntries(JSON.parse(fs.readFileSync(path.join(root,'nodered/flows.template.json'))).map(n=>[n.id,n]));
const call=(id,msg={})=>new Function('msg','node','global',by[id].func)(msg,{warn(){},error(e){throw Error(e)}},{get:()=>({})});
const checks=[],pass=s=>{checks.push(s);console.log('PASS',s);};
(async()=>{
 const db=await mysql.createConnection({host:'127.0.0.1',port:13310,user:'root',database:'ga_p24_release_test',dateStrings:true,multipleStatements:true});
 try{
  const execute=async msg=>{if(Array.isArray(msg))msg=msg[0];return {...msg,payload:(await db.query(msg.topic,msg.payload))[0]};};
  const query=async(id,msg={})=>execute(call(id,msg));
  const field=async(entity_id,value)=>{
   const transported=call('p26_start_field_input',{payload:{event:{data:{entity_id,value}}}});
   await execute(call('p22_draft_binding_result',await query('p20_draft_update',transported)));
  };
  const start=async()=>{const context=await query('p20_start_guard');return call('p20_start_context_result',context);};
  const projection=async()=>{const value=(await db.query('SELECT ha_payload FROM v_ha_start_status_payload'))[0][0].ha_payload;return typeof value==='string'?JSON.parse(value):value;};
  await query('p20_template_select',{payload:'w3470-standard@3.0'});
  await field('select.gjaeringsassistent_pitchmodus','Slurry');
  let p=await projection();let fields=p.attributes.start_fields;
  for(const name of ['slurry_volume_ml','slurry_generation']){
   const f=fields.find(f=>f.field_name===name);assert.equal(f.value,null);assert.equal(f.value_display,'Ikke angitt');assert.equal(f.validation_status,'missing');
  }
  let rejected=await start();assert.equal(rejected[0],null);assert.match(rejected[1].payload,/slurry generasjon/);
  let attempted=(await db.query('SELECT * FROM session_start_attempts ORDER BY requested_at DESC LIMIT 1'))[0][0];
  assert.equal(Number(attempted.ready_to_start),0);
  const snapshots=(await db.query('SELECT * FROM session_start_attempt_fields WHERE attempt_id=?',[attempted.attempt_id]))[0];
  assert.equal(snapshots.find(f=>f.entity_id==='number.gjaeringsassistent_slurry_generasjon').observed_value,null);
  pass('empty DB fields are explicitly missing despite stale HA numbers; rejected Start persists exact field snapshots');
  for(const [id,value] of [['number.gjaeringsassistent_slurry_volum_ml','4000'],['number.gjaeringsassistent_slurry_generasjon','2'],['text.gjaeringsassistent_slurry_kildebatch','IPL'],['text.gjaeringsassistent_oksygenering','3 min på minste']])await field(id,value);
  await field('number.gjaeringsassistent_slurry_generasjon','2');
  // A test-only barrier after snapshot reads lets a separate operator edit the draft.
  // The shipping procedure is used verbatim apart from its name and this barrier.
  let probeSql=fs.readFileSync(path.join(root,'sql/11-runtime-routines.sql'),'utf8');probeSql=probeSql.slice(probeSql.indexOf('CREATE PROCEDURE ga_read_start_context('));probeSql=probeSql.slice(0,probeSql.indexOf('DELIMITER ;')).replace('ga_read_start_context(','ga_read_start_context_probe(').replace(' INSERT INTO session_start_attempts(attempt_id'," SELECT 'snapshot_captured' AS fixture_marker; DO SLEEP(0.2);\n INSERT INTO session_start_attempts(attempt_id").replace(/END\/\//g,'END;');await db.query(probeSql);
  let signal;const captured=new Promise(resolve=>{signal=resolve;});
  const collecting=[];const pending=new Promise((resolve,reject)=>{const q=db.connection.query("CALL ga_read_start_context_probe('snapshot-concurrency-probe',NULL)");q.on('result',row=>{collecting.push(row);if(row.fixture_marker)signal();});q.on('error',reject);q.on('end',()=>resolve(collecting));});
  let timeout;try{await Promise.race([captured,new Promise((_,reject)=>{timeout=setTimeout(()=>reject(Error('snapshot barrier timeout')),5000);})]);}finally{clearTimeout(timeout);}
  const writer=await mysql.createConnection({host:'127.0.0.1',port:13310,user:'root',database:'ga_p24_release_test'});
  try{await writer.query("UPDATE session_setup_draft SET slurry_volume_ml=3900 WHERE draft_key='current'");}finally{await writer.end();}
  const returned=(await pending).flat().find(r=>r.draft_key==='current');assert.equal(Number(returned.slurry_volume_ml),4000);
  const frozen=(await db.query("SELECT observed_value FROM session_start_attempt_fields WHERE attempt_id='snapshot-concurrency-probe' AND entity_id='number.gjaeringsassistent_slurry_volum_ml'"))[0][0];assert.equal(Number(frozen.observed_value),4000);assert.equal(Number((await db.query("SELECT slurry_volume_ml FROM session_setup_draft"))[0][0].slurry_volume_ml),3900);
  await db.query('DROP PROCEDURE ga_read_start_context_probe');await field('number.gjaeringsassistent_slurry_volum_ml','4000');
  pass('concurrent draft edit cannot change the exact validated/returned/recorded start snapshot and does not require an application lock');
  // Complete first round through the real HA/NR field bindings. The final
  // updated file must be rerun after environment recovery before release.
  const initialFields=[
   ['select.gjaeringsassistent_kontroll_malemetode','Hydrometer','measurement_method_id','hydrometer'],
   ['number.gjaeringsassistent_malt_sg','1.056','measured_sg',1.056],
   ['number.gjaeringsassistent_provetemperatur','20','sample_temperature_c',20],
   ['number.gjaeringsassistent_hydrometer_kalibreringstemperatur','20','calibration_temperature_c',20],
   ['number.gjaeringsassistent_manuell_temperatur','9.4','manual_temperature_c',9.4],
   ['number.gjaeringsassistent_trykk','0.2','pressure_bar',0.2],
   ['number.gjaeringsassistent_kjolemaskin_settpunkt','8.1','cooler_setpoint_c',8.1],
   ['number.gjaeringsassistent_kjolemaskin_kalibrering','-0.3','cooler_calibration_offset_c',-0.3],
   ['select.gjaeringsassistent_gjaerlasaktivitet','Sporadisk','airlock_activity','sporadic'],
   ['number.gjaeringsassistent_acetaldehyd','1','acetaldehyde_level',1],
   ['number.gjaeringsassistent_diacetyl','0','diacetyl_level',0],
   ['number.gjaeringsassistent_vorteraktig_preg','2','wort_like_level',2],
   ['number.gjaeringsassistent_svovel_so2','3','sulfur_so2_level',3],
   ['number.gjaeringsassistent_svovel_h2s','4','sulfur_h2s_level',4],
   ['number.gjaeringsassistent_klarhet','5','clarity_level',5],
   ['number.gjaeringsassistent_utfelling_i_prove','2','settling_yeast_level',2],
   ['number.gjaeringsassistent_utfelling_minutter','17','settling_minutes',17],
   ['select.gjaeringsassistent_kontroll_konklusjon','Usikker','user_conclusion','uncertain'],
   ['text.gjaeringsassistent_kontrollnotat','Første målesett · æøå 🍺','note','Første målesett · æøå 🍺']
  ];
  for(const [id,value] of initialFields)await field(id,value);
  p=await projection();assert.equal(Number(p.attributes.start_ready),1);assert.equal(p.attributes.start_fields.find(f=>f.field_name==='slurry_generation').value,'2');
  const write=await start();assert.ok(write[0],JSON.stringify(write));
  await db.query("CREATE TRIGGER reject_initial_fixture BEFORE INSERT ON observation_round_revisions FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Initial round fixture failure'");
  try{
   await assert.rejects(execute(structuredClone(write[0])),/Initial round fixture failure/);
   for(const table of ['sessions','session_template_snapshots','session_process_steps','session_biological_phases','measurement_input_draft','observation_rounds','observation_round_revisions'])
    assert.equal(Number((await db.query('SELECT COUNT(*) n FROM '+table))[0][0].n),0,table+' must roll back with the initial round');
   assert.equal((await db.query("SELECT measured_sg FROM session_setup_draft WHERE draft_key='current'"))[0][0].measured_sg,'1.05600');
  }finally{await db.query('DROP TRIGGER reject_initial_fixture');}
  pass('late initial-round failure rolls back the session, frozen plan and measurement draft while preserving pre-start input');
  await execute(write[0]);const sid=write[0].ga_session_id;
  const rounds=(await db.query('SELECT r.*,s.pitched_at FROM observation_round_revisions r JOIN sessions s ON s.session_id=r.session_id WHERE r.session_id=?',[sid]))[0];
  assert.equal(rounds.length,1);const initialRound=rounds[0];
  for(const [, ,name,expected] of initialFields)assert.equal(typeof expected==='number'?Number(initialRound[name]):initialRound[name],expected,name);
  assert.equal(initialRound.recorded_at,initialRound.pitched_at);
  assert.equal(initialRound.revision_reason,'initial');assert.equal(Number(initialRound.revision_no),1);
  assert.equal(Number(initialRound.corrected_sg),1.056);assert.equal(Number(initialRound.actual_og_used),1.056);
  assert.equal(Number(initialRound.estimated_abv_percent),0);
  assert.equal(initialRound.operation_id,write[0].ga_operation_id);
  await field('number.gjaeringsassistent_diacetyl','4');
  assert.equal(Number((await db.query('SELECT diacetyl_level FROM observation_round_revisions WHERE observation_revision_id=?',[initialRound.observation_revision_id]))[0][0].diacetyl_level),0);
  pass('Start persists exactly one complete first measurement round at pitch with SG, temperature, pressure, cooling, airlock, all sensory fields, settling and Unicode note; later draft edits preserve it');
  const exception=async(kind,c,action,operation)=>{
   const prefix=kind==='process'?'p20_process_exception':'p24_bio_exception';
   const request=call(prefix+'_context',{payload:{event:{data:{evaluation_id:c.evaluation_id,criterion_id:c.criterion_id,action,exception_type:'akseptert_avvik',confirmed:true,note:'',operation_id:operation}}}});
   assert.ok(request[0]);await execute(call(prefix+'_context_result',await execute(request[0])));
  };
  for(const [prefix,kind,view,table] of [['process','process','v_process_evaluation_criterion_read_model','process_criterion_exceptions'],['bio','biological','v_biological_evaluation_criterion_read_model','biological_criterion_exceptions']]){
   await execute(call('p20_'+prefix+'_eval_result',{_msgid:'initial-round-'+prefix,...await query('p20_'+prefix+'_eval_query')}));
   const rows=(await db.query('SELECT * FROM '+view+' WHERE session_id=? ORDER BY criterion_order',[sid]))[0];
   let c=rows.find(r=>r.met===null&&Number(r.exception_register_allowed)===1);
   assert.ok(c,kind+' missing continuous basis must retain NULL and allow a declared exception');
   assert.ok(['missing_basis','missing_coverage','stale'].includes(c.evaluation_status));
   const factTable=kind==='process'?'process_evaluation_criteria':'biological_evaluation_criteria';
   const before=(await db.query('SELECT * FROM '+factTable+' WHERE evaluation_id=? AND criterion_id=?',[c.evaluation_id,c.criterion_id]))[0][0];
   await exception(kind,c,'register','initial-round-'+prefix+'-register');
   let events=(await db.query('SELECT * FROM '+table+' WHERE session_id=? AND criterion_id=? ORDER BY revision_no',[sid,c.criterion_id]))[0];
   assert.equal(events.length,1);assert.equal(events[0].action,'register');assert.equal(events[0].note,null);
   if(kind==='process'){
    const overviewRows=await query('p20_overview_query');
    const overview=JSON.parse(call('p20_overview_result',{_msgid:'initial-round-exception',...overviewRows}).payload);
    assert.equal(overview.process_guidance.readiness,'ready_with_exceptions');
    const condition=overview.process_guidance.condition_evaluations.find(r=>r.criterion_id===c.criterion_id);
    assert.ok(condition.allowed_actions.includes('register_exception'));
   }
   if(kind==='biological'){
    const original=c.evaluation_id;
    await execute(call('p20_bio_eval_result',{_msgid:'initial-round-bio-new-evaluation',...await query('p20_bio_eval_query')}));
    c=(await db.query('SELECT c.* FROM v_biological_evaluation_criterion_read_model c JOIN v_current_biological_candidate_evaluation e ON e.evaluation_id=c.evaluation_id WHERE c.session_id=? AND c.criterion_id=?',[sid,c.criterion_id]))[0][0];
    assert.ok(c);assert.notEqual(c.evaluation_id,original);assert.equal(c.met,null);
   }
   await exception(kind,c,'withdraw','initial-round-'+prefix+'-withdraw');
   events=(await db.query('SELECT * FROM '+table+' WHERE session_id=? AND criterion_id=? ORDER BY revision_no',[sid,c.criterion_id]))[0];
   assert.equal(events.length,2);assert.equal(events[1].action,'withdraw');assert.equal(events[1].supersedes_exception_id,events[0].exception_id);
   assert.deepEqual((await db.query('SELECT * FROM '+factTable+' WHERE evaluation_id=? AND criterion_id=?',[before.evaluation_id,before.criterion_id]))[0][0],before,'exception handling preserves the original evaluation');
   if(kind==='process')assert.equal((await db.query('SELECT readiness FROM v_current_process_guidance WHERE session_id=?',[sid]))[0][0].readiness,'waiting');
  }
  pass('actual B/P evaluation after a complete Start preserves missing time-series basis and allows registered/withdrawn exceptions through HA events without rewriting original evidence');
  const slurry=(await db.query('SELECT * FROM session_slurry_pitches WHERE session_id=?',[sid]))[0][0];assert.equal(Number(slurry.slurry_volume_ml),4000);assert.equal(Number(slurry.slurry_generation),2);assert.equal(slurry.slurry_source_batch,'IPL');
  assert.equal((await db.query('SELECT COUNT(*) n FROM session_dry_pitches WHERE session_id=?',[sid]))[0][0].n,0);
  pass('same-value explicit HA event persists through actual DB binding and complete slurry Start stores only slurry pitch facts');
  // Retain the old session while creating a second operative fermentation.
  await db.query("INSERT INTO session_lifecycle_events(lifecycle_event_id,session_id,lifecycle,occurred_at,note,operation_id,created_at) VALUES('start-control-end',?,'completed',UTC_TIMESTAMP(3),'Native fixture','start-control-end',UTC_TIMESTAMP(3));INSERT INTO session_release_events(release_event_id,session_id,released_at,operation_id,created_at) VALUES('start-control-release',?,UTC_TIMESTAMP(3),'start-control-release',UTC_TIMESTAMP(3));",[sid,sid]);
  await query('p20_template_select',{payload:'w3470-standard@3.0'});
  p=await projection();for(const name of ['slurry_volume_ml','slurry_generation'])assert.equal(p.attributes.start_fields.find(f=>f.field_name===name).value,null);
  const dry=await start();assert.ok(dry[0]);await execute(dry[0]);
  assert.equal((await db.query('SELECT COUNT(*) n FROM v_current_process_visit'))[0][0].n,2);
  const control=(await db.query('SELECT * FROM v_system_check_session'))[0][0];assert.equal(control.check_status,'ok');assert.equal(control.summary,'Aktiv session: prosess=1, biologi=1');
  const inspected=await query('p20_systemcheck_query');inspected.ga_ha_states=inspected.payload.flat().filter(r=>r._set==='ha_registry').map(r=>({entity_id:r.entity_id,state:'unknown'}));
  const result=call('p20_systemcheck_result',inspected);assert.equal(result.ga_systemcheck.checks.find(c=>c.id==='session').status,'ok');
  pass('retained old session plus active fermentation yields process=1/biology=1 through actual Systemkontroll query and consumer');
  await db.query("DELETE FROM start_field_rules WHERE entity_id='text.gjaeringsassistent_kontrollnotat'");
  assert.equal(Number((await db.query('SELECT ready_to_start FROM v_start_readiness'))[0][0].ready_to_start),0);
  assert.match((await db.query("SELECT message FROM v_start_issues WHERE issue_key='field_registry'"))[0][0].message,/ufullstendig/);
  pass('unregistered start binding fails visibly in the DB contract');
  const sources=['installer/install.sh','installer/database-plan.py','installer/migrations.json','sql/00-template-schema.sql','sql/10-runtime-schema.sql','sql/12-operator-schema.sql','sql/12-operator-routines.sql','sql/26-operator-config-seed.sql','sql/23-measurement-source-seed.sql','tools/overview_reads.sql','sql/11-runtime-routines.sql','sql/20-views.sql','sql/21-system-metadata-seed.sql','nodered/flows.template.json','dashboard/gjaeringsassistent-card.js','dashboard/gjaeringsassistent-dashboard.yaml','tests/test-start-control-live.js'];
  fs.writeFileSync(path.join(root,'verification/start-control-regression.json'),JSON.stringify({application_version:fs.readFileSync(path.join(root,'VERSION'),'utf8').trim(),server_version:(await db.query('SELECT VERSION() v'))[0][0].v,status:'pass',target_ha_uat:'not_run',checks,source_fingerprints:Object.fromEntries(sources.map(f=>[f,crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex')]))},null,2)+'\n');
 }finally{await db.end();}
})().catch(e=>{console.error(e.code||'ASSERT',e.sqlMessage||e.stack);process.exitCode=1;});
