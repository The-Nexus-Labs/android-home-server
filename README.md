# Android home server bootstrap

Simple, reproducible host-side automation for turning a Google Pixel 7 Pro (`cheetah`) into a rooted GrapheneOS-based home server.

## What it does

1. Detects and validates the connected device over `adb`
2. Downloads a pinned official GrapheneOS factory image, pinned platform-tools, pinned Magisk, pinned Termux, and pinned Termux:Boot assets
3. Verifies the platform-tools checksum and the GrapheneOS factory-image OpenSSH signature
4. Unlocks the bootloader with explicit on-device confirmation
5. Flashes the pinned official GrapheneOS release with the official `flash-all.sh`
6. Roots GrapheneOS by patching and flashing `init_boot.img` with Magisk on the device itself
7. Installs Termux and Termux:Boot
8. Disables battery optimization and background restrictions for the server role
9. Connects Wi‑Fi from `adb` if SSID credentials are configured
10. Prepares a Termux SSH bootstrap and records SSH connection details

## Reproducibility model

Everything important is pinned in [config/cheetah.env](config/cheetah.env):

- GrapheneOS version
- platform-tools version and checksum
- Magisk APK URL
- Termux APK URL
- Termux:Boot APK URL

Updating the workflow for a newer release is a config change, not a code rewrite.

If `PROFILE` is not set, the scripts auto-detect the connected device codename and use [config/cheetah.env](config/cheetah.env), [config/tangorpro.env](config/tangorpro.env), etc. when a matching profile exists.

`GRAPHENEOS_VERSION=latest` is supported. The exact resolved GrapheneOS release is written into the generated manifest under [artifacts](artifacts), which keeps each run reproducible after resolution while still tracking the latest stable release.

Shared runtime settings such as Wi‑Fi credentials and the temporary Termux SSH password are configured in [config/global.env](config/global.env) instead of per-device profile files.

## Main entrypoint

Use the guided workflow:

```sh
make interactive
```

The interactive script tells the user exactly what to do on the phone at each stage and pauses until the required manual steps are completed.

It is designed to be rerun safely. The workflow detects completed milestones such as bootloader unlock, GrapheneOS already being installed, Magisk root already being available, and SSH already responding, then resumes from the next unfinished step.

## Files

- [config/cheetah.env](config/cheetah.env) — pinned asset versions, Wi‑Fi, and SSH defaults
- [scripts/bootstrap-interactive.sh](scripts/bootstrap-interactive.sh) — full guided workflow
- [scripts/preflight.sh](scripts/preflight.sh) — checks the connected phone state
- [scripts/download-assets.sh](scripts/download-assets.sh) — downloads and verifies all pinned assets
- [scripts/unlock-bootloader.sh](scripts/unlock-bootloader.sh) — destructive unlock helper
- [scripts/flash-grapheneos.sh](scripts/flash-grapheneos.sh) — flashes the official GrapheneOS factory image
- [scripts/root-magisk.sh](scripts/root-magisk.sh) — patches `init_boot.img` on-device and flashes it
- [scripts/postflash-provision.sh](scripts/postflash-provision.sh) — installs Termux, disables idle, stages SSH bootstrap
- [payloads/termux-bootstrap.sh](payloads/termux-bootstrap.sh) — executed inside Termux to install and start `sshd`
- [payloads/magisk-disable-idle.sh](payloads/magisk-disable-idle.sh) — Magisk boot-time battery/background tuning

## Manual steps still required

Some steps cannot be bypassed because the device intentionally requires physical confirmation:

- enable `OEM unlocking`
- confirm the bootloader unlock prompt
- complete first GrapheneOS boot and re-enable `USB debugging`
- open Magisk and allow shell / ADB superuser access
- if automatic Termux execution is blocked, open Termux and run:
  - `./setup.sh`

## Non-interactive targets

```sh
make preflight
make download
make unlock
make flash
make root
make provision
```

## Notes

- `make unlock` wipes the device.
- `make flash` expects the device to already be in Fastboot Mode.
- `make root` expects GrapheneOS to already be booted with USB debugging enabled.
- the default SSH password is intentionally temporary and should be rotated immediately after setup.
