<h1 align="center">Philips TV Remote</h1>

<p align="center">
  Веб-пульт для телевізора Philips Smart TV — працює у браузері, як PWA та нативний iOS-додаток з віджетом на домашньому екрані.
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="#встановлення">Швидкий старт</a> · <a href="#підтримувані-телевізори">Підтримувані TV</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Python-3.x-3776AB?logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/iOS-17%2B-000000?logo=apple&logoColor=white" alt="iOS">
  <img src="https://img.shields.io/badge/Capacitor-8.x-119EFF?logo=capacitor&logoColor=white" alt="Capacitor">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/ліцензія-MIT-green" alt="License">
</p>

<p align="center">
  <img src="screenshot-collapsed.png" width="240" alt="Головний екран">
  &nbsp;&nbsp;&nbsp;
  <img src="screenshot-expanded.png" width="240" alt="Розширені елементи керування">
</p>

---

## Можливості

**Керування пультом**
- Увімкнення/вимкнення, навігація (стрілки, OK, Назад, Додому)
- Гучність (+/−, Mute, слайдер), Канали (+/−)
- Кольорові кнопки (Червона, Зелена, Жовта, Синя)
- Відтворення (Play, Pause, Stop, Перемотка назад/вперед, Запис)
- Швидке перемикання джерел (TV, HDMI 3/4, SAT, Blu-ray, Game, Theater, SCART)

**Підключення**
- Автопошук телевізорів Philips у локальній мережі (сканування підмережі /24)
- PIN-паринг для v6 TV (2016+)
- Підтримка API v1, v5 та v6 — версія визначається автоматично

**Платформа**
- Працює у будь-якому браузері (без встановлення)
- PWA — "Додати на Початковий екран" в iOS/Android
- Нативний iOS-додаток (Capacitor 8)
- **Віджет на домашньому екрані** — Vol+/Vol−/Mute/Standby без відкриття додатку (iOS 17+)
- Liquid Glass дизайн віджету на iOS 26+
- Тактильний відгук при натисканні кнопок (iOS)
- Темна / Світла / Авто тема

---

## Підтримувані телевізори

Використовує JointSpace API на порту 1925. Версія API визначається автоматично.

> **Активація JointSpace на телевізорах 2011–2015:** відкрий меню телевізора і введи `5646877223` на пульті.

### API v1 — HTTP, без авторизації (2009–2015)

| Рік | Серія | Приклад |
|-----|-------|---------|
| 2009 | xxPFL8xxx, xxPFL9xxx | 42PFL8684H/12 |
| 2010 | xxPFL7–9xxx | 46PFL8605H/12 |
| 2011 | xxPFL5**6**xx – xxPFL9**6**xx | 42PFL6158K/12 |
| 2012 | xxPFL5**7**xx – xxPFL8**7**xx | 47PFL6678S/12 |
| 2013 | xxPFL5**8**xx – xxPFL8**8**xx | 55PFL6678S/12 |
| 2014 | xxPFL5**9**xx, xxPUS6**9**xx | 42PUS6809/12 |
| 2015 | xxPFL5**0**xx, xxPUS6**0**xx | 43PUS6031/12 |

4-та цифра серії кодує рік: 6=2011, 7=2012, 8=2013, 9=2014, 0=2015.

### API v5 — HTTP, без авторизації (2014–2015)

Перехідне покоління. Розширений набір команд v1. Багато v5 TV також відповідають на `/1/`.

| Серія |
|-------|
| xxPUS6**9**xx, xxPUS7**9**xx, xxPUS6**0**xx, xxPUS7**0**xx (не Android / Saphi OS) |

### API v6 — HTTPS + PIN-паринг (2016–дотепер)

**Saphi OS** (не Android) — порт 1925

| Рік | Серія | Приклад |
|-----|-------|---------|
| 2016 | xxPUS6**1**xx, xxPFT5**1**xx | 43PUS6162/12 |
| 2017 | xxPUS6**2**xx | 65PUS6162/12 |
| 2018 | xxPUS6**3**xx | 43PUS6753/12 |
| 2019+ | xxPUS6**4**xx, нижчі PUS7xxx | — |

**Android TV** — порт 1926

| Рік | Серія | Приклад |
|-----|-------|---------|
| 2016 | xxPUS7**1**xx, xxPUS8**1**xx | 49PUS7101/12 |
| 2017 | xxPUS7**2**xx, OLEDxx**2** | 55PUS7502/12 |
| 2018 | xxPUS7**3**xx, xxPUS8**3**xx | 58PUS7304/12 |
| 2019 | xxPUS7**4**xx, OLEDxx**4** | 55OLED804/12 |
| 2020+ | xxPUS7**5**xx та новіші | — |

> Всі OLED-моделі (OLED803, OLED804, …) — Android TV, API v6 на порту 1926.

---

## Встановлення

### Браузер / PWA

```bash
git clone https://github.com/zloi2ff/philips-remote.git
cd philips-remote
python3 server.py
```

Відкрий **http://localhost:8888**. Додаток сканує мережу і підключається автоматично. Залежностей pip немає — тільки stdlib.

```bash
# Опціональні змінні середовища
TV_IP=192.168.1.100 python3 server.py    # задати IP телевізора
SERVER_PORT=9000 python3 server.py       # змінити порт (за замовч.: 8888)
API_TOKEN=secret python3 server.py       # увімкнути HMAC-авторизацію
```

**PWA на iPhone:** відкрий URL у Safari → Поділитись → "На Початковий екран".

### Нативний iOS-додаток

Потрібен Xcode 15+, обліковий запис Apple Developer.

```bash
npm install
npx cap sync ios
npx cap open ios
```

В Xcode: вибери пристрій → налаштуй команду підпису → **Cmd+R**.

iOS-додаток підключається до TV **напряму** (без сервера) через `CapacitorHttp` для обходу CORS. IP TV зберігається в `localStorage`.

---

## Архітектура

```
┌──────────────────┐        ┌──────────────────┐
│  Браузер / PWA   │        │   iOS-додаток    │
│                  │        │  (Capacitor 8)   │
│  fetch /api/*    │        │  CapacitorHttp   │
└────────┬─────────┘        └────────┬─────────┘
         │                           │ прямий HTTP/HTTPS
         ▼                           ▼
┌──────────────────┐        ┌──────────────────┐
│   server.py      │        │  Philips TV      │
│  Python-проксі   │───────▶│  порт 1925/1926  │
│  порт 8888       │        │  JointSpace API  │
└──────────────────┘        └──────────────────┘
```

- **`server.py`** — Python-проксі тільки на stdlib (528 рядків, нуль залежностей)
- **`www/index.html`** — один файл: HTML, CSS, JS inline (~2200 рядків)
- **Прапорець `IS_CAPACITOR`** — перемикає між режимом проксі (браузер) і прямим режимом (iOS)
- **`ios/App/PhilipsWidgetExtension/`** — розширення WidgetKit, зчитує конфіг TV з App Group UserDefaults
- **Потік даних Widget → App:** JS `saveConfig()` → `WKScriptMessageHandler` → `UserDefaults(group.com.philips.remote)` → перезавантаження timeline віджету

**iOS discovery** використовує WebRTC для визначення локального IP → паралельне сканування /24 → резервне сканування поширених підмереж (192.168.x.x, 10.x.x.x). `AbortController` обов'язковий для таймаутів (запобігає виснаженню пулу URLSession).

---

## API

### TV Endpoint-и (JointSpace)

| Endpoint | Метод | Опис |
|----------|-------|------|
| `/{v}/system` | GET | Системна інформація, назва моделі |
| `/{v}/audio/volume` | GET/POST | Отримати або встановити гучність |
| `/{v}/sources` | GET | Доступні джерела вхідного сигналу |
| `/{v}/sources/current` | POST | Перемикання джерела |
| `/{v}/input/key` | POST | Надіслати код клавіші пульта |

### Endpoint-и сервера

| Endpoint | Метод | Опис |
|----------|-------|------|
| `/discover` | GET | Сканування /24 для пошуку TV Philips |
| `/config` | GET | Поточний IP/порт/версія API TV |
| `/config` | POST | Встановити конфіг TV `{"ip":"…","port":…}` |
| `/api/*` | ANY | Прозорий проксі до TV |

### Коди клавіш

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

## Розгортання на сервері

Розгорни на домашньому сервері — тоді будь-який пристрій у мережі зможе керувати TV:

```bash
scp server.py user@192.168.1.10:/opt/philips-remote/
scp www/index.html user@192.168.1.10:/opt/philips-remote/www/
ssh user@192.168.1.10 "sudo systemctl restart philips-remote"
```

Приклад systemd unit:

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

## Вирішення проблем

**TV не знаходиться при скануванні**
- Переконайся, що TV і пристрій в одній мережі
- Якщо обидва по Wi-Fi — перевір, чи не увімкнений **AP Isolation** (Client Isolation) на роутері, і вимкни його
- Дротове (Ethernet) підключення TV надійніше для discovery
- Спробуй ввести IP TV вручну

**TV v6 — підключення не вдається**
- Під час першого підключення на екрані TV має з'явитись PIN-код
- HTTPS з самопідписаним сертифікатом — це очікувана поведінка

**iOS — TV не знаходиться**
- WebRTC може не визначити підмережу на деяких роутерах; додаток автоматично перемикається на сканування поширених підмереж
- Переконайся, що дозвіл на локальну мережу надано: Налаштування → Конфіденційність → Локальна мережа

---

## Ліцензія

MIT
