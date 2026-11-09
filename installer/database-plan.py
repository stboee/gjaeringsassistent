#!/usr/bin/env python3
"""Read-only install planning. Reject unknown databases before stopping Node-RED."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path


def migration_digest(root, manifest):
    h = hashlib.sha256()
    for name in dict.fromkeys(manifest['upgrade_files'] + manifest['patch_files']):
        h.update(name.encode() + b'\0' + (root / name).read_bytes() + b'\0')
    return h.hexdigest()


def choose_plan(root, manifest, version, tables, views, history):
    target = (root / 'VERSION').read_text().strip()
    if target != manifest['target_version']:
        raise ValueError('Migreringsmanifest og VERSION avviker')
    digest = migration_digest(root, manifest)
    if tables == 0 and views == 0:
        return {'mode': 'fresh', 'source_version': None, 'migration_sha256': digest}
    if version == target:
        if (tables, views) != (manifest['target_tables'], manifest['target_views']):
            raise ValueError('Installert målversjon har ukjent databasestruktur')
        receipt = next((x for x in history if x['migration_id'] == manifest['migration_id']), None)
        if not receipt or receipt['checksum_sha256'] != digest:
            raise ValueError('Installert målversjon mangler samsvarende migreringskvittering')
        return {'mode': 'reinstall', 'source_version': version, 'migration_sha256': digest}
    if version in manifest['patch_sources']:
        expected = manifest['patch_sources'][version]
        receipt = next((x for x in history if x['migration_id'] == expected['migration_id']), None)
        if (tables, views) != (manifest['target_tables'], manifest['target_views']) or not receipt or receipt['checksum_sha256'] != expected['checksum_sha256']:
            raise ValueError('Filoppgradering krever kjent databasestruktur og samsvarende migreringskvittering')
        return {'mode': 'patch', 'source_version': version, 'migration_sha256': digest}
    if version not in manifest['supported_sources']:
        raise ValueError(f'Ingen verifisert oppgraderingsbane fra {version!r}')
    if (tables, views) != (manifest['baseline_tables'], manifest['baseline_views']):
        raise ValueError(f'Ukjent databasestruktur: {tables} tabeller / {views} views')
    return {'mode': 'upgrade', 'source_version': version, 'migration_sha256': digest}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    manifest = json.loads((root / 'installer/migrations.json').read_text())

    def read(sql):
        result = subprocess.run([
            'docker', 'exec', '-i', args.container, 'sh', '-lc',
            'mariadb -N -B -r -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"'
        ], input=sql, text=True, capture_output=True)
        if result.returncode:
            raise ValueError('Kunne ikke lese databaseidentitet; ingen endringer er utført')
        return result.stdout.strip()

    tables, views = map(int, read("SELECT SUM(TABLE_TYPE='BASE TABLE'),SUM(TABLE_TYPE='VIEW') FROM information_schema.tables WHERE TABLE_SCHEMA=DATABASE();").replace('NULL', '0').split('\t'))
    names = set(read('SELECT TABLE_NAME FROM information_schema.tables WHERE TABLE_SCHEMA=DATABASE();').splitlines())
    base_names = read("SELECT TABLE_NAME FROM information_schema.tables WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE='BASE TABLE';").splitlines()
    import re
    if any(not re.fullmatch(r'[a-z][a-z0-9_]*', name) for name in base_names):
        raise ValueError('Ukjente tabellidentiteter i installasjonsgrunnlaget')
    # Exact physical-table lookups prevent column introspection from resolving
    # the entire nested graph/view chain after a schema-cache invalidation.
    signature = read('\n'.join("SELECT CONCAT_WS(CHAR(9),TABLE_NAME,COLUMN_NAME,COLUMN_TYPE,IS_NULLABLE,COALESCE(COLLATION_NAME,'NULL')) FROM information_schema.columns WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='"+name+"';" for name in base_names))
    signature_sha = hashlib.sha256(('\n'.join(sorted(signature.splitlines()))+'\n').encode()).hexdigest()
    version = None
    if tables == 0 and views == 0 and read('SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA=DATABASE();') != '0':
        raise ValueError('Databasen inneholder ukjente rutiner og regnes ikke som tom')
    if tables or views:
        if not {'database_metadata', 'template_database_metadata'} <= names:
            raise ValueError('Eksisterende database mangler gjenkjennelig versjonsmetadata')
        versions = read('SELECT application_version FROM database_metadata WHERE metadata_id=1 UNION ALL SELECT application_version FROM template_database_metadata WHERE metadata_id=1;').splitlines()
        if len(versions) != 2 or versions[0] != versions[1]:
            raise ValueError('Databaseversjonene mangler eller avviker')
        version = versions[0]
        runtime_schema = int(read('SELECT schema_version FROM database_metadata WHERE metadata_id=1;'))
        template_schema = int(read('SELECT schema_version FROM template_database_metadata WHERE metadata_id=1;'))
        expected_schema = manifest['target_schema_version'] if version == manifest['target_version'] or version in manifest['patch_sources'] else manifest['baseline_schema_version']
        if runtime_schema != expected_schema or template_schema != manifest['template_schema_version']:
            raise ValueError('Ukjent schema-versjon; ingen endringer er utført')
    history = []
    if 'database_migrations' in names:
        for line in read('SELECT migration_id,checksum_sha256 FROM database_migrations;').splitlines():
            migration_id, checksum = line.split('\t')
            history.append({'migration_id': migration_id, 'checksum_sha256': checksum})
    if version in manifest['supported_sources'] and signature_sha != manifest['baseline_schema_sha256']:
        raise ValueError('Databasestrukturen avviker fra verifisert kildeversjon; ingen endringer er utført')
    if (version == manifest['target_version'] or version in manifest['patch_sources']) and signature_sha != manifest['target_schema_sha256']:
        raise ValueError('Databasestrukturen avviker fra verifisert målstruktur; ingen endringer er utført')
    plan = choose_plan(root, manifest, version, tables, views, history)
    plan.update({'target_version': manifest['target_version'], 'migration_id': manifest['migration_id']})
    print(json.dumps(plan, ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        raise SystemExit(str(error))
