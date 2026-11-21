#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

[ "$EUID" -eq 0 ] || {
    echo "ERROR: Run this uninstaller through sudo."
    exit 1
}

UNIT="oc-telegram-watch.service"

systemctl disable --now "$UNIT" 2>/dev/null || true
rm -f "/etc/systemd/system/$UNIT"

systemctl daemon-reload
systemctl reset-failed "$UNIT" 2>/dev/null || true

echo "Telegram watcher uninstalled. Configuration and bot service preserved."
