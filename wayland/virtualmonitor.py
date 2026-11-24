"""Creates a real virtual monitor on GNOME Wayland and shows it in a viewer window.

GNOME treats the virtual monitor as an extra display, so screen-sharing apps can share it on its own.
The virtual monitor only exists while its PipeWire stream is consumed, which the viewer does.
"""

import os
import signal
import sys

import gi

gi.require_version("Gst", "1.0")
gi.require_version("Gtk", "4.0")
from gi.repository import Gio, GLib, Gst, Gtk

SCREEN_CAST = "org.gnome.Mutter.ScreenCast"
DISPLAY_CONFIG = "org.gnome.Mutter.DisplayConfig"
POINTER = "io.github.ckefalianou.PointerPosition"
POINTER_PATH = "/io/github/ckefalianou/PointerPosition"
MIDDLE_WIDTH = 1920
MIN_SIZE = 160
MAX_SIZE = 8192
ARROW = [(0, 0), (0, 17), (4, 13), (7, 20), (10, 19), (7, 12), (12, 12)]


def fail(message):
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def add_signal_handler(signal_number, callback):
    """Uses GLibUnix when present, because GLib.unix_signal_add is deprecated there."""
    try:
        gi.require_version("GLibUnix", "2.0")
        from gi.repository import GLibUnix

        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal_number, callback)
    except (ImportError, ValueError):
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal_number, callback)


def read_display_state(bus):
    try:
        return bus.call_sync(
            DISPLAY_CONFIG, "/org/gnome/Mutter/DisplayConfig", DISPLAY_CONFIG, "GetCurrentState",
            None, None, Gio.DBusCallFlags.NONE, -1, None,
        ).unpack()
    except GLib.Error as error:
        fail(f"could not read the display layout from GNOME ({error.message}). This tool needs GNOME on Wayland.")


def virtual_connectors(state):
    """Returns the connectors of the virtual monitors that exist right now."""
    return {spec[0] for spec, _modes, properties in state[1] if spec[0].startswith("Meta-")}


def primary_screen(state):
    """Returns the primary monitor's width and height in physical pixels, and its scale."""
    _serial, monitors, logical_monitors, _properties = state
    current_modes = {}
    for spec, modes, _monitor_properties in monitors:
        for mode in modes:
            if mode[6].get("is-current"):
                current_modes[spec[0]] = (mode[1], mode[2])

    for _x, _y, scale, transform, is_primary, specs, _logical_properties in logical_monitors:
        if is_primary and specs and specs[0][0] in current_modes:
            width, height = current_modes[specs[0][0]]
            # Odd transforms rotate the monitor by 90 or 270 degrees, which swaps its sides.
            if transform % 2 == 1:
                width, height = height, width
            return width, height, scale

    fail("could not find the primary monitor.")


def read_number(prompt, minimum, maximum):
    value = input(prompt).strip()
    if not value.isdigit() or not minimum <= int(value) <= maximum:
        fail(f"enter a whole number from {minimum} to {maximum}.")
    return int(value)


def choose_size(screen_width, screen_height):
    middle_width = min(MIDDLE_WIDTH, screen_width)
    print("Choose the size of the virtual monitor:")
    print(f"1) Half screen ({screen_width // 2}x{screen_height})")
    print(f"2) Middle part ({middle_width}x{screen_height})")
    print("3) Custom size")
    choice = input("Enter your choice (1/2/3): ").strip()

    if choice == "1":
        return screen_width // 2, screen_height
    if choice == "2":
        return middle_width, screen_height
    if choice == "3":
        return read_number("Width: ", MIN_SIZE, MAX_SIZE), read_number("Height: ", MIN_SIZE, MAX_SIZE)

    fail("invalid choice.")


class VirtualMonitorViewer:
    def __init__(self, bus, width, height, scale, framerate, use_gpu, extension_status):
        self.bus = bus
        self.width = width
        self.height = height
        self.framerate = framerate
        self.use_gpu = use_gpu
        self.extension_status = extension_status
        self.loop = GLib.MainLoop()
        self.session = None
        self.pipeline = None
        self.node_id = None
        self.connector = None
        self.connectors_before = set()
        self.gpu_frames = False
        self.cursor = None
        self.pointer_call_pending = False
        self.retried_in_compatible_mode = False

        self.picture = Gtk.Picture(content_fit=Gtk.ContentFit.CONTAIN)
        self.cursor_layer = Gtk.DrawingArea(can_target=False)
        self.cursor_layer.set_draw_func(self.draw_cursor)
        overlay = Gtk.Overlay(child=self.picture)
        overlay.add_overlay(self.cursor_layer)
        # GTK sizes windows in logical pixels, so the physical size is divided by the screen scale.
        self.window = Gtk.Window(
            title=f"Virtual Monitor {width}x{height}",
            default_width=round(width / scale),
            default_height=round(height / scale),
        )
        self.window.set_child(overlay)
        self.window.connect("close-request", self.stop)

    def mutter_call(self, path, interface, method, parameters=None):
        return self.bus.call_sync(SCREEN_CAST, path, interface, method, parameters, None, Gio.DBusCallFlags.NONE, -1, None)

    def start(self):
        self.connectors_before = virtual_connectors(read_display_state(self.bus))
        try:
            self.session = self.mutter_call(
                "/org/gnome/Mutter/ScreenCast", SCREEN_CAST, "CreateSession", GLib.Variant("(a{sv})", ({},)),
            ).unpack()[0]
            stream = self.mutter_call(
                self.session, SCREEN_CAST + ".Session", "RecordVirtual",
                GLib.Variant("(a{sv})", ({"cursor-mode": GLib.Variant("u", 1), "is-platform": GLib.Variant("b", True)},)),
            ).unpack()[0]
            self.bus.signal_subscribe(
                SCREEN_CAST, SCREEN_CAST + ".Stream", "PipeWireStreamAdded", stream, None,
                Gio.DBusSignalFlags.NONE, self.on_stream_added,
            )
            self.bus.signal_subscribe(
                SCREEN_CAST, SCREEN_CAST + ".Session", "Closed", self.session, None,
                Gio.DBusSignalFlags.NONE, self.stop,
            )
            self.mutter_call(self.session, SCREEN_CAST + ".Session", "Start")
        except GLib.Error as error:
            self.stop()
            fail(f"GNOME refused to create the virtual monitor ({error.message}).")

        if self.use_gpu:
            print("Fast mode: frames stay on the GPU and the viewer draws the cursor.")
        else:
            print(f"Compatible mode: frames are copied so GNOME can draw the cursor. {self.extension_status}")
        print(f"Virtual monitor: {self.width}x{self.height} at up to {self.framerate} fps. Close the viewer or press Ctrl+C to remove it.")

        add_signal_handler(signal.SIGINT, self.stop)
        add_signal_handler(signal.SIGTERM, self.stop)
        self.window.present()
        self.loop.run()
        self.window.destroy()
        print("Virtual monitor removed.")

    def on_stream_added(self, _connection, _sender, _path, _interface, _signal, parameters):
        if self.node_id is not None:
            return
        self.node_id = parameters.unpack()[0]
        self.build_pipeline()
        GLib.timeout_add(250, self.find_own_connector)
        if self.use_gpu:
            GLib.timeout_add(16, self.poll_pointer)

    def build_pipeline(self):
        # Mutter sizes the virtual monitor from the format the consumer asks for.
        size = f"width={self.width},height={self.height},max-framerate={self.framerate}/1"
        caps = f"video/x-raw(memory:DMABuf),{size};video/x-raw,{size}" if self.use_gpu else f"video/x-raw,{size}"
        self.pipeline = Gst.parse_launch(
            f'pipewiresrc path={self.node_id} ! capsfilter caps="{caps}" ! gtk4paintablesink name=sink sync=false'
        )
        sink = self.pipeline.get_by_name("sink")
        self.picture.set_paintable(sink.props.paintable)
        sink.get_static_pad("sink").connect("notify::caps", self.on_caps_changed)
        pipeline_bus = self.pipeline.get_bus()
        pipeline_bus.add_signal_watch()
        pipeline_bus.connect("message::error", self.on_pipeline_error)
        self.pipeline.set_state(Gst.State.PLAYING)

    def on_caps_changed(self, pad, _property):
        caps = pad.get_current_caps()
        # Mutter embeds the cursor only into system-memory frames, so the viewer draws it only for GPU frames.
        self.gpu_frames = bool(caps) and caps.get_features(0).contains("memory:DMABuf")

    def on_pipeline_error(self, _bus, message):
        error = message.parse_error()[0].message
        self.pipeline.set_state(Gst.State.NULL)
        if self.use_gpu and not self.retried_in_compatible_mode:
            # Some drivers cannot share GPU frames with GTK, so the viewer retries with copied frames.
            print(f"GPU frames failed ({error}). Retrying in compatible mode.", file=sys.stderr)
            self.retried_in_compatible_mode = True
            self.use_gpu = False
            self.gpu_frames = False
            self.cursor_layer.queue_draw()
            self.build_pipeline()
            return
        print(f"Error: {error}", file=sys.stderr)
        self.stop()

    def find_own_connector(self):
        """Learns which virtual monitor belongs to this viewer, so another one is never tracked."""
        new_connectors = virtual_connectors(read_display_state(self.bus)) - self.connectors_before
        if len(new_connectors) == 1:
            self.connector = new_connectors.pop()
            return False
        return self.pipeline is not None

    def poll_pointer(self):
        if self.pipeline is None:
            return False
        if self.pointer_call_pending or not self.use_gpu or not self.window.get_mapped():
            return True
        self.pointer_call_pending = True
        self.bus.call(
            POINTER, POINTER_PATH, POINTER, "GetVirtualPointer", None, GLib.VariantType("(siiii)"),
            Gio.DBusCallFlags.NONE, 200, None, self.on_pointer_reply,
        )
        return True

    def on_pointer_reply(self, bus, result):
        self.pointer_call_pending = False
        cursor = None
        try:
            connector, x, y, monitor_width, monitor_height = bus.call_finish(result).unpack()
            if connector and connector == self.connector and monitor_width > 0 and monitor_height > 0:
                # The pointer is in logical pixels, and the stream is in physical pixels.
                cursor = (x * self.width / monitor_width, y * self.height / monitor_height)
        except GLib.Error:
            pass
        if cursor != self.cursor:
            self.cursor = cursor
            self.cursor_layer.queue_draw()

    def draw_cursor(self, _area, context, area_width, area_height):
        if self.cursor is None or not self.gpu_frames:
            return
        scale = min(area_width / self.width, area_height / self.height)
        x = (area_width - self.width * scale) / 2 + self.cursor[0] * scale
        y = (area_height - self.height * scale) / 2 + self.cursor[1] * scale
        context.move_to(x, y)
        for point_x, point_y in ARROW[1:]:
            context.line_to(x + point_x, y + point_y)
        context.close_path()
        context.set_source_rgb(1, 1, 1)
        context.fill_preserve()
        context.set_source_rgb(0, 0, 0)
        context.set_line_width(1.2)
        context.stroke()

    def stop(self, *_):
        if self.pipeline:
            self.pipeline.set_state(Gst.State.NULL)
            self.pipeline = None
        if self.session:
            try:
                self.mutter_call(self.session, SCREEN_CAST + ".Session", "Stop")
            except GLib.Error:
                pass
            self.session = None
        self.loop.quit()
        return False


def pointer_extension_answers(bus):
    try:
        bus.call_sync(
            POINTER, POINTER_PATH, POINTER, "GetVirtualPointer", None, GLib.VariantType("(siiii)"),
            Gio.DBusCallFlags.NONE, 500, None,
        )
        return True
    except GLib.Error:
        return False


def main():
    framerate_text = os.environ.get("FRAMERATE", "30")
    if not framerate_text.isdigit() or not 1 <= int(framerate_text) <= 240:
        fail("FRAMERATE must be a whole number from 1 to 240.")
    framerate = int(framerate_text)
    extension_status = os.environ.get("EXTENSION_STATUS", "")

    Gst.init(None)
    for element in ("pipewiresrc", "gtk4paintablesink"):
        if Gst.ElementFactory.find(element) is None:
            fail(f"the GStreamer element {element} is missing. See the requirements in the README.")

    Gtk.init()
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    screen_width, screen_height, scale = primary_screen(read_display_state(bus))

    try:
        width, height = choose_size(screen_width, screen_height)
    except (EOFError, KeyboardInterrupt):
        print()
        sys.exit(1)

    use_gpu = os.environ.get("COMPATIBLE") != "1" and pointer_extension_answers(bus)
    if os.environ.get("COMPATIBLE") == "1":
        extension_status = "COMPATIBLE=1 is set."
    VirtualMonitorViewer(bus, width, height, scale, framerate, use_gpu, extension_status).start()


if __name__ == "__main__":
    main()
