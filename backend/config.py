"""Rutas locales compartidas; los datos nunca forman parte del paquete web."""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = Path(os.environ.get('PULSO_DATA_DIR', ROOT / 'data')).expanduser().resolve()
WWW_DIR = Path(os.environ.get('PULSO_WEB_DIR', ROOT / 'src')).expanduser().resolve()
SONGS_DIR = DATA_DIR / 'songs'
TEMP_DIR = DATA_DIR / 'temp'
CHUNKS_DIR = TEMP_DIR / 'chunks'
SETLISTS_FILE = DATA_DIR / 'setlists.json'
DB_DIR = DATA_DIR / 'database'
DB_PATH = DB_DIR / 'pulso.db'
MIN_FREE_BYTES = 8 * 1024 * 1024 * 1024

def ensure_data_directories():
    for directory in (SONGS_DIR, TEMP_DIR, CHUNKS_DIR, DB_DIR):
        directory.mkdir(parents=True, exist_ok=True)
