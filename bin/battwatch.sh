#!/bin/bash
while true; do
    bat=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)
    stat=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1)
    if [ -n "$bat" ] && [ "$stat" = "Discharging" ] && [ "$bat" -le 15 ]; then
        notify-send -u critical "battery ${bat}%" "plug in"
        sleep 300
    fi
    sleep 60
done
