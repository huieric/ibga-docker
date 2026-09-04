# ibga-docker

[中文](README.md) · [English](README.en.md)

> **Forked from** [heshiming/ibga](https://github.com/heshiming/ibga) (GPLv3).
> The `upstream` remote points at that upstream project; this fork adds
> containerization, CI/CD, dual image channels, and unattended passkey login on
> top of it.

A one-line way to run Interactive Brokers' IB Gateway in Docker, **7×24 unattended**.

> Image: `ghcr.io/huieric/ibkr` · License: GPLv3 · Repo: [github.com/huieric/ibga-docker](https://github.com/huieric/ibga-docker)

### Login demo

The GIF below was recorded in noVNC and shows the full login flow: container start → autofill credentials → passkey auth → login success → log export. (Username masked)

![Login demo](docs/images/login-demo.gif)

---

## What problem does it solve

IB Gateway is the bridge between your trading strategy and your IBKR account, but it has several traditional pain points:

| Pain point | Description |
|------|------|
| Requires a GUI | Java GUI program, cannot run on a pure CLI server |
| Forced daily restart | IBKR disconnects and restarts daily, interrupting strategies |
| Forced weekly logout | Kicked off after a week without re-login |
| Mandatory passkey auth | IBKR now requires passkey; manual operation is infeasible |
| Paper/Live dialogs | Paper trading shows a confirmation dialog every launch |

ibga-docker solves all of these with a Docker container + automation scripts.

---

## Architecture

```
┌───────────────────────────────────────────────────┐
│                  Container (ibga)                  │
│                                                     │
│  ┌───────┐   ┌───────────┐   ┌─────────────────┐  │
│  │ Xvfb  │──▶│  noVNC    │   │  Bash automation │  │
│  │virtual│   │(web monitor)│   │  (login/restart)│  │
│  └───────┘   └───────────┘   └────────┬────────┘  │
│       │                                │           │
│       ▼                                ▼           │
│  ┌────────────────────────┐  ┌──────────────────┐  │
│  │   IB Gateway (Java)    │◀─│  JAuto + xdotool  │  │
│  │  embedded Chromium     │  │  UI locate + input│  │
│  └───────────┬────────────┘  └──────────────────┘  │
└──────────────┼──────────────────────────────────────┘
               │ TCP 8888 (socat → 4001)
               ▼
    Your strategy (TWS API / ib_insync)
```

---

## Key features

### Unattended login
- **Passkey auto-login (default)**: with the separate [`soft-fido2`](https://github.com/huieric/soft-fido2) container (a software security key presented as a real USB device over USB/IP), IBGA clicks Authenticate automatically — no physical USB key, no manual steps.
- **TOTP auto-login (legacy)**: with `AUTH_METHOD=totp`, `oathtool` generates and fills the 6-digit code (IBKR no longer offers this to new accounts).

> The auth method is controlled by `AUTH_METHOD`: `passkey` (default) and `totp` are mutually exclusive.

### Stability
- **Daily auto-restart**: reconnects automatically at the `IB_LOGOFF` time
- **Crash recovery**: `restart: unless-stopped` + script-level process monitoring
- **Health check**: built-in healthcheck — `docker ps` shows `healthy`
- **Automatic log export**: `IBGA_EXPORT_LOGS=true` exports Gateway/API logs daily

### Usability
- **Disposable container**: binaries and settings are bind-mounted, so upgrades/migrations lose nothing
- **Dual image channels**: `stable` (production) / `latest` (testing)
- **CI/CD auto-build**: new IBKR releases are detected, built, and published automatically — upgrade with `docker compose pull`
- **Built-in Chromium**: open IBKR Client Portal inside the container (e.g. to register a passkey)

---

## Quick start

```yaml
# docker-compose.yml
services:
  my-ibga:
    image: ghcr.io/huieric/ibkr:stable
    restart: unless-stopped
    environment:
      - IB_USERNAME=your_username
      - IB_PASSWORD=your_password
      - IB_TIMEZONE=Asia/Shanghai
      - IB_LOGINTAB=IB API
      - IB_LOGINTYPE=Live Trading     # or Paper Trading
      - IB_LOGOFF=05:30 AM            # daily restart time
      - AUTH_METHOD=passkey           # passkey is the default, can be omitted
    volumes:
      - ./run/program:/home/ibg             # IB Gateway install dir
      - ./run/settings:/home/ibg_settings   # user settings dir
    ports:
      - "8888:8888"    # IB API port (socat forward)
      - "6080:6080"    # noVNC web view (monitor/debug)
```

```bash
docker compose up -d
# open http://server-ip:6080 to watch IB Gateway live
```

Connecting your strategy:

```python
import ib_insync
ib = ib_insync.IB()
ib.connect('127.0.0.1', 8888, clientId=1)
```

---

## Environment variables

See [`docs/references/config-args.md`](docs/references/config-args.md) for the full list. Core items:

| Variable | Required | Description |
|------|:---:|------|
| `IB_USERNAME` | ✅ | IB account username |
| `IB_PASSWORD` | ✅ | IB account password |
| `IB_TIMEZONE` | ✅ | Time zone (TZ database name, e.g. `Asia/Shanghai`) |
| `IB_LOGINTAB` | ✅ | `IB API` or `FIX CTCI` |
| `IB_LOGINTYPE` | ✅ | `Live Trading` or `Paper Trading` |
| `IB_LOGOFF` | ✅ | Daily restart time in `HH:MM AM/PM` |
| `AUTH_METHOD` | — | `passkey` (default) / `totp` (legacy) |
| `TOTP_KEY` | — | Only when `AUTH_METHOD=totp` |
| `IB_REGION` | — | `America` / `Europe` / `Asia` / `China` |
| `IB_APILOG` | — | API message log: empty / any value / `data` |
| `IB_LOGLEVEL` | — | `System` / `Error` / `Warning` / `Info` / `Detail` |
| `IBGA_EXPORT_LOGS` | — | Export logs daily when `true` |
| `IBGA_LOG_EXPORT_DIR` | — | Log export directory |

---

## Unattended passkey login (with soft-fido2)

IBKR now mandates passkey. This repo provides a two-part solution:

| Component | Repo | Role |
|------|------|------|
| `soft-fido2` container | [huieric/soft-fido2](https://github.com/huieric/soft-fido2) | imports the passkey private key and presents it as a real USB device over USB/IP |
| IBGA container | this repo | auto-login + clicks Authenticate (`AUTH_METHOD=passkey`) |

Data flow:

```
soft-fido2 container (network_mode: host, :3240)
     │ USB/IP protocol
     ▼
host usbip attach (vhci-hcd) → real USB device /dev/bus/usb/xxx/yyy
     │ bind mount /dev/bus/usb + cgroup 'c 189:* rwm'
     ▼
IBGA container → IB Gateway (embedded Chromium enumerates the key) → signed login
```

See [FAQ](docs/faq.md#how-to-setup-unattended-passkey-software-security-key-login) for the full setup.

> **Built-in Chromium**: lets you open Client Portal inside the container to register a passkey. Firefox is intentionally not installed (its WebAuthn routing enforces transport rules that block USB/IP passkeys).

---

## Security notes

- **Never expose the API port to the internet**: the IB API is unauthenticated raw TCP; bind it to `127.0.0.1`
- **Secrets**: prefer Docker secrets or a `.env` file over hard-coding credentials in the compose file
- See [`docs/references/security.md`](docs/references/security.md) for more

---

## Upgrading

```bash
docker compose pull      # pull new image
docker compose up -d     # recreate container (data kept via volumes)
```

---

## License

GPLv3. See [LICENSE](LICENSE).
