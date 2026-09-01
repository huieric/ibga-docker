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
