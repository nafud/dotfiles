#!/bin/bash
# current keyboard layout in the bar, as a two-letter mark taken from
# the layout name's first two letters; a layout set that breaks that
# rule earns a real map here. With a single configured layout the mark
# carries no information, so the module renders empty and the bar
# collapses it — it appears with the second layout (the battery-module
# convention: absent hardware, absent module).
# Rendered once, then on each KeyboardLayout* event — the workspaces.sh
# recipe: the event only says "changed", the state is re-read whole.
render() {
    niri msg --json keyboard-layouts \
        | jq -r 'if (.names | length) < 2 then ""
                 else .names[.current_idx][0:2] | ascii_downcase end'
}
render

# stream and bar-watchdog in the background, the group felled when the
# bar goes — the workspaces.sh recipe: waybar orphans its scripts, so
# each script owns its own lifetime
bar=$PPID
while [ "${bar:-1}" -gt 1 ] && [ "$(ps -o comm= -p "$bar" 2>/dev/null)" != "waybar" ]; do
    bar=$(ps -o ppid= -p "$bar" 2>/dev/null | tr -d ' ')
done
trap 'trap - TERM; kill 0' TERM INT EXIT
( while kill -0 "${bar:-1}" 2>/dev/null; do sleep 5; done; kill 0 ) &
niri msg --json event-stream | while IFS= read -r event; do
    case "$event" in
        *KeyboardLayout*) render ;;
    esac
done &
wait -n
