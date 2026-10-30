#!/system/bin/sh

BOTA_MODDIR="${MODDIR:-}"
if [ -z "$BOTA_MODDIR" ]; then
  BOTA_MODDIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
fi
. "$BOTA_MODDIR/scripts/common.sh"

bota_mkdirs

BOTA_LOCK="$BOTA_DATA_DIR/daemon.lock"
BOTA_PIDFILE="$BOTA_DATA_DIR/daemon.pid"

bota_acquire_lock() {
  local _old
  if mkdir "$BOTA_LOCK" 2>/dev/null; then
    printf '%s' "$$" > "$BOTA_PIDFILE"
    trap 'rm -f "$BOTA_PIDFILE"; rmdir "$BOTA_LOCK" 2>/dev/null; exit 0' EXIT INT TERM
    return 0
  fi
  _old=$(cat "$BOTA_PIDFILE" 2>/dev/null)
  if [ -n "$_old" ] && kill -0 "$_old" 2>/dev/null; then
    return 1
  fi
  rmdir "$BOTA_LOCK" 2>/dev/null
  if mkdir "$BOTA_LOCK" 2>/dev/null; then
    printf '%s' "$$" > "$BOTA_PIDFILE"
    trap 'rm -f "$BOTA_PIDFILE"; rmdir "$BOTA_LOCK" 2>/dev/null; exit 0' EXIT INT TERM
    return 0
  fi
  return 1
}

bota_normalize_on_boot() {
  local _cur _prev
  _cur=$(bota_current_slot)
  _prev=$(bota_state_get last_boot_slot)
  bota_state_put last_boot_slot "$_cur"
  if [ -n "$_prev" ] && [ "$_prev" != "$_cur" ]; then
    if bota_state_has patched; then
      bota_log "OTA cycle complete: slot $_prev -> $_cur, root patch present"
    else
      bota_log "WARN: slot $_prev -> $_cur without verified patch; root may be lost"
    fi
    bota_state_clear_cycle
  elif bota_state_has abandoned || bota_state_has cycle_failed; then
    bota_state_clear_outcome
    bota_set_status idle
  fi
}

bota_cooldown_wait() {
  local _last _now _cd _min _remain
  _last=$(bota_state_get last_abandon_epoch)
  [ -n "$_last" ] || return 0
  _now=$(date +%s 2>/dev/null) || return 0
  _cd=${BOTA_ABANDON_COOLDOWN:-1800}
  _min=${BOTA_ABANDON_COOLDOWN_MIN:-60}
  [ "$_cd" -lt "$_min" ] && _cd=$_min
  _remain=$((_cd - (_now - _last)))
  if [ "$_remain" -gt 0 ]; then
    bota_log "cooldown ${_remain}s before next attempt"
    sleep "$_remain"
  fi
  return 0
}

bota_wait_stage1() {
  bota_state_has stage1_downloaded && return 0
  bota_state_put base_slot "$(bota_current_slot)"
  bota_set_status waiting_stage1
  bota_log "waiting for OTA stage 1 (download)"
  while :; do
    if bota_update_in_progress; then
      bota_state_set stage1_downloaded
      bota_log "stage 1 detected"
      return 0
    fi
    sleep "${BOTA_STAGE1_POLL:-15}"
  done
}

bota_wait_stage2() {
  bota_state_has stage2_installed && return 0
  bota_set_status waiting_stage2
  bota_log "waiting for OTA stage 2 (install)"
  while :; do
    if bota_stage2_reached; then
      bota_state_set stage2_installed
      bota_log "stage 2 detected (UPDATED_NEED_REBOOT)"
      return 0
    fi
    sleep "${BOTA_STAGE2_POLL:-10}"
  done
}

bota_do_patch() {
  local _ksud _i _out _rc _part
  bota_state_has patched && return 0
  _ksud=$(bota_find_ksud) || { bota_log "FATAL: ksud not found"; return 1; }
  _part=$(bota_partition_or_empty)
  if ! bota_patch_lock_acquire; then
    bota_log "another patch is already running; skip"
    return 1
  fi
  _i=0
  while [ "$_i" -lt "${BOTA_PATCH_RETRIES:-3}" ]; do
    _i=$((_i + 1))
    bota_set_status patching
    if [ -n "$_part" ]; then
      bota_log "ksud boot-patch --ota --flash --partition $_part (attempt $_i)"
      _out=$("$_ksud" boot-patch --ota --flash --partition "$_part" 2>&1)
    else
      bota_log "ksud boot-patch --ota --flash (attempt $_i)"
      _out=$("$_ksud" boot-patch --ota --flash 2>&1)
    fi
    _rc=$?
    printf '%s\n' "$_out" >> "$BOTA_LOG_FILE" 2>/dev/null
    if [ "$_rc" -eq 0 ]; then
      bota_state_set patched
      bota_log "patch OK"
      bota_patch_lock_release
      return 0
    fi
    bota_log "patch failed rc=$_rc"
    sleep "${BOTA_PATCH_RETRY_DELAY:-20}"
  done
  bota_patch_lock_release
  return 1
}

bota_decide() {
  if bota_state_has patched; then
    if [ "${BOTA_RESUME_AFTER_PATCH:-1}" = "1" ]; then
      bota_resume_manager
    fi
    bota_set_status patched_waiting_reboot
    bota_log "root patch written; reboot may proceed"
    return 0
  fi
  if bota_abandon_update; then
    bota_state_set abandoned
    bota_set_status abandoned
    bota_log "cycle abandoned to protect root; update discarded"
    return 1
  fi
  bota_state_set cycle_failed
  bota_set_status failed_paused
  bota_log "patch failed and abandon unavailable; trigger held paused"
  return 1
}

bota_main() {
  bota_acquire_lock || { bota_log "another daemon is running; exit"; exit 0; }
  bota_log "daemon start pid=$$ slot=$(bota_current_slot)"

  bota_normalize_on_boot

  bota_is_ab || { bota_log "not an A/B device; exit"; exit 0; }

  if bota_state_has patched; then
    bota_log "cycle already patched; daemon idle"
    exit 0
  fi

  while :; do
    bota_cooldown_wait
    if bota_state_has need_resume; then
      bota_resume_manager
      bota_ue --reset_status >/dev/null 2>&1
    fi
    bota_wait_stage1
    if [ "${BOTA_PAUSE_AT_STAGE1:-0}" = "1" ]; then
      bota_pause_manager
    fi
    bota_wait_stage2
    bota_pause_manager
    bota_do_patch
    if bota_decide; then
      bota_log "daemon exit"
      exit 0
    fi
    if bota_state_has cycle_failed; then
      bota_log "daemon holding: reboot trigger left paused"
      exit 0
    fi
    bota_state_clear_attempt
    bota_set_status cooldown
  done
}

# Update-safe flow: lockdown auto-update, then watch for a staged OTA and patch
# the inactive slot. Never pauses services, never reverts slots, never resets
# the update. Safe for a daily driver where the reboot is user-initiated.
bota_main_safe() {
  local _hits _max _poll _sig _last_sig _tick _confirmed
  bota_acquire_lock || { bota_log "another daemon is running; exit"; exit 0; }
  bota_log "daemon start (update-safe) pid=$$ slot=$(bota_current_slot)"

  bota_normalize_on_boot

  bota_is_ab || { bota_log "not an A/B device; exit"; exit 0; }

  bota_lockdown_apply

  if bota_state_has patched; then
    bota_log "cycle already patched; daemon idle"
    exit 0
  fi

  _max=${BOTA_STAGE2_DEBOUNCE:-2}
  _hits=0
  _confirmed=0
  _last_sig=""
  _tick=0
  bota_set_status watching
  bota_log "safe mode: watching for staged OTA (observe_only=${BOTA_OBSERVE_ONLY:-0})"
  while :; do
    _poll=${BOTA_FAST_POLL:-5}
    _sig=$(bota_signal_sig)
    if [ "$_sig" != "$_last_sig" ] || { [ "${BOTA_LOG_HEARTBEAT:-60}" -gt 0 ] 2>/dev/null && [ "$_tick" -ge "${BOTA_LOG_HEARTBEAT:-60}" ]; }; then
      bota_detect_log
      _last_sig=$_sig
      _tick=0
    fi
    _tick=$((_tick + 1))

    if bota_stage2_signal; then
      _hits=$((_hits + 1))
    else
      if [ "$_confirmed" = "1" ]; then
        bota_log "stage2 signal cleared"
      fi
      _hits=0
      _confirmed=0
    fi

    if [ "$_hits" -ge "$_max" ] && [ "$_confirmed" = "0" ]; then
      _confirmed=1
      bota_log "stage2 candidate confirmed (hits=$_hits)"
      if [ "${BOTA_OBSERVE_ONLY:-0}" = "1" ]; then
        bota_log "OBSERVE ONLY: not patching; signals logged"
        bota_set_status observed_stage2
      fi
    fi

    if [ "$_confirmed" = "1" ] && [ "${BOTA_OBSERVE_ONLY:-0}" != "1" ]; then
      if [ "${BOTA_STAGE2_SETTLE:-0}" -gt 0 ] 2>/dev/null; then
        bota_log "stage2 settle: waiting ${BOTA_STAGE2_SETTLE}s before patch"
        sleep "$BOTA_STAGE2_SETTLE"
      fi
      if bota_do_patch; then
        bota_state_put patched_at "$(date +%s 2>/dev/null)"
        bota_set_status patched_waiting_reboot
        bota_log "root patch written; reboot may proceed"
        exit 0
      fi
      bota_log "patch failed; keeping current slot and retrying (no revert/reset)"
      bota_set_status patch_failed_retrying
      _confirmed=0
      _hits=0
      sleep "${BOTA_SAFE_RETRY_DELAY:-60}"
      continue
    fi

    sleep "$_poll"
  done
}

if [ "${BOTA_UPDATE_SAFE:-0}" = "1" ]; then
  bota_main_safe
else
  bota_main
fi
