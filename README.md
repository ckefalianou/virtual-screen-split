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

The script works on the primary display, or on the widest connected display when no primary is set.
The menu offers four options:

1. Single monitor. If other displays are active, it lists them and asks for confirmation before it turns them off. The display it keeps stays at its current resolution, or gets its preferred one if it was off.
2. Two halves.
3. Three parts, with a 1920 px middle part and equal sides. Screens narrower than the middle part plus 1280 px, 3200 px by default, get three equal parts instead.
4. Remove all virtual monitors that the script created.

Change `MIDDLE_WIDTH` in `x11/virtualscreensplit.sh` to set another width for the middle part.

## Wayland (GNOME)

GNOME on Wayland has no equivalent of `xrandr --setmonitor`.
Instead, the script creates a real virtual monitor through Mutter's screen-cast API.
GNOME treats it as an extra display, so screen-sharing apps can share it on its own at full quality.
A viewer window shows the virtual monitor's content, so you can place it anywhere on your physical screen.

KDE, Sway, Hyprland and other Wayland desktops are not supported.

### Features

- Creates a virtual monitor from 160 to 8192 px per side. The presets use the full height of your primary screen and either half its width or 1920 px.
- Keeps frames on the GPU (DMA-BUF), so it stays smooth while a video call encodes your screen.
- Shows the cursor inside the viewer through a small helper GNOME Shell extension.
- Falls back to a compatible mode automatically when the extension is not active or the GPU path reports an error.
- Removes the virtual monitor when you close the viewer or press Ctrl+C.

### Requirements

- GNOME on Wayland. The helper extension is tested on GNOME 50. On other versions the viewer runs in compatible mode.
- Python 3 with PyGObject and GTK 4.14 or newer.
- GStreamer 1.24 or newer with the PipeWire plugin and the GTK 4 plugin from gst-plugins-rs 0.12 or newer.

| Distribution | Packages |
|---|---|
| Ubuntu, Debian 13 or newer | `python3-gi gir1.2-gtk-4.0 gir1.2-gstreamer-1.0 gstreamer1.0-pipewire gstreamer1.0-gtk4` |
| Fedora | `python3-gobject gtk4 pipewire-gstreamer gstreamer1-plugin-gtk4` |
| Arch | `python-gobject gtk4 gst-plugin-pipewire gst-plugin-gtk4` |

The Ubuntu packages are tested. The Fedora and Arch names are given for convenience and are not tested.

### Usage

Keep the `pointer-position@ckefalianou.github.io` folder next to `wayland/virtualmonitor-wayland.sh`, then run `./split.sh`.

1. On the first run the script installs the cursor helper extension. Log out and back in once to activate it. The script also updates the installed copy whenever the extension changes.
2. Choose a size for the virtual monitor.
3. Place the viewer window where you want it on your screen.
4. Move windows into the virtual monitor with Super+Shift+Right, or drag them past the edge of your screen. GNOME usually places the virtual monitor to the right of your displays. Settings › Displays shows where it is.
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

The helper extension returns the pointer position only while the pointer is on a virtual monitor.
While the pointer is on a real display, it returns empty values.
While it is on a virtual monitor, any program in your desktop session can ask for its position, including for virtual monitors that other tools create.

### Troubleshooting

The script prints why the cursor helper extension is not in use:

- **"was just installed" or "was just updated":** log out and back in once.
- **"GNOME has not loaded the cursor helper extension yet":** log out and back in once.
- **"User extensions are turned off":** turn them on in the Extensions app.
- **"is INACTIVE" or another state:** enable the extension in the Extensions app.
- **"does not support this GNOME version yet":** the extension declares the GNOME versions it was tested on. The viewer still works in compatible mode.
- **"failed to load" or "is active but did not answer":** check the log with `journalctl --user -b | grep pointer-position`.
- **"folder is missing next to the script":** keep the extension folder next to `wayland/virtualmonitor-wayland.sh`.
- **"Could not copy" or "Could not compare":** check the permissions of your GNOME Shell extensions folder.

If the viewer stays black without an error, run it with `COMPATIBLE=1`.

### Uninstall

```bash
gnome-extensions uninstall pointer-position@ckefalianou.github.io
```

### Limitations

- The virtual monitor is an extra display next to your screen, not a slice of it. You work in it by moving the pointer past the screen edge and watching the viewer.
- Clicks on the viewer window do not reach the apps inside the virtual monitor.
- The cursor in the viewer is always a plain arrow and does not change shape.
