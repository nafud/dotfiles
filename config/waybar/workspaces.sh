#!/bin/bash
# niri always keeps one empty workspace at the end (dynamic-workspace
# model, not disableable); hide it — list only occupied workspaces plus
# wherever the focus is.
render() {
    niri msg --json workspaces \
        | jq -r 'sort_by(.idx)
                 | map(select(.active_window_id != null or .is_focused))
                 | map(if .is_focused then "[\(.idx)]" else " \(.idx) " end)
                 | join("")'
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
        *Workspace*) render ;;
    esac
done &
wait -n
