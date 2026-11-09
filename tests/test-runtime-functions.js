'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const releaseVersion=fs.readFileSync(path.join(root,'VERSION'),'utf8').trim();
const flow=JSON.parse(fs.readFileSync(path.join(root,'nodered/flows.template.json'),'utf8'));
const haContract=JSON.parse(fs.readFileSync(path.join(root,'contracts/ha-node-red-contract.json'),'utf8'));
const inputContracts=(context)=>{const field=context==='start'?'session_field':'measurement_field';const numbers=haContract.input_bindings.filter(b=>b[field]).flatMap(b=>{const n=haContract.number_constraints.find(n=>n.entity_id===b.entity_id);return n?[{_set:'number_contract',field_name:b[field],converter_id:b.converter_id,display_name:b[field],...n}]:[];});const selects=haContract.input_bindings.filter(b=>b[field]).flatMap(b=>haContract.input_value_mappings.filter(m=>m.entity_id===b.entity_id).map(m=>({_set:'select_contract',field_name:b[field],database_value:m.database_value})));return [numbers,selects];};
const byId=Object.fromEntries(flow.map(n=>[n.id,n]));
function invoke(id,msg,globalObj={get:()=>null}){
  const n=byId[id];
  if(id==='p20_systemcheck_result')msg={...msg,payload:[...msg.payload,[{_set:'session_check',check_id:'session',check_status:'ok',severity:'info',summary:'Ingen operativ session'}],[{_set:'start_readiness',ready_to_start:1,message:'Startgrunnlag OK fra DB-fixture'}]]};
  if(id==='p20_start_context_result'){const d=msg.payload[0]?.[0]||{};const fields=haContract.input_bindings.filter(b=>b.session_field).map(b=>({_set:'start_fields',field_name:b.session_field,converter_id:b.converter_id,input_type:['number','integer'].includes(b.converter_id)?'number':b.converter_id,required_value:0,applicable:1,database_value:d[b.session_field]}));msg={...msg,payload:[...msg.payload,fields,[{_set:'start_validation',ready_to_start:1,message:'Eksplisitt DB-valideringsfixture',...msg.dbStartValidation}]]};}
  if(id==='p20_measurement_context_result'){msg={...msg,payload:[...msg.payload,...inputContracts('measurement')]};const row=msg.payload.find(rows=>rows[0]?._set==='session')?.[0];if(row)row.database_now='2026-10-10 20:00:00.000';}

  msg={_msgid:'unit-msg',...msg};
  const node={warn:()=>{},status:()=>{},error:e=>{throw new Error(String(e))}};
  return new Function('msg','flow','global','node',n.func)(msg,null,globalObj,node);
}
const draft={
 database_now:new Date().toISOString(),resolved_pitched_at:new Date(Date.now()-3600000).toISOString(),session_id_candidate:'unit-start',draft_key:'current',template_version_id:'w3470-standard@3.0',is_demo:0,template_id:'w3470-standard',template_status:'published',
 batch_name:'runtime-function-test',pitch_time_mode:'specified',pitched_at:new Date(Date.now()-3600000).toISOString(),expected_attenuation_min_percent:80,expected_attenuation_max_percent:84,
 volume_l:150,pitch_mode_id:'dry',pitch_temperature_c:10,yeast_amount_g:200,slurry_volume_ml:null,slurry_source_batch:null,slurry_generation:null,oxygenation_note:null,
 measurement_method_id:'refractometer',measured_sg:1.052,sample_temperature_c:20,calibration_temperature_c:20,
 manual_temperature_c:10,pressure_bar:0,cooler_setpoint_c:10,cooler_calibration_offset_c:0,airlock_activity:'none',
 acetaldehyde_level:0,diacetyl_level:0,wort_like_level:0,sulfur_so2_level:0,sulfur_h2s_level:0,clarity_level:0,settling_yeast_level:0,settling_minutes:0,user_conclusion:'uncertain',measurement_note:null
};
const sourceRow={_set:'measurement_source',source_profile_id:'tilt-pro-blue-ha',name:'Tilt Pro Blue · Home Assistant',source_type:'home_assistant',sg_entity_id:'sensor.bryggeri_tilt_pro_blue_bryggeri_tilt_pro_blue_sg',temperature_entity_id:'sensor.bryggeri_tilt_pro_blue_bryggeri_tilt_pro_blue_temperatur',heartbeat_entity_id:'sensor.bryggeri_tilt_pro_blue_bryggeri_tilt_pro_blue_sist_oppdatert',rssi_entity_id:'sensor.bryggeri_tilt_pro_blue_bryggeri_tilt_pro_blue_rssi',poll_interval_seconds:300,gap_threshold_seconds:300,status:'active'};
const measurementStatusRow={...sourceRow,_set:'measurement_status',state:'IDLE',message:'Målekilde konfigurert · ingen aktiv gjæring',session_id:null,is_demo:null,lifecycle:null};
let out=invoke('p20_start_context_result',{payload:[[draft],[],[sourceRow]]});
assert.ok(out[0]);assert.equal(out[1],null);assert.equal(out[2],null);
assert.equal(out[0].ga_route,'start_write');
assert.equal((out[0].topic.match(/\?/g)||[]).length,44);
assert.equal(out[0].payload.length,44);
assert.match(out[0].topic,/CALL ga_start_session_tx\(\)/);
assert.doesNotMatch(out[0].topic,/START TRANSACTION/);
assert.equal(out[0].payload[7],1.052); // actual OG for refractometer before fermentation
assert.equal(out[0].payload[20],1.052); // measured SG; expected FG is derived inside MariaDB
assert.equal(out[0].payload[3],'tilt-pro-blue-ha'); // DB-configured measurement source

const bad={...draft,measured_sg:null,og:1.052};
out=invoke('p20_start_context_result',{payload:[[bad],[],[sourceRow]],dbStartValidation:{ready_to_start:0,message:'Mangler: measured_sg'}});
assert.equal(out[0],null);assert.match(out[1].payload,/measured_sg/);assert.equal(out[2].ga_event.code,'START_REJECTED');

// pitch_time_mode=now must not require a persisted explicit timestamp.
const nowDraft={...draft,pitch_time_mode:'now',pitched_at:null,resolved_pitched_at:draft.database_now};
out=invoke('p20_start_context_result',{payload:[[nowDraft],[],[sourceRow]]});
assert.ok(out[0]);assert.equal(out[1],null);assert.equal(out[0].payload.length,44);assert.equal(out[0].payload[42],'expected-attenuation-midpoint-v1');

// No HA fallback: persisted draft is authoritative even if a stray command value is supplied.
out=invoke('p20_start_context_result',{ga_visible_sg:1.056,payload:[[bad],[],[sourceRow]],dbStartValidation:{ready_to_start:0,message:'Mangler: measured_sg'}});
assert.equal(out[0],null);assert.match(out[1].payload,/measured_sg/);


// Regression: a late HA template echo after Start must not overwrite status or draft.
out=invoke('p20_template_result',{ga_selected:'w3470-standard@3.0',payload:[[{active_count:1}],[]]});
assert.deepEqual(out,[null,null]);

// Template selection may only write a draft when MariaDB has no active session.
out=invoke('p20_template_select',{payload:'w3470-standard@3.0'});
assert.match(out.topic,/CALL ga_select_start_template_tx/);assert.match(fs.readFileSync(path.join(root,'sql/11-runtime-routines.sql'),'utf8'),/NOT EXISTS\(SELECT 1 FROM v_current_session\)/);
assert.equal(out.payload[0],'w3470-standard@3.0');
// Published versions from the actual restore SQL become HA select options,
// independently of whether a pre-start draft or active session exists.
const publishedTemplate={version_id:'w3470-standard@3.0',template_id:'w3470-standard',name:'W-34/70',version_label:'3.0'};
let restore=invoke('p20_restore_result',{payload:[[publishedTemplate],[],[],[],[],[{_set:'ha_selection',selected_template:'Velg template',public_lifecycle:'idle',options_payload:JSON.stringify({options:['Velg template','w3470-standard@3.0']})}]]});
assert.deepEqual(restore[0].payload.options,['Velg template','w3470-standard@3.0']);
assert.equal(restore[5].payload,'Velg template');
restore=invoke('p20_restore_result',{payload:[[publishedTemplate],[draft],[],[],[],[{_set:'ha_selection',selected_template:'w3470-standard@3.0',public_lifecycle:'configured',options_payload:JSON.stringify({options:['Velg template','w3470-standard@3.0']})}]]});
assert.equal(restore[5].payload,'w3470-standard@3.0');

const contract=JSON.parse(fs.readFileSync(path.join(root,'contracts/ha-node-red-contract.json'),'utf8'));
const states=Object.fromEntries(contract.entities.filter(e=>e.status==='active').map(e=>[e.entity_id,{state:'unknown'}]));
states['sensor.gjaeringsassistent_livslop']={state:'configured'}; states['sensor.gjaeringsassistent_systemstatus']={state:'OK'}; states['select.gjaeringsassistent_template']={state:'w3470-standard@3.0'};
states[sourceRow.sg_entity_id]={state:'1.030'};states[sourceRow.temperature_entity_id]={state:'10.2'};states[sourceRow.heartbeat_entity_id]={state:new Date().toISOString()};states[sourceRow.rssi_entity_id]={state:'-67'};

// MariaDB-driven HA registry reconciliation and bootstrap.
const registryRows=contract.entities.filter(e=>e.status==='active').map((e,i)=>({_set:'ha_registry',entity_id:e.entity_id,config_id:e.config_id,entity_type:e.entity_type,direction:e.direction,required:e.entity_id==='number.gjaeringsassistent_pitchtemperatur_c'?0:1,status:'active',bootstrap_mode:e.entity_type==='button'?'registration_only':'literal_then_runtime',bootstrap_value:e.entity_type==='button'?null:'unknown',bootstrap_slot:e.entity_type==='button'?null:1,runtime_node_id:'runtime',bootstrap_node_id:e.entity_type==='button'?null:'bootstrap',sort_order:i+1}));
const aliasRows=[{_set:'ha_alias',alias_entity_id:'select.gjaeringsassistent_templatevalg',entity_id:'select.gjaeringsassistent_template',alias_kind:'legacy'},{_set:'ha_alias',alias_entity_id:'number.gjaeringsassistent_kontroll_raverdi',entity_id:'number.gjaeringsassistent_malt_sg',alias_kind:'legacy'}];
const lineageRow={_set:'lineage',active_functions:19,active_objects:200,orphan_functions:0,missing_producers:0,missing_consumers:0};
const checkDefinitions=['database','schema','writable','home_assistant','session','frontend_publishing','node_red','measurement_source','runtime','configuration','metadata_lineage','time','start_readiness','runtime_issues','completed_archive'].map((check_id,i)=>({_set:'check_definitions',check_id,label:check_id,category:'test',enabled:1,sort_order:i+1,failure_severity:'error'}));
const checkExpectations=[
 ...['missing_absence','missing_relation','version_disagreement'].map(key=>({_set:'check_expectations',check_id:'schema',expectation_key:key,expected_number:0,expected_text:null})),
 {_set:'check_expectations',check_id:'schema',expectation_key:'base_tables',expected_number:140,expected_text:null},
 {_set:'check_expectations',check_id:'schema',expectation_key:'views',expected_number:22,expected_text:null},
 {_set:'check_expectations',check_id:'schema',expectation_key:'innodb_tables',expected_number:140,expected_text:null},
 {_set:'check_expectations',check_id:'configuration',expectation_key:'application_version',expected_number:null,expected_text:releaseVersion},

 {_set:'check_expectations',check_id:'configuration',expectation_key:'ha_registry_active_count',expected_number:75,expected_text:null},
 {_set:'check_expectations',check_id:'configuration',expectation_key:'ha_registry_required_count',expected_number:74,expected_text:null},
 {_set:'check_expectations',check_id:'configuration',expectation_key:'published_templates_min',expected_number:1,expected_text:null},
 {_set:'check_expectations',check_id:'frontend_publishing',expectation_key:'application_version',expected_number:null,expected_text:releaseVersion},
 {_set:'check_expectations',check_id:'frontend_publishing',expectation_key:'artifact_count',expected_number:3,expected_text:null}
];
const frontendPublication={_set:'frontend_publication',status:'ok',application_version:releaseVersion,mount_verified:1,artifact_count:3,matching_artifacts:3,manifest_sha256:'a'.repeat(64)};
const legacyStates={'select.gjaeringsassistent_templatevalg':{state:'w3470-standard@3.0'},'number.gjaeringsassistent_kontroll_raverdi':{state:'1.050'}};
let reconcile=invoke('p21_ha_registry_result',{payload:[registryRows,aliasRows]},{get:k=>k==='homeassistant'?{homeAssistant:{states:legacyStates}}:null});
assert.ok(Array.isArray(reconcile));
assert.ok(Array.isArray(reconcile[0]));
assert.equal(reconcile[0][0].payload.data.type,'config/entity_registry/update');
const migrations=Object.fromEntries(reconcile[0].map(m=>[m.payload.data.entity_id,m.payload.data.new_entity_id]));
assert.equal(migrations['select.gjaeringsassistent_templatevalg'],'select.gjaeringsassistent_template');
assert.equal(migrations['number.gjaeringsassistent_kontroll_raverdi'],'number.gjaeringsassistent_malt_sg');
assert.equal(reconcile[1].ga_ha_registry.length,75);
const desiredStates={'select.gjaeringsassistent_template':{state:'w3470-standard@3.0'},'number.gjaeringsassistent_malt_sg':{state:'1.050'}};
reconcile=invoke('p21_ha_registry_result',{payload:[registryRows,aliasRows]},{get:k=>k==='homeassistant'?{homeAssistant:{states:desiredStates}}:null});
assert.equal(reconcile[0],null);
const boot=invoke('p21_ha_bootstrap_dispatch',{ga_ha_registry:[{entity_id:'sensor.test',config_id:'cfg',entity_type:'sensor',bootstrap_mode:'literal_then_runtime',bootstrap_value:'idle',bootstrap_slot:1}]});
assert.equal(boot.length,64);assert.equal(boot[0].payload,'idle');assert.equal(boot[1],null);

const sourceCheckFixture={_set:'measurement_check',check_id:'measurement_source',check_status:'ok',severity:'info',summary:'Explicit DB source-check fixture'};
const globalObj={get:k=>k==='homeassistant'?{homeAssistant:{states}}:null};
out=invoke('p20_systemcheck_result',{ga_ha_states:Object.entries(states).map(([entity_id,value])=>({entity_id,...value})),payload:[
 [{check_id:'missing_absence',n:0}],[{check_id:'missing_relation',n:0}],[{check_id:'version_disagreement',n:0}],[{check_id:'base_tables',n:140}],[{check_id:'views',n:22}],[{check_id:'innodb_tables',n:140}],
 [{check_id:'published_templates',n:1}],[{check_id:'active_sessions',n:0}],[{check_id:'current_sessions',n:0}],[{check_id:'completed_sessions',n:0}],[{check_id:'active_process',n:0}],[{check_id:'active_biology',n:0}],[{check_id:'active_issues',n:0}],[{_set:'archive_readiness',missing_archive_count:0}],
 [{read_only:'OFF',global_read_only:'OFF',database_writable:1,database_epoch:Date.now()/1000}],
 [{metadata_id:1,schema_version:4,application_version:releaseVersion}],[draft],[],registryRows,aliasRows,[measurementStatusRow],[sourceCheckFixture],[lineageRow],checkDefinitions,checkExpectations,[frontendPublication]
]},globalObj);
assert.equal(out.ga_route,'system_check_write');
assert.equal(out.ga_systemcheck.overall,'ok');
assert.equal((out.topic.match(/\?/g)||[]).length,out.payload.length);
assert.ok(out.ga_systemcheck.checks.some(c=>c.id==='start_readiness'&&c.status==='ok'));
assert.ok(out.ga_systemcheck.checks.some(c=>c.id==='metadata_lineage'&&c.status==='ok'));
assert.ok(out.ga_systemcheck.checks.some(c=>c.id==='frontend_publishing'&&c.status==='ok'));
assert.ok(out.ga_systemcheck.checks.some(c=>c.id==='measurement_source'&&c.status==='ok'));

// MariaDB 12.3.3 returns enum values; only the explicit database decision
// may establish writable status. Missing or malformed evidence must be visible.
for(const decision of [1,'1']){
 const result=invoke('p20_systemcheck_result',{payload:[[{read_only:'OFF',global_read_only:'OFF',database_writable:decision,database_epoch:Date.now()/1000}],[sourceCheckFixture],checkDefinitions]},globalObj);
 assert.equal(result.ga_systemcheck.checks.find(c=>c.id==='writable').status,'ok');
}
for(const mode of ['ON','NO_LOCK','NO_LOCK_NO_ADMIN']){
 const result=invoke('p20_systemcheck_result',{payload:[[{read_only:mode,global_read_only:mode,database_writable:0,database_epoch:Date.now()/1000}],[sourceCheckFixture],checkDefinitions]},globalObj);
 const writable=result.ga_systemcheck.checks.find(c=>c.id==='writable');
 assert.equal(writable.status,'error');assert.ok(writable.summary.includes('read_only='+mode));
}
for(const decision of [undefined,null,'',false,true,'OFF',2,NaN]){
 const result=invoke('p20_systemcheck_result',{payload:[[{read_only:'OFF',global_read_only:'OFF',database_writable:decision,database_epoch:Date.now()/1000}],[sourceCheckFixture],checkDefinitions]},globalObj);
 const writable=result.ga_systemcheck.checks.find(c=>c.id==='writable');
 assert.equal(writable.status,'error');assert.match(writable.summary,/mangler\/ugyldig/);
}

// HA publish regression: null completed_at and partial template data must never create invalid HA states/attributes.
const partialPublish=invoke('p20_publish_status',{ga_state:{session:{session_id:'active-x',batch_name:'Active X',lifecycle:'active',completed_at:null},active:{session_id:'active-x',batch_name:'Active X',lifecycle:'active'},draft:null,notes:[],status_message:'OK'}});
assert.equal(partialPublish.ga_route,'ha_status_read');assert.match(partialPublish.topic,/v_ha_status_payloads/);
// Same contract must work when the HA server cache is stored under a server-specific global-context key.
const altGlobal={get:k=>k==='homeassistant'?{gjaeringsassistentServer:{states}}:null};
const altOut=invoke('p20_systemcheck_result',{ga_ha_states:Object.entries(states).map(([entity_id,value])=>({entity_id,...value})),payload:[
 [{check_id:'missing_absence',n:0}],[{check_id:'missing_relation',n:0}],[{check_id:'version_disagreement',n:0}],[{check_id:'base_tables',n:140}],[{check_id:'views',n:22}],[{check_id:'innodb_tables',n:140}],
 [{check_id:'published_templates',n:1}],[{check_id:'active_sessions',n:0}],[{check_id:'current_sessions',n:0}],[{check_id:'completed_sessions',n:0}],[{check_id:'active_process',n:0}],[{check_id:'active_biology',n:0}],[{check_id:'active_issues',n:0}],[{_set:'archive_readiness',missing_archive_count:0}],
 [{read_only:'OFF',global_read_only:'OFF',database_writable:1,database_epoch:Date.now()/1000}],
 [{metadata_id:1,schema_version:4,application_version:releaseVersion}],[draft],[],registryRows,aliasRows,[measurementStatusRow],[sourceCheckFixture],[lineageRow],checkDefinitions,checkExpectations,[frontendPublication]
]},altGlobal);
assert.ok(altOut.ga_systemcheck.checks.some(c=>c.id==='home_assistant'&&c.status==='ok'));
assert.ok(altOut.ga_systemcheck.checks.some(c=>c.id==='time'&&c.status==='ok'));

const statesWithLegacy={...states,'select.gjaeringsassistent_templatevalg':{state:'w3470-standard@3.0'}};
const legacyGlobal={get:k=>k==='homeassistant'?{homeAssistant:{states:statesWithLegacy}}:null};
const outLegacy=invoke('p20_systemcheck_result',{ga_ha_states:Object.entries(statesWithLegacy).map(([entity_id,value])=>({entity_id,...value})),payload:[
 [{check_id:'missing_absence',n:0}],[{check_id:'missing_relation',n:0}],[{check_id:'version_disagreement',n:0}],[{check_id:'base_tables',n:140}],[{check_id:'views',n:22}],[{check_id:'innodb_tables',n:140}],
 [{check_id:'published_templates',n:1}],[{check_id:'active_sessions',n:0}],[{check_id:'current_sessions',n:0}],[{check_id:'completed_sessions',n:0}],[{check_id:'active_process',n:0}],[{check_id:'active_biology',n:0}],[{check_id:'active_issues',n:0}],[{_set:'archive_readiness',missing_archive_count:0}],
 [{read_only:'OFF',global_read_only:'OFF',database_writable:1,database_epoch:Date.now()/1000}],
 [{metadata_id:1,schema_version:4,application_version:releaseVersion}],[draft],[],registryRows,aliasRows,[measurementStatusRow],[sourceCheckFixture],[lineageRow],checkDefinitions,checkExpectations,[frontendPublication]
]},legacyGlobal);
assert.equal(outLegacy.ga_systemcheck.overall,'ok');
assert.ok(outLegacy.ga_systemcheck.checks.some(c=>c.id==='home_assistant'&&c.status==='ok'&&c.summary.includes('gamle aliaser finnes også')&&c.summary.includes('templatevalg')));

out=invoke('p20_technical_event_writer',{ga_event:{severity:'warning',event_type:'event',code:'TEST',subsystem:'test',message:'Test event',recoverable:1,blocks_operation:0}});
assert.equal(out.ga_route,'technical_event_write');
assert.equal((out.topic.match(/\?/g)||[]).length,out.payload.length);
console.log('RESULT: PASS – Start/SG contract, late-template regression, Systemkontroll and Technical Event SQL');

// Technical read-model: rich lists must be projected through the existing HA entities.
const nowSql=new Date().toISOString().replace('T',' ').replace('Z','');
const run={check_run_id:'syscheck-test',overall_status:'warning',checked_at:nowSql};
const results=[
 {check_id:'database',status:'ok',severity:'info',summary:'DB OK',created_at:nowSql},
 {check_id:'schema',status:'warning',severity:'warning',summary:'Schema warning',created_at:nowSql}
];
const issues=[{rn:1,issue_key:'system_check:schema',event_type:'issue_raised',severity:'warning',code:'SYSTEM_CHECK_SCHEMA',subsystem:'system_check',message:'Schema warning',occurred_at:nowSql,source_component:'p20_systemcheck'}];
const events=Array.from({length:8},(_,i)=>({event_id:`event-${i+1}`,severity:i===0?'warning':'info',code:`E${i+1}`,subsystem:'test',message:`event ${i+1}`,occurred_at:nowSql,source_component:'unit-test'}));
out=invoke('p20_systemcheck_write_result',{});assert.equal(out.ga_route,'ha_technical_read');assert.match(out.topic,/v_ha_technical_payloads/);out=invoke('p20_technical_event_result',{});assert.equal(out.ga_route,'ha_events_read');
console.log('RESULT: PASS – Technical rich read-model and local-time output regression');


// p18 Technical Notes regression: HA event -> transactional session_notes -> HA read-model attributes.
out=invoke('p20_note_save_query',{payload:{note:'Testnotat fra unit',operation_id:'note-unit-1'}});
assert.equal(out.ga_route,'note_save');
assert.match(out.topic,/INSERT (?:IGNORE )?INTO session_notes/);
assert.match(out.topic,/START TRANSACTION/);
assert.equal((out.topic.match(/\?/g)||[]).length,4);
assert.deepEqual(out.payload,['note-unit-1','Testnotat fra unit','note-unit-1','note-unit-1']);
const activeForNote={session_id:'session-note',is_demo:1,batch_name:'note-test',current_process_id:'P1',current_process_name:'Pitch',current_biological_phase_id:'B1',current_biological_phase_name:'Lag',template_version_id:'w3470-standard@3.0',template_name:'W-34/70',version_label:'3.0'};
const noteRows=[{note_id:'note-unit-1',session_id:'session-note',noted_at:nowSql,note_text:'Testnotat fra unit',operation_id:'note-unit-1'}];
out=invoke('p20_note_save_result',{ga_note_operation_id:'note-unit-1',payload:[[{_set:'ack',...noteRows[0]}],[{_set:'active',...activeForNote}],noteRows.map(r=>({_set:'notes',...r}))]});
assert.ok(out[0]);assert.ok(out[1]);
assert.equal(out[0].ga_state.notes.length,1);
assert.equal(out[0].ga_state.notes[0].note_text,'Testnotat fra unit');
assert.equal(out[0].ga_state.note_status,'OK · notat lagret');
assert.equal(out[1].ga_event.code,'NOTE_SAVED');
out=invoke('p20_publish_status',{ga_state:{active:activeForNote,draft:null,notes:noteRows,status_message:'Notat lagret'}});
assert.equal(out.ga_route,'ha_status_read');
console.log('RESULT: PASS – p18 Technical Notes path persisted/read-model contract');

// p20r1-revised8 Template editor: read-model + normalized draft-save contract.
out=invoke('p20_template_editor_read_result',{payload:[[
  {_set:'context',active_session_id:null,active_session_version_id:null,start_selected_version_id:null,admin_selected_version_id:null}
]]});
assert.equal(out.filename,'/data/gjaeringsassistent/ha-public/template-editor.json');
let editor=JSON.parse(out.payload);
assert.equal(editor.mode,'none');
assert.equal(editor.read_only,true);
assert.equal(editor.application_version,releaseVersion);
const tplQuery=invoke('p20_template_editor_query',{});
assert.doesNotMatch(tplQuery.topic,/AS _set,\* FROM/);
assert.match(tplQuery.topic,/AS _set,t\.\* FROM template_defaults t/);

const templateDraft={
 template_id:'unit-template',version_id:'unit-template@draft',status:'draft',name:'Unit template',
 defaults:{batch_name:'Unit',volume_l:150,og:1.050,expected_attenuation_min_percent:80,expected_attenuation_max_percent:84,pitch_temperature_c:10,pitch_mode:'dry',yeast_amount_g:200,measurement_method:'hydrometer',sample_temperature_c:20,calibration_temperature_c:20,manual_temperature_c:10,pressure_bar:0,cooler_setpoint_c:10,cooler_calibration_offset_c:0,airlock_activity:'none',acetaldehyde_level:0,diacetyl_level:0,wort_like_level:0,sulfur_so2_level:0,sulfur_h2s_level:0,clarity_level:0,settling_yeast_level:0,settling_minutes:0,user_conclusion:'uncertain',measurement_note:''},
 yeast:{id:'fermentis-w3470'},biology:{calculations:{sg_rate:{model:'endpoint_rate_v1',inputs:{series_sg:{source_kind:'series',source_id:'tilt_sg'}},parameters:{window_hours:24,minimum_samples:12,minimum_span_minutes:1080}}},phases:[{phase_id:'B1',name:'B1',description:'',criteria:[]}]},
 process:{slots:[{process_id:'P1',enabled:true,name:'P1',description:'',targets:[{target_id:'target-1',metric:'beer_temperature_c',model:'exact',label:'Temperatur',purpose:'',parameters:{value:10}}],actions:[{action_id:'action-1',action_type:'set_target',label:'Sett temperatur',parameters:{target_id:'target-1'}}],criteria:[]}]}
};
out=invoke('p20_template_save_query',{payload:{event:{data:{document:templateDraft,publish:false}}}});
assert.equal(out.ga_route,'template_editor_save');
assert.match(out.topic,/START TRANSACTION/);
assert.match(out.topic,/INSERT INTO template_process_targets/);
assert.match(out.topic,/INSERT INTO template_biology_calculation_linear_regression/);
assert.ok(out.payload.includes('endpoint_rate_v1'),'editor preserves the measured endpoint model and window row');
assert.match(out.topic,/INSERT INTO template_process_action_set_target/);
assert.equal((out.topic.match(/\?/g)||[]).length,out.payload.length);
const badTemplate=structuredClone(templateDraft);
badTemplate.process.slots[0].actions[0].parameters.target_id='missing-target';
out=invoke('p20_template_save_query',{payload:{event:{data:{document:badTemplate,publish:false}}}});
assert.equal(out,null);
console.log('RESULT: PASS – Template editor read-model and normalized draft-save validation');

// p23r1 Template library: admin selection is independent of Start/runtime, retired is reversible.
const libVersions=[
 {_set:'versions',version_id:'tpl@1.0',template_id:'tpl',status:'published',version_label:'1.0',based_on_version_id:null,name:'Published',revision_note:null,created_at:'2026-10-01 06:00:00',published_at:'2026-10-01 06:00:00',retired_at:null},
 {_set:'versions',version_id:'tpl@old',template_id:'tpl',status:'retired',version_label:'0.9',based_on_version_id:null,name:'Old',revision_note:null,created_at:'2026-09-01 06:00:00',published_at:'2026-09-01 06:00:00',retired_at:'2026-10-01 06:10:00'}
];
out=invoke('p20_template_editor_read_result',{payload:[[
 {_set:'context',active_session_id:'active-1',active_session_version_id:'tpl@1.0',start_selected_version_id:'tpl@1.0',admin_selected_version_id:'tpl@old'}
],libVersions]});
editor=JSON.parse(out.payload);
assert.equal(editor.lifecycle.state,'active');
assert.equal(editor.selected_version_id,'tpl@old');
assert.equal(editor.start_selected_version_id,'tpl@1.0');
assert.equal(editor.mode,'retired');
assert.equal(editor.read_only,true);
assert.equal(editor.catalogue.versions.find(v=>v.version_id==='tpl@old').is_selected,true);
assert.equal(editor.catalogue.versions.find(v=>v.version_id==='tpl@1.0').is_start_selected,true);
assert.equal(editor.catalogue.versions.find(v=>v.version_id==='tpl@1.0').is_active_session_source,true);
let admin=invoke('p22_template_admin_select_query',{payload:{event:{data:{version_id:'tpl@old'}}}});
assert.equal(admin.ga_editor_action,'select'); assert.match(admin.topic,/template_editor_state/); assert.deepEqual(admin.payload,['tpl@old']);
let lifecycleCmd=invoke('p22_template_lifecycle_query',{payload:{event:{data:{version_id:'tpl@1.0',action:'retire'}}}});
assert.equal(lifecycleCmd.ga_editor_action,'retire'); assert.match(lifecycleCmd.topic,/status='retired'/); assert.match(lifecycleCmd.topic,/DELETE FROM session_setup_draft/);
lifecycleCmd=invoke('p22_template_lifecycle_query',{payload:{event:{data:{version_id:'tpl@old',action:'reactivate'}}}});
assert.equal(lifecycleCmd.ga_editor_action,'reactivate'); assert.match(lifecycleCmd.topic,/status='published'/);
let clone=invoke('p20_template_clone_query',{payload:{event:{data:{source_version_id:'tpl@old',new_template_id:'new-template',new_name:'New template'}}}});
assert.equal(clone.ga_editor_action,'create_template'); assert.equal(clone.topic,'CALL ga_clone_template_tx(?,?,?,?);'); assert.equal(clone.payload[0],'tpl@old');assert.match(clone.payload[1],/^draft-.*-new-template$/);assert.deepEqual(clone.payload.slice(2),['new-template','New template']);
const cloneRoutine=fs.readFileSync(path.join(root,'sql/11-runtime-routines.sql'),'utf8').split('CREATE PROCEDURE ga_clone_template_tx')[1];
assert.match(cloneRoutine,/status IN \('published','retired'\)/);assert.match(cloneRoutine,/template_analysis_graphs/);assert.doesNotMatch(cloneRoutine.split('INSERT INTO template_defaults')[1].split(';')[0],/expected_fg_min|expected_fg_max/);assert.match(cloneRoutine,/EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL/);assert.ok(cloneRoutine.indexOf('INSERT INTO template_editor_state')<cloneRoutine.indexOf('COMMIT;'));
assert.doesNotMatch(clone.topic,/NOT EXISTS\(SELECT 1 FROM v_current_session\)/);
console.log('RESULT: PASS – p23r1 Template library lifecycle/admin separation');


// Technical export: timestamped structured JSON written through HA-public; entity set comes from DB registry.
const exportStates={'sensor.gjaeringsassistent_livslop':{state:'configured',last_changed:'2026-09-27T12:00:00Z',last_updated:'2026-09-27T12:00:00Z'},'select.gjaeringsassistent_template':{state:'w3470-standard@3.0',attributes:{options:['Velg template','w3470-standard@3.0']}}};
out=invoke('p20_technical_export_query',{payload:{event:{data:{filename:'20260927T142109-gjaeringsassistent-teknisk-status.json'}}}});
assert.equal(out.ga_route,'technical_export');
assert.equal(out.ga_export_filename,'20260927T142109-gjaeringsassistent-teknisk-status.json');
assert.match(out.topic,/ha_entity_registry/);
assert.match(out.topic,/technical_events/);
assert.match(out.topic,/system_check_results/);
assert.match(out.topic,/VERSION\(\) AS database_server_version/);
assert.match(out.topic,/AS database_collation_connection/);
out=invoke('p20_technical_export_query',{payload:{event:{data:{filename:'20260927T142109123-gjaeringsassistent-teknisk-status.json'}}}});
assert.equal(out.ga_export_filename,'20260927T142109123-gjaeringsassistent-teknisk-status.json');
out=invoke('p20_technical_export_result',{ga_export_filename:'20260927T142109-gjaeringsassistent-teknisk-status.json',payload:[
 [{_set:'export_meta',application_version:releaseVersion,exported_at:'2026-09-27T12:21:09Z',database_server_version:'12.3.3-MariaDB',database_sql_mode:'STRICT_TRANS_TABLES',database_character_set_connection:'utf8mb4',database_collation_connection:'utf8mb4_unicode_ci'}],
 [{_set:'active',session_id:'unit-session'}],
 [{_set:'draft',draft_key:'current'}],
 [{_set:'issues',issue_key:'unit-issue'}],
 [{_set:'events',event_id:'unit-event',occurred_at:'2026-09-27 12:21:09'}],
 [{_set:'run',check_run_id:'unit-check'}],
 [{_set:'results',check_id:'database',status:'ok'}],
 [{_set:'measurement_status',state:'LIVE',message:'HA-import aktiv',last_import_cutoff_display:'27.09.2026, 14:20'}],
 [{_set:'ha_registry',entity_id:'sensor.gjaeringsassistent_livslop'},{_set:'ha_registry',entity_id:'select.gjaeringsassistent_template'}],
 [{_set:'published_templates',version_id:'w3470-standard@3.0'}],
 [{_set:'analysis_baselines',baseline_value:1.0463,sample_count:3}],
 [{_set:'analysis_rejection_counts',reason_code:'regression_uncertainty_too_large',rejected_points:7}]
]},{get:k=>k==='homeassistant'?{homeAssistant:{states:exportStates}}:null});
assert.equal(out.ga_publication_target,'/data/gjaeringsassistent/ha-public/exports/20260927T142109-gjaeringsassistent-teknisk-status.json');
const techExport=JSON.parse(out.payload);
assert.equal(techExport.runtime.active_session.session_id,'unit-session');
assert.equal(techExport.runtime.dashboard_entities['sensor.gjaeringsassistent_livslop'].state,'configured');
assert.equal(techExport.active_problems.length,1);
assert.equal(techExport.technical_events.length,1);
assert.equal(techExport.system_check.results[0].check_id,'database');
assert.equal(techExport.application_version,releaseVersion);
assert.equal(techExport.exported_at,'2026-09-27T12:21:09Z');
assert.equal(techExport.measurement_source.status.state,'LIVE');
assert.equal(techExport.time_zone,'Europe/Oslo');
assert.equal(techExport.database_runtime.server_version,'12.3.3-MariaDB');
assert.equal(techExport.database_runtime.collation_connection,'utf8mb4_unicode_ci');
assert.equal(techExport.runtime.node_red_application_version,releaseVersion);
assert.deepEqual(techExport.runtime.dashboard_entities['select.gjaeringsassistent_template'].options,['Velg template','w3470-standard@3.0']);
assert.equal(techExport.template_selection.published_versions[0].version_id,'w3470-standard@3.0');
assert.equal(techExport.schema_version,'1.2');assert.equal(techExport.analysis_quality.baselines[0].baseline_value,1.0463);assert.equal(techExport.analysis_quality.rejection_counts[0].rejected_points,7);
console.log('RESULT: PASS – Technical structured export contract');

// p21r6 Gjæring overview + real-reference demo regression.
out=invoke('p20_demo_prepare_query',{});
assert.equal(out.ga_route,'demo_prepare');
assert.match(out.topic,/CALL ga_prepare_selected_demo_tx/);const demoPreparation=fs.readFileSync(path.join(root,'sql/11-runtime-routines.sql'),'utf8').split('CREATE PROCEDURE ga_prepare_selected_demo_tx()')[1];assert.match(demoPreparation,/w3470-standard@3\.0/);assert.match(demoPreparation,/NOT EXISTS\(SELECT 1 FROM v_current_session\)/);
const demoDraft={draft_key:'current',template_version_id:'w3470-standard@3.0',is_demo:0};
out=invoke('p20_demo_prepare_result',{payload:[[],[demoDraft]]});
assert.ok(out[0]);assert.equal(out[0].ga_demo,true);assert.equal(out[1].payload,'Demo · starter referansedemo');
out=invoke('p20_demo_seed_query',{ga_session_id:'demo-session'});
assert.equal(out.ga_route,'demo_seed');
assert.doesNotMatch(out.topic,/UPDATE sessions/);
assert.match(out.topic,/CALL ga_seed_demo_tx/);
out=invoke('p20_overview_query',{});
assert.equal(out.ga_route,'overview_read');
assert.match(out.topic,/CALL ga_read_overview/);
const overviewSource=fs.readFileSync(path.join(root,'tools/overview_reads.sql'),'utf8');
assert.match(overviewSource,/v_session_display_measurement_series/);
assert.match(overviewSource,/session_process_targets/);
assert.match(overviewSource,/biological_visits/);
out=invoke('p20_overview_result',{payload:[
 [{_set:'summary',session_id:'demo-session',batch_name:'Demo',is_demo:1,active_issue_count:0,og:1.049,expected_fg_min:1.010,expected_fg_max:1.013,pitched_at:'2026-09-26 12:00:00',current_process_order:3,current_process_name:'Demo P3',current_biological_phase_id:'B4',current_biological_phase_order:4,current_biological_phase_name:'Demo B4'}],
 [{_set:'series',at:'2026-09-27 12:00:00',sg:1.020,sg_min:1.0198,sg_max:1.0202,temperature_c:10,pressure_bar:0.5,temperature_plan_c:10,pressure_plan_bar:0.5}],
 [{_set:'observations',recorded_at:'2026-09-27 12:00:00',corrected_sg:1.020,manual_temperature_c:10,pressure_bar:0.5,note:'demo'}],
 [{_set:'process',process_id:'P3',process_order:3,name:'Demo P3',started_at:'2026-09-27 10:00:00',target_temperature_c:10,target_pressure_bar:0.5}],
 [{_set:'biology',phase_id:'B4',phase_order:4,name:'Demo B4',started_at:'2026-09-27 09:00:00'}],
 [{_set:'bio_phases',phase_id:'B4',phase_order:4,name:'Demo B4'}],
 [{_set:'next_process',process_id:'P4',process_order:4,name:'Demo P4',anchor_type:'biological_phase',anchor_biological_phase_id:'B5'}],
 [{_set:'current_metrics',metric_id:'apparent_attenuation_percent',actual_value:79.5,actual_display:'79,5 %'},{_set:'current_metrics',metric_id:'sg_rate_points_per_day',actual_value:2.25,actual_display:'2,25 pkt/d'}],
 [{_set:'report_summary',session_id:'demo-session',batch_display:'Demo',pitched_display:'26.09.2026 12:00',biology_display:'B4 · Demo B4',process_display:'P3 · Demo P3',attenuation_display:'79,5 %',sg_rate_display:'2,25 pkt/d'}],
 [{_set:'clock',database_now:'2026-09-27 12:00:00'}],
 [{_set:'process_guidance',readiness:'not_evaluated',next_process_id:'P4',next_process_name:'Demo P4',trigger_summary:'Prosessevaluator er ikke tilbakeført ennå'}],
 [{_set:'runtime_presentation',elapsed_hours:24,active_phase_elapsed_hours:3,yeast:'W3470',attention:0,active_process_order:3,active_process_name:'Demo P3'}]
]});
assert.equal(out.ga_publication_target,'/data/gjaeringsassistent/ha-public/fermentation-overview.json');
const overview=JSON.parse(out.payload);
assert.equal(overview.session.session_id,'demo-session');
assert.equal(overview.series.length,1);
assert.equal(overview.process_timeline[0].process_id,'P3');
assert.equal(overview.biological_timeline[0].phase_id,'B4');
assert.equal(overview.biological_phases[0].phase_id,'B4');
assert.equal(overview.process_guidance.next_process_name,'Demo P4');
assert.equal(overview.series[0].temperature_plan_c,10);
assert.equal(overview.biological.metrics.apparent_attenuation_percent,79.5);assert.equal(overview.biological.metrics.attenuation_display,'79,5 %');assert.equal(overview.report_summary.attenuation_display,'79,5 %');
assert.ok(Array.isArray(overview.biological.transition_evaluations));
console.log('RESULT: PASS – Gjæring overview read-model and reference demo contract');


// p21r6: Datavindu skal beskrive faktisk vindu/dekning, ikke råt timestamp.
const windowSeries=[];
for(let i=0;i<=6;i++) windowSeries.push({_set:'series',at:`2026-09-28 10:${String(i*5).padStart(2,'0')}:00`,sg:1.020-i*0.0001,temperature_c:10+i*0.05});
out=invoke('p20_overview_result',{payload:[
 [{_set:'summary',session_id:'window-session',batch_name:'Window',is_demo:1,og:1.049,expected_fg_min:1.010,expected_fg_max:1.013,pitched_at:'2026-09-28 09:00:00',current_process_id:'P3',current_process_order:3,current_process_name:'P3',current_process_started_at:'2026-09-28 10:00:00',current_biological_phase_id:'B1',current_biological_phase_order:1,current_biological_phase_name:'B1'}],
 windowSeries,
 [{_set:'bio_phases',phase_id:'B2',phase_order:2,name:'B2'}],
 [{_set:'bio_params',phase_id:'B2',criterion_id:'b2-temp',model_id:'window_median_range',parameter_id:'window_minutes',data_type:'integer',integer_value:30},{_set:'bio_params',phase_id:'B2',criterion_id:'b2-temp',model_id:'window_median_range',parameter_id:'minimum_samples',data_type:'integer',integer_value:5},{_set:'bio_params',phase_id:'B2',criterion_id:'b2-temp',model_id:'window_median_range',parameter_id:'minimum_value',data_type:'real',real_value:9.0},{_set:'bio_params',phase_id:'B2',criterion_id:'b2-temp',model_id:'window_median_range',parameter_id:'maximum_value',data_type:'real',real_value:11.0}],
 [{_set:'bio_evals',evaluation_id:'be-window',current_phase_id:'B1',candidate_phase_id:'B2',evaluated_at:'2026-09-28 10:30:00',outcome:'waiting',confidence:'criteria_not_met'}],
 [{_set:'bio_eval_criteria',evaluation_id:'be-window',phase_id:'B2',criterion_id:'b2-temp',criterion_order:1,role_id:'required',metric_id:'beer_temperature_c',model_id:'window_median_range',evaluation_status:'missing_coverage',display_evaluation_status:'missing_coverage',display_status:'Mangler dekning',required_display:'9,00–11,00 °C',template_requirement_display:'9,00–11,00 °C',effective_requirement_display:'9,00–11,00 °C',criterion_basis_current:1,display_explanation:'ok',met:null,valid:0,actual_value:10.1,measured_at:'2026-09-28 10:30:00',source:'Tilt',explanation:'ok',label:'Temperatur',allowed_actions:'[]',status_display:'Mangler dekning',requirement_display:'9,00–11,00 °C',actual_display:'10,10 °C',data_window_display:'30 min · 6 pkt'}],
 [{_set:'process_steps',process_id:'P4',process_order:4,name:'P4',enabled:1}],
 [{_set:'process_params',process_id:'P4',criterion_id:'p4-stable',model_id:'stability_window',parameter_id:'window_hours',data_type:'real',real_value:24},{_set:'process_params',process_id:'P4',criterion_id:'p4-stable',model_id:'stability_window',parameter_id:'minimum_samples',data_type:'integer',integer_value:3},{_set:'process_params',process_id:'P4',criterion_id:'p4-stable',model_id:'stability_window',parameter_id:'minimum_span_hours',data_type:'real',real_value:0.2},{_set:'process_params',process_id:'P4',criterion_id:'p4-stable',model_id:'stability_window',parameter_id:'since_current_process_start',data_type:'boolean',boolean_value:1}],
 [{_set:'process_eval',evaluation_id:'pe-window',session_id:'window-session',current_process_id:'P3',candidate_process_id:'P4',evaluated_at:'2026-09-28 10:30:00',readiness:'waiting'}],
 [{_set:'process_eval_criteria',evaluation_id:'pe-window',candidate_process_id:'P4',criterion_id:'p4-stable',criterion_order:1,role_id:'required',metric_id:'tilt_sg',model_id:'stability_window',evaluation_status:'not_met',display_evaluation_status:'not_met',display_status:'Ikke oppfylt',required_display:'maks 0,50 pkt',template_requirement_display:'maks 0,50 pkt',effective_requirement_display:'maks 0,50 pkt',criterion_basis_current:1,display_explanation:'venter',met:0,valid:1,actual_value:0.6,measured_at:'2026-09-28 10:30:00',source:'Tilt',explanation:'venter',label:'SG-stabilitet',exception_allowed:0,allowed_actions:'[]',status_display:'Ikke oppfylt',requirement_display:'maks 0,50 pkt',actual_display:'0,60 pkt',data_window_display:'24 t · dekning 0,5 t · 7 pkt'}],
 [{_set:'process_guidance',readiness:'waiting',next_process_id:'P4',next_process_name:'P4',trigger_summary:'Venter'}],
 [{_set:'runtime_presentation',elapsed_hours:1.5,active_phase_elapsed_hours:1.5,yeast:'W3470',attention:0,active_process_order:3,active_process_name:'P3'}]
]});
const windowOverview=JSON.parse(out.payload);
assert.equal(windowOverview.biological.transition_evaluations[0].criteria[0].window,'30 min · 6 pkt');
assert.equal(windowOverview.process_guidance.condition_evaluations[0].window,'24 t · dekning 0,5 t · 7 pkt');
assert.equal(windowOverview.biological.transition_evaluations[0].criteria[0].status,'missing_coverage');
assert.equal(windowOverview.process_guidance.condition_evaluations[0].status,'not_met');
assert.doesNotMatch(windowOverview.biological.transition_evaluations[0].criteria[0].window,/2026-/);
assert.doesNotMatch(windowOverview.process_guidance.condition_evaluations[0].window,/2026-/);
console.log('RESULT: PASS – p21r6 Datavindu uses compact window/coverage semantics');

// p20r1-revised14 Biologi read-model and revision-based biological time correction.
out=invoke('p20_overview_result',{payload:[
 [{_set:'summary',session_id:'bio-session',batch_name:'Bio',is_demo:0,og:1.050,expected_fg_min:1.010,expected_fg_max:1.012,pitched_at:'2026-09-27 10:00:00',current_process_order:1,current_process_name:'P1',current_biological_phase_id:'B1',current_biological_phase_order:1,current_biological_phase_name:'Tilpasning'}],
 [],[],
 [{_set:'process',process_id:'P1',process_order:1,name:'P1',started_at:'2026-09-27 10:00:00',target_temperature_c:11,target_pressure_bar:0}],
 [{_set:'biology',visit_id:'bio-visit-1',phase_id:'B1',phase_order:1,name:'Tilpasning',description:'Første fase',started_at:'2026-09-27 10:00:00',original_started_at:'2026-09-27 10:00:00',manual_started_at:null,revision_no:1}],
 [{_set:'bio_phases',phase_id:'B1',phase_order:1,name:'Tilpasning',description:'Første fase'},{_set:'bio_phases',phase_id:'B2',phase_order:2,name:'Aktiv',description:'Neste fase'}],
 [{_set:'next_process',process_id:'P2',process_order:2,name:'P2'}],
 [],[],
 [{_set:'bio_criteria',phase_id:'B2',criterion_id:'b2-sg',metric_id:'sg',role_id:'required',criterion_model_id:'threshold_max',criterion_order:1,description:'SG under terskel'}],
 [{_set:'bio_params',phase_id:'B2',criterion_id:'b2-sg',parameter_id:'max_value',data_type:'real',real_value:1.035}],
 [{_set:'process_guidance',readiness:'not_evaluated',next_process_id:'P2',next_process_name:'P2',trigger_summary:'Venter'}],
 [{_set:'runtime_presentation',elapsed_hours:0,active_phase_elapsed_hours:0,yeast:'W3470',attention:0,active_process_order:1,active_process_name:'P1'}],
 [{_set:'bio_pending',phase_id:'B2',phase_order:2,phase_name:'Aktiv',outcome:'not_evaluated',availability:'not_yet'}]
]});
const bio=JSON.parse(out.payload);
assert.equal(bio.biological.active_phase_id,'B1');
assert.equal(bio.biological.candidate_phase_id,'B2');
assert.equal(bio.biological.transition_evaluations[0].criteria.length,0);
assert.equal(bio.biological_timeline[0].visit_id,'bio-visit-1');
assert.equal(bio.biological_timeline[0].original_started_at,'2026-09-27 10:00:00');

out=invoke('p20_bio_time_correction_query',{payload:{event:{data:{kind:'biological',target_id:'bio-visit-1',action:'set',timestamp:'2026-09-27T12:30:00.000Z',operation_id:'bio-corr-set'}}}})[0];
assert.equal(out.ga_route,'bio_time_correction');
assert.equal(out.topic,'CALL ga_correct_visit_time_tx(?,?,?,?,?);');
assert.deepEqual(out.payload,['biological','bio-visit-1','set','2026-09-27 12:30:00.000','bio-corr-set']);
assert.equal((out.topic.match(/\?/g)||[]).length,out.payload.length);
out=invoke('p20_bio_time_correction_query',{payload:{event:{data:{kind:'biological',target_id:'bio-visit-1',action:'clear',timestamp:null,operation_id:'bio-corr-clear'}}}})[0];
assert.equal(out.ga_route,'bio_time_correction');
assert.equal((out.topic.match(/\?/g)||[]).length,out.payload.length);
console.log('RESULT: PASS – Biologi p17r12 read-model and revision-based timeline correction');


// p20r1-revised16 Måleresultater: one contracted save button, normalized observation write,
// revision-based activation/deactivation and observation-time correction.
const measurementDraft={
 session_id:'m-session',measurement_method_id:'refractometer',measured_sg:1.030,sample_temperature_c:20,calibration_temperature_c:20,
 manual_temperature_c:12,pressure_bar:0.4,cooler_setpoint_c:11,cooler_calibration_offset_c:0,airlock_activity:'moderate',
 acetaldehyde_level:1,diacetyl_level:2,wort_like_level:0,sulfur_so2_level:1,sulfur_h2s_level:0,clarity_level:2,settling_yeast_level:1,settling_minutes:10,
 user_conclusion:'uncertain',measurement_note:'unit measurement'
};
out=invoke('p20_measurement_context_query',{payload:null});
assert.equal(out.ga_route,'measurement_context');
assert.match(out.topic,/measurement_input_draft/);
assert.doesNotMatch(out.topic,/homeassistant/i);
assert.equal(out.ga_measurement_input,undefined);
out=invoke('p20_measurement_context_result',{...out,payload:[
 [{_set:'session',session_id:'m-session',is_demo:1,og:1.050,expected_fg_min:1.010,expected_fg_max:1.012}],
 [{_set:'draft',...measurementDraft}]
]});
assert.ok(out[0]);assert.equal(out[1],null);out=out[0];
assert.equal(out.ga_route,'measurement_write');
assert.match(out.topic,/INSERT INTO observation_rounds/);
assert.match(out.topic,/INSERT INTO observation_round_revisions/);
assert.equal((out.topic.match(/\?/g)||[]).length,out.payload.length);
assert.ok(out.ga_measurement_saved.corrected_sg<1.03);
// Active field changes resolve their write/conversion contract from MariaDB metadata.
let du=invoke('p20_draft_update',{visible_entity_id:'number.gjaeringsassistent_manuell_temperatur',payload:12.5});
assert.equal(du.ga_route,'draft_update');assert.match(du.topic,/ha_entity_input_bindings/);assert.deepEqual(du.payload,['12.5','number.gjaeringsassistent_manuell_temperatur']);
du=invoke('p22_draft_binding_result',{...du,payload:[{entity_id:'number.gjaeringsassistent_manuell_temperatur',converter_id:'number',session_field:'manual_temperature_c',measurement_field:'manual_temperature_c',mirror_session_field:null,fixed_session_field:null,fixed_session_value:null,mapped_value:null}]});
assert.equal(du.ga_route,'draft_write');assert.match(du.topic,/UPDATE session_setup_draft/);assert.match(du.topic,/UPDATE measurement_input_draft/);assert.deepEqual(du.payload,[12.5,12.5]);
let sgDu=invoke('p20_draft_update',{visible_entity_id:'number.gjaeringsassistent_malt_sg',payload:1.029});
sgDu=invoke('p22_draft_binding_result',{...sgDu,payload:[{entity_id:'number.gjaeringsassistent_malt_sg',converter_id:'number',session_field:'measured_sg',measurement_field:'measured_sg',mirror_session_field:'og',fixed_session_field:null,fixed_session_value:null,mapped_value:null}]});
assert.match(sgDu.topic,/measured_sg=\?/);assert.match(sgDu.topic,/og=\?/);assert.deepEqual(sgDu.payload,[1.029,1.029,1.029]);
let selectDu=invoke('p20_draft_update',{visible_entity_id:'select.gjaeringsassistent_pitchmodus',payload:'Tørrgjær'});
selectDu=invoke('p22_draft_binding_result',{...selectDu,payload:[{entity_id:'select.gjaeringsassistent_pitchmodus',converter_id:'select',session_field:'pitch_mode_id',measurement_field:null,mirror_session_field:null,fixed_session_field:null,fixed_session_value:null,mapped_value:'dry'}]});
assert.deepEqual(selectDu.payload,['dry']);
let st=invoke('p20_measurement_status_query',{payload:{event:{data:{observation_id:'observation-123',status:'disabled',operation_id:'status-1'}}}});
assert.equal(st.ga_route,'measurement_status');assert.match(st.topic,/supersedes_revision_id/);assert.match(st.topic,/status_change/);assert.equal((st.topic.match(/\?/g)||[]).length,st.payload.length);
let tc=invoke('p20_bio_time_correction_query',{payload:{event:{data:{kind:'observation',target_id:'observation-123',action:'set',timestamp:'2026-09-27T13:00:00.000Z',operation_id:'obs-time-1'}}}})[0];

assert.equal(tc.ga_route,'observation_time_correction');assert.match(tc.topic,/observation_round_revisions/);assert.match(tc.topic,/timeline_correction/);assert.equal((tc.topic.match(/\?/g)||[]).length,tc.payload.length);
const processTc=invoke('p20_bio_time_correction_query',{payload:{data:{kind:'process',target_id:'pv-test',action:'set',timestamp:'2026-09-28T12:00:00Z',operation_id:'process-time-test'}}});
assert.ok(processTc[0]);assert.equal(processTc[0].ga_route,'bio_time_correction');assert.equal(processTc[0].topic,'CALL ga_correct_visit_time_tx(?,?,?,?,?);');assert.equal(processTc[0].payload[0],'process');assert.equal(processTc[0].payload[1],'pv-test');
const pitchTc=invoke('p20_bio_time_correction_query',{payload:{data:{kind:'pitch',target_id:'session-test',action:'set',timestamp:'2026-09-28T10:00:00Z',operation_id:'pitch-time-test'}}});
assert.ok(pitchTc[0]);assert.equal(pitchTc[0].ga_route,'bio_time_correction');assert.match(pitchTc[0].topic,/INSERT INTO session_timing_revisions/);assert.match(pitchTc[0].topic,/pitched_at/);assert.equal(pitchTc[0].payload[0],'session-test');


// Demo mode is an ordinary active session: successful measurement write must acknowledge and invoke evaluator.
const savedMeta=out.ga_measurement_saved;
let mw=invoke('p20_measurement_write_result',{ga_operation_id:'measure-unit-1',ga_measurement_saved:savedMeta,payload:[[{session_id:'m-session',is_demo:1,current_process_id:'P1'}]]});
assert.equal(mw.length,5);
assert.equal(mw[0],null);
assert.equal(mw[3].ga_bio_eval_reason,'measurement_saved');
assert.equal(mw[4].ga_event.code,'MEASUREMENT_SAVED');
assert.equal(mw[4].ga_event.correlation_id,'measure-unit-1');

// Restored B evaluator: frozen criteria + Tilt history -> persisted evidence + automatic revision-based transition.
let bq=invoke('p20_bio_eval_query',{});
assert.equal(bq.ga_route,'bio_eval_query');
assert.match(bq.topic,/session_biological_criteria/);
assert.match(bq.topic,/v_current_biological_criterion_revision/);
assert.match(bq.topic,/measurements_5m/);
const now=Date.now(); const sqlTime=ms=>new Date(ms).toISOString().replace('T',' ').replace('Z','');
const bioPayload=[
 [{_set:'summary',session_id:'bio-eval-session',is_demo:1,pitched_at:sqlTime(now-8*3600000),activity_started_at:null,og:1.050,expected_fg_min:1.010,expected_fg_max:1.012,current_visit_id:'bv1',current_phase_id:'B1',current_phase_order:1,current_phase_name:'Tilpasning',current_visit_revision_id:'bv1-r1',current_visit_revision_no:1,current_phase_started_at:sqlTime(now-8*3600000),current_timing_source:'automatic',evaluation_run_id:'11111111111111111111111111111111',current_process_started_at:sqlTime(now-8*3600000),database_now:sqlTime(now),last_import_cutoff_at:sqlTime(now-5*60000)}],
 [
  {_set:'series',at:sqlTime(now-180*60000),tilt_sg:1.050,beer_temperature_c:11,sample_count:1},
  {_set:'series',at:sqlTime(now-120*60000),tilt_sg:1.049,beer_temperature_c:11,sample_count:1},
  {_set:'series',at:sqlTime(now-60*60000),tilt_sg:1.047,beer_temperature_c:11,sample_count:1},
  {_set:'series',at:sqlTime(now-5*60000),tilt_sg:1.045,beer_temperature_c:11,sample_count:1}
 ],
 [],
 [{_set:'phases',phase_id:'B1',phase_order:1,name:'Tilpasning'},{_set:'phases',phase_id:'B2',phase_order:2,name:'Aktiv'}],
 [
  {_set:'criteria',phase_id:'B2',criterion_id:'b2-relative-drop',criterion_order:1,enabled:1,metric_id:'relative_sg_drop_points',model_id:'threshold',role_id:'required',label:'SG-fall siden start'}
 ],
 [
  {_set:'params',phase_id:'B2',criterion_id:'b2-relative-drop',model_id:'threshold',parameter_id:'minimum_value',data_type:'real',real_value:1.5,integer_value:null,boolean_value:null,text_value:null}
 ],
 [],[],
 [
  {_set:'calculations',calculation_id:'tilt_baseline',model_id:'median_first_samples'},
  {_set:'calculations',calculation_id:'sg_rate',model_id:'linear_regression'}
 ],
 [
  {_set:'calculation_inputs',calculation_id:'tilt_baseline',model_id:'median_first_samples',input_id:'series_sg',source_kind:'series',source_id:'tilt_sg'},
  {_set:'calculation_inputs',calculation_id:'sg_rate',model_id:'linear_regression',input_id:'series_sg',source_kind:'series',source_id:'tilt_sg'}
 ],
 [
  {_set:'calculation_params',calculation_id:'tilt_baseline',model_id:'median_first_samples',parameter_id:'sample_count',data_type:'integer',integer_value:3},
  {_set:'calculation_params',calculation_id:'sg_rate',model_id:'linear_regression',parameter_id:'window_hours',data_type:'real',real_value:24},
  {_set:'calculation_params',calculation_id:'sg_rate',model_id:'linear_regression',parameter_id:'minimum_samples',data_type:'integer',integer_value:3}
 ],
 [
  {_set:'metric_rules',metric_id:'relative_sg_drop_points',calculation_model_id:'metric-raw-sg-drop-v1',freshness_mode:'source_timestamp',valid_minimum_value:-100,valid_maximum_value:100},
  {_set:'metric_rules',metric_id:'sg_rate_points_per_day',calculation_model_id:'metric-calculation-output-v1',freshness_mode:'source_timestamp'}
 ],
 [
  {_set:'metric_inputs',metric_id:'relative_sg_drop_points',model_id:'metric-raw-sg-drop-v1',input_id:'series_sg',source_kind:'series',source_id:'tilt_sg'},
  {_set:'metric_inputs',metric_id:'relative_sg_drop_points',model_id:'metric-raw-sg-drop-v1',input_id:'og',source_kind:'session_field',source_id:'og'},
  {_set:'metric_inputs',metric_id:'sg_rate_points_per_day',model_id:'metric-calculation-output-v1',input_id:'calculation',source_kind:'biology_calculation',source_id:'sg_rate'}
 ],
 [
  {_set:'metric_params',metric_id:'relative_sg_drop_points',model_id:'metric-raw-sg-drop-v1',parameter_id:'current_sample_count',data_type:'integer',integer_value:3}
 ]
];
let be=invoke('p20_bio_eval_result',{payload:bioPayload});
assert.equal(be.ga_route,'bio_eval_write');
assert.match(be.topic,/INSERT INTO biological_evaluations/);
assert.match(be.topic,/INSERT INTO biological_evaluation_criteria/);
assert.match(be.topic,/INSERT INTO biological_evaluation_criterion_parameter_values/);
assert.match(be.topic,/INSERT INTO biological_transitions/);
assert.doesNotMatch(be.topic,/UPDATE biological_visit_revisions/);
assert.match(be.topic,/supersedes_revision_id/);
assert.equal((be.topic.match(/\?/g)||[]).length,be.payload.length);
assert.equal(be.ga_bio_eval.transition_phase_id,'B2');
assert.equal(be.payload.some(v=>typeof v==='string'&&/T\d{2}:\d{2}:\d{2}.*Z$/.test(v)),false); // MariaDB DATETIME payloads must be SQL-formatted

// p21r13: history replay is strictly sequential. Even when the imported history
// already satisfies B3, B2 must be materialized first with its own visit and transition.
const replayPayload=structuredClone(bioPayload);
replayPayload[1]=[
  {_set:'series',at:sqlTime(now-180*60000),tilt_sg:1.050,beer_temperature_c:11,sample_count:1},
  {_set:'series',at:sqlTime(now-150*60000),tilt_sg:1.049,beer_temperature_c:11,sample_count:1},
  {_set:'series',at:sqlTime(now-120*60000),tilt_sg:1.048,beer_temperature_c:11,sample_count:1},
  {_set:'series',at:sqlTime(now-90*60000),tilt_sg:1.046,beer_temperature_c:11,sample_count:1},
  {_set:'series',at:sqlTime(now-60*60000),tilt_sg:1.044,beer_temperature_c:11,sample_count:1},
  {_set:'series',at:sqlTime(now-30*60000),tilt_sg:1.042,beer_temperature_c:11,sample_count:1}
];
replayPayload[3].push({_set:'phases',phase_id:'B3',phase_order:3,name:'Hovedgjæring'});
replayPayload[4].push({_set:'criteria',phase_id:'B3',criterion_id:'b3-sg-rate',criterion_order:1,enabled:1,metric_id:'sg_rate_points_per_day',model_id:'threshold',role_id:'required',label:'Aktiv SG-rate'});
replayPayload[5].push({_set:'params',phase_id:'B3',criterion_id:'b3-sg-rate',model_id:'threshold',parameter_id:'minimum_value',data_type:'real',real_value:1.5,integer_value:null,boolean_value:null,text_value:null});
replayPayload[0][0].last_import_cutoff_at=sqlTime(now-30*60000);
let replay=invoke('p20_bio_eval_result',{ga_bio_eval_reason:'ha_history_backfill',payload:replayPayload});
assert.equal(replay.ga_bio_eval.transition_count,2);
assert.equal(replay.ga_bio_eval.transition_phase_id,'B3');
assert.equal(replay.ga_bio_eval.current_phase_id,'B3');
assert.equal((replay.topic.match(/INSERT INTO biological_transitions/g)||[]).length,2);
assert.equal((replay.topic.match(/INSERT INTO biological_visits/g)||[]).length,2);
assert.ok(replay.payload.includes('B2'));
assert.ok(replay.payload.includes('B3'));
assert.equal((replay.topic.match(/\?/g)||[]).length,replay.payload.length);

// A registered measurement-data gap resets a declarative stability window;
// data before the gap cannot satisfy minimum_span_hours after continuity was broken.
const stablePayload=structuredClone(bioPayload);
stablePayload[1]=[
  {_set:'series',at:sqlTime(now-240*60000),tilt_sg:1.0450,beer_temperature_c:11,sample_count:1},
  {_set:'series',at:sqlTime(now-180*60000),tilt_sg:1.0451,beer_temperature_c:11,sample_count:1},
  {_set:'series',at:sqlTime(now-120*60000),tilt_sg:1.0449,beer_temperature_c:11,sample_count:1},
  {_set:'series',at:sqlTime(now-60*60000),tilt_sg:1.0450,beer_temperature_c:11,sample_count:1},
  {_set:'series',at:sqlTime(now-5*60000),tilt_sg:1.0450,beer_temperature_c:11,sample_count:1}
];
stablePayload[4]=[{_set:'criteria',phase_id:'B2',criterion_id:'b2-stability',criterion_order:1,enabled:1,metric_id:'tilt_sg',model_id:'stability_window',role_id:'required',label:'SG-stabilitet'}];
stablePayload[5]=[
  {_set:'params',phase_id:'B2',criterion_id:'b2-stability',model_id:'stability_window',parameter_id:'window_hours',data_type:'real',real_value:4.5},
  {_set:'params',phase_id:'B2',criterion_id:'b2-stability',model_id:'stability_window',parameter_id:'maximum_range_points',data_type:'real',real_value:1.0},
  {_set:'params',phase_id:'B2',criterion_id:'b2-stability',model_id:'stability_window',parameter_id:'minimum_samples',data_type:'integer',integer_value:4},
  {_set:'params',phase_id:'B2',criterion_id:'b2-stability',model_id:'stability_window',parameter_id:'minimum_span_hours',data_type:'real',real_value:3.0},
  {_set:'params',phase_id:'B2',criterion_id:'b2-stability',model_id:'stability_window',parameter_id:'since_current_process_start',data_type:'boolean',boolean_value:0}
];
stablePayload[10]=[{_set:'metric_rules',metric_id:'tilt_sg',calculation_model_id:'metric-direct-source-v1',freshness_mode:'source_timestamp'}];
stablePayload[11]=[{_set:'metric_inputs',metric_id:'tilt_sg',model_id:'metric-direct-source-v1',input_id:'value',source_kind:'series',source_id:'tilt_sg'}];
stablePayload[12]=[];
let stableNoGap=invoke('p20_bio_eval_result',{payload:stablePayload});
assert.equal(stableNoGap.ga_bio_eval.transition_count,1);
const stableWithGap=structuredClone(stablePayload);
stableWithGap.push([{_set:'gaps',gap_started_at:sqlTime(now-110*60000),gap_ended_at:sqlTime(now-90*60000),duration_seconds:1200,threshold_seconds:900}]);
let stableGap=invoke('p20_bio_eval_result',{payload:stableWithGap});
assert.equal(stableGap.ga_bio_eval.transition_count,0);
assert.ok(stableGap.payload.some(v=>typeof v==='string'&&v.includes('Datagap brøt stabilitetsvinduet')));


// p24: explicit handling changes readiness, never the original criterion result.
const handledPayload=structuredClone(bioPayload);
handledPayload[4][0].exception_allowed=1;
handledPayload[5][0].real_value=50; // valid but unmet threshold
let rawUnmet=invoke('p20_bio_eval_result',{payload:handledPayload});assert.equal(rawUnmet.ga_bio_eval.transition_count,0);
const handledAt=now-1000;
handledPayload.push([{_set:'exceptions',phase_id:'B2',criterion_id:'b2-relative-drop',exception_id:'ex-1',action:'register',created_at:sqlTime(handledAt)}]);
let handled=invoke('p20_bio_eval_result',{payload:handledPayload});assert.equal(handled.ga_bio_eval.transition_count,1);assert.ok(handled.payload.includes('ex-1'));assert.ok(handled.payload.includes('not_met'));assert.ok(handled.payload.some(v=>typeof v==='string'&&v.startsWith(sqlTime(now).slice(0,19))),'transition must not predate registration');
handledPayload.at(-1).push({_set:'exceptions',phase_id:'B2',criterion_id:'b2-relative-drop',exception_id:'ex-2',action:'withdraw',created_at:sqlTime(now)});
assert.equal(invoke('p20_bio_eval_result',{payload:handledPayload}).ga_bio_eval.transition_count,0);
handledPayload[5]=[];
assert.equal(invoke('p20_bio_eval_result',{payload:handledPayload}).ga_bio_eval.transition_count,0);

// revised15: required evaluator configuration is never guessed.
const invalidPayload=structuredClone(bioPayload);
invalidPayload[5]=invalidPayload[5].filter(r=>!(r.criterion_id==='b2-relative-drop'&&r.parameter_id==='minimum_value'));
let beInvalid=invoke('p20_bio_eval_result',{payload:invalidPayload});
assert.equal(beInvalid.ga_route,'bio_eval_write');
assert.equal(beInvalid.ga_bio_eval.transition_phase_id,null);
assert.ok(beInvalid.payload.some(v=>typeof v==='string'&&/mangler|ugyldig/.test(v))); 

// p22r7: authoritative frozen metric-output bounds protect B/P decisions, not only Analyse rendering.
const invalidMetricPayload=structuredClone(bioPayload);
const invalidMetricRule=invalidMetricPayload.flat().find(r=>r.metric_id==='relative_sg_drop_points'&&r._set==='metric_rules');
invalidMetricRule.valid_maximum_value=1.0;
let beInvalidMetric=invoke('p20_bio_eval_result',{payload:invalidMetricPayload});
assert.equal(beInvalidMetric.ga_bio_eval.transition_phase_id,null);
assert.ok(beInvalidMetric.payload.some(v=>typeof v==='string'&&v.includes('metric_output_outside_declared_range')));
console.log('RESULT: PASS – p22r7 frozen metric-output validity prevents impossible derived values from driving B transitions');

// revised15 biological criterion correction: only declared correctable parameters may be revised.
let bc=invoke('p20_bio_criterion_correction_context_result',{ga_correction_request:{phase_id:'B2',criterion_id:'b2-sg-rate',parameters:{minimum_value:0.7},action:'override',note:'unit',operation_id:'bio-corr-1'},payload:[
 [{_set:'criterion',session_id:'bio-eval-session',phase_id:'B2',criterion_id:'b2-sg-rate',model_id:'threshold'}],
 [{_set:'allowed',parameter_id:'minimum_value',data_type:'real'}],
 []
]});
assert.equal(bc[0].ga_route,'bio_criterion_write');assert.match(bc[0].topic,/session_biological_criterion_revisions/);assert.match(bc[0].topic,/session_biological_criterion_revision_parameter_values/);assert.equal((bc[0].topic.match(/\?/g)||[]).length,bc[0].payload.length);
let bcBad=invoke('p20_bio_criterion_correction_context_result',{ga_correction_request:{phase_id:'B2',criterion_id:'b2-sg-rate',parameters:{maximum_value:9},action:'override',operation_id:'bio-corr-bad'},payload:[
 [{_set:'criterion',session_id:'bio-eval-session',phase_id:'B2',criterion_id:'b2-sg-rate',model_id:'threshold'}],[{_set:'allowed',parameter_id:'minimum_value',data_type:'real'}],[]
]});
assert.equal(bcBad[0],null);assert.equal(bcBad[1].ga_event.code,'BIO_CRITERION_CORRECTION_REJECTED');

// revised15 expected-FG correction persists a revision and can reset to frozen values.

const pNow=Date.now(), pSql=ms=>new Date(ms).toISOString().replace('T',' ').replace('Z','');
const processPayload=[
 [{_set:'summary',session_id:'p-session',is_demo:1,pitched_at:pSql(pNow-3*86400000),og:1.050,expected_fg_min:1.010,expected_fg_max:1.012,current_visit_id:'pv1',current_process_id:'P1',current_process_order:1,current_process_name:'P1',current_visit_revision_id:'pv1-r1',current_visit_revision_no:1,current_process_started_at:pSql(pNow-86400000),current_biological_phase_id:'B3',current_biological_phase_order:3,current_biological_started_at:pSql(pNow-86400000),latest_observation_id:null,latest_observation_revision_id:null,evaluation_run_id:'22222222222222222222222222222222',database_now:pSql(pNow),last_import_cutoff_at:pSql(pNow-3600000)}],
 [0,1,2,3].map(i=>({_set:'series',at:pSql(pNow-(3-i)*3600000),tilt_sg:1.04-i*.001,beer_temperature_c:10,sample_count:1})),
 [],
 [{_set:'steps',process_id:'P1',process_order:1,name:'P1',enabled:1,historical_replay_auto_transition_allowed:1},{_set:'steps',process_id:'P2',process_order:2,name:'P2',enabled:1,historical_replay_auto_transition_allowed:1}],
 [{_set:'criteria',process_id:'P2',criterion_id:'p2-bio',criterion_order:1,enabled:1,metric_id:'biological_phase_order',model_id:'threshold',role_id:'required',label:'Biofase',exception_allowed:1}],
 [{_set:'params',process_id:'P2',criterion_id:'p2-bio',model_id:'threshold',parameter_id:'minimum_value',data_type:'real',real_value:2,integer_value:null,boolean_value:null,text_value:null}],
 [],[],
 [{_set:'calculations',calculation_id:'tilt_baseline',model_id:'median_first_samples'},{_set:'calculations',calculation_id:'sg_rate',model_id:'linear_regression'}],
 [{_set:'calculation_inputs',calculation_id:'tilt_baseline',model_id:'median_first_samples',input_id:'series_sg',source_kind:'series',source_id:'tilt_sg'},{_set:'calculation_inputs',calculation_id:'sg_rate',model_id:'linear_regression',input_id:'series_sg',source_kind:'series',source_id:'tilt_sg'}],
 [{_set:'calculation_params',calculation_id:'tilt_baseline',model_id:'median_first_samples',parameter_id:'sample_count',data_type:'integer',integer_value:3},{_set:'calculation_params',calculation_id:'sg_rate',model_id:'linear_regression',parameter_id:'window_hours',data_type:'real',real_value:24},{_set:'calculation_params',calculation_id:'sg_rate',model_id:'linear_regression',parameter_id:'minimum_samples',data_type:'integer',integer_value:3}],
 [{_set:'metric_rules',metric_id:'biological_phase_order',calculation_model_id:'metric-current-biology-order-v1',freshness_mode:'not_applicable'}],
 [{_set:'metric_inputs',metric_id:'biological_phase_order',model_id:'metric-current-biology-order-v1',input_id:'phase_order',source_kind:'biology_state',source_id:'current_phase_order'}],
 [],
 [{_set:'targets',process_id:'P2',target_id:'temp',target_order:1,metric_id:'beer_temperature_c',model_id:'exact',label:'Temp',purpose:'',target_value:12,minimum_value:null,maximum_value:null},{_set:'targets',process_id:'P2',target_id:'press',target_order:2,metric_id:'pressure_bar',model_id:'exact',label:'Trykk',purpose:'',target_value:0.8,minimum_value:null,maximum_value:null}],
 []
];
let pe=invoke('p20_process_eval_result',{payload:processPayload});
assert.equal(pe.ga_route,'process_eval_write');assert.equal(pe.ga_process_eval.readiness,'ready');
assert.match(pe.topic,/INSERT INTO process_evaluations/);assert.match(pe.topic,/INSERT INTO process_evaluation_criteria/);assert.match(pe.topic,/INSERT INTO recommendations/);
assert.equal((pe.topic.match(/\?/g)||[]).length,pe.payload.length);
// p22r5: historical replay may establish P2, but a template-disabled automatic
// transition at P3 must stop replay even when the P3 criteria are already met.
const processReplay=structuredClone(processPayload);
processReplay[0][0].evaluation_run_id='44444444444444444444444444444444';
processReplay[3]=[
 {_set:'steps',process_id:'P1',process_order:1,name:'P1',enabled:1,historical_replay_auto_transition_allowed:1},
 {_set:'steps',process_id:'P2',process_order:2,name:'P2',enabled:1,historical_replay_auto_transition_allowed:1},
 {_set:'steps',process_id:'P3',process_order:3,name:'P3',enabled:1,historical_replay_auto_transition_allowed:0}
];
processReplay[4].push({_set:'criteria',process_id:'P3',criterion_id:'p3-bio',criterion_order:1,enabled:1,metric_id:'biological_phase_order',model_id:'threshold',role_id:'required',label:'Biofase',exception_allowed:0});
processReplay[5].push({_set:'params',process_id:'P3',criterion_id:'p3-bio',model_id:'threshold',parameter_id:'minimum_value',data_type:'real',real_value:2,integer_value:null,boolean_value:null,text_value:null});
const pr=invoke('p20_process_eval_result',{ga_process_eval_reason:'ha_history_backfill',payload:processReplay});
assert.equal(pr.ga_process_eval.historical_transition_count,1);
assert.equal(pr.ga_process_eval.historical_transitions[0].to,'P2');
assert.equal(pr.ga_process_eval.candidate_process_id,'P3');
assert.equal(pr.ga_process_eval.readiness,'ready');
assert.equal((pr.topic.match(/INSERT INTO process_transitions/g)||[]).length,1);
let pc=invoke('p20_process_criterion_correction_context_result',{ga_correction_request:{process_id:'P2',criterion_id:'p2-bio',action:'override',parameters:{minimum_value:4},note:'unit',operation_id:'pc1'},payload:[[{_set:'criterion',session_id:'p-session',process_id:'P2',criterion_id:'p2-bio',model_id:'threshold'}],[{_set:'allowed',parameter_id:'minimum_value',data_type:'real'}],[]]});
assert.ok(pc[0]);assert.equal(pc[0].ga_route,'process_criterion_write');assert.match(pc[0].topic,/session_process_criterion_revisions/);assert.doesNotMatch(pc[0].topic,/AS _set,\*/);assert.equal((pc[0].topic.match(/\?/g)||[]).length,pc[0].payload.length);
let px=invoke('p20_process_exception_context_result',{ga_exception_request:{evaluation_id:'pev1',criterion_id:'c1',action:'register',exception_type:'akseptert_avvik',note:'unit',operation_id:'pe1'},payload:[[{_set:'criterion',session_id:'p-session',evaluation_id:'pev1',candidate_process_id:'P2',criterion_id:'c1',met:0,valid:1,exception_allowed:1}],[]]});
assert.ok(px[0]);assert.equal(px[0].ga_route,'process_exception_write');assert.match(px[0].topic,/process_criterion_exceptions/);assert.match(px[0].topic,/SELECT 'saved' AS _set,x\.\* FROM process_criterion_exceptions x/);assert.doesNotMatch(px[0].topic,/AS _set,\*/);assert.equal((px[0].topic.match(/\?/g)||[]).length,px[0].payload.length);
let pg=invoke('p20_process_guidance_result',{payload:[[{_set:'evaluation',session_id:'p-session',evaluation_id:'pev1',observation_revision_id:null,current_process_id:'P1',current_process_name:'P1',candidate_process_id:'P2',candidate_process_name:'P2',readiness:'waiting',effective_readiness:'ready_with_exceptions',required_total:1,required_met:0,required_handled:1,blocking_required:0,recommendation_title:'Gå til P2',recommendation_type:'process_transition',recommendation_explanation:'Alle 1 obligatoriske kriterier er oppfylt eller eksplisitt håndtert.',data_quality:'complete',summary:'0/1',recommendation_run_id:'33333333333333333333333333333333'}],[{_set:'criteria',criterion_id:'c1',role_id:'required',met:0,valid:1,exception_allowed:1}],[{_set:'exceptions',criterion_id:'c1',action:'register',exception_type:'akseptert_avvik'}],[]]});
assert.equal(pg.ga_process_guidance.readiness,'ready_with_exceptions');assert.match(pg.topic,/INSERT INTO recommendations/);assert.match(pg.topic,/SELECT 'recommendation' AS _set,r\.\* FROM recommendations r/);assert.doesNotMatch(pg.topic,/AS _set,\*/);assert.equal((pg.topic.match(/\?/g)||[]).length,pg.payload.length);
let pn=invoke('p20_process_next_result',{ga_process_operation_id:'next1',payload:[[{_set:'current',database_now:'2026-09-28T10:00:00Z',session_id:'p-session',visit_id:'pv1',process_id:'P1',process_order:1,process_name:'P1',visit_revision_id:'pv1-r1',revision_no:1,started_at:pSql(pNow-10000)}],[{_set:'evaluation',evaluation_id:'pev1',candidate_process_id:'P2',candidate_process_name:'P2',readiness:'waiting',effective_readiness:'ready_with_exceptions',blocking_required:0,database_now:new Date().toISOString(),recommended_temperature_c:12,recommended_pressure_bar:.8}],[{_set:'criteria',criterion_id:'c1',role_id:'required',met:0,valid:1}],[{_set:'exceptions',criterion_id:'c1',action:'register'}],[{_set:'recommendation',recommendation_id:'rec1'}]]});
assert.ok(pn[0]);assert.equal(pn[0].ga_route,'process_next_write');assert.match(pn[0].topic,/INSERT INTO process_transitions/);assert.match(pn[0].topic,/SELECT 'active' AS _set,a\.\* FROM v_active_session_summary a/);assert.doesNotMatch(pn[0].topic,/AS _set,\*/);assert.equal((pn[0].topic.match(/\?/g)||[]).length,pn[0].payload.length);
let pb=invoke('p20_process_back_result',{ga_process_operation_id:'back1',payload:[[{_set:'current',database_now:'2026-09-28T10:00:00Z',session_id:'p-session',visit_id:'pv2',process_id:'P2',process_order:2,process_name:'P2',visit_revision_id:'pv2-r1',revision_no:1,started_at:pSql(pNow-10000)}],[{_set:'previous',process_id:'P1',process_order:1,name:'P1'}]]});
assert.ok(pb[0]);assert.equal(pb[0].ga_route,'process_back_write');assert.match(pb[0].topic,/INSERT INTO process_transitions/);assert.match(pb[0].topic,/SELECT 'active' AS _set,a\.\* FROM v_active_session_summary a/);assert.doesNotMatch(pb[0].topic,/AS _set,\*/);assert.equal((pb[0].topic.match(/\?/g)||[]).length,pb[0].payload.length);
console.log('RESULT: PASS – revised16 Prosesstrinn evaluator, correction, exception, recommendation and transitions');

console.log('RESULT: PASS – Måleresultater normalized save and revision operations');

// p21r4 session lifecycle: complete and release are append-only domain operations.
const endSession={ended_at:'2026-09-28T10:00:00Z',recorded_now:'2026-10-15T12:00:00Z',session_id:'life-session',batch_name:'Lifecycle test',lifecycle:'active',is_demo:1};
let life=invoke('p21_session_end_context_result',{payload:[[endSession]]});
assert.ok(life[0]);assert.equal(life[1],null);assert.equal(life[2],null);
assert.equal(life[0].ga_route,'session_end_write');
assert.match(life[0].topic,/INSERT INTO session_lifecycle_events/);
assert.match(life[0].topic,/INSERT INTO process_visit_revisions/);
assert.match(life[0].topic,/INSERT INTO biological_visit_revisions/);
assert.doesNotMatch(life[0].topic,/UPDATE\s+(sessions|process_visit_revisions|biological_visit_revisions)/i);
assert.equal((life[0].topic.match(/\?/g)||[]).length,life[0].payload.length);
let lifeReject=invoke('p21_session_end_context_result',{payload:[[]]});
assert.equal(lifeReject[0],null);assert.equal(lifeReject[2].ga_event.code,'SESSION_END_REJECTED');
let lifeAck=invoke('p21_session_end_write_result',{payload:[[{_set:'session',session_id:'life-session',batch_name:'Lifecycle test',lifecycle:'completed'}],[{_set:'notes',note_id:'n1',note_text:'beholdes'}]]});
assert.equal(lifeAck[0].ga_state.session.lifecycle,'completed');assert.equal(lifeAck[0].ga_state.active,null);assert.equal(lifeAck[1].ga_event.code,'SESSION_COMPLETED');

// Real session must not be released without a verified export; demo is explicitly exempt.
let prep=invoke('p21_session_prepare_context_result',{payload:[[{session_id:'real-completed',lifecycle:'completed',is_demo:0,verified_export_count:0}]]});
assert.equal(prep[0],null);assert.match(prep[1].payload,/verifisert eksport mangler/);assert.equal(prep[2].ga_event.code,'SESSION_PREPARE_REJECTED');
prep=invoke('p21_session_prepare_context_result',{payload:[[{session_id:'demo-completed',lifecycle:'completed',is_demo:1,verified_export_count:0}]]});
assert.ok(prep[0]);assert.equal(prep[0].ga_route,'session_prepare_write');
assert.match(prep[0].topic,/INSERT INTO session_release_events/);
assert.doesNotMatch(prep[0].topic,/DELETE FROM sessions/i);
assert.match(prep[0].topic,/DELETE FROM measurement_input_draft/);
assert.match(prep[0].topic,/DELETE FROM session_setup_draft/);
assert.equal((prep[0].topic.match(/\?/g)||[]).length,prep[0].payload.length);
let prepAck=invoke('p21_session_prepare_write_result',{payload:[[{_set:'release',release_event_id:'release-demo-completed',session_id:'demo-completed',operation_id:'prepare-x'}],[{_set:'current_count',current_count:0}]]});
assert.equal(prepAck[0].ga_restore_reason,'prepare_new');assert.equal(prepAck[2].ga_event.code,'SESSION_RELEASED');
console.log('RESULT: PASS – p21r4 append-only session completion/release and export gate');

// p21r8: completed archive/report builder and history publisher.
out=invoke('p21_session_export_read_result',{ga_archive_attempt_id:'test-attempt',ga_archive_attempt_no:1,ga_template_path:'/data/template.sqlite',payload:[
  [{_set:'clock',database_now:'2026-09-28T18:00:00Z',generated_display:'28.09.2026 20:00'}],
  [{_set:'summary',session_id:'session-test-1'}],
  [{_set:'session',session_id:'session-test-1',batch_name:'Testbatch',report_kind_display:'Avsluttet gjæringsrapport'}],
  [{_set:'archive_session',session_id:'session-test-1',batch_name:'Testbatch',pitched_at:'2026-09-25 20:00:00',template_name:'W-34/70',version_label:'3.0'}],
  [{_set:'lifecycle_events',session_id:'session-test-1',lifecycle:'active',occurred_at:'2026-09-25 20:00:00'},{_set:'lifecycle_events',session_id:'session-test-1',lifecycle:'completed',occurred_at:'2026-09-28 18:00:00'}],
  [{_set:'measurements_5m',session_id:'session-test-1',bucket_at:'2026-09-28 17:55:00',sg_median:1.0301}],
  [{_set:'measurement_data_gaps',session_id:'session-test-1',gap_started_at:'2026-09-25 20:20:00',gap_ended_at:'2026-09-26 07:10:00',duration_seconds:39000,source:'tilt'}],
  [{_set:'notes',session_id:'session-test-1',noted_at:'2026-09-28 12:00:00',note_text:'Testnotat'}]
]});
assert.ok(out.payload);
assert.match(out.filename,/session-session-test-1-export-test-attempt\.html\.stage$/);assert.match(out.ga_report_path,/session-session-test-1-export-test-attempt\.html$/);
assert.match(out.payload,/Avsluttet gjæringsrapport/);assert.match(out.payload,/Testnotat/);assert.match(out.payload,/Kronologisk oversikt/);assert.equal(out.ga_report_bytes,Buffer.byteLength(out.payload));

out=invoke('p21_session_history_result',{payload:[[{_set:'history',session_id:'session-test-1',batch_name:'Testbatch',pitched_at:'2026-09-25 20:00:00',lifecycle:'completed',archive_url:'/local/gjaeringsassistent/exports/session-session-test-1.json',report_url:'/local/gjaeringsassistent/exports/session-session-test-1.html',archive_path:'/data/x.json',archive_sha256:'a'.repeat(64)}]]});
const history=JSON.parse(out.payload);assert.equal(history.sessions.length,1);assert.match(history.sessions[0].report_url,/session-session-test-1\.html$/);assert.match(history.sessions[0].archive_url,/session-session-test-1\.json$/);
console.log('RESULT: PASS – p21r8 completed archive/report and history read-model');


// p22r5: active-session report is a DB-owned snapshot and does not mutate lifecycle.
out=invoke('p22_active_report_query',{});
assert.equal(out.ga_route,'active_report_read');
assert.match(out.topic,/CALL ga_read_report/);
assert.match(fs.readFileSync(path.join(root,'tools/report_reads.sql'),'utf8'),/v_session_report_summary/);
assert.match(out.topic,/UTC_TIMESTAMP\(3\)/);
assert.doesNotMatch(out.topic,/UPDATE\s+session|INSERT INTO session_lifecycle_events/i);

out=invoke('p22_active_report_result',{payload:[
  [{_set:'clock',database_now:'2026-09-29 20:15:00',generated_display:'29.09.2026 20:15',file_stamp:'20260929T201500Z'}],
  [{_set:'summary',session_id:'active-report-session',biology_display:'B4 · Sen gjæring',process_display:'P3 · Første temperaturøkning',latest_tilt_sg_display:'1,0198',attenuation_display:'79,5 %',sg_rate_display:'0,42 SG-poeng/døgn',next_process_display:'P4 · Modning',manual_measurements_display:'2',latest_manual_sg_display:'1,0210',notes_display:'1',datapoints_display:'312'}],
  [{_set:'session',session_id:'active-report-session',batch_name:'Aktiv test',pitched_display:'27.09.2026 23:00',biology_display:'B4 · Sen gjæring',process_display:'P3 · Første temperaturøkning',template_name:'W-34/70 standardprosess',version_label:'3.0'}],
  [{_set:'biology',phase_id:'B2',name:'Aktiv vekst',transitioned_display:'28.09.2026 04:15'}],
  [{_set:'process',process_id:'P2',name:'Hovedgjæring',transitioned_display:'28.09.2026 04:20'}],
  [{_set:'notes',noted_display:'29.09.2026 18:00',note_text:'Testnotat'}]
]});
assert.ok(out);assert.match(out.filename,/session-active-report-session-active-20260929T201500Z-report-unit-msg\.html$/);
assert.match(out.payload,/79,5 %/);assert.match(out.payload,/1,0198/);assert.match(out.payload,/generert 29\.09\.2026 20:15/);
assert.doesNotMatch(out.payload,/63,3 %/);

out=invoke('p22_active_report_register_query',{ga_active_report:out.ga_active_report});
assert.equal(out.ga_route,'active_report_register');assert.match(out.topic,/CALL ga_register_active_report_tx/);assert.equal(out.payload[1],'report-unit-msg');assert.doesNotMatch(out.topic,/session_lifecycle_events|session_release_events/);
assert.equal((out.topic.match(/\?/g)||[]).length,out.payload.length);

out=invoke('p22_active_report_register_result',{payload:[[{_set:'active_report',session_id:'active-report-session',export_kind:'active_report',attempt_no:1,status:'verified',public_url:'/local/gjaeringsassistent/exports/session-active-report-session-active-20260929T201500Z.html',generated_display:'29.09.2026 20:15'}]]});
assert.equal(out.ga_overview_reason,'active_report_verified');
console.log('RESULT: PASS – p22r5 active-session report snapshot uses DB display values and leaves lifecycle unchanged');

// p21r10: Home Assistant historical/live ingestion uses DB-configured source and heartbeat gap truth.
const ingestAnchor=new Date(Date.now()-20*60*1000);
const ingestCursor=new Date(ingestAnchor.getTime()+10*60*1000);
let ih=invoke('p21_live_ingest_context_result',{ga_ingest_reason:'start',payload:[[{_set:'ingest',session_id:'live-session',source_profile_id:sourceRow.source_profile_id,source_name:sourceRow.name,source_type:sourceRow.source_type,source_started_at:ingestAnchor.toISOString().replace('T',' ').replace('Z',''),last_import_cutoff_at:ingestCursor.toISOString().replace('T',' ').replace('Z',''),last_success_at:null,statistics_required:1,statistics_started_at:ingestCursor.toISOString(),open_gap_id:null,open_gap_started_at:null,sg_entity_id:sourceRow.sg_entity_id,temperature_entity_id:sourceRow.temperature_entity_id,heartbeat_entity_id:sourceRow.heartbeat_entity_id,rssi_entity_id:sourceRow.rssi_entity_id,poll_interval_seconds:300,gap_threshold_seconds:300,database_now:new Date().toISOString().replace('T',' ').replace('Z','')}]]});
assert.ok(Array.isArray(ih)&&ih[0]);const ihMsg=ih[0];assert.equal(ihMsg.ga_ingest.session_id,'live-session');assert.equal(ihMsg.payload.entityId,[sourceRow.sg_entity_id,sourceRow.temperature_entity_id,sourceRow.heartbeat_entity_id,sourceRow.rssi_entity_id].join(','));assert.equal(ihMsg.payload.flatten,true);assert.ok(Date.parse(ihMsg.payload.endDate)>Date.parse(ihMsg.payload.startDate));assert.ok(ih[1]&&ih[1].payload.state==='importing');assert.ok(ihMsg.ga_ingest.progress_after>ihMsg.ga_ingest.progress_before);

const fixedIngest={session_id:'live-session',source_profile_id:sourceRow.source_profile_id,source_started_at:'2026-09-28T18:00:00.000Z',import_start:'2026-09-28T18:00:00.000Z',import_end:'2026-09-28T18:05:00.000Z',sg_entity_id:sourceRow.sg_entity_id,temperature_entity_id:sourceRow.temperature_entity_id,heartbeat_entity_id:sourceRow.heartbeat_entity_id,rssi_entity_id:sourceRow.rssi_entity_id,poll_interval_seconds:300,gap_threshold_seconds:300,open_gap_id:null,open_gap_started_at:null};
const historyRows=[
 {entity_id:sourceRow.sg_entity_id,state:'1.0400',last_updated:'2026-09-28T18:00:10.000Z'},
 {entity_id:sourceRow.sg_entity_id,state:'1.0398',last_updated:'2026-09-28T18:02:10.000Z'},
 {entity_id:sourceRow.temperature_entity_id,state:'9.8',last_updated:'2026-09-28T18:01:00.000Z'},
 {entity_id:sourceRow.temperature_entity_id,state:'10.0',last_updated:'2026-09-28T18:04:00.000Z'},
 {entity_id:sourceRow.heartbeat_entity_id,state:'2026-09-28T20:04:30+02:00',last_updated:'2026-09-28T18:04:30.000Z'},
 {entity_id:sourceRow.rssi_entity_id,state:'-67',last_updated:'2026-09-28T18:04:20.000Z'}
];
let ip=invoke('p21_live_history_process',{ga_ingest:{...fixedIngest},payload:historyRows});
assert.equal(ip.ga_route,'ha_ingest_write');assert.equal(ip.ga_ingest_result.inserted_buckets,1);assert.equal(ip.ga_ingest_result.partial_buckets,0);assert.match(ip.topic,/CALL ga_store_ingest_tx/);assert.equal(JSON.parse(ip.payload[4]).rows[0].rssi,-67);assert.equal(JSON.parse(ip.payload[4]).gap_inserts.length,0);assert.equal((ip.topic.match(/\?/g)||[]).length,ip.payload.length);

ip=invoke('p21_live_history_process',{ga_ingest:{...fixedIngest},payload:[]});
assert.equal(ip.ga_ingest_result.inserted_buckets,0);assert.match(ip.topic,/CALL ga_store_ingest_tx/);assert.equal(JSON.parse(ip.payload[4]).gap_inserts.length,1);assert.equal((ip.topic.match(/\?/g)||[]).length,ip.payload.length);

ip=invoke('p21_live_history_process',{ga_ingest:{...fixedIngest,open_gap_id:'ha-gap-live',open_gap_started_at:'2026-09-28T17:55:00.000Z'},payload:historyRows});
assert.equal(JSON.parse(ip.payload[4]).gap_closes[0].id,'ha-gap-live');assert.equal((ip.topic.match(/\?/g)||[]).length,ip.payload.length);
const caughtUp={...ihMsg.ga_ingest,import_start:new Date(Date.now()-5*60000).toISOString(),import_end:new Date().toISOString(),target_import_end:new Date().toISOString()};
let iw=invoke('p21_live_ingest_write_result',{ga_ingest:caughtUp,ga_ingest_result:{inserted_buckets:1,partial_buckets:0},payload:[[{_set:'active',session_id:'live-session'}],[{_set:'ingest',session_id:'live-session',source_profile_id:sourceRow.source_profile_id,last_import_cutoff_at:caughtUp.import_end,last_success_at:caughtUp.import_end,open_gap_id:null,open_gap_started_at:null,last_error:null,inserted_buckets:1,partial_buckets:0}],[{_set:'latest_5m',session_id:'live-session',bucket_at:caughtUp.import_end,sample_count:55,sg_min:1.0397,sg_mean:1.0399,sg_median:1.0399,sg_max:1.0401,temperature_mean_c:9.9,pressure_mean_bar:null,rssi_mean_dbm:-67}]]});
assert.equal(iw.length,7);assert.equal(iw[2],null);assert.ok(iw[5]&&iw[5].ga_ingest_reason==='live_tick');assert.ok(iw[3]&&iw[3].ga_measurement_source_refresh===true);assert.ok(iw[6]&&iw[6].ga_systemcheck_reason==='measurement_source_live');
const ms=invoke('p21_measurement_source_read_result',{payload:[{...Object.fromEntries(JSON.parse(fs.readFileSync(path.join(root,'contracts/ha-node-red-contract.json'),'utf8')).fields.filter(f=>f.projection_id==='measurement_source'&&f.field_path.startsWith('attributes.')).map(f=>[f.field_path.slice(11),'Explicit DB display fixture'])),_set:'measurement_status',state:'LIVE',message:'HA-import aktiv',source_profile_id:sourceRow.source_profile_id,name:sourceRow.name,source_type:'home_assistant',sg_entity_id:sourceRow.sg_entity_id,temperature_entity_id:sourceRow.temperature_entity_id,heartbeat_entity_id:sourceRow.heartbeat_entity_id,rssi_entity_id:sourceRow.rssi_entity_id,poll_interval_seconds:300,gap_threshold_seconds:300,session_id:'live-session',latest_bucket_at:caughtUp.import_end,latest_sample_count:55,sg_median:1.0399,rssi_mean_dbm:-67,latest_sg_display:'median 1,0399',latest_rssi_display:'-67,0 dBm',import_cutoff_display:'28.09.2026 20:00',last_success_display:'28.09.2026 20:00',poll_interval_display:'300 s',gap_threshold_display:'300 s',gap_status_display:'Ingen åpent gap',last_error_display:'Ingen',updated_at:caughtUp.import_end,source:'MariaDB',authority:'MariaDB'},...JSON.parse(fs.readFileSync(path.join(root,'contracts/ha-node-red-contract.json'),'utf8')).fields.filter(f=>f.projection_id==='measurement_source')]});
assert.equal(ms.payload.state,'LIVE');assert.equal(ms.payload.attributes.rssi_mean_dbm,-67);assert.equal(ms.payload.attributes.authority,'MariaDB');assert.equal(ms.payload.attributes.updated_at,caughtUp.import_end);assert.equal(ms.payload.attributes.latest_sg_display,'median 1,0399');

// p22r7: DB-declared measurement validation rejects impossible raw values before measurements_5m.
const validationRules=[
 {signal_id:'sg',rule_id:'sg-range',rule_order:1,model_id:'hard_range_v1',parameters:{minimum_value:0.98,maximum_value:1.2}},
 {signal_id:'sg',rule_id:'sg-min',rule_order:2,model_id:'minimum_acceptance_v1',parameters:{minimum_samples:2,minimum_fraction:0.5}},
 {signal_id:'temperature',rule_id:'temp-range',rule_order:1,model_id:'hard_range_v1',parameters:{minimum_value:-5,maximum_value:40}},
 {signal_id:'temperature',rule_id:'temp-min',rule_order:2,model_id:'minimum_acceptance_v1',parameters:{minimum_samples:2,minimum_fraction:0.5}},
 {signal_id:'rssi',rule_id:'rssi-range',rule_order:1,model_id:'hard_range_v1',parameters:{minimum_value:-130,maximum_value:-1}}
];
const filteredRows=[...historyRows,{entity_id:sourceRow.sg_entity_id,state:'9.9900',last_updated:'2026-09-28T18:03:10.000Z'}];
let validated=invoke('p21_live_history_process',{ga_ingest:{...fixedIngest,validation_rules:validationRules,previous:{sg:null,temperature:null,rssi:null,at:null},poll_interval_seconds:300},payload:filteredRows});
assert.equal(validated.ga_ingest_result.inserted_buckets,1);assert.match(validated.topic,/ga_store_ingest_tx/);assert.equal(JSON.parse(validated.payload[4]).quality.find(q=>q.signal==='sg').accepted,2);assert.ok(JSON.parse(validated.payload[4]).rows[0].sgmax<2);
console.log('RESULT: PASS – p22r7 generic input validation rejects impossible Tilt values before 5-minute persistence');

// p22r7: analysis series obey frozen metadata; impossible derived output is rejected, never clamped or written as a fake value.
const analysisMeasurements=[];for(let i=0;i<15;i++)analysisMeasurements.push({_set:'measurements',bucket_at:`2026-09-28T${String(18+Math.floor(i/12)).padStart(2,'0')}:${String((i%12)*5).padStart(2,'0')}:00.000Z`,sg_median:i<12?1.05:2.0,sample_count:10});
const analysisPayload=[
 [{_set:'context',session_id:'analysis-session',og:1.05,pitched_at:'2026-09-28T18:00:00.000Z',source_started_at:'2026-09-28T18:00:00.000Z',expected_fg_min:1.01,expected_fg_max:1.012,database_now:'2026-09-28T20:00:00.000Z'}],
 [{_set:'series_defs',session_id:'analysis-session',graph_id:'g',series_id:'s',source_kind:'metric',metric_id:'derived-x',provisional_allowed:1,provisional_minimum_samples:3,provisional_minimum_span_minutes:10,band_model:'derived_input_range',minimum_samples:3,minimum_coverage_fraction:0,warmup_minutes:0,valid_minimum_value:-100,valid_maximum_value:100}],
 analysisMeasurements,
 [{_set:'metric_rules',metric_id:'derived-x',calculation_model_id:'metric-raw-sg-drop-v1'}],
 [{_set:'metric_inputs',metric_id:'derived-x',input_id:'tilt_baseline',source_kind:'biology_calculation',source_id:'base'}],
 [{_set:'metric_params',metric_id:'derived-x',parameter_id:'current_sample_count',data_type:'integer',integer_value:3}],
 [{_set:'calc_rules',calculation_id:'base',model_id:'median_first_samples'}],
 [{_set:'calc_median',calculation_id:'base',model_id:'median_first_samples',sample_count:12}]
];
let analysisOut=invoke('p22_analysis_result',{payload:analysisPayload});assert.ok(analysisOut.ga_analysis.rejected_values>0);assert.match(analysisOut.topic,/analysis_validation_events/);assert.equal(analysisOut.payload.includes(-950),false);
console.log('RESULT: PASS – p22r7 analysis output validation rejects impossible derived values instead of clamping/persisting them');



// p24r1: biological phases are criterion-derived; direct manual setter is absent.
assert.equal(byId.p23_bio_phase_correction_query,undefined);
const bioRequest={evaluation_id:'ev-current',criterion_id:'c',action:'register',exception_type:'akseptert_avvik',confirmed:true,note:'',operation_id:'bio-ex-test'};
let bc7=invoke('p24_bio_exception_context',{payload:{event:{data:bioRequest}}});
assert.ok(bc7[0]);assert.equal(bc7[1],null);assert.match(bc7[0].topic,/v_current_biological_candidate_evaluation/);
assert.equal(invoke('p24_bio_exception_context',{payload:{event:{data:{...bioRequest,confirmed:false}}}})[0],null);
let bioContext={...bc7[0],payload:[[{_set:'criterion',session_id:'s',evaluation_id:'ev-current',criterion_id:'c',candidate_phase_id:'B2',exception_allowed:1,met:0,evaluation_status:'not_met'}]]};
let bcr=invoke('p24_bio_exception_context_result',bioContext);
assert.ok(bcr[0]);assert.match(bcr[0].topic,/INSERT INTO biological_criterion_exceptions/);assert.doesNotMatch(bcr[0].topic,/UPDATE biological_evaluation/);assert.ok(bcr[0].payload.includes(null));
assert.equal(invoke('p24_bio_exception_context_result',{...bioContext,payload:[[{...bioContext.payload[0][0],exception_allowed:0}]]})[0],null);
assert.equal(invoke('p24_bio_exception_context_result',{...bioContext,payload:[[{...bioContext.payload[0][0],evaluation_status:'invalid_configuration'}]]})[0],null);
// p23r2-revised7: Technical measurement export is DB-backed and produces a complete range CSV.
let meq=invoke('p23_measurement_export_query',{payload:{event:{data:{filename:'20261004T003000-gjaeringsassistent-maledata.csv',operation_id:'measurement-export-test-1'}}}});
assert.equal(meq.ga_route,'measurement_export');assert.match(meq.topic,/FROM v_session_measurement_series/);assert.match(meq.topic,/FROM v_measurement_data_gaps/);
assert.match(meq.topic,/temperature_min_c/);assert.match(meq.topic,/pressure_max_bar/);assert.match(meq.topic,/rssi_min_dbm/);
let mer=invoke('p23_measurement_export_result',{ga_export_filename:meq.ga_export_filename,ga_export_operation_id:meq.ga_export_operation_id,payload:[
 [{_set:'meta',session_id:'s-export',batch_name:'Batch export',pitched_at_utc:'2026-09-25T20:00:00.000Z',pitched_at_local:'2026-09-25 22:00:00',og:1.047,volume_l:150,expected_attenuation_min_percent:80,expected_attenuation_max_percent:84,expected_fg_min:1.0075,expected_fg_max:1.0094}],
 [{_set:'measurement',session_id:'s-export',timestamp_utc:'2026-10-03T20:00:00.000Z',timestamp_local:'2026-10-03 22:00:00',sample_count:42,sg_min:1.0134,sg_mean:1.0136,sg_median:1.0136,sg_max:1.0138,temperature_min_c:14.1,temperature_mean_c:14.2,temperature_max_c:14.3,pressure_min_bar:0.39,pressure_mean_bar:0.4,pressure_max_bar:0.41,rssi_min_dbm:-70,rssi_mean_dbm:-68,rssi_max_dbm:-66}],
 [{_set:'gap',session_id:'s-export',source:'home_assistant_heartbeat',gap_started_at_utc:'2026-09-26T00:00:00.000Z',gap_started_at_local:'2026-09-26 02:00:00',gap_ended_at_utc:'2026-09-26T01:00:00.000Z',gap_ended_at_local:'2026-09-26 03:00:00',duration_seconds:3600,threshold_seconds:300}]
]});
assert.ok(Array.isArray(mer));assert.ok(mer[0]);assert.equal(mer[1].ga_event.code,'MEASUREMENT_EXPORT_CREATED');
assert.match(mer[0].filename,/20261004T003000-gjaeringsassistent-maledata\.csv$/);
assert.match(mer[0].payload,/row_type,session_id,batch_name/);assert.match(mer[0].payload,/measurement,s-export/);assert.match(mer[0].payload,/1\.0134,1\.0136,1\.0136,1\.0138/);assert.match(mer[0].payload,/14\.1,14\.2,14\.3/);assert.match(mer[0].payload,/0\.39,0\.4,0\.41/);assert.match(mer[0].payload,/-70,-68,-66/);assert.match(mer[0].payload,/gap,s-export/);
let merEmpty=invoke('p23_measurement_export_result',{ga_export_filename:'20261004T003000-gjaeringsassistent-maledata.csv',ga_export_operation_id:'measurement-export-test-empty',payload:[[],[],[]]});
assert.equal(merEmpty[0],null);assert.equal(merEmpty[1].ga_event.code,'MEASUREMENT_EXPORT_REJECTED');
console.log('RESULT: PASS – p23r2 revised7/revised8 criterion-derived B and MariaDB measurement export');

// p23: UAT registration is validated against the structured test catalog and persisted append-only.
let vu=invoke('p23_verification_uat_context',{payload:{event:{data:{test_id:'TEST-UAT-009',result_status:'pass',executor:'Operator',note:'Måltest OK',evidence_ref:'tech-export.json',environment:'HA target',operation_id:'uat-op-1'}}}});
assert.equal(vu.ga_route,'verification_uat_context');
assert.match(vu.topic,/verification_tests/);assert.match(vu.topic,/test_type='UAT'/);assert.equal(vu.ga_uat_req.result_status,'pass');
assert.equal(invoke('p23_verification_uat_context',{payload:{event:{data:{test_id:'TEST-FUNC-001',result_status:'pass'}}}}),null);
let vuw=invoke('p23_verification_uat_context_result',{...vu,payload:[[{test_id:'TEST-UAT-009',title:'Verifikasjonsfane og UAT-lagring',application_version:releaseVersion}]]});
assert.equal(vuw.ga_route,'verification_uat_write');
assert.match(vuw.topic,/START TRANSACTION/);assert.match(vuw.topic,/INSERT INTO verification_test_runs/);assert.match(vuw.topic,/INSERT INTO verification_test_results/);assert.match(vuw.topic,/COMMIT/);
assert.doesNotMatch(vuw.topic,/UPDATE verification_test_results|DELETE FROM verification_test_results/);

// JSON and HTML export are rendered from the exact same DB result payload.
const exportPayload=[
 [{_set:'meta',application_version:releaseVersion,generated_at:'2026-10-01 20:00:00.000'}],
 [{_set:'summary',test_type:'UAT',test_type_display:'Målmiljø / UAT',test_count:10,pass_count:1,fail_count:0,blocked_count:0,not_run_count:9}],
 [{_set:'requirements',requirement_id:'REQ-HA-064',verification_status:'pass',verification_status_display:'Bestått',statement:'UAT-resultat lagres append-only',source_ref:'03-KRAV-DASHBOARD.md'}],
 [{_set:'verifications',verification_id:'VER-UAT-001',verification_status:'pass',verification_status_display:'Bestått'}],
 [{_set:'tests',test_id:'TEST-UAT-009',test_type:'UAT',current_status:'pass',current_status_display:'Bestått',title:'Verifikasjonsfane og UAT-lagring',observed_at:'2026-10-01 20:00:00.000',note:'Måltest OK'}],
 [{_set:'requirement_links',requirement_id:'REQ-HA-064',verification_id:'VER-UAT-001',required:1}],
 [{_set:'test_links',verification_id:'VER-UAT-001',test_id:'TEST-UAT-009',required:1}],
 [{_set:'decisions',decision_id:'DEC-GA-047',decision:'UAT append-only'}],
 [{_set:'decision_links',decision_id:'DEC-GA-047',requirement_id:'REQ-HA-064'}],
 [{_set:'uat_steps',test_id:'TEST-UAT-009',step_order:1,instruction:'Registrer',expected_result:'Lagret'}],
 [{_set:'runs',run_id:'uat-run'}],
 [{_set:'history',result_id:'result-1',test_id:'TEST-UAT-009',result_status:'pass'}],
 []
];
const ve=invoke('p23_verification_export_result',{ga_export_base:'verification-test',payload:exportPayload});
assert.equal(ve.length,2);assert.match(ve[0].filename,/verification-test\.json$/);assert.match(ve[1].filename,/verification-test\.html$/);
const veJson=JSON.parse(ve[0].payload);assert.equal(veJson.tests[0].current_status,'pass');assert.equal(veJson.requirements[0].verification_status,'pass');
assert.match(ve[1].payload,/<!doctype html>/i);assert.match(ve[1].payload,/REQ-HA-064/);assert.match(ve[1].payload,/TEST-UAT-009/);assert.match(ve[1].payload,/Bestått/);
console.log('RESULT: PASS – p23 structured UAT registration and shared JSON/HTML verification export');

console.log('RESULT: PASS – p21r13 active-session-driven Home Assistant ingestion, persisted RSSI/5-minute diagnostics and heartbeat gap lifecycle');
