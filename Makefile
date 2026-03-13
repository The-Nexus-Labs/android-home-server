PROFILE ?=
PYTHON ?= python3

.PHONY: help preflight manifest download unlock flash root provision interactive updates-disable updates-enable updates-status ota-manual ota-auto ota-status

help:
	@printf '%s\n' \
	  'Targets:' \
	  '  PROFILE=...    - optional profile file; defaults to auto-detecting config/<codename>.env' \
	  '  make preflight   - inspect the connected device' \
	  '  make manifest    - build the pinned asset manifest only' \
	  '  make download    - download and verify GrapheneOS, Magisk, Termux assets' \
	  '  make unlock      - reboot to bootloader and unlock (wipes device)' \
	  '  make flash       - flash the pinned GrapheneOS release' \
	  '  make root        - patch init_boot with Magisk on-device and flash it' \
	  '  make updates-disable - disable the OS update client' \
	  '  make updates-enable  - re-enable the OS update client' \
	  '  make updates-status  - print current OS update-client mode' \
	  '  make provision   - install Termux, disable idle, set up SSH/Wi-Fi' \
	  '  make interactive - run the full guided workflow with on-device instructions'

preflight:
	PROFILE="$(PROFILE)" ./scripts/preflight.sh

manifest:
	PROFILE="$(PROFILE)" ./scripts/download-assets.sh --manifest-only

download:
	PROFILE="$(PROFILE)" ./scripts/download-assets.sh --download

unlock:
	PROFILE="$(PROFILE)" ./scripts/unlock-bootloader.sh

flash:
	PROFILE="$(PROFILE)" ./scripts/flash-grapheneos.sh

root:
	PROFILE="$(PROFILE)" ./scripts/root-magisk.sh

updates-disable:
	PROFILE="$(PROFILE)" ./scripts/configure-system-updater.sh disable

updates-enable:
	PROFILE="$(PROFILE)" ./scripts/configure-system-updater.sh enable

updates-status:
	PROFILE="$(PROFILE)" ./scripts/configure-system-updater.sh status

ota-manual: updates-disable

ota-auto: updates-enable

ota-status: updates-status

provision:
	PROFILE="$(PROFILE)" ./scripts/postflash-provision.sh

interactive:
	PROFILE="$(PROFILE)" ./scripts/bootstrap-interactive.sh
