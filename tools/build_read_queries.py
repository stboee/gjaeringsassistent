#!/usr/bin/env python3
"""Compile the authoritative SQL read models into one session-bounded DB operation.

Permanent source data is copied by ordinary SELECT (consistent, non-locking),
then staged via JSON_TABLE into connection-local typed temporary tables.
Derived views are evaluated once in dependency order, retaining their SQL rules.
This is build-time SQL compilation, not a second runtime/domain implementation.
"""
from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[1]
physical=json.loads((ROOT/'contracts/physical-schema.json').read_text())
def statement_end(sql,start):
 quote=None;i=start
 while i<len(sql):
  c=sql[i]
  if quote:
   if c=='\\':i+=1
   elif c==quote:
    if i+1<len(sql) and sql[i+1]==quote:i+=1
    else:quote=None
  elif c in "'\"`":quote=c
  elif sql.startswith('--',i) and (i+2==len(sql) or sql[i+2].isspace()):
   j=sql.find('\n',i);i=len(sql) if j<0 else j
  elif sql.startswith('/*',i):
   j=sql.find('*/',i+2);i=len(sql) if j<0 else j+1
  elif c==';':return i
  i+=1
 raise ValueError('Unterminated SQL statement')
view_sql=(ROOT/'sql/20-views.sql').read_text()
views={m[1]:view_sql[m.end():statement_end(view_sql,m.end())].strip() for m in re.finditer(r'CREATE OR REPLACE VIEW (\w+) AS',view_sql)}
tables=set(physical['tables'])
columns={t:[] for t in tables}
for c in physical['columns']:
 if c['TABLE_NAME'] in columns:columns[c['TABLE_NAME']].append(c)
keys={t:[] for t in tables}
for k in physical['keys']:
 if k['REFERENCED_TABLE_NAME']:
  entry=next((f for f in keys[k['TABLE_NAME']] if f['name']==k['CONSTRAINT_NAME']),None)
  if entry is None:entry={'name':k['CONSTRAINT_NAME'],'parent':k['REFERENCED_TABLE_NAME'],'cols':[],'refs':[]};keys[k['TABLE_NAME']].append(entry)
  entry['cols'].append(k['COLUMN_NAME']);entry['refs'].append(k['REFERENCED_COLUMN_NAME'])
execution_schema=json.loads((ROOT/'contracts/read-execution-schema.json').read_text())['views']
readcols={v:[c['COLUMN_NAME'] for c in cc] for v,cc in execution_schema.items()}
overview=(ROOT/'tools/overview_reads.sql').read_text();report=(ROOT/'tools/report_reads.sql').read_text()
# Library selectors must show all eligible historical sessions, not just the read scope.
external={'v_dashboard_reference_options','v_dashboard_demo_options','v_demo_profile_selection','v_dashboard_graph_view_options'}
# SQL literals remain unchanged; identifiers alone participate in compilation.
def parts(sql):return re.split(r"('(?:''|\\.|[^'])*')",sql)
def identifiers(sql):return set(re.findall(r'\b[a-z][a-z0-9_]*\b',''.join(p for i,p in enumerate(parts(sql)) if i%2==0)))
roots=(identifiers(overview)|identifiers(report))&set(views)-external
order=[];seen=set();physical_used=set()
def visit(v):
 if v in seen:return
 seen.add(v)
 deps=identifiers(views[v])
 physical_used.update(deps&tables)
 for d in sorted(deps&set(views)-external):visit(d)
 order.append(v)
for v in sorted(roots):visit(v)
physical_used.update((identifiers(overview)|identifiers(report))&tables)
# No persistent table is shadowed. Each staged source has an explicit separate name.
name={t:'ga_rb_t_'+t for t in physical_used}|{v:'ga_rb_'+v for v in order}
def rewrite(sql):
 p=parts(sql)
 for i in range(0,len(p),2):p[i]=re.sub(r'\b[a-z][a-z0-9_]*\b',lambda m:name.get(m[0],m[0]),p[i])
 return ''.join(p)
owned=set(json.loads((ROOT/'tools/archive_contract.json').read_text())['session_tables'])
# Identify a child's owning session through the declared FK path, not name heuristics.
def owner_path(table,chain=()):
 if table in chain:return None
 if any(c['COLUMN_NAME']=='session_id' for c in columns[table]):return []
 for fk in keys[table]:
  if fk['parent'] not in owned:continue
  if any(next(c for c in columns[table] if c['COLUMN_NAME']==col)['IS_NULLABLE']=='YES' for col in fk['cols']):continue
  path=owner_path(fk['parent'],chain+(table,))
  if path is not None:return [fk]+path
 return None
base_order=[];pending=set(physical_used)
while pending:
 progress=False
 for t in sorted(pending):
  path=owner_path(t) if t in owned else None
  parent=path[0]['parent'] if path else None
  if parent in pending:continue
  base_order.append(t);pending.remove(t);progress=True;break
 if not progress:raise ValueError('Cyclic owner path: '+str(pending))
all_names=['ga_rb_scope']+[name[t] for t in base_order]+[name[v] for v in order]
drop='DROP TEMPORARY TABLE IF EXISTS '+','.join('`'+n+'`' for n in reversed(all_names))+';'
# Publication invalidation uses indexed aggregate facts, never the graph chain.
# Immutable children are covered by their dated owning event/revision.
signature=[]
large_times={'measurements_5m':['updated_at','bucket_at'],'analysis_series_values':['created_at','sample_at'],'measurement_statistics_hourly':['created_at','start_at'],'analysis_validation_events':['created_at','sample_at']}
for t in base_order:
 cc={c['COLUMN_NAME']:c for c in columns[t]}
 time=next((k for k in ('updated_at','created_at','occurred_at','evaluated_at') if k in cc),None)
 if t=='technical_events':signature.append("(SELECT COALESCE(MAX(event_seq),0) FROM technical_events)")
 elif t in large_times:
  for field in large_times[t]:
   for scope in ('v_session','v_reference'):
    signature.append("(SELECT COALESCE(MAX(`"+field+"`),'') FROM `"+t+"` WHERE session_id="+scope+")")
 elif t in owned and 'session_id' in cc and time:
  signature.append("(SELECT CONCAT(COUNT(*),':',COALESCE(MAX(`"+time+"`),'')) FROM `"+t+"` WHERE session_id=v_session OR session_id=v_reference)")
 elif t.endswith('_selection_events') or t in ('archive_visibility_events','archive_imports','archive_transfer_events'):
  seq=next((k for k in cc if k.endswith('_seq')),None)
  if seq:signature.append('(SELECT COALESCE(MAX(`'+seq+'`),0) FROM `'+t+'`)')
  elif time:signature.append("(SELECT CONCAT(COUNT(*),':',COALESCE(MAX(`"+time+"`),'')) FROM `"+t+"`)")
signature+=['(SELECT COUNT(*) FROM sessions)','(SELECT COALESCE(MAX(selection_seq),0) FROM graph_display_selection_events)','(SELECT COALESCE(MAX(selection_seq),0) FROM demo_profile_selection_events)',"COALESCE(v_session,'')"]
lines=['-- Generated by tools/build_read_queries.py from normalized sources and view SQL.','DELIMITER //',
"CREATE PROCEDURE ga_overview_source_key(OUT p_key CHAR(64)) BEGIN DECLARE v_session VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin; DECLARE v_reference VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin; SELECT session_id INTO v_session FROM v_active_session; SELECT reference_session_id INTO v_reference FROM v_graph_display_selection WHERE source_kind='session'; SELECT SHA2(CONCAT_WS('|', "+','.join(signature)+'),256) INTO p_key; END//',
'CREATE PROCEDURE ga_drop_read_basis() BEGIN '+drop+' END//',
'CREATE PROCEDURE ga_init_read_basis() BEGIN', ' CALL ga_drop_read_basis();',
' CREATE TEMPORARY TABLE ga_rb_scope(session_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY) ENGINE=InnoDB;']
for t in base_order:
 declarations=[]
 for c in columns[t]:
  declared='`'+c['COLUMN_NAME']+'` '+re.sub(r'/\*.*?\*/','',c['COLUMN_TYPE'])
  if c['CHARACTER_SET_NAME']:declared+=' CHARACTER SET '+c['CHARACTER_SET_NAME']+' COLLATE '+c['COLLATION_NAME']
  declarations.append(declared+(' NULL' if c['IS_NULLABLE']=='YES' else ' NOT NULL'))
 indices={}
 for k in physical['indices']:
  if k['TABLE_NAME']==t:indices.setdefault(k['INDEX_NAME'],[]).append(k['COLUMN_NAME'])
 for i,(key,cc) in enumerate(sorted((k,v) for k,v in indices.items() if not k.endswith('__read_change'))):
  if key=='PRIMARY':declarations.append('PRIMARY KEY('+','.join('`'+c+'`' for c in cc)+')')
  else:declarations.append('KEY ga_i'+str(i)+'('+','.join('`'+c+'`' for c in cc)+')')
 lines.append(' CREATE TEMPORARY TABLE `'+name[t]+'`('+','.join(declarations)+') ENGINE=Aria TRANSACTIONAL=0;')
for v in order:
 declarations=[]
 for c in execution_schema[v]:
  declared='`'+c['COLUMN_NAME']+'` '+re.sub(r'/\*.*?\*/','',c['COLUMN_TYPE'])
  if c['CHARACTER_SET_NAME']:declared+=' CHARACTER SET '+c['CHARACTER_SET_NAME']+' COLLATE '+c['COLLATION_NAME']
  declarations.append(declared+' NULL')
 lines.append(' CREATE TEMPORARY TABLE `'+name[v]+'`('+','.join(declarations)+') ENGINE=Aria TRANSACTIONAL=0;')
 cols=readcols.get(v,[])
 candidates=[['session_id','graph_id','series_id','sample_at'],['session_id','metric_id'],['evaluation_id','criterion_id'],['visit_id'],['criterion_revision_id','parameter_id'],['session_id','phase_id','criterion_id'],['session_id','process_id','criterion_id']]
 indices=[]
 for candidate in candidates:
  actual=[c for c in candidate if c in cols]
  if not actual or actual in indices:continue
  indices.append(actual);lines.append(' ALTER TABLE `'+name[v]+'` ADD INDEX ga_i'+str(len(indices))+'('+','.join('`'+c+'`' for c in actual)+');')
lines+=['END//', 'CREATE PROCEDURE ga_fill_read_basis(IN p_session VARCHAR(128)) BEGIN',
' DECLARE v_stage LONGTEXT; DECLARE v_expected BIGINT; DECLARE v_old_limit BIGINT; DECLARE v_limit BIGINT; DECLARE v_step VARCHAR(128); DECLARE v_error TEXT;',
" DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_error=MESSAGE_TEXT; SET v_error=CONCAT(COALESCE(v_step,'read basis'),': ',LEFT(v_error,400)); SET SESSION group_concat_max_len=v_old_limit; RESIGNAL SET MESSAGE_TEXT=v_error; END;",
' SET v_old_limit=@@session.group_concat_max_len;',
' SELECT json_staging_bytes INTO v_limit FROM read_model_execution_policy WHERE policy_id=1;',
" IF v_limit IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB-kontrakt: read-policy mangler'; END IF;",
' SET SESSION group_concat_max_len=v_limit;',
' INSERT INTO ga_rb_scope SELECT session_id FROM sessions WHERE session_id=p_session;',
" INSERT IGNORE INTO ga_rb_scope SELECT s.session_id FROM sessions s JOIN v_graph_display_selection d ON d.source_kind='session' AND d.reference_session_id=s.session_id;"
]
for t in base_order:
 cols=columns[t];where='';lines.append(" SET v_step='source:"+t+"';")
 if t in owned and t!='technical_events':
  path=owner_path(t)
  if path==[]:where=' WHERE a.session_id IN(SELECT session_id FROM ga_rb_scope)'
  elif path:
   fk=path[0];where=' WHERE EXISTS(SELECT 1 FROM `'+name[fk['parent']]+'` p WHERE '+' AND '.join('p.`'+r+'`=a.`'+c+'`' for c,r in zip(fk['cols'],fk['refs']))+')'
  else:raise ValueError('Missing session ownership: '+t)
 fields=[];types=[]
 for i,c in enumerate(cols):
  typ=re.sub(r'/\*.*?\*/','',c['COLUMN_TYPE'])
  value='a.`'+c['COLUMN_NAME']+'`'
  if c['DATA_TYPE'] in ('binary','varbinary','blob','tinyblob','mediumblob','longblob'):raise ValueError('Binary source needs an explicit encoding: '+t)
  if c['DATA_TYPE'] in ('decimal','bigint'):value='CAST('+value+' AS CHAR)'
  if c['DATA_TYPE'] in ('char','varchar','text','tinytext','mediumtext','longtext','enum','set','decimal','bigint'):value='CONVERT('+value+' USING utf8mb4) COLLATE utf8mb4_unicode_ci'
  fields.append(value);types.append('c'+str(i)+' '+typ+" PATH '$["+str(i)+"]'")
 select='SELECT JSON_ARRAYAGG(JSON_ARRAY('+','.join(fields)+')),COUNT(*) FROM `'+t+'` a'+where
 insert=' INSERT INTO `'+name[t]+'`('+','.join('`'+c['COLUMN_NAME']+'`' for c in cols)+") SELECT j.* FROM JSON_TABLE(v_stage, '$[*]' COLUMNS("+','.join(types)+')) j;'
 guard=" IF JSON_VALID(v_stage)=0 OR JSON_LENGTH(v_stage)<>v_expected THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB read staging exceeded policy'; END IF;"
 time=next((c['COLUMN_NAME'] for c in cols if c['COLUMN_NAME'] in ('sample_at','bucket_at')),None)
 if time:
  groups=(',a.session_id' if any(c['COLUMN_NAME']=='session_id' for c in cols) else '')
  lines+=[' BEGIN',' DECLARE ga_done BOOLEAN DEFAULT FALSE;',
   ' DECLARE ga_chunks CURSOR FOR '+select+' GROUP BY DATE(a.`'+time+'`)'+groups+';',
   ' DECLARE CONTINUE HANDLER FOR NOT FOUND SET ga_done=TRUE;',
   ' OPEN ga_chunks;',' ga_days: LOOP',' FETCH ga_chunks INTO v_stage,v_expected;',
   ' IF ga_done THEN LEAVE ga_days; END IF;',guard,insert,
   ' END LOOP;',' CLOSE ga_chunks;',' END;']
 else:
  lines.append(select.replace(' FROM `',' INTO v_stage,v_expected FROM `',1)+';')
  lines+=[' IF v_stage IS NOT NULL THEN',guard,insert,' END IF;']
for v in order:
 lines.append(" SET v_step='view:"+v+"';")
 lines.append(' INSERT INTO `'+name[v]+'` '+rewrite(views[v])+';')
lines+=[' SET SESSION group_concat_max_len=v_old_limit;','END//']
for proc,body,target in [('ga_read_overview',overview,'active'),('ga_read_report',report,'report')]:
 args='IN p_session VARCHAR(128),IN p_now DATETIME(3)' if target=='report' else ''
 lines+=['CREATE PROCEDURE '+proc+'('+args+') BEGIN',' DECLARE v_owner BOOLEAN; DECLARE v_session VARCHAR(128); DECLARE v_source_key CHAR(64); DECLARE v_generated_at DATETIME(3); DECLARE v_operation CHAR(36);',
' DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN IF v_owner THEN ROLLBACK; CALL ga_drop_read_basis(); END IF; RESIGNAL; END;',
' SET v_owner=(@@in_transaction=0);', ' IF v_owner THEN CALL ga_init_read_basis(); START TRANSACTION WITH CONSISTENT SNAPSHOT, READ ONLY; END IF;']
 if target=='active':lines+=[' SELECT session_id INTO v_session FROM v_active_session;',' CALL ga_overview_source_key(v_source_key); SET v_generated_at=UTC_TIMESTAMP(3),v_operation=UUID();']
 else:lines+=[' SET v_session=p_session;', ' SET @ga_report_session=p_session,@ga_report_now=p_now;']
 lines.append(' CALL ga_fill_read_basis(v_session);');lines.append(rewrite(body));
 if target=='active':lines.append(" SELECT 'overview_publication_basis' AS _set,1 AS should_publish,v_source_key AS source_key,v_generated_at AS generated_at,v_operation AS operation_id;")
 lines+=[' IF v_owner THEN COMMIT; CALL ga_drop_read_basis(); END IF;','END//']
lines+=['CREATE PROCEDURE ga_poll_overview() BEGIN',
' DECLARE v_source_key CHAR(64); DECLARE v_previous CHAR(64); DECLARE v_generated DATETIME(3); DECLARE v_seconds INT;',
' CALL ga_overview_source_key(v_source_key);',
' SELECT overview_clock_refresh_seconds INTO v_seconds FROM read_model_execution_policy WHERE policy_id=1;',
" IF v_seconds IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB-kontrakt: overview clock-policy mangler'; END IF;",
' SELECT source_key,generated_at INTO v_previous,v_generated FROM read_model_publication_receipts ORDER BY generated_at DESC,publication_seq DESC LIMIT 1;',
" IF v_previous=v_source_key AND (EXISTS(SELECT 1 FROM v_active_session a WHERE a.is_historical=1) OR UTC_TIMESTAMP(3)<v_generated+INTERVAL v_seconds SECOND) THEN SELECT 'overview_publication_basis' AS _set,0 AS should_publish; ELSE CALL ga_read_overview(); END IF;",
'END//',
'CREATE PROCEDURE ga_ack_overview(IN p_operation CHAR(36),IN p_key CHAR(64),IN p_generated DATETIME(3)) BEGIN',
" IF p_operation IS NULL OR p_key IS NULL OR p_generated IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='DB-kontrakt: publiseringskvittering mangler'; END IF;",
' INSERT IGNORE INTO read_model_publication_receipts(operation_id,source_key,generated_at,published_at) VALUES(p_operation,p_key,p_generated,UTC_TIMESTAMP(3));',
'END//','DELIMITER ;']
# Native bootstrap has a 60 kB per-statement limit. Split private schema/fill
# helpers at complete SQL operations; canonical SELECT logic is unchanged.
for proc in ('ga_init_read_basis','ga_fill_read_basis'):
 start=next(i for i,l in enumerate(lines) if l.startswith('CREATE PROCEDURE '+proc+'('))
 end=next(i for i in range(start+1,len(lines)) if lines[i]=='END//')
 body=lines[start+1:end]
 if proc=='ga_init_read_basis':
  header=body[:1];operations=body[1:];footer=[];declare=[]
 else:
  first=next(i for i,l in enumerate(body) if l.startswith(" SET v_step='source:"))
  header=body[:first];operations=body[first:-1];footer=body[-1:]
  declare=[' DECLARE v_stage LONGTEXT; DECLARE v_expected BIGINT; DECLARE v_step VARCHAR(128); DECLARE v_error TEXT;',
  " DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_error=MESSAGE_TEXT; SET v_error=CONCAT(v_step,': ',LEFT(v_error,350)); RESIGNAL SET MESSAGE_TEXT=v_error; END;"]
  # Source blocks and complete derived inserts are indivisible.
  starts=[i for i,l in enumerate(operations) if l.startswith(' SET v_step=')]+[len(operations)]
  operations=['\n'.join(operations[a:b]) for a,b in zip(starts,starts[1:])]
 chunks=[];chunk=[];size=0
 for op in operations:
  if size+len(op)>35000 and chunk:chunks.append(chunk);chunk=[];size=0
  if len(op)>35000:raise ValueError('Oversized read operation: '+op[:100])
  chunk.append(op);size+=len(op)
 if chunk:chunks.append(chunk)
 helpers=[];calls=[]
 for i,chunk in enumerate(chunks,1):
  helper=proc+'_part_'+str(i)
  helpers+=['CREATE PROCEDURE '+helper+'() BEGIN',*declare,*chunk,'END//']
  calls.append(' CALL '+helper+'();')
 lines[start:end+1]=helpers+[lines[start],*header,*calls,*footer,'END//']
# One generated extension, retained in the installer's existing dependency order.
def spaced(sql):
 chunks=parts(sql)
 for i in range(0,len(chunks),2):chunks[i]=chunks[i].replace(',', ', ')
 return ''.join(chunks)
p=ROOT/'sql/11-runtime-routines.sql';marker='-- BEGIN GENERATED READ BASIS';s=p.read_text().split(marker)[0].rstrip();p.write_text(s+'\n\n'+marker+'\n'+spaced('\n'.join(lines))+'\n')
(ROOT/'contracts/read-execution-plan.json').write_text(json.dumps({'schema_version':'1.0','scope':'requested session plus selected comparison','permanent_sources':base_order,'derived_order':order,'temporary_tables':all_names,'external_library_views':sorted(external),'rules_source':'sql/20-views.sql','overview_source':'tools/overview_reads.sql','report_source':'tools/report_reads.sql'},ensure_ascii=False,indent=2)+'\n')
print('Compiled',len(base_order),'bounded physical sources and',len(order),'derived stages')
