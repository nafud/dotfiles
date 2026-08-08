#!/bin/bash
# mullvad in the bar: shield + relay when the tunnel is up, the state
# word otherwise. Rendered once at start, then on every tunnel state
# change — `mullvad status listen` carries the change notifications and
# the state is re-read whole each time, the workspaces.sh recipe (the
# notification content never needs parsing). A machine without mullvad
# gets an empty module: the guard exits, waybar's restart-interval
# re-probes, and the same restart revives the stream if the daemon is
# ever restarted underneath it.
command -v mullvad >/dev/null || exit 0

# `vpn.sh gui` is the module's click: surface the app window. The GUI
# is single-instance Electron — already running (even headless) it
# shows its window, never a duplicate. gio launch reads the desktop
# entry, whose Exec path contains a space best left to it.
if [ "${1:-}" = "gui" ]; then
    # the click handler inherits the bar's fds — the electron app's
    # chatter must not land in waybar.log
    exec gio launch /usr/share/applications/mullvad-vpn.desktop >/dev/null 2>&1
fi

# `vpn.sh toggle` is the module's right-click. Anything not on the way
# down is taken down; a click mid-connect is a cancel, not a queued
# second connect. The bar re-renders through the listen stream, so the
# toggle only ever issues the command.
if [ "${1:-}" = "toggle" ]; then
    case "$(mullvad status --json 2>/dev/null | jq -r .state)" in
        disconnected|disconnecting) exec mullvad connect ;;
        *)                          exec mullvad disconnect ;;
    esac
fi

# the bar keeps the shortened relay; the tooltip carries what the bar
# elides — exit location, exit address, the relay's full name
render() {
    mullvad status --json 2>/dev/null | jq -c '
        {text: (if   .state == "connected"
                then "󰦝 " + (.details.location.hostname
                             | sub("-(wg|ovpn)-[0-9]+$"; ""))
                elif .state == "error"         then "󰦞 blocked"
                elif .state == "connecting"    then "󰦝 …"
                elif .state == "disconnecting" then "󰦞 …"
                else                                "󰦞 down" end),
         class: .state,
         tooltip: (if .state == "connected" and .details.location != null
                   then "\(.details.location.city), \(.details.location.country)\n\(.details.location.ipv4 // "?") · \(.details.location.hostname)"
                   else "tunnel \(.state)" end)}'
}
render

# stream in the background, reaped by the trap — the workspaces.sh
# recipe: the pipeline must not outlive the bar's reload
trap 'trap - TERM; kill 0' TERM INT EXIT
mullvad status listen 2>/dev/null | while IFS= read -r _; do render; done &
wait
