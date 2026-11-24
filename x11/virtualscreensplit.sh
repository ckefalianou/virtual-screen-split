#!/bin/bash
# Splits one physical monitor into virtual monitors on X11 with "xrandr --setmonitor".
# Apps and screen-sharing tools then see each part as a separate screen.

set -uo pipefail

MIDDLE_WIDTH=1920
# The three-part split needs at least this much room on each side of the middle part.
MIN_SIDE_WIDTH=640
NAME_PREFIX="SPLIT-"
CREATED_MONITORS=()

fail() {
    echo "Error: $1" >&2
    exit 1
}

command -v xrandr >/dev/null || fail "xrandr is not installed."
[ -n "${DISPLAY:-}" ] || fail "DISPLAY is not set. Run this inside an X11 session."

XRANDR_OUTPUT=$(xrandr --query) || fail "xrandr could not read the display layout."

# Prints "name width height x y mm_width mm_height" for every output, with zeros when it has no active mode.
OUTPUTS=$(awk '$2 == "connected" || $2 == "disconnected" {
    geometry = "0x0+0+0"; mm_width = 0; mm_height = 0
    for (i = 3; i <= NF; i++) {
        if ($i ~ /^[0-9]+x[0-9]+\+-?[0-9]+\+-?[0-9]+$/) { geometry = $i }
        if ($i ~ /^[0-9]+mm$/ && $(i + 1) == "x" && $(i + 2) ~ /^[0-9]+mm$/) { mm_width = $i + 0; mm_height = $(i + 2) + 0 }
    }
    split(geometry, parts, /[x+]/)
    print $1, $2, ($3 == "primary" ? "primary" : "-"), parts[1], parts[2], parts[3], parts[4], mm_width, mm_height
}' <<< "$XRANDR_OUTPUT")

# Uses the primary output, or the widest active connected output when no primary is set.
PRIMARY_DISPLAY=$(awk '$2 == "connected" && $3 == "primary" { print $1; exit }' <<< "$OUTPUTS")
if [ -z "$PRIMARY_DISPLAY" ]; then
    PRIMARY_DISPLAY=$(awk '$2 == "connected" && $4 > widest { widest = $4; name = $1 } END { print name }' <<< "$OUTPUTS")
fi
if [ -z "$PRIMARY_DISPLAY" ]; then
    PRIMARY_DISPLAY=$(awk '$2 == "connected" { print $1; exit }' <<< "$OUTPUTS")
fi
[ -n "$PRIMARY_DISPLAY" ] || fail "no connected display was found."

read -r _ _ _ PRIMARY_WIDTH PRIMARY_HEIGHT PRIMARY_X PRIMARY_Y PRIMARY_MM_WIDTH PRIMARY_MM_HEIGHT < <(
    awk -v output="$PRIMARY_DISPLAY" '$1 == output { print; exit }' <<< "$OUTPUTS"
)

# Displays without a physical size get one that matches 96 DPI, so apps never see a size of zero.
if [ "$PRIMARY_MM_WIDTH" -eq 0 ] || [ "$PRIMARY_MM_HEIGHT" -eq 0 ]; then
    PRIMARY_MM_WIDTH=$((PRIMARY_WIDTH * 254 / 960))
    PRIMARY_MM_HEIGHT=$((PRIMARY_HEIGHT * 254 / 960))
fi

# Every other output that is active, connected or not, because each one takes space on the screen.
OTHER_DISPLAYS=$(awk -v primary="$PRIMARY_DISPLAY" '$1 != primary && $4 > 0 { print $1 }' <<< "$OUTPUTS")

require_active_primary() {
    [ "$PRIMARY_WIDTH" -gt 0 ] || fail "$PRIMARY_DISPLAY is turned off. Choose option 1 first to turn it on."
}

# Splits the physical size in proportion to the pixels, so apps keep the right DPI.
millimetres() {
    echo $(( PRIMARY_MM_WIDTH * $1 / PRIMARY_WIDTH ))
}

# The first part takes the real output, and the others use "none", because an output can belong to one monitor only.
add_part() {
    local index="$1" width="$2" offset="$3" output="$4"
    if ! xrandr --setmonitor "${NAME_PREFIX}${index}" \
        "${width}/$(millimetres "$width")x${PRIMARY_HEIGHT}/${PRIMARY_MM_HEIGHT}+$((PRIMARY_X + offset))+${PRIMARY_Y}" \
        "$output"; then
        # A half-finished split would leave the output in one small monitor, so the parts made so far are removed.
        local monitor
        for monitor in "${CREATED_MONITORS[@]}"; do
            xrandr --delmonitor "$monitor" >/dev/null 2>&1
        done
        fail "xrandr could not create ${NAME_PREFIX}${index}."
    fi
    CREATED_MONITORS+=("${NAME_PREFIX}${index}")
}

remove_virtual_monitors() {
    local monitor removed=0
    # The listing prefixes names with "+" or "*", so they are stripped before deleting.
    while read -r monitor; do
        if xrandr --delmonitor "$monitor"; then
            removed=$((removed + 1))
        else
            echo "Warning: could not remove $monitor." >&2
        fi
    done < <(xrandr --listmonitors | awk 'NR > 1 { name = $2; sub(/^[+*]+/, "", name); print name }' | grep "^${NAME_PREFIX}")
    if [ "$removed" -gt 0 ]; then
        echo "Removed $removed virtual monitor(s)."
    else
        echo "No virtual monitors to remove."
    fi
}

single_monitor() {
    if [ -n "$OTHER_DISPLAYS" ]; then
        echo "This keeps $PRIMARY_DISPLAY and turns off: $(echo $OTHER_DISPLAYS)"
        local answer=""
        read -r -p "Continue? (y/N): " answer || answer=""
        [[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
    fi
    remove_virtual_monitors
    # An active output keeps its current mode, and an output that is off gets its preferred mode.
    if [ "$PRIMARY_WIDTH" -gt 0 ]; then
        xrandr --output "$PRIMARY_DISPLAY" --primary || fail "xrandr could not set up $PRIMARY_DISPLAY."
    else
        xrandr --output "$PRIMARY_DISPLAY" --auto --primary || fail "xrandr could not turn on $PRIMARY_DISPLAY."
    fi
    local display
    for display in $OTHER_DISPLAYS; do
        xrandr --output "$display" --off || echo "Warning: could not turn off $display." >&2
    done
    echo "Switched to Single Monitor ($PRIMARY_DISPLAY)."
    if [ -n "$OTHER_DISPLAYS" ]; then
        echo "To turn a display back on, run: xrandr --output <name> --auto"
    fi
}

virtual_split() {
    require_active_primary
    local left_width=$((PRIMARY_WIDTH / 2))
    local right_width=$((PRIMARY_WIDTH - left_width))
    remove_virtual_monitors
    add_part 1 "$left_width" 0 "$PRIMARY_DISPLAY"
    add_part 2 "$right_width" "$left_width" none
    echo "Switched to Virtual Split Mode (${left_width}x${PRIMARY_HEIGHT} | ${right_width}x${PRIMARY_HEIGHT})."
}

virtual_three_split() {
    require_active_primary
    local middle_width=$MIDDLE_WIDTH
    # Screens without room for usable sides get three equal parts instead.
    if [ "$PRIMARY_WIDTH" -lt $((MIDDLE_WIDTH + 2 * MIN_SIDE_WIDTH)) ]; then
        middle_width=$((PRIMARY_WIDTH / 3))
    fi
    local side_width=$(((PRIMARY_WIDTH - middle_width) / 2))
    local right_width=$((PRIMARY_WIDTH - side_width - middle_width))
    remove_virtual_monitors
    add_part 1 "$side_width" 0 "$PRIMARY_DISPLAY"
    add_part 2 "$middle_width" "$side_width" none
    add_part 3 "$right_width" $((side_width + middle_width)) none
    echo "Switched to Virtual Three Split Mode (${side_width}x${PRIMARY_HEIGHT} | ${middle_width}x${PRIMARY_HEIGHT} | ${right_width}x${PRIMARY_HEIGHT})."
}

# Display menu
if [ "$PRIMARY_WIDTH" -gt 0 ]; then
    echo "Display: $PRIMARY_DISPLAY (${PRIMARY_WIDTH}x${PRIMARY_HEIGHT})"
else
    echo "Display: $PRIMARY_DISPLAY (turned off)"
fi
echo "Choose a display mode:"
echo "1) Single Monitor (turns off other displays)"
echo "2) Virtual Split Mode (two halves)"
echo "3) Virtual Three Split Mode (sides and a ${MIDDLE_WIDTH}px middle)"
echo "4) Delete All Virtual Monitors"
choice=""
read -r -p "Enter your choice (1/2/3/4): " choice || choice=""

case $choice in
    1) single_monitor ;;
    2) virtual_split ;;
    3) virtual_three_split ;;
    4) remove_virtual_monitors ;;
    *) fail "invalid choice." ;;
esac
