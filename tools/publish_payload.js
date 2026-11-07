#!/usr/bin/env node
'use strict';
// Reproducible publication derivatives. Runtime authority remains in MariaDB.
const fs=require('node:fs'),path=require('node:path'),zlib=require('node:zlib'),crypto=require('node:crypto');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
function inside(file,root){const relative=path.relative(path.resolve(root),path.resolve(file));if(!relative||relative.startsWith('..')||path.isAbsolute(relative))throw Error('Ugyldig publiseringssti');return path.resolve(file);}
function diagnosticSnapshot(publicRoot,level){
  const filename=path.join(publicRoot,'fermentation-overview.json');
  try{
    const bytes=fs.readFileSync(filename),data=JSON.parse(bytes);
    const result={status:'ok',filename:'fermentation-overview.json',bytes:bytes.length,sha256:hash(bytes),schema_version:data.schema_version,application_version:data.application_version,generated_at:data.generated_at,
      session_id:data.session?.session_id??null,graph_selection:data.graph_selection,demo_selection:data.demo_selection,measurement_source_labels:data.measurement_source_labels,
      collections:{measurement_points:data.series?.length??0,comparison_points:data.comparison_series?.length??0,analysis_points:data.analysis?.series?.length??0,analysis_presentations:data.analysis?.series_definitions?.length??0},
      overview_axes:data.overview_axes,analysis_graphs:data.analysis?.graphs};
    if(level==='full')result.published_payload=data;
    return result;
  }catch(error){return {status:'error',filename:'fermentation-overview.json',error_message:String(error.message||error)};}
}
function lockPublication(target){
  // Only the reproducible JSON/gzip pair is serialized here, never database writes.
  const filename=target+'.publish-lock',token=crypto.randomBytes(12).toString('hex'),started=Date.now();
  while(true){
    try{
      const fd=fs.openSync(filename,'wx',0o600);
      try{fs.writeFileSync(fd,JSON.stringify({pid:process.pid,token}));}catch(error){fs.unlinkSync(filename);throw error;}finally{fs.closeSync(fd);}
      return ()=>{try{if(JSON.parse(fs.readFileSync(filename,'utf8')).token===token)fs.unlinkSync(filename);}catch(error){if(error.code!=='ENOENT')throw error;}};
    }catch(error){
      if(error.code!=='EEXIST')throw error;
      try{
        const owner=JSON.parse(fs.readFileSync(filename,'utf8'));
        try{process.kill(owner.pid,0);}catch(error){if(error.code==='ESRCH'){fs.unlinkSync(filename);continue;}}
      }catch(error){
        if(error.code==='ENOENT')continue;
        if(error instanceof SyntaxError){try{if(Date.now()-fs.statSync(filename).mtimeMs>60000){fs.unlinkSync(filename);continue;}}catch(error){if(error.code==='ENOENT')continue;}}
      }
      if(Date.now()-started>30000)throw Error('Tidsavbrudd ved publisering av JSON/gzip');
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,25);
    }
  }
}
function publishPayload(job,options={}){
  const publicRoot=options.publicRoot||'/data/gjaeringsassistent/ha-public',stageRoot=options.stageRoot||'/data/gjaeringsassistent/runtime/staged';
  const stage=inside(job.stage_path,stageRoot),target=inside(job.target_path,publicRoot);
  if(path.extname(target)!=='.json')throw Error('Publisering krever JSON-mål');
  const data=JSON.parse(fs.readFileSync(stage,'utf8'));
  if(job.diagnostics_level){
    if(!['summary','full'].includes(job.diagnostics_level))throw Error('Ugyldig diagnostikknivå');
    data.diagnostics_level=job.diagnostics_level;
    data.frontend_diagnostics=diagnosticSnapshot(publicRoot,job.diagnostics_level);
  }
  const bytes=Buffer.from(JSON.stringify(data)+'\n'),gzip=zlib.gzipSync(bytes,{level:6});
  if(!zlib.gunzipSync(gzip).equals(bytes))throw Error('Komprimert publisering feilet verifisering');
  fs.mkdirSync(path.dirname(target),{recursive:true});
  const tag=crypto.randomBytes(8).toString('hex'),plainTemp=target+'.'+tag+'.pending',gzipTemp=target+'.gz.'+tag+'.pending';
  const unlock=lockPublication(target);
  try{
    if(data.generated_at&&fs.existsSync(target)){
      let current;try{current=JSON.parse(fs.readFileSync(target,'utf8'));}catch(error){if(!(error instanceof SyntaxError))throw error;}
      if(Date.parse(current?.generated_at)>Date.parse(data.generated_at)){
        fs.rmSync(stage,{force:true});return {status:'ok',target_path:target,skipped_older_snapshot:true};
      }
    }
    fs.writeFileSync(plainTemp,bytes,{mode:0o644});fs.writeFileSync(gzipTemp,gzip,{mode:0o644});
    // Remove the previous compressed representation before changing JSON.
    fs.rmSync(target+'.gz',{force:true});fs.renameSync(plainTemp,target);fs.renameSync(gzipTemp,target+'.gz');
    if(hash(fs.readFileSync(target))!==hash(bytes)||!zlib.gunzipSync(fs.readFileSync(target+'.gz')).equals(bytes))throw Error('Publisert fil feilet tilbake-lesing');
    fs.rmSync(stage,{force:true});
    return {status:'ok',target_path:target,bytes:bytes.length,gzip_bytes:gzip.length,sha256:hash(bytes),diagnostics_level:job.diagnostics_level??null};
  }finally{try{fs.rmSync(plainTemp,{force:true});fs.rmSync(gzipTemp,{force:true});}finally{unlock();}}
}
if(require.main===module){try{console.log(JSON.stringify(publishPayload(JSON.parse(process.argv[2]))));}catch(error){console.log(JSON.stringify({status:'error',error_message:String(error.message||error)}));process.exitCode=1;}}
module.exports={publishPayload,diagnosticSnapshot};
