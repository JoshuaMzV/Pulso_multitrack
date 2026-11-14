"""Direcciones públicas estables; canciones fuera del bundle."""
from flask import Blueprint, send_from_directory
from backend.config import WWW_DIR, SONGS_DIR

app = Blueprint('web', __name__)

@app.route('/')
def serve_index():
    return send_from_directory(WWW_DIR, 'index.html')

@app.route('/songs/<path:path>')
def serve_song(path):
    return send_from_directory(SONGS_DIR, path)

@app.route('/<path:path>')
def serve_static(path):
    return send_from_directory(WWW_DIR, path)
