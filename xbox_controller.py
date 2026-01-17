#!/usr/bin/env python3
"""
Xbox SmartGlass Controller - Basic Implementation
For local network control of Xbox Series S/X and Xbox One
"""

import socket
import struct
import time
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

XBOX_IP = "192.168.31.58"
SMARTGLASS_PORT = 5050

# Message types
MSG_DISCOVERY_REQUEST = 0xDD00
MSG_DISCOVERY_RESPONSE = 0xDD01
MSG_CONNECT_REQUEST = 0xCC00
MSG_CONNECT_RESPONSE = 0xCC01

# Gamepad buttons (bit flags)
BUTTONS = {
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
    def __init__(self, ip=XBOX_IP):
        self.ip = ip
        self.port = SMARTGLASS_PORT
        self.sock = None
        self.connected = False
        self.device_info = None

    def _create_socket(self):
        """Create UDP socket"""
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(2)
        return sock

    def discover(self):
        """
        Discover Xbox on network using SmartGlass discovery
        """
        sock = self._create_socket()
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

        # Discovery request packet
        # Format: type (2 bytes) + flags (2 bytes) + client_id (16 bytes) + padding
        packet = struct.pack('>HH', MSG_DISCOVERY_REQUEST, 0x0000)
        packet += b'\x00' * 16  # client UUID placeholder
        packet += b'\x00' * 26  # padding to 46 bytes

        try:
            # Try direct IP first
            sock.sendto(packet, (self.ip, self.port))

            # Also broadcast
            sock.sendto(packet, ('255.255.255.255', self.port))

            responses = []
            start = time.time()
            while time.time() - start < 2:
                try:
                    data, addr = sock.recvfrom(1024)
                    if len(data) > 4:
                        msg_type = struct.unpack('>H', data[:2])[0]
                        if msg_type == MSG_DISCOVERY_RESPONSE:
                            # Parse device info from response
                            info = self._parse_discovery_response(data, addr)
                            responses.append(info)
                except socket.timeout:
                    break

            sock.close()
            return responses if responses else [{'ip': self.ip, 'status': 'no_response'}]

        except Exception as e:
            sock.close()
            return [{'ip': self.ip, 'status': 'error', 'error': str(e)}]

    def _parse_discovery_response(self, data, addr):
        """Parse discovery response packet"""
        info = {
            'ip': addr[0],
            'port': addr[1],
            'status': 'found',
            'raw_length': len(data)
        }

        # Try to extract device name (usually at offset ~32)
        try:
            # Find null-terminated string for device name
            for i in range(32, min(len(data) - 1, 100)):
                if data[i:i+1] == b'\x00' and i > 32:
                    name = data[32:i].decode('utf-8', errors='ignore').strip('\x00')
                    if name and name.isprintable():
                        info['name'] = name
                        break
        except:
            pass

        return info

    def wake(self):
        """
        Wake Xbox using power on packet
        Xbox must have "Instant-on" power mode enabled
        """
        sock = self._create_socket()
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

        # Power on packet (simplified)
        # Real implementation needs live_id from previous connection
        packet = struct.pack('>HH', 0xDD02, 0x0000)
        packet += b'\x00' * 42

        try:
            sock.sendto(packet, (self.ip, self.port))
            sock.sendto(packet, ('255.255.255.255', self.port))
            sock.close()
            return {'status': 'wake_sent', 'ip': self.ip}
        except Exception as e:
            sock.close()
            return {'status': 'error', 'error': str(e)}

    def send_input(self, button, hold_time=0.1):
        """
        Send gamepad input to Xbox
        Note: Full implementation requires authenticated connection
        This sends basic UDP packets that Xbox may accept in some modes
        """
        if button not in BUTTONS:
            return {'status': 'error', 'error': f'Unknown button: {button}'}

        button_code = BUTTONS[button]
        sock = self._create_socket()

        # Input packet structure (simplified)
        # Real SmartGlass uses encrypted channel
        timestamp = int(time.time() * 1000) & 0xFFFFFFFF

        # Button press
        packet = struct.pack('>HHIHH',
            0xD00D,          # Message type (custom)
            0x0001,          # Flags
            timestamp,       # Timestamp
            button_code,     # Button pressed
            0x0000           # Reserved
        )
        packet += b'\x00' * 32  # Padding

        try:
            sock.sendto(packet, (self.ip, self.port))

            # Button release after hold_time
            time.sleep(hold_time)

            packet_release = struct.pack('>HHIHH',
                0xD00D,
                0x0002,
                timestamp + int(hold_time * 1000),
                0x0000,
                0x0000
            )
            packet_release += b'\x00' * 32
            sock.sendto(packet_release, (self.ip, self.port))

            sock.close()
            return {
                'status': 'sent',
                'button': button,
                'code': hex(button_code),
                'note': 'Basic packet sent. Full control requires SmartGlass auth.'
            }
        except Exception as e:
            sock.close()
            return {'status': 'error', 'error': str(e)}

    def get_status(self):
        """Check if Xbox is reachable"""
        sock = self._create_socket()
        sock.settimeout(1)

        try:
            # Simple ping via discovery
            packet = struct.pack('>HH', MSG_DISCOVERY_REQUEST, 0x0000)
            packet += b'\x00' * 42

            sock.sendto(packet, (self.ip, self.port))

            try:
                data, addr = sock.recvfrom(1024)
                sock.close()
                return {'status': 'online', 'ip': addr[0]}
            except socket.timeout:
                sock.close()
                return {'status': 'offline', 'ip': self.ip}
        except Exception as e:
            sock.close()
            return {'status': 'error', 'error': str(e)}


# HTTP API Handler
class XboxAPIHandler(BaseHTTPRequestHandler):
    controller = XboxController()

    def log_message(self, format, *args):
        pass  # Suppress logs

    def _send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_GET(self):
        if self.path == '/xbox/status':
            result = self.controller.get_status()
            self._send_json(result)
        elif self.path == '/xbox/discover':
            result = self.controller.discover()
            self._send_json(result)
        else:
            self._send_json({'error': 'Not found'}, 404)

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)

        try:
            data = json.loads(body) if body else {}
        except:
            data = {}

        if self.path == '/xbox/input':
            key = data.get('key', '')
            result = self.controller.send_input(key)
            self._send_json(result)
        elif self.path == '/xbox/wake':
            result = self.controller.wake()
            self._send_json(result)
        else:
            self._send_json({'error': 'Not found'}, 404)


def run_xbox_api(port=5558):
    """Run Xbox API server"""
    server = HTTPServer(('0.0.0.0', port), XboxAPIHandler)
    print(f"Xbox API running on port {port}")
    server.serve_forever()


if __name__ == '__main__':
    import sys

    if len(sys.argv) > 1:
        if sys.argv[1] == 'serve':
            run_xbox_api()
        elif sys.argv[1] == 'discover':
            ctrl = XboxController()
            print("Discovering Xbox...")
            result = ctrl.discover()
            print(json.dumps(result, indent=2))
        elif sys.argv[1] == 'status':
            ctrl = XboxController()
            result = ctrl.get_status()
            print(json.dumps(result, indent=2))
        elif sys.argv[1] == 'wake':
            ctrl = XboxController()
            result = ctrl.wake()
            print(json.dumps(result, indent=2))
        elif sys.argv[1] == 'test':
            ctrl = XboxController()
            print("Testing button A...")
            result = ctrl.send_input('a')
            print(json.dumps(result, indent=2))
    else:
        print("Xbox SmartGlass Controller")
        print("Usage:")
        print("  python xbox_controller.py serve    - Run API server")
        print("  python xbox_controller.py discover - Find Xbox")
        print("  python xbox_controller.py status   - Check Xbox status")
        print("  python xbox_controller.py wake     - Wake Xbox")
        print("  python xbox_controller.py test     - Test button press")
