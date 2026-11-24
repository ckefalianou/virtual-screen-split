#!/bin/bash
# Creates a real virtual monitor on GNOME Wayland, the closest thing to "xrandr --setmonitor".
# This wrapper checks the environment and keeps the cursor helper extension installed and up to date.
# The viewer itself is virtualmonitor.py.

set -uo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
EXTENSION_UUID="pointer-position@ckefalianou.github.io"
EXTENSION_SOURCE="$SCRIPT_DIR/$EXTENSION_UUID"
EXTENSION_TARGET="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$EXTENSION_UUID"

fail() {
    echo "Error: $1" >&2
    exit 1
}

if [ "${XDG_SESSION_TYPE:-}" != "wayland" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    fail "this is not a Wayland session. On X11, use x11/virtualscreensplit.sh."
fi
if [[ "${XDG_CURRENT_DESKTOP:-}" != *GNOME* ]]; then
    fail "this tool needs GNOME. KDE, Sway and other Wayland desktops are not supported."
fi

command -v python3 >/dev/null || fail "python3 is not installed."

# Adds the extension to the enabled list and removes it from the disabled list, which takes precedence.
enable_extension() {
    gnome-extensions enable "$EXTENSION_UUID" 2>/dev/null && return
    python3 -I - "$EXTENSION_UUID" <<'PY'
import ast
import subprocess
import sys

uuid = sys.argv[1]


def read_list(key):
    output = subprocess.run(["gsettings", "get", "org.gnome.shell", key], capture_output=True, text=True).stdout
    return ast.literal_eval(output.replace("@as ", "").strip() or "[]")


enabled = read_list("enabled-extensions")
disabled = read_list("disabled-extensions")
if uuid not in enabled:
    subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", repr(enabled + [uuid])], check=True)
if uuid in disabled:
    subprocess.run(["gsettings", "set", "org.gnome.shell", "disabled-extensions", repr([item for item in disabled if item != uuid])], check=True)
PY
}

# Installs the extension, or replaces an installed copy that differs from the one next to this script.
# Returns a short reason when the extension cannot be active in this session.
prepare_extension() {
    if [ ! -d "$EXTENSION_SOURCE" ]; then
        echo "The cursor helper extension folder is missing next to the script."
        return
    fi

    if ! diff -rq "$EXTENSION_SOURCE" "$EXTENSION_TARGET" >/dev/null 2>&1; then
        rm -rf "$EXTENSION_TARGET"
        mkdir -p "$(dirname "$EXTENSION_TARGET")"
        cp -r "$EXTENSION_SOURCE" "$EXTENSION_TARGET"
        enable_extension
        echo "The cursor helper extension was just installed or updated. Log out and back in once to activate it."
        return
    fi

    enable_extension

    if [ "$(gsettings get org.gnome.shell disable-user-extensions 2>/dev/null)" = "true" ]; then
        echo "User extensions are turned off. Turn them on in the Extensions app."
        return
    fi

    local state
    state=$(gnome-extensions info "$EXTENSION_UUID" 2>/dev/null | sed -n 's/^ *State: //p')
    case "$state" in
        ACTIVE) ;;
        "") echo "GNOME has not loaded the cursor helper extension yet. Log out and back in once." ;;
        "OUT OF DATE") echo "The cursor helper extension does not support this GNOME version yet." ;;
        ERROR) echo "The cursor helper extension failed to load. Check: journalctl --user -b | grep $EXTENSION_UUID" ;;
        *) echo "The cursor helper extension is $state. Enable it in the Extensions app." ;;
    esac
}

EXTENSION_STATUS="$(prepare_extension)"
if [[ "$EXTENSION_STATUS" == *"just installed or updated"* ]]; then
    echo "$EXTENSION_STATUS"
fi

EXTENSION_STATUS="$EXTENSION_STATUS" exec python3 -I "$SCRIPT_DIR/virtualmonitor.py"
