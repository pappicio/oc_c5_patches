#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

PATCH_DIR="$BASE/patches"

for f in oc_c5_pickup_patch.py oc_afc_restore_patch.py oc_kalico_runtime_patch.py; do
    [ -f "$PATCH_DIR/$f" ] || {
        echo "ERROR: Missing patch file: $PATCH_DIR/$f"
        exit 1
    }
done

for repo in "$KLIPPER_DIR" "$MOONRAKER_DIR"; do
    [ -d "$repo/.git" ] || {
        echo "ERROR: Repository not found: $repo"
        exit 1
    }
    mkdir -p "$repo/.git/info"
    touch "$repo/.git/info/exclude"
done

link_patch() {
    local src="$1" dst="$2" repo="$3" exclude="$4"

    if [ -e "$dst" ] || [ -L "$dst" ]; then
        if [ -L "$dst" ]; then
            local current
            current="$(readlink "$dst" 2>/dev/null || true)"
            if [ "$current" != "$src" ]; then
                if [ ! -e "$current" ] &&
                   [ "$(basename "$current")" = "$(basename "$src")" ]; then
                    rm -f "$dst"
                else
                    echo "ERROR: Unexpected existing link: $dst -> $current"
                    return 1
                fi
            fi
        else
            echo "ERROR: Destination already exists and is not a symlink: $dst"
            return 1
        fi
    fi

    if [ ! -L "$dst" ]; then
        ln -s "$src" "$dst"
    fi

    grep -qxF "$exclude" "$repo/.git/info/exclude" ||
        echo "$exclude" >> "$repo/.git/info/exclude"

    echo "OK: $dst"
}

link_patch "$PATCH_DIR/oc_c5_pickup_patch.py" \
    "$KLIPPER_DIR/klippy/extras/oc_c5_pickup_patch.py" \
    "$KLIPPER_DIR" "klippy/extras/oc_c5_pickup_patch.py"

link_patch "$PATCH_DIR/oc_afc_restore_patch.py" \
    "$KLIPPER_DIR/klippy/extras/oc_afc_restore_patch.py" \
    "$KLIPPER_DIR" "klippy/extras/oc_afc_restore_patch.py"

link_patch "$PATCH_DIR/oc_kalico_runtime_patch.py" \
    "$MOONRAKER_DIR/moonraker/components/oc_kalico_runtime_patch.py" \
    "$MOONRAKER_DIR" "moonraker/components/oc_kalico_runtime_patch.py"

echo "All three custom patch links have been restored."
