#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/scripts/common.sh"
bota_mkdirs

echo "BetterOTA Root Keeper"
echo "status : $(bota_state_get status)"
echo "slot   : $(bota_current_slot)"
if bota_is_ab; then echo "ab     : yes"; else echo "ab     : no"; fi
if [ "${BOTA_UPDATE_SAFE:-0}" = "1" ]; then echo "mode   : update-safe"; else echo "mode   : fail-closed"; fi
echo "observe: ${BOTA_OBSERVE_ONLY:-0}"
echo "lockdown: enabled=${BOTA_UPDATE_LOCKDOWN:-0} level=${BOTA_LOCKDOWN_LEVEL:-0}"
_ksud=$(bota_find_ksud 2>/dev/null)
echo "ksud   : ${_ksud:-not found}"
_bc=$(bota_find_bootctl 2>/dev/null)
echo "bootctl: ${_bc:-not found}"

if [ -n "$_ksud" ] && bota_state_has stage2_installed && ! bota_state_has patched; then
  echo ""
  echo "stage 2 pending; running ksud boot-patch --ota --flash"
  if [ -n "${BOTA_PATCH_PARTITION:-}" ]; then
    "$_ksud" boot-patch --ota --flash --partition "$BOTA_PATCH_PARTITION"
  else
    "$_ksud" boot-patch --ota --flash
  fi
  _rc=$?
  if [ "$_rc" -eq 0 ]; then
    bota_state_set patched
    bota_set_status patched_waiting_reboot
    echo "patch OK"
  else
    echo "patch failed rc=$_rc"
  fi
elif [ "${BOTA_UPDATE_SAFE:-0}" = "1" ] && [ -n "$_ksud" ] && ! bota_state_has patched && bota_stage2_signal; then
  echo ""
  echo "staged OTA detected (update-safe); running ksud boot-patch --ota --flash"
  if [ -n "${BOTA_PATCH_PARTITION:-}" ]; then
    "$_ksud" boot-patch --ota --flash --partition "$BOTA_PATCH_PARTITION"
  else
    "$_ksud" boot-patch --ota --flash
  fi
  _rc=$?
  if [ "$_rc" -eq 0 ]; then
    bota_state_set patched
    bota_set_status patched_waiting_reboot
    echo "patch OK"
  else
    echo "patch failed rc=$_rc"
  fi
fi
