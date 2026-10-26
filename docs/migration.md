# Moving a car from `adb.tcp` to `tweaks.adb`

For the 2023 EV6 (`CVEV.USA.0000.V015.012.260507`) running the NEMESIS community package
`adb.tcp` ("TCP ADB"). The goal is that **ADB over TCP never drops**: every step is run over
that connection, and losing it means recovering with a USB stick. No step below writes
`/system`, runs `setprop` or restarts `adbd`. Commands run over ADB (`adb shell "..."`);
`nemesis root -c` runs as root.

## What the car has now (read on 2026-10-25)

| What | On the car | Comes from |
|---|---|---|
| `/system/build.prop` | md5 `ef2487699d5a17fffca30a1cbc9f22b0`: the stock file plus `ro.adb.secure=0`, `persist.service.adb.tcp.enable=1`, `service.adb.tcp.port=5555` at the end | adb.tcp |
| build.prop without those three lines | md5 `30e9666d146efe83697f155574d50d30`, the same as adb.tcp's snapshot | stock |
| `.../permissions/com.hkmc.software.engineermode.adb_hide.xml` | absent; adb.tcp's backup has it (md5 `bb94dd63efd6d3494834e649653f795f`) | adb.tcp |
| `persist.service.adb.tcp.enable` | `1`, saved in `/data/property` (adb.tcp's backup: unset before it) | adb.tcp, then Engineering Mode |
| `persist.adb.tcp.port` | `5555`, saved in `/data/property` (Leafia's detached record: unset before it) | HMG Leafia Plus |
| `adbd` | running, listening on 0.0.0.0:5555 | init, on the prop above |
| `/data/nemesis/backup/adb.tcp` | `saved`, `build.prop`, `bp.*.absent` (3), `gp.*.unset` (2), `adb_hide.xml` | adb.tcp |

The pack's `status.sh`, run read-only on the car as root, prints `on ADB over Wi-Fi is on`.

## What uninstalling adb.tcp normally does (don't)

`nemesis uninstall adb.tcp` runs its `scripts/preun.sh`, which calls `restore_all`. With its
backup in place, that:

1. remounts `/system` read-write;
2. rewrites `build.prop` without the three lines;
3. puts `adb_hide.xml` back;
4. deletes `/data/property/persist.service.adb.tcp.enable` (it was unset before);
5. sets `service.adb.tcp.port` to empty;
6. runs `setprop ctl.restart adbd`;
7. then deletes its backup.

The restart at step 6 drops the ADB session. `adbd` comes back on 5555 only because
`persist.adb.tcp.port` is still 5555, and the computer has to reconnect. After the next start
the switch is unset, nothing starts `adbd`, and ADB is gone. If `tweaks.adb` is on by then,
tweaksd notices within 5 minutes and turns it on again, but that relies on tweaksd. That
window is why the steps below detach adb.tcp instead.

## Steps

**0. Prerequisites.**
- cabinwright.tweaks 1.4 or newer (or kia.tweaks 1.2 or newer, its earlier name) installed and running.
- Build `dist/tweaks.adb.zip`.
- Keep **ADB TCP and wireless projection together** (tweaks-projection's `adb-tcp-hotspot`) on.
  The switch has to stay 1 (see the README), so `set_adb_ip` still runs at every start.

**1. Install the pack.** It has no install hooks, so nothing changes.

```sh
adb push dist/tweaks.adb.zip /data/local/tmp/
adb shell "nemesis install /data/local/tmp/tweaks.adb.zip"
```

**2. Let the Tweaks app record the switch.**
- Open the Tweaks app once. It records a system tweak's switch from its first reported state, so
  **ADB over Wi-Fi** shows on: "ADB over Wi-Fi is on".
- Check `/data/nemesis/cabinwright/tweaks/state.json`: `adb-wifi` should show `"want":"on","state":"on"`.
- tweaksd runs nothing, because the tweak is already on.
- Even if `enable.sh` ran, it would do nothing to ADB:
  - it only copies adb.tcp's backup and prints "already on";
  - it never sets the switch while it is 1 already. The host test checks this ("no setprop",
    "adbd not restarted").

If the status is anything else, stop here and uninstall the pack: nothing was changed.

**3. Take over adb.tcp's backup.** This writes only `/data/nemesis/backup/tweaks.adb`.

```sh
adb shell "nemesis root -c 'sh /data/nemesis/apps/tweaks.adb/lib/adb-adopt.sh'"
# expect: taken over into /data/nemesis/backup/tweaks.adb/adb-wifi:
#   adb_hide.xml  build.prop.stock  complete  persist.adb.tcp.port.unset
#   persist.service.adb.tcp.enable.unset  source
```

It refuses if build.prop without adb.tcp's three lines isn't adb.tcp's snapshot byte for byte.

**4. Detach adb.tcp without its undo.** Move away the marker its restore checks first, then
uninstall it:

```sh
adb shell "nemesis root -c 'mv /data/nemesis/backup/adb.tcp/saved /data/nemesis/backup/adb.tcp/saved.detached'"
adb shell "nemesis uninstall adb.tcp"
```

Check:
- `/data/nemesis/adb.tcp.log` ends with `preuninstall adb.tcp`,
  `FAIL: no snapshot to restore`, `keeping /data/nemesis/backup/adb.tcp`.
- `md5 /system/build.prop` is still `ef2487…`.
- `getprop persist.service.adb.tcp.enable` is still 1.
- The tweak still says "on ADB over Wi-Fi is on".
- adb.tcp's backup folder stays, renamed marker and all. It can be deleted later, since step 3
  copied it.

### Why step 4 changes nothing and ADB stays up

**adb.tcp's hook** (`scripts/preun.sh`, md5 `fe8b83275b0eb8108366ee1071cc1d3b`, with
`scripts/common.sh` md5 `cc7f7122b6b29b152e6d23fc3c15096c`, as installed on the car) does this,
in order:

1. `export PATH=...`, then `. ./scripts/common.sh`. At the top level, common.sh only sets
   variables (`PATH`, `LD_LIBRARY_PATH`, `BP`, `HIDE`, `BACKUP_DIR`, `LOG`) and defines functions.
2. `log "preuninstall adb.tcp"` appends a line to `/data/nemesis/adb.tcp.log`.
3. `restore_all` starts with `if [ ! -s "$BACKUP_DIR/saved" ]; then log "FAIL: no snapshot to
   restore"; return 1; fi`. With `saved` moved away it returns there. That is before `sys_rw`,
   before any `restore_*`, before `setprop ctl.restart adbd` and before `rm`.
4. Back in preun.sh, `log "keeping $BACKUP_DIR"` and `exit 1`. `remove_backup_dir` isn't
   reached.

The only write is three lines in its own log. No `setprop`, no remount, and **no `ctl.restart
adbd`**, so the running `adbd` and its sessions are untouched.

`tests/detach-test.sh` runs that exact hook (the car's copy, pointed at a mock with `sed`).
It passes: exit 1, no file changed but the log, no `setprop`, remount or reboot. Without the
`mv`, the same run rewrites `build.prop`, puts `adb_hide.xml` back and calls `setprop`.

**What NEMESIS does with the exit code.** This is from disassembling the car's
`/system/xbin/nemesis` (md5 `0de1a73590bd0c6d35ac747c0a4d8449`):

1. The uninstall routine (around 0x67a0) reads the package's NEMESIS.data and removes its APK
   apps. adb.tcp has none: its `app.0` is `kind=sh`.
2. It logs `hook preuninstall -> …` and runs the hook (0x699c). It doesn't look at the result:
   the next instruction is an unconditional branch.
3. It then stops the package's services (none) and runs a `postuninstall` hook (none).
4. It deletes `/data/nemesis/apps/adb.tcp` and the package's `packages.db` entry, and logs
   `uninstalled adb.tcp`.

A preuninstall hook that exits non-zero doesn't stop the uninstall. Only install checks its hook
(`preinstall failed rc=%d`). Nothing in the uninstall touches `adbd` or props.

**5. Done.**
- `tweaks.adb` now owns ADB over Wi-Fi.
- Engineering Mode's ADB TCP switch and the Tweaks app show the same state.
- No restart is needed.

## Rollback

- **Before step 4:** `adb shell "nemesis uninstall tweaks.adb"`. The pack has no hooks and never
  ran a script, so adb.tcp's install is exactly as before.
  `rm -rf /data/nemesis/backup/tweaks.adb` if you like.
- **After step 4, keeping ADB:** nothing to do.
- **To go back to stock:**
  1. Turn **ADB over Wi-Fi** off in the Tweaks app. It puts build.prop, adb_hide.xml and both
     props back as they were before adb.tcp, and ADB keeps working until the next start.
  2. Restart.
- **Without the app:**
  `nemesis root -c 'sh /data/nemesis/apps/tweaks.adb/tweaks/adb-wifi/disable.sh'`.
- **If ADB is ever lost:**
  - turn on Engineering Mode > Module Info > page 3 (tap a corner until the ADB menu shows) >
    ADB TCP. That switch is visible while the tweak is on.
  - or use the NEMESIS Manager / USB stick (`NEMESIS.sh`) route.
