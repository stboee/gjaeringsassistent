'use strict';
// Actual install.sh, migration planner, dump/restore and MariaDB SQL.
// Docker transport and Node-RED readiness are simulated; no target deployment.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto');
const {spawnSync,spawn}=require('node:child_process'),mysql=require('mysql2/promise');
const root=path.resolve(__dirname,'..'),baseline=process.env.GA_UPGRADE_BASELINE_DIR;
assert.ok(baseline,'GA_UPGRADE_BASELINE_DIR must identify the verified p24r16 source package');
const previous=process.env.GA_UPGRADE_PREVIOUS_DIR;
assert.ok(previous,'GA_UPGRADE_PREVIOUS_DIR must identify the published 2026.11.09-1 source');
const manifest=JSON.parse(fs.readFileSync(path.join(root,'installer/migrations.json'))),version=fs.readFileSync(path.join(root,'VERSION'),'utf8').trim();
const checks=[],pass=s=>{checks.push(s);console.log('PASS',s);};
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'ga-install-upgrade-'));
const ddl=s=>s.replace(/^DELIMITER .*$/gm,'').replace(/END\/\//g,'END;');
(async()=>{
 const db=await mysql.createConnection({host:'127.0.0.1',port:13310,user:'root',multipleStatements:true,dateStrings:true});
 try{
  let database='ga_upgrade_'+crypto.randomBytes(6).toString('hex')+'_test';
  const fresh=async()=>{
   await db.query('CREATE DATABASE IF NOT EXISTS `'+database+'` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;USE `'+database+'`;SET FOREIGN_KEY_CHECKS=0;');
   const [routines]=await db.query('SELECT ROUTINE_NAME,ROUTINE_TYPE FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA=DATABASE()');
   for(const row of routines)await db.query('DROP '+row.ROUTINE_TYPE+' `'+row.ROUTINE_NAME+'`');
   const [objects]=await db.query('SELECT TABLE_NAME,TABLE_TYPE FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE()');
   for(const kind of ['VIEW','BASE TABLE']){const names=objects.filter(x=>x.TABLE_TYPE===kind).map(x=>'`'+x.TABLE_NAME+'`');if(names.length)await db.query('DROP '+(kind==='VIEW'?'VIEW':'TABLE')+' '+names.join(','));}
   await db.query('SET FOREIGN_KEY_CHECKS=1');
  };
  const allowed=new Set(['database_metadata','template_database_metadata','ha_event_registry','ha_projection_fields','information_objects','function_information_dependencies','system_functions','schema_relation_semantics','schema_absence_semantics','system_check_expectations','verification_requirements_catalog','verification_decisions_catalog','verification_verifications','verification_requirements','verification_test_definitions','verification_verification_requirements','verification_verification_tests','verification_decision_requirements','verification_uat_steps']);
  const hash=async(connection=db)=>{
   const [tables]=await connection.query("SELECT TABLE_NAME FROM information_schema.tables WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME");const out={};
   for(const {TABLE_NAME:name} of tables){if(allowed.has(name)||(name.startsWith('verification_')&&!['verification_test_runs','verification_test_results'].includes(name))||name==='database_migrations'||name.startsWith('start_field_')||name.startsWith('session_start_attempt'))continue;
    const [rows]=await connection.query('SELECT * FROM `'+name+'`');const serial=rows.map(r=>JSON.stringify(r)).sort();out[name]=crypto.createHash('sha256').update(JSON.stringify(serial)).digest('hex');
   }return out;
  };
  const input=(folder,env)=>{
   const data=path.join(folder,'data');fs.mkdirSync(data,{recursive:true});fs.copyFileSync(path.join(root,'nodered/flows.template.json'),path.join(data,'flows.json'));fs.writeFileSync(path.join(data,'flows_cred.json'),'{}\n');
   const state=path.join(folder,'state');fs.writeFileSync(state,'running');const bin=path.join(folder,'bin');fs.mkdirSync(bin);
   fs.symlinkSync(path.join(root,'tests/docker-install-simulator.py'),path.join(bin,'docker'));
   return {...process.env,...env,PATH:bin+path.delimiter+process.env.PATH,GA_INSTALLER_SIMULATOR_DATABASE:database,GA_INSTALLER_SIMULATOR_DATA:data,GA_INSTALLER_SIMULATOR_STATE:state};
  };
  const run=(env,expected=0)=>{const result=spawnSync('bash',[path.join(root,'installer/install.sh')],{cwd:root,env,encoding:'utf8',maxBuffer:2e6});assert.equal(result.status,expected,result.stdout+'\n'+result.stderr);return result.stdout;};
  for(const source of [...manifest.supported_sources,...Object.keys(manifest.patch_sources)]){
   const patch=Object.hasOwn(manifest.patch_sources,source),fixture=patch?previous:baseline;
   const fixtureManifest=patch?JSON.parse(fs.readFileSync(path.join(fixture,'installer/migrations.json'),'utf8')):null;
   database='ga_upgrade_'+crypto.randomBytes(6).toString('hex')+'_test';
   await fresh();for(const f of manifest.fresh_files)await db.query(ddl(fs.readFileSync(path.join(fixture,f),'utf8')));
   await db.query('UPDATE database_metadata SET application_version=?;UPDATE template_database_metadata SET application_version=?',[source,source]);
   if(patch){const receipt=manifest.patch_sources[source],h=crypto.createHash('sha256');for(const f of fixtureManifest.upgrade_files)h.update(f+'\0').update(fs.readFileSync(path.join(fixture,f))).update('\0');assert.equal(h.digest('hex'),receipt.checksum_sha256);await db.query('INSERT INTO database_migrations VALUES(?,?,?,?,UTC_TIMESTAMP(3))',[receipt.migration_id,receipt.checksum_sha256,'empty',source]);}
   const by=Object.fromEntries(JSON.parse(fs.readFileSync(path.join(baseline,'nodered/flows.template.json'))).map(n=>[n.id,n]));
   const call=(id,msg={})=>new Function('msg','node',by[id].func)(msg,{warn(){},error(e){throw Error(e)}});
   const execute=async msg=>{if(Array.isArray(msg))msg=msg[0];return {...msg,payload:(await db.query(msg.topic,msg.payload))[0]};};
   const start=async batch=>{await execute(call('p20_template_select',{payload:'w3470-standard@3.0'}));await db.query('UPDATE session_setup_draft SET batch_name=?,pitch_time_mode=\'specified\',pitched_at=UTC_TIMESTAMP(3)-INTERVAL 2 DAY',[batch]);const context=await execute(call('p20_start_guard'));const write=call('p20_start_context_result',context);assert.ok(write[0]);await execute(write[0]);return write[0].ga_session_id;};
   const old=await start('Beholdt tidligere gjæring');
   await db.query("INSERT INTO session_lifecycle_events(lifecycle_event_id,session_id,lifecycle,occurred_at,note,operation_id,created_at) VALUES('upgrade-old-end',?,'completed',UTC_TIMESTAMP(3),'Fixture','upgrade-old-end',UTC_TIMESTAMP(3));INSERT INTO session_release_events(release_event_id,session_id,released_at,operation_id,created_at) VALUES('upgrade-old-release',?,UTC_TIMESTAMP(3),'upgrade-old-release',UTC_TIMESTAMP(3));",[old,old]);
   const active=await start('Aktiv gjæring under oppgradering');
   // Retain a new mutable draft alongside an active session, plus manual history.
   await db.query("UPDATE session_setup_draft SET slurry_volume_ml=4000,slurry_generation=2,slurry_source_batch='IPL',oxygenation_note='Bevar dette';INSERT INTO session_notes(note_id,session_id,noted_at,note_text,operation_id,created_at) VALUES('upgrade-note',?,UTC_TIMESTAMP(3),'Bevar øæå 🍺','upgrade-note',UTC_TIMESTAMP(3))",[active]);
   if(patch)await db.query("CALL ga_read_start_context('upgrade-retained-attempt',NULL)");
   const before=await hash();assert.ok(Object.keys(before).length>180);
   const folder=path.join(temporary,source);fs.mkdirSync(folder);const env=input(folder,{});
   const startRows=patch?JSON.stringify((await db.query('SELECT * FROM session_start_attempts ORDER BY attempt_id;SELECT * FROM session_start_attempt_fields ORDER BY attempt_id,entity_id'))[0]):null;
   if(patch){
    await db.query('UPDATE database_migrations SET checksum_sha256=REPEAT(\'0\',64)');run(env,1);assert.equal(fs.readFileSync(env.GA_INSTALLER_SIMULATOR_STATE,'utf8'),'running');
    await db.query('UPDATE database_migrations SET checksum_sha256=?',[manifest.patch_sources[source].checksum_sha256]);
    await db.query('ALTER TABLE session_setup_draft ADD COLUMN unknown_column INTEGER');run(env,1);assert.equal(fs.readFileSync(env.GA_INSTALLER_SIMULATOR_STATE,'utf8'),'running');await db.query('ALTER TABLE session_setup_draft DROP COLUMN unknown_column');
    pass(source+': invalid prior receipt and altered schema reject file upgrade before stopping Node-RED');
   }
   if(source===manifest.supported_sources[0]){
    await db.query('ALTER TABLE session_setup_draft ADD COLUMN unknown_column INTEGER');
    const rejected=run(env,1);assert.match(rejected,/Databasestrukturen avviker/);assert.equal(fs.readFileSync(env.GA_INSTALLER_SIMULATOR_STATE,'utf8'),'running');
    await db.query('ALTER TABLE session_setup_draft DROP COLUMN unknown_column');
    env.GA_SIMULATE_DUMP_FAILURE='1';run(env,1);delete env.GA_SIMULATE_DUMP_FAILURE;
    assert.deepEqual(await hash(),before);assert.equal((await db.query("SELECT COUNT(*) n FROM information_schema.tables WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='database_migrations'"))[0][0].n,0);
    fs.writeFileSync(env.GA_INSTALLER_SIMULATOR_STATE,'running');
    pass('changed source structure and failed backup prevent migration and preserve all existing domain rows');
   }
   const output=run(env);assert.match(output,/RESULTAT: PASS/);assert.ok(output.includes('Databaseplan: '+(patch?'patch':'upgrade')));
   if(patch){assert.equal(JSON.stringify((await db.query('SELECT * FROM session_start_attempts ORDER BY attempt_id;SELECT * FROM session_start_attempt_fields ORDER BY attempt_id,entity_id'))[0]),startRows);assert.doesNotMatch(output,/-> (?:2026\.11\.09-1-schema|11-runtime-routines|20-views)\.sql/);}
   assert.deepEqual(await hash(),before,'every existing user/domain table must retain byte-equivalent rows');
   assert.equal((await db.query('SELECT session_id FROM v_active_session'))[0][0].session_id,active);
   assert.equal((await db.query('SELECT check_status FROM v_system_check_session'))[0][0].check_status,'ok');assert.equal(Number((await db.query('SELECT COUNT(*) n FROM v_metadata_lineage_gaps'))[0][0].n),0);if(!patch)assert.equal((await db.query("SELECT status FROM verification_decisions_catalog WHERE decision_id='DEC-GA-006'"))[0][0].status,'deprecated');
   const reports=fs.readdirSync(path.join(root,'install-reports')).filter(f=>f.endsWith('.json')).sort();const report=JSON.parse(fs.readFileSync(path.join(root,'install-reports',reports.at(-1))));
   assert.equal(report.prototype_database_reset,false);assert.equal(report.backup_verified,true);assert.equal(report.database_source_version,source);assert.ok(fs.statSync(path.join(report.backup_directory,'database.sql.gz')).size>0);
   const dump=spawnSync('gzip',['-dc',path.join(report.backup_directory,'database.sql.gz')],{maxBuffer:64e6});assert.equal(dump.status,0);
   // Restore on a second isolated server, retaining the original database name.
   // This also proves that no view silently reads the still-running source DB.
   const restoreData=path.join(folder,'restore-data'),base=process.env.GA_MARIADB_BASEDIR;
   const init=spawnSync(path.join(base,'bin/mariadb-install-db'),['--no-defaults','--user=root','--auth-root-authentication-method=normal','--basedir='+base,'--datadir='+restoreData],{env:process.env,encoding:'utf8',maxBuffer:2e6});assert.equal(init.status,0,init.stdout+init.stderr);
   const restoreLog=fs.openSync(path.join(folder,'restore-server.log'),'w');
   const server=spawn(process.env.GA_MARIADB_SERVER,['--no-defaults','--user=root','--basedir='+base,'--datadir='+restoreData,'--socket=','--pid-file='+path.join(folder,'restore.pid'),'--port=13311','--bind-address=127.0.0.1','--innodb-buffer-pool-size=64M','--innodb-use-native-aio=0','--innodb-flush-method=fsync'],{env:process.env,stdio:['ignore',restoreLog,restoreLog]});
   let restored=null;
   try{
    for(let n=0;n<40;n++){try{restored=await mysql.createConnection({host:'127.0.0.1',port:13311,user:'root',multipleStatements:true,dateStrings:true});break;}catch{await new Promise(resolve=>setTimeout(resolve,100));}}
    assert.ok(restored,'isolated restore server ready');await restored.query('CREATE DATABASE `'+database+'` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;USE `'+database+'`;');
    const restore=spawnSync(process.env.GA_MARIADB_CLIENT,['--no-defaults','--host=127.0.0.1','--port=13311','-uroot',database],{input:dump.stdout,maxBuffer:20e6});assert.equal(restore.status,0,String(restore.stderr));
    assert.deepEqual(await hash(restored),before,'the actual backup must restore all preserved rows');
    assert.equal((await restored.query('SELECT session_id FROM v_active_session'))[0][0].session_id,active);
   }finally{if(restored)await restored.end();if(server.exitCode===null){const stopped=new Promise(resolve=>server.once('exit',resolve));server.kill('SIGTERM');await stopped;}fs.closeSync(restoreLog);}
   pass(source+': actual installer upgrades an active/retained fermentation without changing any domain table, and its compressed dump restores identically');
   // Reinstall the same target without replaying migration SQL.
   run(env);const after=await hash();run(env);assert.deepEqual(await hash(),after);assert.equal((await db.query('SELECT COUNT(*) n FROM database_migrations'))[0][0].n,patch?2:1);
   const [expectations]=await db.query("SELECT expected_text FROM system_check_expectations WHERE expectation_key='application_version'");assert.ok(expectations.length>=2);assert.ok(expectations.every(e=>e.expected_text===version));
   pass(source+': reinstall keeps data and matching migration receipts; version expectations agree');
  }
  // Unknown version and known-version schema tampering must fail before stop/backup/mutation.
  const folder=path.join(temporary,'reject');fs.mkdirSync(folder);const env=input(folder,{});const before=await hash();
  await db.query("UPDATE database_metadata SET application_version='unknown';UPDATE template_database_metadata SET application_version='unknown'");run(env,1);assert.equal(fs.readFileSync(env.GA_INSTALLER_SIMULATOR_STATE,'utf8'),'running');assert.deepEqual(await hash(),before);
  pass('unknown source is rejected before stopping Node-RED or changing user data');
  database='ga_upgrade_'+crypto.randomBytes(6).toString('hex')+'_test';await fresh();const freshFolder=path.join(temporary,'fresh');fs.mkdirSync(freshFolder);const freshEnv=input(freshFolder,{});const installed=run(freshEnv);assert.match(installed,/Databaseplan: fresh/);assert.equal((await db.query('SELECT COUNT(*) n FROM sessions'))[0][0].n,0);assert.equal((await db.query('SELECT COUNT(*) n FROM database_migrations'))[0][0].n,1);pass('fresh installation initializes an empty database without a synthetic session or reset');
  const sources=[...new Set(['installer/install.sh','installer/database-plan.py','installer/backup-database.py','installer/migrations.json',...manifest.upgrade_files,...manifest.patch_files,'tests/test-install-upgrade-live.js','tests/docker-install-simulator.py'])];
  fs.writeFileSync(path.join(root,'verification/install-upgrade-regression.json'),JSON.stringify({application_version:version,server_version:(await db.query('SELECT VERSION() v'))[0][0].v,status:'pass',docker_transport:'simulated',target_ha_uat:'not_run',supported_sources:[...manifest.supported_sources,...Object.keys(manifest.patch_sources)],checks,source_fingerprints:Object.fromEntries(sources.map(f=>[f,crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex')]))},null,2)+'\n');
 }finally{await db.end();fs.rmSync(temporary,{recursive:true,force:true});}
})().catch(e=>{console.error(e.code||'ASSERT',e.sqlMessage||e.stack);process.exitCode=1;});
