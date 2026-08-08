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

# The stream must die with the bar: waybar starts each module script in
# a process group of its own and TERMs only the script on reload — a
# foreground pipeline would outlive it as orphans rendering into a dead
# pipe. The group is ours alone, so kill 0 takes down exactly the
# pipeline; backgrounding it frees bash to run the trap the moment the
# signal lands, where a foreground pipeline would hold it to the end.
trap 'trap - TERM; kill 0' TERM INT EXIT
niri msg --json event-stream | while IFS= read -r event; do
    case "$event" in
        *Workspace*) render ;;
    esac
done &
wait
