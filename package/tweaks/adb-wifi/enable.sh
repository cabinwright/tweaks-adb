#!/system/bin/sh
# Turn ADB over Wi-Fi on (see common.sh). Backs up first, never reboots, never restarts a
# running adbd: persist.service.adb.tcp.enable is set with setprop only when it isn't 1 yet
# (setprop with the same value would fire init's trigger again and restart adbd).
D=${0%/*}
. $D/common.sh
if is_on && has_port && [ ! -f "$HIDE" ]; then
    # already on, e.g. as adb.tcp left it: only take over its backup (writes nothing else)
    take_backup >/dev/null 2>&1
    echo "already on"; exit 0
fi
take_backup || fail "couldn't back up the current state"
# 1. the port, read by adbd when it starts
if [ -z "$(boot_value $PORT)" ]; then
    setprop $PORT 5555
    [ "$(boot_value $PORT)" = 5555 ] || put_prop_file $PORT 5555 || fail "setting $PORT"
fi
# 2. Engineering Mode's ADB switch (shows after the next start)
if [ -f "$HIDE" ]; then
    $NEMESIS remount rw >/dev/null 2>&1 || fail "remount /system rw"
    rm -f "$HIDE" || fail "removing $HIDE"
    sync
    $NEMESIS remount ro >/dev/null 2>&1
fi
# 3. the switch itself, last
if ! is_on; then
    if [ "$(getprop $EN)" = 1 ]; then
        # already 1 for now (its file was removed): save it without firing init's trigger
        put_prop_file $EN 1 || fail "saving $EN"
    else
        # starts adbd on port 5555 at once
        setprop $EN 1
        is_on || put_prop_file $EN 1 || fail "saving $EN"
    fi
fi
is_on && has_port || fail "still off after the change"
echo "ADB over Wi-Fi turned on"
exit 0
