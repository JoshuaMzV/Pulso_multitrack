"""
migrate_to_flac.py — Script de migración una sola vez.
Convierte todos los stems WAV/MP3/etc existentes en data/songs/ a FLAC
y actualiza el metadata.json de cada canción.

Ejecutar desde la raíz del proyecto:
    python -m scripts.migrate_to_flac
"""
import os
import sys

# Configurar UTF-8 para Windows (necesario para emojis en consola)
if sys.stdout.encoding != 'utf-8':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if sys.stderr.encoding != 'utf-8':
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
import json
import shutil

from backend.services.flac import convert_to_flac
from backend.config import SONGS_DIR

# Extensiones a convertir
CONVERT_EXTENSIONS = {'.wav', '.aif', '.aiff', '.mp3', '.m4a', '.ogg'}

def format_size(bytes_val):
    """Formatea bytes a MB o GB legible."""
    mb = bytes_val / (1024 * 1024)
    if mb >= 1024:
        return f"{mb/1024:.2f} GB"
    return f"{mb:.1f} MB"

def migrate_song(song_dir):
    """
    Migra todos los stems no-FLAC de una canción a FLAC.
    Actualiza metadata.json y elimina los archivos originales.
    Retorna (convertidos, errores, bytes_ahorrados)
    """
    meta_path = os.path.join(song_dir, 'metadata.json')
    stems_dir = os.path.join(song_dir, 'stems')

    if not os.path.exists(meta_path) or not os.path.exists(stems_dir):
        return 0, 0, 0

    # Leer metadata actual
    with open(meta_path, 'r', encoding='utf-8') as f:
        metadata = json.load(f)

    song_title = metadata.get('title', os.path.basename(song_dir))
    print(f"\n📀 Procesando: {song_title}")

    converted = 0
    errors = 0
    bytes_saved = 0
    metadata_changed = False

    # Recorrer los stems en el metadata
    for stem in metadata.get('stems', []):
        stem_filename = stem.get('filename', '')  # Ej: "stems/bass.wav"
        if not stem_filename:
            continue

        # Ruta completa del archivo
        full_path = os.path.join(song_dir, stem_filename)
        ext = os.path.splitext(full_path)[1].lower()

        # Si ya es FLAC, saltar
        if ext == '.flac':
            print(f"  ✓ Ya es FLAC: {os.path.basename(full_path)}")
            continue

        # Si es una extensión a convertir
        if ext in CONVERT_EXTENSIONS and os.path.exists(full_path):
            original_size = os.path.getsize(full_path)
            flac_filename = os.path.splitext(full_path)[0] + '.flac'

            print(f"  → Convirtiendo {os.path.basename(full_path)} ({format_size(original_size)})...")
            success = convert_to_flac(full_path, flac_filename)

            if success and os.path.exists(flac_filename) and os.path.getsize(flac_filename) > 0:
                flac_size = os.path.getsize(flac_filename)
                saved = original_size - flac_size
                bytes_saved += saved

                # Eliminar archivo original
                os.remove(full_path)
                print(f"     ✅ Convertido: {format_size(original_size)} → {format_size(flac_size)} (ahorro: {format_size(saved)})")

                # Actualizar metadata: cambiar "stems/bass.wav" → "stems/bass.flac"
                new_rel_path = stem_filename.rsplit('.', 1)[0] + '.flac'
                stem['filename'] = new_rel_path
                metadata_changed = True
                converted += 1
            else:
                print(f"     ❌ Error convirtiendo {os.path.basename(full_path)}")
                errors += 1
        elif not os.path.exists(full_path):
            print(f"  ⚠ Archivo no encontrado: {stem_filename}")

    # Guardar metadata actualizado si hubo cambios
    if metadata_changed:
        with open(meta_path, 'w', encoding='utf-8') as f:
            json.dump(metadata, f, indent=2, ensure_ascii=False)
        print(f"  📝 metadata.json actualizado")

    return converted, errors, bytes_saved


def main():
    print("=" * 60)
    print("  PULSO — Migración de stems a FLAC")
    print("=" * 60)
    print(f"  Directorio de canciones: {SONGS_DIR}\n")

    if not os.path.exists(SONGS_DIR):
        print("❌ No se encontró el directorio de canciones.")
        return

    # Listar canciones
    song_dirs = [
        os.path.join(SONGS_DIR, d)
        for d in os.listdir(SONGS_DIR)
        if os.path.isdir(os.path.join(SONGS_DIR, d))
        and os.path.exists(os.path.join(SONGS_DIR, d, 'metadata.json'))
    ]

    if not song_dirs:
        print("No se encontraron canciones para migrar.")
        return

    print(f"  Canciones encontradas: {len(song_dirs)}")

    total_converted = 0
    total_errors = 0
    total_saved = 0

    for song_dir in sorted(song_dirs):
        c, e, s = migrate_song(song_dir)
        total_converted += c
        total_errors += e
        total_saved += s

    print("\n" + "=" * 60)
    print("  RESUMEN DE MIGRACIÓN")
    print("=" * 60)
    print(f"  ✅ Stems convertidos : {total_converted}")
    print(f"  ❌ Errores           : {total_errors}")
    print(f"  💾 Espacio ahorrado  : {format_size(total_saved)}")
    print("=" * 60)

    if total_errors == 0:
        print("\n  🎉 Migración completada sin errores.")
    else:
        print(f"\n  ⚠️  {total_errors} stem(s) no pudieron convertirse. Revisa los mensajes anteriores.")


if __name__ == '__main__':
    main()
