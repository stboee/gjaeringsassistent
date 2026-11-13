'use strict';
// File interchange only. MariaDB owns runtime data and all imported history.
const fs=require('node:fs'),path=require('node:path');
const {DatabaseSync}=require('node:sqlite');
const {randomUUID,createHash}=require('node:crypto');
const contract=require('./archive_contract.json');
const {digest}=require('./archive_export.js');
const q=s=>'`'+String(s).replace(/`/g,'``')+'`';
const uuid=()=>randomUUID().replaceAll('-','');
const allowed=new Set([...contract.session_tables,...contract.template_tables,...contract.registry_tables]);
const owned=new Set([...contract.session_tables,...contract.template_tables]);
const key=(t,r)=>JSON.stringify(t.pk.map(k=>r[k]));
const plain=v=>v===undefined?null:Buffer.isBuffer(v)?new Uint8Array(v):typeof v==='bigint'?v.toString():v;
async function metadata(db,includeAll=false){
 const [cols]=await db.query("SELECT TABLE_NAME,COLUMN_NAME,DATA_TYPE,IS_NULLABLE,EXTRA FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() ORDER BY TABLE_NAME,ORDINAL_POSITION");
 const [keys]=await db.query("SELECT TABLE_NAME,COLUMN_NAME,REFERENCED_TABLE_NAME,REFERENCED_COLUMN_NAME,CONSTRAINT_NAME FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA=DATABASE() ORDER BY TABLE_NAME,CONSTRAINT_NAME,ORDINAL_POSITION");
 const [tables]=await db.query("SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE='BASE TABLE'");const base=new Set(tables.map(t=>t.TABLE_NAME));
 const out={};
 for(const c of cols)if((allowed.has(c.TABLE_NAME)||(includeAll&&base.has(c.TABLE_NAME)))&&!c.EXTRA.includes('GENERATED')){
  const t=out[c.TABLE_NAME]??={columns:[],pk:[],fks:[]};t.columns.push({name:c.COLUMN_NAME,type:c.DATA_TYPE,nullable:c.IS_NULLABLE==='YES',auto:c.EXTRA.includes('auto_increment')});
 }
 for(const k of keys)if(out[k.TABLE_NAME]){
  const t=out[k.TABLE_NAME];if(k.CONSTRAINT_NAME==='PRIMARY')t.pk.push(k.COLUMN_NAME);
  if(k.REFERENCED_TABLE_NAME){let fk=t.fks.find(f=>f.name===k.CONSTRAINT_NAME);if(!fk){fk={name:k.CONSTRAINT_NAME,table:k.REFERENCED_TABLE_NAME,columns:[],references:[]};t.fks.push(fk);}fk.columns.push(k.COLUMN_NAME);fk.references.push(k.REFERENCED_COLUMN_NAME);}
 }
 return out;
}
async function snapshot(db,sessionId,versionId){
 const meta=await metadata(db),rows=Object.fromEntries(Object.keys(meta).map(t=>[t,new Map()]));
 const fetched=new Set();
 // Global presentation facts are DB-owned registry data in both archives.
 const [renderPolicy]=await db.query('SELECT * FROM graph_render_policy');
 for(const row of renderPolicy)rows.graph_render_policy.set(key(meta.graph_render_policy,row),row);
 const add=(name,list)=>{let n=0;for(const row of list){const k=key(meta[name],row);if(!rows[name].has(k)){rows[name].set(k,row);n++;}}return n;};
 const select=async(name,where,args)=>{const [list]=await db.query(`SELECT ${meta[name].columns.map(c=>q(c.name)).join(',')} FROM ${q(name)} WHERE ${where}`,args);return add(name,list);};
 if(sessionId){for(const name of contract.session_tables)if(meta[name]?.columns.some(c=>c.name==='session_id'))await select(name,'session_id=?',[sessionId]);}
 for(const name of contract.template_tables)if(meta[name]?.columns.some(c=>c.name==='version_id'))await select(name,'version_id=?',[versionId]);
 // Pull dependent history rows, then referenced registries. Never walk back
 // from shared registries into unrelated sessions or templates.
 let changed=true;while(changed){changed=false;
  for(const [name,t] of Object.entries(meta))for(const fk of t.fks){
   if(!meta[fk.table])continue;
   if(owned.has(name)&&owned.has(fk.table)&&!t.columns.some(c=>c.name==='session_id'||c.name==='version_id')&&name!=='sessions'&&name!=='templates'){
    const parents=[...rows[fk.table].values()].filter(r=>{const k='back|'+name+'|'+fk.name+'|'+key(meta[fk.table],r);if(fetched.has(k))return false;fetched.add(k);return true;});for(let i=0;i<parents.length;i+=300){const list=parents.slice(i,i+300);if(!list.length)continue;
     const where=list.map(()=>`(${fk.columns.map(c=>q(c)+'=?').join(' AND ')})`).join(' OR ');
     if(await select(name,where,list.flatMap(r=>fk.references.map(c=>r[c]))))changed=true;
    }
   }
   const values=[...rows[name].values()].filter(r=>{if(fk.columns.some(c=>r[c]===null))return false;const k='forward|'+name+'|'+fk.name+'|'+JSON.stringify(fk.columns.map(c=>r[c]));if(fetched.has(k))return false;fetched.add(k);return true;});
   // A published template is exported as one frozen version; its ancestry is
   // provenance, not another editable template in the package.
   if(name==='template_versions'&&fk.columns.includes('based_on_version_id'))continue;
   if(fk.table==='sessions'&&values.some(r=>r[fk.columns[0]]!==sessionId))throw Error('Snapshot inneholder en annen sesjon');
   for(let i=0;i<values.length;i+=300){const list=values.slice(i,i+300);if(!list.length)continue;
    const where=list.map(()=>`(${fk.references.map(c=>q(c)+'=?').join(' AND ')})`).join(' OR ');
    if(await select(fk.table,where,list.flatMap(r=>fk.columns.map(c=>r[c]))))changed=true;
   }
  }
 }
 return {meta,rows};
}
function writeSqlite(filename,manifest,meta,rows,role){
 const file=new DatabaseSync(filename);try{
  file.exec('PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; PRAGMA application_id=1195463745; BEGIN');
  file.exec('CREATE TABLE archive_manifest(key TEXT PRIMARY KEY,value TEXT NOT NULL)');
  const m=file.prepare('INSERT INTO archive_manifest VALUES(?,?)');for(const [k,v]of Object.entries({...manifest,role}))m.run(k,String(v));
  for(const [name,t]of Object.entries(meta)){
   if(role==='template'&&contract.session_tables.includes(name))continue;
   if(role==='session'&&contract.template_tables.includes(name))continue;
   const list=[...rows[name].values()];if(!list.length)continue;
   const type=c=>['tinyint','smallint','mediumint','int','bigint'].includes(c.type)?'INTEGER':['blob','mediumblob','longblob','binary','varbinary'].includes(c.type)?'BLOB':'TEXT';
   file.exec(`CREATE TABLE ${q(name)} (${t.columns.map(c=>q(c.name)+' '+type(c)).join(',')}, PRIMARY KEY(${t.pk.map(q).join(',')})) WITHOUT ROWID`);
   const stmt=file.prepare(`INSERT INTO ${q(name)} VALUES (${t.columns.map(()=>'?').join(',')})`);
   for(const row of list)stmt.run(...t.columns.map(c=>plain(row[c.name])));
  }
  file.exec('COMMIT');if(file.prepare('PRAGMA integrity_check').get().integrity_check!=='ok')throw Error('SQLite integritetskontroll feilet');
 }finally{file.close();}
}
function readSqlite(filename,expectedRole,meta){
 const file=new DatabaseSync(filename,{readOnly:true});try{
  if(file.prepare('PRAGMA application_id').get().application_id!==1195463745)throw Error('Filen er ikke et Gjæringsassistent-arkiv');
  if(file.prepare('PRAGMA integrity_check').get().integrity_check!=='ok')throw Error('SQLite integritetskontroll feilet');
  const manifest=Object.fromEntries(file.prepare('SELECT key,value FROM archive_manifest').all().map(r=>[r.key,r.value]));
  if(manifest.format!==contract.format||!['1',String(contract.version)].includes(manifest.version)||manifest.role!==expectedRole)throw Error('Ukjent arkivformat, versjon eller filrolle');
  const rows={},legacySourceProfiles=[];
  for(const item of file.prepare("SELECT name,type FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'").all()){
   if(item.name==='archive_manifest')continue;
   if(item.type!=='table'||!meta[item.name])throw Error('Arkivet inneholder en ukjent tabell eller et SQL-objekt');
   if(expectedRole==='template'&&contract.session_tables.includes(item.name)||expectedRole==='session'&&contract.template_tables.includes(item.name))throw Error('Tabell i feil arkivfil');
   const actual=file.prepare(`PRAGMA table_info(${q(item.name)})`).all().map(c=>c.name);
   const legacyPitch=manifest.version==='1'&&item.name==='sessions';
   const criterionSnapshot=['biological_evaluation_criterion_parameter_values','process_evaluation_criterion_parameter_values'].includes(item.name);
   const legacyCriterion=criterionSnapshot&&!actual.includes('is_unset');
   const expected=meta[item.name].columns.map(c=>c.name);
   const oldPitch=['yeast_amount_g','slurry_volume_ml','slurry_source_batch','slurry_generation'];
   if(legacyPitch)expected.splice(expected.indexOf('oxygenation_note'),0,...oldPitch);
   const sourceExpected=legacyCriterion?expected.filter(c=>c!=='is_unset'):expected;
   // Exact released source-profile layout only. Preserve its four archived
   // identities separately; they are session provenance, never live settings.
   const oldSourceFields=['sg_entity_id','temperature_entity_id','heartbeat_entity_id','rssi_entity_id'];
   const oldSourceExpected=[...sourceExpected];oldSourceExpected.splice(oldSourceExpected.indexOf('source_type')+1,0,...oldSourceFields);
   const legacySource=item.name==='measurement_source_profiles'&&actual.join('|')===oldSourceExpected.join('|');
   if(!legacySource&&actual.join('|')!==sourceExpected.join('|'))throw Error('Arkivskjema passer ikke til installert versjon: '+item.name);
   const stmt=file.prepare(`SELECT * FROM ${q(item.name)}`);stmt.setReadBigInts(true);
   rows[item.name]=stmt.all().map(r=>Object.fromEntries(Object.entries(r).map(([k,v])=>[k,typeof v==='bigint'?v.toString():v])));
   if(legacySource)for(const row of rows[item.name]){legacySourceProfiles.push({...row});for(const field of oldSourceFields)delete row[field];}
   if(legacyCriterion)for(const row of rows[item.name]){if(['real_value','integer_value','boolean_value','text_value'].filter(k=>row[k]!==null).length!==1)throw Error('Eldre kriteriearkiv har ugyldig verdi');row.is_unset=0;}
   if(legacyPitch){
    rows.session_dry_pitches=[];rows.session_slurry_pitches=[];
    for(const session of rows.sessions){
     if(session.pitch_mode_id==='dry')rows.session_dry_pitches.push({session_id:session.session_id,pitch_mode_id:'dry',yeast_amount_g:session.yeast_amount_g});
     else if(session.pitch_mode_id==='slurry')rows.session_slurry_pitches.push({session_id:session.session_id,pitch_mode_id:'slurry',slurry_volume_ml:session.slurry_volume_ml,slurry_source_batch:session.slurry_source_batch,slurry_generation:session.slurry_generation});
     else throw Error('Eldre arkiv har ukjent pitchmodus');
     for(const field of oldPitch)delete session[field];
    }
   }
  }
  if(legacySourceProfiles.length&&['session_measurement_source_configurations','session_measurement_signal_bindings'].some(t=>rows[t]?.length))throw Error('Arkivet blander eldre sensorprofil og nyere kildehistorikk');
  return {manifest,rows,legacySourceProfiles};
 }finally{file.close();}
}
async function exportArchive(db,job){
 const id=job.session_id||null,root=job.output_dir,exportId=job.export_id||uuid();let version=job.version_id;
 if(id)await db.query('CALL ga_init_read_basis()');
 await db.query('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');await db.query('START TRANSACTION WITH CONSISTENT SNAPSHOT, READ ONLY');
 let snap,info,reportRows=[],clock,lifecycle;try{
  if(id){const [s]=await db.query('SELECT s.*,sts.template_version_id FROM sessions s JOIN session_template_snapshots sts ON sts.session_id=s.session_id WHERE s.session_id=?',[id]);if(s.length!==1)throw Error('Sesjonen finnes ikke');info=s[0];version=info.template_version_id;}
  else{const [v]=await db.query('SELECT * FROM template_versions WHERE version_id=?',[version]);if(v.length!==1||v[0].status==='draft')throw Error('Velg en publisert eller arkivert template');info=v[0];}
  const [now]=await db.query('SELECT UTC_TIMESTAMP(3) AS now');clock=now[0].now;
  snap=await snapshot(db,id,version);
  if(id){const [life]=await db.query('SELECT lifecycle FROM v_all_session WHERE session_id=?',[id]);lifecycle=life[0].lifecycle;
   await db.query('SET @ga_report_session=?,@ga_report_now=?',[id,clock]);
   for(const query of fs.readFileSync(path.join(__dirname,'report_queries.sql'),'utf8').split(';').map(s=>s.trim()).filter(Boolean)){const [rows]=await db.query(query);reportRows.push(...(Array.isArray(rows[0])?rows.filter(Array.isArray).flat():rows).filter(r=>r._set));}
  }await db.commit();
 }catch(e){await db.rollback();throw e;}finally{if(id)await db.query('CALL ga_drop_read_basis()');}
 const template=snap.rows.template_versions.get(JSON.stringify([version]));if(!template)throw Error('Template mangler i snapshot');
 const manifest={format:contract.format,version:contract.version,export_id:exportId,session_id:id||'',template_version_id:version,template_id:template.template_id,template_name:template.name,version_label:template.version_label,exported_at:clock,lifecycle:lifecycle||'',snapshot_kind:id?(lifecycle==='completed'?'completed_archive':'active_snapshot'):'template',batch_name:info.batch_name||'',pitched_at:info.pitched_at||'',measurement_count:id?String(snap.rows.measurements_5m.size+snap.rows.measurement_statistics_hourly.size):'0'};
 const reportHtml=id?require('./report_module.js')(reportRows).replace('</body>',`<p>${manifest.snapshot_kind==='active_snapshot'?'Øyeblikksbilde av aktiv gjæring':'Avsluttet gjæring'} · snapshot ${clock} UTC</p></body>`):null;
 if(id)manifest.report_sha256=createHash('sha256').update(reportHtml).digest('hex');
 const prefix=id?`session-${id}-export-${exportId}`:`template-${template.template_id}-export-${exportId}`;
 if(!/^[A-Za-z0-9._-]+$/.test(prefix))throw Error('Ugyldig arkiv-ID');fs.mkdirSync(root,{recursive:true});
 const results={};const created=[];let frozenManifest=manifest;
 const reportTarget=path.join(root,prefix+'.html');if(id&&fs.existsSync(path.join(root,prefix+'-gjaering.sqlite'))&&!fs.existsSync(reportTarget))throw Error('Ufullstendig eldre eksportsett. Bruk en ny eksport-ID.');
 const publish=(target,content)=>{if(fs.existsSync(target))return;const temp=target+'.writing-'+uuid();try{fs.writeFileSync(temp,content,{flag:'wx'});try{fs.linkSync(temp,target);created.push(target);}catch(e){if(e.code!=='EEXIST')throw e;}}finally{fs.rmSync(temp,{force:true});}};
 try{
  for(const role of id?['session','template']:['template']){
   const target=path.join(root,prefix+(role==='session'?'-gjaering.sqlite':'-template.sqlite')),temp=target+'.writing-'+uuid();
   const existing=async()=>{const p=readSqlite(target,role,snap.meta);for(const k of ['session_id','template_id','template_version_id','export_id'])if(p.manifest[k]!==String(manifest[k]))throw Error('Eksport-ID finnes med et annet arkivgrunnlag');frozenManifest={...p.manifest};delete frozenManifest.role;return {path:target,...await digest(target)};};
   if(fs.existsSync(target)){results[role]=await existing();continue;}
   try{writeSqlite(temp,frozenManifest,snap.meta,snap.rows,role);readSqlite(temp,role,snap.meta);const d=await digest(temp);try{fs.linkSync(temp,target);created.push(target);results[role]={path:target,...d};}catch(e){if(e.code!=='EEXIST')throw e;results[role]=await existing();}}finally{fs.rmSync(temp,{force:true});}
  }
  if(id){if(!fs.existsSync(reportTarget))publish(reportTarget,reportHtml);results.report={path:reportTarget,...await digest(reportTarget)};if(results.report.sha256!==frozenManifest.report_sha256)throw Error('Rapportens SHA-256 avviker fra det frosne eksportsettet');}
  for(const role of ['session','template'])if(results[role]){const r=results[role],side=r.path+'.sha';const content=r.sha256+'  '+path.basename(r.path)+'\n';if(fs.existsSync(side)&&fs.readFileSync(side,'utf8')!==content)throw Error('Eksportens SHA-fil avviker');publish(side,content);r.sha_path=side;}
  return {...results,manifest:frozenManifest};
 }catch(e){for(const f of created)fs.rmSync(f,{force:true});throw e;}
}
async function preview(db,files){
 const meta=await metadata(db),template=readSqlite(files.template,'template',meta),session=files.session?readSqlite(files.session,'session',meta):null;
 if(session)for(const k of ['export_id','session_id','template_version_id','template_id'])if(session.manifest[k]!==template.manifest[k])throw Error('Gjæringsarkiv og template-arkiv tilhører forskjellige eksportsett');
 if((template.rows.template_versions||[]).length!==1||(template.rows.templates||[]).length!==1)throw Error('Arkivet skal inneholde én template og én versjon');
 const tv=template.rows.template_versions[0];if(tv.version_id!==template.manifest.template_version_id||tv.template_id!==template.manifest.template_id)throw Error('Template-ID avviker fra manifestet');
 if(session&&((session.rows.sessions||[]).length!==1||session.rows.sessions[0].session_id!==session.manifest.session_id))throw Error('Sesjon avviker fra manifestet');
 for(const source of [template,session].filter(Boolean))for(const [name,list]of Object.entries(source.rows))for(const row of list){
  if(contract.session_tables.includes(name)&&'session_id' in row&&row.session_id!==session?.manifest.session_id)throw Error('Arkivet inneholder data fra en annen sesjon');
  if(contract.template_tables.includes(name)&&'version_id' in row&&row.version_id!==template.manifest.template_version_id)throw Error('Arkivet inneholder en annen template-versjon');
 }
 if(session){
  const life=[...(session.rows.session_lifecycle_events||[])].sort((a,b)=>String(a.occurred_at).localeCompare(String(b.occurred_at))||String(a.created_at).localeCompare(String(b.created_at)));
  if(life.at(-1)?.lifecycle!=='completed'&&session.manifest.snapshot_kind!=='active_snapshot')throw Error('Arkivet er ikke avsluttet historikk eller et merket aktivt øyeblikksbilde');
  const count=(session.rows.measurements_5m||[]).length+(session.rows.measurement_statistics_hourly||[]).length;
  if(String(count)!==session.manifest.measurement_count)throw Error('Antall målepunkter avviker fra manifestet');
 }
 return {meta,template,session,templateDigest:await digest(files.template),sessionDigest:session?await digest(files.session):null};
}
async function importArchive(db,files,operationId){
 if(!/^[A-Za-z0-9._-]{1,128}$/.test(operationId))throw Error('Ugyldig operasjons-ID');
 const p=await preview(db,files),m=p.template.manifest,newTemplate='import-template-'+uuid(),newVersion='import-version-'+uuid(),newSession=p.session?'import-session-'+uuid():null;
 const mappings=new Map(),mapKey=(t,c,v)=>t+'|'+c+'|'+String(v);
 const all={...p.template.rows};for(const [name,list]of Object.entries(p.session?.rows||{})){
  if(all[name]){const seen=new Map(all[name].map(r=>[key(p.meta[name],r),r]));for(const row of list){const k=key(p.meta[name],row);if(seen.has(k)&&JSON.stringify(seen.get(k))!==JSON.stringify(row))throw Error('Registerverdier avviker mellom filene: '+name);seen.set(k,row);}all[name]=[...seen.values()];}else all[name]=list;
 }
 const seed=(t,c,old,value)=>mappings.set(mapKey(t,c,old),value);
 seed('templates','template_id',m.template_id,newTemplate);seed('template_versions','version_id',m.template_version_id,newVersion);if(newSession)seed('sessions','session_id',m.session_id,newSession);
 for(const [name,list]of Object.entries(all))if(owned.has(name)){
  const t=p.meta[name];if(t.pk.length===1){const col=t.columns.find(c=>c.name===t.pk[0]);if(!col.auto&&!t.fks.some(f=>f.columns.includes(col.name))&&!['sessions','templates','template_versions'].includes(name)&&['varchar','char'].includes(col.type))for(const row of list)seed(name,col.name,row[col.name],'import-'+uuid());}
 }
 // All identity changes propagate through actual foreign keys, including
 // revision ancestry and cross references between criteria and exceptions.
 let changed=true;while(changed){changed=false;for(const [name,list]of Object.entries(all))for(const fk of p.meta[name].fks)for(const row of list)fk.columns.forEach((c,i)=>{
  const replacement=mappings.get(mapKey(fk.table,fk.references[i],row[c]));if(replacement!==undefined&&!mappings.has(mapKey(name,c,row[c]))){seed(name,c,row[c],replacement);changed=true;}
 });}
 const operations=new Map(),now=new Date().toISOString().replace('T',' ').replace('Z','');
 const transformed={};for(const [name,list]of Object.entries(all)){
  const sequence=p.meta[name].columns.find(c=>c.auto);if(sequence)list.sort((a,b)=>Number(a[sequence.name])-Number(b[sequence.name]));
  transformed[name]=list.map(source=>{
  const row={...source};for(const col of p.meta[name].columns){const v=mappings.get(mapKey(name,col.name,source[col.name]));if(v!==undefined)row[col.name]=v;
   if(col.auto)delete row[col.name];if(owned.has(name)&&col.name==='operation_id'&&!p.meta[name].fks.some(f=>f.columns.includes('operation_id'))&&row[col.name]){if(!operations.has(row[col.name]))operations.set(row[col.name],'import-op-'+uuid());row[col.name]=operations.get(row[col.name]);}
  }
  if(name==='template_versions'){row.based_on_version_id=null;row.status='retired';row.retired_at=now;if(!row.published_at||!row.version_label)throw Error('Bare publiserte templater kan importeres');}
  if(name==='analysis_series_values')row.basis_revision_key=row.source_observation_revision_id||'base';
  if(name==='measurement_statistics_hourly')row.statistic_import_id=createHash('sha256').update(newSession+'|'+source.statistic_import_id).digest('hex');
  return row;
 });}
 await db.beginTransaction();try{
  if(newSession){const [existing]=await db.query('SELECT * FROM archive_imports WHERE operation_id=? OR (original_session_id=? AND archive_sha256=? AND template_sha256=?)',[operationId,m.session_id,p.sessionDigest.sha256,p.templateDigest.sha256]);if(existing.length){await db.rollback();return {session_id:existing[0].session_id,template_id:existing[0].template_id,idempotent:true};}}
  else{const [existing]=await db.query("SELECT template_id FROM template_origins WHERE import_operation_id=? AND origin_kind='imported'",[operationId]);if(existing.length){await db.rollback();return {template_id:existing[0].template_id,idempotent:true};}}
  const pending=Object.entries(transformed).flatMap(([name,list])=>list.map(row=>({name,row}))),deferred=[];
  let breakNullableCycle=false;const parentsFound=new Set();
  while(pending.length){let progress=0;
   for(let i=0;i<pending.length;){const item=pending[i],t=p.meta[item.name],row=item.row;let ready=true;const nulls=[];
    for(const fk of t.fks){if(fk.columns.some(c=>row[c]===null||row[c]===undefined))continue;
     const parentKey=fk.table+'|'+JSON.stringify(fk.references)+'|'+JSON.stringify(fk.columns.map(c=>row[c]));
     if(parentsFound.has(parentKey))continue;
     const [found]=await db.query(`SELECT 1 FROM ${q(fk.table)} WHERE ${fk.references.map(c=>q(c)+'=?').join(' AND ')} LIMIT 1`,fk.columns.map(c=>row[c]));
     if(found.length)parentsFound.add(parentKey);
     else if(breakNullableCycle&&fk.columns.includes('applied_exception_id')&&t.columns.find(c=>c.name==='applied_exception_id').nullable)nulls.push('applied_exception_id');
     else{ready=false;break;}
    }
    if(!ready){i++;continue;}
    const cols=Object.keys(row),values=cols.map(c=>nulls.includes(c)?null:row[c]);
    if(!owned.has(item.name)){
     const [existing]=await db.query(`SELECT ${cols.map(q).join(',')} FROM ${q(item.name)} WHERE ${t.pk.map(c=>q(c)+'=?').join(' AND ')}`,t.pk.map(c=>row[c]));
     if(existing.length){for(const c of cols.filter(c=>!['created_at','updated_at'].includes(c)))if(String(existing[0][c])!==String(row[c]))throw Error('Arkivets registerdefinisjon støttes ikke: '+item.name+'/'+c);pending.splice(i,1);progress++;continue;}
    }
    await db.query(`INSERT INTO ${q(item.name)} (${cols.map(q).join(',')}) VALUES (${cols.map(()=>'?').join(',')})`,values);
    if(nulls.length)deferred.push({name:item.name,row,columns:[...new Set(nulls)]});pending.splice(i,1);progress++;
   }
   if(!progress){if(!breakNullableCycle){breakNullableCycle=true;continue;}throw Error('Arkivet har manglende eller sirkulære obligatoriske relasjoner: '+pending.slice(0,4).map(x=>x.name).join(', '));}
  }
  for(const d of deferred){const t=p.meta[d.name];await db.query(`UPDATE ${q(d.name)} SET ${d.columns.map(c=>q(c)+'=?').join(',')} WHERE ${t.pk.map(c=>q(c)+'=?').join(' AND ')}`,[...d.columns.map(c=>d.row[c]),...t.pk.map(c=>d.row[c])]);}
  await db.query("INSERT INTO template_origins(template_id,origin_kind,original_template_id,original_version_id,import_operation_id,source_sha256,created_at) VALUES(?,'imported',?,?,?,?,?)",[newTemplate,m.template_id,m.template_version_id,operationId,p.templateDigest.sha256,now]);
  if(newSession){
   await db.query('INSERT INTO session_release_events(release_event_id,session_id,released_at,operation_id,created_at) VALUES(?,?,?,?,?)',['release-'+uuid(),newSession,now,operationId,now]);
   await db.query('INSERT INTO archive_imports(import_id,operation_id,session_id,template_id,original_session_id,source_export_id,archive_sha256,template_sha256,imported_at) VALUES(?,?,?,?,?,?,?,?,?)',['import-'+uuid(),operationId,newSession,newTemplate,m.session_id,m.export_id,p.sessionDigest.sha256,p.templateDigest.sha256,now]);
  }
  await db.query('CALL ga_convert_legacy_archive_graphs(?,?)',[newVersion,newSession]);
  if(newSession&&p.session.legacySourceProfiles.length){
   // Technical conversion of the known old archive layout. The DB chooses
   // the archived cursor, canonical units and identity of the frozen revision.
   // Earlier source switches and validation bounds were not archived.
   const legacy=JSON.stringify(p.session.legacySourceProfiles);
   const [snapshot]=await db.query(`INSERT INTO session_measurement_source_configurations(session_id,configuration_id,effective_from,profile_name,note,created_at)
    SELECT m.session_id,1,m.last_import_cutoff_at,j.name,'Binding kjent fra eldre SQLite-arkiv ved importcursor; eldre kildebytter og kontrollgrenser er ikke registrert',UTC_TIMESTAMP(3)
    FROM session_measurement_sources m JOIN JSON_TABLE(?, '$[*]' COLUMNS(source_profile_id VARCHAR(128) PATH '$.source_profile_id',name VARCHAR(255) PATH '$.name')) j ON j.source_profile_id=m.source_profile_id WHERE m.session_id=?`,[legacy,newSession]);
   if(snapshot.affectedRows!==1)throw Error('Eldre arkiv mangler entydig sensorprofil for sesjonen');
   await db.query(`INSERT INTO session_measurement_signal_bindings(session_id,configuration_id,signal_id,input_mode,entity_id,unit_id,minimum_value,maximum_value)
    SELECT m.session_id,1,u.signal_id,IF(u.signal_id='pressure','manual','sensor'),
     CASE u.signal_id WHEN 'sg' THEN j.sg WHEN 'temperature' THEN j.temperature WHEN 'heartbeat' THEN j.heartbeat WHEN 'rssi' THEN j.rssi END,u.unit_id,NULL,NULL
    FROM session_measurement_sources m JOIN JSON_TABLE(?, '$[*]' COLUMNS(source_profile_id VARCHAR(128) PATH '$.source_profile_id',sg VARCHAR(255) PATH '$.sg_entity_id',temperature VARCHAR(255) PATH '$.temperature_entity_id',heartbeat VARCHAR(255) PATH '$.heartbeat_entity_id',rssi VARCHAR(255) PATH '$.rssi_entity_id')) j ON j.source_profile_id=m.source_profile_id
    CROSS JOIN measurement_source_units u WHERE m.session_id=? AND u.is_canonical=1 AND u.signal_id IN('sg','temperature','heartbeat','rssi','pressure')`,[legacy,newSession]);
  }
  await db.commit();return {session_id:newSession,template_id:newTemplate,version_id:newVersion,idempotent:false};
 }catch(e){await db.rollback();
  // Concurrent requests can race on the unique archive identity. The losing
  // transaction rolls back every new row, then returns the winning receipt.
  if(e.code==='ER_DUP_ENTRY'){const [existing]=newSession?await db.query('SELECT session_id,template_id FROM archive_imports WHERE operation_id=? OR (original_session_id=? AND archive_sha256=? AND template_sha256=?)',[operationId,m.session_id,p.sessionDigest.sha256,p.templateDigest.sha256]):await db.query('SELECT template_id FROM template_origins WHERE import_operation_id=?',[operationId]);if(existing.length)return {...existing[0],idempotent:true};}throw e;
 }
}
module.exports={metadata,snapshot,writeSqlite,readSqlite,exportArchive,preview,importArchive,contract};
