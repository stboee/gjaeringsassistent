#!/usr/bin/env python3
"""Embed runtime delivery sources and generate installable metadata explicitly."""
from pathlib import Path
import json,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
from documentation_metadata import sync_document_sources
sync_document_sources(ROOT)
# Embed the shared renderer into frontend/report delivery surfaces.
renderer=(ROOT/'tools/graph_renderer.js').read_text(encoding='utf-8')
marker='function gaRenderAnalysisSvg(data){'
card_path=ROOT/'dashboard/gjaeringsassistent-card.js'
card=card_path.read_text(encoding='utf-8')
old_end=card.index('class ',card.index(marker))
card_path.write_text(renderer+'\n'+card[old_end:].lstrip(),encoding='utf-8')
flow_path=ROOT/'nodered/flows.template.json'
flow=json.loads(flow_path.read_text(encoding='utf-8'))
payload_helper=(ROOT/'tools/presentation_payload.js').read_text(encoding='utf-8')
report_helper=renderer+'\n'+payload_helper+'\n'+(ROOT/'tools/report_renderer.js').read_text(encoding='utf-8')
for node in flow:
    if node.get('id') in ['p22_active_report_result','p21_session_export_read_result']:
        wrapper=node['func'].split('// Report transport wrapper\n',1)[1]
        node['func']=report_helper+'\n// Report transport wrapper\n'+wrapper
for node in flow:
    if node.get('id')=='p20_overview_result':
        node['func']=payload_helper+'\n// Overview transport wrapper\n'+node['func'].split('// Overview transport wrapper\n',1)[1]
report_queries=(ROOT/'tools/report_queries.sql').read_text(encoding='utf-8')
for node in flow:
    if node.get('id') in ['p22_active_report_query','p21_session_export_query']:
        body=node['func'];start=body.index('CALL ga_read_report(');end=body.rindex('`')
        node['func']=body[:start]+report_queries+body[end:]
flow_path.write_text(json.dumps(flow,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


# Archive UI is part of the same published, content-hashed card module.
card_path=ROOT/"dashboard/gjaeringsassistent-card.js"
card_text=card_path.read_text(encoding="utf-8").split("\n// BEGIN SQLITE ARCHIVE UI\n")[0]
card_path.write_text(card_text+"\n// BEGIN SQLITE ARCHIVE UI\n"+(ROOT/"dashboard/archive-card.js").read_text(encoding="utf-8"),encoding="utf-8")

# HA contract is a generated projection of the authoritative DB registry.
from system_metadata import load_system_metadata
contract_path=ROOT/'contracts/ha-node-red-contract.json'
contract=json.loads(contract_path.read_text(encoding='utf-8'))
meta=load_system_metadata(ROOT)
from system_metadata import insert_rows
contract['version']=(ROOT/'VERSION').read_text().strip()
contract['start_fields']=insert_rows(ROOT/'sql/21-system-metadata-seed.sql','start_field_rules')
contract['start_pitch_modes']=insert_rows(ROOT/'sql/21-system-metadata-seed.sql','start_field_pitch_modes')
contract['projections']=insert_rows(ROOT/'sql/21-system-metadata-seed.sql','ha_projection_routes')
contract['fields']=insert_rows(ROOT/'sql/21-system-metadata-seed.sql','ha_projection_fields')
contract['draft_bindings']=insert_rows(ROOT/'sql/21-system-metadata-seed.sql','ha_draft_output_bindings')
contract['entities']=[{k:e[k] for k in ['entity_id','config_id','entity_type','display_name','direction','status']} for e in meta['entities']]
contract['input_bindings']=insert_rows(ROOT/'sql/21-system-metadata-seed.sql','ha_entity_input_bindings')
contract['input_value_mappings']=insert_rows(ROOT/'sql/21-system-metadata-seed.sql','ha_entity_input_value_mappings')
contract['number_constraints']=meta['number_constraints']
contract['plugin_version']='0.80.3'
contract['event_channels']=[{'event_type':e['event_type'],'direction':e['direction'],'mode':e['event_mode'],'listener_id':e['listener_node_id']} for e in load_system_metadata(ROOT)['events'] if e['status']=='active']
contract_path.write_text(json.dumps(contract,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

subprocess.run([sys.executable,str(ROOT/'tools/build_verification_registry.py')],cwd=ROOT,check=True)
