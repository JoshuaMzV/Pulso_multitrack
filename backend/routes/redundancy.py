"""Sesiones efímeras de ensayo para dos reproductores de la misma cuenta."""
import secrets
import time
from threading import Lock

from flask import Blueprint, jsonify, request
from backend.services.session import get_auth_user

app = Blueprint("redundancy", __name__)
rooms = {}
lock = Lock()


def clock_ms():
    return time.monotonic_ns() // 1_000_000


@app.route('/api/redundancy', methods=['POST'])
def rehearsal():
    user = get_auth_user()
    if not user:
        return jsonify(error='Inicia sesión en los dos equipos.'), 401
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify(error='Mensaje inválido.'), 400
    action, code, device, fingerprint = (data.get(k) for k in ('action', 'code', 'device', 'fingerprint'))
    if not isinstance(device, str) or not 8 <= len(device) <= 100 or not isinstance(code, str):
        return jsonify(error='Identificación inválida.'), 400
    if not isinstance(fingerprint, str) or len(fingerprint) != 64:
        return jsonify(error='Huella inválida.'), 400

    with lock:
        now = clock_ms()
        for expired in [key for key, room in rooms.items() if now - room['last'] > 900_000]:
            del rooms[expired]
        if action == 'create':
            code = secrets.token_hex(4)
            rooms[code] = dict(owner=user['id'], fingerprint=fingerprint, primary=device, backup=None,
                               start=None, jump=None, ack=False, last=now, backup_seen=0)
        room = rooms.get(code)
        if not room or room['owner'] != user['id']:
            return jsonify(error='Sala no disponible para esta cuenta.'), 404
        if room['fingerprint'] != fingerprint:
            return jsonify(error='La canción o la configuración musical no coincide.'), 409
        if action == 'join' and not room['backup'] and room['start'] is None and device != room['primary']:
            room['backup'] = device
        if device not in (room['primary'], room['backup']):
            return jsonify(error='La sala ya tiene dos equipos.'), 403

        primary = device == room['primary']
        if not primary:
            room['backup_seen'] = now
        connected = bool(room['backup']) and now - room['backup_seen'] < 2000
        if action == 'start':
            if not primary or not connected or room['start'] is not None:
                return jsonify(error='Necesitas un respaldo conectado y una sala nueva.'), 409
            room['start'] = now + 3000
        elif action == 'jump':
            command = data.get('command')
            if (not primary or not connected or not room['start'] or now < room['start'] or room['jump']
                    or not isinstance(command, dict)):
                return jsonify(error='El salto requiere ambos equipos en reproducción y una sala sin salto previo.'), 409
            execute_at, tick_ms = command.get('executeAt'), data.get('tickMs')
            if (type(execute_at) is not int or not 0 < execute_at <= 100_000 or
                    type(tick_ms) not in (int, float) or not 80 <= tick_ms <= 260 or
                    not all(isinstance(command.get(k), str) and 0 < len(command[k]) <= 100 for k in ('songId', 'sectionId'))):
                return jsonify(error='Salto inválido.'), 400
            when = room['start'] + execute_at * tick_ms
            if not now + 1800 <= when <= now + 12000:
                return jsonify(error='El salto quedó fuera de la ventana de programación.'), 409
            room['jump'] = dict(sessionId=code, type='jump', seq=1, executeAt=execute_at,
                                songId=command['songId'], sectionId=command['sectionId'])
        elif action == 'ack':
            if primary or not room['jump'] or data.get('seq') != room['jump']['seq']:
                return jsonify(error='Confirmación inválida.'), 409
            room['ack'] = True
        elif action not in ('create', 'join', 'poll'):
            return jsonify(error='Acción inválida.'), 400
        room['last'] = now
        return jsonify(code=code, primary=primary, connected=connected, now=now,
                       start=room['start'], jump=room['jump'], ack=room['ack'])
