# tweaks.adb, tweak adb-wifi: shared by enable.sh, disable.sh, status.sh and lib/adb-adopt.sh
# (sourced; $D is this folder). Written for the head unit's mksh + toolbox: no printf, sed, awk,
# head, tail or tr, and no echo of arbitrary text (mksh's echo expands backslashes).
#
# What "on" means on this firmware (CVEV.USA 260507), from its init scripts and /sbin/adbd:
# - persist.service.adb.tcp.enable=1 is the only thing that starts adbd while USB is in host
#   mode: init.daudio.rc runs set_adb_ip, set_adb_port, "stop adbd" and "start adbd" on it.
# - adbd listens on TCP when service.adb.tcp.port, or failing that persist.adb.tcp.port, is a
#   port number. set_adb_port sets the first at every start, but it can lose the race with
#   adbd, so persist.adb.tcp.port=5555 is set as well.
# - The adb_hide feature file only hides Engineering Mode's ADB switch. Removing it shows the
#   switch, a way to turn ADB back on from the screen.
# - Engineering Mode's "ADB TCP" switch (com.hkmc.system.app.engineering, ADBSetting) does the
#   same through MiscService.setSystem: on = setprop persist.service.adb.tcp.enable 1; off =
#   setprop ... 0 and "stop adbd". Its screen shows on when getprop says "1". So "on" here is
#   that prop being 1 now (what Engineering Mode shows) and in its saved file (the next start).
# - ro.adb.secure is ignored: default.prop sets it first (ro.* can't change) and this adbd
#   never reads it or checks keys. So this tweak doesn't touch it.
#
# The backup ($B) holds the state before the tweak: for each prop either <name>.value (the
# /data/property file) or <name>.unset; adb_hide.xml or adb_hide.absent; build.prop.stock when
# taken over from the community package adb.tcp, which also added three lines to build.prop.
# KT_TEST_ROOT: host tests.
R=${KT_TEST_ROOT:-}
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
[ -n "$R" ] && PATH=$KT_TEST_PATH:$PATH
BP=$R/system/build.prop
HIDE=$R/system/etc/permissions/com.hkmc.software.engineermode.adb_hide.xml
PROPS=$R/data/property
NET=$R/proc/net/tcp
B=$R/data/nemesis/backup/tweaks.adb/adb-wifi
ADBTCP=$R/data/nemesis/backup/adb.tcp
LEAFIA_REC=$R/data/nemesis/backup/leafia-detached/wireless.carplay.aa.adb
LEAFIA_LIVE=$R/data/nemesis/wireless.carplay.aa.adb
NEMESIS=$R/system/xbin/nemesis
EN=persist.service.adb.tcp.enable
PORT=persist.adb.tcp.port
# the lines adb.tcp appended to build.prop
ADBTCP_LINES='^(ro\.adb\.secure|persist\.service\.adb\.tcp\.enable|service\.adb\.tcp\.port)='

sum() { [ -f "$1" ] && md5 "$1" 2>/dev/null | while read -r s f; do echo "$s"; done; }
fail() { echo "FAIL: $1"; $NEMESIS remount ro >/dev/null 2>&1; exit 1; }

# a key's first value in build.prop, or nothing
bp_value() {
    local l
    while IFS= read -r l || [ -n "$l" ]; do
        case "$l" in "$1="*) echo "${l#*=}"; return ;; esac
    done < "$BP"
}
# a persistent prop as it will be after the next start: its /data/property file, else build.prop
boot_value() {
    if [ -f "$PROPS/$1" ]; then cat "$PROPS/$1"; else bp_value "$1"; fi
}
is_on() { [ "$(getprop $EN)" = 1 ] && [ "$(boot_value $EN)" = 1 ]; }
has_port() { [ -n "$(boot_value $PORT)" ] || [ -n "$(bp_value service.adb.tcp.port)" ]; }
# adbd is listening on 0.0.0.0:5555 right now
listening() { grep ' 00000000:15B3 00000000:0000 0A ' "$NET" >/dev/null 2>&1; }
# build.prop has any of the lines adb.tcp adds
bp_has_lines() { grep -E "$ADBTCP_LINES" "$BP" >/dev/null 2>&1; }

# write a persistent prop's file without setprop (no init trigger, no adbd restart). The file
# holds the bare value: Android reads all of it, so a trailing newline would become part of it.
put_prop_file() {   # <name> <value>
    rm -f "$PROPS/.$1.kt"
    echo -n "$2" > "$PROPS/.$1.kt" && chmod 600 "$PROPS/.$1.kt" && mv "$PROPS/.$1.kt" "$PROPS/$1" \
        || { rm -f "$PROPS/.$1.kt"; return 1; }
}
put_prop_from() {   # <name> <file with the bare value>
    rm -f "$PROPS/.$1.kt"
    cp "$2" "$PROPS/.$1.kt" && chmod 600 "$PROPS/.$1.kt" && mv "$PROPS/.$1.kt" "$PROPS/$1" \
        || { rm -f "$PROPS/.$1.kt"; return 1; }
}

# the state before this tweak: once, from adb.tcp's backup if there is one, else from now
backup_taken() { [ -f "$B/complete" ]; }
adbtcp_backup() {   # prints adb.tcp's backup folder, if a complete one is there
    local d
    for d in "$ADBTCP" "$ADBTCP.detached"; do
        { [ -s "$d/saved" ] || [ -s "$d/saved.detached" ]; } && [ -s "$d/build.prop" ] && { echo "$d"; return; }
    done
}
take_backup() {
    local A T k
    backup_taken && return 0
    T=$B.new
    rm -rf "$T"
    mkdir -p "$T" || { echo "can't write $T"; return 1; }
    A=$(adbtcp_backup)
    if [ -n "$A" ]; then
        # adb.tcp appended its three lines (".absent"); a backup of lines it replaced isn't handled
        for k in ro.adb.secure persist.service.adb.tcp.enable service.adb.tcp.port; do
            [ -f "$A/bp.$k.absent" ] || { echo "adb.tcp's backup has an unexpected build.prop record ($k)"; rm -rf "$T"; return 1; }
        done
        grep -v -E "$ADBTCP_LINES" "$BP" > "$T/bp.check" 2>/dev/null
        [ "$(sum "$T/bp.check")" = "$(sum "$A/build.prop")" ] \
            || { echo "build.prop isn't adb.tcp's snapshot plus its lines - leaving it alone"; rm -rf "$T"; return 1; }
        rm -f "$T/bp.check"
        cp "$A/build.prop" "$T/build.prop.stock" || { rm -rf "$T"; return 1; }
        if [ -f "$A/gp.$EN.unset" ]; then : > "$T/$EN.unset"
        elif [ -s "$A/gp.$EN" ]; then echo -n "$(cat "$A/gp.$EN")" > "$T/$EN.value"
        else echo "adb.tcp's backup has no record of $EN"; rm -rf "$T"; return 1
        fi
        if [ -s "$A/adb_hide.xml" ]; then cp "$A/adb_hide.xml" "$T/adb_hide.xml" || { rm -rf "$T"; return 1; }
        elif [ -f "$A/adb_hide.xml.absent" ]; then : > "$T/adb_hide.absent"
        else echo "adb.tcp's backup has no record of adb_hide"; rm -rf "$T"; return 1
        fi
        echo "adb.tcp ($A)" > "$T/source"
    else
        # from the live state: only from off, with build.prop as Kia ships it
        is_on && { echo "ADB over Wi-Fi was turned on by something else and there's no backup of before"; rm -rf "$T"; return 1; }
        bp_has_lines && { echo "build.prop has ADB lines from something else - leaving it alone"; rm -rf "$T"; return 1; }
        if [ -f "$PROPS/$EN" ]; then cp "$PROPS/$EN" "$T/$EN.value"; else : > "$T/$EN.unset"; fi
        if [ -f "$HIDE" ]; then cp "$HIDE" "$T/adb_hide.xml" || { rm -rf "$T"; return 1; }; else : > "$T/adb_hide.absent"; fi
        echo "live" > "$T/source"
    fi
    # persist.adb.tcp.port: HMG Leafia Plus set it (from unset) when it was installed; its detached
    # record says so. Otherwise it is whatever it is now.
    if [ ! -f "$LEAFIA_LIVE" ] && grep -x port "$LEAFIA_REC" >/dev/null 2>&1; then
        : > "$T/$PORT.unset"
    elif [ -f "$PROPS/$PORT" ]; then
        cp "$PROPS/$PORT" "$T/$PORT.value"
    else
        : > "$T/$PORT.unset"
    fi
    : > "$T/complete"
    mkdir -p "${B%/*}" && rm -rf "$B" && mv "$T" "$B" || { echo "can't write $B"; return 1; }
}

# put a persistent prop back as the backup has it, by its file only (no init trigger)
restore_prop() {   # <name>
    if [ -f "$B/$1.unset" ]; then
        rm -f "$PROPS/$1"
        [ ! -f "$PROPS/$1" ]
    elif [ -f "$B/$1.value" ]; then
        cmp -s "$B/$1.value" "$PROPS/$1" || put_prop_from "$1" "$B/$1.value"
    else
        return 1
    fi
}
