#!/usr/bin/env python3
"""Embed the shared calculation kernel without editing model parameters."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / 'nodered/flows.template.json'
flows = json.loads(path.read_text())
helper = (root / 'tools/analysis_methods.js').read_text()
for node_id in ['p20_bio_eval_result', 'p20_process_eval_result', 'p22_analysis_result']:
    node = next(n for n in flows if n['id'] == node_id)
    source = node['func']
    if not source.startswith('// Shared generic calculation models.'):
        raise ValueError('Shared kernel missing from ' + node_id)
    marker = '\n})();\n'
    end = source.index(marker) + len(marker)
    node['func'] = helper + source[end:]
path.write_text(json.dumps(flows, ensure_ascii=False, indent=2) + '\n')
