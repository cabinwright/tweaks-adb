#!/bin/sh
# A stand-in for the store's kt, for host tests. Installed on $PATH as "kt". It checks every call
# against the calling tweak's need= lines ($TWEAK_DIR/tweak.conf; exit 70 and a DENIED line in
# the log outside them), records each call in $KT_LOG, acts on the mock head unit under
# $KT_TEST_ROOT, and keeps a journal in $KT_JOURNAL the way the runner does:
#   - one stack of layers per file, bottom first: each layer is one tweak's change and keeps
#     what the file was before it (a copy, "absent", or a symbolic link's target);
#   - replace is allowed when the file's original (its bottom layer's, or the file itself when
#     no tweak has changed it) is one of the versions the need lists; adopt records a change
#     another package already made, with the original it is given; replace --under puts a
#     change under the other tweaks' layers, as what the file goes back to when they are off;
#   - "kt --off <tweak id>" replays a tweak's journal as turning it off does: a top layer is
#     undone (the file goes back to its original, if it is still what was written), a lower
#     layer is cut out (the layer above takes over its original), props get their previous
#     values back.
# Car paths (the file a call changes or reads) are under $KT_TEST_ROOT; source and destination
# files are used as they are. The mock's /system is read-only to the scripts, so kt makes a
# folder writable only while it changes it; props are set with $KT_TEST_SETPROP, which the
# scripts don't have. KT_TEST_FAIL=<car path> makes a replace of that file fail.
M=$KT_TEST_ROOT
J=$KT_JOURNAL
LOG=$KT_LOG
mkdir -p "$J/files" "$J/props"

# the host's own md5 tool (the scripts' md5 is a stub with the car's output)
md5of() { if command -v md5sum >/dev/null; then md5sum "$1" | cut -d' ' -f1; else /sbin/md5 -q "$1"; fi; }
note() { echo "${TWEAK_ID:-?} $*" >>"$LOG"; }
deny() {
    note "DENIED $*"
    echo "kt: not declared by ${TWEAK_ID:-?}: $*" >&2
    exit 70
}
die() {
    echo "kt: $*" >&2
    exit 1
}

needs() { grep '^need=' "${TWEAK_DIR:?}/tweak.conf" | sed -e 's/^need=//' -e 's/ | .*//'; }
declared() { needs | grep -qxF "$1"; }
# versions <path>: the versions the tweak's file: need lists for <path>, one per line
versions() { needs | grep -F "file:$1@" | sed "s#^file:$1@##" | tr , '\n'; }
listed() { versions "$1" | grep -qxF "$2"; }

# what a car path is now: link:<target>, absent, or its md5
now() {
    if [ -h "$M$1" ]; then
        echo "link:$(readlink "$M$1")"
    elif [ -f "$M$1" ]; then
        md5of "$M$1"
    else
        echo absent
    fi
}
dir() { echo "$J/files/$(echo "$1" | tr / %)"; }
order() { cat "$(dir "$1")/order" 2>/dev/null; }
top() { order "$1" | tail -n 1; }
bottom() { order "$1" | head -n 1; }
new_layer() {
    n=$(($(cat "$J/seq" 2>/dev/null || echo 0) + 1))
    echo $n >"$J/seq"
    mkdir -p "$(dir "$1")/$n"
    echo "$TWEAK_ID" >"$(dir "$1")/$n/tweak"
    echo $n
}
# keep <layer> <car path>: what the file is now, as that layer's original
keep() {
    if [ -h "$M$2" ]; then
        readlink "$M$2" >"$1/link"
    elif [ -f "$M$2" ]; then
        cp -p "$M$2" "$1/orig"
    else
        : >"$1/absent"
    fi
}
rw() { chmod u+w "$(dirname "$M$1")"; }
ro() { case "$1" in /system/*) chmod u-w "$(dirname "$M$1")" ;; esac; }
# restore <layer> <car path>: the file back as that layer's original
restore() {
    rw "$2"
    rm -f "$M$2"
    if [ -f "$1/link" ]; then
        ln -s "$(cat "$1/link")" "$M$2"
    elif [ -f "$1/orig" ]; then
        cp -p "$1/orig" "$M$2"
    fi
    ro "$2"
}
version_of() {
    if [ -f "$1/link" ]; then echo "link:$(cat "$1/link")"; elif [ -f "$1/orig" ]; then md5of "$1/orig"; else echo absent; fi
}
move_original() {   # <from layer> <to layer>
    rm -f "$2/orig" "$2/absent" "$2/link"
    for f in orig absent link; do
        if [ -f "$1/$f" ]; then mv "$1/$f" "$2/$f"; fi
    done
}

file_replace() {
    under=
    if [ "$1" = --under ]; then
        under=1
        shift
    fi
    p=$1 new=$2 mode=$3
    d=$(dir "$p")
    versions "$p" | grep -q . || deny file replace "$p"
    t=$(top "$p")
    if [ -n "$t" ]; then
        [ "$(now "$p")" = "$(cat "$d/$t/written")" ] || die "$p was changed by something else"
        listed "$p" "$(version_of "$d/$(bottom "$p")")" || deny file replace "$p"
    else
        [ -z "$under" ] || die "no other tweak has changed $p"
        listed "$p" "$(now "$p")" || deny file replace "$p"
    fi
    [ -f "$new" ] || die "no file $new"
    n=$(new_layer "$p")
    if [ -n "$under" ]; then
        b=$(bottom "$p")
        move_original "$d/$b" "$d/$n"
        cp -p "$new" "$d/$b/orig"
        { echo "$n"; cat "$d/order"; } >"$d/order.new" && mv "$d/order.new" "$d/order"
        note "file replace --under $p"
        return 0
    fi
    keep "$d/$n" "$p"
    if [ -z "$mode" ]; then
        if [ -f "$M$p" ] && [ ! -h "$M$p" ]; then
            mode=$(stat -c %a "$M$p" 2>/dev/null || stat -f %Lp "$M$p")
        else
            mode=644
        fi
    fi
    rw "$p"
    rm -f "$M$p.kt"
    { [ "$p" != "${KT_TEST_FAIL:-}" ] && cp "$new" "$M$p.kt" && chmod "$mode" "$M$p.kt" && rm -f "$M$p" && mv "$M$p.kt" "$M$p"; } || {
        rm -f "$M$p.kt"
        ro "$p"
        rm -rf "${d:?}/$n"
        die "writing $p"
    }
    ro "$p"
    now "$p" >"$d/$n/written"
    echo "$n" >>"$d/order"
    note "file replace $p $mode"
}

file_adopt() {
    p=$1 orig=$2
    d=$(dir "$p")
    versions "$p" | grep -q . || deny file adopt "$p"
    if [ "$orig" = absent ]; then
        v=absent
    else
        [ -f "$orig" ] || die "no file $orig"
        v=$(md5of "$orig")
    fi
    listed "$p" "$v" || deny file adopt "$p" "($v)"
    [ -z "$(top "$p")" ] || die "a tweak has already changed $p"
    n=$(new_layer "$p")
    if [ "$orig" = absent ]; then : >"$d/$n/absent"; else cp -p "$orig" "$d/$n/orig"; fi
    now "$p" >"$d/$n/written"
    echo "$n" >>"$d/order"
    note "file adopt $p"
}

file_original() {
    p=$1 dest=$2
    d=$(dir "$p")
    versions "$p" | grep -q . || deny file original "$p"
    b=$(bottom "$p")
    if [ -n "$b" ]; then
        [ -f "$d/$b/orig" ] || die "$p had no file before"
        cp "$d/$b/orig" "$dest"
    else
        listed "$p" "$(now "$p")" || die "$p isn't one of the versions declared"
        cp "$M$p" "$dest"
    fi
    note "file original $p"
}

prop() {   # <set|adopt> <name> <value | previous value>
    declared "prop:$2" || deny prop "$1" "$2"
    j=$J/props/$TWEAK_ID
    mkdir -p "$j"
    if grep -q "^$2=" "$j"/* 2>/dev/null; then
        # already recorded by this tweak: the first previous value stays; adopt does nothing
        if [ "$1" = adopt ]; then
            note "prop adopt $2 (already recorded)"
            return 0
        fi
    else
        if [ "$1" = adopt ]; then
            prev=$3
        elif [ -f "$M/props/$2" ]; then
            prev=$(cat "$M/props/$2")
        else
            prev=
        fi
        n=$(($(cat "$J/seq" 2>/dev/null || echo 0) + 1))
        echo $n >"$J/seq"
        echo "$2=$prev" >"$j/$n"
    fi
    if [ "$1" = set ]; then "$KT_TEST_SETPROP" "$2" "$3" || die "setprop $2"; fi
    note "prop $1 $2 $3"
}

off() {
    TWEAK_ID=$1
    for d in "$J"/files/*; do
        [ -f "$d/order" ] || continue
        p=$(basename "$d" | tr % /)
        sed '1!G;h;$!d' "$d/order" | while read -r l; do
            [ "$(cat "$d/$l/tweak")" = "$TWEAK_ID" ] || continue
            if [ "$l" = "$(top "$p")" ]; then
                if [ "$(now "$p")" = "$(cat "$d/$l/written")" ]; then
                    restore "$d/$l" "$p"
                    # the layer below is now on top, with what was just put back
                    below=$(sed -n "/^$l\$/{x;p;d;};h" "$d/order")
                    if [ -n "$below" ]; then now "$p" >"$d/$below/written"; fi
                    note "undo $p"
                else
                    note "changed by something else: $p"
                fi
            else
                above=$(sed -n "/^$l\$/{n;p;}" "$d/order")
                move_original "$d/$l" "$d/$above"
                note "cut out $p"
            fi
            grep -vx "$l" "$d/order" >"$d/order.new" || true
            mv "$d/order.new" "$d/order"
            rm -rf "${d:?}/$l"
        done
        [ -s "$d/order" ] || rm -rf "$d"
    done
    if [ -d "$J/props/$TWEAK_ID" ]; then
        find "$J/props/$TWEAK_ID" -type f | sed 's#.*/##' | sort -rn | while read -r e; do
            line=$(cat "$J/props/$TWEAK_ID/$e")
            name=${line%%=*} prev=${line#*=}
            # an unset prop goes back to unset: no value now, and no saved file
            if [ -z "$prev" ]; then
                rm -f "$M/props/$name" "$M/data/property/$name"
            else
                printf '%s' "$prev" >"$M/props/$name"
                case "$name" in persist.*) printf '%s' "$prev" >"$M/data/property/$name" ;; esac
            fi
            note "undo prop $name"
        done
        rm -rf "${J:?}/props/$TWEAK_ID"
    fi
}

case "$1 $2" in
    "file replace")
        shift 2
        file_replace "$@"
        ;;
    "file adopt") file_adopt "$3" "$4" ;;
    "file original") file_original "$3" "$4" ;;
    "file md5") [ -f "$M$3" ] && md5of "$M$3" ;;
    "prop get") getprop "$3" ;;
    "prop set") prop set "$3" "$4" ;;
    "prop adopt") prop adopt "$3" "$4" ;;
    "service start" | "service stop")
        declared "service:$3" || deny service "$2" "$3"
        note "service $2 $3"
        ;;
    "kill "*)
        declared "kill:$2" || deny kill "$2"
        note "kill $2"
        ;;
    "logcat "*)
        declared "logs:${2%%:*}" || deny logcat "$2"
        note "logcat $2"
        "$KT_TEST_LOGCAT"
        ;;
    "--off "*) off "$2" ;;
    *) die "unknown call: $*" ;;
esac
