#!/bin/sh
# Host test: runs the adb-wifi tweak's scripts against a mock head unit (build.prop, the
# adb_hide feature file, /data/property, /proc/net/tcp) with stubs for getprop/setprop, md5 and
# nemesis. setprop is logged; setting persist.service.adb.tcp.enable to 1 plays init's trigger
# (adbd restarts and listens on 5555), so the test can tell when a running ADB would drop.
# Covers: on/off from a stock car in both orders, taking over adb.tcp's setup and backup,
# exact restores, Engineering Mode's switch, and refusing states it doesn't know.
#
# usage: tests/host-test.sh      (KT_SH picks the shell for the scripts; default bash, or mksh)
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$HERE/package/tweaks/adb-wifi
SH=${KT_SH:-$(command -v mksh || command -v bash)}
W=$(mktemp -d)
trap 'chmod -R u+w "$W"; rm -rf "$W"' EXIT
FAILS=0

REAL_MD5=$(command -v md5sum || command -v md5)
mkdir -p "$W/stubs"
cat > "$W/stubs/md5" <<EOF
#!/bin/sh
[ -f "\$1" ] || { echo "could not open \$1" >&2; exit 1; }
case "$REAL_MD5" in *md5sum) s=\$($REAL_MD5 "\$1" | cut -d' ' -f1) ;; *) s=\$($REAL_MD5 -q "\$1") ;; esac
echo "\$s  \$1"
EOF
cat > "$W/stubs/getprop" <<'EOF'
#!/bin/sh
cat "$KT_TEST_ROOT/props/$1" 2>/dev/null
EOF
cat > "$W/stubs/setprop" <<'EOF'
#!/bin/sh
M=$KT_TEST_ROOT
echo "$1=$2" >> "$M/setprop.log"
mkdir -p "$M/props"
printf '%s' "$2" > "$M/props/$1"
case "$1" in persist.*) printf '%s' "$2" > "$M/data/property/$1"; chmod 600 "$M/data/property/$1" ;; esac
# init.daudio.rc: on property:persist.service.adb.tcp.enable=1 ... stop adbd; start adbd
if [ "$1" = persist.service.adb.tcp.enable ] && [ "$2" = 1 ]; then
    echo "adbd restarted" >> "$M/adbd.log"; "${0%/*}/listen"
fi
exit 0
EOF
cat > "$W/stubs/listen" <<'EOF'
#!/bin/sh
echo "   2: 00000000:15B3 00000000:0000 0A 00000000:00000000 00:00000000 00000000  2000        0 954 1 00000000 100 0 0 10 0" > "$KT_TEST_ROOT/proc/net/tcp"
EOF
chmod 755 "$W"/stubs/*
export KT_TEST_ROOT=$W/root KT_TEST_PATH=$W/stubs:/usr/bin:/bin:/usr/sbin:/sbin
M=$KT_TEST_ROOT
EN=persist.service.adb.tcp.enable
PORT=persist.adb.tcp.port
HIDE=system/etc/permissions/com.hkmc.software.engineermode.adb_hide.xml

stock() {   # a head unit as Kia ships it: ADB off
    rm -rf "$M"
    mkdir -p $M/system/etc/permissions $M/system/xbin $M/data/property $M/data/nemesis/backup $M/props $M/proc/net
    printf '# begin build properties\nro.build.product=CVEV.USA.0000.V015.012.260507\nro.product.model=daudio\n# end build properties\nro.protocol.version=14\n' > $M/system/build.prop
    printf '<permissions>\n        <feature name="com.hkmc.software.engineermode.adb_hide" />\n</permissions>\n' > $M/$HIDE
    printf '#!/bin/sh\nexit 0\n' > $M/system/xbin/nemesis; chmod 755 $M/system/xbin/nemesis
    printf 'host' > $M/data/property/persist.sys.usb.config; printf 'host' > $M/props/persist.sys.usb.config
    : > $M/proc/net/tcp
    cp $M/system/build.prop "$W/stock.bp"; cp $M/$HIDE "$W/stock.hide"
}
# the car as adb.tcp (and then HMG Leafia Plus, detached) left it, with ADB running
adbtcp_car() {
    stock
    A=$M/data/nemesis/backup/adb.tcp
    mkdir -p $A $M/data/nemesis/backup/leafia-detached
    cp $M/system/build.prop $A/build.prop
    for k in ro.adb.secure $EN service.adb.tcp.port; do echo absent > $A/bp.$k.absent; done
    echo unset > $A/gp.$EN.unset; echo unset > $A/gp.service.adb.tcp.port.unset
    cp $M/$HIDE $A/adb_hide.xml; echo 1 > $A/saved
    printf 'ro.adb.secure=0\npersist.service.adb.tcp.enable=1\nservice.adb.tcp.port=5555\n' >> $M/system/build.prop
    rm $M/$HIDE
    printf 'enable\nport\n' > $M/data/nemesis/backup/leafia-detached/wireless.carplay.aa.adb
    printf 1 > $M/data/property/$EN; printf 5555 > $M/data/property/$PORT
    printf 1 > $M/props/$EN; printf 5555 > $M/props/$PORT; printf 5555 > $M/props/service.adb.tcp.port
    "$W/stubs/listen"
}
# a head unit start: runtime props from build.prop then /data/property; adbd per init's trigger
restart() {
    rm -rf $M/props; mkdir -p $M/props; : > $M/proc/net/tcp
    while IFS= read -r l; do case "$l" in *=*) printf '%s' "${l#*=}" > "$M/props/${l%%=*}" ;; esac; done < $M/system/build.prop
    for f in $M/data/property/*; do [ -f "$f" ] && cp "$f" "$M/props/${f##*/}"; done
    [ "$(cat $M/props/$EN 2>/dev/null)" = 1 ] && "$W/stubs/listen"
    : > $M/setprop.log; : > $M/adbd.log
}
tree() { (cd "$M" && find system data -type f ! -name nemesis | sort | while read -r f; do echo "$(md5of "$f") $f"; done; for p in $EN $PORT; do echo "now $p=[$(cat props/$p 2>/dev/null)]"; done); }
md5of() { if command -v md5sum >/dev/null; then md5sum "$1" | cut -d' ' -f1; else md5 -q "$1"; fi; }

ok() { echo "  ok: $1"; }
bad() { echo "  FAILED: $1"; FAILS=$((FAILS + 1)); }
st() { "$SH" $T/status.sh; }
expect() { local s; s=$(st); case "$s" in "$1") ok "status: $s" ;; *) bad "status: $s (want $1)" ;; esac; }
run() {   # <enable|disable> [fail]
    if "$SH" $T/$1.sh > "$W/log" 2>&1; then
        [ "$2" = fail ] && { bad "$1 should have failed"; cat "$W/log"; } || ok "$1: $(cat "$W/log" | tr '\n' ' ')"
    else
        [ "$2" = fail ] && ok "$1 refused: $(cat "$W/log" | tr '\n' ' ')" || { bad "$1"; cat "$W/log"; }
    fi
}
no_restart() { [ -s $M/adbd.log ] && bad "adbd was restarted (a running ADB session would drop)" || ok "adbd not restarted"; }
no_setprop() { [ -s $M/setprop.log ] && { bad "setprop was called: $(cat $M/setprop.log | tr '\n' ' ')"; } || ok "no setprop"; }
same() { cmp -s "$1" "$2" && ok "$3" || { bad "$3"; diff "$1" "$2" || true; }; }
absent() { [ ! -e "$M/$1" ] && ok "$1 absent" || bad "$1 is there"; }
is_stock_files() {
    same "$W/stock.bp" $M/system/build.prop "build.prop is stock, byte for byte"
    same "$W/stock.hide" $M/$HIDE "adb_hide.xml is back, byte for byte"
    absent data/property/$EN; absent data/property/$PORT
    absent data/nemesis/backup/tweaks.adb/adb-wifi
}

echo "A. stock car: on, off, on, off"
stock; restart; expect "off"
run enable; expect "on ADB over Wi-Fi is on"
[ "$(cat $M/data/property/$EN)" = 1 ] && [ "$(cat $M/data/property/$PORT)" = 5555 ] && ok "props saved without a newline" || bad "saved props"
absent $HIDE
same "$W/stock.bp" $M/system/build.prop "build.prop untouched"
: > $M/setprop.log; : > $M/adbd.log
run enable; no_setprop; no_restart
run disable; expect "off ADB stays on until the next restart"
grep -x "$EN=0" $M/setprop.log >/dev/null && ok "switch set to 0, as Engineering Mode does" || bad "switch not set to 0"
is_stock_files
restart; expect "off"
run enable; expect "on ADB over Wi-Fi is on"
restart; expect "on ADB over Wi-Fi is on"
run disable; restart; expect "off"; is_stock_files
run disable

echo "B. the car as adb.tcp left it: reads on, installing runs nothing, take-over, off, on, off"
adbtcp_car; : > $M/setprop.log; : > $M/adbd.log
expect "on ADB over Wi-Fi is on"
tree > "$W/before"
"$SH" $HERE/package/lib/adb-adopt.sh > "$W/log" 2>&1 && ok "adb-adopt.sh" || { bad "adb-adopt.sh"; cat "$W/log"; }
[ -f $M/data/nemesis/backup/tweaks.adb/adb-wifi/$PORT.unset ] && ok "port was unset before Leafia" || bad "port record"
run enable; no_setprop; no_restart
tree | grep -v 'backup/tweaks.adb' > "$W/after"; grep -v 'backup/tweaks.adb' "$W/before" | diff - "$W/after" > /dev/null && ok "nothing else changed" || { bad "files changed"; diff "$W/before" "$W/after"; }
run disable; no_restart; expect "off ADB stays on until the next restart"
is_stock_files
restart; expect "off"
run enable; expect "on ADB over Wi-Fi is on"; restart; expect "on ADB over Wi-Fi is on"
run disable; restart; expect "off"; is_stock_files

echo "B2. adb.tcp's setup turned off without the take-over step (backup read at once)"
adbtcp_car
run disable; is_stock_files

echo "C. Engineering Mode's switch shows up in the status"
stock; restart; run enable
"$W/stubs/setprop" $EN 0; : > $M/proc/net/tcp    # Engineering Mode off: setprop 0, stop adbd
expect "off"
"$W/stubs/setprop" $EN 1              # Engineering Mode on
expect "on ADB over Wi-Fi is on"

echo "D. after adb.tcp's own undo (switch still 1 until the restart, its file gone, files stock): repaired without restarting adbd"
adbtcp_car; rm $M/data/property/$EN; cp "$W/stock.bp" $M/system/build.prop; cp "$W/stock.hide" $M/$HIDE; : > $M/setprop.log; : > $M/adbd.log
expect "off ADB stays on until the next restart"
run enable; no_setprop; no_restart; expect "on ADB over Wi-Fi is on"

echo "E. states it doesn't know are left alone"
adbtcp_car; echo "ro.something=else" >> $M/system/build.prop; tree > "$W/before"
run disable fail; tree | grep -v 'backup/tweaks.adb' > "$W/after"; grep -v 'backup/tweaks.adb' "$W/before" | diff - "$W/after" >/dev/null && ok "nothing changed" || bad "changed"
expect "on ADB over Wi-Fi is on"
adbtcp_car; rm $M/data/nemesis/backup/adb.tcp/bp.ro.adb.secure.absent; printf 'ro.adb.secure=1\n' > $M/data/nemesis/backup/adb.tcp/bp.ro.adb.secure.line
run disable fail
adbtcp_car; rm -rf $M/data/nemesis/backup/adb.tcp
run disable fail; expect "on ADB over Wi-Fi is on"
stock; restart; printf 'persist.service.adb.tcp.enable=1\n' >> $M/system/build.prop; printf 0 > $M/data/property/$EN; printf 0 > $M/props/$EN
run enable fail; absent data/nemesis/backup/tweaks.adb/adb-wifi
stock; restart; chmod 000 $M/data/property; expect "error can't read the saved settings"; chmod 700 $M/data/property

[ $FAILS = 0 ] && echo "all passed ($SH)" || { echo "$FAILS failed ($SH)"; exit 1; }
