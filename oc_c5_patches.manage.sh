#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f "$0")")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if [ "$EUID" -ne 0 ]; then
    exec sudo env C5_OWNER="$OWNER" /bin/bash "$0" "$@"
fi

PATCH="$BASE/patches/oc_c5_patches"
KS="$BASE/klipperscreen/oc_klipperscreen"
LED="$BASE/led/oc_led"

run_group() {
    local action="$1" group="$2"
    /bin/bash "$group.$action.sh"
}

while true; do
    echo
    echo "======================================"
    echo "       CREATOR 5 - PATCH MANAGER"
    echo "======================================"
    echo "Owner: $OWNER"
    echo "1) Install all groups"
    echo "2) Install PATCH"
    echo "3) Install KLIPPERSCREEN"
    echo "4) Install LED"
    echo "5) Uninstall all groups"
    echo "6) Uninstall PATCH"
    echo "7) Uninstall KLIPPERSCREEN"
    echo "8) Uninstall LED"
    echo "0) Exit"
    echo
    read -rp "Selection: " choice

    case "$choice" in
        1)
            run_group install "$PATCH"
            run_group install "$KS"
            run_group install "$LED"
            ;;
        2) run_group install "$PATCH" ;;
        3) run_group install "$KS" ;;
        4) run_group install "$LED" ;;
        5)
            read -rp "Uninstall all groups? Type REMOVE: " confirm
            [ "$confirm" = REMOVE ] || {
                echo "Cancelled."
                continue
            }
            run_group uninstall "$LED"
            run_group uninstall "$KS"
            run_group uninstall "$PATCH"
            ;;
        6)
            read -rp "Uninstall PATCH? Type REMOVE: " confirm
            [ "$confirm" = REMOVE ] && run_group uninstall "$PATCH" ||
                echo "Cancelled."
            ;;
        7)
            read -rp "Uninstall KLIPPERSCREEN? Type REMOVE: " confirm
            [ "$confirm" = REMOVE ] && run_group uninstall "$KS" ||
                echo "Cancelled."
            ;;
        8)
            read -rp "Uninstall LED? Type REMOVE: " confirm
            [ "$confirm" = REMOVE ] && run_group uninstall "$LED" ||
                echo "Cancelled."
            ;;
        0) exit 0 ;;
        *) echo "Invalid selection." ;;
    esac
done
