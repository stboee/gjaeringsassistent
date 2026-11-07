#!/usr/bin/env python3
from pathlib import Path
import json,re,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from system_metadata import load_system_metadata
meta=load_system_metadata(ROOT)
entities=meta['entities']; events=meta['events']
flow=json.loads((ROOT/'nodered/flows.template.json').read_text(encoding='utf-8'))
contract=json.loads((ROOT/'contracts/ha-node-red-contract.json').read_text(encoding='utf-8'))
dash=(ROOT/'dashboard/gjaeringsassistent-dashboard.yaml').read_text(encoding='utf-8')
card=(ROOT/'dashboard/gjaeringsassistent-card.js').read_text(encoding='utf-8')
by={n.get('id'):n for n in flow}; errs=[]
active=[e for e in entities if e.get('status')=='active']
if len(active)!=75: errs.append(f'MariaDB-register skal ha 75 aktive entiteter, fant {len(active)}')
if contract.get('normative') is not False or 'ha_entity_registry' not in contract.get('generated_from',''):
    errs.append('JSON-kontrakten skal være generert/ikke-normativ; MariaDB-registeret er autoritativt')
# Generated JSON artifact must mirror the DB registry exactly for core contract fields.
db_core={e['entity_id']:{k:e[k] for k in ['entity_id','config_id','entity_type','display_name','direction','status']} for e in entities}
json_core={e['entity_id']:{k:e[k] for k in ['entity_id','config_id','entity_type','display_name','direction','status']} for e in contract['entities']}
if db_core!=json_core: errs.append('generert JSON-kontrakt avviker fra MariaDB ha_entity_registry')
# Physical flow is implementation; validate it against metadata instead of reading metadata from the flow.
for e in active:
    cfg=by.get(e['config_id'])
    if not cfg: errs.append(f"mangler config-node {e['config_id']} for {e['entity_id']}"); continue
    if cfg.get('type')!='ha-entity-config': errs.append(f"{e['config_id']} er ikke ha-entity-config")
    if cfg.get('entityType')!=e['entity_type']: errs.append(f"{e['config_id']} type {cfg.get('entityType')} != DB {e['entity_type']}")
    name=next((x.get('value') for x in cfg.get('haConfig',[]) if x.get('property')=='name'),cfg.get('name'))
    if name!=e['display_name']: errs.append(f"{e['config_id']} navn {name!r} != DB {e['display_name']!r}")
    runtime=by.get(e['runtime_node_id'])
    if not runtime or runtime.get('entityConfig')!=e['config_id']: errs.append(f"runtime-node {e['runtime_node_id']} matcher ikke {e['entity_id']}")
    if e['entity_type']=='button':
        if e['bootstrap_mode']!='registration_only' or e['bootstrap_slot'] is not None or e['bootstrap_node_id'] is not None: errs.append(f"button bootstrap metadata ugyldig: {e['entity_id']}")
    else:
        b=by.get(e['bootstrap_node_id'])
        if not b or (e['bootstrap_mode']!='runtime' and b.get('entityConfig')!=e['config_id']): errs.append(f"bootstrap-node {e['bootstrap_node_id']} matcher ikke {e['entity_id']}")
        slot=e['bootstrap_slot']
        actual=by['p21_ha_bootstrap_dispatch']['wires'][slot-1]
        if actual!=[e['bootstrap_node_id']]: errs.append(f'bootstrap ledning avviker: {e["entity_id"]}')
slots=sorted(int(e['bootstrap_slot']) for e in active if e['entity_type']!='button')
if slots!=list(range(1,65)): errs.append('bootstrap_slot skal være sammenhengende 1..64')
# Dashboard may only use DB-registered active entities.
entity_re=r'(?:binary_sensor|button|number|select|sensor|text)\.gjaeringsassistent_[a-z0-9_]+'
refs=set(re.findall(entity_re,dash+'\n'+card)); allowed={e['entity_id'] for e in active}
unknown=sorted(refs-allowed)
if unknown: errs.append('dashboard/custom-card refererer entiteter uten aktiv DB-kontrakt: '+', '.join(unknown))
# Event contract is also MariaDB metadata; JSON is only the generated artifact.
db_events={e['event_type']:(e['direction'],e['event_mode'],e['listener_node_id']) for e in events if e['status']=='active'}
json_events={e['event_type']:(e['direction'],e['mode'],e['listener_id']) for e in contract.get('event_channels',[])}
if db_events!=json_events: errs.append('generert JSON event-kontrakt avviker fra MariaDB ha_event_registry')
for event,(_,_,listener) in db_events.items():
    n=by.get(listener)
    if not n or n.get('type')!='server-events' or n.get('eventType')!=event: errs.append(f'event {event} mangler forventet listener {listener}')
# Runtime Systemkontroll must read DB metadata, not contain an entity-id copy.
sysq=by.get('p20_systemcheck_query',{}).get('func',''); sysfn=by.get('p20_systemcheck_result',{}).get('func','')
if 'FROM ha_entity_registry' not in sysq or "r._set==='ha_registry'" not in sysfn: errs.append('Systemkontroll bruker ikke MariaDB HA-registeret')
if any(e['entity_id'] in sysfn for e in active): errs.append('Systemkontroll inneholder fortsatt hardkodet HA entity-liste')
if any(x in by for x in ['p20_ha_contract_reconcile_fn','p20_ha_contract_reconcile_api','p20_ha_contract_reconcile_sg_api']): errs.append('gamle hardkodede HA-reconcile-noder finnes fortsatt')
if errs:
    print('RESULT: FAIL – HA–Node-RED-kontrakt fra MariaDB metadata')
    for e in errs: print('FAIL',e)
    raise SystemExit(1)
print(f"RESULT: PASS – MariaDB HA-metadata: {len(active)} aktive entiteter, {len(events)} events, 64 bootstrap-states; JSON/flow/dashboard konsistente")
