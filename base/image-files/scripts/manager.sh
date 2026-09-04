#!/bin/bash

export DISPLAY=:0

# Clear previous lockfile
rm -f /tmp/.X0-lock

# Start VNC server
setsid Xvnc -SecurityTypes None -AlwaysShared=1 -geometry 1920x1080 :0 &

# Start noVNC server
setsid /opt/noVNC/utils/novnc_proxy --vnc localhost:5900 &

# Start openbox
setsid openbox &

if [ ! -z "$IB_TIMEZONE" ]; then
    sudo ln -fs /usr/share/zoneinfo/${IB_TIMEZONE// /_} /etc/localtime
    sudo dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1
fi

source $(dirname "$BASH_SOURCE")/_env.sh
source $(dirname "$BASH_SOURCE")/_utils.sh
source $(dirname "$BASH_SOURCE")/_run_socat.sh
source $(dirname "$BASH_SOURCE")/_run_ibg.sh

sudo mkdir -p {$IBG_DIR,$IBG_SETTINGS_DIR,$IBGA_LOG_EXPORT_DIR}
sudo chown ibg:ibg "$IBG_DIR"
sudo chown ibg:ibg "$IBG_SETTINGS_DIR"
sudo chown ibg:ibg "$IBGA_LOG_EXPORT_DIR"

MSG="------------------------------------------------
 Manager Startup / $(date)
------------------------------------------------
"
_info "$MSG"

# Passkey Authenticate/PIN handling is performed by _maintenance_cycle in
# _run_ibg.sh. Device-node maintenance remains a separate background concern:
# every host usbip re-attach may allocate a new hidraw minor, while the
# container has its own /dev tmpfs. Keep the matching node synchronized so
# Chromium can enumerate the authenticator.
if [ "${AUTH_METHOD:-passkey}" = "passkey" ]; then
    (
        while :; do
            FOUND_NODE=""
            for d in /sys/class/hidraw/hidraw*; do
                [ -e "$d" ] || continue
                if [ -r "$d/device/uevent" ] && \
                   grep -qi 'HID_NAME=soft-fido2' "$d/device/uevent" 2>/dev/null; then
                    FOUND_NODE="$d"
                    break
                fi
            done

            if [ -n "$FOUND_NODE" ]; then
                HRN="$(basename "$FOUND_NODE")"
                MAJMIN="$(cat "$FOUND_NODE/dev" 2>/dev/null)"
                MAJ="${MAJMIN%%:*}"
                MIN="${MAJMIN##*:}"
                EXPECTED="$(printf '%x:%x' "$MAJ" "$MIN")"
                ACTUAL="$(stat -c '%t:%T' "/dev/$HRN" 2>/dev/null || true)"
                if [ "$ACTUAL" != "$EXPECTED" ]; then
                    sudo rm -f "/dev/$HRN"
                    if sudo mknod -m 666 "/dev/$HRN" c "$MAJ" "$MIN"; then
                        _info "• passkey device node /dev/$HRN synchronized ($MAJ:$MIN)\n"
                    fi
                fi
            fi
            sleep 2
        done
    ) &
fi

_run_socat
_run_ibg
