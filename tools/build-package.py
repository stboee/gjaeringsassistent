#!/usr/bin/env python3
from pathlib import Path
import argparse,hashlib,json,subprocess,sys,datetime,zipfile,os
from package_files import package_files
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description='Build the versioned GitHub/source release without local Git or runtime data.')
parser.add_argument('--zip',action='store_true')
parser.add_argument('--output-dir',type=Path,default=ROOT/'dist')
parser.add_argument('--source-commit',help='Exact source commit recorded by the release job')
args=parser.parse_args()
version=(ROOT/'VERSION').read_text().strip()
if args.source_commit:
 import re
 if not re.fullmatch(r'[0-9a-f]{40}',args.source_commit):parser.error('source commit must be a full Git SHA')
 build=json.loads((ROOT/'BUILD-INFO.json').read_text())
 build['source_commit']=args.source_commit
 (ROOT/'BUILD-INFO.json').write_text(json.dumps(build,ensure_ascii=False,indent=2)+'\n')
subprocess.run([sys.executable,str(ROOT/'tools/embed_analysis_methods.py')],cwd=ROOT,check=True)
subprocess.run([sys.executable,str(ROOT/'tools/build_docs.py')],cwd=ROOT,check=True)
def sha(p):
 h=hashlib.sha256()
 with open(p,'rb') as f:
  for b in iter(lambda:f.read(1048576),b''): h.update(b)
 return h.hexdigest()
files=[p for p in package_files(ROOT) if p.name!='SHA256SUMS']
(ROOT/'SHA256SUMS').write_text(''.join(f"{sha(p)}  {p.relative_to(ROOT).as_posix()}\n" for p in files),encoding='utf-8')
subprocess.run([sys.executable,str(ROOT/'tests/verify-package.py')],check=True)
if args.zip:
 args.output_dir.mkdir(parents=True,exist_ok=True)
 out=args.output_dir/('gjaeringsassistent-'+version+'.zip')
 if out.exists(): out.unlink()
 with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
  for p in package_files(ROOT): z.write(p,'gjaeringsassistent-'+version+'/'+p.relative_to(ROOT).as_posix())
 out.with_name(out.name+'.sha256').write_text(f'{sha(out)}  {out.name}\n',encoding='utf-8')
 print(out)
