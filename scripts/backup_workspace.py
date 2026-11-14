"""Respaldo local verificable antes de una migración; no incluye dependencias regenerables."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import os
import shutil
import sqlite3
import subprocess

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED = {'.git', '.venv', 'node_modules', '.local-backups', '__pycache__',
            '.gradle', 'build', 'Pods', '.mycli', '.mycli-fts', '.test-data',
            'test-results', 'playwright-report'}

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def main():
    target = ROOT / '.local-backups' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    target.mkdir(parents=True, exist_ok=False)
    manifest = []
    data_root = Path(os.environ.get('PULSO_DATA_DIR', ROOT / 'data')).expanduser().resolve()
    sources = [(ROOT, 'files')]
    if not data_root.is_relative_to(ROOT) and data_root.exists():
        sources.append((data_root, 'external-data'))
    for base, prefix in sources:
        for directory, folders, files in os.walk(base):
            folders[:] = [name for name in folders if name not in EXCLUDED]
            for name in files:
                source = Path(directory) / name
                relative = source.relative_to(base)
                destination = target / prefix / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)
                sha = digest(source)
                if digest(destination) != sha:
                    raise RuntimeError(f'Falló la verificación: {relative}')
                manifest.append({'path': relative.as_posix(), 'backup_path': destination.relative_to(target).as_posix(),
                                 'sha256': sha, 'bytes': source.stat().st_size})
    (target / 'data-root.txt').write_text(str(data_root), encoding='utf-8')
    database = data_root / 'database/pulso.db'
    if not database.exists():
        database = ROOT / 'backend/database/pulso.db'
    if database.exists():
        with sqlite3.connect(database) as source, sqlite3.connect(target / 'pulso-consistent.db') as copy:
            source.backup(copy)
            if copy.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                raise RuntimeError('SQLite no supera la verificación de integridad')
    (target / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    status = subprocess.check_output(['git', 'status', '--short'], cwd=ROOT)
    (target / 'git-status.txt').write_bytes(status)
    print(json.dumps({'backup': str(target), 'files': len(manifest), 'bytes': sum(x['bytes'] for x in manifest)}))

if __name__ == '__main__':
    main()
