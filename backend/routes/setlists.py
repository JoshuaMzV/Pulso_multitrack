import os
import json
from flask import request, jsonify
from backend.config import SETLISTS_FILE
from backend.services.auth import assign_song_to_group, get_all_groups_map
from flask import Blueprint
from backend.services.session import get_auth_user

app = Blueprint("setlists", __name__)

@app.route('/api/setlists', methods=['GET'])
def get_setlists():
    current_user = get_auth_user()
    # 1) Si no hay logeo (Invitado), retorna vacío total
    if not current_user:
        return jsonify([]), 200

    if not os.path.exists(SETLISTS_FILE):
        return jsonify([]), 200

    try:
        with open(SETLISTS_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
        if not isinstance(data, list):
            data = []

        groups_map = get_all_groups_map()
        for sl in data:
            gid = sl.get('group_id')
            if gid and not sl.get('group_name') and gid in groups_map:
                sl['group_name'] = groups_map[gid]

        # 3) El Admin puede verlo todo
        if current_user.get('role') == 'admin':
            return jsonify(data), 200

        # 2) Usuario de grupo: solo ve las setlists de su propio grupo
        user_group_id = current_user.get('grupo_id')
        if not user_group_id or user_group_id == 'default':
            return jsonify([]), 200

        visible = [sl for sl in data if sl.get('group_id') == user_group_id]
        return jsonify(visible), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/api/setlists', methods=['POST'])
def save_setlists():
    try:
        data = request.json
        if data is None or not isinstance(data, list):
            return jsonify({"error": "Datos inválidos"}), 400
        current_user = get_auth_user()
        if not current_user:
            return jsonify({"error": "Debes iniciar sesión para guardar setlists."}), 401

        existing = []
        if os.path.exists(SETLISTS_FILE):
            try:
                with open(SETLISTS_FILE, 'r', encoding='utf-8') as f:
                    existing = json.load(f)
                if not isinstance(existing, list):
                    existing = []
            except Exception:
                existing = []

        if current_user.get('role') != 'admin':
            user_group_id = current_user.get('grupo_id')
            user_group_name = current_user.get('group_name')
            if not user_group_id or user_group_id == 'default':
                return jsonify({"error": "No perteneces a un grupo activo para guardar setlists."}), 400

            for setlist in data:
                setlist['group_id'] = user_group_id
                setlist['group_name'] = user_group_name
                # Asegurar que todas las canciones de la setlist queden vinculadas al grupo
                for s in (setlist.get('songs') or []):
                    assign_song_to_group(
                        user_group_id,
                        song_id=s.get('folderId') or s.get('id'),
                        title=s.get('title'),
                        user_id=current_user.get('id')
                    )

            # Mantener intactas las setlists de otros grupos y reemplazar las de este grupo
            other_groups_setlists = [sl for sl in existing if sl.get('group_id') != user_group_id]
            final_data = other_groups_setlists + data
        else:
            # Si guarda el Admin, preservar group_id y group_name existentes de cada setlist
            existing_by_id = {
                (sl.get('id'), sl.get('group_id')): sl for sl in existing
            }
            existing_by_only_id = {sl.get('id'): sl for sl in existing if sl.get('id')}
            for setlist in data:
                if not setlist.get('group_id') and setlist.get('id') in existing_by_only_id:
                    orig = existing_by_only_id[setlist.get('id')]
                    if orig.get('group_id'):
                        setlist['group_id'] = orig.get('group_id')
                    if orig.get('group_name'):
                        setlist['group_name'] = orig.get('group_name')
                gid = setlist.get('group_id')
                if gid and gid not in ('default', 'admin'):
                    for s in (setlist.get('songs') or []):
                        assign_song_to_group(
                            gid,
                            song_id=s.get('folderId') or s.get('id'),
                            title=s.get('title'),
                            user_id=current_user.get('id')
                        )
            final_data = data

        with open(SETLISTS_FILE, 'w', encoding='utf-8') as f:
            json.dump(final_data, f, indent=2, ensure_ascii=False)
        print("Setlists actualizadas en el servidor local.")
        return jsonify({"status": "success", "message": "Setlists guardadas correctamente"}), 200
    except Exception as e:
        print(f"Error guardando setlists: {e}")
        return jsonify({"error": str(e)}), 500

