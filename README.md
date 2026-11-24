# Virtual Monitor

Split one large monitor into virtual monitors, so screen-sharing apps like Google Meet or Zoom can share just one part of an ultrawide screen.

The repository has one version for X11 and one for GNOME on Wayland.
`split.sh` detects your session and runs the right one.

```bash
./split.sh
```

## X11

On X11, `xrandr --setmonitor` splits the physical monitor into virtual monitors.
Apps and screen-sharing tools see each part as a separate screen.

Requirements: `xrandr`.

The menu offers four options:

1. Single monitor, which also turns off any second display.
2. Two halves.
3. Three parts, with a 1920 px middle part and equal sides.
4. Remove all virtual monitors.

Change `MIDDLE_WIDTH` in `x11/virtualscreensplit.sh` to set another width for the middle part.

## Wayland (GNOME)

GNOME on Wayland has no equivalent of `xrandr --setmonitor`.
Instead, the script creates a real virtual monitor through Mutter's screen-cast API.
GNOME treats it as an extra display, so screen-sharing apps can share it on its own at full quality.
A viewer window shows the virtual monitor's content, so you can place it anywhere on your physical screen.

### Features

- Creates a virtual monitor of any size, with presets for half or the middle third of your screen.
- Keeps frames on the GPU (DMA-BUF), so it stays smooth while a video call encodes your screen.
- Shows the cursor inside the viewer through a small helper GNOME Shell extension.
- Falls back to a compatible mode automatically when the extension is not active.
- Removes the virtual monitor when you close the viewer or press Ctrl+C, and moves its windows back.

### Requirements

- GNOME 50 on Wayland. `gdctl` needs GNOME 48 or newer, and the extension declares GNOME 50.
- Python 3 with PyGObject and GTK 4.
- GStreamer 1.24 or newer with the PipeWire and GTK 4 plugins.

On Ubuntu:

```bash
sudo apt install python3-gi gir1.2-gtk-4.0 gstreamer1.0-pipewire gstreamer1.0-gtk4 mutter-common-bin
```

### Usage

Keep the `pointer-position@virtualmonitor.local` folder next to `wayland/virtualmonitor-wayland.sh`, then run `./split.sh`.

1. Choose a size for the virtual monitor.
2. On the first run the script installs the cursor helper extension. Log out and back in once to activate it.
3. Place the viewer window where you want it on your screen.
4. Move windows into the virtual monitor with Super+Shift+Right, or drag them past the right edge of your screen.
5. In your call, share the entire screen and pick the virtual monitor.
6. Close the viewer or press Ctrl+C to remove the virtual monitor.

To lower the load on slower machines, reduce the frame rate:

```bash
FRAMERATE=20 ./split.sh
```

### How the cursor works

Mutter leaves the cursor out of GPU frames, and Wayland apps cannot read the pointer position.
The helper extension exposes only the pointer coordinates on the session D-Bus, and the viewer draws an arrow at that spot.
Screen-sharing apps get the real cursor from GNOME as usual, so this only affects the viewer.

### Limitations

- The virtual monitor is an extra display next to your screen, not a slice of it. You work in it by moving the pointer past the screen edge and watching the viewer.
- Clicks on the viewer window do not reach the apps inside the virtual monitor.
- The cursor in the viewer is always a plain arrow and does not change shape.
