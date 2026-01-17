# Philips TV Remote

Веб-пульт для телевізора Philips Smart TV (JointSpace API v1).

![Remote](https://img.shields.io/badge/TV-Philips%206158-blue)
![Python](https://img.shields.io/badge/Python-3.x-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

[English](README.md) | **Українська**

<p align="center">
  <img src="screenshot-collapsed.png" width="280" alt="Згорнутий">
  <img src="screenshot-expanded.png" width="280" alt="Розгорнутий">
</p>

## Підтримувані телевізори

- **Модель:** Philips 42PFL6158K/12 (та схожі серії 6xxx)
- **API:** JointSpace v1 (порт 1925)

## Можливості

- Увімкнення/вимкнення
- Навігація (стрілки, OK, Назад, Додому)
- Керування гучністю (+/-, без звуку, слайдер)
- Перемикання каналів (+/-)
- Цифрова клавіатура (0-9)
- Кольорові кнопки (червона, зелена, жовта, синя)
- Керування відтворенням (play, pause, stop, перемотка)
- Швидке перемикання джерел (TV, HDMI, Blu-ray тощо)
- PWA підтримка (додавання на домашній екран iOS/Android)

## Встановлення

### Швидкий старт

```bash
git clone https://github.com/zloi2ff/philips-remote.git
cd philips-remote
python3 server.py
```

Відкрий http://localhost:8888 у браузері.

### Налаштування

Відредагуй `server.py` для зміни IP-адреси телевізора:

```python
TV_IP = "192.168.31.214"  # IP твого телевізора
TV_PORT = 1925
SERVER_PORT = 8888
```

### Автозапуск (Linux systemd)

```bash
sudo cp philips-remote.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable philips-remote
sudo systemctl start philips-remote
```

## Використання на iPhone/Android

1. Відкрий `http://IP_СЕРВЕРА:8888` в Safari/Chrome
2. Натисни Поділитись → "На Початковий екран"
3. Використовуй як звичайний додаток

## API

Телевізор використовує JointSpace API v1:

| Endpoint | Метод | Опис |
|----------|-------|------|
| `/1/system` | GET | Інформація про систему |
| `/1/audio/volume` | GET/POST | Керування гучністю |
| `/1/sources` | GET | Доступні джерела |
| `/1/sources/current` | POST | Перемикання джерела |
| `/1/input/key` | POST | Надсилання команди |

### Коди клавіш

`Standby`, `VolumeUp`, `VolumeDown`, `Mute`, `ChannelStepUp`, `ChannelStepDown`, `CursorUp`, `CursorDown`, `CursorLeft`, `CursorRight`, `Confirm`, `Back`, `Home`, `Source`, `Info`, `Options`, `Find`, `Adjust`, `Digit0`-`Digit9`, `Play`, `Pause`, `Stop`, `Rewind`, `FastForward`, `Record`, `RedColour`, `GreenColour`, `YellowColour`, `BlueColour`

## Ліцензія

MIT
