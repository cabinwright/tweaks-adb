# Notices

tweaks-adb is licensed under the MIT License (`LICENSE`), Copyright (c) 2026 hazptr.

## NEMESIS and the community package adb.tcp

The pack installs and runs through **NEMESIS** by xwtk (https://github.com/xwtk/hmg_nemesis),
licensed under the GNU Affero General Public License v3.0.

It replaces the NEMESIS community package **TCP ADB** (`adb.tcp`). The `adb-wifi` tweak is an
independent implementation, written from that package's observed behaviour on the car: which
props it sets, which `build.prop` lines it adds and which feature file it removes. No code from
it is included. The tweak reads `adb.tcp`'s backup (`/data/nemesis/backup/adb.tcp`) on the car to
take over from it. `tests/detach-test.sh` runs a copy of `adb.tcp` that the user supplies; the
copy isn't part of this repository.

## HMG Leafia Plus

https://github.com/VysseCodes/HMG-Leafia-Plus (GPL-3.0). No code from it is included. The tweak
reads the record of `persist.adb.tcp.port` that Leafia's package left on the car, as kept by
tweaks-projection's migration (`/data/nemesis/backup/leafia-detached/wireless.carplay.aa.adb`).

## kia-tweaks (MIT)

https://github.com/hazptr/kia-tweaks, Copyright (c) 2026 hazptr. The tweak format, and the
layout of `build.sh` and the host test, follow it and tweaks-projection.
