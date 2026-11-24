#!/bin/bash
# Runs the X11 or the Wayland version, depending on the current session.

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# XDG_SESSION_TYPE is missing or wrong under sudo, ssh and startx, so the display variables are checked too.
# WAYLAND_DISPLAY comes first, because XWayland also sets DISPLAY inside Wayland sessions.
session_type="${XDG_SESSION_TYPE:-}"
if [ "$session_type" != "wayland" ] && [ "$session_type" != "x11" ]; then
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        session_type="wayland"
    elif [ -n "${DISPLAY:-}" ]; then
        session_type="x11"
    fi
fi

case "$session_type" in
    wayland) exec bash "$SCRIPT_DIR/wayland/virtualmonitor-wayland.sh" "$@" ;;
    x11) exec bash "$SCRIPT_DIR/x11/virtualscreensplit.sh" "$@" ;;
    *) echo "Error: no graphical session was found. Run this from a terminal inside your desktop." >&2; exit 1 ;;
esac
