#!/bin/bash

T=/sys/kernel/tracing
LED=/sys/class/leds/status_led

write() {
    printf '%s\n' "$2" > "$1"
}

add_probe() {
    local name="$1"
    local func="$2"

    if ! grep -qE "^p:usb_led/${name}([[:space:]]|$)" "$T/kprobe_events"; then
        printf 'p:usb_led/%s %s\n' "$name" "$func" >> "$T/kprobe_events"
    fi
}

remove_probe() {
    local name="$1"

    if grep -qE "^p:usb_led/${name}([[:space:]]|$)" "$T/kprobe_events"; then
        printf -- '-:usb_led/%s\n' "$name" >> "$T/kprobe_events"
    fi
}

cleanup() {
    trap - EXIT INT TERM

    write "$T/events/usb_led/tx/enable" 0 2>/dev/null || true
    write "$T/events/usb_led/rx/enable" 0 2>/dev/null || true

    remove_probe tx
    remove_probe rx

    write "$LED/trigger" none 2>/dev/null || true
    write "$LED/brightness" 0 2>/dev/null || true

    exec 3<&-
    exit 0
}

trap cleanup EXIT INT TERM

# Configurazione LED
write "$LED/trigger" none
write "$LED/brightness" 0
write "$LED/trigger" oneshot
write "$LED/delay_on" 10
write "$LED/delay_off" 50

# Probe TX/RX
add_probe tx gs_write
add_probe rx gs_read_complete

write "$T/events/usb_led/tx/enable" 1
write "$T/events/usb_led/rx/enable" 1
write "$T/tracing_on" 1

echo "USB activity LED started (oneshot 10/50 ms)"

# Ogni evento USB genera un impulso gestito dal kernel
exec 3< "$T/trace_pipe"

while IFS= read -r -u 3 line; do
    case "$line" in
        *tx:*|*rx:*)
            printf '1\n' > "$LED/shot"
            ;;
    esac
done
