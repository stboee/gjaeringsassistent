'use strict';
// A protocol client for isolated integration tests; never accepts remote hosts.
const fs=require('node:fs'),mysql=require('mysql2/promise');
(async()=>{const input=JSON.parse(fs.readFileSync(0,'utf8'));if(!Number.isInteger(input.port)||input.port<1024)throw Error('Use an isolated test port');const db=await mysql.createConnection({host:'127.0.0.1',port:input.port,user:'root',multipleStatements:true,dateStrings:true});try{await db.query(input.sql);}finally{await db.end();}})().catch(e=>{console.error(e.code,e.sqlMessage||e.message);process.exitCode=1;});
