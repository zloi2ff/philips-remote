#!/usr/bin/env python3
"""
Philips TV Remote Control Server
Proxies requests to JointSpace API
"""

import http.server
import json
import urllib.request
import urllib.error

# Configuration
TV_IP = "192.168.31.214"
TV_PORT = 1925
SERVER_PORT = 8888


class ProxyHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP handler for TV API"""

    def _send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_GET(self):
        if self.path.startswith('/api/'):
            self.proxy_tv('GET')
        else:
            super().do_GET()

    def do_POST(self):
        if self.path.startswith('/api/'):
            self.proxy_tv('POST')
        else:
            self.send_error(404)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def proxy_tv(self, method):
        """Proxy request to Philips TV"""
        tv_path = self.path[4:]  # Remove '/api'
        tv_url = f"http://{TV_IP}:{TV_PORT}{tv_path}"

        try:
            body = None
            if method == 'POST':
                content_length = int(self.headers.get('Content-Length', 0))
                body = self.rfile.read(content_length)

            req = urllib.request.Request(tv_url, data=body, method=method)
            req.add_header('Content-Type', 'application/json')

            with urllib.request.urlopen(req, timeout=5) as response:
                data = response.read()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(data)

        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(e.read())
        except Exception as e:
            self._send_json({'error': str(e)}, 500)

    def log_message(self, format, *args):
        print(f"[{self.log_date_time_string()}] {args[0]}")


def main():
    server = http.server.HTTPServer(('0.0.0.0', SERVER_PORT), ProxyHandler)
    print(f"Philips TV Remote Server")
    print(f"========================")
    print(f"TV: {TV_IP}:{TV_PORT}")
    print(f"Server: http://localhost:{SERVER_PORT}")
    print(f"Press Ctrl+C to stop")
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()
