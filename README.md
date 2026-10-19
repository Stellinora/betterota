# betterota

Make system OTA updates more accommodating to rooted users.

A fail-closed OTA root keeper for **A/B Android devices**. It patches the
inactive slot with KernelSU (`ksud boot-patch --ota --flash`) after the update
is installed, and if patching cannot be verified it **abandons the update rather
than losing root**.

Root is the first priority; the update is best-effort.

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
kam install dist/betterota-v0.1.3.zip --manager KernelSU
```

## Configuration

Runtime defaults live in `src/betterota/scripts/config.sh`. Override them
per device at `/data/adb/betterota/config.sh`.

The most important one:

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

`v0.1.0` is the first version. Host-side checks (`kam check`, `kam build`, shell
smoke tests) pass. On-device validation is still required for:

- `ksud boot-patch --ota --flash` preserving root across a real OTA
- `bootctl hal-info` / `set-active-boot-slot` availability
- the correct `BOTA_PAUSE_SERVICES` value per ROM
