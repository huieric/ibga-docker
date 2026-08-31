#!/usr/bin/env bash
# click_authenticate.sh — 自动点击 IB Gateway 的 passkey "Authenticate" 按钮
#
# 背景：
#   IB Gateway 登录时，若账号开启了 passkey，输入账号密码并点击 Log In 后，
#   会弹出 passkey 验证对话框（"Use your Passkey device" → Authenticate）。
#   这个对话框的 X11 窗口标题通常仍是 "IB Gateway" / "Two Factor
#   Authentication" 之类，并不包含 "passkey"/"authenticate" 字样，因此
#   不能用 `xdotool search --name` 按标题匹配。
#
# 思路：
#   改用与 ibga 其它自动化一致的 JAuto 机制（JVMTI agent）：枚举 Swing UI
#   组件，找到文本含 "Authenticate" 的 JButton，再用 xdotool 点击其坐标
#   （与 _run_ibg.sh 中点击 "Log In" / "OK" 按钮是同一套成熟做法）。
#
#   点击之后虚拟认证器（passkey/virtual_authenticator.py）会立即完成 CTAP2
#   签名应答，本脚本只需保证 "Authenticate" 被点到即可。
#
# 依赖：
#   - JAuto 已随 IB Gateway 启动（由 _run_ibg.sh 注入 -agentpath）
#   - xdotool（base 镜像已内置）
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT="${PASSKEY_CLICK_TIMEOUT:-900}"
INTERVAL="${PASSKEY_CLICK_INTERVAL:-2}"
DISPLAY="${DISPLAY:-:0}"
export DISPLAY

log() { echo "[click-authenticate] $*" >&2; }

# 复用 ibga 的 jauto / 工具函数（位于 /opt/ibga/）
for f in _env.sh _utils.sh _jauto.sh; do
    if [ -f "$SCRIPT_DIR/../$f" ]; then
        # shellcheck disable=SC1090
        source "$SCRIPT_DIR/../$f"
    fi
done

HAS_JAUTO=0
if declare -F _call_jauto >/dev/null 2>&1 && \
   declare -F _jauto_parse_props >/dev/null 2>&1; then
    HAS_JAUTO=1
fi

log "Monitoring for passkey Authenticate button on DISPLAY=$DISPLAY (jauto=$HAS_JAUTO) ..."

start_epoch="$(date +%s)"

# 在一段 jauto 组件输出里找 text 含 "Authenticate" 的 JButton 并点击。
# 返回 0 表示已点击，1 表示没找到。
try_click_from_components() {
    local OUTPUT="$1"
    local COMPONENT BX BY
    while IFS= read -r COMPONENT; do
        [ -z "$COMPONENT" ] && continue
        # 与 _login_click 相同的解析方式：不带引号传入，回填到关联数组
        local -A P="$(_jauto_parse_props $COMPONENT)"
        if [ "${P[F1]:-}" = "javax.swing.JButton" ] && \
           [[ "${P[text]:-}" == *uthenticate* ]]; then
            BX="${P[mx]:-0}"
            BY="${P[my]:-0}"
            if [ "$BX" != "0" ] || [ "$BY" != "0" ]; then
                log "Found Authenticate button at ($BX,$BY); clicking."
                xdotool mousemove "$BX" "$BY" click 1
                return 0
            fi
        fi
    done <<< "$OUTPUT"
    return 1
}

# 用 xdotool 找含 passkey/authenticate 标题的窗口（兜底）
click_via_xdotool() {
    local win_ids first_win
    win_ids="$(xdotool search --name -i 'passkey' 2>/dev/null; \
               xdotool search --name -i 'authenticate' 2>/dev/null)"
    [ -z "$win_ids" ] && return 1
    first_win="$(echo "$win_ids" | head -1 | tr -d '[:space:]')"
    [ -z "$first_win" ] && return 1
    log "Found passkey window (id=$first_win); clicking."
    xdotool windowactivate --sync "$first_win" 2>/dev/null || true
    xdotool windowfocus "$first_win" 2>/dev/null || true
    xdotool key --window "$first_win" Tab 2>/dev/null || true
    xdotool key --window "$first_win" Return 2>/dev/null || true
    return 0
}

while :; do
    now="$(date +%s)"
    if [ "$(( now - start_epoch ))" -ge "$TIMEOUT" ]; then
        log "Timed out after ${TIMEOUT}s without detecting the passkey prompt."
        exit 1
    fi

    CLICKED=0

    if [ "$HAS_JAUTO" = "1" ]; then
        for q in \
            "list_ui_components?window_type=dialog" \
            "list_ui_components?window_class=twslaunch.jauthentication&window_type=dialog" \
            "list_ui_components?window_class=ibgateway"; do
            OUT="$(_call_jauto "$q" 2>/dev/null || true)"
            if [ -n "$OUT" ] && [ "$OUT" != "none" ] && [ "$OUT" != "!timeout!" ]; then
                if try_click_from_components "$OUT"; then
                    CLICKED=1
                    break
                fi
            fi
        done
    fi

    if [ "$CLICKED" != "1" ]; then
        if click_via_xdotool; then
            CLICKED=1
        fi
    fi

    if [ "$CLICKED" = "1" ]; then
        log "Authenticate clicked; continuing to monitor for any re-prompt."
        sleep 3
    fi

    sleep "$INTERVAL"
done
