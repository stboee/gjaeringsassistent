#!/usr/bin/env python3
"""Install the checksum-pinned document builder on an ephemeral Ubuntu CI runner."""
from pathlib import Path
import hashlib
import json
import platform
import shutil
import subprocess
import tempfile
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
pin=json.loads((ROOT/'tools/doc-builder.json').read_text())
expected='pandoc '+pin['pandoc_version']
def matches():
    binary=shutil.which('pandoc')
    return binary and subprocess.check_output([binary,'--version'],text=True).splitlines()[0]==expected and hashlib.sha256(Path(binary).read_bytes()).hexdigest()==pin['ubuntu_amd64_binary_sha256']

if matches():
    print('PASS pinned document builder: '+expected)
else:
    if platform.system()!='Linux' or platform.machine()!='x86_64':
        raise SystemExit('Install the pinned Pandoc version for this platform explicitly')
    with tempfile.TemporaryDirectory(prefix='ga-doc-builder-') as folder:
        package=Path(folder)/'pandoc.deb'
        request=urllib.request.Request(pin['ubuntu_amd64_asset'],headers={'User-Agent':'gjaeringsassistent-documentation'})
        with urllib.request.urlopen(request,timeout=120) as response,package.open('wb') as output:
            shutil.copyfileobj(response,output)
        if hashlib.sha256(package.read_bytes()).hexdigest()!=pin['sha256']:
            raise SystemExit('Pandoc package checksum mismatch')
        subprocess.run(['sudo','dpkg','-i',str(package)],check=True)
    assert matches(), 'Installed builder does not match the pinned upstream binary'
    print('PASS checksum-verified document builder: '+expected)
