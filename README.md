# betterota

Make system OTA updates more accommodating to rooted users.

An OTA root keeper for **A/B Android devices**. It patches the inactive slot
with KernelSU (`ksud boot-patch --ota --flash`) after the update is installed.

Two modes:

- **fail-closed** (default): if patching cannot be verified it abandons the
  update rather than losing root. Root is the first priority; the update is
  best-effort.
- **update-safe** (OnePlus/ColorOS, opt-in): cuts off automatic updates,
  watches for a user-triggered update, and patches the inactive slot. It never
  reverts slots or discards the update.

## What it does

1. Waits for an OTA to appear (payload or `update_engine` status).
2. Waits for the update to finish installing to the inactive slot
   (`UPDATED_NEED_REBOOT`).
3. Runs `ksud boot-patch --ota --flash` against the soon-to-boot slot.
4. On success: lets the reboot proceed (update + root).
5. On failure: forces the active slot back with
   `bootctl set-active-boot-slot <current>`, so any reboot returns to the
   already-rooted system. The update is discarded.

## Requirements

- KernelSU or KernelSU-Next with `ksud boot-patch --ota --flash`
- A/B device (`ro.build.ab_update=true` / `ro.boot.slot_suffix` is set)
- Working `bootctl` HAL for the abandon fallback (`bootctl hal-info`)

## Build

This project is managed with [Kam](https://github.com/MemDeco-WG/Kam):

```bash
kam check
kam build
kam install dist/betterota-v0.2.0.zip --manager KernelSU
```

## Configuration

Runtime defaults live in `src/betterota/scripts/config.sh`. Override them
per device at `/data/adb/betterota/config.sh`.

### Fail-closed mode (default)

```sh
BOTA_PAUSE_SERVICES="update_engine"
```

`BOTA_PAUSE_SERVICES` is a space-separated list of init services to stop after
stage 2 so the night-time auto-reboot can be held long enough to patch. The
correct service name is **OEM-specific** and must be verified on the target
ROM (HyperOS / OxygenOS). If no service matches, the module falls back to the
bootctl slot revert.

Other useful variables: `BOTA_ABANDON_COOLDOWN`, `BOTA_ENABLE_FORCE_ABANDON`,
`BOTA_PATCH_RETRIES`, `BOTA_STAGE1_POLL`, `BOTA_STAGE2_POLL`.

### Update-safe mode (OnePlus / OEM App-driven OTA)

On newer OnePlus/ColorOS ROMs the OTA is driven by OEM apps
(`com.oplus.ota`, `com.oplus.romupdate`, `com.oplus.cota`), the OEM
`update_engine_client` does not expose `--status`/`--is_reboot_needed`, and
KernelSU `bootctl` may fail (`Error getting bootctrl v1.0 module`). Use the
update-safe profile for these devices:

```sh
BOTA_UPDATE_SAFE=1
BOTA_UPDATE_LOCKDOWN=1
BOTA_LOCKDOWN_LEVEL=2        # 1=settings, 2=settings+appops, 3=also freeze scheduler
BOTA_OBSERVE_ONLY=1          # first OTA: log signals only; set 0 to auto-patch
BOTA_PAYLOAD_DIRS="/data/ota_package/OTA"
BOTA_STAGE2_SETTINGS="system:com.oplus.ota.downloaded_status=1"
BOTA_STAGE2_DEBOUNCE=2
BOTA_STAGE2_SETTLE=0          # extra wait after the signal is stable (seconds)
BOTA_FAST_POLL=5
# BOTA_PATCH_PARTITION=init_boot   # optional explicit partition
```

In this mode the module deliberately does **not** use the fail-closed slot
revert. It:

- applies an idempotent auto-update lockdown at boot (settings + appops;
  optional `pm disable-user com.oplus.romupdate` at level 3),
- watches the configured stage-2 signals (no `--status` / `bootctl`),
- runs `ksud boot-patch --ota --flash` on the inactive slot once staged,
- never pauses services, never reverts slots, never resets update state and
  does not use LSPosed. If patching fails it keeps retrying/logging; the
  update is not discarded.

Start with `BOTA_OBSERVE_ONLY=1` for the first real OTA to confirm the signal
values in `/data/adb/betterota/betterota.log`, then set it to `0`.

## Runtime data

- State: `/data/adb/betterota/state/`
- Log: `/data/adb/betterota/betterota.log`
- Manager action button: prints status and, if stage 2 is pending, runs the patch

## Development

```bash
kam validate
kam check     # requires shellcheck
kam test      # host-side smoke tests, no device needed
kam build
```

CI lives in `.github/workflows`:

- `Validate Kam Module` runs `kam validate`, `kam check` and `kam test` on PRs
  and pushes to `main`.
- `Build Kam Module` builds the ZIP on every push/PR and publishes a GitHub
  Release on `v*` tags or manual dispatch.

Releasing: bump `version` / `versionCode` in `kam.toml`, commit, then push a
matching tag (for example `v0.2.0`).

## Status

Host-side checks (`kam validate`, `kam test`, `kam build`) pass. On-device
validation is still required for:

- `ksud boot-patch --ota --flash` preserving root across a real OTA
- the exact OEM stage-2 signal values (use `BOTA_OBSERVE_ONLY=1` on the first
  OTA and read the log)
- `update_engine_client --follow` idle behaviour
- `bootctl hal-info` / `set-active-boot-slot` availability (fail-closed mode)
