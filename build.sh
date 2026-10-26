#!/bin/sh
# Builds the tweaks.adb NEMESIS package (a tweak pack for Cabinwright tweaks): dist/tweaks.adb.zip from
# package/ (NEMESIS.data, tweaks/adb-wifi/, lib/). Needs only sh and zip.
# Install over ADB (cabinwright.tweaks 1.4 or newer must be installed; its tweaksd runs the tweak):
#   adb push dist/tweaks.adb.zip /data/local/tmp/
#   adb shell "nemesis install [--update] /data/local/tmp/tweaks.adb.zip"
set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
P=$ROOT/package

# The head unit's shell (mksh) has no printf, sed, awk, head, tail or tr
if grep -rnE '(^[[:space:]]*|[|;&(][[:space:]]*|\$\([[:space:]]*)(printf|sed|awk|head|tail|tr)[[:space:]]' --include='*.sh' "$P" | grep -vE ':[0-9]+:[[:space:]]*#'; then
    echo "build.sh: a command the head unit doesn't have, in the scripts above" >&2
    exit 1
fi
for f in $(find "$P" -name '*.sh'); do sh -n "$f" || { echo "build.sh: syntax error in $f" >&2; exit 1; }; done
# NEMESIS runs uninstall hooks on every update too: a tweak pack has none
if grep -qE '^(preinstall|postinstall|preuninstall|postuninstall)=' "$P/NEMESIS.data"; then
    echo "build.sh: NEMESIS.data must not have install hooks" >&2; exit 1
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$P/." "$STAGE/"
find "$STAGE" -name .DS_Store -delete
mkdir -p "$ROOT/dist" && rm -f "$ROOT/dist/tweaks.adb.zip"
(cd "$STAGE" && zip -qrX "$ROOT/dist/tweaks.adb.zip" .)
echo "$ROOT/dist/tweaks.adb.zip"
