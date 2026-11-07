'use strict';
const core=require('./sqlite_archive.js'),{randomUUID}=require('node:crypto');
function checksumNotice(filename,sha,sidecars){
 const side=(sidecars||[]).find(f=>f.filename===filename+'.sha'||f.filename===filename+'.sha256');
 if(!side)return {kind:'missing',message:`${filename}: SHA-fil mangler. Import er fortsatt tillatt.`};
 const lines=String(side.text||'').trim().split(/\r?\n/);const match=lines.length===1?lines[0].match(/^([0-9a-fA-F]{64})(?:\s+\*?(.+))?$/):null;
 if(!match||match[2]&&match[2]!==filename)return {kind:'unreadable',message:`${filename}: SHA-filen kan ikke tolkes for denne filen. Import er fortsatt tillatt.`};
 if(match[1].toLowerCase()!==sha)return {kind:'mismatch',message:`${filename}: SHA-256 avviker fra SHA-filen. Import er fortsatt tillatt.`};return null;
}
async function inspectFiles(db,job,upload,dir){
 const meta=await core.metadata(db),items=[];await db.beginTransaction();
 await db.query('DELETE FROM archive_import_candidates WHERE operation_id=?',[job.operation_id]);await db.query('DELETE FROM archive_checksum_warnings WHERE operation_id=?',[job.operation_id]);
 for(const id of job.upload_ids){const file=await upload(db,id,dir);const [rows]=await db.query('SELECT filename,sha256 FROM archive_uploads WHERE upload_id=?',[id]);const name=rows[0].filename;
  let archive;try{archive=core.readSqlite(file,'template',meta);}catch(e){try{archive=core.readSqlite(file,'session',meta);}catch(_){throw e;}}
  const notice=checksumNotice(name,rows[0].sha256,job.checksum_files);if(notice)await db.query('INSERT INTO archive_checksum_warnings(operation_id,upload_id,filename,warning_kind,message,created_at) VALUES(?,?,?,?,?,UTC_TIMESTAMP(3))',[job.operation_id,id,name,notice.kind,notice.message]);items.push({id,file,...archive});
 }
 const templates=items.filter(i=>i.manifest.role==='template');if(!templates.length)throw Error('Velg minst ett template-arkiv');
 for(const t of templates){const matched=items.filter(s=>s.manifest.role==='session'&&['export_id','session_id','template_version_id','template_id'].every(k=>s.manifest[k]===t.manifest[k]));if(matched.length>1)throw Error('Flere gjæringsfiler til samme eksportsett');
  const session=matched[0];const p=await core.preview(db,{template:t.file,session:session?.file});const m=p.template.manifest,tv=p.template.rows.template_versions[0];
  await db.query('INSERT INTO archive_import_candidates(candidate_id,operation_id,template_upload_id,session_upload_id,source_export_id,source_session_id,template_name,version_label,batch_name,pitched_at,snapshot_kind,measurement_count,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,UTC_TIMESTAMP(3))',['candidate-'+randomUUID().replaceAll('-',''),job.operation_id,t.id,session?.id||null,m.export_id,m.session_id||null,tv.name,tv.version_label,m.batch_name||null,m.pitched_at||null,m.snapshot_kind||'completed_archive',session?Number(m.measurement_count):0]);
 }
 const unmatched=items.filter(i=>i.manifest.role==='session'&&!templates.some(t=>['export_id','session_id','template_version_id','template_id'].every(k=>i.manifest[k]===t.manifest[k])));if(unmatched.length)throw Error('En gjæringsfil mangler sitt tilhørende template-arkiv');
 const [warnings]=await db.query('SELECT * FROM archive_checksum_warnings WHERE operation_id=?',[job.operation_id]);await db.commit();return {candidate_count:templates.length,warnings};
}
module.exports={checksumNotice,inspectFiles};
