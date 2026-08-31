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

# --- apply the new-device-verification patch ------------------------------
# Upstream does not implement Bitwarden's "New device verification required"
# flow, so logging in from a new IP/device fails with HTTP 400. This patch
# adds support for entering the emailed verification code and resubmitting
# the login with the newDeviceOtp field.
log "Applying new-device-verification patch ..."
if command -v patch >/dev/null 2>&1; then
    patch -p1 --forward <<'PATCH_EOF'
diff --git a/src/actions.rs b/src/actions.rs
--- a/src/actions.rs
+++ b/src/actions.rs
@@ -18,6 +18,7 @@ pub async fn login(
     password: crate::locked::Password,
     two_factor_token: Option<&str>,
     two_factor_provider: Option<crate::api::TwoFactorProviderType>,
+    new_device_otp: Option<&str>,
 ) -> Result<(
     String,
     String,
@@ -47,6 +48,7 @@ pub async fn login(
             &identity.master_password_hash,
             two_factor_token,
             two_factor_provider,
+            new_device_otp,
         )
         .await?;
 
diff --git a/src/api.rs b/src/api.rs
--- a/src/api.rs
+++ b/src/api.rs
@@ -302,6 +302,11 @@ struct ConnectTokenReq {
     two_factor_token: Option<String>,
     #[serde(rename = "twoFactorProvider")]
     two_factor_provider: Option<u32>,
+    #[serde(
+        rename = "newDeviceOtp",
+        skip_serializing_if = "Option::is_none"
+    )]
+    new_device_otp: Option<String>,
     #[serde(flatten)]
     auth: ConnectTokenAuth,
 }
@@ -1008,6 +1013,7 @@ impl Client {
             device_push_token: String::new(),
             two_factor_token: None,
             two_factor_provider: None,
+            new_device_otp: None,
         };
         let client = self.reqwest_client().await?;
         let res = client
@@ -1044,6 +1050,7 @@ impl Client {
         password_hash: &crate::locked::PasswordHash,
         two_factor_token: Option<&str>,
         two_factor_provider: Option<TwoFactorProviderType>,
+        new_device_otp: Option<&str>,
     ) -> Result<(String, String, String)> {
         let connect_req = match sso_id {
             Some(sso_id) => {
@@ -1067,6 +1074,8 @@ impl Client {
                         .map(std::string::ToString::to_string),
                     two_factor_provider: two_factor_provider
                         .map(|ty| ty as u32),
+                    new_device_otp: new_device_otp
+                        .map(std::string::ToString::to_string),
                 }
             }
             None => ConnectTokenReq {
@@ -1085,6 +1094,8 @@ impl Client {
                 two_factor_token: two_factor_token
                     .map(std::string::ToString::to_string),
                 two_factor_provider: two_factor_provider.map(|ty| ty as u32),
+                new_device_otp: new_device_otp
+                    .map(std::string::ToString::to_string),
             },
         };
 
@@ -1804,6 +1815,11 @@ fn classify_login_error(error_res: &ConnectErrorRes, code: u16) -> Error {
             }
             _ => {}
         },
+        "device_error" => {
+            if error_desc == Some("New device verification required") {
+                return Error::NewDeviceVerificationRequired;
+            }
+        }
         "invalid_client" => {
             return Error::IncorrectApiKey;
         }
diff --git a/src/bin/rbw-agent/actions.rs b/src/bin/rbw-agent/actions.rs
--- a/src/bin/rbw-agent/actions.rs
+++ b/src/bin/rbw-agent/actions.rs
@@ -113,7 +113,7 @@ pub async fn login(
             )
             .await
             .context("failed to read password from pinentry")?;
-            match rbw::actions::login(&email, password.clone(), None, None)
+            match rbw::actions::login(&email, password.clone(), None, None, None)
                 .await
             {
                 Ok((
@@ -202,6 +202,54 @@ pub async fn login(
                         "unsupported two factor methods: {providers:?}"
                     ));
                 }
+                Err(rbw::error::Error::NewDeviceVerificationRequired) => {
+                    let otp = rbw::pinentry::getpin(
+                        &config_pinentry().await?,
+                        "New Device Verification",
+                        "Enter the verification code sent to your email.",
+                        None,
+                        environment,
+                        false,
+                    )
+                    .await
+                    .context(
+                        "failed to read new device verification code \
+                         from pinentry",
+                    )?;
+                    let otp = std::str::from_utf8(otp.password())
+                        .context("code was not valid utf8")?;
+                    let (
+                        access_token,
+                        refresh_token,
+                        kdf,
+                        iterations,
+                        memory,
+                        parallelism,
+                        protected_key,
+                    ) = rbw::actions::login(
+                        &email,
+                        password.clone(),
+                        None,
+                        None,
+                        Some(otp),
+                    )
+                    .await?;
+                    login_success(
+                        state.clone(),
+                        access_token,
+                        refresh_token,
+                        kdf,
+                        iterations,
+                        memory,
+                        parallelism,
+                        protected_key,
+                        password,
+                        db,
+                        email,
+                    )
+                    .await?;
+                    break 'attempts;
+                }
                 Err(rbw::error::Error::IncorrectPassword { message }) => {
                     if i == 3 {
                         return Err(rbw::error::Error::IncorrectPassword {
@@ -264,6 +312,7 @@ async fn two_factor(
             password.clone(),
             Some(code),
             Some(provider),
+            None,
         )
         .await
         {
diff --git a/src/error.rs b/src/error.rs
--- a/src/error.rs
+++ b/src/error.rs
@@ -235,6 +235,9 @@ pub enum Error {
         sso_email_2fa_session_token: Option<String>,
     },
 
+    #[error("new device verification required")]
+    NewDeviceVerificationRequired,
+
     #[error("unimplemented cipherstring type: {ty}")]
     UnimplementedCipherStringType { ty: String },
PATCH_EOF
else
    err "patch command not found; cannot apply new-device-verification patch."
    exit 1
fi

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
