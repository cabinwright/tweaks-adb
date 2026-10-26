#!/system/bin/sh
# tweaks.adb: take over the community package adb.tcp's backup (and HMG Leafia Plus's detached
# record of persist.adb.tcp.port) into this pack's backup, /data/nemesis/backup/tweaks.adb.
# Writes nothing else. Run as root before detaching adb.tcp (docs/migration.md).
D=${0%/*}/../tweaks/adb-wifi
. $D/common.sh
if backup_taken; then echo "already taken over: $B ($(cat "$B/source"))"; exit 0; fi
[ -n "$(adbtcp_backup)" ] || { echo "FAIL: no complete adb.tcp backup in $ADBTCP"; exit 1; }
take_backup || { echo "FAIL: not taken over"; exit 1; }
echo "taken over into $B:"
ls "$B"
