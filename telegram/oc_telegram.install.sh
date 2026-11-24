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
PATCH="$SCRIPT_DIR/telegram_runtime_patch.py"
UNIT="oc-telegram-watch.service"
BOT_UNIT="moonraker-telegram-bot.service"
DROPIN_DIR="/etc/systemd/system/$BOT_UNIT.d"
DROPIN="$DROPIN_DIR/oc-telegram-runtime.conf"
PYTHON="$OWNER_HOME/moonraker-telegram-bot-env/bin/python"
MAIN="$OWNER_HOME/moonraker-telegram-bot/bot/main.py"
LOG="$OWNER_HOME/printer_data/logs/telegram.log"

[ -f "$CONF" ] || {
    echo "Telegram configuration not found. Installation skipped."
    exit 0
}

[ -f "$WATCHER" ] || {
    echo "ERROR: Telegram watcher script not found."
    exit 1
}

[ -f "$PATCH" ] || {
    echo "ERROR: Telegram runtime patch not found."
    exit 1
}

[ -x "$PYTHON" ] || {
    echo "ERROR: Telegram Python environment not found: $PYTHON"
    exit 1
}

[ -f "$MAIN" ] || {
    echo "ERROR: Telegram bot source not found: $MAIN"
    exit 1
}

systemctl cat "$BOT_UNIT" >/dev/null 2>&1 || {
    echo "ERROR: $BOT_UNIT is not installed."
    exit 1
}

# Validate the launcher and the expected source line before installation.
"$PYTHON" - "$PATCH" "$MAIN" <<'PY'
import pathlib
import sys

patch = pathlib.Path(sys.argv[1])
main = pathlib.Path(sys.argv[2])

compile(patch.read_text(encoding="utf-8"), str(patch), "exec")

source = main.read_text(encoding="utf-8")
expected = 'mess += "Printer online on " + get_local_ip()'

if source.count(expected) != 1:
    raise SystemExit("ERROR: Expected greeting line was not found exactly once.")

print("Telegram runtime patch preflight: OK")
PY

mkdir -p "$DROPIN_DIR"

cat > "$DROPIN" <<SERVICE
# OpenCreator Telegram runtime greeting patch
[Service]
ExecStart=
ExecStart=$PYTHON $PATCH -c $CONF -l $LOG
SERVICE

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

chmod 755 "$WATCHER" "$PATCH"

systemctl daemon-reload
systemctl enable --now "$UNIT"

if ! systemctl is-active --quiet "$UNIT"; then
    echo "ERROR: Telegram watcher is not active."
    systemctl --no-pager --full status "$UNIT" || true
    exit 1
fi

systemctl restart "$BOT_UNIT"

echo "Telegram runtime greeting patch installed."
echo "Telegram watcher installed and active."
