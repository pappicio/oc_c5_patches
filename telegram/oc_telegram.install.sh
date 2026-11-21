#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

[ "$EUID" -eq 0 ] || {
    echo "ERROR: Run this installer through sudo."
    exit 1
}

CONF="$CONFIG_DIR/telegram.conf"
WATCHER="$SCRIPT_DIR/telegram_watch.sh"
UNIT="oc-telegram-watch.service"

[ -f "$CONF" ] || {
    echo "Telegram configuration not found. Installation skipped."
    exit 0
}

[ -f "$WATCHER" ] || {
    echo "ERROR: Telegram watcher script not found."
    exit 1
}

systemctl cat moonraker-telegram-bot.service >/dev/null 2>&1 || {
    echo "ERROR: moonraker-telegram-bot.service is not installed."
    exit 1
}

cat > "/etc/systemd/system/$UNIT" <<SERVICE
[Unit]
Description=OpenCreator Telegram Bot Host Watcher
After=network.target

[Service]
Type=simple
User=$OWNER
Environment=HOME=$OWNER_HOME
ExecStart=/bin/bash $WATCHER
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

chmod 755 "$WATCHER"

systemctl daemon-reload
systemctl enable --now "$UNIT"

if ! systemctl is-active --quiet "$UNIT"; then
    echo "ERROR: Telegram watcher is not active."
    systemctl --no-pager --full status "$UNIT" || true
    exit 1
fi

echo "Telegram watcher installed and active."
