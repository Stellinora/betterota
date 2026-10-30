#!/system/bin/sh

BOTA_MODDIR="${BOTA_MODDIR:-${MODDIR:-}}"
if [ -z "$BOTA_MODDIR" ]; then
  BOTA_MODDIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd)
fi

. "$BOTA_MODDIR/scripts/config.sh"
[ -f "$BOTA_USER_CONFIG" ] && . "$BOTA_USER_CONFIG"

bota_log() {
  local _ts _msg _sz
  _ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
  _msg="$_ts $*"
  mkdir -p "$BOTA_DATA_DIR" 2>/dev/null
  if [ -f "$BOTA_LOG_FILE" ]; then
    _sz=$(wc -c < "$BOTA_LOG_FILE" 2>/dev/null || echo 0)
    if [ "$_sz" -gt "${BOTA_LOG_MAX_BYTES:-524288}" ] 2>/dev/null; then
      mv -f "$BOTA_LOG_FILE" "$BOTA_LOG_FILE.1" 2>/dev/null
    fi
  fi
  printf '%s\n' "$_msg" >> "$BOTA_LOG_FILE" 2>/dev/null
  command -v log >/dev/null 2>&1 && log -t BetterOTA -p i "$*" 2>/dev/null
  return 0
}

bota_mkdirs() {
  mkdir -p "$BOTA_DATA_DIR" "$BOTA_STATE_DIR" 2>/dev/null
}

bota_state_set() {
  mkdir -p "$BOTA_STATE_DIR" 2>/dev/null
  : > "$BOTA_STATE_DIR/$1"
}

bota_state_has() {
  [ -e "$BOTA_STATE_DIR/$1" ]
}

bota_state_rm() {
  rm -f "$BOTA_STATE_DIR/$1" 2>/dev/null
}

bota_state_get() {
  if [ -f "$BOTA_STATE_DIR/$1" ]; then
    cat "$BOTA_STATE_DIR/$1" 2>/dev/null
  fi
}

bota_state_put() {
  mkdir -p "$BOTA_STATE_DIR" 2>/dev/null
  printf '%s' "$2" > "$BOTA_STATE_DIR/$1"
}

bota_set_status() {
  bota_state_put status "$1"
}

bota_state_clear_attempt() {
  rm -f "$BOTA_STATE_DIR"/stage1_downloaded \
        "$BOTA_STATE_DIR"/stage2_installed \
        "$BOTA_STATE_DIR"/manager_paused \
        "$BOTA_STATE_DIR"/patched \
        "$BOTA_STATE_DIR"/abandoned \
        "$BOTA_STATE_DIR"/cycle_failed 2>/dev/null
}

bota_state_clear_outcome() {
  bota_state_clear_attempt
  rm -f "$BOTA_STATE_DIR"/need_resume \
        "$BOTA_STATE_DIR"/paused_services 2>/dev/null
}

bota_state_clear_cycle() {
  bota_state_clear_outcome
  rm -f "$BOTA_STATE_DIR"/base_slot \
        "$BOTA_STATE_DIR"/last_abandon_epoch 2>/dev/null
  bota_set_status idle
}

bota_current_slot() {
  getprop ro.boot.slot_suffix 2>/dev/null
}

bota_is_ab() {
  local _ab
  _ab=$(getprop ro.build.ab_update 2>/dev/null)
  [ "$_ab" = "true" ] && return 0
  [ -n "$(bota_current_slot)" ]
}

bota_find_ksud() {
  local _c _p
  _c=$(command -v ksud 2>/dev/null)
  for _p in "$_c" /data/adb/ksu/bin/ksud /data/adb/ksud /system/bin/ksud /system/xbin/ksud; do
    if [ -n "$_p" ] && [ -x "$_p" ]; then
      printf '%s' "$_p"
      return 0
    fi
  done
  return 1
}

bota_find_bootctl() {
  local _c _p
  _c=$(command -v bootctl 2>/dev/null)
  for _p in "$_c" /data/adb/ksu/bin/bootctl /data/adb/bootctl; do
    if [ -n "$_p" ] && [ -x "$_p" ]; then
      printf '%s' "$_p"
      return 0
    fi
  done
  return 1
}

bota_ue() {
  local _c
  _c=$(command -v update_engine_client 2>/dev/null) || return 1
  "$_c" "$@"
}

bota_ue_status() {
  bota_ue --status 2>/dev/null
}

bota_slot_flipped() {
  local _bc _a _c
  _bc=$(bota_find_bootctl) || return 1
  _a=$("$_bc" get-active-boot-slot 2>/dev/null)
  _c=$("$_bc" get-current-slot 2>/dev/null)
  [ -n "$_a" ] && [ -n "$_c" ] && [ "$_a" != "$_c" ]
}

bota_update_in_progress() {
  local _f _st
  for _f in $BOTA_PAYLOAD_PATHS; do
    [ -e "$_f" ] && return 0
  done
  _st=$(bota_ue_status)
  case "$_st" in
    *DOWNLOADING*|*VERIFYING*|*FINALIZING*|*UPDATING*|*CHECKING_FOR_UPDATE*|*UPDATE_AVAILABLE*)
      return 0 ;;
  esac
  bota_slot_flipped
}

bota_stage2_reached() {
  local _st
  if bota_ue --is_reboot_needed >/dev/null 2>&1; then
    return 0
  fi
  _st=$(bota_ue_status)
  case "$_st" in
    *UPDATED_NEED_REBOOT*) return 0 ;;
  esac
  bota_slot_flipped
}

bota_service_exists() {
  [ -n "$(getprop init.svc.$1 2>/dev/null)" ]
}

bota_pause_manager() {
  local _s
  [ "${BOTA_ENABLE_PAUSE:-1}" = "1" ] || return 0
  bota_state_has manager_paused && return 0
  : > "$BOTA_STATE_DIR/paused_services"
  for _s in $BOTA_PAUSE_SERVICES; do
    if bota_service_exists "$_s"; then
      setprop ctl.stop "$_s" 2>/dev/null
      printf '%s\n' "$_s" >> "$BOTA_STATE_DIR/paused_services"
      bota_log "paused service: $_s"
    else
      bota_log "service not present, skip: $_s"
    fi
  done
  if [ -s "$BOTA_STATE_DIR/paused_services" ]; then
    bota_state_set manager_paused
    bota_state_set need_resume
    bota_set_status paused
  else
    bota_log "no reboot trigger service matched; relying on slot revert"
  fi
  return 0
}

bota_resume_manager() {
  local _s
  if [ -f "$BOTA_STATE_DIR/paused_services" ]; then
    while read -r _s; do
      [ -n "$_s" ] || continue
      setprop ctl.start "$_s" 2>/dev/null
      bota_log "resumed service: $_s"
    done < "$BOTA_STATE_DIR/paused_services"
  fi
  bota_state_rm need_resume
  bota_state_rm manager_paused
  bota_state_rm paused_services
  return 0
}

bota_abandon_update() {
  local _bc _slot
  [ "${BOTA_ENABLE_FORCE_ABANDON:-1}" = "1" ] || return 1
  _bc=$(bota_find_bootctl) || { bota_log "bootctl not found; cannot abandon"; return 1; }
  "$_bc" hal-info >/dev/null 2>&1 || { bota_log "bootctl hal-info failed; cannot abandon"; return 1; }
  _slot=$("$_bc" get-current-slot 2>/dev/null)
  [ -n "$_slot" ] || { bota_log "cannot read current slot; cannot abandon"; return 1; }
  "$_bc" set-active-boot-slot "$_slot" 2>/dev/null || { bota_log "set-active-boot-slot failed"; return 1; }
  bota_state_put last_abandon_epoch "$(date +%s 2>/dev/null)"
  bota_log "abandoned OTA: forced active slot back to $_slot"
  return 0
}

# --- update-safe helpers (OnePlus / OEM App-driven OTA) ---------------------

bota_dir_has_files() {
  local _d _first
  for _d in "$@"; do
    [ -d "$_d" ] || continue
    _first=$(find "$_d" -type f 2>/dev/null | head -n 1)
    [ -n "$_first" ] && return 0
  done
  return 1
}

bota_prop_match() {
  local _kv _k _v
  for _kv in $BOTA_STAGE2_PROPS; do
    _k=${_kv%%=*}
    _v=${_kv#*=}
    [ "$(getprop "$_k" 2>/dev/null)" = "$_v" ] || return 1
  done
  return 0
}

bota_setting_match() {
  local _kv _ns _rest _k _v
  for _kv in $BOTA_STAGE2_SETTINGS; do
    _ns=${_kv%%:*}
    _rest=${_kv#*:}
    _k=${_rest%%=*}
    _v=${_rest#*=}
    [ "$(settings get "$_ns" "$_k" 2>/dev/null)" = "$_v" ] || return 1
  done
  return 0
}

# Returns 0 only when every configured signal group matches.
bota_stage2_signal() {
  local _any=0
  if [ -n "${BOTA_STAGE2_PROPS:-}" ]; then
    _any=1
    bota_prop_match || return 1
  fi
  if [ -n "${BOTA_STAGE2_SETTINGS:-}" ]; then
    _any=1
    bota_setting_match || return 1
  fi
  if [ -n "${BOTA_PAYLOAD_DIRS:-}" ]; then
    _any=1
    # shellcheck disable=SC2086
    bota_dir_has_files $BOTA_PAYLOAD_DIRS || return 1
  fi
  [ "$_any" = "1" ]
}

bota_signal_sig() {
  local _nf
  # shellcheck disable=SC2086
  _nf=$(find ${BOTA_PAYLOAD_DIRS:-/data/ota_package/OTA} -type f 2>/dev/null | wc -l)
  printf '%s|%s|%s|%s|%s\n' \
    "$(getprop persist.sys.sota.state 2>/dev/null)" \
    "$(getprop persist.vendor.oplus.update_status 2>/dev/null)" \
    "$(settings get system com.oplus.ota.downloaded_status 2>/dev/null)" \
    "$(settings get secure com.oplus.ota.detected_status 2>/dev/null)" \
    "${_nf:-0}"
}

bota_detect_log() {
  local _sig _sota _upd _dl _det _nf
  _sig=$(bota_signal_sig)
  _sota=${_sig%%|*}; _sig=${_sig#*|}
  _upd=${_sig%%|*}; _sig=${_sig#*|}
  _dl=${_sig%%|*}; _sig=${_sig#*|}
  _det=${_sig%%|*}; _nf=${_sig#*|}
  bota_log "detect: sota=$_sota oplus_update=$_upd downloaded=$_dl detected=$_det ota_files=$_nf"
}

bota_lockdown_apply() {
  local _p _lvl
  [ "${BOTA_UPDATE_LOCKDOWN:-0}" != "0" ] || return 0
  _lvl=${BOTA_LOCKDOWN_LEVEL:-2}
  settings put global ota_disable_automatic_update 1 2>/dev/null
  settings put global can_update_at_night 0 2>/dev/null
  bota_log "lockdown: settings applied (auto update off)"
  if [ "$_lvl" -ge 2 ] 2>/dev/null; then
    for _p in $BOTA_LOCKDOWN_APPS; do
      appops set "$_p" RUN_ANY_IN_BACKGROUND ignore 2>/dev/null
      appops set "$_p" RUN_IN_BACKGROUND ignore 2>/dev/null
      appops set "$_p" SCHEDULE_EXACT_ALARM ignore 2>/dev/null
      bota_log "lockdown: appops restricted $_p"
    done
  fi
  if [ "$_lvl" -ge 3 ] 2>/dev/null; then
    if pm disable-user --user 0 "$BOTA_LOCKDOWN_FREEZE_APP" >/dev/null 2>&1; then
      bota_log "lockdown: frozen $BOTA_LOCKDOWN_FREEZE_APP"
    else
      bota_log "lockdown: freeze failed for $BOTA_LOCKDOWN_FREEZE_APP"
    fi
  fi
  return 0
}
