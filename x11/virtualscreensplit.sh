#!/bin/bash
# Splits one physical monitor into virtual monitors on X11 with "xrandr --setmonitor".
# Apps and screen-sharing tools then see each part as a separate screen.

set -uo pipefail

MIDDLE_WIDTH=1920
NAME_PREFIX="SPLIT-"

fail() {
    echo "Error: $1" >&2
    exit 1
}

command -v xrandr >/dev/null || fail "xrandr is not installed."
[ -n "${DISPLAY:-}" ] || fail "DISPLAY is not set. Run this inside an X11 session."

XRANDR_OUTPUT=$(xrandr --query) || fail "xrandr could not read the display layout."

# Uses the primary output, or the first connected output when no primary is set.
PRIMARY_DISPLAY=$(awk '$2 == "connected" && $3 == "primary" { print $1; exit }' <<< "$XRANDR_OUTPUT")
if [ -z "$PRIMARY_DISPLAY" ]; then
    PRIMARY_DISPLAY=$(awk '$2 == "connected" { print $1; exit }' <<< "$XRANDR_OUTPUT")
fi
[ -n "$PRIMARY_DISPLAY" ] || fail "no connected display was found."

# The header line holds the current geometry, e.g. "DP-1 connected primary 5120x1440+0+0 (...) 1190mm x 340mm".
read -r PRIMARY_WIDTH PRIMARY_HEIGHT PRIMARY_X PRIMARY_Y PRIMARY_MM_WIDTH PRIMARY_MM_HEIGHT < <(
    awk -v output="$PRIMARY_DISPLAY" '$1 == output {
        geometry = ""; mm_width = 0; mm_height = 0
        for (i = 2; i <= NF; i++) {
            if ($i ~ /^[0-9]+x[0-9]+\+-?[0-9]+\+-?[0-9]+$/) { geometry = $i }
            if ($i ~ /^[0-9]+mm$/ && $(i + 1) == "x" && $(i + 2) ~ /^[0-9]+mm$/) { mm_width = $i + 0; mm_height = $(i + 2) + 0 }
        }
        split(geometry, parts, /[x+]/)
        print parts[1], parts[2], parts[3], parts[4], mm_width, mm_height
        exit
    }' <<< "$XRANDR_OUTPUT"
)
[[ "${PRIMARY_WIDTH:-}" =~ ^[0-9]+$ && "$PRIMARY_WIDTH" -gt 0 ]] || fail "$PRIMARY_DISPLAY has no active mode."

OTHER_DISPLAYS=$(awk -v primary="$PRIMARY_DISPLAY" '$2 == "connected" && $1 != primary { print $1 }' <<< "$XRANDR_OUTPUT")

# Splits the physical size in proportion to the pixels, so apps keep the right DPI.
millimetres() {
    echo $(( PRIMARY_MM_WIDTH * $1 / PRIMARY_WIDTH ))
}

# The first part takes the real output, and the others use "none", because an output can belong to one monitor only.
add_part() {
    local index="$1" width="$2" offset="$3" output="$4"
    xrandr --setmonitor "${NAME_PREFIX}${index}" \
        "${width}/$(millimetres "$width")x${PRIMARY_HEIGHT}/${PRIMARY_MM_HEIGHT}+$((PRIMARY_X + offset))+${PRIMARY_Y}" \
        "$output" || fail "xrandr could not create ${NAME_PREFIX}${index}."
}

remove_virtual_monitors() {
    local monitor
    # The listing prefixes names with "+" or "*", so they are stripped before deleting.
    while read -r monitor; do
        xrandr --delmonitor "$monitor" || echo "Warning: could not remove $monitor." >&2
    done < <(xrandr --listmonitors | awk 'NR > 1 { name = $2; sub(/^[+*]+/, "", name); print name }' | grep "^${NAME_PREFIX}")
    echo "Removed all virtual monitors."
}

single_monitor() {
    if [ -n "$OTHER_DISPLAYS" ]; then
        echo "This turns off: $(echo $OTHER_DISPLAYS)"
        read -r -p "Continue? (y/N): " answer
        [[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
    fi
    remove_virtual_monitors
    xrandr --output "$PRIMARY_DISPLAY" --auto --primary || fail "xrandr could not set up $PRIMARY_DISPLAY."
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
    local left_width=$((PRIMARY_WIDTH / 2))
    local right_width=$((PRIMARY_WIDTH - left_width))
    remove_virtual_monitors
    add_part 1 "$left_width" 0 "$PRIMARY_DISPLAY"
    add_part 2 "$right_width" "$left_width" none
    echo "Switched to Virtual Split Mode (${left_width}x${PRIMARY_HEIGHT} | ${right_width}x${PRIMARY_HEIGHT})."
}

virtual_three_split() {
    local middle_width=$MIDDLE_WIDTH
    # Narrow screens get three equal parts, because a 1920 px middle part would leave no room.
    if [ "$PRIMARY_WIDTH" -le $((MIDDLE_WIDTH + 200)) ]; then
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
echo "Display: $PRIMARY_DISPLAY (${PRIMARY_WIDTH}x${PRIMARY_HEIGHT})"
echo "Choose a display mode:"
echo "1) Single Monitor (turns off other displays)"
echo "2) Virtual Split Mode (two halves)"
echo "3) Virtual Three Split Mode (sides and a ${MIDDLE_WIDTH}px middle)"
echo "4) Delete All Virtual Monitors"
read -r -p "Enter your choice (1/2/3/4): " choice

case $choice in
    1) single_monitor ;;
    2) virtual_split ;;
    3) virtual_three_split ;;
    4) remove_virtual_monitors ;;
    *) fail "invalid choice." ;;
esac
