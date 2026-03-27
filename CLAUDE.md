# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Classic Remote — multi-brand TV remote control app. Supports Philips, LG, Samsung, Sony, TCL, Xiaomi, and Hisense TVs. Runs as a Python proxy server with a single-page web UI, also packaged as a standalone native iOS app via Capacitor 8.

## Architecture

```
server.py                              ← Python proxy: serves www/, proxies /api/* to TV (browser mode only)
www/index.html                         ← Single-file web UI (HTML + CSS + JS inline), ~3070 lines
ios/App/App/AppDelegate.swift          ← Registers WKScriptMessageHandler for tvConfig bridge
ios/App/App/TvConfigHandler.swift      ← Saves TV config (ip/port/brand/token/psk) to App Group UserDefaults
ios/App/App/TvConfigPlugin.swift       ← Capacitor plugin stub (secondary approach, not primary)
ios/App/PhilipsWidgetExtension/        ← WidgetKit extension (iOS 17+)
  PhilipsWidget.swift                  ← Widget UI + timeline provider (.never policy)
  TvControlIntent.swift                ← 4 AppIntents + multi-brand key dispatch (HTTP-based brands)
capacitor.config.json
docs/index.html                        ← GitHub Pages privacy policy (https://zloi2ff.github.io/classic-remote/)
RELEASE_CHECKLIST.md                   ← Step-by-step App Store release instructions
```

### Multi-Brand Driver Architecture

All 7 brands implemented in `www/index.html` via a driver abstraction pattern:

| Brand | Protocol | Port | Auth | JS Transport |
|-------|----------|------|------|-------------|
| Philips | HTTP REST (JointSpace) | 1925/1926 | Digest (v6) | `fetch()` |
| LG | WebSocket SSAP | 3000 | Client-key (TV prompt) | `WebSocket` |
| Samsung | WebSocket | 8001 | Token (TV prompt) | `WebSocket` |
| Sony | HTTP REST + IRCC SOAP | 80 | PSK header / PIN | `fetch()` |
| TCL | HTTP Roku ECP | 8060 | None | `fetch()` |
| Xiaomi | HTTP GET | 6095 | None (MIUI only) | `fetch()` |
| Hisense | HTTP Roku ECP | 8060 | None (Roku models only) | `fetch()` |

**Key abstractions in `www/index.html`:**
- `KEY_MAPS` — universal key → per-brand protocol key mapping (e.g., `'Power'` → `'Standby'` for Philips, `'KEY_POWER'` for Samsung)
- `EXTRA_BUTTONS` — brand-specific buttons rendered dynamically in the collapsible section
- `BRANDS` — brand metadata (name, default port)
- `driverSendKey(universalKey)` — dispatches to brand-specific send function (`_philipsSendKey`, `_lgSendKey`, `_samsungSendKey`, etc.)
- `driverGetVolume()` / `driverSetVolume()` — brand-aware volume control
- `driverProbe(ip, brand)` — probes a specific IP for a specific brand's TV
- `driverConnect()` / `driverDisconnect()` — manages WebSocket connections (LG/Samsung)
- `scanAllBrandsOnSubnet(subnet)` — parallel multi-protocol discovery

**First launch flow:** Brand selection screen → user picks brand or "Scan All" → brand-specific discovery → connect → main remote.

**Dual-mode frontend:** The same `www/index.html` runs in two contexts:
- **Browser** (via `server.py`): `IS_CAPACITOR=false` → relative URLs `/api/1/input/key` → proxy → TV
- **iOS/Capacitor** (`capacitor://localhost`): `IS_CAPACITOR=true` → direct URLs to TV

**iOS direct mode** (no server needed):
- TV discovery: `getLocalIpViaWebRTC()` → `scanSubnetDirect()`, fallback to `scanCommonSubnets()`
- **AbortController is required** for scan timeouts — `CapacitorHttp` passes `signal` to WKWebView for GET requests. `Promise.race` without signal does NOT cancel connections and causes URLSession pool exhaustion (762 zombie connections → TV not found).
- CORS bypass: `CapacitorHttp.enabled: true` in `capacitor.config.json` patches `fetch()` through native Swift `URLSession`
- Config stored in `localStorage`: `tvIp`, `tvPort`, `tvApiVersion`, `tvBrand`, `tvName`, plus per-IP auth tokens

**App Group data flow (widget):**
1. JS `saveConfig()` calls `window.webkit.messageHandlers.tvConfig.postMessage({ip, port, apiVersion, authUser, authPass, brand, token, psk})`
2. `TvConfigHandler.swift` validates RFC-1918 IP, writes to `UserDefaults(suiteName: "group.com.philips.remote")`
3. `WidgetCenter.shared.reloadAllTimelines()` triggers widget refresh
4. Widget `TvConfig.load()` reads brand + config from App Group
5. `TvSender.sendKey()` dispatches to brand-specific HTTP sender (Philips/Sony/Roku/Xiaomi); Samsung/LG silently no-op (WebSocket not available in widget extensions)

## Commands

```bash
# Run server (stdlib only, no pip install)
python3 server.py
TV_IP=192.168.1.100 SERVER_PORT=9000 python3 server.py

# iOS — sync and build
npm run sync                    # or: npx cap sync ios
npm run open                    # or: npx cap open ios

# Build for connected device
xcodebuild -project ios/App/App.xcodeproj -scheme App -configuration Debug \
  -destination 'id=<DEVICE_UDID>' -allowProvisioningUpdates build

# Build for simulator
xcodebuild -project ios/App/App.xcodeproj -scheme App -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIM_UDID>' -allowProvisioningUpdates build

# Find connected device UDID
xcrun devicectl list devices

# Install and launch on device
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/App-*/Build/Products/Debug-iphoneos -name "App.app" -maxdepth 1 | head -1)
xcrun devicectl device install app --device <DEVICE_UDID> "$APP_PATH"
xcrun devicectl device process launch --device <DEVICE_UDID> com.philips.remote

# Deploy to production server
npm run deploy
# or manually:
scp server.py zloi2ff@192.168.31.73:/home/zloi2ff/philips-remote/
scp www/index.html zloi2ff@192.168.31.73:/home/zloi2ff/philips-remote/www/
ssh zloi2ff@192.168.31.73 "sudo systemctl restart philips-remote"
```

## Key Design Decisions

- **Zero Python dependencies** — `server.py` uses only stdlib. No pip install.
- **Single HTML file** — all CSS/JS inline in `www/index.html`. No build step, no bundler.
- **`ThreadingHTTPServer`** — critical: TV API calls have 5s timeout; blocking would freeze all clients.
- **Universal key names** — all HTML buttons use logical names (`Power`, `VolumeUp`, `Up`, `OK`) mapped through `KEY_MAPS[brand]` to protocol-specific keys.
- **`selectTvByIndex(i, el, context)`** — TV list items use index into `_discoveredTvs{}` map instead of inline JSON args to avoid HTML attribute quote-escaping bugs.
- **`IS_CAPACITOR` flag** — `window.location.protocol === 'capacitor:' || !!window.Capacitor?.isNative` — gates all iOS-specific paths.
- **WebSocket drivers (LG/Samsung)** — persistent connections managed by `_lgWs`/`_samsungWs` globals; LG uses a secondary pointer socket for key input.
- **SONY IRCC** — SOAP XML over HTTP with `X-Auth-PSK` header; IRCC codes are base64-encoded IR commands stored in `SONY_IRCC` constant.
- **Roku ECP** — simple HTTP POST to `/keypress/{key}` on port 8060, no auth, shared by TCL and Hisense Roku models.
- **Optional `API_TOKEN`** — env var for shared-secret auth on `/api/*`, `/config`, `/discover`, `/probe`; checked via `hmac.compare_digest`. Absent = open access.
- **CORS restricted** — `Access-Control-Allow-Origin: *` only on `/api/*` proxy responses. `/config`, `/discover`, `/probe` have no CORS headers.
- **`apiFetch()`** — for Philips v6+Capacitor always delegates to `digestFetch()`. Other brands use their own send functions.
- **Adaptive layout** — `@media (min-height: 800px)` increases button sizes for Pro Max and tall screens. Color buttons placed above sources to avoid ad banner overlap.
- **Widget audio feedback** — `AudioServicesPlaySystemSound(1104)` in each AppIntent `perform()` (haptics not available in widget extensions).

## Widget Architecture

- **AppIntents** — `TvButtonView<Intent: AppIntent>` must stay generic (not `any AppIntent` array) to avoid `AppIntentsSSUTraining` build failures. Top-level functions also break SSUTraining — keep all helpers inside `enum` namespaces.
- **Multi-brand widget** — `TvSender.sendKey()` switches on `config.brand`: Philips (JointSpace), Sony (IRCC SOAP), TCL/Hisense (Roku ECP), Xiaomi (HTTP GET). Samsung/LG silently skip (WebSocket not supported in widget).
- **`BrandKeyMaps`** — maps logical actions (`VolumeUp`, `Standby`) to wire key names per brand; returns `nil` for unsupported actions (e.g., Xiaomi Mute).
- **`applicationDidBecomeActive`** — WKScriptMessageHandler registered here (not `didFinishLaunching`) because `CAPBridgeViewController.webView` is only available after Capacitor finishes loading.
- **Entitlements** — `ios/App/App/App.entitlements` and `ios/App/PhilipsWidgetExtension/PhilipsWidgetExtension.entitlements` — both must have `group.com.philips.remote`. `CODE_SIGN_ENTITLEMENTS` must be set in all 4 build configurations in `project.pbxproj`.
- **Timeline policy** — `.never` because `TvConfigHandler` calls `reloadAllTimelines()` on config change. No periodic wakeup needed.
- **iOS 26+ design** — `.glassEffect()` on `RoundedRectangle` inside `.background {}` — NOT on the `Button` itself (makes button invisible). Pre-iOS 26 uses dark gradient fallback.
- **Digest Auth in widget** — `LocalNetworkDelegate` conforms to both `URLSessionDelegate` (SSL) and `URLSessionTaskDelegate` (HTTP Digest). URLSession created per-request with `defer { session.finishTasksAndInvalidate() }` to prevent memory leak.
- **IP validation** — Widget's `TvConfig.load()` validates RFC-1918 before use (duplicated from `TvConfigHandler.isPrivateIPv4` because widget can't reference main target).

## Monetization (iOS)

- **Free**: AdMob banner (`@capacitor-community/admob`)
- **Pro**: RevenueCat IAP (`@revenuecat/purchases-capacitor`) — entitlement `pro`, product `remove_ads`
- Config object `MONETIZATION` in `www/index.html` (~line 1092) has all placeholder IDs
- AdMob uses **real production IDs**. RevenueCat uses **test key** — replace with `appl_` production key before enabling IAP. See `RELEASE_CHECKLIST.md`.
- App Store name: **Classic TV Remote Control** (Bundle ID: `com.philips.remote`)
- Privacy policy: https://zloi2ff.github.io/classic-remote/

## Deployment

Production server: `zloi2ff@192.168.31.73` (Wyse 5070, Ubuntu), systemd service `philips-remote`, port 8888. SSH key auth. UFW must allow port 8888.

## Language

User communication: Ukrainian. Code, variables, commits: English.
