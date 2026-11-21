#!/bin/bash

if [ "$(id -u)" -eq 0 ]; then
    OWNER="${SUDO_USER:-${C5_OWNER:-}}"
    if [ -z "$OWNER" ] || [ "$OWNER" = root ]; then
        echo "ERROR: Unable to determine the owner account." >&2
        exit 1
    fi
else
    OWNER="$(id -un)"
fi

OWNER_HOME="$(getent passwd "$OWNER" | cut -d: -f6)"
[ -n "$OWNER_HOME" ] && [ -d "$OWNER_HOME" ] || {
    echo "ERROR: Home directory not found for $OWNER." >&2
    exit 1
}

BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_DIR="$OWNER_HOME/printer_data/config"
KLIPPER_DIR="$OWNER_HOME/klipper"
MOONRAKER_DIR="$OWNER_HOME/moonraker"

export OWNER OWNER_HOME BASE CONFIG_DIR KLIPPER_DIR MOONRAKER_DIR
