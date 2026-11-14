"""Copia datos históricos, verifica hashes y rechaza conflictos sin sobrescribir."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import sqlite3

ROOT = Path(__file__).resolve().parents[1]

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def migrate(root=ROOT, destination=None):
    destination = Path(destination or os.environ.get('PULSO_DATA_DIR', root / 'data')).resolve()
    pairs = []
    for old, new in [('www/songs', 'songs'), ('backend/setlists.json', 'setlists.json'),
                     ('backend/database/pulso.db', 'database/pulso.db'), ('backend/temp', 'temp')]:
        source = root / old
        files = [source] if source.is_file() else sorted(source.rglob('*')) if source.exists() else []
        for item in files:
            if item.is_file():
                relative = Path(new) if source.is_file() else Path(new) / item.relative_to(source)
                target = destination / relative
                if target.exists() and digest(item) != digest(target):
                    raise RuntimeError(f'Conflicto: {target}; no se sobrescribió ningún archivo.')
                pairs.append((item, target))
    manifest = []
    for source, target in pairs:
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            shutil.copy2(source, target)
        sha = digest(source)
        if digest(target) != sha:
            raise RuntimeError(f'Hash incorrecto: {target}')
        manifest.append({'source': str(source), 'target': str(target), 'sha256': sha})
    database = destination / 'database/pulso.db'
    if database.exists():
        with sqlite3.connect(f'{database.as_uri()}?mode=ro', uri=True) as connection:
            if connection.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                raise RuntimeError('Base de datos inconsistente; conservar originales y restaurar respaldo SQLite.')
    destination.mkdir(parents=True, exist_ok=True)
    if manifest or not (destination / 'migration-manifest.json').exists():
        (destination / 'migration-manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    return manifest

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path)
    args = parser.parse_args()
    print(f'Archivos verificados: {len(migrate(destination=args.destination))}. Originales conservados.')
