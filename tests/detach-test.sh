#!/bin/sh
# Checks the adb.tcp detach in docs/migration.md by running adb.tcp's own preuninstall hook
# against a mock of the car as adb.tcp left it, with its backup's "saved" marker moved away.
# adb.tcp's scripts aren't part of this repository: pass a copy of the installed package
# (adb pull /data/nemesis/apps/adb.tcp). Its absolute paths are pointed at the mock with sed.
# Passes if the hook exits non-zero having written nothing but its log, and called no setprop
# (so no "ctl.restart adbd").
#
# usage: tests/detach-test.sh <adb.tcp package dir>
set -e
SRC=$(cd "$1" && pwd)
SH=${KT_SH:-$(command -v mksh || command -v bash)}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
M=$W/root
mkdir -p "$W/stubs" $M/system/etc/permissions $M/system/xbin $M/system/bin $M/data/property $M/data/nemesis/backup/adb.tcp
for c in setprop reboot mount; do printf '#!/bin/sh\necho "%s $*" >> %s/calls.log\n' $c "$W" > "$W/stubs/$c"; done
printf '#!/bin/sh\necho "nemesis $*" >> %s/calls.log\n' "$W" > $M/system/xbin/nemesis
printf '#!/bin/sh\necho "reboot $*" >> %s/calls.log\n' "$W" > $M/system/bin/reboot
printf '#!/bin/sh\necho unset\n' > "$W/stubs/getprop"
chmod 755 "$W"/stubs/* $M/system/xbin/nemesis $M/system/bin/reboot

# the car: adb.tcp's three lines in build.prop, adb_hide removed, its backup in place
printf 'ro.build.product=CVEV.USA.0000.V015.012.260507\nro.protocol.version=14\n' > $M/data/nemesis/backup/adb.tcp/build.prop
{ cat $M/data/nemesis/backup/adb.tcp/build.prop; printf 'ro.adb.secure=0\npersist.service.adb.tcp.enable=1\nservice.adb.tcp.port=5555\n'; } > $M/system/build.prop
B=$M/data/nemesis/backup/adb.tcp
for k in ro.adb.secure persist.service.adb.tcp.enable service.adb.tcp.port; do echo absent > $B/bp.$k.absent; done
echo unset > $B/gp.persist.service.adb.tcp.enable.unset; echo unset > $B/gp.service.adb.tcp.port.unset
printf '<permissions/>\n' > $B/adb_hide.xml; echo 1 > $B/saved
printf 1 > $M/data/property/persist.service.adb.tcp.enable; printf 5555 > $M/data/property/persist.adb.tcp.port

# the package, pointed at the mock
A=$M/data/nemesis/apps/adb.tcp
mkdir -p $A
cp -R "$SRC/." $A/
for f in $A/scripts/*.sh; do
    sed -e "s#^export PATH=.*#export PATH=$W/stubs:/usr/bin:/bin#" -e "s#/system/#$M/system/#g" -e "s#/data/#$M/data/#g" "$f" > "$f.t" && mv "$f.t" "$f"
done

# the detach: move the marker its restore checks first
mv $B/saved $B/saved.detached
snap() { (cd $M && find . -type f ! -name adb.tcp.log ! -path './data/nemesis/apps/*' | sort | while read -r f; do echo "$(cksum < "$f") $f"; done); }
snap > "$W/before"
if (cd $A && "$SH" ./scripts/preun.sh) > "$W/out" 2>&1; then rc=0; else rc=$?; fi
snap > "$W/after"
FAILS=0
echo "preun.sh exit $rc:"; sed 's/^/    /' "$W/out"
grep -q 'FAIL: no snapshot to restore' "$W/out" && echo "  ok: its restore stopped at its first check" || { echo "  FAILED: not stopped at the snapshot check"; FAILS=1; }
[ $rc != 0 ] && echo "  ok: exits non-zero (NEMESIS ignores a preuninstall's exit code and goes on)" || { echo "  FAILED: exit 0"; FAILS=1; }
diff "$W/before" "$W/after" > /dev/null && echo "  ok: no file changed (only its log was written)" || { echo "  FAILED: files changed"; diff "$W/before" "$W/after"; FAILS=1; }
[ ! -s "$W/calls.log" ] && echo "  ok: no setprop, remount or reboot" || { echo "  FAILED: calls:"; cat "$W/calls.log"; FAILS=1; }
[ $FAILS = 0 ] && echo "detach is a no-op" || exit 1
