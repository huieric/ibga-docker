#!/usr/bin/env bash
# start_passkey.sh — 在 IB Gateway 容器内启动 passkey "Authenticate" 点击器
#
# 注意：软件 passkey 认证器本身已迁移到独立的 soft-fido2 仓库
# （github.com/huieric/soft-fido2），以 USB/IP 的方式在宿主机上呈现为一个
# 真实 USB 设备。IB Gateway 通过 `devices: [/dev/bus/usb]` 访问它。
#
# 因此本脚本只负责登录流程里的最后一步：当 IB Gateway 弹出 passkey 验证
# 对话框时，自动点击 "Authenticate" 按钮（点击后由 soft-fido2 完成 CTAP2
# 签名应答）。
#
# 环境变量：
#   PASSKEY_ENABLED   设为 1 才启用（默认关闭，避免影响 TOTP/IB Key 用户）
#
set -euo pipefail

PASSKEY_ENABLED="${PASSKEY_ENABLED:-0}"
PASSKEY_DIR="${PASSKEY_DIR:-/opt/ibga/passkey}"
CLICK_SCRIPT="$PASSKEY_DIR/click_authenticate.sh"

if [ "$PASSKEY_ENABLED" != "1" ]; then
    echo "[start-passkey] PASSKEY_ENABLED!=1; skipping passkey clicker." >&2
    exit 0
fi

log() { echo "[start-passkey] $*" >&2; }

# 把 soft-fido2 的 hidraw 节点补到容器内。
#
# IB Gateway 的内嵌 Chromium 在 Linux 上通过 /dev/hidraw*（usbhid 子系统）
# 发现 FIDO 密钥，而不是 /dev/bus/usb。宿主机 usbhid 会为 USB/IP 设备创建
# hidraw 节点，但容器的 /dev 是独立 tmpfs，看不到它；而 devices: 只快照
# USB 节点。这里从 /sys/class/hidraw 找到 VID/PID=3713 的设备并 mknod。
#
# 前提：compose 中需放行 hidraw 主设备号，即 device_cgroup_rules 同时含
#   'c 189:* rwm'（USB）和 'c <hidraw-major>:* rwm'（hidraw，通常是 239）。
(
    for _ in $(seq 1 60); do
        for d in /sys/class/hidraw/hidraw*; do
            [ -e "$d" ] || continue
            HRN="$(basename "$d")"
            FOUND=""
            if [ -r "$d/device/name" ] && [ "$(cat "$d/device/name" 2>/dev/null)" = "soft-fido2 FIDO2 Passkey" ]; then
                FOUND=1
            elif [ -r "$d/device/uevent" ] && grep -qi 'HID_ID=0003:00003713:00003713' "$d/device/uevent" 2>/dev/null; then
                FOUND=1
            fi
            if [ -n "$FOUND" ]; then
                MAJMIN="$(cat "$d/dev" 2>/dev/null)"
                if [ -n "$MAJMIN" ] && [ ! -e "/dev/$HRN" ]; then
                    sudo mknod -m 666 "/dev/$HRN" c "${MAJMIN%%:*}" "${MAJMIN##*:}" \
                        && log "Created /dev/$HRN (${MAJMIN}) so Chromium can reach the passkey."
                fi
                break 2
            fi
        done
        sleep 1
    done
) &
HIDNOD_PID=$!

# 监督循环：点击器常驻。万一它异常退出，立即重启，保证后续任何一次
# 重新登录（每日 IB_LOGOFF 重启等）都有点击器在场。
while :; do
    log "Starting Authenticate clicker (the passkey itself is served by the soft-fido2 container)..."

    bash "$CLICK_SCRIPT" &
    CLICK_PID=$!
    log "Clicker PID=$CLICK_PID"

    wait "$CLICK_PID" || true
    log "Clicker exited (code=$?); restarting in 2s ..."
    sleep 2
done
