#!/usr/bin/env python3
"""
Philips TV Remote Control Server
Proxies requests to JointSpace API and serves web UI.
Supports auto-discovery of Philips TVs on the local network.
Supports JointSpace API versions 1 (HTTP) and 6 (HTTPS, Android TV).
"""

import http.server
import json
import ssl
import urllib.request
import urllib.error
import os
import socket
import threading

# Constants
API_PREFIX = '/api'
JOINTSPACE_PORT = 1925
TV_REQUEST_TIMEOUT = 5  # seconds
SCAN_TIMEOUT = 1         # seconds per host during network scan

# Configuration via environment variables
SERVER_PORT = int(os.environ.get('SERVER_PORT', '8888'))

# Mutable TV config (can be changed at runtime via /config endpoint)
tv_config = {
    'ip':         os.environ.get('TV_IP', ''),
    'port':       int(os.environ.get('TV_PORT', str(JOINTSPACE_PORT))),
    'apiVersion': int(os.environ.get('TV_API_VERSION', '1')),
}

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WWW_DIR    = os.path.join(SCRIPT_DIR, 'www')


def _ssl_context():
    """Return an SSL context that skips certificate verification.
    Philips TVs use self-signed certificates for JointSpace v6 (HTTPS)."""
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def get_local_subnet():
    """Detect the local network subnet by connecting to an external address."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(2)
        s.connect(('8.8.8.8', 80))
        local_ip = s.getsockname()[0]
        s.close()
        parts = local_ip.split('.')
        return f"{parts[0]}.{parts[1]}.{parts[2]}", local_ip
    except Exception:
        return None, None


def check_tv(ip, port, timeout=SCAN_TIMEOUT):
    """Check if a Philips TV responds at the given IP.
    Tries API v1 (HTTP), v6 (HTTPS), v5 (HTTP) in order.
    Returns device info dict with apiVersion field, or None."""
    candidates = [
        (1, 'http'),
        (6, 'https'),
        (5, 'http'),
    ]
    for api_version, scheme in candidates:
        try:
            url = f"{scheme}://{ip}:{port}/{api_version}/system"
            req = urllib.request.Request(url)
            ctx = _ssl_context() if scheme == 'https' else None
            with urllib.request.urlopen(req, timeout=timeout, context=ctx) as response:
                data = json.loads(response.read())
                return {
                    'ip':         ip,
                    'port':       port,
                    'apiVersion': api_version,
                    'name':       data.get('name', 'Philips TV'),
                    'model':      data.get('model', ''),
                }
        except Exception:
            continue
    return None


def scan_network(subnet, port=JOINTSPACE_PORT):
    """Scan /24 subnet for Philips TVs. Returns list of found devices."""
    found = []
    lock  = threading.Lock()

    def scan_ip(ip):
        result = check_tv(ip, port)
        if result:
            with lock:
                found.append(result)

    threads = []
    for i in range(1, 255):
        ip = f"{subnet}.{i}"
        t  = threading.Thread(target=scan_ip, args=(ip,), daemon=True)
        threads.append(t)
        t.start()

    for t in threads:
        t.join(timeout=SCAN_TIMEOUT + 2)

    return found


class ProxyHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP handler that proxies TV API calls, serves static files,
    and provides TV discovery and configuration endpoints."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WWW_DIR, **kwargs)

    def _send_json(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(body))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        content_length = int(self.headers.get('Content-Length', 0))
        return self.rfile.read(content_length)

    def do_GET(self):
        if self.path == '/':
            self.path = '/index.html'

        if self.path == '/discover':
            self._handle_discover()
        elif self.path == '/config':
            self._handle_get_config()
        elif self.path.startswith(API_PREFIX + '/'):
            self._proxy_tv('GET')
        else:
            super().do_GET()

    def do_POST(self):
        if self.path == '/config':
            self._handle_set_config()
        elif self.path.startswith(API_PREFIX + '/'):
            self._proxy_tv('POST')
        else:
            self.send_error(404)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def _handle_discover(self):
        """Scan local network for Philips TVs on JointSpace port."""
        subnet, local_ip = get_local_subnet()
        if not subnet:
            self._send_json({'error': 'Cannot determine local network', 'tvs': []}, 500)
            return
        tvs = scan_network(subnet)
        self._send_json({'tvs': tvs, 'subnet': subnet, 'localIp': local_ip})

    def _handle_get_config(self):
        """Return current TV configuration."""
        self._send_json(tv_config)

    def _handle_set_config(self):
        """Update TV configuration at runtime."""
        body = json.loads(self._read_body())
        if 'ip'         in body: tv_config['ip']         = body['ip']
        if 'port'       in body: tv_config['port']       = int(body['port'])
        if 'apiVersion' in body: tv_config['apiVersion'] = int(body['apiVersion'])
        self._send_json(tv_config)

    def _proxy_tv(self, method):
        """Proxy an HTTP/HTTPS request to the Philips TV JointSpace API."""
        if not tv_config['ip']:
            self._send_json({
                'error': 'TV not configured. Use discovery or set IP manually.'
            }, 503)
            return

        # v6+ uses HTTPS; older models use plain HTTP
        scheme = 'https' if tv_config['apiVersion'] >= 6 else 'http'
        tv_path = self.path[len(API_PREFIX):]
        tv_url  = f"{scheme}://{tv_config['ip']}:{tv_config['port']}{tv_path}"
        ctx     = _ssl_context() if scheme == 'https' else None

        try:
            body = self._read_body() if method == 'POST' else None
            req  = urllib.request.Request(tv_url, data=body, method=method)
            req.add_header('Content-Type', 'application/json')

            with urllib.request.urlopen(req, timeout=TV_REQUEST_TIMEOUT, context=ctx) as response:
                data = response.read()
                self.send_response(response.status)
                self.send_header('Content-Type',
                                 response.headers.get('Content-Type', 'application/json'))
                self.send_header('Content-Length', len(data))
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(data)

        except urllib.error.HTTPError as e:
            error_body = e.read()
            self.send_response(e.code)
            self.send_header('Content-Length', len(error_body))
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(error_body)
        except Exception as e:
            self._send_json({'error': str(e)}, 502)

    def log_message(self, format, *args):
        print(f"[{self.log_date_time_string()}] {format % args}")


def main():
    server = http.server.ThreadingHTTPServer(('0.0.0.0', SERVER_PORT), ProxyHandler)

    print("Philips TV Remote Server")
    print("========================")
    if tv_config['ip']:
        print(f"TV: {tv_config['ip']}:{tv_config['port']} (API v{tv_config['apiVersion']})")
    else:
        print("TV: not configured (use web UI to discover)")
    print(f"Server: http://localhost:{SERVER_PORT}")
    print("Press Ctrl+C to stop")
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()
