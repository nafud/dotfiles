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

render() {
    mullvad status --json 2>/dev/null | jq -c '
        {text: (if   .state == "connected"
                then "󰦝 " + (.details.location.hostname
                             | sub("-(wg|ovpn)-[0-9]+$"; ""))
                elif .state == "error"         then "󰦞 blocked"
                elif .state == "connecting"    then "󰦝 …"
                elif .state == "disconnecting" then "󰦞 …"
                else                                "󰦞 down" end),
         class: .state}'
}
render
mullvad status listen 2>/dev/null | while IFS= read -r _; do render; done
