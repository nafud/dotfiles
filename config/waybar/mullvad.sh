#!/bin/bash
# Mullvad tunnel state in the bar: a shield glyph per state (locked when
# up, struck when down, hollow in transition, alert on error) with a
# one-word mark, colored by class. Clicking opens the Mullvad app to
# pick a destination; right-click toggles the tunnel. Without the
# mullvad CLI or with the daemon down the module renders empty and the
# bar collapses it (the battery-module convention: absent hardware,
# absent module).
# Rendered once, then on each tunnel-state event from `mullvad status
# listen` — the layout.sh recipe: the event only says "changed", the
# state is re-read whole.
command -v mullvad >/dev/null || exit 0

case "${1:-}" in
    gui)
        # through the desktop entry: the /usr/bin/mullvad-vpn wrapper
        # hands the app a literal "%U". The click handler inherits the
        # bar's fds — the app's (Electron) chatter must not land in
        # waybar.log.
        exec gio launch /usr/share/applications/mullvad-vpn.desktop >/dev/null 2>&1 ;;
    toggle)
        case "$(mullvad status -j 2>/dev/null | jq -r '.state // empty')" in
            connected|connecting) exec mullvad disconnect >/dev/null 2>&1 ;;
            *)                    exec mullvad connect    >/dev/null 2>&1 ;;
        esac ;;
esac

render() {
    local status state glyph mark class where
    status=$(mullvad status -j 2>/dev/null) || { echo; return; }
    state=$(jq -r '.state // empty' <<<"$status")
    case "$state" in
        connected)                glyph=󰦝 mark=on  class=connected ;;
        connecting|disconnecting) glyph=󰒙 mark=…   class=connecting ;;
        disconnected)             glyph=󰦜 mark=off class=disconnected ;;
        error)                    glyph=󰻌 mark=err class=error ;;
        *) echo; return ;;
    esac
    # tooltip: the visible location — the relay's when up, your own when
    # down — so the mark alone never has to carry that detail
    where=$(jq -r '.details.location // {} | [.city, .country] | map(select(. != null)) | join(", ")' <<<"$status")
    jq -cn --arg text "$glyph $mark" --arg class "$class" \
        --arg tooltip "mullvad: $state${where:+ — $where}" \
        '{text: $text, class: $class, tooltip: $tooltip}'
}
render

# stream and bar-watchdog in the background, the group felled when the
# bar goes — the layout.sh recipe: waybar orphans its scripts, so each
# script owns its own lifetime
bar=$PPID
while [ "${bar:-1}" -gt 1 ] && [ "$(ps -o comm= -p "$bar" 2>/dev/null)" != "waybar" ]; do
    bar=$(ps -o ppid= -p "$bar" 2>/dev/null | tr -d ' ')
done
trap 'trap - TERM; kill 0' TERM INT EXIT
( while kill -0 "${bar:-1}" 2>/dev/null; do sleep 5; done; kill 0 ) &
# each event is a state line plus indented detail lines; only the state
# line triggers a render
mullvad status listen 2>/dev/null | while IFS= read -r line; do
    case "$line" in [A-Z]*) render ;; esac
done &
wait -n
