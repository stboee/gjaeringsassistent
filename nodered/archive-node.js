'use strict';
// Each job owns one connection and transaction in a worker thread. No runtime
// queues, domain caches or credentials in flow messages.
module.exports=function(RED){
 const {Worker}=require('node:worker_threads'),path=require('node:path');
 function ArchiveNode(config){
  RED.nodes.createNode(this,config);const node=this,database=RED.nodes.getNode(config.mydb),workers=new Set();
  node.on('input',(msg,send,done)=>{
   if(!database?.credentials){done(Error('Arkivnoden mangler MariaDB-konfigurasjon'));return;}
   const job=msg.ga_archive_job;if(!job){done(Error('Arkivjobb mangler'));return;}
   const worker=new Worker(path.join(__dirname,'archive_worker.js'),{workerData:{job,config:{userDir:RED.settings.userDir||'/data',database:{host:database.host,port:database.port,database:database.dbname,user:database.credentials.user,password:database.credentials.password,charset:database.charset||'UTF8MB4_UNICODE_CI'}}}});
   workers.add(worker);node.status({fill:'blue',shape:'dot',text:`${workers.size} arkivjobb(er)`});let finished=false;
   const finish=e=>{if(finished)return;finished=true;workers.delete(worker);node.status(workers.size?{fill:'blue',shape:'dot',text:`${workers.size} arkivjobb(er)`}:{});done(e);};
   worker.on('message',r=>{if(r.error){msg.ga_archive_error=r.error;send([null,msg]);finish();}else{msg.ga_sqlite_result=r.result;send([msg,null]);finish();}});
   worker.on('error',e=>{msg.ga_archive_error=e.message;send([null,msg]);finish();});worker.on('exit',code=>{if(!finished)finish(Error('Arkivarbeider stoppet: '+code));});
  });
  node.on('close',async()=>{await Promise.all([...workers].map(w=>w.terminate()));});
 }
 RED.nodes.registerType('ga-archive-transfer',ArchiveNode);
};
