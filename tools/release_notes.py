#!/usr/bin/env python3
"""Select the current release section from the single maintained release history."""
from pathlib import Path
import re


def current_release_notes(root):
    root=Path(root)
    version=(root/'VERSION').read_text().strip()
    lines=(root/'RELEASE-NOTES.md').read_text().splitlines()
    if not lines or not lines[0].startswith('# '+version+' – '):
        raise ValueError('Releasehistorikkens første tittel må samsvare med VERSION')
    end=next((i for i,line in enumerate(lines[1:],1)
              if re.match(r'^#{1,2} \d{4}\.\d{2}\.\d{2}-\d+\b',line)),len(lines))
    return '\n'.join(lines[:end]).rstrip()+'\n'


if __name__=='__main__':
    print(current_release_notes(Path(__file__).resolve().parents[1]),end='')
