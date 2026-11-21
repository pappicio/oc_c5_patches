#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

[ "$EUID" -eq 0 ] || {
    echo "ERROR: Run this uninstaller through sudo."
    exit 1
}

systemctl disable --now oc-usb-activity-led.service 2>/dev/null || true
rm -f /etc/systemd/system/oc-usb-activity-led.service

systemctl daemon-reload
systemctl reset-failed oc-usb-activity-led.service 2>/dev/null || true

echo "LED group uninstalled."
echo "The LED support script was preserved."
