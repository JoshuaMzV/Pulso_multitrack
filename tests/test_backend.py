"""Regresiones de API y migración, siempre contra datos temporales."""
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
import wave
import zipfile

TEST_ROOT = Path(__file__).resolve().parents[1] / '.test-data'
TEST_ROOT.mkdir(exist_ok=True)
WORKSPACE = tempfile.TemporaryDirectory(prefix='pulso-test-', dir=TEST_ROOT)
os.environ['PULSO_DATA_DIR'] = WORKSPACE.name
from backend.local_server import create_app
from backend.config import SONGS_DIR, TEMP_DIR
from backend.services.imports import process_assembled_zip
from scripts.migrate_data import migrate


class BackendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = create_app().test_client()
        response = cls.client.post('/api/auth/register', json={
            'username': 'regression-admin', 'password': 'Test-only-password-123!',
            'invite_code': 'PULSO-ADMIN-SETUP'})
        assert response.status_code == 201, response.json

    def login(self):
        result = self.client.post('/api/auth/login', json={
            'username': 'regression-admin', 'password': 'Test-only-password-123!'})
        self.assertEqual(result.status_code, 200)
        return {'Authorization': 'Bearer ' + result.json['token']}

    def test_login_logout_and_setlist_persistence(self):
        headers = self.login()
        self.assertTrue(self.client.get('/api/auth/me', headers=headers).json['authenticated'])
        payload = [{'id': 'test-list', 'name': 'Ensayo', 'songs': [{'id': 'test', 'key': 'E', 'transposeKey': 'D'}]}]
        self.assertEqual(self.client.post('/api/setlists', headers=headers, json=payload).status_code, 200)
        self.assertEqual(self.client.get('/api/setlists', headers=headers).json, payload)
        self.assertEqual(self.client.get('/api/setlists').json, [])
        self.client.post('/api/auth/logout', headers=headers)
        self.assertFalse(self.client.get('/api/auth/me', headers=headers).json['authenticated'])

    def test_import_flac_and_stable_song_url(self):
        audio = io.BytesIO()
        with wave.open(audio, 'wb') as wav:
            wav.setparams((1, 2, 44100, 0, 'NONE', 'not compressed'))
            wav.writeframes(b'\0\0' * 4410)
        archive = TEMP_DIR / 'regression.zip'
        with zipfile.ZipFile(archive, 'w') as bundle:
            for name in ('Piano.wav', 'Click.wav', 'Guia.wav'):
                bundle.writestr(name, audio.getvalue())
        metadata, warnings = process_assembled_zip(str(archive), 'Regression song', 'Test', 120, 'E')
        self.assertEqual(len(metadata['stems']), 3, warnings)
        self.assertEqual([s['category'] for s in metadata['stems'][:2]], ['click', 'guide'])
        for stem in metadata['stems']:
            response = self.client.get(f"/songs/{metadata['id']}/{stem['filename']}")
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.data[:4], b'fLaC')
            response.close()
        catalog = self.client.get('/api/songs', headers=self.login()).json
        self.assertTrue(any(song['id'] == metadata['id'] for song in catalog))

    def test_web_and_private_paths(self):
        for route in ('/', '/js/main.js', '/styles/base.css', '/vendor/jszip.min.js'):
            response = self.client.get(route)
            self.assertEqual(response.status_code, 200, route)
            response.close()
        self.assertEqual(self.client.get('/data/database/pulso.db').status_code, 404)

    def test_migration_idempotence_and_conflicts(self):
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            root = Path(temporary)
            source = root / 'www/songs/test/audio.flac'
            source.parent.mkdir(parents=True)
            source.write_bytes(b'original-audio')
            destination = root / 'data'
            first = migrate(root, destination)
            self.assertEqual(first, migrate(root, destination))
            self.assertTrue(source.exists())
            target = destination / 'songs/test/audio.flac'
            target.write_bytes(b'newer-audio')
            with self.assertRaises(RuntimeError):
                migrate(root, destination)
            self.assertEqual(target.read_bytes(), b'newer-audio')


def tearDownModule():
    WORKSPACE.cleanup()
