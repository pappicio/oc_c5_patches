#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

[ "$EUID" -eq 0 ] || {
    echo "ERROR: Run this installer through sudo."
    exit 1
}

LED_SCRIPT="$SCRIPT_DIR/usb-activity-led.sh"
[ -f "$LED_SCRIPT" ] || {
    echo "ERROR: LED support script not found: $LED_SCRIPT"
    exit 1
}

cat > /etc/systemd/system/oc-usb-activity-led.service <<SERVICE
[Unit]
Description=OpenCreator USB Activity LED
After=local-fs.target

[Service]
Type=simple
ExecStart=/bin/bash $LED_SCRIPT
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
SERVICE

chmod 755 "$LED_SCRIPT"
systemctl daemon-reload

# Stop the legacy LED service before starting its replacement.
systemctl disable --now usb-activity-led.service 2>/dev/null || true

if ! systemctl enable --now oc-usb-activity-led.service; then
    systemctl enable --now usb-activity-led.service 2>/dev/null || true
    echo "ERROR: New LED service failed. Legacy service restart attempted."
    exit 1
fi

if ! systemctl is-active --quiet oc-usb-activity-led.service; then
    systemctl enable --now usb-activity-led.service 2>/dev/null || true
    echo "ERROR: New LED service is not active. Legacy service restart attempted."
    exit 1
fi

echo "LED group installed successfully."
