#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

[ "$EUID" -eq 0 ] || {
    echo "ERROR: Run this uninstaller through sudo."
    exit 1
}

UNIT="oc-telegram-watch.service"
BOT_UNIT="moonraker-telegram-bot.service"
DROPIN="/etc/systemd/system/$BOT_UNIT.d/oc-telegram-runtime.conf"

systemctl disable --now "$UNIT" 2>/dev/null || true
rm -f "/etc/systemd/system/$UNIT"
rm -f "$DROPIN"

systemctl daemon-reload
systemctl reset-failed "$UNIT" 2>/dev/null || true

if systemctl cat "$BOT_UNIT" >/dev/null 2>&1; then
    systemctl restart "$BOT_UNIT"
fi

echo "Telegram runtime patch and watcher uninstalled."
echo "Original Telegram bot startup command restored."
echo "Configuration and bot service preserved."
