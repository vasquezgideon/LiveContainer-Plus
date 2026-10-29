#!/usr/bin/env python3
"""Sends *simulated* head orientation packets to the LC Plus spatial test receiver."""
import argparse
import json
import math
import socket
import time

p = argparse.ArgumentParser()
p.add_argument('--host', required=True, help='iPhone LAN IP; NOT the glasses IP')
p.add_argument('--port', type=int, default=38271)
p.add_argument('--hz', type=int, default=30)
a = p.parse_args()
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    try:
        while True:
            t = time.monotonic()
            payload = {'yaw': 14 * math.sin(t / 3), 'pitch': 6 * math.sin(t / 4), 'worn': True}
            sock.sendto(json.dumps(payload).encode('utf-8'), (a.host, a.port))
            time.sleep(1.0 / max(1, min(a.hz, 60)))
    except KeyboardInterrupt:
        pass
