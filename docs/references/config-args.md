---
layout: default
title: Configuration Arguments
description: IBGA configuration arguments in Docker Compose style
parent: References
nav_order: 1
---

# Configuration Arguments

IBGA is configured via environment variables in the `docker-compose.yml`.

| Variable | Required | Description |
|----------|:---:|-------------|
| `IB_USERNAME` | ✓ | IB account username |
| `IB_PASSWORD` | ✓ | IB account password |
| `IB_TIMEZONE` | ✓ | Time zone (TZ database name, e.g. `Asia/Shanghai`). Governs the daily restart time and the time reported by the API. |
| `IB_LOGINTAB` | ✓ | Login tab / API type: `IB API` or `FIX CTCI` |
| `IB_LOGINTYPE` | ✓ | Login type / trading mode: `Live Trading` or `Paper Trading` |
| `IB_LOGOFF` | ✓ | Daily restart time in `HH:MM AM/PM` format (e.g. `05:30 AM`). IBGA applies this and forces "Auto restart". |
| `IB_REGION` | | Region combo box: `America`, `Europe`, `Asia`, `China` |
| `IB_APILOG` | | Enable API message log. Empty = off, any value = on, `data` = also include market data |
| `IB_LOGLEVEL` | | Logging level: `System`, `Error`, `Warning`, `Info`, `Detail` |
| `AUTH_METHOD` | | Second factor: `passkey` (default, IBKR-mandated) or `totp` (legacy). Mutually exclusive. |
| `TOTP_KEY` | | TOTP secret; only used when `AUTH_METHOD=totp` |
| `IBGA_EXPORT_LOGS` | | `true` to export today's and yesterday's Gateway/API logs daily |
| `IBGA_LOG_EXPORT_DIR` | | Directory to export logs into (default: settings dir `/home/ibg_settings/exported_logs`) |

Values are case- and text-sensitive (e.g. `IB_LOGINTAB=IB API`, not `IBAPI`). IB Gateway must stay in English, since the automation scripts match UI text in English.

Internal variables with defaults (`IBG_DIR`, `IBG_SETTINGS_DIR`, `IBG_PORT_INTERNAL`, `IBG_PORT`, `IBG_DOWNLOAD_URL`) can be overridden but are rarely needed.
