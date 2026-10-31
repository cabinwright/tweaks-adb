#!/system/bin/sh
# One line: on|off|error <text>. Reads only. "On" is the switch Engineering Mode shows;
# /proc/net/tcp says whether adbd is listening right now.
D=${TWEAK_DIR:-${0%/*}}
. "$D/common.sh"
if is_on; then
    if ! has_port; then echo "error turned on elsewhere without a port number"
    elif [ -n "$(eth0_clashes)" ]; then echo "on works; wireless projection after the next restart"
    elif listening; then echo "on ADB over Wi-Fi is on"
    else echo "on works after the next restart"
    fi
elif listening; then
    echo "off ADB stays on until the next restart"
else
    echo "off"
fi
