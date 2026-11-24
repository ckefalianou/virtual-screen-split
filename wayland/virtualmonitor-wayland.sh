#!/bin/bash
# Creates a real virtual monitor on GNOME Wayland, the closest thing to "xrandr --setmonitor".
# GNOME treats it as an extra screen, so Google Meet can share it on its own at full quality.
# Its picture is shown in a viewer window that you place on the part of the LG you want.

set -euo pipefail

MIDDLE_WIDTH=1920
# Lower it to 20 or 15 if Meet still lags.
FRAMERATE="${FRAMERATE:-30}"
EXTENSION_UUID="pointer-position@virtualmonitor.local"
EXTENSION_SOURCE="$(dirname "$(readlink -f "$0")")/$EXTENSION_UUID"
EXTENSION_TARGET="$HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID"

# The helper extension lets the fast GPU path draw the cursor, because Mutter leaves it out of GPU frames.
install_pointer_extension() {
    if [ -d "$EXTENSION_TARGET" ] || [ ! -d "$EXTENSION_SOURCE" ]; then
        return
    fi
    mkdir -p "$(dirname "$EXTENSION_TARGET")"
    cp -r "$EXTENSION_SOURCE" "$EXTENSION_TARGET"
    gnome-extensions enable "$EXTENSION_UUID" 2>/dev/null || python3 -I - "$EXTENSION_UUID" <<'PY'
import ast
import subprocess
import sys

enabled = ast.literal_eval(subprocess.run(["gsettings", "get", "org.gnome.shell", "enabled-extensions"], capture_output=True, text=True).stdout.replace("@as ", ""))
if sys.argv[1] not in enabled:
    subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", repr(enabled + [sys.argv[1]])], check=True)
PY
    echo "Installed the cursor helper extension. Log out and back in once to activate it."
}

install_pointer_extension

read -r SCREEN_WIDTH SCREEN_HEIGHT < <(gdctl show | awk '
    /Current mode/ { want_mode = 1; next }
    want_mode { match($0, /[0-9]+x[0-9]+/); split(substr($0, RSTART, RLENGTH), size, "x"); print size[1], size[2]; exit }
')
HALF_WIDTH=$((SCREEN_WIDTH / 2))

# Display menu
echo "Choose the size of the virtual monitor:"
echo "1) Half screen (${HALF_WIDTH}x${SCREEN_HEIGHT})"
echo "2) Middle third (${MIDDLE_WIDTH}x${SCREEN_HEIGHT})"
echo "3) Custom size"
read -r -p "Enter your choice (1/2/3): " choice

case $choice in
    1) WIDTH=$HALF_WIDTH; HEIGHT=$SCREEN_HEIGHT ;;
    2) WIDTH=$MIDDLE_WIDTH; HEIGHT=$SCREEN_HEIGHT ;;
    3) read -r -p "Width: " WIDTH; read -r -p "Height: " HEIGHT ;;
    *) echo "Invalid choice, exiting."; exit 1 ;;
esac

if ! [[ "$WIDTH" =~ ^[0-9]+$ && "$HEIGHT" =~ ^[0-9]+$ ]]; then
    echo "Error: width and height must be numbers."
    exit 1
fi

echo "Virtual monitor: ${WIDTH}x${HEIGHT} at up to ${FRAMERATE} fps. Close the viewer window or press Ctrl+C to remove it."

python3 -I - "$WIDTH" "$HEIGHT" "$FRAMERATE" <<'PY'
import re
import signal
import subprocess
import sys

import gi

gi.require_version("Gst", "1.0")
gi.require_version("Gtk", "4.0")
from gi.repository import Gio, GLib, Gst, Gtk

width = int(sys.argv[1])
height = int(sys.argv[2])
framerate = int(sys.argv[3])
auto_stop_seconds = int(sys.argv[4]) if len(sys.argv) > 4 else 0

MUTTER = "org.gnome.Mutter.ScreenCast"
POINTER = "local.VirtualMonitor.PointerPosition"
POINTER_PATH = "/local/VirtualMonitor/PointerPosition"
ARROW = [(0, 0), (0, 17), (4, 13), (7, 20), (10, 19), (7, 12), (12, 12)]

Gst.init(None)


def add_signal_handler(signal_number, callback):
    """Uses GLibUnix when present, because GLib.unix_signal_add is deprecated there."""
    try:
        gi.require_version("GLibUnix", "2.0")
        from gi.repository import GLibUnix

        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal_number, callback)
    except (ImportError, ValueError):
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal_number, callback)


Gtk.init()
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
loop = GLib.MainLoop()
state = {"pipeline": None, "session": None, "origin": None, "cursor": None}


def mutter_call(path, interface, method, parameters=None):
    return bus.call_sync(MUTTER, path, interface, method, parameters, None, Gio.DBusCallFlags.NONE, -1, None)


def read_pointer():
    try:
        return bus.call_sync(POINTER, POINTER_PATH, POINTER, "Get", None, None, Gio.DBusCallFlags.NONE, 200, None).unpack()
    except GLib.Error:
        return None


fast_mode = read_pointer() is not None
if fast_mode:
    print("Fast mode: frames stay on the GPU and the viewer draws the cursor.")
else:
    print("Compatible mode: the cursor helper extension is not active, so frames are copied to show the cursor.")

picture = Gtk.Picture(content_fit=Gtk.ContentFit.CONTAIN)
cursor_layer = Gtk.DrawingArea(can_target=False)
overlay = Gtk.Overlay(child=picture)
overlay.add_overlay(cursor_layer)
window = Gtk.Window(title=f"Virtual Monitor {width}x{height}", default_width=width, default_height=height)
window.set_child(overlay)


def draw_cursor(area, context, area_width, area_height):
    if state["cursor"] is None:
        return
    scale = min(area_width / width, area_height / height)
    x = (area_width - width * scale) / 2 + state["cursor"][0] * scale
    y = (area_height - height * scale) / 2 + state["cursor"][1] * scale
    context.move_to(x, y)
    for point_x, point_y in ARROW[1:]:
        context.line_to(x + point_x, y + point_y)
    context.close_path()
    context.set_source_rgb(1, 1, 1)
    context.fill_preserve()
    context.set_source_rgb(0, 0, 0)
    context.set_line_width(1.2)
    context.stroke()


cursor_layer.set_draw_func(draw_cursor)


def refresh_origin():
    """Finds where GNOME placed the virtual monitor, since the user can move it in Settings."""
    output = subprocess.run(["gdctl", "show"], capture_output=True, text=True).stdout
    for block in output.split("Logical monitor #")[1:]:
        position = re.search(r"Position: \((-?\d+), (-?\d+)\)", block)
        if position and "Meta-" in block:
            state["origin"] = (int(position.group(1)), int(position.group(2)))
    return True


def update_cursor():
    pointer = read_pointer()
    cursor = None
    if pointer and state["origin"]:
        x = pointer[0] - state["origin"][0]
        y = pointer[1] - state["origin"][1]
        if 0 <= x < width and 0 <= y < height:
            cursor = (x, y)
    if cursor != state["cursor"]:
        state["cursor"] = cursor
        cursor_layer.queue_draw()
    return True


def stop(*_):
    if state["pipeline"]:
        state["pipeline"].set_state(Gst.State.NULL)
        state["pipeline"] = None
    if state["session"]:
        try:
            mutter_call(state["session"], MUTTER + ".Session", "Stop")
        except GLib.Error:
            pass
        state["session"] = None
    loop.quit()
    return False


def on_stream_added(connection, sender, path, interface, signal_name, parameters):
    node_id = parameters.unpack()[0]
    # Mutter sizes the virtual monitor from the format the consumer asks for.
    # Mutter draws the cursor only into system-memory frames, so the GPU path needs the helper extension.
    size = f"width={width},height={height},max-framerate={framerate}/1"
    caps = f"video/x-raw(memory:DMABuf),{size};video/x-raw,{size}" if fast_mode else f"video/x-raw,{size}"
    pipeline = Gst.parse_launch(
        f'pipewiresrc path={node_id} ! capsfilter caps="{caps}" '
        "! gtk4paintablesink name=sink sync=false"
    )
    picture.set_paintable(pipeline.get_by_name("sink").props.paintable)
    pipeline_bus = pipeline.get_bus()
    pipeline_bus.add_signal_watch()
    pipeline_bus.connect("message::error", lambda _bus, message: (print(f"Error: {message.parse_error()[0].message}", file=sys.stderr), stop()))
    pipeline.set_state(Gst.State.PLAYING)
    state["pipeline"] = pipeline
    if fast_mode:
        GLib.timeout_add(500, lambda: refresh_origin() and False)
        GLib.timeout_add_seconds(2, refresh_origin)
        GLib.timeout_add(16, update_cursor)


session = mutter_call("/org/gnome/Mutter/ScreenCast", MUTTER, "CreateSession", GLib.Variant("(a{sv})", ({},))).unpack()[0]
state["session"] = session
stream = mutter_call(
    session, MUTTER + ".Session", "RecordVirtual",
    GLib.Variant("(a{sv})", ({"cursor-mode": GLib.Variant("u", 1), "is-platform": GLib.Variant("b", True)},)),
).unpack()[0]
bus.signal_subscribe(None, MUTTER + ".Stream", "PipeWireStreamAdded", stream, None, Gio.DBusSignalFlags.NONE, on_stream_added)
bus.signal_subscribe(None, MUTTER + ".Session", "Closed", session, None, Gio.DBusSignalFlags.NONE, stop)
mutter_call(session, MUTTER + ".Session", "Start")

window.connect("close-request", stop)
add_signal_handler(signal.SIGINT, stop)
add_signal_handler(signal.SIGTERM, stop)
if auto_stop_seconds:
    GLib.timeout_add_seconds(auto_stop_seconds, stop)

window.present()
loop.run()
window.destroy()
print("Virtual monitor removed.")
PY
