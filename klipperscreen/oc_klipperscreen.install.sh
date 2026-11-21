#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

[ "$EUID" -eq 0 ] || {
    echo "ERROR: Run this installer through sudo."
    exit 1
}

SETTINGS="$BASE/settings.json"
DEFAULT_IP="192.168.1.194"

if [ -f "$SETTINGS" ]; then
    SAVED_IP=$(python3 -c '
import json, sys, ipaddress
try:
    with open(sys.argv[1]) as f:
        ip = json.load(f)["soc_ip"]
    ipaddress.IPv4Address(ip)
    print(ip)
except Exception:
    print("")
' "$SETTINGS" 2>/dev/null || true)
else
    SAVED_IP=""
fi

DEFAULT_IP="${SAVED_IP:-$DEFAULT_IP}"

while true; do
    read -rp "Creator 5 SOC IP address [$DEFAULT_IP]: " SOC_IP
    SOC_IP="${SOC_IP:-$DEFAULT_IP}"

    if python3 -c 'import ipaddress,sys; ipaddress.IPv4Address(sys.argv[1])' "$SOC_IP" 2>/dev/null; then
        break
    fi

    echo "Invalid IPv4 address. Please try again."
done

SOC_IP="$SOC_IP" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, tempfile

path = os.environ["SETTINGS"]
data = {"soc_ip": os.environ["SOC_IP"]}

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
try:
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
PY

chown "$OWNER:$OWNER" "$SETTINGS"
chmod 600 "$SETTINGS"
echo "SOC IP address saved: $SOC_IP"

for f in ks_watch.sh kscreen_view.py; do
    [ -f "$SCRIPT_DIR/$f" ] || {
        echo "ERROR: Missing KlipperScreen support file: $SCRIPT_DIR/$f"
        exit 1
    }
done

cat > /etc/systemd/system/oc-ks-watch.service <<SERVICE
[Unit]
Description=OpenCreator KlipperScreen Host Watcher
After=network.target

[Service]
Type=simple
User=$OWNER
ExecStart=/bin/bash $SCRIPT_DIR/ks_watch.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE

cat > /etc/systemd/system/oc-kscreen-view.service <<SERVICE
[Unit]
Description=OpenCreator KlipperScreen Remote Touch Viewer
After=systemd-user-sessions.service
StartLimitIntervalSec=0

[Service]
Type=simple
User=$OWNER
Group=$OWNER
SupplementaryGroups=input
WorkingDirectory=$OWNER_HOME
Environment=HOME=$OWNER_HOME
Environment=WAYLAND_DISPLAY=wayland-0
Environment=PYTHONUNBUFFERED=1
ExecStartPre=/bin/sh -c 'uid=\$(id -u); until [ -S /run/user/\$uid/wayland-0 ] && [ -c /dev/uinput ]; do sleep 2; done'
ExecStart=/usr/bin/python3 $SCRIPT_DIR/kscreen_view.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

chmod 755 "$SCRIPT_DIR/ks_watch.sh" "$SCRIPT_DIR/kscreen_view.py"

systemctl daemon-reload

LEGACY_SERVICES=(ks-watch.service kscreen-view.service)
NEW_SERVICES=(oc-ks-watch.service oc-kscreen-view.service)
BACKUP_SUFFIX=".before-oc-klipperscreen-$(date +%Y%m%d-%H%M%S)"

# Preserve the legacy unit files before switching services.
for service in "${LEGACY_SERVICES[@]}"; do
    unit="/etc/systemd/system/$service"
    if [ -f "$unit" ]; then
        cp -a "$unit" "$unit$BACKUP_SUFFIX"
        echo "Legacy unit backup: $unit$BACKUP_SUFFIX"
    fi
done

# The old viewer owns TCP port 8085, so it must stop before its replacement starts.
systemctl disable --now "${LEGACY_SERVICES[@]}" 2>/dev/null || true

if ! systemctl enable --now "${NEW_SERVICES[@]}"; then
    echo "ERROR: New KlipperScreen services failed. Restoring legacy services."
    systemctl disable --now "${NEW_SERVICES[@]}" 2>/dev/null || true
    systemctl enable --now "${LEGACY_SERVICES[@]}" || true
    exit 1
fi

FAILED=0
for service in "${NEW_SERVICES[@]}"; do
    if ! systemctl is-active --quiet "$service"; then
        echo "ERROR: $service is not active."
        systemctl --no-pager --full status "$service" || true
        FAILED=1
    else
        echo "OK: $service is active."
    fi
done

if [ "$FAILED" -ne 0 ]; then
    echo "ERROR: Restoring legacy KlipperScreen services."
    systemctl disable --now "${NEW_SERVICES[@]}" 2>/dev/null || true
    systemctl enable --now "${LEGACY_SERVICES[@]}" || true
    exit 1
fi

# Remove legacy unit definitions only after both replacements are confirmed active.
for service in "${LEGACY_SERVICES[@]}"; do
    rm -f "/etc/systemd/system/$service"
done

systemctl daemon-reload
systemctl reset-failed "${LEGACY_SERVICES[@]}" 2>/dev/null || true

echo "KlipperScreen group installed successfully."
