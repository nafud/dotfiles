#!/bin/bash
# current keyboard layout in the bar, as a two-letter mark: en, az, ru.
# The mark is the layout name's first two letters — which is exactly
# right for every layout configured (English (US), Azerbaijani,
# Russian); a fourth layout that breaks the rule earns a real map here.
# Rendered once, then on each KeyboardLayout* event — the workspaces.sh
# recipe: the event only says "changed", the state is re-read whole.
render() {
    niri msg --json keyboard-layouts \
        | jq -r '.names[.current_idx][0:2] | ascii_downcase'
}
render

# stream in the background, reaped by the trap — the workspaces.sh
# recipe: the pipeline must not outlive the bar's reload
trap 'trap - TERM; kill 0' TERM INT EXIT
niri msg --json event-stream | while IFS= read -r event; do
    case "$event" in
        *KeyboardLayout*) render ;;
    esac
done &
wait
