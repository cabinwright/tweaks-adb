# Moving a car from `adb.tcp` to `tweaks.adb`

For the 2023 EV6 (`CVEV.USA.0000.V015.012.260507`) running the NEMESIS community package
`adb.tcp` ("TCP ADB"). The goal is that **ADB over TCP never drops**: every step is run over
that connection, and losing it means recovering with a USB stick. No step below writes
`/system`, runs `setprop` or restarts `adbd`. Commands run over ADB (`adb shell "..."`);
`nemesis root -c` runs as root.

## What adb.tcp leaves on the car

| What | On the car | Comes from |
|---|---|---|
| `/system/build.prop` | md5 `ef2487699d5a17fffca30a1cbc9f22b0`: the stock file plus `ro.adb.secure=0`, `persist.service.adb.tcp.enable=1`, `service.adb.tcp.port=5555` at the end | adb.tcp |
| build.prop without those three lines | md5 `30e9666d146efe83697f155574d50d30`, the same as adb.tcp's snapshot | stock |
| `.../permissions/com.hkmc.software.engineermode.adb_hide.xml` | absent; adb.tcp's backup has it (md5 `bb94dd63efd6d3494834e649653f795f`) | adb.tcp |
| `persist.service.adb.tcp.enable` | `1`, saved in `/data/property` (adb.tcp's backup: unset before it) | adb.tcp, then Engineering Mode |
| `persist.adb.tcp.port` | `5555`, saved in `/data/property` (Leafia's detached record: unset before it) | HMG Leafia Plus |
| `adbd` | running, listening on 0.0.0.0:5555 | init, on the prop above |
| `/data/nemesis/backup/adb.tcp` | `saved`, `build.prop`, `bp.*.absent` (3), `gp.*.unset` (2), `adb_hide.xml` | adb.tcp |

The pack's `status.sh` reports this as `on ADB over Wi-Fi is on`.

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
the switch is unset, nothing starts `adbd`, and ADB is gone. Once the pack has taken over, the
store would also report the tweak as "Changed by something else". That is why the steps below
detach adb.tcp instead.

## Steps

**0. Prerequisites.**
- cabinwright.store 1.0 or newer installed.

**1. Install the pack** from the store. It has no install hooks, so nothing changes. The store
lists the tweak's needs before you agree.

**2. Take over adb.tcp's setup.** In the Tweaks app, turn on **ADB over Wi-Fi**. It finds
adb.tcp's changes and takes them over: the store's runner records adb.tcp's snapshot of
`build.prop`, its copy of `adb_hide.xml` (each checked against the stock md5) and the switch's
value before adb.tcp as the originals. It says "ADB over Wi-Fi was already on: taken over,
nothing changed". It never sets the switch while it is 1 already, so `adbd` isn't restarted; the
host test checks this ("no setprop", "adbd not restarted").

It refuses, changing nothing, if build.prop without adb.tcp's three lines isn't adb.tcp's
snapshot byte for byte.

**3. Detach adb.tcp without its undo.** Move away the marker its restore checks first, then
uninstall it. These are root commands over ADB, which the store's lockdown keeps to NEMESIS
Manager: turn **Lockdown** off in the store's settings for this step, and back on afterwards.

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
- adb.tcp's backup folder stays, renamed marker and all. The runner keeps its own copies of the
  originals, so it can be deleted.

### Why step 3 changes nothing and ADB stays up

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

**4. Done.**
- `tweaks.adb` now owns ADB over Wi-Fi.
- Engineering Mode's ADB TCP switch and the Tweaks app show the same state.
- No restart is needed.

## Rollback

- **Before step 2:** uninstall the pack from the store. It never ran a script, so adb.tcp's
  install is exactly as before.
- **After step 2, before step 3:** turning the tweak off, or removing the pack, puts back the
  state from before adb.tcp (and ADB stops at the next start). To keep adb.tcp's setup, leave
  the tweak on.
- **After step 3, keeping ADB:** nothing to do.
- **To go back to stock:**
  1. Turn **ADB over Wi-Fi** off in the Tweaks app. The runner puts build.prop, adb_hide.xml
     and both props back as they were before adb.tcp, and ADB keeps working until the next start.
  2. Restart.
- **If ADB is ever lost:**
  - turn on Engineering Mode > Module Info > page 3 (tap a corner until the ADB menu shows) >
    ADB TCP. That switch is visible while the tweak is on.
  - or use the NEMESIS Manager / USB stick (`NEMESIS.sh`) route.
