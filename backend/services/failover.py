"""Decisión A/B para un selector externo al reproductor."""
from dataclasses import dataclass
import math


def pilot_present(samples, sample_rate: int, frequency: float, *, min_rms: float) -> bool:
    """Identifica el tono continuo en un canal dedicado con muestras PCM normalizadas."""
    if not 0 < frequency < sample_rate / 2 or min_rms <= 0:
        raise ValueError('La frecuencia o el umbral del piloto no es válido.')
    size = len(samples)
    if size < math.ceil(4 * sample_rate / frequency):
        raise ValueError('El bloque de audio debe cubrir al menos cuatro ciclos del piloto.')

    omega = 2 * math.pi * frequency / sample_rate
    coefficient = 2 * math.cos(omega)
    last = previous = energy = 0.0
    for sample in samples:
        current = sample + coefficient * last - previous
        previous, last = last, current
        energy += sample * sample
    power = last * last + previous * previous - coefficient * last * previous
    pilot_energy = 2 * power / size
    return pilot_energy >= size * min_rms * min_rms and pilot_energy >= energy * 0.6


@dataclass
class FailoverSelector:
    loss_ms: int
    ready_ms: int
    active: str = 'A'
    armed: bool = False
    _last_ms: int | None = None
    _loss_since: int | None = None
    _backup_since: int | None = None

    def __post_init__(self):
        if self.loss_ms <= 0 or self.ready_ms <= 0:
            raise ValueError('Los tiempos de detección deben ser positivos.')

    def observe(self, now_ms: int, *, a_alive: bool, b_alive: bool, b_aligned: bool) -> bool:
        """Devuelve True si el selector debe pasar de A a B en este bloque."""
        if self._last_ms is not None and now_ms < self._last_ms:
            raise ValueError('El reloj del selector debe ser monotónico.')
        self._last_ms = now_ms
        if a_alive:
            self._loss_since = None
        elif self._loss_since is None:
            self._loss_since = now_ms
        if not (b_alive and b_aligned):
            self._backup_since = None
        elif self._backup_since is None:
            self._backup_since = now_ms

        if not self.armed or self.active != 'A' or self._loss_since is None or self._backup_since is None:
            return False
        if now_ms - self._loss_since < self.loss_ms or now_ms - self._backup_since < self.ready_ms:
            return False
        self.active = 'B'
        return True

    def arm(self):
        self.armed = True
        self._loss_since = None

    def select(self, source: str):
        """El operador elige A o B y desarma el cambio automático."""
        if source not in ('A', 'B'):
            raise ValueError('La fuente debe ser A o B.')
        self.active = source
        self.armed = False
        self._loss_since = None
