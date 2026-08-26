#!/bin/bash
# The recording mark: present, in the condition amber, while
# gpu-screen-recorder runs (bin/record-toggle pokes the module at start
# and stop; the module's interval catches a recorder stopped some other
# way). Absent otherwise, and the bar collapses the module. The glyph's
# span is the one tools/waybar-icon-span measured for U+F0EC2.
if pgrep -x gpu-screen-recorder >/dev/null; then
    printf '%s\n' "{\"text\": \"<span size='88.0%' rise='527' letter_spacing='6983'>󰻂</span>\", \"class\": \"recording\", \"tooltip\": \"recording — click to stop\"}"
else
    printf '%s\n' '{"text": ""}'
fi
