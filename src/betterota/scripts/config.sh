export BOTA_DATA_DIR=${BOTA_DATA_DIR:-/data/adb/betterota}
export BOTA_STATE_DIR=${BOTA_STATE_DIR:-$BOTA_DATA_DIR/state}
export BOTA_LOG_FILE=${BOTA_LOG_FILE:-$BOTA_DATA_DIR/betterota.log}
export BOTA_USER_CONFIG=${BOTA_USER_CONFIG:-$BOTA_DATA_DIR/config.sh}

export BOTA_PAYLOAD_PATHS=${BOTA_PAYLOAD_PATHS:-"/data/ota_package/payload.bin /data/ota_package/update.zip"}

export BOTA_PAUSE_SERVICES=${BOTA_PAUSE_SERVICES:-"update_engine"}
export BOTA_PAUSE_AT_STAGE1=${BOTA_PAUSE_AT_STAGE1:-0}
export BOTA_ENABLE_PAUSE=${BOTA_ENABLE_PAUSE:-1}

export BOTA_RESUME_AFTER_PATCH=${BOTA_RESUME_AFTER_PATCH:-1}

export BOTA_ENABLE_FORCE_ABANDON=${BOTA_ENABLE_FORCE_ABANDON:-1}
export BOTA_ABANDON_COOLDOWN=${BOTA_ABANDON_COOLDOWN:-1800}
export BOTA_ABANDON_COOLDOWN_MIN=${BOTA_ABANDON_COOLDOWN_MIN:-60}

export BOTA_STAGE1_POLL=${BOTA_STAGE1_POLL:-15}
export BOTA_STAGE2_POLL=${BOTA_STAGE2_POLL:-10}

export BOTA_PATCH_RETRIES=${BOTA_PATCH_RETRIES:-3}
export BOTA_PATCH_RETRY_DELAY=${BOTA_PATCH_RETRY_DELAY:-20}

# --- update-safe profile (OnePlus / OEM App-driven OTA) ---------------------
# BOTA_UPDATE_SAFE=1 replaces the fail-closed slot-revert flow with:
#   lockdown auto-update -> detect staged OTA -> ksud boot-patch (no slot switch).
export BOTA_UPDATE_SAFE=${BOTA_UPDATE_SAFE:-0}

# Re-apply the auto-update lockdown at boot.
#   0 = off, 1 = settings only, 2 = settings + appops, 3 = also pm disable-user scheduler
export BOTA_UPDATE_LOCKDOWN=${BOTA_UPDATE_LOCKDOWN:-0}
export BOTA_LOCKDOWN_LEVEL=${BOTA_LOCKDOWN_LEVEL:-2}
export BOTA_LOCKDOWN_APPS=${BOTA_LOCKDOWN_APPS:-"com.oplus.romupdate com.oplus.ota com.oplus.cota"}
export BOTA_LOCKDOWN_FREEZE_APP=${BOTA_LOCKDOWN_FREEZE_APP:-com.oplus.romupdate}

# observe-only logs detected signals but never patches (use for the first OTA).
export BOTA_OBSERVE_ONLY=${BOTA_OBSERVE_ONLY:-0}

# Stage-2 detection. Every configured group must match (debounced).
#   BOTA_PAYLOAD_DIRS: dirs that must contain files
#   BOTA_STAGE2_PROPS: "prop=value ..." (all must match)
#   BOTA_STAGE2_SETTINGS: "namespace:key=value ..." (all must match)
export BOTA_PAYLOAD_DIRS=${BOTA_PAYLOAD_DIRS:-"/data/ota_package/OTA"}
export BOTA_STAGE2_PROPS=${BOTA_STAGE2_PROPS:-""}
export BOTA_STAGE2_SETTINGS=${BOTA_STAGE2_SETTINGS:-"system:com.oplus.ota.downloaded_status=1"}
export BOTA_STAGE2_DEBOUNCE=${BOTA_STAGE2_DEBOUNCE:-2}
export BOTA_FAST_POLL=${BOTA_FAST_POLL:-5}

# Logging: rotate the log at this size, and re-log the detect snapshot every
# N polls even when nothing changes (0 disables the heartbeat).
export BOTA_LOG_MAX_BYTES=${BOTA_LOG_MAX_BYTES:-524288}
export BOTA_LOG_HEARTBEAT=${BOTA_LOG_HEARTBEAT:-60}

# Optional explicit KernelSU patch partition (init_boot | boot | vendor_boot).
export BOTA_PATCH_PARTITION=${BOTA_PATCH_PARTITION:-}
