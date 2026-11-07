'use strict';
// TEST-FUNC-017, TEST-FUNC-018, TEST-FUNC-019. Isolated MariaDB only.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto');
const mysql=require('mysql2/promise'),{DatabaseSync}=require('node:sqlite');
const core=require('../tools/sqlite_archive'),worker=require('../tools/archive_worker');
const root=path.resolve(__dirname,'..'),flows=JSON.parse(fs.readFileSync(path.join(root,'nodered/flows.template.json'))),by=Object.fromEntries(flows.map(n=>[n.id,n]));
const config={host:'127.0.0.1',port:Number(process.env.GA_TEST_PORT||13310),user:'root',database:process.env.GA_TEST_DATABASE||'ga_p24_release_test',dateStrings:true,decimalNumbers:false,supportBigNumbers:true,bigNumberStrings:true,multipleStatements:true};
const run=id=>new Function('msg','node',by[id].func)({}, {error:e=>{throw Error(e)},warn:()=>{}});
const checks=[];function pass(name){checks.push(name);console.log('PASS',name);}
(async()=>{
 const db=await mysql.createConnection(config),live=await mysql.createConnection(config),dir=fs.mkdtempSync(path.join(os.tmpdir(),'ga-sqlite-test-'));
 try{
  const [version]=await db.query('SELECT VERSION() AS version');assert.match(version[0].version,/^12\.3\.3-/);
  // Isolated fixture: release earlier regression sessions before demo Start.
  await db.query("INSERT INTO session_release_events(release_event_id,session_id,released_at,operation_id,created_at) SELECT CONCAT('r10-fixture-release-',session_id),session_id,UTC_TIMESTAMP(3),CONCAT('r10-fixture-release-',session_id),UTC_TIMESTAMP(3) FROM v_current_session");
  // Use the shipped start/seed transactions with the restored original demo.
  await db.query("INSERT INTO demo_profile_selection_events(profile_id,operation_id,selected_at) VALUES('ipl-synthetic-p17r12','r10-test-ipl-choice-3',UTC_TIMESTAMP(3))");
  const prepare=run('p20_demo_prepare_query');await db.query(prepare.topic,prepare.payload);
  const vars={session_id:'r10-original-ipl',is_demo:1,template_version:'w3470-standard@3.0',source_profile:'tilt-pro-blue-ha',batch_name:'2026-05-29 IPL',pitched_at:'2026-05-29 20:00:00',created_at:'2026-05-29 20:00:00',og:1.049,volume_l:150,pitch_mode:'dry',pitch_temperature_c:8,yeast_amount_g:202,expected_attenuation_min:80,expected_attenuation_max:84,operation_id:'r10-original-ipl-start',measurement_method:'hydrometer',measured_sg:1.049,sample_temperature_c:20,calibration_temperature_c:20,corrected_sg:1.049,manual_temperature_c:8,pressure_bar:0,cooler_setpoint_c:8,cooler_calibration_offset_c:0,airlock_activity:'none',user_conclusion:'uncertain',measurement_note:'',corrected_sg_model:'hydrometer-temperature-correction-sg-v1',abv_now:0,finished_abv:5.25,finished_abv_model:'expected-attenuation-midpoint-v1'};
  for(const name of ['acetaldehyde_level','diacetyl_level','wort_like_level','sulfur_so2_level','sulfur_h2s_level','clarity_level','settling_yeast_level','settling_minutes'])vars[name]=0;
  const parameters=[];let startSql=fs.readFileSync(path.join(root,'sql/start-session.sql'),'utf8').split('SELECT s.*')[0].replace(/SET @ga_([a-z0-9_]+)=\?;/g,(match,key)=>{parameters.push(vars[key]??null);return match;});await db.query(startSql+"CALL ga_seed_demo_tx('r10-original-ipl');",parameters);
  const [points]=await db.query("SELECT offset_seconds,sg_mean,temperature_mean_c,pressure_bar FROM demo_reference_measurements_5m r JOIN demo_reference_synthetic_details p USING(profile_id,offset_seconds) WHERE profile_id='ipl-synthetic-p17r12' ORDER BY offset_seconds");
  const [measurements]=await db.query("SELECT TIMESTAMPDIFF(SECOND,'2026-05-29 20:00:00',bucket_at) AS offset_seconds,sg_mean,temperature_mean_c,pressure_mean_bar AS pressure_bar FROM measurements_5m WHERE session_id='r10-original-ipl' ORDER BY bucket_at");
  const expectedPoints=points.map(r=>({...r,pressure_bar:Number(r.pressure_bar)}));assert.equal(points.length,209);assert.equal(measurements.length,209);assert.deepEqual(measurements.map(r=>({...r,offset_seconds:Number(r.offset_seconds),pressure_bar:Number(r.pressure_bar)})),expectedPoints);
  const [segments]=await db.query("SELECT DISTINCT interval_seconds,segment_id FROM v_session_measurement_segments WHERE session_id='r10-original-ipl'");assert.equal(segments.length,2);assert.ok(segments.every(s=>s.interval_seconds===3600));
  const [state]=await db.query("SELECT current_process_id,current_biological_phase_id FROM v_current_session_summary WHERE session_id='r10-original-ipl'");assert.equal(state[0].current_process_id,'P5');assert.equal(state[0].current_biological_phase_id,'B4');
  assert.equal((await db.query('SELECT state FROM v_session_start_status'))[0][0].state,'ready');
  await db.query("INSERT INTO session_lifecycle_events(lifecycle_event_id,session_id,lifecycle,occurred_at,note,operation_id,created_at) VALUES('r10-original-ipl-end','r10-original-ipl','completed','2026-06-07 20:00:00','Test','r10-original-ipl-end','2026-06-07 20:00:00')");
  assert.equal((await db.query('SELECT state FROM v_session_start_status'))[0][0].state,'completed');
  const ready=new Function('msg','node',by.p21_session_prepare_context_result.func)({payload:[{session_id:'r10-original-ipl',lifecycle:'completed',is_demo:1}]},{error:e=>{throw Error(e)}})[0];await db.query(ready.topic,ready.payload);
  assert.equal((await db.query('SELECT state FROM v_session_start_status'))[0][0].state,'idle');
  pass('209 original IPL values, pressure, hourly segments and P5/B4 history');
  const pair=await core.exportArchive(db,{session_id:'r10-original-ipl',export_id:'r10-native-pair',output_dir:dir}),files={session:pair.session.path,template:pair.template.path};
  assert.ok(pair.session.path.endsWith('-gjaering.sqlite'));assert.equal(path.basename(pair.session.path).replace('-gjaering.sqlite',''),path.basename(pair.template.path).replace('-template.sqlite',''));
  const p=await core.preview(db,files);assert.equal(p.session.rows.measurements_5m.length,209);assert.ok(!p.session.rows.template_versions);assert.equal(p.template.rows.template_versions.length,1);
  const repeated=await core.exportArchive(db,{session_id:'r10-original-ipl',export_id:'r10-native-pair',output_dir:dir});assert.equal(repeated.session.sha256,pair.session.sha256);assert.equal(repeated.template.sha256,pair.template.sha256);
  pass('normalized SQLite pair, manifest match and complete measurement history');
  // A genuine v1 column layout must convert before import, without inventing pitch facts.
  const legacyFiles={session:path.join(dir,'legacy-gjaering.sqlite'),template:path.join(dir,'legacy-template.sqlite')};
  fs.copyFileSync(files.session,legacyFiles.session);fs.copyFileSync(files.template,legacyFiles.template);
  for(const role of ['session','template']){const f=new DatabaseSync(legacyFiles[role]);f.exec("UPDATE archive_manifest SET value='1' WHERE key='version'");
    // Released pre-r13 archives had three derived graphs plus explicit raw-graph policies.
    const prefix=role==='session'?'session':'template';
    for(const suffix of ['analysis_graph_series','analysis_graphs'])f.exec('DELETE FROM '+prefix+'_'+suffix+" WHERE graph_id IN ('sg','temperature','pressure')");
    f.exec('UPDATE '+prefix+'_analysis_graphs SET sort_order=sort_order-3');
    f.exec('DROP TABLE graph_render_policy');
    if(role==='session'){
    const cols=p.meta.sessions.columns.map(c=>c.name),old=['yeast_amount_g','slurry_volume_ml','slurry_source_batch','slurry_generation'];cols.splice(cols.indexOf('oxygenation_note'),0,...old);
    f.exec('ALTER TABLE sessions RENAME TO sessions_v2');f.exec('CREATE TABLE sessions ('+cols.map(c=>'"'+c+'" TEXT').join(',')+')');
    const dry=p.session.rows.session_dry_pitches[0];const row={...p.session.rows.sessions[0],yeast_amount_g:dry.yeast_amount_g,slurry_volume_ml:null,slurry_source_batch:null,slurry_generation:null};
    f.prepare('INSERT INTO sessions VALUES('+cols.map(()=>'?').join(',')+')').run(...cols.map(c=>row[c]));f.exec('DROP TABLE sessions_v2; DROP TABLE session_dry_pitches');
  }f.close();}
  const legacy=await core.preview(db,legacyFiles);assert.deepEqual(legacy.session.rows.sessions,p.session.rows.sessions);assert.deepEqual(legacy.session.rows.session_dry_pitches,p.session.rows.session_dry_pitches);assert.deepEqual(legacy.session.rows.measurements_5m,p.session.rows.measurements_5m);
  const legacyImport=await core.importArchive(db,legacyFiles,'r12-legacy-import');assert.equal((await db.query('SELECT COUNT(*) AS n FROM session_dry_pitches WHERE session_id=?',[legacyImport.session_id]))[0][0].n,'1');
  assert.equal((await db.query('SELECT COUNT(*) AS n FROM template_analysis_graphs WHERE version_id=?',[legacyImport.version_id]))[0][0].n,'6');
  assert.equal((await db.query('SELECT COUNT(*) AS n FROM session_analysis_graphs WHERE session_id=?',[legacyImport.session_id]))[0][0].n,'6');
  assert.equal((await db.query("SELECT COUNT(DISTINCT graph_id) AS n FROM v_graph_raw_series WHERE session_id=? AND series_id='measured'",[legacyImport.session_id]))[0][0].n,'3');
  const legacyTemplate=await core.importArchive(db,{template:legacyFiles.template},'r13-legacy-template-only');
  assert.equal((await db.query('SELECT COUNT(*) AS n FROM template_analysis_graphs WHERE version_id=?',[legacyTemplate.version_id]))[0][0].n,'6');
  const ambiguous=path.join(dir,'legacy-ambiguous-template.sqlite');fs.copyFileSync(legacyFiles.template,ambiguous);const ambiguousDb=new DatabaseSync(ambiguous);ambiguousDb.exec("UPDATE template_analysis_graphs SET graph_id='sg' WHERE graph_id='sg-rate'; UPDATE template_analysis_graph_series SET graph_id='sg' WHERE graph_id='sg-rate'");ambiguousDb.close();
  const templatesBefore=(await db.query('SELECT COUNT(*) AS n FROM templates'))[0][0].n;
  await assert.rejects(core.importArchive(db,{template:ambiguous},'r13-legacy-ambiguous'),/tvetydig graf-ID/);
  assert.equal((await db.query('SELECT COUNT(*) AS n FROM templates'))[0][0].n,templatesBefore);
  const badLegacy=path.join(dir,'legacy-missing-pitch.sqlite');fs.copyFileSync(legacyFiles.session,badLegacy);const missingPitch=new DatabaseSync(badLegacy);missingPitch.exec('UPDATE sessions SET yeast_amount_g=NULL');missingPitch.close();await assert.rejects(core.importArchive(db,{session:badLegacy,template:legacyFiles.template},'r12-legacy-invalid'));
  pass('legacy SQLite v1 layout converts and imports exact existing pitch facts; missing pitch facts reject');
  pass('legacy raw graph policies convert through DB catalog for session and template-only imports; ambiguous IDs roll back');

  const liveVars={...vars,session_id:'r10-live',is_demo:0,batch_name:'Pågående gjæring',pitched_at:'2026-10-01 00:00:00',operation_id:'r10-live-start'};const liveParameters=[];const liveStart=startSql.replace(/SET @ga_([a-z0-9_]+)=\?;/g,(match,key)=>{liveParameters.push(liveVars[key]??null);return match;});await db.query(liveStart,liveParameters);
  const [activeBefore]=await live.query('SELECT session_id FROM v_active_session ORDER BY session_id');assert.ok(activeBefore.length);
  const activeId=activeBefore[0].session_id;let writes=0,stop=false;
  const writing=(async()=>{while(!stop){const at=new Date(Date.parse('2026-10-09T00:00:00Z')+writes*300000).toISOString().replace('T',' ').replace('Z','');await live.query('INSERT INTO measurements_5m(session_id,bucket_at,sample_count,sg_min,sg_mean,sg_median,sg_max,temperature_min_c,temperature_mean_c,temperature_max_c,created_at,updated_at) VALUES(?,?,1,1.013,1.013,1.013,1.013,12,12,12,UTC_TIMESTAMP(3),UTC_TIMESTAMP(3)) ON DUPLICATE KEY UPDATE updated_at=VALUES(updated_at)',[activeId,at]);writes++;await new Promise(r=>setTimeout(r,10));}})();
  let imported;try{imported=await core.importArchive(db,files,'r10-live-import');}finally{stop=true;await writing;}
  assert.ok(writes>0);assert.deepEqual((await live.query('SELECT session_id FROM v_active_session ORDER BY session_id'))[0],activeBefore);
  assert.equal((await db.query('SELECT COUNT(*) AS n FROM v_current_session WHERE session_id=?',[imported.session_id]))[0][0].n,'0');
  assert.deepEqual((await db.query('SELECT TIMESTAMPDIFF(SECOND,\'2026-05-29 20:00:00\',bucket_at) AS offset_seconds,sg_mean,temperature_mean_c,pressure_mean_bar AS pressure_bar FROM measurements_5m WHERE session_id=? ORDER BY bucket_at',[imported.session_id]))[0].map(r=>({...r,offset_seconds:Number(r.offset_seconds),pressure_bar:Number(r.pressure_bar)})),expectedPoints);
  assert.equal((await db.query('SELECT origin_kind FROM template_origins WHERE template_id=?',[imported.template_id]))[0][0].origin_kind,'imported');assert.notEqual(imported.template_id,'w3470-standard');
  await assert.rejects(db.query("CALL ga_clone_template_tx(?,?,'','')",[imported.version_id,'r10-illegal-original-draft']),/ny template-ID/);
  await db.query("CALL ga_clone_template_tx(?,?,?,?)",[imported.version_id,'r10-own-copy-draft','r10-own-copy','Egen kopi']);
  assert.equal((await db.query("SELECT origin_kind FROM v_template_library WHERE version_id='r10-own-copy-draft'"))[0][0].origin_kind,'own');
  const replay=await core.importArchive(db,files,'r10-live-import');assert.equal(replay.session_id,imported.session_id);assert.equal(replay.idempotent,true);
  const duplicate=await core.importArchive(db,files,'r10-another-import-request');assert.equal(duplicate.session_id,imported.session_id);
  pass('import during real measurement writes; active session unchanged; atomic historical release; own copy and idempotence');
  // A late CHECK failure must roll back the new template as well as the session.
  const bad=path.join(dir,'bad-gjaering.sqlite');fs.copyFileSync(files.session,bad);const edit=new DatabaseSync(bad);edit.exec('UPDATE measurements_5m SET sample_count=0');edit.close();
  const before=(await db.query('SELECT COUNT(*) AS n FROM templates'))[0][0].n;
  await assert.rejects(core.importArchive(db,{session:bad,template:files.template},'r10-rollback-test'));
  assert.equal((await db.query('SELECT COUNT(*) AS n FROM templates'))[0][0].n,before);assert.equal((await db.query("SELECT COUNT(*) AS n FROM archive_imports WHERE operation_id='r10-rollback-test'"))[0][0].n,'0');
  const cross=path.join(dir,'wrong-scope.sqlite');fs.copyFileSync(files.session,cross);const scopeEdit=new DatabaseSync(cross);scopeEdit.exec("UPDATE measurements_5m SET session_id='r10-live'");scopeEdit.close();await assert.rejects(core.preview(db,{session:cross,template:files.template}),/annen sesjon/);
  const other=await core.exportArchive(db,{version_id:'s04-cool@1.0',export_id:'r10-other-template',output_dir:dir});await assert.rejects(core.preview(db,{session:files.session,template:other.template.path}),/forskjellige eksportsett/);
  const once=await core.importArchive(db,{template:files.template},'r10-template-only-1'),twice=await core.importArchive(db,{template:files.template},'r10-template-only-2');assert.notEqual(once.template_id,twice.template_id);
  await db.query("INSERT INTO graph_display_selection_events(source_kind,reference_session_id,interval_seconds,operation_id,selected_at) VALUES('session',?,300,'r10-compare-imported',UTC_TIMESTAMP(3))",[imported.session_id]);const [comparison]=await db.query('SELECT COUNT(*) AS n FROM v_graph_reference_measurement_series WHERE session_id=?',[activeId]);assert.equal(comparison[0].n,'209');const [markers]=await db.query('SELECT axis_label FROM v_session_analysis_time_markers WHERE session_id=? LIMIT 2',[activeId]);assert.ok(markers.length);assert.ok(markers.every(r=>/Dag \d+ · \d{2}\.\d{2}/.test(r.axis_label)));
  pass('late rollback, wrong pair rejection, unique template imports and imported comparison/date labels');
  // Independent connections exercise the real routine's uniqueness allocation.
  const clients=await Promise.all(Array.from({length:12},()=>mysql.createConnection(config)));
  try{await Promise.all(clients.map((c,i)=>c.query('CALL ga_register_active_report_tx(?,?,?,?)',[activeId,'r10-report-'+i,'/data/test-report-'+i+'.html',crypto.createHash('sha256').update('report'+i).digest('hex')])));await Promise.all(clients.map((c,i)=>c.query('CALL ga_register_active_report_tx(?,?,?,?)',[activeId,'r10-report-'+i,'/data/test-report-'+i+'.html',crypto.createHash('sha256').update('report'+i).digest('hex')])));}finally{await Promise.all(clients.map(c=>c.end()));}
  assert.equal((await db.query("SELECT COUNT(*) AS n FROM session_exports WHERE operation_id LIKE 'r10-report-%'"))[0][0].n,'12');
  pass('12 concurrent active reports and replay without duplicate primary keys');
  // Exercise the actual upload reconstruction and worker, not only the core.
  const ids={};for(const [role,file]of Object.entries(files)){const bytes=fs.readFileSync(file),id='r10-upload-'+role;ids[role+'_upload_id']=id;await db.query('INSERT INTO archive_uploads(upload_id,filename,expected_bytes,expected_chunks,sha256,created_at) VALUES(?,?,?,?,?,UTC_TIMESTAMP(3))',[id,path.basename(file),bytes.length,Math.ceil(bytes.length/65536),crypto.createHash('sha256').update(bytes).digest('hex')]);for(let n=0;n<Math.ceil(bytes.length/65536);n++)await db.query('INSERT INTO archive_upload_chunks(upload_id,chunk_no,payload,created_at) VALUES(?,?,?,UTC_TIMESTAMP(3))',[id,n,bytes.subarray(n*65536,(n+1)*65536)]);}
  // Stage the exact local-node files as the installer does, then invoke its
  // actual input adapter with the MySQL config node's credential shape.
  const staged=path.join(dir,'node');fs.mkdirSync(staged);
  fs.copyFileSync(path.join(root,'nodered/archive-node.js'),path.join(staged,'archive-node.js'));
  for(const file of ['archive_worker.js', 'sqlite_archive.js', 'archive_contract.json', 'archive_export.js', 'archive_admin.js', 'archive_catalog.js', 'report_module.js', 'graph_renderer.js', 'presentation_payload.js', 'report_renderer.js', 'report_queries.sql'])fs.copyFileSync(path.join(root,'tools',file),path.join(staged,file));
  let NodeType;const RED={settings:{userDir:process.env.GA_PALETTE_DIR||process.cwd()},nodes:{registerType:(name,type)=>{assert.equal(name,'ga-archive-transfer');NodeType=type;},createNode:node=>{node.handlers={};node.on=(name,fn)=>{node.handlers[name]=fn;};node.status=()=>{};},getNode:()=>({host:config.host,port:config.port,dbname:config.database,credentials:{user:config.user,password:''}})}};
  require(path.join(staged,'archive-node.js'))(RED);const adapter=new NodeType({mydb:'test-config'});
  let heartbeats=0;const timer=setInterval(()=>heartbeats++,5);let forwarded;
  try{await new Promise((resolve,reject)=>adapter.handlers.input({ga_archive_job:{action:'preview',operation_id:'r10-worker-preview',...ids}},msg=>{forwarded=msg;},e=>e?reject(e):resolve()));}finally{clearInterval(timer);await adapter.handlers.close();}
  assert.ok(heartbeats>0);assert.equal(forwarded[1],null);assert.equal(forwarded[0].ga_sqlite_result.manifest.session_id,'r10-original-ipl');
  pass('chunk upload checksum, actual Node-RED adapter, palette driver and worker preview');
  const admin=require('../tools/archive_admin'),catalog=require('../tools/archive_catalog');
  // Both roles and names are read from file content. SHA warnings never block.
  const standaloneBytes=fs.readFileSync(other.template.path),standaloneId='r11-standalone-upload';
  await db.query('INSERT INTO archive_uploads(upload_id,filename,expected_bytes,expected_chunks,sha256,created_at) VALUES(?,?,?,?,?,UTC_TIMESTAMP(3))',[standaloneId,path.basename(other.template.path),standaloneBytes.length,Math.ceil(standaloneBytes.length/65536),crypto.createHash('sha256').update(standaloneBytes).digest('hex')]);for(let n=0;n<Math.ceil(standaloneBytes.length/65536);n++)await db.query('INSERT INTO archive_upload_chunks(upload_id,chunk_no,payload,created_at) VALUES(?,?,?,UTC_TIMESTAMP(3))',[standaloneId,n,standaloneBytes.subarray(n*65536,(n+1)*65536)]);
  const inspected=await worker.run({database:config,userDir:process.env.GA_PALETTE_DIR},{action:'inspect_files',operation_id:'r11-inspect',upload_ids:[...Object.values(ids),standaloneId],checksum_files:[{filename:path.basename(files.template)+'.sha',text:'f'.repeat(64)},{filename:path.basename(other.template.path)+'.sha',text:'bad'}]});
  assert.equal(inspected.candidate_count,2);assert.equal(inspected.warnings.length,3);
  const [catalogue]=await db.query("SELECT * FROM v_archive_import_candidates WHERE operation_id='r11-inspect'");const candidates=catalogue.filter(c=>c.can_import_session===1);assert.equal(catalogue.length,2);assert.ok(catalogue.some(c=>c.can_import_session===0));assert.ok(candidates[0].display_name.includes('2026-05-29 IPL'));assert.equal(candidates[0].can_import_session,1);
  assert.equal(catalog.checksumNotice('x.sqlite','a'.repeat(64),[{filename:'x.sqlite.sha',text:'bad'}]).kind,'unreadable');
  const candidateImport=await worker.run({database:config,userDir:process.env.GA_PALETTE_DIR},{action:'import_template',operation_id:'r11-warning-import',candidate_id:candidates[0].candidate_id});assert.ok(candidateImport.template_id);
  assert.ok((await db.query("SELECT message FROM archive_transfer_events WHERE operation_id='r11-warning-import' AND status='done'"))[0][0].message.includes('Advarsel'));
  pass('one archive catalogue from manifests; missing/mismatched SHA warnings; import still succeeds');
  let snapshotStop=false,snapshotWrites=0;const writingSnapshot=(async()=>{while(!snapshotStop){const at=new Date(Date.parse('2026-10-10T00:00:00Z')+snapshotWrites*300000).toISOString().replace('T',' ').replace('Z','');await live.query('INSERT INTO measurements_5m(session_id,bucket_at,sample_count,sg_min,sg_mean,sg_median,sg_max,temperature_min_c,temperature_mean_c,temperature_max_c,created_at,updated_at) VALUES(?,?,1,1.012,1.012,1.012,1.012,12,12,12,UTC_TIMESTAMP(3),UTC_TIMESTAMP(3))',[activeId,at]);snapshotWrites++;await new Promise(r=>setTimeout(r,10));}})();let activePair;try{activePair=await core.exportArchive(db,{session_id:activeId,export_id:'r11-active',output_dir:dir});}finally{snapshotStop=true;await writingSnapshot;}assert.ok(snapshotWrites>0);assert.equal(activePair.manifest.snapshot_kind,'active_snapshot');assert.ok(fs.readFileSync(activePair.report.path,'utf8').includes('Øyeblikksbilde av aktiv gjæring'));
  for(const role of ['session','template'])assert.equal(fs.readFileSync(activePair[role].sha_path,'utf8'),activePair[role].sha256+'  '+path.basename(activePair[role].path)+'\n');
  assert.equal(activePair.report.sha256,activePair.manifest.report_sha256);
  const activePreview=await core.preview(db,{session:activePair.session.path,template:activePair.template.path});assert.equal(activePreview.session.rows.measurements_5m.length,String(activePair.manifest.measurement_count)==='0'?0:Number(activePair.manifest.measurement_count));
  const activeUploads=[];for(const role of ['template','session']){const bytes=fs.readFileSync(activePair[role].path),id='r11-active-upload-'+role;activeUploads.push(id);await db.query('INSERT INTO archive_uploads(upload_id,filename,expected_bytes,expected_chunks,sha256,created_at) VALUES(?,?,?,?,?,UTC_TIMESTAMP(3))',[id,path.basename(activePair[role].path),bytes.length,Math.ceil(bytes.length/65536),crypto.createHash('sha256').update(bytes).digest('hex')]);for(let n=0;n<Math.ceil(bytes.length/65536);n++)await db.query('INSERT INTO archive_upload_chunks(upload_id,chunk_no,payload,created_at) VALUES(?,?,?,UTC_TIMESTAMP(3))',[id,n,bytes.subarray(n*65536,(n+1)*65536)]);}
  const activeInspection=await worker.run({database:config,userDir:process.env.GA_PALETTE_DIR},{action:'inspect_files',operation_id:'r11-active-inspect',upload_ids:activeUploads,checksum_files:[]});assert.equal(activeInspection.warnings.length,2);const [activeCandidates]=await db.query("SELECT candidate_id FROM v_archive_import_candidates WHERE operation_id='r11-active-inspect'");
  const activeImport=await worker.run({database:config,userDir:process.env.GA_PALETTE_DIR},{action:'import_session',operation_id:'r11-active-import',candidate_id:activeCandidates[0].candidate_id});
  const activeReplay=await worker.run({database:config,userDir:process.env.GA_PALETTE_DIR},{action:'import_session',operation_id:'r11-active-import',candidate_id:activeCandidates[0].candidate_id});assert.equal(activeReplay.idempotent,true);assert.equal((await db.query('SELECT COUNT(*) AS n FROM v_active_session WHERE session_id=?',[activeImport.session_id]))[0][0].n,'0');assert.equal((await db.query('SELECT COUNT(*) AS n FROM v_dashboard_reference_options WHERE reference_id=?',[activeImport.session_id]))[0][0].n,'1');
  assert.deepEqual((await db.query('SELECT session_id FROM v_active_session ORDER BY session_id'))[0],activeBefore);
  await assert.rejects(admin.deleteArchive(db,{action:'delete_session',operation_id:'r11-delete-active',session_id:activeId}),/Aktiv/);
  // A used imported template blocks deletion and rolls back the whole pair.
  await assert.rejects(admin.deleteArchive(db,{action:'delete_template',operation_id:'r11-delete-used',template_id:imported.template_id}),/brukes/);
  await assert.rejects(admin.deleteArchive(db,{action:'delete_session',operation_id:'r11-delete-linked-used',session_id:imported.session_id,delete_template:true}),/brukes/);
  assert.equal((await db.query('SELECT COUNT(*) AS n FROM sessions WHERE session_id=?',[imported.session_id]))[0][0].n,'1');
  const deleted=await admin.deleteArchive(db,{action:'delete_session',operation_id:'r11-delete-imported',session_id:imported.session_id});assert.ok(deleted.deleted_rows>209);
  assert.equal((await db.query('SELECT COUNT(*) AS n FROM measurements_5m WHERE session_id=?',[imported.session_id]))[0][0].n,'0');assert.equal((await db.query('SELECT source_kind FROM graph_display_selection_events ORDER BY selection_seq DESC LIMIT 1'))[0][0].source_kind,'none');
  assert.equal((await admin.deleteArchive(db,{action:'delete_session',operation_id:'r11-delete-imported',session_id:imported.session_id})).idempotent,true);
  await admin.deleteArchive(db,{action:'delete_session',operation_id:'r11-delete-snapshot',session_id:activeImport.session_id,delete_template:true});assert.equal((await db.query('SELECT COUNT(*) AS n FROM templates WHERE template_id=?',[activeImport.template_id]))[0][0].n,'0');
  await admin.deleteArchive(db,{action:'delete_template',operation_id:'r11-delete-free',template_id:once.template_id});
  await admin.deleteArchive(db,{action:'delete_session',operation_id:'r11-delete-local',session_id:'r10-original-ipl'});
  assert.ok(fs.existsSync(pair.session.path)&&fs.existsSync(pair.template.path));assert.deepEqual((await db.query('SELECT session_id FROM v_active_session ORDER BY session_id'))[0],activeBefore);
  pass('active snapshot SQLite/report/SHA; historical snapshot import; permanent local/imported deletion, rollback, replay and live protection');
  fs.writeFileSync(path.join(root,'verification/p24r15-archive-regression.json'),JSON.stringify({application_version:fs.readFileSync(path.join(root,'VERSION'),'utf8').trim(),server_version:version[0].version,status:'pass',checks,deleted_rows:deleted.deleted_rows,active_export_sha256:activePair.session.sha256,concurrent_snapshot_writes:snapshotWrites},null,2)+'\n');
  const [viewColumns]=await db.query("SELECT c.TABLE_NAME,c.COLUMN_NAME FROM information_schema.COLUMNS c JOIN information_schema.VIEWS v ON v.TABLE_SCHEMA=c.TABLE_SCHEMA AND v.TABLE_NAME=c.TABLE_NAME WHERE c.TABLE_SCHEMA=DATABASE() ORDER BY c.TABLE_NAME,c.ORDINAL_POSITION");
  const viewContract={};for(const row of viewColumns)(viewContract[row.TABLE_NAME]??=[]).push(row.COLUMN_NAME);assert.equal(Object.keys(viewContract).length,178);
  fs.writeFileSync(path.join(root,'contracts/read-model-columns.json'),JSON.stringify(viewContract,null,2)+'\n');
  const library=run('p24_archive_library_query');await db.query(library.topic,library.payload);
  fs.writeFileSync(path.join(root,'verification/p24r10-sqlite-regression.json'),JSON.stringify({application_version:fs.readFileSync(path.join(root,'VERSION'),'utf8').trim(),server_version:version[0].version,status:'pass',checks,concurrent_measurement_writes:writes,session_archive_bytes:pair.session.bytes,template_archive_bytes:pair.template.bytes},null,2)+'\n');
  console.log('RESULT: PASS – SQLite transfer and concurrency on actual MariaDB 12.3.3');
 }finally{await db.end();await live.end();fs.rmSync(dir,{recursive:true,force:true});}
})().catch(e=>{console.error(e);process.exitCode=1;});
