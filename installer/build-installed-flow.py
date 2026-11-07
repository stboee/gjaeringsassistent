#!/usr/bin/env python3
import argparse, json, pathlib, sys


def fail(msg):
    print(f"FEIL: {msg}", file=sys.stderr)
    raise SystemExit(2)


def load(path):
    try:
        return json.loads(pathlib.Path(path).read_text(encoding='utf-8'))
    except Exception as e:
        fail(f"kan ikke lese {path}: {e}")


def choose_mysql(nodes):
    candidates=[n for n in nodes if n.get('type')=='MySQLdatabase']
    if not candidates:
        fail("fant ingen eksisterende MySQLdatabase-konfigurasjonsnode. node-red-node-mysql må være konfigurert og testet først")
    preferred=[]
    for n in candidates:
        vals=' '.join(str(v) for v in n.values()).lower()
        if 'gjaeringsassistent-mariadb' in vals or 'gjaeringsassistent' in str(n.get('db','')).lower():
            preferred.append(n)
    if len(preferred)==1:
        return preferred[0]
    if len(candidates)==1:
        return candidates[0]
    fail("fant flere MySQLdatabase-konfigurasjoner og kunne ikke entydig velge Gjæringsassistent-MariaDB")


def choose_ha_server(nodes):
    servers=[n for n in nodes if n.get('type')=='server']
    exact=[n for n in servers if n.get('id')=='cfg_ha_gjaering_v1']
    if len(exact)==1:
        return exact[0]
    # Prefer a server already referenced by Gjæringsassistent HA nodes.
    refs=[]
    for n in nodes:
        if 'gjæringsassistent' in str(n.get('name','')).lower() or 'gjaeringsassistent' in str(n.get('name','')).lower():
            s=n.get('server')
            if s: refs.append(s)
    refset=set(refs)
    byref=[n for n in servers if n.get('id') in refset]
    if len(byref)==1:
        return byref[0]
    named=[n for n in servers if 'gjær' in str(n.get('name','')).lower() or 'gjaer' in str(n.get('name','')).lower()]
    if len(named)==1:
        return named[0]
    if len(servers)==1:
        return servers[0]
    fail("fant ikke entydig eksisterende Home Assistant server-konfigurasjon")


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--template', required=True)
    ap.add_argument('--current', required=True)
    ap.add_argument('--output', required=True)
    args=ap.parse_args()
    template=load(args.template)
    current=load(args.current)
    mysql_cfg=dict(choose_mysql(current))
    # Preserve config-node ID/credentials; explicitly declare time and string
    # semantics so server version defaults cannot change the SQL contract.
    mysql_cfg['tz']='Z'
    mysql_cfg['charset']='UTF8MB4_UNICODE_CI'
    ha_cfg=choose_ha_server(current)

    mysql_placeholder='cfg_mariadb_p20r1'
    ha_placeholder='cfg_ha_gjaering_v1'
    out=[]
    for n0 in template:
        n=dict(n0)
        if n.get('id') in (mysql_placeholder,ha_placeholder):
            continue
        # Patch only known config references, not arbitrary text.
        if n.get('mydb')==mysql_placeholder:
            n['mydb']=mysql_cfg['id']
        if n.get('server')==ha_placeholder:
            n['server']=ha_cfg['id']
        out.append(n)

    # Reuse the exact tested config objects so flows_cred.json remains valid.
    out.append(mysql_cfg)
    if ha_cfg['id'] != mysql_cfg['id']:
        out.append(ha_cfg)

    ids=[]
    for n in out:
        i=n.get('id')
        if not i: fail(f"node uten id: {n.get('type')}")
        ids.append(i)
    dup=sorted({i for i in ids if ids.count(i)>1})
    if dup: fail(f"dupliserte node-id-er etter patch: {dup}")
    idset=set(ids)
    missing=[]
    for n in out:
        for group in n.get('wires',[]) or []:
            for target in group:
                if target not in idset:
                    missing.append((n['id'],target))
    if missing: fail(f"wires peker på manglende noder: {missing[:10]}")

    # Contract checks for the p20r1 architecture.
    mysql_nodes=[n for n in out if n.get('type')=='mysql']
    if len(mysql_nodes)!=1: fail(f"forventet nøyaktig én mysql runtime-node, fant {len(mysql_nodes)}")
    if mysql_nodes[0].get('mydb')!=mysql_cfg['id']: fail("mysql runtime-node peker ikke på bevart MariaDB-config")
    if any('sqlite' in str(n.get('type','')).lower() for n in out): fail("SQLite-node finnes i p20r1-flow")
    text='\n'.join(str(n.get('func','')) for n in out if n.get('type')=='function')
    if 'flow.set(' in text or 'global.set(' in text: fail("domenestate skrives til flow/global context")

    pathlib.Path(args.output).write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({
      'mysql_config_id':mysql_cfg['id'],
      'mysql_config_name':mysql_cfg.get('name',''),
      'ha_server_id':ha_cfg['id'],
      'ha_server_name':ha_cfg.get('name',''),
      'node_count':len(out),
      'runtime_mysql_nodes':len(mysql_nodes),
      'mysql_timezone':mysql_cfg.get('tz'),
      'mysql_charset':mysql_cfg.get('charset')
    },ensure_ascii=False))

if __name__=='__main__': main()
