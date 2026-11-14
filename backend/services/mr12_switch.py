"""Selector de ensayo para la Midas MR12 por OSC."""
import argparse
import socket
import struct
import time

from backend.services.failover import FailoverSelector


def osc_string(value):
    encoded = value.encode('ascii') + b'\0'
    return encoded.ljust((len(encoded) + 3) & ~3, b'\0')


def meter_levels(packet):
    prefix = osc_string('/meters/1') + osc_string(',b')
    if not packet.startswith(prefix):
        return None
    blob = packet[len(prefix):]
    if len(blob) != 88 or struct.unpack_from('>I', blob)[0] != 84:
        return None
    if struct.unpack_from('<I', blob, 4)[0] != 40:
        return None
    return tuple(level / 256 for level in struct.unpack_from('<40h', blob, 8))


def channel_address(channel):
    return osc_string(f'/ch/{channel:02}/mix/on')


def read_channel(sock, channel):
    address = channel_address(channel)
    sock.send(address)
    prefix = address + osc_string(',i')
    deadline = time.monotonic() + 1
    while time.monotonic() < deadline:
        try:
            packet = sock.recv(4096)
        except TimeoutError:
            continue
        if len(packet) == len(prefix) + 4 and packet.startswith(prefix):
            return struct.unpack_from('>i', packet, len(prefix))[0]
    raise RuntimeError(f'La consola no confirmó el canal {channel}.')


def switch_to_backup(sock, primary, backup):
    # Primero silenciar A y verificarlo antes de abrir B.
    for channels, value in ((primary, 0), (backup, 1)):
        for channel in channels:
            sock.send(channel_address(channel) + osc_string(',i') + struct.pack('>i', value))
        for channel in channels:
            if read_channel(sock, channel) != value:
                raise RuntimeError(f'El canal {channel} no cambió. Revisa la consola y usa el cambio manual.')


def monitor(sock, args):
    selector = FailoverSelector(loss_ms=150, ready_ms=500)
    subscription = osc_string('/meters') + osc_string(',s') + osc_string('/meters/1')
    renew_at = report_at = 0
    last_meter = time.monotonic()
    healthy_since = None
    while True:
        now = time.monotonic()
        if now >= renew_at:
            sock.send(subscription)
            renew_at = now + 5
        try:
            levels = meter_levels(sock.recv(4096))
        except TimeoutError:
            levels = None
        now = time.monotonic()
        if now - last_meter > 1:
            raise RuntimeError('Se perdió la lectura de la consola. Usa el cambio manual.')
        if levels is None:
            continue
        if now - last_meter > .25:
            selector = FailoverSelector(loss_ms=150, ready_ms=500)
            healthy_since = None
        last_meter = now
        a_db, b_db = (levels[channel - 1] for channel in (args.pilot_a, args.pilot_b))
        a_alive, b_alive = a_db >= args.threshold, b_db >= args.threshold
        if args.arm and not selector.armed:
            if not (a_alive and b_alive):
                healthy_since = None
            elif healthy_since is None:
                healthy_since = now
            elif now - healthy_since >= .5:
                selector.arm()
                print('Armado. A al aire, B en espera.', flush=True)
        if selector.observe(round(now * 1000), a_alive=a_alive, b_alive=b_alive, b_aligned=args.arm):
            switch_to_backup(sock, args.a, args.b)
            print('B quedó al aire. El retorno a A es manual.', flush=True)
            return
        if now >= report_at:
            print(f'Piloto A {a_db:.1f} dB · B {b_db:.1f} dB', flush=True)
            report_at = now + 1


def main():
    parser = argparse.ArgumentParser(description='Ensayo A/B de PULSO con Midas MR12.')
    parser.add_argument('host', help='IP de la MR12 en la red local')
    parser.add_argument('--a', nargs='+', type=int, required=True, help='Canales de audio de A')
    parser.add_argument('--b', nargs='+', type=int, required=True, help='Canales de audio de B')
    parser.add_argument('--pilot-a', type=int, required=True, help='Entrada dedicada al piloto A')
    parser.add_argument('--pilot-b', type=int, required=True, help='Entrada dedicada al piloto B')
    parser.add_argument('--threshold', type=float, default=-45, help='Umbral de piloto en dBFS')
    parser.add_argument('--arm', action='store_true', help='Habilita el cambio tras confirmar la sincronía de B')
    args = parser.parse_args()
    channels = [*args.a, *args.b, args.pilot_a, args.pilot_b]
    if (len(args.a) != len(args.b) or len(channels) != len(set(channels)) or
            not all(1 <= channel <= 12 for channel in channels) or not -100 <= args.threshold < 0):
        parser.error('Usa el mismo número de canales para A y B, entradas distintas del 1 al 12 y un umbral válido.')

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect((args.host, 10024))
            sock.settimeout(.2)
            if args.arm and (any(read_channel(sock, channel) != 1 for channel in args.a) or
                             any(read_channel(sock, channel) != 0 for channel in args.b)):
                raise RuntimeError('Antes de armar deja A audible y B silenciado en la consola.')
            monitor(sock, args)
    except KeyboardInterrupt:
        return
    except (OSError, RuntimeError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
