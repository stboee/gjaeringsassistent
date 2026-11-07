'use strict';
// REQ-MOTOR-040 REQ-COM-080 REQ-HA-067: file-backed verification and append-only retry.
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),crypto=require('node:crypto');
const {spawnSync}=require('node:child_process');
const {DatabaseSync}=require('node:sqlite');
const root=path.resolve(__dirname,'..'),flow=JSON.parse(fs.readFileSync(path.join(root,'nodered/flows.template.json'))),by=Object.fromEntries(flow.map(n=>[n.id,n]));
const call=(id,msg)=>new Function('msg','node','Buffer',by[id].func)(msg,{error:e=>{throw Error(e)},warn:()=>{},status:()=>{}},Buffer);
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'ga-archive-'));
try{
 const archivePath=path.join(tmp,'archive-gjaering.sqlite'),templatePath=path.join(tmp,'archive-template.sqlite');
 const archive=new DatabaseSync(archivePath);archive.exec('CREATE TABLE facts(value TEXT)');archive.prepare('INSERT INTO facts VALUES(?)').run('ø'.repeat(10*1024*1024));archive.close();
 const template=new DatabaseSync(templatePath);template.exec("CREATE TABLE template(name TEXT);INSERT INTO template VALUES('Testtemplate')");template.close();
 const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
 const html='<!doctype html><p>'+ 'x'.repeat(3*1024*1024)+'</p>';
 assert.ok(fs.statSync(archivePath).size>19090552);
 const job={session_id:'test',attempt_id:'attempt-1',stage_report_path:path.join(tmp,'report.html.pending'),archive_path:archivePath,template_path:templatePath,report_path:path.join(tmp,'report.html'),archive_bytes:fs.statSync(archivePath).size,archive_sha256:hash(archivePath),template_bytes:fs.statSync(templatePath).size,template_sha256:hash(templatePath),report_bytes:Buffer.byteLength(html)};
 fs.writeFileSync(job.stage_report_path,html);
 const run=j=>spawnSync(process.execPath,[path.join(root,'tools/archive_export.js'),Buffer.from(JSON.stringify(j)).toString('base64')],{encoding:'utf8'});
 let result=run(job);assert.equal(result.status,0,result.stderr);assert.ok(result.stdout.length<1536,'only compact file metadata leaves the helper');
 const evidence=JSON.parse(result.stdout);assert.equal(evidence.status,'verified');assert.equal(evidence.archive_bytes,job.archive_bytes);assert.equal(evidence.archive_sha256,job.archive_sha256);assert.equal(evidence.template_sha256,job.template_sha256);assert.equal(fs.readFileSync(job.report_path,'utf8'),html);assert.ok(!fs.existsSync(job.stage_report_path));
 let msg={ga_export_session_id:'test',ga_archive_attempt_id:'attempt-1',ga_archive_attempt_no:1,ga_archive_bytes:job.archive_bytes,ga_template_bytes:job.template_bytes,ga_report_bytes:job.report_bytes,payload:result.stdout};
 msg=call('p24_archive_file_result',msg);const sql=call('p21_session_export_verify_query',msg);
 assert.equal((sql.topic.match(/\?/g)||[]).length,sql.payload.length);assert.doesNotMatch(sql.topic,/SHA2\(/);assert.ok(Buffer.byteLength(JSON.stringify(sql.payload))<2048);assert.ok(sql.payload.includes(evidence.archive_sha256));assert.ok(sql.payload.includes(evidence.template_sha256));assert.equal(sql.payload[0],'verified');
 // A read-back must not accept a short file, a missing report, or an
 // invalid helper result. Every failure has a compact DB-registerable cause.
 const short={...job,attempt_id:'attempt-2',archive_path:path.join(tmp,'short.sqlite'),report_path:path.join(tmp,'short.html')};fs.writeFileSync(short.archive_path,'short');fs.writeFileSync(short.stage_report_path,html);
 result=run(short);assert.equal(result.status,1);assert.equal(JSON.parse(result.stdout).status,'failed');assert.match(JSON.parse(result.stdout).error_message,/SQLite-par har endret/);assert.ok(!fs.existsSync(short.report_path));
 const tampered={...job,attempt_id:'attempt-tampered',template_sha256:'0'.repeat(64),report_path:path.join(tmp,'tampered.html')};result=run(tampered);assert.equal(result.status,1);assert.match(JSON.parse(result.stdout).error_message,/SQLite-par har endret/);
 const missing={...job,attempt_id:'attempt-3',report_path:path.join(tmp,'missing.html'),stage_report_path:path.join(tmp,'does-not-exist')};
 result=run(missing);assert.equal(result.status,1);assert.match(JSON.parse(result.stdout).error_message,/ENOENT/);
 msg=call('p24_archive_file_result',{...msg,ga_archive_attempt_id:'attempt-3',payload:result.stdout});const failure=call('p21_session_export_verify_query',msg);assert.equal(failure.payload[0],'failed');assert.ok(failure.payload.some(x=>typeof x==='string'&&x.includes('ENOENT')));assert.ok(Buffer.byteLength(JSON.stringify(failure.payload))<2048);
 const malformed=call('p24_archive_file_result',{...msg,payload:'not-json'});assert.equal(malformed.ga_archive_result.status,'failed');
 const mismatch=call('p24_archive_file_result',{...msg,payload:JSON.stringify({...evidence,archive_bytes:1})});assert.equal(mismatch.ga_archive_result.status,'failed');
 const attempt=call('p24_archive_attempt_query',{});assert.match(attempt.topic,/CALL ga_request_archive_tx/);assert.doesNotMatch(attempt.topic,/UPDATE session_|DELETE FROM session_|session_lifecycle_events/);assert.equal(by.h_retry_archive_v1.wires[0][0],'p24_archive_attempt_query');
 console.log('RESULT: PASS – >19 MB SQLite pair verification, both hashes, compact SQL, missing/tampered/short files and retry contract');
}finally{fs.rmSync(tmp,{recursive:true,force:true});}
