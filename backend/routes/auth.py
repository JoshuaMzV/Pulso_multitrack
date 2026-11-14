import secrets
import string
from flask import request, jsonify
from backend.services.auth import register_user_with_invite, authenticate_user, create_user_session, delete_session, create_invite_code, list_invites, validate_invite_code, list_groups_with_members, set_password_and_require_change, change_user_password, list_groups, get_group_with_members, assign_song_to_group, get_all_groups_map
from flask import Blueprint
from backend.services.session import get_auth_user

app = Blueprint("auth", __name__)

@app.route('/api/auth/register', methods=['POST'])
def auth_register():
    """Registra un nuevo usuario canjeando un código de invitación."""
    data = request.json or {}
    username = data.get('username', '').strip()
    password = data.get('password', '').strip()
    invite_code = data.get('invite_code', '').strip()
    group_mode = data.get('group_mode', 'none').strip().lower()
    group_id = data.get('group_id')
    group_name = data.get('group_name', '').strip()

    if not username or not password or not invite_code:
        return jsonify({"error": "Todos los campos son requeridos (usuario, contraseña y código de invitación)."}), 400

    try:
        user = register_user_with_invite(username, password, invite_code, group_mode, group_id, group_name)
        token = create_user_session(user['id'])
        return jsonify({
            "status": "success",
            "message": f"¡Bienvenido a PULSO, {user['username']}! Te has registrado con rol '{user['role']}'.",
            "token": token,
            "user": user
        }), 201
    except ValueError as e:
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        print(f"Error en registro: {e}")
        return jsonify({"error": "Error interno al procesar el registro."}), 500


@app.route('/api/auth/login', methods=['POST'])
def auth_login():
    """Inicia sesión con usuario y contraseña."""
    data = request.json or {}
    username = data.get('username', '').strip()
    password = data.get('password', '').strip()

    if not username or not password:
        return jsonify({"error": "Usuario y contraseña requeridos."}), 400

    user = authenticate_user(username, password)
    if not user:
        return jsonify({"error": "Credenciales inválidas. Verifica tu usuario y contraseña."}), 401

    token = create_user_session(user['id'])
    return jsonify({
        "status": "success",
        "message": f"Sesión iniciada como '{user['username']}'.",
        "token": token,
        "user": user
    }), 200


@app.route('/api/auth/logout', methods=['POST'])
def auth_logout():
    """Cierra la sesión activa invalidando el token."""
    auth_header = request.headers.get('Authorization', '')
    token = None
    if auth_header.startswith('Bearer '):
        token = auth_header.split(' ', 1)[1].strip()
    elif 'X-Auth-Token' in request.headers:
        token = request.headers['X-Auth-Token'].strip()
    elif 'pulso_auth_token' in request.cookies:
        token = request.cookies['pulso_auth_token'].strip()

    if token:
        delete_session(token)
    return jsonify({"status": "success", "message": "Sesión cerrada correctamente."}), 200


@app.route('/api/auth/me', methods=['GET'])
def auth_me():
    """Devuelve los datos del usuario autenticado."""
    user = get_auth_user()
    if not user:
        return jsonify({"authenticated": False, "user": None}), 200
    return jsonify({
        "authenticated": True,
        "user": user
    }), 200


@app.route('/api/auth/check-invite', methods=['GET'])
def auth_check_invite():
    code = (request.args.get('code') or '').strip().upper()
    if not code:
        return jsonify({"valid": False, "error": "Código vacío"}), 400
    valid, row_or_err = validate_invite_code(code)
    if not valid:
        return jsonify({"valid": False, "error": row_or_err}), 200
    groups_map = get_all_groups_map()
    gid = row_or_err['group_id']
    gname = row_or_err['group_name'] or (groups_map.get(gid) if gid else None)
    return jsonify({
        "valid": True,
        "role": 'admin' if row_or_err['role'] == 'admin' else 'user',
        "group_id": gid,
        "group_name": gname
    }), 200


@app.route('/api/groups', methods=['GET'])
def public_list_groups():
    return jsonify({"groups": list_groups()}), 200


@app.route('/api/groups/current', methods=['GET'])
def current_group():
    current_user = get_auth_user()
    if not current_user or current_user.get('role') == 'admin':
        return jsonify({"group": None}), 200
    group_id = current_user.get('grupo_id')
    if not group_id or group_id == 'default':
        return jsonify({"group": None}), 200
    group = get_group_with_members(group_id)
    return jsonify({"group": group}), 200


@app.route('/api/groups/songs', methods=['GET', 'POST'])
def group_songs_endpoint():
    current_user = get_auth_user()
    if not current_user:
        if request.method == 'POST':
            return jsonify({"error": "Debes iniciar sesión."}), 401
        return jsonify({"authenticated": False, "all_access": False, "song_keys": []}), 200

    if request.method == 'POST':
        data = request.json or {}
        song_id = data.get('id') or data.get('song_id') or data.get('folderId')
        title = data.get('title')
        target_group = data.get('group_id') if current_user.get('role') == 'admin' else current_user.get('grupo_id')
        if target_group and target_group not in ('default', 'admin'):
            assign_song_to_group(target_group, song_id=song_id, title=title, user_id=current_user.get('id'))
        return jsonify({"status": "success"}), 200

    # Catalogo compartido: all_access True para todos los usuarios autenticados
    return jsonify({
        "authenticated": True,
        "all_access": True,
        "role": current_user.get('role', 'user'),
        "group_id": current_user.get('grupo_id'),
        "group_name": current_user.get('group_name'),
        "song_keys": []
    }), 200


@app.route('/api/admin/invite', methods=['POST'])
def admin_create_invite():
    """Genera un nuevo código de invitación. Requiere rol 'admin'."""
    current_user = get_auth_user()
    if not current_user or current_user.get('role') != 'admin':
        return jsonify({"error": "Acceso denegado. Se requiere rol de Administrador."}), 403

    data = request.json or {}
    role = data.get('role', 'user').lower().strip()
    custom_code = data.get('custom_code')
    days_valid = int(data.get('days_valid', 30))
    group_name = data.get('group_name', '').strip() or None

    if role != 'user':
        return jsonify({"error": "El administrador solo puede generar invitaciones USER."}), 400

    try:
        invite = create_invite_code(role='user', created_by_id=current_user['id'], custom_code=custom_code,
                days_valid=days_valid)
        return jsonify({
            "status": "success",
            "message": f"Código de invitación para rol '{role}' creado con éxito.",
            "invite": invite
        }), 201
    except ValueError as e:
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        print(f"Error creando invitación: {e}")
        return jsonify({"error": "Error interno al generar código de invitación."}), 500


@app.route('/api/admin/invites', methods=['GET'])
def admin_list_invites():
    """Lista todos los códigos de invitación. Requiere rol 'admin'."""
    current_user = get_auth_user()
    if not current_user or current_user.get('role') != 'admin':
        return jsonify({"error": "Acceso denegado. Se requiere rol de Administrador."}), 403

    try:
        invites = list_invites()
        return jsonify({"invites": invites}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/api/admin/groups', methods=['GET'])
def admin_list_groups():
    current_user = get_auth_user()
    if not current_user or current_user.get('role') != 'admin':
        return jsonify({"error": "Acceso denegado. Se requiere rol de Administrador."}), 403
    return jsonify({"groups": list_groups_with_members()}), 200


@app.route('/api/admin/users/<int:user_id>/reset-password', methods=['POST'])
def admin_reset_password(user_id):
    current_user = get_auth_user()
    if not current_user or current_user.get('role') != 'admin':
        return jsonify({"error": "Acceso denegado. Se requiere rol de Administrador."}), 403

    alphabet = string.ascii_uppercase + string.digits
    temporary_password = 'PULSO-' + ''.join(secrets.choice(alphabet) for _ in range(8))
    try:
        set_password_and_require_change(user_id, temporary_password)
        return jsonify({"status": "success", "temporary_password": temporary_password,
                        "message": "Contraseña temporal creada. El usuario debe cambiarla al entrar."}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 404


@app.route('/api/auth/change-password', methods=['POST'])
def auth_change_password():
    current_user = get_auth_user()
    if not current_user:
        return jsonify({"error": "Debes iniciar sesión."}), 401
    new_password = (request.json or {}).get('new_password', '').strip()
    try:
        change_user_password(current_user['id'], new_password)
        return jsonify({"status": "success", "message": "Contraseña actualizada correctamente."}), 200
    except ValueError as e:
        return jsonify({"error": str(e)}), 400


@app.route('/api/admin/users/<int:user_id>', methods=['DELETE'])
def admin_delete_user(user_id):
    current_user = get_auth_user()
    if not current_user or current_user.get('role') != 'admin':
        return jsonify({"error": "Acceso denegado. Se requiere rol de Administrador."}), 403
    if current_user['id'] == user_id:
        return jsonify({"error": "No puedes eliminar tu propia cuenta de administrador."}), 400

    from backend.services.auth import get_connection
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM sessions WHERE user_id = ?", (user_id,))
        cursor.execute("DELETE FROM users WHERE id = ?", (user_id,))
        if cursor.rowcount == 0:
            return jsonify({"error": "Usuario no encontrado."}), 404
        conn.commit()
        return jsonify({"status": "success", "message": "Cuenta eliminada."}), 200
    finally:
        conn.close()


@app.route('/api/groups/invite', methods=['POST'])
def group_create_member_invite():
    current_user = get_auth_user()
    if not current_user or current_user.get('role') != 'user' or current_user.get('leadership_level') not in ('leader', 'subleader'):
        return jsonify({"error": "Solo el líder o sublíder pueden invitar miembros."}), 403
    try:
        invite = create_invite_code(role='user', created_by_id=current_user['id'],
                                   days_valid=int((request.json or {}).get('days_valid', 30)),
                                   group_id=current_user['grupo_id'],
                                   group_name=current_user.get('group_name'))
        return jsonify({"status": "success", "invite": invite}), 201
    except Exception as e:
        return jsonify({"error": str(e)}), 400


@app.route('/api/groups/members/<int:user_id>/leadership', methods=['PUT'])
def group_update_leadership(user_id):
    current_user = get_auth_user()
    if not current_user or current_user.get('leadership_level') != 'leader':
        return jsonify({"error": "Solo el líder general puede asignar al sublíder."}), 403

    level = (request.json or {}).get('leadership_level', 'member').strip().lower()
    if level not in ('subleader', 'member'):
        return jsonify({"error": "Nivel inválido."}), 400

    from backend.services.auth import get_connection
    conn = get_connection()
    try:
        target = conn.execute("SELECT id, grupo_id, leadership_level FROM users WHERE id = ?", (user_id,)).fetchone()
        if not target or target['grupo_id'] != current_user['grupo_id']:
            return jsonify({"error": "El usuario no pertenece a tu grupo."}), 404
        if target['id'] == current_user['id']:
            return jsonify({"error": "El líder general no puede cambiarse a sí mismo."}), 400
        if level == 'subleader':
            existing = conn.execute("""
                SELECT id FROM users WHERE grupo_id = ? AND leadership_level = 'subleader' AND id != ?
            """, (current_user['grupo_id'], user_id)).fetchone()
            if existing:
                return jsonify({"error": "Este grupo ya tiene un sublíder."}), 409
        conn.execute("UPDATE users SET leadership_level = ? WHERE id = ?", (level, user_id))
        conn.commit()
        return jsonify({"status": "success", "leadership_level": level}), 200
    finally:
        conn.close()

