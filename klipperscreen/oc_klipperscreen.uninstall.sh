#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

[ "$EUID" -eq 0 ] || {
    echo "ERROR: Run this uninstaller through sudo."
    exit 1
}

systemctl disable --now oc-ks-watch.service oc-kscreen-view.service 2>/dev/null || true
rm -f /etc/systemd/system/oc-ks-watch.service
rm -f /etc/systemd/system/oc-kscreen-view.service

systemctl daemon-reload
systemctl reset-failed oc-ks-watch.service oc-kscreen-view.service 2>/dev/null || true

echo "KlipperScreen group uninstalled."
echo "Source files, settings.json and KlipperScreen.conf were preserved."
