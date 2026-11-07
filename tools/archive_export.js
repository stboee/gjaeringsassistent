'use strict';
// Technical file transport only. Domain data are serialized by the DB exporter.
const fs=require('node:fs'),fsp=fs.promises,path=require('node:path');
const {createHash,randomUUID}=require('node:crypto');
const {Transform}=require('node:stream'),{pipeline}=require('node:stream/promises');
async function digest(file){
 const hash=createHash('sha256');let bytes=0;
 for await(const chunk of fs.createReadStream(file)){hash.update(chunk);bytes+=chunk.length;}
 return {sha256:hash.digest('hex'),bytes};
}
async function publish(source,target,expectedBytes){
 if(!Number.isSafeInteger(expectedBytes)||expectedBytes<1)throw Error('Ugyldig forventet filstørrelse');
 if(source===target||path.dirname(source)!==path.dirname(target))throw Error('Ugyldige arkivstier');
 const temp=target+'.writing-'+randomUUID(),hash=createHash('sha256');let bytes=0;
 try{
  await pipeline(fs.createReadStream(source),new Transform({transform(chunk,enc,done){hash.update(chunk);bytes+=chunk.length;done(null,chunk);}}),fs.createWriteStream(temp,{flags:'wx',mode:0o644}));
  const expected=hash.digest('hex');
  if(bytes!==expectedBytes)throw Error(`Filstørrelse avviker: ${bytes} != ${expectedBytes}`);
  const written=await digest(temp);
  if(written.bytes!==bytes||written.sha256!==expected)throw Error('Kontrollsum av skrevet fil avviker fra eksporterte byte');
  // Link refuses to overwrite an earlier immutable export, then remove temp.
  await fsp.link(temp,target);await fsp.unlink(temp);
  const final=await digest(target);
  if(final.bytes!==bytes||final.sha256!==expected)throw Error('Sluttkontroll av publisert fil feilet');
  return {path:target,sha256:expected,bytes};
 }finally{await fsp.unlink(temp).catch(e=>{if(e.code!=='ENOENT')throw e;});}
}
async function exportJob(job){
 if(!job||!job.session_id||!job.attempt_id)throw Error('Eksportjobb mangler session/attempt');
 let archive,template;
 if(job.template_path){
  archive={path:job.archive_path,...await digest(job.archive_path)};
  template={path:job.template_path,...await digest(job.template_path)};
  if(archive.bytes!==job.archive_bytes||archive.sha256!==job.archive_sha256||template.bytes!==job.template_bytes||template.sha256!==job.template_sha256)throw Error('SQLite-par har endret størrelse eller kontrollsum');
 }else archive=await publish(job.stage_json_path,job.archive_path,job.archive_bytes);
 const report=await publish(job.stage_report_path,job.report_path,job.report_bytes);
 if(job.stage_json_path)await fsp.unlink(job.stage_json_path);await fsp.unlink(job.stage_report_path);
 return {status:'verified',archive_path:archive.path,archive_sha256:archive.sha256,archive_bytes:archive.bytes,template_path:template?.path,template_sha256:template?.sha256,template_bytes:template?.bytes,report_path:report.path,report_sha256:report.sha256,report_bytes:report.bytes};
}
module.exports={digest,publish,exportJob};
if(require.main===module){
 (async()=>{
  let job;
  try{job=JSON.parse(Buffer.from(process.argv[2]||'','base64').toString('utf8'));const result=await exportJob(job);process.stdout.write(JSON.stringify(result)+'\n');}
  catch(e){process.stdout.write(JSON.stringify({status:'failed',error_message:String(e.message),archive_path:job?.archive_path??null,report_path:job?.report_path??null})+'\n');process.exitCode=1;}
 })();
}
