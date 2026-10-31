#!/system/bin/sh
# Turn off: the runner puts back everything kt changed. Running set_adb_ip again (enable.sh) left
# nothing to undo: an eth0 address it narrowed stays /32 until the next start, which ADB and the
# hotspot are both fine with.
echo "eth0 keeps its address until the next start"
