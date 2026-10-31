#!/bin/sh
# Host test: runs the adb-wifi tweak's scripts against a mock head unit (build.prop, the
# adb_hide feature file, /data/property, /proc/net/tcp) the way the store's runner runs them:
# with $TWEAK_ID, $TWEAK_DIR and $TWEAK_DATA set, /system read-only to them, and a stand-in kt
# (tests/fake-kt.sh) that checks every call against the tweak's need= lines and keeps the
# runner's journal. Turning the tweak off is that journal replayed. setprop is only reachable
# through kt and is logged; setting persist.service.adb.tcp.enable to 1 plays init's trigger
# (adbd restarts and listens on 5555), so the test can tell when a running ADB would drop.
# Covers: on/off from a stock car, taking over adb.tcp's and Leafia's setup, exact restores,
# Engineering Mode's switch, and refusing states it doesn't know.
#
# usage: tests/host-test.sh      (KT_SH picks the shell for the scripts; default mksh, or bash)
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$HERE/package/tweaks/adb-wifi
SH=${KT_SH:-$(command -v mksh || command -v bash)}
W=$(mktemp -d)
trap 'chmod -R u+w "$W"; rm -rf "$W"' EXIT
FAILS=0

REAL_MD5=$(command -v md5sum || command -v md5)
md5of() { case "$REAL_MD5" in *md5sum) md5sum "$1" | cut -d' ' -f1 ;; *) "$REAL_MD5" -q "$1" ;; esac; }
mkdir -p "$W/stubs" "$W/priv"
cat >"$W/stubs/md5" <<EOF
#!/bin/sh
[ -f "\$1" ] || { echo "could not open \$1" >&2; exit 1; }
case "$REAL_MD5" in *md5sum) s=\$($REAL_MD5 "\$1" | cut -d' ' -f1) ;; *) s=\$($REAL_MD5 -q "\$1") ;; esac
echo "\$s  \$1"
EOF
cat >"$W/stubs/getprop" <<'EOF'
#!/bin/sh
cat "$KT_TEST_ROOT/props/$1" 2>/dev/null
EOF
# only kt has setprop
cat >"$W/priv/setprop" <<'EOF'
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
cat >"$W/priv/listen" <<'EOF'
#!/bin/sh
echo "   2: 00000000:15B3 00000000:0000 0A 00000000:00000000 00:00000000 00000000  2000        0 954 1 00000000 100 0 0 10 0" > "$KT_TEST_ROOT/proc/net/tcp"
EOF
cp "$HERE/tests/fake-kt.sh" "$W/stubs/kt"
chmod 755 "$W"/stubs/* "$W"/priv/*
export KT_TEST_ROOT="$W/root" KT_JOURNAL="$W/journal" KT_LOG="$W/kt.log" KT_TEST_SETPROP="$W/priv/setprop"
export PATH="$W/stubs:/usr/bin:/bin:/usr/sbin:/sbin"
M=$KT_TEST_ROOT
EN=persist.service.adb.tcp.enable
PORT=persist.adb.tcp.port
HIDE=system/etc/permissions/com.hkmc.software.engineermode.adb_hide.xml
# the stock files: build.prop and adb_hide.xml as this firmware ships them have these md5s
# (common.sh); the mock uses stand-ins, so the tweak.conf and common.sh md5s are swapped for theirs
STOCK_BP='# begin build properties\nro.build.product=CVEV.USA.0000.V015.012.260507\nro.product.model=daudio\n# end build properties\nro.protocol.version=14\n'
STOCK_HIDE='<permissions>\n        <feature name="com.hkmc.software.engineermode.adb_hide" />\n</permissions>\n'
printf '%b' "$STOCK_BP" >"$W/stock.bp"
printf '%b' "$STOCK_HIDE" >"$W/stock.hide"
# the pack, with the mock's stock md5s in place of the car's
P=$W/pack
cp -R "$HERE/package/." "$P/"
T=$P/tweaks/adb-wifi
for f in "$T/tweak.conf" "$T/common.sh" "$P/lib/adb-adopt.sh"; do
    sed -e "s/30e9666d146efe83697f155574d50d30/$(md5of "$W/stock.bp")/" \
        -e "s/bb94dd63efd6d3494834e649653f795f/$(md5of "$W/stock.hide")/" "$f" >"$f.t"
    mv "$f.t" "$f"
done

stock() {   # a head unit as it ships: ADB off; a runner with nothing recorded
    [ -d "$M" ] && chmod -R u+w "$M"
    rm -rf "$M" "$KT_JOURNAL" "$W/data"
    : >"$KT_LOG"
    mkdir -p "$M/system/etc/permissions" "$M/data/property" "$M/data/nemesis/backup" "$M/props" "$M/proc/net" "$W/data"
    cp "$W/stock.bp" "$M/system/build.prop"
    cp "$W/stock.hide" "$M/$HIDE"
    mkdir -p "$M/system/bin"
    printf '#!/bin/sh\necho "toolbox $*" >> %s/toolbox.log\n' "$M" >"$M/system/bin/toolbox"
    chmod 755 "$M/system/bin/toolbox"
    ln -s toolbox "$M/system/bin/ifconfig"
    printf 'host' >"$M/data/property/persist.sys.usb.config"
    printf 'host' >"$M/props/persist.sys.usb.config"
    : >"$M/proc/net/tcp"
    ro
}
ro() { find "$M/system" -type d -exec chmod a-w {} +; }
rw() { find "$M/system" -type d -exec chmod u+w {} +; }
# the car as adb.tcp (and then HMG Leafia Plus, detached) left it, with ADB running
adbtcp_car() {
    stock
    rw
    A=$M/data/nemesis/backup/adb.tcp
    mkdir -p "$A" "$M/data/nemesis/backup/leafia-detached"
    cp "$M/system/build.prop" "$A/build.prop"
    for k in ro.adb.secure $EN service.adb.tcp.port; do echo absent >"$A/bp.$k.absent"; done
    echo unset >"$A/gp.$EN.unset"
    echo unset >"$A/gp.service.adb.tcp.port.unset"
    cp "$M/$HIDE" "$A/adb_hide.xml"
    echo 1 >"$A/saved"
    printf 'ro.adb.secure=0\npersist.service.adb.tcp.enable=1\nservice.adb.tcp.port=5555\n' >>"$M/system/build.prop"
    rm "$M/$HIDE"
    ro
    printf 'enable\nport\n' >"$M/data/nemesis/backup/leafia-detached/wireless.carplay.aa.adb"
    printf 1 >"$M/data/property/$EN"
    printf 5555 >"$M/data/property/$PORT"
    printf 1 >"$M/props/$EN"
    printf 5555 >"$M/props/$PORT"
    printf 5555 >"$M/props/service.adb.tcp.port"
    "$W/priv/listen"
}
# a head unit start: runtime props from build.prop then /data/property; adbd per init's trigger
restart() {
    rm -rf "$M/props"
    mkdir -p "$M/props"
    : >"$M/proc/net/tcp"
    while IFS= read -r l; do case "$l" in *=*) printf '%s' "${l#*=}" >"$M/props/${l%%=*}" ;; esac; done <"$M/system/build.prop"
    for f in "$M"/data/property/*; do if [ -f "$f" ]; then cp "$f" "$M/props/${f##*/}"; fi; done
    if [ "$(cat "$M/props/$EN" 2>/dev/null)" = 1 ]; then "$W/priv/listen"; fi
    : >"$M/setprop.log"
    : >"$M/adbd.log"
}
tree() {
    (cd "$M" && find system data -type f ! -path system/bin/ifconfig | sort | while read -r f; do echo "$(md5of "$f") $f"; done
     for p in $EN $PORT; do echo "now $p=[$(cat "props/$p" 2>/dev/null)]"; done)
}

ok() { echo "  ok: $1"; }
bad() {
    echo "  FAILED: $1"
    FAILS=$((FAILS + 1))
}
as() {
    mkdir -p "$W/data/adb-wifi"
    TWEAK_ID=adb-wifi TWEAK_DIR=$T TWEAK_DATA=$W/data/adb-wifi "$@"
}
st() { as "$SH" "$T/status.sh"; }
expect() {
    s=$(st)
    if [ "$s" = "$1" ]; then ok "status: $s"; else bad "status: $s (want $1)"; fi
}
on() {   # [fail]
    if as "$SH" "$T/enable.sh" >"$W/log" 2>&1; then
        if [ "$1" = fail ]; then
            bad "on should have failed"
            cat "$W/log"
        else
            ok "on: $(tr '\n' ' ' <"$W/log")"
        fi
    elif [ "$1" = fail ]; then
        ok "on refused: $(tr '\n' ' ' <"$W/log")"
    else
        bad "on"
        cat "$W/log"
    fi
}
off() {   # the runner replays the journal
    as kt --off adb-wifi
    ok "off"
}
no_restart() { if [ -s "$M/adbd.log" ]; then bad "adbd was restarted (a running ADB session would drop)"; else ok "adbd not restarted"; fi; }
# saving the port (enable.sh) sets the value it already has: nothing else may be set
no_setprop() {
    if grep -qv "^$PORT=5555\$" "$M/setprop.log" 2>/dev/null; then bad "setprop was called: $(tr '\n' ' ' <"$M/setprop.log")"; else ok "no setprop but the saved port"; fi
}
same() {
    if cmp -s "$1" "$2"; then ok "$3"; else
        bad "$3"
        diff "$1" "$2" || true
    fi
}
absent() { if [ ! -e "$M/$1" ]; then ok "$1 absent"; else bad "$1 is there"; fi; }
is_stock_files() {
    same "$W/stock.bp" "$M/system/build.prop" "build.prop is stock, byte for byte"
    same "$W/stock.hide" "$M/$HIDE" "adb_hide.xml is stock, byte for byte"
    absent "data/property/$EN"
    absent "data/property/$PORT"
}
declared() { if grep DENIED "$KT_LOG"; then bad "kt calls outside the needs"; else ok "every kt call was declared"; fi; }

echo "A. stock car: on, off, on, off"
stock
restart
expect "off"
on
expect "on ADB over Wi-Fi is on"
if [ "$(cat "$M/data/property/$EN")" = 1 ] && [ "$(cat "$M/data/property/$PORT")" = 5555 ]; then ok "props saved"; else bad "saved props"; fi
same "$P/tweaks/adb-wifi/adb_hide.shown.xml" "$M/$HIDE" "adb_hide.xml has no feature: the switch shows"
same "$W/stock.bp" "$M/system/build.prop" "build.prop untouched"
: >"$M/setprop.log"
: >"$M/adbd.log"
on
no_setprop
no_restart
off
expect "off ADB stays on until the next restart"
if [ "$(cat "$M/props/$EN" 2>/dev/null)" != 1 ]; then ok "Engineering Mode's switch shows off"; else bad "switch still 1"; fi
is_stock_files
restart
expect "off"
on
expect "on ADB over Wi-Fi is on"
restart
expect "on ADB over Wi-Fi is on"
off
restart
expect "off"
is_stock_files
declared

echo "B. the car as adb.tcp left it: reads on, taken over without a change, off, on, off"
adbtcp_car
: >"$M/setprop.log"
: >"$M/adbd.log"
expect "on ADB over Wi-Fi is on"
tree >"$W/before"
on
no_setprop
no_restart
tree >"$W/after"
if diff "$W/before" "$W/after" >/dev/null; then ok "nothing changed"; else
    bad "files changed"
    diff "$W/before" "$W/after" || true
fi
off
no_restart
expect "off ADB stays on until the next restart"
is_stock_files
restart
expect "off"
on
expect "on ADB over Wi-Fi is on"
restart
expect "on ADB over Wi-Fi is on"
off
restart
expect "off"
is_stock_files
declared

echo "C. Engineering Mode's switch shows up in the status"
stock
restart
on
"$W/priv/setprop" $EN 0
: >"$M/proc/net/tcp" # Engineering Mode off: setprop 0, stop adbd
expect "off"
"$W/priv/setprop" $EN 1 # Engineering Mode on
expect "on ADB over Wi-Fi is on"

echo "D. turned on in Engineering Mode first: taken over without restarting adbd; off sets the switch to 0"
stock
restart
"$W/priv/setprop" $EN 1
: >"$M/setprop.log"
: >"$M/adbd.log"
on
no_restart
expect "on ADB over Wi-Fi is on"
off
if [ "$(cat "$M/props/$EN")" = 0 ]; then ok "switch back to 0, as Engineering Mode's own switch does"; else bad "switch is $(cat "$M/props/$EN")"; fi
no_restart
declared

echo "E. states it doesn't know are left alone"
adbtcp_car
rw
echo "ro.something=else" >>"$M/system/build.prop"
ro
tree >"$W/before"
on fail
tree >"$W/after"
if diff "$W/before" "$W/after" >/dev/null; then ok "nothing changed"; else bad "changed"; fi
adbtcp_car
rm "$M/data/nemesis/backup/adb.tcp/bp.ro.adb.secure.absent"
printf 'ro.adb.secure=1\n' >"$M/data/nemesis/backup/adb.tcp/bp.ro.adb.secure.line"
on fail
stock
restart
rw
printf 'persist.service.adb.tcp.enable=1\n' >>"$M/system/build.prop"
ro
on fail
declared

echo "F. on again after off, with adb.tcp's old backup still there"
adbtcp_car
on
off
expect "off ADB stays on until the next restart"
restart
on
expect "on ADB over Wi-Fi is on"
off
is_stock_files
declared

echo "the ifconfig wrapper: ADB and wireless projection together"
stock
printf '#!/bin/sh\necho "eth0     UP    192.168.0.123/24  0x00001043 0a:d0:0d:00:0b:ad"\n' >"$W/stubs/netcfg"
chmod 755 "$W/stubs/netcfg"
on
if [ ! -h "$M/system/bin/ifconfig" ] && cmp -s "$M/system/bin/ifconfig" "$HERE/package/lib/ifconfig" && [ -x "$M/system/bin/ifconfig" ]; then
    ok "wrapper installed, executable"
else
    bad "wrapper not installed"
fi
if grep -qx 'adb-wifi service start set_adb_ip' "$KT_LOG"; then ok "stock set_adb_ip re-run through the wrapper"; else bad "set_adb_ip not re-run"; fi
# the wrapper itself: only the stock call changes
sed "s#/system/bin/toolbox#$M/system/bin/toolbox#" "$HERE/package/lib/ifconfig" >"$W/ifc"
: >"$M/toolbox.log"
sh "$W/ifc" eth0 192.168.0.123
sh "$W/ifc" usb0 up
sh "$W/ifc" eth0 192.168.0.123 netmask 255.255.255.255
if printf 'toolbox ifconfig eth0 192.168.0.123 netmask 255.255.255.255\ntoolbox ifconfig usb0 up\ntoolbox ifconfig eth0 192.168.0.123 netmask 255.255.255.255\n' | diff - "$M/toolbox.log" >/dev/null; then
    ok "wrapper: /32 for set_adb_ip's call, everything else unchanged"
else
    bad "wrapper calls"
fi
off
if [ -h "$M/system/bin/ifconfig" ] && [ "$(readlink "$M/system/bin/ifconfig")" = toolbox ]; then ok "toolbox link back"; else bad "link not restored"; fi
rm -f "$W/stubs/netcfg"
declared

echo "the port is saved even when this boot already has it"
stock
printf 5555 >"$M/props/$PORT"
on
if [ "$(cat "$M/data/property/$PORT" 2>/dev/null)" = 5555 ]; then ok "saved for the next start"; else bad "port not saved"; fi
declared

if [ $FAILS = 0 ]; then echo "all passed ($SH)"; else
    echo "$FAILS failed ($SH)"
    exit 1
fi
