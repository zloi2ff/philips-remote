#!/usr/bin/env python3
"""
Remote Control Server
- Philips TV: proxies to JointSpace API
- Xbox: SmartGlass protocol for local network control
"""

import http.server
import json
import urllib.request
import urllib.error
import socket
import struct
import time

# Configuration
TV_IP = "192.168.31.214"
TV_PORT = 1925
XBOX_IP = "192.168.31.58"
XBOX_PORT = 5050
SERVER_PORT = 8888

# Xbox button codes
XBOX_BUTTONS = {
    'a': 0x1000,
    'b': 0x2000,
    'x': 0x4000,
    'y': 0x8000,
    'dpad_up': 0x0001,
    'dpad_down': 0x0002,
    'dpad_left': 0x0004,
    'dpad_right': 0x0008,
    'start': 0x0010,
    'back': 0x0020,
    'left_thumb': 0x0040,
    'right_thumb': 0x0080,
    'left_shoulder': 0x0100,
    'right_shoulder': 0x0200,
    'nexus': 0x0400,
    'menu': 0x0010,
    'view': 0x0020,
}


class XboxController:
    """Simple Xbox SmartGlass controller for local network"""

    def __init__(self, ip=XBOX_IP, port=XBOX_PORT):
        self.ip = ip
        self.port = port

    def _create_socket(self, timeout=2):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(timeout)
        return sock

    def get_status(self):
        """Check if Xbox is online"""
        sock = self._create_socket(timeout=1)
        try:
            # Discovery packet
            packet = struct.pack('>HH', 0xDD00, 0x0000) + b'\x00' * 42
            sock.sendto(packet, (self.ip, self.port))

            try:
                data, addr = sock.recvfrom(1024)
                return {'status': 'online', 'ip': addr[0]}
            except socket.timeout:
                return {'status': 'offline', 'ip': self.ip}
        except Exception as e:
            return {'status': 'error', 'error': str(e)}
        finally:
            sock.close()

    def discover(self):
        """Discover Xbox devices on network"""
        sock = self._create_socket(timeout=3)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

        packet = struct.pack('>HH', 0xDD00, 0x0000) + b'\x00' * 42
        results = []

        try:
            sock.sendto(packet, (self.ip, self.port))
            sock.sendto(packet, ('255.255.255.255', self.port))

            start = time.time()
            while time.time() - start < 2:
                try:
                    data, addr = sock.recvfrom(1024)
                    if len(data) > 4:
                        results.append({
                            'ip': addr[0],
                            'port': addr[1],
                            'status': 'found'
                        })
                except socket.timeout:
                    break

            return results if results else [{'ip': self.ip, 'status': 'no_response'}]
        except Exception as e:
            return [{'status': 'error', 'error': str(e)}]
        finally:
            sock.close()

    def wake(self):
        """Send wake packet to Xbox"""
        sock = self._create_socket()
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

        packet = struct.pack('>HH', 0xDD02, 0x0000) + b'\x00' * 42

        try:
            sock.sendto(packet, (self.ip, self.port))
            sock.sendto(packet, ('255.255.255.255', self.port))
            return {'status': 'wake_sent', 'ip': self.ip}
        except Exception as e:
            return {'status': 'error', 'error': str(e)}
        finally:
            sock.close()

    def send_input(self, button, hold_time=0.08):
        """Send gamepad button input"""
        if button not in XBOX_BUTTONS:
            return {'status': 'error', 'error': f'Unknown button: {button}'}

        button_code = XBOX_BUTTONS[button]
        sock = self._create_socket()
        timestamp = int(time.time() * 1000) & 0xFFFFFFFF

        try:
            # Button press packet
            packet = struct.pack('>HHIHH',
                0xD00D, 0x0001, timestamp, button_code, 0x0000
            ) + b'\x00' * 32
            sock.sendto(packet, (self.ip, self.port))

            time.sleep(hold_time)

            # Button release packet
            packet_release = struct.pack('>HHIHH',
                0xD00D, 0x0002, timestamp + int(hold_time * 1000), 0x0000, 0x0000
            ) + b'\x00' * 32
            sock.sendto(packet_release, (self.ip, self.port))

            return {'status': 'sent', 'button': button}
        except Exception as e:
            return {'status': 'error', 'error': str(e)}
        finally:
            sock.close()


# Global Xbox controller instance
xbox = XboxController()


class ProxyHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP handler for TV and Xbox APIs"""

    def _send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_GET(self):
        if self.path.startswith('/api/xbox/'):
            self.handle_xbox('GET')
        elif self.path.startswith('/api/'):
            self.proxy_tv('GET')
        else:
            super().do_GET()

    def do_POST(self):
        if self.path.startswith('/api/xbox/'):
            self.handle_xbox('POST')
        elif self.path.startswith('/api/'):
            self.proxy_tv('POST')
        else:
            self.send_error(404)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def handle_xbox(self, method):
        """Handle Xbox API requests"""
        path = self.path[10:]  # Remove '/api/xbox/'

        # Read body for POST
        body = {}
        if method == 'POST':
            content_length = int(self.headers.get('Content-Length', 0))
            if content_length:
                try:
                    body = json.loads(self.rfile.read(content_length))
                except:
                    body = {}

        if path == 'status':
            result = xbox.get_status()
        elif path == 'discover':
            result = xbox.discover()
        elif path == 'wake':
            result = xbox.wake()
        elif path == 'input':
            key = body.get('key', '')
            result = xbox.send_input(key)
        else:
            result = {'error': 'Unknown Xbox endpoint'}

        self._send_json(result)

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
    print(f"Remote Control Server")
    print(f"=====================")
    print(f"TV:   {TV_IP}:{TV_PORT}")
    print(f"Xbox: {XBOX_IP}:{XBOX_PORT}")
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
