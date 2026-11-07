"""One explicit file selection for a checkout and an unpacked release alike."""
from pathlib import Path
from fnmatch import fnmatch

ROOT_FILES = {
    'VERSION', 'README.md', 'AGENTS.md', 'LICENSE', 'OVERLEVERING.md',
    'RELEASE-NOTES.md', 'TEST-RESULTS.md', 'BUILD-INFO.json',
    'RELEASE-MANIFEST.json', 'SHA256SUMS', '.gitignore', '.gitattributes',
}
COMPONENTS = {
    'dashboard', 'nodered', 'installer', 'sql', 'tests', 'tools', 'docs',
    'compose', 'reference', 'contracts', 'verification',
}
TRANSIENT_DIRS = {'node_modules', '__pycache__', 'install-reports', '.cache', '.tmp', 'secrets', 'credentials'}
LOCAL_NAMES = {'secrets.yaml', 'secrets.yml', 'secrets.json', 'credentials.json',
               'credentials.yaml', 'credentials.yml', '.npmrc', '.config.runtime.json'}


def is_source_file(path: Path):
    name = path.name
    return (not TRANSIENT_DIRS.intersection(path.parts)
            and name not in LOCAL_NAMES
            and not fnmatch(name, '*_cred.json*')
            and not name.startswith('.config.runtime.json.')
            and not (name.startswith('.env') and not name.endswith('.example'))
            and path.suffix not in {'.pyc', '.pem', '.key', '.p12', '.pfx'})


def package_files(root: Path):
    paths = [root / name for name in ROOT_FILES if (root / name).is_file()]
    for name in COMPONENTS:
        paths.extend(p for p in (root / name).rglob('*')
                     if p.is_file() and is_source_file(p.relative_to(root)))
    return sorted(paths)
