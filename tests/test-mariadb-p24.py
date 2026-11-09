#!/usr/bin/env python3
"""Optional SQL integration test on an initialized, isolated MariaDB datadir.

Never run against a production datadir. Bootstrap requires no network server.
Example: LD_LIBRARY_PATH=... python3 tests/test-mariadb-p24.py --binary .../mariadbd --basedir .../usr --datadir .../isolated-data
"""
import argparse, json, re, subprocess, tempfile, time, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
for arg in ['binary', 'basedir', 'datadir']:
    parser.add_argument('--' + arg, required=True)
parser.add_argument('--expected-version', default=json.loads((ROOT/'BUILD-INFO.json').read_text())['runtime_dependencies']['mariadb'], help='Expected version; defaults to the pinned release version in BUILD-INFO.json')
parser.add_argument('--port',type=int,help='Existing isolated localhost server; protocol mode is required for temporary read-basis integration')
args = parser.parse_args()
version_text = subprocess.run([args.binary, '--no-defaults', '--version'], text=True, capture_output=True, check=True).stdout.strip()
actual_version = re.search(r'Ver (\d+\.\d+\.\d+)', version_text)[1]
if args.expected_version and actual_version != args.expected_version:
    raise RuntimeError(f'Expected MariaDB {args.expected_version}, got {actual_version}')
print('SERVER', version_text, flush=True)

def prepare(sql):
    def routine(match):
        raw=match[1].replace('END//','END;');out=[];safe=[];quote=None;i=0
        while i<len(raw):
            c=raw[i]
            if quote:
                out.append(c)
                if c=='\\' and i+1<len(raw):i+=1;out.append(raw[i])
                elif c==quote:
                    if i+1<len(raw) and raw[i+1]==quote:i+=1;out.append(raw[i])
                    else:quote=None
            elif c in "'\"`":quote=c;out.append(c)
            elif raw.startswith('--',i) and (i+2==len(raw) or raw[i+2].isspace()):
                j=raw.find('\n',i);i=len(raw)-1 if j<0 else j-1
            elif raw.startswith('/*',i):
                j=raw.find('*/',i+2)
                if j<0:raise ValueError('Unclosed SQL comment')
                i=j+1
            elif c.isspace():
                if out and out[-1]!=' ':
                    if out[-1]!=';':safe.append(len(out))
                    out.append(' ')
            else:out.append(c)
            i+=1
        if quote:raise ValueError('Unclosed SQL literal')
        flat=''.join(out);chunks=[];pos=0
        while len(flat)-pos>900:
            ends=[x for x in safe if pos<x<=pos+900]
            if not ends:raise ValueError('Long SQL token in bootstrap')
            end=ends[-1];chunks.append(flat[pos:end]);pos=end+1
        chunks.append(flat[pos:]);return '\n'.join(chunks)+'\n'
    def statements(text):
        # The client protocol accepts ;SELECT on one line. Native bootstrap
        # needs a newline between statements. Keep quoted literals intact.
        text='\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('--'))+'\n'
        out=[];quote=None;escaped=False
        for char in text:
            out.append(char)
            if escaped:escaped=False;continue
            if quote:
                if char=='\\':escaped=True
                elif char==quote:quote=None
            elif char in "'\"`":quote=char
            elif char==';':out.append('\n')
        return ''.join(out)
    sql=sql.replace('END//\nCREATE','END//\nDELIMITER ;\nDELIMITER //\nCREATE')
    pieces=re.split(r'(DELIMITER //\s*[\s\S]*?DELIMITER ;)',sql)
    return ''.join(re.sub(r'DELIMITER //\s*([\s\S]*?)DELIMITER ;',routine,p) if p.startswith('DELIMITER //') else statements(p) for p in pieces)

def execute(sql, label):
    if args.port:
        result=subprocess.run(['node',str(ROOT/'tests/sql-client.js')],input=json.dumps({'port':args.port,'sql':prepare("SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;\nSET time_zone='+00:00';\n"+sql)}),text=True,capture_output=True)
        if result.returncode:raise RuntimeError(label+'\n'+result.stderr[-3000:])
        print('PASS',label,flush=True);return
    # Bootstrap fixture is fully offline between calls. Aria's transient logs
    # are recreated in this isolated directory; production is never touched.
    for log in Path(args.datadir).glob('aria_log*'):log.unlink()
    result = subprocess.run([args.binary, '--no-defaults', '--bootstrap', '--user=root',
        '--basedir=' + args.basedir, '--datadir=' + args.datadir, '--skip-networking',
        '--innodb-buffer-pool-size=64M','--innodb-use-native-aio=0','--innodb-flush-method=fsync'], input=prepare("SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;\nSET time_zone='+00:00';\n"+sql), text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(label + '\n' + result.stderr[-4000:])
    print('PASS', label)

# Load the installer's actual dependency order; a separate test-only order
# would miss routines needed by seed-time template cloning.
files=[Path(f).stem for f in json.loads((ROOT/'installer/migrations.json').read_text())['fresh_files']]
assert len(files)==13 and len(set(files))==13,files
assert files.index('11-runtime-routines')<files.index('04-ale-templates-seed'),files
# Isolated fixture from the host's zoneinfo; this never touches the user's DB.
from zoneinfo import ZoneInfo
zone=ZoneInfo('Europe/Oslo')
transitions=[];previous=None
for stamp in range(0,2145916800,3600):
    local=datetime.datetime.fromtimestamp(stamp,datetime.timezone.utc).astimezone(zone)
    current=int(local.utcoffset().total_seconds())
    if current!=previous:transitions.append((stamp,1 if current==7200 else 0));previous=current
sqltz="DELETE FROM mysql.time_zone_name WHERE Name='Europe/Oslo';\nDELETE FROM mysql.time_zone_transition WHERE Time_zone_id=999;\nDELETE FROM mysql.time_zone_transition_type WHERE Time_zone_id=999;\nDELETE FROM mysql.time_zone WHERE Time_zone_id=999;\nINSERT INTO mysql.time_zone VALUES(999,'N');\nINSERT INTO mysql.time_zone_name VALUES('Europe/Oslo',999);\nINSERT INTO mysql.time_zone_transition_type VALUES(999,0,3600,0,'CET'),(999,1,7200,1,'CEST');\n"
for stamp,kind in transitions:sqltz+=f"INSERT INTO mysql.time_zone_transition VALUES(999,{stamp},{kind});\n"
execute(sqltz,'Oslo timezone fixture')
db = 'ga_p24_release_test'
execute(f'DROP DATABASE IF EXISTS {db};\nCREATE DATABASE {db} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\nUSE {db};\n' +
    '\n'.join((ROOT / 'sql' / (f + '.sql')).read_text() for f in files), 'clean schema, routines, views and all seeds')

def literal(value):
    if value is None: return 'NULL'
    if isinstance(value, (int, float)): return str(value)
    return "'" + str(value).replace("'", "''") + "'"

def flow_query(node_id, payload=None, fields=None, return_message=False):
    # Run the shipped Function source, so SQL drift in the real runtime paths
    # is covered in addition to schema/view installation.
    js = '''const fs=require('fs');const f=JSON.parse(fs.readFileSync(process.argv[1]));
const n=f.find(n=>n.id===process.argv[2]);let out=new Function('msg','node','global',n.func)(
{payload:JSON.parse(process.argv[3]),...JSON.parse(process.argv[4])},{error:e=>{throw Error(e)}},{get:()=>({})});
if(Array.isArray(out))out=out[0];if(!out?.topic)throw Error('Missing SQL for '+n.id);process.stdout.write(JSON.stringify(out));'''
    msg=json.loads(subprocess.run(['node','-e',js,str(ROOT/'nodered/flows.template.json'),node_id,json.dumps(payload or {}),json.dumps(fields or {})],text=True,capture_output=True,check=True).stdout)
    if return_message:
        return msg
    values=iter(msg.get('payload', []))
    # Substitute matches in the original SQL once. A literal parameter may
    # itself contain '?' and must never consume a later placeholder.
    return re.sub(r'\?',lambda _:literal(next(values)),msg['topic'])

read_queries=['p20_restore_query','p20_systemcheck_query','p20_template_editor_query',
    'p20_technical_export_query','p20_overview_query','p23_verification_read_query']
for query in read_queries:
    execute('USE '+db+';\n'+flow_query(query), 'actual '+query+' SQL before Start')
execute('USE '+db+';\n'+flow_query('p20_template_select','w3470-standard@3.0'),
    'actual template selection SQL creates the pre-start draft')

variables = {
    'session_id': 'p24-sql-session', 'is_demo': 0, 'template_version': 'w3470-standard@3.0',
    'source_profile': 'tilt-pro-blue-ha', 'batch_name': 'P24 SQL integration',
    'pitched_at': '2026-10-01 00:00:00', 'created_at': '2026-10-01 00:00:00',
    'og': 1.05, 'volume_l': 150, 'pitch_mode': 'dry', 'pitch_temperature_c': 12,
    'yeast_amount_g': 201, 'expected_attenuation_min': 80, 'expected_attenuation_max': 84,
    'operation_id': 'p24-sql-start', 'measurement_method': 'hydrometer', 'measured_sg': 1.05,
    'sample_temperature_c': 20, 'calibration_temperature_c': 20, 'corrected_sg': 1.05,
    'manual_temperature_c': 12, 'pressure_bar': 0, 'cooler_setpoint_c': 12, 'cooler_calibration_offset_c': 0,
    'airlock_activity': 'none', 'user_conclusion': 'uncertain', 'measurement_note': '',
    'corrected_sg_model': 'hydrometer-temperature-correction-sg-v1', 'abv_now': 0, 'finished_abv': 5.25,
    'finished_abv_model': 'expected-attenuation-midpoint-v1',
}
for key in ['acetaldehyde_level', 'diacetyl_level', 'wort_like_level', 'sulfur_so2_level',
    'sulfur_h2s_level', 'clarity_level', 'settling_yeast_level', 'settling_minutes']:
    variables[key] = 0
sql = (ROOT / 'sql/start-session.sql').read_text()
sql = re.sub(r'SET @ga_([a-z0-9_]+)=\?;', lambda m: f'SET @ga_{m[1]}={literal(variables.get(m[1]))};', sql)
sql=sql[:sql.index('SELECT s.*')]
execute('USE ' + db + ';\n' + sql, 'Start freezes session through real transaction routine')
for query in read_queries:
    execute('USE '+db+';\n'+flow_query(query), 'actual '+query+' SQL with active session')

checks = [
    ("(SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_type='BASE TABLE')=207", 'table count'),
    ("(SELECT COUNT(*) FROM information_schema.views WHERE table_schema=DATABASE())=183", 'view count'),
    ("(SELECT COUNT(*) FROM template_biological_criteria WHERE exception_allowed<>1)=0", 'default biology exception policy'),
    ("(SELECT COUNT(*) FROM template_process_criteria WHERE exception_allowed<>1)=0", 'default process exception policy'),
    ("(SELECT expected_attenuation_min_percent=80 AND expected_attenuation_max_percent=84 FROM template_defaults WHERE version_id='p24-clone')=1", 'clone attenuation columns'),
    ("(SELECT COUNT(*) FROM template_analysis_graph_series WHERE version_id='p24-clone')=(SELECT COUNT(*) FROM template_analysis_graph_series WHERE version_id='w3470-standard@3.0')", 'clone all series'),
    ("(SELECT COUNT(*) FROM session_analysis_graph_series WHERE provisional_allowed=0)=(SELECT COUNT(*) FROM template_analysis_graph_series WHERE version_id='w3470-standard@3.0')", 'frozen measured-only policy'),
    ("(SELECT COUNT(*) FROM session_overview_graph_policy)=3", 'frozen overview band policy'),
    ("(SELECT COUNT(*) FROM session_analysis_graph_series WHERE graph_id='sg-stability' AND band_model<>'none')=0", 'stability has no band'),
    ("(SELECT COUNT(*) FROM v_metadata_lineage_gaps)=0", 'metadata lineage'),
    ("(SELECT COUNT(*) FROM template_versions WHERE version_id='p24-failed-clone')=0", 'failed clone rollback'),
    ("(SELECT COUNT(*) FROM templates WHERE template_id='p24-failed-template')=0", 'failed clone identity rollback'),
    ("(SELECT selected_version_id FROM template_editor_state WHERE state_key='current')='p24-clone'", 'failed clone keeps selection'),
]
sql = f'''USE {db};
CALL ga_clone_template_tx('w3470-standard@3.0','p24-clone','p24-template','Clone test');
DELIMITER //
CREATE TRIGGER p24_clone_failure BEFORE INSERT ON template_defaults FOR EACH ROW BEGIN IF NEW.version_id='p24-failed-clone' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Injected copy failure'; END IF; END//
CREATE PROCEDURE p24_check_clone_rollback() BEGIN DECLARE failed INT DEFAULT 0; DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET failed=1; CALL ga_clone_template_tx('w3470-standard@3.0','p24-failed-clone','p24-failed-template','Fail'); IF failed<>1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Expected clone failure'; END IF; END//
CREATE PROCEDURE p24_assert(IN condition_met BOOLEAN,IN message_text_value VARCHAR(255)) BEGIN IF condition_met IS NULL OR NOT condition_met THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=message_text_value; END IF; END//
DELIMITER ;
CALL p24_check_clone_rollback();
DROP TRIGGER p24_clone_failure;
'''
sql += '\n'.join('CALL p24_assert(' + condition + ',' + literal(label) + ');' for condition, label in checks) + '\n'
execute(sql, 'clone full fields, injected rollback, policy freeze, counts and lineage')
view_queries=''.join('SELECT COUNT(*) FROM '+name+';\n' for name in re.findall(r'CREATE OR REPLACE VIEW\s+(\w+)',(ROOT/'sql/20-views.sql').read_text(),re.I))
execute('USE '+db+';\n'+view_queries,'all 183 actual view queries')
execute('USE '+db+';\n'+''.join('SET NAMES utf8mb4 '+collation+';\n'+
    "SELECT COUNT(*) FROM v_metadata_lineage_gaps WHERE gap_type='no_dependency';\n"+
    "SELECT COUNT(*) FROM v_metadata_lineage_gaps WHERE gap_type='missing_producer';\n"+
    "SELECT COUNT(*) FROM v_metadata_lineage_gaps WHERE gap_type='missing_consumer';\n"
    for collation in ['COLLATE utf8mb4_unicode_ci','COLLATE utf8mb4_general_ci','']),
    'lineage filters with declared, legacy client and MariaDB 11.8 default collations')
# Read the actual shipping query's database-variable row from MariaDB. Numeric
# fixtures hid the 12.x enum OFF -> Number('OFF') = NaN defect in p24r4.
variable_query=next(statement.strip() for statement in flow_query('p20_systemcheck_query').split(';') if statement.strip().startswith('SELECT @@read_only'))
# This narrow read_only test supplies unrelated required metadata explicitly.
# Full source classification through actual SQL is covered by TEST-FUNC-023.
def system_check_basis(info):
    return [[info],[{'_set':'session_check','check_id':'session','check_status':'ok','severity':'info','summary':'Explicit session fixture for writable check'}],[{'_set':'measurement_check','check_id':'measurement_source','check_status':'ok','severity':'info','summary':'Source fixture for isolated writable check'}],[{'_set':'check_definitions','check_id':'measurement_source','label':'Målekilde','category':'measurement'}]]
mode_rows={}
mode_evidence=[]
for mode in ['ON','NO_LOCK','NO_LOCK_NO_ADMIN','OFF']:
    with tempfile.TemporaryDirectory() as temp:
        outfile=Path(temp)/'database-variables.tsv'
        # Distinct actual database timestamps also give distinct append-only run IDs.
        delay='DO SLEEP(1);\n' if mode=='OFF' else ''
        execute('SET GLOBAL read_only='+literal(mode)+';\n'+delay+variable_query+
            ' INTO OUTFILE '+literal(str(outfile))+" FIELDS TERMINATED BY '\\t' LINES TERMINATED BY '\\n';\nSET GLOBAL read_only='OFF';\n",
            'actual 12.3.3 read_only='+mode+' through shipping Systemkontroll query')
        values=outfile.read_text().strip().split('\t')
    assert len(values)==4,values
    info=dict(read_only=values[0],global_read_only=values[1],database_writable=int(values[2]),database_epoch=float(values[3]))
    assert info['read_only']==mode and info['global_read_only']==mode,info
    assert info['database_writable']==int(mode=='OFF'),info
    message=flow_query('p20_systemcheck_result',system_check_basis(info),return_message=True)
    result=next(c for c in message['ga_systemcheck']['checks'] if c['id']=='writable')
    assert result['status']==('ok' if mode=='OFF' else 'error'),(info,result)
    mode_rows[mode]=info
    mode_evidence.append({'actual_database_row':info,'function_result':result})
execute('USE '+db+';\n'+flow_query('p20_systemcheck_result',system_check_basis(mode_rows['ON']))+
    "\nCALL p24_assert((SELECT COUNT(*) FROM system_check_runs)=1,'Systemkontroll run written');\n"+
    "CALL p24_assert((SELECT COUNT(*) FROM system_check_results)=15,'all Systemkontroll results written');\n"+
    "CALL p24_assert((SELECT COUNT(*) FROM v_active_technical_issues WHERE issue_key='system_check:writable')=1,'read_only ON raises writable issue');\n",
    'actual Systemkontroll write SQL with real ON row and all 15 results')
execute('USE '+db+';\n'+flow_query('p20_systemcheck_result',system_check_basis(mode_rows['OFF']))+
    "\nCALL p24_assert((SELECT COUNT(*) FROM system_check_runs)=2,'append-only recovery run written');\n"+
    "CALL p24_assert((SELECT COUNT(*) FROM system_check_results WHERE check_id='writable' AND status='error')=1,'original writable error retained');\n"+
    "CALL p24_assert((SELECT COUNT(*) FROM system_check_results WHERE check_id='writable' AND status='ok')=1,'real OFF row is writable');\n"+
    "CALL p24_assert((SELECT COUNT(*) FROM technical_events WHERE issue_key='system_check:writable' AND event_type='issue_cleared')=1,'recovery clears issue append-only');\n"+
    "CALL p24_assert((SELECT COUNT(*) FROM v_active_technical_issues WHERE issue_key='system_check:writable')=0,'writable issue no longer active');\n",
    'real OFF row is writable and clears prior issue without rewriting history')
(ROOT/'verification/p24r9-writable-regression.json').write_text(json.dumps({
    'application_version':(ROOT/'VERSION').read_text().strip(),
    'server_version':version_text,'sql_transport':'native isolated MariaDB bootstrap; actual query rows passed to shipping Function source',
    'variable_query':variable_query,'cases':mode_evidence,
    'append_only_issue_recovery':'pass; error result retained, new OK result and issue_cleared event, no active writable issue'
},ensure_ascii=False,indent=2)+'\n')
sql=f'''USE {db};
INSERT INTO analysis_series_values(session_id,graph_id,series_id,sample_at,basis_pitched_at,actual_value,value_status,standard_basis_met,measured_at,sample_count,window_started_at,window_ended_at,requested_window_seconds,coverage_seconds,source_kind,created_at)
VALUES ('p24-sql-session','sg-rate','sg-rate','2026-10-01 18:00:00','2026-10-01 00:00:00',2.88,'standard',1,'2026-10-01 18:00:00',217,'2026-10-01 00:00:00','2026-10-01 18:00:00',86400,64800,'metric',UTC_TIMESTAMP(3)),
('p24-sql-session','sg-rate','sg-rate','2026-10-02 00:00:00','2026-10-01 00:00:00',2.88,'standard',1,'2026-10-02 00:00:00',289,'2026-10-01 00:00:00','2026-10-02 00:00:00',86400,86400,'metric',UTC_TIMESTAMP(3));
CALL p24_assert((SELECT value_status='standard' AND line_color='#039be5' AND line_dasharray='' AND basis_display LIKE 'Ordinær%' FROM v_session_analysis_series WHERE graph_id='sg-rate' AND sample_at='2026-10-01 18:00:00'),'measured-only status and style preserved');
CALL p24_assert((SELECT value_status='standard' AND line_color='#039be5' AND line_dasharray='' FROM v_session_analysis_series WHERE graph_id='sg-rate' AND sample_at='2026-10-02 00:00:00'),'standard status and style');
CALL p24_assert((SELECT COUNT(*) FROM v_session_analysis_graphs WHERE x_axis_started_at='2026-10-01 00:00:00')=6,'analysis pitch axes');
CALL p24_assert((SELECT COUNT(*) FROM v_session_overview_graph_axes WHERE x_axis_started_at='2026-10-01 00:00:00')=3,'overview pitch axes');
INSERT INTO session_timing_revisions(timing_revision_id,session_id,timing_field,revision_no,supersedes_revision_id,value_at,source,created_at)
VALUES ('p24-pitch-r2','p24-sql-session','pitched_at',2,'timing-p24-sql-session-pitch-r1','2026-09-30 23:00:00','manual',UTC_TIMESTAMP(3));
CALL p24_assert((SELECT COUNT(*) FROM v_session_analysis_graphs WHERE x_axis_started_at='2026-09-30 23:00:00')=6,'analysis effective pitch');
CALL p24_assert((SELECT COUNT(*) FROM v_session_overview_graph_axes WHERE x_axis_started_at='2026-09-30 23:00:00')=3,'overview effective pitch');
'''
# Two unmet evaluations of the same candidate preserve their raw result. A
# withdrawal can supersede the original handling after the new evaluation.
for i in [1,2]:
    sql+=f"INSERT INTO biological_evaluations(evaluation_id,session_id,current_phase_id,candidate_phase_id,evaluated_at,outcome,engine_version,created_at) VALUES ('p24-e{i}','p24-sql-session','B1','B2','2026-10-01 00:10:00','not_met','test',UTC_TIMESTAMP(3));\n"
    sql+=f"INSERT INTO biological_evaluation_criteria(evaluation_id,session_id,phase_id,criterion_id,criterion_order,role_id,metric_id,model_id,met,valid,evaluation_status,created_at) SELECT 'p24-e{i}',session_id,phase_id,criterion_id,criterion_order,role_id,metric_id,model_id,0,1,'not_met',UTC_TIMESTAMP(3) FROM session_biological_criteria WHERE phase_id='B2' LIMIT 1;\n"
sql+="""INSERT INTO biological_criterion_exceptions(exception_id,session_id,phase_id,evaluation_id,criterion_id,revision_no,action,exception_type,confirmed,note,created_at)
SELECT 'p24-ex1',session_id,phase_id,evaluation_id,criterion_id,1,'register','akseptert_avvik',1,NULL,UTC_TIMESTAMP(3) FROM biological_evaluation_criteria WHERE evaluation_id='p24-e1';
INSERT INTO biological_criterion_exceptions(exception_id,session_id,phase_id,evaluation_id,criterion_id,revision_no,supersedes_exception_id,action,confirmed,note,created_at)
SELECT 'p24-ex2',session_id,phase_id,evaluation_id,criterion_id,2,'p24-ex1','withdraw',1,NULL,UTC_TIMESTAMP(3) FROM biological_evaluation_criteria WHERE evaluation_id='p24-e2';
CALL p24_assert((SELECT COUNT(*) FROM biological_evaluation_criteria WHERE evaluation_id IN ('p24-e1','p24-e2') AND met=0)=2,'original unmet evaluations retained');
CALL p24_assert((SELECT COUNT(*) FROM v_session_biological_exception_read_model)=2,'both handling revisions in report read-model');
"""
execute(sql,'persisted status/style, shared effective-pitch axes and biological handling across evaluations')

# Read the real frozen model rows into a Node-RED message. This tests the
# production Function's write transaction against the actual shipping schema.
def frozen_message():
    definitions={
      'series_defs':('session_analysis_graph_series','graph_id series_id source_kind metric_id minimum_samples minimum_coverage_fraction warmup_minutes valid_minimum_value valid_maximum_value provisional_allowed provisional_minimum_samples provisional_minimum_span_minutes band_model'),
      'metric_rules':('session_metric_runtime_rules','metric_id calculation_model_id valid_minimum_value valid_maximum_value'),
      'metric_inputs':('session_metric_runtime_inputs','metric_id input_id source_kind source_id'),
      'metric_params':('session_metric_runtime_parameter_values','metric_id parameter_id data_type real_value integer_value boolean_value text_value'),
      'calc_rules':('session_biology_calculations','calculation_id model_id'),
      'calc_params':('session_biology_calculation_parameter_values','calculation_id parameter_id data_type real_value integer_value boolean_value text_value'),
    }
    parts=[]
    for key,(table,cols) in definitions.items():
        args_sql=','.join(literal(c)+','+c for c in cols.split())
        parts.append(literal(key)+",(SELECT JSON_ARRAYAGG(JSON_OBJECT("+args_sql+")) FROM "+table+" WHERE session_id='p24-sql-session')")
    with tempfile.TemporaryDirectory(prefix='ga-p24-model-') as td:
        target=Path(td)/'frozen.json'
        execute('USE '+db+';\nSELECT JSON_OBJECT('+','.join(parts)+') INTO DUMPFILE '+literal(str(target))+';', 'read frozen calculation/metric/publication policies')
        raw=json.loads(target.read_text())
    return [[{'_set':key,**row} for row in (json.loads(value) if isinstance(value,str) else value or [])] for key,value in raw.items()]

model_sets=frozen_message()
pitch=datetime.datetime(2026,9,30,23)
def iso(t):return t.isoformat(timespec='milliseconds')+'Z'
context=[{'_set':'context','session_id':'p24-sql-session','og':1.05,'pitched_at':iso(pitch)}]
measurements=[]
for i in range(577):
    sg=round(1.05-min(i,288)*4/288000,5)
    measurements.append({'_set':'measurements','bucket_at':iso(pitch+datetime.timedelta(minutes=5*i)), 'sg_median':sg,'sg_min':sg-.00005,'sg_max':sg+.00005})
message=[context,measurements,*model_sets]
analysis_sql=flow_query('p22_analysis_result',message)
last='2026-10-02 23:00:00'
execute('USE '+db+';\nSET timestamp=UNIX_TIMESTAMP('+literal(last)+');\n'+analysis_sql+'''

CALL p24_assert((SELECT COUNT(*) FROM session_calculation_baselines)=1,'one qualified baseline');
CALL p24_assert((SELECT baseline_value=1.049990 AND sample_count=3 FROM session_calculation_baselines),'earliest qualified pitch prefix');
CALL p24_assert((SELECT ABS(actual_value)<0.01 AND evaluation_status='standard' FROM v_current_metric_value WHERE metric_id='sg_rate_points_per_day'),'current rate is a fresh zero, independent of old criterion snapshots');
CALL p24_assert((SELECT ABS(actual_value-8.00)<0.01 FROM v_current_metric_value WHERE metric_id='apparent_attenuation_percent'),'current AA uses actual OG and raw Tilt');
CALL p24_assert((SELECT actual_value=0 FROM v_current_metric_value WHERE metric_id='sg_stability_24h_points'),'24-hour stability zero');
CALL p24_assert((SELECT ABS(actual_value-4)<0.01 FROM v_current_metric_value WHERE metric_id='sg_stability_48h_points'),'48-hour stability independent curve');
CALL p24_assert((SELECT COUNT(DISTINCT series_id) FROM v_session_analysis_series WHERE graph_id='sg-stability' AND actual_value IS NOT NULL)=2,'two stability series through the fermentation');
CALL p24_assert((SELECT COUNT(*) FROM analysis_series_values WHERE graph_id='sg-stability' AND (range_min_value IS NOT NULL OR range_max_value IS NOT NULL))=0,'no stability band');
CALL p24_assert((SELECT abv_now_display LIKE '%estimert' AND attenuation_display IS NOT NULL AND yeast_display IS NOT NULL FROM v_active_session_report_summary),'live summary ABV, AA and yeast');
SET @value_count=(SELECT COUNT(*) FROM analysis_series_values);
SET @event_count=(SELECT COUNT(*) FROM analysis_validation_events);
'''+analysis_sql+'''
CALL p24_assert((SELECT COUNT(*) FROM analysis_series_values)=@value_count,'analysis facts replay idempotent');
CALL p24_assert((SELECT COUNT(*) FROM analysis_validation_events)=@event_count,'analysis rejection facts replay idempotent');
CALL p24_assert((SELECT COUNT(*) FROM session_calculation_baselines)=1,'baseline replay immutable');
''', 'actual measured analysis transaction, live zero, 24/48 curves, AA/ABV and idempotence')
# Simulate source-history purging: reuse the saved baseline, without pitch rows.
base=[{'_set':'baselines','calculation_id':'tilt_baseline','pitched_at':iso(pitch),'baseline_value':1.04999,'sample_count':3,'measured_at':iso(pitch+datetime.timedelta(minutes=10)),'window_started_at':iso(pitch),'window_ended_at':iso(pitch+datetime.timedelta(minutes=10))}]
late_sql=flow_query('p22_analysis_result',[context,measurements[-13:],base,*model_sets])
execute('USE '+db+';\nSET timestamp=UNIX_TIMESTAMP('+literal(last)+');\n'+late_sql+'''
CALL p24_assert((SELECT baseline_value=1.049990 FROM session_calculation_baselines),'purging cannot shift pitch baseline');
CALL p24_assert((SELECT ABS(actual_value-8.00)<0.01 FROM v_current_metric_value WHERE metric_id='apparent_attenuation_percent'),'AA preserved after source history loss');
SET timestamp=UNIX_TIMESTAMP('2026-10-07 00:00:00');
CALL p24_assert((SELECT actual_value IS NULL AND evaluation_status='missing_basis' FROM v_current_metric_value WHERE metric_id='sg_rate_points_per_day'),'stale rate becomes unavailable, not retained or zeroed');
''','saved calibration survives history loss and stale current values are unavailable')
# Explicit NULL optional bounds are normalized facts, never numeric zero.
for scope,owner in [('bio','phase_id'),('process','process_id')]:
    criterion={'_set':'criterion','session_id':'p24-sql-session',owner:'B5' if scope=='bio' else 'P3','criterion_id':'aa_near_target' if scope=='bio' else 'temp_start_ramp','model_id':'threshold'}
    # Resolve the actual first threshold criterion for this owner from the seed.
    table='template_biological_criteria' if scope=='bio' else 'template_process_criteria'
    text=(ROOT/'sql/03-w3470-template-seed.sql').read_text()
    pattern=r"'w3470-standard@3.0','"+criterion[owner]+r"','([^']+)',[^\n]*?'threshold'"
    match=re.search(pattern,text)
    if match is None:raise RuntimeError('Missing threshold fixture '+scope)
    criterion['criterion_id']=match[1]
    allowed=[{'_set':'allowed','parameter_id':key,'data_type':kind} for key,kind in [('minimum_value','real'),('maximum_value','real'),('maximum_age_minutes','integer')]]
    sql=flow_query('p20_'+scope+'_criterion_correction_context_result',[[criterion],allowed],{'ga_correction_request':{'action':'override','parameters':{'minimum_value':1,'maximum_value':None,'maximum_age_minutes':None}}})
    runtime_table='session_biological_criterion_revision_parameter_values' if scope=='bio' else 'session_process_criterion_revision_parameter_values'
    execute('USE '+db+';\n'+sql+'\nCALL p24_assert((SELECT COUNT(*) FROM '+runtime_table+" WHERE is_unset=1 AND real_value IS NULL AND integer_value IS NULL)=2,'optional fields persist unset');",'actual '+scope+' correction transaction with unset optional bounds')
new_pitch=pitch+datetime.timedelta(minutes=5)
new_context=[{'_set':'context','session_id':'p24-sql-session','og':1.05,'pitched_at':iso(new_pitch)}]
new_basis_sql=flow_query('p22_analysis_result',[new_context,measurements,*model_sets])
execute('USE '+db+';\n'+"""
INSERT INTO session_timing_revisions(timing_revision_id,session_id,timing_field,revision_no,supersedes_revision_id,value_at,source,created_at)
VALUES ('p24-pitch-r3','p24-sql-session','pitched_at',3,'p24-pitch-r2','2026-09-30 23:05:00','manual',UTC_TIMESTAMP(3));
"""+new_basis_sql+"""
CALL p24_assert((SELECT COUNT(*) FROM session_calculation_baselines)=2,'pitch correction retains old baseline and qualifies new baseline');
CALL p24_assert((SELECT COUNT(DISTINCT basis_pitched_at) FROM analysis_series_values)=3,'both corrected and original analysis facts are retained');
CALL p24_assert((SELECT COUNT(DISTINCT basis_pitched_at) FROM v_session_analysis_series WHERE actual_value IS NOT NULL)=1,'current series excludes former pitch bases');
CALL p24_assert((SELECT MIN(basis_pitched_at)='2026-09-30 23:05:00' FROM v_session_analysis_series WHERE actual_value IS NOT NULL),'current series uses corrected pitch');
CALL p24_assert((SELECT y_axis_min=0 FROM v_session_analysis_graph_axes WHERE graph_id='sg-stability'),'nonnegative stability axis starts at zero');
""",'pitch correction appends a new analysis basis and retains historical facts')
# Manual observations retain the old facts while the current graph follows
# the latest observation revision, including a revised SG and actual time.
def json_read(expression,label):
    with tempfile.TemporaryDirectory(prefix='ga-p24-read-') as td:
        target=Path(td)/'row.json'
        execute('USE '+db+';\nSELECT '+expression+' INTO DUMPFILE '+literal(str(target))+';',label)
        return json.loads(target.read_text())
ob=json_read("(SELECT JSON_OBJECT('observation_revision_id',observation_revision_id,'recorded_at',DATE_FORMAT(recorded_at,'%Y-%m-%dT%H:%i:%s.000Z'),'corrected_sg',corrected_sg) FROM v_current_observation_revision LIMIT 1)",'read actual Start observation revision')
manual_sql=flow_query('p22_analysis_result',[new_context,[{'_set':'observations',**ob}],*model_sets])
execute('USE '+db+';\n'+manual_sql+"\nCALL p24_assert((SELECT COUNT(*) FROM v_session_analysis_series WHERE series_id='manual-attenuation' AND actual_value IS NOT NULL)=1,'manual observation creates its own actual point');",'persist real manual observation with FK revision basis')
cols=re.search(r'CREATE TABLE IF NOT EXISTS observation_round_revisions \(([\s\S]*?)\) ENGINE=',(ROOT/'sql/10-runtime-schema.sql').read_text())[1]
cols=[line.strip().split()[0] for line in cols.splitlines() if re.match(r'^    [a-z][a-z0-9_]+ ',line)]
changes={'observation_revision_id':"'p24-observation-r2'",'revision_no':'revision_no+1','supersedes_revision_id':'observation_revision_id','recorded_at':"'2026-10-01 01:00:00'",'corrected_sg':'1.01000','created_at':'UTC_TIMESTAMP(3)'}
execute('USE '+db+';\nINSERT INTO observation_round_revisions('+','.join(cols)+') SELECT '+','.join(changes.get(c,c) for c in cols)+' FROM v_current_observation_revision LIMIT 1;', 'append corrected manual SG/time without altering first revision')
ob2={'_set':'observations','observation_revision_id':'p24-observation-r2','recorded_at':'2026-10-01T01:00:00.000Z','corrected_sg':1.01}
revised_manual_sql=flow_query('p22_analysis_result',[new_context,[ob2],*model_sets])
execute('USE '+db+';\n'+revised_manual_sql+"\nCALL p24_assert((SELECT COUNT(*) FROM analysis_series_values WHERE series_id='manual-attenuation')=2,'manual revisions retained append-only');\nCALL p24_assert((SELECT COUNT(*) FROM v_session_analysis_series WHERE series_id='manual-attenuation' AND actual_value IS NOT NULL)=1,'only current manual observation appears');\nCALL p24_assert((SELECT ABS(actual_value-80)<0.001 AND measured_at='2026-10-01 01:00:00' FROM v_session_analysis_latest WHERE series_id='manual-attenuation'),'current manual AA and actual timestamp follow correction');",'corrected manual AA/current latest excludes former revision')
# Exercise completion, pending/failed retry and release using the shipped SQL.
end_sql=flow_query('p21_session_end_context_result',[[{'session_id':'p24-sql-session','lifecycle':'active','ended_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'recorded_now':datetime.datetime.now(datetime.timezone.utc).isoformat()}]])
execute('USE '+db+';\n'+end_sql+"\nCALL p24_assert((SELECT archive_status='missing' FROM v_session_archive_status),'missing export is visible after completion');",'actual Avslutt write transaction; archive required')
attempt_sql=flow_query('p24_archive_attempt_query',fields={'ga_export_session_id':'p24-sql-session'})
execute('USE '+db+';\n'+attempt_sql+"\nCALL p24_assert((SELECT archive_status='pending' FROM v_session_archive_status),'pending attempt is visible');",'archive attempt is persisted before files are built')
get_attempt="(SELECT JSON_OBJECT('attempt_id',attempt_id,'attempt_no',attempt_no) FROM session_export_attempts ORDER BY attempt_no DESC LIMIT 1)"
a=json_read(get_attempt,'read first actual DB-generated archive attempt')
failed_sql=flow_query('p21_session_export_verify_query',fields={'ga_export_session_id':'p24-sql-session','ga_archive_attempt_id':a['attempt_id'],'ga_archive_result':{'status':'failed','error_message':'Injected missing report file'}})
execute('USE '+db+';\n'+failed_sql+"\nCALL p24_assert((SELECT archive_status='failed' AND archive_error_message='Injected missing report file' FROM v_session_archive_status),'failure and cause remain visible');\nCALL p24_assert((SELECT COUNT(*) FROM session_lifecycle_events WHERE lifecycle='completed')=1,'archive failure cannot repeat session end');",'archive failure is registered as terminal append-only metadata')
# Even a fabricated context acknowledgement cannot bypass the DB release gate.
prepare_sql=flow_query('p21_session_prepare_context_result',[[{'session_id':'p24-sql-session','lifecycle':'completed','is_demo':0,'verified_export_count':1}]])
execute('USE '+db+';\n'+prepare_sql+"\nCALL p24_assert((SELECT COUNT(*) FROM session_release_events)=0,'DB rejects release without verified archive');",'Gjør klar retains completed session until file verification')
execute('USE '+db+';\n'+attempt_sql+"\nCALL p24_assert((SELECT COUNT(*) FROM session_export_attempts)=2,'retry is a distinct persisted attempt');\nCALL p24_assert((SELECT archive_status='pending' FROM v_session_archive_status),'retry pending is visible');",'retry on completed session appends attempt without a new lifecycle end')
a2=json_read(get_attempt,'read retry attempt identity')
with tempfile.TemporaryDirectory(prefix='ga-p24-large-export-') as td:
    td=Path(td);archive=json.dumps({'session_id':'p24-sql-session','facts':'ø'*(10*1024*1024)},ensure_ascii=False)+'\n';html='<!doctype html><p>Actual report</p>'
    job={'session_id':'p24-sql-session','attempt_id':a2['attempt_id'],'stage_json_path':str(td/'data.json.pending'),'stage_report_path':str(td/'report.html.pending'),'archive_path':str(td/'data.json'),'report_path':str(td/'report.html'),'archive_bytes':len(archive.encode()),'report_bytes':len(html.encode())}
    import sqlite3,hashlib
    # Large-file transport is exercised with a real SQLite pair. Normalized
    # application contents and import rollback are covered by test-sqlite-live.
    job.pop('stage_json_path');job['archive_path']=str(td/'session-test-export-002-gjaering.sqlite');job['template_path']=str(td/'session-test-export-002-template.sqlite')
    for role,file in [('session',job['archive_path']),('template',job['template_path'])]:
        with sqlite3.connect(file) as conn:
            conn.execute('CREATE TABLE transport_test(value TEXT)')
            conn.execute('INSERT INTO transport_test VALUES(?)',(archive if role=='session' else 'template',))
    for role,field in [('archive','archive_path'),('template','template_path')]:
        data=Path(job[field]).read_bytes();job[role+'_bytes']=len(data);job[role+'_sha256']=hashlib.sha256(data).hexdigest()
    Path(job['stage_report_path']).write_text(html)
    import base64
    result=json.loads(subprocess.run(['node',str(ROOT/'tools/archive_export.js'),base64.b64encode(json.dumps(job).encode()).decode()],capture_output=True,text=True,check=True).stdout)
    assert result['status']=='verified' and result['archive_bytes']>19090552
    registered=flow_query('p21_session_export_verify_query',fields={'ga_export_session_id':'p24-sql-session','ga_archive_attempt_id':a2['attempt_id'],'ga_archive_result':result})
    assert len(registered.encode())<2048
    execute('USE '+db+';\n'+registered+registered+"\nCALL p24_assert((SELECT archive_status='verified' FROM v_session_archive_status),'actual >19 MB file metadata verifies archive');\nCALL p24_assert((SELECT COUNT(*) FROM session_exports WHERE export_kind='completed_archive')=2,'terminal results are replay idempotent and failed result retained');\nCALL p24_assert((SELECT archive_bytes>19090552 AND report_sha256 IS NOT NULL FROM session_exports WHERE status='verified'),'both file metadata are registered');",'actual >19 MB helper verification registered in MariaDB by compact SQL')
    execute('USE '+db+';\n'+prepare_sql+"\nCALL p24_assert((SELECT COUNT(*) FROM v_current_session)=0,'verified release permits a new fermentation');\nCALL p24_assert((SELECT COUNT(*) FROM session_lifecycle_events WHERE lifecycle='completed')=1,'retry/release did not add a completed event');\nCALL p24_assert((SELECT COUNT(*) FROM v_session_history WHERE archive_url IS NOT NULL AND report_url IS NOT NULL)=1,'history uses actual verified attempt paths');",'actual Gjør klar releases only after SQLite pair and HTML verification')
# Frozen ale configuration is exercised through the same Start transaction.
for version,temp,aa,amount,targets in [('s04-cool@1.0',18,74,120,[18,18,19,20,20,20,20]),('m42-cool@1.0',17,77,70,[17,17,18,19,20,20,20])]:
    vals={**variables,'session_id':'sql-'+version.split('@')[0],'template_version':version,'operation_id':'start-'+version.split('@')[0],'pitch_temperature_c':temp,'manual_temperature_c':temp,'cooler_setpoint_c':temp,'expected_attenuation_min':aa,'expected_attenuation_max':82,'yeast_amount_g':amount,'is_demo':1}
    source=(ROOT/'sql/start-session.sql').read_text();source=re.sub(r'SET @ga_([a-z0-9_]+)=\?;',lambda m:f'SET @ga_{m[1]}={literal(vals.get(m[1]))};',source);source=source[:source.index('SELECT s.*')]
    assertions="\nCALL p24_assert((SELECT COUNT(*) FROM session_process_criteria WHERE session_id="+literal(vals['session_id'])+" AND process_id='P8' AND role_id='required')=5,'ale cold-crash requirements frozen');\nCALL p24_assert((SELECT COUNT(*) FROM session_analysis_graph_series WHERE session_id="+literal(vals['session_id'])+" AND provisional_allowed<>0)=0,'ale analysis is measured-only');\n"
    for i,t in enumerate(targets,1):assertions+="CALL p24_assert((SELECT target_value="+str(t)+" FROM session_process_target_exact WHERE session_id="+literal(vals['session_id'])+" AND process_id='P"+str(i)+"' AND target_id='beer_temperature'),'ale temperature target frozen');\n"
    for field in ['diacetyl','acetaldehyde']:
        for param,value in [('maximum_value',0),('maximum_age_minutes',720)]:
            column='integer_value' if param=='maximum_age_minutes' else 'real_value'
            assertions+="CALL p24_assert((SELECT "+column+"="+str(value)+" FROM session_process_criterion_parameter_values WHERE session_id="+literal(vals['session_id'])+" AND process_id='P8' AND criterion_id='p8-"+field+"' AND parameter_id="+literal(param)+"),'fresh sensory control before crash');\n"
    assertions+="CALL p24_assert((SELECT real_value="+str(aa)+" FROM session_biological_criterion_parameter_values WHERE session_id="+literal(vals['session_id'])+" AND phase_id='B6' AND criterion_id='b6-attenuation' AND parameter_id='minimum_value'),'ale biological attenuation threshold');\n"
    execute('USE '+db+';\n'+source+assertions,'actual Start freezes '+version+' targets, final manual/sensory controls and analysis policies')
    execute('USE '+db+';\nINSERT INTO session_release_events(release_event_id,session_id,released_at,operation_id,created_at) VALUES ('+literal('test-release-'+vals['session_id'])+','+literal(vals['session_id'])+",UTC_TIMESTAMP(3),"+literal('fixture-release-'+vals['session_id'])+",UTC_TIMESTAMP(3));",'release isolated demo fixture')
# The shipped editor's complete draft-save SQL must retain the endpoint
# model and its declared window row as well as normalized parameter values.
fixture_source=(ROOT/'tests/test-runtime-functions.js').read_text()
a=fixture_source.index('const templateDraft=');b=fixture_source.index('\n};',a)+3
editor_doc=json.loads(subprocess.run(['node','-e',fixture_source[a:b]+';process.stdout.write(JSON.stringify(templateDraft));'],text=True,capture_output=True,check=True).stdout)
editor_sql=flow_query('p20_template_save_query',{'event':{'data':{'document':editor_doc,'publish':False}}})
execute('USE '+db+";\nCALL ga_clone_template_tx('w3470-standard@3.0','unit-template@draft','unit-template','Unit template');\n"+editor_sql+"\nCALL p24_assert((SELECT model_id='endpoint_rate_v1' AND window_hours=24 AND minimum_samples=12 FROM template_biology_calculation_linear_regression WHERE version_id='unit-template@draft' AND calculation_id='sg_rate'),'editor retains endpoint window row');",'actual editor draft-save retains endpoint model/window configuration')
print('RESULT: PASS – actual MariaDB 12.3.3 SQL integration, revision-aware manual AA, >19 MB file metadata, failure/retry/release and ale freeze; target HA/Node-RED UAT remains separate')


# p24r7: install and exercise both DB-selected fixtures unchanged, then hourly
# statistics and comparison against the real frozen session read-model.
def r7_start(sid,is_demo,og=1.05):
    vals={**variables,'session_id':sid,'operation_id':'start-'+sid,'is_demo':is_demo,'og':og,'measured_sg':og,'corrected_sg':og}
    source=(ROOT/'sql/start-session.sql').read_text()
    source=re.sub(r'SET @ga_([a-z0-9_]+)=\?;',lambda m:f'SET @ga_{m[1]}={literal(vals.get(m[1]))};',source)
    execute('USE '+db+';\n'+source[:source.index('SELECT s.*')], 'r7 actual Start '+sid)
def r7_release_fixture(sid):
    execute('USE '+db+f";\nINSERT INTO session_release_events(release_event_id,session_id,released_at,operation_id,created_at) VALUES('release-{sid}','{sid}',UTC_TIMESTAMP(3),'release-{sid}',UTC_TIMESTAMP(3));", 'release isolated r7 fixture '+sid)
for profile,count,og,sid in [('tilt-pro-blue-20260925',691,1.0463,'r7-ipl'),('gyllen-pils-20260925',2924,1.048,'r7-gyllen')]:
    execute('USE '+db+';\n'+flow_query('p24r7_selection_write',{'data':{'profile_id':profile,'operation_id':'choose-'+sid}})+flow_query('p20_demo_prepare_query'), 'persist demo choice and actual preparation '+profile)
    r7_start(sid,1,og)
    execute('USE '+db+';\n'+flow_query('p20_demo_seed_query',fields={'ga_session_id':sid})+f"\nCALL p24_assert((SELECT COUNT(*) FROM measurements_5m WHERE session_id='{sid}')={count},'correct fixture count');\nCALL p24_assert((SELECT COUNT(*) FROM session_demo_sources WHERE session_id='{sid}' AND profile_id='{profile}')=1,'frozen demo identity');\nCALL p24_assert((SELECT COUNT(*) FROM measurements_5m m JOIN demo_reference_measurements_5m d ON d.profile_id='{profile}' AND d.offset_seconds=TIMESTAMPDIFF(SECOND,(SELECT pitched_at FROM v_all_session WHERE session_id='{sid}'),m.bucket_at) WHERE m.session_id='{sid}' AND (m.sg_median<>d.sg_median OR m.sg_mean<>d.sg_mean OR m.temperature_mean_c<>d.temperature_mean_c))=0,'fixture values unchanged');", 'r7 seed '+profile+' with exact original values')
    r7_release_fixture(sid)
r7_start('r7-hourly',0)
anchor=datetime.datetime(2026,10,1,tzinfo=datetime.timezone.utc)
hourly=[]
for i in range(73):
    if i==36:continue
    at=anchor+datetime.timedelta(hours=i);sg=1.05-i*.0001
    hourly.append(dict(start=at.strftime('%Y-%m-%d %H:%M:%S.000'),end=(at+datetime.timedelta(hours=1)).strftime('%Y-%m-%d %H:%M:%S.000'),sg_min=sg-.0001,sg_mean=sg,sg_max=sg+.0001,temperature_min=11,temperature_mean=12,temperature_max=13,rssi_min=-80,rssi_mean=-70,rssi_max=-60))
job=dict(rows=[],hourly=hourly,quality=[],gap_inserts=[],gap_closes=[],partial_count=0)
ingest=f"CALL ga_store_ingest_tx('r7-hourly','2026-10-04 01:00:00',300,NULL,{literal(json.dumps(job))});\n"
execute('USE '+db+';\n'+ingest+ingest+"CALL p24_assert((SELECT COUNT(*) FROM measurement_statistics_hourly WHERE session_id='r7-hourly')=72,'idempotent hourly imports');\nCALL p24_assert((SELECT COUNT(*) FROM measurements_5m WHERE session_id='r7-hourly')=0,'no fabricated five-minute data');\nCALL p24_assert((SELECT COUNT(*) FROM v_session_measurement_series WHERE session_id='r7-hourly' AND (sample_count IS NOT NULL OR sg_median IS NOT NULL))=0,'hourly data has no invented median or count');\nCALL p24_assert((SELECT COUNT(*) FROM v_session_hourly_analysis_values WHERE session_id='r7-hourly')>100,'real hourly AA rate and stability available');\nCALL p24_assert((SELECT COUNT(*) FROM v_session_measurement_segments WHERE session_id='r7-hourly' AND segment_id=1)>0,'missing hour breaks the line');", 'hourly imports/replay, actual means and a missing-hour segment')
execute('USE '+db+";\nCALL p24_assert((SELECT COUNT(*) FROM v_session_hourly_analysis_values v JOIN session_analysis_graph_series d ON d.session_id=v.session_id AND d.graph_id=v.graph_id AND d.series_id=v.series_id WHERE v.session_id='r7-hourly' AND d.metric_id='sg_rate_points_per_day' AND ABS(v.actual_value-2.4)<0.00001)>0,'hourly endpoint rate is exact');\nCALL p24_assert((SELECT COUNT(*) FROM v_session_hourly_analysis_values v JOIN session_analysis_graph_series d ON d.session_id=v.session_id AND d.graph_id=v.graph_id AND d.series_id=v.series_id WHERE v.session_id='r7-hourly' AND d.metric_id='sg_stability_24h_points' AND ABS(v.actual_value-2.4)<0.00001)>0,'hourly 24h range is exact');", 'hourly analysis preserves endpoint/range calculations')
# A failure after measurements have been inserted must roll the whole import back.
failjob={**job,'rows':[dict(bt='2026-10-05 00:00:00.000',count=3,sgmin=1.01,sgmean=1.01,sgmedian=1.01,sgmax=1.01,tempmin=12,temp=12,tempmax=12)],'hourly':[dict(start='2026-10-05 00:00:00.000',end='2026-10-05 01:00:00.000',sg_min=1.01,sg_mean=1.01,sg_max=1.01)]}
execute('USE '+db+f";\nDELIMITER //\nCREATE TRIGGER r7_fail_hourly BEFORE INSERT ON measurement_statistics_hourly FOR EACH ROW BEGIN IF NEW.start_at='2026-10-05 00:00:00' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Injected import failure'; END IF; END//\nCREATE PROCEDURE r7_import_rollback() BEGIN DECLARE failed INT DEFAULT 0; DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET failed=1; CALL ga_store_ingest_tx('r7-hourly','2026-10-05 01:00:00',300,NULL,{literal(json.dumps(failjob))}); IF failed<>1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Failure expected'; END IF; END//\nDELIMITER ;\nCALL r7_import_rollback();DROP TRIGGER r7_fail_hourly;\nCALL p24_assert((SELECT COUNT(*) FROM measurements_5m WHERE session_id='r7-hourly')=0,'import rollback removed partial rows');\nCALL p24_assert((SELECT last_import_cutoff_at='2026-10-04 01:00:00' FROM session_measurement_sources WHERE session_id='r7-hourly'),'rollback retains import cursor');", 'ingestion transaction rollback with an injected later failure')
choice={'source_kind':'reference','reference_id':'gyllen-pils-20260925','interval_seconds':900,'window_hours':None,'operation_id':'r7-compare'}
execute('USE '+db+';\n'+flow_query('p24r7_selection_write',{'data':choice})+"CALL p24_assert((SELECT COUNT(*) FROM v_graph_reference_measurement_series)=2924,'complete comparison dataset');\nCALL p24_assert((SELECT COUNT(*) FROM v_graph_reference_analysis_series WHERE actual_value IS NOT NULL)>6000,'comparison uses its own compiled analysis');\nCALL p24_assert((SELECT MIN(bucket_at) FROM v_graph_reference_measurement_series)=(SELECT pitched_at FROM v_active_session),'comparison pitch alignment');\nSELECT * FROM v_dashboard_analysis_series;SELECT * FROM v_dashboard_analysis_latest;", 'persistent comparison selector, elapsed alignment and independent analysis')
r8_halfhour={**choice,'interval_seconds':1800,'operation_id':'r8-half-hour-display'}
execute('USE '+db+';\nSET @r8_points_15=(SELECT COUNT(*) FROM v_dashboard_analysis_series);\n'+flow_query('p24r7_selection_write',r8_halfhour)+"CALL p24_assert((SELECT COUNT(*) FROM v_dashboard_analysis_series)<=@r8_points_15,'half-hour presentation does not increase points');\nCALL p24_assert((SELECT COUNT(*) FROM measurement_statistics_hourly WHERE session_id='r7-hourly')=72,'presentation retains all hourly authority');\n"+flow_query('p24r7_selection_write',{**choice,'operation_id':'r8-restore-display'}), 'r8 half-hour display and unchanged source data')
for query in ['p20_overview_query','p22_active_report_query','p23_measurement_export_query']:
    execute('USE '+db+';\n'+flow_query(query), 'r7 actual '+query+' with hourly primary and detailed comparison')
# Many checks may finish in one second; full results are atomic and IDs unique.
checksjson=json_read("(SELECT JSON_ARRAYAGG(JSON_OBJECT('id',check_id,'status','ok','severity','info','summary','r7 check')) FROM system_check_definitions WHERE enabled=1)", 'r7 complete check fixture')
execute('USE '+db+';\n'+''.join('CALL ga_store_system_check_tx(\'ok\','+literal(json.dumps(checksjson))+');\n' for _ in range(10))+"CALL p24_assert((SELECT COUNT(*) FROM system_check_runs WHERE overall_status='ok')>=10,'unique rapid check runs');\nCALL p24_assert((SELECT COUNT(*) FROM system_check_runs r WHERE (SELECT COUNT(*) FROM system_check_results c WHERE c.check_run_id=r.check_run_id)<>15)=0,'every run has all results');", 'rapid unique atomic Systemkontroll runs')
execute('USE '+db+f";\nSET @r7_checks={literal(json.dumps(checksjson))};\nDELIMITER //\nCREATE TRIGGER r7_fail_check BEFORE INSERT ON system_check_results FOR EACH ROW BEGIN IF NEW.check_order=3 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Injected check failure'; END IF; END//\nCREATE PROCEDURE r7_check_rollback() BEGIN DECLARE failed INT DEFAULT 0; DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET failed=1; CALL ga_store_system_check_tx('ok',@r7_checks); IF failed<>1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Failure expected'; END IF; END//\nDELIMITER ;\nSET @before=(SELECT COUNT(*) FROM system_check_runs);CALL r7_check_rollback();DROP TRIGGER r7_fail_check;CALL p24_assert((SELECT COUNT(*) FROM system_check_runs)=@before,'check rollback removes partial run');", 'Systemkontroll rollback with an injected middle-result failure')
execute('USE '+db+";\nINSERT INTO technical_events(event_id,schema_version,occurred_at,severity,event_type,code,issue_key,subsystem,message,recoverable,blocks_operation,created_at) VALUES('z-r7-raise','1.0','2026-10-01','error','issue_raised','R7','r7-same-time','test','Raised',1,0,'2026-10-01'),('a-r7-clear','1.0','2026-10-01','info','issue_cleared','R7','r7-same-time','test','Cleared',1,0,'2026-10-01');\nCALL p24_assert((SELECT COUNT(*) FROM v_active_technical_issues WHERE issue_key='r7-same-time')=0,'event sequence orders equal timestamps');", 'technical recovery ordering with identical timestamps')
short_choice={**choice,'window_hours':24,'operation_id':'r7-short-window'}
execute('USE '+db+';\n'+flow_query('p24r7_selection_write',{'data':short_choice})+"CALL p24_assert((SELECT x_axis_started_at FROM v_report_graph_time_axis WHERE session_id='r7-hourly')=(SELECT pitched_at FROM v_active_session),'report remains full session');\nCALL p24_assert((SELECT x_axis_started_at FROM v_session_graph_time_axis WHERE session_id='r7-hourly')>(SELECT pitched_at FROM v_active_session),'dashboard uses selected window');CALL p24_assert((SELECT COUNT(*) FROM v_graph_definitions WHERE session_id='r7-hourly' AND render_scope='report' AND x_axis_started_at=(SELECT pitched_at FROM v_active_session))=6,'shared renderer report remains full session');CALL p24_assert((SELECT COUNT(*) FROM v_graph_time_markers WHERE session_id='r7-hourly' AND render_scope='report' AND marker_at<(SELECT x_axis_started_at FROM v_session_graph_time_axis WHERE session_id='r7-hourly'))>0,'shared report keeps earlier dates');", 'report time range independent of dashboard selection')
execute('USE '+db+';\n'+flow_query('p21_session_end_context_result',[[{'session_id':'r7-hourly','lifecycle':'active','ended_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'recorded_now':datetime.datetime.now(datetime.timezone.utc).isoformat()}]])+flow_query('p21_session_export_query',fields={'ga_export_session_id':'r7-hourly'})+"CALL p24_assert((SELECT COUNT(*) FROM v_report_analysis_series WHERE session_id='r7-hourly' AND actual_value IS NOT NULL)>100,'completed report retains hourly analysis');", 'actual completed archive/report SQL with hourly source and full chronology')
print('PASS prior data/lifecycle/statistics/comparison/atomic regressions',flush=True)

# r8: the installed schema and actual HA command receiver accept 30 minutes.
# Systemkontroll's current epoch must work when MariaDB uses Oslo summer time.
execute('USE '+db+";\nSET time_zone='+02:00';\nCALL p24_assert(ABS(UNIX_TIMESTAMP()-UNIX_TIMESTAMP(UTC_TIMESTAMP(3))) BETWEEN 7198 AND 7201,'old clock expression reproduces false offset');\nSET time_zone='+00:00';\nCALL p24_assert((SELECT expected_number=207 FROM system_check_expectations WHERE check_id='schema' AND expectation_key='innodb_tables'),'all InnoDB expectations updated');\nCALL p24_assert((SELECT COUNT(*) FROM v_dashboard_graph_view_options WHERE option_kind='interval' AND value_number=1800)=1,'30 minute option is DB owned');", 'r8 clock and schema expectation regressions')
r8_choice={'source_kind':'reference','reference_id':'gyllen-pils-20260925','interval_seconds':1800,'window_hours':None,'operation_id':'r8-direct-choice'}
execute('USE '+db+';\n'+flow_query('p24r7_selection_write',r8_choice)+"CALL p24_assert((SELECT interval_seconds=1800 AND operation_id='r8-direct-choice' FROM v_graph_display_selection),'actual direct HA command persisted');\n", 'r8 direct event data persist shared 30-minute choice')
execute('USE '+db+';\n'+flow_query('p20_technical_export_query'), 'r8 actual technical diagnostic query')


epoch_expression=re.search(r'(UNIX_TIMESTAMP\([^;\n]*?) AS database_epoch',flow_query('p20_systemcheck_query'))[1]
execute('USE '+db+";\nSET time_zone='+02:00';\nCALL p24_assert(ABS("+epoch_expression+"-UNIX_TIMESTAMP())<2,'actual clock expression is independent of Oslo offset');\n", 'r8 actual Systemkontroll clock expression in Oslo timezone')

(ROOT/'verification/p24r9-data-regression.json').write_text(json.dumps({'application_version':(ROOT/'VERSION').read_text().strip(),'server_version':version_text,'result':'pass','checks':['691 unchanged legacy reference points','2924 Gyllen pils points','frozen dataset identity','72 hourly records with missing hour','no fabricated raw/median/count','exact hourly endpoint and range','atomic import rollback','comparison elapsed alignment and own analysis','actual overview/report/CSV queries','10 rapid unique complete system checks','atomic check rollback','30-minute display without raw data loss','direct HA selection command','all 202 InnoDB expectations','Oslo epoch regression and actual clock expression','actual expanded technical diagnostic query']},ensure_ascii=False,indent=2)+'\n')
print('RESULT: PASS – r8 native MariaDB data/lifecycle/statistics/comparison/diagnostics/clock checks',flush=True)

# r9 regressions: real command envelopes, DB import policy/recovery, and
# current criterion parameters/markers. All fixtures are isolated test facts.
r7_release_fixture('r7-hourly')
r7_start('r9-criteria',0)
for i,wrap in enumerate([lambda c:c,lambda c:{'data':c},lambda c:{'event':c},lambda c:{'event':{'data':c}}]):
    command={**r8_choice,'operation_id':'r9-choice-'+str(i)}
    execute('USE '+db+';\n'+flow_query('p24r7_selection_write',wrap(command))+"CALL p24_assert((SELECT operation_id="+literal(command['operation_id'])+" FROM v_graph_display_selection),'event envelope is persisted');\n"+flow_query('p24r7_selection_write',wrap({'profile_id':'gyllen-pils-20260925','operation_id':'r9-demo-'+str(i)}))+"CALL p24_assert((SELECT operation_id="+literal('r9-demo-'+str(i))+" FROM v_demo_profile_selection),'demo envelope is persisted');",'r9 graph/demo event envelope '+str(i))
# Use the actual shipped context SELECT to test DB decisions, not a copied CASE.
context_select=flow_query('p21_live_ingest_context_query').split(';')[0]
for seconds,needed in [(300,0),(3599,0),(3600,1),(86400,1)]:
    execute('USE '+db+f";\nUPDATE session_measurement_sources SET last_success_at=UTC_TIMESTAMP(3),last_import_cutoff_at=DATE_SUB(UTC_TIMESTAMP(3),INTERVAL {seconds} SECOND) WHERE session_id='r9-criteria';\nCALL p24_assert((SELECT statistics_required FROM ({context_select}) actual_context)={needed},'statistics policy from actual SQL');",'r9 actual DB statistics decision after '+str(seconds)+' seconds')
execute('USE '+db+";\nUPDATE session_measurement_sources SET last_success_at=NULL WHERE session_id='r9-criteria';\nCALL p24_assert((SELECT statistics_required FROM ("+context_select+") actual_context)=1,'initial history needs statistics');",'r9 initial statistics decision')
recovered={'severity':'info','event_type':'issue_cleared','code':'HA_STATISTICS_RECOVERED','issue_key':'ha-statistics','subsystem':'measurement_source','message':'HA langtidsstatistikk er tilgjengelig igjen','recoverable':1,'blocks_operation':0}
warning={**recovered,'severity':'warning','event_type':'issue_raised','code':'HA_STATISTICS_UNAVAILABLE','message':'Injected statistics failure'}
execute('USE '+db+';\nSET @before=(SELECT COUNT(*) FROM technical_events WHERE code=\'HA_STATISTICS_RECOVERED\');\n'+flow_query('p20_technical_event_writer',fields={'ga_event':recovered})+"CALL p24_assert((SELECT COUNT(*) FROM technical_events WHERE code='HA_STATISTICS_RECOVERED')=@before,'healthy API produces no recovery spam');\n"+flow_query('p20_technical_event_writer',fields={'ga_event':warning})+"UPDATE session_measurement_sources SET last_success_at=UTC_TIMESTAMP(3),last_import_cutoff_at=DATE_SUB(UTC_TIMESTAMP(3),INTERVAL 300 SECOND) WHERE session_id='r9-criteria';\nCALL p24_assert((SELECT statistics_required FROM ("+context_select+") actual_context)=1,'unresolved API failure schedules historical retry');\nCALL p24_assert((SELECT statistics_started_at=source_started_at FROM ("+context_select+") actual_context),'retry repairs earlier history');\n"+flow_query('p20_technical_event_writer',fields={'ga_event':recovered})+flow_query('p20_technical_event_writer',fields={'ga_event':recovered})+"CALL p24_assert((SELECT COUNT(*) FROM technical_events WHERE code='HA_STATISTICS_RECOVERED')=@before+1,'one actual recovery is stored');\nCALL p24_assert((SELECT COUNT(*) FROM v_active_technical_issues WHERE issue_key='ha-statistics')=0,'recovery closes issue');\n",'r9 actual warning/recovery transaction and no healthy-success spam')

def read_rows(table,cols,where,label):
    return json_read('(SELECT COALESCE(JSON_ARRAYAGG(JSON_OBJECT('+','.join(literal(c)+','+c for c in cols)+')),JSON_ARRAY()) FROM '+table+' WHERE '+where+')',label)
# W-34/70 process thresholds describe phase order and have no default metric
# graph. Bind one to a direct criterion series in the isolated fixture so the
# process_criterion branch is tested as well as metric-bound requirements.
columns=json_read("(SELECT JSON_ARRAYAGG(column_name ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='session_analysis_graph_series')",'r9 fixture series columns')
changes={'series_id':literal('r9-process-threshold'),'sort_order':'1000','source_kind':literal('process_criterion'),'metric_id':'NULL','owner_id':literal('P3'),'criterion_id':literal('p3-biological-phase')}
execute('USE '+db+';\nINSERT INTO session_analysis_graph_series('+','.join(columns)+') SELECT '+','.join(changes.get(c,'x.'+c) for c in columns)+" FROM session_analysis_graph_series x WHERE x.session_id='r9-criteria' AND x.graph_id='sg-rate' LIMIT 1;",'r9 isolated direct process criterion graph binding')
criterion_evidence=[]
for scope,kind,owner in [('bio','biological','phase_id'),('process','process','process_id')]:
    c=json_read("(SELECT JSON_OBJECT('session_id',c.session_id,'"+owner+"',c."+owner+",'criterion_id',c.criterion_id,'model_id',c.model_id) FROM session_"+kind+"_criteria c WHERE c.session_id='r9-criteria' AND c.model_id='threshold' AND EXISTS(SELECT 1 FROM v_session_analysis_requirements q WHERE q.session_id=c.session_id AND q.owner_type="+literal('biology' if scope=='bio' else 'process')+" AND q.owner_id=c."+owner+" AND q.criterion_id=c.criterion_id AND q.minimum_value IS NOT NULL) LIMIT 1)",'r9 read graph-bound '+scope+' threshold')
    where="session_id='r9-criteria' AND "+owner+'='+literal(c[owner])+' AND criterion_id='+literal(c['criterion_id'])
    base=read_rows('session_'+kind+'_criterion_parameter_values',['parameter_id','data_type','real_value','integer_value','boolean_value','text_value'],where,'r9 read frozen '+scope+' parameters')
    allowed=json_read('(SELECT JSON_ARRAYAGG(JSON_OBJECT(\'parameter_id\',p.parameter_id,\'data_type\',m.data_type)) FROM session_'+kind+'_correctable_parameters p JOIN criterion_model_parameters m ON m.model_id=p.model_id AND m.parameter_id=p.parameter_id WHERE p.'+where+')','r9 read frozen correction policy '+scope)
    reqwhere="session_id='r9-criteria' AND owner_type="+literal('biology' if scope=='bio' else 'process')+' AND owner_id='+literal(c[owner])+' AND criterion_id='+literal(c['criterion_id'])
    reqcols=['graph_id','owner_type','owner_id','criterion_id','minimum_value','maximum_value','met_at','owner_display','requirement_display']
    original=read_rows('v_session_analysis_requirements',reqcols,reqwhere,'r9 original graph requirements '+scope)
    minimum=float(original[0]['minimum_value'])+0.25
    def revision(action,parameters,seq):
        current=read_rows('v_current_'+kind+'_criterion_revision',['criterion_revision_id','revision_no','action'],where,'r9 read correction head '+scope)
        sets=[[{'_set':'criterion',**c}],[{'_set':'allowed',**p} for p in allowed],[{'_set':'base_params',**p} for p in base],[{'_set':'current',**p} for p in current]]
        op='r9-'+scope+'-'+str(seq)
        execute('USE '+db+';\n'+flow_query('p20_'+scope+'_criterion_correction_context_result',sets,{'ga_correction_request':{'action':action,'parameters':parameters,'operation_id':op}}),'r9 real '+scope+' '+action+' transaction '+str(seq))
        return json_read('(SELECT JSON_QUOTE(criterion_revision_id) FROM v_current_'+kind+'_criterion_revision WHERE '+where+')','r9 read persisted revision id '+scope)
    def met_fact(rev,seq):
        eid='r9-met-'+scope+'-'+str(seq);at='2026-10-10 01:00:0'+str(seq)
        if scope=='bio':
            ev="INSERT INTO biological_evaluations(evaluation_id,session_id,candidate_phase_id,evaluated_at,outcome,engine_version,created_at) VALUES ("+literal(eid)+",'r9-criteria',"+literal(c[owner])+','+literal(at)+",'met','r9-fixture',UTC_TIMESTAMP(3));"
            ownercol='phase_id'
        else:
            ev="INSERT INTO process_evaluations(evaluation_id,session_id,current_process_id,candidate_process_id,evaluated_at,readiness,engine_version,created_at) VALUES ("+literal(eid)+",'r9-criteria','P1',"+literal(c[owner])+','+literal(at)+",'ready','r9-fixture',UTC_TIMESTAMP(3));"
            ownercol='candidate_process_id'
        ev+='INSERT INTO '+kind+'_evaluation_criteria(evaluation_id,session_id,'+ownercol+',criterion_id,criterion_revision_id,criterion_order,role_id,metric_id,model_id,met,valid,evaluation_status,created_at) SELECT '+literal(eid)+',session_id,'+owner+',criterion_id,'+literal(rev)+",criterion_order,role_id,metric_id,model_id,1,1,'met',UTC_TIMESTAMP(3) FROM session_"+kind+'_criteria WHERE '+where+';'
        execute('USE '+db+';\n'+ev,'r9 append explicit '+scope+' met evidence '+str(seq))
    met_fact(None,0)
    rev=revision('override',{'minimum_value':minimum,'maximum_value':minimum+5},1)
    execute('USE '+db+';\nCALL p24_assert((SELECT COUNT(*) FROM v_session_analysis_requirements WHERE '+reqwhere+f' AND minimum_value={minimum} AND maximum_value={minimum+5} AND met_at IS NULL)='+str(len(original)) +",'override thresholds replace graph requirements and old met');",'r9 effective bound addition and obsolete marker '+scope)
    met_fact(rev,1)
    changed=read_rows('v_session_analysis_requirements',reqcols,reqwhere,'r9 current graph/report requirements '+scope)
    assert all(x['met_at']=='2026-10-10 01:00:01.000000' or str(x['met_at']).startswith('2026-10-10 01:00:01') for x in changed),changed
    criterion_evidence.extend(changed)
    revision('override',{'minimum_value':minimum+1,'maximum_value':None},2)
    execute('USE '+db+';\nCALL p24_assert((SELECT COUNT(*) FROM v_session_analysis_requirements WHERE '+reqwhere+f' AND minimum_value={minimum+1} AND maximum_value IS NULL AND met_at IS NULL)='+str(len(original))+",'explicit unset is not zero or base fallback');",'r9 explicit unset bound '+scope)
    reset=revision('reset',{},3)
    restored=read_rows('v_session_analysis_requirements',reqcols,reqwhere,'r9 reset graph requirements '+scope)
    for a,b in zip(original,restored):
        assert (a['minimum_value'],a['maximum_value'])==(b['minimum_value'],b['maximum_value']) and b['met_at'] is None,(a,b)
    met_fact(reset,3)
    execute('USE '+db+';\nCALL p24_assert((SELECT COUNT(*) FROM v_session_analysis_requirements WHERE '+reqwhere+" AND met_at='2026-10-10 01:00:03')="+str(len(original))+",'reset uses its own evaluation evidence');",'r9 reset marker revision '+scope)
    assert read_rows('session_'+kind+'_criterion_parameter_values',['parameter_id','data_type','real_value','integer_value','boolean_value','text_value'],where,'r9 unchanged frozen '+scope+' parameters')==base
# Distinct metric-only fixture graphs prove window association; the product's
# combined stability graph deliberately includes both 24- and 48-hour curves.
for table in ['session_analysis_graphs','session_analysis_graph_series']:
    columns=json_read("(SELECT JSON_ARRAYAGG(column_name ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name="+literal(table)+')','r9 read frozen graph columns '+table)
    for window in [24,48]:
        gid='r9-window-'+str(window)
        values=','.join(literal(gid) if c=='graph_id' else str(1000+window) if c=='sort_order' and table=='session_analysis_graphs' else 'x.'+c for c in columns)
        extra=" AND x.source_kind='metric' AND EXISTS(SELECT 1 FROM session_metric_runtime_parameter_values mp WHERE mp.session_id=x.session_id AND mp.metric_id=x.metric_id AND mp.parameter_id='window_hours' AND mp.real_value="+str(window)+')' if table.endswith('_series') else ''
        execute('USE '+db+';\nINSERT INTO '+table+'('+','.join(columns)+') SELECT '+values+' FROM '+table+" x WHERE x.session_id='r9-criteria' AND x.graph_id='sg-stability'"+extra+';','r9 isolated '+str(window)+'-hour graph fixture '+table)
for scope,kind,owner in [('bio','biological','phase_id'),('process','process','process_id')]:
    c=json_read("(SELECT JSON_OBJECT('session_id',c.session_id,'"+owner+"',c."+owner+",'criterion_id',c.criterion_id,'model_id',c.model_id) FROM session_"+kind+"_criteria c JOIN session_"+kind+"_criterion_parameter_values p ON p.session_id=c.session_id AND p."+owner+'=c.'+owner+" AND p.criterion_id=c.criterion_id WHERE c.session_id='r9-criteria' AND c.model_id='stability_window' AND p.parameter_id='window_hours' AND p.real_value IN (24,48) LIMIT 1)",'r9 read '+scope+' 24-hour stability criterion')
    assert c, 'Missing frozen stability criterion '+scope
    where="session_id='r9-criteria' AND "+owner+'='+literal(c[owner])+' AND criterion_id='+literal(c['criterion_id'])
    base=read_rows('session_'+kind+'_criterion_parameter_values',['parameter_id','data_type','real_value','integer_value','boolean_value','text_value'],where,'r9 stability frozen '+scope)
    allowed=json_read('(SELECT JSON_ARRAYAGG(JSON_OBJECT(\'parameter_id\',p.parameter_id,\'data_type\',m.data_type)) FROM session_'+kind+'_correctable_parameters p JOIN criterion_model_parameters m ON m.model_id=p.model_id AND m.parameter_id=p.parameter_id WHERE p.'+where+')','r9 stability correction policy '+scope)
    reqwhere="session_id='r9-criteria' AND owner_type="+literal('biology' if scope=='bio' else 'process')+' AND owner_id='+literal(c[owner])+' AND criterion_id='+literal(c['criterion_id'])
    original_window=int(next(p['real_value'] for p in base if p['parameter_id']=='window_hours'));new_window=48 if original_window==24 else 24
    execute('USE '+db+';\nCALL p24_assert((SELECT COUNT(*) FROM v_session_analysis_requirements WHERE '+reqwhere+" AND graph_id='r9-window-"+str(original_window)+"')=1,'original window matches');\nCALL p24_assert((SELECT COUNT(*) FROM v_session_analysis_requirements WHERE "+reqwhere+" AND graph_id='r9-window-"+str(new_window)+"')=0,'original window does not match other');",'r9 original stability window association '+scope)
    revision('override',{'window_hours':new_window},4)
    execute('USE '+db+';\nCALL p24_assert((SELECT COUNT(*) FROM v_session_analysis_requirements WHERE '+reqwhere+" AND graph_id='r9-window-"+str(original_window)+"')=0,'corrected window leaves original');\nCALL p24_assert((SELECT COUNT(*) FROM v_session_analysis_requirements WHERE "+reqwhere+" AND graph_id='r9-window-"+str(new_window)+"')=1,'corrected window matches new');",'r9 effective stability window association '+scope)
    revision('reset',{},5)
    execute('USE '+db+';\nCALL p24_assert((SELECT COUNT(*) FROM v_session_analysis_requirements WHERE '+reqwhere+" AND graph_id='r9-window-"+str(original_window)+"')=1,'reset restores original window');",'r9 reset stability window association '+scope)

# Capture actual DB graph selections/comparison and corrected requirement labels
# for a separate frontend/shared-report regression using the shipped renderer.
selection=json_read("(SELECT JSON_OBJECT('source_kind',source_kind,'reference_profile_id',reference_profile_id,'interval_seconds',interval_seconds,'window_hours',window_hours,'operation_id',operation_id,'selection_seq',selection_seq) FROM v_graph_display_selection)",'r9 actual published selection values')
comparison=read_rows('v_graph_reference_measurement_series',['bucket_at','sg_median','temperature_mean_c','source_display'],'1=1','r9 actual comparison read-model')
assert comparison, 'DB comparison must contain real reference points'
(ROOT/'verification/p24r9-runtime-regression.json').write_text(json.dumps({'application_version':(ROOT/'VERSION').read_text().strip(),'server_version':version_text,'status':'pass','graph_selection':selection,'comparison_points':len(comparison),'comparison_example':comparison[:3],'corrected_requirements':criterion_evidence,'checks':['four command envelopes through actual SQL','initial/live/catchup decisions from actual DB query','failure retry and one real recovery','bio/process override/add optional bound/unset/reset','current revision met markers','unchanged frozen parameters','24/48-hour association follows override and reset']},ensure_ascii=False,indent=2)+'\n')
print('RESULT: PASS – r9 native event/import/current-criterion regressions',flush=True)
