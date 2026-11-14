from flask import request
from backend.services.auth import get_user_from_token


def get_auth_user():
    """Extrae y valida el usuario actual desde Authorization header, X-Auth-Token o cookie."""
    auth_header = request.headers.get('Authorization', '')
    token = None
    if auth_header.startswith('Bearer '):
        token = auth_header.split(' ', 1)[1].strip()
    elif 'X-Auth-Token' in request.headers:
        token = request.headers['X-Auth-Token'].strip()
    elif 'pulso_auth_token' in request.cookies:
        token = request.cookies['pulso_auth_token'].strip()
    
    if not token:
        return None
    return get_user_from_token(token)

