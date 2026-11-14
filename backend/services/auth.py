"""
auth_db.py — Módulo de Autenticación, Roles y Códigos de Invitación para PULSO
Utiliza SQLite3 y werkzeug.security para máxima portabilidad y seguridad sin dependencias externas.
"""
import os
import re
import unicodedata
import sqlite3
import secrets
import string
from datetime import datetime, timedelta
from werkzeug.security import generate_password_hash, check_password_hash

from backend.config import DB_DIR, DB_PATH

os.makedirs(DB_DIR, exist_ok=True)

def get_connection():
    """Obtiene una conexión a la base de datos SQLite con soporte para Row dicts."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn

def init_auth_db():
    """Inicializa las tablas de usuarios, invitaciones y sesiones."""
    conn = get_connection()
    cursor = conn.cursor()

    # 1. Tabla de Usuarios
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        role TEXT CHECK(role IN ('admin', 'user', 'lider', 'miembro')) DEFAULT 'user',
        grupo_id TEXT DEFAULT 'default',
        leadership_level TEXT CHECK(leadership_level IN ('leader', 'subleader', 'member')) DEFAULT 'member',
        must_change_password INTEGER DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_by INTEGER,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (created_by) REFERENCES users(id)
    )
    """)

    # 2. Tabla de Códigos de Invitación
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS invite_codes (
        code TEXT PRIMARY KEY,
        role TEXT CHECK(role IN ('admin', 'user', 'lider', 'miembro')) NOT NULL,
        created_by INTEGER,
        used_by INTEGER,
        group_id TEXT,
        group_name TEXT,
        used_at TIMESTAMP,
        expires_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (created_by) REFERENCES users(id),
        FOREIGN KEY (used_by) REFERENCES users(id)
    )
    """)

    # 3. Tabla de Sesiones Activas
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS sessions (
        token TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        expires_at TIMESTAMP NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    )
    """)

    # 4. Tabla de Canciones por Grupo (Aislamiento de catálogo por grupo)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS group_songs (
        group_id TEXT NOT NULL,
        song_key TEXT NOT NULL,
        title TEXT,
        added_by INTEGER,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (group_id, song_key)
    )
    """)

    conn.commit()

    # Migraciones ligeras para instalaciones creadas antes de grupos y recuperacion.
    user_columns = {row['name'] for row in cursor.execute("PRAGMA table_info(users)")}
    if 'leadership_level' not in user_columns:
        cursor.execute("ALTER TABLE users ADD COLUMN leadership_level TEXT DEFAULT 'member'")
    if 'must_change_password' not in user_columns:
        cursor.execute("ALTER TABLE users ADD COLUMN must_change_password INTEGER DEFAULT 0")

    invite_columns = {row['name'] for row in cursor.execute("PRAGMA table_info(invite_codes)")}
    if 'group_id' not in invite_columns:
        cursor.execute("ALTER TABLE invite_codes ADD COLUMN group_id TEXT")
    if 'group_name' not in invite_columns:
        cursor.execute("ALTER TABLE invite_codes ADD COLUMN group_name TEXT")
    cursor.execute("UPDATE users SET leadership_level = 'member' WHERE leadership_level IS NULL")
    conn.commit()

    # Si no existe ningún usuario, crear el código de configuración inicial maestro
    cursor.execute("SELECT COUNT(*) as count FROM users")
    user_count = cursor.fetchone()['count']

    if user_count == 0:
        setup_code = "PULSO-ADMIN-SETUP"
        cursor.execute("SELECT code FROM invite_codes WHERE code = ?", (setup_code,))
        if not cursor.fetchone():
            cursor.execute("""
            INSERT INTO invite_codes (code, role, created_at)
            VALUES (?, 'admin', CURRENT_TIMESTAMP)
            """, (setup_code,))
            conn.commit()
            print("=" * 60)
            print("[*] PULSO SETUP: No hay usuarios registrados.")
            print(f"   Codigo de invitacion de Administrador generado:")
            print(f"   -> {setup_code}")
            print("   Usa este codigo en la pantalla de registro para crear tu usuario Admin.")
            print("=" * 60)

    conn.close()

# ---------- GESTIÓN DE CÓDIGOS DE INVITACIÓN ----------

def generate_random_code(prefix="PULSO"):
    """Genera un código legible de 8 caracteres alfanuméricos en mayúsculas."""
    chars = "".join([c for c in string.ascii_uppercase + string.digits if c not in 'OI01'])
    random_part = ''.join(secrets.choice(chars) for _ in range(8))
    return f"{prefix}-{random_part[:4]}-{random_part[4:]}"

def create_invite_code(role='miembro', created_by_id=None, custom_code=None, days_valid=30, group_id=None, group_name=None):
    """Crea un nuevo código de invitación con un rol específico."""
    if role == 'user':
        role = 'miembro'
    if role not in ('admin', 'miembro'):
        raise ValueError("Rol inválido. Debe ser 'admin' o 'user'.")

    code = (custom_code.strip().upper() if custom_code else generate_random_code('USER' if role == 'miembro' else role.upper()))
    expires_at = (datetime.utcnow() + timedelta(days=days_valid)).strftime('%Y-%m-%d %H:%M:%S')

    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("""
        INSERT INTO invite_codes (code, role, created_by, group_id, group_name, expires_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """, (code, role, created_by_id, group_id, group_name, expires_at))
        conn.commit()
        return {
            "code": code,
            "role": 'user' if role == 'miembro' else role,
            "group_id": group_id,
            "group_name": group_name,
            "expires_at": expires_at
        }
    finally:
        conn.close()

def list_invites():
    """Lista todos los códigos de invitación con estado y creador."""
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("""
        SELECT 
            i.code, i.role, i.group_id, i.group_name, i.created_at, i.expires_at, i.used_at,
            u_creator.username as created_by_username,
            u_user.username as used_by_username
        FROM invite_codes i
        LEFT JOIN users u_creator ON i.created_by = u_creator.id
        LEFT JOIN users u_user ON i.used_by = u_user.id
        ORDER BY i.created_at DESC
        """)
        rows = cursor.fetchall()
        invites = []
        for r in rows:
            is_used = r['used_at'] is not None
            invites.append({
                "code": r['code'],
                "role": 'user' if r['role'] == 'miembro' else r['role'],
                "group_id": r['group_id'],
                "group_name": r['group_name'],
                "is_used": is_used,
                "created_by": r['created_by_username'] or "Sistema",
                "used_by": r['used_by_username'],
                "used_at": r['used_at'],
                "created_at": r['created_at'],
                "expires_at": r['expires_at']
            })
        return invites
    finally:
        conn.close()

def validate_invite_code(code):
    """Valida si un código de invitación existe, no ha sido usado y no expiró."""
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT * FROM invite_codes WHERE code = ?", (code.strip().upper(),))
        row = cursor.fetchone()
        if not row:
            return False, "Código de invitación no válido."
        if row['used_by'] is not None:
            return False, "Este código de invitación ya ha sido utilizado."
        if row['expires_at']:
            try:
                exp = datetime.strptime(row['expires_at'], '%Y-%m-%d %H:%M:%S')
                if datetime.utcnow() > exp:
                    return False, "El código de invitación ha expirado."
            except Exception:
                pass
        return True, row
    finally:
        conn.close()

# ---------- GESTIÓN DE USUARIOS Y AUTENTICACIÓN ----------

def register_user_with_invite(username, password, invite_code, group_mode='none', group_id=None, group_name=None):
    """Registra un nuevo usuario canjeando un código de invitación."""
    username = username.strip().lower()
    if len(username) < 3:
        raise ValueError("El nombre de usuario debe tener al menos 3 caracteres.")
    if len(password) < 6:
        raise ValueError("La contraseña debe tener al menos 6 caracteres.")

    valid, invite_or_err = validate_invite_code(invite_code)
    if not valid:
        raise ValueError(invite_or_err)

    invite = invite_or_err
    role = 'admin' if invite['role'] == 'admin' else 'user'
    stored_role = 'admin' if role == 'admin' else 'miembro'
    leadership_level = 'member'
    resolved_group_id = invite['group_id'] or group_id or 'default'

    conn = get_connection()
    cursor = conn.cursor()
    try:
        # Verificar si el nombre de usuario ya existe
        cursor.execute("SELECT id FROM users WHERE username = ?", (username,))
        if cursor.fetchone():
            raise ValueError(f"El nombre de usuario '{username}' ya está en uso.")

        # Hashear la contraseña
        pwd_hash = generate_password_hash(password, method='scrypt')

        if role == 'admin':
            resolved_group_id = 'admin'
            leadership_level = 'leader'
        elif role == 'user' and invite['group_id']:
            # La invitación ya fue emitida por un líder/sublíder para unirse directamente a su grupo
            group = cursor.execute("SELECT id FROM groups WHERE id = ?", (invite['group_id'],)).fetchone()
            if not group:
                raise ValueError("El grupo de esta invitación ya no existe.")
            resolved_group_id = invite['group_id']
            leadership_level = 'member'
        elif role == 'user' and group_mode == 'create':
            if not group_name or len(group_name.strip()) < 2:
                raise ValueError("Escribe el nombre del grupo o ministerio.")
            resolved_group_id = generate_group_id()
            cursor.execute(
                "INSERT INTO groups (id, name, created_by) VALUES (?, ?, NULL)",
                (resolved_group_id, group_name.strip())
            )
            leadership_level = 'leader'
        elif role == 'user' and group_mode == 'join':
            if not group_id:
                raise ValueError("Selecciona un grupo para unirte.")
            group = cursor.execute("SELECT id FROM groups WHERE id = ?", (group_id,)).fetchone()
            if not group:
                raise ValueError("El grupo seleccionado ya no existe.")
            resolved_group_id = group_id
            leadership_level = 'member'
        elif role == 'user':
            raise ValueError("Elige si vas a crear o unirte a un grupo.")

        cursor.execute("""
        INSERT INTO users (username, password_hash, role, grupo_id, leadership_level)
        VALUES (?, ?, ?, ?, ?)
        """, (username, pwd_hash, stored_role, resolved_group_id, leadership_level))
        user_id = cursor.lastrowid

        if leadership_level == 'leader':
            cursor.execute("UPDATE groups SET created_by = ? WHERE id = ?", (user_id, resolved_group_id))

        # Marcar código como usado
        now_str = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')
        cursor.execute("""
        UPDATE invite_codes 
        SET used_by = ?, used_at = ?
        WHERE code = ?
        """, (user_id, now_str, invite['code']))

        conn.commit()

        group_row = cursor.execute("SELECT name FROM groups WHERE id = ?", (resolved_group_id,)).fetchone()

        return {
            "id": user_id,
            "username": username,
            "role": role,
            "grupo_id": resolved_group_id,
            "group_name": group_row['name'] if group_row else None,
            "leadership_level": leadership_level,
            "must_change_password": False
        }
    finally:
        conn.close()

def authenticate_user(username, password):
    """Autentica un usuario con nombre y contraseña."""
    username = username.strip().lower()
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("""
            SELECT u.*, g.name AS group_name
            FROM users u LEFT JOIN groups g ON g.id = u.grupo_id
            WHERE u.username = ?
        """, (username,))
        user = cursor.fetchone()
        if not user:
            return None
        if check_password_hash(user['password_hash'], password):
            return {
                "id": user['id'],
                "username": user['username'],
                "role": 'user' if user['role'] == 'miembro' else user['role'],
                "grupo_id": user['grupo_id'],
                "group_name": user['group_name'],
                "leadership_level": user['leadership_level'] or 'member',
                "must_change_password": bool(user['must_change_password']),
                "created_at": user['created_at']
            }
        return None
    finally:
        conn.close()

# ---------- GESTIÓN DE SESIONES ----------

def create_user_session(user_id, days_valid=30):
    """Crea un token de sesión criptográfico para el usuario."""
    token = secrets.token_hex(32)
    expires_at = (datetime.utcnow() + timedelta(days=days_valid)).strftime('%Y-%m-%d %H:%M:%S')

    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("""
        INSERT INTO sessions (token, user_id, expires_at)
        VALUES (?, ?, ?)
        """, (token, user_id, expires_at))
        conn.commit()
        return token
    finally:
        conn.close()

def get_user_from_token(token):
    """Valida un token y devuelve el usuario si la sesión es válida."""
    if not token:
        return None

    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("""
         SELECT u.id, u.username, u.role, u.grupo_id, g.name AS group_name, u.leadership_level,
             u.must_change_password, s.expires_at
        FROM sessions s
        JOIN users u ON s.user_id = u.id
        LEFT JOIN groups g ON g.id = u.grupo_id
        WHERE s.token = ?
        """, (token,))
        row = cursor.fetchone()
        if not row:
            return None

        # Verificar expiración
        try:
            exp = datetime.strptime(row['expires_at'], '%Y-%m-%d %H:%M:%S')
            if datetime.utcnow() > exp:
                delete_session(token)
                return None
        except Exception:
            pass

        return {
            "id": row['id'],
            "username": row['username'],
            "role": 'user' if row['role'] == 'miembro' else row['role'],
            "grupo_id": row['grupo_id']
            ,"group_name": row['group_name']
            ,"leadership_level": row['leadership_level'] or 'member'
            ,"must_change_password": bool(row['must_change_password'])
        }
    finally:
        conn.close()

def delete_session(token):
    """Elimina una sesión activa (Logout)."""
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("DELETE FROM sessions WHERE token = ?", (token,))
        conn.commit()
    finally:
        conn.close()

def generate_group_id():
    return f"GRP-{secrets.token_hex(3).upper()}"

def list_groups_with_members():
    conn = get_connection()
    try:
        groups = conn.execute("SELECT id, name, created_by, created_at FROM groups ORDER BY name").fetchall()
        result = []
        for group in groups:
            members = conn.execute("""
                SELECT id, username, role, leadership_level, created_at
                FROM users WHERE grupo_id = ? ORDER BY
                CASE leadership_level WHEN 'leader' THEN 0 WHEN 'subleader' THEN 1 ELSE 2 END,
                username
            """, (group['id'],)).fetchall()
            result.append({"id": group['id'], "name": group['name'], "created_by": group['created_by'],
                           "created_at": group['created_at'], "members": [dict(member) for member in members]})
        return result
    finally:
        conn.close()

def list_groups():
    conn = get_connection()
    try:
        rows = conn.execute("SELECT id, name FROM groups ORDER BY name").fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()

def get_group_with_members(group_id):
    conn = get_connection()
    try:
        group = conn.execute("SELECT id, name, created_by, created_at FROM groups WHERE id = ?", (group_id,)).fetchone()
        if not group:
            return None
        members = conn.execute("""
            SELECT id, username, leadership_level, created_at
            FROM users WHERE grupo_id = ? ORDER BY
            CASE leadership_level WHEN 'leader' THEN 0 WHEN 'subleader' THEN 1 ELSE 2 END,
            username
        """, (group_id,)).fetchall()
        return {"id": group['id'], "name": group['name'], "created_by": group['created_by'],
                "created_at": group['created_at'], "members": [dict(member) for member in members]}
    finally:
        conn.close()

def set_password_and_require_change(user_id, temporary_password):
    conn = get_connection()
    try:
        conn.execute("UPDATE users SET password_hash = ?, must_change_password = 1 WHERE id = ?",
                     (generate_password_hash(temporary_password, method='scrypt'), user_id))
        conn.commit()
    finally:
        conn.close()

def change_user_password(user_id, new_password):
    if len(new_password) < 6:
        raise ValueError("La contraseña debe tener al menos 6 caracteres.")
    conn = get_connection()
    try:
        conn.execute("UPDATE users SET password_hash = ?, must_change_password = 0 WHERE id = ?",
                     (generate_password_hash(new_password, method='scrypt'), user_id))
        conn.commit()
    finally:
        conn.close()

def normalize_song_key(val):
    """Normaliza un título o ID de canción (sin acentos, minúsculas, alfanumérico) para cruce exacto."""
    if not val:
        return ""
    s = str(val).strip().lower()
    s = unicodedata.normalize('NFD', s)
    s = ''.join(c for c in s if unicodedata.category(c) != 'Mn')
    s = re.sub(r'[^a-z0-9]+', '_', s).strip('_')
    return s

def assign_song_to_group(group_id, song_id=None, title=None, user_id=None):
    """Registra una canción (por su id y/o título) como perteneciente a un grupo específico."""
    if not group_id or group_id in ('default', 'admin'):
        return
    keys_to_add = set()
    if song_id:
        k1 = normalize_song_key(song_id)
        if k1:
            keys_to_add.add(k1)
    if title:
        k2 = normalize_song_key(title)
        if k2:
            keys_to_add.add(k2)
    if not keys_to_add:
        return

    conn = get_connection()
    try:
        for k in keys_to_add:
            conn.execute("""
                INSERT OR IGNORE INTO group_songs (group_id, song_key, title, added_by)
                VALUES (?, ?, ?, ?)
            """, (group_id, k, title or song_id, user_id))
        conn.commit()
    finally:
        conn.close()

def get_group_song_keys(group_id):
    """Devuelve el conjunto de song_keys normalizados que pertenecen a un grupo."""
    if not group_id or group_id == 'default':
        return set()
    conn = get_connection()
    try:
        rows = conn.execute("SELECT song_key, title FROM group_songs WHERE group_id = ?", (group_id,)).fetchall()
        keys = set()
        for r in rows:
            if r['song_key']:
                keys.add(r['song_key'])
                keys.add(normalize_song_key(r['song_key']))
            if r['title']:
                keys.add(normalize_song_key(r['title']))
        return keys
    finally:
        conn.close()

def get_all_groups_map():
    """Devuelve un diccionario {group_id: group_name} de todos los grupos."""
    conn = get_connection()
    try:
        rows = conn.execute("SELECT id, name FROM groups").fetchall()
        return {r['id']: r['name'] for r in rows}
    finally:
        conn.close()

# Auto-inicializar tablas al importar
init_auth_db()
