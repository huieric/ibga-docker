#!/usr/bin/env bash
# export_credential.sh — 准备 IBKR passkey 私钥供虚拟认证器读取
#
# 工作方式：将宿主机挂载进来的私钥 JSON（由 IMPORT_PASSKEY_FILE 指定）复制
# 到虚拟认证器读取的目标路径（PASSKEY_FILE）。这是唯一支持的方式：完全
# 无头、可靠，不依赖任何交互式解锁流程。
#
# 私钥 JSON 需要你自己预先在一台可交互操作 Bitwarden CLI 的机器上，用
# bitwarden-use（bwu，见 https://github.com/leeguooooo/bitwarden-use）
# 的 `bwu fido2 get <name>` 导出一次，整理成 JSON 后挂载进容器（例如通过
# docker secret 或 bind mount），并设置 IMPORT_PASSKEY_FILE 指向挂载路径。
# 详见 README「无人值守 Passkey 登录」一节。
#
# 环境变量：
#   IMPORT_PASSKEY_FILE  宿主机挂载进来的私钥 JSON 路径（必需）
#   PASSKEY_FILE         目标输出路径（默认 /home/ibg_settings/ibkr_passkey.json）
#
set -euo pipefail

PASSKEY_FILE="${PASSKEY_FILE:-/home/ibg_settings/ibkr_passkey.json}"
IMPORT_PASSKEY_FILE="${IMPORT_PASSKEY_FILE:-}"

mkdir -p "$(dirname "$PASSKEY_FILE")"

if [ -s "$PASSKEY_FILE" ]; then
    echo "[export_credential] Passkey JSON already present at $PASSKEY_FILE" >&2
    exit 0
fi

if [ -z "$IMPORT_PASSKEY_FILE" ]; then
    echo "[export_credential] ERROR: IMPORT_PASSKEY_FILE is not set." >&2
    echo "[export_credential]   Mount the exported passkey JSON and set" >&2
    echo "[export_credential]   IMPORT_PASSKEY_FILE to its path. See README." >&2
    exit 1
fi

if [ ! -f "$IMPORT_PASSKEY_FILE" ]; then
    echo "[export_credential] ERROR: IMPORT_PASSKEY_FILE=$IMPORT_PASSKEY_FILE not found." >&2
    exit 1
fi

cp "$IMPORT_PASSKEY_FILE" "$PASSKEY_FILE"
chmod 600 "$PASSKEY_FILE"
echo "[export_credential] Copied imported passkey JSON from $IMPORT_PASSKEY_FILE" >&2
