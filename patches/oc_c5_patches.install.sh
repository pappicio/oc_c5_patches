#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

[ "$EUID" -eq 0 ] || {
    echo "ERROR: Run this installer through sudo."
    exit 1
}

PATCH_DIR="$BASE/patches"
UPDATER_BASE="$CONFIG_DIR/.opencreator-updater/base/printer.base.cfg"
DROPIN_DIR="/etc/systemd/system/klipper.service.d"
DROPIN="$DROPIN_DIR/c5-patches.conf"
UNIT="oc-c5-patch-links.service"

for f in oc_c5_pickup_patch.py oc_afc_restore_patch.py oc_kalico_runtime_patch.py; do
    [ -f "$PATCH_DIR/$f" ] || {
        echo "ERROR: Missing patch file: $PATCH_DIR/$f"
        exit 1
    }
done

[ -d "$KLIPPER_DIR/.git" ] || {
    echo "ERROR: Klipper repository not found: $KLIPPER_DIR"
    exit 1
}
[ -d "$MOONRAKER_DIR/.git" ] || {
    echo "ERROR: Moonraker repository not found: $MOONRAKER_DIR"
    exit 1
}

for f in "$CONFIG_DIR/printer.base.cfg" "$UPDATER_BASE" "$CONFIG_DIR/moonraker.conf"; do
    [ -f "$f" ] || {
        echo "ERROR: Required configuration file not found: $f"
        exit 1
    }
done

# Rename only the managed section headers.
CONFIG_DIR="$CONFIG_DIR" UPDATER_BASE="$UPDATER_BASE" python3 - <<'PY'
import os
import re
import shutil
import time

files = [
    (
        os.path.join(os.environ["CONFIG_DIR"], "printer.base.cfg"),
        {
            "c5_pickup_patch": "oc_c5_pickup_patch",
            "afc_restore_patch": "oc_afc_restore_patch",
        },
    ),
    (
        os.environ["UPDATER_BASE"],
        {
            "c5_pickup_patch": "oc_c5_pickup_patch",
            "afc_restore_patch": "oc_afc_restore_patch",
        },
    ),
    (
        os.path.join(os.environ["CONFIG_DIR"], "moonraker.conf"),
        {"kalico_runtime_patch": "oc_kalico_runtime_patch"},
    ),
]

def section_names(lines):
    result = []
    for line in lines:
        match = re.match(r"^\s*\[([^\]]+)\]\s*(?:[#;].*)?$", line)
        if match:
            result.append(match.group(1).strip())
    return result

for path, mapping in files:
    with open(path, encoding="utf-8") as f:
        lines = f.readlines()

    names = section_names(lines)
    changed = False

    for old, new in mapping.items():
        if old in names and new in names:
            raise SystemExit(
                f"ERROR: Both [{old}] and [{new}] exist in {path}. "
                "Resolve this conflict before continuing."
            )

        if old in names:
            for i, line in enumerate(lines):
                if re.match(
                    rf"^\s*\[{re.escape(old)}\]\s*(?:[#;].*)?$", line
                ):
                    lines[i] = re.sub(
                        rf"^\s*\[{re.escape(old)}\]",
                        f"[{new}]",
                        line,
                        count=1,
                    )
                    changed = True
                    print(f"Renamed [{old}] to [{new}] in {path}")
                    break
        elif new not in names:
            if lines and not lines[-1].endswith("\n"):
                lines[-1] += "\n"
            if lines and lines[-1].strip():
                lines.append("\n")
            lines.extend([f"[{new}]\n", "\n"])
            changed = True
            print(f"Added [{new}] to {path}")

    if changed:
        backup = path + ".before-oc-c5-patches-" + time.strftime("%Y%m%d-%H%M%S")
        shutil.copy2(path, backup)
        with open(path, "w", encoding="utf-8") as f:
            f.writelines(lines)
        print(f"Backup: {backup}")
PY

# Install a dedicated service without modifying the legacy service.
cat > "/etc/systemd/system/$UNIT" <<SERVICE
[Unit]
Description=Restore OpenCreator Creator 5 custom patch links
After=local-fs.target
Before=klipper.service moonraker.service

[Service]
Type=oneshot
User=$OWNER
ExecStart=/bin/bash $PATCH_DIR/oc_c5_patches.restore_links.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE

# Update only the managed ExecStartPre entry.
mkdir -p "$DROPIN_DIR"
DROPIN="$DROPIN" BASE="$BASE" python3 - <<'PY'
import os
import shutil
import time

path = os.environ["DROPIN"]
base = os.environ["BASE"]
new_line = f'/bin/bash "{base}/patches/oc_c5_patches.restore_links.sh"'

lines = []
if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        lines = f.readlines()

updated = False
result = []

for line in lines:
    if line.lstrip().startswith("ExecStartPre=") and (
        "c5_patches/restore_patch_links.sh" in line
        or "oc_c5_patches/patches/oc_c5_patches.restore_links.sh" in line
    ):
        result.append("ExecStartPre=" + new_line + "\n")
        updated = True
    else:
        result.append(line)

if not updated:
    if not any(line.strip() == "[Service]" for line in result):
        result.extend(["\n", "[Service]\n"])
    result.append("ExecStartPre=" + new_line + "\n")

if os.path.exists(path):
    backup = path + ".before-oc-c5-patches-" + time.strftime("%Y%m%d-%H%M%S")
    shutil.copy2(path, backup)
    print(f"Drop-in backup: {backup}")

with open(path, "w", encoding="utf-8") as f:
    f.writelines(result)

print(f"Updated Klipper drop-in: {path}")
PY

chmod 755 "$PATCH_DIR/oc_c5_patches.restore_links.sh"

runuser -u "$OWNER" -- /bin/bash "$PATCH_DIR/oc_c5_patches.restore_links.sh"

systemctl daemon-reload
systemctl enable --now "$UNIT"

# Retire the legacy patch-link service only after the replacement is active.
if ! systemctl is-active --quiet "$UNIT"; then
    echo "ERROR: Replacement patch-link service is not active. Legacy setup was left untouched."
    exit 1
fi

LEGACY_UNIT="c5-patch-links-clean.service"
LEGACY_FILE="/etc/systemd/system/$LEGACY_UNIT"

if [ -f "$LEGACY_FILE" ]; then
    if ! grep -Fq 'c5_patches/groups/patches/restore_links.sh' "$LEGACY_FILE"; then
        echo "ERROR: Unexpected legacy service definition: $LEGACY_FILE"
        echo "The legacy service was not removed."
        exit 1
    fi
    cp -a "$LEGACY_FILE" "$LEGACY_FILE.before-oc-c5-patches-$(date +%Y%m%d-%H%M%S)"
fi

systemctl disable --now "$LEGACY_UNIT" 2>/dev/null || true

if [ -f "$LEGACY_FILE" ]; then
    rm -f "$LEGACY_FILE"
    echo "Removed legacy service unit: $LEGACY_UNIT"
fi

remove_legacy_link() {
    local link="$1" expected_target="$2" current
    if [ -L "$link" ]; then
        current="$(readlink "$link")"
        if [ "$current" = "$expected_target" ]; then
            rm -f "$link"
            echo "Removed legacy patch link: $link"
        else
            echo "WARNING: Preserving unexpected symlink: $link -> $current"
        fi
    elif [ -e "$link" ]; then
        echo "WARNING: Preserving non-symlink path: $link"
    fi
}

remove_legacy_link "$KLIPPER_DIR/klippy/extras/c5_pickup_patch.py" \
    "$OWNER_HOME/printer_data/config/c5_patches/c5_pickup_patch.py"
remove_legacy_link "$KLIPPER_DIR/klippy/extras/afc_restore_patch.py" \
    "$OWNER_HOME/printer_data/config/c5_patches/afc_restore_patch.py"
remove_legacy_link "$MOONRAKER_DIR/moonraker/components/kalico_runtime_patch.py" \
    "$OWNER_HOME/printer_data/config/c5_patches/kalico_runtime_patch.py"

remove_legacy_exclude() {
    local file="$1" entry="$2" backup
    [ -f "$file" ] || return 0
    if grep -qxF "$entry" "$file"; then
        backup="$file.before-oc-c5-patches-$(date +%Y%m%d-%H%M%S)"
        cp -a "$file" "$backup"
        grep -vxF "$entry" "$file" > "$file.tmp"
        cat "$file.tmp" > "$file"
        rm -f "$file.tmp"
        echo "Removed legacy Git exclude: $entry"
    fi
}

remove_legacy_exclude "$KLIPPER_DIR/.git/info/exclude" \
    "klippy/extras/c5_pickup_patch.py"
remove_legacy_exclude "$KLIPPER_DIR/.git/info/exclude" \
    "klippy/extras/afc_restore_patch.py"
remove_legacy_exclude "$MOONRAKER_DIR/.git/info/exclude" \
    "moonraker/components/kalico_runtime_patch.py"

systemctl daemon-reload

echo "OpenCreator custom patches installed."
echo "Restarting Klipper and Moonraker..."

for service in klipper.service moonraker.service; do
    if systemctl restart "$service" && systemctl is-active --quiet "$service"; then
        echo "OK: $service is active."
    else
        echo "ERROR: $service failed to restart."
        systemctl --no-pager --full status "$service" || true
        exit 1
    fi
done

echo "PATCH installation completed successfully."
