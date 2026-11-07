#!/usr/bin/env python3
"""Reject an unverified database version before any installation mutation."""
import argparse
import json
import re
import sys
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--build-info', type=Path, required=True)
parser.add_argument('--server-version', required=True)
args = parser.parse_args()
expected = json.loads(args.build_info.read_text())['runtime_dependencies']['mariadb']
observed = args.server_version.strip()
match = re.fullmatch(r'(\d+\.\d+\.\d+)(?:[-+].*)?', observed)
if not re.fullmatch(r'\d+\.\d+\.\d+', expected):
    sys.exit('Ugyldig MariaDB-versjon i release-metadata.')
if not match or match[1] != expected:
    sys.exit(f'MariaDB-versjon avviker: forventet {expected}, faktisk {observed!r}. Oppdater eksisterende MariaDB-tjeneste før installasjon. Ingen database-reset eller flowendring er startet.')
print(json.dumps({'expected_version': expected, 'server_version': observed}))
