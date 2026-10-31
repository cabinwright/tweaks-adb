# tweaks.adb: taking over what the community package adb.tcp ("TCP ADB") and HMG Leafia Plus
# set up (sourced by adb-wifi's enable.sh). Their changes are taken over with kt adopt and the
# originals from their own records, so turning adb-wifi off puts back the state from before
# them, as if this tweak had made the change. Their files are only read, through kt file md5
# where the tweak's uid may not be able to read them.
#
# adb.tcp keeps its backup in /data/nemesis/backup/adb.tcp: build.prop as it was before it
# appended three lines (one bp.<key>.absent record each), adb_hide.xml before it removed it,
# gp.persist.service.adb.tcp.enable.unset (or gp.<prop> with the value) for the switch, and a
# marker, saved (saved.detached once detached, docs/migration.md).
# Leafia's package set persist.adb.tcp.port from unset. Its record of that,
# /data/nemesis/wireless.carplay.aa.adb, lists "port"; tweaks-projection's migration keeps a
# copy in backup/leafia-detached/ when the package is detached.
ADBTCP=/data/nemesis/backup/adb.tcp
LEAFIA_REC=/data/nemesis/backup/leafia-detached/wireless.carplay.aa.adb
LEAFIA_LIVE=/data/nemesis/wireless.carplay.aa.adb
# md5 of Leafia's record when it lists the port: "port", or "enable" and "port", one per line
SUM_REC_PORT="3da8068c4487068b34fbda555a2d3f18 8376711814ddee26a2a77408db8d26f9"
SUM_EMPTY=d41d8cd98f00b204e9800998ecf8427e
SUM_BP=30e9666d146efe83697f155574d50d30     # build.prop as this firmware ships it

has() { [ -n "$(kt file md5 "$1" 2>/dev/null)" ]; }
nonempty() {
    local s
    s=$(kt file md5 "$1" 2>/dev/null)
    [ -n "$s" ] && [ "$s" != "$SUM_EMPTY" ]
}

adbtcp_backup() {   # prints adb.tcp's backup folder, if a complete one is there
    local d
    for d in "$ADBTCP" "$ADBTCP.detached"; do
        if { nonempty "$d/saved" || nonempty "$d/saved.detached"; } && nonempty "$d/build.prop"; then
            echo "$d"
            return
        fi
    done
}

# adbtcp_plan: what adb.tcp changed and is still in place, taken over; fails, changing
# nothing, on a state its backup doesn't explain
adbtcp_plan() {
    local A k
    A=$(adbtcp_backup)
    if [ -z "$A" ]; then
        if bp_has_lines; then echo "build.prop has ADB lines from something else - leaving it alone"; return 1; fi
        return 0
    fi
    if bp_has_lines; then
        # adb.tcp appended its three lines; a backup of lines it replaced isn't handled
        for k in ro.adb.secure persist.service.adb.tcp.enable service.adb.tcp.port; do
            has "$A/bp.$k.absent" || { echo "adb.tcp's backup has an unexpected build.prop record ($k)"; return 1; }
        done
        grep -v -E "$ADBTCP_LINES" "$R$BP" > "$TWEAK_DATA/bp.check" 2>/dev/null
        if [ "$(sum "$TWEAK_DATA/bp.check")" != "$SUM_BP" ] || [ "$(kt file md5 "$A/build.prop")" != "$SUM_BP" ]; then
            rm -f "$TWEAK_DATA/bp.check"
            echo "build.prop isn't adb.tcp's snapshot plus its lines - leaving it alone"
            return 1
        fi
        rm -f "$TWEAK_DATA/bp.check"
        step adopt "$BP" "$R$A/build.prop"
    fi
    if [ ! -e "$R$HIDE" ] && [ "$(kt file md5 "$A/adb_hide.xml" 2>/dev/null)" = "$SUM_HIDE" ]; then
        step adopt "$HIDE" "$R$A/adb_hide.xml"
    fi
    if is_on; then
        if has "$A/gp.$EN.unset"; then step propadopt "$EN" ""
        elif nonempty "$A/gp.$EN"; then step propadopt "$EN" "$(cat "$R$A/gp.$EN")"
        fi
    fi
}

# leafia_plan: the port Leafia's package set, taken over once that package is detached
leafia_plan() {
    local s
    [ -n "$(getprop "$PORT")" ] || return 0
    has "$LEAFIA_LIVE" && return 0
    s=$(kt file md5 "$LEAFIA_REC" 2>/dev/null)
    [ -n "$s" ] || return 0
    case " $SUM_REC_PORT " in *" $s "*) step propadopt "$PORT" "" ;; esac
}
