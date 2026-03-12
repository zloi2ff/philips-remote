#!/usr/bin/env python3
"""
Philips TV Remote Control Server
Proxies requests to JointSpace API and serves web UI.
Supports auto-discovery of Philips TVs on the local network.
Supports JointSpace API versions 1 (HTTP) and 6 (HTTPS, Android TV).
"""

import hmac
import http.server
import ipaddress
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

# Optional API token for authentication. If not set, server runs without auth
# (backward compatible) but prints a warning at startup.
API_TOKEN: str = os.environ.get('API_TOKEN', '')

# Mutable TV config (can be changed at runtime via /config endpoint)
tv_config = {
    'ip':         os.environ.get('TV_IP', ''),
    'port':       int(os.environ.get('TV_PORT', str(JOINTSPACE_PORT))),
    'apiVersion': int(os.environ.get('TV_API_VERSION', '1')),
}

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WWW_DIR    = os.path.join(SCRIPT_DIR, 'www')

# Rate-limiting lock for /discover: only one scan at a time
_discover_lock = threading.Lock()

# Private RFC-1918 networks allowed as TV IP targets (SSRF mitigation)
_PRIVATE_NETWORKS = [
    ipaddress.IPv4Network('10.0.0.0/8'),
    ipaddress.IPv4Network('172.16.0.0/12'),
    ipaddress.IPv4Network('192.168.0.0/16'),
]

# Security headers added to every response
_SECURITY_HEADERS = [
    ('X-Content-Type-Options', 'nosniff'),
    ('X-Frame-Options',        'DENY'),
    ('Referrer-Policy',        'no-referrer'),
]


def is_valid_tv_ip(ip: str) -> bool:
    """Return True only if ip is a valid RFC-1918 private unicast address.

    Rejects loopback, link-local, multicast, and any public address to
    prevent Server-Side Request Forgery (SSRF) attacks via the /config endpoint.
    """
    try:
        addr = ipaddress.IPv4Address(ip)
    except ValueError:
        return False
    if addr.is_loopback or addr.is_link_local or addr.is_multicast:
        return False
    return any(addr in net for net in _PRIVATE_NETWORKS)


def _ssl_context() -> ssl.SSLContext:
    """Return an SSL context that skips certificate verification.

    NOTE: Philips TVs use self-signed certificates for JointSpace v6 (HTTPS).
    Certificate pinning is impractical without access to the real TV certificate,
    so CERT_NONE is an accepted trade-off for a LAN-only tool.
    """
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def get_local_subnet() -> tuple[str | None, str | None]:
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


def check_tv(ip: str, port: int, timeout: int = SCAN_TIMEOUT) -> dict | None:
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


def scan_network(subnet: str, port: int = JOINTSPACE_PORT) -> list[dict]:
    """Scan /24 subnet for Philips TVs. Returns list of found devices."""
    found: list[dict] = []
    lock  = threading.Lock()

    def scan_ip(ip: str) -> None:
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

    # ------------------------------------------------------------------
    # Security headers
    # ------------------------------------------------------------------

    def end_headers(self) -> None:
        """Inject security headers into every response before flushing."""
        for name, value in _SECURITY_HEADERS:
            self.send_header(name, value)
        super().end_headers()

    # ------------------------------------------------------------------
    # Auth
    # ------------------------------------------------------------------

    def _check_auth(self) -> bool:
        """Verify X-API-Token header when API_TOKEN env variable is set.

        Uses hmac.compare_digest to prevent timing attacks.
        Returns True if auth passes (or if no token is configured).
        """
        if not API_TOKEN:
            return True
        token = self.headers.get('X-API-Token', '')
        return hmac.compare_digest(token, API_TOKEN)

    # ------------------------------------------------------------------
    # Response helpers
    # ------------------------------------------------------------------

    def _send_json(self, data: dict, status: int = 200) -> None:
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(body))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self) -> bytes:
        content_length = int(self.headers.get('Content-Length', 0))
        return self.rfile.read(content_length)

    # ------------------------------------------------------------------
    # Routing
    # ------------------------------------------------------------------

    def do_GET(self) -> None:
        if self.path == '/':
            self.path = '/index.html'

        # Static files do not require authentication
        if not self.path.startswith((API_PREFIX + '/', '/discover', '/config')):
            super().do_GET()
            return

        if not self._check_auth():
            self._send_json({'error': 'Unauthorized'}, 401)
            return

        if self.path == '/discover':
            self._handle_discover()
        elif self.path == '/config':
            self._handle_get_config()
        elif self.path.startswith(API_PREFIX + '/'):
            self._proxy_tv('GET')

    def do_POST(self) -> None:
        if not self._check_auth():
            self._send_json({'error': 'Unauthorized'}, 401)
            return

        if self.path == '/config':
            self._handle_set_config()
        elif self.path.startswith(API_PREFIX + '/'):
            self._proxy_tv('POST')
        else:
            self.send_error(404)

    def do_OPTIONS(self) -> None:
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, X-API-Token')
        self.end_headers()

    # ------------------------------------------------------------------
    # Endpoint handlers
    # ------------------------------------------------------------------

    def _handle_discover(self) -> None:
        """Scan local network for Philips TVs on JointSpace port.

        Only one scan runs at a time; concurrent requests get 429.
        Response intentionally omits subnet and local IP to avoid
        leaking network topology to the client.
        """
        acquired = _discover_lock.acquire(blocking=False)
        if not acquired:
            self._send_json({'error': 'Scan already in progress'}, 429)
            return
        try:
            subnet, _local_ip = get_local_subnet()
            if not subnet:
                self._send_json({'error': 'Cannot determine local network', 'tvs': []}, 500)
                return
            tvs = scan_network(subnet)
            self._send_json({'tvs': tvs})
        finally:
            _discover_lock.release()

    def _handle_get_config(self) -> None:
        """Return current TV configuration."""
        self._send_json(tv_config)

    def _handle_set_config(self) -> None:
        """Update TV configuration at runtime."""
        try:
            body = json.loads(self._read_body())
        except json.JSONDecodeError:
            self._send_json({'error': 'Invalid JSON'}, 400)
            return

        if 'ip' in body:
            ip = str(body['ip'])
            if not is_valid_tv_ip(ip):
                self._send_json({'error': 'Invalid TV IP address'}, 400)
                return
            tv_config['ip'] = ip

        if 'port' in body:
            try:
                port = int(body['port'])
            except (ValueError, TypeError):
                self._send_json({'error': 'Invalid port'}, 400)
                return
            if not (1 <= port <= 65535):
                self._send_json({'error': 'Port must be 1–65535'}, 400)
                return
            tv_config['port'] = port
        if 'apiVersion' in body:
            try:
                api_version = int(body['apiVersion'])
            except (ValueError, TypeError):
                self._send_json({'error': 'Invalid apiVersion'}, 400)
                return
            if api_version not in (1, 5, 6):
                self._send_json({'error': 'apiVersion must be 1, 5, or 6'}, 400)
                return
            tv_config['apiVersion'] = api_version

        self._send_json(tv_config)

    def _proxy_tv(self, method: str) -> None:
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
            print(f"[proxy] TV request failed: {e}")
            self._send_json({'error': 'TV unreachable'}, 502)

    def log_message(self, format, *args):
        print(f"[{self.log_date_time_string()}] {format % args}")


def main() -> None:
    server = http.server.ThreadingHTTPServer(('0.0.0.0', SERVER_PORT), ProxyHandler)

    print("Philips TV Remote Server")
    print("========================")
    if tv_config['ip']:
        print(f"TV: {tv_config['ip']}:{tv_config['port']} (API v{tv_config['apiVersion']})")
    else:
        print("TV: not configured (use web UI to discover)")
    print(f"Server: http://localhost:{SERVER_PORT}")

    if not API_TOKEN:
        print("WARNING: API_TOKEN is not set — server is running without authentication.")
        print("         Set the API_TOKEN environment variable to enable token auth.")

    print("Press Ctrl+C to stop")
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()
