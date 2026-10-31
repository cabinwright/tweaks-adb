# tweaks.adb, tweak adb-wifi: shared by enable.sh, status.sh and lib/adb-adopt.sh (sourced; $D
# is this folder). Written for the head unit's mksh + toolbox: no printf, sed, awk, head, tail or
# tr, and no echo of arbitrary text (mksh's echo expands backslashes).
#
# What "on" means on this firmware (CVEV.USA 260507), from its init scripts and /sbin/adbd:
# - persist.service.adb.tcp.enable=1 is the only thing that starts adbd while USB is in host
#   mode: init.daudio.rc runs set_adb_ip, set_adb_port, "stop adbd" and "start adbd" on it.
# - adbd listens on TCP when service.adb.tcp.port, or failing that persist.adb.tcp.port, is a
#   port number. set_adb_port sets the first at every start, but it can lose the race with
#   adbd, so persist.adb.tcp.port=5555 is set as well.
# - The adb_hide feature file only hides Engineering Mode's ADB switch. Replacing it with one
#   that declares no feature shows the switch, a way to turn ADB back on from the screen.
# - Engineering Mode's "ADB TCP" switch (com.hkmc.system.app.engineering, ADBSetting) does the
#   same through MiscService.setSystem: on = setprop persist.service.adb.tcp.enable 1; off =
#   setprop ... 0 and "stop adbd". Its screen shows on when getprop says "1". So "on" here is
#   that prop being 1, and kt prop set does what the switch does; no binder call is needed.
# - set_adb_ip runs "ifconfig eth0 192.168.0.123", a /24 inside the projection hotspot's
#   192.168.0.0/24: replies to phones would leave through eth0. lib/ifconfig, in place of the
#   ifconfig -> toolbox link, makes that one call a /32, so ADB and wireless projection work
#   together. An address already given this boot is narrowed by running set_adb_ip again.
# - ro.adb.secure is ignored: default.prop sets it first (ro.* can't change) and this adbd
#   never reads it or checks keys. So this tweak doesn't touch it.
#
# Runs as the tweak's own uid and changes things only through kt; the runner keeps what was
# there before and puts it back when the tweak is turned off. KT_TEST_ROOT: host tests.
R=${KT_TEST_ROOT:-}
PATH=$PATH:/system/bin:/system/xbin
BP=/system/build.prop
HIDE=/system/etc/permissions/com.hkmc.software.engineermode.adb_hide.xml
NET=$R/proc/net/tcp
EN=persist.service.adb.tcp.enable
PORT=persist.adb.tcp.port
SUM_HIDE=bb94dd63efd6d3494834e649653f795f   # adb_hide.xml as this firmware ships it
IFC=/system/bin/ifconfig
SUM_IFC=41cd6ec48b1606dfdaeb62640015d408   # lib/ifconfig
# the lines adb.tcp appended to build.prop
ADBTCP_LINES='^(ro\.adb\.secure|persist\.service\.adb\.tcp\.enable|service\.adb\.tcp\.port)='

sum() { [ -f "$1" ] && md5 "$1" 2>/dev/null | while read -r s _; do echo "$s"; done; }
fail() { echo "FAIL: $1"; exit 1; }

# a key's first value in build.prop, or nothing
bp_value() {
    local l
    while IFS= read -r l || [ -n "$l" ]; do
        case "$l" in "$1="*) echo "${l#*=}"; return ;; esac
    done < "$R$BP"
}
is_on() { [ "$(getprop $EN)" = 1 ]; }
has_port() { [ -n "$(getprop $PORT)" ] || [ -n "$(bp_value service.adb.tcp.port)" ]; }
# adbd is listening on 0.0.0.0:5555 right now
listening() { grep ' 00000000:15B3 00000000:0000 0A ' "$NET" >/dev/null 2>&1; }
# build.prop has any of the lines adb.tcp adds
bp_has_lines() { grep -E "$ADBTCP_LINES" "$R$BP" >/dev/null 2>&1; }
# Engineering Mode's ADB switch is hidden: the feature file as it ships
is_hidden() { [ "$(sum "$R$HIDE")" = $SUM_HIDE ]; }
# ifconfig is the stock link to toolbox
ifc_stock() {
    local l
    [ -h "$R$IFC" ] || return 1
    l=$(ls -l "$R$IFC")
    case "$l" in *"-> toolbox") return 0 ;; esac
    return 1
}
ifc_ours() { [ ! -h "$R$IFC" ] && [ "$(sum "$R$IFC")" = $SUM_IFC ]; }
# eth0 has the stock ADB address as a /24 right now
eth0_clashes() {
    netcfg 2>/dev/null | while read -r i _ a _; do
        [ "$i" = eth0 ] && [ "$a" = 192.168.0.123/24 ] && echo y
    done
}

# the plan: what to do, gathered first so that a check that fails changes nothing
STEPS=
step() { STEPS="$STEPS $1:$2:$3"; }   # <put|exe|adopt|prop|port|propadopt> <file or prop> <file or value>
run_steps() {
    local s v n f
    for s in $STEPS; do
        v=${s%%:*}; s=${s#*:}; n=${s%%:*}; f=${s#*:}
        case $v in
            put) kt file replace "$n" "$f" || return 1 ;;
            exe) kt file replace "$n" "$f" 0755 || return 1 ;;
            adopt) kt file adopt "$n" "$f" || return 1 ;;
            prop | port) kt prop set "$n" "$f" || return 1 ;;
            propadopt) kt prop adopt "$n" "$f" || return 1 ;;
        esac
    done
}
