'use strict';
// Contract boundary tests use shipping argument expressions and the real publisher.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),zlib=require('node:zlib'),child=require('node:child_process');
const root=path.resolve(__dirname,'..'),catalog=require('../contracts/interface-catalog.json'),schema=require('../contracts/publication-job.schema.json');
const flow=JSON.parse(fs.readFileSync(path.join(root,'nodered/flows.template.json'))),by=Object.fromEntries(flow.map(n=>[n.id,n]));
const {publishPayload}=require('../tools/publish_payload.js');
function validate(job){
  assert.ok(job&&typeof job==='object'&&!Array.isArray(job));
  for(const key of schema.required)assert.ok(Object.hasOwn(job,key),'Missing '+key);
  for(const [key,value] of Object.entries(job)){
    const field=schema.properties[key];assert.ok(field,'Unknown '+key);assert.equal(typeof value,field.type);
    if(field.minLength)assert.ok(value.length>=field.minLength);
    if(field.enum)assert.ok(field.enum.includes(value));
  }
}
const pub=catalog.interfaces.find(i=>i.interface_id==='IF-NR-PUBLICATION'),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'ga-contract-'));
const stageRoot=path.join(tmp,'staged'),publicRoot=path.join(tmp,'public');fs.mkdirSync(stageRoot);fs.mkdirSync(publicRoot);
try{
  for(const pipe of pub.pipelines){
    const expressions=[...by[pipe.producer].func.matchAll(/msg\.ga_publication_args=JSON\.stringify\((\{.*?\})\);/g)];assert.ok(expressions.length);
    for(let i=0;i<expressions.length;i++){
      const filename=path.join(stageRoot,pipe.producer+i+"-ø-'-$-`.json"),target=path.join(publicRoot,pipe.producer+i+'.json');
      const msg={filename,ga_publication_target:target,ga_diagnostics_level:'summary'};
      const job=new Function('msg','return '+expressions[i][1])(msg);validate(job);
      const quoted=new Function('msg',by[pipe.arguments].func)({ga_publication_args:JSON.stringify(job)}).payload;
      const roundtrip=child.execFileSync('/bin/sh',['-c',"node -e 'process.stdout.write(process.argv[1])' "+quoted],{encoding:'utf8'});assert.deepEqual(JSON.parse(roundtrip),job);
      fs.writeFileSync(filename,JSON.stringify({contract_fixture:true,unicode:'øæå',generated_at:'2026-11-14T00:00:00Z'}));
      const result=publishPayload(job,{stageRoot,publicRoot});assert.equal(result.status,'ok');
      const bytes=fs.readFileSync(target);assert.equal(JSON.parse(bytes).unicode,'øæå');assert.deepEqual(zlib.gunzipSync(fs.readFileSync(target+'.gz')),bytes);
      for(const bad of [{source_path:filename,target_path:target},{stage_path:null,target_path:target},{...job,unexpected:1},{...job,diagnostics_level:'guess'}])assert.throws(()=>validate(bad));
      assert.throws(()=>publishPayload({source_path:filename,target_path:target},{stageRoot,publicRoot}));
    }
  }
  console.log('RESULT: PASS – all shipping publication producers: schema, shell roundtrip, actual JSON/gzip readback and negative keys/types');
}finally{fs.rmSync(tmp,{recursive:true,force:true});}
