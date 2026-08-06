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
niri msg --json event-stream | while IFS= read -r event; do
    case "$event" in
        *Workspace*) render ;;
    esac
done
