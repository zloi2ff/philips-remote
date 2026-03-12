# App Store Release Checklist

## Step 1 — AdMob

1. Register at https://admob.google.com
2. Add iOS app → get **App ID** and **Banner Unit ID**
3. Replace in 3 files:

**`ios/App/App/Info.plist`** line 59:
```xml
<string>ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX</string>
```

**`capacitor.config.json`** — replace both values:
```json
"AdMob": {
  "appId": "ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX",
  "initializeForTesting": false
}
```

**`www/index.html`** — `MONETIZATION` object, line ~1058:
```js
admobBannerId: 'ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX',
```

---

## Step 2 — RevenueCat

1. Register at https://app.revenuecat.com
2. Create project → Add iOS app → get **API Key** (`appl_...`)
3. Create: Entitlement `pro` → Product `remove_ads` → Offering `default`

**`www/index.html`** — `MONETIZATION` object:
```js
rcApiKeyIos: 'appl_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
```

---

## Step 3 — App Store Connect

1. Create app at https://appstoreconnect.apple.com
   - Bundle ID: `com.philips.remote`
   - SKU: `philips-remote`

2. Add In-App Purchase:
   - Type: **Non-Consumable**
   - Product ID: `remove_ads`  ← must match exactly
   - Price: choose tier
   - Add localization (EN + UK)

3. After first submission, get numeric **App Store ID** (from the app URL on App Store)

**`www/index.html`** — `MONETIZATION` object:
```js
appStoreId: '1234567890',  // numeric ID from App Store URL
```

---

## Step 4 — Xcode

- Open `ios/App/App.xcodeproj` in Xcode
- Target `App` → `Signing & Capabilities` → `+ Capability` → **In-App Purchase**

---

## Step 5 — Final build

```bash
npx cap sync ios
# Then archive in Xcode: Product → Archive → Distribute App
```

---

## Summary of all replacements

| File | What to replace | Where to get |
|------|----------------|-------------|
| `ios/App/App/Info.plist` | `GADApplicationIdentifier` value | AdMob console |
| `capacitor.config.json` | `AdMob.appId` + set `initializeForTesting: false` | AdMob console |
| `www/index.html` | `admobBannerId` | AdMob console → Banner Ad Unit |
| `www/index.html` | `rcApiKeyIos` | RevenueCat → Project Settings → API Keys |
| `www/index.html` | `appStoreId` | App Store Connect (after first submission) |
