# 常见问题（FAQ）

## IBGA 支持什么操作系统？

IBGA 是自包含的 Docker 镜像，可在任何能运行 Docker 的地方运行（Linux、macOS、Windows）。

## 二步认证如何处理？

IBKR 现已**强制 Passkey** 认证；旧的 IB Key 推送和 TOTP 方式已不再对多数账户开放。
默认的全自动路径是[软件 passkey（soft-fido2）流程](#如何配置无人值守-passkey登录)（`AUTH_METHOD=passkey`）。

对于仍开放旧方式的账户：

- **TOTP / Mobile Authenticator App** — `AUTH_METHOD=totp` + `TOTP_KEY`
- **IB Key 推送** — 仅手动：打开 VNC 界面，在手机上 2 分钟内批准

两种方式互斥：`AUTH_METHOD` 只能是 `passkey`（默认）或 `totp`。

## 如何运行多个账户？

为每个账户定义一个服务，使用不同的名字和端口：

```yaml
services:
  account-a:
    image: ghcr.io/huieric/ibkr:stable
    environment:
      - IB_USERNAME=username_a
    ports:
      - "8888:8888"
      - "6080:6080"
  account-b:
    image: ghcr.io/huieric/ibkr:stable
    environment:
      - IB_USERNAME=username_b
    ports:
      - "8889:8888"
      - "6081:6080"
```

注意：实盘与模拟账户之间无法共享行情订阅，除非两个实例使用相同的 MAC 地址
（IBGA 目前不支持）。

## 如何把日志导出到自定义宿主目录？

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

## 如何配置 TOTP（Mobile Authenticator App）自动登录？

> **旧方式。** IBKR 现已强制 passkey。TOTP 仅作为备选文档保留，可能不适用于你的账户。
> 使用 `AUTH_METHOD=totp` 并提供 `TOTP_KEY`。

TOTP 是基于预共享密钥生成的 6 位时间码。从 Mobile Authenticator 应用（如支持
导出密钥的 2FAS）导出密钥后设置：

```yaml
services:
  my-ibga:
    image: ghcr.io/huieric/ibkr:stable
    environment:
      - AUTH_METHOD=totp
      - TOTP_KEY=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

IBGA 会用 `oathtool` 自动生成并填入动态码。

## 如何配置无人值守 passkey 登录？

IBKR 强制 passkey。IBGA 支持完全无头的软件 passkey 流程，由两个组件配合：

1. **认证器** — [`huieric/soft-fido2`](https://github.com/huieric/soft-fido2)，
   导入 passkey 私钥，并经 USB/IP 呈现为真实 USB 设备。
2. **点击器** — IBGA 的 `_run_ibg.sh` 用 `xdotool`/JAuto 点击 "Authenticate"
   按钮（`AUTH_METHOD=passkey`，默认）。

为什么用 USB/IP：IB Gateway 的 passkey 界面跑在内嵌 Chromium 里，在 **USB 总线**
上枚举 FIDO 密钥；UHID 设备对它不可见。USB/IP 把密钥呈现为 Chromium 能找到的真实
USB 设备。

### 1. 导出 passkey 私钥（一次性，容器外操作）

在能交互的终端上（容器外）：

```bash
curl -fsSL https://raw.githubusercontent.com/leeguooooo/bitwarden-use/main/install.sh | sh
bwu config set email <your-bitwarden-email>
bwu unlock
bwu fido2 list
bwu fido2 get "<entry-name>" > ibkr_passkey.txt   # 原始 key:value 输出
```

保留 `bwu fido2 get` 的原始输出即可——soft-fido2 直接解析（无需转 JSON）。格式如下：

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

> **先在 Bitwarden 里注册 passkey**：IBKR 对 `getAssertion` 强制执行 `allowList`
> ——认证器只能返回 IBKR 发给**该账户**的凭据 ID，浏览器还会在本地检查该列表。
> 在别处注册的凭据不在列表里，登录会报 "Try a different security key"。
> 请在 Bitwarden 扩展里为该账户注册新 passkey，再导出。

### 2. 运行 soft-fido2 认证器容器

```yaml
services:
  soft-fido2:
    image: ghcr.io/huieric/soft-fido2:latest
    network_mode: host
    restart: unless-stopped
    volumes:
      - ./passkeys:/run/fido/passkeys:ro   # 每个 IBKR 账户一个文件
    environment:
      SOFT_FIDO2_IMPORT_DIR: /run/fido/passkeys
```

```bash
docker compose up -d
```

### 3. 在宿主机上挂载为真实 USB 设备

```bash
sudo modprobe vhci-hcd
sudo usbip attach -r 127.0.0.1 -b 1-1.1
lsusb -v -d 3713:3713   # 应显示虚拟 FIDO2 设备
```

> 重启或容器重启后需重复。开机加载模块：`echo vhci-hcd | sudo tee
> /etc/modules-load.d/vhci-hcd.conf`。`usbip` 在 `linux-tools-generic` 中；
> `vhci-hcd` 在 `linux-modules-extra`（Ubuntu/AWS）中。自动重挂请使用
> soft-fido2 的 `usbip-watchdog.service`。

### 4. 让 IB Gateway 访问虚拟 USB 设备

```yaml
services:
  my-ibga:
    image: ghcr.io/huieric/ibkr:stable
    volumes:
      - /dev/bus/usb:/dev/bus/usb   # 实时查看宿主 USB 设备
    device_cgroup_rules:
      - 'c 189:* rwm'               # USB 设备主设备号 189
      - 'c 239:* rwm'               # hidraw (usbhid) 节点
    environment:
      - AUTH_METHOD=passkey
      # ... 其他 IB_* 变量 ...
```

> Chromium 通过 `/dev/bus/usb`（libusb）和 `/dev/hidraw*`（usbhid）枚举 FIDO 密钥。
> `manager.sh`（`AUTH_METHOD=passkey` 时）会在容器内自动 `mknod` hidraw 节点；
> `c 239:*` 规则允许对其 I/O。hidraw 主设备号通常是 239（`grep hidraw /proc/devices`）。

### 5. 验证

启动两个容器。IBGA 填入凭据、点击 "Authenticate"，soft-fido2 对 WebAuthn 挑战签名。检查：

```bash
docker compose logs soft-fido2
docker exec <ibga> sh -c 'ls /dev/bus/usb/*/* 2>/dev/null'
```
