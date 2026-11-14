import unittest
import struct
from math import sin, tau

from backend.services.failover import FailoverSelector, pilot_present
from backend.services.mr12_switch import meter_levels, osc_string


class FailoverTests(unittest.TestCase):
    def test_mr12_meter_packet(self):
        header = osc_string('/meters/1') + osc_string(',b')
        payload = struct.pack('>I', 84) + struct.pack('<I40h', 40, -128 * 256, *([-18 * 256] * 39))
        self.assertEqual(meter_levels(header + payload)[:2], (-128.0, -18.0))
        self.assertIsNone(meter_levels(header + payload[:-1]))

    def test_pilot_distinguishes_signal_from_silence_and_wrong_tone(self):
        rate = 48000

        def block(frequency, amplitude=0.1):
            return [amplitude * sin(tau * frequency * i / rate + 0.5) for i in range(480)]

        for frequency, amplitude, expected in [(1000, 0.1, True), (1000, 0.0, False),
                                               (1000, 0.001, False), (1500, 0.1, False)]:
            with self.subTest(frequency=frequency, amplitude=amplitude):
                self.assertEqual(pilot_present(block(frequency, amplitude), rate, 1000, min_rms=0.01),
                                 expected)

    def test_switch_requires_sustained_loss_and_ready_backup(self):
        selector = FailoverSelector(loss_ms=60, ready_ms=300)

        def observe(now, a=True, b=True, aligned=True):
            return selector.observe(now, a_alive=a, b_alive=b, b_aligned=aligned)

        selector.arm()
        self.assertFalse(observe(0))
        self.assertFalse(observe(300, a=False))
        self.assertFalse(observe(330))
        self.assertFalse(observe(400, a=False, aligned=False))
        self.assertFalse(observe(460, a=False, aligned=False))
        self.assertFalse(observe(470, a=False))
        self.assertFalse(observe(769, a=False))
        self.assertTrue(observe(770, a=False))
        self.assertEqual(selector.active, 'B')
        self.assertFalse(observe(1000))
        self.assertEqual(selector.active, 'B')
        selector.select('A')
        self.assertFalse(observe(1100, a=False))
        self.assertFalse(observe(1300, a=False))
        self.assertEqual(selector.active, 'A')
