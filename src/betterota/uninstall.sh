#!/system/bin/sh
_bota_pid=$(cat /data/adb/betterota/daemon.pid 2>/dev/null)
[ -n "$_bota_pid" ] && kill "$_bota_pid" 2>/dev/null
[ -d /data/adb/betterota/state ] && rm -rf /data/adb/betterota/state
[ -f /data/adb/betterota/daemon.pid ] && rm -f /data/adb/betterota/daemon.pid
[ -d /data/adb/betterota/daemon.lock ] && rmdir /data/adb/betterota/daemon.lock 2>/dev/null
exit 0
