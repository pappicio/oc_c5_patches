#!/bin/sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SETTINGS="$SCRIPT_DIR/../settings.json"
CONF="$HOME/printer_data/config/telegram.conf"
LOG="/tmp/oc_telegram_watch.log"

log() {
    echo "$(date) $*" >> "$LOG"
}

LAST=$(awk '
/^\[bot\]/ { section=1; next }
/^\[/ { section=0 }
section && /^[[:space:]]*server[[:space:]]*:/ {
    sub(/^[[:space:]]*server[[:space:]]*:[[:space:]]*/, "")
    print
    exit
}' "$CONF" 2>/dev/null)

PREV=""
COUNT=0
INITIAL_LOGGED=0

irq() {
    awk '/dwc3/ {sum += $2} END {print sum+0}' /proc/interrupts
}

while true; do
    A=$(irq)
    sleep 1
    B=$(irq)

    SOC_IP=$(python3 -c '
import json, ipaddress, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
ip = data["soc_ip"]
ipaddress.IPv4Address(ip)
print(ip)
' "$SETTINGS" 2>/dev/null) || {
        log "ERROR: settings.json is missing or SOC IP is invalid."
        sleep 5
        continue
    }

    if [ $((B - A)) -gt 4 ]; then
        HOST="localhost"
        NAME="Creator 5 Tunneled"
    else
        HOST="$SOC_IP"
        NAME="Creator 5 SOC"
    fi

    if [ "$HOST" = "$PREV" ]; then
        COUNT=$((COUNT + 1))
    else
        COUNT=1
        PREV="$HOST"
    fi

    if [ "$COUNT" -ge 5 ]; then
        if [ "$HOST" = "$LAST" ]; then
            if [ "$INITIAL_LOGGED" -eq 0 ]; then
                log "Mode detected: $HOST ($NAME). Configuration already matches."
                INITIAL_LOGGED=1
            fi
        else
            if python3 - "$CONF" "$HOST" <<'PY'
import os
import re
import stat
import sys
import tempfile

path, host = sys.argv[1:3]

with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()

section = None
found = False

for i, line in enumerate(lines):
    match = re.match(r"^\s*\[([^\]]+)\]\s*(?:[#;].*)?$", line)
    if match:
        section = match.group(1).strip().lower()
        continue

    if section == "bot":
        match = re.match(r"^(\s*server\s*:\s*)(.*?)(\r?\n)?$", line)
        if match:
            found = True
            newline = match.group(3) or ""
            if match.group(2).strip() != host:
                lines[i] = match.group(1) + host + newline
            break

if not found:
    sys.exit(2)

mode = stat.S_IMODE(os.stat(path).st_mode)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))

try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.writelines(lines)
    os.chmod(tmp, mode)
    os.replace(tmp, path)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
PY
            then
                if [ "$HOST" = "$SOC_IP" ]; then
                    log "Waiting for Creator 5 boot: 30 seconds."
                    sleep 30
                fi

                if sudo -n /usr/bin/systemctl restart --no-block moonraker-telegram-bot.service; then
                    LAST="$HOST"
                    INITIAL_LOGGED=1
                    log "Mode detected: $HOST ($NAME). Telegram bot restart requested."
                else
                    log "ERROR: Telegram bot restart request failed for $HOST."
                    sleep 5
                fi
            else
                log "ERROR: Unable to update [bot] server."
                sleep 5
            fi
        fi
    fi
done
