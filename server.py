#!/usr/bin/env python3
"""
Philips TV Remote Proxy Server
Runs on localhost:8080, proxies requests to TV at 192.168.31.214:1925
"""

import http.server
import json
import urllib.request
import urllib.error
from urllib.parse import urlparse

TV_IP = "192.168.31.214"
TV_PORT = 1925
SERVER_PORT = 8080

class ProxyHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/api/'):
            self.proxy_request('GET')
        else:
            super().do_GET()

    def do_POST(self):
        if self.path.startswith('/api/'):
            self.proxy_request('POST')
        else:
            self.send_error(404)

    def proxy_request(self, method):
        # Remove /api prefix
        tv_path = self.path[4:]  # Remove '/api'
        tv_url = f"http://{TV_IP}:{TV_PORT}{tv_path}"

        try:
            # Read body for POST
            body = None
            if method == 'POST':
                content_length = int(self.headers.get('Content-Length', 0))
                body = self.rfile.read(content_length)

            # Create request to TV
            req = urllib.request.Request(
                tv_url,
                data=body,
                method=method
            )
            req.add_header('Content-Type', 'application/json')

            # Send request
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
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps({'error': str(e)}).encode())

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def log_message(self, format, *args):
        print(f"[{self.log_date_time_string()}] {args[0]}")

def main():
    server = http.server.HTTPServer(('0.0.0.0', SERVER_PORT), ProxyHandler)
    print(f"Philips TV Remote Server")
    print(f"========================")
    print(f"TV IP: {TV_IP}:{TV_PORT}")
    print(f"Server: http://localhost:{SERVER_PORT}")
    print(f"Open http://localhost:{SERVER_PORT} in your browser")
    print(f"Press Ctrl+C to stop")
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()

if __name__ == '__main__':
    main()
