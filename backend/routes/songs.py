import os
import shutil
import zipfile
import json
import uuid
import urllib.request
from flask import request, jsonify
from werkzeug.utils import secure_filename
from backend.config import SONGS_DIR, TEMP_DIR, CHUNKS_DIR, SETLISTS_FILE
from backend.services.flac import convert_to_flac
from backend.services.stem_classifier import classify_stem_filename, AUDIO_EXTENSIONS
from backend.services.auth import normalize_song_key, assign_song_to_group
from flask import Blueprint
from backend.services.session import get_auth_user
from backend.services.imports import check_disk_space, process_assembled_zip

app = Blueprint("songs", __name__)

@app.route('/api/upload-chunk', methods=['POST'])
def upload_chunk():
    """
    Recibe fragmentos de un ZIP grande. Estados:
    UPLOADING → (último chunk) → ASSEMBLED → PROCESSING → READY → CLEAN
    """
    # Todos los usuarios autenticados pueden subir; el admin mantiene control global.
    current_user = get_auth_user()
    if not current_user:
        return jsonify({"error": "Debes iniciar sesión para subir multitracks."}), 401

    # Guardián de disco
    ok, free_gb = check_disk_space()
    if not ok:
        return jsonify({
            "error": f"Espacio en disco insuficiente ({free_gb} GB libres, mínimo 8 GB). Libera espacio antes de subir."
        }), 507

    upload_id = request.form.get('uploadId')
    chunk_idx = int(request.form.get('chunkIndex', 0))
    total_chunks = int(request.form.get('totalChunks', 1))
    
    if not upload_id:
        return jsonify({"error": "uploadId requerido"}), 400
    
    chunk_file = request.files.get('chunk')
    if not chunk_file:
        return jsonify({"error": "No se recibió el fragmento de archivo"}), 400

    # Guardar chunk en directorio temporal
    upload_dir = os.path.join(CHUNKS_DIR, secure_filename(upload_id))
    os.makedirs(upload_dir, exist_ok=True)
    
    chunk_path = os.path.join(upload_dir, f"part_{chunk_idx}")
    chunk_file.save(chunk_path)
    
    print(f"[UPLOADING] Chunk {chunk_idx + 1}/{total_chunks} para '{upload_id}'")

    # Si NO es el último chunk, solo confirmar recepción
    if chunk_idx < total_chunks - 1:
        return jsonify({
            "status": "chunk_received",
            "chunkIndex": chunk_idx,
            "totalChunks": total_chunks
        })

    # ═══ ÚLTIMO CHUNK: Ensamblar y procesar ═══
    
    # Leer metadata del último chunk
    title = request.form.get('title', 'Sin Titulo')
    artist = request.form.get('artist', 'Desconocido')
    bpm = float(request.form.get('bpm', 120.0))
    key = request.form.get('key', 'C')
    
    # Guardar carátula si viene
    cover_path = None
    cover_file = request.files.get('cover')
    if cover_file and cover_file.filename:
        cover_path = os.path.join(upload_dir, 'cover_temp' + os.path.splitext(cover_file.filename)[1])
        cover_file.save(cover_path)

    try:
        # ASSEMBLED: Unir todas las partes en un solo ZIP
        assembled_zip = os.path.join(TEMP_DIR, f"{upload_id}_assembled.zip")
        print(f"[ASSEMBLED] Ensamblando {total_chunks} partes en ZIP...")
        
        with open(assembled_zip, 'wb') as out:
            for i in range(total_chunks):
                part_path = os.path.join(upload_dir, f"part_{i}")
                if not os.path.exists(part_path):
                    return jsonify({"error": f"Falta el fragmento {i}"}), 400
                with open(part_path, 'rb') as part:
                    shutil.copyfileobj(part, out)

        # Verificar que el ZIP es válido
        try:
            with zipfile.ZipFile(assembled_zip, 'r') as test:
                test.testzip()
        except zipfile.BadZipFile:
            return jsonify({"error": "El archivo ensamblado no es un ZIP válido"}), 400

        # PROCESSING → READY: Usar el pipeline compartido
        metadata, warnings = process_assembled_zip(
            assembled_zip, title, artist, bpm, key, cover_path,
            group_id=current_user.get('grupo_id'),
            group_name=current_user.get('group_name'),
            user_id=current_user.get('id')
        )
        
        if metadata is None:
            return jsonify({"error": warnings[0] if warnings else "Error procesando"}), 400

        return jsonify({
            "status": "success",
            "message": f"¡'{title}' procesada! {len(metadata['stems'])} stems en FLAC.",
            "warnings": warnings,
            "song": metadata
        })

    except Exception as e:
        print(f"[ERROR] Error procesando upload {upload_id}: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        # CLEAN: Limpiar chunks y ZIP ensamblado
        if os.path.exists(upload_dir):
            shutil.rmtree(upload_dir)
        assembled_path = os.path.join(TEMP_DIR, f"{upload_id}_assembled.zip")
        if os.path.exists(assembled_path):
            os.remove(assembled_path)


@app.route('/api/upload', methods=['POST'])
def upload_multitrack():
    # Todos los usuarios autenticados pueden subir multitracks.
    current_user = get_auth_user()
    if not current_user:
        return jsonify({"error": "Debes iniciar sesión para subir multitracks."}), 401

    # Guardián de disco
    ok, free_gb = check_disk_space()
    if not ok:
        return jsonify({
            "error": f"Espacio en disco insuficiente ({free_gb} GB libres, mínimo 8 GB)."
        }), 507

    if 'file' not in request.files:
        return jsonify({"error": "No se encontró ningún archivo."}), 400
    
    file = request.files['file']
    if file.filename == '':
        return jsonify({"error": "Nombre de archivo vacío."}), 400
        
    if not file.filename.endswith('.zip'):
        return jsonify({"error": "Por favor sube un archivo .zip con los stems."}), 400
        
    # Read form data
    title = request.form.get('title', os.path.splitext(file.filename)[0].replace("_", " ").title())
    artist = request.form.get('artist', 'Desconocido')
    bpm = float(request.form.get('bpm', 120.0))
    key = request.form.get('key', 'C')
    
    cover_file = request.files.get('cover')
        
    # Guardar ZIP temporal
    zip_id = str(uuid.uuid4())[:8]
    zip_path = os.path.join(TEMP_DIR, f"{zip_id}.zip")
    extract_path = os.path.join(TEMP_DIR, zip_id)
    file.save(zip_path)
    
    warnings = []
    processed_stems = []
    category_counts = {}
    
    song_folder = secure_filename(title.replace(" ", "_"))
    song_out_dir = os.path.join(SONGS_DIR, song_folder)
    stems_out_dir = os.path.join(song_out_dir, 'stems')
    
    os.makedirs(stems_out_dir, exist_ok=True)
    
    cover_filename = "assets/user_sketch.png"
    if cover_file and cover_file.filename != '':
        ext = os.path.splitext(cover_file.filename)[1].lower()
        if ext in ['.jpg', '.jpeg', '.png', '.webp']:
            cname = f"cover{ext}"
            cover_file.save(os.path.join(song_out_dir, cname))
            cover_filename = f"songs/{song_folder}/{cname}"
    
    try:
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(extract_path)
            
        # Explorar archivos extraídos
        for root, dirs, files in os.walk(extract_path):
            for filename in files:
                if filename.startswith('__MACOSX') or filename.startswith('.'):
                    continue
                    
                ext = os.path.splitext(filename)[1].lower()
                filepath = os.path.join(root, filename)
                
                # Ignorar y advertir sobre archivos no de audio
                if ext not in AUDIO_EXTENSIONS:
                    warnings.append(f"Archivo ignorado (no es audio): {filename}")
                    continue
                    
                # Clasificar stem
                classification = classify_stem_filename(filename)
                
                # Generar ID único para no sobreescribir stems de la misma categoría
                cat = classification['category']
                if cat == 'other':
                    # Use a slug of the filename for 'other'
                    base_name = secure_filename(os.path.splitext(filename)[0].lower())
                    stem_id = base_name
                else:
                    category_counts[cat] = category_counts.get(cat, 0) + 1
                    count = category_counts[cat]
                    stem_id = cat if count == 1 else f"{cat}_{count}"
                
                # Convertir a FLAC
                out_filename = f"{stem_id}.flac"
                out_filepath = os.path.join(stems_out_dir, out_filename)
                
                print(f"Convirtiendo {filename} a FLAC ({out_filename})...")
                success = convert_to_flac(filepath, out_filepath)
                
                if success:
                    # Guardamos 'id' real para el mixer
                    classification['id'] = stem_id
                    classification['filename'] = f"stems/{out_filename}"
                    classification['original'] = filename
                    if classification['category'] == 'other':
                        classification['label'] = os.path.splitext(filename)[0][:12].upper()
                    processed_stems.append(classification)
                else:
                    warnings.append(f"Fallo al convertir {filename}")
                    
        if not processed_stems:
            return jsonify({"error": "No se encontraron audios válidos en el ZIP."}), 400
            
        # Ordenar stems
        priority_order = ["click", "guide", "drums", "bass", "keys", "pad", "guitars", "vocals", "other"]
        processed_stems.sort(key=lambda s: priority_order.index(s["category"]) if s["category"] in priority_order else 99)
        
        user_group_id = current_user.get('grupo_id') if current_user else None
        user_group_name = current_user.get('group_name') if current_user else None
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
        if user_group_id and user_group_id not in ('default', 'admin') and user_group_id not in group_ids:
            group_ids.append(user_group_id)

        # Guardar metadata
        metadata = {
            "id": song_folder,
            "title": title,
            "artist": artist,
            "bpm": bpm,
            "key": key,
            "cover": cover_filename,
            "group_id": user_group_id if user_group_id not in ('default', 'admin') else None,
            "group_name": user_group_name,
            "group_ids": group_ids,
            "stems": processed_stems
        }
        
        with open(meta_file_path, 'w', encoding='utf-8') as f:
            json.dump(metadata, f, indent=2, ensure_ascii=False)

        if user_group_id and user_group_id not in ('default', 'admin'):
            assign_song_to_group(user_group_id, song_folder, title, current_user.get('id'))
            
        return jsonify({
            "message": "Canción subida y procesada correctamente",
            "warnings": warnings,
            "metadata": metadata
        })
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        # Limpiar temporales
        if os.path.exists(zip_path):
            os.remove(zip_path)
        if os.path.exists(extract_path):
            shutil.rmtree(extract_path)


@app.route('/api/songs/<song_id>/mapping', methods=['PUT'])
def update_mapping(song_id):
    song_folder = secure_filename(song_id)
    meta_path = os.path.join(SONGS_DIR, song_folder, 'metadata.json')
    if not os.path.exists(meta_path):
        return jsonify({"error": "Canción no encontrada"}), 404
        
    try:
        new_mapping = request.json
        with open(meta_path, 'r', encoding='utf-8') as f:
            metadata = json.load(f)
            
        # Actualizar labels, colors o eliminaciones según lo mande el frontend
        if 'stems' in new_mapping:
            metadata['stems'] = new_mapping['stems']
            
        with open(meta_path, 'w', encoding='utf-8') as f:
            json.dump(metadata, f, indent=2)
            
        return jsonify({"message": "Mapeo actualizado"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/api/songs/<song_id>/sections', methods=['PUT'])
def update_sections(song_id):
    new_sections = request.json
    if new_sections is None or not isinstance(new_sections, list):
        return jsonify({"error": "Formato de secciones inválido"}), 400

    updated_meta = False
    norm_target = normalize_song_key(song_id)

    # 1. Actualizar en data/songs/<folder>/metadata.json si la carpeta física existe
    song_folder = secure_filename(song_id)
    meta_path = os.path.join(SONGS_DIR, song_folder, 'metadata.json')
    if not os.path.exists(meta_path) and os.path.exists(SONGS_DIR):
        for d in os.listdir(SONGS_DIR):
            cand_path = os.path.join(SONGS_DIR, d, 'metadata.json')
            if os.path.isfile(cand_path):
                try:
                    with open(cand_path, 'r', encoding='utf-8') as f:
                        m = json.load(f)
                    if (
                        normalize_song_key(m.get('id')) == norm_target
                        or normalize_song_key(m.get('title')) == norm_target
                        or normalize_song_key(d) == norm_target
                    ):
                        meta_path = cand_path
                        break
                except Exception:
                    pass

    if os.path.exists(meta_path):
        try:
            with open(meta_path, 'r', encoding='utf-8') as f:
                metadata = json.load(f)
            metadata['sections'] = new_sections
            with open(meta_path, 'w', encoding='utf-8') as f:
                json.dump(metadata, f, indent=2, ensure_ascii=False)
            updated_meta = True
        except Exception as e:
            print(f"Error actualizando metadata de {meta_path}: {e}")

    # 2. Actualizar también en backend/setlists.json para que quede persistido en todas las setlists
    updated_setlist = False
    if os.path.exists(SETLISTS_FILE):
        try:
            with open(SETLISTS_FILE, 'r', encoding='utf-8') as f:
                all_setlists = json.load(f)
            if isinstance(all_setlists, list):
                for sl in all_setlists:
                    for s in (sl.get('songs') or []):
                        if (
                            normalize_song_key(s.get('id')) == norm_target
                            or normalize_song_key(s.get('folderId')) == norm_target
                            or normalize_song_key(s.get('title')) == norm_target
                        ):
                            s['sections'] = new_sections
                            updated_setlist = True
                if updated_setlist:
                    with open(SETLISTS_FILE, 'w', encoding='utf-8') as f:
                        json.dump(all_setlists, f, indent=2, ensure_ascii=False)
        except Exception as e:
            print(f"Error actualizando setlists.json con nuevas secciones: {e}")

    return jsonify({
        "status": "success",
        "message": "Secciones de la canción actualizadas correctamente.",
        "updated_meta": updated_meta,
        "updated_setlist": updated_setlist,
        "sections": new_sections
    }), 200


@app.route('/api/songs/import-from-cloud', methods=['POST'])
def import_song_from_cloud():
    current_user = get_auth_user()
    user_group_id = current_user.get('grupo_id') if current_user else None
    user_group_name = current_user.get('group_name') if current_user else None

    data = request.json or {}
    download_url = data.get('downloadUrl')
    title = data.get('title', 'Sin Titulo').strip()
    artist = data.get('artist', 'Desconocido').strip()
    bpm = float(data.get('bpm', 120.0))
    key = data.get('key', 'C').strip()
    
    if not download_url:
        return jsonify({"error": "downloadUrl requerida"}), 400
        
    safe_folder = secure_filename(title.replace(" ", "_"))
    song_out_dir = os.path.join(SONGS_DIR, safe_folder)
    meta_path = os.path.join(song_out_dir, 'metadata.json')
    
    # Si ya existe en disco local con su metadata, vincular al grupo actual y retornar de inmediato
    if os.path.exists(meta_path):
        try:
            with open(meta_path, 'r', encoding='utf-8') as f:
                meta = json.load(f)
            if user_group_id and user_group_id not in ('default', 'admin'):
                group_ids = list(meta.get('group_ids') or [])
                if meta.get('group_id') and meta.get('group_id') not in group_ids:
                    group_ids.append(meta.get('group_id'))
                if user_group_id not in group_ids:
                    group_ids.append(user_group_id)
                    meta['group_ids'] = group_ids
                    if not meta.get('group_id'):
                        meta['group_id'] = user_group_id
                        meta['group_name'] = user_group_name
                    with open(meta_path, 'w', encoding='utf-8') as fw:
                        json.dump(meta, fw, indent=2, ensure_ascii=False)
                assign_song_to_group(user_group_id, safe_folder, title, current_user.get('id'))
            return jsonify({
                "status": "already_exists",
                "message": "La canción ya existe en el servidor local.",
                "metadata": meta
            }), 200
        except Exception:
            pass

    stems_out_dir = os.path.join(song_out_dir, 'stems')
    os.makedirs(stems_out_dir, exist_ok=True)
    
    temp_zip = os.path.join(TEMP_DIR, f"{safe_folder}_temp.zip")
    extract_path = os.path.join(TEMP_DIR, f"{safe_folder}_extract")
    
    try:
        print(f"Descargando multitrack de la nube desde {download_url}...")
        req = urllib.request.Request(download_url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=90) as response, open(temp_zip, 'wb') as out_file:
            shutil.copyfileobj(response, out_file)
            
        print(f"Extrayendo archivo ZIP de {title}...")
        with zipfile.ZipFile(temp_zip, 'r') as zip_ref:
            zip_ref.extractall(extract_path)
            
        processed_stems = []
        category_counts = {}
        
        for root, dirs, files in os.walk(extract_path):
            for filename in files:
                if filename.startswith('__MACOSX') or filename.startswith('.'):
                    continue
                ext = os.path.splitext(filename)[1].lower()
                filepath = os.path.join(root, filename)
                if ext not in AUDIO_EXTENSIONS:
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
                
                # Convertir a FLAC (igual que /api/upload)
                out_filename = f"{stem_id}.flac"
                out_filepath = os.path.join(stems_out_dir, out_filename)
                
                print(f"Convirtiendo {filename} a FLAC ({out_filename})...")
                success = convert_to_flac(filepath, out_filepath)
                
                if success:
                    classification['id'] = stem_id
                    classification['filename'] = f"stems/{out_filename}"
                    classification['original'] = filename
                    if classification.get('category') == 'other':
                        classification['label'] = os.path.splitext(filename)[0][:12].upper()
                    processed_stems.append(classification)
                else:
                    print(f"  ⚠ Fallo al convertir {filename}, guardando en formato original...")
                    fallback_filename = f"{stem_id}{ext}"
                    fallback_path = os.path.join(stems_out_dir, fallback_filename)
                    shutil.copy2(filepath, fallback_path)
                    classification['id'] = stem_id
                    classification['filename'] = f"stems/{fallback_filename}"
                    classification['original'] = filename
                    if classification.get('category') == 'other':
                        classification['label'] = os.path.splitext(filename)[0][:12].upper()
                    processed_stems.append(classification)
                
        priority_order = ["click", "guide", "drums", "bass", "keys", "pad", "guitars", "vocals", "other"]
        processed_stems.sort(key=lambda s: priority_order.index(s["category"]) if s["category"] in priority_order else 99)
        
        group_ids = [user_group_id] if (user_group_id and user_group_id not in ('default', 'admin')) else []

        metadata = {
            "id": safe_folder,
            "title": title,
            "artist": artist,
            "bpm": bpm,
            "key": key,
            "cover": f"songs/{safe_folder}/cover.jpg" if os.path.exists(os.path.join(song_out_dir, 'cover.jpg')) else None,
            "group_id": user_group_id if user_group_id not in ('default', 'admin') else None,
            "group_name": user_group_name,
            "group_ids": group_ids,
            "stems": processed_stems,
            "sections": [
                {"name": "INTRO", "bar": 0, "len": 8},
                {"name": "VERSO", "bar": 8, "len": 16},
                {"name": "CORO", "bar": 24, "len": 16}
            ]
        }
        
        with open(meta_path, 'w', encoding='utf-8') as f:
            json.dump(metadata, f, indent=2, ensure_ascii=False)

        if user_group_id and user_group_id not in ('default', 'admin'):
            assign_song_to_group(user_group_id, safe_folder, title, current_user.get('id'))
            
        print(f"Canción '{title}' importada a local exitosamente con {len(processed_stems)} stems.")
        return jsonify({
            "status": "success",
            "message": f"Canción '{title}' guardada localmente con éxito",
            "metadata": metadata
        }), 200
    except Exception as e:
        print(f"Error importando desde la nube: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        if os.path.exists(temp_zip):
            try: os.remove(temp_zip)
            except: pass
        if os.path.exists(extract_path):
            try: shutil.rmtree(extract_path)
            except: pass


@app.route('/api/songs', methods=['GET'])
def list_songs():
    current_user = get_auth_user()
    # 1) Si no hay logeo (Invitado), no cargan canciones
    if not current_user:
        return jsonify([]), 200

    all_songs = []
    if os.path.exists(SONGS_DIR):
        for folder in os.listdir(SONGS_DIR):
            meta_path = os.path.join(SONGS_DIR, folder, 'metadata.json')
            if os.path.isfile(meta_path):
                try:
                    with open(meta_path, 'r', encoding='utf-8') as f:
                        all_songs.append(json.load(f))
                except Exception as e:
                    print(f"Error leyendo {meta_path}: {e}")

    # Catalogo compartido: todos los usuarios autenticados ven todas las canciones
    return jsonify(all_songs), 200

