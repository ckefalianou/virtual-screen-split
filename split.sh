#!/bin/bash
# Runs the X11 or the Wayland version, depending on the current session.

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

case "${XDG_SESSION_TYPE:-}" in
    wayland) exec "$SCRIPT_DIR/wayland/virtualmonitor-wayland.sh" "$@" ;;
    x11) exec "$SCRIPT_DIR/x11/virtualscreensplit.sh" "$@" ;;
    *) echo "Unknown session type: ${XDG_SESSION_TYPE:-none}. Run the script in x11/ or wayland/ directly."; exit 1 ;;
esac
