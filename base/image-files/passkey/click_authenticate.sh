#!/usr/bin/env bash
# click_authenticate.sh — 自动点击 IB Gateway 的 "Use your Passkey device" → Authenticate
#
# 背景：
#   IB Gateway 登录时，若账号开启了 passkey，会弹出一个原生对话框：
#     "Use your Passkey device"  +  [Authenticate >] 按钮
#   IBC（IBCAlpha）目前不识别这个窗口（它只处理 Second Factor Authentication
#   与 Security Code Card），所以必须由外部脚本代为点击 Authenticate。
#
# 思路：
#   用 xdotool 在 noVNC 的 X 显示上循环扫描窗口标题。当出现包含
#   "Passkey" / "Authenticate" 字样的窗口时，把焦点给它，然后通过键盘
#   导航（Tab 移动到按钮 + Enter / 或直接匹配按钮文字）触发点击。
#
#   由于点击之后虚拟认证器（passkey/virtual_authenticator.py）会立即完成
#   CTAP2 签名应答，本脚本只需保证 "Authenticate" 被点到即可，无需人工干预。
#
# 依赖：
#   xdotool（Dockerfile.template 中已安装）
#
# 用法：
#   click_authenticate.sh [--timeout <秒>] [--interval <秒>]
#
# 默认超时 600 秒（IB Gateway 登录窗口期内足够），默认扫描间隔 2 秒。
#
set -uo pipefail

TIMEOUT="${PASSKEY_CLICK_TIMEOUT:-900}"
INTERVAL="${PASSKEY_CLICK_INTERVAL:-2}"
DISPLAY="${DISPLAY:-:0}"

start_epoch="$(date +%s)"

log() { echo "[click-authenticate] $*" >&2; }

log "Monitoring for IB Gateway passkey prompt on DISPLAY=$DISPLAY ..."

while :; do
    now="$(date +%s)"
    if [ "$(( now - start_epoch ))" -ge "$TIMEOUT" ]; then
        log "Timed out after ${TIMEOUT}s without detecting a passkey prompt."
        exit 1
    fi

    # 查找标题包含 passkey 关键词的窗口（IB Gateway 用 "Passkey" / "Authenticate"）
    # xdotool 的 search 支持正则式 `--name`。
    win_ids="$(xdotool search --name -i 'passkey' 2>/dev/null; \
               xdotool search --name -i 'authenticate' 2>/dev/null)"

    if [ -n "$win_ids" ]; then
        first_win="$(echo "$win_ids" | head -1 | tr -d '[:space:]')"
        if [ -n "$first_win" ]; then
            log "Found passkey window (id=$first_win); clicking Authenticate."
            # 激活并聚焦该窗口，确保后续键盘事件送到正确的窗口
            xdotool windowactivate --sync "$first_win" 2>/dev/null || true
            xdotool windowfocus "$first_win" 2>/dev/null || true

            # 用 Tab+Enter 触发 Authenticate。窗口里有若干控件，
            # 连续 Tab 键聚焦按钮，再按 Enter 触发。
            # 为稳妥起见做三次 Tab -> Enter 尝试（按钮位置不定的兜底）。
            xdotool key --window "$first_win" Tab 2>/dev/null || true
            xdotool key --window "$first_win" Return 2>/dev/null || true
            sleep 1
            xdotool key --window "$first_win" Tab 2>/dev/null || true
            xdotool key --window "$first_win" Return 2>/dev/null || true
            sleep 1
            xdotool key --window "$first_win" Tab 2>/dev/null || true
            xdotool key --window "$first_win" Return 2>/dev/null || true

            log "Authenticate clicked (attempted). Continuing to monitor for completion..."
        fi
    fi

    sleep "$INTERVAL"
done
