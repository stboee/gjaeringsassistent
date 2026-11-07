#!/usr/bin/env python3
"""Read the machine-readable p21 system metadata seed without requiring a live DB.
Runtime authority is MariaDB after install; this parser exists for release/build validation.
"""
from pathlib import Path
import re


def _split_sql_values(text):
    out=[]; cur=[]; quoted=False; i=0
    while i < len(text):
        ch=text[i]
        if ch=="'":
            cur.append(ch)
            if quoted and i+1 < len(text) and text[i+1]=="'":
                cur.append("'"); i+=2; continue
            quoted=not quoted; i+=1; continue
        if ch==',' and not quoted:
            out.append(''.join(cur).strip()); cur=[]; i+=1; continue
        cur.append(ch); i+=1
    out.append(''.join(cur).strip())
    return out


def _value(v):
    v=v.strip()
    if v.upper()=='NULL': return None
    if v.startswith("'") and v.endswith("'"):
        return v[1:-1].replace("''", "'")
    try:
        return int(v)
    except ValueError:
        try:return float(v)
        except ValueError:return v


def insert_rows(path, table):
    # The generated seed deliberately uses one INSERT per line.  Parse both
    # idempotent registry INSERTs (with ON DUPLICATE KEY UPDATE) and ordinary
    # dependency INSERTs.  This keeps release validation independent of a live DB.
    rows=[]
    prefix=re.compile(rf"^INSERT INTO {re.escape(table)}\(([^\)]*)\) VALUES \(")
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        m=prefix.match(line.strip())
        if not m:
            continue
        rest=line.strip()[m.end():]
        marker=') ON DUPLICATE KEY UPDATE '
        if marker in rest:
            values_text=rest.split(marker,1)[0]
        elif rest.endswith(');'):
            values_text=rest[:-2]
        else:
            raise ValueError(f'{table}: unsupported INSERT form: {line[:120]}')
        cols=[x.strip() for x in m.group(1).split(',')]
        vals=[_value(x) for x in _split_sql_values(values_text)]
        if len(cols)!=len(vals):
            raise ValueError(f'{table}: {len(cols)} columns != {len(vals)} values')
        rows.append(dict(zip(cols,vals)))
    return rows


def load_system_metadata(root):
    seed=Path(root)/'sql/21-system-metadata-seed.sql'
    return {
        'entities':insert_rows(seed,'ha_entity_registry'),
        'events':insert_rows(seed,'ha_event_registry'),
        'aliases':insert_rows(seed,'ha_entity_aliases'),
        'select_options':insert_rows(seed,'ha_entity_select_options'),
        'number_constraints':insert_rows(seed,'ha_entity_number_constraints'),
        'functions':insert_rows(seed,'system_functions'),
        'dependencies':insert_rows(seed,'function_information_dependencies'),
        'system_check_definitions':insert_rows(seed,'system_check_definitions'),
        'system_check_expectations':insert_rows(seed,'system_check_expectations'),
    }
