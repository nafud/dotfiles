#!/bin/bash
# pacman updates in the bar. checkupdates (pacman-contrib) syncs a
# throwaway copy of the sync databases, so counting pending updates
# never touches the real DB (the partial-upgrade trap `pacman -Sy`
# would set). Monochrome at rest; color marks pending updates.
# Clicking the module runs the upgrade in a terminal; applying it
# rewrites the pacman DB, which waybar-updates.path turns into a poke
# that clears the badge.
command -v checkupdates >/dev/null || exit 0

if [ "${1:-}" = "gui" ]; then
    # the click handler inherits the bar's fds — the terminal's own
    # output must not land in waybar.log
    exec alacritty -e sh -c \
        'sudo pacman -Syu; printf "\ndone — Enter to close "; read -r _' \
        >/dev/null 2>&1
fi

# 0 = updates listed, 2 = none pending; 1 (error: network down, db
# locked) renders nothing rather than a stale count
list="$(checkupdates 2>/dev/null)" && rc=0 || rc=$?
case $rc in
    2) jq -cn '{text: "󰚰", tooltip: "up to date", class: "uptodate"}'; exit 0 ;;
    0) ;;
    *) exit 0 ;;
esac

total=$(grep -c . <<<"$list")

# tooltip: the pending packages themselves, capped so a big rebuild
# does not paint a screen-high tooltip
tooltip=$(head -n 15 <<<"$list" | awk '{printf "%s%s %s → %s", sep, $1, $2, $4; sep="\n"}')
[ "$total" -gt 15 ] && tooltip="$tooltip"$'\n'"… $((total - 15)) more"

jq -cn --arg text "󰚰 $total" --arg tooltip "$tooltip" \
    '{text: $text, tooltip: $tooltip, class: "updates"}'
