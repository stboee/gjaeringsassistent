#!/usr/bin/env python3
"""Lossless SQL backup, including views, without evaluating their expressions.

MariaDB 12.3's dump client can resolve a view through SHOW CREATE TABLE using a
different connection collation. Dump physical tables/routines/triggers normally;
read view definitions and their original charset/security metadata separately.
Node-RED must already be stopped; this utility never changes database objects.
"""
import argparse
import gzip
import json
import re
import subprocess


def identifier(value):
    return '`' + value.replace('`', '``') + '`'


def view_order(views):
    known = {row['name']: row for row in views}
    pending = set(known)
    ordered = []
    while pending:
        ready = []
        for name in sorted(pending):
            # Stored MariaDB view definitions qualify and backtick identifiers.
            sql = re.sub(r"'(?:''|\\.|[^'])*'", "''", known[name]['definition'])
            references = {x.replace('``', '`') for x in re.findall(r'`((?:``|[^`])+)`', sql)}
            if not (references & pending - {name}):
                ready.append(name)
        if not ready:
            raise ValueError('Kunne ikke bestemme avhengighetsrekkefølge for backup-views')
        for name in ready:
            ordered.append(known[name])
            pending.remove(name)
    return ordered


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()

    def read(sql):
        result = subprocess.run([
            'docker', 'exec', '-i', args.container, 'sh', '-lc',
            'mariadb -N -B -r -uroot -p"$MARIADB_ROOT_PASSWORD" "$MARIADB_DATABASE"'
        ], input='SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;\n'+sql, text=True, capture_output=True)
        if result.returncode:
            raise ValueError('Kunne ikke lese backupmetadata: '+result.stderr.strip())
        return result.stdout.strip()

    database = read('SELECT DATABASE();')
    if not re.fullmatch(r'[a-zA-Z0-9_]+', database):
        raise ValueError('Uventet databasenavn i backupmetadata')
    rows = read("""SELECT JSON_OBJECT('name',v.TABLE_NAME,'definition',v.VIEW_DEFINITION,
      'definer',v.DEFINER,'security',v.SECURITY_TYPE,'check_option',v.CHECK_OPTION,
      'charset',v.CHARACTER_SET_CLIENT,'collation',v.COLLATION_CONNECTION)
      FROM information_schema.VIEWS v WHERE v.TABLE_SCHEMA=DATABASE() ORDER BY v.TABLE_NAME;""")
    views = [json.loads(line) for line in rows.splitlines() if line]
    ordered = view_order(views)
    ignored = ['--ignore-table='+database+'.'+row['name'] for row in views]
    command = ['docker', 'exec', args.container, 'sh', '-lc',
               'exec mariadb-dump --single-transaction --quick --routines --triggers --events --hex-blob --default-character-set=utf8mb4 -uroot -p"$MARIADB_ROOT_PASSWORD" "$@" "$MARIADB_DATABASE"',
               'ga-backup', *ignored]
    # A failed dump closes with an error before the installer accepts this file.
    with gzip.open(args.output, 'wb') as output:
        process = subprocess.Popen(command, stdout=subprocess.PIPE)
        while chunk := process.stdout.read(1024*1024):
            output.write(chunk)
        if process.wait():
            raise ValueError('mariadb-dump feilet; ingen databaseendring er startet')
        for view in ordered:
            user, separator, host = view['definer'].rpartition('@')
            if not separator or view['security'] not in ('DEFINER', 'INVOKER'):
                raise ValueError('Ufullstendig sikkerhetsmetadata for view')
            for value in (view['charset'], view['collation']):
                if not re.fullmatch('[a-zA-Z0-9_]+', value):
                    raise ValueError('Ugyldig tegnsettmetadata for view')
            check = ''
            if view['check_option'] != 'NONE':
                if view['check_option'] not in ('LOCAL', 'CASCADED'):
                    raise ValueError('Ukjent view CHECK OPTION')
                check = ' WITH '+view['check_option']+' CHECK OPTION'
            statement = ('\nSET character_set_client='+view['charset']+'; SET collation_connection='+view['collation']+';\n'
                         'CREATE OR REPLACE ALGORITHM=UNDEFINED DEFINER='+identifier(user)+'@'+identifier(host)+
                         ' SQL SECURITY '+view['security']+' VIEW '+identifier(view['name'])+' AS '+view['definition']+check+';\n')
            output.write(statement.encode('utf-8'))
    print(json.dumps({'views': len(views), 'backup': args.output, 'database': database}, ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        raise SystemExit(str(error))
