<h1 align="center">Philips TV Remote</h1>

<p align="center">
  Web-based remote control for Philips Smart TV — works as a browser app, PWA, and native iOS app with a Home Screen widget.
</p>

<p align="center">
  <a href="README.uk.md">Українська</a> · <a href="#installation">Quick start</a> · <a href="#supported-tvs">Supported TVs</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Python-3.x-3776AB?logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/iOS-17%2B-000000?logo=apple&logoColor=white" alt="iOS">
  <img src="https://img.shields.io/badge/Capacitor-8.x-119EFF?logo=capacitor&logoColor=white" alt="Capacitor">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

<p align="center">
  <img src="screenshot-collapsed.png" width="240" alt="Main screen">
  &nbsp;&nbsp;&nbsp;
  <img src="screenshot-expanded.png" width="240" alt="More controls">
</p>

---

## Features

**Remote control**
- Power on/off, navigation (arrows, OK, Back, Home)
- Volume (+/−, Mute, slider), Channel (+/−)
- Color buttons (Red, Green, Yellow, Blue)
- Playback controls (Play, Pause, Stop, Rewind, Forward, Record)
- Quick source switching (TV, HDMI 3/4, SAT, Blu-ray, Game, Theater, SCART)

**Smart connectivity**
- Auto-discovery of Philips TVs on local network (/24 subnet scan)
- PIN pairing for v6 TVs (2016+)
- Supports API v1, v5 and v6 — auto-detected on connect

**Platform**
- Works in any browser (no installation required)
- PWA — add to Home Screen on iOS/Android
- Native iOS app (Capacitor 8)
- **Home Screen widget** — Vol+/Vol−/Mute/Standby without opening the app (iOS 17+)
- Liquid Glass widget design on iOS 26+
- Haptic feedback on button press (iOS)
- Dark / Light / Auto theme

---

## Supported TVs

Uses the JointSpace API on port 1925. API version is auto-detected.

> **Enable JointSpace on 2011–2015 TVs:** open the TV menu and enter `5646877223` on the remote.

### API v1 — HTTP, no auth (2009–2015)

| Year | Series | Example |
|------|--------|---------|
| 2009 | xxPFL8xxx, xxPFL9xxx | 42PFL8684H/12 |
| 2010 | xxPFL7–9xxx | 46PFL8605H/12 |
| 2011 | xxPFL5**6**xx – xxPFL9**6**xx | 42PFL6158K/12 |
| 2012 | xxPFL5**7**xx – xxPFL8**7**xx | 47PFL6678S/12 |
| 2013 | xxPFL5**8**xx – xxPFL8**8**xx | 55PFL6678S/12 |
| 2014 | xxPFL5**9**xx, xxPUS6**9**xx | 42PUS6809/12 |
| 2015 | xxPFL5**0**xx, xxPUS6**0**xx | 43PUS6031/12 |

The 4th digit of the series encodes year: 6=2011, 7=2012, 8=2013, 9=2014, 0=2015.

### API v5 — HTTP, no auth (2014–2015)

Transitional generation. Superset of v1 commands. Many v5 TVs also respond on `/1/`.

| Series |
|--------|
| xxPUS6**9**xx, xxPUS7**9**xx, xxPUS6**0**xx, xxPUS7**0**xx (non-Android / Saphi OS) |

### API v6 — HTTPS + PIN pairing (2016–present)

**Saphi OS** (non-Android) — port 1925

| Year | Series | Example |
|------|--------|---------|
| 2016 | xxPUS6**1**xx, xxPFT5**1**xx | 43PUS6162/12 |
| 2017 | xxPUS6**2**xx | 65PUS6162/12 |
| 2018 | xxPUS6**3**xx | 43PUS6753/12 |
| 2019+ | xxPUS6**4**xx, lower-end PUS7xxx | — |

**Android TV** — port 1926

| Year | Series | Example |
|------|--------|---------|
| 2016 | xxPUS7**1**xx, xxPUS8**1**xx | 49PUS7101/12 |
| 2017 | xxPUS7**2**xx, OLEDxx**2** | 55PUS7502/12 |
| 2018 | xxPUS7**3**xx, xxPUS8**3**xx | 58PUS7304/12 |
| 2019 | xxPUS7**4**xx, OLEDxx**4** | 55OLED804/12 |
| 2020+ | xxPUS7**5**xx and newer | — |

> All OLED models (OLED803, OLED804, …) are Android TV — API v6 on port 1926.

---

## Installation

### Browser / PWA

```bash
git clone https://github.com/zloi2ff/philips-remote.git
cd philips-remote
python3 server.py
```

Open **http://localhost:8888**. The app scans the network and connects automatically. No pip install needed — stdlib only.

```bash
# Optional env vars
TV_IP=192.168.1.100 python3 server.py    # preset TV IP
SERVER_PORT=9000 python3 server.py       # change port (default: 8888)
API_TOKEN=secret python3 server.py       # enable HMAC auth
```

**To use as PWA on iPhone:** open the URL in Safari → Share → "Add to Home Screen".

### Native iOS App

Requires Xcode 15+, Apple Developer account.

```bash
npm install
npx cap sync ios
npx cap open ios
```

In Xcode: select your device → set signing team → **Cmd+R**.

The iOS app connects to the TV **directly** (no server needed) using `CapacitorHttp` to bypass CORS. TV IP is stored in `localStorage`.

---

## Architecture

```
┌─────────────────┐        ┌──────────────────┐
│   Browser / PWA │        │   iOS App        │
│                 │        │  (Capacitor 8)   │
│  fetch /api/*   │        │  CapacitorHttp   │
└────────┬────────┘        └────────┬─────────┘
         │                          │ direct HTTP/HTTPS
         ▼                          ▼
┌─────────────────┐        ┌──────────────────┐
│   server.py     │        │  Philips TV      │
│  Python proxy   │───────▶│  port 1925/1926  │
│  port 8888      │        │  JointSpace API  │
└─────────────────┘        └──────────────────┘
```

- **`server.py`** — stdlib-only Python proxy (528 lines, zero dependencies)
- **`www/index.html`** — single-file UI: all HTML, CSS, JS inline (~2200 lines)
- **`IS_CAPACITOR` flag** — switches between proxy mode (browser) and direct mode (iOS)
- **`ios/App/PhilipsWidgetExtension/`** — WidgetKit extension, reads TV config from App Group UserDefaults
- **Widget → App data flow:** JS `saveConfig()` → `WKScriptMessageHandler` → `UserDefaults(group.com.philips.remote)` → widget timeline reload

**iOS discovery** uses WebRTC to detect local IP → parallel /24 subnet scan → falls back to common subnet ranges. `AbortController` is required for scan timeouts (prevents URLSession pool exhaustion).

---

## API Reference

### TV Endpoints (JointSpace)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/{v}/system` | GET | System info, model name |
| `/{v}/audio/volume` | GET/POST | Get or set volume |
| `/{v}/sources` | GET | Available input sources |
| `/{v}/sources/current` | POST | Switch source |
| `/{v}/input/key` | POST | Send remote key code |

### Server Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/discover` | GET | Scan local /24 subnet for Philips TVs |
| `/config` | GET | Current TV IP/port/apiVersion |
| `/config` | POST | Set TV config `{"ip":"…","port":…}` |
| `/api/*` | ANY | Transparent proxy to TV |

### Key Codes

```
Standby · VolumeUp · VolumeDown · Mute
ChannelStepUp · ChannelStepDown
CursorUp · CursorDown · CursorLeft · CursorRight · Confirm
Back · Home · Source · Info · Options · Find · Adjust
Digit0–Digit9
Play · Pause · Stop · Rewind · FastForward · Record
RedColour · GreenColour · YellowColour · BlueColour
```

---

## Self-Hosting

Deploy on a home server so any device on your LAN can use the remote:

```bash
scp server.py user@192.168.1.10:/opt/philips-remote/
scp www/index.html user@192.168.1.10:/opt/philips-remote/www/
ssh user@192.168.1.10 "sudo systemctl restart philips-remote"
```

Example systemd unit:

```ini
[Unit]
Description=Philips TV Remote
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/philips-remote/server.py
WorkingDirectory=/opt/philips-remote
Restart=always
Environment=SERVER_PORT=8888

[Install]
WantedBy=multi-user.target
```

---

## Troubleshooting

**TV not found during scan**
- Make sure the TV and your device are on the same network
- If both are on Wi-Fi, check if **AP Isolation** (Client Isolation) is enabled on your router — disable it
- Wired (Ethernet) connection on the TV is more reliable for discovery
- Try entering the TV IP manually

**v6 TV — connection fails**
- A PIN dialog should appear on the TV screen during first pairing
- HTTPS with self-signed certificate is used — this is expected

**iOS app — TV not found**
- WebRTC subnet detection may fail on some networks; the app falls back to scanning common subnets (192.168.x.x, 10.x.x.x)
- Ensure Local Network permission is granted in iOS Settings → Privacy

---

## License

MIT
