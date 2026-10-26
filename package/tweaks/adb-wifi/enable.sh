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
# 1. the port, read by adbd when it starts
[ -n "$(getprop $PORT)" ] || step prop $PORT 5555
# 2. Engineering Mode's ADB switch (shows after the next start)
is_hidden && step put $HIDE "$D/adb_hide.shown.xml"
# 3. the switch itself, last. Already 1 (from Engineering Mode): kept as it is, and turning the
# tweak off sets it to 0, as Engineering Mode's own switch does
if ! is_on; then
    step prop $EN 1
else
    case "$STEPS" in *"propadopt:$EN:"*) ;; *) step propadopt $EN 0 ;; esac
fi
run_steps || fail "stopped part way - turn it off to put back what was changed"
if ! is_on || ! has_port; then fail "still off after the change"; fi
case "$STEPS" in
    *" put:"* | *" prop:"*) echo "ADB over Wi-Fi turned on" ;;
    *) echo "ADB over Wi-Fi was already on: taken over, nothing changed" ;;
esac
exit 0
