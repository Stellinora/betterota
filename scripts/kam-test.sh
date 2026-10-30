#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOD="$ROOT/src/betterota"
FAILED=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILED=1; }

for f in "$MOD"/*.sh "$MOD"/scripts/*.sh; do
  [ -f "$f" ] || continue
  if ! sh -n "$f" 2>/dev/null; then
    fail "syntax: $f"
  fi
done
[ "$FAILED" -eq 0 ] && pass "shell syntax"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"
mkdir -p "$BIN" "$TMP/data" "$TMP/ota"

cat > "$BIN/getprop" <<EOF
#!/bin/sh
case "\$1" in
  ro.boot.slot_suffix) cat "$TMP/slot" 2>/dev/null ;;
  ro.build.ab_update) echo true ;;
  init.svc.update_engine) echo running ;;
  *) echo "" ;;
esac
EOF
cat > "$BIN/setprop" <<EOF
#!/bin/sh
echo "setprop \$*" >> "$TMP/setprop.log"
EOF
printf '#!/bin/sh\nexit 0\n' > "$BIN/log"
cat > "$BIN/update_engine_client" <<EOF
#!/bin/sh
case "\$1" in
  --is_reboot_needed) exit 0 ;;
  --status) echo "Current operation: UPDATE_STATUS_UPDATED_NEED_REBOOT"; exit 0 ;;
  --reset_status) exit 0 ;;
  *) exit 0 ;;
esac
EOF
cat > "$BIN/bootctl" <<EOF
#!/bin/sh
echo "bootctl \$*" >> "$TMP/bootctl.log"
case "\$1" in
  hal-info) exit 0 ;;
  get-current-slot) echo 0; exit 0 ;;
  get-active-boot-slot) echo 1; exit 0 ;;
  set-active-boot-slot) exit 0 ;;
esac
exit 0
EOF
cat > "$BIN/settings" <<EOF
#!/bin/sh
echo "settings \$*" >> "$TMP/settings.log"
case "\$*" in
  "get system com.oplus.ota.downloaded_status") cat "$TMP/downloaded_status" 2>/dev/null || echo 0 ;;
  "get secure com.oplus.ota.detected_status") cat "$TMP/detected_status" 2>/dev/null || echo 0 ;;
  *) exit 0 ;;
esac
EOF
cat > "$BIN/appops" <<EOF
#!/bin/sh
echo "appops \$*" >> "$TMP/appops.log"
exit 0
EOF
cat > "$BIN/pm" <<EOF
#!/bin/sh
echo "pm \$*" >> "$TMP/pm.log"
exit 0
EOF
chmod +x "$BIN"/*
export PATH="$BIN:$PATH"

run_daemon() {
  local secs="$1"
  timeout -s KILL "$secs" env \
    MODDIR="$MOD" \
    BOTA_DATA_DIR="$TMP/data" \
    BOTA_LOG_FILE="$TMP/betterota.log" \
    BOTA_PAYLOAD_PATHS="$TMP/ota/payload.bin" \
    BOTA_USER_CONFIG="$TMP/data/config.sh" \
    BOTA_STAGE1_POLL="${BOTA_STAGE1_POLL:-1}" \
    BOTA_STAGE2_POLL="${BOTA_STAGE2_POLL:-1}" \
    BOTA_PATCH_RETRIES="${BOTA_PATCH_RETRIES:-1}" \
    BOTA_PATCH_RETRY_DELAY="${BOTA_PATCH_RETRY_DELAY:-0}" \
    BOTA_ABANDON_COOLDOWN="${BOTA_ABANDON_COOLDOWN:-1800}" \
    BOTA_ABANDON_COOLDOWN_MIN="${BOTA_ABANDON_COOLDOWN_MIN:-60}" \
    BOTA_UPDATE_SAFE="${BOTA_UPDATE_SAFE:-0}" \
    BOTA_UPDATE_LOCKDOWN="${BOTA_UPDATE_LOCKDOWN:-0}" \
    BOTA_LOCKDOWN_LEVEL="${BOTA_LOCKDOWN_LEVEL:-2}" \
    BOTA_LOCKDOWN_APPS="${BOTA_LOCKDOWN_APPS:-com.oplus.romupdate com.oplus.ota com.oplus.cota}" \
    BOTA_OBSERVE_ONLY="${BOTA_OBSERVE_ONLY:-0}" \
    BOTA_PAYLOAD_DIRS="${BOTA_PAYLOAD_DIRS:-$TMP/ota_dir}" \
    BOTA_STAGE2_PROPS="${BOTA_STAGE2_PROPS:-}" \
    BOTA_STAGE2_SETTINGS="${BOTA_STAGE2_SETTINGS:-system:com.oplus.ota.downloaded_status=1}" \
    BOTA_STAGE2_DEBOUNCE="${BOTA_STAGE2_DEBOUNCE:-2}" \
    BOTA_STAGE2_SETTLE="${BOTA_STAGE2_SETTLE:-0}" \
    BOTA_SAFE_RETRY_DELAY="${BOTA_SAFE_RETRY_DELAY:-0}" \
    BOTA_FAST_POLL="${BOTA_FAST_POLL:-1}" \
    BOTA_PATCH_PARTITION="${BOTA_PATCH_PARTITION:-}" \
    sh "$MOD/scripts/ota_keeper.sh"
}

reset_env() {
  rm -rf "$TMP/data"
  rm -f "$TMP/betterota.log"
  mkdir -p "$TMP/data"
  : > "$TMP/setprop.log"
  : > "$TMP/bootctl.log"
  : > "$TMP/settings.log"
  : > "$TMP/appops.log"
  : > "$TMP/pm.log"
  : > "$TMP/ksud.log"
  rm -rf "$TMP/ota_dir"
  rm -rf "$TMP/data/patch.lock" "$TMP/data/patch.pid"
  mkdir -p "$TMP/ota_dir"
  echo 0 > "$TMP/downloaded_status"
  echo 0 > "$TMP/detected_status"
}

set_ksud() {
  cat > "$BIN/ksud" <<EOF
#!/bin/sh
echo "$2"
exit "$1"
EOF
  chmod +x "$BIN/ksud"
}

set_ksud_args() {
  cat > "$BIN/ksud" <<EOF
#!/bin/sh
echo "ksud \$*" >> "$TMP/ksud.log"
echo "- Done!"
exit 0
EOF
  chmod +x "$BIN/ksud"
}

set_bootctl_ok() {
  cat > "$BIN/bootctl" <<EOF
#!/bin/sh
echo "bootctl \$*" >> "$TMP/bootctl.log"
case "\$1" in
  hal-info) exit 0 ;;
  get-current-slot) echo 0; exit 0 ;;
  get-active-boot-slot) echo 1; exit 0 ;;
  set-active-boot-slot) exit 0 ;;
esac
exit 0
EOF
  chmod +x "$BIN/bootctl"
}

set_bootctl_fail() {
  cat > "$BIN/bootctl" <<EOF
#!/bin/sh
echo "bootctl \$*" >> "$TMP/bootctl.log"
exit 1
EOF
  chmod +x "$BIN/bootctl"
}

echo _a > "$TMP/slot"
touch "$TMP/ota/payload.bin"

set_ksud 0 "- Done!"
reset_env
if run_daemon 15 >/dev/null 2>&1; then
  pass "A: daemon exits after success"
else
  fail "A: daemon did not exit cleanly"
fi
if [ "$(cat "$TMP/data/state/status" 2>/dev/null)" = "patched_waiting_reboot" ]; then
  pass "A: status patched_waiting_reboot"
else
  fail "A: unexpected status"
fi
if grep -q 'ctl.stop' "$TMP/setprop.log" && grep -q 'ctl.start' "$TMP/setprop.log"; then
  pass "A: reboot trigger paused then resumed"
else
  fail "A: pause/resume missing"
fi

echo _b > "$TMP/slot"
run_daemon 2 >/dev/null 2>&1
if grep -q 'OTA cycle complete' "$TMP/betterota.log" 2>/dev/null; then
  pass "C: slot switch normalized"
else
  fail "C: slot switch not handled"
fi
echo _a > "$TMP/slot"

set_ksud 1 "- Patch Error: flash failed"
reset_env
if BOTA_ABANDON_COOLDOWN=2 BOTA_ABANDON_COOLDOWN_MIN=1 run_daemon 6 >/dev/null 2>&1; then
  fail "B: daemon exited instead of watching"
else
  pass "B: daemon keeps watching after failure"
fi
if grep -q 'abandoned OTA' "$TMP/betterota.log" 2>/dev/null; then
  pass "B: update abandoned"
else
  fail "B: no abandon recorded"
fi
abandons="$(grep -c 'abandoned OTA' "$TMP/betterota.log" 2>/dev/null)"
if [ "${abandons:-0}" -ge 2 ]; then
  pass "B: watchdog retried (${abandons}x)"
else
  fail "B: watchdog did not retry (count=${abandons:-0})"
fi
if grep -q 'set-active-boot-slot' "$TMP/bootctl.log" 2>/dev/null; then
  pass "B: active slot reverted"
else
  fail "B: no active slot revert"
fi

set_ksud 1 "- Patch Error: flash failed"
set_bootctl_fail
reset_env
run_daemon 5 >/dev/null 2>&1
if grep -q 'trigger held paused\|daemon holding' "$TMP/betterota.log" 2>/dev/null; then
  pass "D: abandon unavailable holds trigger paused"
else
  fail "D: hold not recorded"
fi
if grep -q 'ctl.stop' "$TMP/setprop.log" && ! grep -q 'ctl.start' "$TMP/setprop.log"; then
  pass "D: trigger stopped and not resumed"
else
  fail "D: pause/resume state inconsistent"
fi
if [ "$(cat "$TMP/data/state/status" 2>/dev/null)" = "failed_paused" ]; then
  pass "D: status failed_paused"
else
  fail "D: unexpected status"
fi
if [ -f "$TMP/data/state/cycle_failed" ]; then
  pass "D: cycle_failed persisted"
else
  fail "D: cycle_failed not persisted"
fi
set_bootctl_ok

# --- update-safe mode ------------------------------------------------------
set_ksud 0 "- Done!"

reset_env
echo payload > "$TMP/ota_dir/payload.bin"
echo 1 > "$TMP/downloaded_status"
if BOTA_UPDATE_SAFE=1 BOTA_OBSERVE_ONLY=1 BOTA_STAGE2_DEBOUNCE=2 BOTA_FAST_POLL=1 run_daemon 6 >/dev/null 2>&1; then
  fail "E: observe daemon exited"
else
  pass "E: observe daemon keeps watching"
fi
_obs="$(grep -c 'OBSERVE ONLY' "$TMP/betterota.log" 2>/dev/null)"
if [ "${_obs:-0}" -eq 1 ]; then
  pass "E: observe-only logged once"
else
  fail "E: observe log count=${_obs:-0}"
fi
if [ ! -f "$TMP/data/state/patched" ]; then
  pass "E: observe did not patch"
else
  fail "E: observe patched unexpectedly"
fi

reset_env
echo payload > "$TMP/ota_dir/payload.bin"
echo 1 > "$TMP/downloaded_status"
if BOTA_UPDATE_SAFE=1 BOTA_OBSERVE_ONLY=0 BOTA_STAGE2_DEBOUNCE=2 BOTA_FAST_POLL=1 run_daemon 10 >/dev/null 2>&1; then
  pass "F: auto-patch daemon exits"
else
  fail "F: auto-patch did not exit"
fi
if [ "$(cat "$TMP/data/state/status" 2>/dev/null)" = "patched_waiting_reboot" ]; then
  pass "F: status patched_waiting_reboot"
else
  fail "F: unexpected status"
fi
if [ -f "$TMP/data/state/patched" ]; then
  pass "F: patched marker set"
else
  fail "F: patched marker missing"
fi
if grep -q 'ksud boot-patch --ota --flash' "$TMP/betterota.log" 2>/dev/null; then
  pass "F: ksud boot-patch called"
else
  fail "F: ksud boot-patch not called"
fi

reset_env
echo 0 > "$TMP/downloaded_status"
BOTA_UPDATE_SAFE=1 BOTA_UPDATE_LOCKDOWN=1 BOTA_LOCKDOWN_LEVEL=2 BOTA_STAGE2_DEBOUNCE=100 BOTA_FAST_POLL=1 run_daemon 3 >/dev/null 2>&1 || true
if grep -q 'lockdown: settings applied' "$TMP/betterota.log" 2>/dev/null; then
  pass "G: lockdown settings applied"
else
  fail "G: lockdown settings missing"
fi
if grep -q 'settings put global ota_disable_automatic_update 1' "$TMP/settings.log" 2>/dev/null; then
  pass "G: auto-update disabled via settings"
else
  fail "G: auto-update setting missing"
fi
if grep -q 'appops set com.oplus.romupdate RUN_ANY_IN_BACKGROUND ignore' "$TMP/appops.log" 2>/dev/null; then
  pass "G: appops background restriction"
else
  fail "G: appops restriction missing"
fi

reset_env
set_ksud_args
echo payload > "$TMP/ota_dir/payload.bin"
echo 1 > "$TMP/downloaded_status"
BOTA_UPDATE_SAFE=1 BOTA_PATCH_PARTITION=init_boot BOTA_STAGE2_DEBOUNCE=2 BOTA_FAST_POLL=1 run_daemon 10 >/dev/null 2>&1 || true
if grep -q -- 'boot-patch --ota --flash --partition init_boot' "$TMP/ksud.log" 2>/dev/null; then
  pass "H: patch partition forwarded"
else
  fail "H: patch partition missing"
fi

reset_env
set_ksud_args
echo payload > "$TMP/ota_dir/payload.bin"
echo 1 > "$TMP/downloaded_status"
BOTA_UPDATE_SAFE=1 BOTA_PATCH_PARTITION=evil BOTA_STAGE2_DEBOUNCE=2 BOTA_FAST_POLL=1 run_daemon 10 >/dev/null 2>&1 || true
if grep -q 'boot-patch --ota --flash' "$TMP/ksud.log" 2>/dev/null && ! grep -q -- '--partition' "$TMP/ksud.log" 2>/dev/null; then
  pass "I: invalid partition ignored"
else
  fail "I: invalid partition handling wrong"
fi

reset_env
(
  export MODDIR="$MOD"
  export BOTA_DATA_DIR="$TMP/data"
  export BOTA_LOG_FILE="$TMP/betterota.log"
  export BOTA_USER_CONFIG="$TMP/data/config.sh"
  . "$MOD/scripts/common.sh"
  bota_lockdown_restore
) >/dev/null 2>&1
if grep -q 'appops set com.oplus.romupdate RUN_ANY_IN_BACKGROUND default' "$TMP/appops.log" 2>/dev/null \
   && grep -q 'pm enable com.oplus.romupdate' "$TMP/pm.log" 2>/dev/null; then
  pass "J: lockdown restore resets appops and enables scheduler"
else
  fail "J: lockdown restore incomplete"
fi

if [ "$FAILED" -eq 0 ]; then
  echo "All tests passed."
else
  echo "Tests failed."
fi
exit "$FAILED"
