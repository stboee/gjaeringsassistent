#!/usr/bin/env python3
"""Protect documented requirements, decisions and deliberate guardrail repetition."""
from pathlib import Path
import json
import re
ROOT=Path(__file__).resolve().parents[1]


def rows(pattern, id_pattern):
    result={}
    for p in (ROOT/'docs').glob(pattern):
        for line in p.read_text().splitlines():
            if re.match(r'^\|\s*'+id_pattern+r'\s*\|',line):
                cells=[c.strip() for c in line.strip().strip('|').split('|')]
                assert cells[0] not in result, cells[0]
                result[cells[0]]=cells
    return result


history=json.loads((ROOT/'docs/sources/requirements-history.json').read_text())
baseline=next(e for e in history['events'] if e['kind']=='documented_baseline')
requirements={r['id']:[r['id'],r['status'],r['requirement']] for r in baseline['requirements']}
decisions={d['id']:[d['id'],d['decision'],d['rationale'],d['consequence']] for d in baseline['decisions']}
for event in history['events']:
    if event['kind'] in ['requirement_addition','decision_addition']:
        target=requirements if event['kind']=='requirement_addition' else decisions
        assert event['item_id'] not in target and event['after'][0]==event['item_id']
        assert event['reason'] and event['source_locator']
        target[event['item_id']]=event['after']
    if event['kind'] in ['requirement_change','decision_change']:
        target=requirements if event['kind']=='requirement_change' else decisions
        assert event['before']==target[event['item_id']] and event['after'][0]==event['item_id']
        assert event['reason'] and event['source_locator']
        target[event['item_id']]=event['after']
assert rows('0[1-4]-*.md',r'REQ-[A-Z]+-\d+')==requirements, 'Requirement changed/lost without provenance event'
assert rows('14-*.md',r'(?:DEC|ADR)-[A-Z0-9-]+')==decisions, 'Decision changed/lost without provenance event'
policy=json.loads((ROOT/'docs/sources/document-policy.json').read_text())
block=(ROOT/policy['guardrail_source']).read_text().strip()
for name in policy['guardrail_targets']:
    text=(ROOT/name).read_text()
    assert text.count(block)==1, 'Missing or divergent guardrails: '+name
active={p.name for p in (ROOT/'docs').glob('*.md')}
mapped=[p for g in policy['groups'] for p in g['documents']]
assert len(mapped)==len(set(mapped)) and set(mapped)==active-{'index.md'}
revision=json.loads((ROOT/policy['revision_source']).read_text())
assert revision['base_commit']==history['baseline_commit']==policy['baseline_commit']
for item in revision['blocks']:
    assert item['disposition'] in {'retained','moved','reviewed_rewrite'}
    assert re.fullmatch('[a-f0-9]{64}',item['sha256'])
    for name in item['destinations']:
        assert (ROOT/name).is_file(),name
    if item['disposition']=='reviewed_rewrite':
        assert item['reason']
expected_open={line.strip().strip('|').split('|')[0].strip():[c.strip() for c in line.strip().strip('|').split('|')] for line in baseline['open_items']}
assert rows('15-*.md',r'OPEN-\d+')==expected_open
assert len(expected_open)==revision['original_open_items']
print(f'RESULT: PASS – {len(requirements)} requirements, {len(decisions)} decisions, all OPEN IDs, complete document map and {len(policy["guardrail_targets"])} deliberate guardrail copies')
