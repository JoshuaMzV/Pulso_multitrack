"""Servidor de desarrollo: python -m backend.local_server."""
import os
from flask import Flask
from backend.config import ensure_data_directories

def create_app():
    ensure_data_directories()
    from backend.routes import auth, songs, setlists, system, web, redundancy
    app = Flask(__name__, static_folder=None)
    for module in (auth, songs, setlists, system, web, redundancy):
        app.register_blueprint(module.app)
    return app

app = create_app()

if __name__ == '__main__':
    app.run(host=os.environ.get('PULSO_HOST', '127.0.0.1'),
            port=int(os.environ.get('PULSO_PORT', '5000')), debug=False)
