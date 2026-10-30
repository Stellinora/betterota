#!/system/bin/sh
_bota_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [ -f "$_bota_dir/scripts/common.sh" ]; then
  . "$_bota_dir/scripts/common.sh"
  command -v bota_lockdown_restore >/dev/null 2>&1 && bota_lockdown_restore
fi

_bota_pid=$(cat /data/adb/betterota/daemon.pid 2>/dev/null)
[ -n "$_bota_pid" ] && kill "$_bota_pid" 2>/dev/null
_bota_patch_pid=$(cat /data/adb/betterota/patch.pid 2>/dev/null)
[ -n "$_bota_patch_pid" ] && kill "$_bota_patch_pid" 2>/dev/null
[ -d /data/adb/betterota/state ] && rm -rf /data/adb/betterota/state
[ -f /data/adb/betterota/daemon.pid ] && rm -f /data/adb/betterota/daemon.pid
[ -f /data/adb/betterota/patch.pid ] && rm -f /data/adb/betterota/patch.pid
[ -d /data/adb/betterota/daemon.lock ] && rmdir /data/adb/betterota/daemon.lock 2>/dev/null
[ -d /data/adb/betterota/patch.lock ] && rmdir /data/adb/betterota/patch.lock 2>/dev/null
exit 0
