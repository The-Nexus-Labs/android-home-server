PROFILE ?=
PYTHON ?= python3
ACTION ?= run
INTERACTIVE_ARGS ?=

.PHONY: help preflight manifest download unlock flash root provision interactive interactive-force step updates-disable updates-enable updates-status ota-manual ota-auto ota-status

help:
	@printf '%s\n' \
	  'Targets:' \
	  '  PROFILE=...    - optional profile file; defaults to auto-detecting config/<codename>.env' \
	  '  STEP=...       - step key for make step (for example connect-wifi)' \
	  '  ACTION=...     - run, apply, test, guide or name for make step' \
	  '  INTERACTIVE_ARGS=... - extra flags for make interactive (for example INTERACTIVE_ARGS=--force)' \
	  '  make preflight   - inspect the connected device' \
	  '  make manifest    - build the pinned asset manifest only' \
	  '  make download    - download and verify GrapheneOS, Magisk, Termux assets' \
	  '  make unlock      - reboot to bootloader and unlock (wipes device)' \
	  '  make flash       - flash the pinned GrapheneOS release' \
	  '  make root        - patch init_boot with Magisk on-device and flash it' \
	  '  make updates-disable - disable the OS update client' \
	  '  make updates-enable  - re-enable the OS update client' \
	  '  make updates-status  - print current OS update-client mode' \
	  '  make provision   - run the provisioning steps after root is ready' \
	  '  make step        - run one step from src/steps via the step runner' \
	  '  make interactive - run the full guided workflow with on-device instructions' \
	  '  make interactive INTERACTIVE_ARGS=--force - reflash GrapheneOS and rerun all post-flash steps'

preflight:
	PROFILE="$(PROFILE)" ./src/run-step.sh inspect-device apply

manifest:
	PROFILE="$(PROFILE)" ./src/run-step.sh prepare-assets apply --manifest-only

download:
	PROFILE="$(PROFILE)" ./src/run-step.sh prepare-assets apply --download

unlock:
	PROFILE="$(PROFILE)" ./src/run-step.sh unlock-bootloader apply

flash:
	PROFILE="$(PROFILE)" ./src/run-step.sh flash-grapheneos apply

root:
	PROFILE="$(PROFILE)" ./src/run-step.sh install-magisk-root apply

updates-disable:
	PROFILE="$(PROFILE)" ./src/run-step.sh disable-system-updater apply disable

updates-enable:
	PROFILE="$(PROFILE)" ./src/run-step.sh disable-system-updater apply enable

updates-status:
	PROFILE="$(PROFILE)" ./src/run-step.sh disable-system-updater apply status

ota-manual: updates-disable

ota-auto: updates-enable

ota-status: updates-status

provision:
	PROFILE="$(PROFILE)" ./src/run-step.sh connect-wifi run
	PROFILE="$(PROFILE)" ./src/run-step.sh disable-wifi-mac-randomization run
	PROFILE="$(PROFILE)" ./src/run-step.sh enable-wifi-send-device-name run
	PROFILE="$(PROFILE)" ./src/run-step.sh disable-system-updater apply disable
	PROFILE="$(PROFILE)" ./src/run-step.sh install-magisk-service run
	PROFILE="$(PROFILE)" ./src/run-step.sh install-termux run
	PROFILE="$(PROFILE)" ./src/run-step.sh stage-termux-bootstrap run
	PROFILE="$(PROFILE)" ./src/run-step.sh disable-magisk-ui-notification run
	PROFILE="$(PROFILE)" ./src/run-step.sh disable-magisk-shell-notification run
	PROFILE="$(PROFILE)" ./src/run-step.sh disable-magisk-termux-notification run
	PROFILE="$(PROFILE)" ./src/run-step.sh verify-final-state apply

step:
	@test -n "$(STEP)" || { printf '%s\n' 'STEP is required, for example: make step STEP=connect-wifi'; exit 1; }
	PROFILE="$(PROFILE)" ./src/run-step.sh "$(STEP)" "$(ACTION)"

interactive:
	@PROFILE="$(PROFILE)" ./src/bootstrap-interactive.sh $(INTERACTIVE_ARGS)

interactive-force:
	@PROFILE="$(PROFILE)" ./src/bootstrap-interactive.sh --force
