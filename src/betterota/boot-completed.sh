#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/scripts/common.sh"
bota_mkdirs
bota_lockdown_apply
if bota_state_has abandoned; then
  bota_log "boot-completed: a previous OTA was abandoned to protect root"
fi
if bota_state_has cycle_failed; then
  bota_log "boot-completed: previous OTA cycle failed, reboot trigger left paused"
fi
if bota_state_has patched; then
  bota_log "boot-completed: root patch verified for this cycle"
fi
bota_log "boot-completed: status=$(bota_state_get status)"
