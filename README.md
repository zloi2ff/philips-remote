# Philips TV Remote

Web-based remote control for Philips Smart TV (JointSpace API v1/v5/v6). Available as web app and native iOS app with Home Screen widget.

**English** | [Українська](README.uk.md)

<p align="center">
  <img src="screenshot-collapsed.png" width="280" alt="Collapsed">
  <img src="screenshot-expanded.png" width="280" alt="Expanded">
</p>

![Version](https://img.shields.io/badge/version-1.1-blue)
![Remote](https://img.shields.io/badge/TV-Philips%206158-blue)
![Python](https://img.shields.io/badge/Python-3.x-green)
![Capacitor](https://img.shields.io/badge/Capacitor-8.x-blue)
![License](https://img.shields.io/badge/License-MIT-yellow)

## Supported TV

- **Model:** Philips 42PFL6158K/12 (and similar 6xxx series)
- **API:** JointSpace v1 (port 1925)

## Features

- Auto-discovery of Philips TVs on local network
- Manual TV IP configuration
- Power on/off
- Navigation (arrows, OK, Back, Home)
- Volume control (+/-, mute, slider)
- Channel switching (+/-)
- Color buttons (red, green, yellow, blue)
- Playback controls (play, pause, stop, rewind, forward)
- Quick source switching (TV, HDMI, Blu-ray, etc.)
- Visual button feedback with haptic (iOS)
- PWA support (add to home screen on iOS/Android)
- Native iOS app (Capacitor)
- **Home Screen widget** — Vol+/Vol-/Mute/Standby controls without opening the app (iOS 17+, Liquid Glass on iOS 26+)

## Installation

### Quick Start

```bash
git clone https://github.com/zloi2ff/philips-remote.git
cd philips-remote
python3 server.py
```

Open http://localhost:8888 in your browser. The app will prompt you to scan the network or enter your TV's IP address.

### Configuration

The server can be configured via environment variables:

```bash
# Set TV IP (optional — can be configured from the web UI)
TV_IP=192.168.1.100 python3 server.py

# Change server port
SERVER_PORT=9000 python3 server.py

# Set TV port (default: 1925)
TV_PORT=1925 python3 server.py
```

## Usage on iPhone/Android

### Web App (PWA)

1. Open `http://YOUR_SERVER_IP:8888` in Safari/Chrome
2. Tap Share button → "Add to Home Screen"
3. Use as a native app

### Native iOS App

Build and install with Xcode:

```bash
# Install dependencies
npm install

# Sync with iOS
npx cap sync ios

# Open in Xcode
npx cap open ios
```

In Xcode:
1. Select your iPhone device
2. Configure signing (Signing & Capabilities → Team)
3. Press Run (Cmd+R)

## API Reference

The TV uses JointSpace API v1:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/1/system` | GET | System info |
| `/1/audio/volume` | GET/POST | Volume control |
| `/1/sources` | GET | Available sources |
| `/1/sources/current` | POST | Switch source |
| `/1/input/key` | POST | Send remote key |

### Server Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/discover` | GET | Scan local network for Philips TVs |
| `/config` | GET | Get current TV IP configuration |
| `/config` | POST | Set TV IP (`{"ip": "...", "port": ...}`) |

### Key codes

`Standby`, `VolumeUp`, `VolumeDown`, `Mute`, `ChannelStepUp`, `ChannelStepDown`, `CursorUp`, `CursorDown`, `CursorLeft`, `CursorRight`, `Confirm`, `Back`, `Home`, `Source`, `Info`, `Options`, `Find`, `Adjust`, `Digit0`-`Digit9`, `Play`, `Pause`, `Stop`, `Rewind`, `FastForward`, `Record`, `RedColour`, `GreenColour`, `YellowColour`, `BlueColour`

## License

MIT
