#!/bin/sh
# Checks each package/tweaks/<id>/tweak.conf against the tweak format the store's runner reads:
# only its keys; name, summary, description, firmware, kind and default present; every need=
# line "<need> | <reason>" of a known kind, file: needs with an md5 (or absent, or link:<target>)
# for each version; a oneshot tweak with binder, kill, service or root needs has a disable.sh.
# usage: tools/check-tweaks.sh <package dir>
P=$1
bad=0
err() {
    echo "check-tweaks: $1" >&2
    bad=1
}
for c in "$P"/tweaks/*/tweak.conf; do
    t=${c%/tweak.conf}
    id=${t##*/}
    for k in name summary description firmware kind default; do
        grep -q "^$k=." "$c" || err "$id: no $k="
    done
    grep -qE '^kind=(oneshot|service)$' "$c" || err "$id: kind is oneshot or service"
    grep -qE '^default=(on|off)$' "$c" || err "$id: default is on or off"
    grep -vE '^(name|summary|description|firmware|kind|default|conflicts|need)=' "$c" | grep . >/dev/null \
        && err "$id: unknown keys: $(grep -vE '^(name|summary|description|firmware|kind|default|conflicts|need)=' "$c" | tr '\n' ' ')"
    lasting=
    grep '^need=' "$c" | while IFS= read -r l; do
        n=${l#need=}
        case "$n" in *" | "?*) ;; *) echo "check-tweaks: $id: no reason: $l" >&2; echo x ;; esac
        n=${n%% | *}
        case "$n" in
            file:/*@*)
                for v in $(echo "${n#*@}" | tr , ' '); do
                    echo "$v" | grep -qE '^([0-9a-f]{32}|absent|link:.+)$' || { echo "check-tweaks: $id: bad version $v in $n" >&2; echo x; }
                done ;;
            prop:?* | setting:?*/?* | service:?* | kill:?* | logs:?* | root) ;;
            binder:?*" "?*) ;;
            *) echo "check-tweaks: $id: unknown need: $n" >&2; echo x ;;
        esac
    done | grep -q x && bad=1
    grep -qE '^need=(binder|kill|service|root)' "$c" && lasting=1
    if [ -n "$lasting" ] && grep -qx 'kind=oneshot' "$c" && [ ! -f "$t/disable.sh" ]; then
        err "$id: a oneshot tweak with binder, kill, service or root needs must have disable.sh"
    fi
done
exit $bad
