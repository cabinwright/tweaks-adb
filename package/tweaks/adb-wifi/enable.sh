#!/system/bin/sh
# Turn ADB over Wi-Fi on (see common.sh). What adb.tcp or HMG Leafia Plus already set up is
# taken over (lib/adb-adopt.sh); the rest goes through kt. Never reboots and never restarts a
# running adbd: persist.service.adb.tcp.enable is set only when it isn't 1 yet (setting it again
# would fire init's trigger and restart adbd).
D=${TWEAK_DIR:-${0%/*}}
. "$D/common.sh"
. "$D/../../lib/adb-adopt.sh"
adbtcp_plan || fail "nothing changed"
leafia_plan
# 1. eth0's address, before the switch below brings it up
if ! ifc_ours; then
    ifc_stock || fail "/system/bin/ifconfig isn't the stock toolbox link - leaving it alone"
    [ "$(sum "$D/../../lib/ifconfig")" = $SUM_IFC ] || fail "lib/ifconfig in the package is damaged"
    step exe $IFC "$D/../../lib/ifconfig"
fi
# 2. the port, read by adbd when it starts. Set even when getprop has it: this boot's value may
# not be saved, and only the saved one is there at the next start
case "$STEPS" in *"propadopt:$PORT:"*) ;; *) step port $PORT 5555 ;; esac
# 3. Engineering Mode's ADB switch (shows after the next start)
is_hidden && step put $HIDE "$D/adb_hide.shown.xml"
# 4. the switch itself, last. Already 1 (from Engineering Mode): kept as it is, and turning the
# tweak off sets it to 0, as Engineering Mode's own switch does
if ! is_on; then
    step prop $EN 1
else
    case "$STEPS" in *"propadopt:$EN:"*) ;; *) step propadopt $EN 0 ;; esac
fi
run_steps || fail "stopped part way - turn it off to put back what was changed"
if ! is_on || ! has_port; then fail "still off after the change"; fi
# ADB TCP already gave eth0 its /24 this boot: run the stock service again, now through the
# wrapper, so it becomes /32 at once
if [ -n "$(eth0_clashes)" ]; then
    kt service start set_adb_ip
    sleep 2
    [ -n "$(eth0_clashes)" ] && echo "eth0 still has 192.168.0.123/24 - it is narrowed at the next start"
fi
case "$STEPS" in
    *" put:"* | *" exe:"* | *" prop:"*) echo "ADB over Wi-Fi turned on" ;;
    *) echo "ADB over Wi-Fi was already on: taken over, nothing changed" ;;
esac
exit 0
