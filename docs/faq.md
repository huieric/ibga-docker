---
layout: default
title: Frequently Asked Questions
description: Frequently asked questions for IBGA.
nav_order: 3
---

# FAQ

- [What OS does IBGA support?](#what-os-does-ibga-support)
- [How is two-factor authentication handled?](#how-is-two-factor-authentication-handled)
- [How do I run multiple accounts?](#how-do-i-run-multiple-accounts)
- [How do I export logs to a custom host directory?](#how-do-i-export-logs-to-a-custom-host-directory)
- [How to setup TOTP (Mobile Authenticator App) automated login?](#how-to-setup-totp-mobile-authenticator-app-automated-login)
- [How to setup unattended passkey (software security key) login?](#how-to-setup-unattended-passkey-software-security-key-login)

---

## What OS does IBGA support?

IBGA is a self-contained Docker image. It runs anywhere Docker runs (Linux, macOS, Windows).

## How is two-factor authentication handled?

IBKR now **mandates passkey** authentication; the legacy IB Key push and TOTP flows are no longer offered to most accounts. The default, fully-automated path is the [software passkey (soft-fido2) flow](#how-to-setup-unattended-passkey-software-security-key-login) (`AUTH_METHOD=passkey`).

For accounts that still expose older flows:

- **TOTP / Mobile Authenticator App** — `AUTH_METHOD=totp` + `TOTP_KEY` (see [below](#how-to-setup-totp-mobile-authenticator-app-automated-login)).
- **IB Key push** — manual only: open the VNC view and approve on your phone within 2 minutes.

The two methods are mutually exclusive: `AUTH_METHOD` is exactly `passkey` (default) or `totp`.

## How do I run multiple accounts?

Define one service per account, with distinct names and ports:

```yaml
services:
  account-a:
    image: ghcr.io/huieric/ibkr:stable
    environment:
      - IB_USERNAME=username_a
      # ...
    ports:
      - "8888:8888"
      - "6080:6080"
  account-b:
    image: ghcr.io/huieric/ibkr:stable
    environment:
      - IB_USERNAME=username_b
      # ...
    ports:
      - "8889:8888"
      - "6081:6080"
```

Note: live and paper accounts cannot share market-data subscriptions unless both instances share the same MAC address, which IBGA does not currently support.

## How do I export logs to a custom host directory?

```yaml
services:
  my-ibga:
    image: ghcr.io/huieric/ibkr:stable
    environment:
      - IBGA_EXPORT_LOGS=true
      - IBGA_LOG_EXPORT_DIR=/home/ibg_logs
    volumes:
      - ./run/program:/home/ibg
      - ./run/settings:/home/ibg_settings
      - ./run/logs:/home/ibg_logs
```

## How to setup TOTP (Mobile Authenticator App) automated login?

> **Legacy option.** IBKR now mandates passkey. TOTP is documented as a
> fallback only and may not be offered to your account. Use `AUTH_METHOD=totp`
> and provide `TOTP_KEY`.

TOTP is a 6-digit time-based code generated from a pre-shared secret. To obtain the secret, export it from your Mobile Authenticator app (e.g. 2FAS, which allows secret export), then set:

```yaml
services:
  my-ibga:
    image: ghcr.io/huieric/ibkr:stable
    environment:
      - AUTH_METHOD=totp
      - TOTP_KEY=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

IBGA generates and enters the code automatically using `oathtool`.

## How to setup unattended passkey (software security key) login?

IBKR mandates passkey authentication. IBGA supports a fully headless software-passkey flow split across two components:

1. **The authenticator** — [`huieric/soft-fido2`](https://github.com/huieric/soft-fido2), which imports the passkey private key and serves it as a real USB device over USB/IP.
2. **The clicker** — IBGA's `_run_ibg.sh` clicks the "Authenticate" button via `xdotool`/JAuto (`AUTH_METHOD=passkey`, the default).

Why USB/IP: IB Gateway's passkey UI runs in an embedded Chromium that enumerates FIDO keys on the **USB bus**; a UHID device is invisible to it. USB/IP presents the key as a real USB device Chromium can find.

### 1. Export the passkey private key (once, out-of-band)

On a machine where you can interact with a terminal (outside the container):

```bash
curl -fsSL https://raw.githubusercontent.com/leeguooooo/bitwarden-use/main/install.sh | sh
bwu config set email <your-bitwarden-email>
bwu unlock
bwu fido2 list
bwu fido2 get "<entry-name>" > ibkr_passkey.txt   # raw key:value output
```

Keep the raw `bwu fido2 get` output as-is — soft-fido2 parses it directly (no JSON conversion). It looks like:

```
name: example-ibkr
credentialId: 01234567-89ab-cdef-0123-456789abcdef
rpId: interactivebrokers.com.hk
userHandle: <redacted>
keyType: public-key
keyCurve: P-256
privateKey (base64url): <redacted>
-----BEGIN PRIVATE KEY-----
<redacted>
-----END PRIVATE KEY-----
```

> **Register the passkey in Bitwarden first**: IBKR enforces a strict
> `allowList` on `getAssertion` — the authenticator may only return a
> credential whose ID IBKR issued to *this* account, and the browser checks
> that list locally. A credential registered elsewhere will not be in the
> list, so the login fails with "Try a different security key". Register a new
> passkey for the account in the Bitwarden extension, then export it.

### 2. Run the soft-fido2 authenticator container

```yaml
services:
  soft-fido2:
    image: ghcr.io/huieric/soft-fido2:latest
    network_mode: host
    restart: unless-stopped
    volumes:
      - ./ibkr_passkey.txt:/run/fido/ibkr_passkey.txt:ro
    environment:
      SOFT_FIDO2_IMPORT_FILE: /run/fido/ibkr_passkey.txt
```

```bash
docker compose up -d
```

### 3. Attach it as a real USB device on the host

```bash
sudo modprobe vhci-hcd
sudo usbip attach -r 127.0.0.1 -b 1-1.1
lsusb -v -d 3713:3713   # should show the virtual FIDO2 device
```

> Repeat after a reboot or container restart. To load the module at boot:
> `echo vhci-hcd | sudo tee /etc/modules-load.d/vhci-hcd.conf`. `usbip` ships
> in `linux-tools-generic`; `vhci-hcd` is in `linux-modules-extra` (Ubuntu/AWS).
> For automatic re-attach, use soft-fido2's `usbip-watchdog.service`.

### 4. Give IB Gateway access to the virtual USB device

```yaml
services:
  my-ibga:
    image: ghcr.io/huieric/ibkr:stable
    volumes:
      - /dev/bus/usb:/dev/bus/usb   # live view of host USB devices
    device_cgroup_rules:
      - 'c 189:* rwm'               # USB device nodes use major 189
      - 'c 239:* rwm'               # hidraw (usbhid) nodes
    environment:
      - AUTH_METHOD=passkey
      # ... other IB_* variables ...
```

> Chromium enumerates FIDO keys through both `/dev/bus/usb` (libusb) and
> `/dev/hidraw*` (usbhid). `manager.sh` (when `AUTH_METHOD=passkey`)
> automatically `mknod`s the hidraw node inside the container; the `c 239:*`
> rule permits I/O on it. The hidraw major is usually 239 (`grep hidraw
> /proc/devices`).

### 5. Verify

Start both containers. IBGA enters credentials, clicks "Authenticate", and soft-fido2 signs the WebAuthn challenge. Check:

```bash
docker compose logs soft-fido2
docker exec <ibga> sh -c 'ls /dev/bus/usb/*/* 2>/dev/null'
```
