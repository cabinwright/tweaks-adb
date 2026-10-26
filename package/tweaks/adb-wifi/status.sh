#!/system/bin/sh
# One line: on|off|error <text>. Reads only. "On" is what the next start will do (the saved
# props); /proc/net/tcp says whether adbd is listening right now.
D=${0%/*}
. $D/common.sh
[ -r "$PROPS" ] && [ -x "$PROPS" ] || { echo "error can't read the saved settings"; exit 0; }
if is_on; then
    if ! has_port; then echo "error turned on elsewhere without a port number"
    elif listening; then echo "on ADB over Wi-Fi is on"
    else echo "on works after the next restart"
    fi
else
    listening && echo "off ADB stays on until the next restart" || echo "off"
fi
