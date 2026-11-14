#!/usr/bin/env python3
"""Check owned interface metadata against actual SQL registries and physical flow."""
from pathlib import Path
import json
import re
import sys
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from documentation_metadata import interface_reference, routine_definitions
from system_metadata import insert_rows


def publication_errors(flow, catalog, schema):
    errors = []
    by = {n['id']: n for n in flow}
    pub = next(i for i in catalog['interfaces'] if i['interface_id']=='IF-NR-PUBLICATION')
    declared = {p['producer'] for p in pub['pipelines']}
    actual = {n['id'] for n in flow if 'ga_publication_args=JSON.stringify' in n.get('func', '')}
    if declared != actual:
        errors.append('Publication producer catalog does not cover actual producers')
    required, allowed = set(schema['required']), set(schema['properties'])
    for pipe in pub['pipelines']:
        if any(pipe[k] not in by for k in pipe):
            errors.append('Missing publication node'); continue
        source = by[pipe['producer']].get('func', '')
        expressions = re.findall(r'msg\.ga_publication_args=JSON\.stringify\(\{(.*?)\}\);', source)
        if not expressions:
            errors.append('No actual publication argument object: '+pipe['producer'])
        for expression in expressions:
            keys = set(re.findall(r'(?:^|,)\s*(\w+)\s*:', expression))
            if not required <= keys or not keys <= allowed:
                errors.append('Publication keys violate schema: '+pipe['producer'])
        for previous, following in [('producer','staging'), ('staging','arguments'), ('arguments','executor')]:
            if pipe[following] not in by[pipe[previous]].get('wires',[[]])[0]:
                errors.append('Broken publication path: '+pipe[previous])
        executor = by[pipe['executor']]
        if 'publish_payload.js' not in executor.get('command', '') or executor.get('addpay')!='payload':
            errors.append('Wrong publication consumer: '+pipe['executor'])
        for slot, key in [(0,'success'), (1,'stderr')]:
            if pipe[key] not in executor.get('wires',[[],[]])[slot]:
                errors.append('Publication result is not observed: '+pipe[key])
        staging = by[pipe['staging']]
        if staging.get('filename')!='filename' or staging.get('filenameType')!='msg':
            errors.append('Staging does not consume msg.filename')
    return errors


def main():
    catalog = json.loads((ROOT/'contracts/interface-catalog.json').read_text())
    flow = json.loads((ROOT/'nodered/flows.template.json').read_text())
    contract = json.loads((ROOT/'contracts/ha-node-red-contract.json').read_text())
    for interface in catalog['interfaces']:
        for kind in ['authority','derived_or_captured','implementation','checks']:
            for source in interface[kind]:
                assert (ROOT/source).is_file(), source
    schema = json.loads((ROOT/'contracts/publication-job.schema.json').read_text())
    assert schema['required']==['stage_path','target_path'] and schema['additionalProperties'] is False
    assert not publication_errors(flow, catalog, schema), publication_errors(flow,catalog,schema)
    # Regression: each actual producer must fail if the old wrong key returns.
    pub = next(i for i in catalog['interfaces'] if i['interface_id']=='IF-NR-PUBLICATION')
    for pipe in pub['pipelines']:
        mutated = json.loads(json.dumps(flow))
        n = next(n for n in mutated if n['id']==pipe['producer'])
        n['func'] = n['func'].replace('stage_path:msg.filename','source_path:msg.filename')
        assert publication_errors(mutated,catalog,schema), pipe['producer']
    mutated = json.loads(json.dumps(flow))
    next(n for n in mutated if n['id']==pub['pipelines'][-1]['executor'])['wires'][1]=[]
    assert publication_errors(mutated,catalog,schema)
    # Check complete generated arrays, not only entity IDs and event names.
    mapping = {'projections':'ha_projection_routes','fields':'ha_projection_fields',
               'draft_bindings':'ha_draft_output_bindings','input_bindings':'ha_entity_input_bindings',
               'input_value_mappings':'ha_entity_input_value_mappings',
               'number_constraints':'ha_entity_number_constraints','start_fields':'start_field_rules',
               'start_pitch_modes':'start_field_pitch_modes'}
    for key, table in mapping.items():
        assert contract[key]==insert_rows(ROOT/'sql/21-system-metadata-seed.sql',table), key
    by = {n['id']:n for n in flow}
    for route in contract['projections']:
        assert route['consumer_node_id'] in by, route
        source=route['source_object_id'].removeprefix('view:')
        assert re.search(r'CREATE OR REPLACE VIEW\s+'+re.escape(source)+r'\b', (ROOT/'sql/20-views.sql').read_text()), source
    # Catch stale schema prose like the old DOC-19 2.3 reference against the actual producer.
    versions=set(re.findall(r"schema_version:'([^']+)'",by['p20_overview_result']['func']))
    assert len(versions)==1, 'Ambiguous overview serialization schema'
    for document in (ROOT/'docs').glob('*.md'):
        for declared in re.findall(r'(?:Oversikt bruker schema|Oversiktspayload)\s+([0-9.]+)',document.read_text(),re.I):
            assert declared.rstrip('.') in versions, 'Stale overview schema: '+document.name
    reference = interface_reference(ROOT)
    unknown = set(reference['node_red_routine_calls'])-set(routine_definitions(ROOT))
    assert not unknown, 'Unknown routine CALLs: '+str(sorted(unknown))
    assert reference==json.loads((ROOT/'docs/generated/interface-reference.json').read_text()), 'Stale interface reference'
    print('RESULT: PASS – DB/NR/HA contracts, full registry arrays, actual publication chains; wrong-key and disconnected-error mutations rejected')


if __name__=='__main__':
    main()
