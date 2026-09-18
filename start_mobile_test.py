import subprocess
import threading
import http.server
import socketserver
import os
import re
import sys

PORT = 5000
DIRECTORY = r"E:\Proyectos\Setlist_Multitrack\www"

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

def run_server():
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        print(f"Serving {DIRECTORY} on port {PORT}...")
        httpd.serve_forever()

t = threading.Thread(target=run_server, daemon=True)
t.start()

cmd = [r"C:\Program Files (x86)\cloudflared\cloudflared.exe", "tunnel", "--url", f"http://localhost:{PORT}"]
proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)

for line in proc.stdout:
    sys.stdout.write(line)
    sys.stdout.flush()
    m = re.search(r"https://[a-zA-Z0-9-]+\.trycloudflare\.com", line)
    if m:
        url = m.group(0)
        print(f"\n==================================================", flush=True)
        print(f"MOBILE TEST URL: {url}", flush=True)
        print(f"==================================================\n", flush=True)
