'use strict';
// Explicit deletion of an entire retained aggregate. Never delete a live session.
const core=require('./sqlite_archive.js'),{randomUUID}=require('node:crypto');
const q=s=>'`'+String(s).replace(/`/g,'``')+'`';
const identity=(t,r)=>JSON.stringify(t.pk.map(c=>r[c]));
async function collect(db,meta,seed,scope){
 const rows={};const add=(name,list)=>{const map=rows[name]??=new Map();let n=0;for(const r of list){if(scope==='session'&&r.session_id&&r.session_id!==seed.sessions[0].session_id)throw Error('En annen sesjon refererer til historikken');const key=identity(meta[name],r);if(!map.has(key)){map.set(key,r);n++;}}return n;};
 for(const [name,list]of Object.entries(seed))add(name,list);
 const fetched=new Set();let changed=true;
 while(changed){changed=false;for(const [name,t]of Object.entries(meta))for(const fk of t.fks){
  if(!rows[fk.table]?.size||name==='archive_transfer_events'||name==='template_editor_state')continue;
  if(scope==='template'&&!core.contract.template_tables.includes(name)&&name!=='template_origins')continue;
  const parents=[...rows[fk.table].values()].filter(r=>{const k=name+'|'+fk.name+'|'+identity(meta[fk.table],r);if(fetched.has(k))return false;fetched.add(k);return true;});
  for(let i=0;i<parents.length;i+=150){const list=parents.slice(i,i+150);const [child]=await db.query(`SELECT ${t.columns.map(c=>q(c.name)).join(',')} FROM ${q(name)} WHERE ${list.map(()=>`(${fk.columns.map(c=>q(c)+'=?').join(' AND ')})`).join(' OR ')}`,list.flatMap(r=>fk.references.map(c=>r[c])));if(add(name,child))changed=true;}
 }}return rows;
}
async function remove(db,meta,rows){
 // Nullable internal backlinks can form cycles. Clear only backlinks whose
 // parent is also inside this deletion, leaving retained aggregates untouched.
 const reaches=(from,to,seen=new Set())=>{if(from===to)return true;if(seen.has(from))return false;seen.add(from);return meta[from].fks.some(f=>rows[f.table]?.size&&reaches(f.table,to,seen));};
 for(const [name,map]of Object.entries(rows))for(const row of map.values())for(const fk of meta[name].fks){
  const nullable=fk.columns.find(c=>meta[name].columns.find(x=>x.name===c).nullable);
  if(!reaches(fk.table,name)||!nullable||fk.columns.some(c=>row[c]===null)||!rows[fk.table]?.size)continue;
  if(![...rows[fk.table].values()].some(p=>fk.references.every((c,i)=>String(p[c])===String(row[fk.columns[i]]))))continue;
  await db.query(`UPDATE ${q(name)} SET ${q(nullable)}=NULL WHERE ${meta[name].pk.map(c=>q(c)+'=?').join(' AND ')}`,meta[name].pk.map(c=>row[c]));row[nullable]=null;
 }
 const pending=new Set(Object.keys(rows).filter(t=>rows[t].size));let deleted=0;
 while(pending.size){let progress=false;for(const name of [...pending]){
  const blocked=[...pending].some(child=>meta[child].fks.some(f=>f.table===name&&[...rows[child].values()].some(r=>f.columns.every(c=>r[c]!==null)&&[...rows[name].values()].some(p=>f.references.every((c,i)=>String(p[c])===String(r[f.columns[i]]))))));if(blocked)continue;
  const list=[...rows[name].values()],t=meta[name];for(let i=0;i<list.length;i+=150){const part=list.slice(i,i+150);const [result]=await db.query(`DELETE FROM ${q(name)} WHERE ${part.map(()=>`(${t.pk.map(c=>q(c)+'=?').join(' AND ')})`).join(' OR ')}`,part.flatMap(r=>t.pk.map(c=>r[c])));deleted+=result.affectedRows;}pending.delete(name);progress=true;
 }if(!progress)throw Error('Slettingen har obligatoriske sirkulære referanser: '+[...pending].join(', '));}return deleted;
}
async function removeTemplate(db,meta,id){
 const [origin]=await db.query("SELECT * FROM template_origins WHERE template_id=? AND origin_kind='imported'",[id]);if(!origin.length)throw Error('Bare importerte originaltemplates kan slettes her');
 const [refs]=await db.query('SELECT session_references,derived_references FROM v_template_library WHERE template_id=? LIMIT 1',[id]);if(!refs.length||Number(refs[0].session_references)||Number(refs[0].derived_references))throw Error('Templaten brukes av en sesjon eller en egen template. Fjern referansene først.');
 const [templates]=await db.query('SELECT * FROM templates WHERE template_id=?',[id]);const [versions]=await db.query('SELECT * FROM template_versions WHERE template_id=?',[id]);
 await db.query('UPDATE template_editor_state SET selected_version_id=NULL WHERE selected_version_id IN (SELECT version_id FROM template_versions WHERE template_id=?)',[id]);
 return remove(db,meta,await collect(db,meta,{templates,template_versions:versions,template_origins:origin},'template'));
}
async function deleteArchive(db,job){
 const [receipt]=await db.query("SELECT session_id,template_id FROM archive_transfer_events WHERE operation_id=? AND action=? AND status='done' ORDER BY event_seq DESC LIMIT 1",[job.operation_id,job.action]);if(receipt.length)return {...receipt[0],idempotent:true};
 const meta=await core.metadata(db,true);await db.beginTransaction();try{
  let count=0,templateId=job.template_id||null;
  if(job.action==='delete_session'){
   const [session]=await db.query('SELECT * FROM v_all_session WHERE session_id=?',[job.session_id]);const [active]=await db.query('SELECT 1 FROM v_active_session WHERE session_id=?',[job.session_id]);const [imports]=await db.query('SELECT * FROM archive_imports WHERE session_id=?',[job.session_id]);
   if(!session.length||active.length||(session[0].lifecycle!=='completed'&&!imports.length))throw Error('Aktiv eller ukjent gjæring kan ikke slettes');
   if(job.delete_template){if(!imports.length)throw Error('Sesjonen har ingen importert template');templateId=imports[0].template_id;}
   const [selection]=await db.query('SELECT * FROM graph_display_selection_events ORDER BY selection_seq DESC LIMIT 1');
   if(selection[0]?.reference_session_id===job.session_id)await db.query("INSERT INTO graph_display_selection_events(source_kind,interval_seconds,window_hours,operation_id,selected_at) VALUES('none',?,?,?,UTC_TIMESTAMP(3))",[selection[0].interval_seconds,selection[0].window_hours,job.operation_id+'-selection']);
   const [root]=await db.query('SELECT * FROM sessions WHERE session_id=?',[job.session_id]);const seed={sessions:root};
   for(const [name,t]of Object.entries(meta))if(name!=='sessions'&&name!=='archive_transfer_events'&&t.columns.some(c=>c.name==='session_id')){const [list]=await db.query(`SELECT ${t.columns.map(c=>q(c.name)).join(',')} FROM ${q(name)} WHERE session_id=?`,[job.session_id]);if(list.length)seed[name]=list;}
   count+=await remove(db,meta,await collect(db,meta,seed,'session'));
   if(job.delete_template)count+=await removeTemplate(db,meta,templateId);
  }else if(job.action==='delete_template')count+=await removeTemplate(db,meta,templateId);else throw Error('Ukjent slettehandling');
  // Receipt belongs to operational bookkeeping and survives aggregate removal.
  await db.query("INSERT INTO archive_transfer_events(operation_id,action,status,message,session_id,template_id,occurred_at) VALUES(?,?,'done',?,?,?,UTC_TIMESTAMP(3))",[job.operation_id,job.action,`Slettet fra MariaDB · ${count} rader · eksportfiler er beholdt`,job.session_id||null,templateId]);
  await db.commit();return {session_id:job.session_id||null,template_id:templateId,deleted_rows:count};
 }catch(e){await db.rollback();throw e;}
}
module.exports={deleteArchive};
