# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Philips TV Remote — web-based remote control for Philips Smart TV (JointSpace API v1/v5/v6, port 1925). Runs as a Python proxy server with a single-page web UI, also packaged as a standalone native iOS app via Capacitor 8.

## Architecture

```
server.py           ← Python proxy: serves www/, proxies /api/* to TV, /discover, /config
www/index.html      ← Single-file web UI (HTML + CSS + JS inline), 1700+ lines
ios/App/            ← Xcode project (SPM, not CocoaPods)
capacitor.config.json
RELEASE_CHECKLIST.md ← Step-by-step App Store release instructions
```

**Dual-mode frontend:** The same `www/index.html` runs in two contexts:
- **Browser** (via `server.py`): `IS_CAPACITOR=false` → relative URLs like `/api/1/input/key` → proxy → TV
- **iOS/Capacitor** (`capacitor://localhost`): `IS_CAPACITOR=true` → direct URLs `http://{tvIp}:1925/1/input/key` → TV

**Key server endpoints:**
- `GET /discover` — scans local /24 subnet, 254 concurrent threads, rate-limited with `_discover_lock`
- `GET/POST /config` — runtime TV IP/port/apiVersion (mutable `tv_config` dict); IP validated against RFC-1918 ranges to prevent SSRF
- `/api/*` — transparent proxy; strips `/api` prefix, uses HTTPS for API v6+

**iOS direct mode** (no server needed):
- TV discovery: `getLocalIpViaWebRTC()` → `scanSubnetDirect()`, fallback to `scanCommonSubnets()` (8 common home subnets in parallel)
- CORS bypass: `CapacitorHttp.enabled: true` in `capacitor.config.json` patches `fetch()` through native Swift `URLSession`
- TV config stored in `localStorage`: keys `tvIp`, `tvPort`, `tvApiVersion`

**JointSpace API versions:** `check_tv()` / `probeTvDirect()` tries v1 HTTP → v6 HTTPS → v5 HTTP in order. v6 uses HTTPS with self-signed certs (verification disabled intentionally).

## Commands

```bash
# Run server (stdlib only, no pip install)
python3 server.py
TV_IP=192.168.1.100 SERVER_PORT=9000 python3 server.py

# iOS — build and install on connected device
npx cap sync ios
xcodebuild -project ios/App/App.xcodeproj -scheme App -configuration Debug \
  -destination 'id=<DEVICE_UDID>' -allowProvisioningUpdates build

# Find connected device UDID
xcrun devicectl list devices

# Install and launch on device
xcrun devicectl device install app --device <DEVICE_UDID> <path/to/App.app>
xcrun devicectl device process launch --device <DEVICE_UDID> com.philips.remote
```

## Key Design Decisions

- **Zero Python dependencies** — `server.py` uses only stdlib. No pip install.
- **Single HTML file** — all CSS/JS inline in `www/index.html`. No build step, no bundler.
- **`ThreadingHTTPServer`** — critical: TV API calls have 5s timeout; blocking would freeze all clients.
- **`selectTvByIndex(i, el, context)`** — TV list items use index into `_discoveredTvs{}` map instead of inline JSON args to avoid HTML attribute quote-escaping bugs.
- **`IS_CAPACITOR` flag** — `window.location.protocol === 'capacitor:'` — gates all iOS-specific paths.
- **Optional `API_TOKEN`** — env var for shared-secret auth on `/api/*`, `/config`, `/discover`; checked via `hmac.compare_digest`. Absent = open access (backward compat).

## Monetization (iOS)

- **Free**: AdMob banner (`@capacitor-community/admob`)
- **Pro**: RevenueCat IAP (`@revenuecat/purchases-capacitor`) — entitlement `pro`, product `remove_ads`
- Config object `MONETIZATION` in `www/index.html` has all placeholder IDs
- Currently using **Google test AdMob IDs** — replace before App Store. See `RELEASE_CHECKLIST.md`.

## Deployment

Production server: `zloi2ff@192.168.31.73` (Wyse 5070, Ubuntu), systemd service `philips-remote`, port 8888. SSH key auth. UFW must allow port 8888.

```bash
# Deploy server update
scp server.py www/index.html zloi2ff@192.168.31.73:/home/zloi2ff/philips-remote/
scp www/index.html zloi2ff@192.168.31.73:/home/zloi2ff/philips-remote/www/
ssh zloi2ff@192.168.31.73 "echo 'PASSWORD' | sudo -S systemctl restart philips-remote"
```

## Language

User communication: Ukrainian. Code, variables, commits: English.
