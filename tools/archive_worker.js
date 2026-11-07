'use strict';
const {parentPort,workerData}=require('node:worker_threads');
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {createHash}=require('node:crypto');
const core=require('./sqlite_archive.js');
async function upload(db,id,dir){
 const [metadata]=await db.query('SELECT * FROM archive_uploads WHERE upload_id=?',[id]);const m=metadata[0];
 if(!m||!Number.isSafeInteger(Number(m.expected_bytes))||Number(m.expected_bytes)>512*1024*1024)throw Error('Opplasting mangler eller overskrider 512 MiB');
 const [chunks]=await db.query('SELECT chunk_no,payload FROM archive_upload_chunks WHERE upload_id=? ORDER BY chunk_no',[id]);
 if(chunks.length!==m.expected_chunks||chunks.some((c,i)=>c.chunk_no!==i))throw Error('Opplastingen er ikke ferdig. Vent på kvittering og prøv igjen.');
 const filename=path.join(dir,id+'.sqlite'),fd=fs.openSync(filename,'wx'),hash=createHash('sha256');let bytes=0;
 try{for(const c of chunks){fs.writeSync(fd,c.payload);bytes+=c.payload.length;hash.update(c.payload);}}finally{fs.closeSync(fd);}
 if(bytes!==Number(m.expected_bytes)||hash.digest('hex')!==m.sha256)throw Error('Opplastingens størrelse eller kontrollsum avviker');return filename;
}
async function event(db,j,status,message,result={}){
 const m=result.manifest||{};
 await db.query('INSERT INTO archive_transfer_events(operation_id,action,status,message,session_id,template_id,source_session_id,source_template_id,batch_name,template_name,pitched_display,measurement_count,archive_path,template_path,report_path,occurred_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,UTC_TIMESTAMP(3))',[
  j.operation_id,j.action,status,message,result.session_id||j.session_id||null,result.template_id||null,m.session_id||null,m.template_id||null,m.batch_name||null,m.template_name||null,m.pitched_at||null,m.measurement_count||null,result.session?.path||null,result.template?.path||null,result.report?.path||null
 ]);
}
async function run(config,job){
 const palette=require.resolve('node-red-node-mysql/package.json',{paths:[config.userDir||'/data',__dirname]});
 const driver=require(require.resolve('mysql2/promise',{paths:[path.dirname(palette)]}));
 const db=await driver.createConnection({...config.database,decimalNumbers:false,dateStrings:true,supportBigNumbers:true,bigNumberStrings:true,timezone:'Z',charset:'UTF8MB4_UNICODE_CI',multipleStatements:false});
 let dir;
 try{
  await db.query("SET time_zone='+00:00'");
  await event(db,job,'busy','Arkivoperasjon pågår');let result;
  if(['export_session','export_template'].includes(job.action)){
   result=await core.exportArchive(db,{session_id:job.action==='export_session'?job.session_id:null,version_id:job.version_id,export_id:job.export_id||job.operation_id,output_dir:config.outputDir||'/data/gjaeringsassistent/ha-public/exports'});
  }else if(['delete_session','delete_template'].includes(job.action)){
   result=await require('./archive_admin.js').deleteArchive(db,job);if(result.idempotent)await event(db,job,'done','Slettingen er allerede fullført',result);return result;
  }else if(job.action==='inspect_files'){
   dir=fs.mkdtempSync(path.join(os.tmpdir(),'ga-archive-'));
   result=await require('./archive_catalog.js').inspectFiles(db,job,upload,dir);
  }else if(['preview','import_session','import_template'].includes(job.action)){


   if(job.action!=='preview'){
    const [existing]=job.action==='import_session'?await db.query('SELECT session_id,template_id FROM archive_imports WHERE operation_id=?',[job.operation_id]):await db.query("SELECT template_id FROM template_origins WHERE import_operation_id=? AND origin_kind='imported'",[job.operation_id]);
    if(existing.length){const result={...existing[0],idempotent:true};await event(db,job,'done','Arkivet er allerede importert',result);return result;}
   }
   if(job.candidate_id){const [candidate]=await db.query('SELECT * FROM v_archive_import_candidates WHERE candidate_id=?',[job.candidate_id]);if(!candidate.length)throw Error('Velg et kontrollert arkiv på nytt');job.template_upload_id=candidate[0].template_upload_id;job.session_upload_id=job.action==='import_session'?candidate[0].session_upload_id:null;const [warnings]=await db.query('SELECT message FROM archive_checksum_warnings WHERE operation_id=? AND upload_id IN(?,?)',[candidate[0].operation_id,job.template_upload_id,job.session_upload_id]);job.checksum_warning_messages=warnings.map(w=>w.message);}
   dir=fs.mkdtempSync(path.join(os.tmpdir(),'ga-archive-'));
   const files={template:await upload(db,job.template_upload_id,dir)};if(job.session_upload_id)files.session=await upload(db,job.session_upload_id,dir);
   if(job.action==='import_session'&&!files.session)throw Error('Gjæringsimport krever begge SQLite-filene');
   if(job.action==='import_template')delete files.session;
   const p=await core.preview(db,files);result={manifest:p.template.manifest};
   if(job.action!=='preview')Object.assign(result,await core.importArchive(db,files,job.operation_id));
  }else throw Error('Ukjent arkivhandling');
  await event(db,job,['preview','inspect_files'].includes(job.action)?'preview':'done',job.action==='inspect_files'?`Arkivfiler kontrollert · ${result.candidate_count} valg · ${result.warnings.length} SHA-advarsler`:job.action==='preview'?'Arkiv kontrollert · klar for import':(result.idempotent?'Arkivet er allerede importert':'Arkivoperasjon fullført')+(job.checksum_warning_messages?.length?' · Advarsel: '+job.checksum_warning_messages.join(' · '):''),result);
  if(job.action.startsWith('import_'))for(const id of [job.template_upload_id,job.session_upload_id].filter(Boolean)){await db.query('DELETE FROM archive_upload_chunks WHERE upload_id=?',[id]);await db.query('DELETE FROM archive_uploads WHERE upload_id=?',[id]);}
  return result;
 }catch(e){await db.rollback().catch(()=>{});await event(db,job,'failed',String(e.message)).catch(()=>{});throw e;
 }finally{if(dir)fs.rmSync(dir,{recursive:true,force:true});await db.end();}
}
module.exports={run,upload,event};
if(parentPort)run(workerData.config,workerData.job).then(result=>parentPort.postMessage({result})).catch(e=>parentPort.postMessage({error:String(e.message)}));
