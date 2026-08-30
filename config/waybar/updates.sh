#!/bin/bash
# pacman + AUR updates in the bar. checkupdates (pacman-contrib) syncs a
# throwaway copy of the sync databases, so counting pending updates
# never touches the real DB (the partial-upgrade trap `pacman -Sy`
# would set); paru -Qua adds the AUR set's pending bumps. Absent while
# up to date; the count appears, in amber, when there is something to
# apply. Clicking the module runs the upgrade in a terminal; applying
# it rewrites the pacman DB, which waybar-updates.path turns into a
# poke that re-renders the module — empty again.
command -v checkupdates >/dev/null || exit 0

if [ "${1:-}" = "gui" ]; then
    # the click handler inherits the bar's fds — the terminal's own
    # output must not land in the bar's journal. paru -Syu covers repos and
    # AUR alike; plain pacman is the fallback before paru exists.
    if command -v paru >/dev/null; then
        exec alacritty -e sh -c \
            'paru -Syu; printf "\ndone — Enter to close "; read -r _' \
            >/dev/null 2>&1
    fi
    exec alacritty -e sh -c \
        'sudo pacman -Syu; printf "\ndone — Enter to close "; read -r _' \
        >/dev/null 2>&1
fi

# 0 = updates listed, 2 = none pending; 1 (error: network down, db
# locked) renders nothing rather than a stale count
repo="$(checkupdates 2>/dev/null)" && rc=0 || rc=$?
[ "$rc" -eq 1 ] && exit 0

# same "name old -> new" line format as checkupdates; a failure (AUR
# unreachable) counts as no AUR updates rather than no module
aur=""
if command -v paru >/dev/null; then
    aur="$(paru -Qua 2>/dev/null)" || aur=""
fi

list="$(printf '%s\n%s\n' "$repo" "$aur" | grep .)" || true
total=$(grep -c . <<<"$list")
# nothing pending: render empty and the bar collapses the module (the
# battery-module convention: absent condition, absent module)
if [ "$total" -eq 0 ]; then
    echo
    exit 0
fi

# tooltip: the pending packages themselves, capped so a big rebuild
# does not paint a screen-high tooltip
tooltip=$(head -n 15 <<<"$list" | awk '{printf "%s%s %s → %s", sep, $1, $2, $4; sep="\n"}')
[ "$total" -gt 15 ] && tooltip="$tooltip"$'\n'"… $((total - 15)) more"

jq -cn --arg text "<span size='98.0%' letter_spacing='5087'>󰚰</span> $total" --arg tooltip "$tooltip" \
    '{text: $text, tooltip: $tooltip, class: "updates"}'
