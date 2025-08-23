#!/bin/bash

export DISPLAY=:0

# Clear previous lockfile
rm -f /tmp/.X0-lock

# Start VNC server
setsid Xvnc -SecurityTypes None -AlwaysShared=1 -geometry 1920x1080 :0 &

# Start noVNC server
setsid ./noVNC/utils/novnc_proxy --vnc localhost:5900 &

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

_run_socat
_run_ibg
