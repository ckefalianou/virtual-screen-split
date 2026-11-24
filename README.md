# Virtual Monitor

Split one large monitor into virtual monitors, so screen-sharing apps like Google Meet or Zoom can share just one part of an ultrawide screen.

The repository has one version for X11 and one for GNOME on Wayland.
`split.sh` detects your session and runs the right one.

```bash
./split.sh
```

> [!NOTE]
> I built this for my own setup and use it personally, so it is tested only on the hardware and desktop I run.
> It may not work everywhere. Ideas, bug reports and fixes are very welcome, so feel free to open an issue or a pull request.

## X11

On X11, `xrandr --setmonitor` splits the physical monitor into virtual monitors.
Apps and screen-sharing tools see each part as a separate screen.
Window managers that read RandR monitors, such as i3, use them for placement too.

GNOME 50 and newer have no X11 session, so this version is for other X11 desktops such as Xfce, Cinnamon or i3.

Requirements: `xrandr`.

The script works on the primary display, or on the first connected display when no primary is set.
The menu offers four options:

1. Single monitor. It asks for confirmation, then turns off every other display.
2. Two halves.
3. Three parts, with a 1920 px middle part and equal sides. Screens up to 2120 px wide get three equal parts instead.
4. Remove all virtual monitors that the script created.

Change `MIDDLE_WIDTH` in `x11/virtualscreensplit.sh` to set another width for the middle part.

## Wayland (GNOME)

GNOME on Wayland has no equivalent of `xrandr --setmonitor`.
Instead, the script creates a real virtual monitor through Mutter's screen-cast API.
GNOME treats it as an extra display, so screen-sharing apps can share it on its own at full quality.
A viewer window shows the virtual monitor's content, so you can place it anywhere on your physical screen.

KDE, Sway, Hyprland and other Wayland desktops are not supported.

### Features

- Creates a virtual monitor of any size, with presets for half or the middle part of your primary screen.
- Keeps frames on the GPU (DMA-BUF), so it stays smooth while a video call encodes your screen.
- Shows the cursor inside the viewer through a small helper GNOME Shell extension.
- Falls back to a compatible mode automatically when the extension is not active or GPU frames fail.
- Removes the virtual monitor when you close the viewer or press Ctrl+C.

### Requirements

- GNOME on Wayland. The helper extension is tested on GNOME 50. On other versions the viewer runs in compatible mode.
- Python 3 with PyGObject and GTK 4.14 or newer.
- GStreamer 1.24 or newer with the PipeWire plugin and the GTK 4 plugin from gst-plugins-rs 0.12 or newer.

| Distribution | Packages |
|---|---|
| Ubuntu, Debian | `python3-gi gir1.2-gtk-4.0 gstreamer1.0-pipewire gstreamer1.0-gtk4` |
| Fedora | `python3-gobject gtk4 pipewire-gstreamer gstreamer1-plugin-gtk4` |
| Arch | `python-gobject gtk4 gst-plugin-pipewire gst-plugin-gtk4` |

The Ubuntu packages are tested. The Fedora and Arch names are given for convenience and are not tested.

### Usage

Keep the `pointer-position@ckefalianou.github.io` folder next to `wayland/virtualmonitor-wayland.sh`, then run `./split.sh`.

1. Choose a size for the virtual monitor.
2. On the first run the script installs the cursor helper extension. Log out and back in once to activate it. The script also updates the installed copy whenever the extension changes.
3. Place the viewer window where you want it on your screen.
4. Move windows into the virtual monitor with Super+Shift+Right, or drag them past the edge of your screen. GNOME places the virtual monitor to the right of your rightmost display, as Settings › Displays shows.
5. In your call, share the entire screen and pick the virtual monitor.
6. Close the viewer or press Ctrl+C to remove the virtual monitor. GNOME then moves its windows back to your other displays.

| Variable | Default | Effect |
|---|---|---|
| `FRAMERATE` | `30` | Highest frame rate of the virtual monitor, from 1 to 240. Lower it on slower machines. |
| `COMPATIBLE` | unset | Set to `1` to copy frames instead of keeping them on the GPU, for example with drivers that show a black viewer. |

```bash
FRAMERATE=20 ./split.sh
```

### How the cursor works

Mutter leaves the cursor out of GPU frames, and Wayland apps cannot read the pointer position.
The helper extension tells the viewer where the pointer is, and the viewer draws an arrow at that spot.
Screen-sharing apps get the real cursor from GNOME as usual, so this only affects the viewer.

### Privacy

The helper extension answers only while the pointer is on a virtual monitor.
While the pointer is on a real display, it shares nothing.
While it is on a virtual monitor, any program in your desktop session can ask for its position.

### Troubleshooting

The script prints why it runs in compatible mode:

- **Just installed or updated:** log out and back in once.
- **User extensions are turned off:** turn them on in the Extensions app.
- **Not supported on this GNOME version:** the extension declares the GNOME versions it was tested on. The viewer still works in compatible mode.
- **Failed to load:** check the log with `journalctl --user -b | grep pointer-position`.

### Uninstall

```bash
gnome-extensions disable pointer-position@ckefalianou.github.io
rm -rf ~/.local/share/gnome-shell/extensions/pointer-position@ckefalianou.github.io
```

### Limitations

- The virtual monitor is an extra display next to your screen, not a slice of it. You work in it by moving the pointer past the screen edge and watching the viewer.
- Clicks on the viewer window do not reach the apps inside the virtual monitor.
- The cursor in the viewer is always a plain arrow and does not change shape.
