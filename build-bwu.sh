#!/usr/bin/env bash
# build-bwu.sh — build a locally-compatible bitwarden-use (bwu) binary from source
#
# Why: the prebuilt binary from the upstream GitHub release is linked against a
# newer glibc (GLIBC_2.39) and fails on Ubuntu 22.04 (glibc 2.35) with:
#   version `GLIBC_2.39' not found (required by .../bitwarden-use)
# Building from source on the target machine produces a binary linked against
# that machine's own glibc, which always runs.
#
# Usage:
#   ./build-bwu.sh                       # build and install to $HOME/.local/bin
#   BWU_INSTALL_DIR=/usr/local/bin ./build-bwu.sh
#
# Env vars:
#   BWU_REPO         upstream repo URL (default: https://github.com/leeguooooo/bitwarden-use.git)
#   BWU_REF          branch/tag to build   (default: main)
#   BWU_INSTALL_DIR  where to install the binaries (default: $HOME/.local/bin)
#   BWU_KEEP_SRC     if set to 1, keep the cloned source tree (default: delete)
#
set -euo pipefail

BWU_REPO="${BWU_REPO:-https://github.com/leeguooooo/bitwarden-use.git}"
BWU_REF="${BWU_REF:-main}"
BWU_INSTALL_DIR="${BWU_INSTALL_DIR:-$HOME/.local/bin}"
BWU_KEEP_SRC="${BWU_KEEP_SRC:-0}"

log() { printf '\033[36m[bwu-build]\033[0m %s\n' "$*"; }
err() { printf '\033[31m[bwu-build]\033[0m %s\n' "$*" >&2; }

# --- ensure cargo / rustc -------------------------------------------------
if ! command -v cargo >/dev/null 2>&1; then
    log "cargo not found; installing Rust via rustup ..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    # shellcheck disable=SC1091
    source "$HOME/.cargo/env"
fi

if ! command -v cargo >/dev/null 2>&1; then
    err "cargo still not available after install; aborting."
    exit 1
fi

# edition = "2024" requires rustc >= 1.85
RUSTC_MIN="1.85"
RUSTC_VER="$(rustc --version | awk '{print $2}')"
if [ "$(printf '%s\n%s\n' "$RUSTC_MIN" "$RUSTC_VER" | sort -V | head -1)" != "$RUSTC_MIN" ]; then
    err "rustc $RUSTC_VER is too old; need >= $RUSTC_MIN. Run: rustup update stable"
    exit 1
fi

# --- clone source ---------------------------------------------------------
WORK_DIR="$(mktemp -d)"
trap 'if [ "$BWU_KEEP_SRC" != "1" ]; then rm -rf "$WORK_DIR"; fi' EXIT

log "Cloning $BWU_REPO (ref=$BWU_REF) ..."
git clone --depth 1 --branch "$BWU_REF" "$BWU_REPO" "$WORK_DIR"

cd "$WORK_DIR"

# The upstream Cargo.toml declares `edition = "2026"`, which only the very
# newest toolchains understand. Normalize it to 2024 (Rust >= 1.85). Its
# `rust-version = "1.82.0"` is also too low for edition 2024, so bump it too.
log "Normalizing Cargo.toml (edition 2026 -> 2024, rust-version -> 1.85) ..."
sed -i 's/^edition = "2026"/edition = "2024"/; s/^rust-version = "1.82.0"/rust-version = "1.85.0"/' Cargo.toml
grep -nE '^(edition|rust-version)' Cargo.toml

# --- build -----------------------------------------------------------------
log "Building release binaries (this may take a few minutes) ..."
cargo build --release --bin bitwarden-use --bin bitwarden-use-agent

# --- install ---------------------------------------------------------------
mkdir -p "$BWU_INSTALL_DIR"
install -m 0755 target/release/bitwarden-use "$BWU_INSTALL_DIR/bitwarden-use"
install -m 0755 target/release/bitwarden-use-agent "$BWU_INSTALL_DIR/bitwarden-use-agent"
ln -sf "$BWU_INSTALL_DIR/bitwarden-use" "$BWU_INSTALL_DIR/bwu"

log "Installed to $BWU_INSTALL_DIR:"
ls -l "$BWU_INSTALL_DIR/bitwarden-use" "$BWU_INSTALL_DIR/bitwarden-use-agent" "$BWU_INSTALL_DIR/bwu"

# --- sanity checks ---------------------------------------------------------
log "Self-test:"
"$BWU_INSTALL_DIR/bitwarden-use" --version

# Show the highest GLIBC symbol the binary needs, so the user can confirm it
# does not exceed their libc version (e.g. Ubuntu 22.04 has glibc 2.35).
if command -v objdump >/dev/null 2>&1; then
    MAX_GLIBC="$(objdump -T "$BWU_INSTALL_DIR/bitwarden-use" \
        | grep -oE 'GLIBC_[0-9.]+' | sort -V | uniq | tail -1)"
    log "Highest required GLIBC version: ${MAX_GLIBC:-<none>}"
else
    log "objdump not found; skipping GLIBC requirement check."
fi

log "Done."
