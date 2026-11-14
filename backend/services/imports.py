import os
import shutil
import zipfile
import json
from werkzeug.utils import secure_filename
from backend.config import SONGS_DIR, MIN_FREE_BYTES
from backend.services.flac import convert_to_flac
from backend.services.stem_classifier import classify_stem_filename, AUDIO_EXTENSIONS
from backend.services.auth import assign_song_to_group


def check_disk_space():
    """Verifica que haya suficiente espacio en disco. Retorna (ok, free_gb)."""
    try:
        stat = shutil.disk_usage(SONGS_DIR)
        free_gb = stat.free / (1024**3)
        return stat.free >= MIN_FREE_BYTES, round(free_gb, 1)
    except Exception:
        return True, -1  # Si no podemos verificar, dejamos pasar


def process_assembled_zip(zip_path, title, artist, bpm, key, cover_path=None, group_id=None, group_name=None, user_id=None):
    """
    Pipeline compartido: extrae ZIP, clasifica stems, convierte a FLAC, genera metadata.
    Usado tanto por /api/upload como por /api/upload-chunk (DRY).
    Estados: ASSEMBLED → PROCESSING → READY → CLEAN
    """
    extract_path = zip_path + '_extracted'
    warnings = []
    processed_stems = []
    category_counts = {}
    
    song_folder = secure_filename(title.replace(" ", "_"))
    song_out_dir = os.path.join(SONGS_DIR, song_folder)
    stems_out_dir = os.path.join(song_out_dir, 'stems')
    os.makedirs(stems_out_dir, exist_ok=True)

    # Procesar carátula si se proporcionó
    cover_filename = "assets/user_sketch.png"
    if cover_path and os.path.exists(cover_path):
        ext = os.path.splitext(cover_path)[1].lower()
        if ext in ['.jpg', '.jpeg', '.png', '.webp']:
            cname = f"cover{ext}"
            shutil.copy2(cover_path, os.path.join(song_out_dir, cname))
            cover_filename = f"songs/{song_folder}/{cname}"

    try:
        print(f"[PROCESSING] Extrayendo ZIP de '{title}'...")
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(extract_path)

        # Recorrer archivos extraídos
        for root, dirs, files in os.walk(extract_path):
            for filename in files:
                if filename.startswith('__MACOSX') or filename.startswith('.'):
                    continue
                ext = os.path.splitext(filename)[1].lower()
                filepath = os.path.join(root, filename)
                
                if ext not in AUDIO_EXTENSIONS:
                    warnings.append(f"Archivo ignorado (no es audio): {filename}")
                    continue

                classification = classify_stem_filename(filename)
                cat = classification['category']
                if cat == 'other':
                    base_name = secure_filename(os.path.splitext(filename)[0].lower())
                    stem_id = base_name
                else:
                    category_counts[cat] = category_counts.get(cat, 0) + 1
                    count = category_counts[cat]
                    stem_id = cat if count == 1 else f"{cat}_{count}"

                out_filename = f"{stem_id}.flac"
                out_filepath = os.path.join(stems_out_dir, out_filename)

                print(f"  Convirtiendo {filename} → {out_filename}...")
                success = convert_to_flac(filepath, out_filepath)

                if success:
                    classification['id'] = stem_id
                    classification['filename'] = f"stems/{out_filename}"
                    classification['original'] = filename
                    if classification['category'] == 'other':
                        classification['label'] = os.path.splitext(filename)[0][:12].upper()
                    processed_stems.append(classification)
                else:
                    warnings.append(f"Fallo al convertir {filename}")

        if not processed_stems:
            return None, ["No se encontraron audios válidos en el ZIP."]

        # Ordenar stems por prioridad
        priority_order = ["click", "guide", "drums", "bass", "keys", "pad", "guitars", "vocals", "other"]
        processed_stems.sort(key=lambda s: priority_order.index(s["category"]) if s["category"] in priority_order else 99)

        group_ids = []
        meta_file_path = os.path.join(song_out_dir, 'metadata.json')
        if os.path.exists(meta_file_path):
            try:
                with open(meta_file_path, 'r', encoding='utf-8') as old_f:
                    old_meta = json.load(old_f)
                    group_ids = list(old_meta.get('group_ids') or [])
                    if old_meta.get('group_id') and old_meta.get('group_id') not in group_ids:
                        group_ids.append(old_meta.get('group_id'))
            except Exception:
                pass
        if group_id and group_id not in ('default', 'admin') and group_id not in group_ids:
            group_ids.append(group_id)

        # Guardar metadata
        metadata = {
            "id": song_folder,
            "title": title,
            "artist": artist,
            "bpm": bpm,
            "key": key,
            "cover": cover_filename,
            "group_id": group_id if group_id not in ('default', 'admin') else None,
            "group_name": group_name,
            "group_ids": group_ids,
            "stems": processed_stems
        }

        with open(meta_file_path, 'w', encoding='utf-8') as f:
            json.dump(metadata, f, indent=2, ensure_ascii=False)

        if group_id and group_id not in ('default', 'admin'):
            assign_song_to_group(group_id, song_folder, title, user_id)

        print(f"[READY] '{title}' procesada: {len(processed_stems)} stems FLAC")
        return metadata, warnings

    finally:
        # CLEAN: borrar archivos temporales de extracción
        if os.path.exists(extract_path):
            shutil.rmtree(extract_path)

