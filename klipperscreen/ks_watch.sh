#!/bin/sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SETTINGS="$SCRIPT_DIR/../settings.json"
CONF="$HOME/printer_data/config/KlipperScreen.conf"

LAST=$(awk '/^moonraker_host:/ {print $2; exit}' "$CONF" 2>/dev/null)
PREV=""
COUNT=0

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
        echo "$(date) ERROR: settings.json is missing or SOC IP is invalid." >> /tmp/ks_watch.log
        sleep 5
        continue
    }

    if [ $((B - A)) -gt 4 ]; then
        HOST=127.0.0.1
    else
        HOST=$SOC_IP
    fi

    if [ "$HOST" = "$PREV" ]; then
        COUNT=$((COUNT + 1))
    else
        COUNT=1
        PREV=$HOST
    fi

    if [ "$COUNT" -ge 5 ] && [ "$HOST" != "$LAST" ]; then
        if [ "$HOST" = "127.0.0.1" ]; then
            NAME="Creator 5 Tunneled"
        else
            NAME="Creator 5 SOC"
        fi

        if sed -i -e "s/^moonraker_host:.*/moonraker_host: $HOST/" \
                  -e "s/^\[printer .*\]/[printer $NAME]/" "$CONF"; then

            if [ "$HOST" = "$SOC_IP" ]; then
                echo "$(date) Waiting for Creator 5 boot: 30 seconds." >> /tmp/ks_watch.log
                sleep 30
            fi

            if sudo -n /usr/bin/systemctl restart --no-block KlipperScreen.service; then
                LAST=$HOST
                echo "$(date) Mode detected: $HOST ($NAME). Restart requested." >> /tmp/ks_watch.log
            else
                echo "$(date) ERROR: Restart request failed for $HOST." >> /tmp/ks_watch.log
            fi
        fi
    fi
done
