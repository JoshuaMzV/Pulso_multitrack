import os
from flask import jsonify
from backend.config import SONGS_DIR, MIN_FREE_BYTES
from flask import Blueprint
from backend.services.imports import check_disk_space

app = Blueprint("system", __name__)

@app.route('/api/system/status', methods=['GET'])
def system_status():
    """Retorna el estado del servidor: espacio libre, canciones, etc."""
    ok, free_gb = check_disk_space()
    song_count = 0
    if os.path.exists(SONGS_DIR):
        song_count = len([d for d in os.listdir(SONGS_DIR) 
                         if os.path.isfile(os.path.join(SONGS_DIR, d, 'metadata.json'))])
    return jsonify({
        "diskFreeGB": free_gb,
        "diskOk": ok,
        "minFreeGB": MIN_FREE_BYTES / (1024**3),
        "songCount": song_count,
        "status": "online"
    })

