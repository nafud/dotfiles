#!/bin/bash
# current keyboard layout in the bar, as a two-letter mark taken from
# the layout name's first two letters; a layout set that breaks that
# rule earns a real map here. With a single configured layout the mark
# carries no information, so the module renders empty and the bar
# collapses it — it appears with the second layout (the battery-module
# convention: absent hardware, absent module).
# Rendered once, then on each KeyboardLayout* event: the event only
# says "changed", the state is re-read whole.
render() {
    niri msg --json keyboard-layouts \
        | jq -r 'if (.names | length) < 2 then ""
                 else .names[.current_idx][0:2] | ascii_downcase end'
}
render

# The stream must die with the bar. waybar never signals its module
# scripts — on reload and on exit alike they are silently orphaned, the
# stream rendering into a dead pipe forever (bash survives the EPIPE:
# jq takes it, the loop reads on). So the script owns its lifetime: it
# finds the bar it was spawned under and a watchdog takes the process
# group down the moment that bar is gone. The group is ours alone
# (waybar setpgids each module), so kill 0 fells exactly this pipeline;
# everything runs in the background because a foreground pipeline would
# hold bash's traps hostage until the stream ended.
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
