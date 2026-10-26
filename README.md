# tweaks-adb

A tweak pack for [kia-tweaks](https://github.com/hazptr/kia-tweaks) with one switch: **ADB over
Wi-Fi**. NEMESIS package `tweaks.adb`; the tweak shows up in the **Tweaks** app, and kia-tweaks'
`tweaksd` runs it. Written for the 2023 Kia EV6 (Gen5W, firmware
`CVEV.USA.0000.V015.012.260507`) and limited to that firmware.

It replaces the NEMESIS community package `adb.tcp` ("TCP ADB"). It takes over that package's
setup and backup, so a car running `adb.tcp` can move to it without ADB dropping (see
[docs/migration.md](docs/migration.md)).

> **Warning:** ADB over Wi-Fi has no authentication on this firmware: anyone who joins the
> car's Wi-Fi can control the head unit.

| Tweak | Kind | What it does |
|---|---|---|
| ADB over Wi-Fi (`adb-wifi`) | oneshot, system | A computer on the car's Wi-Fi can use ADB on port 5555. |

Needs kia-tweaks 1.2 or newer (tweak pack support in `tweaksd`).

## What it changes

It works the same way as Engineering Mode's **ADB TCP** switch, so the two always agree:

- **On**:
  - sets `persist.adb.tcp.port=5555` if it has no value;
  - removes `/system/etc/permissions/com.hkmc.software.engineermode.adb_hide.xml`, which
    shows Engineering Mode's ADB switch from the next start on, so ADB can be turned back on
    from the screen;
  - then sets `persist.service.adb.tcp.enable=1` with `setprop`, as the switch does. This
    starts ADB at once.

  If that prop is already 1, it isn't set again: setting it again would restart `adbd` and
  drop every ADB session. A computer would have to reconnect.
- **Off**:
  - puts back exactly what was there before;
  - sets `persist.service.adb.tcp.enable` to 0 with `setprop`, so Engineering Mode shows off
    at once, then restores its saved file as the backup has it;
  - doesn't stop `adbd`: the running ADB keeps working until the next start. Engineering
    Mode's own switch stops `adbd` right away; this tweak doesn't, so turning it off from the
    car can't cut off a session in use.
- **Status** reads `persist.service.adb.tcp.enable`, the value Engineering Mode's screen reads,
  and its saved file in `/data/property`. A change made in Engineering Mode shows up in the
  Tweaks app. `/proc/net/tcp` tells whether ADB is listening right now, so the status says when
  a restart is still needed.

The backup is in `/data/nemesis/backup/tweaks.adb/adb-wifi`. When the car came from `adb.tcp`,
the backup is made from `adb.tcp`'s own (`/data/nemesis/backup/adb.tcp`). Turning off then also
puts back `/system/build.prop` byte for byte; `adb.tcp` had added three lines to it. If something
else changed those files, the tweak leaves them alone and reports an error.

Nothing reboots.

## How ADB starts on this head unit

These findings come from the car's init scripts, `/sbin/adbd`, and the Engineering Mode app
(`com.hkmc.system.app.engineering`, `ADBSetting`), with the framework's `MiscService`:

- **The switch.** Engineering Mode's switch calls `MiscService.setSystem(7)` to turn on, which
  sets `persist.service.adb.tcp.enable` to `1`. It calls `setSystem(8)` to turn off, which sets
  `0` and stops `adbd`. It keeps no other state. Its screen shows "on" when the prop reads `1`.
- **What starts `adbd`.** `init.daudio.rc` starts `adbd` on
  `persist.service.adb.tcp.enable=1`, together with `set_adb_port`
  (`service.adb.tcp.port=5555`) and `set_adb_ip`. It is the only thing that starts `adbd`
  while the USB port is in host mode, as it is here.
  - HMG Leafia Plus's alternative, the port prop alone with the switch at 0, leaves `adbd`
    stopped after a restart.
- **The port.** `adbd` listens on TCP when `service.adb.tcp.port` or, failing that,
  `persist.adb.tcp.port` holds a port. `set_adb_port` can lose the race with `adbd`, so the
  tweak sets `persist.adb.tcp.port` as well.
- **eth0.** `set_adb_ip` runs `ifconfig eth0 192.168.0.123` (a /24) at every start. That clashes
  with the wireless projection hotspot, so keep **ADB TCP and wireless projection together**
  (`adb-tcp-hotspot`, in tweaks-projection) on.
- **No authentication.** This `adbd` never asks for a key. It doesn't read `ro.adb.secure`
  (`default.prop` sets it to 1, and `adb.tcp`'s `ro.adb.secure=0` line in `build.prop` can't
  change a read-only prop anyway), and it never reads `adb_keys`. "Only approved computers"
  isn't possible without replacing `adbd`, so this pack doesn't offer it.

## Layout

| Path | What |
|---|---|
| `package/NEMESIS.data` | `id=tweaks.adb`, no apps, no services, no install hooks |
| `package/tweaks/adb-wifi/` | `tweak.conf` and the scripts (kia-tweaks' format) |
| `package/lib/adb-adopt.sh` | copies `adb.tcp`'s backup into this pack's backup (migration step) |
| `tests/host-test.sh` | runs the tweak against a mock head unit on a computer |
| `tests/detach-test.sh` | runs `adb.tcp`'s own uninstall hook against a mock to check the detach |

## Build and test

```sh
sh build.sh                          # -> dist/tweaks.adb.zip (needs zip)
sh tests/host-test.sh                # KT_SH=mksh|dash|bash picks the shell for the scripts
sh tests/detach-test.sh <adb.tcp>    # a copy of /data/nemesis/apps/adb.tcp (not included)
```

## License

MIT (see `LICENSE`), Copyright (c) 2026 hazptr. See `NOTICE.md`. Not affiliated with Hyundai or
Kia. Modifying your head unit is at your own risk.
