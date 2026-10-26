#!/system/bin/sh
# Put back what enable.sh (or adb.tcp, when taken over) changed, exactly as the backup has it.
# Never reboots and never stops adbd: a running adbd stays until the next start. Files on
# /system first, the props last, so a half-done run still reads "on" and is run again.
D=${0%/*}
. $D/common.sh
is_on || { echo "already off"; exit 0; }
take_backup || fail "no backup of the state before, and adb.tcp's isn't usable"
backup_taken || fail "no backup of the state before"
# 1. build.prop, when adb.tcp added its lines: back to its snapshot, byte for byte
if [ -f "$B/build.prop.stock" ] && [ "$(sum "$BP")" != "$(sum "$B/build.prop.stock")" ]; then
    grep -v -E "$ADBTCP_LINES" "$BP" > "$B/bp.check" 2>/dev/null
    [ "$(sum "$B/bp.check")" = "$(sum "$B/build.prop.stock")" ] || { rm -f "$B/bp.check"; fail "build.prop was changed by something else - leaving it alone"; }
    rm -f "$B/bp.check"
    $NEMESIS remount rw >/dev/null 2>&1 || fail "remount /system rw"
    rm -f "$BP.kt"
    cp "$B/build.prop.stock" "$BP.kt" && chmod 644 "$BP.kt" && mv "$BP.kt" "$BP" || { rm -f "$BP.kt"; fail "writing build.prop"; }
    sync
    [ "$(sum "$BP")" = "$(sum "$B/build.prop.stock")" ] || fail "build.prop isn't the snapshot after the copy"
fi
# 2. adb_hide
if [ -f "$B/adb_hide.xml" ] && ! cmp -s "$B/adb_hide.xml" "$HIDE"; then
    $NEMESIS remount rw >/dev/null 2>&1 || fail "remount /system rw"
    rm -f "$HIDE.kt"
    cp "$B/adb_hide.xml" "$HIDE.kt" && chmod 644 "$HIDE.kt" && mv "$HIDE.kt" "$HIDE" || { rm -f "$HIDE.kt"; fail "writing $HIDE"; }
    sync
elif [ -f "$B/adb_hide.absent" ] && [ -f "$HIDE" ]; then
    $NEMESIS remount rw >/dev/null 2>&1 || fail "remount /system rw"
    rm -f "$HIDE" || fail "removing $HIDE"
    sync
fi
$NEMESIS remount ro >/dev/null 2>&1
# 3. the props. The switch first goes to 0 with setprop, as Engineering Mode's switch does, so
# its screen shows off at once (init has no trigger for 0, and unlike Engineering Mode this
# doesn't stop adbd); then the saved files go back as the backup has them.
restore_prop $PORT || fail "putting $PORT back"
[ "$(getprop $EN)" = 0 ] || setprop $EN 0
restore_prop $EN || fail "putting $EN back"
is_on && fail "still on after the change"
rm -rf "$B"
listening && echo "ADB over Wi-Fi turned off; it stays on until the next restart" || echo "ADB over Wi-Fi turned off"
exit 0
