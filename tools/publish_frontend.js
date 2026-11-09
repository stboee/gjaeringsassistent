#!/usr/bin/env node
'use strict';
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const VERSION='2026.11.09-1';
const SOURCE_DIR='/data/gjaeringsassistent/frontend-source';
const PUBLIC_DIR='/data/gjaeringsassistent/ha-public';
const STATUS_FILE='/data/gjaeringsassistent/runtime/frontend-publication-status.json';
const MANIFEST_PUBLIC='frontend-manifest.json';
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const decodeMount=s=>s.replace(/\\040/g,' ').replace(/\\011/g,'\t').replace(/\\012/g,'\n').replace(/\\134/g,'\\');
function exactMountPoint(target){
  let text=''; try{text=fs.readFileSync('/proc/self/mountinfo','utf8');}catch(error){return {ok:false,error:`Kan ikke lese /proc/self/mountinfo: ${error.message}`};}
  const wanted=path.resolve(target);
  for(const line of text.split('\n')){if(!line)continue;const fields=line.split(' ');if(fields.length>5&&path.resolve(decodeMount(fields[4]))===wanted)return {ok:true,line};}
  return {ok:false,error:`${wanted} er ikke et eget mountpoint i Node-RED-containeren`};
}
function atomicWrite(filename,bytes,mode=0o644){
  const tmp=`${filename}.tmp-${process.pid}-${Date.now()}`;
  fs.writeFileSync(tmp,bytes,{mode});
  const actual=fs.readFileSync(tmp);
  if(hash(actual)!==hash(bytes)){try{fs.unlinkSync(tmp);}catch{};throw new Error(`SHA read-back feilet for ${path.basename(filename)}`);}
  fs.renameSync(tmp,filename);
  return {sha256:hash(actual),bytes:actual.length};
}
function verifyPublished(filename,expectedSha,expectedBytes){
  if(!fs.existsSync(filename))throw new Error(`Publisert fil mangler etter rename: ${path.basename(filename)}`);
  const bytes=fs.readFileSync(filename), actualSha=hash(bytes);
  if(actualSha!==expectedSha||bytes.length!==expectedBytes)throw new Error(`Sluttkontroll feilet for ${path.basename(filename)}`);
  return {sha256:actualSha,bytes:bytes.length};
}
function persistStatus(status){try{fs.mkdirSync(path.dirname(STATUS_FILE),{recursive:true});atomicWrite(STATUS_FILE,Buffer.from(JSON.stringify(status,null,2)+'\n'),0o640);}catch(error){process.stderr.write(`Kunne ikke lagre frontendstatus: ${error.message}\n`);}}
function fail(message,details={}){const status={schema_version:'1.0',version:VERSION,status:'error',checked_at:new Date().toISOString(),error:message,...details};persistStatus(status);process.stderr.write(JSON.stringify(status)+'\n');process.exitCode=1;return status;}
function main(){
  if(!fs.existsSync(PUBLIC_DIR))return fail('HA-public-mount mangler; Node-RED oppretter ikke mountpointet',{public_dir:PUBLIC_DIR});
  let stat;try{stat=fs.statSync(PUBLIC_DIR);}catch(error){return fail(error.message);}
  if(!stat.isDirectory())return fail('HA-public-stien er ikke en katalog',{public_dir:PUBLIC_DIR});
  const mount=exactMountPoint(PUBLIC_DIR);if(!mount.ok)return fail(mount.error,{public_dir:PUBLIC_DIR});
  try{fs.accessSync(PUBLIC_DIR,fs.constants.R_OK|fs.constants.W_OK);}catch(error){return fail('HA-public-mount er ikke lesbar/skrivbar',{error:error.message});}
  const sources={
    card:{source:'gjaeringsassistent-card.js',public_name:'gjaeringsassistent-card.js'},
    dashboard:{source:'gjaeringsassistent-dashboard.yaml',public_name:'gjaeringsassistent-dashboard.yaml'},
    loader:{source:'gjaeringsassistent-card-loader.js',public_name:'gjaeringsassistent-card-loader.js'}
  };
  const files={};
  try{
    for(const [key,item] of Object.entries(sources)){
      const src=path.join(SOURCE_DIR,item.source); if(!fs.existsSync(src))throw new Error(`Mangler frontendkilde: ${src}`);
      const bytes=fs.readFileSync(src), published=atomicWrite(path.join(PUBLIC_DIR,item.public_name),bytes);
      files[key]={source:item.source,public_name:item.public_name,source_sha256:hash(bytes),sha256:published.sha256,bytes:published.bytes};
    }
    for(const item of Object.values(files))verifyPublished(path.join(PUBLIC_DIR,item.public_name),item.sha256,item.bytes);
    const manifest={schema_version:'2.0',version:VERSION,published_at:new Date().toISOString(),files};
    const manifestBytes=Buffer.from(JSON.stringify(manifest,null,2)+'\n'), manifestPath=path.join(PUBLIC_DIR,MANIFEST_PUBLIC);
    const manifestResult=atomicWrite(manifestPath,manifestBytes);verifyPublished(manifestPath,manifestResult.sha256,manifestResult.bytes);
    const status={schema_version:'1.0',version:VERSION,status:'ok',checked_at:new Date().toISOString(),public_dir:PUBLIC_DIR,mount_verified:true,manifest:MANIFEST_PUBLIC,manifest_sha256:manifestResult.sha256,files};
    persistStatus(status);process.stdout.write(JSON.stringify(status)+'\n');return status;
  }catch(error){return fail(error.message,{public_dir:PUBLIC_DIR,mount_verified:true});}
}
if(require.main===module)main();
module.exports={main,exactMountPoint,atomicWrite,verifyPublished};
