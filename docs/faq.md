---
layout: default
title: Frequently Asked Questions
description: Frequently asked questions for IBGA, including bash script and Docker Compose configuration examples.
nav_order: 3
---

# IBGA Frequently Asked Questions
{: .no_toc }

<details open markdown="block">
  <summary>
    Table of contents
  </summary>
  {: .text-delta }
1. TOC
{:toc}
</details>

---

## What OS does IBGA support?

IBGA is a self-sufficient image. It runs on Docker. <a href="https://docs.docker.com/engine/install/" target="_blank">Docker is available on a variety of Linux platforms, macOS, and Windows 10</a>.

---

## What makes IBGA different from IBC?

<a href="https://github.com/IbcAlpha/IBC" target="_blank">IBC</a> automates many aspects of the Interactive Broker trading software. It is, however, not designed to run in a headless server. Before I started on IBGA, I spent plenty of time trying to make IBC work inside a container but couldn't reliably do so.

Technically, IBC is a Java program hosting the IB Gateway main class. Certain aspects of IBC can only be done via reverse-engineering how IB Gateway works. IBGA on the other hand, uses two-component automation: one to extract UI coordinates, and another to simulate input. It is a more efficient way to achieve automation, and I don't need to reverse-engineer the app.

---

## Can I host IBGA on an internet server?

**Not recommended.**{: .text-red-200 } Please refer to [Security](references/security.md) to learn about the potential issues of hosting IBGA on a public server.

---

## How is two-factor authentication (Interactive Brokers Secure Login System SLS) handled in IBGA?

Interactive Brokers now enforces two-factor authentication for trading. As a result, IBGA's login procedure can no longer be fully automated. The easiest second factor (whether you have a physical password device or not) is to configure IB Key on your phone (<a href="https://guides.interactivebrokers.com/iphone/log_in/activating_ios.htm" target="_blank">iPhone</a>, <a href="https://guides.interactivebrokers.com/androidphone/log_in/activating_ios.htm" target="_blank">Android</a> Guide). Once this is configured, you will see the following IBGA screen (via VNC) upon login, right after IBGA automatically enters the password.

<img src="images/two-factor-auth.png" width="500">

Your phone will receive a push notification where you can tap and allow the login.

IBGA can support physical password devices too, in which case, you have to open up the VNC in a browser (generally a computer is preferred over a phone) to enter the password according to instructions.

In both scenarios, the confirmation has to be done within 2 minutes. If you didn't complete the login, IBG will return to the initial login screen.

Note that if you have more than one device (for instance, an IB Key on phone and a physical device), you will be presented with a choice, in which case, you have to open up the VNC in a browser and choose "IB Key" before you receive a push notification. By default, IBGA will not touch second factor device choices. But by [setting IB_PREFER_IBKEY environment variable to "true"](references/config-args.md#IB_PREFER_IBKEY), IBGA will automatically choose IB Key when there are more than one choices, enabling simple confirmation without VNC.

---

## How do I run multiple instances of IB Gateway on the same server?

In the [example configuration](getting-started/configuring.md#an-example-docker-compose-configuration-file), only one service node (`my-ibga`) is created. Within the context of IBGA, one service is one container running one instance of IB Gateway. Running another instance needs another service node, with different ports. For example:

    version: '2'
    services:
      my-ibga:
        ...
        environment:
          ...
          - IB_USERNAME=username_account1
          ...
        ports:
          - "15800:5800"
          - "4000:4000"
      my-other-account:
        ...
        environment:
          ...
          - IB_USERNAME=username_account2
          ...
        ports:
          - "15801:5800"
          - "4001:4000"

However, you cannot share live account market data subscriptions with the paper trading account using this method. For market data sharing to work, both IB Gateway instances must share the same <a href="https://en.wikipedia.org/wiki/MAC_address" target="_blank">NIC MAC address</a>, which IBGA does not currently support.

---

## How do I export logs to a non-settings directory on the host?

First, log exporting is configured using the [`IBGA_EXPORT_LOGS`](references/config-args.html#IBGA_EXPORT_LOGS) variable. To export into a custom directory, mount it in `docker-compose.yml` like the program and settings directory, and set [`IBGA_LOG_EXPORT_DIR`](references/config-args.html#IBGA_LOG_EXPORT_DIR) respectively:

    version: '2'
    services:
      my-ibga:
        image: ghcr.io/huieric/ibkr
        environment:
          ...
          - IBGA_EXPORT_LOGS=true
          - IBGA_LOG_EXPORT_DIR=/home/ibg_logs
        volumes:
          - ./run/program:/home/ibg
          - ./run/settings:/home/ibg_settings
          - ./run/logs:/home/ibg_logs

---

## Why Xvfb but not the modern xserver-xorg-video-dummy as the framebuffer?

Mainly the size. Switching to `xserver-xorg-video-dummy` adds about 30MB of additional dependencies to the image without any improvement to the functionality whatsoever.

---

## Can I distribute IBGA as a commercial product?

IBGA is available under the [GPLv3](https://www.gnu.org/licenses/gpl-3.0.en.html){:target="_blank"} license as well as a commercial license. Users choosing to use IBGA under the free, open-source license must comply with its terms. Alternatively, users may choose to purchase a commercial license, which enables the distribution of IBGA in any form without restrictions.

Please contact `heshiming at gmail dot com` for the commercial licensing option.

---

## How to setup TOTP (Mobile Authenticator App) automated login?

<a href="https://ibkrguides.com/securelogin/sls/mobile-authenticator.htm" target="_blank">IBKR Mobile Authenticator</a> is a form of two-factor authentication via a common standard, software based solution. It generates a 6-digit numeric passcode calculated using a pre-shared secret and the current time.

Since late 2023, new accounts at IBKR would be prompted to use Mobile Authenticator Apps as the first option of second factor login. Upon login, the IBKR Portal will show a QR code (containing a shared secret generated by IBKR) asking you to use an app to scan it, and then enter the 6-digit passcode to confirm.

In this guide, we will use the <a href="https://2fas.com" target="_blank">2FAS</a> app as the Mobile Authenticator App, because it is open-source and the secret keys can easily be exported. If you choose to use a commercial app such as <a href="https://shieldplanet.com/extract-secret-keys-from-google-authenticator-qr-code/" target="_blank">Google Authenticator</a>, you will generally face some difficulty in exporting those secret keys because the designer of the program does not let you easily move to an alternative (No it has nothing to do with security per se). And even though 2FAS is available on both iOS and Android, it is easier to copy a file from Android as for iOS, you still need to connect a cable and use iTunes to transfer the backup file.

Once you used 2FAS app to obtain Mobile Authenticator access, <a href="https://2fas.com/support/2fas-mobile-app/i-want-to-move-copy-transfer-tokens-codes-between-ios-and-android/">use its export function to export the key to a "local 2FAS backup file"</a>. Copy this .2fas file to a computer. It is in fact a text file which you can open using a text editor. Its content is similar to this:

    { "services":
      [
        { "name":"Interactive Brokers",
          "secret":"XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
          "updatedAt":17249840000000,
          "otp":
            {
              "link":"otpauth://totp/Interactive Brokers:username?secret=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX&issuer=Interactive Brokers",
              "label":"username",
              "account":"username",
              "issuer":"Interactive Brokers",
              "tokenType":"TOTP",
              "source":"Link"
            },
            "order":{"position":0},"icon":{"selected":"Label","label":{"text":"IN","backgroundColor":"Brown"},"iconCollection":{"id":"id"}}}
        ],
      "groups":[],"updatedAt":17249840000000,"schemaVersion":4,"appVersionCode":5000022,"appVersionName":"5.4.5"
    }

The part marked as "X" in the above content is your 32-character secret key (generated by IBKR, received via the QR code at 2FAS). Once you obtained it, you can use the `TOTP_KEY` environment variable in the docker-compose configuration:

    services:
      my-ibga:
        image: ghcr.io/huieric/ibkr
        environment:
          ...
          - TOTP_KEY=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

And IBGA will automatically generate and enter the 6-digit passcode for you. Generation of the code is done by a third-party program named <a href="https://www.nongnu.org/oath-toolkit/oathtool.1.html" target="_blank">oathtool</a>.

Note that if your account is already using IB Key or Printed/Digital Keycode Card, there is currently no way to switch to Mobile Authenticator App (as of November 2024).

---

## How to setup unattended passkey (software security key) login?

Interactive Brokers now mandates **passkey** authentication for many accounts; the
TOTP / IB Key flows that IBGA could automate no longer apply. IBGA supports a
**software passkey** solution that keeps login fully headless. It is split across
two cooperating components:

1. **The authenticator** — a separate container,
   [`huieric/soft-fido2`](https://github.com/huieric/soft-fido2), imports the
   passkey private key and serves it as a **real USB device over USB/IP**.
2. **The clicker** — IBGA's `__maintenance_handle_passkey` (in
   `_run_ibg.sh`) clicks the passkey "Authenticate" button via
   `xdotool`/JAuto once IB Gateway shows the prompt (enabled with
   `PASSKEY_ENABLED=1`).

Why USB/IP: IB Gateway's passkey UI runs in an embedded Chromium that enumerates
FIDO keys on the **USB bus**; a UHID device (`/dev/uhid`) is invisible to it.
USB/IP presents the software key as a real USB device, which Chromium can find.

### 1. Export the passkey private key (once, out-of-band)

On a machine where you can interact with a terminal (this step is interactive and
is done **outside** the container):

```bash
curl -fsSL https://raw.githubusercontent.com/leeguooooo/bitwarden-use/main/install.sh | sh
bwu config set email <your-bitwarden-email>
bwu unlock           # prompts for your master password
bwu fido2 list       # find the IBKR passkey entry
bwu fido2 get "<entry-name>" > ibkr_passkey.txt   # raw key:value output, no conversion
```

Keep the raw `bwu fido2 get` output as-is — soft-fido2 parses it directly
(no JSON conversion). It looks like:

```
name: IBKR-trader
credentialId: 8f2f1b74-012e-4344-90e6-ff808c1eecd5
rpId: interactivebrokers.com.hk
userHandle: 1Ssnr-E_lIGEvjuKztQCLw
keyType: public-key
keyCurve: P-256
privateKey (base64url): MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg...
-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----
```

The key material does not rotate, so you only need to do this once.

> **Register the passkey in Bitwarden first**: IBKR enforces a strict
> `allowList` on `getAssertion` — the authenticator may only return a
> credential whose ID IBKR issued to *this* account, and the browser checks
> that list locally. A credential registered elsewhere (e.g. Windows Hello on
> another machine) will not be in the list, so the login fails with
> "Try a different security key". Register a new passkey for the account in
> the Bitwarden extension, then export it with the steps above.

### 2. Run the soft-fido2 authenticator container

The authenticator imports the exported file and serves it as a real USB device
over USB/IP (port `3240`, host network). Create a `compose.yml` next to your
ibga compose file:

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
docker compose logs -f soft-fido2   # expect "USB/IP authenticator listening on 0.0.0.0:3240"
```

### 3. Attach it as a real USB device on the host

```bash
sudo modprobe vhci-hcd
sudo usbip list -r 127.0.0.1
sudo usbip attach -r 127.0.0.1 -b 1-1.1
lsusb -v -d 3713:3713   # should show the virtual FIDO2 device
```

> Repeat after a reboot or container restart (the `vhci-hcd` module and the
> `usbip attach` binding do not persist). To load the module at boot, run once:
> `echo vhci-hcd | sudo tee /etc/modules-load.d/vhci-hcd.conf`.
> `usbip` ships in `linux-tools-generic` (Debian/Ubuntu); `vhci-hcd` is in
> `linux-modules-extra` on Ubuntu/AWS.

### 4. Give IB Gateway access to the virtual USB device

After `usbip attach`, the virtual key appears on the host as a real USB device
under `/dev/bus/usb/...`. Expose that directory as a **live bind mount** (a
`devices:` entry snapshots devices at container creation and will not see the
dynamically-attached USB/IP device) and permit the USB device major number:

```yaml
services:
  my-ibga:
    image: ghcr.io/huieric/ibkr
    volumes:
      - /dev/bus/usb:/dev/bus/usb   # live view of host USB devices
    device_cgroup_rules:
      - 'c 189:* rwm'               # USB device nodes use major 189
      - 'c 239:* rwm'               # hidraw (usbhid) nodes — IB Gateway's embedded
                                    # Chromium discovers FIDO keys via /dev/hidraw*
    environment:
      - PASSKEY_ENABLED=1
      # ... other IB_* variables ...
```

> **Why hidraw too**: IB Gateway's passkey UI runs in an embedded Chromium that
> enumerates FIDO keys through `/dev/hidraw*` (the usbhid subsystem), not
> `/dev/bus/usb`. The host's usbhid driver creates `/dev/hidrawN` for the
> USB/IP device; `manager.sh` (when `PASSKEY_ENABLED=1`) automatically `mknod`s
> that node inside the container, and the `c 239:*` cgroup rule above is what
> actually permits I/O on it. The hidraw major number is dynamic (usually 239;
> check with `grep hidraw /proc/devices` on the host if it differs).

> **Startup order** (across two compose files): keep the two projects
> **independent** — do not merge them with `include:` and do not add
> `depends_on`. `include:` would pull soft-fido2 into this project and start it
> a second time; `depends_on` can only reference services within one project.
> No Compose ordering is needed: soft-fido2 is self-sufficient (a host-side
> systemd/watchdog runs `usbip attach`), and IB Gateway retries its login until
> the key is available. Start them independently:
>
> ```bash
> docker compose -f <soft-fido2>/compose.yml up -d   # watchdog attaches the key
> docker compose -f <ibga>/compose.yml up -d
> ```

### 5. Verify

Start both containers. IB Gateway should log in automatically: IBGA enters the
credentials, the clicker presses "Authenticate", and the soft-fido2 container
signs the WebAuthn challenge. Check the logs:

```bash
docker compose logs soft-fido2       # "loaded passkey rpId=..." + "listening on 0.0.0.0:3240"
docker exec <ibga> sh -c 'ls /dev/bus/usb/*/* 2>/dev/null'   # the virtual device node
```


