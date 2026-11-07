#!/usr/bin/env python3
from pathlib import Path
import json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as d:
    d=Path(d)
    current=d/'current.json'; output=d/'out.json'
    current.write_text(json.dumps([
      {'id':'mysql-tested','type':'MySQLdatabase','name':'Gjæringsassistent MariaDB','host':'gjaeringsassistent-mariadb','port':'3306','db':'gjaeringsassistent'},
      {'id':'ha-tested','type':'server','name':'Home Assistant – Gjæringsassistent','version':6,'addon':False,'wires':[]},
      {'id':'old-ga-node','type':'ha-sensor','name':'Gjæringsassistent old','server':'ha-tested','wires':[]}
    ]),encoding='utf-8')
    r=subprocess.run(['python3',str(ROOT/'installer/build-installed-flow.py'),'--template',str(ROOT/'nodered/flows.template.json'),'--current',str(current),'--output',str(output)],capture_output=True,text=True)
    assert r.returncode==0,r.stderr
    meta=json.loads(r.stdout)
    nodes=json.loads(output.read_text(encoding='utf-8'))
    assert meta['mysql_config_id']=='mysql-tested'
    assert meta['ha_server_id']=='ha-tested'
    assert len([n for n in nodes if n.get('type')=='mysql'])==1
    assert next(n for n in nodes if n.get('type')=='mysql')['mydb']=='mysql-tested'
    assert {n.get('server') for n in nodes if n.get('server')}=={'ha-tested'}
    mysql_node=next(n for n in nodes if n.get('id')=='mysql-tested')
    assert mysql_node.get('tz')=='Z'
    assert meta.get('mysql_timezone')=='Z'
    assert mysql_node.get('charset')=='UTF8MB4_UNICODE_CI'
    assert meta.get('mysql_charset')=='UTF8MB4_UNICODE_CI'
    assert any(n.get('id')=='mysql-tested' for n in nodes)
    assert any(n.get('id')=='ha-tested' for n in nodes)
print('RESULT: PASS – tested config-node IDs are preserved and all references are patched')
