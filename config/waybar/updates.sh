#!/bin/bash
# mint's update manager in the bar. The tray icon mintupdate ships is
# an XApp status icon — Cinnamon/MATE panels only, waybar's tray can
# never dock it — so the bar renders the state itself: mintupdate-cli
# carries the same blacklist and kernel logic as the GUI, the count is
# its line count. Monochrome at rest; color marks pending updates,
# the rose reserved for pending security fixes. The autostarted GUI
# process (config/niri/misc.kdl) keeps the apt cache fresh; clicking
# the module surfaces its window — single-instance, never a duplicate.
command -v mintupdate-cli >/dev/null || exit 0

if [ "${1:-}" = "gui" ]; then
    exec mintupdate
fi

list="$(mintupdate-cli list 2>/dev/null)" || exit 0

total=$(grep -c . <<<"$list")
if [ "$total" -eq 0 ]; then
    jq -cn '{text: "󰚰", tooltip: "up to date", class: "uptodate"}'
    exit 0
fi

security=$(grep -c '^security' <<<"$list")
class=updates
[ "$security" -gt 0 ] && class=security

# tooltip: per-type counts, biggest first — "8 package · 5 security · 1 kernel"
tooltip=$(awk '{n[$1]++} END {for (t in n) print n[t], t}' <<<"$list" \
          | sort -rn | awk '{printf "%s%d %s", sep, $1, $2; sep=" · "}')

jq -cn --arg text "󰚰 $total" --arg tooltip "$tooltip" --arg class "$class" \
    '{text: $text, tooltip: $tooltip, class: $class}'
