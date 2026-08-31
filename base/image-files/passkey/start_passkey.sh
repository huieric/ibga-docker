#!/usr/bin/env bash
# start_passkey.sh — 在容器内启动整套软件 passkey 登录链路
#
# 这个脚本负责：
#   1. 从挂载的私钥 JSON（IMPORT_PASSKEY_FILE）复制出凭据文件
#   2. 启动虚拟 CTAP2 认证器（passkey/virtual_authenticator.py）
#   3. 启动 Authenticate 按钮自动点击脚本（passkey/click_authenticate.sh）
#
# 它被 base/image-files/scripts/manager.sh 调用（在启动 IB Gateway 之前），
# 并在后台持续运行，直到容器停止。
#
# 依赖：
#   - /dev/uhid 已暴露给容器（compose.yml 中 `devices: [/dev/uhid]`）
#   - xdotool 已安装（base 镜像已内置）
#
# 环境变量（可在 compose.yml 提供）：
#   PASSKEY_ENABLED      设为 1 才启用（默认关闭，避免影响 TOTP/IB Key 用户）
#   IMPORT_PASSKEY_FILE  宿主机挂载进来的私钥 JSON 路径（必需，见 export_credential.sh）
#   PASSKEY_FILE         凭据文件路径（默认 /home/ibg_settings/ibkr_passkey.json）
#
set -euo pipefail

PASSKEY_ENABLED="${PASSKEY_ENABLED:-0}"
PASSKEY_FILE="${PASSKEY_FILE:-/home/ibg_settings/ibkr_passkey.json}"
PASSKEY_DIR="${PASSKEY_DIR:-/opt/ibga/passkey}"
# ibga base 镜像已预建 /opt/venv（含 ib-insync/pandas），passkey 依赖也装在这里
VENV_PYTHON="/opt/venv/bin/python3"
CRED_EXPORT_SCRIPT="$PASSKEY_DIR/export_credential.sh"
AUTH_SCRIPT="$PASSKEY_DIR/virtual_authenticator.py"
CLICK_SCRIPT="$PASSKEY_DIR/click_authenticate.sh"

if [ "$PASSKEY_ENABLED" != "1" ]; then
    echo "[start-passkey] PASSKEY_ENABLED!=1; skipping software passkey login." >&2
    exit 0
fi

log() { echo "[start-passkey] $*" >&2; }

# 1. 从挂载的 JSON 复制凭据（若目标文件尚不存在）
if [ ! -s "$PASSKEY_FILE" ]; then
    log "Copying passkey credential from IMPORT_PASSKEY_FILE..."
    if ! bash "$CRED_EXPORT_SCRIPT"; then
        log "WARNING: credential copy failed; virtual authenticator will wait for it."
    fi
else
    log "Credential already present: $PASSKEY_FILE"
fi

# 2. 校验 /dev/uhid 并放宽权限（容器以 ibg 用户运行，需读写该设备节点）
if [ ! -e /dev/uhid ]; then
    log "ERROR: /dev/uhid not present. Ensure the container runs with --device /dev/uhid." >&2
    exit 1
fi
sudo chmod 666 /dev/uhid 2>/dev/null || log "WARNING: cannot chmod /dev/uhid; authenticator may fail to open it."

# 3. 启动虚拟认证器（后台）—— 使用 venv 里的 Python（已装 fido2/cbor2/cryptography）
log "Starting virtual CTAP2 authenticator..."
"$VENV_PYTHON" "$AUTH_SCRIPT" --credential-file "$PASSKEY_FILE" --device /dev/uhid &
AUTH_PID=$!
log "Virtual authenticator PID=$AUTH_PID"

# 4. 启动 Authenticate 点击脚本（后台）
log "Starting Authenticate clicker..."
bash "$CLICK_SCRIPT" &
CLICK_PID=$!
log "Clicker PID=$CLICK_PID"

# 5. 若启动期间挂载文件还没就位，后台重试复制
( while :; do
    if [ -s "$PASSKEY_FILE" ]; then
        break
    fi
    sleep 5
    bash "$CRED_EXPORT_SCRIPT" 2>/dev/null || true
 done ) &
RETRY_PID=$!

# 6. 保持前台，转发信号（Ctrl+C / SIGTERM 时优雅关闭子进程）
trap 'kill $AUTH_PID $CLICK_PID $RETRY_PID 2>/dev/null || true' INT TERM
wait "$AUTH_PID"
