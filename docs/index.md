---
layout: default
title: Home
description: IBGA runs IB Gateway headless in Docker, with unattended passkey login.
nav_order: 0
---

# IB Gateway Automation (IBGA)

IBGA runs [IB Gateway](https://www.interactivebrokers.com/en/trading/ibgateway-latest.php) in headless mode inside Docker, automating logins, daily restarts, and option dialogs.

IBKR now **mandates passkey** authentication. IBGA handles it unattended by default (`AUTH_METHOD=passkey`), served by the companion [`soft-fido2`](https://github.com/huieric/soft-fido2) container over USB/IP. The legacy TOTP (Mobile Authenticator App) flow is retained as a documented option.

## Benefits

* A `docker compose` flavored configuration
* Store username, password, time zone and other options in one place
* Automatic installation and upgrade of IB Gateway
* Automatic handling of daily restarts, crashes, and the one-week logout limit
* Automatic handling of paper trading confirmation and options dialogs
* Automatic daily export of logs
* Settings retained across upgrades (disposable container design)
* [Unattended passkey login (soft-fido2)](faq.md#how-to-setup-unattended-passkey-software-security-key-login) — default; IBKR now mandates passkey
* [Mobile Authenticator App automation (legacy)](faq.md#how-to-setup-totp-mobile-authenticator-app-automated-login)

## Under the hood

* IBGA is a set of bash scripts.
* [JAuto](https://github.com/huieric/jauto), a JVMTI agent, determines screen locations of windows, text boxes, and buttons.
* [xdotool](https://github.com/jordansissel/xdotool) simulates keyboard and mouse input.
* [Xvfb](https://en.wikipedia.org/wiki/Xvfb) + [noVNC](https://novnc.com/) provide a VNC-capable X11 environment for IB Gateway.
* [oathtool](https://www.nongnu.org/oath-toolkit/oathtool.1.html) generates TOTP passcodes (legacy).

## Example docker-compose.yml

```yaml
services:
  my-ibga:
    image: ghcr.io/huieric/ibkr:stable
    restart: unless-stopped
    environment:
      - IB_USERNAME=username
      - IB_PASSWORD=password
      - IB_TIMEZONE=America/New_York
      - IB_LOGINTAB=IB API
      - IB_LOGINTYPE=Live Trading
      - IB_LOGOFF=11:55 PM
      - AUTH_METHOD=passkey
    volumes:
      - ./run/program:/home/ibg
      - ./run/settings:/home/ibg_settings
    ports:
      - "8888:8888"
      - "6080:6080"
```
