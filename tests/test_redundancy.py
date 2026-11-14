import unittest
from unittest.mock import patch

from flask import Flask
from backend.routes import redundancy


class RedundancyTests(unittest.TestCase):
    def test_pair_start_and_ack_from_backup(self):
        app = Flask(__name__)
        app.register_blueprint(redundancy.app)
        client = app.test_client()
        fingerprint = 'a' * 64
        code = ''

        def send(action, device='primary-1', **fields):
            return client.post('/api/redundancy', json={
                'action': action, 'code': code, 'device': device,
                'fingerprint': fingerprint, **fields
            })

        with patch.object(redundancy, 'rooms', {}), \
             patch.object(redundancy, 'get_auth_user', return_value={'id': 1}), \
             patch.object(redundancy, 'clock_ms', return_value=1000) as clock:
            code = send('create').json['code']
            self.assertEqual(send('start').status_code, 409)
            self.assertEqual(send('join', 'backup-01', fingerprint='b' * 64).status_code, 409)
            self.assertTrue(send('join', 'backup-01').json['connected'])
            self.assertEqual(send('start').json['start'], 4000)
            clock.return_value = 4100
            send('poll', 'backup-01')
            proposed = send('jump', tickMs=125, command={
                'executeAt': 32, 'songId': 'song', 'sectionId': '1'
            })
            self.assertFalse(proposed.json['ack'])
            self.assertEqual(send('ack', seq=1).status_code, 409)
            self.assertEqual(send('poll', 'backup-01').json['jump']['executeAt'], 32)
            self.assertTrue(send('ack', 'backup-01', seq=1).json['ack'])
            self.assertTrue(send('poll').json['ack'])
