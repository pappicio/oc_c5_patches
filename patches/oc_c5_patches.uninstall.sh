#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

[ "$EUID" -eq 0 ] || {
    echo "ERROR: Run this uninstaller through sudo."
    exit 1
}

UNIT="oc-c5-patch-links.service"
UPDATER_BASE="$CONFIG_DIR/.opencreator-updater/base/printer.base.cfg"
DROPIN="/etc/systemd/system/klipper.service.d/c5-patches.conf"

systemctl disable --now "$UNIT" 2>/dev/null || true
rm -f "/etc/systemd/system/$UNIT"
systemctl daemon-reload
systemctl reset-failed "$UNIT" 2>/dev/null || true

remove_link() {
    local link="$1" target="$2"
    if [ -L "$link" ] &&
       [ "$(readlink -f "$link" 2>/dev/null || true)" = "$target" ]; then
        rm -f "$link"
        echo "Removed link: $link"
    fi
}

remove_link "$KLIPPER_DIR/klippy/extras/oc_c5_pickup_patch.py" \
    "$BASE/patches/oc_c5_pickup_patch.py"
remove_link "$KLIPPER_DIR/klippy/extras/oc_afc_restore_patch.py" \
    "$BASE/patches/oc_afc_restore_patch.py"
remove_link "$MOONRAKER_DIR/moonraker/components/oc_kalico_runtime_patch.py" \
    "$BASE/patches/oc_kalico_runtime_patch.py"

remove_exclude() {
    local file="$1" entry="$2"
    [ -f "$file" ] || return 0
    grep -vxF "$entry" "$file" > "$file.tmp" || true
    cat "$file.tmp" > "$file"
    rm -f "$file.tmp"
}

remove_exclude "$KLIPPER_DIR/.git/info/exclude" \
    "klippy/extras/oc_c5_pickup_patch.py"
remove_exclude "$KLIPPER_DIR/.git/info/exclude" \
    "klippy/extras/oc_afc_restore_patch.py"
remove_exclude "$MOONRAKER_DIR/.git/info/exclude" \
    "moonraker/components/oc_kalico_runtime_patch.py"

# Remove only the new managed configuration sections.
CONFIG_DIR="$CONFIG_DIR" UPDATER_BASE="$UPDATER_BASE" python3 - <<'PY'
import os
import re
import shutil
import time

files = [
    (
        os.path.join(os.environ["CONFIG_DIR"], "printer.base.cfg"),
        {"oc_c5_pickup_patch", "oc_afc_restore_patch"},
    ),
    (
        os.environ["UPDATER_BASE"],
        {"oc_c5_pickup_patch", "oc_afc_restore_patch"},
    ),
    (
        os.path.join(os.environ["CONFIG_DIR"], "moonraker.conf"),
        {"oc_kalico_runtime_patch"},
    ),
]

for path, targets in files:
    if not os.path.isfile(path):
        print(f"Configuration not found, skipping: {path}")
        continue

    with open(path, encoding="utf-8") as f:
        lines = f.readlines()

    remove = set()
    current = None

    for i, line in enumerate(lines):
        match = re.match(r"^\s*\[([^\]]+)\]\s*(?:[#;].*)?$", line)
        if match:
            current = match.group(1).strip()
            if current in targets:
                remove.add(i)
        elif current in targets:
            remove.add(i)

    if not remove:
        print(f"No managed sections found: {path}")
        continue

    backup = path + ".before-oc-c5-patches-" + time.strftime("%Y%m%d-%H%M%S")
    shutil.copy2(path, backup)

    with open(path, "w", encoding="utf-8") as f:
        f.writelines(line for i, line in enumerate(lines) if i not in remove)

    print(f"Backup: {backup}")
    print(f"Removed managed sections from: {path}")
PY

# Remove only the ExecStartPre entry installed by this project.
if [ -f "$DROPIN" ]; then
    DROPIN="$DROPIN" BASE="$BASE" python3 - <<'PY'
import os
import shutil
import time

path = os.environ["DROPIN"]
base = os.environ["BASE"]
managed_paths = (
    f"{base}/patches/oc_c5_patches.restore_links.sh",
    "oc_c5_patches/patches/oc_c5_patches.restore_links.sh",
)
with open(path, encoding="utf-8") as f:
    lines = f.readlines()

result = [
    line for line in lines
    if not (
        line.lstrip().startswith("ExecStartPre=")
        and any(target in line for target in managed_paths)
    )
]

if result != lines:
    backup = path + ".before-oc-c5-patches-uninstall-" + time.strftime("%Y%m%d-%H%M%S")
    shutil.copy2(path, backup)
    result = [line for line in result if line.strip() != ""]
    if result:
        with open(path, "w", encoding="utf-8") as f:
            f.writelines(result)
    else:
        os.remove(path)
    print(f"Updated drop-in: {path}")
PY
fi

systemctl daemon-reload
echo "OpenCreator custom patches have been uninstalled."
echo "Legacy services and external OpenCreator components were not modified."
